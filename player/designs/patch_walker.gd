extends Node3D
## Patch (unit P-47CH), concept "Walker".
## A low, rounded municipal sanitation hull on four short articulated wheel-legs. A camera-lens head with a
## mechanical aperture iris sits on a two-joint neck boom at the front. One hydraulic crane arm with a
## three-finger grab claw picks single pieces of litter (a can, a sheet of paper, a bottle) off the ground
## and drops them into the hopper in the middle of the deck. A horizontal compaction ram runs along the
## spine and finished bales leave through the hinged rear hatch.
## Faces -Z, base at y = 0. Real-world scale: ~1.4 m to the antenna tip, ~1.1 m long, ~1.1 m wide.

const PAINT_ORANGE := Color(0.66, 0.31, 0.11)
const PAINT_YELLOW := Color(0.72, 0.57, 0.2)
const PAINT_WHITE := Color(0.74, 0.72, 0.66)
const PAINT_DARK := Color(0.16, 0.17, 0.16)
const PAINT_BLACK := Color(0.045, 0.045, 0.045)

const WHEEL_R: float = 0.17
const DECK: float = 0.81
const L_UPPER: float = 0.42
const L_FORE: float = 0.40
const IRIS_BLADES: int = 7
const IRIS_R: float = 0.062

# Arm poses: [yaw, shoulder pitch, elbow, wrist, jaw open] in degrees.
const ARM_REST: Array = [0.0, 165.0, -173.0, -14.0, 6.0]
const ARM_REACH: Array = [0.0, -44.0, -38.0, -8.0, 40.0]
const ARM_GRAB: Array = [0.0, -47.0, -37.0, -6.0, 2.0]
const ARM_DUMP: Array = [-43.0, 101.5, -246.0, 54.6, 2.0]
const ARM_DROP: Array = [-43.0, 101.5, -246.0, 54.6, 40.0]

var chest_point := Vector3(0, 0.98, -0.09)
var back_hatch_point := Vector3(0, 0.6, 0.62)
var vent_points: Array[Vector3] = [Vector3(-0.37, 0.7, 0.3), Vector3(0.37, 0.7, 0.3)]
var stack_point := Vector3(0, 1.03, 0.3)
var lens_point := Vector3(0, 1.17, -0.64)
var sleeping: bool = false

var _lean: Node3D
var _body: Node3D
var _wheels: Array[Node3D] = []
var _front_steer: Array[Node3D] = []
var _neck_yaw: Node3D
var _neck_lo: Node3D
var _neck_hi: Node3D
var _head: Node3D
var _blades: Array[Node3D] = []
var _glow_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _lamp_light: OmniLight3D
var _arm_yaw: Node3D
var _arm_sh: Node3D
var _arm_el: Node3D
var _arm_wr: Node3D
var _jaws: Array[Node3D] = []
var _needle: Node3D
var _fill_lamp_mat: StandardMaterial3D
var _ram_rod: Node3D
var _hatch: Node3D
var _paint_mats: Array[ShaderMaterial] = []
var _paint_cov: Dictionary = {}
var _batches: Dictionary = {}
var _mat_cache: Dictionary = {}

var _time: float = 0.0
var _spin: float = 0.0
var _lean_now := Vector2.ZERO
var _steer_now: float = 0.0
var _scoop_hold: float = 0.0
var _scoop_phase: float = 0.0
var _arm_now: Array = ARM_REST.duplicate()
var _shudder_t: float = 0.0
var _dip: float = 0.0
var _look_target: float = 0.0
var _look_now: float = 0.0
var _iris_target: float = 0.55
var _iris_now: float = 0.55
var _blink_timer: float = 3.5
var _blink: float = 0.0
var _flash_v: float = 0.0
var _fill_now: float = 0.0
var _fill_target: float = 0.0
var _press_t: float = 0.0
var _hatch_t: float = 0.0
var _droop: float = 0.0
var _debug_pose: String = ""


func _ready() -> void:
	_build()
	_debug_pose = OS.get_environment("WALKER_POSE")
	var pose: String = _debug_pose
	if pose == "reach":
		_apply_arm(ARM_REACH)
	elif pose == "dump":
		_apply_arm(ARM_DROP)
	elif pose == "work":
		_apply_arm(ARM_GRAB)
		press(1.0)
		open_hatch(1.0)
		set_happy(1.0)
		_iris_now = 1.0
	_update_iris()


# ---------------------------------------------------------------- building helpers

