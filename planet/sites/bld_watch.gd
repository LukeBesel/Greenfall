class_name BldWatch
extends Node
## [v8bld] Dev: what changes on the town's buildings while Lumi walks and stands (owner: "building
## was glitching a bit then stopped"). `--bld-watch[=seconds]` on an orbit run:
##   - walks Lumi (a scripted 5 m/s walk, no input) from the yard to the nearest lake shore
##     (`--bld-walk-to=x,z` site metres instead), turns him to face the town and stands;
##   - every frame, for every GeometryInstance3D and Light3D under the hub sites (the town, its
##     outskirts, kits, lots) and every big one anywhere within 300 m: added / removed, shown /
##     hidden, mesh swapped, and its visibility range state as the renderer works it out (distance
##     from the camera to the instance's AABB centre, margins as hysteresis when the fade is off);
##   - the `site_inv` global (the frame the city shader's maths run in) and the building material's
##     life_on / life_tex (TownLife);
##   - an in-play BuildBudget (something still building) and its last label.
## `[bldw]` lines: every event while it happens (capped), then a summary: events per node per
## minute, flips, how long anything built in play. `--bld-watch-quit` quits at the end, exit 1 if a
## node flips more than FLIP_MAX times in the window or anything near was still building after
## BUILD_MAX_S of play.

const WALK_MPS: float = 5.0
const FLIP_MAX: int = 2
const BUILD_MAX_S: float = 5.0
const BIG_M: float = 6.0
const NEAR_M: float = 300.0
const LOG_CAP: int = 200

var so: SliceOrbit
var _t: float = 0.0
var _dur: float = 90.0
var _path: Array[Vector3] = []  # world points
var _seg: int = 0
var _cur := Vector3.ZERO
var _face: Vector3 = Vector3.ZERO
var _standing_t: float = -1.0
var _watch: Dictionary = {}  # instance id -> {node, vis, range, mesh, flips, events, name}
var _events: Array = []
var _logged: int = 0
var _site_inv := Projection()
var _life_tex_id: int = 0
var _life_on: float = -1.0
var _building_t: float = 0.0
var _building_at: String = ""
var _build_spans: Array = []
var _span_from: float = -1.0
var _added: int = 0
var _removed: int = 0
var _done: bool = false


func setup(p_so: SliceOrbit) -> void:
	so = p_so
	name = "BldWatch"
	_dur = DevHooks.get_f("bld-watch", 90.0)
	if _dur < 5.0:
		_dur = 90.0


func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	get_tree().node_removed.connect(_on_removed)
	_plan.call_deferred()


func _lumi() -> Patch:
	return so.w.get("patch")


func _plan() -> void:
	var g: OrbitPlanet = so.globe
	var lumi: Patch = _lumi()
	var hub_xf: Transform3D = g.sites[0]["transform"]
	var dest: Vector3
	if DevHooks.has("bld-walk-to"):
		var p: PackedStringArray = DevHooks.get_s("bld-walk-to", "0,-120").split(",")
		dest = g.terrain.ground((hub_xf * Vector3(float(p[0]), 0.0, float(p[1]))).normalized())
	else:
		dest = _lake_shore()
	var a: Vector3 = lumi.global_position
	var n: int = maxi(2, int(a.distance_to(dest) / 4.0))
	for i: int in range(1, n + 1):
		var d: Vector3 = a.normalized().slerp(dest.normalized(), float(i) / n)
		_path.append(g.terrain.ground(d))
	_face = hub_xf.origin
	_scan_all()
	if DevHooks.has("bld-zfight"):
		zfight_report(_sites_root())
	var dl: Vector3 = hub_xf.affine_inverse() * dest
	print("[bldw] walk %.0f m from (%.0f, %.0f) to site (%.0f, %.0f), then stand %.0f s looking at the town" % [
		a.distance_to(dest), (hub_xf.affine_inverse() * a).x, (hub_xf.affine_inverse() * a).z, dl.x, dl.z, _dur])


