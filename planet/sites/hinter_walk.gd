class_name HinterWalk
extends RefCounted
## [v5play] Walk check for the land between the hub towns (planet/sites/hinterland.gd), the
## hinterland's version of CityWalk. Picks the densest clusters of hinterland buildings in view of
## the start town, puts Lumi in each, lets the junk and the colliders stream in, then flood-fills
## Lumi's collision box over a disc round him on a STEP grid against the hinterland's colliders
## (buildings, tanks, cars, fences, poles), lake cells and steep ground, and reports:
##   - the walkable ground reached, and free ground walled in by buildings or props (pockets),
##   - whether the walk leaves the disc in every compass direction that has free ground,
##   - junk pieces on blocked or unreachable ground (inside a footprint: could never be cleaned),
##   - the tightest gap between two neighbouring buildings (Lumi is 1.1 m wide).
## Run: godot --headless --path . -- --fresh --orbit --no-intro --hinter-walk [--hinter-walk-spots=N]   (exit 1 on a
## failure). --hinter-walk-at=x,z checks one spot (start-site metres, as --orbit-spawn).

const STEP: float = 0.5
const BOX := Vector3(1.1, 0.95, 1.0)
const BOX_Y: float = 0.25 + 0.475
const HALF_M: float = 50.0
const POCKET_M2: float = 6.0
const BIG_POCKET_M2: float = 25.0
const MAX_RISE: float = 0.62  # per metre, as TargetReach
const MIN_GAP_M: float = 1.6


