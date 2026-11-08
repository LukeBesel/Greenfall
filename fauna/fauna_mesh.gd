class_name FaunaMesh
extends RefCounted
## [wild] Builds one ArrayMesh per animal out of soft primitives (ellipsoids, tapered limbs,
## cones). Every vertex carries the rig data art/shaders/fauna.gdshader reads: CUSTOM0 = (pivot,
## part id), UV = (coat tint mask, gloss), plus a vertex colour. Animals face -Z, feet at y = 0.

const BODY: int = 0
const LEG_FL: int = 1
const LEG_FR: int = 2
const LEG_BL: int = 3
const LEG_BR: int = 4
const HEAD: int = 5
const TAIL: int = 6
const WING_L: int = 7
const WING_R: int = 8
const FLEX: int = 9
## [fauna2] Outer wing (hand + primaries): folds about the wrist (pivot) on the upstroke, then
## follows the inner wing about the shoulder (pivot2, in CUSTOM1).
const WINGTIP_L: int = 10
const WINGTIP_R: int = 11
const HIND: int = 12
const FRONT: int = 13

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _cu := PackedFloat32Array()
var _cu2 := PackedFloat32Array()
var _i := PackedInt32Array()

## Current rig state applied to the next parts (set with rig()).
var part: int = BODY
var pivot: Vector3 = Vector3.ZERO
var pivot2: Vector3 = Vector3.ZERO
## [fauna2] Subtle colour variation: soft mottling over the coat (0 = flat colour).
var vary: float = 0.06
var vary_scale: float = 18.0

static var _sph: Dictionary = {}


static func _sphere(segs: int, rings: int) -> Mesh:
	var k: String = "%d_%d" % [segs, rings]
	if not _sph.has(k):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = segs
		s.rings = rings
		_sph[k] = s
	return _sph[k]


func rig(p_part: int, p_pivot: Vector3 = Vector3.ZERO, p_pivot2: Vector3 = Vector3.ZERO) -> FaunaMesh:
	part = p_part
	pivot = p_pivot
	pivot2 = p_pivot2
	return self


## Smooth value-ish noise in -1..1 (sum of sines; no texture needed).
func _mottle(p: Vector3) -> float:
	var q: Vector3 = p * vary_scale
	return (sin(q.x * 1.3 + sin(q.z * 0.7)) * sin(q.y * 1.1 + 1.7) + sin(q.z * 1.7 + q.x * 0.4) * 0.6 + sin((q.x + q.y + q.z) * 2.3) * 0.3) / 1.6


## Adds a mesh with a transform. tint: 0..1 coat mask; gloss: 0..1.
func add(mesh: Mesh, xf: Transform3D, col: Color, tint: float = 0.0, gloss: float = 0.0) -> void:
	var bn: Basis = xf.basis.inverse().transposed()
	for s: int in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: Variant = arr[Mesh.ARRAY_INDEX]
		# [fauna2] Sculpted parts carry their own colours (alpha = coat mask) and glossy surfaces.
		var pc: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var sm: Material = mesh.surface_get_material(s)
		var sgloss: float = 1.0 if sm and sm.resource_name == "Gloss" else gloss
		var base: int = _v.size()
		for k: int in pv.size():
			var wp: Vector3 = xf * pv[k]
			_v.append(wp)
			_n.append((bn * (pn[k] if k < pn.size() else Vector3.UP)).normalized())
			var vcol: Color = col
			var vt: float = tint
			if k < pc.size():
				vcol = Color(pc[k].r, pc[k].g, pc[k].b, 1.0)
				vt = pc[k].a
			if vary > 0.0 and sgloss < 0.5:
				var m: float = 1.0 + vary * _mottle(wp)
				_c.append(Color(vcol.r * m, vcol.g * m, vcol.b * m, vcol.a))
			else:
				_c.append(vcol)
			_uv.append(Vector2(vt, sgloss))
			_cu.append_array([pivot.x, pivot.y, pivot.z, float(part)])
			_cu2.append_array([pivot2.x, pivot2.y, pivot2.z, 0.0])
		if pi == null:
			for k: int in pv.size():
				_i.append(base + k)
		else:
			for k: int in (pi as PackedInt32Array):
				_i.append(base + k)


