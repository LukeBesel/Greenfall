class_name LedgerDrone
extends Node3D
## One of the Ledger's old disposal drones: a boxy charcoal hauler with four ducted rotors, an
## amber hazard band, a red sensor eye and a cargo bin underneath. After the contract is
## rewritten it is repainted in green "delivery" lights. Movement is driven by LedgerArc with
## tweens; this node only animates itself (rotors, bob, bank) and its ground shadow.

const RED := Color(1.0, 0.18, 0.12)
const GREEN := Color(0.35, 1.0, 0.5)

var friendly: bool = false
var cargo: Node3D
var _rotors: Array[Node3D] = []
var _eye_mat: StandardMaterial3D
var _band_mat: StandardMaterial3D
var _eye: OmniLight3D
var _beam: SpotLight3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _hum: AudioStreamPlayer3D
var _flaps: Array[Node3D] = []
var _t: float = 0.0
var _last_pos: Vector3
var ground_y: Callable  # (x, z) -> float


func _ready() -> void:
	_build()
	_last_pos = global_position


func _build() -> void:
	var body_mat: ShaderMaterial = Mats.worn_paint(Color(0.3, 0.31, 0.34), 0.95, 0.25, 61.0, 0.55)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var hull := Node3D.new()
	hull.name = "Hull"
	hull.scale = Vector3.ONE * 1.3
	add_child(hull)
	hull.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.5, 0.42, 1.0), 0.12, 3), body_mat))
	hull.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.9, 0.22, 0.7), 0.08, 2), body_mat, Vector3(0, 0.27, -0.05)))
	_band_mat = Mats.lamp(Color(1.0, 0.6, 0.1), 0.35)
	# Hazard band: thin glowing strips on each face (not a plate, so it reads from above too).
	for spec: Array in [[Vector3(0, 0.0, 0.502), Vector3(1.1, 0.06, 0.01)], [Vector3(0, 0.0, -0.502), Vector3(1.1, 0.06, 0.01)], [Vector3(0.752, 0.0, 0), Vector3(0.01, 0.06, 0.6)], [Vector3(-0.752, 0.0, 0), Vector3(0.01, 0.06, 0.6)]]:
		hull.add_child(EggProps.mesh(ProcMesh.box(spec[1]), _band_mat, spec[0]))
	# Sensor eye (front, +Z) and a stencil on both flanks.
	_eye_mat = Mats.lamp(RED, 3.0)
	hull.add_child(EggProps.mesh(ProcMesh.sphere(0.09, 12, 6), _eye_mat, Vector3(0, 0.02, 0.5)))
	hull.add_child(EggProps.mesh(ProcMesh.cyl(0.13, 0.13, 0.04, 14), steel, Vector3(0, 0.02, 0.49), Vector3(90, 0, 0)))
	for s: float in [-1.0, 1.0]:
		var st := EggProps.label("LEDGER  WMS-07", 26, Color(0.95, 0.8, 0.5, 0.9), Vector3(s * 0.755, 0.06, 0), Vector3(0, s * 90.0, 0))
		hull.add_child(st)
	# Arms + ducted rotors.
	for p: Vector3 in [Vector3(0.95, 0.12, 0.7), Vector3(-0.95, 0.12, 0.7), Vector3(0.95, 0.12, -0.7), Vector3(-0.95, 0.12, -0.7)]:
		var arm_len: float = Vector2(p.x, p.z).length()
		var arm := EggProps.mesh(ProcMesh.box(Vector3(0.1, 0.07, arm_len)), steel, p * 0.5 + Vector3(0, 0.06, 0))
		arm.rotation.y = atan2(p.x, p.z)
		hull.add_child(arm)
		hull.add_child(EggProps.mesh(ProcMesh.torus(0.36, 0.42, 20, 6), body_mat, p, Vector3.ZERO, Vector3(1, 1.8, 1)))
		var rotor := Node3D.new()
		rotor.position = p + Vector3(0, 0.02, 0)
		hull.add_child(rotor)
		for k: int in 2:
			rotor.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.68, 0.015, 0.07)), steel, Vector3.ZERO, Vector3(0, k * 90.0, 4)))
		rotor.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.05, 0.06, 8), steel))
		_rotors.append(rotor)
	# Cargo bin with two bomb-bay flaps.
	var bin_mat: ShaderMaterial = Mats.worn_paint(Color(0.72, 0.55, 0.12), 0.7, 0.6, 62.0, 0.7)
	for spec: Array in [[Vector3(0, -0.35, 0.3), Vector3(0.76, 0.3, 0.03)], [Vector3(0, -0.35, -0.3), Vector3(0.76, 0.3, 0.03)], [Vector3(0.38, -0.35, 0), Vector3(0.03, 0.3, 0.63)], [Vector3(-0.38, -0.35, 0), Vector3(0.03, 0.3, 0.63)]]:
		hull.add_child(EggProps.mesh(ProcMesh.box(spec[1]), bin_mat, spec[0]))
	# Struts from hull to bin.
	for x: float in [-0.3, 0.3]:
		hull.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.04, 0.2, 0.5)), steel, Vector3(x, -0.18, 0)))
	for s: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(s * 0.38, -0.5, 0)
		hull.add_child(hinge)
		hinge.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.38, 0.025, 0.6)), bin_mat, Vector3(-s * 0.19, 0, 0)))
		_flaps.append(hinge)
	cargo = Node3D.new()
	cargo.name = "Cargo"
	cargo.position = Vector3(0, -0.38, 0)
	hull.add_child(cargo)
	_eye = OmniLight3D.new()
	_eye.light_color = RED
	_eye.light_energy = 1.6
	_eye.omni_range = 4.0
	_eye.position = Vector3(0, -0.2, 0.7)
	add_child(_eye)
	_beam = SpotLight3D.new()
	_beam.light_color = RED
	_beam.light_energy = 0.0
	_beam.spot_range = 14.0
	_beam.spot_angle = 18.0
	_beam.rotation_degrees = Vector3(-90, 0, 0)
	_beam.position = Vector3(0, -0.7, 0)
	add_child(_beam)
	# Soft round shadow on the ground (top level, follows the drone).
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.0)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_color = Color(0, 0, 0, 0.55)
	_shadow_mat.albedo_texture = _shadow_tex()
	_shadow_mat.disable_receive_shadows = true
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	var hum_stream: AudioStream = StorySfx.stream("drone_hum")
	if hum_stream:
		_hum = AudioStreamPlayer3D.new()
		_hum.stream = hum_stream
		_hum.bus = "SFX"
		_hum.unit_size = 10.0
		_hum.max_distance = 80.0
		_hum.volume_db = -4.0
		_hum.autoplay = true
		add_child(_hum)
	set_friendly(friendly)


