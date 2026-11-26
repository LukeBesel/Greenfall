extends RefCounted
## [artguard] The world side of the art guard (tools/art_guard.sh; docs/ART_BASELINE.md). On a fresh
## globe with the start town up (`--fresh --orbit --no-intro --art-guard`) it checks what new art
## can break, prints readable [artguard] lines, then one `[artguard] JSON {...}` line that
## tools/art_guard.py compares with docs/art_baseline.json, and quits:
##   mesh/collider: in the start yard and town (site-local, round the pad), every visible solid
##     prop has a collider (Lumi would walk through it) and every solid collider has something
##     visible over it (an invisible wall). Leaks are listed by owner and spot; the baseline's own
##     leaks (and docs/art_baseline.json allow.passable / allow.invisible) do not fail.
##   colliders: the census of solid shapes there (count, a hash of their rounded boxes) per area.
##   white: visible surfaces with no material at all (Godot draws them default white).
##   builders: triangles per procedural build (Lumi in every design, each robot body and look,
##     each kit building and state, the ship tiers) and default-white surfaces in each.
##   rig: every member and node name that player/patch.gd, player/lumi_style_rig.gd,
##     player/photo_poser.gd, story/intro.gd, systems/lumi_style.gd and the Locker / builder UI use
##     on Lumi's model exists on a built PatchModel; every animation they play exists.
##   locker: each colour slot, eye shape, head piece, chest, shoulders, held item, companion,
##     pattern and wear of the Character Builder changes how Lumi looks (a fingerprint of his
##     visible meshes, materials and shader values).
##   film: every shot of data/intro_shots.json has its code, every cue its _cue_ method, every line
##     its text, every camera anchor resolves (yard anchors on the start site), and the nodes the
##     film looks up by name on the ark, the pods and the crash site are still there.
## --art-guard-fault=NAME plants one fault to prove the check catches it: walkthrough (a 1 m crate
## with no collider by the bench), invisible (a box collider with nothing over it), white (a mesh
## with no material), rig (a member the code would call that the model lacks), locker (the eye
## colour slot stops applying), film (a shot cue with no method), tris (a builder 3x heavier).

const BAND_LO: float = 0.2
const BAND_HI: float = 1.2
const CELL: float = 0.5
## Start area round the pad (site-local metres): the yard, the town and its edge.
const YARD_R: float = 32.0
const SKIP_CLASSES: Array[String] = ["Patch", "PatchModel", "Robot", "RobotVisual", "SphereBot", "JunkCube", "LitterView", "Fauna",
	"Garden", "FarJunk", "PickupFx", "GlobeView", "HUD", "PhotoMode", "SkyDirector", "Vfx", "SphereTerrain",
	"SphereShell", "SphereStreamer", "SphereJunkView", "SphereLitter", "SphereWater", "Intro", "SpaceStage", "FaunaSpace", "GlimBot"]
const SKIP_NAMES: Array[String] = ["Ground", "Cubes", "Fleet", "Skyline", "Fauna", "Garden", "Plants", "Sky", "Weather", "Chunks", "Water"]
const RIG_FILES: Array[String] = ["res://player/patch.gd", "res://player/lumi_style_rig.gd", "res://player/photo_poser.gd",
	"res://story/intro.gd", "res://systems/lumi_style.gd", "res://ui/locker_panel.gd", "res://ui/lumi_builder.gd",
	"res://ui/model_preview.gd", "res://player/pickup_fx.gd", "res://player/carry_point.gd", "res://story/space_stage.gd"]
## Names the film's code looks up with get_node_or_null / find_child on its sets.
const FILM_FILES: Array[String] = ["res://story/intro.gd", "res://story/space_stage.gd", "res://story/crash_site.gd",
	"res://story/escape_pod.gd", "res://story/cradle_ship.gd"]

static var fault: String = ""
static var fails: Array = []
static var warns: Array = []


static func _fail(area: String, msg: String) -> void:
	fails.append({"area": area, "msg": msg})
	print("[artguard] FAIL %s: %s" % [area, msg])


static func _warn(area: String, msg: String) -> void:
	warns.append({"area": area, "msg": msg})
	print("[artguard] WARN %s: %s" % [area, msg])


static func _class_of(n: Node) -> String:
	var s: Script = n.get_script() as Script
	while s:
		if s.get_global_name() != "":
			return s.get_global_name()
		s = s.get_base_script()
	return n.get_class()


## A name that is the same on every run: the nearest scripted ancestor's class and the node's own
## name without Godot's @digits.
static func _key(n: Node) -> String:
	var a: Node = n.get_parent()
	while a and _class_of(a) == a.get_class() and a.get_parent():
		a = a.get_parent()
	var nm: String = String(n.name)
	var re := RegEx.create_from_string("@?[A-Za-z0-9_]*@\\d+|\\d+$")
	nm = re.sub(nm, "#", true)
	var pn: String = re.sub(String(n.get_parent().name), "#", true) if n.get_parent() else ""
	return "%s/%s/%s" % [_class_of(a) if a else "?", pn, nm]


static func _skip(n: Node) -> bool:
	if n.name in SKIP_NAMES or String(n.name).begins_with("Junk_") or n.has_meta("pile"):
		return true
	return _class_of(n) in SKIP_CLASSES


