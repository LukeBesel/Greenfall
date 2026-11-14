class_name YardProbe
extends Node
## [v1yard] Dev: `--orbit --yard-probe`. How close the junk starts to the start yard's pad and
## the pod, and what stands in the yard. Prints, after the start site settles:
##   [yardprobe] band A-B m: cells n (dirty d, hub h)  pieces p   (site-local distance from the yard centre)
##   [yardprobe] nearest piece: from spawn X m, from pod Y m, from the pad edge Z m
##   [yardprobe] pieces on the pad: N (inside PAD_HALF_M)
## Then the yard's objects (vehicle, buddy) and quits when --yard-probe-quit is given.

const PAD_HALF_M: float = 10.5
var so: Node  # SliceOrbit


static func attach(p_so: Node) -> YardProbe:
	var y := YardProbe.new()
	y.name = "YardProbe"
	y.so = p_so
	p_so.add_child(y)
	return y


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for i: int in int(DevHooks.get_f("yard-probe", 90.0)):
		await get_tree().process_frame
	print(report())
	var clr: Array[String] = e_clearance(so)
	print("\n".join(clr))
	if DevHooks.has("yard-probe-quit"):
		get_tree().quit(1 if clr.any(func(l: String) -> bool: return l.contains("FAIL")) else 0)


## [v9a] Goal audit: a new player's first E at the bench dug up a part that lay by it. Every
## buried part near the start yard keeps YardKeepOut.PART_CLEAR_M from each yard E spot (bench,
## bin, scale, pod, rocket, the build anchors), and the yard's own E spots keep Camp's min gap.
## Lines "[yardprobe] FAIL ..." for each one too close; one summary line.
static func e_clearance(p_so: Node) -> Array[String]:
	var out: Array[String] = []
	var g: OrbitPlanet = p_so.get("globe")
	var ko: YardKeepOut = g.yard_keep_out() if g else null
	if ko == null:
		return out
	var f: SphereField = g.field
	var c0: int = g.start_cell()
	for c: int in g.grid.cells_within(g.grid.centers[c0], 40.0, c0):
		f.materialize(c)  # its parts roll as it is laid
	var n: int = 0
	var worst: float = INF
	for i: int in f.part_pos.size():
		var q: Vector2 = ko.local(f.part_pos[i].normalized())
		if q.length() > 30.0:
			continue
		n += 1
		for e: Vector2 in ko.e_points:
			var d: float = q.distance_to(e)
			worst = minf(worst, d)
			if d < YardKeepOut.PART_CLEAR_M - 0.05:
				out.append("[yardprobe] FAIL buried part %d at yard (%.1f, %.1f) is %.1f m from the E spot at (%.1f, %.1f) (keep %.1f m)" % [i, q.x, q.y, d, e.x, e.y, YardKeepOut.PART_CLEAR_M])
	var w: Node = p_so.get("w")
	var camp: Camp = w.get("camp") as Camp if w else null
	if camp:  # (Camp.too_close compares world x/z: a flat-world measure, wrong on the globe)
		var gap: float = float(Camp.cfg().get("min_gap", 3.0))
		var pts: Array = camp.points()
		for i: int in pts.size():
			for j: int in range(i + 1, pts.size()):
				var d2: float = OrbitUp.ground_dist(pts[i][1], pts[j][1])
				if d2 < gap:
					out.append("[yardprobe] FAIL yard E spots too close: %s-%s %.1f m (keep %.1f m)" % [pts[i][0], pts[j][0], d2, gap])
	out.append("[yardprobe] E clearance: %d buried parts within 30 m of the yard, nearest %.1f m from an E spot (keep %.1f m)" % [n, worst, YardKeepOut.PART_CLEAR_M])
	return out


