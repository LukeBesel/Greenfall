class_name RocketModel
extends ShipModel
## [ship] Compatibility name: the vertical rocket became Lumi's ship (automation/ship_model.gd).
## Old callers (RocketModel.new(), build(t), plume) get the ship; the mesh helpers below are still
## shared by RocketPlume and the landing pad.


## Legacy: the old lathe hull's radius (the ship has no lathe hull). Kept for old callers.
static func hull_r(_y: float) -> float:
	return 0.9


# --- Mesh and material helpers ----------------------------------------------------------

## Surface of revolution of a (radius, y) profile. a0..a1 limits the sweep (a partial band).
static func lathe(prof: PackedVector2Array, segs: int, a0: float = 0.0, a1: float = TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = prof.size()
	# Per-profile-point 2D normals (outward), averaged over neighbouring segments.
	var nrm: Array[Vector2] = []
	for i: int in n:
		var d := Vector2.ZERO
		if i > 0:
			d += (prof[i] - prof[i - 1]).normalized()
		if i < n - 1:
			d += (prof[i + 1] - prof[i]).normalized()
		nrm.append(Vector2(d.y, -d.x).normalized())
	var cols: int = segs + 1
	var verts: Array[Vector3] = []
	var norms: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	for s: int in cols:
		var a: float = lerpf(a0, a1, float(s) / segs)
		var ca: float = cos(a)
		var sa: float = sin(a)
		for i: int in n:
			verts.append(Vector3(prof[i].x * ca, prof[i].y, prof[i].x * sa))
			norms.append(Vector3(nrm[i].x * ca, nrm[i].y, nrm[i].x * sa))
			uvs.append(Vector2(float(s) / segs, float(i) / (n - 1)))
	for s: int in segs:
		for i: int in n - 1:
			var a00: int = s * n + i
			var a10: int = (s + 1) * n + i
			for idx: int in [a00, a10, a00 + 1, a10, a10 + 1, a00 + 1]:
				st.set_normal(norms[idx])
				st.set_uv(uvs[idx])
				st.add_vertex(verts[idx])
	return st.commit()


## Prism from a polygon in the XY plane, `depth` thick along Z.
static func extrude(poly: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	var h: float = depth * 0.5
	var ccw: bool = _area(poly) > 0.0
	for side: float in [1.0, -1.0]:
		st.set_normal(Vector3(0, 0, side))
		for k: int in range(0, tri.size(), 3):
			var order: Array = [0, 2, 1] if (side > 0.0) == ccw else [0, 1, 2]
			for o: int in order:
				var p: Vector2 = poly[tri[k + o]]
				st.set_normal(Vector3(0, 0, side))
				st.add_vertex(Vector3(p.x, p.y, h * side))
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var e: Vector2 = (b - a).normalized()
		var nn := Vector3(e.y, -e.x, 0) * (1.0 if ccw else -1.0)
		var quad: Array[Vector3] = [Vector3(a.x, a.y, h), Vector3(b.x, b.y, h), Vector3(b.x, b.y, -h), Vector3(a.x, a.y, -h)]
		var idx: Array = [0, 1, 2, 0, 2, 3] if ccw else [0, 2, 1, 0, 3, 2]
		for j: int in idx:
			st.set_normal(nn)
			st.add_vertex(quad[j])
	return st.commit()


static func _area(poly: PackedVector2Array) -> float:
	var s: float = 0.0
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _additive(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m
