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
## after the build), --shot-height=M (command view height past the game's 400 m zoom limit).

const FAST_SLICE_US: int = 1500000


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
