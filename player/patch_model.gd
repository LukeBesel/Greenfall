class_name PatchModel
extends Node3D
## Patch (unit P-47CH), concept v2 "Beetle".
## A small, round, dome-backed sanitation unit painted a sun-faded powder blue, worn through to rust at
## every edge, rolling on four stubby wheel-legs with little shell fenders. The dome back is the
## compaction lid: it is hinged at the rear, cracks open while Patch feeds and is pulled down hard by
## two side rams when he presses. A round head pod on a short bellows neck carries one big camera lens
## with a rust-stained brass bezel and an 8-blade aperture iris, a tilting brow plate for mood and a
## whip antenna with a coral lamp. Two small clamp arms tucked under the chin pick single bits of
## litter and feed them into the wide intake mouth; strapped bales drop out of the rear tailgate hatch.
## Faces -Z, base at y = 0. Real-world scale: ~0.9 m to the antenna lamp, ~0.72 m long, ~0.66 m wide.

const BLUE := Color(0.5, 0.76, 0.95)         # powder / sky blue
const BLUE_DEEP := Color(0.42, 0.64, 0.82)    # shaded blue for fenders and trim
const CREAM := Color(0.88, 0.83, 0.70)        # face plate, belly, arms
const CORAL := Color(0.88, 0.36, 0.25)        # accents: hubs, knobs, fingertips, lamp
const MUSTARD := Color(0.86, 0.64, 0.18)
const BLACK := Color(0.05, 0.05, 0.05)

const WHEEL_R: float = 0.075
const TUB_Y0: float = 0.19
const TUB_Y1: float = 0.43
const TUB_HZ: float = 0.33
const TUB_FZ: float = -0.36   # front of the tub (the "chin" ledge carrying the neck)
const L1: float = 0.13
const L2: float = 0.12

## Interface: local anchor points used by the controller.
var chest_point := Vector3(0, 0.3, -0.39)
var back_hatch_point := Vector3(0, 0.3, 0.38)
var vent_points: Array[Vector3] = [Vector3(-0.1, 0.6, 0.18), Vector3(0.1, 0.6, 0.18), Vector3(-0.29, 0.34, 0.1)]
var stack_point := Vector3(0.15, 0.68, 0.22)
var lens_point := Vector3(0, 0.645, -0.46)
var sleeping: bool = false
var _iris_now: float = 0.55

var _rig: Node3D
var _pan: Node3D
var _tilt: Node3D
var _brow: Node3D
var _lid: Node3D
var _hatch: Node3D
var _blades: Array[Node3D] = []
var _sensor_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _needle: Node3D
var _gauge_lamp_mat: StandardMaterial3D
var _wheels: Array[Node3D] = []
var _swivels: Array[Node3D] = []
var _arms: Array[Dictionary] = []
var _rams: Array[Array] = []
var _paint_mats: Array[ShaderMaterial] = []

var _time: float = 0.0
var _rust: float = 0.55
var _wheel_angle: float = 0.0
var _steer: float = 0.0
var _lean := Vector2.ZERO
var _dip: float = 0.0
var _dip_target: float = 0.0
var _scoop_hold: float = 0.0
var _scoop_amount: float = 0.0
var _scoop_phase: float = 0.0
var _shudder_t: float = 0.0
var _look_yaw: float = 0.0
var _look_target: float = 0.0
var _tilt_now: float = 0.0
var _roll_now: float = 0.0
var _brow_now: float = 0.0
var _iris_target: float = 0.55
var _flash_t: float = 0.0
var _fill_angle: float = 0.0
var _fill_target: float = 0.0
var _press_now: float = 0.0
var _hatch_now: float = 0.0
var _lid_now: float = 0.0
var _debug_phase: float = -1.0


func _ready() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_build_legs()
	_build_shell()
	_build_lid()
	_build_mouth()
	_build_gauge()
	_build_hatch()
	_build_head()
	for s: float in [-1.0, 1.0]:
		_build_arm(s)
	# Debug poses for stills: BEETLE_POSE="scoop:0.3,press:1,hatch:1,happy:1,sleep:1"
	var pose: String = OS.get_environment("BEETLE_POSE")
	if pose != "":
		for kv: String in pose.split(","):
			var p: PackedStringArray = kv.split(":")
			if p.size() == 2:
				match p[0]:
					"scoop": _debug_phase = float(p[1])
					"press": _press_now = float(p[1])
					"hatch": _hatch_now = float(p[1])
					"happy": _iris_target = float(p[1]); _iris_now = _iris_target
					"sleep": sleeping = float(p[1]) > 0.5
	_update_arms()
	_update_rams()


# ---------------------------------------------------------------- helpers