static func run(h: Hinterland, terrain: SphereTerrain, field: SphereField, centre: Vector3, half_m: float = HALF_M) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = h.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = BOX - Vector3(0.06, 0.06, 0.06)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = PhysLayers.SOLID
	var n: int = int(half_m * 2.0 / STEP) + 1
	var c_dir: Vector3 = centre.normalized()
	var fr: Basis = SphereGrid.frame(c_dir)
	var R: float = terrain.R
	var dir_at := func(lx: float, lz: float) -> Vector3:
		return (c_dir * R + fr.x * lx + fr.z * lz).normalized()
	var state := PackedByteArray()  # 0 outside the disc or water, 1 free, 2 blocked (solid), 3 steep
	state.resize(n * n)
	var hgt := PackedFloat32Array()
	hgt.resize(n * n)
	var free_n: int = 0
	var solid_n: int = 0
	for iz: int in n:
		for ix: int in n:
			var lx: float = ix * STEP - half_m
			var lz: float = iz * STEP - half_m
			if lx * lx + lz * lz > half_m * half_m:
				continue
			var up: Vector3 = dir_at.call(lx, lz)
			var cell: int = field.grid.cell_at(up)
			if cell < 0 or field.is_water(cell):
				continue
			hgt[iz * n + ix] = terrain.height(up)
			var g: Vector3 = terrain.ground(up)
			q.transform = Transform3D(SphereGrid.frame(up), g + up * BOX_Y)
			var ok: bool = true
			for hit: Dictionary in space.intersect_shape(q, 8):
				var co: Object = hit.get("collider")
				if co is Node and h.is_ancestor_of(co as Node):
					ok = false
					break
			state[iz * n + ix] = 1 if ok else 2
			solid_n += 0 if ok else 1
	# Steep ground (over MAX_RISE in a metre) blocks the walk too.
	var m: int = int(1.0 / STEP)
	for iz2: int in n:
		for ix2: int in n:
			var i: int = iz2 * n + ix2
			if state[i] != 1:
				continue
			for d: Vector2i in [Vector2i(m, 0), Vector2i(-m, 0), Vector2i(0, m), Vector2i(0, -m)]:
				var nx: int = ix2 + d.x
				var nz: int = iz2 + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n or state[nz * n + nx] == 0:
					continue
				if absf(hgt[nz * n + nx] - hgt[i]) > MAX_RISE:
					state[i] = 3
					break
	for i2: int in n * n:
		free_n += 1 if state[i2] == 1 else 0
	var idx := func(lx: float, lz: float) -> int:
		var ix: int = int(round((lx + half_m) / STEP))
		var iz: int = int(round((lz + half_m) / STEP))
		return -1 if ix < 0 or iz < 0 or ix >= n or iz >= n else iz * n + ix
	# Start: the free point nearest the centre.
	var s0: int = -1
	var best: float = INF
	for i3: int in n * n:
		if state[i3] != 1:
			continue
		var v := Vector2((i3 % n) * STEP - half_m, floori(float(i3) / n) * STEP - half_m)
		if v.length_squared() < best:
			best = v.length_squared()
			s0 = i3
	var out: Dictionary = {"start_free": s0 >= 0, "solid_m2": solid_n * STEP * STEP}
	var seen := PackedByteArray()
	seen.resize(n * n)
	var reached: int = 0
	if s0 >= 0:
		reached = _flood(state, seen, n, s0, Vector2.ZERO)[0]
	var pockets: Array = []  # [area m2, centre]
	var mark := seen.duplicate()
	var ok_map := seen.duplicate()  # reached, or part of a patch the disc's rim cuts off (open beyond it)
	for i4: int in n * n:
		if state[i4] != 1 or mark[i4] == 1:
			continue
		var res: Array = _flood(state, mark, n, i4, Vector2(-half_m, -half_m))
		var area: float = int(res[0]) * STEP * STEP
		# A patch cut off by the disc's rim (or a lake's far side) isn't walled in by the hinterland.
		if bool(res[2]):
			_flood(state, ok_map, n, i4, Vector2.ZERO)
		if area >= POCKET_M2 and not bool(res[2]):
			pockets.append([area, res[1]])
	pockets.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	# Out of the disc in every direction that has free ground on the rim.
	var has_rim: Array[bool] = []
	var got_rim: Array[bool] = []
	has_rim.resize(8)
	got_rim.resize(8)
	for i5: int in n * n:
		if state[i5] != 1:
			continue
		var lx2: float = (i5 % n) * STEP - half_m
		var lz2: float = floori(float(i5) / n) * STEP - half_m
		if Vector2(lx2, lz2).length() < half_m - 8.0:
			continue
		var sec: int = posmod(roundi(atan2(lz2, lx2) / (TAU / 8.0)), 8)
		has_rim[sec] = true
		if seen[i5] == 1:
			got_rim[sec] = true
	var shut: PackedStringArray = []
	var names: PackedStringArray = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	for k: int in 8:
		if has_rim[k] and not got_rim[k]:
			shut.append(names[k])
	# Junk on blocked or unreachable ground.
	var pieces: int = 0
	var bad_pieces: int = 0
	var bad_at: Array = []
	for c: int in field.grid.cells_within(c_dir, half_m):
		if field.materialized[c] == 0:
			continue
		for pid: int in field.pieces_in(c):
			var rel: Vector3 = field.piece_xf[pid].origin - c_dir * R
			var lp := Vector2(rel.dot(fr.x), rel.dot(fr.z))
			var j: int = idx.call(lp.x, lp.y)
			if j < 0 or state[j] == 0 or lp.length() > half_m - 2.0:
				continue
			pieces += 1
			var ok3: bool = false
			for dz: int in range(-2, 3):
				for dx: int in range(-2, 3):
					var j2: int = idx.call(lp.x + dx * STEP, lp.y + dz * STEP)
					if j2 >= 0 and ok_map[j2] == 1:
						ok3 = true
			if not ok3:
				bad_pieces += 1
				if bad_at.size() < 6:
					bad_at.append(lp.snappedf(0.1))
					if DevHooks.has("walk-debug"):
						var tally: Array[int] = [0, 0, 0, 0]
						for dz2: int in range(-6, 7):
							for dx2: int in range(-6, 7):
								var j3: int = idx.call(lp.x + dx2 * STEP, lp.y + dz2 * STEP)
								if j3 >= 0:
									tally[state[j3]] += 1
						print("[hwalk] piece %d at %s: within 3 m %d cells off the disc or wet, %d free, %d solid, %d steep; keep-out %s" % [pid, str(lp.snappedf(0.1)), tally[0], tally[1], tally[2], tally[3],
							str(field.keep_out.call(field.piece_xf[pid].origin.normalized())) if field.keep_out.is_valid() else "-"])
	out["free_m2"] = free_n * STEP * STEP
	out["reached_m2"] = reached * STEP * STEP
	out["pockets"] = pockets
	out["shut"] = shut
	out["pieces"] = pieces
	out["bad_pieces"] = bad_pieces
	out["bad_at"] = bad_at
	var big: Array = pockets.filter(func(pk: Array) -> bool: return float(pk[0]) >= BIG_POCKET_M2)
	out["pass"] = bool(out["start_free"]) and shut.is_empty() and big.is_empty() and bad_pieces == 0
	return out


