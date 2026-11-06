extends Node3D
## Patch (unit P-47CH), concept "Sweeper".
## A compact, rounded little municipal street-sweeper, decommissioned decades ago. Four small chunky
## wheels on visible coil-over struts carry a chipped white body. Two worn disc brushes at the front
## corners sweep litter into reach; two folding side arms end in dustpan scoops with a hinged clamp
## finger, so Patch picks up single pieces of trash (a can, a sheet of paper, a bottle) and tips each
## one into the open front hopper. One camera lens with an aperture iris sits in a domed sensor
## turret on the roof (it pans and tilts), under a small sun-hood. Twin compaction rams run along the
## ram housing behind the turret; strapped bales leave through the chevron-striped rear hatch.
## Faces -Z, base at y = 0. Real-world scale: about 1.05 m to the dome, 1.3 m to the antenna lamp,
## 1.25 m long including brushes and hopper.

const WHITE := Color(0.74, 0.72, 0.66)        # chipped utility white
const ORANGE := Color(0.64, 0.31, 0.11)       # faded municipal orange
const YELLOW := Color(0.70, 0.55, 0.17)       # faded safety yellow
const GREEN := Color(0.22, 0.28, 0.21)        # utility green (running gear)
const BLACK := Color(0.05, 0.05, 0.05)

const WHEEL_R: float = 0.16
const WHEEL_X: float = 0.39
const WHEEL_Z: Array = [-0.30, 0.32]
const BODY_HW: float = 0.30
const BODY_Y0: float = 0.38
const BODY_Y1: float = 0.78
const BODY_Z0: float = -0.45
const BODY_Z1: float = 0.49
const ARM_X: float = 0.38
const SHOULDER := Vector3(0.0, 0.60, -0.28)
const L1: float = 0.34
const L2: float = 0.36
const BRUSH_R: float = 0.15

## Interface: local anchor points used by the controller.
var chest_point := Vector3(0, 0.70, -0.56)
var back_hatch_point := Vector3(0, 0.56, 0.56)
var vent_points: Array[Vector3] = [Vector3(-0.33, 0.64, 0.33), Vector3(-0.265, 0.96, 0.42), Vector3(0.24, 0.88, -0.12)]
var stack_point := Vector3(0, 0.96, 0.27)
var lens_point := Vector3(0, 0.9, -0.31)
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
var _brushes: Array[Node3D] = []
var _arms: Array[Dictionary] = []
var _rams: Array[Array] = []    # [barrel, rod, anchor_a, anchor_b]
var _press_rods: Array[Node3D] = []
var _hatch: Node3D
var _paint_mats: Array[ShaderMaterial] = []

var _time: float = 0.0
var _rust: float = 0.6
var _wheel_angle: float = 0.0
var _brush_angle: float = 0.0
var _speed: float = 0.0
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
	_build_wheels()
	_build_chassis()
	_build_body()
	_build_hopper()
	_build_brushes()
	_build_turret()
	_build_ram_housing()
	_build_hatch()
	_build_gauge()
	for s: float in [-1.0, 1.0]:
		_build_arm(s)
	# Debug poses for stills: SWEEPER_POSE="scoop:0.3,press:1,hatch:1,happy:1"
	var pose: String = OS.get_environment("SWEEPER_POSE")
	if pose != "":
		for kv: String in pose.split(","):
			var p: PackedStringArray = kv.split(":")
			if p.size() == 2:
				match p[0]:
					"scoop": _debug_phase = float(p[1])
					"press": _press_now = float(p[1])
					"hatch": _hatch_now = float(p[1])
					"happy": _iris_target = float(p[1]); _iris_now = _iris_target
	_update_arms()


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
	var d: Vector3 = (b - a).normalized()
	if absf(d.dot(Vector3.UP)) > 0.9999:
		return Transform3D(Basis.IDENTITY if d.y > 0.0 else Basis(Vector3.RIGHT, PI), (a + b) * 0.5)
	var q := Quaternion(Vector3.UP, d)
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


## A plate cut to a convex outline in the ZY plane (points are Vector2(z, y)), thickness along X.
## Both windings are emitted so it renders from either side with correct normals.
func _prism(poly: Array, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = thick * 0.5
	var n: int = poly.size()
	var tris: Array = []
	for side: float in [-1.0, 1.0]:
		for i: int in range(1, n - 1):
			var a: Vector2 = poly[0]
			var b: Vector2 = poly[i]
			var c: Vector2 = poly[i + 1]
			tris.append([Vector3(h * side, a.y, a.x), Vector3(h * side, b.y, b.x), Vector3(h * side, c.y, c.x), Vector3(side, 0, 0)])
	for i: int in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var e: Vector2 = b - a
		var nrm := Vector3(0, -e.x, e.y).normalized()
		var p0 := Vector3(-h, a.y, a.x)
		var p1 := Vector3(h, a.y, a.x)
		var p2 := Vector3(h, b.y, b.x)
		var p3 := Vector3(-h, b.y, b.x)
		tris.append([p0, p1, p2, nrm])
		tris.append([p0, p2, p3, nrm])
	for t: Array in tris:
		var nn: Vector3 = t[3]
		for k: int in [0, 1, 2]:
			st.set_normal(nn)
			st.add_vertex(t[k])
		for k: int in [0, 2, 1]:
			st.set_normal(-nn)
			st.add_vertex(t[k])
	return st.commit()


## ProcMesh.rounded_box with its triangle winding flipped to Godot's front-face convention
## (the stock helper renders inside-out with back-face culling).
func _rbox(size: Vector3, radius: float, seg: int = 4) -> ArrayMesh:
	var src: ArrayMesh = ProcMesh.rounded_box(size, radius, seg)
	var arr: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var i: int = 0
	while i + 2 < v.size():
		for k: int in [0, 2, 1]:
			st.set_normal(nm[i + k])
			st.add_vertex(v[i + k])
		i += 3
	return st.commit()


## Curved sheet (an annular sector) around the X axis: angles in degrees in the ZY plane, measured
## from +Z toward +Y, extruded `width` along X. Used for mudguards and the lens sun-hood.
func _arc_band(r0: float, r1: float, a0: float, a1: float, width: float, segs: int = 14) -> Array:
	var parts: Array = []
	for k: int in segs:
		var b0: float = deg_to_rad(lerpf(a0, a1, float(k) / segs))
		var b1: float = deg_to_rad(lerpf(a0, a1, float(k + 1) / segs))
		var poly: Array = [Vector2(cos(b0) * r0, sin(b0) * r0), Vector2(cos(b0) * r1, sin(b0) * r1), Vector2(cos(b1) * r1, sin(b1) * r1), Vector2(cos(b1) * r0, sin(b1) * r0)]
		parts.append(ProcMesh.part(_prism(poly, width)))
	return parts


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


func _chevrons(parent: Node3D, w: float, h: float, xf: Transform3D, seed: float) -> void:
	var back := MeshInstance3D.new()
	back.mesh = ProcMesh.merge([ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.002)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.0015)))])
	back.material_override = _paint(YELLOW.lightened(0.08), 0.75, 0.5, seed + 0.5, 0.5, -0.6)
	back.transform = xf
	parent.add_child(back)
	var chev := MeshInstance3D.new()
	chev.mesh = _chevron_mesh(w, h, h * 0.55)
	chev.material_override = _paint(BLACK, 0.7, 0.5, seed, 0.6, -0.6)
	chev.transform = xf
	parent.add_child(chev)