func _paint(color: Color, coverage: float, rust: float, seed: float, grime: float = 0.5, floor_y: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(color, coverage, rust, seed, grime)
	m.set_shader_parameter("grime_floor", floor_y)
	m.set_shader_parameter("grime_height", 0.3)
	m.set_shader_parameter("fade", 0.15)
	m.set_shader_parameter("dust", 0.08)
	m.set_meta("cov", coverage)
	_paint_mats.append(m)
	return m


func _bake(parent: Node3D, mesh: Mesh, mat: Material, xf: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.merge([ProcMesh.part(mesh, xf)])
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _bake_many(parent: Node3D, parts: Array, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.merge(parts)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _node(parent: Node3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


func _x(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return ProcMesh.xf(pos, rot, scl)


func _between(a: Vector3, b: Vector3) -> Transform3D:
	var d: Vector3 = b - a
	var q := Quaternion(Vector3.UP, d.normalized())
	return Transform3D(Basis(q), (a + b) * 0.5)


func _hose(parent: Node3D, p0: Vector3, p1: Vector3, p2: Vector3, r: float = 0.008) -> void:
	var parts: Array = []
	var n: int = 8
	var prev: Vector3 = p0
	for i: int in range(1, n + 1):
		var t: float = float(i) / n
		var p: Vector3 = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		parts.append(ProcMesh.part(ProcMesh.cyl(r, r, (p - prev).length() * 1.12, 8), _between(prev, p)))
		prev = p
	_bake_many(parent, parts, Mats.rubber())


func _bolts(parent: Node3D, points: Array, normal: Vector3, size: float = 0.008) -> void:
	var parts: Array = []
	var q := Quaternion(Vector3.UP, normal.normalized())
	for p: Vector3 in points:
		parts.append(ProcMesh.part(ProcMesh.cyl(size, size * 1.1, size * 0.9, 8), Transform3D(Basis(q), p)))
	_bake_many(parent, parts, Mats.metal("dark_steel"))


func _stencil(parent: Node3D, text: String, size_px: int, pos: Vector3, rot_deg: Vector3, color: Color = Color(0.93, 0.9, 0.8, 0.6)) -> Label3D:
	var l: Label3D = Mats.stencil(text, size_px, color)
	l.position = pos
	l.rotation_degrees = rot_deg
	l.font = _stencil_font()
	parent.add_child(l)
	return l


var _font: Font
func _stencil_font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Monospace"])
		f.font_weight = 700
		_font = f
	return _font


func _dark() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.02, 0.02)
	m.roughness = 1.0
	return m


# ---------------------------------------------------------------- build

func _build_legs() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var fender_mat: ShaderMaterial = _paint(BLUE, 0.8, 0.6, 3.3, 0.5, -0.25)
	var hub_mat: ShaderMaterial = _paint(CORAL, 0.7, 0.6, 4.1, 0.6)
	for zs: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			var hub_pos := Vector3(0.265 * s, WHEEL_R, 0.215 * zs)
			# Leg: a stubby strut out of the belly, a knuckle and a little shell fender over the wheel.
			var leg: Array = []
			leg.append(ProcMesh.part(ProcMesh.cyl(0.024, 0.028, 0.16, 10), _between(Vector3(0.17 * s, 0.25, 0.215 * zs), Vector3(0.235 * s, 0.11, 0.215 * zs))))
			leg.append(ProcMesh.part(ProcMesh.sphere(0.034, 10, 5), _x(Vector3(0.235 * s, 0.11, 0.215 * zs))))
			_bake_many(_rig, leg, steel)
			# Rubber gaiter on the strut.
			var gaiter: Array = []
			for k: int in 3:
				var p: Vector3 = Vector3(0.17 * s, 0.25, 0.215 * zs).lerp(Vector3(0.235 * s, 0.11, 0.215 * zs), 0.3 + k * 0.17)
				gaiter.append(ProcMesh.part(ProcMesh.torus(0.018, 0.036, 12, 6), Transform3D(Basis(Quaternion(Vector3.UP, Vector3(0.065 * s, -0.14, 0).normalized())), p)))
			_bake_many(_rig, gaiter, Mats.rubber(Color(0.07, 0.07, 0.07)))
			var swivel: Node3D = _node(self, hub_pos)
			if zs < 0.0:
				_swivels.append(swivel)
			# Fender: a half shell over the top of the wheel, like a little beetle foot.
			_bake(swivel, ProcMesh.hemisphere(0.1, 18, 6), fender_mat, _x(Vector3(0.005 * s, 0.0, 0), Vector3.ZERO, Vector3(0.62, 1.0, 1.05)))
			var lip: TorusMesh = ProcMesh.torus(0.095, 0.105, 24, 6)
			_bake(swivel, lip, steel, _x(Vector3(0.005 * s, 0.0, 0), Vector3.ZERO, Vector3(0.62, 1.0, 1.05)))
			var spin: Node3D = _node(swivel, Vector3(0.012 * s, 0, 0))
			_bake(spin, ProcMesh.cyl(WHEEL_R, WHEEL_R, 0.055, 22), Mats.rubber(), _x(Vector3.ZERO, Vector3(0, 0, 90)))
			var tread: Array = []
			for k: int in 14:
				var a: float = TAU * k / 14.0
				tread.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.012, 0.016)), _x(Vector3(0, cos(a) * WHEEL_R, sin(a) * WHEEL_R), Vector3(rad_to_deg(-a), 0, 0))))
			_bake_many(spin, tread, Mats.rubber(Color(0.05, 0.05, 0.05)))
			_bake(spin, ProcMesh.cyl(0.045, 0.05, 0.02, 16), hub_mat, _x(Vector3(0.03 * s, 0, 0), Vector3(0, 0, 90)))
			_bake(spin, ProcMesh.cyl(0.016, 0.016, 0.03, 8), Mats.metal("steel"), _x(Vector3(0.04 * s, 0, 0), Vector3(0, 0, 90)))
			var nuts: Array = []
			for k: int in 4:
				var a: float = TAU * k / 4.0 + 0.4
				nuts.append(Vector3(0.042 * s, cos(a) * 0.03, sin(a) * 0.03))
			_bolts(spin, nuts, Vector3(s, 0, 0), 0.006)
			_wheels.append(spin)