# ------------------------------------------------------------------------------------- the run
static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	fault = DevHooks.get_s("art-guard-fault", "") if DevHooks.has("art-guard-fault") else ""
	if fault == "all":
		fault = "walkthrough,invisible,white,rig,locker,film,tris"
	var t_all: int = Time.get_ticks_msec()
	await tree.create_timer(DevHooks.get_f("art-guard", 3.0)).timeout
	while so.hub_frame == null or bool(so.w.get("building")):
		await tree.process_frame
	var sm: SiteManager = so.globe.site_manager
	var p: SitePrefab = sm.prefab(0)
	while p == null or not p.is_built:
		await tree.process_frame
		p = sm.prefab(0)
	for k: int in 30:
		await tree.process_frame
	for k: int in 4:
		await tree.physics_frame
	var out: Dictionary = {}
	var frame := Transform3D(p.global_basis.orthonormalized(), p.global_position)
	if fault != "":
		await _plant(so, p, frame)
	print("[artguard] world up in %d ms; fault %s" % [Time.get_ticks_msec() - t_all, fault if fault != "" else "none"])
	var t0: int = Time.get_ticks_msec()
	out["audit"] = _mesh_collider_audit(so, frame)
	print("[artguard] mesh/collider audit in %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	out["builders"] = await _builders(tree)
	print("[artguard] builders in %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	out["rig"] = await _rig(tree, so)
	out["locker"] = await _locker(tree)
	print("[artguard] rig + locker in %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	out["film"] = await _film(tree, so)
	print("[artguard] film in %d ms" % (Time.get_ticks_msec() - t0))
	out["look"] = look_settings(so)
	var aud: Dictionary = out["audit"]
	out["colliders"] = aud["colliders"]
	out["white_surfaces"] = aud["white"]
	out["fails"] = fails
	out["warns"] = warns
	out["fault"] = fault
	print("[artguard] world checks: %d fail, %d warn (%d ms)" % [fails.size(), warns.size(), Time.get_ticks_msec() - t_all])
	print("[artguard] JSON " + JSON.stringify(out))
	tree.quit(0)


# ------------------------------------------------------------------------------------- faults
static func _plant(so: SliceOrbit, p: SitePrefab, frame: Transform3D) -> void:
	var bench: Vector3 = p.anchor_local("bench").origin if p.anchor("bench") else Vector3(4, 0, 4)
	var at: Vector3 = bench + Vector3(3.0, 0.0, 3.0)
	var g: float = _ground_local(so, frame, at)
	for f: String in fault.split(",", false):
		_plant_one(f, p, frame, at, g)
	for k: int in 3:
		await so.w.get_tree().physics_frame


static func _plant_one(f: String, p: SitePrefab, frame: Transform3D, at: Vector3, g: float) -> void:
	match f:
		"walkthrough":
			var crate := MeshInstance3D.new()
			crate.name = "PlantedCrate"
			crate.mesh = ProcMesh.box(Vector3(1.0, 1.1, 1.0))
			crate.material_override = StandardMaterial3D.new()
			p.add_child(crate)
			crate.global_transform = frame * Transform3D(Basis.IDENTITY, Vector3(at.x, g + 0.55, at.z))
			print("[artguard] planted: a 1 m crate with no collider at site (%.1f, %.1f)" % [at.x, at.z])
		"invisible":
			pass  # planted by the audit itself on open ground (_plant_wall), where nothing visible stands
		"white":
			var mi := MeshInstance3D.new()
			mi.name = "PlantedWhite"
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (ProcMesh.box(Vector3(0.3, 0.3, 0.3)) as Mesh).surface_get_arrays(0))
			mi.mesh = am
			p.add_child(mi)
			mi.global_transform = frame * Transform3D(Basis.IDENTITY, Vector3(at.x, g + 2.5, at.z))
			print("[artguard] planted: a mesh with no material at site (%.1f, %.1f)" % [at.x, at.z])


# ------------------------------------------------------------------------------------- audit
static func _ground_local(so: SliceOrbit, frame: Transform3D, local: Vector3) -> float:
	var wp: Vector3 = frame * Vector3(local.x, 0.0, local.z)
	return (frame.affine_inverse() * so.globe.terrain.ground(wp.normalized())).y


static func _tri_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var t: int = 0
	if mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for s: int in am.get_surface_count():
			if am.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var il: int = am.surface_get_array_index_len(s)
			t += (il if il > 0 else am.surface_get_array_len(s)) / 3
		return t
	return mesh.get_faces().size() / 3


static func _no_material(gi: GeometryInstance3D, mesh: Mesh) -> int:
	if gi.material_override != null or mesh == null:
		return 0
	var n: int = 0
	for s: int in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(s)
		if gi is MeshInstance3D and (gi as MeshInstance3D).get_surface_override_material(s) != null:
			m = (gi as MeshInstance3D).get_surface_override_material(s)
		if m == null:
			n += 1
	return n


## Visible geometry and solid colliders within the start area, compared both ways.
static func _mesh_collider_audit(so: SliceOrbit, frame: Transform3D) -> Dictionary:
	var inv: Transform3D = frame.affine_inverse()
	var radius: float = VerdanceSite.TOWN_R + 6.0
	var space: PhysicsDirectSpaceState3D = so.w.get_world_3d().direct_space_state
	var vis: Dictionary = {}    # Vector2i cell -> true: visible geometry in the body band
	var props: Array = []       # [node, local aabb]: single props to check for a collider
	var merged: Array = []      # [node, local points in the band]
	var white: Array = []
	var nwhite: int = 0
	var geo: int = 0
	var gcache: Dictionary = {}
	var ground := func(x: float, z: float) -> float:
		var k := Vector2i(floori(x / 4.0), floori(z / 4.0))
		if not gcache.has(k):
			gcache[k] = _ground_local(so, frame, Vector3((k.x + 0.5) * 4.0, 0, (k.y + 0.5) * 4.0))
		return gcache[k]
	var stack: Array[Node] = [so.w]
	var dbg: Dictionary = {}
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if DevHooks.has("art-guard-debug") and n is GeometryInstance3D:
			var why: String = "skip" if _skip(n) else "hidden" if not (n as Node3D).is_visible_in_tree() else n.get_class()
			if n is MultiMeshInstance3D and why == "MultiMeshInstance3D" and (n.get_meta("inst_xf", []) as Array).is_empty():
				why = "mmi-no-xf"
			var d0: float = Vector2((inv * (n as Node3D).global_position).x, (inv * (n as Node3D).global_position).z).length()
			if d0 < radius:
				var kk: String = "%s %s" % [why, _key(n).get_slice("/", 0)]
				dbg[kk] = int(dbg.get(kk, 0)) + 1
		if n != so.w and _skip(n):
			continue
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		if n is CanvasItem or n is CanvasLayer or n is SubViewport:
			continue
		for c: Node in n.get_children():
			stack.append(c)
		var items: Array = []  # [mesh, global xf]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			items.append([(n as MeshInstance3D).mesh, (n as Node3D).global_transform])
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			var xfs: Array = n.get_meta("inst_xf", [])
			var cnt: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			if xfs.is_empty() and DisplayServer.get_name() != "headless":
				for i: int in cnt:
					xfs.append(mm.get_instance_transform(i))
			for i: int in mini(cnt, xfs.size()):
				items.append([mm.mesh, (n as Node3D).global_transform * (xfs[i] as Transform3D)])
		if items.is_empty():
			continue
		var gi := n as GeometryInstance3D
		for it: Array in items:
			var mesh: Mesh = it[0]
			var xf: Transform3D = inv * (it[1] as Transform3D)
			if xf.basis.determinant() == 0.0:
				continue
			var ab: AABB = xf * mesh.get_aabb()
			var c: Vector3 = ab.get_center()
			if Vector2(c.x, c.z).length() > radius + maxf(ab.size.x, ab.size.z) * 0.5:
				continue
			geo += 1
			var nw: int = _no_material(gi, mesh)
			if nw > 0:
				nwhite += nw
				if white.size() < 8:
					white.append("%s at (%.0f, %.0f)" % [_key(n), c.x, c.z])
			var clutter: bool = ColliderAudit._clutter(n, mesh) or (n is MeshInstance3D and PropColliders._see_through(n as MeshInstance3D))
			# The body band raster of everything visible (clutter too: a wall of cloth is still seen).
			var small: bool = ab.size.x <= 1.5 and ab.size.z <= 1.5
			if small:
				var g: float = ground.call(c.x, c.z)
				if ab.end.y >= g + BAND_LO and ab.position.y <= g + BAND_HI:
					for cx: int in range(floori(ab.position.x / CELL), floori(ab.end.x / CELL) + 1):
						for cz: int in range(floori(ab.position.z / CELL), floori(ab.end.z / CELL) + 1):
							vis[Vector2i(cx, cz)] = true
					if not clutter and n is MeshInstance3D:
						props.append([n, ab, g])
			else:
				var pts: Array = _band_points(mesh, xf, ground, radius, vis)
				if not clutter and n is MeshInstance3D and not pts.is_empty():
					merged.append([n, pts])
	if DevHooks.has("art-guard-debug"):
		var ks: Array = dbg.keys()
		ks.sort()
		for kk: String in ks:
			print("[artguard-debug] %5d %s" % [dbg[kk], kk])
	# Walk-through: solid-looking props with nothing solid in their band.
	var leaks: Array = []
	for pr: Array in props:
		var n: Node = pr[0]
		var ab: AABB = pr[1]
		var g: float = pr[2]
		if ab.position.y > g + 0.6 or ab.end.y < g + 0.5 or ab.size.y < 0.3 or minf(ab.size.x, ab.size.z) < 0.05 or maxf(ab.size.x, ab.size.z) < 0.1:
			continue
		var lo: float = maxf(ab.position.y, g + BAND_LO)
		var hi: float = minf(ab.end.y, g + BAND_HI)
		if hi - lo < 0.15:
			continue
		var ctr := Vector3(ab.get_center().x, (lo + hi) * 0.5, ab.get_center().z)
		if not _covered(space, frame, ctr, Vector3(ab.size.x * 0.4, (hi - lo) * 0.5, ab.size.z * 0.4)):
			leaks.append({"key": _key(n), "at": [snappedf(ctr.x, 0.1), snappedf(ctr.z, 0.1)], "size": [snappedf(ab.size.x, 0.05), snappedf(ab.size.y, 0.05), snappedf(ab.size.z, 0.05)]})
	for mg: Array in merged:
		var n: Node = mg[0]
		var pts: Array = mg[1]
		var bad: Dictionary = {}
		var tested: int = 0
		for q: Vector3 in pts:
			tested += 1
			if not _covered(space, frame, q, Vector3(0.22, 0.2, 0.22)):
				bad[Vector2i(floori(q.x), floori(q.z))] = q
		for grp: Array in _groups(bad, 1):
			if grp.size() < 2:
				continue  # a lone metre of a sloped edge, a rail end, an awning lip
			var mn := Vector2(INF, INF)
			var mx := Vector2(-INF, -INF)
			for k: Vector2i in grp:
				mn = mn.min(Vector2(k))
				mx = mx.max(Vector2(k) + Vector2.ONE)
			leaks.append({"key": _key(n), "at": [snappedf((mn.x + mx.x) * 0.5, 0.1), snappedf((mn.y + mx.y) * 0.5, 0.1)], "size": [mx.x - mn.x, 0.0, mx.y - mn.y], "cells": grp.size()})
	if "invisible" in fault:
		_plant_wall(so, frame, vis, ground)
	# Invisible walls: solid shapes in the band with nothing visible along their outline.
	var walls: Array = []
	var shapes: Array = []  # [key, local aabb]
	for body: Node in so.w.find_children("*", "CollisionObject3D", true, false):
		var co := body as CollisionObject3D
		if co is RigidBody3D or co is CharacterBody3D or co is Area3D or (co.collision_layer & PhysLayers.SOLID) == 0:
			continue
		if _skipped_above(co, so.w):
			continue
		for cs: Node in co.find_children("*", "CollisionShape3D", true, false):
			var shp := cs as CollisionShape3D
			if shp.disabled or shp.shape == null or shp.shape is WorldBoundaryShape3D or shp.shape is HeightMapShape3D:
				continue
			var xf: Transform3D = inv * shp.global_transform
			var ab: AABB = xf * _shape_aabb(shp.shape)
			var c: Vector3 = ab.get_center()
			if Vector2(c.x, c.z).length() > radius:
				continue
			if ab.size.x > 60.0 or ab.size.z > 60.0:
				continue  # the pad slab, the town's ground plates
			shapes.append([_key(shp), ab])
			var g: float = ground.call(c.x, c.z)
			if ab.end.y < g + BAND_LO + 0.1 or ab.position.y > g + BAND_HI - 0.1:
				continue  # not in Lumi's way
			var seen: int = 0
			var tot: int = 0
			for pt: Vector2 in _outline(ab):
				tot += 1
				var k := Vector2i(floori(pt.x / CELL), floori(pt.y / CELL))
				var hit: bool = false
				for o: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
					if vis.has(k + o):
						hit = true
						break
				seen += 1 if hit else 0
			if tot > 0 and float(seen) / tot < 0.34:
				walls.append({"key": _key(shp), "at": [snappedf(c.x, 0.1), snappedf(c.z, 0.1)], "size": [snappedf(ab.size.x, 0.05), snappedf(ab.size.y, 0.05), snappedf(ab.size.z, 0.05)], "seen": snappedf(float(seen) / tot, 0.01)})
	# The census: count and a hash of the rounded boxes, the yard and the town apart.
	var census: Dictionary = {}
	for area: String in ["yard", "town"]:
		var rows: PackedStringArray = []
		for s: Array in shapes:
			var ab: AABB = s[1]
			var d: float = Vector2(ab.get_center().x, ab.get_center().z).length()
			if (area == "yard") != (d <= YARD_R):
				continue
			rows.append("%.0f,%.0f,%.0f/%.0f,%.0f,%.0f" % [ab.position.x * 2, ab.position.y * 2, ab.position.z * 2, ab.size.x * 2, ab.size.y * 2, ab.size.z * 2])
		rows.sort()
		census[area] = {"count": rows.size(), "hash": "\n".join(rows).sha1_text().substr(0, 12)}
	var r: Dictionary = {"leaks": leaks, "walls": walls, "colliders": census, "white": {"count": nwhite, "eg": white},
		"geometry": geo, "props": props.size(), "merged": merged.size(), "vis_cells": vis.size()}
	print("[artguard] start area (r %.0f m): %d visible geometry pieces, %d props and %d merged meshes checked, %d solid shapes (yard %d, town %d), %d visible cells in the band" % [
		radius, geo, props.size(), merged.size(), shapes.size(), census["yard"]["count"], census["town"]["count"], vis.size()])
	print("[artguard] walk-through spots %d, invisible walls %d, default-white surfaces %d" % [leaks.size(), walls.size(), nwhite])
	for l: Dictionary in leaks:
		print("[artguard]   walk-through: %s at site (%.1f, %.1f) size %s" % [l["key"], l["at"][0], l["at"][1], str(l["size"])])
	for l: Dictionary in walls:
		print("[artguard]   invisible wall: %s at site (%.1f, %.1f) size %s, %.0f%% of its outline seen" % [l["key"], l["at"][0], l["at"][1], str(l["size"]), float(l["seen"]) * 100.0])
	return r


static func _skipped_above(n: Node, root: Node) -> bool:
	var a: Node = n
	while a and a != root:
		if _skip(a):
			return true
		a = a.get_parent()
	return false


## Points of a merged mesh's surface in Lumi's body band (site-local), and its band cells into `vis`.
static func _band_points(mesh: Mesh, xf: Transform3D, ground: Callable, radius: float, vis: Dictionary) -> Array:
	var faces: PackedVector3Array = mesh.get_faces()
	var pts: Array = []
	var seen: Dictionary = {}
	for i: int in range(0, faces.size(), 3):
		var stack: Array = [[xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]]]
		while not stack.is_empty():
			var tri: Array = stack.pop_back()
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var cc: Vector3 = tri[2]
			var mn: Vector3 = a.min(b).min(cc)
			var mx: Vector3 = a.max(b).max(cc)
			var cx: float = (mn.x + mx.x) * 0.5
			var cz: float = (mn.z + mx.z) * 0.5
			if Vector2(cx, cz).length() > radius:
				continue
			var g: float = ground.call(cx, cz)
			if mx.y < g + BAND_LO or mn.y > g + BAND_HI:
				continue
			var e_max: float = maxf((b - a).length(), maxf((cc - b).length(), (a - cc).length()))
			if e_max > 0.0 and (b - a).cross(cc - a).length() / e_max < 0.025:
				continue  # a wire's sliver
			if e_max > 1.0:
				var ab: Vector3 = (a + b) * 0.5
				var bc: Vector3 = (b + cc) * 0.5
				var ca: Vector3 = (cc + a) * 0.5
				stack.append_array([[a, ab, ca], [ab, b, bc], [ca, bc, cc], [ab, bc, ca]])
				continue
			var ctr: Vector3 = (a + b + cc) / 3.0
			if ctr.y < g + BAND_LO or ctr.y > g + BAND_HI:
				continue
			var k := Vector2i(floori(ctr.x / CELL), floori(ctr.z / CELL))
			vis[k] = true
			# Only upright faces stop Lumi; one point per cell and height step.
			var nrm: Vector3 = (b - a).cross(cc - a)
			if nrm.length() < 1e-6 or absf(nrm.normalized().y) > 0.6:
				continue
			var kk := Vector3i(k.x, k.y, floori((ctr.y - g) / 0.4))
			if seen.has(kk):
				continue
			seen[kk] = true
			pts.append(ctr)
	return pts


static func _covered(space: PhysicsDirectSpaceState3D, frame: Transform3D, local: Vector3, half: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = (half * 2.0).max(Vector3(0.04, 0.04, 0.04))
	q.shape = bs
	q.transform = frame * Transform3D(Basis.IDENTITY, local)
	q.collision_mask = PhysLayers.SOLID
	q.collide_with_areas = false
	return not space.intersect_shape(q, 1).is_empty()


static func _shape_aabb(s: Shape3D) -> AABB:
	if s is BoxShape3D:
		var sz: Vector3 = (s as BoxShape3D).size
		return AABB(-sz * 0.5, sz)
	if s is CylinderShape3D:
		var c := s as CylinderShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2, c.height, c.radius * 2))
	if s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2, c.height, c.radius * 2))
	if s is SphereShape3D:
		var r: float = (s as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * r * 2)
	var pts: PackedVector3Array = []
	if s is ConcavePolygonShape3D:
		pts = (s as ConcavePolygonShape3D).get_faces()
	elif s is ConvexPolygonShape3D:
		pts = (s as ConvexPolygonShape3D).points
	if pts.is_empty():
		return AABB()
	var ab := AABB(pts[0], Vector3.ZERO)
	for p: Vector3 in pts:
		ab = ab.expand(p)
	return ab


