class_name AssetLib
extends RefCounted
## Loads vendor models (glTF scenes) and textures by id.
## Models are flattened into a single Mesh (all MeshInstances merged, surface materials kept) so
## they can be drawn with MultiMesh. Single-mesh models keep their imported LODs.

const MODEL_DIR: String = "res://art/vendor/polyhaven/models/%s/%s_1k.gltf"
const TEX_DIR: String = "res://art/vendor/polyhaven/textures/%s/%s_%s_1k.jpg"

static var _meshes: Dictionary = {}
static var _offsets: Dictionary = {}
static var _aabbs: Dictionary = {}


## Mesh for a model id, already in model-root space.
static func model_mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		_load_model(id)
	return _meshes[id]


static var _lite: Dictionary = {}


## A lighter version of a model mesh using the importer-generated LOD closest to (but not above)
## max_tris triangles per surface. Keeps materials. Falls back to the full mesh.
static func model_mesh_lite(id: String, max_tris: int = 1500) -> Mesh:
	var key: String = "%s@%d" % [id, max_tris]
	if _lite.has(key):
		return _lite[key]
	var out: Mesh = lite(model_mesh(id), max_tris)
	_lite[key] = out
	return out


static var _lite_by_rid: Dictionary = {}


## Lighter version of any mesh (see model_mesh_lite).
static func lite(full: Mesh, max_tris: int) -> Mesh:
	var key: String = "%d@%d" % [full.get_rid().get_id(), max_tris]
	if _lite_by_rid.has(key):
		return _lite_by_rid[key]
	var out := ArrayMesh.new()
	var total_full: int = 0
	var total_lite: int = 0
	for s: int in full.get_surface_count():
		var arrays: Array = full.surface_get_arrays(s)
		var idx_full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		total_full += idx_full.size() / 3
		var best: PackedInt32Array = idx_full
		var surf: Dictionary = RenderingServer.mesh_get_surface(full.get_rid(), s)
		var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var budget: int = max_tris * 3 / maxi(full.get_surface_count(), 1)
		var lods: Array = surf.get("lods", [])
		if best.size() > budget and lods.is_empty():
			# No importer LODs (merged or odd meshes): generate them now.
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
			im.generate_lods(25.0, 60.0, [])
			for li: int in im.get_surface_lod_count(0):
				var idx: PackedInt32Array = im.get_surface_lod_indices(0, li)
				best = idx
				if idx.size() <= budget:
					break
		if best.size() > budget:
			for lod: Dictionary in lods:
				var data: PackedByteArray = lod.get("index_data", PackedByteArray())
				var wide: bool = vcount > 65535
				var n: int = data.size() / (4 if wide else 2)
				if n <= 0:
					continue
				var idx := PackedInt32Array()
				idx.resize(n)
				for i: int in n:
					idx[i] = data.decode_u32(i * 4) if wide else data.decode_u16(i * 2)
				best = idx
				if n <= budget:
					break
		arrays[Mesh.ARRAY_INDEX] = best
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		total_lite += best.size() / 3
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, full.surface_get_material(s))
	if total_lite >= total_full:
		_lite_by_rid[key] = full
		return full
	_lite_by_rid[key] = out
	return out


static func model_aabb(id: String) -> AABB:
	if not _aabbs.has(id):
		_load_model(id)
	return _aabbs[id]


static var _parts: Dictionary = {}


## One named MeshInstance from a model (for files that bundle variants, e.g. fire_hydrant).
static func model_part(id: String, node_name: String) -> Mesh:
	var key: String = id + "::" + node_name
	if _parts.has(key):
		return _parts[key]
	var ps: PackedScene = load(MODEL_DIR % [id, id])
	var root: Node = ps.instantiate()
	var mesh: Mesh = null
	var found: Array = []
	_collect(root, Transform3D.IDENTITY, found)
	for f: Dictionary in found:
		if String((f["mi"] as Node).name) == node_name:
			mesh = (f["mi"] as MeshInstance3D).mesh
			_apply_overrides(f["mi"], mesh)
	root.free()
	if mesh == null:
		mesh = model_mesh(id)
	_parts[key] = mesh
	return mesh


static func has_model(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR % [id, id])


static func _load_model(id: String) -> void:
	var path: String = MODEL_DIR % [id, id]
	var ps: PackedScene = load(path)
	if ps == null:
		push_error("Missing model %s" % id)
		_meshes[id] = BoxMesh.new()
		_aabbs[id] = AABB(Vector3(-0.1, 0, -0.1), Vector3(0.2, 0.2, 0.2))
		return
	var root: Node = ps.instantiate()
	var found: Array = []
	_collect(root, Transform3D.IDENTITY, found)
	var mesh: Mesh
	if found.size() == 1 and (found[0]["xform"] as Transform3D).is_equal_approx(Transform3D.IDENTITY):
		mesh = found[0]["mi"].mesh
		_apply_overrides(found[0]["mi"], mesh)
	else:
		mesh = _merge(found)
	root.free()
	_meshes[id] = mesh
	_aabbs[id] = mesh.get_aabb()


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here: Transform3D = xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append({"mi": n, "xform": here})
	for c: Node in n.get_children():
		_collect(c, here, out)


static func _apply_overrides(mi: MeshInstance3D, mesh: Mesh) -> void:
	for s: int in mesh.get_surface_count():
		var o: Material = mi.get_surface_override_material(s)
		if o:
			mesh.surface_set_material(s, o)


static func _merge(found: Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	for f: Dictionary in found:
		var mi: MeshInstance3D = f["mi"]
		var xf: Transform3D = f["xform"]
		var nb: Basis = xf.basis.inverse().transposed()
		for s: int in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i: int in v.size():
				v[i] = xf * v[i]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for i: int in nr.size():
					nr[i] = (nb * nr[i]).normalized()
				arr[Mesh.ARRAY_NORMAL] = nr
			if arr[Mesh.ARRAY_TANGENT] != null:
				var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for i: int in range(0, tg.size(), 4):
					var t: Vector3 = (xf.basis * Vector3(tg[i], tg[i + 1], tg[i + 2])).normalized()
					tg[i] = t.x
					tg[i + 1] = t.y
					tg[i + 2] = t.z
				arr[Mesh.ARRAY_TANGENT] = tg
			# Drop arrays the merged mesh doesn't need (bones/weights would break without a skeleton).
			arr[Mesh.ARRAY_BONES] = null
			arr[Mesh.ARRAY_WEIGHTS] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


static func tex(id: String, map: String) -> Texture2D:
	var p: String = TEX_DIR % [id, id, map]
	return load(p) if ResourceLoader.exists(p) else null


## A StandardMaterial3D from a Poly Haven texture set (diff / nor_gl / arm).
static func pbr_material(id: String, uv_scale: float = 1.0, tint: Color = Color.WHITE, triplanar: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(id, "diff")
	m.albedo_color = tint
	var n: Texture2D = tex(id, "nor_gl")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var arm: Texture2D = tex(id, "arm")
	if arm:
		m.ao_enabled = true
		m.ao_texture = arm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness_texture = arm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
		m.roughness = 1.0
	m.uv1_scale = Vector3.ONE * uv_scale
	m.uv1_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
