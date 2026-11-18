class_name PlayerInput
extends InputSource
## Reads named input actions (keyboard/mouse/controller; touch overlay injects the same actions).

var enabled: bool = true:
	set(v):
		if v and not enabled:
			_enabled_at = Engine.get_physics_frames()
		enabled = v
var _scoop_toggled: bool = false
## Physics frame input was last re-enabled on. The press that closed a modal (B on a controller
## is both ui_cancel and drop; E closes a memory shard) must not also act in gameplay.
var _enabled_at: int = -1


func _fresh() -> bool:
	# The closing press can still read as just_pressed on the next physics step, so skip both.
	return enabled and (_enabled_at < 0 or Engine.get_physics_frames() - _enabled_at > 1)


func get_world_move(cam_yaw: float) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var v: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := Basis(Vector3.UP, cam_yaw)
	var w: Vector3 = basis * Vector3(v.x, 0.0, v.y)
	return w.limit_length(1.0)


func update(_delta: float) -> void:
	if _fresh() and not Settings.hold_to_scoop and Input.is_action_just_pressed("scoop"):
		_scoop_toggled = not _scoop_toggled


func scoop_held() -> bool:
	if not enabled:
		return false
	return Input.is_action_pressed("scoop") if Settings.hold_to_scoop else _scoop_toggled


func cube_pressed() -> bool:
	return _fresh() and Input.is_action_just_pressed("cube")


func interact_pressed() -> bool:
	return _fresh() and Input.is_action_just_pressed("interact")


func drop_pressed() -> bool:
	return _fresh() and Input.is_action_just_pressed("drop")
