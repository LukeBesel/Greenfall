class_name PatchModel
extends Node3D
## Patch (unit P-47CH), concept "Drum".
## An upright, rolled-steel compactor drum (a weathered municipal bin) on a three-wheel base: two
## drive wheels at the rear sides and a swivel caster up front. A one-lens sensor head on a short
## offset mast at the front-top pans and tilts; its aperture iris opens when Patch is content.
## Two small two-segment hydraulic arms with clamshell jaws pick up single pieces of litter (a can,
## a sheet of paper) and drop them into the open front trough. A vertical compaction ram stands on
## the lid, and strapped bales leave through the hinged hatch at the back.
## Faces -Z, base at y = 0. Real-world scale: about 1.3 m to the head, 1.1 m long.

const ORANGE := Color(0.66, 0.33, 0.12)       # faded municipal orange
const YELLOW := Color(0.74, 0.58, 0.16)       # safety yellow
const WHITE := Color(0.76, 0.74, 0.68)        # chipped utility white
const GREEN := Color(0.24, 0.31, 0.22)        # utility green (running gear)
const BLACK := Color(0.05, 0.05, 0.05)

const DRUM_R: float = 0.36
const DRUM_Z: float = 0.06
const DRUM_Y0: float = 0.27
const DRUM_Y1: float = 1.0
const WHEEL_R: float = 0.215
const CASTER_R: float = 0.085
const L1: float = 0.34
const L2: float = 0.40
const JAW_L: float = 0.13

## Interface: local anchor points used by the controller.
var chest_point := Vector3(0, 0.56, -0.42)
var back_hatch_point := Vector3(0, 0.47, 0.62)
var vent_points: Array[Vector3] = [Vector3(-0.39, 0.80, 0.14), Vector3(-0.17, 1.2, 0.27), Vector3(0.2, 1.08, 0.3)]
var stack_point := Vector3(0, 0.98, 0.66)
var lens_point := Vector3(-0.1, 1.23, -0.37)
var sleeping: bool = false

var _rig: Node3D            # sprung body (lean, dip, vibration)
var _pan: Node3D
var _tilt: Node3D
var _blades: Array[Node3D] = []
var _sensor_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _needle: Node3D
var _gauge_lamp_mat: StandardMaterial3D
var _wheels: Array[Node3D] = []
var _caster_swivel: Node3D
var _caster_wheel: Node3D
var _arms: Array[Dictionary] = []
var _rams: Array[Array] = []    # [barrel, rod, anchor_a, anchor_b]
var _press_rod: Node3D
var _press_cap: Node3D
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
var _iris_now: float = 0.55
var _iris_target: float = 0.55
var _flash_t: float = 0.0
var _fill_angle: float = 0.0
var _fill_target: float = 0.0
var _press_now: float = 0.0
var _hatch_now: float = 0.0
var _debug_phase: float = -1.0


func _ready() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_build_running_gear()
	_build_drum()
	_build_hopper()
	_build_head()
	_build_ram()
	_build_hatch()
	for s: float in [-1.0, 1.0]:
		_build_arm(s)
	# Debug poses for stills: DRUM_POSE="scoop:0.3,press:1,hatch:1"
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
	_update_arms(0.0)


# ---------------------------------------------------------------- helpers

func _paint(color: Color, coverage: float, rust: float, seed: float, grime: float = 0.5, floor_y: float = 0.0) -> ShaderMaterial:
	var m: ShaderMaterial = Mats.worn_paint(color, coverage, rust, seed, grime)
	m.set_shader_parameter("grime_floor", floor_y)
	m.set_shader_parameter("grime_height", 0.45)
	m.set_meta("cov", coverage)
	_paint_mats.append(m)
	return m


## Mesh instance with the transform baked into the vertices, so object space equals parent space
## (the worn-paint shader keys grime and wear on object-space height).
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


## Transform placing a Y-axis primitive between two points.
func _between(a: Vector3, b: Vector3) -> Transform3D:
	var d: Vector3 = b - a
	var q := Quaternion(Vector3.UP, d.normalized())
	return Transform3D(Basis(q), (a + b) * 0.5)


func _tube(r: float, a: Vector3, b: Vector3, segs: int = 10) -> Dictionary:
	return ProcMesh.part(ProcMesh.cyl(r, r, a.distance_to(b), segs), _between(a, b))


## Rubber hose along a quadratic bezier.
func _hose(parent: Node3D, p0: Vector3, p1: Vector3, p2: Vector3, r: float = 0.012) -> void:
	var parts: Array = []
	var n: int = 10
	var prev: Vector3 = p0
	for i: int in range(1, n + 1):
		var t: float = float(i) / n
		var p: Vector3 = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var d: Vector3 = p - prev
		parts.append(ProcMesh.part(ProcMesh.cyl(r, r, d.length() * 1.12, 8), _between(prev, p)))
		prev = p
	for e: Vector3 in [p0, p2]:
		parts.append(ProcMesh.part(ProcMesh.cyl(r * 1.5, r * 1.5, 0.03, 8), Transform3D(Basis.IDENTITY, e)))
	_bake_many(parent, parts, Mats.rubber())


## Hex bolt heads, axis along `normal`.
func _bolts(parent: Node3D, points: Array, normal: Vector3, size: float = 0.011) -> void:
	var parts: Array = []
	var q := Quaternion(Vector3.UP, normal.normalized())
	for p: Vector3 in points:
		parts.append(ProcMesh.part(ProcMesh.cyl(size, size, size * 0.9, 6), Transform3D(Basis(q), p)))
	_bake_many(parent, parts, Mats.metal("dark_steel"))


## Bolts around the drum circumference at height y.
func _drum_bolts(y: float, count: int, skip_front: bool = false) -> void:
	var parts: Array = []
	for i: int in count:
		var a: float = TAU * (i + 0.5) / count
		var dir := Vector3(sin(a), 0, cos(a))
		if skip_front and dir.z < -0.6:
			continue
		var p := Vector3(0, y, DRUM_Z) + dir * (DRUM_R + 0.004)
		var q := Quaternion(Vector3.UP, dir)
		parts.append(ProcMesh.part(ProcMesh.cyl(0.011, 0.011, 0.012, 6), Transform3D(Basis(q), p)))
	_bake_many(_rig, parts, Mats.metal("dark_steel"))


## Clip polygon (Vector2 list) against x in [-hw, hw].
func _clip_x(poly: Array, hw: float) -> Array:
	var out: Array = poly
	for side: float in [-1.0, 1.0]:
		var src: Array = out
		out = []
		for i: int in src.size():
			var a: Vector2 = src[i]
			var b: Vector2 = src[(i + 1) % src.size()]
			var ina: bool = a.x * side <= hw
			var inb: bool = b.x * side <= hw
			if ina:
				out.append(a)
			if ina != inb:
				var t: float = (hw * side - a.x) / (b.x - a.x)
				out.append(a.lerp(b, t))
	return out


