extends Node
## [intro2] Startup: the first frame is the loading screen (ui/loading_screen.gd), which loads the
## title screen on a thread and warms its shaders before showing it.


func _ready() -> void:
	if DevHooks.has("orbit"):  # [orbB] dev: straight into the game, past the title screen
		Loader.goto("res://scenes/slice.tscn")
		return
	Loader.goto("res://scenes/main_menu.tscn")
