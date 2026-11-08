class_name SiteReach
extends RefCounted
## [orbD] Narrow-gap audit for hub sites: can Lumi reach every interactable anchor?
## Flood-fills Lumi's collision box (Patch on a sphere: 1.1 x 0.95 x 1.0 m, its base 0.25 m over
## the ground) over a STEP grid in site-local metres, from the spot Lumi steps off the rocket
## (rocket_pad + (4.5, 0, 3)). Only the prefab's own colliders count (the audit is about the
## site's geometry; junk is scooped). A free cell has no overlap with any of them. Every anchor
## except rocket_pad must have a reachable cell within REACH_M (the interact reach).
## Run on a globe: --orbit --site-reach[=planet] (OrbitSites), prints a [reach] line per hub and
## exits 1 if any anchor is cut off. Results: {reachable: int, anchors: {name: bool}, cut: [names]}

const STEP: float = 0.5
const HALF_M: float = 62.0
const REACH_M: float = 2.0
const BOX := Vector3(1.1, 0.95, 1.0)
const BOX_Y: float = 0.25 + 0.475
const SKIP: Array[String] = ["rocket_pad"]
## A floor this far above the ground counts (decks, pads); higher hits are roofs and tops.
const FLOOR_UP_M: float = 1.6
## Largest step between neighbouring cells Lumi's hover takes (kerbs, deck edges, ramps).
const STEP_UP_M: float = 0.45
## Lumi reaches a machine from within this of its edge; edges searched out to MAX_EDGE_M.
const EDGE_M: float = 1.2
const MAX_EDGE_M: float = 6.0
## Anchors moved by fix_anchors keep this far apart (machines 3 m apart, minus a little).
const SPACING_M: float = 2.6
## Walking lane kept between moved machines' footprints.
const LANE_M: float = 1.2
## Footprint radius (m) of the model standing on each anchor (the start yard's machines).
const FOOT: Dictionary = {"nursery": 3.0, "stations": 4.2, "shack": 2.2, "telescope": 2.0, "fabricator": 2.5,
	"pod": 2.2, "depot": 2.2, "bench": 2.2, "signal_tower": 1.3, "composter": 1.3, "generator": 1.0, "radio": 0.9,
	"locker": 0.8, "bin": 0.8, "camera_bot": 0.5, "door": 0.5}


## With every machine standing as a disc of its footprint: does a walk from the landing spot over
## the reachable ground still get to every machine's edge (within EDGE_M of its rim)?
static func _no_worse(before: Array, after: Array) -> bool:
	if after.is_empty() or not bool(after[after.size() - 1]):
		return false  # the new machine itself must be reachable
	for i: int in before.size():
		if bool(before[i]) and not bool(after[i]):
			return false
	return true


## Per disc: is its edge reachable from the landing spot with every disc standing?
static func _reached(state: PackedByteArray, n: int, discs: Array, start: Vector3) -> Array:
	var to_i := func(x: float, z: float) -> int:
		var ix: int = int(round((x + HALF_M) / STEP))
		var iz: int = int(round((z + HALF_M) / STEP))
		return -1 if ix < 0 or iz < 0 or ix >= n or iz >= n else iz * n + ix
	var blocked := func(i: int) -> bool:
		var x: float = (i % n) * STEP - HALF_M
		var z: float = floori(float(i) / n) * STEP - HALF_M
		for d: Array in discs:
			var dp: Vector3 = d[0]
			if dp.distance_to(start) < 0.05:
				continue  # the landing spot is kept clear for spacing, it isn't an obstacle
			if Vector2(dp.x - x, dp.z - z).length() < float(d[1]):
				return true
		return false
	var out: Array = []
	var s0: int = to_i.call(start.x, start.z)
	if s0 < 0 or state[s0] != 3:
		for d: Array in discs:
			out.append(true)  # no landing information: don't block placement
		return out
	var seen := PackedByteArray()
	seen.resize(n * n)
	var stack := PackedInt32Array([s0])
	seen[s0] = 1
	while not stack.is_empty():
		var c: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var cx: int = c % n
		var cz: int = floori(float(c) / n)
		for dd: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + dd.x
			var nz: int = cz + dd.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var j: int = nz * n + nx
			if seen[j] == 1 or state[j] != 3 or blocked.call(j):
				continue
			seen[j] = 1
			stack.append(j)
	for d: Array in discs:
		var dp: Vector3 = d[0]
		var lim: float = float(d[1]) + EDGE_M
		var ok: bool = false
		var r: int = int(ceil(lim / STEP))
		for dz: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if Vector2(dx, dz).length() * STEP > lim:
					continue
				var j2: int = to_i.call(dp.x + dx * STEP, dp.z + dz * STEP)
				if j2 >= 0 and seen[j2] == 1:
					ok = true
					break
			if ok:
				break
		out.append(ok)
	return out


