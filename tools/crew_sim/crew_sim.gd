class_name CrewSim
extends RefCounted
## The crew simulator: how the crew grows across a planet's cities, in seconds, from the tables
## the game reads and on the game's own chain rules (CrewChain for the ground and the Assembler's
## line, CrewRules for the cap and the prices). See tools/crew_sim/README.md.
##
## What is simulated, in one-second steps of player time:
## - cities are cleaned one after the other, each over its calibrated minutes, nearest hex first;
##   every cleaned hex leaves its buried parts (CrewChain.seed_cell);
## - Lumi's hands bring Parts per hex (calibrated), a city may give arrival salvage;
## - each Scrounger makes real trips: out to the nearest hexes that hold parts, a dig, and back,
##   at its speed, dig rate and sack from the robots table;
## - Lumi builds robots by hand at the bench until the Assembler stands, then only the first of a
##   type; the Assembler's line builds the rest in the policy's mix;
## - the crew cap follows the base level and the cities open.
## - mastery (tools/crew_sim/crew_sim_mastery.gd): what Lumi's hands and the crew could each clean,
##   kind by kind, on the game's mastery rules; the hand share of all cleaning by city.
## What is not: cleaning speed (the city minutes are an input, so a bigger crew does not finish a
## city sooner here) and the rocket's Parts.
##
## Use: var r: Dictionary = CrewSim.run(def, CrewSim.load_calibration(), "default")

const CALIBRATION: String = "res://tools/crew_sim/calibration.json"
const TICK_S: float = 1.0
## Synthetic hex ids: city index x this + the hex's place in the cleaning order.
const CELL_BLOCK: int = 1000000
const POLICY_DEFAULT: String = "default"
const POLICY_ALL_FINDERS: String = "all_scroungers"
const POLICY_NO_FINDERS: String = "no_scroungers"


class City:
	extends RefCounted
	var id: String = ""
	var rings: int = 0
	var hexes: int = 0
	var seconds: float = 0.0
	var cleaned: int = 0
	## Next hex in ring order that may still hold parts (hexes before it are empty).
	var dig_from: int = 0


static func load_calibration() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CALIBRATION))
	var out: Dictionary = {}
	if parsed is Dictionary:
		for k: String in parsed:
			if k != "_doc":
				out[k] = (parsed[k] as Dictionary)["value"] if parsed[k] is Dictionary and (parsed[k] as Dictionary).has("value") else parsed[k]
	return out


## The ring a hex stands on when hexes are counted outward from the middle (hex 0 = the middle).
static func ring_of(index: int) -> int:
	var r: int = 0
	while Districts.hexes_for_rings(r) <= index:
		r += 1
	return r


## Seconds of one Scrounger trip: out to a hex on `first_ring`, `hops` more hexes each one hex
## further along, back from `last_ring`, and the dig. `spacing_m` = metres driven per ring.
static func trip_seconds(first_ring: int, hops: int, last_ring: int, parts: float, spacing_m: float, speed: float, dig_rate: float) -> float:
	return float(first_ring + hops + last_ring) * spacing_m / maxf(speed, 0.01) + parts / maxf(dig_rate, 0.01)


## Runs a whole planet. Returns {crew_by_city, curve (crew per 10 minutes), crew_end, cap_end,
## by_type, parts_earned, parts_scrounged, parts_hand, parts_arrival, parts_left, parts_on_builds,
## parts_on_tiers, assembled, hand_built, fastest_doubling_s, longest_stall_s, first_robot_min,
## first_assembler_min, ground_seeded, minutes, mastery (CrewSimMastery.result)}.
static func run(def: PlanetDefinition, cal: Dictionary, policy: String = POLICY_DEFAULT) -> Dictionary:
	var sim := CrewSim.new()
	sim._setup(def, cal, policy)
	return sim._play()