## Ellipsoid at c with radii r, rotated by rot (degrees, XYZ).
func ell(c: Vector3, r: Vector3, col: Color, tint: float = 1.0, rot: Vector3 = Vector3.ZERO, segs: int = 12, rings: int = 7, gloss: float = 0.0) -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	add(_sphere(segs, rings), Transform3D(b * Basis.from_scale(r), c), col, tint, gloss)


## Tapered limb from a (radius ra) to b (radius rb), with a soft ball at each end.
func limb(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, tint: float = 1.0, segs: int = 8, caps: bool = true) -> void:
	var d: Vector3 = b - a
	var h: float = d.length()
	if h < 0.0001:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = rb
	cyl.bottom_radius = ra
	cyl.height = h
	cyl.radial_segments = segs
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var y: Vector3 = d / h
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	add(cyl, Transform3D(Basis(x, y, z), (a + b) * 0.5), col, tint)
	if caps:
		ell(a, Vector3.ONE * ra, col, tint, Vector3.ZERO, segs, 4)
		ell(b, Vector3.ONE * rb, col, tint, Vector3.ZERO, segs, 4)


## Chain of limbs through points with radii (tails, necks).
func chain(pts: Array, radii: Array, col: Color, tint: float = 1.0, segs: int = 8) -> void:
	for k: int in pts.size() - 1:
		limb(pts[k], pts[k + 1], float(radii[k]), float(radii[k + 1]), col, tint, segs, true)


## Cone from base centre a (radius r) to tip b; sides = 3..8 (ears, beaks, fins).
func cone(a: Vector3, b: Vector3, r: float, col: Color, tint: float = 1.0, sides: int = 6, flat: float = 1.0, gloss: float = 0.0) -> void:
	var d: Vector3 = b - a
	var h: float = d.length()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = r
	cyl.height = h
	cyl.radial_segments = sides
	cyl.rings = 1
	var y: Vector3 = d / h
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y)
	add(cyl, Transform3D(Basis(x, y, z * flat), (a + b) * 0.5), col, tint, gloss)


func commit() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_CUSTOM0] = _cu
	arrays[Mesh.ARRAY_CUSTOM1] = _cu2
	arrays[Mesh.ARRAY_INDEX] = _i
	var m := ArrayMesh.new()
	var fmt: int = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return m


## [fauna2] A glossy eye with a sclera-free dark iris ring and a catchlight (what makes a face
## read as alive). c: centre, r: radii, yaw: degrees the eye turns outward, iris: colour.
func eye(c: Vector3, r: Vector3, yaw: float, iris: Color = Color(0.05, 0.04, 0.035), pupil: bool = false) -> void:
	var rot := Vector3(0, yaw, 0)
	ell(c, r, iris, 0.0, rot, 10, 6, 1.0)
	var b := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
	var fwd: Vector3 = b * Vector3(0, 0, -1)
	if pupil:
		ell(c + fwd * r.z * 0.8, Vector3(r.x * 0.5, r.y * 0.6, r.z * 0.3), Color(0.02, 0.015, 0.01), 0.0, rot, 8, 4, 1.0)
	# Catchlight: up and toward the front, a little outward.
	var side: float = signf(c.x) if absf(c.x) > 0.0001 else 1.0
	var glint: Vector3 = c + fwd * r.z * 0.85 + Vector3(0, r.y * 0.4, 0) + b * Vector3(side * r.x * 0.15, 0, 0)
	var g: float = minf(r.x, r.y) * 0.28
	ell(glint, Vector3(g, g, g * 0.6), Color(1.0, 1.0, 1.0), 0.0, rot, 6, 4, 1.0)


## [fauna2] A flattened patch lying on an ellipsoid's surface (spots, markings).
## c, r: the ellipsoid; dir: direction from its centre; size: (w, thickness, l).
func patch_on(c: Vector3, r: Vector3, dir: Vector3, size: Vector3, col: Color, tint: float = 1.0) -> void:
	var d: Vector3 = dir.normalized()
	var p: Vector3 = c + r * d
	var n: Vector3 = (d / r).normalized()
	var x: Vector3 = n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(n)
	add(_sphere(8, 4), Transform3D(Basis(x * size.x, n * size.y, z * size.z), p - n * size.y * 0.3), col, tint, 0.0)


func tri_count() -> int:
	return _i.size() / 3
