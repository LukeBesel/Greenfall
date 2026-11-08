extends Node
## [intro2] Startup: the first frame is the loading screen (ui/loading_screen.gd), which loads the
## title screen on a thread and warms its shaders before showing it.


func _ready() -> void:
	if DevHooks.has("sphere-demo"):  # [sgrid] hex globe foundation demo (planet/sphere/sphere_demo.gd)
		get_tree().change_scene_to_file.call_deferred("res://planet/sphere/sphere_demo.tscn")
		return
	if SliceOrbit.wanted():  # [orbB] --orbit: the game's slice on the walkable globe (scenes/slice_orbit.gd)
		Loader.goto("res://scenes/slice.tscn")
		return
	if DevHooks.has("orbit"):  # [orbit] walkable globe prototype (planet/orbit/verdance_globe.gd; --orbit=v1 the first one)
		Loader.goto("res://planet/orbit/%s.tscn" % ("orbit_world" if DevHooks.get_s("orbit", "") == "v1" else "verdance_globe"))
		return
	Loader.goto("res://scenes/main_menu.tscn")