## Points every half metre along an AABB's footprint outline (site-local XZ).
static func _outline(ab: AABB) -> Array:
	var out: Array = []
	var x0: float = ab.position.x
	var x1: float = ab.end.x
	var z0: float = ab.position.z
	var z1: float = ab.end.z
	var nx: int = maxi(1, ceili((x1 - x0) / CELL))
	var nz: int = maxi(1, ceili((z1 - z0) / CELL))
	for i: int in nx + 1:
		var x: float = lerpf(x0, x1, float(i) / nx)
		out.append(Vector2(x, z0))
		out.append(Vector2(x, z1))
	for i: int in range(1, nz):
		var z: float = lerpf(z0, z1, float(i) / nz)
		out.append(Vector2(x0, z))
		out.append(Vector2(x1, z))
	return out


static func _groups(cells: Dictionary, reach: int) -> Array:
	var done: Dictionary = {}
	var out: Array = []
	for k: Vector2i in cells:
		if done.has(k):
			continue
		var grp: Array = [k]
		done[k] = true
		var qi: int = 0
		while qi < grp.size():
			var cur: Vector2i = grp[qi]
			qi += 1
			for dx: int in range(-reach, reach + 1):
				for dz: int in range(-reach, reach + 1):
					var nk: Vector2i = cur + Vector2i(dx, dz)
					if cells.has(nk) and not done.has(nk):
						done[nk] = true
						grp.append(nk)
		out.append(grp)
	return out


