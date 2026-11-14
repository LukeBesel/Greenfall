class_name InputSource
extends RefCounted
## Abstract source of Patch's intentions. The player, the autoplay bot and touch controls all
## implement this, so gameplay code never reads raw devices.


## Desired movement in world space (XZ, length 0..1). cam_yaw = camera yaw in radians.
func get_world_move(_cam_yaw: float) -> Vector3:
	return Vector3.ZERO


func scoop_held() -> bool:
	return false


func cube_pressed() -> bool:
	return false


func interact_pressed() -> bool:
	return false


func drop_pressed() -> bool:
	return false


## Called once per physics frame before the getters (for edge detection).
func update(_delta: float) -> void:
	pass