## [v8bld] --bld-zfight: CoplanarAudit over every city building mesh of the built sites (the
## town's merged bodies and detail meshes, the outskirts tiles). Returns the pairs found.
static func zfight_report(root: Node) -> int:
	var total: int = 0
	var area: float = 0.0
	var meshes: int = 0
	var worst: Array = []
	var city_mats: Array = [BuildingDetail.material(), TownOutskirts.material()]
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		for sf: int in mi.mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(sf)
			if not (mat in city_mats):
				continue
			var r: Dictionary = CoplanarAudit.audit(CoplanarAudit.tris_of(mi.mesh, sf), Transform3D.IDENTITY, CoplanarAudit.cols_of(mi.mesh, sf))
			meshes += 1
			total += int(r["pairs"])
			area += float(r["area"])
			for w: Array in r["worst"]:
				worst.append([w[0], mi.global_transform * (w[1] as Vector3), str(mi.get_path()).get_slice("/", str(mi.get_path()).get_slice_count("/") - 2) + "/" + mi.name, "kinds %s axis %d%+d, mesh-local %s" % [w[4], w[2], w[3], str(w[1])]])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("[bldw] z-fight audit: %d city building meshes, %d coplanar overlapping face pairs, %.1f m2" % [meshes, total, area])
	for w: Array in worst.slice(0, 6):
		print("[bldw]   %.2f m2 on %s (%s)" % [w[0], w[2], w[3]])
	return total


func _lake_shore() -> Vector3:
	var g: OrbitPlanet = so.globe
	var from: Vector3 = g.grid.centers[g.start_cell()].normalized()
	var best_land: int = -1
	var bd: float = INF
	for c: int in g.grid.cells_within(from, 600.0):
		if g.cells.state[c] != 5 or g.cells.has_flag(c, SphereCells.F_SITE) or g.grid.centers[c].angle_to(from) * g.terrain.R < 60.0:
			continue
		for o: int in g.grid.neighbors(c):
			if g.cells.state[o] == 5 or g.cells.has_flag(o, SphereCells.F_SITE):
				continue
			var d: float = g.grid.centers[o].angle_to(from)
			if d < bd:
				bd = d
				best_land = o
	if best_land < 0:
		return g.terrain.ground(from)
	return g.terrain.ground(g.grid.centers[best_land].normalized())


func _sites_root() -> Node:
	return so.globe.site_manager


func _under_sites(n: Node) -> bool:
	var r: Node = _sites_root()
	return r != null and r.is_ancestor_of(n)


func _interesting(n: Node) -> bool:
	if not (n is GeometryInstance3D or n is Light3D):
		return false
	if _under_sites(n):
		return true
	if n is GeometryInstance3D and (n as Node3D).is_inside_tree():
		var gi: GeometryInstance3D = n
		var bb: AABB = gi.get_aabb()
		if bb.size.length() < BIG_M:
			return false
		var lumi: Patch = _lumi()
		return lumi != null and (gi.global_transform * bb.get_center()).distance_to(lumi.global_position) < NEAR_M
	return false


func _scan_all() -> void:
	var r: Node = _sites_root()
	if r == null:
		print("[bldw] no site manager")
		return
	for n: Node in r.find_children("*", "Node3D", true, false):
		if n is GeometryInstance3D or n is Light3D:
			_track(n)
	print("[bldw] watching %d nodes under the sites" % _watch.size())


func _track(n: Node3D) -> void:
	var id: int = n.get_instance_id()
	if _watch.has(id):
		return
	_watch[id] = {"node": n, "vis": n.is_visible_in_tree(), "range": _range_state(n, -2), "mesh": _mesh_id(n),
		"flips": 0, "events": 0, "name": _short(n)}


func _short(n: Node) -> String:
	var p: String = str(n.get_path())
	var parts: PackedStringArray = p.split("/")
	return "/".join(parts.slice(maxi(0, parts.size() - 3)))


