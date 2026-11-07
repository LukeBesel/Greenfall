extends Node3D
## Patch v2 (unit P-47CH), concept A "Pocket hauler".
## A small, slightly bottom-heavy rounded capsule (an old street-bin shell, powder-blue paint worn
## through to rust) leaning a little forward on two fat soft tyres and a little rear caster. One big
## camera-lens eye sits in a hooded visor pod at the front-top, with a mechanical aperture iris and a
## curved eyelid shutter that droops when he is sleepy. Below it, a rubber-curtained intake "mouth"
## with a scoop lip takes in junk; a stubby two-joint grabber arm on his right feeds it. A tiny
## compaction ram pokes out of the lid like a knob, and bales leave through a hinged hatch at the back.
## Faces -Z, base at y = 0. About 0.9 m to the antenna lamp, 0.72 m long.

const BLUE := Color(0.50, 0.71, 0.86)        # faded powder / sky blue
const BLUE_DK := Color(0.30, 0.45, 0.58)     # darker blue for the skirt and trims
const CREAM := Color(0.86, 0.82, 0.70)       # chipped cream (visor lid, hubs)
const CORAL := Color(0.80, 0.36, 0.26)       # faded coral-red accents
const MUSTARD := Color(0.80, 0.62, 0.20)     # mustard (hatch, arm)
const MINT := Color(0.55, 0.74, 0.62)        # mismatched repair patch

const WHEEL_R: float = 0.16
const WHEEL_X: float = 0.31
const WHEEL_Z: float = -0.05
const CASTER_R: float = 0.05
const CASTER_Z: float = 0.25
const BODY_C := Vector3(0, 0.47, 0.03)
const BODY_S := Vector3(0.46, 0.46, 0.54)
const TILT: float = -6.0          # degrees; negative leans the top forward (-Z)
const EYE_C := Vector3(0, 0.0, -0.085)   # lens centre inside the visor pod
const L1: float = 0.14
const L2: float = 0.14

## Interface: local anchor points used by the controller.
var chest_point := Vector3(0, 0.30, -0.29)
var back_hatch_point := Vector3(0, 0.38, 0.36)
var vent_points: Array[Vector3] = [Vector3(-0.25, 0.45, 0.1), Vector3(0.13, 0.75, 0.17), Vector3(0.18, 0.55, 0.27)]
var stack_point := Vector3(0, 0.75, 0.22)
var lens_point := Vector3(0, 0.5, -0.33)
var sleeping: bool = false
var _iris_now: float = 0.55

var _rig: Node3D
var _body: Node3D
var _pan: Node3D
var _tilt: Node3D
var _lid: Node3D
var _blades: Array[Node3D] = []
var _sensor_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _fill_leds: Array[StandardMaterial3D] = []
var _wheels: Array[Node3D] = []
var _caster_swivel: Node3D
var _caster_wheel: Node3D
var _arm: Dictionary = {}
var _press_rod: Node3D
var _hatch: Node3D
var _paint_mats: Array[ShaderMaterial] = []

var _time: float = 0.0
var _rust: float = 0.55
var _wheel_angle: float = 0.0
var _caster_angle: float = 0.0
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
var _lid_now: float = 35.0
var _iris_target: float = 0.55
var _flash_t: float = 0.0
var _fill_ratio: float = 0.0
var _fill_lo: float = 0.7
var _fill_hi: float = 1.0
var _press_now: float = 0.0
var _hatch_now: float = 0.0
var _debug_phase: float = -1.0
var _blink_t: float = 3.0


func _ready() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_body = _node(_rig, Vector3(0, -0.07, 0))
	_build_running_gear()
	_build_body()
	_build_intake()
	_build_eye()
	_build_ram()
	_build_hatch()
	_build_arm()
	var pose: String = OS.get_environment("DRUM_POSE")
	if pose != "":
		for kv: String in pose.split(","):
			var p: PackedStringArray = kv.split(":")
			if p.size() == 2:
				match p[0]:
					"scoop": _debug_phase = float(p[1])
					"press": _press_now = float(p[1])
					"hatch": _hatch_now = float(p[1])
					"happy": _iris_target = float(p[1]); _iris_now = _iris_target
	_update_arm()
	set_rust(_rust)


# ---------------------------------------------------------------- helpers

func _paint(color: Color, coverage: float, rust: float, seed_: float, grime: float = 0.5, floor_y: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(color, coverage, rust, seed_, grime)
	m.set_shader_parameter("grime_floor", floor_y)
	m.set_shader_parameter("grime_height", 0.35)
	m.set_shader_parameter("fade", 0.2)
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


func _hose(parent: Node3D, p0: Vector3, p1: Vector3, p2: Vector3, r: float = 0.01) -> void:
	var parts: Array = []
	var n: int = 10
	var prev: Vector3 = p0
	for i: int in range(1, n + 1):
		var t: float = float(i) / n
		var p: Vector3 = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		parts.append(ProcMesh.part(ProcMesh.cyl(r, r, (p - prev).length() * 1.12, 8), _between(prev, p)))
		prev = p
	_bake_many(parent, parts, Mats.rubber())


func _bolts(parent: Node3D, points: Array, normal: Vector3, size: float = 0.009) -> void:
	var parts: Array = []
	var q := Quaternion(Vector3.UP, normal.normalized())
	for p: Vector3 in points:
		parts.append(ProcMesh.part(ProcMesh.cyl(size, size, size * 0.9, 6), Transform3D(Basis(q), p)))
	_bake_many(parent, parts, Mats.metal("dark_steel"))


## Thin slab whose plan outline follows the body's rounded corners (rounded box squashed in Y).
func _slab(w: float, h: float, d: float, plan_r: float) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(1, h / (plan_r * 2.0), 1)), Vector3.ZERO)