## Flood from cell s over free cells (state 1), marking `seen`. Returns [cells, mean local point
## (plus `origin`), whether it touched the disc's rim or water (a state-0 neighbour)].
static func _flood(state: PackedByteArray, seen: PackedByteArray, n: int, s: int, origin: Vector2) -> Array:
	var stack := PackedInt32Array([s])
	seen[s] = 1
	var cnt: int = 0
	var sum := Vector2.ZERO
	var rim: bool = false
	while not stack.is_empty():
		var c: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		cnt += 1
		var cx: int = c % n
		var cz: int = floori(float(c) / n)
		sum += Vector2(cx * STEP, cz * STEP)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + d.x
			var nz: int = cz + d.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				rim = true
				continue
			var j: int = nz * n + nx
			if state[j] == 0:
				rim = true
			elif seen[j] == 0 and state[j] == 1:
				seen[j] = 1
				stack.append(j)
	return [cnt, sum / maxi(cnt, 1) + origin, rim]


## The tightest gap between two hinterland things that both block Lumi (footprint rectangles, in
## metres between their nearest edges), over everything decided so far: [gap m, world point].
static func tightest_gap(h: Hinterland) -> Array:
	var items: Array = []  # [origin, transform, size, -, kind]
	for c: int in h.decided_cells():
		for e: Array in h.decided(c):
			var xf: Transform3D = e[1]
			if int(e[0]) == Hinterland.K_TRACK:
				continue  # a road strip: flat, nothing to wedge against
			items.append([xf.origin, xf, e[2], c, int(e[0])])
	var best: float = INF
	var at := Vector3.ZERO
	var kinds: String = ""
	var tight: int = 0
	for i: int in items.size():
		var a: Array = items[i]
		for j: int in range(i + 1, items.size()):
			var b: Array = items[j]
			var dv: Vector3 = (b[0] as Vector3) - (a[0] as Vector3)
			if dv.length_squared() > 40.0 * 40.0 or int(a[3]) == int(b[3]):
				continue  # one hex's own yard (house, shed, fences) is laid out on purpose
			var g: float = Hinterland.rect_gap(a[1], a[2], b[1], b[2])
			if g < MIN_GAP_M:
				tight += 1
			if g < best:
				best = g
				at = ((a[0] as Vector3) + (b[0] as Vector3)) * 0.5
				kinds = "%s / %s" % [_kind_name(int(a[4])), _kind_name(int(b[4]))]
	return [best, at, kinds, tight, items.size()]


static func _kind_name(k: int) -> String:
	return str(Hinterland.ARCH[k][0]) if k >= 0 else Hinterland.PROPS[-k - 1]


