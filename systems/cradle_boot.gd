extends Node
## [late] Autoload "CradleBoot": loads the Cradle Mode profile (systems/cradle_mode.gd) at startup,
## before the title screen or a district reads a save, and points SaveManager at the current
## world's slot.


func _ready() -> void:
	CradleMode.boot()