func _stencil(parent: Node3D, text: String, size_px: int, pos: Vector3, rot_deg: Vector3, color: Color = Color(0.12, 0.12, 0.11, 0.62)) -> Label3D:
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


func _flat(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


# ---------------------------------------------------------------- build

func _build_wheels() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var tyre: Mesh = AssetLib.model_mesh("old_tyre")
	var rim: Mesh = AssetLib.model_mesh("rusted_wheel_rim_01")
	var tscale: float = WHEEL_R * 2.0 / 0.6
	for z: float in WHEEL_Z:
		for s: float in [-1.0, 1.0]:
			var hub: Node3D = _node(self, Vector3(WHEEL_X * s, WHEEL_R, z))
			var spin: Node3D = _node(hub, Vector3.ZERO)
			var t := MeshInstance3D.new()
			t.mesh = tyre
			t.rotation_degrees = Vector3(0, 90, 0)
			t.scale = Vector3(tscale, tscale, 0.78)
			spin.add_child(t)
			var r := MeshInstance3D.new()
			r.mesh = rim
			r.rotation_degrees = Vector3(0, 90, 0)
			r.scale = Vector3(tscale * 0.84, tscale * 0.84, 0.72)
			spin.add_child(r)
			_bake(spin, ProcMesh.cyl(0.035, 0.045, 0.04, 14), steel, _x(Vector3(0.05 * s, 0, 0), Vector3(0, 0, 90)))
			var nuts: Array = []
			for k: int in 5:
				var a: float = TAU * k / 5.0
				nuts.append(Vector3(0.062 * s, cos(a) * 0.055, sin(a) * 0.055))
			_bolts(spin, nuts, Vector3(s, 0, 0), 0.009)
			_wheels.append(spin)


func _build_chassis() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var frame_mat: ShaderMaterial = _paint(GREEN, 0.5, 0.75, 3.3, 0.95)
	# Lower tub: a narrower pressed-steel pan under the body, carrying the suspension.
	_bake(_rig, _rbox(Vector3(0.46, 0.24, 0.9), 0.05, 3), frame_mat, _x(Vector3(0, 0.33, 0.02)))
	# Skid plate and side rails.
	_bake(_rig, ProcMesh.box(Vector3(0.38, 0.02, 0.8)), steel, _x(Vector3(0, 0.205, 0.02)))
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.box(Vector3(0.03, 0.05, 0.92)), _paint(GREEN.darkened(0.15), 0.4, 0.8, 4.0 + s, 1.0), _x(Vector3(0.235 * s, 0.4, 0.02)))
		_bolts(_rig, [Vector3(0.251 * s, 0.4, -0.3), Vector3(0.251 * s, 0.4, -0.1), Vector3(0.251 * s, 0.4, 0.12), Vector3(0.251 * s, 0.4, 0.34)], Vector3(s, 0, 0), 0.009)
	# Suspension per corner: a trailing/leading arm pivoted on the tub, a coil-over strut standing on
	# the arm in the gap between the wheels, up to a bracket on the body flank.
	var spring_mat: ShaderMaterial = _paint(YELLOW.darkened(0.1), 0.5, 0.75, 5.5, 0.9)
	var guard_mat: ShaderMaterial = _paint(ORANGE.darkened(0.1), 0.5, 0.75, 7.0, 0.9)
	for z: float in WHEEL_Z:
		var inward: float = signf(-z)   # toward the middle of the wheelbase
		for s: float in [-1.0, 1.0]:
			var knuckle := Vector3(0.315 * s, WHEEL_R, z)
			var pivot := Vector3(0.26 * s, 0.25, z + 0.24 * inward)
			_bake(_rig, ProcMesh.cyl(0.022, 0.022, 0.1, 10), steel, _x(Vector3(0.35 * s, WHEEL_R, z), Vector3(0, 0, 90)))   # stub axle
			_bake(_rig, ProcMesh.box(Vector3(0.035, 0.09, 0.07)), steel, _x(knuckle))   # upright
			_bake(_rig, ProcMesh.cyl(0.026, 0.026, 0.06, 12), steel, _x(pivot, Vector3(0, 0, 90)))   # pivot bush
			_bake(_rig, ProcMesh.box(Vector3(0.03, 0.06, 0.06)), frame_mat, _x(pivot + Vector3(-0.025 * s, 0.03, 0)))   # pivot bracket
			var zc: float = z + 0.2 * inward
			var bot := Vector3(0.345 * s, 0.215, zc)
			var top := Vector3(0.345 * s, 0.5, zc - 0.03 * inward)
			var arm_parts: Array = []
			arm_parts.append(_tube(0.02, pivot, knuckle + Vector3(0, 0.0, 0)))
			arm_parts.append(_tube(0.013, Vector3(0.3 * s, 0.215, zc), bot))   # strut lug
			_bake_many(_rig, arm_parts, frame_mat)
			var dir: Vector3 = (top - bot).normalized()
			# Damper: steel body + chrome shaft + rubber top bush.
			_bake_many(_rig, [_tube(0.017, bot, bot + dir * 0.13)], steel)
			_bake_many(_rig, [_tube(0.008, bot + dir * 0.12, top)], Mats.metal("chrome"))
			_bake_many(_rig, [_tube(0.026, top - dir * 0.012, top + dir * 0.01, 12)], Mats.rubber())
			_bake(_rig, ProcMesh.cyl(0.014, 0.014, 0.05, 8), steel, _x(bot, Vector3(0, 0, 90)))   # lower eye
			# Coil spring wound around the damper between two perches.
			var basis := Basis(Quaternion(Vector3.UP, dir))
			var coil: Array = []
			var turns: float = 5.5
			var segs: int = 66
			var c0: Vector3 = bot + dir * 0.05
			var length: float = c0.distance_to(top - dir * 0.03)
			var prev: Vector3 = c0 + basis * Vector3(0.03, 0, 0)
			for i: int in range(1, segs + 1):
				var u: float = float(i) / segs
				var a: float = u * turns * TAU
				var p: Vector3 = c0 + basis * Vector3(cos(a) * 0.03, u * length, sin(a) * 0.03)
				coil.append(_tube(0.0055, prev, p, 6))
				prev = p
			coil.append(_tube(0.037, c0 - dir * 0.006, c0 + dir * 0.002, 12))
			coil.append(_tube(0.037, top - dir * 0.034, top - dir * 0.026, 12))
			_bake_many(_rig, coil, spring_mat)
			# Top bracket welded to the body flank.
			_bake(_rig, ProcMesh.box(Vector3(0.075, 0.025, 0.07)), steel, _x(Vector3(0.335 * s, 0.515, top.z)))
			_bake(_rig, _prism([Vector2(top.z - 0.03, 0.503), Vector2(top.z + 0.03, 0.503), Vector2(top.z, 0.45)], 0.012), steel, _x(Vector3(0.31 * s, 0, 0)))
			# Mudguard: a curved steel arc over the tyre, bracketed to the body.
			var gparts: Array = []
			for gp: Dictionary in _arc_band(WHEEL_R + 0.035, WHEEL_R + 0.043, 12.0, 168.0, 0.15, 16):
				gparts.append(ProcMesh.part(gp["mesh"], Transform3D(Basis.IDENTITY, Vector3(WHEEL_X * s, WHEEL_R, z))))
			for gp: Dictionary in _arc_band(WHEEL_R + 0.035, WHEEL_R + 0.055, 12.0, 168.0, 0.012, 16):
				gparts.append(ProcMesh.part(gp["mesh"], Transform3D(Basis.IDENTITY, Vector3((WHEEL_X + 0.075) * s, WHEEL_R, z))))
			_bake_many(_rig, gparts, guard_mat)
			_bake(_rig, ProcMesh.box(Vector3(0.1, 0.03, 0.04)), steel, _x(Vector3(0.33 * s, WHEEL_R + 0.2, z)))
	# Front and rear bumpers.
	_bake(_rig, ProcMesh.box(Vector3(0.62, 0.05, 0.05)), steel, _x(Vector3(0, 0.3, BODY_Z1 + 0.02)))
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.box(Vector3(0.04, 0.04, 0.08)), steel, _x(Vector3(0.18 * s, 0.3, 0.45)))
	_chevrons(_rig, 0.6, 0.044, _x(Vector3(0, 0.3, BODY_Z1 + 0.046), Vector3(0, 180, 0)), 6.1)
	# Tail lamps.
	var red: StandardMaterial3D = Mats.lamp(Color(0.8, 0.08, 0.05), 0.4)
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.cyl(0.026, 0.026, 0.02, 14), red, _x(Vector3(0.24 * s, 0.37, BODY_Z1 + 0.012), Vector3(90, 0, 0)))
		_bake(_rig, ProcMesh.torus(0.024, 0.032, 14, 6), steel, _x(Vector3(0.24 * s, 0.37, BODY_Z1 + 0.018), Vector3(90, 0, 0)))


