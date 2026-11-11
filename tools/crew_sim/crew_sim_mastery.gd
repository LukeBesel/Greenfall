class_name CrewSimMastery
extends RefCounted
## The crew simulator's mastery ledger (design spec section 3; core/mastery_rules.gd): beside the
## crew's growth it keeps, second by second, how much Lumi's hands could clean and how much the
## crew could, kind by kind, with the game's own mastery rules: Lumi's work on a kind raises its
## level, robots may not work a kind under the level they need, and their rate follows the level.
##
## It measures CAPACITY in hexes of waste: what each side could clean in the time, not what was
## left to clean (the city minutes are the simulator's input). Hand share = hand / (hand + crew).
## Robot rates are the game's tables. Lumi's own rate past the first city is not measured in the
## game yet: calibration.json `hand_hexes_per_min`, marked ESTIMATE.
##
## Policy for Lumi's hands: a kind of this city she can work but robots cannot yet (under the
## level they need) gets all her time until it is learnt; after that she works the kinds by their
## share of the city's waste.
##
## Use: var m := CrewSimMastery.new(); m.setup(def, cal); m.enter_city(i); m.step(dt, ...)

const SCOOP_ACTION_S: float = 3.0

var cfg: Dictionary = {}
var units: Dictionary[String, float] = {}
var _kinds: Dictionary = {}
var _base: String = ""
var _cal: Dictionary = {}
var _cities: Array[Dictionary] = []
var _city: int = -1
var _share: Dictionary[String, float] = {}
var _rows: Array[Dictionary] = []
var _city_t: float = 0.0


func setup(def: PlanetDefinition, cal: Dictionary) -> void:
	var table: Dictionary = def.table(Pollution.TABLE)
	cfg = MasteryRules.config(table, def.table("robots"))
	_kinds = table.get("kinds", {})
	_base = str(table.get("base", ""))
	_cal = cal
	for id: String in _kinds:
		units[id] = 0.0
	var raw: Array = (def.table("districts").get("districts", []) as Array)
	for d: Variant in raw:
		_cities.append(d as Dictionary)


func level(kind: String) -> int:
	return MasteryRules.level_for(cfg, kind, float(units.get(kind, 0.0)))


func enter_city(index: int) -> void:
	_city = index
	_city_t = 0.0
	_share = _city_shares(index)
	_rows.append({"hand": 0.0, "crew": 0.0, "waiting_robot_s": 0.0, "first_level_min": {}, "hex_work": float(_cities[index].get("hex_work", 1.0)),
		"hexes": Districts.hexes_for_rings(int(_cities[index].get("rings", 0)))})


## Each kind's share of the city's waste, in hexes of waste per hex of city: a kind beside the
## base kind lies on `density` of the land hexes and owns `share` of each; a floating kind is the
## city's water hexes; the base kind has the rest of the land.
func _city_shares(index: int) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	var water: float = _at(_cal.get("water_hex_share", []), index, 0.0)
	var others: float = 0.0
	for id: Variant in (_cities[index].get("pollution", [_base]) as Array):
		var kd: Dictionary = _kinds.get(str(id), {})
		var spawn: Dictionary = kd.get("spawn", {})
		if str(id) == _base:
			continue
		if str(kd.get("work", "")) == Pollution.WORK_FLOAT:
			if water > 0.0:
				out[str(id)] = water
			continue
		out[str(id)] = (1.0 - water) * float(spawn.get("density", 1.0)) * float(spawn.get("share", 0.3))
		others += out[str(id)]
	out[_base] = maxf(0.0, 1.0 - water - others)
	return out


## One step of `dt` player seconds. crew: {robot type: count}; types: the robots table's types by
## id; tier_mult: func(type id) -> float.
func step(dt: float, crew: Dictionary, types: Dictionary, tier_mult: Callable) -> void:
	if _city < 0:
		return
	_city_t += dt
	var row: Dictionary = _rows[_city]
	_hand(dt, row)
	var near: float = 1.0 + (MasteryRules.near_factor(cfg, 0.0) - 1.0) * float(_cal.get("crew_near_share", 0.0))
	var duty: float = float(_cal.get("crew_duty", 1.0))
	for type_id: String in crew:
		var n: int = int(crew[type_id])
		var role: String = str((types[type_id] as Dictionary).get("role", ""))
		var mine: Array[String] = []
		var total: float = 0.0
		for id: String in MasteryRules.kinds_of_role(cfg, role):
			if _share.has(id):
				mine.append(id)
				total += _share[id]
		if n <= 0 or mine.is_empty() or total <= 0.0:
			continue
		var worked: bool = false
		for id: String in mine:
			var factor: float = MasteryRules.robot_factor(cfg, id, level(id))
			if factor <= 0.0:
				continue
			worked = true
			var rate: float = _robot_hexes_per_s(types[type_id], id, row) * float(tier_mult.call(type_id))
			row["crew"] = float(row["crew"]) + float(n) * (_share[id] / total) * rate * factor * near * duty * dt
		if not worked:
			row["waiting_robot_s"] = float(row["waiting_robot_s"]) + float(n) * dt


