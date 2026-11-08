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
## [orbD] Detour round obstacles (lap tests): with `body` set, when it stalls for STALL_S while
## pushing ahead, it sidesteps, passes, and steps back onto its line (alternating sides if the
## first side is blocked too), so a junk mound or a prop never ends a lap test.
var body: CharacterBody3D
const STALL_S: float = 0.6
const SIDE_S: float = 1.4
const PASS_S: float = 1.6
var _stall: float = 0.0
var _phase: int = 0  # 0 ahead, 1 side, 2 pass, 3 back
var _phase_t: float = 0.0
var _side: float = 1.0
var _tries: int = 0


func _init(p_stick: Vector3 = Vector3(0, 0, -1), p_boost: bool = false) -> void:
	stick = p_stick.limit_length(1.0)
	boost = p_boost


func update(delta: float) -> void:
	_detour(delta)
	_jump = false
	if jump_every > 0.0:
		_t += delta
		if _t >= jump_every:
			_t = 0.0
			_jump = true


func get_world_move(_cam_yaw: float) -> Vector3:
	if not active:
		return Vector3.ZERO
	match _phase:
		1:
			return Vector3(_side, 0, -0.15).normalized()
		3:
			return Vector3(-_side, 0, -0.15).normalized()
	return stick


func _detour(delta: float) -> void:
	if body == null or not active or stick.length() < 0.1:
		return
	var up: Vector3 = body.global_position.normalized()
	var spd: float = (body.velocity - up * body.velocity.dot(up)).length()
	if _phase == 0:
		_stall = _stall + delta if spd < 0.6 else 0.0
		if _stall >= STALL_S:
			_stall = 0.0
			_phase = 1
			_phase_t = 0.0
		return
	_phase_t += delta
	if _phase == 1 and spd < 0.3 and _phase_t > 0.5:
		_side = -_side  # this side is blocked too: try the other way, a little further
		_tries += 1
		_phase_t = -0.6 * _tries
		return
	var dur: float = SIDE_S if _phase != 2 else PASS_S
	if _phase_t >= dur:
		_phase = (_phase + 1) % 4
		_phase_t = 0.0
		if _phase == 0:
			_tries = 0


func boost_held() -> bool:
	return active and boost


func jump_pressed() -> bool:
	return active and _jump


func scoop_held() -> bool:
	return active and scoop
