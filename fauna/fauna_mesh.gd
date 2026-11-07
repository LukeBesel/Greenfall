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
const HIND: int = 12
const FRONT: int = 13

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _cu := PackedFloat32Array()
var _i := PackedInt32Array()

## Current rig state applied to the next parts (set with rig()).
var part: int = BODY
var pivot: Vector3 = Vector3.ZERO

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


func rig(p_part: int, p_pivot: Vector3 = Vector3.ZERO) -> FaunaMesh:
	part = p_part
	pivot = p_pivot
	return self


## Adds a mesh with a transform. tint: 0..1 coat mask; gloss: 0..1.
func add(mesh: Mesh, xf: Transform3D, col: Color, tint: float = 0.0, gloss: float = 0.0) -> void:
	var bn: Basis = xf.basis.inverse().transposed()
	for s: int in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var pi: Variant = arr[Mesh.ARRAY_INDEX]
		var base: int = _v.size()
		for k: int in pv.size():
			_v.append(xf * pv[k])
			_n.append((bn * (pn[k] if k < pn.size() else Vector3.UP)).normalized())
			_c.append(col)
			_uv.append(Vector2(tint, gloss))
			_cu.append_array([pivot.x, pivot.y, pivot.z, float(part)])
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
	arrays[Mesh.ARRAY_INDEX] = _i
	var m := ArrayMesh.new()
	var fmt: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return m


func tri_count() -> int:
	return _i.size() / 3
