class_name PlanetDefinition
extends Resource
## Everything that makes one planet different from another. Shared systems read the current
## definition through the Planets autoload and never name a planet themselves.
##
## Small facts are typed fields here. Big content lives in JSON tables in the planet's folder;
## `tables` maps a table name to its file. A new planet is a new folder with one of these and its
## tables: see docs/PLANET_PLAYBOOK.md.

## Table names every planet must provide.
const REQUIRED_TABLES: Array[String] = ["pollution", "upgrades", "regrowth", "tutorial", "goals"]
## Table names a planet may provide. Systems that use one must cope with it being absent.
const OPTIONAL_TABLES: Array[String] = [
	"districts", "restoration", "rigs", "research", "robots", "balance", "sites", "hub", "stations", "plants", "fauna", "events", "story",
	"player", "robot_level", "field", "builds", "yard", "trash_bin", "outposts", "frontiers", "signal_tower",
	"guide_lines", "shards", "eggs", "ledger", "codex", "museum", "postgame",
]

## Stable id: lowercase, one word. Saves are keyed by it, so it never changes after release.
@export var id: StringName
@export var display_name: String
@export var tagline: String
## Order in the campaign (0 = first). Planets are offered in this order.
@export var order: int = 0
## Whether this planet ships in the current build. Parked planets stay loadable for tests.
@export var shipped: bool = true

@export_group("Globe")
## Grid frequency: the globe has 10 * f * f + 2 cells of about 10 m. Radius grows linearly with it.
@export var globe_frequency: int = 128
## Number of hub sites placed on the globe.
@export var hub_count: int = 10
## Seed for terrain and content placement.
@export var world_seed: int = 0

@export_group("Pacing")
## Minutes a first-time player should need to reach this planet's ending. The simulator checks it.
@export var target_playtime_min: float = 240.0

@export_group("Content tables")
## Table name -> JSON file. Paths are res:// paths, normally inside this planet's folder.
@export var tables: Dictionary[String, String] = {}

@export_group("Look and sound")
## Optional script with static hooks for this planet's own art: apply(world, field, kind),
## dress_view(...). Shared code calls it only through this field.
@export var env_script: Script
## Key colours by role (ground_polluted, ground_restored, sky_day, accent...).
@export var palette: Dictionary[String, Color] = {}
## Key for the music director's track set.
@export var music_set: String = ""

var _cache: Dictionary = {}


## The parsed table, or an empty Dictionary when this planet does not have it.
func table(table_name: String) -> Dictionary:
	if _cache.has(table_name):
		return _cache[table_name]
	var out: Dictionary = {}
	var path: String = tables.get(table_name, "")
	if path != "" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out = parsed
	_cache[table_name] = out
	return out


func has_table(table_name: String) -> bool:
	return tables.has(table_name) and FileAccess.file_exists(tables[table_name])


## Number of cells on this planet's globe.
func cell_count() -> int:
	return 10 * globe_frequency * globe_frequency + 2


## Problems that would stop this planet from loading. Empty when the definition is usable.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var id_text: String = String(id)
	if id_text == "":
		errors.append("id is empty")
	elif id_text != id_text.to_lower() or id_text.contains(" "):
		errors.append("id '%s' must be lowercase with no spaces" % id_text)
	if display_name == "":
		errors.append("display_name is empty")
	if globe_frequency < 1:
		errors.append("globe_frequency must be at least 1")
	if hub_count < 1:
		errors.append("hub_count must be at least 1")
	if target_playtime_min <= 0.0:
		errors.append("target_playtime_min must be positive")
	for required: String in REQUIRED_TABLES:
		if not tables.has(required):
			errors.append("missing required table '%s'" % required)
	for table_name: String in tables:
		if not table_name in REQUIRED_TABLES and not table_name in OPTIONAL_TABLES:
			errors.append("unknown table '%s'" % table_name)
			continue
		var path: String = tables[table_name]
		if not FileAccess.file_exists(path):
			errors.append("table '%s': file not found: %s" % [table_name, path])
		elif not JSON.parse_string(FileAccess.get_file_as_string(path)) is Dictionary:
			errors.append("table '%s': not a JSON object: %s" % [table_name, path])
	return errors


## Drops parsed tables so edited files are read again (tools and tests).
func clear_cache() -> void:
	_cache.clear()
