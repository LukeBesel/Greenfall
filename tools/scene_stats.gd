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
	# [v5load] Distance culling counts too: an instance past its visibility_range_end (measured, as
	# the renderer does, from the camera to its bounds' centre) is left out and counted in
	# `range_culled`. STATS_NO_RANGE=1 gives the old whole-scene numbers.
	var cam: Camera3D = root.get_viewport().get_camera_3d() if root.is_inside_tree() and OS.get_environment("STATS_NO_RANGE") == "" else null
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		if cam and g.visibility_range_end > 0.0:
			var ctr: Vector3 = g.global_transform * g.get_aabb().get_center()
			if cam.global_position.distance_to(ctr) > g.visibility_range_end + g.visibility_range_end_margin:
				total["range_culled"] = int(total.get("range_culled", 0)) + 1
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
			if str(g.name).begins_with("@") or sub in ["MultiMeshInstance3D", "MeshInstance3D"]:  # [v5load] unnamed: say whose it is
				var par: Node = g.get_parent()
				sub = "%s<%s<%s" % [sub.left(9), str(par.name).rstrip("0123456789_-").replace("@", ""), str(par.get_parent().name).rstrip("0123456789_-").replace("@", "") if par.get_parent() else ""]
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
		for f: String in groups[key]:
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
	if OS.get_environment("CAM_PROBE") != "":
		probe_camera(root, float(OS.get_environment("CAM_PROBE_REACH")) if OS.get_environment("CAM_PROBE_REACH") != "" else 6.0)
	for fv: Node in root.find_children("*", "FieldView", true, false):  # [vqa2] junk LOD split
		if (fv as FieldView).lod:
			var c2: Vector2i = (fv as FieldView).lod.counts()
			print("[stats] junk lod: near=%d far=%d radius=%.0f m id=%d" % [c2.x, c2.y, (fv as FieldView).lod.near_radius, (fv as FieldView).lod.get_instance_id()])
	var c: Dictionary = census(root, shadow_splits)
	var groups: Dictionary = c["groups"]
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(groups[a]["est_draws"]) > int(groups[b]["est_draws"]))
	print("[stats] group                 nodes  meshes  mm(inst)    labels  surf  shadow  est_draws   tris")
	for k: String in keys:
		var r: Dictionary = groups[k]
		if int(r["est_draws"]) < 4 and int(r["tris"]) < 100000:  # [vqa2] keep heavy one-surface groups
			continue
		print("[stats] %-20s %6d %7d %4d(%6d) %6d %5d %7d %10d %9d" % [k.left(20 if OS.get_environment("STATS_SPLIT") == "" else 60), r["nodes"], r["meshes"], r["multimeshes"], r["mm_instances"], r["labels"], r["surfaces"], r["shadow_surfaces"], r["est_draws"], r["tris"]])
	var t: Dictionary = c["total"]
	print("[stats] TOTAL nodes=%d meshes=%d multimeshes=%d mm_instances=%d labels=%d surfaces=%d shadow_surfaces=%d materials=%d est_draws=%d tris=%d" % [
		t["nodes"], t["meshes"], t["multimeshes"], t["mm_instances"], t["labels"], t["surfaces"], t["shadow_surfaces"], t["materials"], t["est_draws"], t["tris"]])
	if int(t.get("range_culled", 0)) > 0:
		print("[stats] %d instances past their visibility range from the camera are not counted (STATS_NO_RANGE=1 counts them)" % int(t["range_culled"]))