func _mesh_id(n: Node) -> int:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return (n as MeshInstance3D).mesh.get_instance_id()
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		return mm.get_instance_id() * 31 + mm.visible_instance_count
	return 0


## The renderer's visibility range check (RendererSceneCull::_visibility_range_check): distance from
## the camera to the instance's world AABB centre; with the fade off, the margins are hysteresis.
## 0 in range, 1 nearer than begin, -1 past end. prev -2: no previous state.
func _range_state(n: Node3D, prev: int) -> int:
	if not (n is GeometryInstance3D):
		return 0
	var gi: GeometryInstance3D = n
	if gi.visibility_range_end <= 0.0 and gi.visibility_range_begin <= 0.0:
		return 0
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return prev
	var c: Vector3 = gi.global_transform * gi.get_aabb().get_center()
	var d: float = cam.global_position.distance_to(c)
	var bo: float = -gi.visibility_range_begin_margin
	var eo: float = gi.visibility_range_end_margin
	if gi.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and prev != 0:
		bo = -bo
		eo = -eo
	if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + eo:
		return -1
	if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin + bo:
		return 1
	return 0


func _event(what: String, n: String, id: int = 0) -> void:
	if _t < 1.0 or not is_inside_tree():
		return  # the start yard's own first-frame merges
	_events.append([_t, what, n])
	if id != 0 and _watch.has(id):
		_watch[id]["events"] = int(_watch[id]["events"]) + 1
	if _logged < LOG_CAP:
		_logged += 1
		var lumi: Patch = _lumi()
		var cam: Camera3D = get_viewport().get_camera_3d()
		var dn: String = ""
		if id != 0 and _watch.has(id) and is_instance_valid(_watch[id]["node"]) and cam:
			var gi: Node3D = _watch[id]["node"]
			var c: Vector3 = gi.global_position
			if gi is GeometryInstance3D:
				c = gi.global_transform * (gi as GeometryInstance3D).get_aabb().get_center()
			dn = " (%.0f m from the camera)" % cam.global_position.distance_to(c)
		print("[bldw] t=%.2f %s %s%s%s" % [_t, what, n, dn, " standing" if _standing_t >= 0.0 else ""])
		if lumi == null:
			return


## [v8bld] Materials that first show up in play (the warm-up never drew them): on Metal / Vulkan
## each new shader (and vertex-format variant) is compiled the first time it is seen.
var _mats_seen: Dictionary = {}  # shader key -> true
var _new_mats: Array = []  # [t, key, node]
var _mats_ready: bool = false


static func mat_key(m: Material) -> String:
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		return "shader:" + (sh.resource_path if sh and sh.resource_path != "" else str(sh.get_instance_id() if sh else 0))
	if m is BaseMaterial3D:
		var b: BaseMaterial3D = m
		# The features that pick BaseMaterial3D's generated shader (close enough to count variants).
		var k: PackedStringArray = [str(b.transparency), str(b.shading_mode), str(b.cull_mode), str(b.vertex_color_use_as_albedo),
			str(b.billboard_mode), str(b.no_depth_test), str(b.emission_enabled), str(b.normal_enabled), str(b.roughness_texture != null),
			str(b.metallic_texture != null), str(b.albedo_texture != null), str(b.uv1_triplanar), str(b.depth_draw_mode), str(b.blend_mode),
			str(b.ao_enabled), str(b.rim_enabled), str(b.proximity_fade_enabled), str(b.distance_fade_mode), str(b.texture_filter),
			str(b.diffuse_mode), str(b.specular_mode), str(b.disable_receive_shadows), str(b.use_point_size), str(b.grow)]
		return "base:" + ",".join(k)
	return m.get_class()


