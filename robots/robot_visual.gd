class_name RobotVisual
extends Node3D
## Procedural robot models. One builder per type, four looks by tier:
##   salvage (rusty, mismatched) -> restored (repainted, tidy) -> modern (clean panels, light strips)
##   -> hover (sleek shell, no wheels, thruster rings, tractor-beam emitter).
## Faces -Z.

var type_id: String = "scoopie"
var look: String = "salvage"

var _wheels: Array[Node3D] = []
var _arm: Node3D
var _beacon_mat: StandardMaterial3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _thrusters: Array[MeshInstance3D] = []
var _body: Node3D
var _t: float = 0.0
var hover: bool = false
var emitter_point := Vector3(0, 0.5, -0.4)
var hopper_point := Vector3(0, 0.6, 0)
var fork_point := Vector3(0, 0.35, -0.7)


func build(p_type: String, p_look: String) -> void:
	type_id = p_type
	look = p_look
	hover = look == "hover"
	for c: Node in get_children():
		c.queue_free()
	_wheels.clear()
	_thrusters.clear()
	_body = Node3D.new()
	add_child(_body)
	if type_id == "haulbug":
		_build_haulbug()
	else:
		_build_scoopie()
	_build_beam()


func _paint() -> Material:
	match look:
		"salvage":
			return Mats.worn_paint([Color(0.55, 0.5, 0.2), Color(0.3, 0.4, 0.45), Color(0.6, 0.3, 0.2)][randi() % 3], 0.35, 0.8, randf() * 10.0, 0.8)
		"restored":
			return Mats.worn_paint(Color(0.95, 0.7, 0.12), 0.88, 0.3, randf() * 10.0, 0.4)
		"modern":
			return Mats.worn_paint(Color(0.92, 0.93, 0.92), 0.98, 0.05, randf() * 10.0, 0.12)
		_:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.93, 0.95, 0.97)
			m.metallic = 0.3
			m.roughness = 0.25
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
			return m


func _trim() -> Material:
	match look:
		"salvage":
			return Mats.metal("dark_steel")
		"restored":
			return Mats.worn_paint(Color(0.18, 0.18, 0.2), 0.9, 0.2, 3.0, 0.4)
		"modern":
			return Mats.worn_paint(Color(0.12, 0.42, 0.48), 1.0, 0.0, 4.0, 0.05)
		_:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.12, 0.13, 0.15)
			m.metallic = 0.8
			m.roughness = 0.3
			return m


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


func _locomotion(width: float, length: float, wheel_r: float, hover_y: float = 0.5) -> void:
	if hover:
		var thr := Mats.lamp(Color(0.35, 0.8, 1.0), 2.5)
		for x: float in [-width * 0.36, width * 0.36]:
			for z: float in [-length * 0.28, length * 0.28]:
				# Thruster pod tucked under the shell, glowing downward.
				_mi(_body, ProcMesh.cyl(0.09, 0.07, 0.12, 14), _trim(), Vector3(x, hover_y + 0.04, z))
				var ring := _mi(_body, ProcMesh.torus(0.06, 0.095, 16, 6), _trim(), Vector3(x, hover_y - 0.03, z))
				var glow := _mi(_body, ProcMesh.cyl(0.065, 0.065, 0.02, 14), thr, Vector3(x, hover_y - 0.04, z))
				_thrusters.append(glow)
				ring.name = "thruster"
		return
	var tyre: Material = Mats.rubber()
	var hub: Material = _trim()
	for x: float in [-width * 0.5, width * 0.5]:
		for z: float in [-length * 0.32, length * 0.32]:
			var w := Node3D.new()
			w.position = Vector3(x, wheel_r, z)
			_body.add_child(w)
			_mi(w, ProcMesh.cyl(wheel_r, wheel_r, 0.1, 16), tyre, Vector3.ZERO, Vector3(0, 0, 90))
			_mi(w, ProcMesh.cyl(wheel_r * 0.55, wheel_r * 0.55, 0.11, 10), hub, Vector3.ZERO, Vector3(0, 0, 90))
			_wheels.append(w)


func _beacon(pos: Vector3) -> void:
	var col: Color = Color(1.0, 0.6, 0.15) if look in ["salvage", "restored"] else Color(0.3, 0.9, 1.0)
	_beacon_mat = Mats.lamp(col, 1.5)
	_mi(_body, ProcMesh.cyl(0.012, 0.012, 0.18, 6), _trim(), pos - Vector3(0, 0.09, 0))
	_mi(_body, ProcMesh.sphere(0.035, 8, 4), _beacon_mat, pos + Vector3(0, 0.02, 0))


