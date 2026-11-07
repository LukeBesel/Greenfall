class_name OchreProps
extends RefCounted
## [planet-ochre] Procedural meshes for Ochre: field junk (ore tailings, broken drill bits, mining
## crates, bucket teeth, ore sacks), desert plants (date palms, agaves, barrel cacti, aloes), sails,
## and the bucket-wheel excavators. Vertex-coloured, low-poly, built once and cached.

static var _cache: Dictionary = {}


## Collects primitive pieces per material into one mesh each (one draw call per material).
class Batch:
	var sts: Dictionary = {}

	func st_for(mat: Material) -> SurfaceTool:
		var key: int = mat.get_instance_id()
		if not sts.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[key] = [st, mat]
		return sts[key][0]

	func add(mesh: Mesh, xf: Transform3D, mat: Material, col: Color = Color.WHITE) -> void:
		OchreProps.put(st_for(mat), mesh, xf, col)

	func box(pos: Vector3, size: Vector3, mat: Material, basis: Basis = Basis(), col: Color = Color.WHITE) -> void:
		add(OchreProps.unit_box(), Transform3D(basis * Basis.from_scale(size), pos), mat, col)

	func beam(a: Vector3, b: Vector3, thick: float, mat: Material, col: Color = Color.WHITE) -> void:
		add(OchreProps.unit_box(), OchreProps.beam_xf(a, b, thick), mat, col)

	func flush(parent: Node3D, shadows: bool = true, vis_end: float = 0.0) -> Array[MeshInstance3D]:
		var out: Array[MeshInstance3D] = []
		for key: int in sts:
			var st: SurfaceTool = sts[key][0]
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = sts[key][1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if vis_end > 0.0:
				mi.visibility_range_end = vis_end
			parent.add_child(mi)
			out.append(mi)
		sts.clear()
		return out


static func unit_box() -> BoxMesh:
	if not _cache.has("box"):
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		_cache["box"] = b
	return _cache["box"]


static func beam_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d: Vector3 = b - a
	var l: float = d.length()
	var y: Vector3 = d / maxf(l, 0.0001)
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * thick, y * l, z * thick), (a + b) * 0.5)


## Appends a primitive mesh (flat-shaded: normals are regenerated) with one vertex colour.
static func put(st: SurfaceTool, mesh: Mesh, xf: Transform3D, col: Color) -> void:
	for s: int in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i: int in v.size():
				idx.append(i)
		for i: int in idx:
			st.set_color(col)
			st.add_vertex(xf * v[i])