func _note_mats(n: Node, at_start: bool) -> void:
	if not (n is GeometryInstance3D):
		return
	for m: Material in ShaderWarmup._materials_of(n):
		if not ShaderWarmup._spatial(m):
			continue
		var k: String = mat_key(m)
		if _mats_seen.has(k):
			continue
		_mats_seen[k] = true
		if not at_start:
			_new_mats.append([_t, k, _short(n)])
			_event("new shader in view: %s" % k.left(60), _short(n))


func _on_added(n: Node) -> void:
	if _done or so == null or not (n is Node3D):
		return
	if _mats_ready:
		_note_mats(n, false)
	if not _interesting(n):
		return
	_added += 1
	_track(n)
	if _t > 1.0:
		_event("added", _short(n), n.get_instance_id())


func _on_removed(n: Node) -> void:
	if _done:
		return
	var id: int = n.get_instance_id()
	if not _watch.has(id):
		return
	_removed += 1
	_event("removed", str(_watch[id]["name"]), id)
	_watch.erase(id)


func _physics_process(delta: float) -> void:
	if _done or so == null or _path.is_empty():
		return
	var lumi: Patch = _lumi()
	if _seg < _path.size():
		# A scripted walk on its own cursor (through walls: the view matters, not the route).
		if _cur == Vector3.ZERO:
			_cur = lumi.global_position
		var tgt: Vector3 = _path[_seg]
		var step: float = WALK_MPS * delta
		var to: Vector3 = tgt - _cur
		var fwd: Vector3 = to.normalized() if to.length() > 0.01 else lumi.forward()
		if to.length() <= step:
			_seg += 1
			_cur = tgt
		else:
			_cur = so.globe.terrain.ground((_cur + fwd * step).normalized())
		var up1: Vector3 = _cur.normalized()
		lumi.place_on_sphere(_cur, (fwd - up1 * fwd.dot(up1)).normalized())
		if _seg >= _path.size():
			var up: Vector3 = lumi.global_position.normalized()
			var f: Vector3 = _face - lumi.global_position
			f = (f - up * f.dot(up)).normalized()
			lumi.place_on_sphere(lumi.global_position, f)
			so.cam.reset_frame(f)
			_standing_t = 0.0
			print("[bldw] t=%.1f standing at the shore, facing the town" % _t)