func _node(parent: Node3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


## Worn paint material, grime anchored to the ground for the node it is used on.
func _paint(node: Node3D, color: Color, coverage: float, rust: float, grime: float = 0.5) -> ShaderMaterial:
	var key: String = "p%d_%s_%.2f_%.2f" % [node.get_instance_id(), color.to_html(), coverage, rust]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: ShaderMaterial = Mats.worn_paint(color, coverage, rust, float(_paint_mats.size()) * 1.37, grime)
	var root_y: float = (global_transform.affine_inverse() * node.global_transform).origin.y
	m.set_shader_parameter("grime_floor", -root_y)
	m.set_shader_parameter("grime_height", 0.55)
	m.set_shader_parameter("tex_scale", 2.2)
	_mat_cache[key] = m
	_paint_mats.append(m)
	_paint_cov[m] = coverage
	return m


func _add(node: Node3D, mat: Material, mesh: Mesh, x: Transform3D) -> void:
	var key: String = "%d_%d" % [node.get_instance_id(), mat.get_instance_id()]
	if not _batches.has(key):
		_batches[key] = {"node": node, "mat": mat, "parts": []}
	(_batches[key]["parts"] as Array).append({"mesh": mesh, "xform": x})


func _commit() -> void:
	for k: String in _batches:
		var b: Dictionary = _batches[k]
		var mi := MeshInstance3D.new()
		mi.mesh = ProcMesh.merge(b["parts"])
		mi.material_override = b["mat"]
		(b["node"] as Node3D).add_child(mi)
	_batches.clear()


func _between(a: Vector3, b: Vector3, hint: Vector3 = Vector3.RIGHT) -> Transform3D:
	var y: Vector3 = (b - a).normalized()
	var x: Vector3 = hint - y * hint.dot(y)
	if x.length() < 0.01:
		x = Vector3.FORWARD - y * y.dot(Vector3.FORWARD)
	x = x.normalized()
	var z: Vector3 = x.cross(y)
	return Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _rod(node: Node3D, mat: Material, a: Vector3, b: Vector3, r: float, segs: int = 12) -> void:
	_add(node, mat, ProcMesh.cyl(r, r, a.distance_to(b), segs), _between(a, b))


func _bar(node: Node3D, mat: Material, a: Vector3, b: Vector3, w: float, d: float, hint: Vector3 = Vector3.RIGHT) -> void:
	_add(node, mat, ProcMesh.box(Vector3(w, a.distance_to(b), d)), _between(a, b, hint))


func _bolt(node: Node3D, pos: Vector3, n: Vector3, r: float = 0.008) -> void:
	_add(node, Mats.metal("dark_steel"), ProcMesh.cyl(r, r, 0.007, 6), _between(pos, pos + n * 0.007))


func _bolt_row(node: Node3D, a: Vector3, b: Vector3, count: int, n: Vector3) -> void:
	for i: int in count:
		_bolt(node, a.lerp(b, float(i) / maxf(1.0, float(count - 1))), n)


## Tube along a smoothed polyline (hoses, rails). flip = normals inward (inner wall of a hood).
func _tube(pts: Array, r: float, segs: int = 10, flip: bool = false) -> ArrayMesh:
	var c := Curve3D.new()
	for p: Vector3 in pts:
		c.add_point(p)
	for i: int in c.point_count:
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (nxt - prev) * 0.22
		c.set_point_in(i, -t)
		c.set_point_out(i, t)
	c.bake_interval = 0.015
	var baked: PackedVector3Array = c.get_baked_points()
	if baked.size() < 2:
		baked = PackedVector3Array([pts[0], pts[pts.size() - 1]])
	var rings: Array = []
	var nref := Vector3.UP
	for i: int in baked.size():
		var t: Vector3 = (baked[mini(i + 1, baked.size() - 1)] - baked[maxi(i - 1, 0)]).normalized()
		if i == 0:
			nref = Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		nref = (nref - t * nref.dot(t)).normalized()
		var bn: Vector3 = t.cross(nref)
		var ring: Array = []
		for s: int in segs + 1:
			var a: float = TAU * float(s) / float(segs)
			var d: Vector3 = nref * cos(a) + bn * sin(a)
			ring.append([baked[i] + d * r, d])
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings.size() - 1:
		for s: int in segs:
			var q: Array = [rings[i][s], rings[i][s + 1], rings[i + 1][s + 1], rings[i + 1][s]]
			var order: Array = [0, 1, 2, 0, 2, 3] if flip else [0, 2, 1, 0, 3, 2]
			for k: int in order:
				st.set_normal(-(q[k][1] as Vector3) if flip else q[k][1])
				st.add_vertex(q[k][0])
	return st.commit()


## Flat double-sided polygon in the XY plane (normal +Z), extruded by a tiny thickness.
func _flat(polys: Array, thick: float = 0.0015) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly: PackedVector2Array in polys:
		var idx: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
		for side: int in 2:
			var z: float = -thick * 0.5 if side == 0 else thick * 0.5
			var nz: float = -1.0 if side == 0 else 1.0
			for t: int in range(0, idx.size(), 3):
				var tri: Array = [idx[t], idx[t + 1], idx[t + 2]]
				if side == 1:
					tri = [idx[t], idx[t + 2], idx[t + 1]]
				for k: int in tri:
					st.set_normal(Vector3(0, 0, nz))
					st.add_vertex(Vector3(poly[k].x, poly[k].y, z))
		# rim
		for i: int in poly.size():
			var p0: Vector2 = poly[i]
			var p1: Vector2 = poly[(i + 1) % poly.size()]
			var e: Vector2 = (p1 - p0).normalized()
			var n := Vector3(e.y, -e.x, 0)
			var quad: Array = [Vector3(p0.x, p0.y, -thick * 0.5), Vector3(p1.x, p1.y, -thick * 0.5), Vector3(p1.x, p1.y, thick * 0.5), Vector3(p0.x, p0.y, thick * 0.5)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n)
				st.add_vertex(quad[k])
	st.generate_normals()
	return st.commit()


## 45-degree hazard stripes clipped to a w x h rectangle. odd picks the alternate set.
func _stripes(w: float, h: float, stripe: float, odd: bool) -> ArrayMesh:
	var rect := PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)])
	var polys: Array = []
	var n: int = int(ceil((w + h) / stripe)) + 1
	for i: int in range(-n, n):
		if (posmod(i, 2) == 1) != odd:
			continue
		var x0: float = float(i) * stripe
		var band := PackedVector2Array([Vector2(x0 - h, -h), Vector2(x0 + stripe - h, -h), Vector2(x0 + stripe + h, h), Vector2(x0 + h, h)])
		for p: PackedVector2Array in Geometry2D.intersect_polygons(band, rect):
			if p.size() >= 3:
				polys.append(p)
	return _flat(polys, 0.002)


func _label(parent: Node3D, text: String, size_px: int, pos: Vector3, rot_deg: Vector3, color: Color = Color(0.88, 0.86, 0.78, 0.7)) -> void:
	var l: Label3D = Mats.stencil(text, size_px, color)
	l.position = pos
	l.rotation_degrees = rot_deg
	l.font = SystemFont.new()
	(l.font as SystemFont).font_names = PackedStringArray(["DejaVu Sans Mono", "Monospace"])
	(l.font as SystemFont).font_weight = 700
	parent.add_child(l)


# ---------------------------------------------------------------- the machine

func _build() -> void:
	_lean = _node(self, Vector3(0, WHEEL_R, 0))
	_body = _node(_lean, Vector3(0, -WHEEL_R, 0))
	_build_hull()
	_build_hopper()
	_build_spine()
	_build_hatch()
	_build_gauge()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_build_leg(sx, sz)
	_build_neck()
	_build_arm()
	_commit()
	var lens_node: Node3D = _head.get_meta("lens")
	lens_point = (global_transform.affine_inverse() * lens_node.global_transform).origin