static func _mat_vc(tex_id: String, rough: float, metal: float = 0.0, tex_scale: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if tex_id != "":
		m.albedo_texture = AssetLib.tex(tex_id, "diff")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tex_scale
		var n: Texture2D = AssetLib.tex(tex_id, "nor_gl")
		if n:
			m.normal_enabled = true
			m.normal_texture = n
	return m


static func _commit(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.index()
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, mat)
	return m


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return ProcMesh.xf(pos, rot_deg, scl)


# --- Field junk --------------------------------------------------------------------------------

## id -> mesh (each with its surface material, ready for MultiMesh).
static func junk_meshes() -> Dictionary:
	if _cache.has("junk"):
		return _cache["junk"]
	var out: Dictionary = {}
	out["ochre_tailings"] = _tailings(11)
	out["ochre_tailings_b"] = _tailings(29)
	out["ochre_drill_bit"] = _drill_bit()
	out["ochre_drill_rod"] = _drill_rod()
	out["ochre_crate"] = _crate(false)
	out["ochre_crate_open"] = _crate(true)
	out["ochre_bucket_tooth"] = _tooth()
	out["ochre_ore_sack"] = _sack()
	_cache["junk"] = out
	return out


## A lumpy clump of ore and tailings rubble.
static func _tailings(seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := _new_st()
	var cols: Array[Color] = [Color(0.78, 0.55, 0.3), Color(0.62, 0.6, 0.5), Color(0.66, 0.36, 0.22), Color(0.84, 0.74, 0.5)]
	var sph := SphereMesh.new()
	sph.radial_segments = 8
	sph.rings = 4
	sph.radius = 1.0
	sph.height = 2.0
	for k: int in 5:
		var r: float = rng.randf_range(0.14, 0.32) * (1.4 if k == 0 else 1.0)
		var p := Vector3(rng.randf_range(-0.35, 0.35), r * 0.55, rng.randf_range(-0.3, 0.3)) if k > 0 else Vector3(0, r * 0.5, 0)
		var arr: Array = sph.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var jit := PackedVector3Array()
		for i: int in v.size():
			var d: Vector3 = v[i]
			var h: float = sin(d.x * 5.1 + k) * cos(d.z * 4.3 + seed_v) * 0.22 + sin(d.y * 7.0 + k * 2.0) * 0.12
			jit.append(Vector3(d.x, d.y * 0.62, d.z) * (1.0 + h))
		var col: Color = cols[(k + seed_v) % cols.size()]
		for i: int in idx:
			st.set_color(col.lerp(Color(0.5, 0.45, 0.4), clampf(-jit[i].y, 0.0, 1.0) * 0.4))
			st.add_vertex(p + jit[i] * r)
	return _commit(st, _cached_mat("rock", func() -> Material: return _mat_vc("red_laterite_soil_stones", 0.95, 0.0, 1.6)))


static func _cached_mat(key: String, make: Callable) -> Material:
	var k: String = "mat_" + key
	if not _cache.has(k):
		_cache[k] = make.call()
	return _cache[k]


static func _rust() -> Material:
	return _cached_mat("rust", func() -> Material: return _mat_vc("rusty_metal_02", 0.7, 0.6, 2.5))


## A broken tricone rock bit: threaded shank, a snapped stub of drill pipe and three toothed cones.
static func _drill_bit() -> ArrayMesh:
	var st := _new_st()
	var steel := Color(0.62, 0.58, 0.54)
	var rust := Color(0.66, 0.4, 0.24)
	put(st, ProcMesh.cyl(0.17, 0.2, 0.22, 10), _xf(Vector3(0, 0.33, 0)), steel)
	put(st, ProcMesh.cyl(0.11, 0.13, 0.2, 10), _xf(Vector3(0, 0.54, 0)), rust)
	put(st, ProcMesh.cyl(0.08, 0.09, 0.28, 8), _xf(Vector3(0.0, 0.76, 0.0), Vector3(6, 0, 4)), rust.darkened(0.15))
	for k: int in 3:
		var a: float = TAU * k / 3.0
		var dir := Vector3(cos(a), 0, sin(a))
		var xf := Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, deg_to_rad(-125.0)), dir * 0.11 + Vector3(0, 0.2, 0))
		put(st, ProcMesh.cyl(0.02, 0.12, 0.17, 9), xf, Color(0.42, 0.4, 0.38))
		for r: int in 2:
			put(st, ProcMesh.cyl(0.13 - r * 0.04, 0.13 - r * 0.04, 0.025, 9), xf * _xf(Vector3(0, -0.04 + r * 0.06, 0)), Color(0.55, 0.52, 0.48))
	return _commit(st, _rust())


## A snapped length of drill rod with a tool joint.
static func _drill_rod() -> ArrayMesh:
	var st := _new_st()
	put(st, ProcMesh.cyl(0.075, 0.075, 1.6, 10), _xf(Vector3(0, 0.8, 0)), Color(0.6, 0.42, 0.28))
	put(st, ProcMesh.cyl(0.1, 0.1, 0.28, 10), _xf(Vector3(0, 0.14, 0)), Color(0.62, 0.6, 0.56))
	put(st, ProcMesh.cyl(0.05, 0.075, 0.12, 6), _xf(Vector3(0, 1.66, 0), Vector3(8, 0, 0)), Color(0.5, 0.36, 0.26))
	return _commit(st, _rust())


