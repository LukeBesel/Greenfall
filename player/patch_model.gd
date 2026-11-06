class_name PatchModel
extends Node3D
## Patch, built from code: squat teal box body, domed head fused to the body with one big porthole
## lens, mushroom antenna bulb, stubby mismatched scoop arms, chunky treads, a chest fill gauge,
## one brass bolt that doesn't match, and an old flower sticker. Rusty forever.
## Faces -Z.

const PAINT := Color(0.33, 0.66, 0.62)
const PAINT_LIGHT := Color(0.45, 0.76, 0.7)
const TREAD := Color(0.24, 0.22, 0.28)
const BRASS := Color(0.88, 0.66, 0.3)
const HAND_L := Color(1.0, 0.78, 0.25)
const HAND_R := Color(0.98, 0.52, 0.22)
const LENS_GLASS := Color(0.08, 0.12, 0.22)
const IRIS := Color(0.35, 0.9, 1.0)

var rust_amount: float = 0.45

var _lean: Node3D
var _squash: Node3D
var _head: Node3D
var _iris_group: Node3D
var _pupil: MeshInstance3D
var _iris_mat: ShaderMaterial
var _bulb_mat: ShaderMaterial
var _arm_l: Node3D
var _arm_r: Node3D
var _gauge: MeshInstance3D
var _gauge_mat: StandardMaterial3D
var _tread_mats: Array[ShaderMaterial] = []
var _body_mats: Array[ShaderMaterial] = []
var _all_mats: Array[ShaderMaterial] = []

var _time: float = 0.0
var _scoop_t: float = 0.0
var _scoop_amount: float = 0.0
var _shudder: float = 0.0
var _squash_v: float = 0.0
var _squash_x: float = 0.0
var _blink_timer: float = 2.0
var _tread_offset: float = 0.0
var _look_yaw: float = 0.0
var _look_target_yaw: float = 0.0
var _iris_target: float = 0.5
var _iris_now: float = 0.5
var _lean_now := Vector2.ZERO
var _flash: float = 0.0
var sleeping: bool = false

## Local-space anchor points used by the controller.
var chest_point := Vector3(0, 0.62, -0.3)
var back_hatch_point := Vector3(0, 0.55, 0.5)
var vent_points: Array[Vector3] = [Vector3(-0.2, 1.05, 0.3), Vector3(0.2, 1.05, 0.3)]
var stack_point := Vector3(0, 1.38, 0.08)
var lens_point := Vector3(0, 1.08, -0.32)


func _ready() -> void:
	_build()