## Point on the body shell surface: body-space direction -> rig position (rounded box approximation).
func _body_xf(local: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(TILT), 0, 0))
	return Transform3D(b * Basis.from_euler(rot * (PI / 180.0)), BODY_C + b * local)


## Spherical band shell: points R*(sin b, cos b cos a, -cos b sin a); a = 0 up, 90 forward (-Z).
## Emits both windings so it renders from either side; outer and inner skins plus the front rim.
func _sphere_band(r: float, thick: float, a0: float, a1: float, na: int = 14, nb: int = 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pt := func(rad: float, a: float, b: float) -> Vector3:
		var ar: float = deg_to_rad(a)
		var br: float = deg_to_rad(b)
		return Vector3(sin(br), cos(br) * cos(ar), -cos(br) * sin(ar)) * rad
	var quad := func(p: Array, nrm: Array) -> void:
		for idx: int in [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]:
			st.set_normal(nrm[idx])
			st.add_vertex(p[idx])
	for skin: int in 2:
		var rad: float = r if skin == 0 else r - thick
		var sg: float = 1.0 if skin == 0 else -1.0
		for i: int in na:
			for j: int in nb:
				var aa: float = lerpf(a0, a1, float(i) / na)
				var ab: float = lerpf(a0, a1, float(i + 1) / na)
				var ba: float = lerpf(-90.0, 90.0, float(j) / nb)
				var bb: float = lerpf(-90.0, 90.0, float(j + 1) / nb)
				var ps: Array = [pt.call(rad, aa, ba), pt.call(rad, ab, ba), pt.call(rad, ab, bb), pt.call(rad, aa, bb)]
				var ns: Array = []
				for p: Vector3 in ps:
					ns.append(p.normalized() * sg)
				quad.call(ps, ns)
	# Rim along the a1 edge.
	for j: int in nb:
		var ba: float = lerpf(-90.0, 90.0, float(j) / nb)
		var bb: float = lerpf(-90.0, 90.0, float(j + 1) / nb)
		var ps: Array = [pt.call(r, a1, ba), pt.call(r, a1, bb), pt.call(r - thick, a1, bb), pt.call(r - thick, a1, ba)]
		var nr: Vector3 = (pt.call(1.0, a1 + 1.0, 0.0) as Vector3) - (pt.call(1.0, a1, 0.0) as Vector3)
		nr = nr.normalized()
		quad.call(ps, [nr, nr, nr, nr])
	return st.commit()


func _stencil(parent: Node3D, text: String, size_px: int, pos: Vector3, rot_deg: Vector3, color: Color = Color(0.9, 0.88, 0.8, 0.55)) -> Label3D:
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


# ---------------------------------------------------------------- build

func _build_running_gear() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	# Axle beam under the body.
	_bake(_rig, ProcMesh.cyl(0.03, 0.03, WHEEL_X * 2.0 - 0.1, 12), steel, _x(Vector3(0, WHEEL_R, WHEEL_Z), Vector3(0, 0, 90)))
	var tyre: Mesh = AssetLib.model_mesh("old_tyre")
	var tscale: float = WHEEL_R * 2.0 / 0.6
	var hub_mat: ShaderMaterial = _paint(CREAM, 0.7, 0.6, 3.1, 0.6)
	for s: float in [-1.0, 1.0]:
		var hub: Node3D = _node(self, Vector3(WHEEL_X * s, WHEEL_R, WHEEL_Z))
		var spin: Node3D = _node(hub, Vector3.ZERO)
		var t := MeshInstance3D.new()
		t.mesh = tyre
		t.rotation_degrees = Vector3(0, 90, 0)
		t.scale = Vector3(tscale, tscale, 1.45 * tscale)   # fat, soft balloon tyre
		spin.add_child(t)
		# Painted dished hub with a domed cap and five nuts.
		_bake(spin, ProcMesh.cyl(0.085, 0.09, 0.09, 24), hub_mat, _x(Vector3(0, 0, 0), Vector3(0, 0, 90)))
		_bake(spin, ProcMesh.sphere(0.05, 18, 8), _paint(CORAL, 0.7, 0.55, 3.7 + s, 0.4), _x(Vector3(0.05 * s, 0, 0), Vector3.ZERO, Vector3(0.55, 1, 1)))
		var nuts: Array = []
		for k: int in 5:
			var a: float = TAU * k / 5.0
			nuts.append(Vector3(0.047 * s, cos(a) * 0.066, sin(a) * 0.066))
		_bolts(spin, nuts, Vector3(s, 0, 0), 0.009)
		_wheels.append(spin)
	# Rear swivel caster on a short painted post.
	_caster_swivel = _node(_rig, Vector3(0, 0.17, CASTER_Z))
	_bake(_caster_swivel, ProcMesh.cyl(0.035, 0.04, 0.04, 14), steel, _x(Vector3(0, 0.0, 0)))
	var fork: Array = []
	for s: float in [-1.0, 1.0]:
		fork.append(ProcMesh.part(ProcMesh.box(Vector3(0.01, 0.13, 0.04)), _x(Vector3(0.035 * s, -0.065, 0.02), Vector3(14, 0, 0))))
	fork.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, 0.016, 0.05)), _x(Vector3(0, -0.015, 0.005))))
	_bake_many(_caster_swivel, fork, _paint(BLUE_DK, 0.5, 0.7, 5.1, 0.8, -0.2))
	_caster_wheel = _node(_caster_swivel, Vector3(0, CASTER_R - 0.17, 0.04))
	_bake(_caster_wheel, ProcMesh.cyl(CASTER_R, CASTER_R, 0.045, 18), Mats.rubber(Color(0.06, 0.06, 0.06)), _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(_caster_wheel, ProcMesh.cyl(0.026, 0.026, 0.05, 12), _paint(CREAM, 0.6, 0.6, 5.7, 0.7), _x(Vector3.ZERO, Vector3(0, 0, 90)))


func _build_body() -> void:
	var shell: ShaderMaterial = _paint(BLUE, 0.7, 0.72, 7.3, 0.5)
	# Main capsule shell (rounded box, very soft corners), leaning forward.
	_bake(_body, ProcMesh.rounded_box(BODY_S, 0.2, 6), shell, _body_xf(Vector3.ZERO))
	# Domed lid.
	# Rolled seam band where the lid meets the shell.
	_bake(_body, ProcMesh.rounded_box(Vector3(BODY_S.x + 0.012, 0.4, BODY_S.z + 0.012), 0.2, 6), _paint(CREAM, 0.6, 0.7, 4.4, 0.5), _body_xf(Vector3(0, -0.02, 0)) * _slab(0, 0.018, 0, 0.2))
	# Bottom-heavy skirt / bumper band, darker and grimy.
	_bake(_body, ProcMesh.rounded_box(Vector3(BODY_S.x + 0.02, 0.4, BODY_S.z + 0.03), 0.2, 6), _paint(BLUE_DK.lightened(0.22), 0.6, 0.75, 6.6, 0.7, 0.1), _body_xf(Vector3(0, -0.18, 0)) * _slab(0, 0.11, 0, 0.2))
	# Rubber bump strip around the skirt.
	_bake(_body, ProcMesh.rounded_box(Vector3(BODY_S.x + 0.03, 0.4, BODY_S.z + 0.05), 0.2, 6), Mats.rubber(Color(0.07, 0.07, 0.07)), _body_xf(Vector3(0, -0.14, 0)) * _slab(0, 0.028, 0, 0.2))
	# Wheel arches: dark recesses either side so the tyres tuck in.
	# Side louvre vent (left), bolted.
	var vent: Node3D = _node(_body, Vector3(-BODY_S.x * 0.5 - 0.004, 0.5, 0.17), Vector3(0, -90, 0))
	_bake(vent, ProcMesh.rounded_box(Vector3(0.16, 0.11, 0.03), 0.012, 2), Mats.metal("dark_steel"))
	var lv: Array = []
	for k: int in 4:
		lv.append(ProcMesh.part(ProcMesh.box(Vector3(0.13, 0.01, 0.024)), _x(Vector3(0, -0.036 + k * 0.024, -0.016), Vector3(35, 0, 0))))
	_bake_many(vent, lv, Mats.metal("steel"))
	# Mismatched repair patch: a bolted mint plate on the left flank (he is literally patched).
	var pt: Node3D = _node(_body, Vector3(-BODY_S.x * 0.5 - 0.006, 0.38, -0.08), Vector3(0, -90, 4))
	_bake(pt, ProcMesh.box(Vector3(0.15, 0.1, 0.006)), _paint(MINT, 0.6, 0.7, 9.3, 0.5), _x(Vector3.ZERO))
	_bolts(pt, [Vector3(-0.065, 0.04, -0.004), Vector3(0.065, 0.04, -0.004), Vector3(-0.065, -0.04, -0.004), Vector3(0.065, -0.04, -0.004)], Vector3(0, 0, -1), 0.007)
	# Serial stencils on both flanks.
	_stencil(_body, "P-47CH", 70, Vector3(-BODY_S.x * 0.5 - 0.008, 0.55, -0.07), Vector3(0, -90, 0), Color(0.92, 0.9, 0.82, 0.55))
	_stencil(_body, "MUNI SANITATION", 24, Vector3(-BODY_S.x * 0.5 - 0.008, 0.49, -0.07), Vector3(0, -90, 0), Color(0.92, 0.9, 0.82, 0.4))
	_stencil(_body, "P-47CH", 60, Vector3(BODY_S.x * 0.5 + 0.008, 0.62, 0.12), Vector3(0, 90, 0), Color(0.92, 0.9, 0.82, 0.5))
	# Exhaust stub on the lid, rear-right.
	_bake(_body, ProcMesh.cyl(0.02, 0.024, 0.09, 12), Mats.metal("dark_steel"), _x(Vector3(0.13, 0.76, 0.17)))
	_bake(_body, ProcMesh.torus(0.017, 0.026, 12, 6), Mats.metal("steel"), _x(Vector3(0.13, 0.805, 0.17)))
	# Fill gauge: five little lamps in a steel strip on the back of the lid (seen from the follow cam).
	var g: Node3D = _node(_body, Vector3(0, 0.625, 0.275), Vector3(-25, 0, 0))
	_bake(g, ProcMesh.rounded_box(Vector3(0.17, 0.045, 0.02), 0.01, 2), Mats.metal("dark_steel"))
	for k: int in 5:
		var m: StandardMaterial3D = Mats.lamp(Color(0.45, 0.8, 0.35), 0.1)
		_fill_leds.append(m)
		_bake(g, ProcMesh.hemisphere(0.011, 10, 4), m, _x(Vector3(-0.06 + k * 0.03, 0, 0.01), Vector3(90, 0, 0)))


func _build_intake() -> void:
	var coral: ShaderMaterial = _paint(CORAL, 0.66, 0.6, 11.0, 0.6)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	# Mouth frame: a rounded coral bezel on the lower front of the shell.
	var f: Node3D = _node(_body, Vector3(0, 0.37, -0.255), Vector3(TILT, 0, 0))
	_bake(f, ProcMesh.rounded_box(Vector3(0.34, 0.15, 0.06), 0.05, 4), coral, _x(Vector3.ZERO))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.015, 0.015, 0.015)
	dark.roughness = 1.0
	_bake(f, ProcMesh.rounded_box(Vector3(0.28, 0.1, 0.02), 0.035, 3), dark, _x(Vector3(0, 0, -0.025)))
	var flaps: Array = []
	for k: int in 6:
		var x: float = -0.113 + k * 0.045
		flaps.append(ProcMesh.part(ProcMesh.box(Vector3(0.042, 0.085, 0.006)), _x(Vector3(x, -0.004, -0.034), Vector3(randf_range(-4, 4), 0, 0))))
	_bake_many(f, flaps, Mats.rubber(Color(0.08, 0.08, 0.075)))
	_bake(f, ProcMesh.box(Vector3(0.28, 0.016, 0.016)), steel, _x(Vector3(0, 0.045, -0.035)))
	_bolts(f, [Vector3(-0.15, 0.045, -0.032), Vector3(0.15, 0.045, -0.032)], Vector3(0, 0, -1), 0.008)
	# Scoop lip below the mouth: a small sloped tray like a chin.
	var tr_: Array = []
	tr_.append(ProcMesh.part(ProcMesh.box(Vector3(0.34, 0.016, 0.13)), _x(Vector3(0, 0.29, -0.33), Vector3(-12, 0, 0))))
	for s: float in [-1.0, 1.0]:
		tr_.append(ProcMesh.part(ProcMesh.box(Vector3(0.016, 0.05, 0.13)), _x(Vector3(0.17 * s, 0.31, -0.33), Vector3(-12, 0, 0))))
	tr_.append(ProcMesh.part(ProcMesh.cyl(0.012, 0.012, 0.35, 10), _x(Vector3(0, 0.305, -0.395), Vector3(0, 0, 90))))
	_bake_many(_body, tr_, _paint(MUSTARD, 0.6, 0.65, 12.0, 0.7))
	_bake(_body, ProcMesh.box(Vector3(0.34, 0.02, 0.03)), steel, _x(Vector3(0, 0.28, -0.39)))   # wear strip