## A Ledger ore-sample crate: plank sides, steel corner straps, a faded amber band.
static func _crate(open: bool) -> ArrayMesh:
	var st := _new_st()
	var wood := Color(0.62, 0.45, 0.3)
	var dark := Color(0.32, 0.3, 0.28)
	var amber := Color(0.86, 0.6, 0.14)
	var s := Vector3(1.0, 0.62, 0.66)
	for i: int in 3:
		var y: float = 0.11 + i * 0.2
		put(st, unit_box(), _xf(Vector3(0, y, 0), Vector3.ZERO, Vector3(s.x, 0.18, s.z)), wood.darkened(0.06 * (i % 2)))
	if not open:
		put(st, unit_box(), _xf(Vector3(0, s.y + 0.02, 0), Vector3(0, 0, 1.5), Vector3(s.x + 0.02, 0.05, s.z + 0.02)), wood.lightened(0.05))
	else:
		put(st, unit_box(), _xf(Vector3(0.12, s.y + 0.25, -s.z * 0.5 - 0.02), Vector3(-70, 0, 0), Vector3(s.x + 0.02, 0.05, s.z)), wood.lightened(0.05))
		put(st, unit_box(), _xf(Vector3(0, s.y - 0.08, 0), Vector3.ZERO, Vector3(s.x - 0.08, 0.06, s.z - 0.08)), Color(0.7, 0.5, 0.3))
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.33, 0.33]:
			put(st, unit_box(), _xf(Vector3(x * s.x, s.y * 0.5, z * 2.0 * s.z * 0.5), Vector3.ZERO, Vector3(0.05, s.y + 0.02, 0.05)), dark)
	put(st, unit_box(), _xf(Vector3(0, 0.36, 0), Vector3.ZERO, Vector3(s.x + 0.015, 0.09, s.z + 0.015)), amber)
	return _commit(st, _cached_mat("crate", func() -> Material: return _mat_vc("rusty_metal_03", 0.85, 0.0, 1.2)))


## A worn excavator bucket tooth.
static func _tooth() -> ArrayMesh:
	var st := _new_st()
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.16
	c.height = 0.62
	c.radial_segments = 4
	c.rings = 1
	put(st, c, _xf(Vector3(0, 0.31, 0), Vector3(0, 45, 0), Vector3(1.0, 1.0, 0.55)), Color(0.55, 0.38, 0.26))
	put(st, unit_box(), _xf(Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(0.26, 0.1, 0.16)), Color(0.45, 0.42, 0.4))
	return _commit(st, _rust())


## A tied canvas ore-sample sack, sun-bleached.
static func _sack() -> ArrayMesh:
	var st := _new_st()
	var sph := SphereMesh.new()
	sph.radial_segments = 10
	sph.rings = 5
	sph.radius = 0.3
	sph.height = 0.5
	put(st, sph, _xf(Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8)), Color(0.85, 0.76, 0.6))
	put(st, ProcMesh.cyl(0.04, 0.1, 0.16, 8), _xf(Vector3(0, 0.5, 0)), Color(0.8, 0.7, 0.55))
	put(st, unit_box(), _xf(Vector3(0, 0.25, 0.23), Vector3.ZERO, Vector3(0.3, 0.12, 0.02)), Color(0.75, 0.5, 0.2))
	return _commit(st, _cached_mat("canvas", func() -> Material: return _mat_vc("polystyrene", 0.95, 0.0, 2.0)))


# --- Plants ------------------------------------------------------------------------------------

static func foliage_mat() -> ShaderMaterial:
	return _cached_mat("foliage", func() -> Material:
		var m := ShaderMaterial.new()
		m.shader = preload("res://planet/planets/ochre/ochre_foliage.gdshader")
		return m) as ShaderMaterial