static func _shadow_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 1))
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.45, Color(0, 0, 0, 0.7))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func set_friendly(v: bool) -> void:
	friendly = v
	if _eye_mat == null:
		return
	var c: Color = GREEN if v else RED
	_eye_mat.emission = c
	_eye_mat.albedo_color = c.darkened(0.3)
	_eye.light_color = c
	_beam.light_color = c
	_band_mat.emission = Color(0.3, 0.95, 0.5) if v else Color(1.0, 0.6, 0.1)
	_band_mat.albedo_color = (_band_mat.emission as Color).darkened(0.3)


## Red scanning beam while it picks its spot (0 = off).
func set_beam(energy: float) -> void:
	if _beam:
		var tw := create_tween()
		tw.tween_property(_beam, "light_energy", energy, 0.4)


func open_bin(open: bool) -> void:
	for i: int in _flaps.size():
		var tw := create_tween()
		tw.tween_property(_flaps[i], "rotation:z", (1.0 if i == 0 else -1.0) * (-1.6 if open else 0.0), 0.35).set_trans(Tween.TRANS_BACK)
	Audio.play("hydraulic", 1.3, -10.0)


func _process(delta: float) -> void:
	_t += delta
	for r: Node3D in _rotors:
		r.rotate_y(delta * 38.0)
	var hull: Node3D = get_node("Hull")
	# Bob, and bank into the direction of travel.
	var vel: Vector3 = (global_position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = global_position
	var local_v: Vector3 = global_transform.basis.inverse() * vel
	hull.position.y = sin(_t * 2.2) * 0.08
	hull.rotation.x = lerpf(hull.rotation.x, clampf(local_v.z * 0.04, -0.35, 0.35), minf(delta * 4.0, 1.0))
	hull.rotation.z = lerpf(hull.rotation.z, clampf(-local_v.x * 0.04, -0.35, 0.35), minf(delta * 4.0, 1.0))
	if vel.length() > 0.5:
		var want: float = atan2(vel.x, vel.z)
		rotation.y = lerp_angle(rotation.y, want, minf(delta * 2.5, 1.0))
	if _shadow:
		var gy: float = float(ground_y.call(global_position.x, global_position.z)) if ground_y.is_valid() else 0.0
		var h: float = maxf(global_position.y - gy, 0.1)
		_shadow.global_position = Vector3(global_position.x, gy + 0.04, global_position.z)
		_shadow.global_rotation = Vector3(0, rotation.y, 0)
		var s: float = clampf(1.4 - h * 0.03, 0.6, 1.4)
		_shadow.scale = Vector3(s, 1, s)
		_shadow_mat.albedo_color.a = clampf(0.75 - h * 0.025, 0.12, 0.7)
	if _eye and not friendly:
		_eye.light_energy = 1.2 + (0.8 if fmod(_t, 1.0) < 0.15 else 0.0)