# ------------------------------------------------------------------------------------- builders
static func _census(root: Node) -> Dictionary:
	var tris: int = 0
	var white: int = 0
	var meshes: int = 0
	for n: Node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		if not (n is GeometryInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			tris += _tri_count((n as MeshInstance3D).mesh)
			white += _no_material(n as GeometryInstance3D, (n as MeshInstance3D).mesh)
			meshes += 1
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			var cnt: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			tris += _tri_count(mm.mesh) * cnt
			white += _no_material(n as GeometryInstance3D, mm.mesh)
			meshes += 1
	return {"tris": tris, "white": white, "meshes": meshes}


static func _builders(tree: SceneTree) -> Dictionary:
	var out: Dictionary = {}
	var holder := Node3D.new()
	holder.name = "ArtGuardBuilders"
	holder.position = Vector3(0, -5000, 0)
	tree.root.add_child(holder)
	for v: String in PatchModel.VARIANTS:
		var m := PatchModel.new()
		m.preview_variant = v
		holder.add_child(m)
		out["lumi/" + v] = _census(m)
		m.free()
	for t: String in ["scoopie", "haulbug", "skimmer", "seedling", "drip", "multibot"]:
		for look: String in ["salvage", "restored", "modern", "hover"]:
			var rv := RobotVisual.new()
			holder.add_child(rv)
			rv.build(t, look)
			await tree.process_frame
			out["robot/%s/%s" % [t, look]] = _census(rv)
			rv.free()
	for k: String in KitBuilding.KINDS:
		for st: String in ["broken", "repaired", "restored"]:
			var kb: Node3D = KitBuilding.create(k, st, 1)
			holder.add_child(kb)
			out["kit/%s/%s" % [k, st]] = _census(kb)
			kb.free()
	for tier: int in [1, 4, 7]:
		var sm := ShipModel.new()
		holder.add_child(sm)
		sm.build(tier)
		out["ship/%d" % tier] = _census(sm)
		sm.free()
	if "tris" in fault:
		out["lumi/aurora"]["tris"] = int(out["lumi/aurora"]["tris"]) * 3
	holder.free()
	var lumi: Dictionary = out["lumi/aurora"]
	print("[artguard] builders: %d builds; Lumi %d tris, a Scoopie Mk I %d, a hangar %d, the ship Mk VII %d" % [
		out.size(), lumi["tris"], out["robot/scoopie/salvage"]["tris"], out["kit/hangar/restored"]["tris"], out["ship/7"]["tris"]])
	return out


# ------------------------------------------------------------------------------------- rig
## What the code uses on Lumi's model, from the sources: model.X, m.X ... (variables typed or
## named as the model), get("X") / has_method("X") on them, get_node("X") / find_child("X"), and
## animation names played on an AnimationPlayer.
static func contract() -> Dictionary:
	var members: Dictionary = {}  # name -> file
	var nodes: Dictionary = {}
	var anims: Dictionary = {}
	var re_var := RegEx.create_from_string("(?:var|func\\s+\\w+\\(|,)\\s*(\\w+)\\s*:\\s*PatchModel\\b|(\\w+)\\s*:?=\\s*PatchModel\\.new|(\\w+)\\s*=\\s*[^\\n]*as PatchModel\\b")
	for path: String in RIG_FILES:
		var src: String = FileAccess.get_file_as_string(path)
		if src == "":
			continue
		var names: Dictionary = {"model": true, "_model": true, "lumi_model": true}
		for m: RegExMatch in re_var.search_all(src):
			for gi: int in [1, 2, 3]:
				if m.get_string(gi) != "":
					names[m.get_string(gi)] = true
		for k: String in names.keys():
			if k.length() < 3:
				names.erase(k)  # a function's `m` is the model in one function and a mesh in the next
		var alt: String = "|".join(PackedStringArray(names.keys()))
		var re_dot := RegEx.create_from_string("(?<![\\w.])(?:" + alt + ")\\.([A-Za-z_]\\w*)")
		var re_str := RegEx.create_from_string("(?<![\\w.])(?:" + alt + ")\\.(?:get|has_method|call|set|get_node_or_null|get_node|find_child|has_node)\\(\"([^\"]+)\"")
		for m: RegExMatch in re_dot.search_all(src):
			var nm: String = m.get_string(1)
			if nm in ["get", "has_method", "call", "set", "get_node_or_null", "get_node", "find_child", "has_node", "find_children", "is_inside_tree", "new"]:
				continue
			members[nm] = path.get_file()
		for m: RegExMatch in re_str.search_all(src):
			var whole: String = m.get_string(0)
			if ".get_node" in whole or ".find_child" in whole or ".has_node" in whole:
				nodes[m.get_string(1)] = path.get_file()
			else:
				members[m.get_string(1)] = path.get_file()
		var re_anim := RegEx.create_from_string("(?<![\\w.])\\w*(?:anim|Anim|_ap)\\w*\\.(?:play|play_backwards|queue)\\(\"([^\"]+)\"")
		for m: RegExMatch in re_anim.search_all(src):
			anims[m.get_string(1)] = path.get_file()
	return {"members": members, "nodes": nodes, "anims": anims}


static func _rig(tree: SceneTree, so: SliceOrbit) -> Dictionary:
	var c: Dictionary = contract()
	if "rig" in fault:
		(c["members"] as Dictionary)["set_wing_flap"] = "patch.gd (planted)"
	var m := PatchModel.new()
	tree.root.add_child(m)
	var props: Dictionary = {}
	for p: Dictionary in m.get_property_list():
		props[str(p["name"])] = true
	var consts: Dictionary = (m.get_script() as Script).get_script_constant_map()
	var missing: Array = []
	for nm: String in c["members"]:
		if not (m.has_method(nm) or props.has(nm) or m.has_signal(nm) or consts.has(nm)):
			missing.append("%s (%s)" % [nm, c["members"][nm]])
	var nodes_missing: Array = []
	for nm: String in c["nodes"]:
		if m.find_child(nm, true, false) == null and m.get_node_or_null(NodePath(nm)) == null:
			nodes_missing.append("%s (%s)" % [nm, c["nodes"][nm]])
	var have_anims: Dictionary = {}
	for ap: Node in m.find_children("*", "AnimationPlayer", true, false):
		for a: StringName in (ap as AnimationPlayer).get_animation_list():
			have_anims[String(a)] = true
	var anims_missing: Array = []
	for a: String in c["anims"]:
		if not have_anims.has(a):
			anims_missing.append("%s (%s)" % [a, c["anims"][a]])
	# The live Lumi in the world is the same class (a replaced model must still be a PatchModel).
	var live: Variant = so.w.get("patch").get("model") if so.w.get("patch") else null
	if not (live is PatchModel):
		_fail("rig", "Lumi in the world has no PatchModel (Patch.model is %s)" % str(live))
	m.free()
	missing.sort()
	nodes_missing.sort()
	for x: String in missing:
		print("[artguard]   rig: the code uses %s on Lumi's model; a built PatchModel has no such member" % x)
	for x: String in nodes_missing:
		print("[artguard]   rig: node %s looked up on Lumi's model; not on a fresh build" % x)
	for x: String in anims_missing:
		print("[artguard]   rig: animation %s played; not on Lumi's model" % x)
	print("[artguard] rig: %d members, %d node names, %d animations used by the code; %d / %d / %d missing" % [
		(c["members"] as Dictionary).size(), (c["nodes"] as Dictionary).size(), (c["anims"] as Dictionary).size(), missing.size(), nodes_missing.size(), anims_missing.size()])
	return {"members": (c["members"] as Dictionary).size(), "missing": missing, "nodes_missing": nodes_missing, "anims_missing": anims_missing}


# ------------------------------------------------------------------------------------- locker
## What Lumi looks like, as a hash of his visible meshes, materials and shader values.
static func fingerprint(root: Node) -> String:
	var rows: PackedStringArray = []
	for k: StringName in root.get_meta_list():
		var mv: Variant = root.get_meta(k)
		if mv is Color or mv is float or mv is int or mv is String:
			rows.append("meta %s=%s" % [k, (mv as Color).to_html() if mv is Color else str(mv)])
	for n: Node in [root] + root.find_children("*", "", true, false):
		if n is Node3D and not (n as Node3D).is_visible_in_tree():
			continue
		if n is Label3D:
			var l := n as Label3D
			rows.append("L %s %s %s" % [l.text, l.modulate.to_html(), l.outline_modulate.to_html()])
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
		if mesh == null:
			continue
		var ab: AABB = (root as Node3D).global_transform.affine_inverse() * (gi.global_transform * mesh.get_aabb()) if root is Node3D else mesh.get_aabb()
		rows.append("M %s %s" % [str(ab.position.snapped(Vector3.ONE * 0.01)), str(ab.size.snapped(Vector3.ONE * 0.01))])
		for s: int in mesh.get_surface_count():
			var mat: Material = gi.material_override
			if mat == null and n is MeshInstance3D:
				mat = (n as MeshInstance3D).get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var depth: int = 0
			while mat and depth < 4:
				rows.append("  " + _mat_row(mat))
				mat = mat.next_pass
				depth += 1
	return "\n".join(rows).sha1_text()


static func _mat_row(mat: Material) -> String:
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		return "B %s %s %.2f %s" % [b.albedo_color.to_html(), b.emission.to_html() if b.emission_enabled else "-", b.emission_energy_multiplier, str(b.albedo_texture)]
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var vals: PackedStringArray = []
		if sm.shader:
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				var v: Variant = sm.get_shader_parameter(str(u["name"]))
				vals.append("%s=%s" % [u["name"], (v as Color).to_html() if v is Color else str(v) if not (v is Object) else str(v.get_instance_id() if false else v.get_class())])
		return "S %s %s" % [sm.shader.resource_path if sm.shader else "-", ",".join(vals)]
	return mat.get_class()


static func _styled(tree: SceneTree, holder: Node3D, s: Dictionary) -> String:
	var m := PatchModel.new()
	m.set_meta("lumi_style", s)
	holder.add_child(m)
	m._process(0.05)
	var rig: Node = m.get_node_or_null("LumiStyleRig")
	if rig and rig.has_method("_process"):
		rig._process(0.05)
	var f: String = fingerprint(m)
	m.free()
	return f


static func _locker(tree: SceneTree) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "ArtGuardLocker"
	tree.root.add_child(holder)
	var keep: Variant = GameState.flags.get("skins_unlocked", null)
	GameState.flags["skins_unlocked"] = PatchModel.VARIANTS.keys()
	var base: Dictionary = LumiStyle.preset("aurora")
	var f0: String = _styled(tree, holder, base)
	var dead: Array = []
	var tried: int = 0
	var test_cols: Array[Color] = [Color("#ff2a6d"), Color("#1a5cff")]
	for slot: String in LumiStyle.COLOR_SLOTS:
		if "locker" in fault and slot == "eyes":
			continue
		tried += 1
		var changed: bool = false
		for col: Color in test_cols:  # one of two far-apart colours differs from the preset's
			var s: Dictionary = base.duplicate(true)
			LumiStyle.set_value(s, slot, col)
			if _styled(tree, holder, s) != f0:
				changed = true
				break
		if not changed:
			dead.append("colour %s" % slot)
	if "locker" in fault:
		dead.append("colour eyes (planted: the slot was skipped)")
	for slot: String in LumiStyle.PART_SLOTS:
		for o: Dictionary in LumiStyle.options(slot):
			var id: String = str(o.get("id", ""))
			if id == str(base.get(slot, "")):
				continue
			tried += 1
			var s: Dictionary = base.duplicate(true)
			LumiStyle.set_value(s, slot, id)
			if str(s.get(slot, "")) != id:
				s[slot] = id
			if _styled(tree, holder, s) == f0:
				dead.append("%s %s" % [slot, id])
	var s2: Dictionary = base.duplicate(true)
	if s2.has("wear"):
		tried += 1
		LumiStyle.set_value(s2, "wear", 0.0 if float(s2.get("wear", 0.5)) > 0.5 else 1.0)
		if _styled(tree, holder, s2) == f0:
			dead.append("wear")
	if keep == null:
		GameState.flags.erase("skins_unlocked")
	else:
		GameState.flags["skins_unlocked"] = keep
	holder.free()
	dead.sort()
	print("[artguard] locker: %d style choices tried, %d change nothing on Lumi%s" % [tried, dead.size(), (": " + ", ".join(dead)) if not dead.is_empty() else ""])
	return {"tried": tried, "dead": dead}


# ------------------------------------------------------------------------------------- film
static func _film(tree: SceneTree, so: SliceOrbit) -> Dictionary:
	var table: Dictionary = Intro.load_table()
	var shots: Array = table.get("shots", [])
	var intro_script: GDScript = load("res://story/intro.gd")
	var methods: Dictionary = {}
	for md: Dictionary in intro_script.get_script_method_list():
		methods[str(md["name"])] = true
	var lines: Dictionary = Intro.lines()
	var bad: Array = []
	var world_anchor_names: Dictionary = {}
	for s: Dictionary in shots:
		var id: String = str(s.get("id", ""))
		if not methods.has("_in_" + id) and not methods.has("_run_" + id):
			bad.append("shot %s has no _in_/_run_ code" % id)
		var cues: Array = (s.get("cues", []) as Array).duplicate()
		if "film" in fault and id == "hatch":
			cues.append([1.0, "open_wing_flap"])
		for cu: Variant in cues:
			if not methods.has("_cue_" + str((cu as Array)[1])):
				bad.append("shot %s cue %s has no _cue_ method" % [id, str((cu as Array)[1])])
		for l: Variant in s.get("lines", []):
			if not lines.has(str((l as Array)[1])):
				bad.append("shot %s line %s has no text" % [id, str((l as Array)[1])])
		var cam: Dictionary = s.get("cam", {})
		for k: String in ["anchor", "look_anchor", "target", "center"]:
			if cam.has(k):
				var a: String = str(cam[k])
				if str(s.get("set", "")) == "world" and not a in ["", "pod", "lumi", "glim"]:
					world_anchor_names[a] = id
				elif str(s.get("set", "")) != "world" and not a in ["", "ark", "pod", "lumi"]:
					bad.append("shot %s anchor %s is not a space-set subject" % [id, a])
	var ef: String = str(table.get("end_face", ""))
	if ef != "":
		world_anchor_names[ef] = "end_face"
	var sp: SitePrefab = so.globe.site_manager.prefab(0)
	for a: String in world_anchor_names:
		if not sp.anchor_names().has(a):
			bad.append("shot %s frames yard anchor '%s', the start site has no such anchor" % [world_anchor_names[a], a])
	# Node names the film's code looks up on its sets, against the sets as built.
	var wanted: Dictionary = {}
	var re := RegEx.create_from_string("(?:get_node_or_null|get_node|find_child|has_node)\\(\"([^\"/]+)\"")
	for path: String in FILM_FILES:
		for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(path)):
			if not m.get_string(1).begins_with("/"):
				wanted[m.get_string(1)] = path.get_file()
	var re2 := RegEx.create_from_string("(?:get_node_or_null|get_node|find_child)\\((\\w+)\\.(\\w+)\\)")
	var stage := SpaceStage.new()
	stage.name = "ArtGuardStage"
	tree.root.add_child(stage)
	for k: int in 3:
		await tree.process_frame
	var roots: Array[Node] = [stage]
	var pod_site: Variant = so.w.get_meta("orbit_pod", null) if so.w.has_meta("orbit_pod") else null
	if pod_site is Node:
		roots.append(pod_site)
	for n: Node in tree.get_nodes_in_group("crash_site"):
		roots.append(n)
	var gpod: Node3D = Intro.build_pod()
	stage.add_child(gpod)
	roots.append(gpod)
	if GlimDirector.STUCK_NAME != "":
		wanted[String(GlimDirector.STUCK_NAME)] = "intro.gd (GlimDirector.STUCK_NAME)"
	var found: Array = []
	var not_found: Array = []
	for nm: String in wanted:
		var hit: bool = false
		for r: Node in roots:
			if r.find_child(nm, true, false) != null:
				hit = true
				break
		if hit:
			found.append(nm)
		else:
			not_found.append(nm)
	for subj: String in ["ark", "pod", "vault_pod", "lumi"]:
		if stage.get(subj) == null:
			bad.append("the space stage built no %s" % subj)
	stage.free()
	found.sort()
	not_found.sort()
	for b: String in bad:
		print("[artguard]   film: " + b)
	print("[artguard] film: %d shots, %d cues, %d yard anchors; %d node names looked up, found on the sets: %s; not found: %s" % [
		shots.size(), shots.reduce(func(acc: int, s: Dictionary) -> int: return acc + (s.get("cues", []) as Array).size(), 0), world_anchor_names.size(),
		wanted.size(), ", ".join(found), ", ".join(not_found) if not not_found.is_empty() else "-"])
	return {"shots": shots.size(), "bad": bad, "nodes_found": found, "nodes_not_found": not_found}