func _build_shell() -> void:
	var c_y: float = (TUB_Y0 + TUB_Y1) * 0.5
	var tub_mat: ShaderMaterial = _paint(BLUE, 0.84, 0.6, 1.7, 0.45, 0.05)
	var tub_len: float = TUB_HZ - TUB_FZ
	var tub_cz: float = (TUB_HZ + TUB_FZ) * 0.5
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.54, TUB_Y1 - TUB_Y0, tub_len), 0.08, 5), tub_mat, _x(Vector3(0, c_y, tub_cz)))
	# Cream belly pan, heavily grimed.
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.5, 0.05, tub_len - 0.06), 0.02, 2), _paint(CREAM.darkened(0.15), 0.55, 0.8, 2.2, 1.0), _x(Vector3(0, TUB_Y0 + 0.01, tub_cz)))
	# Cream rub strip around the waist where lid meets tub, with a coral pinstripe under it.
	# Bands are squashed copies of the tub so their plan-view corners follow its rounding.
	var band: ArrayMesh = ProcMesh.rounded_box(Vector3(0.556, 0.24, tub_len + 0.016), 0.088, 5)
	_bake(_rig, band, _paint(CREAM, 0.75, 0.65, 2.9, 0.3), _x(Vector3(0, 0.338, tub_cz), Vector3.ZERO, Vector3(1, 0.024 / 0.24, 1)))
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.548, 0.24, tub_len + 0.008), 0.084, 5), _paint(CORAL, 0.75, 0.6, 3.1, 0.3), _x(Vector3(0, 0.312, tub_cz), Vector3.ZERO, Vector3(1, 0.012 / 0.24, 1)))
	# Side bolt rows.
	for s: float in [-1.0, 1.0]:
		var pts: Array = []
		for k: int in 6:
			pts.append(Vector3(0.271 * s, 0.395, -0.22 + k * 0.088))
		_bolts(_rig, pts, Vector3(s, 0, 0), 0.007)
	# Rust streaks: darker vertical stains under the bolts on the left side (a patch-welded plate).
	var plate: ShaderMaterial = _paint(BLUE.darkened(0.12), 0.45, 0.9, 5.5, 0.8)
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.012, 0.1, 0.16), 0.004, 1), plate, _x(Vector3(-0.274, 0.28, 0.17)))
	_bolts(_rig, [Vector3(-0.281, 0.32, 0.105), Vector3(-0.281, 0.32, 0.235), Vector3(-0.281, 0.24, 0.105), Vector3(-0.281, 0.24, 0.235)], Vector3(-1, 0, 0), 0.006)
	# Louvred side vent (left, front).
	var vent: Node3D = _node(_rig, Vector3(-0.272, 0.28, -0.18), Vector3(0, -90, 0))
	var lv: Array = []
	for k: int in 4:
		lv.append(ProcMesh.part(ProcMesh.box(Vector3(0.12, 0.01, 0.02)), _x(Vector3(0, -0.03 + k * 0.02, -0.004), Vector3(35, 0, 0))))
	_bake_many(vent, lv, Mats.metal("dark_steel"))
	_bake(vent, ProcMesh.box(Vector3(0.12, 0.08, 0.004)), _dark(), _x(Vector3(0, 0, 0.003)))
	# Faded serials on both flanks.
	_stencil(_rig, "P-47CH", 64, Vector3(0.277, 0.29, 0.1), Vector3(0, 90, 0))
	_stencil(_rig, "P-47CH", 64, Vector3(-0.277, 0.29, -0.0), Vector3(0, -90, 0))
	_stencil(_rig, "MUNICIPAL SANITATION", 18, Vector3(0.277, 0.25, 0.1), Vector3(0, 90, 0), Color(0.93, 0.9, 0.8, 0.4))


func _build_lid() -> void:
	# Dome back = compaction lid, hinged at the rear edge of the tub.
	_lid = _node(_rig, Vector3(0, TUB_Y1, 0.3))
	var dome_c := Vector3(0, -0.005, -0.27)
	var dome_mat: ShaderMaterial = _paint(BLUE.lightened(0.05), 0.85, 0.6, 7.7, 0.2, -0.3)
	var dscale := Vector3(0.9, 0.68, 1.0)
	_bake(_lid, ProcMesh.hemisphere(0.3, 40, 12), dome_mat, _x(dome_c, Vector3.ZERO, dscale))
	# Lid rim.
	_bake(_lid, ProcMesh.torus(0.29, 0.31, 48, 6), _paint(CREAM.darkened(0.05), 0.6, 0.7, 8.1, 0.3, -0.2), _x(dome_c + Vector3(0, 0.005, 0), Vector3.ZERO, Vector3(0.9, 1.0, 1.0)))
	# Beetle wing-case split: a raised seam over the top, front to back, plus two shallow ribs.
	var seam: Array = []
	for k: int in 18:
		var a0: float = PI * k / 18.0
		var a1: float = PI * (k + 1) / 18.0
		var p0 := dome_c + Vector3(0, sin(a0) * 0.302 * dscale.y, cos(a0) * 0.302 * dscale.z)
		var p1 := dome_c + Vector3(0, sin(a1) * 0.302 * dscale.y, cos(a1) * 0.302 * dscale.z)
		seam.append(ProcMesh.part(ProcMesh.cyl(0.008, 0.008, p0.distance_to(p1) * 1.1, 6), _between(p0, p1)))
	_bake_many(_lid, seam, _paint(CREAM, 0.65, 0.7, 8.6, 0.2, -0.2))
	# Rivets along the seam.
	var riv: Array = []
	for k: int in range(2, 17, 2):
		var a: float = PI * k / 18.0
		for xs: float in [-1.0, 1.0]:
			var dir := Vector3(0.03 * xs / 0.3, sin(a), cos(a)).normalized()
			var p := dome_c + Vector3(dir.x * 0.3 * dscale.x, dir.y * 0.302 * dscale.y, dir.z * 0.302 * dscale.z)
			riv.append(ProcMesh.part(ProcMesh.sphere(0.0045, 6, 3), _x(p)))
	_bake_many(_lid, riv, Mats.metal("steel"))
	# Vent grille near the back of the dome (exhaust heat from the compactor motor).
	for xs: float in [-1.0, 1.0]:
		var g: Node3D = _node(_lid, dome_c + Vector3(0.1 * xs, 0.17, 0.12), Vector3(-38, 0, 0))
		_bake(g, ProcMesh.rounded_box(Vector3(0.09, 0.016, 0.08), 0.006, 2), Mats.metal("dark_steel"), _x(Vector3.ZERO))
		var sl: Array = []
		for k: int in 4:
			sl.append(ProcMesh.part(ProcMesh.box(Vector3(0.075, 0.006, 0.008)), _x(Vector3(0, 0.009, -0.027 + k * 0.018))))
		_bake_many(g, sl, _dark())
	# Little stack pipe at the rear right.
	_bake(_lid, ProcMesh.cyl(0.018, 0.022, 0.1, 10), Mats.metal("dark_steel"), _x(Vector3(0.15, 0.17, -0.08), Vector3(-15, 0, 0)))
	_bake(_lid, ProcMesh.torus(0.015, 0.024, 12, 6), Mats.metal("steel"), _x(Vector3(0.15, 0.22, -0.068), Vector3(-15, 0, 0)))
	# Hinge knuckles at the back.
	var hk: Array = []
	for xs: float in [-0.14, 0.14]:
		hk.append(ProcMesh.part(ProcMesh.cyl(0.02, 0.02, 0.07, 10), _x(Vector3(xs, 0.0, 0.01), Vector3(0, 0, 90))))
	_bake_many(_lid, hk, Mats.metal("dark_steel"))
	_bake(_rig, ProcMesh.cyl(0.009, 0.009, 0.36, 8), Mats.metal("steel"), _x(Vector3(0, TUB_Y1, 0.31), Vector3(0, 0, 90)))
	# Compaction rams: a short cylinder on each flank pulls the lid down.
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.box(Vector3(0.025, 0.04, 0.04)), Mats.metal("dark_steel"), _x(Vector3(0.28 * s, 0.31, -0.06)))
		var a: Node3D = _node(_rig, Vector3(0.29 * s, 0.31, -0.06))
		var lug_pos := Vector3(0.275 * s, 0.03, -0.26)
		_bake(_lid, ProcMesh.box(Vector3(0.03, 0.035, 0.05)), Mats.metal("dark_steel"), _x(lug_pos + Vector3(-0.012 * s, 0, 0)))
		var b: Node3D = _node(_lid, lug_pos + Vector3(0.012 * s, 0, 0))
		_add_ram(a, b, 0.016, 0.1, _paint(CREAM, 0.65, 0.7, 9.0 + s, 0.3))