func _mat(color: Color, rust: float, seed: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = ProcMesh.toon_material(color, rust, seed)
	_all_mats.append(m)
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _build() -> void:
	_lean = Node3D.new()
	_lean.name = "Lean"
	add_child(_lean)
	_squash = Node3D.new()
	_squash.name = "Squash"
	_lean.add_child(_squash)
	var body_mat: ShaderMaterial = _mat(PAINT, rust_amount, 1.3)
	_body_mats.append(body_mat)

	# Treads
	for side: float in [-1.0, 1.0]:
		var tm: ShaderMaterial = _mat(TREAD, 0.0)
		tm.set_shader_parameter("stripe_freq", 9.0)
		tm.set_shader_parameter("rim_strength", 0.15)
		_tread_mats.append(tm)
		_mesh(_squash, ProcMesh.rounded_box(Vector3(0.26, 0.32, 0.98), 0.12, 3), tm, Vector3(0.42 * side, 0.16, 0.0))
		var hub_mat: ShaderMaterial = _mat(BRASS, 0.35, 4.0 + side)
		for z: float in [-0.3, 0.0, 0.3]:
			_mesh(_squash, ProcMesh.cyl(0.085, 0.085, 0.04, 12), hub_mat, Vector3(0.56 * side, 0.16, z), Vector3(0, 0, 90))

	# Body
	_mesh(_squash, ProcMesh.rounded_box(Vector3(0.8, 0.62, 0.8), 0.11, 4), body_mat, Vector3(0, 0.62, 0))
	# Chest hatch with fill gauge
	var hatch_mat: ShaderMaterial = _mat(PAINT * 0.78, 0.25, 7.0)
	_mesh(_squash, ProcMesh.rounded_box(Vector3(0.5, 0.34, 0.05), 0.04, 2), hatch_mat, Vector3(0, 0.6, -0.4))
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.1, 0.15)
	_mesh(_squash, ProcMesh.box(Vector3(0.09, 0.26, 0.02)), glass, Vector3(0.15, 0.6, -0.43))
	_gauge_mat = StandardMaterial3D.new()
	_gauge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gauge_mat.albedo_color = Color(0.4, 1.0, 0.5)
	var gauge_pivot := Node3D.new()
	gauge_pivot.position = Vector3(0.15, 0.48, -0.445)
	_squash.add_child(gauge_pivot)
	_gauge = _mesh(gauge_pivot, ProcMesh.box(Vector3(0.07, 0.24, 0.01)), _gauge_mat, Vector3(0, 0.12, 0))
	gauge_pivot.scale = Vector3(1, 0.001, 1)
	_gauge.set_meta("pivot", gauge_pivot)
	_mesh(_squash, ProcMesh.cyl(0.025, 0.025, 0.14, 8), _mat(BRASS, 0.3), Vector3(-0.12, 0.6, -0.44), Vector3(0, 0, 90))
	# Back hatch + steam vents
	_mesh(_squash, ProcMesh.rounded_box(Vector3(0.44, 0.3, 0.05), 0.04, 2), hatch_mat, Vector3(0, 0.55, 0.4))
	for vp: Vector3 in vent_points:
		_mesh(_squash, ProcMesh.cyl(0.05, 0.06, 0.16, 10), _mat(TREAD * 1.4, 0.4, vp.x), vp - Vector3(0, 0.08, 0))
	# Bolts: three rusty, one shiny brass that doesn't match.
	var bolt_mat: ShaderMaterial = _mat(Color(0.55, 0.55, 0.58), 0.6, 9.0)
	for bp: Vector3 in [Vector3(0.3, 0.84, -0.405), Vector3(-0.3, 0.38, -0.405), Vector3(0.3, 0.38, -0.405)]:
		_mesh(_squash, ProcMesh.cyl(0.03, 0.03, 0.025, 6), bolt_mat, bp, Vector3(90, 0, 0))
	_mesh(_squash, ProcMesh.cyl(0.045, 0.045, 0.035, 6), _mat(Color(1.0, 0.8, 0.3), 0.0), Vector3(-0.3, 0.84, -0.41), Vector3(90, 0, 0))
	# Flower sticker on the right side, a little faded.
	var petal := _mat(Color(1.0, 0.55, 0.75), 0.15, 2.0)
	var center := _mat(Color(1.0, 0.85, 0.3), 0.1, 3.0)
	var sticker := Node3D.new()
	sticker.position = Vector3(0.405, 0.66, 0.08)
	sticker.rotation_degrees = Vector3(0, 0, -90)
	_squash.add_child(sticker)
	for k: int in 5:
		var a: float = TAU * k / 5.0
		_mesh(sticker, ProcMesh.cyl(0.055, 0.055, 0.008, 10), petal, Vector3(cos(a) * 0.07, 0, sin(a) * 0.07))
	_mesh(sticker, ProcMesh.cyl(0.045, 0.045, 0.012, 10), center, Vector3.ZERO)

	# Head: dome fused onto the body.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 0.93, 0)
	_squash.add_child(_head)
	var dome_mat: ShaderMaterial = _mat(PAINT_LIGHT, rust_amount * 0.7, 5.7)
	_body_mats.append(dome_mat)
	_mesh(_head, ProcMesh.hemisphere(0.37, 20, 8), dome_mat, Vector3.ZERO)
	_mesh(_head, ProcMesh.torus(0.35, 0.4, 24, 6), _mat(PAINT * 0.7, 0.5, 8.0), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	# Lens: porthole on the front of the dome, pitched up a little.
	var lens := Node3D.new()
	lens.name = "Lens"
	lens.position = Vector3(0, 0.16, -0.3)
	lens.rotation_degrees = Vector3(28, 0, 0)
	_head.add_child(lens)
	_mesh(lens, ProcMesh.torus(0.15, 0.2, 24, 8), _mat(BRASS, 0.35, 6.0), Vector3.ZERO, Vector3(90, 0, 0))
	var glass_mat: ShaderMaterial = _mat(LENS_GLASS, 0.0)
	glass_mat.set_shader_parameter("spec_strength", 0.9)
	_mesh(lens, ProcMesh.cyl(0.16, 0.16, 0.05, 24), glass_mat, Vector3(0, 0, 0.0), Vector3(90, 0, 0))
	_iris_group = Node3D.new()
	_iris_group.position = Vector3(0, 0, -0.03)
	lens.add_child(_iris_group)
	_iris_mat = _mat(IRIS, 0.0)
	_iris_mat.set_shader_parameter("emission_color", IRIS)
	_iris_mat.set_shader_parameter("emission_strength", 0.9)
	_mesh(_iris_group, ProcMesh.cyl(0.1, 0.1, 0.01, 24), _iris_mat, Vector3.ZERO, Vector3(90, 0, 0))
	_pupil = _mesh(_iris_group, ProcMesh.cyl(0.05, 0.05, 0.012, 20), _mat(Color(0.03, 0.04, 0.08), 0.0), Vector3(0, 0, -0.004), Vector3(90, 0, 0))
	var hl := StandardMaterial3D.new()
	hl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hl.albedo_color = Color(1, 1, 1)
	_mesh(_iris_group, ProcMesh.sphere(0.028, 8, 4), hl, Vector3(-0.05, 0.05, -0.012))
	_mesh(_iris_group, ProcMesh.sphere(0.013, 6, 3), hl, Vector3(0.045, -0.04, -0.012))
	# Antenna with a mushroom bulb.
	var ant := Node3D.new()
	ant.position = Vector3(0.14, 0.3, 0.1)
	ant.rotation_degrees = Vector3(-8, 0, -12)
	_head.add_child(ant)
	_mesh(ant, ProcMesh.cyl(0.014, 0.018, 0.32, 6), _mat(Color(0.5, 0.5, 0.55), 0.5), Vector3(0, 0.16, 0))
	_bulb_mat = _mat(Color(1.0, 0.45, 0.35), 0.0)
	_bulb_mat.set_shader_parameter("emission_color", Color(1.0, 0.55, 0.3))
	_bulb_mat.set_shader_parameter("emission_strength", 0.6)
	_mesh(ant, ProcMesh.hemisphere(0.08, 12, 5), _bulb_mat, Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1, 1.1, 1))
	_mesh(ant, ProcMesh.cyl(0.08, 0.08, 0.01, 12), _mat(Color(1.0, 0.95, 0.85), 0.0), Vector3(0, 0.32, 0))
	for k: int in 3:
		var a: float = TAU * k / 3.0 + 0.4
		_mesh(ant, ProcMesh.sphere(0.018, 6, 3), _mat(Color(1, 1, 0.95), 0.0), Vector3(cos(a) * 0.05, 0.36, sin(a) * 0.05))

	# Arms: stubby pistons with scoop paddles (mismatched colors).
	_arm_l = _build_arm(-1.0, HAND_L)
	_arm_r = _build_arm(1.0, HAND_R)