func _build_hull() -> void:
	var b: Node3D = _body
	var orange: ShaderMaterial = _paint(b, PAINT_ORANGE, 0.62, 0.6, 0.6)
	var orange2: ShaderMaterial = _paint(b, PAINT_ORANGE.darkened(0.06), 0.66, 0.6, 0.5)
	var dark: ShaderMaterial = _paint(b, PAINT_DARK, 0.55, 0.55, 0.7)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	# Main tub and deck.
	_add(b, orange, ProcMesh.rounded_box(Vector3(0.7, 0.46, 1.0), 0.12, 6), ProcMesh.xf(Vector3(0, 0.54, 0.05)))
	_add(b, orange2, ProcMesh.rounded_box(Vector3(0.62, 0.08, 0.88), 0.035, 3), ProcMesh.xf(Vector3(0, DECK - 0.04, 0.05)))
	# Weld seam / rub strip where deck meets tub.
	_add(b, steel, ProcMesh.rounded_box(Vector3(0.5, 0.02, 0.84), 0.01, 2), ProcMesh.xf(Vector3(0, DECK - 0.075, 0.05)))
	# Belly skid plate.
	_add(b, steel, ProcMesh.rounded_box(Vector3(0.5, 0.035, 0.8), 0.015, 2), ProcMesh.xf(Vector3(0, 0.31, 0.05)))
	# Front bumper bar with brackets.
	_add(b, steel, ProcMesh.rounded_box(Vector3(0.62, 0.07, 0.06), 0.02, 2), ProcMesh.xf(Vector3(0, 0.38, -0.47)))
	for x: float in [-0.2, 0.2]:
		_add(b, steel, ProcMesh.box(Vector3(0.04, 0.05, 0.05)), ProcMesh.xf(Vector3(x, 0.38, -0.44)))
		_bolt(b, Vector3(x, 0.38, -0.5), Vector3.FORWARD, 0.01)
	# Front hazard panel.
	var fp := Transform3D(Basis.IDENTITY, Vector3(0, 0.56, -0.452))
	_add(b, dark, ProcMesh.box(Vector3(0.42, 0.13, 0.006)), fp)
	_add(b, _paint(b, PAINT_YELLOW, 0.6, 0.5), _stripes(0.4, 0.11, 0.045, false), fp.translated(Vector3(0, 0, -0.004)))
	_add(b, _paint(b, PAINT_BLACK, 0.85, 0.5), _stripes(0.4, 0.11, 0.045, true), fp.translated(Vector3(0, 0, -0.004)))
	_bolt_row(b, Vector3(-0.2, 0.62, -0.457), Vector3(0.2, 0.62, -0.457), 6, Vector3.FORWARD)
	_bolt_row(b, Vector3(-0.2, 0.5, -0.457), Vector3(0.2, 0.5, -0.457), 6, Vector3.FORWARD)
	# Side panels, bolts, vents, hoses.
	for sx: float in [-1.0, 1.0]:
		var n := Vector3(sx, 0, 0)
		var x: float = sx * 0.353
		_add(b, orange2, ProcMesh.rounded_box(Vector3(0.012, 0.2, 0.3), 0.005, 2), ProcMesh.xf(Vector3(x, 0.54, -0.04)))
		_bolt_row(b, Vector3(x + sx * 0.006, 0.63, -0.17), Vector3(x + sx * 0.006, 0.63, 0.09), 5, n)
		_bolt_row(b, Vector3(x + sx * 0.006, 0.45, -0.17), Vector3(x + sx * 0.006, 0.45, 0.09), 5, n)
		# Louvred vent.
		var vc := Vector3(sx * 0.352, 0.55, 0.3)
		_add(b, steel, ProcMesh.box(Vector3(0.02, 0.18, 0.2)), ProcMesh.xf(vc))
		for i: int in 5:
			_add(b, dark, ProcMesh.box(Vector3(0.03, 0.012, 0.18)), ProcMesh.xf(vc + Vector3(sx * 0.012, -0.065 + i * 0.032, 0), Vector3(0, 0, sx * -35.0)))
		_bolt(b, vc + Vector3(sx * 0.011, 0.08, -0.09), n)
		_bolt(b, vc + Vector3(sx * 0.011, 0.08, 0.09), n)
		_bolt(b, vc + Vector3(sx * 0.011, -0.08, -0.09), n)
		_bolt(b, vc + Vector3(sx * 0.011, -0.08, 0.09), n)
		vent_points[0 if sx < 0 else 1] = vc + Vector3(sx * 0.04, 0, 0)
		# Hydraulic line along the side, clipped on.
		var hz: Array = [Vector3(sx * 0.33, 0.7, -0.38), Vector3(sx * 0.346, 0.69, -0.1), Vector3(sx * 0.346, 0.69, 0.15), Vector3(sx * 0.33, 0.7, 0.42)]
		_add(b, Mats.rubber(), _tube(hz, 0.011, 8), Transform3D.IDENTITY)
		for z: float in [-0.25, 0.0, 0.2]:
			_add(b, steel, ProcMesh.box(Vector3(0.012, 0.03, 0.02)), ProcMesh.xf(Vector3(sx * 0.352, 0.69, z)))
		# Suspension brackets.
		for sz: float in [-1.0, 1.0]:
			_add(b, steel, ProcMesh.box(Vector3(0.05, 0.05, 0.06)), ProcMesh.xf(Vector3(sx * 0.37, 0.63, sz * 0.2)))
	# Serial stencils.
	_label(b, "P-47CH", 64, Vector3(0.362, 0.56, -0.04), Vector3(0, 90, 0))
	_label(b, "P-47CH", 64, Vector3(-0.362, 0.56, -0.04), Vector3(0, -90, 0))
	_label(b, "SANITATION DEPT.  UNIT 47", 20, Vector3(-0.362, 0.49, -0.04), Vector3(0, -90, 0), Color(0.85, 0.83, 0.75, 0.55))
	_label(b, "SANITATION DEPT.  UNIT 47", 20, Vector3(0.362, 0.49, -0.04), Vector3(0, 90, 0), Color(0.85, 0.83, 0.75, 0.55))


func _build_hopper() -> void:
	var b: Node3D = _body
	var yellow: ShaderMaterial = _paint(b, PAINT_YELLOW, 0.55, 0.7, 0.4)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var cz: float = -0.09
	var y0: float = DECK
	# Dark throat.
	var throat := StandardMaterial3D.new()
	throat.albedo_color = Color(0.03, 0.028, 0.025)
	throat.roughness = 0.95
	_add(b, throat, ProcMesh.box(Vector3(0.3, 0.004, 0.27)), ProcMesh.xf(Vector3(0, y0 + 0.002, cz)))
	# Flared walls: front low, back tall.
	_add(b, yellow, ProcMesh.box(Vector3(0.36, 0.08, 0.014)), ProcMesh.xf(Vector3(0, y0 + 0.035, cz - 0.148), Vector3(-20, 0, 0)))
	_add(b, yellow, ProcMesh.box(Vector3(0.36, 0.13, 0.014)), ProcMesh.xf(Vector3(0, y0 + 0.06, cz + 0.15), Vector3(15, 0, 0)))
	for sx: float in [-1.0, 1.0]:
		_add(b, yellow, ProcMesh.box(Vector3(0.014, 0.1, 0.3)), ProcMesh.xf(Vector3(sx * 0.172, y0 + 0.045, cz), Vector3(0, 0, -sx * 14.0)))
		# Rim angle iron.
		_add(b, steel, ProcMesh.box(Vector3(0.025, 0.012, 0.32)), ProcMesh.xf(Vector3(sx * 0.186, y0 + 0.098, cz)))
		# Corner gussets.
		for sz: float in [-1.0, 1.0]:
			_bolt(b, Vector3(sx * 0.16, y0 + 0.004, cz + sz * 0.13), Vector3.UP)
	_add(b, steel, ProcMesh.box(Vector3(0.39, 0.012, 0.025)), ProcMesh.xf(Vector3(0, y0 + 0.07, cz - 0.172)))
	_add(b, steel, ProcMesh.box(Vector3(0.39, 0.012, 0.025)), ProcMesh.xf(Vector3(0, y0 + 0.124, cz + 0.168)))
	# Rubber flap curtain at the back.
	for i: int in 5:
		_add(b, Mats.rubber(Color(0.07, 0.07, 0.07)), ProcMesh.box(Vector3(0.062, 0.07, 0.006)), ProcMesh.xf(Vector3(-0.13 + i * 0.065, y0 + 0.04, cz + 0.12), Vector3(18, 0, 0)))
	chest_point = Vector3(0, y0 + 0.08, cz)