func _build_mouth() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var z: float = TUB_FZ
	# Intake mouth: a wide pill-shaped slot (a little grin under the eye) with a cream surround.
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.36, 0.13, 0.13), 0.064, 5), _paint(CREAM, 0.75, 0.7, 12.0, 0.4), _x(Vector3(0, 0.3, z + 0.006), Vector3.ZERO, Vector3(1, 1, 0.25)))
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.31, 0.088, 0.088), 0.043, 5), _dark(), _x(Vector3(0, 0.3, z - 0.004), Vector3.ZERO, Vector3(1, 1, 0.25)))
	var flaps: Array = []
	for k: int in 6:
		var x: float = -0.142 + k * 0.057
		flaps.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.06, 0.006)), _x(Vector3(x * 0.88, 0.308, z - 0.012), Vector3(randf_range(-4, 4), 0, 0))))
	_bake_many(_rig, flaps, Mats.rubber(Color(0.08, 0.075, 0.07)))
	# Scoop lip (chin): a little sloped mustard plate with worn stripes, the "lower jaw".
	var lip: Array = []
	lip.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.38, 0.016, 0.1), 0.007, 2), _x(Vector3(0, 0.215, z - 0.04), Vector3(14, 0, 0))))
	for s: float in [-1.0, 1.0]:
		lip.append(ProcMesh.part(ProcMesh.box(Vector3(0.012, 0.05, 0.08)), _x(Vector3(0.19 * s, 0.225, z - 0.035))))
	_bake_many(_rig, lip, _paint(MUSTARD, 0.62, 0.7, 13.0, 0.7))
	var stripes: Array = []
	for k: int in 5:
		stripes.append(ProcMesh.part(ProcMesh.box(Vector3(0.025, 0.004, 0.09)), _x(Vector3(-0.14 + k * 0.07, 0.224, z - 0.04), Vector3(14, 35, 0))))
	_bake_many(_rig, stripes, _paint(BLACK, 0.7, 0.5, 13.5, 0.6))
	_bake(_rig, ProcMesh.box(Vector3(0.38, 0.02, 0.025)), steel, _x(Vector3(0, 0.2, z - 0.085)))


func _build_gauge() -> void:
	# Round fill dial on the right flank, toward the front.
	var g: Node3D = _node(_rig, Vector3(0.272, 0.29, -0.2), Vector3(0, -90, 0))
	_bake(g, ProcMesh.cyl(0.046, 0.05, 0.02, 24), _paint(CREAM, 0.65, 0.7, 14.0, 0.3), _x(Vector3(0, 0, -0.005), Vector3(90, 0, 0)))
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.85, 0.83, 0.75)
	face.roughness = 0.7
	_bake(g, ProcMesh.cyl(0.038, 0.038, 0.004, 24), face, _x(Vector3(0, 0, -0.016), Vector3(90, 0, 0)))
	var ticks: Array = []
	for k: int in 7:
		var ta: float = deg_to_rad(-120.0 + k * 40.0)
		ticks.append(ProcMesh.part(ProcMesh.box(Vector3(0.003, 0.009, 0.002)), Transform3D(Basis(Vector3(0, 0, -1), ta), Vector3(sin(ta) * 0.03, cos(ta) * 0.03, -0.019))))
	var tick_mat := StandardMaterial3D.new()
	tick_mat.albedo_color = Color(0.08, 0.08, 0.08)
	_bake_many(g, ticks, tick_mat)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.15, 0.1)
	var rz: Array = []
	for k: int in 3:
		var ta: float = deg_to_rad(95.0 + k * 10.0)
		rz.append(ProcMesh.part(ProcMesh.box(Vector3(0.01, 0.005, 0.002)), Transform3D(Basis(Vector3(0, 0, -1), ta + PI * 0.5), Vector3(sin(ta) * 0.033, cos(ta) * 0.033, -0.019))))
	_bake_many(g, rz, red)
	_needle = _node(g, Vector3(0, 0, -0.021))
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.75, 0.15, 0.1)
	_bake(_needle, ProcMesh.box(Vector3(0.003, 0.032, 0.002)), nm, _x(Vector3(0, 0.013, 0)))
	_bake(_needle, ProcMesh.cyl(0.005, 0.005, 0.005, 8), Mats.metal("brass"), _x(Vector3.ZERO, Vector3(90, 0, 0)))
	_bake(g, ProcMesh.cyl(0.04, 0.04, 0.003, 24), Mats.glass(Color(0.6, 0.65, 0.65, 0.18), 0.1), _x(Vector3(0, 0, -0.024), Vector3(90, 0, 0)))
	_gauge_lamp_mat = Mats.lamp(Color(0.45, 0.8, 0.35), 0.6)
	_bake(g, ProcMesh.hemisphere(0.012, 12, 4), _gauge_lamp_mat, _x(Vector3(0.07, -0.015, -0.006), Vector3(-90, 0, 0)))
	_bake(g, ProcMesh.cyl(0.017, 0.017, 0.012, 12), Mats.metal("dark_steel"), _x(Vector3(0.07, -0.015, 0.0), Vector3(90, 0, 0)))


