extends Node
## [intro2] Startup: the first frame is the loading screen (ui/loading_screen.gd), which loads the
## title screen on a thread and warms its shaders before showing it.


func _ready() -> void:
	if DevHooks.has("sphere-demo"):  # [sgrid] hex globe foundation demo (planet/sphere/sphere_demo.gd)
		get_tree().change_scene_to_file.call_deferred("res://planet/sphere/sphere_demo.tscn")
		return
	if DevHooks.has("orbit"):  # [orbB] --orbit (dev): straight into the game (scenes/slice.tscn on the globe), no title screen
		Loader.goto("res://scenes/slice.tscn")
		return
	Loader.goto("res://scenes/main_menu.tscn")
