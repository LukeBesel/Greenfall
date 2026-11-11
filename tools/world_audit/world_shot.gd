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
## not start the ending; pair it with --district-stage=ID:4 for a clean, fully restored town).

const FAST_SLICE_US: int = 1500000
const FLAG_TOWN_STAGE: String = "town-stage"
const TOWN_STAGE_EVERY: int = 5  # frames between looks for towns that came up since

var _frame: int = 0


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
	if DevHooks.has(FLAG_TOWN_STAGE) and _frame % TOWN_STAGE_EVERY == 0 and get_tree().current_scene:
		_set_town_stage(get_tree().current_scene, int(DevHooks.get_f(FLAG_TOWN_STAGE, 0.0)))


## Every town under `n` takes the look of district stage `stage` (towns build in play, so this
## runs again and again; a town already at the stage is left alone).
func _set_town_stage(n: Node, stage: int) -> void:
	if n is TownSite:
		if (n as TownSite).district_stage != stage:
			(n as TownSite).set_district_stage(stage)
		return
	for c: Node in n.get_children():
		_set_town_stage(c, stage)
