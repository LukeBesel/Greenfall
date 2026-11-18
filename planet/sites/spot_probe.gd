class_name SpotProbe
extends RefCounted
## [v8fix] Dev: --spot-probe=x,y,z [--orbit-hop=N --hop-skip]. After the hop (or 4 s after start),
## puts Lumi at that world point and reports what is around it: TargetReach's verdict there
## (with colliders), a flood over free ground (colliders counted) out to 20 m, and every solid
## collider within 7 m with its node path. For checking a spot the autoplay bot logged as a trap.
## --spot-probe-wait=S: seconds before the probe (default 4 + 40 a hop). Prints [spot] lines and quits.

const R_M: float = 7.0
const FLOOD_M: float = 20.0


static func run_dev(so: Node) -> void:
	var tree: SceneTree = so.get_tree()
	var hops: int = DevHooks.get_s("orbit-hop", "").split(",", false).size()
	await tree.create_timer(DevHooks.get_f("spot-probe-wait", 4.0 + 40.0 * hops)).timeout
	var xyz: PackedStringArray = DevHooks.get_s("spot-probe", "0,0,0").split(",")
	var w: Node = so.get("w")
	var p := Vector3.ZERO
	if xyz[0].begins_with("outpost"):  # --spot-probe=outpostK: the active hub's outpost K (its centre)
		for m: Node in tree.get_nodes_in_group("outposts"):
			var its: Array = m.get("items")
			if int(xyz[0].trim_prefix("outpost")) < its.size():
				p = (its[int(xyz[0].trim_prefix("outpost"))] as Node3D).global_position
	else:
		p = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
	var stand: Vector3 = p
	if DevHooks.has("spot-probe-off"):  # stand Lumi this far off the spot (frame x), to load its colliders without standing in them
		stand = p + SphereGrid.frame(p.normalized()).x * DevHooks.get_f("spot-probe-off", 9.0)
	var patch: Node3D = w.get("patch")
	if patch and patch.has_method("place_on_sphere"):
		patch.call("place_on_sphere", stand + stand.normalized() * 0.3, Vector3.FORWARD)
	for k: int in 20:
		await tree.physics_frame
	await tree.create_timer(2.0).timeout
	var tr_: TargetReach = TargetReach.for_world(w, true, patch)
	print("[spot] at %s: why=%s reach=%s escapes(ground only)=%s" % [str(p), tr_.why(p), tr_.reach(p), tr_.escapes(p)])
	# Flood over free ground with colliders counted.
	var d: Vector3 = p.normalized()
	var f: Basis = SphereGrid.frame(d)
	var R: float = tr_.terrain.R
	var step: float = 0.5
	var lim: int = int(FLOOD_M / step)
	var seen: Dictionary = {Vector2i.ZERO: true}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	var n: int = 0
	var out: bool = false
	var blockers: Dictionary = {}
	while not stack.is_empty() and n < 20000:
		var at: Vector2i = stack.pop_back()
		n += 1
		if at.x * at.x + at.y * at.y >= lim * lim:
			out = true
			break
		for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = at + o
			if seen.has(q):
				continue
			seen[q] = true
			var qd: Vector3 = (d * R + (f.x * q.x + f.z * q.y) * step).normalized()
			var why: String = tr_.why(qd)
			if why == "":
				stack.append(q)
			else:
				blockers[why] = int(blockers.get(why, 0)) + 1
	print("[spot] pockets within 6 m: %d" % tr_.pockets(p))
	print("[spot] flood (0.5 m grid, colliders counted): %d cells, %s, edge blockers %s" % [n, "gets out to %d m" % int(FLOOD_M) if out else "SHUT IN", str(blockers)])
	# Colliders near the spot.
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = R_M
	q.shape = sph
	q.collision_mask = PhysLayers.SOLID
	q.transform = Transform3D(Basis(), p)
	var space: PhysicsDirectSpaceState3D = (w as Node3D).get_world_3d().direct_space_state
	for hit: Dictionary in space.intersect_shape(q, 64):
		var co: Object = hit.get("collider")
		if co is Node3D and (co as Node3D).global_position.length() > 100.0 and not (co as Node).is_in_group("ground") and not (patch and patch.is_ancestor_of(co as Node)) and co != patch:
			var n3: Node3D = co
			var sh: String = ""
			var cs: Node = n3.get_child(int(hit.get("shape", 0))) if n3.get_child_count() > int(hit.get("shape", 0)) else null
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape:
				sh = (cs as CollisionShape3D).shape.get_class()
			print("[spot]   %5.1f m  %s  %s" % [n3.global_position.distance_to(p), str(n3.get_path()).replace("/root/", ""), sh])
	# A map of the ground around the spot (0.5 m cells, x = frame x, rows = frame z): '.' free,
	# '#' building, '~' water, '^' steep, a letter per collider (legend below), '@' the spot.
	var probe := PhysicsShapeQueryParameters3D.new()
	var bx := BoxShape3D.new()
	bx.size = TargetReach.PROBE
	probe.shape = bx
	probe.collision_mask = PhysLayers.SOLID
	var legend: Dictionary = {}
	var shapes: Dictionary = {}
	var near_o: Node3D = null
	for m: Node in tree.get_nodes_in_group("outposts"):
		for o: Node in m.get("items"):
			if near_o == null or (o as Node3D).global_position.distance_to(p) < near_o.global_position.distance_to(p):
				near_o = o
	var half: int = int(DevHooks.get_f("spot-probe-map", 8.0) / step)
	for zi: int in range(-half, half + 1):
		var row: String = ""
		for xi: int in range(-half, half + 1):
			if xi == 0 and zi == 0:
				row += "@"
				continue
			var qd: Vector3 = (d * R + (f.x * xi + f.z * zi) * step).normalized()
			if tr_.last_shut.has(Vector2i(xi, zi)):
				row += "*"
				continue
			var g: String = tr_.why_ground(qd)
			if g != "":
				row += {"building": "#", "water": "~", "steep": "^"}.get(g, "?")
				continue
			probe.transform = Transform3D(SphereGrid.frame(qd), tr_.terrain.ground(qd) + qd * TargetReach.PROBE_Y)
			var ch: String = "."
			for hit: Dictionary in space.intersect_shape(probe, 8):
				var co: Node = hit.get("collider") as Node
				if co == null or co.is_in_group("ground") or co == patch or (patch and patch.is_ancestor_of(co)):
					continue
				var key: String = "%s#%d" % [str(co.get_path()).replace("/root/Slice/", ""), int(hit.get("shape", 0))]
				if not legend.has(key):
					shapes[key] = [co, int(hit.get("shape", 0))]
					legend[key] = char(65 + legend.size() % 26) if legend.size() < 26 else char(97 + (legend.size() - 26) % 26)
				ch = legend[key]
				break
			row += ch
		print("[spot] map %s" % row)
	for key: String in legend:
		var info: String = ""
		var co2: CollisionObject3D = shapes[key][0] as CollisionObject3D
		if co2 and near_o:
			var own: Object = co2.shape_owner_get_owner(co2.shape_find_owner(int(shapes[key][1])))
			if own is CollisionShape3D:
				var cs2: CollisionShape3D = own
				var sz: String = str((cs2.shape as BoxShape3D).size) if cs2.shape is BoxShape3D else cs2.shape.get_class()
				info = "  at %s in %s's frame, %s" % [str(near_o.to_local(cs2.global_position).snapped(Vector3.ONE * 0.1)), near_o.name, sz]
		print("[spot] legend %s = %s%s" % [legend[key], key, info])
	var op: Array = tree.get_nodes_in_group("outposts")
	for m: Node in op:
		for o: Node in m.get("items"):
			print("[spot]   outpost %s at %.1f m" % [o.name, (o as Node3D).global_position.distance_to(p)])
	print("[spot] done")
	tree.quit()