# ------------------------------------------------------------------------------------- views
## Rendered (`--art-guard-views=DIR`): four fixed views of the start area by day and three of them at
## dusk and at night, all from one load, each held a few seconds;
## prints `[artguard-view] NAME draw_calls= objects= prims= tex_mem= vmem=` and saves DIR/view_NAME.png.
static func run_views(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	var dir: String = DevHooks.get_s("art-guard-views", "screenshots/art_guard")
	if not dir.begins_with("/"):
		dir = ProjectSettings.globalize_path("res://" + dir)
	DirAccess.make_dir_recursive_absolute(dir)
	await DevHooks.wait_wall_for(3.0)  # wall clock: game time crawls on a software render
	while so.hub_frame == null or bool(so.w.get("building")):
		await tree.process_frame
	var p: SitePrefab = so.globe.site_manager.prefab(0)
	while p == null or not p.is_built:
		await tree.process_frame
		p = so.globe.site_manager.prefab(0)
	await DevHooks.wait_wall_for(DevHooks.get_f("art-guard-settle", 20.0))
	var frame := Transform3D(p.global_basis.orthonormalized(), p.global_position)
	var hud: Variant = so.w.get("hud")
	if hud is CanvasItem or hud is CanvasLayer:
		hud.set("visible", false)
	for cl: Node in tree.root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.name = "ArtGuardCam"
	cam.fov = 55.0
	cam.far = 4000.0
	so.w.add_child(cam)
	cam.make_current()
	var patch: Node3D = so.w.get("patch")
	var bench: Vector3 = p.anchor_local("bench").origin if p.anchor("bench") else Vector3(4, 0, 4)
	var lumi: Vector3 = frame.affine_inverse() * patch.global_position
	var lf: Vector3 = frame.basis.inverse() * (-patch.global_basis.z)
	lf.y = 0.0
	lf = lf.normalized() if lf.length() > 0.01 else Vector3(0, 0, -1)
	var views: Array = [
		["lumi", lumi + lf * 3.4 + Vector3(0, 1.3, 0), lumi + Vector3(0, 0.6, 0)],
		["yard", bench + Vector3(-6.0, 7.0, 16.0), bench + Vector3(0, 0.5, -2.0)],
		["town", Vector3(0, 55.0, 120.0), Vector3(0, 0, 10.0)],
		["street", Vector3(-30.0, 2.2, 40.0), Vector3(10.0, 1.6, 0.0)],
	]
	# One load for every light: by day (the new game's morning), at dusk and at night, set the way
	# --life-tour does (SkyDirector time_of_day / spin, frozen).
	var timed: Array = []
	for v: Array in views:
		timed.append([v[0], v[1], v[2], 0.32])
	for t: Array in [["dusk", 0.77], ["night", 0.95]]:
		for v: Array in views:
			if str(v[0]) in ["lumi", "yard", "town"]:
				timed.append([str(t[0]) + "_" + str(v[0]), v[1], v[2], t[1]])
	views = timed
	for v: Array in views:
		var eye: Vector3 = v[1]
		var at: Vector3 = v[2]
		eye.y += _ground_local(so, frame, eye) if str(v[0]) == "street" else 0.0
		cam.global_transform = frame * Transform3D(Basis.IDENTITY, eye)
		cam.look_at(frame * at, frame.basis.y)
		var sky: Variant = so.w.get("sky_director")
		if sky is SkyDirector:
			(sky as SkyDirector).time_of_day = float(v[3])
			(sky as SkyDirector).spin = SkyDirector.spin_for_local_time(float(v[3]), patch.global_position)
			(sky as SkyDirector).frozen = true
		await DevHooks.wait_wall_for(DevHooks.get_f("art-guard-view-wait", 6.0))
		for k: int in 4:
			await tree.process_frame
		var rs := RenderingServer
		print("[artguard-view] %s draw_calls=%d objects=%d prims=%d tex_mem=%d vmem=%d" % [v[0],
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)])
		var img: Image = so.w.get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("view_%s.png" % v[0]))
	print("[artguard-view] done")
	tree.quit(0)


