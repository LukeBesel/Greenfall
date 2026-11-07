class_name SceneStats
extends RefCounted
## [deck] Deterministic geometry census of a 3D scene, for draw-call work without a GPU.
## DevHooks `--scene-stats[=S]` prints it S seconds after start (works headless). Per top-level
## child of the scene: visible GeometryInstance3D count, mesh surfaces, shadow-casting surfaces,
## MultiMesh instances, Label3D and particle nodes. `est_draws` is a rough Forward+ estimate:
## every visible surface draws once in the colour pass and once in the depth prepass, and every
## shadow-casting surface once more per shadow split. Real numbers come from `--perf` renders.


static func census(root: Node, shadow_splits: int = 1) -> Dictionary:
	var groups: Dictionary = {}
	var mats: Dictionary = {}
	var total: Dictionary = _blank()
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var top: Node = g
		while top.get_parent() and top.get_parent() != root:
			top = top.get_parent()
		var key: String = str(top.name)
		if key.begins_with("@") and top.get_script():  # anonymous node: name it by its script
			key = str((top.get_script() as Script).resource_path.get_file().get_basename())
		elif key.begins_with("@"):
			key = "%s>%s" % [key.get_slice("@", 1), str(g.get_parent().name) if g.get_parent() != top else str(g.name)]
		if OS.get_environment("STATS_SPLIT") == key:  # e.g. STATS_SPLIT=City: break one group down
			var sub: String = str(g.name).rstrip("0123456789_-").replace("@", "")
			key = "%s/%s" % [key, (g.mesh.resource_name if g is MeshInstance3D and g.mesh and g.mesh.resource_name != "" else sub)]
		var row: Dictionary = groups.get(key, _blank())
		var surf: int = 1
		if g is MeshInstance3D:
			var m: Mesh = (g as MeshInstance3D).mesh
			surf = m.get_surface_count() if m else 0
			row["meshes"] += 1
			row["tris"] += _tris(m)
			for s: int in surf:
				var mat: Material = (g as MeshInstance3D).get_active_material(s)
				if mat:
					mats[mat.get_rid()] = true
		elif g is MultiMeshInstance3D:
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			surf = mm.mesh.get_surface_count() if mm and mm.mesh else 0
			row["multimeshes"] += 1
			var n_inst: int = mm.visible_instance_count if mm and mm.visible_instance_count >= 0 else (mm.instance_count if mm else 0)
			row["mm_instances"] += n_inst
			row["tris"] += n_inst * _tris(mm.mesh if mm else null)
		elif g is Label3D:
			row["labels"] += 1
		elif g is GPUParticles3D or g is CPUParticles3D:
			row["particles"] += 1
		if g.material_override:
			mats[g.material_override.get_rid()] = true
		row["nodes"] += 1
		row["surfaces"] += surf
		var casts: bool = g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if casts:
			row["shadow_surfaces"] += surf
		row["est_draws"] += surf * 2 + (surf * shadow_splits if casts else 0)
		groups[key] = row
	for key: String in groups:
		for f: String in total:
			total[f] += groups[key][f]
	total["materials"] = mats.size()
	return {"total": total, "groups": groups}


static func _blank() -> Dictionary:
	return {"nodes": 0, "meshes": 0, "multimeshes": 0, "mm_instances": 0, "labels": 0, "particles": 0,
		"surfaces": 0, "shadow_surfaces": 0, "est_draws": 0, "tris": 0}


static var _tri_cache: Dictionary = {}


static func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var id: int = m.get_rid().get_id()
	if _tri_cache.has(id):
		return _tri_cache[id]
	var t: int = 0
	for s: int in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		@warning_ignore("integer_division")
		t += ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_tri_cache[id] = t
	return t


static func print_census(root: Node, shadow_splits: int = 1) -> void:
	var c: Dictionary = census(root, shadow_splits)
	var groups: Dictionary = c["groups"]
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(groups[a]["est_draws"]) > int(groups[b]["est_draws"]))
	print("[stats] group                 nodes  meshes  mm(inst)    labels  surf  shadow  est_draws   tris")
	for k: String in keys:
		var r: Dictionary = groups[k]
		if int(r["est_draws"]) < 4:
			continue
		print("[stats] %-20s %6d %7d %4d(%6d) %6d %5d %7d %10d %9d" % [k.left(20), r["nodes"], r["meshes"], r["multimeshes"], r["mm_instances"], r["labels"], r["surfaces"], r["shadow_surfaces"], r["est_draws"], r["tris"]])
	var t: Dictionary = c["total"]
	print("[stats] TOTAL nodes=%d meshes=%d multimeshes=%d mm_instances=%d labels=%d surfaces=%d shadow_surfaces=%d materials=%d est_draws=%d tris=%d" % [
		t["nodes"], t["meshes"], t["multimeshes"], t["mm_instances"], t["labels"], t["surfaces"], t["shadow_surfaces"], t["materials"], t["est_draws"], t["tris"]])
