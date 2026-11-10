extends PaceSimRdPolicy
## A player who never builds a robot, nor anything only robots need (Bot Bay, base levels, robot
## research). The game must still be finishable this way.


func _init() -> void:
	buys_robots = false