## [vqa2] What sits right in front of the play camera: casts rays through the bottom band and the
## centre of the screen and lists visible geometry whose world AABB they cross within `reach` m.
## `CAM_PROBE=1` with `--scene-stats` prints it (headless works).
static func probe_camera(root: Node, reach: float = 6.0) -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam == null:
		print("[camprobe] no camera")
		return
	var vs: Vector2 = root.get_viewport().get_visible_rect().size
	print("[camprobe] cam=%s fwd=%s near=%.2f" % [cam.global_position, -cam.global_basis.z, cam.near])
	var hits: Dictionary = {}
	var pts: Array = []
	for fy: float in [0.5, 0.8, 0.9, 0.97]:
		for fx: float in [0.1, 0.3, 0.5, 0.7, 0.9]:
			pts.append(Vector2(fx, fy))
	if OS.get_environment("CAM_PROBE_AT") != "":  # e.g. "0.955,0.74": one screen point only
		var at: PackedStringArray = OS.get_environment("CAM_PROBE_AT").split(",")
		pts = [Vector2(float(at[0]), float(at[1]))]
		var o0: Vector3 = cam.project_ray_origin(vs * pts[0])
		var d0: Vector3 = cam.project_ray_normal(vs * pts[0])
		var wp: Vector3 = o0 + d0 * ((0.12 - o0.y) / d0.y)
		var sl: Node = root.get_tree().current_scene
		var info: String = ""
		if sl and sl.get("field") != null:
			var f: HexField = sl.field
			var hid: int = f.hex_at(wp)
			info = " hex=%d water=%s grid_r=%d" % [hid, str(f.is_water(hid)) if hid >= 0 else "-", f.radius]
			var pw: Vector3 = wp + f.border_warp(wp)
			var aw: Vector2i = Hex.world_to_axial(Vector2(pw.x, pw.z), f.hex_size)
			info += " warped_axial=%s ring=%d in_grid=%s warped_id=%d" % [aw, Hex.distance(aw, Vector2i.ZERO), str(f.axial_to_id.has(aw)), int(f.axial_to_id.get(aw, -1))]
		print("[camprobe] point on y=0.12: %s%s" % [wp, info])
		var space: PhysicsDirectSpaceState3D = cam.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(o0, o0 + d0 * 400.0)
		var hit: Dictionary = space.intersect_ray(q)
		var sun: DirectionalLight3D = sl.get("sun") if sl else null
		if sun == null:
			for n: Node in root.find_children("*", "DirectionalLight3D", true, false):
				if (n as DirectionalLight3D).visible:
					sun = n
					break
		if sun:
			var to_sun: Vector3 = sun.global_basis.z
			var qs := PhysicsRayQueryParameters3D.create(wp + Vector3(0, 0.05, 0), wp + to_sun * 300.0)
			var hs: Dictionary = space.intersect_ray(qs)
			print("[camprobe] toward sun %s (shadow max %.0f m): %s" % [to_sun, sun.directional_shadow_max_distance, str((hs["collider"] as Node).get_path()) + " at " + str(hs["position"]) if not hs.is_empty() else "open sky"])
		if not hit.is_empty():
			print("[camprobe] physics hit %s at %s (%.1f m) normal=%s" % [(hit["collider"] as Node).get_path(), hit["position"], o0.distance_to(hit["position"]), hit["normal"]])
	for pt: Vector2 in pts:
		var fx: float = pt.x
		var fy: float = pt.y
		if true:
			var o: Vector3 = cam.project_ray_origin(vs * Vector2(fx, fy))
			var d: Vector3 = cam.project_ray_normal(vs * Vector2(fx, fy))
			for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
				var g: GeometryInstance3D = n as GeometryInstance3D
				if not g.is_visible_in_tree():
					continue
				var box: AABB = g.global_transform * g.get_aabb()
				if g is MultiMeshInstance3D:  # test each instance's own box
					var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
					if mm == null or mm.mesh == null or not box.intersects(AABB(o, d * reach).abs().grow(0.01)):
						continue
					var nvis: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
					for ii: int in mini(nvis, 20000):
						var ib: AABB = g.global_transform * mm.get_instance_transform(ii) * mm.mesh.get_aabb()
						var ih: Variant = ib.intersects_segment(o, o + d * reach)
						if ih != null or ib.has_point(o):
							var idist: float = 0.0 if ih == null else o.distance_to(ih)
							var ik: String = "%s#%d" % [g.get_path(), ii]
							if not hits.has(ik) or float(hits[ik][0]) > idist:
								hits[ik] = [idist, fy, ib.size]
					continue
				var hit: Variant = box.intersects_segment(o, o + d * reach)
				if hit != null or box.has_point(o):
					var dist: float = 0.0 if hit == null else o.distance_to(hit)
					var k: String = str(g.get_path())
					if not hits.has(k) or float(hits[k][0]) > dist:
						hits[k] = [dist, fy, box.size]
	for k: String in hits:
		var nd: Node = root.get_node_or_null(NodePath(k.split("#")[0]))
		var extra: String = ""
		if nd is MeshInstance3D:
			extra = " at %s mesh=%s %s" % [(nd as Node3D).global_position, (nd as MeshInstance3D).mesh.resource_name, (nd as MeshInstance3D).mesh.resource_path]
		print("[camprobe] %.2f m (row %.2f) size=%s %s%s" % [hits[k][0], hits[k][1], hits[k][2], k, extra])
