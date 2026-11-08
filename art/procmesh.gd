class_name ProcMesh
extends RefCounted
## Procedural mesh helpers. All meshes carry vertex colors so one toon material can serve many parts.
## Vertex color alpha is used by the junk shader as "how much the instance tint applies".


## Rounded box centered at origin. Built from a subdivided cube whose points are pushed onto
## an inner box + radius, giving soft toy-like edges.
static func rounded_box(size: Vector3, radius: float, seg: int = 4, color: Color = Color.WHITE) -> ArrayMesh:
	var h: Vector3 = size * 0.5
	var r: float = minf(radius, minf(h.x, minf(h.y, h.z)) * 0.999)
	var inner: Vector3 = h - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = maxi(2, seg * 2)
	# Each face: normal axis and two tangent axes.
	var faces: Array = [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid: Array = []
		for j: int in n + 1:
			var row: Array = []
			for i: int in n + 1:
				var a: float = float(i) / n * 2.0 - 1.0
				var b: float = float(j) / n * 2.0 - 1.0
				var p: Vector3 = (nrm + u * a + v * b) * h
				var c: Vector3 = p.clamp(-inner, inner)
				var d: Vector3 = p - c
				var dn: Vector3 = d.normalized() if d.length() > 0.00001 else nrm
				row.append([c + dn * r, dn])
			grid.append(row)
		for j: int in n:
			for i: int in n:
				var q: Array = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
				for idx: int in [0, 1, 2, 0, 2, 3]:  # [world2] clockwise from outside (was inside-out: see-through with back-face culling)
					st.set_color(color)
					st.set_normal(q[idx][1])
					st.add_vertex(q[idx][0])
	return st.commit()


## Merges parts into one ArrayMesh. parts: Array of {mesh: Mesh, xform: Transform3D, color: Color}.
## Colors overwrite per part so the result has consistent vertex colors.
static func merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	for part_: Dictionary in parts:
		var mesh: Mesh = part_["mesh"]
		var xf_: Transform3D = part_.get("xform", Transform3D.IDENTITY)
		var col: Color = part_.get("color", Color.WHITE)
		var basis_n: Basis = xf_.basis.inverse().transposed()
		for s: int in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var pc: Variant = arr[Mesh.ARRAY_COLOR]
			var use_src_col: bool = part_.get("keep_colors", false) and pc != null
			var base: int = verts.size()
			for i: int in pv.size():
				verts.append(xf_ * pv[i])
				norms.append((basis_n * pn[i]).normalized() if pn.size() > i else Vector3.UP)
				cols.append((pc as PackedColorArray)[i] if use_src_col else col)
			if pi.is_empty():
				for i: int in pv.size():
					idxs.append(base + i)
			else:
				for i: int in pi:
					idxs.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func part(mesh: Mesh, xform: Transform3D = Transform3D.IDENTITY, color: Color = Color.WHITE) -> Dictionary:
	return {"mesh": mesh, "xform": xform, "color": color}


static func cyl(r_top: float, r_bot: float, height: float, segs: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = height
	m.radial_segments = segs
	m.rings = 1
	return m


static func sphere(radius: float, segs: int = 12, rings: int = 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m


static func hemisphere(radius: float, segs: int = 16, rings: int = 6) -> SphereMesh:
	var m := sphere(radius, segs, rings)
	m.is_hemisphere = true
	m.height = radius
	return m


static func torus(inner: float, outer: float, rings: int = 16, ring_segs: int = 8) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = ring_segs
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 3
	return m


static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
	return Transform3D(b, pos)


static func toon_material(color: Color, rust: float = 0.0, seed_: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/toon.gdshader")
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rust_amount", rust)
	m.set_shader_parameter("rust_seed", seed_)
	return m