func _build_body() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var body_mat: ShaderMaterial = _paint(WHITE, 0.6, 0.7, 1.7, 0.8)
	var size := Vector3(BODY_HW * 2.0, BODY_Y1 - BODY_Y0, BODY_Z1 - BODY_Z0)
	var ctr := Vector3(0, (BODY_Y0 + BODY_Y1) * 0.5, (BODY_Z0 + BODY_Z1) * 0.5)
	_bake(_rig, _rbox(size, 0.11, 6), body_mat, _x(ctr))
	# Orange belt line around the lower body (a separate, proud rubbing strip).
	var belt: ShaderMaterial = _paint(ORANGE, 0.55, 0.75, 2.4, 0.8)
	var bp: Array = []
	for s: float in [-1.0, 1.0]:
		bp.append(ProcMesh.part(ProcMesh.box(Vector3(0.014, 0.07, size.z - 0.12)), _x(Vector3((BODY_HW + 0.002) * s, 0.5, ctr.z))))
	bp.append(ProcMesh.part(ProcMesh.box(Vector3(size.x - 0.12, 0.07, 0.014)), _x(Vector3(0, 0.5, BODY_Z1 + 0.002))))
	_bake_many(_rig, bp, belt)
	# Panel seams (vertical weld lines) and bolt rows along the belt.
	var seams: Array = []
	for z: float in [-0.16, 0.12]:
		for s: float in [-1.0, 1.0]:
			seams.append(ProcMesh.part(ProcMesh.box(Vector3(0.008, 0.13, 0.012)), _x(Vector3((BODY_HW + 0.002) * s, 0.615, z))))
	seams.append(ProcMesh.part(ProcMesh.box(Vector3(size.x - 0.16, 0.008, 0.012)), _x(Vector3(0, BODY_Y1 + 0.002, 0.07))))
	_bake_many(_rig, seams, steel)
	for s: float in [-1.0, 1.0]:
		var pts: Array = []
		for k: int in 7:
			pts.append(Vector3((BODY_HW + 0.01) * s, 0.5, -0.33 + k * 0.12))
		_bolts(_rig, pts, Vector3(s, 0, 0), 0.008)
	# Serial stencils, both flanks, and a faded department line.
	for s: float in [-1.0, 1.0]:
		var x: float = (BODY_HW + 0.003) * s
		_stencil(_rig, "P-47CH", 80, Vector3(x, 0.665, -0.02), Vector3(0, 90 * s, 0), Color(0.1, 0.1, 0.09, 0.55))
		_stencil(_rig, "MUNICIPAL SANITATION  DEPT. 4", 20, Vector3(x, 0.6, -0.02), Vector3(0, 90 * s, 0), Color(0.12, 0.12, 0.1, 0.4))
	# Left flank: louvred cooling vent (steam/hydraulic relief).
	var vent: Node3D = _node(_rig, Vector3(-BODY_HW - 0.012, 0.64, 0.33), Vector3(0, 90, 0))
	_bake(vent, _rbox(Vector3(0.18, 0.14, 0.03), 0.01, 2), steel)
	var lv: Array = []
	for k: int in 5:
		lv.append(ProcMesh.part(ProcMesh.box(Vector3(0.16, 0.01, 0.03)), _x(Vector3(0, -0.05 + k * 0.025, -0.018), Vector3(35, 0, 0))))
	_bake_many(vent, lv, _paint(WHITE.darkened(0.3), 0.4, 0.8, 8.8, 0.5, -0.6))
	# Right flank: bolted access panel with a latch.
	var ap: Node3D = _node(_rig, Vector3(BODY_HW + 0.006, 0.64, 0.33), Vector3(0, 90, 0))
	_bake(ap, ProcMesh.box(Vector3(0.17, 0.15, 0.008)), _paint(WHITE.darkened(0.12), 0.5, 0.75, 9.4, 0.6, -0.64), _x(Vector3.ZERO))
	_bolts(ap, [Vector3(-0.075, 0.062, 0.005), Vector3(0.075, 0.062, 0.005), Vector3(-0.075, -0.062, 0.005), Vector3(0.075, -0.062, 0.005)], Vector3(0, 0, 1), 0.007)
	_bake(ap, ProcMesh.box(Vector3(0.05, 0.018, 0.02)), Mats.metal("steel"), _x(Vector3(0, 0, 0.012)))
	# Exhaust stack, rear-left corner of the roof, with a rain flap.
	_bake(_rig, ProcMesh.cyl(0.028, 0.032, 0.18, 12), steel, _x(Vector3(-0.265, BODY_Y1 + 0.08, 0.42)))
	_bake(_rig, ProcMesh.torus(0.026, 0.035, 12, 6), Mats.metal("steel"), _x(Vector3(-0.265, BODY_Y1 + 0.03, 0.42)))
	_bake(_rig, ProcMesh.cyl(0.036, 0.036, 0.006, 12), steel, _x(Vector3(-0.265, BODY_Y1 + 0.182, 0.43), Vector3(-24, 0, 0)))


