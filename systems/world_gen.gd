class_name WorldGen
extends RefCounted
## [late] Cradle Mode worlds (data/cradle.json). Pure and deterministic: a world index and seed
## give its name, world type (the planet generator's biome mix), city names and modifiers.
## World 0 is always Verdance, exactly as the campaign generates it (empty mix, no modifiers).

const PATH: String = "res://data/cradle.json"
const VERDANCE_SEED: int = 4471

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


## The planet seed of the n-th world (0 = Verdance). Spread out so neighbours share nothing.
static func seed_for(index: int, salt: int = 0) -> int:
	if index <= 0:
		return VERDANCE_SEED
	var h: int = hash("greenfall_world_%d_%d" % [index, salt]) & 0x7FFFFFFF
	return 10007 + (h % 900000)


static func world_type(id: String) -> Dictionary:
	for t: Dictionary in cfg().get("world_types", []):
		if str(t["id"]) == id:
			return t
	return {}


static func modifier(id: String) -> Dictionary:
	for m: Dictionary in cfg().get("modifiers", []):
		if str(m["id"]) == id:
			return m
	return {}


## A full world record: {index, seed, name, type, mix, modifiers}. `index` 0 is Verdance.
## World types cycle so the first four new worlds are all different; modifiers are two
## distinct picks from the seed.
static func make(index: int, seed_v: int = -1) -> Dictionary:
	if seed_v < 0:
		seed_v = seed_for(index)
	if index <= 0:
		return {"index": 0, "seed": VERDANCE_SEED, "name": "Verdance", "type": "verdance", "mix": {}, "modifiers": []}
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var types: Array = cfg().get("world_types", [])
	var t: Dictionary = types[(index - 1) % types.size()] if not types.is_empty() else {}
	var mix: Dictionary = (t.get("mix", {}) as Dictionary).duplicate(true)
	mix["city_names"] = city_names(r)
	return {"index": index, "seed": seed_v, "name": world_name(r), "type": str(t.get("id", "rust_world")),
		"mix": mix, "modifiers": pick_modifiers(r, 2)}


static func world_name(r: RandomNumberGenerator) -> String:
	var np: Dictionary = cfg().get("name_parts", {})
	var a: Array = np.get("first", ["Nova"])
	var b: Array = np.get("last", ["ra"])
	return str(a[r.randi() % a.size()]) + str(b[r.randi() % b.size()])


## The towns of a new world: shuffled from the list, the start town first.
static func city_names(r: RandomNumberGenerator) -> Array:
	var pool: Array = (cfg().get("city_names", []) as Array).duplicate()
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool


static func pick_modifiers(r: RandomNumberGenerator, n: int) -> Array:
	var ids: Array = []
	for m: Dictionary in cfg().get("modifiers", []):
		ids.append(str(m["id"]))
	var out: Array = []
	while out.size() < mini(n, ids.size()):
		var id: String = ids[r.randi() % ids.size()]
		if not (id in out):
			out.append(id)
	return out


## Biome counts of a generated planet (land cells only), for tests and the bridge's world card.
static func biome_histogram(p: PlanetData) -> Dictionary:
	var out: Dictionary = {}
	for i: int in p.cell_count():
		var b: String = PlanetData.BIOMES[p.biome[i]]
		out[b] = int(out.get(b, 0)) + 1
	return out


## Short "Ice Moon · Heavy Rain, Long Nights" line.
static func describe(w: Dictionary) -> String:
	var t: Dictionary = world_type(str(w.get("type", "")))
	var tn: String = TranslationServer.translate(str(t.get("name", "Home world")))
	var mods: Array[String] = []
	for id: Variant in w.get("modifiers", []):
		mods.append(TranslationServer.translate(str(modifier(str(id)).get("name", id))))
	return tn if mods.is_empty() else "%s  ·  %s" % [tn, ", ".join(mods)]
