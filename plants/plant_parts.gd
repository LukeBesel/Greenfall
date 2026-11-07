class_name PlantParts
extends RefCounted
## [green] Single plant variants from a Poly Haven plant file. Those files lay several variants
## (and their LOD copies) out in a row, so the merged AssetLib mesh of "one plant" is really a
## metre-long strip of overlapping clumps. Here each LOD0 variant is its own mesh at its own
## origin, lightened to a per-variant triangle budget.

static var _cache: Dictionary = {}


static func variants(id: String, max_tris: int = 4000) -> Array[Mesh]:
	var key: String = "%s@%d" % [id, max_tris]
	if _cache.has(key):
		return _cache[key]
	var out: Array[Mesh] = []
	if AssetLib.has_model(id):
		var ps: PackedScene = load(AssetLib.MODEL_DIR % [id, id])
		var root: Node = ps.instantiate() if ps else null
		if root:
			var found: Array = []
			_collect(root, found)
			for mi: MeshInstance3D in found:
				var nm: String = String(mi.name)
				if "_LOD" in nm and not nm.ends_with("_LOD0"):
					continue  # importer copies of a variant at lower detail
				var mesh: Mesh = mi.mesh
				for s: int in mesh.get_surface_count():
					var o: Material = mi.get_surface_override_material(s)
					if o:
						mesh.surface_set_material(s, o)
				out.append(AssetLib.lite(mesh, max_tris))
			root.free()
	if out.is_empty() and AssetLib.has_model(id):
		out.append(AssetLib.model_mesh_lite(id, max_tris))
	_cache[key] = out
	return out


static func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c: Node in n.get_children():
		_collect(c, out)