## Black diagonal hazard stripes in the XY plane (facing -Z), clipped to w x h.
func _chevron_mesh(w: float, h: float, stripe: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = w * 0.5
	var hh: float = h * 0.5
	var x: float = -hw - h
	while x < hw + h:
		var poly: Array = [Vector2(x, -hh), Vector2(x + stripe, -hh), Vector2(x + stripe + h, hh), Vector2(x + h, hh)]
		poly = _clip_x(poly, hw)
		if poly.size() >= 3:
			for i: int in range(1, poly.size() - 1):
				var tri: Array = [poly[0], poly[i], poly[i + 1]]
				for k: int in [0, 1, 2]:
					st.set_normal(Vector3(0, 0, -1))
					st.add_vertex(Vector3(tri[k].x, tri[k].y, 0))
				for k: int in [0, 2, 1]:
					st.set_normal(Vector3(0, 0, 1))
					st.add_vertex(Vector3(tri[k].x, tri[k].y, 0))
		x += stripe * 2.0
	return st.commit()


func _stencil(parent: Node3D, text: String, size_px: int, pos: Vector3, rot_deg: Vector3, color: Color = Color(0.86, 0.83, 0.74, 0.62)) -> Label3D:
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
	var frame_mat: ShaderMaterial = _paint(GREEN, 0.55, 0.7, 3.3, 0.9)
	# Sub-frame: two longitudinal channels and a front nose plate carrying the caster.
	var parts: Array = []
	for s: float in [-1.0, 1.0]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.07, 0.09, 0.96)), _x(Vector3(0.2 * s, 0.235, -0.12))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.48, 0.05, 0.22)), _x(Vector3(0, 0.255, -0.5))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.48, 0.07, 0.07)), _x(Vector3(0, 0.235, 0.3))))
	_bake_many(_rig, parts, frame_mat)
	# Rear axle housing.
	_bake(self, ProcMesh.cyl(0.045, 0.045, 0.8, 14), steel, _x(Vector3(0, WHEEL_R, 0.2), Vector3(0, 0, 90)))
	_bake(self, ProcMesh.box(Vector3(0.22, 0.12, 0.16)), frame_mat, _x(Vector3(0, WHEEL_R, 0.2)))   # differential
	# Drive wheels: scaled real tyres on rusted rims.
	var tyre: Mesh = AssetLib.model_mesh("old_tyre")
	var rim: Mesh = AssetLib.model_mesh("rusted_wheel_rim_01")
	var tscale: float = WHEEL_R * 2.0 / 0.6
	for s: float in [-1.0, 1.0]:
		var hub: Node3D = _node(self, Vector3(0.45 * s, WHEEL_R, 0.2))
		var spin: Node3D = _node(hub, Vector3.ZERO)
		var t := MeshInstance3D.new()
		t.mesh = tyre
		t.rotation_degrees = Vector3(0, 90, 0)
		t.scale = Vector3(tscale, tscale, 1.05)
		spin.add_child(t)
		var r := MeshInstance3D.new()
		r.mesh = rim
		r.rotation_degrees = Vector3(0, 90, 0)
		r.scale = Vector3(0.6, 0.6, 0.8)
		spin.add_child(r)
		# Hub cap and wheel nuts.
		var hc: MeshInstance3D = _bake(spin, ProcMesh.cyl(0.05, 0.06, 0.05, 14), steel, _x(Vector3(0.07 * s, 0, 0), Vector3(0, 0, 90)))
		hc.name = "Hub"
		var nuts: Array = []
		for k: int in 5:
			var a: float = TAU * k / 5.0
			nuts.append(Vector3(0.09 * s, cos(a) * 0.075, sin(a) * 0.075))
		_bolts(spin, nuts, Vector3(s, 0, 0), 0.012)
		_wheels.append(spin)
		# Mudguard: a curved steel arc over the tyre, bracketed to the frame.
		var gparts: Array = []
		for k: int in 9:
			var a0: float = deg_to_rad(-5.0 + k * 19.0)
			var a1: float = deg_to_rad(-5.0 + (k + 1) * 19.0)
			var rr: float = WHEEL_R + 0.045
			var p0 := Vector3(0.45 * s, WHEEL_R + sin(a0) * rr, 0.2 + cos(a0) * rr)
			var p1 := Vector3(0.45 * s, WHEEL_R + sin(a1) * rr, 0.2 + cos(a1) * rr)
			var mid: Vector3 = (p0 + p1) * 0.5
			var tang: Vector3 = (p1 - p0).normalized()
			var b := Basis(Vector3(1, 0, 0), tang.cross(Vector3(1, 0, 0)).normalized() * -1.0, tang)
			gparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.13, 0.01, p0.distance_to(p1) * 1.08)), Transform3D(b.orthonormalized(), mid)))
		_bake_many(_rig, gparts, _paint(GREEN, 0.5, 0.75, 7.0 + s, 0.8))
		_bake(_rig, ProcMesh.box(Vector3(0.12, 0.03, 0.05)), steel, _x(Vector3(0.34 * s, 0.47, 0.2)))
	# Front swivel caster.
	_caster_swivel = _node(_rig, Vector3(0, 0.23, -0.52))
	_bake(_caster_swivel, ProcMesh.cyl(0.045, 0.05, 0.05, 14), steel, _x(Vector3(0, 0.0, 0)))
	var fork: Array = []
	for s: float in [-1.0, 1.0]:
		fork.append(ProcMesh.part(ProcMesh.box(Vector3(0.012, 0.16, 0.05)), _x(Vector3(0.05 * s, -0.08, 0.04), Vector3(-14, 0, 0))))
	fork.append(ProcMesh.part(ProcMesh.box(Vector3(0.11, 0.02, 0.06)), _x(Vector3(0, -0.02, 0.01))))
	_bake_many(_caster_swivel, fork, _paint(GREEN, 0.5, 0.7, 5.1, 0.8, -0.2))
	_caster_wheel = _node(_caster_swivel, Vector3(0, CASTER_R - 0.23, 0.06))
	_bake(_caster_wheel, ProcMesh.cyl(CASTER_R, CASTER_R, 0.06, 18), Mats.rubber(Color(0.05, 0.05, 0.05)), _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(_caster_wheel, ProcMesh.cyl(0.045, 0.045, 0.066, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(_caster_wheel, ProcMesh.cyl(0.012, 0.012, 0.12, 6), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))


func _build_drum() -> void:
	var c := Vector3(0, 0, DRUM_Z)
	var drum_mat: ShaderMaterial = _paint(ORANGE, 0.62, 0.65, 1.7, 0.75)
	var h: float = DRUM_Y1 - DRUM_Y0
	_bake(_rig, ProcMesh.cyl(DRUM_R, DRUM_R - 0.01, h, 40), drum_mat, _x(c + Vector3(0, DRUM_Y0 + h * 0.5, 0)))
	# Domed lid with a rolled rim.
	var lid_mat: ShaderMaterial = _paint(ORANGE.lightened(0.04), 0.55, 0.7, 2.9, 0.3)
	_bake(_rig, ProcMesh.sphere(DRUM_R + 0.006, 40, 14), lid_mat, _x(c + Vector3(0, DRUM_Y1 - 0.01, 0), Vector3.ZERO, Vector3(1, 0.17, 1)))
	var rim: Array = []
	for y: float in [DRUM_Y1, 0.70, 0.42, DRUM_Y0 + 0.02]:
		rim.append(ProcMesh.part(ProcMesh.torus(DRUM_R - 0.012, DRUM_R + 0.016, 48, 8), _x(c + Vector3(0, y, 0))))
	_bake_many(_rig, rim, _paint(ORANGE.darkened(0.2), 0.45, 0.8, 4.4, 0.8))
	# Base skirt (darker, heavily grimed).
	_bake(_rig, ProcMesh.cyl(DRUM_R + 0.012, DRUM_R + 0.02, 0.06, 40), _paint(GREEN.darkened(0.2), 0.4, 0.85, 6.6, 1.0), _x(c + Vector3(0, DRUM_Y0 + 0.02, 0)))
	_drum_bolts(DRUM_Y1 - 0.02, 28)
	_drum_bolts(0.70, 24, true)
	_drum_bolts(0.42, 24, true)
	# Vertical weld seam on the left-rear.
	var seam_dir := Vector3(sin(deg_to_rad(-140.0)), 0, cos(deg_to_rad(-140.0)))
	_bake(_rig, ProcMesh.box(Vector3(0.014, h - 0.06, 0.01)), Mats.metal("dark_steel"),
		Transform3D(Basis(Vector3.UP, deg_to_rad(-140.0)), c + seam_dir * DRUM_R + Vector3(0, DRUM_Y0 + h * 0.5, 0)))
	# Faded serial stencil on the right flank and a smaller one on the back.
	var a: float = deg_to_rad(80.0)
	var pr: Vector3 = c + Vector3(sin(a), 0, cos(a)) * (DRUM_R + 0.004)
	_stencil(_rig, "P-47CH", 110, pr + Vector3(0, 0.56, 0), Vector3(0, 80, 0))
	_stencil(_rig, "MUNICIPAL SANITATION", 30, pr + Vector3(0, 0.49, 0), Vector3(0, 80, 0), Color(0.84, 0.8, 0.7, 0.45))
	var al: float = deg_to_rad(-80.0)
	var pl: Vector3 = c + Vector3(sin(al), 0, cos(al)) * (DRUM_R + 0.004)
	_stencil(_rig, "P-47CH", 110, pl + Vector3(0, 0.56, 0), Vector3(0, -80, 0))
	# Side louvre vent box (left) with hydraulic relief.
	var vent: Node3D = _node(_rig, c + Vector3(-DRUM_R - 0.01, 0.8, 0.08), Vector3(0, -90, 0))
	_bake(vent, ProcMesh.rounded_box(Vector3(0.2, 0.16, 0.05), 0.01, 2), _paint(WHITE.darkened(0.25), 0.5, 0.6, 8.8, 0.3, -0.8))
	var lv: Array = []
	for k: int in 5:
		lv.append(ProcMesh.part(ProcMesh.box(Vector3(0.17, 0.012, 0.03)), _x(Vector3(0, -0.055 + k * 0.027, -0.03), Vector3(35, 0, 0))))
	_bake_many(vent, lv, Mats.metal("dark_steel"))
	# Exhaust stub on the lid, rear-left.
	_bake(_rig, ProcMesh.cyl(0.03, 0.035, 0.16, 12), Mats.metal("dark_steel"), _x(Vector3(-0.17, 1.1, 0.27)))
	_bake(_rig, ProcMesh.torus(0.026, 0.036, 12, 6), Mats.metal("steel"), _x(Vector3(-0.17, 1.18, 0.27)))
	# Fill gauge: analog dial on the front-right of the drum, above the intake.
	var ga: float = deg_to_rad(155.0)
	var gp: Vector3 = c + Vector3(sin(ga), 0, cos(ga)) * (DRUM_R + 0.01) + Vector3(0, 0.865, 0)
	var g: Node3D = _node(_rig, gp, Vector3(0, rad_to_deg(ga) + 180.0, 0))
	_bake(g, ProcMesh.cyl(0.062, 0.066, 0.03, 24), Mats.metal("dark_steel"), _x(Vector3(0, 0, -0.005), Vector3(90, 0, 0)))
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.82, 0.8, 0.72)
	face.roughness = 0.7
	_bake(g, ProcMesh.cyl(0.052, 0.052, 0.006, 24), face, _x(Vector3(0, 0, -0.019), Vector3(90, 0, 0)))
	var ticks: Array = []
	for k: int in 9:
		var ta: float = deg_to_rad(-120.0 + k * 30.0)
		ticks.append(ProcMesh.part(ProcMesh.box(Vector3(0.003, 0.012, 0.002)), Transform3D(Basis(Vector3(0, 0, -1), ta), Vector3(sin(ta) * 0.04, cos(ta) * 0.04, -0.023))))
	var tick_mat := StandardMaterial3D.new()
	tick_mat.albedo_color = Color(0.08, 0.08, 0.08)
	_bake_many(g, ticks, tick_mat)
	var red_zone := StandardMaterial3D.new()
	red_zone.albedo_color = Color(0.55, 0.12, 0.08)
	var rz: Array = []
	for k: int in 4:
		var ta: float = deg_to_rad(95.0 + k * 8.0)
		rz.append(ProcMesh.part(ProcMesh.box(Vector3(0.012, 0.006, 0.002)), Transform3D(Basis(Vector3(0, 0, -1), ta + PI * 0.5), Vector3(sin(ta) * 0.046, cos(ta) * 0.046, -0.023))))
	_bake_many(g, rz, red_zone)
	_needle = _node(g, Vector3(0, 0, -0.026))
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.1, 0.1, 0.1)
	_bake(_needle, ProcMesh.box(Vector3(0.004, 0.045, 0.002)), nm, _x(Vector3(0, 0.018, 0)))
	_bake(_needle, ProcMesh.cyl(0.006, 0.006, 0.006, 8), Mats.metal("brass"), _x(Vector3.ZERO, Vector3(90, 0, 0)))
	_bake(g, ProcMesh.cyl(0.054, 0.054, 0.004, 24), Mats.glass(Color(0.6, 0.65, 0.65, 0.18), 0.1), _x(Vector3(0, 0, -0.03), Vector3(90, 0, 0)))
	# Indicator lamp beside the dial.
	_gauge_lamp_mat = Mats.lamp(Color(0.45, 0.8, 0.35), 0.6)
	_bake(g, ProcMesh.hemisphere(0.016, 12, 4), _gauge_lamp_mat, _x(Vector3(-0.09, -0.02, -0.012), Vector3(-90, 0, 0)))
	_bake(g, ProcMesh.cyl(0.022, 0.022, 0.016, 12), Mats.metal("dark_steel"), _x(Vector3(-0.09, -0.02, -0.004), Vector3(90, 0, 0)))


