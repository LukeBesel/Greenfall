class_name SphereAutoInput
extends InputSource
## [smove] Dev/test input: a fixed camera-local stick (x right, z back; default straight ahead),
## optional boost, scoop and a jump every `jump_every` seconds (0 = never).

var stick := Vector3(0, 0, -1)
var boost: bool = false
var scoop: bool = false
var jump_every: float = 0.0
var active: bool = true
var _t: float = 0.0
var _jump: bool = false


func _init(p_stick: Vector3 = Vector3(0, 0, -1), p_boost: bool = false) -> void:
	stick = p_stick.limit_length(1.0)
	boost = p_boost


func update(delta: float) -> void:
	_jump = false
	if jump_every > 0.0:
		_t += delta
		if _t >= jump_every:
			_t = 0.0
			_jump = true


func get_world_move(_cam_yaw: float) -> Vector3:
	return stick if active else Vector3.ZERO


func boost_held() -> bool:
	return active and boost


func jump_pressed() -> bool:
	return active and _jump


func scoop_held() -> bool:
	return active and scoop
