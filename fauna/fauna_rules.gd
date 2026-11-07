class_name FaunaRules
extends RefCounted
## [wild] Who lives where (pure rules, unit-tested in tests/test_fauna.gd). Data: data/fauna.json.
## A district is described per hex by a context: {hex, level (-1 = none), hub, water, shore, clean,
## removed (0..1 junk cleared), locked (ice), edge (Sustained+ at the edge of the restored area),
## near_level (best level of a land neighbour)}. plan() turns the contexts into the animals the
## district should have now: Array of {sp, hex, n}, nearest hexes first, capped per species and
## for the district. Counts are stable (seeded by district, hex and species), so animals don't
## flicker as the plan is re-made.

const PATH: String = "res://data/fauna.json"

static var _cfg: Dictionary = {}
static var _by_id: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
		for d: Dictionary in _cfg.get("species", []):
			_by_id[str(d["id"])] = d
	return _cfg


static func defs() -> Array:
	return cfg().get("species", [])


static func def(id: String) -> Dictionary:
	cfg()
	return _by_id.get(id, {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in defs():
		out.append(str(d["id"]))
	return out


## Region tags for a district biome: "" (city) -> [city]; ordinary wild biomes -> [wild, wild_*];
## frontier biome ids stay as they are.
static func regions(biome: String) -> Array[String]:
	match biome:
		"":
			return ["city"]
		"dust_dunes":
			return ["wild", "wild_dust"]
		"frostcap":
			return ["wild", "wild_frost"]
		"neon_coast":
			return ["wild", "wild_coast"]
		"rustlands", "fungal_marsh":
			return ["wild"]
	return [biome]


static func in_region(d: Dictionary, regs: Array) -> bool:
	for r: Variant in d.get("regions", []):
		if str(r) in regs:
			return true
	return false


static func time_ok(d: Dictionary, night: bool) -> bool:
	match str(d.get("time", "any")):
		"night":
			return night
		"day":
			return not night
	return true


## Does this hex suit the species at all (ignoring chance and caps)?
static func suits(d: Dictionary, ctx: Dictionary, regs: Array, night: bool) -> bool:
	if not in_region(d, regs) or not time_ok(d, night):
		return false
	var where: String = str(d.get("where", "land"))
	if where == "district":
		return false  # handled per district
	var lv: Array = d.get("levels", [0, 5])
	if where == "water":
		if not bool(ctx.get("water", false)) or not bool(ctx.get("clean", false)):
			return false
		return not d.has("near_level") or int(ctx.get("near_level", 0)) >= int(d["near_level"])
	if bool(ctx.get("water", false)):
		return false
	if bool(ctx.get("locked", false)) and not bool(d.get("ice_ok", false)):
		return false
	if where == "shore" and not bool(ctx.get("shore", false)):
		return false
	var level: int = int(ctx.get("level", -1))
	if bool(ctx.get("hub", false)):
		if not bool(d.get("hub_ok", false)):
			return false
		level = 1
	if level < 0:
		return false
	if level < int(lv[0]) or level > int(lv[1]):
		return false
	if bool(d.get("junk", false)):
		return not bool(ctx.get("clean", false)) and float(ctx.get("removed", 0.0)) < 0.92
	if bool(d.get("edge", false)) and not bool(ctx.get("edge", false)):
		return false
	return true


## How many of the species this hex gets now (0 when it doesn't suit). Rats thin out as their
## hex is cleaned; fish grow with lake clarity.
static func count_for(d: Dictionary, ctx: Dictionary, regs: Array, night: bool, district_seed: int, clarity: float = 0.0) -> int:
	if not suits(d, ctx, regs, night):
		return 0
	var r := RandomNumberGenerator.new()
	r.seed = hash([district_seed, int(ctx.get("hex", 0)), str(d["id"])])
	if r.randf() >= float(d.get("chance", 1.0)):
		return 0
	var ph: Array = d.get("per_hex", [1, 1])
	var n: int = r.randi_range(int(ph[0]), int(ph[1]))
	if bool(d.get("junk", false)):
		n = int(ceil(float(n) * (1.0 - float(ctx.get("removed", 0.0)))))
	if str(d.get("kind", "")) == "school":
		n = int(round(float(n) * (0.7 + 0.3 * clampf(clarity, 0.0, 1.0)) + clampf(clarity, 0.0, 1.0) * 2.0))
	return maxi(n, 0)


## The district's animals now. contexts: Array of hex contexts; focus_d: hex id -> distance to
## Lumi (nearest first); regs: region tags. Returns Array of {sp, hex, n} (hex -1 for district-wide).
static func plan(contexts: Array, regs: Array, night: bool, district_seed: int, focus_d: Dictionary = {}, clarity: float = 0.0) -> Array:
	var order: Array = contexts.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(focus_d.get(int(a["hex"]), 0.0)) < float(focus_d.get(int(b["hex"]), 0.0)))
	var out: Array = []
	var total: int = 0
	var max_total: int = int(cfg().get("max_agents", 90))
	for d: Dictionary in defs():
		var sid: String = str(d["id"])
		var cap: int = int(d.get("cap", 99))
		var used: int = 0
		if str(d.get("where", "")) == "district":
			if in_region(d, regs) and time_ok(d, night):
				var ph: Array = d.get("per_hex", [1, 1])
				var r := RandomNumberGenerator.new()
				r.seed = hash([district_seed, sid])
				var nd: int = mini(r.randi_range(int(ph[0]), int(ph[1])), cap)
				out.append({"sp": sid, "hex": -1, "n": nd})
				total += nd
			continue
		for ctx: Dictionary in order:
			if used >= cap:
				break
			var n: int = mini(count_for(d, ctx, regs, night, district_seed, clarity), cap - used)
			if n <= 0:
				continue
			out.append({"sp": sid, "hex": int(ctx["hex"]), "n": n})
			used += n
			total += n
	# District cap: drop the farthest entries first (swarms and schools count once).
	if total > max_total:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(focus_d.get(int(a["hex"]), 0.0)) < float(focus_d.get(int(b["hex"]), 0.0)))
		var kept: Array = []
		var acc: int = 0
		for e: Dictionary in out:
			var w: int = 1 if str(def(str(e["sp"])).get("kind", "")) in ["swarm", "school"] else int(e["n"])
			if acc + w > max_total:
				continue
			acc += w
			kept.append(e)
		out = kept
	return out