func _build_spine() -> void:
	var b: Node3D = _body
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	var dark: ShaderMaterial = _paint(b, PAINT_DARK, 0.6, 0.5, 0.4)
	var y: float = DECK + 0.055
	# Front clevis bracket and barrel.
	_add(b, steel, ProcMesh.box(Vector3(0.09, 0.07, 0.03)), ProcMesh.xf(Vector3(0, y - 0.025, 0.085)))
	_rod(b, steel, Vector3(-0.05, y, 0.085), Vector3(0.05, y, 0.085), 0.012)
	_rod(b, dark, Vector3(0, y, 0.1), Vector3(0, y, 0.34), 0.042, 16)
	_rod(b, steel, Vector3(0, y, 0.1), Vector3(0, y, 0.118), 0.047, 16)
	_rod(b, steel, Vector3(0, y, 0.322), Vector3(0, y, 0.342), 0.047, 16)
	_add(b, steel, ProcMesh.box(Vector3(0.11, 0.05, 0.03)), ProcMesh.xf(Vector3(0, y - 0.03, 0.33)))
	# Hydraulic feed hoses to the barrel.
	_add(b, Mats.rubber(), _tube([Vector3(0.03, y + 0.03, 0.115), Vector3(0.07, y + 0.04, 0.09), Vector3(0.12, DECK + 0.005, 0.07)], 0.009, 8), Transform3D.IDENTITY)
	_add(b, Mats.rubber(), _tube([Vector3(-0.03, y + 0.03, 0.33), Vector3(-0.08, y + 0.03, 0.3), Vector3(-0.13, DECK + 0.005, 0.26)], 0.009, 8), Transform3D.IDENTITY)
	# Moving rod and crosshead.
	_ram_rod = _node(b, Vector3(0, y, 0.34))
	_rod(_ram_rod, chrome, Vector3(0, 0, 0), Vector3(0, 0, 0.1), 0.02)
	_add(_ram_rod, steel, ProcMesh.box(Vector3(0.2, 0.05, 0.035)), ProcMesh.xf(Vector3(0, -0.01, 0.11)))
	# Guide rails for the crosshead.
	for sx: float in [-1.0, 1.0]:
		_add(b, steel, ProcMesh.box(Vector3(0.02, 0.03, 0.2)), ProcMesh.xf(Vector3(sx * 0.11, DECK + 0.015, 0.44)))
	# Bale rack: two tube rails on posts.
	for sx: float in [-1.0, 1.0]:
		var r: Array = [Vector3(sx * 0.22, DECK + 0.01, 0.12), Vector3(sx * 0.22, DECK + 0.1, 0.15), Vector3(sx * 0.22, DECK + 0.105, 0.44), Vector3(sx * 0.22, DECK + 0.01, 0.47)]
		_add(b, _paint(b, PAINT_YELLOW, 0.4, 0.8, 0.3), _tube(r, 0.014, 10), Transform3D.IDENTITY)
		for z: float in [0.12, 0.47]:
			_add(b, steel, ProcMesh.box(Vector3(0.04, 0.02, 0.04)), ProcMesh.xf(Vector3(sx * 0.22, DECK + 0.005, z)))
	stack_point = Vector3(0, DECK + 0.125, 0.3)


func _build_hatch() -> void:
	var b: Node3D = _body
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.025, 0.022, 0.02)
	hole.roughness = 0.95
	_add(b, hole, ProcMesh.box(Vector3(0.36, 0.2, 0.02)), ProcMesh.xf(Vector3(0, 0.545, 0.545)))
	# Frame.
	_add(b, steel, ProcMesh.box(Vector3(0.42, 0.025, 0.02)), ProcMesh.xf(Vector3(0, 0.66, 0.556)))
	_add(b, steel, ProcMesh.box(Vector3(0.42, 0.025, 0.02)), ProcMesh.xf(Vector3(0, 0.43, 0.556)))
	for sx: float in [-1.0, 1.0]:
		_add(b, steel, ProcMesh.box(Vector3(0.025, 0.24, 0.02)), ProcMesh.xf(Vector3(sx * 0.198, 0.545, 0.556)))
		_rod(b, steel, Vector3(sx * 0.18, 0.67, 0.575), Vector3(sx * 0.12, 0.67, 0.575), 0.013)
	_hatch = _node(b, Vector3(0, 0.67, 0.575))
	var door := _paint(_hatch, PAINT_ORANGE.darkened(0.05), 0.5, 0.75, 0.6)
	_add(_hatch, door, ProcMesh.rounded_box(Vector3(0.39, 0.235, 0.025), 0.008, 2), ProcMesh.xf(Vector3(0, -0.12, 0.0)))
	var sp := Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0.0145))
	_add(_hatch, _paint(_hatch, PAINT_YELLOW, 0.55, 0.6), _stripes(0.37, 0.055, 0.035, false), sp)
	_add(_hatch, _paint(_hatch, PAINT_BLACK, 0.85, 0.6), _stripes(0.37, 0.055, 0.035, true), sp)
	_rod(_hatch, steel, Vector3(-0.11, 0, 0), Vector3(0.11, 0, 0), 0.013)
	# Strap hinges, latch handle.
	for sx: float in [-1.0, 1.0]:
		_add(_hatch, steel, ProcMesh.box(Vector3(0.035, 0.12, 0.008)), ProcMesh.xf(Vector3(sx * 0.14, -0.055, 0.016)))
		_bolt(_hatch, Vector3(sx * 0.14, -0.03, 0.02), Vector3.BACK)
		_bolt(_hatch, Vector3(sx * 0.14, -0.09, 0.02), Vector3.BACK)
	_bar(_hatch, steel, Vector3(-0.06, -0.155, 0.03), Vector3(0.06, -0.155, 0.03), 0.014, 0.014, Vector3.UP)
	_bar(_hatch, steel, Vector3(-0.06, -0.155, 0.03), Vector3(-0.06, -0.155, 0.012), 0.014, 0.014)
	_bar(_hatch, steel, Vector3(0.06, -0.155, 0.03), Vector3(0.06, -0.155, 0.012), 0.014, 0.014)
	_label(_hatch, "P-47CH", 36, Vector3(0, -0.09, 0.0135), Vector3(0, 0, 0), Color(0.9, 0.88, 0.8, 0.6))
	back_hatch_point = Vector3(0, 0.545, 0.62)


func _build_gauge() -> void:
	var g := _node(_body, Vector3(-0.215, DECK + 0.005, -0.28), Vector3(-28, 0, 0))
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.78, 0.76, 0.68)
	face.roughness = 0.6
	_add(g, steel, ProcMesh.cyl(0.058, 0.062, 0.035, 20), ProcMesh.xf(Vector3(0, 0.0175, 0)))
	_add(g, face, ProcMesh.cyl(0.05, 0.05, 0.004, 24), ProcMesh.xf(Vector3(0, 0.036, 0)))
	_add(g, Mats.metal("brass"), ProcMesh.torus(0.049, 0.06, 24, 6), ProcMesh.xf(Vector3(0, 0.038, 0), Vector3.ZERO, Vector3(1, 0.5, 1)))
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.05, 0.05, 0.05)
	ink.roughness = 0.7
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.08, 0.05)
	red.roughness = 0.6
	for i: int in 9:
		var a: float = deg_to_rad(-120.0 + 240.0 * float(i) / 8.0)
		var d := Vector3(sin(a), 0, -cos(a))
		_add(g, red if i >= 7 else ink, ProcMesh.box(Vector3(0.003, 0.002, 0.012)), Transform3D(Basis(Vector3.UP, -a), Vector3(0, 0.039, 0) + d * 0.04))
	_needle = _node(g, Vector3(0, 0.041, 0))
	_add(_needle, red, ProcMesh.box(Vector3(0.003, 0.002, 0.042)), ProcMesh.xf(Vector3(0, 0, -0.016)))
	_add(_needle, ink, ProcMesh.cyl(0.006, 0.006, 0.004, 10), Transform3D.IDENTITY)
	# Glass.
	var gl := Mats.glass(Color(0.6, 0.65, 0.7, 0.18), 0.05)
	_add(g, gl, ProcMesh.cyl(0.05, 0.05, 0.002, 24), ProcMesh.xf(Vector3(0, 0.047, 0)))
	# Status lamp next to it.
	_fill_lamp_mat = Mats.lamp(Color(0.35, 0.9, 0.35), 1.5)
	_add(g, steel, ProcMesh.cyl(0.016, 0.018, 0.02, 10), ProcMesh.xf(Vector3(0.085, 0.01, 0.02)))
	_add(g, _fill_lamp_mat, ProcMesh.hemisphere(0.013, 10, 4), ProcMesh.xf(Vector3(0.085, 0.02, 0.02)))
	_set_needle(0.0)