func _build_hopper() -> void:
	var orange: ShaderMaterial = _paint(ORANGE, 0.6, 0.65, 11.0, 0.7)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var z0: float = BODY_Z0 + 0.02
	var zf: float = -0.69
	# Side cheeks: low at the front lip, rising to the body.
	var cheek: Array = [Vector2(z0, 0.4), Vector2(zf, 0.4), Vector2(zf - 0.02, 0.6), Vector2(z0 - 0.06, 0.8), Vector2(z0, 0.8)]
	for s: float in [-1.0, 1.0]:
		_bake(_rig, _prism(cheek, 0.02), orange, _x(Vector3(0.265 * s, 0, 0)))
		_bake(_rig, ProcMesh.box(Vector3(0.03, 0.02, 0.32)), orange, _x(Vector3(0.265 * s, 0.705, -0.585), Vector3(-37, 0, 0)))   # rolled top edge
	# Floor and front wall.
	_bake(_rig, ProcMesh.box(Vector3(0.53, 0.02, z0 - zf)), orange, _x(Vector3(0, 0.405, (z0 + zf) * 0.5)))
	_bake(_rig, ProcMesh.box(Vector3(0.53, 0.2, 0.02)), orange, _x(Vector3(0, 0.5, zf - 0.008), Vector3(-6, 0, 0)))
	_bake(_rig, ProcMesh.cyl(0.015, 0.015, 0.55, 10), orange, _x(Vector3(0, 0.6, zf - 0.02), Vector3(0, 0, 90)))   # rolled lip
	_chevrons(_rig, 0.5, 0.1, _x(Vector3(0, 0.495, zf - 0.02), Vector3(-6, 0, 0)), 13.0)
	# Dark interior and the rubber curtain where litter passes into the compaction chamber.
	var dark: StandardMaterial3D = _flat(Color(0.025, 0.025, 0.025), 1.0)
	_bake(_rig, ProcMesh.box(Vector3(0.5, 0.3, 0.01)), dark, _x(Vector3(0, 0.6, BODY_Z0 - 0.003)))
	var flaps: Array = []
	for k: int in 7:
		var x: float = -0.21 + k * 0.07
		flaps.append(ProcMesh.part(ProcMesh.box(Vector3(0.066, 0.29, 0.008)), _x(Vector3(x, 0.575, BODY_Z0 - 0.012), Vector3(4.0 * sin(k * 2.3), 0, 0))))
	_bake_many(_rig, flaps, Mats.rubber(Color(0.11, 0.105, 0.1)))
	var frame: Array = []
	frame.append(ProcMesh.part(ProcMesh.box(Vector3(0.53, 0.07, 0.03)), _x(Vector3(0, 0.765, BODY_Z0 - 0.012))))
	for sx: float in [-1.0, 1.0]:
		frame.append(ProcMesh.part(ProcMesh.box(Vector3(0.03, 0.36, 0.03)), _x(Vector3(0.245 * sx, 0.6, BODY_Z0 - 0.012))))
	_bake_many(_rig, frame, orange)
	_bake(_rig, ProcMesh.box(Vector3(0.48, 0.025, 0.03)), steel, _x(Vector3(0, 0.735, BODY_Z0 - 0.02)))
	_bolts(_rig, [Vector3(-0.2, 0.735, BODY_Z0 - 0.036), Vector3(0, 0.735, BODY_Z0 - 0.036), Vector3(0.2, 0.735, BODY_Z0 - 0.036)], Vector3(0, 0, -1), 0.009)
	# Gussets under the hopper floor to the tub.
	for s: float in [-1.0, 1.0]:
		_bake(_rig, _prism([Vector2(-0.43, 0.395), Vector2(-0.62, 0.395), Vector2(-0.43, 0.3)], 0.016), steel, _x(Vector3(0.16 * s, 0, 0)))
	_bolts(_rig, [Vector3(-0.276, 0.5, -0.6), Vector3(-0.276, 0.5, -0.5), Vector3(0.276, 0.5, -0.6), Vector3(0.276, 0.5, -0.5)], Vector3(1, 0, 0), 0.008)
	_stencil(_rig, "KEEP HANDS CLEAR", 22, Vector3(0.277, 0.55, -0.56), Vector3(0, 90, 0), Color(0.08, 0.08, 0.07, 0.7))


func _build_brushes() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var arm_mat: ShaderMaterial = _paint(GREEN, 0.5, 0.75, 14.0, 0.9)
	var bristle_mat: StandardMaterial3D = _flat(Color(0.13, 0.1, 0.07), 0.95)
	var worn_mat: StandardMaterial3D = _flat(Color(0.2, 0.17, 0.12), 0.95)
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0.25 * s, 0.0, -0.62)
		# Swing arm: a fabricated box beam from the tub's front corner out to the brush motor.
		var root := Vector3(0.17 * s, 0.27, -0.4)
		var tip: Vector3 = c + Vector3(0, 0.17, 0)
		var beam := Transform3D(Basis.looking_at(tip - root, Vector3.UP), (root + tip) * 0.5)
		_bake(_rig, _rbox(Vector3(0.05, 0.06, root.distance_to(tip) + 0.04), 0.01, 2), arm_mat, beam)
		_bake(_rig, ProcMesh.box(Vector3(0.09, 0.09, 0.05)), steel, _x(root + Vector3(0, 0, 0.01)))
		_bake(_rig, ProcMesh.cyl(0.044, 0.048, 0.08, 14), arm_mat, _x(c + Vector3(0, 0.14, 0)))
		_bake(_rig, ProcMesh.cyl(0.05, 0.05, 0.014, 14), steel, _x(c + Vector3(0, 0.185, 0)))
		_hose(_rig, c + Vector3(0.035 * s, 0.17, 0.02), c + Vector3(0.0, 0.3, 0.15), root + Vector3(-0.02 * s, 0.06, 0.0), 0.008)
		# Spinning disc: steel backing plate with tufts of worn bristles splayed outward.
		var disc: Node3D = _node(_rig, c + Vector3(0, 0.085, 0), Vector3(-6, 0, -7 * s))
		_bake(disc, ProcMesh.cyl(0.1, 0.1, 0.018, 20), steel)
		_bake(disc, ProcMesh.cyl(0.03, 0.03, 0.03, 10), Mats.metal("steel"), _x(Vector3(0, 0.02, 0)))
		var br: Array = []
		var br2: Array = []
		var count: int = 54
		for k: int in count:
			var a: float = TAU * k / count + 0.05 * sin(k * 7.1)
			var r0: float = 0.055 + 0.03 * fposmod(k * 0.37, 1.0)
			var r1: float = BRUSH_R - 0.012 * fposmod(k * 0.61, 1.0)
			var dirv := Vector3(cos(a), 0, sin(a))
			var p0: Vector3 = dirv * r0 + Vector3(0, -0.008, 0)
			var p1: Vector3 = dirv * r1 + Vector3(0, -0.078 + 0.01 * fposmod(k * 0.83, 1.0), 0) + Vector3(-dirv.z, 0, dirv.x) * 0.015
			var t: Dictionary = _tube(0.0065, p0, p1, 5)
			if k % 3 == 0:
				br2.append(t)
			else:
				br.append(t)
		_bake_many(disc, br, bristle_mat)
		_bake_many(disc, br2, worn_mat)
		_brushes.append(disc)