func _build_hopper() -> void:
	var yel: ShaderMaterial = _paint(YELLOW, 0.6, 0.6, 11.0, 0.7)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	# Throat: a framed rectangular opening in the drum front with a rubber curtain.
	_bake(_rig, ProcMesh.box(Vector3(0.6, 0.38, 0.14)), _paint(ORANGE.darkened(0.25), 0.5, 0.7, 12.0, 0.6), _x(Vector3(0, 0.6, -0.25)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	dark.roughness = 1.0
	_bake(_rig, ProcMesh.box(Vector3(0.52, 0.3, 0.01)), dark, _x(Vector3(0, 0.59, -0.323)))
	var flaps: Array = []
	for k: int in 7:
		var x: float = -0.22 + k * 0.0733
		flaps.append(ProcMesh.part(ProcMesh.box(Vector3(0.068, 0.27, 0.008)), _x(Vector3(x, 0.6, -0.332), Vector3(randf_range(-3, 3), 0, 0))))
	_bake_many(_rig, flaps, Mats.rubber(Color(0.07, 0.07, 0.065)))
	_bake(_rig, ProcMesh.box(Vector3(0.6, 0.035, 0.03)), steel, _x(Vector3(0, 0.76, -0.33)))   # curtain rail
	_bolts(_rig, [Vector3(-0.26, 0.76, -0.348), Vector3(-0.09, 0.76, -0.348), Vector3(0.09, 0.76, -0.348), Vector3(0.26, 0.76, -0.348)], Vector3(0, 0, -1), 0.01)
	# Trough: floor sloping down into the throat, two side cheeks, front lip.
	var tr: Array = []
	tr.append(ProcMesh.part(ProcMesh.box(Vector3(0.6, 0.02, 0.32)), _x(Vector3(0, 0.425, -0.47), Vector3(-6, 0, 0))))
	for s: float in [-1.0, 1.0]:
		# cheek: trapezoid approximated by a box with a slanted top cap
		tr.append(ProcMesh.part(ProcMesh.box(Vector3(0.022, 0.2, 0.36)), _x(Vector3(0.3 * s, 0.5, -0.46))))
		tr.append(ProcMesh.part(ProcMesh.box(Vector3(0.022, 0.16, 0.2)), _x(Vector3(0.3 * s, 0.63, -0.38), Vector3(-28, 0, 0))))
		tr.append(ProcMesh.part(ProcMesh.box(Vector3(0.034, 0.022, 0.43)), _x(Vector3(0.3 * s, 0.645, -0.43), Vector3(-24, 0, 0))))   # rolled top edge
	tr.append(ProcMesh.part(ProcMesh.box(Vector3(0.62, 0.13, 0.022)), _x(Vector3(0, 0.47, -0.635), Vector3(-10, 0, 0))))
	tr.append(ProcMesh.part(ProcMesh.cyl(0.016, 0.016, 0.63, 10), _x(Vector3(0, 0.535, -0.645), Vector3(0, 0, 90))))   # rolled lip
	_bake_many(_rig, tr, yel)
	# Hazard chevrons on the front lip.
	var chev := MeshInstance3D.new()
	chev.mesh = _chevron_mesh(0.58, 0.085, 0.045)
	chev.material_override = _paint(BLACK, 0.7, 0.5, 13.0, 0.6, -0.45)
	chev.transform = _x(Vector3(0, 0.475, -0.6475), Vector3(-10, 0, 0))
	_rig.add_child(chev)
	# Wear strip under the lip and gussets to the frame.
	_bake(_rig, ProcMesh.box(Vector3(0.62, 0.03, 0.05)), steel, _x(Vector3(0, 0.405, -0.62)))
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.box(Vector3(0.02, 0.14, 0.1)), steel, _x(Vector3(0.18 * s, 0.33, -0.56), Vector3(30, 0, 0)))
	_bolts(_rig, [Vector3(-0.311, 0.47, -0.58), Vector3(-0.311, 0.47, -0.35), Vector3(0.311, 0.47, -0.58), Vector3(0.311, 0.47, -0.35)], Vector3(1, 0, 0), 0.01)
	_stencil(_rig, "KEEP HANDS CLEAR", 26, Vector3(0.312, 0.5, -0.47), Vector3(0, 90, 0), Color(0.08, 0.08, 0.07, 0.7))


func _build_head() -> void:
	var white: ShaderMaterial = _paint(WHITE, 0.72, 0.55, 21.0, 0.15, -0.3)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var base := Vector3(-0.1, DRUM_Y1 + 0.04, -0.17)
	# Mast: a short steel post with a gusset plate, offset to Patch's right.
	_bake(_rig, ProcMesh.cyl(0.05, 0.065, 0.04, 16), steel, _x(base + Vector3(0, -0.0, 0)))
	_bake(_rig, ProcMesh.cyl(0.03, 0.03, 0.1, 12), Mats.metal("steel"), _x(base + Vector3(0, 0.06, 0)))
	_pan = _node(_rig, base + Vector3(0, 0.11, 0))
	_bake(_pan, ProcMesh.cyl(0.05, 0.05, 0.03, 16), _paint(GREEN, 0.5, 0.7, 22.0, 0.3, -1.0), _x(Vector3.ZERO))
	# Tilt yoke.
	var yoke: Array = []
	for s: float in [-1.0, 1.0]:
		yoke.append(ProcMesh.part(ProcMesh.box(Vector3(0.012, 0.09, 0.05)), _x(Vector3(0.137 * s, 0.05, 0))))
	yoke.append(ProcMesh.part(ProcMesh.box(Vector3(0.286, 0.014, 0.05)), _x(Vector3(0, 0.012, 0))))
	_bake_many(_pan, yoke, _paint(GREEN, 0.5, 0.7, 23.0, 0.3, -1.0))
	_tilt = _node(_pan, Vector3(0, 0.085, 0))
	_bolts(_pan, [Vector3(-0.145, 0.08, 0), Vector3(0.145, 0.08, 0)], Vector3(1, 0, 0), 0.016)
	# Housing: a rounded sheet-metal box, slightly taller at the back.
	_bake(_tilt, ProcMesh.rounded_box(Vector3(0.25, 0.17, 0.22), 0.045, 4), white, _x(Vector3(0, 0.0, 0.0)))
	_bake(_tilt, ProcMesh.box(Vector3(0.258, 0.012, 0.228)), steel, _x(Vector3(0, -0.04, 0)))   # seam band
	# Sun visor.
	_bake(_tilt, ProcMesh.box(Vector3(0.15, 0.006, 0.045)), steel, _x(Vector3(0, 0.072, -0.118), Vector3(-12, 0, 0)))
	# Rear access plate with screws.
	_bake(_tilt, ProcMesh.box(Vector3(0.14, 0.09, 0.006)), _paint(WHITE.darkened(0.15), 0.6, 0.6, 24.0, 0.1, -0.3), _x(Vector3(0, 0, 0.111)))
	_bolts(_tilt, [Vector3(-0.06, 0.035, 0.115), Vector3(0.06, 0.035, 0.115), Vector3(-0.06, -0.035, 0.115), Vector3(0.06, -0.035, 0.115)], Vector3(0, 0, 1), 0.006)
	# Lens: a stepped steel barrel with an 8-blade aperture behind glass.
	var lens: Node3D = _node(_tilt, Vector3(0, -0.005, -0.108))
	lens.scale = Vector3.ONE * 1.12
	_bake(lens, ProcMesh.cyl(0.07, 0.074, 0.02, 32), steel, _x(Vector3(0, 0, -0.005), Vector3(90, 0, 0)))
	var tube: CylinderMesh = ProcMesh.cyl(0.062, 0.066, 0.045, 32)
	tube.cap_top = false
	tube.cap_bottom = false
	_bake(lens, tube, _paint(WHITE.darkened(0.1), 0.6, 0.5, 25.0, 0.1, 1.0), _x(Vector3(0, 0, -0.035), Vector3(90, 0, 0)))
	var sleeve: CylinderMesh = ProcMesh.cyl(0.0605, 0.0605, 0.045, 32)
	sleeve.cap_top = false
	sleeve.cap_bottom = false
	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.03, 0.03, 0.03)
	sleeve_mat.roughness = 0.6
	sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bake(lens, sleeve, sleeve_mat, _x(Vector3(0, 0, -0.035), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.torus(0.05, 0.064, 32, 8), steel, _x(Vector3(0, 0, -0.058), Vector3(90, 0, 0)))
	var knurl: Array = []
	for k: int in 24:
		var a: float = TAU * k / 24.0
		knurl.append(ProcMesh.part(ProcMesh.box(Vector3(0.006, 0.006, 0.03)), _x(Vector3(cos(a) * 0.066, sin(a) * 0.066, -0.035))))
	_bake_many(lens, knurl, steel)
	# Sensor element (dim warm glow seen through the aperture).
	_sensor_mat = Mats.lamp(Color(1.0, 0.66, 0.3), 1.0)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.01, 0.01, 0.012)
	back_mat.roughness = 0.3
	_bake(lens, ProcMesh.cyl(0.052, 0.052, 0.004, 32), back_mat, _x(Vector3(0, 0, -0.03), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.cyl(0.03, 0.03, 0.004, 24), _sensor_mat, _x(Vector3(0, 0, -0.033), Vector3(90, 0, 0)))
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.32, 0.31, 0.3)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.38
	for k: int in 8:
		var piv: Node3D = _node(lens, Vector3(0, 0, -0.038 - k * 0.0007))
		piv.rotation.z = TAU * k / 8.0
		var arm: Node3D = _node(piv, Vector3.ZERO)
		_bake(arm, ProcMesh.box(Vector3(0.036, 0.032, 0.0012)), blade_mat, _x(Vector3(0.006, 0.016, 0)))
		_blades.append(arm)
	var glass_mat: StandardMaterial3D = Mats.glass(Color(0.45, 0.5, 0.55, 0.07), 0.04)
	glass_mat.metallic = 0.0
	_bake(lens, ProcMesh.cyl(0.054, 0.054, 0.003, 32), glass_mat, _x(Vector3(0, 0, -0.054), Vector3(90, 0, 0)))
	# Antenna whip with a caged amber lamp.
	var ant: Node3D = _node(_tilt, Vector3(0.085, 0.085, 0.06), Vector3(-6, 0, -8))
	_bake(ant, ProcMesh.cyl(0.018, 0.022, 0.025, 10), steel, _x(Vector3(0, 0.01, 0)))
	_bake(ant, ProcMesh.cyl(0.004, 0.006, 0.17, 6), Mats.metal("steel"), _x(Vector3(0, 0.1, 0)))
	_lamp_mat = Mats.lamp(Color(1.0, 0.62, 0.22), 1.2)
	_bake(ant, ProcMesh.sphere(0.017, 12, 6), _lamp_mat, _x(Vector3(0, 0.2, 0)))
	var cage: Array = []
	for k: int in 3:
		var a: float = TAU * k / 3.0
		cage.append(ProcMesh.part(ProcMesh.cyl(0.0022, 0.0022, 0.05, 4), _x(Vector3(cos(a) * 0.021, 0.2, sin(a) * 0.021))))
	cage.append(ProcMesh.part(ProcMesh.torus(0.018, 0.024, 12, 4), _x(Vector3(0, 0.178, 0))))
	cage.append(ProcMesh.part(ProcMesh.cyl(0.024, 0.024, 0.006, 10), _x(Vector3(0, 0.226, 0))))
	_bake_many(ant, cage, steel)
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(0, 0.2, 0)
	_lamp_light.light_color = Color(1.0, 0.62, 0.25)
	_lamp_light.light_energy = 0.15
	_lamp_light.omni_range = 0.6
	ant.add_child(_lamp_light)
	# Cable from head to mast.
	_hose(_rig, base + Vector3(0.06, 0.02, 0.05), base + Vector3(0.12, 0.08, 0.1), base + Vector3(0.05, 0.16, 0.1), 0.007)
	_stencil(_tilt, "P-47CH", 26, Vector3(0.126, -0.005, 0.02), Vector3(0, 90, 0), Color(0.12, 0.12, 0.11, 0.6))


