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


static func model_aabb(id: String) -> AABB:
	if not _aabbs.has(id):
		_load_model(id)
	return _aabbs[id]


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
