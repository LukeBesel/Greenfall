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
		_arm.spring_length = lerpf(_arm.spring_length, distance, clampf(delta * 8.0, 0.0, 1.0))
	rotation.y = yaw
	_pitch_node.rotation.x = pitch
	# Shake.
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	_noise_t += delta * 40.0
	var s: float = _trauma * _trauma * Settings.shake_intensity
	camera.h_offset = sin(_noise_t * 1.3) * 0.25 * s
	camera.v_offset = sin(_noise_t * 1.7 + 2.0) * 0.25 * s
	camera.rotation.z = sin(_noise_t * 0.9 + 5.0) * 0.03 * s


func snap() -> void:
	if target:
		_focus = target.global_position + Vector3(0, 1.1, 0)
		global_position = _focus
		_arm.spring_length = distance


## Fixed framings for automated screenshots.
func apply_preset(name: String) -> void:
	match name:
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
