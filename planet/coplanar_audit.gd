class_name CoplanarAudit
extends RefCounted
## [v8bld] Finds z-fighting in merged meshes: triangles that face the same way on the same plane
## (within TOL m) and overlap. Two such faces flicker against each other as the camera moves (the
## depth test picks one or the other per pixel and frame) and look still when the camera stops.
## Axis-aligned faces only (the city's boxes); slanted ones are skipped.

const TOL: float = 0.004
const MIN_AREA: float = 0.005


## Overlapping same-facing coplanar pairs in a triangle list (non-indexed, 3 vertices a triangle).
## Returns {"pairs": int, "area": float m2, "worst": Array of [area, Vector3 at, axis, sign]}.
static func audit(verts: PackedVector3Array, xf: Transform3D = Transform3D.IDENTITY, cols: PackedColorArray = PackedColorArray()) -> Dictionary:
	var buckets: Dictionary = {}  # Vector3i(axis, sign, round(o / TOL)) -> Array of tri index
	var plane: Dictionary = {}  # tri -> offset
	@warning_ignore("integer_division")
	var nt: int = verts.size() / 3
	for t: int in nt:
		var a: Vector3 = xf * verts[t * 3]
		var b: Vector3 = xf * verts[t * 3 + 1]
		var c: Vector3 = xf * verts[t * 3 + 2]
		var nrm: Vector3 = (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			continue
		nrm = nrm.normalized()
		var ax: int = nrm.abs().max_axis_index()
		if absf(nrm[ax]) < 0.9995:
			continue
		if absf(a[ax] - b[ax]) > 0.0005 or absf(a[ax] - c[ax]) > 0.0005:
			continue
		var o: float = (a[ax] + b[ax] + c[ax]) / 3.0
		var key := Vector3i(ax, 1 if nrm[ax] > 0.0 else -1, roundi(o / TOL))
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(t)
		plane[t] = o
	var pairs: int = 0
	var area: float = 0.0
	var worst: Array = []
	for key: Vector3i in buckets:
		var list: Array = buckets[key]
		var near: Array = list.duplicate()
		var up := Vector3i(key.x, key.y, key.z + 1)
		if buckets.has(up):
			near.append_array(buckets[up])
		var u: int = (key.x + 1) % 3
		var v: int = (key.x + 2) % 3
		for i: int in list.size():
			var ti: int = list[i]
			var pi: PackedVector2Array = _tri2(verts, xf, ti, u, v)
			var bi: Rect2 = _bounds(pi)
			for j: int in near.size():
				var tj: int = near[j]
				if tj <= ti and j < list.size():
					continue  # each pair once within the bucket
				if tj == ti or absf(float(plane[ti]) - float(plane[tj])) > TOL:
					continue
				var pj: PackedVector2Array = _tri2(verts, xf, tj, u, v)
				if not bi.grow(-0.001).intersects(_bounds(pj)):
					continue
				var ar: float = _overlap(pi, pj)
				if ar < MIN_AREA:
					continue
				pairs += 1
				area += ar
				var at: Vector3 = xf * verts[ti * 3]
				var kinds: String = ""
				if cols.size() == verts.size():  # BuildingDetail kinds (COLOR.a * 16) of the two faces
					kinds = "%d/%d" % [int(cols[ti * 3].a * 16.0), int(cols[tj * 3].a * 16.0)]
				worst.append([ar, at, key.x, key.y, kinds, ti, tj])
	worst.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	return {"pairs": pairs, "area": area, "worst": worst.slice(0, 8)}


## Every MeshInstance3D under root (its surfaces' triangles in root's space).
static func audit_node(root: Node3D) -> Dictionary:
	var out: Dictionary = {"pairs": 0, "area": 0.0, "meshes": 0, "worst": []}
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform if root.is_inside_tree() else mi.transform
		var r: Dictionary = audit(tris_of(mi.mesh), xf)
		out["meshes"] = int(out["meshes"]) + 1
		out["pairs"] = int(out["pairs"]) + int(r["pairs"])
		out["area"] = float(out["area"]) + float(r["area"])
		for w: Array in r["worst"]:
			(out["worst"] as Array).append([w[0], w[1], w[2], w[3], str(mi.name)])
	(out["worst"] as Array).sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	out["worst"] = (out["worst"] as Array).slice(0, 8)
	return out


## The per-vertex colours matching tris_of (BuildingDetail keeps its kind in COLOR.a).
static func cols_of(m: Mesh, only: int = -1) -> PackedColorArray:
	var out := PackedColorArray()
	for s: int in m.get_surface_count():
		if (only >= 0 and s != only) or m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr: Array = AssetLib.surf_arrays(m, s) if m is ArrayMesh else m.surface_get_arrays(s)
		var cs: Variant = arr[Mesh.ARRAY_COLOR]
		var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if not (cs is PackedColorArray) or (cs as PackedColorArray).size() != n:
			cs = PackedColorArray()
			(cs as PackedColorArray).resize(n)
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			for i: int in idx:
				out.append((cs as PackedColorArray)[i])
		else:
			out.append_array(cs)
	return out


static func tris_of(m: Mesh, only: int = -1) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s: int in m.get_surface_count():
		if (only >= 0 and s != only) or m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr: Array = AssetLib.surf_arrays(m, s) if m is ArrayMesh else m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			for i: int in idx:
				out.append(vs[i])
		else:
			out.append_array(vs)
	return out


static func _tri2(verts: PackedVector3Array, xf: Transform3D, t: int, u: int, v: int) -> PackedVector2Array:
	var p := PackedVector2Array()
	for k: int in 3:
		var q: Vector3 = xf * verts[t * 3 + k]
		p.append(Vector2(q[u], q[v]))
	if (p[1] - p[0]).cross(p[2] - p[0]) < 0.0:
		var tmp: Vector2 = p[1]
		p[1] = p[2]
		p[2] = tmp
	return p


static func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q: Vector2 in p:
		r = r.expand(q)
	return r


## Area of the intersection of two counter-clockwise triangles (Sutherland-Hodgman).
static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var poly: PackedVector2Array = a
	for e: int in 3:
		var c0: Vector2 = b[e]
		var c1: Vector2 = b[(e + 1) % 3]
		var inp: PackedVector2Array = poly
		poly = PackedVector2Array()
		if inp.is_empty():
			break
		for i: int in inp.size():
			var p: Vector2 = inp[i]
			var q: Vector2 = inp[(i + 1) % inp.size()]
			var pin: bool = (c1 - c0).cross(p - c0) >= -1e-6
			var qin: bool = (c1 - c0).cross(q - c0) >= -1e-6
			if pin:
				poly.append(p)
			if pin != qin:
				var d: Vector2 = q - p
				var den: float = (c1 - c0).cross(d)
				if absf(den) > 1e-12:
					var t: float = (c1 - c0).cross(c0 - p) / den
					poly.append(p + d * clampf(t, 0.0, 1.0))
	if poly.size() < 3:
		return 0.0
	var ar: float = 0.0
	for i: int in poly.size():
		ar += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(ar) * 0.5
