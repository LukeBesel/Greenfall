class_name StraightWalkInput
extends InputSource
## [orbit] Dev input: Lumi walks in a fixed world direction (XZ) at `strength`, nothing else.
## Used by the edge test (--edge-test) and the orbit loop test (--orbit-walk).

var dir := Vector3(1, 0, 0)
var strength: float = 1.0
var active: bool = true


func _init(p_dir: Vector3 = Vector3(1, 0, 0), p_strength: float = 1.0) -> void:
	dir = Vector3(p_dir.x, 0.0, p_dir.z).normalized()
	strength = p_strength


func get_world_move(_cam_yaw: float) -> Vector3:
	return dir * strength if active else Vector3.ZERO