func _build_eye() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	_pan = _node(_body, Vector3(0, 0.57, -0.2))
	# Neck collar sunk into the shell.
	_bake(_pan, ProcMesh.cyl(0.1, 0.11, 0.04, 20), steel, _x(Vector3(0, -0.06, 0.04), Vector3(-30, 0, 0)))
	_tilt = _node(_pan, Vector3.ZERO)
	# Visor pod: a squat cream ball the lens is set into.
	_bake(_tilt, ProcMesh.sphere(0.13, 28, 12), _paint(CREAM, 0.75, 0.55, 21.0, 0.2, -0.3), _x(Vector3(0, 0, 0.0), Vector3.ZERO, Vector3(1.08, 0.98, 0.72)))
	# Hood / brow: a blue shell over the top of the lens.
	_bake(_tilt, _sphere_band(0.14, 0.008, -70.0, 30.0), _paint(BLUE, 0.7, 0.6, 22.0, 0.2, -0.3), _x(Vector3(0, 0.006, EYE_C.z + 0.035)))
	# Lens assembly.
	var lens: Node3D = _node(_tilt, EYE_C)
	_bake(lens, ProcMesh.cyl(0.098, 0.1, 0.022, 36), steel, _x(Vector3(0, 0, 0.0), Vector3(90, 0, 0)))
	var tube: CylinderMesh = ProcMesh.cyl(0.088, 0.092, 0.035, 36)
	tube.cap_top = false
	tube.cap_bottom = false
	_bake(lens, tube, Mats.metal("chrome"), _x(Vector3(0, 0, -0.025), Vector3(90, 0, 0)))
	var sleeve: CylinderMesh = ProcMesh.cyl(0.086, 0.086, 0.035, 36)
	sleeve.cap_top = false
	sleeve.cap_bottom = false
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.03, 0.03, 0.03)
	sleeve_mat.roughness = 0.6
	sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bake(lens, sleeve, sleeve_mat, _x(Vector3(0, 0, -0.025), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.torus(0.078, 0.094, 36, 8), _paint(CORAL, 0.75, 0.5, 23.0, 0.1, 1.0), _x(Vector3(0, 0, -0.043), Vector3(90, 0, 0)))
	var knurl: Array = []
	for k: int in 30:
		var a: float = TAU * k / 30.0
		knurl.append(ProcMesh.part(ProcMesh.box(Vector3(0.007, 0.007, 0.022)), _x(Vector3(cos(a) * 0.092, sin(a) * 0.092, -0.022))))
	_bake_many(lens, knurl, steel)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.01, 0.012, 0.015)
	back_mat.roughness = 0.25
	_bake(lens, ProcMesh.cyl(0.08, 0.08, 0.004, 36), back_mat, _x(Vector3(0, 0, -0.012), Vector3(90, 0, 0)))
	# Sensor: warm amber pupil glow behind the aperture.
	_sensor_mat = Mats.lamp(Color(1.0, 0.7, 0.32), 1.2)
	_bake(lens, ProcMesh.cyl(0.042, 0.042, 0.004, 28), _sensor_mat, _x(Vector3(0, 0, -0.015), Vector3(90, 0, 0)))
	var glint := Mats.lamp(Color(1.0, 0.95, 0.85), 2.5)
	_bake(lens, ProcMesh.cyl(0.008, 0.008, 0.003, 10), glint, _x(Vector3(0.016, 0.016, -0.018), Vector3(90, 0, 0)))
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.3, 0.29, 0.28)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.35
	for k: int in 9:
		var piv: Node3D = _node(lens, Vector3(0, 0, -0.02 - k * 0.0008))
		piv.rotation.z = TAU * k / 9.0
		var arm: Node3D = _node(piv, Vector3.ZERO)
		_bake(arm, ProcMesh.box(Vector3(0.06, 0.05, 0.0012)), blade_mat, _x(Vector3(0.01, 0.025, 0)))
		_blades.append(arm)
	var glass_mat: StandardMaterial3D = Mats.glass(Color(0.55, 0.65, 0.7, 0.08), 0.03)
	glass_mat.metallic = 0.0
	glass_mat.clearcoat_enabled = true
	glass_mat.clearcoat = 1.0
	_bake(lens, ProcMesh.sphere(0.086, 32, 10), glass_mat, _x(Vector3(0, 0, -0.04), Vector3.ZERO, Vector3(1, 1, 0.25)))
	# Eyelid shutter: a cream shell that swings down over the lens.
	_lid = _node(_tilt, Vector3(0, 0, EYE_C.z + 0.035))
	_bake(_lid, _sphere_band(0.125, 0.006, -150.0, 0.0), _paint(CREAM.darkened(0.08), 0.7, 0.55, 24.0, 0.2, -0.3), _x(Vector3.ZERO))
	for s: float in [-1.0, 1.0]:
		_bake(_tilt, ProcMesh.cyl(0.018, 0.018, 0.012, 12), steel, _x(Vector3(0.128 * s, 0.0, EYE_C.z + 0.035), Vector3(0, 0, 90)))
	# Antenna whip with a little lamp, from the hood top-left.
	var ant: Node3D = _node(_body, Vector3(-0.14, 0.73, 0.08), Vector3(-8, 0, 10))
	_bake(ant, ProcMesh.cyl(0.016, 0.02, 0.03, 10), steel, _x(Vector3(0, 0.01, 0)))
	var spring: Array = []
	for k: int in 5:
		spring.append(ProcMesh.part(ProcMesh.torus(0.006, 0.011, 10, 4), _x(Vector3(0, 0.035 + k * 0.007, 0))))
	_bake_many(ant, spring, Mats.metal("steel"))
	_bake(ant, ProcMesh.cyl(0.0035, 0.005, 0.12, 6), Mats.metal("steel"), _x(Vector3(0, 0.12, 0)))
	_lamp_mat = Mats.lamp(Color(1.0, 0.45, 0.25), 1.2)
	_bake(ant, ProcMesh.sphere(0.02, 14, 8), _lamp_mat, _x(Vector3(0, 0.19, 0)))
	_bake(ant, ProcMesh.cyl(0.013, 0.016, 0.012, 10), steel, _x(Vector3(0, 0.172, 0)))
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0, 0.19, 0)
	_lamp_light.light_color = Color(1.0, 0.5, 0.3)
	_lamp_light.light_energy = 0.15
	_lamp_light.omni_range = 0.5
	ant.add_child(_lamp_light)
	_hose(_body, Vector3(0.1, 0.6, -0.14), Vector3(0.15, 0.68, -0.06), Vector3(0.1, 0.735, 0.0), 0.007)


