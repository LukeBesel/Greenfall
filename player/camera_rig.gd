class_name CameraRig
extends Node3D
## Smooth third-person follow camera with orbit (mouse / right stick), zoom, trauma-based shake,
## and an optional first-person "lens view".

var target: Node3D
var yaw: float = 0.0
var pitch: float = -0.3
var distance: float = 6.2
var min_distance: float = 3.5
var max_distance: float = 26.0
var lens_view: bool = false
var input_enabled: bool = true

var camera: Camera3D
var _arm: SpringArm3D
var _pitch_node: Node3D
var _trauma: float = 0.0
var _focus := Vector3.ZERO
var _noise_t: float = 0.0
## Mouse look not yet applied (Settings.mouse_smoothing eases it in over a few frames).
var _look_pending := Vector2.ZERO
## [onboard2] Arm length that keeps the view's edges clear of nearby walls and roofs (see clear_length).
var _clear_len: float = INF
var _clear_t: float = 0.0


func _ready() -> void:
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.3
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	_arm.shape = sph
	_pitch_node.add_child(_arm)
	camera = Camera3D.new()
	camera.fov = Settings.fov
	camera.far = 600.0
	# Gentle far blur on High/Ultra: distant skyline softens like a real lens, the play area stays sharp.
	if Settings.quality >= Settings.Quality.HIGH:
		var attrs := CameraAttributesPractical.new()
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = 55.0
		attrs.dof_blur_far_transition = 60.0
		attrs.dof_blur_amount = 0.06
		camera.attributes = attrs
	_arm.add_child(camera)
	camera.current = true
	EventBus.shake_requested.connect(add_trauma)


func add_trauma(amount: float) -> void:
	if Settings.shake_intensity > 0.0 and not Settings.reduced_motion:
		_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m: InputEventMouseMotion = event
		var d := Vector2(m.relative.x, m.relative.y * (-1.0 if Settings.invert_y else 1.0)) * Settings.mouse_sensitivity
		if Settings.mouse_smoothing:
			_look_pending += d
		else:
			yaw -= d.x
			pitch -= d.y
	elif event.is_action_pressed("zoom_in"):
		distance = maxf(min_distance, distance * 0.88)
	elif event.is_action_pressed("zoom_out"):
		distance = minf(max_distance, distance * 1.13)
	elif event.is_action_pressed("lens_view"):
		lens_view = not lens_view


func _process(delta: float) -> void:
	if target == null:
		return
	if input_enabled:
		var look: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
		yaw -= look.x * 2.6 * delta * Settings.stick_sensitivity  # [deck]
		pitch -= look.y * 1.8 * delta * Settings.stick_sensitivity * (-1.0 if Settings.invert_y else 1.0)
	if _look_pending != Vector2.ZERO:
		var take: Vector2 = _look_pending * clampf(delta * 18.0, 0.0, 1.0) if Settings.mouse_smoothing else _look_pending
		yaw -= take.x
		pitch -= take.y
		_look_pending -= take
		if _look_pending.length_squared() < 1e-8:
			_look_pending = Vector2.ZERO
	pitch = clampf(pitch, -1.35, -0.08) if not lens_view else clampf(pitch, -0.9, 0.6)
	var want: Vector3 = target.global_position + Vector3(0, 1.1, 0)
	_focus = _focus.lerp(want, clampf(delta * 10.0, 0.0, 1.0)) if _focus != Vector3.ZERO else want
	if lens_view and target is Patch:
		var p: Patch = target
		global_position = p.to_global(p.model.lens_point)
		yaw = lerp_angle(yaw, p.rotation.y, clampf(delta * 6.0, 0.0, 1.0))
		_arm.spring_length = 0.0
		camera.near = 0.32  # look past the lens housing itself
		camera.fov = lerpf(camera.fov, Settings.fov + 10.0, clampf(delta * 6.0, 0.0, 1.0))
	else:
		global_position = _focus
		camera.near = 0.05
		camera.fov = lerpf(camera.fov, Settings.fov, clampf(delta * 6.0, 0.0, 1.0))
		# [onboard2] The arm alone only sweeps the centre line, so a roof or wall near the camera could
		# fill a corner of the view as a big dark slab. Pull in until the frustum's near edges are clear.
		_clear_t -= delta
		if _clear_t <= 0.0:
			_clear_t = 0.1
			var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(16, 9)
			_clear_len = clear_length(get_world_3d().direct_space_state, _focus, view_basis(yaw, pitch), distance, \
					min_distance, camera.fov, vp.x / maxf(vp.y, 1.0))
		var want_len: float = minf(distance, _clear_len)
		var rate: float = 8.0 if want_len < _arm.spring_length else 3.0  # in quickly, out gently
		_arm.spring_length = lerpf(_arm.spring_length, want_len, clampf(delta * rate, 0.0, 1.0))
	rotation.y = yaw
	_pitch_node.rotation.x = pitch
	# Shake.
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	_noise_t += delta * 40.0
	var s: float = _trauma * _trauma * Settings.shake_intensity
	camera.h_offset = sin(_noise_t * 1.3) * 0.25 * s
	camera.v_offset = sin(_noise_t * 1.7 + 2.0) * 0.25 * s
	camera.rotation.z = sin(_noise_t * 0.9 + 5.0) * 0.03 * s


