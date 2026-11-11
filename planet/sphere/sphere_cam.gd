class_name SphereCam
extends Node3D
## [smove] Follow camera for a planet. `frame` is the camera's surface frame (x right, y local up,
## z back) at the target. Each frame it is parallel-transported from the old up to the new one,
## so walking straight never spins the view, and yaw input rotates it about the local up. The
## camera is built with look_at(up = frame.y): its right vector is always perpendicular to the
## local up, so the horizon stays level at any latitude, poles included.
## Views: "follow" (behind and above, mouse / right-stick orbit, zoom, spring-arm collision) and
## "command" (high overhead looking down at the local area; zoom changes the height). Hover-boost
## pulls the camera back, widens the FOV and lazily swings it behind Lumi's heading.

var target: Node3D
var surface: SphereSurface
var frame := Basis()
var view: String = "follow":
	set(v):
		view = v
var input_enabled: bool = true
## [orbE] First-person lens view (the flat CameraRig's, for LensOverlay): the eye at Lumi's lens,
## looking along the camera frame, level on the local up.
var lens_view: bool = false
var _near0: float = -1.0
var pitch: float = -0.32
var distance: float = 6.2
var min_distance: float = 3.5
var max_distance: float = 26.0
var command_height: float = 70.0
var min_command: float = 30.0
var max_command: float = 400.0
var command_tilt: float = 0.35  # radians off straight down, top of screen = frame forward
var fov: float = 70.0
var collide_mask: int = 1
## Auto swing-behind (rad/s at full boost); manual look suspends it for `manual_hold` seconds.
var follow_rate: float = 1.6
var manual_hold: float = 1.5

var camera: Camera3D
## [orbC] Command view can pan away from the target: a unit direction on the planet it centres on
## (ZERO = over the target). pan_command() moves it; leaving Command view recentres.
var command_focus := Vector3.ZERO
var _focus := Vector3.ZERO
var _arm: float = 6.2
var _mode_t: float = 0.0  # 0 follow .. 1 command
var _look_pending := Vector2.ZERO
var _manual_t: float = 0.0
var _last_up := Vector3.ZERO
var _boost_fx: float = 0.0
## [v6feel] The flat camera's manners, on the globe: a soft arm that eases in before a wall cuts the
## view (whiskers either side and above), screen shake, and Lumi hidden when the camera is in his head.
var _soft: float = 6.2
var _trauma: float = 0.0
var _noise_t: float = 0.0
var _hid: Node3D
const HIDE_IN_M: float = 1.3
const HIDE_OUT_M: float = 1.6
## Extra downward pitch (radians) while a wall close behind Lumi cuts the arm short: the camera
## climbs the wall and looks down at him instead of sitting in the back of his head.
var _tilt: float = 0.0
const TILT_BELOW_M: float = 3.0
const TILT_MAX: float = -1.5  # [v6feel] the steepest the climb goes (radians; -PI/2 is straight down)
const WHISKER: float = 0.38  # radians either side of the arm, and above it


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = _setting("fov", fov)
	camera.near = 0.05
	camera.far = 20000.0
	add_child(camera)
	camera.current = true
	if surface == null:
		surface = SphereSurface.new()
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("shake_requested"):
		bus.connect("shake_requested", add_trauma)  # [v6feel] bale press, depot, big pieces


## [v6feel] Screen shake (honours the Shake setting and Reduced motion, as the flat camera did).
func add_trauma(amount: float) -> void:
	if float(_setting("shake_intensity", 1.0)) > 0.0 and not bool(_setting("reduced_motion", false)):
		_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _setting(n: String, d: Variant) -> Variant:
	var s: Node = get_node_or_null("/root/Settings")
	return s.get(n) if s and s.get(n) != null else d


## Re-centres the frame behind the target's facing `fwd` and snaps the camera into place.
func reset_frame(fwd: Vector3) -> void:
	if target == null:
		return
	var u: Vector3 = surface.up_at(target.global_position)
	var b: Basis = SphereMath.basis_from_up_fwd(u, fwd)
	frame = b
	_last_up = u
	snap()