func _build_ram() -> void:
	# Tiny compaction ram poking out of the lid: a short barrel, chrome rod and coral knob cap.
	var base := Vector3(0.0, 0.74, 0.06)
	_bake(_body, ProcMesh.cyl(0.06, 0.07, 0.025, 20), Mats.metal("dark_steel"), _x(base))
	_bake(_body, ProcMesh.cyl(0.042, 0.042, 0.06, 20), _paint(MUSTARD, 0.6, 0.6, 32.0, 0.2, -1.0), _x(base + Vector3(0, 0.04, 0)))
	_bake(_body, ProcMesh.cyl(0.047, 0.047, 0.012, 20), Mats.metal("dark_steel"), _x(base + Vector3(0, 0.07, 0)))
	_bolts(_body, [base + Vector3(0.055, 0.014, 0), base + Vector3(-0.055, 0.014, 0), base + Vector3(0, 0.014, 0.055), base + Vector3(0, 0.014, -0.055)], Vector3.UP, 0.007)
	_press_rod = _node(_body, base + Vector3(0, 0.076, 0))
	_bake(_press_rod, ProcMesh.cyl(0.014, 0.014, 0.08, 12), Mats.metal("chrome"), _x(Vector3(0, -0.02, 0)))
	_bake(_press_rod, ProcMesh.sphere(0.03, 16, 8), _paint(CORAL, 0.72, 0.5, 33.0, 0.2, -1.0), _x(Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.7, 1)))
	_hose(_body, Vector3(0.15, 0.73, 0.12), Vector3(0.1, 0.8, 0.1), Vector3(0.04, 0.78, 0.06), 0.008)