func _build_hatch() -> void:
	var z: float = TUB_HZ
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.3, 0.14, 0.02), 0.02, 2), _dark(), _x(Vector3(0, 0.31, z - 0.005)))
	# Tailgate hinged at the bottom; drops down and out to let the bale roll off.
	_hatch = _node(_rig, Vector3(0, 0.235, z + 0.012))
	var door_mat: ShaderMaterial = _paint(CREAM, 0.62, 0.75, 42.0, 0.6, -0.1)
	_bake(_hatch, ProcMesh.rounded_box(Vector3(0.33, 0.16, 0.022), 0.02, 3), door_mat, _x(Vector3(0, 0.078, 0)))
	var rib: Array = []
	for x: float in [-0.1, 0.1]:
		rib.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.022, 0.13, 0.014), 0.005, 1), _x(Vector3(x, 0.078, 0.016))))
	_bake_many(_hatch, rib, door_mat)
	_bake(_hatch, ProcMesh.rounded_box(Vector3(0.08, 0.022, 0.03), 0.008, 2), _paint(CORAL, 0.7, 0.6, 43.0, 0.4), _x(Vector3(0, 0.13, 0.02)))
	_stencil(_hatch, "P-47CH", 30, Vector3(0, 0.07, 0.0115), Vector3.ZERO, Color(0.15, 0.2, 0.25, 0.65))
	_stencil(_hatch, "BALE OUT", 18, Vector3(0, 0.035, 0.0115), Vector3.ZERO, Color(0.15, 0.2, 0.25, 0.5))
	_bake(_rig, ProcMesh.cyl(0.011, 0.011, 0.34, 8), Mats.metal("steel"), _x(Vector3(0, 0.235, z + 0.012), Vector3(0, 0, 90)))
	# Reflector lamps either side of the tailgate.
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.cyl(0.02, 0.02, 0.012, 14), Mats.lamp(Color(0.9, 0.2, 0.1), 0.25), _x(Vector3(0.21 * s, 0.33, z + 0.002), Vector3(90, 0, 0)))
		_bake(_rig, ProcMesh.torus(0.019, 0.026, 14, 5), Mats.metal("dark_steel"), _x(Vector3(0.21 * s, 0.33, z + 0.004), Vector3(90, 0, 0)))


func _build_head() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var base := Vector3(0, TUB_Y1, -0.27)
	# Neck: collar, rubber bellows, swivel plate.
	_bake(_rig, ProcMesh.cyl(0.065, 0.075, 0.035, 18), _paint(CREAM, 0.65, 0.7, 20.0, 0.3), _x(base + Vector3(0, 0.005, 0)))
	var bel: Array = []
	for k: int in 4:
		bel.append(ProcMesh.part(ProcMesh.torus(0.022, 0.048, 16, 6), _x(base + Vector3(0, 0.03 + k * 0.018, 0))))
	_bake_many(_rig, bel, Mats.rubber(Color(0.08, 0.08, 0.08)))
	_pan = _node(_rig, base + Vector3(0, 0.095, 0))
	_bake(_pan, ProcMesh.cyl(0.05, 0.05, 0.02, 16), steel, _x(Vector3.ZERO))
	# Yoke arms up to the head's side pivots.
	var yk: Array = []
	for s: float in [-1.0, 1.0]:
		yk.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.016, 0.1, 0.05), 0.006, 1), _x(Vector3(0.17 * s, 0.07, 0))))
	yk.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.356, 0.016, 0.05), 0.006, 1), _x(Vector3(0, 0.015, 0))))
	_bake_many(_pan, yk, _paint(BLUE_DEEP, 0.6, 0.7, 21.0, 0.3, -1.0))
	_tilt = _node(_pan, Vector3(0, 0.125, 0))
	_tilt.scale = Vector3.ONE * 1.12
	# Ear knobs (tilt pivots), coral.
	for s: float in [-1.0, 1.0]:
		_bake(_pan, ProcMesh.cyl(0.032, 0.035, 0.02, 16), _paint(CORAL, 0.72, 0.6, 22.0 + s, 0.2, -1.0), _x(Vector3(0.185 * s, 0.125, 0), Vector3(0, 0, 90)))
		_bake(_pan, ProcMesh.cyl(0.012, 0.012, 0.03, 8), Mats.metal("steel"), _x(Vector3(0.193 * s, 0.125, 0), Vector3(0, 0, 90)))
	# Head pod: a round blue shell with a cream face plate.
	var head_mat: ShaderMaterial = _paint(BLUE.lightened(0.04), 0.8, 0.55, 23.0, 0.15, -0.3)
	_bake(_tilt, ProcMesh.sphere(0.14, 36, 18), head_mat, _x(Vector3.ZERO, Vector3.ZERO, Vector3(1.03, 0.94, 0.96)))
	_bake(_tilt, ProcMesh.torus(0.138, 0.15, 36, 6), Mats.metal("dark_steel"), _x(Vector3(0, 0, 0.0), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.92)))   # seam band
	# Face disc behind the lens.
	_bake(_tilt, ProcMesh.cyl(0.112, 0.118, 0.02, 32), _paint(CREAM, 0.7, 0.75, 24.0, 0.2, -0.3), _x(Vector3(0, -0.005, -0.112), Vector3(90, 0, 0)))
	# Rust-stained brass bezel.
	var bezel_mat: ShaderMaterial = _paint(Color(0.72, 0.52, 0.22), 0.4, 1.0, 25.0, 0.8, 0.3)
	bezel_mat.set_shader_parameter("metallic_bare", 0.6)
	_bake(_tilt, ProcMesh.torus(0.078, 0.105, 36, 10), bezel_mat, _x(Vector3(0, -0.005, -0.128), Vector3(90, 0, 0), Vector3(1, 0.7, 1)))
	var bz_bolts: Array = []
	for k: int in 8:
		var a: float = TAU * (k + 0.5) / 8.0
		bz_bolts.append(Vector3(cos(a) * 0.092, sin(a) * 0.092 - 0.005, -0.138))
	_bolts(_tilt, bz_bolts, Vector3(0, 0, -1), 0.006)
	# Lens: barrel, sensor, 8-blade aperture, glass.
	var lens: Node3D = _node(_tilt, Vector3(0, -0.005, -0.13))
	lens.scale = Vector3.ONE * 1.2
	var tube: CylinderMesh = ProcMesh.cyl(0.064, 0.066, 0.04, 32)
	tube.cap_top = false
	tube.cap_bottom = false
	_bake(lens, tube, Mats.metal("dark_steel"), _x(Vector3(0, 0, -0.012), Vector3(90, 0, 0)))
	var sleeve: CylinderMesh = ProcMesh.cyl(0.062, 0.062, 0.04, 32)
	sleeve.cap_top = false
	sleeve.cap_bottom = false
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.03, 0.03, 0.03)
	sleeve_mat.roughness = 0.6
	sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bake(lens, sleeve, sleeve_mat, _x(Vector3(0, 0, -0.012), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.torus(0.054, 0.068, 32, 8), Mats.metal("chrome"), _x(Vector3(0, 0, -0.032), Vector3(90, 0, 0)))
	_sensor_mat = Mats.lamp(Color(1.0, 0.68, 0.3), 1.0)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.01, 0.01, 0.012)
	back_mat.roughness = 0.3
	_bake(lens, ProcMesh.cyl(0.056, 0.056, 0.004, 32), back_mat, _x(Vector3(0, 0, -0.004), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.cyl(0.03, 0.03, 0.004, 24), _sensor_mat, _x(Vector3(0, 0, -0.007), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.sphere(0.008, 8, 4), Mats.lamp(Color(1, 0.95, 0.85), 2.0), _x(Vector3(0.012, 0.012, -0.01)))
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.3, 0.29, 0.28)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.38
	for k: int in 8:
		var piv: Node3D = _node(lens, Vector3(0, 0, -0.014 - k * 0.0007))
		piv.rotation.z = TAU * k / 8.0
		var arm: Node3D = _node(piv, Vector3.ZERO)
		_bake(arm, ProcMesh.box(Vector3(0.04, 0.034, 0.0012)), blade_mat, _x(Vector3(0.007, 0.017, 0)))
		_blades.append(arm)
	var glass_mat: StandardMaterial3D = Mats.glass(Color(0.5, 0.6, 0.65, 0.08), 0.03)
	glass_mat.metallic = 0.0
	_bake(lens, ProcMesh.cyl(0.058, 0.058, 0.003, 32), glass_mat, _x(Vector3(0, 0, -0.03), Vector3(90, 0, 0)))
	# Brow plate: hinged above the lens, lifts when happy, droops when sleepy.
	_brow = _node(_tilt, Vector3(0, 0.1, -0.08))
	_bake(_brow, ProcMesh.rounded_box(Vector3(0.17, 0.014, 0.075), 0.006, 2), _paint(CREAM, 0.68, 0.7, 26.0, 0.2, -0.5), _x(Vector3(0, 0, -0.035)))
	_bake(_brow, ProcMesh.cyl(0.008, 0.008, 0.15, 8), Mats.metal("steel"), _x(Vector3.ZERO, Vector3(0, 0, 90)))
	# Little cheek lamps.
	for s: float in [-1.0, 1.0]:
		_bake(_tilt, ProcMesh.cyl(0.012, 0.012, 0.01, 12), Mats.lamp(Color(1.0, 0.45, 0.35), 0.35), _x(Vector3(0.105 * s, -0.06, -0.085), Vector3(90, 0, 0)))
	# Antenna whip with a coral lamp.
	var ant: Node3D = _node(_tilt, Vector3(-0.07, 0.11, 0.04), Vector3(-10, 0, 14))
	_bake(ant, ProcMesh.cyl(0.016, 0.02, 0.025, 10), Mats.metal("dark_steel"), _x(Vector3(0, 0.0, 0)))
	_bake(ant, ProcMesh.cyl(0.0035, 0.005, 0.15, 6), Mats.metal("steel"), _x(Vector3(0, 0.085, 0)))
	_lamp_mat = Mats.lamp(Color(1.0, 0.35, 0.22), 1.2)
	_bake(ant, ProcMesh.sphere(0.02, 12, 6), _lamp_mat, _x(Vector3(0, 0.17, 0)))
	_bake(ant, ProcMesh.torus(0.004, 0.012, 10, 4), Mats.metal("brass"), _x(Vector3(0, 0.152, 0)))
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0, 0.17, 0)
	_lamp_light.light_color = Color(1.0, 0.4, 0.25)
	_lamp_light.light_energy = 0.15
	_lamp_light.omni_range = 0.5
	ant.add_child(_lamp_light)
	_stencil(_tilt, "P-47CH", 22, Vector3(0, 0.02, 0.137), Vector3(0, 180, 0), Color(0.15, 0.2, 0.25, 0.6))
	_hose(_rig, base + Vector3(0.05, 0.02, 0.05), base + Vector3(0.11, 0.08, 0.08), base + Vector3(0.12, 0.12, 0.03), 0.006)


