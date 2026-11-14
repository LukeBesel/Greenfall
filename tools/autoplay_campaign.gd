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


## One file per --save-dir stage chain, so parallel runs don't overwrite each other.
static func path() -> String:
	var d: String = DevHooks.get_s("save-dir", "")
	return PATH if d == "" else PATH.replace(".json", "_%s.json" % d.validate_filename())

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
	var f := FileAccess.open(ProjectSettings.globalize_path(path()), FileAccess.READ)
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
	var fp: String = ProjectSettings.globalize_path(path())
	DirAccess.make_dir_recursive_absolute(fp.get_base_dir())
	var f := FileAccess.open(fp, FileAccess.WRITE)
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


# --- Robot builder (the builder goals) --------------------------------------------------------

## A player tinkering at the Builder tab: fit one robot slot by slot with parts from the bin or
## cheap crafts (bolts + a stored part), then save that crew's build as a preset. Returns what
## happened ("" = nothing).
static func tinker(world: Node) -> String:
	var fleet: Fleet = world.get("fleet")
	if fleet == null or fleet.robots().is_empty():
		return ""
	var r: Robot = null
	for rb: Robot in fleet.robots():
		if r == null or rb.build.size() > r.build.size():
			r = rb
	if RobotBuilder.is_full_custom(r.build):
		if RobotBuilder.preset(r.role()).is_empty():
			RobotBuilder.save_preset(r.role(), r.build)
			return "preset %s" % r.role()
		return ""
	for slot: String in RobotBuilder.SLOTS:
		if str(r.build.get(slot, "")) != "":
			continue
		var best: String = ""
		for p: Dictionary in RobotBuilder.parts_for_slot(slot):
			var id: String = str(p["id"])
			if not RobotBuilder.fits(id, r.type_id):
				continue
			if RobotBuilder.count(id) > 0:
				best = id
				break
			if best == "" and RobotBuilder.craftable(id) and RobotBuilder.craft_block_reason(id) == "":
				best = id
		if best == "":
			continue
		if RobotBuilder.count(best) <= 0 and not RobotBuilder.craft(best):
			continue
		if RobotBuilder.equip(r, slot, best) == "":
			return "fit %s on %s" % [best, r.robot_name]
	return ""


# --- Where to fly next ----------------------------------------------------------------------

const FRONTIER_ORDER: Array[String] = ["dust_flats", "frozen_port", "sunken_city", "cradle_returns"]


static func frontier_kid(world: Node) -> String:
	return Frontiers.world_kind(world)


## A frontier is finished for the critical path: base 5 and half its land Growing (the Cradle:
## its completion hook has fired).
static func frontier_finished(fid: String, hi: int) -> bool:
	if fid == "cradle_returns":
		return GameState.flags.get("cradle_returned", false)
	return Frontiers.base_level(hi) >= 5 and Frontiers.growing_frac(hi) >= 0.5


## This district has nothing left on the critical path.
static func district_done(world: Node) -> bool:
	var kid: String = frontier_kid(world)
	if kid == "cradle_returns":
		return GameState.flags.get("cradle_returned", false)
	if int(world.hub.level) < 5:
		return false
	if kid == "":
		return true
	if kid == "cradle_returns":
		return GameState.flags.get("cradle_returned", false)
	return false  # [v6flat] a live frontier district (gone with the flat world) was done at 50% Growing


## The hub to fly to now, or -1 (stay). Frontiers in unlock order first; else the next ordinary
## district whose base is below level 5 (more level-5 bases open the frontiers).
static func next_hub(world: Node) -> int:
	if not district_done(world):
		return -1
	var planet: PlanetData = world.planet
	var here: int = int(world.hub_index)
	for fid: String in FRONTIER_ORDER:
		if not planet.frontier_hubs.has(fid):
			continue
		var hi: int = int(planet.frontier_hubs[fid])
		if frontier_finished(fid, hi):
			continue
		if Frontiers.can_launch(planet, hi):
			return hi if hi != here else -1
		break  # the next frontier is still locked: build more bases meanwhile
	if GameState.flags.get("cradle_returned", false):
		return -1  # post-game: stay and keep planting (Seed Ark)
	for i: int in planet.base_hub_count:
		if i != here and Frontiers.base_level(i) < 5:
			return i
	return -1


## Research to pull forward in this district (frontier needs).
static func research_first(world: Node) -> Array[String]:
	match frontier_kid(world):
		"frozen_port":
			return ["hedgerows", "evergreens", "dune_fences", "cold_hardy_seeds", "heat_pumps"]
		"dust_flats":
			return ["dew_condensers", "hedgerows", "evergreens", "dune_fences"]
	return []


## Cradle pad hexes (plant and sustain these first), else []. [v6flat] Only the flat Cradle
## Returns district had a pad: none on the globe.
static func pad_hexes(_world: Node) -> Array[int]:
	return []