var _cfg: Dictionary = {}
var _cal: Dictionary = {}
var _policy: String = POLICY_DEFAULT
var _chain := CrewChain.new()
var _mastery := CrewSimMastery.new()
var _cities: Array[City] = []
var _types: Dictionary[String, Dictionary] = {}
var _order: Array[String] = []
var _crew: Dictionary[String, int] = {}
var _tier: Dictionary[String, int] = {}
## One entry per Scrounger: seconds until it is back at the base, and the Parts it carries.
var _finders: Array[Dictionary] = []
var _parts: float = 0.0
var _t: float = 0.0
var _city: int = 0
var _hand_acc: float = 0.0
var _bench_acc: float = 0.0
var _out: Dictionary = {}
var _doubling_marks: Array[Vector2] = []
var _last_robot_t: float = 0.0


func _setup(def: PlanetDefinition, cal: Dictionary, policy: String) -> void:
	_cfg = def.table("robots")
	_cal = cal
	_policy = policy
	_chain.configure(_cfg.get("chain", {}))
	_mastery.setup(def, cal)
	for raw: Variant in _cfg.get("types", []):
		var t: Dictionary = raw
		_types[str(t["id"])] = t
		_order.append(str(t["id"]))
	var minutes: Array = cal.get("city_minutes", [])
	var specs: Array[Dictionary] = Districts.specs_for(def)
	for i: int in specs.size():
		var c := City.new()
		c.id = str(specs[i]["id"])
		c.rings = int(specs[i]["rings"])
		c.hexes = Districts.hexes_for_rings(c.rings)
		c.seconds = float(minutes[mini(i, minutes.size() - 1)]) * 60.0 if not minutes.is_empty() else 1800.0
		_cities.append(c)
	var mix: Dictionary = cal.get("mix", {})
	for id: String in _order:
		var w: int = int(mix.get(id, 0))
		if id == _finder():
			w = 0 if policy == POLICY_NO_FINDERS else w
		elif policy == POLICY_ALL_FINDERS:
			w = 0
		_chain.set_weight(id, w)
	_out = {"crew_by_city": [], "curve": [], "parts_earned": 0.0, "parts_scrounged": 0.0, "parts_hand": 0.0, "parts_arrival": 0.0,
		"parts_on_builds": 0.0, "parts_on_tiers": 0.0, "assembled": 0, "hand_built": 0, "fastest_doubling_s": INF,
		"longest_stall_s": 0.0, "first_robot_min": -1.0, "first_assembler_min": -1.0}


func _play() -> Dictionary:
	var city_start: float = 0.0
	var next_curve: float = 600.0
	_enter_city(0)
	while _city < _cities.size():
		_t += TICK_S
		var c: City = _cities[_city]
		_clean(c, city_start)
		_scrounge()
		_bench()
		_line()
		_mastery.step(TICK_S, _crew, _types, _tier_mult)
		if _t >= next_curve:
			(_out["curve"] as Array).append(_total())
			next_curve += 600.0
		if c.cleaned >= c.hexes and _t - city_start >= c.seconds:
			(_out["crew_by_city"] as Array).append(_total())
			_city += 1
			city_start = _t
			if _city < _cities.size():
				_enter_city(_city)
	_out["crew_end"] = _total()
	_out["cap_end"] = _cap()
	_out["by_type"] = _crew.duplicate()
	_out["parts_left"] = _parts
	_out["ground_seeded"] = _chain.seeded_parts
	_out["ground_left"] = _chain.stock_total()
	_out["minutes"] = _t / 60.0
	_out["mastery"] = _mastery.result(_cal.get("city_minutes", []))
	return _out


# --- The world --------------------------------------------------------------------------------------

func _enter_city(i: int) -> void:
	_last_robot_t = _t  # waits are counted inside a city
	_mastery.enter_city(i)
	var salvage: float = _chain.claim_arrival(_cities[i].id)
	if salvage > 0.0:
		_earn(salvage, "parts_arrival")
	var unlock: Dictionary = _chain.assembler_cfg().get("unlock", {})
	if not _chain.offered and (str(unlock.get("district", "")) == _cities[i].id or not unlock.has("district")):
		_chain.offered = true