func _build_ram() -> void:
	# Vertical compaction cylinder on the lid, rear-centre, on a trunnion frame.
	var base := Vector3(0.05, DRUM_Y1 + 0.03, 0.14)
	var frame_mat: ShaderMaterial = _paint(GREEN, 0.5, 0.7, 31.0, 0.3, -1.0)
	var fr: Array = []
	fr.append(ProcMesh.part(ProcMesh.cyl(0.11, 0.12, 0.04, 20), _x(base + Vector3(0, 0.02, 0))))
	for s: float in [-1.0, 1.0]:
		fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.018, 0.13, 0.07)), _x(base + Vector3(0.09 * s, 0.1, 0))))
	_bake_many(_rig, fr, frame_mat)
	var barrel: ShaderMaterial = _paint(YELLOW.darkened(0.1), 0.55, 0.6, 32.0, 0.2, -1.0)
	_bake(_rig, ProcMesh.cyl(0.064, 0.064, 0.15, 20), barrel, _x(base + Vector3(0, 0.12, 0)))
	_bake(_rig, ProcMesh.cyl(0.072, 0.072, 0.025, 20), Mats.metal("dark_steel"), _x(base + Vector3(0, 0.05, 0)))
	_bake(_rig, ProcMesh.cyl(0.072, 0.072, 0.025, 20), Mats.metal("dark_steel"), _x(base + Vector3(0, 0.2, 0)))
	var tie: Array = []
	for k: int in 4:
		var a: float = TAU * (k + 0.5) / 4.0
		tie.append(ProcMesh.part(ProcMesh.cyl(0.006, 0.006, 0.16, 6), _x(base + Vector3(cos(a) * 0.072, 0.125, sin(a) * 0.072))))
	_bake_many(_rig, tie, Mats.metal("steel"))
	_bolts(_rig, [base + Vector3(-0.1, 0.1, 0), base + Vector3(0.1, 0.1, 0)], Vector3(1, 0, 0), 0.016)
	# Tail rod: sinks into the cylinder as the ram presses down inside the drum.
	_press_rod = _node(_rig, base + Vector3(0, 0.213, 0))
	_bake(_press_rod, ProcMesh.cyl(0.022, 0.022, 0.16, 14), Mats.metal("chrome"), _x(Vector3(0, -0.05, 0)))
	_press_cap = _node(_press_rod, Vector3(0, 0.03, 0))
	_bake(_press_cap, ProcMesh.cyl(0.034, 0.034, 0.03, 14), Mats.metal("dark_steel"), _x(Vector3.ZERO))
	_bake(_press_cap, ProcMesh.cyl(0.018, 0.018, 0.04, 6), Mats.metal("dark_steel"), _x(Vector3(0, 0.02, 0), Vector3(0, 0, 90)))
	# Hydraulic lines from the pump block to the cylinder ports.
	_bake(_rig, ProcMesh.rounded_box(Vector3(0.12, 0.07, 0.1), 0.01, 2), Mats.metal("dark_steel"), _x(Vector3(0.22, DRUM_Y1 + 0.06, 0.18)))
	_hose(_rig, Vector3(0.2, DRUM_Y1 + 0.09, 0.15), Vector3(0.14, 1.16, 0.12), Vector3(0.115, 1.17, 0.14), 0.011)
	_hose(_rig, Vector3(0.24, DRUM_Y1 + 0.09, 0.2), Vector3(0.18, 1.06, 0.12), Vector3(0.115, 1.09, 0.14), 0.011)
	_bake(_rig, ProcMesh.cyl(0.016, 0.02, 0.05, 8), Mats.metal("brass"), _x(Vector3(0.25, DRUM_Y1 + 0.11, 0.2)))   # relief valve


