class_name GroundProbe
extends Node
## [v3qa] Dev QA: `--orbit --ground-probe[=FRAMES] [--ground-probe-r=M] [--ground-probe-quit]`.
## Owner item 41 (no glitches on Verdance). After the start area streams in, lists what looks
## wrong on the ground around Lumi:
##   - floating: a visible prop whose lowest corner is over GAP m above the terrain and that
##     nothing (another mesh's box or a collider) holds up;
##   - sunken: a visible prop wholly under the terrain;
##   - junk: live field pieces more than GAP m above or BURY m under the terrain.
## Lines: "[ground] float <group> n=<count> at hub0 (x, z) alt <m>", "[ground] sunk ...",
## "[ground] junk ...", then "[ground] RESULT float=F sunk=S junk=J". Positions are start-site
## local metres (x east, z south), so a repro is `--orbit-spawn=x,z`.

const GAP: float = 0.35
const BURY: float = 0.6
var so: Node  # SliceOrbit


static func attach(p_so: Node) -> GroundProbe:
	var y := GroundProbe.new()
	y.name = "GroundProbe"
	y.so = p_so
	p_so.add_child(y)
	return y


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for i: int in int(DevHooks.get_f("ground-probe", 240.0)):
		await get_tree().process_frame
	await get_tree().physics_frame
	for l: String in report():
		print(l)
	if DevHooks.has("ground-probe-quit"):
		get_tree().quit(0)


func report() -> PackedStringArray:
	var g: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var p: Node3D = w.get("patch")
	var centre: Vector3 = p.global_position if p else g.terrain.ground(g.grid.centers[g.start_cell()])
	var radius: float = DevHooks.get_f("ground-probe-r", 120.0)
	var inv: Transform3D = (g.sites[0]["transform"] as Transform3D).affine_inverse()
	var boxes: Array[AABB] = []
	var items: Array = []  # [name, corners(PackedVector3Array), owner id]
	for n: Node in w.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree() or not gi.is_inside_tree():
			continue
		if gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var la: AABB = mm.mesh.get_aabb()
			var cnt: int = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			for k: int in mini(cnt, 20000):
				var t: Transform3D = gi.global_transform * mm.get_instance_transform(k)
				if t.origin.distance_to(centre) > radius:
					continue
				if t.basis.get_scale().length() < 0.01:
					continue  # hidden instance (scaled to zero)
				_add(items, boxes, _group(gi) + "[mm]", t, la, gi)
		else:
			var a: AABB = gi.get_aabb()
			if a.size.length() < 0.05:
				continue
			if gi.global_position.distance_to(centre) > radius:
				continue
			_add(items, boxes, _group(gi), gi.global_transform, a, gi)
	var floats: Dictionary = {}
	var sunk: Dictionary = {}
	var space: PhysicsDirectSpaceState3D = (w as Node3D).get_world_3d().direct_space_state
	for it: Array in items:
		var cs: PackedVector3Array = it[1]
		var lo: float = INF
		var hi: float = -INF
		var lo_p: Vector3 = cs[0]
		for c: Vector3 in cs:
			var al: float = g.terrain.altitude(c)
			if al < lo:
				lo = al
				lo_p = c
			hi = maxf(hi, al)
		if hi < -0.05:
			_tally(sunk, it[0], inv * lo_p, hi, it[2])
			continue
		if lo <= GAP:
			continue
		var up: Vector3 = lo_p.normalized()
		var below: Vector3 = lo_p - up * 0.12
		var held: bool = false
		for bi: int in boxes.size():
			if boxes[bi].grow(0.02).has_point(below) and bi != int(it[3]):
				held = true
				break
		if not held:
			var q := PhysicsRayQueryParameters3D.create(lo_p + up * 0.05, lo_p - up * (lo + 0.2))
			var hit: Dictionary = space.intersect_ray(q)
			if not hit.is_empty() and g.terrain.altitude(hit["position"]) > 0.1:
				held = true
		if not held:
			_tally(floats, it[0], inv * lo_p, lo, it[2])
	var out: PackedStringArray = []
	for k: String in _sorted(floats):
		var e: Array = floats[k]
		out.append("[ground] float %s n=%d at hub0 (%.1f, %.1f) alt %.2f m (%s)" % [k, e[0], e[1].x, e[1].z, e[2], e[3]])
	for k: String in _sorted(sunk):
		var e: Array = sunk[k]
		out.append("[ground] sunk %s n=%d at hub0 (%.1f, %.1f) top %.2f m (%s)" % [k, e[0], e[1].x, e[1].z, e[2], e[3]])
	var f: SphereField = g.field
	var jn: int = 0
	var worst: float = 0.0
	var worst_p := Vector3.ZERO
	for pid: int in f.piece_pos.size():
		if f.piece_alive[pid] == 0 or f.piece_pos[pid].distance_to(centre) > radius:
			continue
		var al2: float = g.terrain.altitude(f.piece_pos[pid]) - (f.piece_lift[pid] if pid < f.piece_lift.size() else 0.0)  # lift: origin over the ground
		if al2 > GAP + 0.6 or al2 < -BURY:
			var hc: int = f.piece_hex[pid]
			if f.is_water(hc):
				continue  # floating on a lake
			var near_lm: bool = false
			for lm: Dictionary in f.landmarks:
				if (lm["pos"] as Vector3).distance_to(f.piece_pos[pid]) < 6.0:
					near_lm = true
					break
			if near_lm:
				continue  # on a heap or wreck
			jn += 1
			if absf(al2) > absf(worst):
				worst = al2
				worst_p = inv * f.piece_pos[pid]
	if jn > 0:
		out.append("[ground] junk pieces off the ground n=%d worst %.2f m at hub0 (%.1f, %.1f)" % [jn, worst, worst_p.x, worst_p.z])
	out.append("[ground] RESULT float=%d sunk=%d junk=%d (items %d within %.0f m)" % [floats.size(), sunk.size(), jn, items.size(), radius])
	return out


func _add(items: Array, boxes: Array[AABB], name: String, t: Transform3D, a: AABB, gi: Node) -> void:
	var cs := PackedVector3Array()
	for i: int in 8:
		cs.append(t * a.get_endpoint(i))
	var wa := AABB(cs[0], Vector3.ZERO)
	for c: Vector3 in cs:
		wa = wa.expand(c)
	items.append([name, cs, "%s size %s" % [gi.name, (wa.size * 10.0).round() / 10.0], boxes.size()])
	# Big boxes (ground chunks, merged batches) hold everything up; they don't count as support.
	boxes.append(wa if wa.size.x < 20.0 and wa.size.y < 20.0 and wa.size.z < 20.0 else AABB())


## A node path without instance numbers, so a row of the same prop is one line.
static func _group(n: Node) -> String:
	var parts: PackedStringArray = []
	var cur: Node = n
	for i: int in 4:
		if cur == null or cur.name == "Slice":
			break
		var s: String = String(cur.name)
		var rx := RegEx.create_from_string("[0-9@]+")
		parts.insert(0, rx.sub(s, "#", true))
		cur = cur.get_parent()
	return "/".join(parts)


static func _tally(d: Dictionary, k: String, lp: Vector3, v: float, what: String) -> void:
	var e: Array = d.get(k, [0, lp, v, what])
	e[0] = int(e[0]) + 1
	d[k] = e


static func _sorted(d: Dictionary) -> Array:
	var ks: Array = d.keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return int(d[a][0]) > int(d[b][0]))
	return ks