func _build_hatch() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var zb: float = 0.31
	# Frame and dark opening.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	_bake(_body, ProcMesh.rounded_box(Vector3(0.3, 0.24, 0.03), 0.04, 3), dark, _x(Vector3(0, 0.45, zb - 0.01), Vector3(TILT, 0, 0)))
	_bake(_body, ProcMesh.rounded_box(Vector3(0.34, 0.28, 0.02), 0.05, 3), steel, _x(Vector3(0, 0.45, zb - 0.02), Vector3(TILT, 0, 0)))
	# Door hinged along its top edge, swings up and back.
	_hatch = _node(_body, Vector3(0, 0.585, zb + 0.012))
	var door_mat: ShaderMaterial = _paint(MUSTARD, 0.62, 0.65, 42.0, 0.7, -0.7)
	_bake(_hatch, ProcMesh.rounded_box(Vector3(0.31, 0.25, 0.024), 0.045, 3), door_mat, _x(Vector3(0, -0.13, 0)))
	var ribs: Array = []
	for x: float in [-0.08, 0.08]:
		ribs.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.025, 0.2, 0.014), 0.006, 2), _x(Vector3(x, -0.13, 0.016))))
	_bake_many(_hatch, ribs, door_mat)
	_bake(_hatch, ProcMesh.box(Vector3(0.1, 0.02, 0.03)), steel, _x(Vector3(0, -0.235, 0.02)))   # latch handle
	_stencil(_hatch, "P-47CH", 40, Vector3(0, -0.11, 0.0125), Vector3(0, 0, 0), Color(0.12, 0.12, 0.1, 0.6))
	_stencil(_hatch, "BALE OUT", 22, Vector3(0, -0.165, 0.0125), Vector3.ZERO, Color(0.12, 0.12, 0.1, 0.5))
	_bake(_body, ProcMesh.cyl(0.012, 0.012, 0.3, 10), Mats.metal("steel"), _x(Vector3(0, 0.585, zb + 0.012), Vector3(0, 0, 90)))
	for s: float in [-1.0, 1.0]:
		_bake(_body, ProcMesh.cyl(0.016, 0.016, 0.03, 10), steel, _x(Vector3(0.16 * s, 0.585, zb + 0.012), Vector3(0, 0, 90)))
	# Little bale rack on top-rear.
	var rack: Array = []
	for s: float in [-1.0, 1.0]:
		rack.append(ProcMesh.part(ProcMesh.cyl(0.009, 0.009, 0.06, 6), _x(Vector3(0.13 * s, 0.76, 0.22))))
	rack.append(ProcMesh.part(ProcMesh.cyl(0.009, 0.009, 0.27, 6), _x(Vector3(0, 0.79, 0.22), Vector3(0, 0, 90))))
	_bake_many(_body, rack, Mats.metal("steel"))