func snap() -> void:
	if target == null:
		return
	var u: Vector3 = surface.up_at(target.global_position)
	_focus = target.global_position + u * 1.1
	_arm = distance
	_soft = distance
	_mode_t = 1.0 if view == "command" else 0.0
	update_camera(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m: InputEventMouseMotion = event
		var inv: float = -1.0 if _setting("invert_y", false) else 1.0
		_look_pending += Vector2(m.relative.x, m.relative.y * inv) * float(_setting("mouse_sensitivity", 0.003))
		_manual_t = manual_hold
	elif InputMap.has_action("lens_view") and event.is_action_pressed("lens_view") and view == "follow":  # [orbE]
		lens_view = not lens_view
	elif event.is_action_pressed("zoom_in"):
		if view == "command":
			command_height = maxf(min_command, command_height * 0.85)
		else:
			distance = maxf(min_distance, distance * 0.88)
	elif event.is_action_pressed("zoom_out"):
		if view == "command":
			command_height = minf(max_command, command_height * 1.18)
		else:
			distance = minf(max_distance, distance * 1.13)


## [orbC] Pan the Command view: v = stick/keys (x right, y down = toward the screen's bottom),
## at a speed that grows with height, along the camera frame on the planet.
func pan_command(v: Vector2, delta: float) -> void:
	if view != "command" or target == null or v == Vector2.ZERO:
		return
	if command_focus == Vector3.ZERO:
		command_focus = surface.up_at(target.global_position)
	var move: Vector3 = frame.x * v.x + frame.z * v.y
	var m: Vector3 = SphereMath.tangent(move, command_focus)
	if m.length() < 1e-5:
		return
	var dist: float = command_height * 1.2 * delta * minf(v.length(), 1.0)
	var adv: Array = SphereMath.advance(command_focus, m.normalized(), dist / surface.radius)
	command_focus = adv[0]


func recenter_command() -> void:
	command_focus = Vector3.ZERO


## Yaw the frame about the local up (radians, positive = turn left).
func add_yaw(a: float) -> void:
	frame = (Basis(frame.y, a) * frame).orthonormalized()


func _process(delta: float) -> void:
	update_camera(delta)


func update_camera(delta: float) -> void:
	if target == null or camera == null:
		return
	var tp: Vector3 = target.global_position
	if view != "command":
		command_focus = Vector3.ZERO  # [orbC]
	elif command_focus != Vector3.ZERO:
		tp = surface.ground(command_focus)  # [orbC] panned away from Lumi
	var u: Vector3 = surface.up_at(tp)
	if _last_up == Vector3.ZERO:
		_last_up = u
	frame = SphereMath.transport(frame, _last_up, u)
	# Re-orthonormalise around the exact up so float drift can never tilt the horizon.
	frame = SphereMath.basis_from_up_fwd(u, -frame.z)
	_last_up = u
	# Look input.
	_manual_t = maxf(0.0, _manual_t - delta)
	if input_enabled:
		var look: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down") if InputMap.has_action("look_left") else Vector2.ZERO
		if look != Vector2.ZERO:
			_manual_t = manual_hold
		var ss: float = float(_setting("stick_sensitivity", 1.0))
		var inv: float = -1.0 if _setting("invert_y", false) else 1.0
		add_yaw(-look.x * 2.6 * delta * ss)
		pitch -= look.y * 1.8 * delta * ss * inv
	if _look_pending != Vector2.ZERO:
		var take: Vector2 = _look_pending * clampf(delta * 18.0, 0.0, 1.0) if _setting("mouse_smoothing", false) else _look_pending
		add_yaw(-take.x)
		pitch -= take.y
		_look_pending -= take
		if _look_pending.length_squared() < 1e-8:
			_look_pending = Vector2.ZERO
	if lens_view and view == "follow":  # [orbE] the lens looks level and up as well
		pitch = clampf(pitch, -0.9, 0.6)
	else:
		pitch = clampf(pitch, -1.35, -0.06)
	# Boost: lazily swing behind the heading, pull back, widen the lens.
	var boost: float = 0.0
	var spd: float = 0.0
	var motor: SphereMotor = target.get("motor") as SphereMotor if "motor" in target else null
	if motor:
		boost = motor.boost_t
		spd = motor.hv.length()
	_boost_fx = lerpf(_boost_fx, boost, SphereMath.damp(3.0, delta))
	if motor and spd > 1.0 and _manual_t <= 0.0 and view == "follow" and boost > 0.05:
		var head: Vector3 = SphereMath.tangent_dir(motor.hv, u, -frame.z)
		var cur: Vector3 = -frame.z
		var ang: float = cur.signed_angle_to(head, u)
		add_yaw(clampf(ang, -1.0, 1.0) * minf(1.0, follow_rate * boost * delta))
	# Focus: smoothed in world space; tangent lag is bounded so a boost never loses Lumi.
	var want: Vector3 = tp + u * 1.1
	if _focus == Vector3.ZERO or delta <= 0.0:
		_focus = want
	else:
		# [v6feel] Along the ground it keeps up closely; up and down it follows softly, so a hop over
		# a kerb or a landing is a gentle rise of the view, not a bump.
		var gap: Vector3 = want - _focus
		var gap_up: Vector3 = u * gap.dot(u)
		_focus += (gap - gap_up) * SphereMath.damp(14.0, delta) + gap_up * SphereMath.damp(7.0, delta)
		var lag: Vector3 = want - _focus
		if lag.length() > 2.5:
			_focus = want - lag.normalized() * 2.5
	_mode_t = move_toward(_mode_t, 1.0 if view == "command" else 0.0, delta * 1.6) if delta > 0.0 else _mode_t
	var e: float = _mode_t * _mode_t * (3.0 - 2.0 * _mode_t)
	var fu: Vector3 = surface.up_at(_focus)
	# Follow pose (spring-arm collision against walls and props, never below the ground).
	var want_d: float = distance * (1.0 + 0.45 * _boost_fx)
	var flat_dir: Vector3 = (frame.z * cos(pitch) - frame.y * sin(pitch)).normalized()
	if delta > 0.0 and view == "follow" and not lens_view:
		# [v6feel] How much steeper the view must be for a usable arm (0 when the plain one is fine).
		var tilt_to: float = 0.0
		if _collide(_focus, flat_dir, want_d) < minf(want_d, TILT_BELOW_M):
			var best_d: float = 0.0
			# [v6feel] Up to nearly overhead: backed against a tall wall, every slope still hit it and
			# the camera sat in his head (arm 0.6 m, Lumi hidden).
			for extra: float in [0.3, 0.6, 0.9, 1.2, 1.6]:
				var pt: float = maxf(pitch - extra, TILT_MAX)
				var dt_: float = _collide(_focus, (frame.z * cos(pt) - frame.y * sin(pt)).normalized(), want_d)
				if dt_ > best_d + 0.3:
					best_d = dt_
					tilt_to = pitch - pt
				if dt_ >= minf(want_d, TILT_BELOW_M + 0.6):
					break
		_tilt = lerpf(_tilt, tilt_to, SphereMath.damp(5.0 if tilt_to > _tilt else 1.5, delta))
	elif delta <= 0.0:
		_tilt = 0.0
	var pitch_v: float = maxf(pitch - _tilt, TILT_MAX)
	var dir: Vector3 = (frame.z * cos(pitch_v) - frame.y * sin(pitch_v)).normalized()
	var d: float = _collide(_focus, dir, want_d)
	if delta <= 0.0:
		_soft = want_d
		_arm = d
	else:
		# [v6feel] Whiskers: where the arm would be cut if the view turned a little or a roof came
		# over. The soft arm eases toward that (in quickly, out gently), so most walls pull the
		# camera in before they can cut the view; the centre sweep stays the hard limit.
		var side: Basis = Basis(frame.y, WHISKER)
		var d_l: float = _collide(_focus, side * dir, want_d)
		var d_r: float = _collide(_focus, side.inverse() * dir, want_d)
		var up_dir: Vector3 = Basis(frame.x, -WHISKER) * dir
		var d_u: float = _collide(_focus, up_dir, want_d)
		if d < want_d and _thin_block(dir, want_d):
			d = want_d  # something small crossing the line (a post, a planter's end): look past it
		if d_u < want_d and _thin_block(up_dir, want_d):
			d_u = want_d
		var soft_to: float = clampf(minf(minf(d_l, d_r) + 1.2, d_u + 0.6), minf(want_d, 2.4), want_d)
		_soft = lerpf(_soft, soft_to, SphereMath.damp(8.0 if soft_to < _soft else 3.0, delta))
		_arm = minf(d, lerpf(_arm, minf(_soft, d), SphereMath.damp(10.0, delta)))
	_hide_target(view == "follow" and not lens_view and _mode_t < 0.05)
	var p_follow: Vector3 = _focus + dir * _arm
	var alt: float = surface.altitude(p_follow)
	if alt < 0.45:
		p_follow += surface.up_at(p_follow) * (0.45 - alt)
	var look_follow: Vector3 = _focus
	# Command pose: high above the local area looking down, screen-up = frame forward.
	var p_cmd: Vector3 = _focus + fu * command_height * cos(command_tilt) + frame.z * command_height * sin(command_tilt)
	var look_cmd: Vector3 = _focus - frame.z * command_height * 0.12
	var pos: Vector3 = p_follow.lerp(p_cmd, e)
	var look_at_p: Vector3 = look_follow.lerp(look_cmd, e)
	global_position = pos
	var up_ref: Vector3 = surface.up_at(pos)
	# Straight-down views use frame forward as the screen's up; otherwise the local up (level horizon).
	var fwd_v: Vector3 = (look_at_p - pos).normalized()
	if absf(fwd_v.dot(up_ref)) > 0.995:
		up_ref = -frame.z
	camera.global_transform = Transform3D(Basis.looking_at(fwd_v, up_ref), pos)
	_lens_pose(u)  # [orbE]
	# [v6feel] Shake.
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	_noise_t += delta * 40.0
	var sh: float = _trauma * _trauma * float(_setting("shake_intensity", 1.0))
	camera.h_offset = sin(_noise_t * 1.3) * 0.25 * sh
	camera.v_offset = sin(_noise_t * 1.7 + 2.0) * 0.25 * sh
	if sh > 0.0005:
		camera.global_transform = camera.global_transform * Transform3D(Basis(Vector3(0, 0, 1), sin(_noise_t * 0.9 + 5.0) * 0.03 * sh), Vector3.ZERO)
	var base_fov: float = float(_setting("fov", fov))
	camera.fov = lerpf(camera.fov, base_fov + 12.0 * _boost_fx - 8.0 * e, SphereMath.damp(6.0, delta)) if delta > 0.0 else base_fov


## [orbE] Lens view: the camera at the model's lens point, looking along the frame with pitch.
func _lens_pose(u: Vector3) -> void:
	if _near0 < 0.0:
		_near0 = camera.near
	var model: Node3D = target.get("model") as Node3D if "model" in target else null
	if not lens_view or view != "follow" or model == null:
		camera.near = _near0
		return
	var lp: Variant = model.get("lens_point")
	var eye: Vector3 = model.to_global(lp if lp is Vector3 else Vector3(0, 0.78, -0.3))
	var look: Vector3 = (-frame.z * cos(pitch) + u * sin(pitch)).normalized()
	camera.global_transform = Transform3D(Basis.looking_at(look, u), eye)
	camera.near = 0.32  # look past the lens housing itself (as the flat lens view)


## Spring-arm: the longest clear distance along `dir` from `from` (sphere sweep, radius 0.3).
func _collide(from: Vector3, dir: Vector3, length: float) -> float:
	if not is_inside_tree():
		return length
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return length
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.3
	q.shape = s
	q.collision_mask = collide_mask
	q.transform = Transform3D(Basis(), from)
	q.motion = dir * length
	var r: PackedFloat32Array = space.cast_motion(q)
	if r.size() < 2 or r[0] >= 1.0:
		return length
	return maxf(0.6, length * r[0] - 0.1)


## [v6feel] True when what cuts the arm is narrow (a post, a sign's leg: clear a little to each side) and
## the camera's own spot is free: the arm ignores it instead of jumping in and easing back out.
func _thin_block(dir: Vector3, length: float) -> bool:
	for b: Basis in [Basis(frame.y, 0.22), Basis(frame.y, -0.22)]:
		if _collide(_focus, b * dir, length) < length - 0.05:
			return false
	return _free_at(_focus + dir * length)


## [v6feel] True when a camera-sized ball at `p` touches nothing the arm collides with.
func _free_at(p: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.4
	q.shape = sh
	q.collision_mask = collide_mask
	q.transform = Transform3D(Basis(), p)
	return space.intersect_shape(q, 1).is_empty()


## [v6feel] With a wall right behind him the arm ends in Lumi's head, which then fills the screen:
## closer than HIDE_IN_M his model is hidden (and shown again past HIDE_OUT_M, so it never flickers).
func _hide_target(allowed: bool) -> void:
	var m: Node3D = target.get("model") as Node3D if target and "model" in target else null
	var hide: bool = allowed and m != null and (_arm < HIDE_IN_M or (_hid != null and _arm < HIDE_OUT_M))
	if hide == (_hid != null):
		return
	if is_instance_valid(_hid):
		_hid.visible = true
	_hid = null
	if hide and m.visible:
		m.visible = false
		_hid = m


func hides_target() -> bool:
	return _hid != null


## Roll error in radians: how far the camera's right vector tilts out of the local horizon.
func horizon_roll() -> float:
	var u: Vector3 = surface.up_at(camera.global_position)
	return absf(asin(clampf(camera.global_basis.x.normalized().dot(u), -1.0, 1.0)))