func _hand(dt: float, row: Dictionary) -> void:
	var rate: float = _at(_cal.get("hand_hexes_per_min", []), _city, 0.0) / 60.0
	var scoop: float = float(_cal.get("hand_scoop_share", 1.0))
	var teach: String = ""
	for id: String in _share:
		if id != _base and not MasteryRules.robots_allowed(cfg, id, level(id)):
			teach = id
			break
	if not MasteryRules.robots_allowed(cfg, _base, level(_base)):
		teach = _base
	for id: String in _share:
		var part: float = (1.0 if id == teach else 0.0) if teach != "" else _share[id]
		if part <= 0.0:
			continue
		var before: int = level(id)
		var hexes: float = rate * part * (1.0 + (MasteryRules.hand_bonus(cfg, before) - 1.0) * scoop) * dt
		row["hand"] = float(row["hand"]) + hexes
		units[id] += MasteryRules.gain(cfg, id, hexes * float(row["hex_work"]))
		if before == 0 and level(id) > 0:
			(row["first_level_min"] as Dictionary)[id] = _city_t / 60.0


## Hexes of waste a second one robot of a type clears of a kind, at its own rate (tier 0, level 5).
func _robot_hexes_per_s(type_def: Dictionary, kind: String, row: Dictionary) -> float:
	var stats: Dictionary = type_def.get("stats", {})
	var kd: Dictionary = _kinds.get(kind, {})
	match str(kd.get("work", Pollution.WORK_PIECES)):
		Pollution.WORK_HELD:
			return float(kd.get("robot_units", 20.0)) * float(stats.get("work_rate", 0.0)) / SCOOP_ACTION_S / maxf(float(row["hex_work"]), 1.0)
		Pollution.WORK_FLOAT:
			return float(stats.get("scoop_rate", 0.0)) * 0.35 * 0.9 / SphereOffline.UNITS_PER_WATER_CELL
	return float(stats.get("scoop_rate", 0.0)) * 0.35 * 0.9 / SphereOffline.UNITS_PER_CELL


static func _at(list: Variant, index: int, fallback: float) -> float:
	var a: Array = list if list is Array else []
	return float(a[mini(index, a.size() - 1)]) if not a.is_empty() else fallback


## {by_city: [{hand_share, hand_hexes, crew_hexes, coverage, waiting_robot_min, first_level_min,
## hand_needed_per_min (Lumi's rate that would make the target share)}], levels: {kind: level},
## hand_share_volume (all cities, weighted by their waste), rule: {min, cities, target, pass,
## worst, target_met: [city indexes]}}.
func result(minutes: Array) -> Dictionary:
	var rule: Dictionary = (cfg.get("hand_share", {}) as Dictionary).duplicate()
	var by_city: Array = []
	var hand_vol: float = 0.0
	var all_vol: float = 0.0
	var worst: float = 1.0
	var met: Array = []
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		var hand: float = float(row["hand"])
		var crew: float = float(row["crew"])
		var share: float = hand / (hand + crew) if hand + crew > 0.0 else 1.0
		var mins: float = _at(minutes, i, 1.0)
		var target: float = float(rule.get("target", 0.0))
		by_city.append({"hand_share": share, "hand_hexes": hand, "crew_hexes": crew, "coverage": (hand + crew) / maxf(float(row["hexes"]), 1.0),
			"waiting_robot_min": float(row["waiting_robot_s"]) / 60.0, "first_level_min": row["first_level_min"],
			"hand_needed_per_min": target / maxf(1.0 - target, 0.001) * crew / maxf(mins, 0.001)})
		hand_vol += hand * float(row["hex_work"])
		all_vol += (hand + crew) * float(row["hex_work"])
		if i < int(rule.get("cities", 0)):
			worst = minf(worst, share)
		if share >= target:
			met.append(i)
	var levels: Dictionary = {}
	for id: String in units:
		levels[id] = level(id)
	rule["worst"] = worst
	rule["pass"] = worst >= float(rule.get("min", 0.0))
	rule["target_met"] = met
	return {"by_city": by_city, "levels": levels, "hand_share_volume": hand_vol / all_vol if all_vol > 0.0 else 1.0, "rule": rule}