func _process(delta: float) -> void:
	if _done or so == null or _path.is_empty():
		return
	_t += delta
	if not _mats_ready and _t >= 1.0:
		_mats_ready = true
		for gi: Node in get_tree().current_scene.find_children("*", "GeometryInstance3D", true, false):
			_note_mats(gi, true)
		print("[bldw] %d shader keys in the scene at the start (what the warm-up drew)" % _mats_seen.size())
	if int(_t / 10.0) != int((_t - delta) / 10.0):
		var hx: Transform3D = so.globe.sites[0]["transform"]
		var lp: Vector3 = hx.affine_inverse() * _lumi().global_position
		print("[bldw] t=%.0f Lumi at site (%.0f, %.0f), path %d/%d" % [_t, lp.x, lp.z, _seg, _path.size()])
	if _standing_t >= 0.0:
		_standing_t += delta
	# Building in play.
	if BuildBudget.current != null:
		_building_t += delta
		_building_at = BuildBudget.last_at
		if _span_from < 0.0:
			_span_from = _t
			_event("build starts", BuildBudget.last_at)
	elif _span_from >= 0.0:
		_build_spans.append([_span_from, _t, _building_at])
		_event("build ends (%.1f s)" % (_t - _span_from), _building_at)
		_span_from = -1.0
	# Shader state.
	var si: Variant = RenderingServer.global_shader_parameter_get("site_inv")
	if si is Projection and si != _site_inv:
		if _t > 0.5:
			_event("site_inv changed", "global")
		_site_inv = si
	var m: ShaderMaterial = BuildingDetail.material()
	var lt: Variant = m.get_shader_parameter("life_tex")
	var lt_id: int = (lt as Object).get_instance_id() if lt is Object else 0
	var lo: float = float(m.get_shader_parameter("life_on")) if m.get_shader_parameter("life_on") != null else 0.0
	if lt_id != _life_tex_id or lo != _life_on:
		if _t > 0.5:
			_event("building material life_tex/life_on changed (on=%.0f)" % lo, "BuildingDetail.material")
		_life_tex_id = lt_id
		_life_on = lo
	# Per node.
	for id: int in _watch.keys():
		var w: Dictionary = _watch[id]
		var n: Node3D = w["node"]
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var v: bool = n.is_visible_in_tree()
		if v != bool(w["vis"]):
			w["vis"] = v
			w["flips"] = int(w["flips"]) + 1
			_event("shown" if v else "hidden", str(w["name"]), id)
		var r: int = _range_state(n, int(w["range"]))
		if r != int(w["range"]):
			w["range"] = r
			w["flips"] = int(w["flips"]) + 1
			_event("range " + ["past end", "in range", "nearer than begin"][r + 1], str(w["name"]), id)
		var mid: int = _mesh_id(n)
		if mid != int(w["mesh"]):
			w["mesh"] = mid
			w["flips"] = int(w["flips"]) + 1
			_event("mesh swapped", str(w["name"]), id)
	if DevHooks.has("bld-look") and _standing_t >= 2.0:
		# [v8bld] --bld-look: the player looks round while standing (a full turn every 12 s): the
		# camera swings round Lumi on its arm, so the distance to everything changes by a few metres.
		var up: Vector3 = _lumi().global_position.normalized()
		var f0: Vector3 = _face - _lumi().global_position
		f0 = (f0 - up * f0.dot(up)).normalized()
		so.cam.frame = SphereMath.basis_from_up_fwd(up, f0.rotated(up, (_standing_t - 2.0) * TAU / 12.0))
	if DevHooks.has("bld-burst") and DisplayServer.get_name() != "headless":
		_burst()
	if DevHooks.has("bld-progress") and _standing_t >= 0.0:
		_progress()
	if _standing_t >= _dur:
		_finish()


## [v8bld] --bld-burst=DIR (rendered runs): every frame of the last 3 s of the walk and the first
## 6 s standing, saved as DIR/fNNN_{w|s}.png, for frame-to-frame diffs of the town (pops, flicker).
var _burst_n: int = 0


func _burst() -> void:
	var walk_left: float = INF
	if _standing_t < 0.0:
		walk_left = float(_path.size() - _seg) * 4.0 / WALK_MPS
	var on: bool = walk_left < 3.0 or (_standing_t >= 0.0 and _standing_t < 6.0)
	if not on or _burst_n >= 120:
		return
	var dir: String = DevHooks.get_s("bld-burst", "screenshots/bld")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + dir))
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://%s/f%03d_%s_%.2f.png" % [dir, _burst_n, "w" if _standing_t < 0.0 else "s", _t]))
	_burst_n += 1


## [v8bld] --bld-progress: what 20-40 minutes of play change round Lumi while he stands looking at
## the town: the hub levels up (10 s in), robots clean every cell within 200 m (from 15 s, 40 cells
## a second) so the blocks wake up (TownLife), and the evening comes (dusk: windows, lamps).
var _prog_stage: int = 0
var _to_clean: PackedInt32Array = PackedInt32Array()
var _clean_acc: float = 0.0
var _life_moving_frames: int = 0