func _build_turret() -> void:
	var white: ShaderMaterial = _paint(WHITE, 0.68, 0.6, 21.0, 0.2, -0.3)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var base := Vector3(0, BODY_Y1, -0.1)
	# Fixed slewing ring on the roof.
	_bake(_rig, ProcMesh.cyl(0.17, 0.18, 0.03, 32), steel, _x(base + Vector3(0, 0.012, 0)))
	var rb: Array = []
	for k: int in 12:
		var a: float = TAU * (k + 0.5) / 12.0
		rb.append(Vector3(cos(a) * 0.168, 0.03, sin(a) * 0.168) + base)
	_bolts(_rig, rb, Vector3.UP, 0.008)
	_pan = _node(_rig, base + Vector3(0, 0.03, 0))
	# Pan collar (green) that the dome sits down into.
	var collar: CylinderMesh = ProcMesh.cyl(0.162, 0.165, 0.06, 32)
	_bake(_pan, collar, _paint(GREEN, 0.5, 0.75, 22.0, 0.3, -1.0), _x(Vector3(0, 0.03, 0)))
	_bake(_pan, ProcMesh.torus(0.158, 0.172, 32, 6), steel, _x(Vector3(0, 0.06, 0)))
	# Tilt trunnions either side.
	for s: float in [-1.0, 1.0]:
		_bake(_pan, ProcMesh.box(Vector3(0.025, 0.07, 0.06)), _paint(GREEN, 0.5, 0.75, 22.5, 0.3, -1.0), _x(Vector3(0.165 * s, 0.085, 0)))
		_bake(_pan, ProcMesh.cyl(0.02, 0.02, 0.02, 10), Mats.metal("steel"), _x(Vector3(0.18 * s, 0.1, 0), Vector3(0, 0, 90)))
	_tilt = _node(_pan, Vector3(0, 0.1, 0))
	# Domed housing: short drum + flattened dome.
	_bake(_tilt, ProcMesh.cyl(0.15, 0.15, 0.1, 32), white, _x(Vector3(0, -0.02, 0)))
	_bake(_tilt, ProcMesh.hemisphere(0.15, 32, 8), white, _x(Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.72, 1)))
	_bake(_tilt, ProcMesh.torus(0.146, 0.156, 32, 6), steel, _x(Vector3(0, 0.03, 0)))   # seam band
	var dome_bolts: Array = []
	for k: int in 16:
		var a: float = TAU * (k + 0.5) / 16.0
		dome_bolts.append(Vector3(cos(a) * 0.153, 0.03, sin(a) * 0.153))
	_bake_many(_tilt, dome_bolts.map(func(p: Vector3) -> Dictionary: return ProcMesh.part(ProcMesh.cyl(0.006, 0.006, 0.006, 6), Transform3D(Basis(Quaternion(Vector3.UP, Vector3(p.x, 0, p.z).normalized())), p))), steel)
	# Rear service hatch on the dome.
	_bake(_tilt, ProcMesh.box(Vector3(0.1, 0.06, 0.006)), _paint(WHITE.darkened(0.15), 0.6, 0.6, 24.0, 0.1, -0.3), _x(Vector3(0, -0.02, 0.15)))
	_bolts(_tilt, [Vector3(-0.042, 0.0, 0.154), Vector3(0.042, 0.0, 0.154), Vector3(-0.042, -0.04, 0.154), Vector3(0.042, -0.04, 0.154)], Vector3(0, 0, 1), 0.005)
	_stencil(_tilt, "P-47CH", 22, Vector3(0.151, -0.03, 0.0), Vector3(0, 90, 0), Color(0.12, 0.12, 0.11, 0.6))
	# Lens: a stepped steel barrel with an 8-blade aperture behind glass.
	var lens: Node3D = _node(_tilt, Vector3(0, -0.012, -0.135))
	lens.scale = Vector3.ONE * 1.05
	_bake(lens, ProcMesh.cyl(0.074, 0.078, 0.03, 32), steel, _x(Vector3(0, 0, -0.005), Vector3(90, 0, 0)))
	var tube: CylinderMesh = ProcMesh.cyl(0.064, 0.068, 0.05, 32)
	tube.cap_top = false
	tube.cap_bottom = false
	_bake(lens, tube, _paint(WHITE.darkened(0.1), 0.6, 0.55, 25.0, 0.1, 1.0), _x(Vector3(0, 0, -0.04), Vector3(90, 0, 0)))
	var sleeve: CylinderMesh = ProcMesh.cyl(0.0625, 0.0625, 0.05, 32)
	sleeve.cap_top = false
	sleeve.cap_bottom = false
	var sleeve_mat := _flat(Color(0.03, 0.03, 0.03), 0.6)
	sleeve_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bake(lens, sleeve, sleeve_mat, _x(Vector3(0, 0, -0.04), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.torus(0.052, 0.067, 32, 8), steel, _x(Vector3(0, 0, -0.066), Vector3(90, 0, 0)))
	var knurl: Array = []
	for k: int in 24:
		var a: float = TAU * k / 24.0
		knurl.append(ProcMesh.part(ProcMesh.box(Vector3(0.006, 0.006, 0.026)), _x(Vector3(cos(a) * 0.069, sin(a) * 0.069, -0.04))))
	_bake_many(lens, knurl, steel)
	_sensor_mat = Mats.lamp(Color(1.0, 0.66, 0.3), 1.0)
	_bake(lens, ProcMesh.cyl(0.054, 0.054, 0.004, 32), _flat(Color(0.01, 0.01, 0.012), 0.3), _x(Vector3(0, 0, -0.03), Vector3(90, 0, 0)))
	_bake(lens, ProcMesh.cyl(0.03, 0.03, 0.004, 24), _sensor_mat, _x(Vector3(0, 0, -0.033), Vector3(90, 0, 0)))
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.32, 0.31, 0.3)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.38
	for k: int in 8:
		var piv: Node3D = _node(lens, Vector3(0, 0, -0.038 - k * 0.0007))
		piv.rotation.z = TAU * k / 8.0
		var arm: Node3D = _node(piv, Vector3.ZERO)
		_bake(arm, ProcMesh.box(Vector3(0.038, 0.034, 0.0012)), blade_mat, _x(Vector3(0.006, 0.017, 0)))
		_blades.append(arm)
	var glass_mat: StandardMaterial3D = Mats.glass(Color(0.45, 0.5, 0.55, 0.07), 0.04)
	glass_mat.metallic = 0.0
	_bake(lens, ProcMesh.cyl(0.056, 0.056, 0.003, 32), glass_mat, _x(Vector3(0, 0, -0.062), Vector3(90, 0, 0)))
	# Sun-hood: a curved sheet-steel visor over the top half of the lens.
	var hood: Array = []
	for hp: Dictionary in _arc_band(0.082, 0.087, 5.0, 175.0, 0.07, 18):
		hood.append(ProcMesh.part(hp["mesh"], _x(Vector3(0, 0, -0.065), Vector3(0, 90, 0))))
	_bake_many(lens, hood, _paint(WHITE.darkened(0.35), 0.45, 0.7, 26.0, 0.2, 1.0))
	# Antenna whip with a caged amber lamp, rear-right of the dome.
	var ant: Node3D = _node(_tilt, Vector3(0.07, 0.115, 0.07), Vector3(-8, 0, -10))
	_bake(ant, ProcMesh.cyl(0.016, 0.02, 0.025, 10), steel, _x(Vector3(0, 0.01, 0)))
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
	# Signal cable from the dome down into the roof.
	_hose(_rig, base + Vector3(-0.1, 0.0, 0.14), base + Vector3(-0.16, 0.04, 0.2), base + Vector3(-0.15, 0.0, 0.26), 0.007)