## The dev flag: waits for the world, picks the spots, walks each, prints and quits.
static func run_dev(so: SliceOrbit, h: Hinterland) -> void:
	var tree: SceneTree = so.w.get_tree()
	if h == null:
		print("[hwalk] FAIL: no hinterland")
		tree.quit(1)
		return
	var p: Patch = so.w.get("patch")
	var g: OrbitPlanet = so.globe
	await tree.create_timer(8.0).timeout
	for k: int in 600:  # the first ring of hexes is decided a few hundred a frame
		if h.is_settled():
			break
		await tree.process_frame
	var spots: Array[Vector3] = []
	if DevHooks.has("hinter-walk-at"):
		var sp: PackedStringArray = DevHooks.get_s("hinter-walk-at", "400,0").split(",")
		spots.append(g.terrain.local_to_dir(g.start_cell(), float(sp[0]), float(sp[1]) if sp.size() > 1 else 0.0) * g.terrain.R)
	else:
		spots = _dense_spots(h, int(DevHooks.get_f("hinter-walk-spots", 4.0)))
	if spots.is_empty():
		print("[hwalk] FAIL: no hinterland buildings in view of the start town")
		tree.quit(1)
		return
	var gap: Array = tightest_gap(h)
	var fails: int = 0
	for s: Vector3 in spots:
		var tr_: TargetReach = TargetReach.for_field(g.field)
		var stand: Vector3 = tr_.open_spot(s) if tr_ else g.terrain.ground(s.normalized())
		p.place_on_sphere(stand + stand.normalized() * 0.3, p.forward())
		p.velocity = Vector3.ZERO
		await tree.create_timer(6.0).timeout  # junk, hexes and colliders stream in round him
		for k2: int in 600:
			if h.is_settled():
				break
			await tree.process_frame
		h.refresh_colliders(p.global_position)
		for k3: int in 3:
			await tree.physics_frame
		var t0: int = Time.get_ticks_msec()
		var r: Dictionary = run(h, g.terrain, g.field, stand)
		var loc: Vector2 = _local_m(g, stand)
		var pk: PackedStringArray = []
		for e: Array in (r["pockets"] as Array).slice(0, 4):
			pk.append("%d m2@(%.0f,%.0f)" % [int(e[0]), (e[1] as Vector2).x, (e[1] as Vector2).y])
		print("[hwalk] spot (%.0f, %.0f): %d m2 free, %d m2 reached, %d m2 under buildings and props, shut %s, pockets %d%s, junk %d pieces / %d unreachable%s (%d ms) %s" % [
			loc.x, loc.y, int(r["free_m2"]), int(r["reached_m2"]), int(r["solid_m2"]), "none" if (r["shut"] as PackedStringArray).is_empty() else ",".join(r["shut"]),
			(r["pockets"] as Array).size(), "" if pk.is_empty() else " (" + ", ".join(pk) + ")", int(r["pieces"]), int(r["bad_pieces"]),
			"" if (r["bad_at"] as Array).is_empty() else " at " + str(r["bad_at"]), Time.get_ticks_msec() - t0, "ok" if r["pass"] else "FAIL"])
		fails += 0 if r["pass"] else 1
	var gap_ok: bool = int(gap[3]) == 0
	var gl: Vector2 = _local_m(g, gap[1])
	print("[hwalk] %d footprints in view; tightest gap %.2f m (%s) at (%.0f, %.0f)%s" % [int(gap[4]), float(gap[0]), str(gap[2]), gl.x, gl.y,
		"" if gap_ok else "; %d pairs under %.1f m (Lumi can wedge)" % [int(gap[3]), MIN_GAP_M]])
	print("[hwalk] %s" % ("PASS" if fails == 0 and gap_ok else "FAIL"))
	tree.quit(0 if fails == 0 and gap_ok else 1)


## Up to `count` spots, the densest building clusters first, at least 120 m apart.
static func _dense_spots(h: Hinterland, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for c: int in h.decided_cells():
		for e: Array in h.decided(c):
			if int(e[0]) >= 0:
				pts.append((e[1] as Transform3D).origin)
	var scored: Array = []
	for a: Vector3 in pts:
		var nb: int = 0
		for b: Vector3 in pts:
			if a.distance_squared_to(b) < 45.0 * 45.0:
				nb += 1
		scored.append([nb, a])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) > int(y[0]))
	var out: Array[Vector3] = []
	for s: Array in scored:
		var far: bool = true
		for o: Vector3 in out:
			if o.distance_to(s[1]) < 120.0:
				far = false
		if far:
			out.append(s[1])
			if out.size() >= count:
				break
	return out


## Start-site metres (x east, z south; as --orbit-spawn=x,z) of a world point.
static func _local_m(g: OrbitPlanet, pos: Vector3) -> Vector2:
	var u: Vector3 = g.grid.centers[g.start_cell()]
	var east: Vector3 = Vector3.UP.cross(u).normalized()
	var south: Vector3 = u.cross(east).normalized() * -1.0
	var d: Vector3 = pos.normalized()
	var t: Vector3 = d - u * d.dot(u)
	if t.length() < 0.000001:
		return Vector2.ZERO
	t = t.normalized() * acos(clampf(d.dot(u), -1.0, 1.0)) * g.grid.radius_m
	return Vector2(t.dot(east), t.dot(south))
