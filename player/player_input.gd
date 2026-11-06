class_name PlayerInput
extends InputSource
## Reads named input actions (keyboard/mouse/controller; touch overlay injects the same actions).

var enabled: bool = true
var _scoop_toggled: bool = false


func get_world_move(cam_yaw: float) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var v: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := Basis(Vector3.UP, cam_yaw)
	var w: Vector3 = basis * Vector3(v.x, 0.0, v.y)
	return w.limit_length(1.0)


func update(_delta: float) -> void:
	if enabled and not Settings.hold_to_scoop and Input.is_action_just_pressed("scoop"):
		_scoop_toggled = not _scoop_toggled


func scoop_held() -> bool:
	if not enabled:
		return false
	return Input.is_action_pressed("scoop") if Settings.hold_to_scoop else _scoop_toggled


func cube_pressed() -> bool:
	return enabled and Input.is_action_just_pressed("cube")


func interact_pressed() -> bool:
	return enabled and Input.is_action_just_pressed("interact")


func drop_pressed() -> bool:
	return enabled and Input.is_action_just_pressed("drop")