func _build_ram_housing() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var green: ShaderMaterial = _paint(GREEN.lightened(0.05), 0.74, 0.6, 31.0, 0.4, -1.0)
	var ctr := Vector3(0, BODY_Y1 + 0.065, 0.27)
	_bake(_rig, _rbox(Vector3(0.34, 0.13, 0.38), 0.035, 3), green, _x(ctr))
	_bake(_rig, ProcMesh.box(Vector3(0.36, 0.018, 0.4)), steel, _x(Vector3(0, BODY_Y1 + 0.006, 0.27)))   # flange
	var fb: Array = []
	for k: int in 5:
		var z: float = 0.09 + k * 0.09
		fb.append(Vector3(-0.172, BODY_Y1 + 0.017, z))
		fb.append(Vector3(0.172, BODY_Y1 + 0.017, z))
	_bolts(_rig, fb, Vector3.UP, 0.007)
	# Carry deck on top: two steel rails with end stops (bales ride here).
	var rails: Array = []
	for s: float in [-1.0, 1.0]:
		rails.append(ProcMesh.part(ProcMesh.box(Vector3(0.03, 0.02, 0.36)), _x(Vector3(0.12 * s, ctr.y + 0.075, 0.27))))
		rails.append(ProcMesh.part(ProcMesh.box(Vector3(0.03, 0.035, 0.02)), _x(Vector3(0.12 * s, ctr.y + 0.09, 0.45))))
	_bake_many(_rig, rails, Mats.metal("steel"))
	_stencil(_rig, "NO STEP", 26, Vector3(0, ctr.y + 0.066, 0.12), Vector3(-90, 0, 0), Color(0.82, 0.78, 0.68, 0.5))
	# Twin compaction rams along the housing flanks.
	var barrel_mat: ShaderMaterial = _paint(YELLOW.darkened(0.1), 0.55, 0.65, 32.0, 0.3, -1.0)
	for s: float in [-1.0, 1.0]:
		var x: float = 0.205 * s
		var y: float = BODY_Y1 + 0.05
		_bake(_rig, ProcMesh.cyl(0.03, 0.03, 0.24, 16), barrel_mat, _x(Vector3(x, y, 0.1), Vector3(90, 0, 0)))
		for z: float in [-0.02, 0.22]:
			_bake(_rig, ProcMesh.cyl(0.036, 0.036, 0.02, 16), steel, _x(Vector3(x, y, z), Vector3(90, 0, 0)))
		_bake(_rig, ProcMesh.box(Vector3(0.04, 0.05, 0.04)), steel, _x(Vector3(x, y - 0.025, -0.02)))   # trunnion foot
		# Guide rail for the rod-end slider.
		_bake(_rig, ProcMesh.box(Vector3(0.02, 0.012, 0.2)), Mats.metal("steel"), _x(Vector3(x, BODY_Y1 + 0.008, 0.36)))
		var rod: Node3D = _node(_rig, Vector3(x, y, 0.22))
		_bake(rod, ProcMesh.cyl(0.013, 0.013, 0.2, 12), Mats.metal("chrome"), _x(Vector3(0, 0, -0.02), Vector3(90, 0, 0)))
		_bake(rod, ProcMesh.box(Vector3(0.045, 0.05, 0.04)), steel, _x(Vector3(0, -0.015, 0.09)))
		_bake(rod, ProcMesh.cyl(0.01, 0.01, 0.06, 8), Mats.metal("steel"), _x(Vector3(0, 0, 0.09), Vector3(0, 0, 90)))
		_press_rods.append(rod)
		_hose(_rig, Vector3(x, y + 0.03, 0.0), Vector3(x * 0.8, y + 0.1, 0.05), Vector3(0.1 * s, ctr.y + 0.065, 0.1), 0.009)
	# Pump block and relief valve, front-right of the housing.
	_bake(_rig, _rbox(Vector3(0.1, 0.07, 0.08), 0.01, 2), steel, _x(Vector3(0.235, BODY_Y1 + 0.04, -0.12)))
	_bake(_rig, ProcMesh.cyl(0.014, 0.018, 0.05, 8), Mats.metal("brass"), _x(Vector3(0.24, BODY_Y1 + 0.1, -0.12)))


func _build_hatch() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var zb: float = BODY_Z1
	# Frame and dark chute behind the door.
	_bake(_rig, ProcMesh.box(Vector3(0.36, 0.25, 0.01)), _flat(Color(0.02, 0.02, 0.02), 1.0), _x(Vector3(0, 0.575, zb + 0.002)))
	var fr: Array = []
	for s: float in [-1.0, 1.0]:
		fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.035, 0.3, 0.03)), _x(Vector3(0.2 * s, 0.575, zb + 0.01))))
	fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.44, 0.035, 0.03)), _x(Vector3(0, 0.73, zb + 0.01))))
	fr.append(ProcMesh.part(ProcMesh.box(Vector3(0.44, 0.04, 0.05)), _x(Vector3(0, 0.425, zb + 0.015))))
	_bake_many(_rig, fr, steel)
	# Door hinged at the top, swings up and back.
	_hatch = _node(_rig, Vector3(0, 0.728, zb + 0.035))
	var door_mat: ShaderMaterial = _paint(ORANGE, 0.55, 0.7, 42.0, 0.7, -0.7)
	_bake(_hatch, ProcMesh.box(Vector3(0.36, 0.28, 0.022)), door_mat, _x(Vector3(0, -0.15, 0)))
	var ribs: Array = []
	for x: float in [-0.1, 0.1]:
		ribs.append(ProcMesh.part(ProcMesh.box(Vector3(0.025, 0.26, 0.018)), _x(Vector3(x, -0.15, 0.018))))
	_bake_many(_hatch, ribs, door_mat)
	_chevrons(_hatch, 0.34, 0.06, _x(Vector3(0, -0.255, 0.0115), Vector3(0, 180, 0)), 43.0)
	_stencil(_hatch, "BALE EJECT", 30, Vector3(0, -0.09, 0.0115), Vector3.ZERO, Color(0.1, 0.1, 0.09, 0.7))
	_stencil(_hatch, "STAND CLEAR", 22, Vector3(0, -0.14, 0.0115), Vector3.ZERO, Color(0.1, 0.1, 0.09, 0.6))
	_stencil(_hatch, "P-47CH", 26, Vector3(0, -0.19, 0.0115), Vector3.ZERO, Color(0.1, 0.1, 0.09, 0.55))
	_bake(_hatch, ProcMesh.box(Vector3(0.06, 0.02, 0.03)), Mats.metal("steel"), _x(Vector3(0, -0.29, 0.015)))   # latch
	_bake(_rig, ProcMesh.cyl(0.013, 0.013, 0.4, 10), Mats.metal("steel"), _x(Vector3(0, 0.728, zb + 0.035), Vector3(0, 0, 90)))   # hinge pin
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.box(Vector3(0.03, 0.03, 0.04)), steel, _x(Vector3(0.17 * s, 0.728, zb + 0.02)))
	# Small hatch-lift rams either side.
	for s: float in [-1.0, 1.0]:
		_bake(_rig, ProcMesh.cyl(0.016, 0.016, 0.14, 10), _paint(GREEN, 0.5, 0.7, 44.0 + s, 0.6), _x(Vector3(0.245 * s, 0.6, zb + 0.02)))
		_bake(_rig, ProcMesh.cyl(0.008, 0.008, 0.08, 8), Mats.metal("chrome"), _x(Vector3(0.245 * s, 0.7, zb + 0.02)))