func _clean(c: City, city_start: float) -> void:
	var want: int = mini(c.hexes, int(floorf((_t - city_start) / maxf(c.seconds, 1.0) * float(c.hexes))))
	var per_hex: Array = _cal.get("hand_parts_per_hex", [])
	while c.cleaned < want:
		_chain.seed_cell(_city * CELL_BLOCK + c.cleaned, c.id)
		c.cleaned += 1
		if not per_hex.is_empty():
			_hand_acc += float(per_hex[mini(_city, per_hex.size() - 1)])
	if _hand_acc >= 1.0:
		var whole: float = floorf(_hand_acc)
		_hand_acc -= whole
		_earn(whole, "parts_hand")


func _earn(parts: float, key: String) -> void:
	_parts += parts
	_out[key] = float(_out[key]) + parts
	_out["parts_earned"] = float(_out["parts_earned"]) + parts


# --- Scroungers -------------------------------------------------------------------------------------

func _scrounge() -> void:
	for f: Dictionary in _finders:
		f["left"] = float(f["left"]) - TICK_S
		if float(f["left"]) > 0.0:
			continue
		if float(f["carry"]) > 0.0:
			var whole: float = _chain.deliver(float(f["carry"]))
			f["carry"] = 0.0
			if whole > 0.0:
				_earn(whole, "parts_scrounged")
		_send_out(f)


## A free Scrounger's next trip: the nearest hexes that hold parts, in the city in play first, then
## the ones before it. It digs until the sack is full, then comes back.
func _send_out(f: Dictionary) -> void:
	var finder: Dictionary = _types.get(_finder(), {})
	var stats: Dictionary = finder.get("stats", {})
	var mult: float = _tier_mult(_finder())
	var speed: float = maxf(float(stats.get("speed", 1.0)) * mult, 0.1)
	var dig: float = maxf(float(stats.get("dig_rate", 1.0)) * mult, 0.01)
	var sack: float = maxf(float(stats.get("sack", 1.0)), 1.0)
	var spacing: float = float(_cal.get("hex_spacing_m", 17.35)) * float(_cal.get("path_factor", 1.3))
	for back: int in _city + 1:
		var ci: int = _city - back
		var c: City = _cities[ci]
		var got: float = 0.0
		var first_ring: int = -1
		var last_ring: int = 0
		var hops: int = 0
		while c.dig_from < c.cleaned and got < sack - 0.001:
			var cell: int = ci * CELL_BLOCK + c.dig_from
			var took: float = _chain.take(cell, sack - got)
			if took > 0.0:
				got += took
				last_ring = ring_of(c.dig_from)
				if first_ring < 0:
					first_ring = last_ring
				else:
					hops += 1
			if not _chain.has_stock(cell):
				c.dig_from += 1
		if got > 0.0:
			f["carry"] = got
			f["left"] = trip_seconds(first_ring, hops, last_ring, got, spacing, speed, dig)
			return
	f["left"] = float(_cal.get("idle_rescan_s", 5.0))


# --- Building ---------------------------------------------------------------------------------------

## Lumi at the bench, every bench_visit_s: one robot by hand (any type before the Assembler stands,
## only the first of a type after), the Assembler itself, then a tier step with Parts to spare.
func _bench() -> void:
	_bench_acc += TICK_S
	if _bench_acc < float(_cal.get("bench_visit_s", 100.0)):
		return
	_bench_acc = 0.0
	if _chain.offered and not _chain.built:
		var cost: float = float((_chain.assembler_cfg().get("cost", {}) as Dictionary).get("parts", 0.0))
		if _parts >= cost:
			_parts -= cost
			_chain.built = true
			_out["first_assembler_min"] = _t / 60.0
	var pick: String = _hand_pick()
	if pick != "" and _total() < _cap() and _parts >= _price(pick):
		_parts -= _price(pick)
		_out["parts_on_builds"] = float(_out["parts_on_builds"]) + _price(pick)
		_out["hand_built"] = int(_out["hand_built"]) + 1
		_add_robot(pick)
		return
	_maybe_tier()