func report() -> String:
	var g: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var sm: SiteManager = g.site_manager
	var sp: SitePrefab = sm.prefab(0)
	var inv: Transform3D = (g.sites[0]["transform"] as Transform3D).affine_inverse()
	var lines: PackedStringArray = []
	var bands: Dictionary = {}
	var f: SphereField = g.field
	for c: int in g.grid.cells_within(g.grid.centers[g.start_cell()], 50.0, g.start_cell()):
		var lp: Vector3 = inv * g.terrain.ground(g.grid.centers[c])
		var b: int = int(Vector2(lp.x, lp.z).length() / 4.0)
		var e: Array = bands.get(b, [0, 0, 0, 0])
		e[0] += 1
		if g.cells.is_dirty(c):
			e[1] += 1
		if g.cells.has_flag(c, SphereCells.F_HUB):
			e[2] += 1
		bands[b] = e
	var spawn: Vector3 = Vector3(0, 0, 0.5)
	var pod: Vector3 = sp.anchor_local("pod").origin
	var near_spawn: float = INF
	var near_pod: float = INF
	var near_edge: float = INF
	var on_pad: int = 0
	var half: float = PAD_HALF_M
	for pid: int in f.piece_pos.size():
		if f.piece_alive[pid] == 0:
			continue
		var lp2: Vector3 = inv * f.piece_pos[pid]
		var q := Vector2(lp2.x, lp2.z)
		if q.length() > 60.0:
			continue
		var b2: int = int(q.length() / 4.0)
		var e2: Array = bands.get(b2, [0, 0, 0, 0])
		e2[3] += 1
		bands[b2] = e2
		near_spawn = minf(near_spawn, q.distance_to(Vector2(spawn.x, spawn.z)))
		near_pod = minf(near_pod, q.distance_to(Vector2(pod.x, pod.z)))
		var out: float = maxf(absf(q.x), absf(q.y)) - half
		if out < 0.0:
			on_pad += 1
		else:
			near_edge = minf(near_edge, out)
	var keys: Array = bands.keys()
	keys.sort()
	for k: int in keys:
		var e3: Array = bands[k]
		lines.append("[yardprobe] band %2d-%2d m: cells %d (dirty %d, hub %d)  pieces %d" % [k * 4, k * 4 + 4, e3[0], e3[1], e3[2], e3[3]])
	lines.append("[yardprobe] nearest piece: from spawn %.1f m, from pod %.1f m, from the pad edge %.1f m" % [near_spawn, near_pod, near_edge])
	lines.append("[yardprobe] pieces on the pad: %d (pad half %.1f m)" % [on_pad, half])
	lines.append(_pod_ring(w))
	# Things that should not be there at the start.
	var sled: Variant = (so.get("sites") as Object).get("sled") if so.get("sites") else null
	lines.append("[yardprobe] sled: %s" % (("shown" if (sled as Node3D).is_visible_in_tree() else "hidden") if sled is Node3D else "none"))
	var glim: Node = w.get_node_or_null("Glim") if w else null
	lines.append("[yardprobe] glim: %s (found=%s)" % [("shown" if (glim as Node3D).is_visible_in_tree() else "hidden") if glim is Node3D else "none", str(Glim.is_found())])
	var camp: Camp = w.get("camp") if w else null
	var blink: Node3D = camp.camera_bot if camp else null
	lines.append("[yardprobe] blink: %s" % (("shown" if blink.is_visible_in_tree() else "hidden") if blink else "none"))
	return "\n".join(lines)


## How close Lumi's box (SiteReach.BOX, its base 0.25 m up) gets round the pod: per ring radius
## (m from the pod's axis at the ground), how many of 24 spots overlap the pod's colliders.
func _pod_ring(w: Node) -> String:
	var site: Node3D = w.get_meta("orbit_pod", null) as Node3D if w else null
	if site == null:
		return "[yardprobe] pod: none"
	var pod: Node3D = (site as CrashSite).pod
	var space: PhysicsDirectSpaceState3D = pod.get_world_3d().direct_space_state
	var up: Vector3 = site.global_position.normalized()
	var f: Basis = SphereGrid.frame(up)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = PropColliders.box_shape(SiteReach.BOX)
	q.collision_mask = PhysLayers.PROP
	var parts: PackedStringArray = []
	for r: float in [1.2, 1.4, 1.6, 1.8, 2.2, 2.8]:
		var hit: int = 0
		for k: int in 24:
			var a: float = TAU * k / 24.0
			var out: Vector3 = f.x * cos(a) + f.z * sin(a)
			var at: Vector3 = site.global_position + out * r + up * SiteReach.BOX_Y
			q.transform = Transform3D(Basis(out.cross(up).normalized(), up, out).orthonormalized(), at)
			for h: Dictionary in space.intersect_shape(q, 4):
				if pod.is_ancestor_of(h["collider"] as Node) or h["collider"] == pod:
					hit += 1
					break
		parts.append("%.1fm:%d" % [r, hit])
	return "[yardprobe] pod ring (blocked of 24): " + " ".join(parts)