func _build_gauge() -> void:
	# Analog fill dial on the roof, front-right, tilted up toward a following camera.
	var g: Node3D = _node(_rig, Vector3(0.2, BODY_Y1 + 0.045, -0.33), Vector3(52, -28, 0))
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	_bake(_rig, ProcMesh.box(Vector3(0.1, 0.05, 0.08)), steel, _x(Vector3(0.2, BODY_Y1 + 0.015, -0.32)))   # pedestal
	_bake(g, ProcMesh.cyl(0.058, 0.062, 0.03, 24), steel, _x(Vector3(0, 0, -0.005), Vector3(90, 0, 0)))
	var face: StandardMaterial3D = _flat(Color(0.82, 0.8, 0.72), 0.7)
	_bake(g, ProcMesh.cyl(0.049, 0.049, 0.006, 24), face, _x(Vector3(0, 0, -0.019), Vector3(90, 0, 0)))
	var ticks: Array = []
	for k: int in 9:
		var ta: float = deg_to_rad(-120.0 + k * 30.0)
		ticks.append(ProcMesh.part(ProcMesh.box(Vector3(0.003, 0.011, 0.002)), Transform3D(Basis(Vector3(0, 0, -1), ta), Vector3(sin(ta) * 0.037, cos(ta) * 0.037, -0.023))))
	_bake_many(g, ticks, _flat(Color(0.08, 0.08, 0.08)))
	var rz: Array = []
	for k: int in 4:
		var ta: float = deg_to_rad(95.0 + k * 8.0)
		rz.append(ProcMesh.part(ProcMesh.box(Vector3(0.011, 0.006, 0.002)), Transform3D(Basis(Vector3(0, 0, -1), ta + PI * 0.5), Vector3(sin(ta) * 0.043, cos(ta) * 0.043, -0.023))))
	_bake_many(g, rz, _flat(Color(0.55, 0.12, 0.08)))
	_needle = _node(g, Vector3(0, 0, -0.026))
	_bake(_needle, ProcMesh.box(Vector3(0.004, 0.042, 0.002)), _flat(Color(0.1, 0.1, 0.1)), _x(Vector3(0, 0.017, 0)))
	_bake(_needle, ProcMesh.cyl(0.006, 0.006, 0.006, 8), Mats.metal("brass"), _x(Vector3.ZERO, Vector3(90, 0, 0)))
	_bake(g, ProcMesh.cyl(0.051, 0.051, 0.004, 24), Mats.glass(Color(0.6, 0.65, 0.65, 0.18), 0.1), _x(Vector3(0, 0, -0.03), Vector3(90, 0, 0)))
	_gauge_lamp_mat = Mats.lamp(Color(0.45, 0.8, 0.35), 0.6)
	_bake(g, ProcMesh.hemisphere(0.015, 12, 4), _gauge_lamp_mat, _x(Vector3(-0.085, -0.02, -0.012), Vector3(-90, 0, 0)))
	_bake(g, ProcMesh.cyl(0.021, 0.021, 0.016, 12), steel, _x(Vector3(-0.085, -0.02, -0.004), Vector3(90, 0, 0)))