func _build_arm(side: float, hand_color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.43 * side, 0.7, -0.08)
	_squash.add_child(pivot)
	var joint_mat: ShaderMaterial = _mat(Color(0.5, 0.5, 0.55), 0.5, side)
	_mesh(pivot, ProcMesh.sphere(0.075, 10, 5), joint_mat, Vector3.ZERO)
	_mesh(pivot, ProcMesh.cyl(0.045, 0.05, 0.28, 8), joint_mat, Vector3(0.03 * side, -0.06, -0.13), Vector3(-65, 0, 0))
	_mesh(pivot, ProcMesh.cyl(0.032, 0.032, 0.16, 8), _mat(Color(0.75, 0.75, 0.8), 0.2, side * 2.0), Vector3(0.03 * side, -0.14, -0.28), Vector3(-65, 0, 0))
	_mesh(pivot, ProcMesh.rounded_box(Vector3(0.2, 0.06, 0.18), 0.03, 2), _mat(hand_color, 0.35, 3.0 + side), Vector3(0.03 * side, -0.2, -0.38), Vector3(-15, 0, 0))
	return pivot


func _process(delta: float) -> void:
	_time += delta
	# Scoop arms: alternating sweeps while scooping, rest pose otherwise.
	_scoop_amount = move_toward(_scoop_amount, 1.0 if _scoop_t > 0.0 else 0.0, delta * 6.0)
	var s: float = _time * 13.0
	_arm_l.rotation.x = lerpf(0.0, sin(s) * 0.7 - 0.25, _scoop_amount)
	_arm_r.rotation.x = lerpf(0.0, sin(s + PI) * 0.7 - 0.25, _scoop_amount)
	_arm_l.rotation.y = lerpf(0.0, -0.35 + sin(s) * 0.25, _scoop_amount)
	_arm_r.rotation.y = lerpf(0.0, 0.35 - sin(s) * 0.25, _scoop_amount)
	_scoop_t = maxf(0.0, _scoop_t - delta)
	# Squash spring.
	var k: float = 220.0
	var c: float = 14.0
	_squash_v += (-k * _squash_x - c * _squash_v) * delta
	_squash_x += _squash_v * delta
	var sq: float = clampf(_squash_x, -0.4, 0.4)
	_squash.scale = Vector3(1.0 + sq * 0.5, 1.0 - sq, 1.0 + sq * 0.5)
	# Shudder (compaction).
	if _shudder > 0.0:
		_shudder -= delta
		_squash.position = Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.025
	else:
		_squash.position = Vector3.ZERO
	# Head look-at hint.
	_look_yaw = lerp_angle(_look_yaw, _look_target_yaw, delta * 4.0)
	_head.rotation.y = _look_yaw
	# Iris dilation + blinking.
	_iris_now = lerpf(_iris_now, _iris_target, delta * 5.0)
	_pupil.scale = Vector3.ONE * lerpf(0.6, 1.5, _iris_now)
	_blink_timer -= delta
	if sleeping:
		_iris_group.scale = Vector3(1, 0.08, 1)
	elif _blink_timer <= 0.0:
		_blink_timer = randf_range(2.5, 5.5)
		var tw := create_tween()
		tw.tween_property(_iris_group, "scale", Vector3(1, 0.08, 1), 0.06)
		tw.tween_property(_iris_group, "scale", Vector3.ONE, 0.09)
	elif _iris_group.scale.y < 0.1 and not sleeping:
		_iris_group.scale = Vector3.ONE
	# Antenna bulb pulse.
	var pulse: float = 0.55 + 0.25 * sin(_time * 2.2) + _flash * 2.0
	_bulb_mat.set_shader_parameter("emission_strength", pulse)
	_flash = maxf(0.0, _flash - delta * 2.0)
	for m: ShaderMaterial in _body_mats:
		m.set_shader_parameter("flash", _flash * 0.25)