func _build_scoopie() -> void:
	var lift: float = 0.32 if hover else 0.0
	var paint: Material = _paint()
	var trim: Material = _trim()
	_locomotion(0.56, 0.62, 0.12, 0.2 + lift)
	# Hopper body.
	if look == "hover":
		_mi(_body, ProcMesh.capsule(0.28, 0.75), paint, Vector3(0, 0.42 + lift, 0), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.85))
		_mi(_body, ProcMesh.box(Vector3(0.5, 0.02, 0.5)), Mats.lamp(Color(0.3, 0.9, 1.0), 1.2), Vector3(0, 0.62 + lift, 0.0))
	else:
		var r: float = 0.08 if look == "salvage" else (0.1 if look == "restored" else 0.14)
		_mi(_body, ProcMesh.rounded_box(Vector3(0.56, 0.36, 0.62), r, 3), paint, Vector3(0, 0.36, 0))
		_mi(_body, ProcMesh.rounded_box(Vector3(0.5, 0.06, 0.56), 0.03, 2), trim, Vector3(0, 0.56, 0))
		if look == "modern":
			_mi(_body, ProcMesh.box(Vector3(0.58, 0.025, 0.02)), Mats.lamp(Color(0.3, 0.9, 1.0), 1.5), Vector3(0, 0.42, -0.315))
		if look == "salvage":
			_mi(_body, ProcMesh.box(Vector3(0.22, 0.16, 0.02)), Mats.worn_paint(Color(0.7, 0.3, 0.2), 0.4, 0.8, 9.0), Vector3(0.12, 0.38, 0.315), Vector3(0, 0, 8))
	hopper_point = Vector3(0, 0.62 + lift, 0)
	# Arm with scoop (or beam emitter for hover).
	_arm = Node3D.new()
	_arm.position = Vector3(0, 0.5 + lift, -0.28)
	_body.add_child(_arm)
	if hover:
		_mi(_arm, ProcMesh.cyl(0.05, 0.08, 0.14, 14), trim, Vector3(0, -0.08, -0.08), Vector3(90, 0, 0))
		_mi(_arm, ProcMesh.cyl(0.045, 0.045, 0.01, 14), Mats.lamp(Color(0.4, 1.0, 0.8), 3.0), Vector3(0, -0.08, -0.155), Vector3(90, 0, 0))
		emitter_point = _arm.position + Vector3(0, -0.08, -0.16)
	else:
		_mi(_arm, ProcMesh.cyl(0.03, 0.03, 0.34, 8), trim, Vector3(0, -0.05, -0.15), Vector3(-60, 0, 0))
		_mi(_arm, ProcMesh.rounded_box(Vector3(0.3, 0.05, 0.18), 0.02, 2), paint, Vector3(0, -0.2, -0.28), Vector3(-10, 0, 0))
		emitter_point = _arm.position + Vector3(0, -0.2, -0.3)
	_beacon(Vector3(0.18, 0.78 + lift, 0.2))
	# A small sensor eye.
	_mi(_body, ProcMesh.cyl(0.05, 0.05, 0.05, 14), trim, Vector3(-0.16, 0.6 + lift, -0.3), Vector3(90, 0, 0))
	_mi(_body, ProcMesh.cyl(0.032, 0.032, 0.01, 14), Mats.lamp(Color(0.5, 1.0, 0.9) if look != "salvage" else Color(1.0, 0.6, 0.3), 1.2), Vector3(-0.16, 0.6 + lift, -0.328), Vector3(90, 0, 0))


func _build_haulbug() -> void:
	var lift: float = 0.3 if hover else 0.0
	var paint: Material = _paint()
	var trim: Material = _trim()
	_locomotion(0.7, 0.9, 0.11, 0.2 + lift)
	if hover:
		_mi(_body, ProcMesh.rounded_box(Vector3(0.7, 0.18, 0.9), 0.08, 3), paint, Vector3(0, 0.28 + lift, 0))
	else:
		_mi(_body, ProcMesh.rounded_box(Vector3(0.7, 0.22, 0.9), 0.05 if look == "salvage" else 0.08, 3), paint, Vector3(0, 0.28, 0))
	_mi(_body, ProcMesh.rounded_box(Vector3(0.6, 0.36, 0.22), 0.05, 2), paint, Vector3(0, 0.55 + lift, 0.3))
	# Mast and forks.
	for x: float in [-0.22, 0.22]:
		_mi(_body, ProcMesh.box(Vector3(0.05, 0.7, 0.05)), trim, Vector3(x, 0.6 + lift, -0.42))
		_mi(_body, ProcMesh.box(Vector3(0.07, 0.03, 0.55)), trim, Vector3(x, 0.24 + lift, -0.68))
	fork_point = Vector3(0, 0.28 + lift, -0.7)
	_beacon(Vector3(0, 0.82 + lift, 0.3))
	emitter_point = Vector3(0, 0.5 + lift, -0.5)


func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.28
	cone.height = 1.0
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(0.35, 1.0, 0.8, 0.25)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


## Points the tractor beam from the emitter to a world position (hover tier). null hides it.
func beam_to(world_pos: Variant) -> void:
	if world_pos == null or not hover:
		_beam.visible = false
		return
	var a: Vector3 = to_global(emitter_point)
	var b: Vector3 = world_pos
	var len: float = maxf(a.distance_to(b), 0.05)
	_beam.visible = true
	_beam.global_position = (a + b) * 0.5
	var up: Vector3 = (a - b).normalized()
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_beam.global_transform.basis = Basis(side, up, side.cross(up)).scaled(Vector3(1, len, 1))


func animate(speed: float, working: bool, delta: float) -> void:
	_t += delta
	for w: Node3D in _wheels:
		w.rotation.x -= speed * delta / 0.12
	if hover and _body:
		_body.position.y = sin(_t * 2.2) * 0.03
		_body.rotation.z = sin(_t * 1.3) * 0.02
		for th: MeshInstance3D in _thrusters:
			(th.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0 + sin(_t * 18.0) * 0.4 + speed * 0.4
	if _arm and not hover:
		_arm.rotation.x = (sin(_t * 9.0) * 0.4 - 0.2) if working else lerpf(_arm.rotation.x, 0.0, delta * 4.0)
	if _beam_mat and _beam and _beam.visible:
		_beam_mat.albedo_color.a = 0.18 + 0.08 * sin(_t * 25.0)
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 1.0 + (1.5 if fmod(_t, 1.4) < 0.15 else 0.0)