## A date palm: a gently curved ringed trunk and a crown of drooping, folded fronds.
## COLOR.a is the sway weight (0 at the root). About 300 triangles.
static func palm(seed_v: int) -> ArrayMesh:
	var key: String = "palm_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := _new_st()
	var h: float = rng.randf_range(6.5, 9.5)
	var bend: float = rng.randf_range(0.6, 1.6)
	var sides: int = 6
	var segs: int = 8
	var pts: Array[Vector3] = []
	for i: int in segs + 1:
		var t: float = float(i) / segs
		pts.append(Vector3(bend * t * t, h * t, 0.0))
	for i: int in segs:
		var r0: float = lerpf(0.3, 0.17, float(i) / segs)
		var r1: float = lerpf(0.3, 0.17, float(i + 1) / segs)
		for s: int in sides:
			var a0: float = TAU * s / sides
			var a1: float = TAU * (s + 1) / sides
			var c0 := Color(0.5, 0.4, 0.3, float(i) / segs) if i % 2 == 0 else Color(0.6, 0.5, 0.38, float(i) / segs)
			var c1 := Color(c0.r, c0.g, c0.b, float(i + 1) / segs)
			var q: Array[Vector3] = [pts[i] + Vector3(cos(a0), 0, sin(a0)) * r0, pts[i] + Vector3(cos(a1), 0, sin(a1)) * r0,
				pts[i + 1] + Vector3(cos(a1), 0, sin(a1)) * r1, pts[i + 1] + Vector3(cos(a0), 0, sin(a0)) * r1]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(c0 if k < 2 else c1)
				st.add_vertex(q[k])
	var top: Vector3 = pts[segs]
	var n_fr: int = 12
	for f: int in n_fr:
		var az: float = TAU * f / n_fr + rng.randf_range(-0.2, 0.2)
		var el: float = deg_to_rad(rng.randf_range(15.0, 55.0)) if f % 3 != 0 else deg_to_rad(rng.randf_range(55.0, 75.0))
		var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var side := Vector3(-sin(az), 0, cos(az))
		var p: Vector3 = top
		var ln: float = rng.randf_range(3.2, 4.4)
		var nseg: int = 6
		var prev_l := Vector3.ZERO
		var prev_c := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var green := Color(0.3, 0.47, 0.18).lerp(Color(0.45, 0.55, 0.22), rng.randf())
		for k: int in nseg + 1:
			var t: float = float(k) / nseg
			var w: float = 0.55 * sin(PI * minf(t * 1.15, 1.0)) + 0.04
			var down := Vector3(0, -1, 0)
			var lft: Vector3 = p + side * w + down * w * 0.35
			var rgt: Vector3 = p - side * w + down * w * 0.35
			if k > 0:
				var ca := Color(green.r, green.g, green.b, 1.0).lerp(Color(0.62, 0.6, 0.3, 1.0), t * 0.5)
				var cb := ca.darkened(0.12)
				for tri: Array in [[prev_l, prev_c, p], [prev_l, p, lft], [prev_c, prev_r, rgt], [prev_c, rgt, p]]:
					for vv: Vector3 in tri:
						st.set_color(ca if vv in [p, lft, rgt] else cb)
						st.add_vertex(vv)
			prev_l = lft
			prev_c = p
			prev_r = rgt
			p += dir * (ln / nseg)
			dir = (dir + Vector3(0, -0.32, 0)).normalized()
	# Date clusters under the crown.
	for k: int in 3:
		var a: float = TAU * k / 3.0 + 0.4
		put(st, ProcMesh.sphere(0.32, 6, 3), _xf(top + Vector3(cos(a) * 0.35, -0.45, sin(a) * 0.35)), Color(0.75, 0.45, 0.15, 0.95))
	var m: ArrayMesh = _commit(st, foliage_mat())
	_cache[key] = m
	return m


## An agave rosette: stiff blue-green pointed leaves with pale edges.
static func agave(seed_v: int) -> ArrayMesh:
	var key: String = "agave_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := _new_st()
	var base := Color(0.4, 0.55, 0.46).lerp(Color(0.5, 0.58, 0.36), rng.randf())
	for i: int in 16:
		var az: float = TAU * i * 0.618 + rng.randf_range(-0.1, 0.1)
		var el: float = deg_to_rad(lerpf(70.0, 18.0, float(i) / 16.0))
		var ln: float = rng.randf_range(0.7, 1.15) * lerpf(0.8, 1.15, float(i) / 16.0)
		var d := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var sd := Vector3(-sin(az), 0, cos(az))
		var b0: Vector3 = sd * 0.09
		var mid: Vector3 = d * ln * 0.45 + Vector3(0, 0.04, 0)
		var tip: Vector3 = d * ln + Vector3(0, -0.05 * cos(el), 0)
		var ridge: Vector3 = mid + Vector3(0, 0.05, 0)
		var edge := base.lightened(0.25)
		edge.a = 0.2
		var c := Color(base.r, base.g, base.b, 0.2)
		for tri: Array in [[b0, ridge, mid + sd * 0.11], [-b0, mid - sd * 0.11, ridge], [ridge, tip, mid + sd * 0.11], [ridge, mid - sd * 0.11, tip]]:
			for vv: Vector3 in tri:
				st.set_color(edge if vv == tip else c)
				st.add_vertex(vv)
	var m: ArrayMesh = _commit(st, foliage_mat())
	_cache[key] = m
	return m