## speed_ratio 0..1, local_accel x = sideways, y = forward. Drives bounce, lean and tread scroll.
func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	_tread_offset += speed * delta * 1.6
	for m: ShaderMaterial in _tread_mats:
		m.set_shader_parameter("stripe_offset", _tread_offset)
	var target := Vector2(clampf(-local_accel.y * 0.012, -0.12, 0.12), clampf(local_accel.x * 0.01, -0.1, 0.1))
	_lean_now = _lean_now.lerp(target, clampf(delta * 8.0, 0.0, 1.0))
	_lean.rotation = Vector3(_lean_now.x, 0.0, _lean_now.y)
	_lean.position.y = absf(sin(_time * 15.0)) * 0.03 * speed_ratio


func set_scooping(active: bool) -> void:
	if active:
		_scoop_t = 0.12


func set_fill(ratio: float, band: Array) -> void:
	var pivot: Node3D = _gauge.get_meta("pivot")
	pivot.scale = Vector3(1, clampf(ratio, 0.001, 1.08), 1)
	if ratio > float(band[1]) + 0.0001:
		_gauge_mat.albedo_color = Color(1.0, 0.35, 0.3)
	elif ratio >= float(band[0]):
		_gauge_mat.albedo_color = Color(1.0, 0.85, 0.25)
	else:
		_gauge_mat.albedo_color = Color(0.4, 1.0, 0.5)


func shudder(duration: float = 0.35) -> void:
	_shudder = duration


func squash(amount: float) -> void:
	_squash_v += amount * 10.0


## Turn the head toward a world position (hint system). null = look forward.
func look_toward(world_pos: Variant) -> void:
	if world_pos == null:
		_look_target_yaw = 0.0
		return
	var local: Vector3 = global_transform.affine_inverse() * (world_pos as Vector3)
	var yaw: float = atan2(-local.x, -local.z)
	_look_target_yaw = clampf(yaw, -0.9, 0.9)


func set_happy(amount: float) -> void:
	_iris_target = clampf(amount, 0.0, 1.0)


func flash() -> void:
	_flash = 1.0


func set_rust(amount: float) -> void:
	rust_amount = clampf(amount, 0.2, 1.0)
	for m: ShaderMaterial in _body_mats:
		m.set_shader_parameter("rust_amount", rust_amount)
