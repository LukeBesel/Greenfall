class_name DistrictsDev
extends Node
## Dev flags for the districts and the launch point (listed in autoload/DevHooks.gd):
##   --district-stage=<id>:<stage>[,<id>:<stage>...]  set every land hex of a district to a regrowth
##       stage once the world is up (cleaned, tracked by HexLevels, no rewards)
##   --launch-ready[=S]  meet the planet's launch rule S wall-clock seconds after the process
##       started (default 20): every district is set to the rule's stage. The ending then plays
##       at DEV_PACE with no credits, so a short headless run reaches the end screen. Every
##       source is shut down first (unpaid), since a running source holds its city's last stage.
##   --sources-shut=all|<id>[,<id>...]  shut those cities' sources down at start (unpaid), with
##       the events a real shutdown fires (systems/sources.gd)
## Added by the world only when one of the flags is given.

const FLAG_STAGE: String = "district-stage"
const FLAG_LAUNCH: String = "launch-ready"
const FLAG_SOURCES: String = "sources-shut"
const DEFAULT_LAUNCH_S: float = 20.0
const DEV_PACE: float = 3.0

var _districts: Districts
var _restoration: Restoration
var _crews: OrbitCrews
var _cells: SphereCells
var _levels: HexLevels
var _sources: Sources
var _launch_done: bool = false


## Adds the dev node to `parent` when a flag asks for it. Returns it, or null.
static func attach(parent: Node, districts: Districts, restoration: Restoration, ending: PlanetEnding,
		crews: OrbitCrews, cells: SphereCells, levels: HexLevels, sources: Sources = null) -> DistrictsDev:
	if not (DevHooks.has(FLAG_STAGE) or DevHooks.has(FLAG_LAUNCH) or DevHooks.has(FLAG_SOURCES)):
		return null
	var dev := DistrictsDev.new()
	dev.name = "DistrictsDev"
	dev._districts = districts
	dev._restoration = restoration
	dev._crews = crews
	dev._cells = cells
	dev._levels = levels
	dev._sources = sources
	if DevHooks.has(FLAG_LAUNCH):
		ending.pace = DEV_PACE
		ending.skip_credits = true
	parent.add_child(dev)
	return dev


func _ready() -> void:
	set_process(DevHooks.has(FLAG_LAUNCH))
	if DevHooks.has(FLAG_STAGE):
		_apply_stage_flag.call_deferred()
	if DevHooks.has(FLAG_SOURCES):
		_shut_sources.call_deferred(DevHooks.get_s(FLAG_SOURCES, "all"))


func _process(_delta: float) -> void:
	if _launch_done or Time.get_ticks_msec() / 1000.0 < DevHooks.get_f(FLAG_LAUNCH, DEFAULT_LAUNCH_S):
		return
	_launch_done = true
	set_process(false)
	_shut_sources("all")
	for id: String in _districts.ids():
		set_stage(id, _restoration.launch_stage())
	print("[districts] dev: launch rule met (%d districts at stage %d)" % [_districts.count(), _restoration.launch_stage()])


## Sets every land hex of district `id` to regrowth stage `stage` (0 leaves its hexes as they
## are: a hex's stage never drops). Returns how many hexes changed.
func set_stage(id: String, stage: int) -> int:
	var target: int = clampi(stage, 0, Districts.MAX_STAGE)
	var changed: int = 0
	if target <= 0:
		return changed
	for c: int in _districts.cells_of(id):
		var now: int = Districts.cell_stage(_cells, c)
		if now == Districts.NOT_LAND or now >= target:
			continue
		if now == 0:
			_cells.release_hold(c)  # every pollution kind on the hex goes, not only what a scoop takes
			_crews.work_cell(c, 0.0)
		_levels.track(c)
		if _levels.levels.has(c):
			_levels.levels[c] = maxi(int(_levels.levels[c]), target)
		_cells.set_level(c, target)
		changed += 1
	return changed


## Shuts the named cities' sources down ("all", "1" or "" = every one). Returns how many.
func _shut_sources(which: String) -> int:
	if _sources == null:
		return 0
	var every: bool = which in ["all", "1", ""]
	var n: int = 0
	for id: String in _sources.ids():
		if (every or id in which.split(",", false)) and _sources.force_shut(id):
			n += 1
	print("[sources] dev: %d shut down (%s)" % [n, which])
	return n


func _apply_stage_flag() -> void:
	for pair: String in DevHooks.get_s(FLAG_STAGE, "").split(",", false):
		var id: String = pair.get_slice(":", 0)
		var stage: int = int(pair.get_slice(":", 1))
		if not _districts.has(id):
			print("[districts] dev: no district '%s' (have %s)" % [id, ", ".join(_districts.ids())])
			continue
		var n: int = set_stage(id, stage)
		print("[districts] dev: %s set to stage %d (%d hexes changed): district stage %d" % [id, stage, n, _districts.stage_of(id)])
