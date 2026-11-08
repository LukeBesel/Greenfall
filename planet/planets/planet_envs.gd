class_name PlanetEnvs
extends RefCounted
## [planet-rime] Registry of the campaign planets' environment scripts (data/planets.json, a dict
## keyed by planet id). Each entry names an `env` script with static entry points:
##   dev_hub(planet: PlanetData) -> int          which hub the --planet-env dev hook loads
##   prepare_field(field: HexField) -> void       before HexField.generate (biome junk set)
##   dress_view(view: FieldView) -> void          before FieldView.setup (ground layers, fx)
##   apply(world: Node, field: HexField, kind: Dictionary) -> void   once the scene is built
## Missing entry points are skipped, so an env only needs apply().

const PATH := "res://data/planets.json"

static var _cache: Dictionary = {}


static func all() -> Dictionary:
	if _cache.is_empty() and FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_cache = d
	return _cache


## The planet's entry (with "id" filled in), or {} if unknown.
static func entry(id: String) -> Dictionary:
	var e: Variant = all().get(id, {})
	if not (e is Dictionary) or (e as Dictionary).is_empty():
		if id != "":
			push_warning("PlanetEnvs: no planet '%s' in %s" % [id, PATH])
		return {}
	var out: Dictionary = (e as Dictionary).duplicate(true)
	out["id"] = id
	return out


## Calls a static entry point of the entry's env script; returns its result (null if absent).
static func call_env(e: Dictionary, fn: String, args: Array) -> Variant:
	if e.is_empty():
		return null
	var path: String = str(e.get("env", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var scr: Script = load(path)
	if scr == null:
		return null
	var found: bool = false
	for m: Dictionary in scr.get_script_method_list():
		if str(m.get("name", "")) == fn:
			found = true
			break
	if not found:
		return null
	return scr.callv(fn, args)


## The hub the dev hook loads: the env's dev_hub(planet), else the current one.
static func dev_hub(e: Dictionary, planet: PlanetData) -> int:
	var h: Variant = call_env(e, "dev_hub", [planet])
	return int(h) if h is int else GameState.current_hub