func _build_arm(s: float) -> void:
	var arm_mat: ShaderMaterial = _paint(CREAM, 0.68, 0.7, 50.0 + s * 3.0, 0.5, -0.4)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var shoulder_pos := Vector3(0.215 * s, 0.27, TUB_FZ)
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.05, 0.07, 0.05), 0.01, 2), steel, _x(Vector3(0.215 * s, 0.27, TUB_FZ + 0.02)))
	var shoulder: Node3D = _node(_rig, shoulder_pos)
	var yaw: Node3D = _node(shoulder, Vector3.ZERO)
	_bake(yaw, ProcMesh.cyl(0.028, 0.028, 0.06, 14), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(yaw, ProcMesh.cyl(0.02, 0.02, 0.064, 12), _paint(CORAL, 0.7, 0.6, 51.0 + s, 0.3), _x(Vector3(0.0, 0, 0), Vector3(0, 0, 90), Vector3(1.0, 1.05, 1.0)))
	var upper: Node3D = _node(yaw, Vector3.ZERO)
	_bake(upper, ProcMesh.rounded_box(Vector3(0.036, 0.04, L1 + 0.03), 0.014, 2), arm_mat, _x(Vector3(0, 0, -L1 * 0.5)))
	var elbow: Node3D = _node(upper, Vector3(0, 0, -L1))
	_bake(elbow, ProcMesh.cyl(0.022, 0.022, 0.05, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(elbow, ProcMesh.rounded_box(Vector3(0.03, 0.034, L2 + 0.02), 0.012, 2), arm_mat, _x(Vector3(0, 0, -L2 * 0.5)))
	var wrist: Node3D = _node(elbow, Vector3(0, 0, -L2))
	_bake(wrist, ProcMesh.cyl(0.02, 0.02, 0.046, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(wrist, ProcMesh.rounded_box(Vector3(0.05, 0.03, 0.03), 0.008, 2), steel, _x(Vector3(0, 0, -0.018)))
	# Two-finger clamp that pinches sideways.
	var tip_mat: ShaderMaterial = _paint(CORAL, 0.72, 0.6, 52.0 + s, 0.3, -0.4)
	var halves: Array[Node3D] = []
	for side: float in [1.0, -1.0]:
		var hv: Node3D = _node(wrist, Vector3(0.016 * side, 0, -0.03))
		_bake(hv, ProcMesh.rounded_box(Vector3(0.01, 0.026, 0.06), 0.004, 1), Mats.metal("steel"), _x(Vector3(0, 0, -0.03)))
		_bake(hv, ProcMesh.rounded_box(Vector3(0.024, 0.03, 0.016), 0.006, 2), tip_mat, _x(Vector3(-0.008 * side, 0, -0.062)))
		halves.append(hv)
	_hose(_rig, Vector3(0.24 * s, 0.36, TUB_FZ + 0.06), Vector3(0.27 * s, 0.33, TUB_FZ), Vector3(0.235 * s, 0.29, TUB_FZ - 0.01), 0.006)
	_arms.append({"s": s, "yaw": yaw, "upper": upper, "elbow": elbow, "wrist": wrist, "halves": halves})


func _add_ram(a: Node3D, b: Node3D, r: float, length: float, barrel_mat: Material) -> void:
	var barrel := Node3D.new()
	var rod := Node3D.new()
	_rig.add_child(barrel)
	_rig.add_child(rod)
	_bake(barrel, ProcMesh.cyl(r, r, length, 12), barrel_mat, _x(Vector3(0, 0, -length * 0.5), Vector3(90, 0, 0)))
	_bake(barrel, ProcMesh.cyl(r * 1.25, r * 1.25, 0.015, 12), Mats.metal("dark_steel"), _x(Vector3(0, 0, -length), Vector3(90, 0, 0)))
	_bake(rod, ProcMesh.cyl(r * 0.45, r * 0.45, length, 10), Mats.metal("chrome"), _x(Vector3(0, 0, -length * 0.5), Vector3(90, 0, 0)))
	_rams.append([barrel, rod, a, b])


# ---------------------------------------------------------------- animation

## Scoop keyframes: [t, shoulder pitch, forearm absolute pitch, jaw absolute pitch, clamp open 0..1, inward yaw].
const SCOOP_KEYS: Array = [
	[0.0, -30.0, -95.0, -100.0, 0.5, 0.0],
	[0.22, -52.0, -88.0, -95.0, 0.95, -4.0],
	[0.36, -52.0, -88.0, -95.0, 0.0, -4.0],
	[0.62, 70.0, -55.0, -115.0, 0.0, 22.0],
	[0.74, 70.0, -55.0, -115.0, 0.9, 22.0],
	[1.0, -30.0, -95.0, -100.0, 0.5, 0.0],
]
const REST_POSE: Array = [0.0, -72.0, 45.0, 80.0, 0.1, 6.0]


func _sample_scoop(t: float) -> Array:
	for i: int in SCOOP_KEYS.size() - 1:
		var k0: Array = SCOOP_KEYS[i]
		var k1: Array = SCOOP_KEYS[i + 1]
		if t <= float(k1[0]):
			var u: float = smoothstep(float(k0[0]), float(k1[0]), t)
			var out: Array = []
			for j: int in k0.size():
				out.append(lerpf(float(k0[j]), float(k1[j]), u))
			return out
	return SCOOP_KEYS[SCOOP_KEYS.size() - 1]


func _update_arms() -> void:
	for arm: Dictionary in _arms:
		var s: float = arm["s"]
		var phase: float = _scoop_phase + (0.0 if s > 0.0 else 0.5)
		if _debug_phase >= 0.0:
			phase = _debug_phase + (0.0 if s > 0.0 else 0.5)
		var cyc: Array = _sample_scoop(fposmod(phase, 1.0))
		var amt: float = 1.0 if _debug_phase >= 0.0 else _scoop_amount
		var p: Array = []
		for j: int in REST_POSE.size():
			p.append(lerpf(float(REST_POSE[j]), float(cyc[j]), amt))
		var th1: float = p[1]
		var phi: float = p[2]
		var jaw: float = p[3]
		(arm["yaw"] as Node3D).rotation.y = deg_to_rad(float(p[5])) * s
		(arm["upper"] as Node3D).rotation.x = deg_to_rad(th1)
		(arm["elbow"] as Node3D).rotation.x = deg_to_rad(phi - th1)
		(arm["wrist"] as Node3D).rotation.x = deg_to_rad(jaw - phi)
		var open: float = deg_to_rad(2.0 + float(p[4]) * 28.0)
		var halves: Array = arm["halves"]
		(halves[0] as Node3D).rotation.y = -open
		(halves[1] as Node3D).rotation.y = open


func _update_rams() -> void:
	for r: Array in _rams:
		var barrel: Node3D = r[0]
		var rod: Node3D = r[1]
		var pa: Vector3 = _rig.to_local((r[2] as Node3D).global_position)
		var pb: Vector3 = _rig.to_local((r[3] as Node3D).global_position)
		if pa.distance_to(pb) < 0.001:
			continue
		barrel.transform = Transform3D(Basis.looking_at(pb - pa, Vector3.RIGHT), pa)
		rod.transform = Transform3D(Basis.looking_at(pa - pb, Vector3.RIGHT), pb)


func _process(delta: float) -> void:
	_time += delta
	_scoop_amount = move_toward(_scoop_amount, 1.0 if _scoop_hold > 0.0 else 0.0, delta * 3.0)
	if _scoop_amount > 0.0:
		_scoop_phase = fposmod(_scoop_phase + delta / 1.6, 1.0)
	_scoop_hold = maxf(0.0, _scoop_hold - delta)
	_update_arms()
	# Suspension: lean, tiny dip, vibration.
	_dip = lerpf(_dip, _dip_target, clampf(delta * 10.0, 0.0, 1.0))
	_dip_target = move_toward(_dip_target, 0.0, delta * 0.2)
	var jitter := Vector3.ZERO
	if _shudder_t > 0.0:
		_shudder_t -= delta
		jitter = Vector3(sin(_time * 91.0), sin(_time * 117.0) * 0.6, sin(_time * 73.0)) * 0.003
	if sleeping:
		jitter = Vector3.ZERO
	var breathe: float = sin(_time * (0.9 if sleeping else 1.6)) * (0.003 if sleeping else 0.0015)
	_rig.position = Vector3(0, -_dip - _press_now * 0.006 + breathe, 0) + jitter
	_rig.rotation = Vector3(_lean.x, 0, _lean.y)
	# Lid: cracks open while feeding, pulled down past closed by the rams when pressing.
	var lid_target: float = deg_to_rad(9.0) * _scoop_amount
	lid_target = lerpf(lid_target, deg_to_rad(-2.0), _press_now)
	_lid_now = lerpf(_lid_now, lid_target, clampf(delta * 6.0, 0.0, 1.0))
	_lid.rotation.x = _lid_now
	_update_rams()
	# Head: pan toward target, curious tilt and roll; sleeping droops it.
	_look_yaw = lerp_angle(_look_yaw, _look_target, clampf(delta * 3.0, 0.0, 1.0))
	_pan.rotation.y = _look_yaw
	var tilt_target: float = deg_to_rad(-22.0) if sleeping else deg_to_rad(-4.0 + 10.0 * _iris_target + sin(_time * 0.7) * 2.0)
	_tilt_now = lerpf(_tilt_now, tilt_target, clampf(delta * 2.5, 0.0, 1.0))
	_tilt.rotation.x = _tilt_now
	var roll_target: float = deg_to_rad(10.0) if sleeping else deg_to_rad(sin(_time * 0.45) * 5.0 + 4.0 * _iris_target)
	_roll_now = lerpf(_roll_now, roll_target, clampf(delta * 2.0, 0.0, 1.0))
	_tilt.rotation.z = _roll_now
	# Brow: raised when happy, lowered over the lens when asleep.
	var brow_target: float = deg_to_rad(-28.0) if sleeping else deg_to_rad(8.0 + 22.0 * _iris_target)
	_brow_now = lerpf(_brow_now, brow_target, clampf(delta * 5.0, 0.0, 1.0))
	_brow.rotation.x = _brow_now
	# Aperture.
	var ap: float = 0.0 if sleeping else _iris_target
	_iris_now = lerpf(_iris_now, ap, clampf(delta * 6.0, 0.0, 1.0))
	var r_ap: float = lerpf(0.004, 0.03, _iris_now)
	for b: Node3D in _blades:
		b.position = Vector3(0, r_ap, 0)
		b.rotation.z = lerpf(0.5, 0.15, _iris_now)
	_sensor_mat.emission_energy_multiplier = (0.05 if sleeping else 0.9 + 0.8 * _iris_now)
	# Antenna lamp.
	_flash_t = maxf(0.0, _flash_t - delta * 2.5)
	var pulse: float = 0.7 + 0.3 * sin(_time * 2.4)
	if sleeping:
		pulse = 0.12 + 0.1 * maxf(0.0, sin(_time * 0.8))
	_lamp_mat.emission_energy_multiplier = pulse + _flash_t * 6.0
	_lamp_light.light_energy = 0.1 + _flash_t * 1.5
	_fill_angle = lerpf(_fill_angle, _fill_target, clampf(delta * 4.0, 0.0, 1.0))
	_needle.rotation.z = -_fill_angle
	_hatch.rotation.x = _hatch_now * deg_to_rad(100.0)


# ---------------------------------------------------------------- interface

func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	_wheel_angle -= speed * delta / WHEEL_R
	for w: Node3D in _wheels:
		w.rotation.x = _wheel_angle
	var target_steer: float = clampf(-local_accel.x * 0.04, -0.45, 0.45) if absf(speed) > 0.05 else _steer
	_steer = lerp_angle(_steer, target_steer, clampf(delta * 5.0, 0.0, 1.0))
	for sw: Node3D in _swivels:
		sw.rotation.y = _steer
	var target := Vector2(clampf(-local_accel.y * 0.004, -0.035, 0.035), clampf(local_accel.x * 0.004, -0.03, 0.03))
	target.x += 0.0 * speed_ratio
	_lean = _lean.lerp(target, clampf(delta * 4.0, 0.0, 1.0))


func set_scooping(active: bool) -> void:
	if active:
		_scoop_hold = 0.15


func set_fill(ratio: float, band: Array) -> void:
	_fill_target = deg_to_rad(lerpf(-120.0, 120.0, clampf(ratio / 1.15, 0.0, 1.0)))
	var lo: float = float(band[0]) if band.size() > 0 else 0.7
	var hi: float = float(band[1]) if band.size() > 1 else 1.0
	if ratio > hi + 0.0001:
		_gauge_lamp_mat.emission = Color(1.0, 0.18, 0.1)
		_gauge_lamp_mat.emission_energy_multiplier = 1.6 + 0.8 * sin(_time * 10.0)
	elif ratio >= lo:
		_gauge_lamp_mat.emission = Color(1.0, 0.65, 0.15)
		_gauge_lamp_mat.emission_energy_multiplier = 1.4
	else:
		_gauge_lamp_mat.emission = Color(0.45, 0.8, 0.35)
		_gauge_lamp_mat.emission_energy_multiplier = 0.6


func shudder(duration: float) -> void:
	_shudder_t = maxf(_shudder_t, duration)


func squash(amount: float) -> void:
	_dip_target = clampf(_dip_target + absf(amount) * 0.008, 0.0, 0.01)


func look_toward(world_pos: Variant) -> void:
	if world_pos == null:
		_look_target = 0.0
		return
	var local: Vector3 = _rig.global_transform.affine_inverse() * (world_pos as Vector3)
	var d: Vector3 = local - _pan.position
	_look_target = clampf(atan2(-d.x, -d.z), -1.4, 1.4)


func set_happy(amount: float) -> void:
	_iris_target = clampf(amount, 0.0, 1.0)


func flash() -> void:
	_flash_t = 1.0


func set_rust(amount: float) -> void:
	_rust = clampf(amount, 0.0, 1.0)
	for m: ShaderMaterial in _paint_mats:
		var cov: float = m.get_meta("cov", 0.6)
		m.set_shader_parameter("rust_amount", clampf(0.35 + _rust * 0.6, 0.0, 1.0))
		m.set_shader_parameter("paint_coverage", clampf(cov * (1.25 - _rust * 0.5), 0.15, 0.95))


func press(t: float) -> void:
	_press_now = clampf(t, 0.0, 1.0)


func open_hatch(t: float) -> void:
	_hatch_now = clampf(t, 0.0, 1.0)