func _build_leg(sx: float, sz: float) -> void:
	var b: Node3D = _body
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	var dark: ShaderMaterial = _paint(b, PAINT_DARK, 0.6, 0.6, 0.8)
	var hip := Vector3(sx * 0.355, 0.44, sz * 0.31)
	var knee := Vector3(sx * 0.47, 0.6, sz * 0.4)
	var axle := Vector3(sx * 0.485, WHEEL_R, sz * 0.44)
	# Hip housing.
	_rod(b, steel, hip - Vector3(sx * 0.03, 0, 0), hip + Vector3(sx * 0.055, 0, 0), 0.065, 16)
	_rod(b, chrome, hip + Vector3(sx * 0.05, 0, 0), hip + Vector3(sx * 0.07, 0, 0), 0.022, 10)
	# Thigh: twin plates.
	for o: float in [-0.022, 0.022]:
		var off := Vector3(0, 0, o)
		_bar(b, dark, hip + Vector3(sx * 0.04, 0, 0) + off, knee + off, 0.07, 0.014, Vector3.UP)
	# Knee.
	_rod(b, steel, knee - Vector3(sx * 0.04, 0, 0), knee + Vector3(sx * 0.04, 0, 0), 0.05, 14)
	_rod(b, chrome, knee + Vector3(sx * 0.04, 0, 0), knee + Vector3(sx * 0.05, 0, 0), 0.02, 8)
	# Shin.
	_add(b, dark, ProcMesh.rounded_box(Vector3(0.065, knee.distance_to(axle), 0.08), 0.02, 2), _between(knee, axle, Vector3.RIGHT))
	# Suspension strut from the hull bracket into the shin.
	var top := Vector3(sx * 0.38, 0.63, sz * 0.2)
	var low: Vector3 = knee.lerp(axle, 0.45) - Vector3(sx * 0.03, 0, 0)
	var mid: Vector3 = top.lerp(low, 0.5)
	_rod(b, steel, top, mid, 0.018)
	_rod(b, chrome, mid, low, 0.01)
	_add(b, steel, ProcMesh.box(Vector3(0.03, 0.03, 0.03)), ProcMesh.xf(low))
	# Hose from hull to knee.
	_add(b, Mats.rubber(), _tube([Vector3(sx * 0.35, 0.58, sz * 0.25), Vector3(sx * 0.41, 0.64, sz * 0.31), knee + Vector3(-sx * 0.02, 0.03, -sz * 0.03)], 0.008, 8), Transform3D.IDENTITY)
	# Wheel.
	var hub: Vector3 = axle + Vector3(sx * 0.085, 0, 0)
	_rod(b, steel, axle - Vector3(sx * 0.02, 0, 0), hub, 0.022, 10)
	var steer := _node(b, hub)
	if sz < 0:
		_front_steer.append(steer)
	var spin := _node(steer, Vector3.ZERO)
	_wheels.append(spin)
	var tyre := MeshInstance3D.new()
	tyre.mesh = AssetLib.model_mesh("old_tyre")
	tyre.transform = ProcMesh.xf(Vector3.ZERO, Vector3(0, 90, 0), Vector3.ONE * (WHEEL_R * 2.0 / 0.6))
	spin.add_child(tyre)
	var rim := _paint(spin, PAINT_YELLOW.darkened(0.15), 0.45, 0.8, 0.9)
	_rod(spin, rim, Vector3(-0.038, 0, 0), Vector3(0.038, 0, 0), 0.095, 16)
	_rod(spin, steel, Vector3(sx * 0.03, 0, 0), Vector3(sx * 0.05, 0, 0), 0.035, 8)
	for i: int in 5:
		var a: float = TAU * float(i) / 5.0
		_bolt(spin, Vector3(sx * 0.039, sin(a) * 0.06, cos(a) * 0.06), Vector3(sx, 0, 0), 0.006)


func _build_neck() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	_neck_yaw = _node(_body, Vector3(0, DECK, -0.3))
	var collar := _paint(_neck_yaw, PAINT_DARK, 0.6, 0.5, 0.3)
	_add(_neck_yaw, steel, ProcMesh.cyl(0.075, 0.08, 0.03, 20), ProcMesh.xf(Vector3(0, 0.015, 0)))
	_add(_neck_yaw, collar, ProcMesh.cyl(0.06, 0.068, 0.04, 18), ProcMesh.xf(Vector3(0, 0.05, 0)))
	for sx: float in [-1.0, 1.0]:
		_add(_neck_yaw, collar, ProcMesh.box(Vector3(0.015, 0.07, 0.06)), ProcMesh.xf(Vector3(sx * 0.04, 0.09, 0)))
	_rod(_neck_yaw, chrome, Vector3(-0.055, 0.1, 0), Vector3(0.055, 0.1, 0), 0.012)
	_neck_lo = _node(_neck_yaw, Vector3(0, 0.1, 0), Vector3(80, 0, 0))
	var white_lo := _paint(_neck_lo, PAINT_WHITE, 0.6, 0.6, 0.2)
	_add(_neck_lo, white_lo, ProcMesh.rounded_box(Vector3(0.08, 0.065, 0.21), 0.022, 2), ProcMesh.xf(Vector3(0, 0, -0.1)))
	# Parallel hydraulic ram on the neck.
	_rod(_neck_lo, steel, Vector3(0, 0.048, -0.01), Vector3(0, 0.04, -0.11), 0.013)
	_rod(_neck_lo, chrome, Vector3(0, 0.048, -0.11), Vector3(0, 0.048, -0.19), 0.007)
	_add(_neck_lo, Mats.rubber(), _tube([Vector3(0.04, -0.025, 0.0), Vector3(0.046, -0.03, -0.1), Vector3(0.04, -0.025, -0.2)], 0.007, 8), Transform3D.IDENTITY)
	_rod(_neck_lo, steel, Vector3(-0.045, 0, -0.2), Vector3(0.045, 0, -0.2), 0.024, 14)
	_neck_hi = _node(_neck_lo, Vector3(0, 0, -0.2), Vector3(-35, 0, 0))
	var white_hi := _paint(_neck_hi, PAINT_WHITE, 0.6, 0.6, 0.2)
	_add(_neck_hi, white_hi, ProcMesh.rounded_box(Vector3(0.07, 0.06, 0.07), 0.02, 2), ProcMesh.xf(Vector3(0, 0, -0.03)))
	# Yoke around the head.
	_add(_neck_hi, steel, ProcMesh.box(Vector3(0.27, 0.035, 0.03)), ProcMesh.xf(Vector3(0, 0, -0.06)))
	for sx: float in [-1.0, 1.0]:
		_add(_neck_hi, white_hi, ProcMesh.rounded_box(Vector3(0.016, 0.06, 0.11), 0.006, 2), ProcMesh.xf(Vector3(sx * 0.128, 0, -0.105)))
	_head = _node(_neck_hi, Vector3(0, 0, -0.15), Vector3(-45, 0, 0))
	_build_head()


