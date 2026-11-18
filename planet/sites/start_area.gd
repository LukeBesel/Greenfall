class_name StartArea
extends RefCounted
## [v8hex] The start area round base 1 (the Landing Yard): data/start_area.json.
## Owner item (Nov 13): "get rid of large items around base 1 like that large barrel".
##   radius_m         the start area: hex cells whose centre lies this close to the start pad hold
##                    only junk Lumi lifts at Lift Strength 0 (SphereField.small_only); no wreck
##                    landmark, junk mound or junk-looking prop stands in it (big_things checks)
##   leftover_from    the leftover rule (SphereField.leftover_from)
##   heal_from        a loaded save's start-area hex this far cleared but not clean heals once
##   greenhouse_half  the First Seed greenhouse's ground kept clear of junk (x, z half, m)
##   junk_look        words in the node names of props that look like junk Lumi could take

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = Economy.read_json("res://data/start_area.json")
		_cfg = d if d is Dictionary and not (d as Dictionary).is_empty() else {"radius_m": 40.0}
	return _cfg


static func radius_m() -> float:
	return float(cfg().get("radius_m", 40.0))


## [v9c] The small-junk rule's radius round the other hubs' pads (0 = off).
static func station_radius_m() -> float:
	return float(cfg().get("station_radius_m", 0.0))


static func leftover_from() -> float:
	return float(cfg().get("leftover_from", 0.8))


static func heal_from() -> float:
	return float(cfg().get("heal_from", 0.9))


static func greenhouse_half() -> Vector2:
	var a: Array = cfg().get("greenhouse_half", [3.7, 5.2])
	return Vector2(float(a[0]), float(a[1]))


## Whether a site-local point of the start site (x, z m from the yard centre) lies in the start area.
static func inside_local(x: float, z: float, grow: float = 0.0) -> bool:
	var r: float = radius_m() + grow
	return x * x + z * z < r * r


## Big things in the start area, one line each ("<what> at (x, z) d=Dm"): live field pieces over
## Lift Strength 0, wreck landmarks, and visible props whose name says junk
## ("junk_look": drums, barrels, wrecks...) that Lumi can't take.
static func big_things(g: OrbitPlanet, w: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var f: SphereField = g.field
	var inv: Transform3D = (g.sites[0]["transform"] as Transform3D).affine_inverse()
	for pid: int in f.piece_pos.size():
		if f.piece_alive[pid] == 0 or int(f.piece_size[pid]) <= Pace.SIZE_SMALL:
			continue
		var lp: Vector3 = inv * f.piece_pos[pid]
		if inside_local(lp.x, lp.z) and f.small_only.has(f.piece_hex[pid]):
			out.append("piece %s (vol %.1f) at (%.1f, %.1f) d=%.0fm" % [f.piece_model[pid], f.piece_model_vol[pid], lp.x, lp.z, Vector2(lp.x, lp.z).length()])
	for lm: Dictionary in f.landmarks:
		if lm.get("gone", false):
			continue
		var lp2: Vector3 = inv * (lm["pos"] as Vector3)
		if inside_local(lp2.x, lp2.z):
			out.append("landmark %s at (%.1f, %.1f) d=%.0fm" % [lm["model"], lp2.x, lp2.z, Vector2(lp2.x, lp2.z).length()])
	var sp: SitePrefab = g.site_manager.prefab(0) if g.site_manager else null
	if sp and sp.content:
		for ch: Node in sp.content.get_children():
			for e2: Variant in ch.get("lot_junk") if ch.get("lot_junk") is Array else []:
				var q: Vector2 = (e2 as Array)[0]
				if inside_local(q.x, q.y, 9.0):
					out.append("lot props (%s) at (%.1f, %.1f) d=%.0fm" % [(e2 as Array)[1], q.x, q.y, q.length()])
	if w:
		for e: Array in junk_props(g, w):
			out.append("prop %s at (%.1f, %.1f) d=%.0fm size %.1f m" % [e[0], e[1].x, e[1].z, Vector2(e[1].x, e[1].z).length(), e[2]])
	return out


## Visible props in the start area whose node path matches a "junk_look" word: [[name, site-local
## pos, size m]], a multimesh per instance. With --hex-audit-props every visible mesh over 0.6 m.
static func junk_props(g: OrbitPlanet, w: Node) -> Array:
	var words: Array = cfg().get("junk_look", [])
	var dump: bool = DevHooks.has("hex-audit-props")
	var inv: Transform3D = (g.sites[0]["transform"] as Transform3D).affine_inverse()
	var out: Array = []
	for n: Node in w.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var nm: String = _path(gi)
		var hit: bool = dump
		for wd: Variant in words:
			if nm.to_lower().contains(str(wd).to_lower()):
				hit = true
				break
		if not hit:
			continue
		if gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var la: AABB = mm.mesh.get_aabb()
			var cnt: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for k: int in mini(cnt, 50000):
				var t: Transform3D = gi.global_transform * mm.get_instance_transform(k)
				if t.basis.get_scale().length() < 0.01:
					continue
				var lp: Vector3 = inv * t.origin
				var sz: float = (t.basis * la.size).length() * 0.577
				if inside_local(lp.x, lp.z) and sz > (0.3 if dump else 0.6) and lp.length() > 0.01:
					out.append([nm + "[mm]", lp, sz])
		else:
			var a: AABB = gi.get_aabb()
			var lp2: Vector3 = inv * (gi.global_transform * a.get_center())
			var sz2: float = (gi.global_basis * a.size).length() * 0.577
			if inside_local(lp2.x, lp2.z) and sz2 > (0.3 if dump else 0.6) and sz2 < 30.0:
				out.append([nm, lp2, sz2])
	return out


static func _path(n: Node) -> String:
	var parts: PackedStringArray = []
	var p: Node = n
	while p and parts.size() < 4:
		parts.insert(0, str(p.name))
		p = p.get_parent()
	return "/".join(parts)
