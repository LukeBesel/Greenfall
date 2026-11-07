class_name AutoplayCampaign
extends RefCounted
## [beat] Whole-game layer of the autoplay bot (tools/autoplay.gd): campaign milestones that
## survive rocket travel (scene reloads) and staged runs, and the planner that decides when to
## leave a district and where to fly (next ordinary district, the frontiers in unlock order, the
## Cradle). Frontier mechanics (heaters, greenhouses, pad focus) live here too so the district
## bot stays readable.
##
## Milestones go to screenshots/autoplay_milestones.json (game time in seconds, from
## stats.time_played, so they add up across --save-dir stages). --fresh starts a new file.

const PATH: String = "res://screenshots/autoplay_milestones.json"

static var marks: Dictionary = {}
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if DevHooks.has("fresh"):
		marks = {}
		_write()
		return
	var f := FileAccess.open(ProjectSettings.globalize_path(PATH), FileAccess.READ)
	if f:
		var v: Variant = JSON.parse_string(f.get_as_text())
		if v is Dictionary:
			marks = v


static func mark(key: String, t: float) -> void:
	_load()
	if marks.has(key):
		return
	marks[key] = snappedf(t, 0.1)
	print("[Campaign] %s at %.1f min" % [key, t / 60.0])
	_write()


static func _write() -> void:
	var path: String = ProjectSettings.globalize_path(PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(marks, "  ", false))


## Milestones sorted by time, in minutes (for the report).
static func timeline_min() -> Array:
	_load()
	var keys: Array = marks.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(marks[a]) < float(marks[b]))
	var out: Array = []
	for k: Variant in keys:
		out.append([str(k), snappedf(float(marks[k]) / 60.0, 0.1)])
	return out