func _build_hatch() -> void:
	var c := Vector3(0, 0, DRUM_Z)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	# Bale chute: a squared box out of the drum back.
	_bake(_rig, ProcMesh.box(Vector3(0.5, 0.42, 0.24)), _paint(ORANGE.darkened(0.18), 0.55, 0.7, 41.0, 0.8), _x(c + Vector3(0, 0.5, 0.37)))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.02)
	_bake(_rig, ProcMesh.box(Vector3(0.42, 0.34, 0.01)), dark, _x(c + Vector3(0, 0.49, 0.486)))
	var fr: Array = []
	for s: float in [-1.0, 1.0]:
		fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.04, 0.44, 0.03)), _x(c + Vector3(0.245 * s, 0.5, 0.49))))
	fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.53, 0.04, 0.03)), _x(c + Vector3(0, 0.71, 0.49))))
	fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.53, 0.04, 0.05)), _x(c + Vector3(0, 0.29, 0.49))))
	_bake_many(_rig, fr, steel)
	# Hinged door (hinge at the top, swings up and back).
	_hatch = _node(_rig, c + Vector3(0, 0.705, 0.51))
	var door_mat: ShaderMaterial = _paint(YELLOW, 0.55, 0.65, 42.0, 0.7, -0.7)
	_bake(_hatch, ProcMesh.box(Vector3(0.46, 0.4, 0.025)), door_mat, _x(Vector3(0, -0.2, 0)))
	var ribs: Array = []
	for x: float in [-0.12, 0.12]:
		ribs.append(ProcMesh.part(ProcMesh.box(Vector3(0.03, 0.36, 0.02)), _x(Vector3(x, -0.2, 0.02))))
	ribs.append(ProcMesh.part(ProcMesh.box(Vector3(0.4, 0.03, 0.02)), _x(Vector3(0, -0.36, 0.02))))
	_bake_many(_hatch, ribs, door_mat)
	var chev := MeshInstance3D.new()
	chev.mesh = _chevron_mesh(0.4, 0.06, 0.04)
	chev.material_override = _paint(BLACK, 0.7, 0.5, 43.0, 0.6, -0.7)
	chev.transform = _x(Vector3(0, -0.36, 0.0315), Vector3(0, 180, 0))
	_hatch.add_child(chev)
	_stencil(_hatch, "BALE EJECT", 34, Vector3(0, -0.12, 0.031), Vector3.ZERO, Color(0.1, 0.1, 0.09, 0.7))
	_stencil(_hatch, "STAND CLEAR", 26, Vector3(0, -0.17, 0.031), Vector3.ZERO, Color(0.1, 0.1, 0.09, 0.6))
	_stencil(_hatch, "P-47CH", 30, Vector3(0, -0.25, 0.031), Vector3.ZERO, Color(0.1, 0.1, 0.09, 0.55))
	_bake(_rig, ProcMesh.cyl(0.016, 0.016, 0.5, 10), Mats.metal("steel"), _x(c + Vector3(0, 0.705, 0.51), Vector3(0, 0, 90)))   # hinge pin
	# Ejector rams either side of the chute.
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.cyl(0.024, 0.024, 0.2, 12), _paint(GREEN, 0.5, 0.7, 44.0 + s, 0.6), _x(c + Vector3(0.27 * s, 0.45, 0.36), Vector3(90, 0, 0)))
		_bake(_rig, ProcMesh.cyl(0.011, 0.011, 0.1, 8), Mats.metal("chrome"), _x(c + Vector3(0.27 * s, 0.45, 0.5), Vector3(90, 0, 0)))
	# Carry rack above the chute (where finished bales ride).
	var rack: Array = []
	for s: float in [-1.0, 1.0]:
		rack.append(_tube(0.013, Vector3(0.18 * s, 0.93, 0.36), Vector3(0.18 * s, 0.93, 0.8)))
		rack.append(_tube(0.013, Vector3(0.18 * s, 0.93, 0.8), Vector3(0.18 * s, 1.02, 0.82)))
		rack.append(_tube(0.011, Vector3(0.18 * s, 0.93, 0.62), Vector3(0.18 * s, 0.79, 0.43)))
	rack.append(_tube(0.013, Vector3(-0.18, 1.02, 0.82), Vector3(0.18, 1.02, 0.82)))
	rack.append(_tube(0.011, Vector3(-0.18, 0.93, 0.6), Vector3(0.18, 0.93, 0.6)))
	_bake_many(_rig, rack, _paint(GREEN, 0.45, 0.75, 45.0, 0.4))


