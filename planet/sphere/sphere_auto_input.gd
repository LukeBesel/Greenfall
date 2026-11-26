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
			return Vector3(-signf(_net), 0, -0.15).normalized()
	return stick


func _detour(delta: float) -> void:
	if body == null or not active or stick.length() < 0.1:
		return
	# Stalled = little net ground covered over the last WINDOW_S (pressing on a mound jitters
	# at ~1 m/s without getting anywhere, so instantaneous speed can't tell).
	_win_t += delta
	if _win_t >= WINDOW_S:
		var p: Vector3 = body.global_position
		_win_stalled = _win_pos != Vector3.ZERO and p.distance_to(_win_pos) < WINDOW_MIN_M
		_win_pos = p
		_win_t = 0.0
	_stall = _stall + delta if _win_stalled else 0.0
	_phase_t += delta
	match _phase:
		0:  # ahead: a stall starts a sidestep, each one longer while the obstacle goes on
			_free_t += delta
			if _free_t > 12.0:
				_escal = 0
			if _stall >= STALL_S:
				_go_side()
		1:  # sideways: blocked this way too -> the other way, longer
			_net += _side * delta
			if _stall >= STALL_S:
				_side = -_side
				_go_side()
			elif _phase_t >= _side_dur:
				_phase = 2
				_phase_t = 0.0
				_stall = 0.0
				_win_stalled = false
		2:  # pass the obstacle: still blocked -> keep sidestepping the same way
			if _stall >= STALL_S:
				_go_side()
			elif _phase_t >= PASS_S:
				_phase = 3
				_phase_t = 0.0
				_stall = 0.0
		3:  # step back onto the line by the net offset (a blocked return just carries on ahead)
			_net -= signf(_net) * delta
			if absf(_net) < 0.1 or _stall >= STALL_S:
				_phase = 0
				_phase_t = 0.0
				_stall = 0.0
				_free_t = 0.0


var _escal: int = 0
const WINDOW_S: float = 0.5
const WINDOW_MIN_M: float = 0.6
var _win_t: float = 0.0
var _win_pos := Vector3.ZERO
var _win_stalled: bool = false
var _side_dur: float = SIDE_S
var _net: float = 0.0
var _free_t: float = 0.0


func _go_side() -> void:
	_win_stalled = false
	_win_t = 0.0
	_win_pos = Vector3.ZERO
	_escal = mini(_escal + 1, 6)
	_side_dur = SIDE_S * float(_escal)
	_phase = 1
	_phase_t = 0.0
	_stall = 0.0
	_free_t = 0.0


func boost_held() -> bool:
	return active and boost


func jump_pressed() -> bool:
	return active and _jump


func scoop_held() -> bool:
	return active and scoop