func _build_head() -> void:
	var h: Node3D = _head
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var white := _paint(h, PAINT_WHITE, 0.62, 0.55, 0.15)
	# Housing: a squat rounded can, slightly wider than tall.
	_add(h, white, ProcMesh.rounded_box(Vector3(0.22, 0.165, 0.19), 0.068, 5), ProcMesh.xf(Vector3(0, 0.01, -0.01)))
	# Pivot bosses into the yoke.
	for sx: float in [-1.0, 1.0]:
		_rod(h, steel, Vector3(sx * 0.105, 0, 0), Vector3(sx * 0.122, 0, 0), 0.03, 14)
		_bolt(h, Vector3(sx * 0.137, 0, 0), Vector3(sx, 0, 0), 0.01)
	# Rivets along the housing seam.
	for k: int in 4:
		for sx2: float in [-1.0, 1.0]:
			_bolt(h, Vector3(sx2 * 0.111, -0.04 + k * 0.03, 0.045), Vector3(sx2, 0, 0), 0.005)
	# Lens barrel.
	var fz: float = -0.135
	_rod(h, steel, Vector3(0, 0.005, -0.09), Vector3(0, 0.005, fz), 0.075, 24)
	# Hood: outer and inner walls plus lip.
	var hood_a := Vector3(0, 0.005, fz + 0.002)
	var hood_b := Vector3(0, 0.005, fz - 0.03)
	_add(h, steel, _tube([hood_a, hood_b], 0.084, 24), Transform3D.IDENTITY)
	var hood_in := StandardMaterial3D.new()
	hood_in.albedo_color = Color(0.03, 0.03, 0.03)
	hood_in.roughness = 0.6
	hood_in.metallic = 0.5
	_add(h, hood_in, _tube([hood_a, hood_b], 0.08, 24, true), Transform3D.IDENTITY)
	_add(h, steel, ProcMesh.torus(0.079, 0.086, 24, 6), ProcMesh.xf(hood_b, Vector3(90, 0, 0)))
	# Sensor: dark glass with a soft warm glow in the middle.
	var aperture := _node(h, Vector3(0, 0.005, fz))
	var sensor := Mats.glass(Color(0.02, 0.025, 0.03, 1.0), 0.1)
	_add(aperture, sensor, ProcMesh.cyl(0.074, 0.074, 0.002, 24), ProcMesh.xf(Vector3(0, 0, -0.001), Vector3(90, 0, 0)))
	_glow_mat = Mats.lamp(Color(1.0, 0.72, 0.42), 1.4)
	_add(aperture, _glow_mat, ProcMesh.sphere(0.022, 14, 6), ProcMesh.xf(Vector3(0, 0, -0.0), Vector3.ZERO, Vector3(1, 1, 0.25)))
	# Iris blades.
	var blade_mesh: ArrayMesh = _blade_mesh()
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.3, 0.3, 0.31)
	blade_mat.metallic = 0.9
	blade_mat.roughness = 0.38
	for i: int in IRIS_BLADES:
		var a: float = TAU * float(i) / float(IRIS_BLADES)
		var piv := _node(aperture, Vector3(cos(a) * IRIS_R, sin(a) * IRIS_R, -0.0045 - 0.0008 * i))
		piv.set_meta("base", a)
		var mi := MeshInstance3D.new()
		mi.mesh = blade_mesh
		mi.material_override = blade_mat
		piv.add_child(mi)
		_blades.append(piv)
	# Bezel ring over the blade roots, then the front element.
	_add(aperture, steel, ProcMesh.torus(0.046, 0.08, 28, 8), ProcMesh.xf(Vector3(0, 0, -0.013), Vector3(90, 0, 0), Vector3(1, 1, 0.3)))
	_add(aperture, Mats.glass(Color(0.1, 0.12, 0.14, 0.22), 0.02), ProcMesh.sphere(0.07, 24, 8), ProcMesh.xf(Vector3(0, 0, -0.016), Vector3.ZERO, Vector3(1, 1, 0.12)))
	var lens_node := _node(aperture, Vector3(0, 0, -0.04))
	h.set_meta("lens", lens_node)
	# Small focus motor on the side and a cable into the neck.
	_rod(h, steel, Vector3(0.09, -0.05, -0.08), Vector3(0.09, -0.05, -0.11), 0.017, 10)
	_add(h, Mats.rubber(), _tube([Vector3(0.0, -0.06, 0.07), Vector3(0.0, -0.09, 0.09), Vector3(0.0, -0.1, 0.13)], 0.008, 8), Transform3D.IDENTITY)
	# Rear vents on the head.
	# Antenna with lamp.
	var amount := Vector3(-0.06, 0.09, 0.04)
	_add(h, steel, ProcMesh.cyl(0.014, 0.018, 0.02, 10), ProcMesh.xf(amount + Vector3(0, 0.005, 0)))
	_rod(h, Mats.metal("steel"), amount, amount + Vector3(0, 0.13, 0), 0.0035, 6)
	_lamp_mat = Mats.lamp(Color(1.0, 0.55, 0.15), 1.2)
	var bulb_p: Vector3 = amount + Vector3(0, 0.145, 0)
	_add(h, _lamp_mat, ProcMesh.sphere(0.014, 12, 6), ProcMesh.xf(bulb_p))
	# Wire cage over the bulb.
	for k: int in 3:
		var a: float = TAU * float(k) / 3.0
		_add(h, steel, _tube([bulb_p + Vector3(cos(a) * 0.014, -0.014, sin(a) * 0.014), bulb_p + Vector3(cos(a) * 0.019, 0.0, sin(a) * 0.019), bulb_p + Vector3(0, 0.02, 0)], 0.0015, 4), Transform3D.IDENTITY)
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = bulb_p
	_lamp_light.light_color = Color(1.0, 0.6, 0.25)
	_lamp_light.light_energy = 0.15
	_lamp_light.omni_range = 0.6
	h.add_child(_lamp_light)
	_label(h, "47", 36, Vector3(-0.111, 0.02, -0.01), Vector3(0, -90, 0), Color(0.15, 0.14, 0.12, 0.8))