func _build_arm(s: float) -> void:
	var yel: ShaderMaterial = _paint(YELLOW, 0.55, 0.65, 50.0 + s * 3.0, 0.5, -0.7)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	var shoulder_pos := Vector3(0.355 * s, 0.73, -0.25)
	# Shoulder bracket bolted to the trough cheek and drum.
	_bake(_rig, ProcMesh.box(Vector3(0.03, 0.16, 0.16)), steel, _x(Vector3(0.325 * s, 0.68, -0.24)))
	_bolts(_rig, [Vector3(0.341 * s, 0.63, -0.29), Vector3(0.341 * s, 0.63, -0.19)], Vector3(s, 0, 0), 0.009)
	var shoulder: Node3D = _node(_rig, shoulder_pos)
	var yaw: Node3D = _node(shoulder, Vector3.ZERO)
	_bake(yaw, ProcMesh.cyl(0.04, 0.04, 0.07, 14), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	var upper: Node3D = _node(yaw, Vector3.ZERO)
	# Upper arm: twin side plates (a fabricated boom) with a pin at each end.
	var up: Array = []
	up.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.05, 0.06, L1 + 0.04), 0.012, 2), _x(Vector3(0, 0, -L1 * 0.5))))
	_bake_many(upper, up, yel)
	_bake(upper, ProcMesh.cyl(0.013, 0.013, 0.08, 8), Mats.metal("steel"), _x(Vector3(0, 0, -L1), Vector3(0, 0, 90)))
	_bake(upper, ProcMesh.box(Vector3(0.03, 0.035, 0.05)), steel, _x(Vector3(0, 0.045, -0.08)))   # ram lug
	_hose(upper, Vector3(0.03 * s, 0.035, -0.02), Vector3(0.04 * s, 0.06, -L1 * 0.5), Vector3(0.03 * s, 0.03, -L1 + 0.02), 0.008)
	var elbow: Node3D = _node(upper, Vector3(0, 0, -L1))
	var fore: Array = []
	fore.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.042, 0.05, L2 + 0.03), 0.01, 2), _x(Vector3(0, 0, -L2 * 0.5 + 0.01))))
	fore.append(ProcMesh.part(ProcMesh.box(Vector3(0.036, 0.07, 0.06)), _x(Vector3(0, 0.03, 0.03), Vector3(30, 0, 0))))   # lever horn
	_bake_many(elbow, fore, yel)
	_bake(elbow, ProcMesh.cyl(0.03, 0.03, 0.064, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	var wrist: Node3D = _node(elbow, Vector3(0, 0, -L2))
	_bake(wrist, ProcMesh.cyl(0.026, 0.026, 0.07, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(wrist, ProcMesh.box(Vector3(0.08, 0.05, 0.04)), steel, _x(Vector3(0, 0, -0.02)))
	# Clamshell jaw: two scoops hinged on the wrist cross-pin; closed they cup a can or a crumpled sheet.
	var halves: Array[Node3D] = []
	for side: float in [1.0, -1.0]:
		var hv: Node3D = _node(wrist, Vector3(0, 0, -0.035))
		var sp: Array = []
		sp.append(ProcMesh.part(ProcMesh.box(Vector3(0.1, 0.008, 0.11)), _x(Vector3(0, 0.035 * side, -0.05))))   # back wall
		sp.append(ProcMesh.part(ProcMesh.box(Vector3(0.1, 0.04, 0.008)), _x(Vector3(0, 0.017 * side, -0.104), Vector3(-22 * side, 0, 0))))   # curled tip
		for x: float in [-0.05, 0.05]:
			sp.append(ProcMesh.part(ProcMesh.box(Vector3(0.006, 0.036, 0.11)), _x(Vector3(x, 0.018 * side, -0.05))))
		_bake_many(hv, sp, steel)
		var teeth: Array = []
		for k: int in 4:
			teeth.append(ProcMesh.part(ProcMesh.box(Vector3(0.012, 0.01, 0.018)), _x(Vector3(-0.036 + k * 0.024, 0.004 * side, -0.115))))
		_bake_many(hv, teeth, Mats.metal("steel"))
		halves.append(hv)
	# Rams: shoulder lift (body to boom) and elbow (boom to forearm horn).
	var a1: Node3D = _node(_rig, Vector3(0.36 * s, 0.5, -0.17))
	_bake(_rig, ProcMesh.box(Vector3(0.04, 0.05, 0.05)), steel, _x(Vector3(0.335 * s, 0.5, -0.17)))
	var b1: Node3D = _node(upper, Vector3(0, -0.035, -0.17))
	_add_ram(a1, b1, 0.024, 0.19, yel)
	var a2: Node3D = _node(upper, Vector3(0, 0.062, -0.08))
	var b2: Node3D = _node(elbow, Vector3(0, 0.055, 0.05))
	_add_ram(a2, b2, 0.019, 0.17, yel)
	_hose(_rig, Vector3(0.3 * s, 0.86, -0.06), Vector3(0.38 * s, 0.86, -0.2), Vector3(0.36 * s, 0.76, -0.25), 0.01)
	_arms.append({"s": s, "yaw": yaw, "upper": upper, "elbow": elbow, "wrist": wrist, "halves": halves})


func _add_ram(a: Node3D, b: Node3D, r: float, length: float, barrel_mat: Material) -> void:
	var barrel := Node3D.new()
	var rod := Node3D.new()
	_rig.add_child(barrel)
	_rig.add_child(rod)
	_bake(barrel, ProcMesh.cyl(r, r, length, 12), barrel_mat, _x(Vector3(0, 0, -length * 0.5), Vector3(90, 0, 0)))
	_bake(barrel, ProcMesh.cyl(r * 1.25, r * 1.25, 0.02, 12), Mats.metal("dark_steel"), _x(Vector3(0, 0, -length), Vector3(90, 0, 0)))
	_bake(barrel, ProcMesh.cyl(r * 0.7, r * 0.7, r * 3.0, 8), Mats.metal("steel"), _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(rod, ProcMesh.cyl(r * 0.45, r * 0.45, length, 10), Mats.metal("chrome"), _x(Vector3(0, 0, -length * 0.5), Vector3(90, 0, 0)))
	_bake(rod, ProcMesh.cyl(r * 0.7, r * 0.7, r * 3.0, 8), Mats.metal("steel"), _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_rams.append([barrel, rod, a, b])


# ---------------------------------------------------------------- animation

## Scoop keyframes: [t, shoulder pitch, forearm absolute pitch, jaw absolute pitch, jaw open 0..1, inward yaw].
const SCOOP_KEYS: Array = [
	[0.0, -20.0, -85.0, -95.0, 0.4, 0.0],
	[0.22, -44.0, -60.0, -100.0, 0.85, -6.0],
	[0.36, -44.0, -60.0, -100.0, 0.0, -6.0],
	[0.62, 28.0, -100.0, -150.0, 0.0, 30.0],
	[0.74, 28.0, -100.0, -150.0, 0.9, 30.0],
	[1.0, -20.0, -85.0, -95.0, 0.4, 0.0],
]
const REST_POSE: Array = [0.0, 12.0, -104.0, -150.0, 0.05, 0.0]


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


func _update_arms(delta: float) -> void:
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
		var open: float = deg_to_rad(4.0 + float(p[4]) * 38.0)
		var halves: Array = arm["halves"]
		(halves[0] as Node3D).rotation.x = open
		(halves[1] as Node3D).rotation.x = -open
	for r: Array in _rams:
		var barrel: Node3D = r[0]
		var rod: Node3D = r[1]
		var pa: Vector3 = _rig.to_local((r[2] as Node3D).global_position)
		var pb: Vector3 = _rig.to_local((r[3] as Node3D).global_position)
		if pa.distance_to(pb) < 0.001:
			continue
		var up := Vector3.RIGHT
		barrel.transform = Transform3D(Basis.looking_at(pb - pa, up), pa)
		rod.transform = Transform3D(Basis.looking_at(pa - pb, up), pb)


func _process(delta: float) -> void:
	_time += delta
	# Scooping.
	_scoop_amount = move_toward(_scoop_amount, 1.0 if _scoop_hold > 0.0 else 0.0, delta * 3.0)
	if _scoop_amount > 0.0:
		_scoop_phase = fposmod(_scoop_phase + delta / 1.7, 1.0)
	_scoop_hold = maxf(0.0, _scoop_hold - delta)
	_update_arms(delta)
	# Suspension: lean from acceleration, tiny dip, mechanical vibration while shuddering.
	_dip = lerpf(_dip, _dip_target, clampf(delta * 10.0, 0.0, 1.0))
	_dip_target = move_toward(_dip_target, 0.0, delta * 0.2)
	var jitter := Vector3.ZERO
	if _shudder_t > 0.0:
		_shudder_t -= delta
		jitter = Vector3(sin(_time * 91.0), sin(_time * 117.0) * 0.6, sin(_time * 73.0)) * 0.0035
	if sleeping:
		jitter = Vector3.ZERO
	_rig.position = Vector3(0, -_dip, 0) + jitter
	_rig.rotation = Vector3(_lean.x, 0, _lean.y)
	# Head: pan toward target, tilt with mood; sleeping slumps it forward.
	_look_yaw = lerp_angle(_look_yaw, _look_target, clampf(delta * 3.0, 0.0, 1.0))
	_pan.rotation.y = _look_yaw
	var tilt_target: float = deg_to_rad(-26.0) if sleeping else deg_to_rad(-6.0 + 8.0 * _iris_target + sin(_time * 0.7) * 1.5)
	_tilt_now = lerpf(_tilt_now, tilt_target, clampf(delta * 2.5, 0.0, 1.0))
	_tilt.rotation.x = _tilt_now
	_tilt.rotation.z = deg_to_rad(4.0 if not sleeping else 9.0)
	# Aperture: blades slide and rotate; open = wide.
	var ap: float = 0.0 if sleeping else _iris_target
	_iris_now = lerpf(_iris_now, ap, clampf(delta * 6.0, 0.0, 1.0))
	var r_ap: float = lerpf(0.004, 0.027, _iris_now)
	for b: Node3D in _blades:
		b.position = Vector3(0, r_ap, 0)
		b.rotation.z = lerpf(0.5, 0.15, _iris_now)
	_sensor_mat.emission_energy_multiplier = (0.05 if sleeping else 0.9 + 0.8 * _iris_now)
	# Antenna lamp: slow idle pulse, bright on flash.
	_flash_t = maxf(0.0, _flash_t - delta * 2.5)
	var pulse: float = 0.6 + 0.3 * sin(_time * 2.4)
	if sleeping:
		pulse = 0.12 + 0.1 * maxf(0.0, sin(_time * 0.8))
	_lamp_mat.emission_energy_multiplier = pulse + _flash_t * 6.0
	_lamp_light.light_energy = 0.1 + _flash_t * 1.5
	# Gauge needle with a little hydraulic lag.
	_fill_angle = lerpf(_fill_angle, _fill_target, clampf(delta * 4.0, 0.0, 1.0))
	_needle.rotation.z = -_fill_angle
	# Ram tail rod and hatch.
	_press_rod.position.y = DRUM_Y1 + 0.03 + 0.213 - _press_now * 0.1
	_hatch.rotation.x = -_hatch_now * deg_to_rad(105.0)


# ---------------------------------------------------------------- interface

func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	_wheel_angle -= speed * delta / WHEEL_R
	for w: Node3D in _wheels:
		w.rotation.x = _wheel_angle
	# Caster trails into turns (from lateral acceleration) and spins with ground speed.
	var target_swivel: float = clampf(-local_accel.x * 0.06, -0.8, 0.8) if absf(speed) > 0.05 else _caster_angle
	_caster_angle = lerp_angle(_caster_angle, target_swivel, clampf(delta * 5.0, 0.0, 1.0))
	_caster_swivel.rotation.y = _caster_angle
	_caster_wheel.rotation.x -= speed * delta / CASTER_R
	var target := Vector2(clampf(-local_accel.y * 0.004, -0.035, 0.035), clampf(local_accel.x * 0.004, -0.03, 0.03))
	target.x += 0.004 * speed_ratio * 0.0
	_lean = _lean.lerp(target, clampf(delta * 4.0, 0.0, 1.0))


func set_scooping(active: bool) -> void:
	if active:
		_scoop_hold = 0.15


func set_fill(ratio: float, band: Array) -> void:
	# Dial sweeps -120..+120 degrees; the red zone sits above the band's upper edge.
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
	_dip_target = clampf(_dip_target + absf(amount) * 0.01, 0.0, 0.012)


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
