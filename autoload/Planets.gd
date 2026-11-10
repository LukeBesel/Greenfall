extends Node
## The registry of planets and the one currently being played.
##
## Scans `res://planets/<id>/planet.tres` at start. Shared systems call `Planets.current()` for
## everything that differs between planets and never name a planet themselves.

signal current_changed(planet: PlanetDefinition)

const PLANETS_DIR: String = "res://planets"
const DEFINITION_FILE: String = "planet.tres"

var _defs: Dictionary[StringName, PlanetDefinition] = {}
var _current: PlanetDefinition


func _ready() -> void:
	register_dir(PLANETS_DIR)
	var first: PlanetDefinition = first_shipped()
	if first:
		_current = first


## Loads every `<dir>/<id>/planet.tres`. Returns how many were added. Invalid ones are reported
## and skipped. Tests call this with a fixtures folder.
func register_dir(dir_path: String) -> int:
	var added: int = 0
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return 0
	for folder: String in dir.get_directories():
		if folder.begins_with("_"):
			continue
		var path: String = "%s/%s/%s" % [dir_path, folder, DEFINITION_FILE]
		if not ResourceLoader.exists(path):
			continue
		if register(load(path) as PlanetDefinition, path):
			added += 1
	return added


## Adds one definition. Returns false (and reports why) when it is null or invalid.
func register(def: PlanetDefinition, source: String = "") -> bool:
	if def == null:
		push_error("Planets: not a PlanetDefinition: %s" % source)
		return false
	var errors: PackedStringArray = def.validate()
	if not errors.is_empty():
		push_error("Planets: %s is invalid: %s" % [source if source != "" else String(def.id), "; ".join(errors)])
		return false
	_defs[def.id] = def
	return true


func unregister(planet_id: StringName) -> void:
	_defs.erase(planet_id)
	if _current and _current.id == planet_id:
		_current = first_shipped()
		current_changed.emit(_current)


func has(planet_id: StringName) -> bool:
	return _defs.has(planet_id)


## The definition for an id, or null.
func by_id(planet_id: StringName) -> PlanetDefinition:
	return _defs.get(planet_id)


## Every registered planet, in campaign order.
func all() -> Array[PlanetDefinition]:
	var out: Array[PlanetDefinition] = []
	out.assign(_defs.values())
	out.sort_custom(func(a: PlanetDefinition, b: PlanetDefinition) -> bool: return a.order < b.order)
	return out


## The first planet in campaign order that ships in this build, or null.
func first_shipped() -> PlanetDefinition:
	for def: PlanetDefinition in all():
		if def.shipped:
			return def
	return null


## The planet being played. Null only when no planet is registered.
func current() -> PlanetDefinition:
	return _current


func current_id() -> StringName:
	return _current.id if _current else &""


## Switches the planet being played. Returns false when the id is unknown.
func set_current(planet_id: StringName) -> bool:
	if not _defs.has(planet_id):
		push_error("Planets: unknown planet '%s'" % planet_id)
		return false
	if _current == _defs[planet_id]:
		return true
	_current = _defs[planet_id]
	current_changed.emit(_current)
	return true