static func foot(nm: String) -> float:
	return float(FOOT.get(nm, 0.4))


## True when the anchor's footprint (a circle of `rad`) sits on reachable ground: centre and rim.
static func _all_reach(reach_at: Callable, c: Vector3, rad: float) -> bool:
	if not reach_at.call(c):
		return false
	for k: int in 8:
		var a: float = TAU * k / 8.0
		if not reach_at.call(c + Vector3(cos(a), 0, sin(a)) * rad * 0.8):
			return false
	return true


static func audit(p: SitePrefab, terrain: SphereTerrain, only: Node = null) -> Dictionary:
	var own: Node = only if only else p
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = BOX - Vector3(0.06, 0.06, 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	var n: int = int(HALF_M * 2.0 / STEP) + 1
	var xf: Transform3D = p.global_transform
	var state := PackedByteArray()  # 0 unknown, 1 free, 2 blocked
	state.resize(n * n)
	var floor_h := PackedFloat32Array()  # floor height above the terrain (site decks, pads, ice)
	floor_h.resize(n * n)
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = 0xFFFFFFFF
	var to_idx := func(lx: float, lz: float) -> int:
		var ix: int = int(round((lx + HALF_M) / STEP))
		var iz: int = int(round((lz + HALF_M) / STEP))
		return -1 if ix < 0 or iz < 0 or ix >= n or iz >= n else iz * n + ix
	var free := func(idx: int) -> bool:
		if state[idx] != 0:
			return state[idx] == 1
		var lx: float = (idx % n) * STEP - HALF_M
		var lz: float = floori(float(idx) / n) * STEP - HALF_M
		var wp: Vector3 = xf * Vector3(lx, 0, lz)
		var up: Vector3 = wp.normalized()
		var g: Vector3 = terrain.ground(up)
		# Stand on the prefab's own floor where it has one (raft decks, plated pads, ice), like
		# SphereMotor's ground ray does: the highest prefab surface within FLOOR_UP_M over the ground.
		var fh: float = 0.0
		ray.from = g + up * FLOOR_UP_M
		ray.to = g - up * 0.5
		var ex: Array[RID] = []
		for k: int in 4:
			ray.exclude = ex
			var rh: Dictionary = space.intersect_ray(ray)
			if rh.is_empty():
				break
			var rc: Object = rh["collider"]
			if rc is Node and own.is_ancestor_of(rc as Node):
				fh = maxf(0.0, ((rh["position"] as Vector3) - g).dot(up))
				break
			ex.append(rh["rid"])
		floor_h[idx] = fh
		q.transform = Transform3D(SphereGrid.frame(up), g + up * (fh + BOX_Y))
		var ok: bool = true
		for hit: Dictionary in space.intersect_shape(q, 16):
			var co: Object = hit.get("collider")
			if co is Node and own.is_ancestor_of(co as Node):
				ok = false
				break
		state[idx] = 1 if ok else 2
		return ok
	var start_l: Vector3 = p.anchor_local("rocket_pad") * Vector3(4.5, 0, 3.0)
	var s0: int = to_idx.call(start_l.x, start_l.z)
	var reach: int = 0
	if s0 >= 0 and free.call(s0):
		var seen := PackedByteArray()
		seen.resize(n * n)
		var stack := PackedInt32Array([s0])
		seen[s0] = 1
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			reach += 1
			var cx: int = c % n
			var cz: int = floori(float(c) / n)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var nz: int = cz + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var j: int = nz * n + nx
				if seen[j] == 1:
					continue
				if free.call(j) and absf(floor_h[j] - floor_h[c]) <= STEP_UP_M:
					seen[j] = 1
					stack.append(j)
		state = _mark_reached(state, seen)
	var anchors: Dictionary = {}
	var cut: Array[String] = []
	for nm: String in p.anchor_names():
		if nm in SKIP:
			continue
		var a: Vector3 = p.anchor_local(nm).origin
		# A machine's own body fills its anchor: Lumi needs to get to its edge. The edge is the
		# nearest free cell; a reachable cell must lie within that distance + EDGE_M (and REACH_M).
		var edge: float = -1.0
		var reach_ok: bool = false
		var rmax: int = int(ceil(MAX_EDGE_M / STEP))
		var cells: Array = []
		for dz: int in range(-rmax, rmax + 1):
			for dx: int in range(-rmax, rmax + 1):
				var d: float = Vector2(dx, dz).length() * STEP
				if d <= MAX_EDGE_M:
					cells.append([d, dx, dz])
		cells.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for e: Array in cells:
			var j2: int = to_idx.call(a.x + int(e[1]) * STEP, a.z + int(e[2]) * STEP)
			if j2 < 0:
				continue
			var d2: float = e[0]
			if edge < 0.0 and free.call(j2):
				edge = d2
			var lim: float = maxf(REACH_M, (edge if edge >= 0.0 else 0.0) + EDGE_M)
			if edge >= 0.0 and d2 > lim:
				break
			if state[j2] == 3:
				reach_ok = true
				break
		anchors[nm] = reach_ok
		if not reach_ok:
			cut.append(nm)
	if DevHooks.has("reach-map") and only == null:  # dev: the walk map round the site, 1 char per metre
		var rows: PackedStringArray = []
		var hm: int = int(DevHooks.get_f("reach-map", 45.0))
		for z: int in range(-hm, hm + 1, 1):
			var line: String = ""
			for x: int in range(-hm, hm + 1, 1):
				var j3: int = to_idx.call(float(x), float(z))
				var ch: String = " "
				if j3 >= 0:
					if state[j3] == 0:
						free.call(j3)
					ch = [" ", ".", "#", "o"][state[j3]]
					if ch == "." and floor_h[j3] > 0.3:
						ch = ","  # free, on a deck or pad (raised floor) but not reached
				if x == int(round(start_l.x)) and z == int(round(start_l.z)):
					ch = "S"
				line += ch
			rows.append(line)
		print("[reach-map]\n" + "\n".join(rows))
		var prof: PackedStringArray = []
		for xx: int in range(0, 46):
			var j4: int = to_idx.call(float(xx), -0.6)
			if j4 >= 0:
				if state[j4] == 0:
					free.call(j4)
				prof.append("%d:%s%.2f" % [xx, ["?", "", "#", "o"][state[j4]], floor_h[j4]])
		print("[reach-prof] " + " ".join(prof))
	var why: String = ""
	if s0 >= 0 and state[s0] != 3:  # what blocks the landing spot (for the report)
		for hit: Dictionary in space.intersect_shape(q, 8):
			var co: Object = hit.get("collider")
			if co is Node and own.is_ancestor_of(co as Node):
				why += " %s" % String((co as Node).get_path()).get_slice("/Content/", 1)
		why = "floor %.2f m:%s" % [floor_h[s0], why]
	return {"reachable": reach, "anchors": anchors, "cut": cut, "start_free": s0 >= 0 and state[s0] == 3, "why": why,
		"state": state, "n": n}


## Reached free cells become 3 (free but unreached stays 1).
static func _mark_reached(state: PackedByteArray, seen: PackedByteArray) -> PackedByteArray:
	for i: int in state.size():
		if seen[i] == 1 and state[i] == 1:
			state[i] = 3
	return state


## True when Lumi's box fits at a site-local point (standing on the prefab's floor, if any).
static func free_at(p: SitePrefab, terrain: SphereTerrain, local: Vector3, only: Node = null) -> bool:
	var owner_n: Node = only if only else p
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var wp: Vector3 = p.global_transform * Vector3(local.x, 0, local.z)
	var up: Vector3 = wp.normalized()
	var g: Vector3 = terrain.ground(up)
	var fh: float = 0.0
	var ray := PhysicsRayQueryParameters3D.create(g + up * FLOOR_UP_M, g - up * 0.5)
	var ex: Array[RID] = []
	for k: int in 4:
		ray.exclude = ex
		var rh: Dictionary = space.intersect_ray(ray)
		if rh.is_empty():
			break
		var rc: Object = rh["collider"]
		if rc is Node and p.is_ancestor_of(rc as Node):
			fh = maxf(0.0, ((rh["position"] as Vector3) - g).dot(up))
			break
		ex.append(rh["rid"])
	var shape := BoxShape3D.new()
	shape.size = BOX - Vector3(0.06, 0.06, 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(SphereGrid.frame(up), g + up * (fh + BOX_Y))
	for hit: Dictionary in space.intersect_shape(q, 16):
		var co: Object = hit.get("collider")
		if co is Node and owner_n.is_ancestor_of(co as Node):
			return false
	return true


## The nearest free site-local point to `local` (rings of 0.75 m out to max_r), or `local`.
static func nearest_free(p: SitePrefab, terrain: SphereTerrain, local: Vector3, max_r: float = 18.0, only: Node = null) -> Vector3:
	if free_at(p, terrain, local, only):
		return local
	var r: float = 0.75
	while r <= max_r:
		var n: int = maxi(8, int(TAU * r / 0.75))
		for k: int in n:
			var a: float = TAU * k / n
			var c := local + Vector3(cos(a) * r, 0, sin(a) * r)
			if free_at(p, terrain, c, only):
				return c
		r += 0.75
	return local


## Moves a prefab's standard anchors out of its geometry (builders that don't know the anchor
## defaults: Ochre's yard, Tidewell's raft deck). The rocket pad moves so that the spot Lumi
## steps off to is free. Returns the anchors moved.
static func fix_anchors(p: SitePrefab, terrain: SphereTerrain) -> PackedStringArray:
	var moved := PackedStringArray()
	# 1. The rocket pad: the spot Lumi steps off to must be free of the prefab's geometry.
	var pad: Marker3D = p.anchor("rocket_pad")
	var reserved: Array[Vector3] = []
	if pad:
		var step: Vector3 = pad.position + Vector3(4.5, 0, 3.0)
		var to: Vector3 = nearest_free(p, terrain, step, 18.0, p.content)
		if to.distance_to(step) > 0.01:
			pad.position = to - Vector3(4.5, 0, 3.0)
			moved.append("rocket_pad")
		reserved.append(pad.position)
		reserved.append(pad.position + Vector3(4.5, 0, 3.0))
	# 2. Every other anchor: on ground Lumi can reach from there (a raft's deck, not the sea), clear
	# of the prefab's geometry and of the other machines' footprints with a walking lane between.
	var r: Dictionary = audit(p, terrain, p.content)
	var state: PackedByteArray = r["state"]
	var n: int = r["n"]
	var reach_at := func(l: Vector3) -> bool:
		var ix: int = int(round((l.x + HALF_M) / STEP))
		var iz: int = int(round((l.z + HALF_M) / STEP))
		return ix >= 0 and iz >= 0 and ix < n and iz < n and state[iz * n + ix] == 3
	var placed: Array = []  # [pos, radius]
	if pad:
		placed.append([pad.position + Vector3(4.5, 0, 3.0), 1.2])  # Lumi's landing spot
	var spaced := func(l: Vector3, rad: float) -> bool:
		for q: Array in placed:
			var qp: Vector3 = q[0]
			if Vector2(qp.x - l.x, qp.z - l.z).length() < rad + float(q[1]) + LANE_M:
				return false
		return true
	var todo: Array[String] = []
	for nm: String in p.anchor_names():  # pass 1: designed anchors, and reachable depot/bench/door, stay
		if nm == "rocket_pad" or nm == "shack":
			continue  # the lean-to stands over the bench (YardSite): the bench's footprint covers it
		var keep: bool = nm in p.designed or (nm in ["depot", "bench", "door"] and reach_at.call(p.anchor(nm).position))
		if keep:
			placed.append([p.anchor(nm).position, foot(nm)])
		else:
			todo.append(nm)
	todo.sort_custom(func(x: String, y: String) -> bool: return foot(x) > foot(y))  # big machines first
	for nm: String in todo:  # pass 2: the rest go to the nearest reachable spot with room
		var m: Marker3D = p.anchor(nm)
		var at: Vector3 = m.position
		var rad: float = foot(nm)
		var rr: float = STEP
		var found: bool = false
		while rr <= HALF_M and not found:
			var k_n: int = maxi(8, int(TAU * rr / STEP))
			for k: int in k_n:
				var a: float = TAU * k / k_n
				var c := at + Vector3(cos(a) * rr, 0, sin(a) * rr)
				if _all_reach(reach_at, c, rad) and spaced.call(c, rad):
					var trial: Array = placed.duplicate()
					trial.append([c, rad])
					var land: Vector3 = pad.position + Vector3(4.5, 0, 3.0) if pad else Vector3.ZERO
					if _no_worse(_reached(state, n, placed, land), _reached(state, n, trial, land)):
						m.position = c
						found = true
						break
			rr += STEP
		if found:
			moved.append(nm)
		if DevHooks.has("reach-debug"):
			print("[reach-fix] %s r=%.1f %s at (%.1f, %.1f)" % [nm, rad, "placed" if found else "NO ROOM", m.position.x, m.position.z])
		placed.append([m.position, rad])
	if not moved.is_empty():
		p.anchors_moved.emit(moved)
	return moved
