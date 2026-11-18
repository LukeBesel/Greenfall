class_name SphereWalker
extends CharacterBody3D
## [smove] Lumi on a planet: the real PatchModel driven by SphereMotor. Input is read in the
## camera's surface frame (`cam.frame`: x right, y up, z back; parallel-transported), or in the
## walker's own transported frame when there is no camera, so a held stick walks a great circle.
## API kept for the orbit prototype: up(), face(fwd), distance, input.
## Patch.gd can use SphereMotor directly the same way (see step() below).

var input: InputSource
var cam: Node3D  # SphereCam (anything with a `frame: Basis`)
var surface: SphereSurface
var motor: SphereMotor
var model: PatchModel
var with_model: bool = true
## Optional per-physics-frame hook: scoop_fn.call(self, delta) while scoop is held.
var scoop_fn: Callable
var distance: float:
	get:
		return motor.distance if motor else 0.0
var _frame := Basis()
var _prev_v := Vector3.ZERO
var _was_moving: bool = false
var _tilt := Quaternion.IDENTITY


func _init(p_surface: SphereSurface = null) -> void:
	surface = p_surface if p_surface else SphereSurface.new()
	motor = SphereMotor.new(surface)


func _ready() -> void:
	add_to_group("sphere_walker")
	collision_layer = 2
	collision_mask = 1 | 4
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Lifted 0.25 m off the floor: the hover spring holds the height, the box only meets walls.
	box.size = Vector3(1.1, 0.95, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.25 + 0.475, 0)
	add_child(shape)
	if with_model:
		model = PatchModel.new()
		model.name = "Model"
		add_child(model)
	if input == null:
		input = SphereInput.new()
	motor.landed.connect(_on_landed)
	motor.jumped.connect(func() -> void:
		if model:
			model.squash(0.3)
		if is_inside_tree() and get_node_or_null("/root/Audio"):
			Audio.play("whoosh", 1.3, -12.0))


func up() -> Vector3:
	return surface.up_at(global_position)


func face(fwd: Vector3) -> void:
	motor.face(self, fwd)
	_frame = SphereMath.basis_from_up_fwd(up(), fwd)


## Puts Lumi on the ground under `pos` facing `fwd` and resets the input frame.
func place(pos: Vector3, fwd: Vector3) -> void:
	motor.place(self, pos, fwd)
	_frame = SphereMath.basis_from_up_fwd(up(), fwd)
	_prev_v = Vector3.ZERO


## The frame stick input is read in (x right, y up, z back).
func input_frame() -> Basis:
	if cam and "frame" in cam:
		return cam.get("frame")
	return _frame


func wish_from_stick(mv: Vector3) -> Vector3:
	var f: Basis = input_frame()
	return f.x * mv.x + f.z * mv.z


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	input.update(delta)
	var u0: Vector3 = up()
	var mv: Vector3 = input.get_world_move(0.0)  # camera-local: x right, z back
	var boost: bool = input.has_method("boost_held") and input.call("boost_held")
	var jump: bool = input.has_method("jump_pressed") and input.call("jump_pressed")
	var wish: Vector3 = wish_from_stick(mv) if mv.length_squared() > 0.0001 else Vector3.ZERO
	motor.step(self, wish, delta, boost, jump)
	var u1: Vector3 = up()
	_frame = SphereMath.transport(_frame, u0, u1).orthonormalized()
	if scoop_fn.is_valid() and input.scoop_held():
		scoop_fn.call(self, delta)
	_animate(delta)


func _animate(delta: float) -> void:
	if model == null:
		return
	var hs: float = motor.hv.length()
	var acc: Vector3 = (motor.hv - _prev_v) / maxf(delta, 0.0001)
	_prev_v = motor.hv
	var la: Vector3 = global_basis.inverse() * acc
	model.set_motion(hs, motor.speed_ratio(), Vector2(la.x, -la.z), delta)
	# Lean the model onto the terrain (the body itself stays radial so the frame never wobbles),
	# and a little nose-down while boosting.
	var nl: Vector3 = (global_basis.inverse() * motor.ground_normal).normalized()
	var want := Quaternion(Vector3.UP, nl).slerp(Quaternion.IDENTITY, 0.35) if nl.dot(Vector3.UP) < 0.99999 else Quaternion.IDENTITY
	want = want * Quaternion(Vector3.RIGHT, -0.12 * motor.boost_t)
	_tilt = _tilt.slerp(want, SphereMath.damp(8.0, delta))
	model.quaternion = _tilt
	var moving: bool = hs > 0.6
	if moving != _was_moving:
		_was_moving = moving
		model.squash(0.25 if moving else -0.3)


func _on_landed(impact: float) -> void:
	if model and impact > 2.0:
		model.squash(-clampf(impact * 0.06, 0.1, 0.45))
	if impact > 3.0 and is_inside_tree() and get_node_or_null("/root/Vfx"):
		Vfx.burst("dust", global_position + up() * 0.1, Color(0.8, 0.65, 0.5, 0.6), 0.6)