func _build_arm() -> void:
	var mus: ShaderMaterial = _paint(MUSTARD, 0.6, 0.65, 50.0, 0.5, -0.7)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var shoulder_pos := Vector3(0.215, 0.47, -0.205)
	# Round coral shoulder disc on the right flank.
	_bake(_body, ProcMesh.cyl(0.06, 0.065, 0.025, 20), _paint(CORAL, 0.65, 0.6, 51.0, 0.4), _x(Vector3(0.2, 0.47, -0.185), Vector3(0, 45, 90)))
	var shoulder: Node3D = _node(_body, shoulder_pos)
	var yaw: Node3D = _node(shoulder, Vector3.ZERO)
	_bake(yaw, ProcMesh.sphere(0.042, 16, 8), steel, _x(Vector3.ZERO))
	var upper: Node3D = _node(yaw, Vector3.ZERO)
	_bake(upper, ProcMesh.capsule(0.032, L1 + 0.05), mus, _x(Vector3(0, 0, -L1 * 0.5), Vector3(90, 0, 0)))
	_hose(upper, Vector3(0.03, 0.02, -0.02), Vector3(0.05, 0.035, -L1 * 0.5), Vector3(0.03, 0.02, -L1 + 0.02), 0.007)
	var elbow: Node3D = _node(upper, Vector3(0, 0, -L1))
	_bake(elbow, ProcMesh.cyl(0.034, 0.034, 0.075, 14), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(elbow, ProcMesh.capsule(0.028, L2 + 0.04), mus, _x(Vector3(0, 0, -L2 * 0.5), Vector3(90, 0, 0)))
	var wrist: Node3D = _node(elbow, Vector3(0, 0, -L2))
	_bake(wrist, ProcMesh.cyl(0.03, 0.034, 0.03, 14), steel, _x(Vector3(0, 0, -0.008), Vector3(90, 0, 0)))
	_bake(wrist, ProcMesh.cyl(0.036, 0.036, 0.02, 14), _paint(CORAL, 0.65, 0.6, 52.0, 0.4), _x(Vector3(0, 0, -0.03), Vector3(90, 0, 0)))
	# Three-finger claw: rounded fingers with rubber tips, opening radially.
	var fingers: Array[Node3D] = []
	for k: int in 3:
		var root: Node3D = _node(wrist, Vector3(0, 0, -0.038))
		root.rotation.z = TAU * k / 3.0
		var hv: Node3D = _node(root, Vector3(0, 0.02, 0))
		var fp: Array = []
		fp.append(ProcMesh.part(ProcMesh.capsule(0.009, 0.06), _x(Vector3(0, 0.0, -0.028), Vector3(90, 0, 0))))
		fp.append(ProcMesh.part(ProcMesh.capsule(0.008, 0.045), _x(Vector3(0, -0.012, -0.068), Vector3(60, 0, 0))))
		_bake_many(hv, fp, steel)
		_bake(hv, ProcMesh.sphere(0.011, 10, 6), Mats.rubber(Color(0.1, 0.1, 0.1)), _x(Vector3(0, -0.024, -0.085)))
		fingers.append(hv)
	_arm = {"yaw": yaw, "upper": upper, "elbow": elbow, "wrist": wrist, "fingers": fingers}


# ---------------------------------------------------------------- animation

## Scoop keyframes: [t, shoulder pitch, forearm absolute pitch, claw absolute pitch, open 0..1, inward yaw].
const SCOOP_KEYS: Array = [
	[0.0, -40.0, -60.0, -75.0, 0.4, -4.0],
	[0.22, -60.0, -70.0, -85.0, 0.9, -6.0],
	[0.36, -60.0, -70.0, -85.0, 0.0, -6.0],
	[0.62, 40.0, -70.0, -80.0, 0.0, 60.0],
	[0.74, 40.0, -70.0, -80.0, 0.95, 60.0],
	[1.0, -40.0, -60.0, -75.0, 0.4, -4.0],
]
## Folded "little T-rex arm" rest pose.
const REST_POSE: Array = [0.0, -72.0, 45.0, -40.0, 0.15, -4.0]


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


func _update_arm() -> void:
	if _arm.is_empty():
		return
	var phase: float = _debug_phase if _debug_phase >= 0.0 else _scoop_phase
	var cyc: Array = _sample_scoop(fposmod(phase, 1.0))
	var amt: float = 1.0 if _debug_phase >= 0.0 else _scoop_amount
	var p: Array = []
	for j: int in REST_POSE.size():
		p.append(lerpf(float(REST_POSE[j]), float(cyc[j]), amt))
	var th1: float = p[1]
	var phi: float = p[2]
	var jaw: float = p[3]
	(_arm["yaw"] as Node3D).rotation.y = deg_to_rad(float(p[5]))
	(_arm["upper"] as Node3D).rotation.x = deg_to_rad(th1)
	(_arm["elbow"] as Node3D).rotation.x = deg_to_rad(phi - th1)
	(_arm["wrist"] as Node3D).rotation.x = deg_to_rad(jaw - phi)
	var open: float = deg_to_rad(-5.0 + float(p[4]) * 40.0)
	for f: Node3D in _arm["fingers"]:
		f.rotation.x = -open


func _process(delta: float) -> void:
	_time += delta
	_scoop_amount = move_toward(_scoop_amount, 1.0 if _scoop_hold > 0.0 else 0.0, delta * 3.0)
	if _scoop_amount > 0.0:
		_scoop_phase = fposmod(_scoop_phase + delta / 1.6, 1.0)
	_scoop_hold = maxf(0.0, _scoop_hold - delta)
	_update_arm()
	# Suspension.
	_dip = lerpf(_dip, _dip_target, clampf(delta * 10.0, 0.0, 1.0))
	_dip_target = move_toward(_dip_target, 0.0, delta * 0.2)
	var jitter := Vector3.ZERO
	if _shudder_t > 0.0:
		_shudder_t -= delta
		jitter = Vector3(sin(_time * 91.0), sin(_time * 117.0) * 0.6, sin(_time * 73.0)) * 0.003
	if sleeping:
		jitter = Vector3.ZERO
	_rig.position = Vector3(0, -_dip, 0) + jitter
	_rig.rotation = Vector3(_lean.x, 0, _lean.y)
	# Eye pod: pan toward target, tilt with mood, slump when sleeping.
	_look_yaw = lerp_angle(_look_yaw, _look_target, clampf(delta * 3.0, 0.0, 1.0))
	_pan.rotation.y = _look_yaw
	var tilt_target: float = deg_to_rad(-18.0) if sleeping else deg_to_rad(-4.0 + 8.0 * _iris_target + sin(_time * 0.7) * 1.5)
	_tilt_now = lerpf(_tilt_now, tilt_target, clampf(delta * 2.5, 0.0, 1.0))
	_tilt.rotation.x = _tilt_now
	_tilt.rotation.z = deg_to_rad(5.0 if not sleeping else 10.0) * (1.0 - 0.5 * _iris_now)
	# Aperture: blades slide outward as the iris opens.
	var ap: float = 0.0 if sleeping else _iris_target
	_iris_now = lerpf(_iris_now, ap, clampf(delta * 6.0, 0.0, 1.0))
	var r_ap: float = lerpf(0.008, 0.05, _iris_now)
	for b: Node3D in _blades:
		b.position = Vector3(0, r_ap, 0)
		b.rotation.z = lerpf(0.45, 0.12, _iris_now)
	_sensor_mat.emission_energy_multiplier = (0.05 if sleeping else 0.9 + 1.0 * _iris_now)
	# Eyelid: droops with low mood, nearly shut asleep, occasional blink.
	_blink_t -= delta
	var blink: float = 0.0
	if _blink_t < 0.0:
		blink = 1.0
		if _blink_t < -0.14:
			_blink_t = randf_range(2.5, 6.0)
	var lid_target: float = 150.0 if sleeping else lerpf(42.0, 12.0, _iris_target)
	if blink > 0.0 and not sleeping:
		lid_target = 165.0
	_lid_now = lerpf(_lid_now, lid_target, clampf(delta * (22.0 if blink > 0.0 else 5.0), 0.0, 1.0))
	_lid.rotation.x = -deg_to_rad(_lid_now)
	# Antenna lamp.
	_flash_t = maxf(0.0, _flash_t - delta * 2.5)
	var pulse: float = 0.6 + 0.3 * sin(_time * 2.4)
	if sleeping:
		pulse = 0.12 + 0.1 * maxf(0.0, sin(_time * 0.8))
	_lamp_mat.emission_energy_multiplier = pulse + _flash_t * 6.0
	_lamp_light.light_energy = 0.1 + _flash_t * 1.5
	_update_fill_leds()
	# Ram knob and hatch.
	_press_rod.position.y = 0.74 + 0.076 - _press_now * 0.05
	_hatch.rotation.x = -_hatch_now * deg_to_rad(105.0)


func _update_fill_leds() -> void:
	var lit: float = clampf(_fill_ratio / 1.0, 0.0, 1.15) * 5.0
	var over: bool = _fill_ratio > _fill_hi + 0.0001
	var in_band: bool = _fill_ratio >= _fill_lo
	for k: int in _fill_leds.size():
		var m: StandardMaterial3D = _fill_leds[k]
		var on: bool = lit > float(k) + 0.5
		if over:
			m.emission = Color(1.0, 0.18, 0.1)
			m.emission_energy_multiplier = 1.6 + 0.8 * sin(_time * 10.0)
		elif on:
			m.emission = Color(1.0, 0.65, 0.15) if in_band else Color(0.45, 0.85, 0.35)
			m.emission_energy_multiplier = 1.4
		else:
			m.emission = Color(0.45, 0.8, 0.35)
			m.emission_energy_multiplier = 0.05


# ---------------------------------------------------------------- interface

func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	_wheel_angle -= speed * delta / WHEEL_R
	for w: Node3D in _wheels:
		w.rotation.x = _wheel_angle
	var target_swivel: float = clampf(local_accel.x * 0.06, -0.8, 0.8) if absf(speed) > 0.05 else _caster_angle
	_caster_angle = lerp_angle(_caster_angle, target_swivel, clampf(delta * 5.0, 0.0, 1.0))
	_caster_swivel.rotation.y = _caster_angle
	_caster_wheel.rotation.x -= speed * delta / CASTER_R
	var target := Vector2(clampf(-local_accel.y * 0.004, -0.035, 0.035), clampf(local_accel.x * 0.004, -0.03, 0.03))
	target.x += 0.0 * speed_ratio
	_lean = _lean.lerp(target, clampf(delta * 4.0, 0.0, 1.0))


func set_scooping(active: bool) -> void:
	if active:
		_scoop_hold = 0.15


func set_fill(ratio: float, band: Array) -> void:
	_fill_ratio = ratio
	_fill_lo = float(band[0]) if band.size() > 0 else 0.7
	_fill_hi = float(band[1]) if band.size() > 1 else 1.0


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
	_look_target = clampf(atan2(-d.x, -d.z), -0.9, 0.9)


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
