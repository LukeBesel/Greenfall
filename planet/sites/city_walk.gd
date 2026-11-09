class_name CityWalk
extends RefCounted
## [v3city] Walk check for a hub town (owner item 42: a full city that stays walkable). Flood-fills
## Lumi's collision box over the site from where Lumi stands (the start: (0, 6) on the pad) on a
## STEP grid, against the prefab's own colliders (buildings, furniture, fences, parked wrecks), and
## reports:
##   - the walkable area reached, and the free ground Lumi can NOT reach (pockets walled in by
##     buildings or props: junk lying there could never be cleaned),
##   - whether the walk gets out of the town in all eight compass directions (no walled-in yard),
##   - the junk pieces already laid on the site's cells that lie on blocked or unreachable ground.
## Run: godot --headless --path . -- --fresh --orbit --city-walk   (exit 1 on a failure).

const STEP: float = 0.5
const BOX := Vector3(1.1, 0.95, 1.0)
const BOX_Y: float = 0.25 + 0.475
## Pockets of unreachable free ground smaller than this (m2) are slivers behind props, not lots.
const POCKET_M2: float = 6.0


static func run(p: SitePrefab, terrain: SphereTerrain, field: SphereField, half_m: float, start: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = BOX - Vector3(0.06, 0.06, 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = PhysLayers.SOLID
	var n: int = int(half_m * 2.0 / STEP) + 1
	var xf: Transform3D = p.global_transform
	var state := PackedByteArray()  # 0 outside the disc, 1 free, 2 blocked
	state.resize(n * n)
	var free_n: int = 0
	for iz: int in n:
		for ix: int in n:
			var lx: float = ix * STEP - half_m
			var lz: float = iz * STEP - half_m
			if lx * lx + lz * lz > half_m * half_m:
				continue
			var up: Vector3 = (xf * Vector3(lx, 0, lz)).normalized()
			var g: Vector3 = terrain.ground(up)
			q.transform = Transform3D(SphereGrid.frame(up), g + up * BOX_Y)
			var ok: bool = true
			for hit: Dictionary in space.intersect_shape(q, 8):
				var co: Object = hit.get("collider")
				if co is Node and p.is_ancestor_of(co as Node):
					ok = false
					break
			state[iz * n + ix] = 1 if ok else 2
			free_n += 1 if ok else 0
	var idx := func(lx: float, lz: float) -> int:
		var ix: int = int(round((lx + half_m) / STEP))
		var iz: int = int(round((lz + half_m) / STEP))
		return -1 if ix < 0 or iz < 0 or ix >= n or iz >= n else iz * n + ix
	var s0: int = idx.call(start.x, start.z)
	var out: Dictionary = {"start_free": s0 >= 0 and state[s0] == 1}
	var seen := PackedByteArray()
	seen.resize(n * n)
	var reached: int = 0
	if out["start_free"]:
		var stack := PackedInt32Array([s0])
		seen[s0] = 1
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			reached += 1
			var cx: int = c % n
			var cz: int = floori(float(c) / n)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var nz: int = cz + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var j: int = nz * n + nx
				if seen[j] == 0 and state[j] == 1:
					seen[j] = 1
					stack.append(j)
	# Unreachable free pockets (connected components of free, unseen cells).
	var pockets: Array = []  # [area m2, centre]
	var mark := seen.duplicate()
	for i: int in n * n:
		if state[i] != 1 or mark[i] == 1:
			continue
		var stack2 := PackedInt32Array([i])
		mark[i] = 1
		var cnt: int = 0
		var sum := Vector2.ZERO
		while not stack2.is_empty():
			var c2: int = stack2[stack2.size() - 1]
			stack2.resize(stack2.size() - 1)
			cnt += 1
			var cx2: int = c2 % n
			var cz2: int = floori(float(c2) / n)
			sum += Vector2(cx2 * STEP - half_m, cz2 * STEP - half_m)
			for d2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx2: int = cx2 + d2.x
				var nz2: int = cz2 + d2.y
				if nx2 < 0 or nz2 < 0 or nx2 >= n or nz2 >= n:
					continue
				var j2: int = nz2 * n + nx2
				if mark[j2] == 0 and state[j2] == 1:
					mark[j2] = 1
					stack2.append(j2)
		var area: float = cnt * STEP * STEP
		if area >= POCKET_M2:
			pockets.append([area, sum / cnt])
	pockets.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	# Out of town in every direction: a reached cell in the outer 12 m of each 45-degree sector.
	var dirs: Array[bool] = []
	dirs.resize(8)
	for i: int in n * n:
		if seen[i] == 0:
			continue
		var lx2: float = (i % n) * STEP - half_m
		var lz2: float = floori(float(i) / n) * STEP - half_m
		if Vector2(lx2, lz2).length() < half_m - 12.0:
			continue
		var sec: int = posmod(roundi(atan2(lz2, lx2) / (TAU / 8.0)), 8)
		dirs[sec] = true
	# Junk already laid on the site that lies on blocked or unreachable ground.
	var bad_pieces: int = 0
	var pieces: int = 0
	var bad_at: Array = []
	if field:
		var inv: Transform3D = xf.affine_inverse()
		for c3: int in p.site.get("cells", PackedInt32Array()):
			if field.materialized[c3] == 0:
				continue
			for pid: int in field.pieces_in(c3):
				var lp: Vector3 = inv * field.piece_xf[pid].origin
				var j3: int = idx.call(lp.x, lp.z)
				if j3 < 0 or state[j3] == 0:
					continue
				pieces += 1
				# Lumi scoops from a little way off: the piece is fine if a reached cell is within 1 m.
				var ok3: bool = false
				for dz: int in range(-2, 3):
					for dx: int in range(-2, 3):
						var j4: int = idx.call(lp.x + dx * STEP, lp.z + dz * STEP)
						if j4 >= 0 and seen[j4] == 1:
							ok3 = true
				if not ok3:
					bad_pieces += 1
					if bad_at.size() < 8:
						bad_at.append(Vector2(lp.x, lp.z))
						if DevHooks.has("walk-debug"):
							var ko: Variant = field.keep_out
							print("[walk] piece %d cell %d at (%.1f, %.1f) keep-out %s mid %s" % [pid, c3, lp.x, lp.z,
								str(ko.call(field.piece_xf[pid].origin.normalized())) if ko is Callable and (ko as Callable).is_valid() else "-", str(field.piece_model[pid]) if "piece_model" in field else "?"])
	out["free_m2"] = free_n * STEP * STEP
	out["reached_m2"] = reached * STEP * STEP
	out["pockets"] = pockets
	out["dirs"] = dirs
	out["pieces"] = pieces
	out["bad_pieces"] = bad_pieces
	out["bad_at"] = bad_at
	var big: Array = pockets.filter(func(pk: Array) -> bool: return float(pk[0]) >= 25.0)
	out["pass"] = bool(out["start_free"]) and not dirs.has(false) and big.is_empty() and bad_pieces == 0
	return out


## The dev flag: waits for the start site and the junk near it, runs the check, prints and quits.
static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	var sm: SiteManager = so.globe.site_manager
	await tree.create_timer(DevHooks.get_f("city-walk", 8.0)).timeout
	var p: SitePrefab = sm.prefab(0)
	if p == null or not p.is_built:
		print("[walk] FAIL: no start site")
		tree.quit(1)
		return
	for k: int in 3:
		await tree.physics_frame
	if DevHooks.has("walk-debug"):
		var inv0: Transform3D = p.global_transform.affine_inverse()
		var wl: PackedStringArray = []
		for c: int in p.site.get("cells", PackedInt32Array()):
			if so.globe.cells.state[c] == 5:
				var lp0: Vector3 = inv0 * so.globe.grid.centers[c] * so.globe.terrain.R
				wl.append("(%.0f,%.0f)" % [lp0.x, lp0.z])
		print("[walk] water cells on the site: %d %s" % [wl.size(), " ".join(wl)])
	var half: float = VerdanceSite.TOWN_R + 14.0
	var t0: int = Time.get_ticks_msec()
	var r: Dictionary = run(p, so.globe.terrain, so.globe.field, half, Vector3(0, 0, 6))
	var names: PackedStringArray = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var shut: PackedStringArray = []
	for i: int in 8:
		if not (r["dirs"] as Array)[i]:
			shut.append(names[i])
	var pk: PackedStringArray = []
	for e: Array in (r["pockets"] as Array).slice(0, 6):
		pk.append("%d m2@(%.0f,%.0f)" % [int(e[0]), (e[1] as Vector2).x, (e[1] as Vector2).y])
	print("[walk] start town: %d m2 free, %d m2 reached from the pad, out of town to %s, %d unreachable pockets%s, junk %d pieces / %d unreachable%s (%d ms)" % [
		int(r["free_m2"]), int(r["reached_m2"]), "every side" if shut.is_empty() else "all but " + ",".join(shut),
		(r["pockets"] as Array).size(), "" if pk.is_empty() else " (" + ", ".join(pk) + ")", int(r["pieces"]), int(r["bad_pieces"]),
		"" if (r["bad_at"] as Array).is_empty() else " at " + str(r["bad_at"]), Time.get_ticks_msec() - t0])
	print("[walk] %s" % ("PASS" if r["pass"] else "FAIL"))
	tree.quit(0 if r["pass"] else 1)
