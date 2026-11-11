extends Node
## World audit renders (task M3-17). Starts the slice without the menu and loading screen, makes it
## the current scene (so --scene-stats and --shot work as usual), and lets a hub town that builds
## in play use long work slices: on software GL a frame takes about a second, and the game's 6 ms
## a frame would never finish a town before the screenshot. Nothing is saved (--fresh).
## Run (one at a time):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1280x720 res://tools/world_audit/world_shot.tscn -- --fresh --no-intro \
##     --quality=1 --no-hud --orbit-spawn=x,z,yaw --shot=PATH --shot-delay=S --quit-after=S
## Extra flags: --shot-cam=dist,pitch (follow camera distance in m and pitch in radians, set
## after the build), --shot-height=M (command view height past the game's 400 m zoom limit),
## --town-stage=N (the towns' own look for district stage N, through TownSite.set_district_stage:
## lights, trees, paving and planting only. No hex changes, so nothing is cleaned and stage 5 does
## not start the ending; pair it with --district-stage=ID:4 for a clean, fully restored town),
## --town-source=shut_down (every town's pollution source in that state, through
## TownSite.set_source_state), --shot-hub=N[,x,z,yaw_deg] (stand on hub N's site, x m east and
## z m south of its centre in the site's own frame, turned yaw_deg from its north; the local time
## there is --orbit-time, 0.42 by default, so far hubs render in daylight too).

const FAST_SLICE_US: int = 1500000
const FLAG_TOWN_STAGE: String = "town-stage"
const FLAG_TOWN_SOURCE: String = "town-source"
const FLAG_HUB: String = "shot-hub"
const TOWN_STAGE_EVERY: int = 5  # frames between looks for towns that came up since
const DEFAULT_TIME: float = 0.42

var _frame: int = 0
var _at_hub: bool = false


func _ready() -> void:
	await get_tree().process_frame
	var s: Node = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(s)
	get_tree().current_scene = s
	var orbit: SliceOrbit = s.get("orbit")
	if orbit and orbit.cam:
		if DevHooks.has("shot-cam"):
			var a: PackedStringArray = DevHooks.get_s("shot-cam", "6,-0.3").split(",")
			orbit.cam.distance = float(a[0])
			if a.size() > 1:
				orbit.cam.pitch = float(a[1])
		if DevHooks.has("shot-height"):
			orbit.cam.max_command = maxf(orbit.cam.max_command, DevHooks.get_f("shot-height", 400.0))
			orbit.cam.command_height = DevHooks.get_f("shot-height", 400.0)


func _process(_delta: float) -> void:
	var b: BuildBudget = BuildBudget.current
	if b and b.play_slice_us > 0 and b.play_slice_us < FAST_SLICE_US:
		b.play_slice_us = FAST_SLICE_US
		b.set("_slice_us", FAST_SLICE_US)
	_frame += 1
	var scene: Node = get_tree().current_scene
	if scene == null or _frame % TOWN_STAGE_EVERY != 0:
		return
	if DevHooks.has(FLAG_HUB) and not _at_hub:
		_go_to_hub(scene.get("orbit") as SliceOrbit)
	if DevHooks.has(FLAG_TOWN_STAGE) or DevHooks.has(FLAG_TOWN_SOURCE):
		_set_town_stage(scene, int(DevHooks.get_f(FLAG_TOWN_STAGE, -1.0)), DevHooks.get_s(FLAG_TOWN_SOURCE, ""))


## Stands Lumi on hub N's site (once the globe and Lumi are up) and sets the local time there.
func _go_to_hub(orbit: SliceOrbit) -> void:
	if orbit == null or orbit.cam == null or orbit.globe == null or orbit.globe.site_manager == null:
		return
	var patch: Patch = orbit.w.get("patch") as Patch
	var a: PackedStringArray = DevHooks.get_s(FLAG_HUB, "0").split(",")
	var sm: SiteManager = orbit.globe.site_manager
	var hub: int = int(a[0])
	if patch == null or hub < 0 or hub >= sm.sites.size():
		return
	_at_hub = true
	var xf: Transform3D = sm.sites[hub]["transform"]
	var at: Vector3 = xf * Vector3(float(a[1]) if a.size() > 1 else 0.0, 0.0, float(a[2]) if a.size() > 2 else 0.0)
	var up: Vector3 = at.normalized()
	var north: Vector3 = (-xf.basis.z).normalized().rotated(xf.basis.y.normalized(), deg_to_rad(float(a[3]) if a.size() > 3 else 0.0))
	north = (north - up * north.dot(up)).normalized()
	patch.place_on_sphere(orbit.globe.terrain.ground(up) + up * 0.3, north)
	orbit.cam.reset_frame(north)
	orbit.cam.snap()
	if orbit.day:
		orbit.day.set("_phi0", atan2(up.x, up.z) + (DevHooks.get_f("orbit-time", DEFAULT_TIME) - 0.5) * TAU - TAU * orbit.day.elapsed() / (orbit.day.day_min * 60.0))


## Every town under `n` takes the look of district stage `stage` (-1: left alone) and its source
## the state `source` ("": left alone). Towns build in play, so this runs again and again; a town
## already there is left alone.
func _set_town_stage(n: Node, stage: int, source: String) -> void:
	if n is TownSite:
		var t: TownSite = n
		if stage >= 0 and t.district_stage != stage:
			t.set_district_stage(stage)
		if source != "" and t.source_state != source:
			t.set_source_state(source)
		return
	for c: Node in n.get_children():
		_set_town_stage(c, stage, source)