## The arm's orientation for a yaw/pitch (the camera looks along -Z of it, and sits at +Z * length).
static func view_basis(yaw_: float, pitch_: float) -> Basis:
	return Basis(Vector3.UP, yaw_) * Basis(Vector3.RIGHT, pitch_)


## Directions (in view space) to the frustum's corners and edge midpoints, top excluded (the sky).
static func edge_dirs(fov_deg: float, aspect: float) -> Array[Vector3]:
	var ty: float = tan(deg_to_rad(fov_deg) * 0.5)
	var tx: float = ty * aspect
	var out: Array[Vector3] = []
	for v: Vector2 in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]:
		out.append(Vector3(v.x * tx, v.y * ty, -1.0).normalized())
	return out


## [onboard2] The longest arm (from `want` down to `min_len`) whose camera sees no WORLD geometry
## (walls, roofs, stations) close by along its view edges: anything nearer than ~40% of the arm,
## standing higher than the focus, would fill that part of the screen. Ground hits don't count.
static func clear_length(space: PhysicsDirectSpaceState3D, focus: Vector3, b: Basis, want: float, min_len: float, \
		fov_deg: float, aspect: float) -> float:
	if space == null:
		return want
	var dirs: Array[Vector3] = edge_dirs(fov_deg, aspect)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = PhysLayers.WORLD
	q.hit_from_inside = true
	var l: float = want
	for k: int in 7:
		var cam_pos: Vector3 = focus + b * Vector3(0, 0, l)
		var reach: float = maxf(2.0, l * 0.4)
		var blocked: bool = false
		for d: Vector3 in dirs:
			q.from = cam_pos
			q.to = cam_pos + b * d * reach
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).y > focus.y - 0.6:
				blocked = true
				break
		if not blocked:
			return l
		if l <= min_len:
			break
		l = maxf(min_len, l * 0.8)
	return min_len


func snap() -> void:
	if target:
		_focus = target.global_position + Vector3(0, 1.1, 0)
		global_position = _focus
		_arm.spring_length = distance


## Fixed framings for automated screenshots.
func apply_preset(name_: String) -> void:
	match name_:
		"close":
			distance = 4.2
			pitch = -0.32
		"wide":
			distance = 22.0
			pitch = -0.75
		"top":
			distance = 40.0
			pitch = -1.3
		"side":
			distance = 5.0
			pitch = -0.2
			yaw += PI * 0.5
		"front":
			distance = 4.5
			pitch = -0.25
			yaw += PI
	snap()