## One curved iris blade, local origin at its pivot, extending along +X.
func _blade_mesh() -> ArrayMesh:
	var L: float = 0.056
	var W: float = 0.044
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var n: int = 8
	for i: int in n + 1:
		var t: float = float(i) / float(n)
		var c := Vector2(L * t, 0.008 * sin(PI * t))
		var w: float = W * (0.55 + 0.45 * sin(PI * minf(1.0, t * 1.3)))
		top.append(c + Vector2(0, w * 0.5))
		bot.append(c - Vector2(0, w * 0.5))
	var poly := PackedVector2Array()
	for p: Vector2 in top:
		poly.append(p)
	for i: int in range(bot.size() - 1, -1, -1):
		poly.append(bot[i])
	return _flat([poly], 0.0008)


func _build_arm() -> void:
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	_arm_yaw = _node(_body, Vector3(0.275, DECK, -0.32))
	var base := _paint(_arm_yaw, PAINT_DARK, 0.6, 0.6, 0.4)
	_add(_arm_yaw, steel, ProcMesh.cyl(0.07, 0.075, 0.025, 18), ProcMesh.xf(Vector3(0, 0.0125, 0)))
	_add(_arm_yaw, base, ProcMesh.cyl(0.055, 0.062, 0.03, 16), ProcMesh.xf(Vector3(0, 0.04, 0)))
	for sx: float in [-1.0, 1.0]:
		_add(_arm_yaw, base, ProcMesh.rounded_box(Vector3(0.014, 0.07, 0.08), 0.006, 2), ProcMesh.xf(Vector3(sx * 0.045, 0.07, 0)))
	_rod(_arm_yaw, chrome, Vector3(-0.06, 0.07, 0), Vector3(0.06, 0.07, 0), 0.013)
	_arm_sh = _node(_arm_yaw, Vector3(0, 0.07, 0))
	var yel := _paint(_arm_sh, PAINT_YELLOW, 0.55, 0.65, 0.4)
	_add(_arm_sh, yel, ProcMesh.rounded_box(Vector3(0.055, 0.06, L_UPPER + 0.03), 0.018, 2), ProcMesh.xf(Vector3(0, 0, -L_UPPER * 0.5)))
	_rod(_arm_sh, steel, Vector3(-0.038, 0, 0), Vector3(0.038, 0, 0), 0.032, 14)
	# Lift ram under the boom.
	_rod(_arm_sh, steel, Vector3(0, -0.045, -0.03), Vector3(0, -0.045, -0.2), 0.017)
	_rod(_arm_sh, chrome, Vector3(0, -0.045, -0.2), Vector3(0, -0.045, -0.33), 0.009)
	_add(_arm_sh, steel, ProcMesh.box(Vector3(0.03, 0.03, 0.03)), ProcMesh.xf(Vector3(0, -0.04, -0.34)))
	_add(_arm_sh, Mats.rubber(), _tube([Vector3(0.03, 0.03, -0.02), Vector3(0.036, 0.04, -0.2), Vector3(0.03, 0.03, -0.39)], 0.008, 8), Transform3D.IDENTITY)
	_bolt_row(_arm_sh, Vector3(0.028, 0, -0.06), Vector3(0.028, 0, -0.36), 4, Vector3.RIGHT)
	_arm_el = _node(_arm_sh, Vector3(0, 0, -L_UPPER))
	var yel2 := _paint(_arm_el, PAINT_YELLOW, 0.5, 0.7, 0.4)
	_rod(_arm_el, steel, Vector3(-0.04, 0, 0), Vector3(0.04, 0, 0), 0.03, 14)
	_add(_arm_el, yel2, ProcMesh.rounded_box(Vector3(0.045, 0.05, L_FORE), 0.015, 2), ProcMesh.xf(Vector3(0, 0, -L_FORE * 0.5)))
	_rod(_arm_el, steel, Vector3(0, 0.04, -0.02), Vector3(0, 0.04, -0.2), 0.013)
	_rod(_arm_el, chrome, Vector3(0, 0.04, -0.2), Vector3(0, 0.04, -0.33), 0.007)
	_add(_arm_el, Mats.rubber(), _tube([Vector3(-0.027, 0.02, 0.0), Vector3(-0.032, 0.025, -0.2), Vector3(-0.027, 0.02, -0.37)], 0.007, 8), Transform3D.IDENTITY)
	_arm_wr = _node(_arm_el, Vector3(0, 0, -L_FORE))
	_rod(_arm_wr, steel, Vector3(-0.032, 0, 0), Vector3(0.032, 0, 0), 0.026, 12)
	# Claw palm: a short housing with three fingers (two on one side, one opposing) for single items.
	_add(_arm_wr, steel, ProcMesh.cyl(0.035, 0.03, 0.05, 12), ProcMesh.xf(Vector3(0, 0, -0.035), Vector3(90, 0, 0)))
	_add(_arm_wr, _paint(_arm_wr, PAINT_DARK, 0.5, 0.6, 0.5), ProcMesh.rounded_box(Vector3(0.08, 0.06, 0.03), 0.01, 2), ProcMesh.xf(Vector3(0, 0, -0.065)))
	var finger_mat: StandardMaterial3D = Mats.metal("steel")
	for spec: Array in [[1.0, -0.024], [1.0, 0.024], [-1.0, 0.0]]:
		var side: float = spec[0]
		var j := _node(_arm_wr, Vector3(spec[1], side * 0.022, -0.075))
		j.set_meta("side", side)
		_jaws.append(j)
		_rod(j, steel, Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), 0.009, 8)
		var p0 := Vector3(0, 0, 0)
		var p1 := Vector3(0, side * 0.012, -0.06)
		var p2 := Vector3(0, side * 0.0, -0.105)
		var p3 := Vector3(0, -side * 0.018, -0.125)
		_bar(j, finger_mat, p0, p1, 0.016, 0.011)
		_bar(j, finger_mat, p1, p2, 0.014, 0.01)
		_bar(j, finger_mat, p2, p3, 0.012, 0.009)
		_add(j, Mats.rubber(Color(0.1, 0.1, 0.1)), ProcMesh.box(Vector3(0.017, 0.006, 0.03)), _between(p2, p3).translated(Vector3(0, -side * 0.003, 0)))
	_apply_arm(ARM_REST)


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	_time += delta
	# Arm.
	var target: Array
	if _scoop_hold > 0.0:
		_scoop_hold -= delta
		_scoop_phase = fmod(_scoop_phase + delta / 1.7, 1.0)
		target = _arm_cycle(_scoop_phase)
		for i: int in 5:
			_arm_now[i] = lerpf(_arm_now[i], target[i], clampf(delta * 14.0, 0.0, 1.0))
	elif _debug_pose == "":
		_scoop_phase = 0.0
		for i: int in 5:
			_arm_now[i] = lerpf(_arm_now[i], ARM_REST[i], clampf(delta * 4.0, 0.0, 1.0))
	if _debug_pose == "" or _scoop_hold > 0.0:
		_apply_arm(_arm_now)
	# Head.
	_droop = lerpf(_droop, 1.0 if sleeping else 0.0, clampf(delta * 2.0, 0.0, 1.0))
	_look_now = lerp_angle(_look_now, _look_target, clampf(delta * 5.0, 0.0, 1.0))
	var idle: float = 0.0 if sleeping else sin(_time * 0.7) * 0.03 + sin(_time * 1.9) * 0.01
	_neck_yaw.rotation.y = _look_now + idle
	_neck_lo.rotation.x = deg_to_rad(80.0 - 45.0 * _droop)
	_neck_hi.rotation.x = deg_to_rad(-35.0 - 20.0 * _droop)
	var scoop_look: float = 12.0 if _scoop_hold > 0.0 else 0.0
	_head.rotation.x = deg_to_rad(-45.0 + 30.0 * _droop - scoop_look + sin(_time * 0.53) * 1.5)
	# Iris.
	_blink_timer -= delta
	if _blink_timer <= 0.0 and not sleeping:
		_blink = 1.0
		_blink_timer = randf_range(3.5, 7.5)
	_blink = maxf(0.0, _blink - delta * 5.0)
	var want: float = 0.0 if sleeping else _iris_target
	_iris_now = lerpf(_iris_now, want, clampf(delta * 6.0, 0.0, 1.0))
	_update_iris()
	# Lamps.
	_flash_v = maxf(0.0, _flash_v - delta * 2.5)
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.2)
	var lamp_e: float = (0.0 if sleeping else 0.6 + 0.5 * pulse) + _flash_v * 5.0
	_lamp_mat.emission_energy_multiplier = lamp_e
	_lamp_light.light_energy = 0.05 + lamp_e * 0.12
	_glow_mat.emission_energy_multiplier = (0.15 if sleeping else 1.1 + 0.5 * _iris_now)
	# Gauge needle (damped, a little overshoot like a real movement).
	_fill_now = lerpf(_fill_now, _fill_target, clampf(delta * 3.0, 0.0, 1.0))
	_set_needle(_fill_now + sin(_time * 23.0) * 0.003 * (1.0 if _shudder_t > 0.0 else 0.0))
	# Body: lean, shudder, dip.
	_shudder_t = maxf(0.0, _shudder_t - delta)
	var sh: float = minf(1.0, _shudder_t * 4.0)
	_dip = lerpf(_dip, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	_lean.position = Vector3(sin(_time * 61.0) * 0.003 * sh, WHEEL_R - _dip + sin(_time * 47.0) * 0.002 * sh, sin(_time * 53.0) * 0.002 * sh)
	_lean.rotation = Vector3(_lean_now.x, 0.0, _lean_now.y + sin(_time * 39.0) * 0.004 * sh)
	_ram_rod.position.z = 0.34 + 0.09 * _press_t
	_hatch.rotation.x = -1.75 * _hatch_t


func _arm_cycle(p: float) -> Array:
	var keys: Array = [[0.0, ARM_REST], [0.24, ARM_REACH], [0.36, ARM_GRAB], [0.64, ARM_DUMP], [0.74, ARM_DROP], [1.0, ARM_REST]]
	for k: int in keys.size() - 1:
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if p <= b[0]:
			var t: float = smoothstep(0.0, 1.0, (p - float(a[0])) / (float(b[0]) - float(a[0])))
			var out: Array = []
			for i: int in 5:
				out.append(lerpf(a[1][i], b[1][i], t))
			return out
	return ARM_REST


func _apply_arm(p: Array) -> void:
	_arm_yaw.rotation.y = deg_to_rad(p[0])
	_arm_sh.rotation.x = deg_to_rad(p[1])
	_arm_el.rotation.x = deg_to_rad(p[2])
	_arm_wr.rotation.x = deg_to_rad(p[3])
	for j: Node3D in _jaws:
		j.rotation.x = deg_to_rad(float(p[4]) * float(j.get_meta("side")))


func _update_iris() -> void:
	var open: float = clampf(_iris_now * (1.0 - _blink), 0.0, 1.0)
	var swing: float = deg_to_rad(lerpf(160.0, 95.0, open))
	for b: Node3D in _blades:
		b.rotation.z = float(b.get_meta("base")) + swing


func _set_needle(r: float) -> void:
	_needle.rotation.y = -deg_to_rad(-120.0 + 240.0 * clampf(r, 0.0, 1.05))


# ---------------------------------------------------------------- interface

func set_motion(speed: float, speed_ratio: float, local_accel: Vector2, delta: float) -> void:
	_spin -= speed * delta / WHEEL_R
	for w: Node3D in _wheels:
		w.rotation.x = _spin
	var target := Vector2(clampf(-local_accel.y * 0.004, -0.035, 0.035), clampf(local_accel.x * 0.003, -0.03, 0.03))
	_lean_now = _lean_now.lerp(target, clampf(delta * 5.0, 0.0, 1.0))
	_steer_now = lerpf(_steer_now, clampf(-local_accel.x * 0.02, -0.3, 0.3) * clampf(speed_ratio * 2.0, 0.0, 1.0), clampf(delta * 6.0, 0.0, 1.0))
	for s: Node3D in _front_steer:
		s.rotation.y = _steer_now


func set_scooping(active: bool) -> void:
	if active:
		_scoop_hold = 0.15


func set_fill(ratio: float, band: Array) -> void:
	_fill_target = clampf(ratio, 0.0, 1.05)
	var lo: float = float(band[0]) if band.size() > 0 else 0.9
	var hi: float = float(band[1]) if band.size() > 1 else 1.0
	var c: Color
	if ratio > hi + 0.0001:
		c = Color(1.0, 0.2, 0.12)
	elif ratio >= lo:
		c = Color(0.35, 1.0, 0.35)
	else:
		c = Color(1.0, 0.65, 0.15)
	if _fill_lamp_mat:
		_fill_lamp_mat.emission = c
		_fill_lamp_mat.albedo_color = c.darkened(0.4)


func shudder(duration: float) -> void:
	_shudder_t = maxf(_shudder_t, duration)


func squash(amount: float) -> void:
	_dip = clampf(_dip + absf(amount) * 0.01, 0.0, 0.012)


func look_toward(world_pos: Variant) -> void:
	if world_pos == null:
		_look_target = 0.0
		return
	var local: Vector3 = global_transform.affine_inverse() * (world_pos as Vector3)
	_look_target = clampf(atan2(-(local.x - _neck_yaw.position.x), -(local.z - _neck_yaw.position.z)), -1.0, 1.0)


func set_happy(amount: float) -> void:
	_iris_target = clampf(amount, 0.0, 1.0)


func flash() -> void:
	_flash_v = 1.0


func set_rust(amount: float) -> void:
	var a: float = clampf(amount, 0.0, 1.0)
	for m: ShaderMaterial in _paint_mats:
		m.set_shader_parameter("rust_amount", clampf(0.35 + a * 0.6, 0.0, 1.0))
		m.set_shader_parameter("paint_coverage", clampf(float(_paint_cov[m]) * (1.25 - a * 0.5), 0.05, 1.0))


func press(t: float) -> void:
	_press_t = clampf(t, 0.0, 1.0)


func open_hatch(t: float) -> void:
	_hatch_t = clampf(t, 0.0, 1.0)
