class_name PlanetEnvs
extends RefCounted
## [planet-ochre] Registry of the solar-system planet environments (data/planets.json, keyed by
## planet id). Each entry names an env script with two static entry points:
##   static func prepare(kind: Dictionary) -> void   before the district's field is generated
##                                                   (junk models, biome set)
##   static func apply(world: Node, field: HexField, kind: Dictionary) -> void   once the scene is built
## Dev hook: `--planet-env=<id>` loads a wild district and dresses it with that planet's env
## (does nothing unless the flag is set).

const PATH: String = "res://data/planets.json"

static var _all: Dictionary = {}


static func all() -> Dictionary:
	if _all.is_empty() and FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			for k: String in d:
				if not k.begins_with("_") and d[k] is Dictionary:
					_all[k] = d[k]
	return _all


static func kind(id: String) -> Dictionary:
	return all().get(id, {})


static func script_for(k: Dictionary) -> Script:
	var p: String = str(k.get("env_script", ""))
	return load(p) as Script if p != "" and ResourceLoader.exists(p) else null


## Calls the env's prepare(); safe to call more than once.
static func prepare(k: Dictionary) -> void:
	var s: Script = script_for(k)
	if s:
		s.call("prepare", k)


static func apply(world: Node, k: Dictionary) -> void:
	var s: Script = script_for(k)
	if s:
		s.call("apply", world, world.get("field"), k)


## The dev hook's planet (empty without --planet-env). On a fresh start it moves to a wild hub
## (no city streets) that is not a frontier, so the env owns the whole landscape.
static func dev_prepare(planet: PlanetData, loaded: bool) -> Dictionary:
	if not DevHooks.has("planet-env"):
		return {}
	var k: Dictionary = kind(DevHooks.get_s("planet-env", ""))
	if k.is_empty():
		push_warning("--planet-env: unknown planet id (see data/planets.json)")
		return {}
	if not loaded:
		var frontier: Array = planet.frontier_hubs.values()
		var pick: int = -1
		var want: String = str(k.get("prefer_biome", ""))
		for i: int in planet.hubs.size():
			if i > 0 and planet.city[planet.hubs[i]] < 0 and not frontier.has(i):
				if pick < 0 or PlanetData.BIOMES[planet.biome[planet.hubs[i]]] == want:
					pick = i
				if PlanetData.BIOMES[planet.biome[planet.hubs[i]]] == want:
					break
		if pick > 0:
			GameState.switch_hub(pick)
		if DevHooks.has("hub-level"):
			GameState.world["hub_level"] = clampi(int(DevHooks.get_f("hub-level", 1.0)), 1, 5)
	prepare(k)
	return k
