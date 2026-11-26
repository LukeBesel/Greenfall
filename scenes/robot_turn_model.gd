extends Node3D
## [art6] A helper robot as a turnaround model (tools/turnaround.sh takes a model script):
##   tools/turnaround.sh res://scenes/robot_turn_model.gd OUT --bot=haulbug --bot-look=salvage [--bot-work] [--bot-speed=2] [--bot-carry=4]
## Faces -Z like every robot visual. --bot-work plays the working cycle, --bot-speed drives the wheels.

var _v: RobotVisual


func _ready() -> void:
	_v = RobotVisual.new()
	add_child(_v)
	_v.build(DevHooks.get_s("bot", "scoopie"), DevHooks.get_s("bot-look", "salvage"))
	if DevHooks.has("bot-carry") and _v.has_method("set_load"):
		_v.call("set_load", int(DevHooks.get_f("bot-carry", 0.0)))


func _process(delta: float) -> void:
	_v.animate(DevHooks.get_f("bot-speed", 0.0), DevHooks.has("bot-work"), delta)