# ------------------------------------------------------------------------------------- look
## The lighting, sky and water settings as numbers (read only): the environment, both suns, the
## sky shader and the lake shader's parameters. A change is news for the merge, not a fault.
static func look_settings(so: SliceOrbit) -> Dictionary:
	var out: Dictionary = {}
	var env: Environment = so.day.env if so.day else null
	if env:
		var e: Dictionary = {}
		for k: String in ["background_mode", "background_energy_multiplier", "ambient_light_source", "ambient_light_color", "ambient_light_energy",
				"ambient_light_sky_contribution", "reflected_light_source", "tonemap_mode", "tonemap_exposure", "tonemap_white", "glow_enabled",
				"glow_intensity", "glow_bloom", "fog_enabled", "fog_mode", "fog_light_color", "fog_light_energy", "fog_density", "fog_sky_affect",
				"fog_height", "fog_height_density", "volumetric_fog_enabled", "volumetric_fog_density", "ssao_enabled", "sdfgi_enabled",
				"adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation"]:
			e[k] = _num(env.get(k))
		out["env"] = e
	for nm: String in ["sun", "sun2"]:
		var l: Variant = so.day.get(nm) if so.day else null
		if l is DirectionalLight3D:
			var d := l as DirectionalLight3D
			out[nm] = {"color": d.light_color.to_html(), "energy": snappedf(d.light_energy, 0.001), "indirect": snappedf(d.light_indirect_energy, 0.001),
				"shadow": d.shadow_enabled, "visible": d.visible}
	out["sky"] = _shader_params(so.day.sky_mat if so.day else null)
	var water: Variant = so.sites.get("water") if so.sites else null
	out["water"] = _shader_params(water.get("_mat") if water else null)
	var keys: Array = out.keys()
	print("[artguard] look: environment %s, sky %d params, water %d params" % [
		"tonemap %s exposure %s fog %s" % [str(out.get("env", {}).get("tonemap_mode")), str(out.get("env", {}).get("tonemap_exposure")), str(out.get("env", {}).get("fog_enabled"))],
		(out["sky"] as Dictionary).size(), (out["water"] as Dictionary).size()])
	return out