func _progress() -> void:
	var g: OrbitPlanet = so.globe
	var sm: SiteManager = g.site_manager
	if _prog_stage == 0 and _standing_t >= 10.0:
		_prog_stage = 1
		sm.set_level(0, 3)
		print("[bldw] t=%.1f progress: hub 0 to level 3" % _t)
		var tl: Node = null
		for ch: Node in (sm.prefab(0) as SitePrefab).content.get_children():
			if ch is VerdanceSite:
				tl = ch.get_node_or_null("TownLife")
		if tl and tl.has_signal("stage_changed"):
			tl.stage_changed.connect(func(key: Vector2i, st: int) -> void: _event("town block %s wakes to stage %d" % [str(key), st], "TownLife"))
	if _prog_stage == 1 and _standing_t >= 15.0:
		_prog_stage = 2
		for c: int in g.grid.cells_within(_lumi().global_position.normalized(), 200.0):
			if g.cells.is_dirty(c):
				_to_clean.append(c)
		print("[bldw] t=%.1f progress: cleaning %d cells round Lumi" % [_t, _to_clean.size()])
	if _prog_stage == 2:
		_clean_acc += get_process_delta_time() * 40.0
		var did: bool = false
		while _clean_acc >= 1.0 and not _to_clean.is_empty():
			_clean_acc -= 1.0
			var c: int = _to_clean[_to_clean.size() - 1]
			_to_clean.resize(_to_clean.size() - 1)
			g.cells.set_junk(c, 0.0)
			did = true
		if did:
			g.cells.flush()
	var vs2: VerdanceSite = null
	if sm.prefab(0) and (sm.prefab(0) as SitePrefab).content:
		for ch: Node in (sm.prefab(0) as SitePrefab).content.get_children():
			if ch is VerdanceSite:
				vs2 = ch
	var tl2: Node = vs2.get_node_or_null("TownLife") if vs2 else null
	if tl2 and bool(tl2.get("_moving")):
		_life_moving_frames += 1


func _finish() -> void:
	_done = true
	var walk_s: float = _t - _standing_t
	var walk_ev: int = 0
	var stand_ev: int = 0
	var by_kind: Dictionary = {}
	for e: Array in _events:
		if float(e[0]) < walk_s:
			walk_ev += 1
		else:
			stand_ev += 1
		var k: String = str(e[1]).split(" (")[0]
		by_kind[k] = int(by_kind.get(k, 0)) + 1
	var worst: Array = []
	for id: int in _watch:
		if int(_watch[id]["flips"]) > 0:
			worst.append([int(_watch[id]["flips"]), str(_watch[id]["name"])])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("[bldw] summary: %.0f s walking (%d events), %.0f s standing (%d events); %d nodes watched, %d added, %d removed" % [
		walk_s, walk_ev, _standing_t, stand_ev, _watch.size(), _added, _removed])
	print("[bldw] by kind: %s" % JSON.stringify(by_kind))
	print("[bldw] %d new shader keys appeared in play" % _new_mats.size())
	for e: Array in _new_mats:
		print("[bldw]   t=%.1f %s on %s" % [e[0], e[1], e[2]])
	if DevHooks.has("bld-progress"):
		print("[bldw] town life easing on %d frames (%.1f s at 60 fps)" % [_life_moving_frames, _life_moving_frames / 60.0])
	for i: int in mini(10, worst.size()):
		print("[bldw] flips %d (%.1f/min): %s" % [worst[i][0], float(worst[i][0]) / maxf(_t / 60.0, 0.01), worst[i][1]])
	var built_late: float = 0.0
	for s: Array in _build_spans:
		print("[bldw] built in play %.1f..%.1f s (%.1f s), last at %s" % [s[0], s[1], float(s[1]) - float(s[0]), s[2]])
		built_late = maxf(built_late, float(s[1]) - float(s[0]))
	if _span_from >= 0.0:
		print("[bldw] still building at the end since %.1f s (%s)" % [_span_from, _building_at])
		built_late = maxf(built_late, _t - _span_from)
	var max_flips: int = int(worst[0][0]) if not worst.is_empty() else 0
	var ok: bool = max_flips <= FLIP_MAX and built_late <= BUILD_MAX_S
	print("[bldw] %s: most flips on one node %d (max %d), longest in-play build %.1f s (max %.0f)" % [
		"PASS" if ok else "FAIL", max_flips, FLIP_MAX, built_late, BUILD_MAX_S])
	if DevHooks.has("bld-watch-quit"):
		get_tree().quit(0 if ok else 1)