func _hand_pick() -> String:
	var open: Array[String] = _unlocked()
	for id: String in open:  # the first of a type is always Lumi's own
		if _crew.get(id, 0) == 0 and _chain.weight(id) > 0:
			return id
	if _chain.built:
		return ""
	return _chain.pick(open, _crew, _total())


func _maybe_tier() -> void:
	if not CrewRules.tiers_open(_cfg, _city + 1):
		return
	var reserve: float = float(_cal.get("tier_reserve_parts", 60.0))
	for id: String in _order:
		if _crew.get(id, 0) == 0:
			continue
		var price: float = CrewRules.tier_parts(_cfg, _types[id], _tier.get(id, 0), _crew[id])
		if price >= 0.0 and _parts >= price + reserve:
			_parts -= price
			_out["parts_on_tiers"] = float(_out["parts_on_tiers"]) + price
			_tier[id] = _tier.get(id, 0) + 1
			return


func _line() -> void:
	var allowed: Array[String] = []
	for id: String in _unlocked():
		if _crew.get(id, 0) > 0:
			allowed.append(id)
	var res: Dictionary = _chain.tick_line(TICK_S, _parts, _total() < _cap(), allowed, _price)
	if float(res["spend"]) > 0.0:
		_parts -= float(res["spend"])
		_out["parts_on_builds"] = float(_out["parts_on_builds"]) + float(res["spend"])
	if str(res["built"]) != "":
		_out["assembled"] = int(_out["assembled"]) + 1
		_add_robot(str(res["built"]))


func _add_robot(type_id: String) -> void:
	_crew[type_id] = _crew.get(type_id, 0) + 1
	if type_id == _finder():
		_finders.append({"left": 0.0, "carry": 0.0})
	var n: int = _total()
	if n == 1:
		_out["first_robot_min"] = _t / 60.0
	if _city >= 1:
		_out["longest_stall_s"] = maxf(float(_out["longest_stall_s"]), _t - _last_robot_t)
	_last_robot_t = _t
	# Fastest doubling, from 4 robots up: the time since the crew was half this size.
	_doubling_marks.append(Vector2(_t, float(n)))
	if n >= 8:
		for m: Vector2 in _doubling_marks:
			if m.y * 2.0 >= float(n):
				_out["fastest_doubling_s"] = minf(float(_out["fastest_doubling_s"]), _t - m.x)
				break


# --- Rules read from the tables ---------------------------------------------------------------------

func _finder() -> String:
	return str((_cfg.get("chain", {}) as Dictionary).get("finder", ""))


func _total() -> int:
	var n: int = 0
	for id: String in _crew:
		n += _crew[id]
	return n


func _cap() -> int:
	return CrewRules.cap(_cfg, _base_level(), _city + 1)


func _base_level() -> int:
	var levels: Array = _cal.get("base_level_by_city", [])
	var lv: int = int(levels[mini(_city, levels.size() - 1)]) if not levels.is_empty() else 1
	if _city == 0 and _t < float(_cal.get("base_level_2_min", 0.0)) * 60.0:
		return 1
	return lv


func _price(type_id: String) -> float:
	return CrewRules.build_parts(_cfg, _types[type_id], _crew.get(type_id, 0), _tier.get(type_id, 0))


func _tier_mult(type_id: String) -> float:
	var tiers: Array = _cfg.get("tiers", [])
	if tiers.is_empty():
		return 1.0
	return float((tiers[clampi(_tier.get(type_id, 0), 0, tiers.size() - 1)] as Dictionary).get("mult", 1.0))


## Robot types Lumi has the plans for by now: calibration type_open {type: [city index, minute in
## that city]}. A type the calibration does not name is never built here.
func _unlocked() -> Array[String]:
	var out: Array[String] = []
	var open: Dictionary = _cal.get("type_open", {})
	var in_city_s: float = _t
	for i: int in _city:
		in_city_s -= _cities[i].seconds
	for id: String in _order:
		if not open.has(id):
			continue
		var at: Array = open[id]
		if _city > int(at[0]) or (_city == int(at[0]) and in_city_s >= float(at[1]) * 60.0):
			out.append(id)
	return out