static func _num(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.0001)
	if v is Color:
		return (v as Color).to_html()
	if v is Vector2 or v is Vector3 or v is Vector4:
		return str(v)
	if v is Object:
		return (v as Object).get_class()
	return v


static func _shader_params(m: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (m is ShaderMaterial) or (m as ShaderMaterial).shader == null:
		return out
	var sm := m as ShaderMaterial
	out["_shader"] = sm.shader.resource_path
	for u: Dictionary in sm.shader.get_shader_uniform_list():
		out[str(u["name"])] = _num(sm.get_shader_parameter(str(u["name"])))
	return out



## The planted invisible wall: a 3 m box collider on the first open ground round the pad (no visible
## geometry within a metre of its footprint).
static func _plant_wall(so: SliceOrbit, frame: Transform3D, vis: Dictionary, ground: Callable) -> void:
	for r: float in [12.0, 16.0, 20.0, 26.0, 32.0, 40.0]:
		for k: int in 24:
			var c := Vector2(cos(k * TAU / 24.0), sin(k * TAU / 24.0)) * r
			var clear: bool = true
			for cx: int in range(floori((c.x - 2.5) / CELL), floori((c.x + 2.5) / CELL) + 1):
				for cz: int in range(floori((c.y - 1.2) / CELL), floori((c.y + 1.2) / CELL) + 1):
					if vis.has(Vector2i(cx, cz)):
						clear = false
			if not clear:
				continue
			var g: float = ground.call(c.x, c.y)
			var sb := StaticBody3D.new()
			sb.name = "PlantedWall"
			sb.collision_layer = PhysLayers.PROP
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(3.0, 1.6, 0.4)
			cs.shape = bs
			sb.add_child(cs)
			so.globe.site_manager.prefab(0).add_child(sb)
			sb.global_transform = frame * Transform3D(Basis.IDENTITY, Vector3(c.x, g + 0.8, c.y))
			print("[artguard] planted: a 3 m box collider with nothing over it at site (%.1f, %.1f)" % [c.x, c.y])
			return
	print("[artguard] planted: no open ground found for the invisible wall")