## A ribbed barrel cactus, flowering on top.
static func barrel_cactus() -> ArrayMesh:
	if _cache.has("barrel"):
		return _cache["barrel"]
	var st := _new_st()
	var ribs: int = 14
	var rings: int = 6
	for j: int in rings:
		for i: int in ribs * 2:
			var a0: float = TAU * i / (ribs * 2)
			var a1: float = TAU * (i + 1) / (ribs * 2)
			var q: Array[Vector3] = []
			for pr: Array in [[a0, j], [a1, j], [a1, j + 1], [a0, j + 1]]:
				var e: float = PI * 0.5 * (1.0 - float(pr[1]) / rings)
				var r: float = (0.42 + (0.05 if int(round(float(pr[0]) / (TAU / (ribs * 2)))) % 2 == 0 else 0.0)) * cos(e * 0.92 - 0.1)
				q.append(Vector3(cos(pr[0]) * r, 0.62 * (1.0 - cos(PI * float(pr[1]) / rings)) * 0.85, sin(pr[0]) * r))
			for k: int in [0, 2, 1, 0, 3, 2]:
				st.set_color(Color(0.3, 0.46, 0.24, 0.0).lerp(Color(0.42, 0.52, 0.26, 0.0), float(j) / rings))
				st.add_vertex(q[k])
	for k: int in 6:
		var a: float = TAU * k / 6.0
		put(st, ProcMesh.sphere(0.07, 6, 3), _xf(Vector3(cos(a) * 0.15, 1.02, sin(a) * 0.15)), Color(0.95, 0.55, 0.2, 0.0))
	var m: ArrayMesh = _commit(st, foliage_mat())
	_cache["barrel"] = m
	return m


## An aloe: a rosette of thick fleshy leaves and a tall stalk of orange-red flowers.
static func aloe(seed_v: int) -> ArrayMesh:
	var key: String = "aloe_%d" % seed_v
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 3
	var st := _new_st()
	for i: int in 11:
		var az: float = TAU * i * 0.618
		var el: float = deg_to_rad(rng.randf_range(25.0, 60.0))
		var ln: float = rng.randf_range(0.5, 0.75)
		var d := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var sd := Vector3(-sin(az), 0, cos(az))
		var c := Color(0.42, 0.52, 0.3, 0.15)
		for tri: Array in [[sd * 0.06, d * ln, -sd * 0.06], [sd * 0.06, Vector3(0, 0.05, 0) + d * ln * 0.4, d * ln], [-sd * 0.06, d * ln, Vector3(0, 0.05, 0) + d * ln * 0.4]]:
			for vv: Vector3 in tri:
				st.set_color(c)
				st.add_vertex(vv)
	put(st, ProcMesh.cyl(0.015, 0.025, 1.1, 5), _xf(Vector3(0, 0.55, 0)), Color(0.45, 0.42, 0.25, 0.4))
	put(st, ProcMesh.cyl(0.02, 0.08, 0.38, 6), _xf(Vector3(0, 1.25, 0)), Color(0.95, 0.38, 0.16, 0.8))
	var m: ArrayMesh = _commit(st, foliage_mat())
	_cache[key] = m
	return m


# --- Sails ---------------------------------------------------------------------------------------

## A tensioned sail between corners (3 or 4 world points relative to `origin`), sagging in the
## middle; UV 0..1 across it for the sail shader.
static func sail_mesh(corners: Array[Vector3], sag: float) -> ArrayMesh:
	var st := _new_st()
	var n: int = 6
	var quad: bool = corners.size() >= 4
	var c0: Vector3 = corners[0]
	var c1: Vector3 = corners[1]
	var c2: Vector3 = corners[2]
	var c3: Vector3 = corners[3] if quad else corners[2]
	var grid: Array = []
	for j: int in n + 1:
		var row: Array = []
		for i: int in n + 1:
			var u: float = float(i) / n
			var v: float = float(j) / n
			var p: Vector3 = c0.lerp(c1, u).lerp(c3.lerp(c2, u), v)
			p.y -= sag * sin(PI * u) * sin(PI * v)
			row.append([p, Vector2(u, v)])
		grid.append(row)
	for j: int in n:
		for i: int in n:
			for k: Array in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var e: Array = grid[j + k[1]][i + k[0]]
				st.set_uv(e[1])
				st.add_vertex(e[0])
	st.generate_normals()
	return st.commit()