## Hex contexts for a live district. level_of: Callable(hid) -> int (-1 when untracked).
static func contexts(field: HexField, level_of: Callable) -> Array:
	var out: Array = []
	var lv := PackedInt32Array()
	lv.resize(field.hex_count())
	for h: int in field.hex_count():
		lv[h] = int(level_of.call(h))
	for h: int in field.hex_count():
		var water: bool = field.is_water(h)
		var hub: bool = field.hex_hub[h] != 0
		var near: int = -1
		var edge: bool = false
		var shore: bool = false
		for nb: Vector2i in Hex.neighbors(field.hex_axial[h]):
			var j: int = int(field.axial_to_id.get(nb, -1))
			if j < 0:
				edge = true
				continue
			if field.is_water(j):
				shore = true
				continue
			near = maxi(near, 1 if field.hex_hub[j] != 0 else lv[j])
			if lv[j] < 4 and field.hex_hub[j] == 0:
				edge = true
		out.append({"hex": h, "level": lv[h], "hub": hub, "water": water, "shore": shore and not water,
			"clean": field.is_clean(h) or hub, "removed": field.removed_fraction(h), "locked": field.locked.has(h),
			"edge": edge and lv[h] >= 4, "near_level": near})
	return out


## A point an animal may stand on: inside the field, no junk piece within r, not a building
## footprint, and (unless junk_ok) not on a hex that still has junk mounds under it.
static func spot_ok(field: HexField, p: Vector3, r: float, junk_ok: bool = false) -> bool:
	var h: int = field.hex_at(p)
	if h < 0:
		return false
	if field.layout and field.layout.surface_at(p.x, p.z) == CityLayout.Surface.BUILDING:
		return false
	if not junk_ok and not field.is_clean(h) and field.hex_hub[h] == 0:
		return false
	if field.ground_height(h, p) > 0.04:
		return false
	var seen: Dictionary = {}
	for o: Vector3 in [Vector3.ZERO, Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		var hh: int = field.hex_at(p + o)
		if hh < 0 or seen.has(hh):
			continue
		seen[hh] = true
		var r2: float = r * r
		for pid: int in field.hex_pieces[hh]:
			if field.piece_alive[pid] == 1:
				var d: Vector3 = field.piece_pos[pid] - p
				if d.x * d.x + d.z * d.z < r2:
					return false
	return true