func _build_arm(s: float) -> void:
	var yel: ShaderMaterial = _paint(YELLOW, 0.55, 0.7, 50.0 + s * 3.0, 0.5, -0.7)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var sp := Vector3(ARM_X * s, SHOULDER.y, SHOULDER.z)
	# Shoulder bracket bolted to the body flank.
	_bake(_rig, ProcMesh.box(Vector3(ARM_X - BODY_HW + 0.01, 0.14, 0.14)), steel, _x(Vector3((BODY_HW + ARM_X) * 0.5 * s - 0.02 * s, sp.y, sp.z)))
	_bolts(_rig, [Vector3((BODY_HW + 0.012) * s, sp.y + 0.05, sp.z - 0.05), Vector3((BODY_HW + 0.012) * s, sp.y + 0.05, sp.z + 0.05), Vector3((BODY_HW + 0.012) * s, sp.y - 0.05, sp.z - 0.05), Vector3((BODY_HW + 0.012) * s, sp.y - 0.05, sp.z + 0.05)], Vector3(s, 0, 0), 0.008)
	var shoulder: Node3D = _node(_rig, sp)
	var yaw: Node3D = _node(shoulder, Vector3.ZERO)
	_bake(yaw, ProcMesh.cyl(0.042, 0.042, 0.07, 14), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	var upper: Node3D = _node(yaw, Vector3.ZERO)
	_bake(upper, _rbox(Vector3(0.05, 0.06, L1 + 0.04), 0.012, 2), yel, _x(Vector3(0, 0, -L1 * 0.5)))
	_bake(upper, ProcMesh.cyl(0.013, 0.013, 0.08, 8), Mats.metal("steel"), _x(Vector3(0, 0, -L1), Vector3(0, 0, 90)))
	_bake(upper, ProcMesh.box(Vector3(0.03, 0.035, 0.05)), steel, _x(Vector3(0, -0.045, -0.15)))   # ram lug
	_bake(upper, ProcMesh.box(Vector3(0.03, 0.035, 0.05)), steel, _x(Vector3(0, 0.045, -0.08)))
	_hose(upper, Vector3(0.03 * s, 0.035, -0.02), Vector3(0.042 * s, 0.06, -L1 * 0.5), Vector3(0.03 * s, 0.03, -L1 + 0.02), 0.008)
	var elbow: Node3D = _node(upper, Vector3(0, 0, -L1))
	var fore: Array = []
	fore.append(ProcMesh.part(_rbox(Vector3(0.042, 0.05, L2 + 0.03), 0.01, 2), _x(Vector3(0, 0, -L2 * 0.5 + 0.01))))
	fore.append(ProcMesh.part(ProcMesh.box(Vector3(0.036, 0.07, 0.06)), _x(Vector3(0, 0.03, 0.03), Vector3(30, 0, 0))))   # lever horn
	_bake_many(elbow, fore, yel)
	_bake(elbow, ProcMesh.cyl(0.03, 0.03, 0.064, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	var wrist: Node3D = _node(elbow, Vector3(0, 0, -L2))
	_bake(wrist, ProcMesh.cyl(0.026, 0.026, 0.07, 12), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	# Dustpan scoop: floor, two side walls and a back wall; open at the tip with a worn steel edge.
	var sc: Array = []
	sc.append(ProcMesh.part(ProcMesh.box(Vector3(0.12, 0.008, 0.13)), _x(Vector3(0, -0.03, -0.08))))
	sc.append(ProcMesh.part(ProcMesh.box(Vector3(0.12, 0.06, 0.008)), _x(Vector3(0, -0.002, -0.016))))
	for x: float in [-0.06, 0.06]:
		sc.append(ProcMesh.part(_prism([Vector2(-0.016, -0.034), Vector2(-0.145, -0.034), Vector2(-0.145, -0.022), Vector2(-0.016, 0.028)], 0.007), _x(Vector3(x, 0, 0))))
	_bake_many(wrist, sc, _paint(YELLOW.darkened(0.15), 0.4, 0.8, 52.0 + s, 0.7, -0.2))
	_bake(wrist, ProcMesh.box(Vector3(0.124, 0.01, 0.016)), Mats.metal("steel"), _x(Vector3(0, -0.032, -0.15)))   # wear edge
	_bake(wrist, ProcMesh.box(Vector3(0.06, 0.04, 0.03)), steel, _x(Vector3(0, 0.0, -0.005)))   # wrist block
	# Hinged clamp finger: closes down over a single item lying in the scoop.
	var thumb: Node3D = _node(wrist, Vector3(0, 0.03, -0.02))
	var th: Array = []
	th.append(_tube(0.009, Vector3(-0.035, 0, 0), Vector3(-0.035, 0, -0.09)))
	th.append(_tube(0.009, Vector3(0.035, 0, 0), Vector3(0.035, 0, -0.09)))
	th.append(_tube(0.009, Vector3(-0.035, 0, -0.09), Vector3(-0.03, -0.035, -0.125)))
	th.append(_tube(0.009, Vector3(0.035, 0, -0.09), Vector3(0.03, -0.035, -0.125)))
	th.append(_tube(0.009, Vector3(-0.03, -0.035, -0.125), Vector3(0.03, -0.035, -0.125)))
	_bake_many(thumb, th, Mats.metal("steel"))
	_bake(thumb, ProcMesh.cyl(0.012, 0.012, 0.09, 10), steel, _x(Vector3.ZERO, Vector3(0, 0, 90)))
	_bake(thumb, ProcMesh.box(Vector3(0.07, 0.012, 0.02)), Mats.rubber(), _x(Vector3(0, -0.042, -0.122)))   # rubber pad
	# Rams: shoulder lift (body to boom) and elbow (boom to forearm horn).
	var a1: Node3D = _node(_rig, Vector3(0.35 * s, 0.5, -0.21))
	_bake(_rig, ProcMesh.box(Vector3(0.07, 0.05, 0.05)), steel, _x(Vector3(0.33 * s, 0.5, -0.21)))
	var b1: Node3D = _node(upper, Vector3(0, -0.045, -0.15))
	_add_ram(a1, b1, 0.022, 0.17, yel)
	var a2: Node3D = _node(upper, Vector3(0, 0.062, -0.08))
	var b2: Node3D = _node(elbow, Vector3(0, 0.055, 0.05))
	_add_ram(a2, b2, 0.017, 0.15, yel)
	_hose(_rig, Vector3(0.21 * s, BODY_Y1 + 0.03, -0.12), Vector3((BODY_HW + 0.05) * s, 0.8, -0.2), Vector3((ARM_X - 0.01) * s, sp.y + 0.04, sp.z + 0.02), 0.01)
	_arms.append({"s": s, "yaw": yaw, "upper": upper, "elbow": elbow, "wrist": wrist, "thumb": thumb})


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

## Pick-and-tip keyframes: [t, shoulder pitch, forearm absolute pitch, scoop absolute pitch,
## clamp open 0..1, inward yaw]. Reach out low, close the clamp on one item, lift it over the
## hopper, tip and open, return.
const SCOOP_KEYS: Array = [
	[0.0, 30.0, -105.0, -160.0, 0.3, 0.0],
	[0.2, -16.0, -68.0, -65.0, 1.0, -10.0],
	[0.3, -16.0, -68.0, -65.0, 1.0, -10.0],
	[0.4, -14.0, -70.0, -60.0, 0.0, -8.0],
	[0.66, 66.0, 12.0, -150.0, 0.0, 28.0],
	[0.78, 66.0, 12.0, -165.0, 1.0, 28.0],
	[1.0, 30.0, -105.0, -160.0, 0.3, 0.0],
]
const REST_POSE: Array = [0.0, 40.0, -120.0, -175.0, 0.0, 0.0]


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
		(arm["thumb"] as Node3D).rotation.x = deg_to_rad(2.0 + float(p[4]) * 55.0)
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
	# Arms.
	_scoop_amount = move_toward(_scoop_amount, 1.0 if _scoop_hold > 0.0 else 0.0, delta * 3.0)
	if _scoop_amount > 0.0:
		_scoop_phase = fposmod(_scoop_phase + delta / 2.2, 1.0)
	_scoop_hold = maxf(0.0, _scoop_hold - delta)
	_update_arms()
	# Brushes: turn inward (sweeping toward the centre line) with ground speed and while scooping.
	var brush_rate: float = clampf(absf(_speed) * 4.0, 0.0, 9.0) + _scoop_amount * 5.0
	if sleeping:
		brush_rate = 0.0
	_brush_angle += brush_rate * delta
	for i: int in _brushes.size():
		var side: float = -1.0 if i == 0 else 1.0
		(_brushes[i] as Node3D).rotation.y = _brush_angle * side
	# Suspension: lean from acceleration, tiny dip, mechanical vibration while shuddering.
	_dip = lerpf(_dip, _dip_target, clampf(delta * 10.0, 0.0, 1.0))
	_dip_target = move_toward(_dip_target, 0.0, delta * 0.2)
	var jitter := Vector3.ZERO
	if _shudder_t > 0.0 and not sleeping:
		_shudder_t -= delta
		jitter = Vector3(sin(_time * 91.0), sin(_time * 117.0) * 0.6, sin(_time * 73.0)) * 0.0035
	_rig.position = Vector3(0, -_dip, 0) + jitter
	_rig.rotation = Vector3(_lean.x, 0, _lean.y)
	# Turret: pan toward target, tilt with mood; sleeping slumps it forward.
	_look_yaw = lerp_angle(_look_yaw, _look_target, clampf(delta * 3.0, 0.0, 1.0))
	_pan.rotation.y = _look_yaw
	var tilt_target: float = deg_to_rad(-18.0) if sleeping else deg_to_rad(-5.0 + 8.0 * _iris_target + sin(_time * 0.7) * 1.2)
	_tilt_now = lerpf(_tilt_now, tilt_target, clampf(delta * 2.5, 0.0, 1.0))
	_tilt.rotation.x = _tilt_now
	# Aperture: blades slide and rotate; open = wide.
	var ap: float = 0.0 if sleeping else _iris_target
	_iris_now = lerpf(_iris_now, ap, clampf(delta * 6.0, 0.0, 1.0))
	var r_ap: float = lerpf(0.004, 0.028, _iris_now)
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
	# Compaction rams and hatch.
	for rod: Node3D in _press_rods:
		rod.position.z = 0.22 + _press_now * 0.1
	_hatch.rotation.x = -_hatch_now * deg_to_rad(100.0)


# ---------------------------------------------------------------- interface

func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	_speed = speed
	_wheel_angle -= speed * delta / WHEEL_R
	for w: Node3D in _wheels:
		w.rotation.x = _wheel_angle
	var target := Vector2(clampf(-local_accel.y * 0.004, -0.03, 0.03), clampf(local_accel.x * 0.004, -0.025, 0.025))
	target.x -= 0.004 * clampf(speed_ratio, 0.0, 1.0)   # nose settles a touch under way
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
	_look_target = clampf(atan2(-d.x, -d.z), -1.6, 1.6)


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
