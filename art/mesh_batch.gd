class_name MeshBatch
extends RefCounted
## [deck] Draw-call batching for static props. Collects (mesh, transform, material) and emits
## as few nodes as possible while keeping the look identical:
##  - instance(): same mesh + material + shadow setting -> one MultiMeshInstance3D. Exact: the
##    shader sees the same object-space VERTEX/UV per instance as the separate nodes did.
##  - merge(): same material + shadow setting -> one ArrayMesh with every attribute kept
##    (normals, tangents, UV, UV2, colours). Exact for world-space shaders and UV-mapped
##    materials; object-space triplanar materials must be instance()d instead.
## Optional `cell` (metres) splits batches into ground squares so frustum culling and
## visibility ranges still work per area.

var cell: float = 0.0
var visibility_end: float = 0.0
var visibility_margin: float = 0.0
var _inst: Dictionary = {}  # key -> {mesh, mat, shadow, xfs: Array[Transform3D]}
var _merge: Dictionary = {}  # key -> {mat, shadow, parts: Array}


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.z / cell)) if cell > 0.0 else Vector2i.ZERO


func instance(mesh: Mesh, xf: Transform3D, mat: Material = null, shadow: bool = true) -> void:
	if mesh == null:
		return
	var c: Vector2i = _cell_of(xf.origin)
	var key: String = "%d|%d|%d|%d,%d" % [mesh.get_rid().get_id(), mat.get_rid().get_id() if mat else 0, int(shadow), c.x, c.y]
	if not _inst.has(key):
		_inst[key] = {"mesh": mesh, "mat": mat, "shadow": shadow, "xfs": []}
	(_inst[key]["xfs"] as Array).append(xf)


## `at` places the part in a cell when the transform's origin doesn't (pre-transformed meshes).
func merge(mesh: Mesh, xf: Transform3D, mat: Material = null, shadow: bool = true, at: Vector3 = Vector3.INF) -> void:
	if mesh == null:
		return
	var c: Vector2i = _cell_of(xf.origin if at == Vector3.INF else at)
	for s: int in mesh.get_surface_count():
		var m: Material = mat if mat else mesh.surface_get_material(s)
		var key: String = "%d|%d|%d,%d" % [m.get_rid().get_id() if m else 0, int(shadow), c.x, c.y]
		if not _merge.has(key):
			_merge[key] = {"mat": m, "shadow": shadow, "parts": []}
		(_merge[key]["parts"] as Array).append([mesh, s, xf])


func is_empty() -> bool:
	return _inst.is_empty() and _merge.is_empty()


## Adds the batched nodes under `parent` and clears the batch. Returns the nodes made.
func flush(parent: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for key: String in _inst:
		_flush_inst(_inst[key], parent, out)
	for key: String in _merge:
		_flush_merge(_merge[key], parent, out)
	_inst.clear()
	_merge.clear()
	return out


## [leftovers] flush() that yields to the loading screen between batches (BuildBudget); the same
## nodes in the same order. Await it.
func flush_async(parent: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for key: String in _inst:
		await BuildBudget.check("batch")
		_flush_inst(_inst[key], parent, out)
	for key: String in _merge:
		await BuildBudget.check("batch merge")
		_flush_merge(_merge[key], parent, out)
	_inst.clear()
	_merge.clear()
	return out


func _flush_inst(b: Dictionary, parent: Node, out: Array[GeometryInstance3D]) -> void:
	var xfs: Array = b["xfs"]
	var g: GeometryInstance3D
	if xfs.size() == 1:
		var mi := MeshInstance3D.new()
		mi.mesh = b["mesh"]
		mi.transform = xfs[0]
		g = mi
	else:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.set_meta("inst_xf", xfs)  # [world2] CPU copy for tools/collider_audit.gd (headless can't read MultiMeshes back)
		g = mmi
	_finish(g, b["mat"], b["shadow"])
	parent.add_child(g)
	out.append(g)


func _flush_merge(b: Dictionary, parent: Node, out: Array[GeometryInstance3D]) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = merged_mesh(b["parts"])
	_finish(mi, b["mat"], b["shadow"])
	parent.add_child(mi)
	out.append(mi)


func _finish(g: GeometryInstance3D, mat: Material, shadow: bool) -> void:
	if mat:
		g.material_override = mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if visibility_end > 0.0:
		g.visibility_range_end = visibility_end
		g.visibility_range_end_margin = visibility_margin


## One surface from [mesh, surface index, transform] parts, keeping every vertex attribute
## that all parts share (normals, tangents, UV, UV2, colours).
static func merged_mesh(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idxs := PackedInt32Array()
	var all_t: bool = true
	var all_uv: bool = true
	var all_uv2: bool = true
	var all_col: bool = true
	var datas: Array = []
	for p: Array in parts:
		var arr: Array = (p[0] as Mesh).surface_get_arrays(int(p[1]))
		datas.append(arr)
		all_t = all_t and arr[Mesh.ARRAY_TANGENT] != null
		all_uv = all_uv and arr[Mesh.ARRAY_TEX_UV] != null
		all_uv2 = all_uv2 and arr[Mesh.ARRAY_TEX_UV2] != null
		all_col = all_col and arr[Mesh.ARRAY_COLOR] != null
	for k: int in parts.size():
		var arr: Array = datas[k]
		var xf: Transform3D = parts[k][2]
		var nb: Basis = xf.basis.inverse().transposed()
		var flip: float = -1.0 if xf.basis.determinant() < 0.0 else 1.0
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var pn: Variant = arr[Mesh.ARRAY_NORMAL]
		var base: int = verts.size()
		for i: int in pv.size():
			verts.append(xf * pv[i])
			norms.append((nb * (pn as PackedVector3Array)[i]).normalized() if pn != null else Vector3.UP)
		if all_t:
			var pt: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i: int in pv.size():
				var t: Vector3 = (xf.basis * Vector3(pt[i * 4], pt[i * 4 + 1], pt[i * 4 + 2])).normalized()
				tans.append_array([t.x, t.y, t.z, pt[i * 4 + 3] * flip])
		if all_uv:
			uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
		if all_uv2:
			uv2s.append_array(arr[Mesh.ARRAY_TEX_UV2])
		if all_col:
			cols.append_array(arr[Mesh.ARRAY_COLOR])
		var pi: Variant = arr[Mesh.ARRAY_INDEX]
		if pi == null:
			for i: int in pv.size():
				idxs.append(base + i)
		else:
			# Mirrored transforms flip the winding: swap two corners to keep faces outward.
			var ia: PackedInt32Array = pi
			for t3: int in range(0, ia.size(), 3):
				if flip < 0.0:
					idxs.append_array([base + ia[t3], base + ia[t3 + 2], base + ia[t3 + 1]])
				else:
					idxs.append_array([base + ia[t3], base + ia[t3 + 1], base + ia[t3 + 2]])
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	if all_t:
		a[Mesh.ARRAY_TANGENT] = tans
	if all_uv:
		a[Mesh.ARRAY_TEX_UV] = uvs
	if all_uv2:
		a[Mesh.ARRAY_TEX_UV2] = uv2s
	if all_col:
		a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_INDEX] = idxs
	var out := ArrayMesh.new()
	if not verts.is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out
