class_name SphereField
extends HexField
## [orbit] Phase A: the HexField API on the walkable globe, so Patch, the HUD and the depot run
## unchanged on a round planet. Hex ids are SphereGrid cell ids (163,842 at level 7). Junk lives
## as numbers in SphereCells (junk left per cell); real scoopable pieces are made only for cells
## that enter a near ring (materialize), deterministic per cell, and written back as the cell's
## junk fraction when scooped. Positions are world points on the sphere; "up" is radial.
## Phase B replaces the slice's HexField with this (parts, piles, landmarks, biomes).

const FULL_PIECES: int = 70  # pieces on an untouched 10 m hex (the flat districts' density)

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var piece_xf: Array[Transform3D] = []
var materialized := PackedByteArray()
var _cell_pieces: Dictionary = {}  # cell -> PackedInt32Array
var _type_w: Array[float] = []
var _type_wsum: float = 0.0
var _lift_cache: Dictionary = {}  # model id -> [upright lift, lying lift]


func _init(p_grid: SphereGrid, p_terrain: SphereTerrain, p_cells: SphereCells, p_seed: int = 4471) -> void:
	super(0, 10.0, p_seed)
	grid = p_grid
	terrain = p_terrain
	cells = p_cells
	var n: int = grid.cell_count()
	hex_total.resize(n)
	hex_left.resize(n)
	hex_clean.resize(n)
	hex_hub.resize(n)
	hex_water.resize(n)
	materialized.resize(n)
	junk_hex_count = 0
	cleaned_count = 0
	for i: int in n:
		var water: bool = cells.state[i] == 5
		hex_water[i] = 1 if water else 0
		hex_hub[i] = 1 if cells.has_flag(i, SphereCells.F_SITE) and not cells.is_dirty(i) else 0
		hex_total[i] = 1.0
		hex_left[i] = cells.junk[i] if cells.is_dirty(i) else 0.0
		hex_clean[i] = 0 if cells.is_dirty(i) else 1
		if not water and hex_hub[i] == 0:
			junk_hex_count += 1
			if hex_clean[i] == 1:
				cleaned_count += 1
	for id: String in Economy.junk_ids:
		var w: float = float(Economy.junk_types[id].get("weight", 1.0))
		_type_w.append(w)
		_type_wsum += w


func hex_count() -> int:
	return grid.cell_count()


func hex_center(id: int) -> Vector3:
	return terrain.ground(grid.centers[id])


func hex_at(world: Vector3) -> int:
	return grid.cell_at(world)


func is_water(id: int) -> bool:
	return id >= 0 and hex_water[id] == 1


func up_at(p: Vector3) -> Vector3:
	return p.normalized()


func hexes_near(pos: Vector3, ring: int = 1) -> Array[int]:
	var out: Array[int] = []
	for c: int in grid.cells_around(grid.cell_at(pos), ring):
		out.append(c)
	return out


func pieces_in(cell: int) -> PackedInt32Array:
	return _cell_pieces.get(cell, PackedInt32Array())


## Makes the scoopable pieces of a cell (once). Count follows the cell's junk left, so a hex the
## crews half cleaned shows half its junk. Returns the new piece ids.
func materialize(cell: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if materialized[cell] == 1:
		return out
	materialized[cell] = 1
	if not cells.is_dirty(cell) or hex_water[cell] == 1:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, 911])
	var left: float = cells.junk[cell]
	var count: int = int(round(FULL_PIECES * left))
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	var vol_sum: float = 0.0
	for k: int in count:
		var r: float = sqrt(rng.randf()) * hex_size * 0.92
		var a: float = rng.randf() * TAU
		var d: Vector3 = (ctr + (f.x * cos(a) + f.z * sin(a)) * (r / grid.radius_m)).normalized()
		var ti: int = _pick_type(rng)
		var models: Array = Economy.junk_types[Economy.junk_ids[ti]].get("models", [])
		var mdl: Dictionary = _pick_model(rng, models) if not models.is_empty() else {}
		var mid: String = str(mdl.get("id", ""))
		var vol: float = float(mdl.get("vol", 0.5))
		var lie: bool = rng.randf() < float(mdl.get("lie", 0.3))
		var s: float = rng.randf_range(0.9, 1.1)
		var lf: Basis = SphereGrid.frame(d)
		var b := Basis(lf.y, rng.randf() * TAU) * lf
		if lie:
			b = Basis(b.x, PI * 0.5) * b
		b = b.scaled(Vector3.ONE * s)
		var lift: float = float(_lifts(mid)[1 if lie else 0])
		var pos: Vector3 = terrain.ground(d) + d * (lift * s - 0.02)
		var pid: int = piece_pos.size()
		piece_pos.append(pos)
		piece_type.append(ti)
		piece_model.append(mid)
		piece_pose.append(1 if lie else 0)
		piece_vol.append(vol)
		piece_hex.append(cell)
		piece_yaw.append(0.0)
		piece_scale.append(s)
		piece_tilt.append(0.0)
		piece_embed.append(0.0)
		piece_alive.append(1)
		piece_xf.append(Transform3D(b, pos))
		out.append(pid)
		vol_sum += vol
	_cell_pieces[cell] = out
	# The cell's ledger in volume: total so that left / total stays the cell's junk fraction.
	hex_left[cell] = vol_sum
	hex_total[cell] = vol_sum / maxf(left, 0.01)
	return out


func _lifts(mid: String) -> Array:
	if not _lift_cache.has(mid):
		var l: Array = [0.0, 0.0]
		if mid != "" and AssetLib.has_model(mid):
			var bb: AABB = AssetLib.model_aabb(mid)
			l = [-bb.position.y, bb.size.z * 0.5]
		_lift_cache[mid] = l
	return _lift_cache[mid]


func _pick_type(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf() * _type_wsum
	for i: int in _type_w.size():
		r -= _type_w[i]
		if r <= 0.0:
			return i
	return _type_w.size() - 1


## Robots or crews took junk off a materialized cell: remove pieces down to `left` (0..1).
## Returns the removed piece ids (the view hides them).
func reduce_to(cell: int, left: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	if materialized[cell] == 0:
		return out
	for pid: int in pieces_in(cell):
		if removed_fraction(cell) >= 1.0 - left - 0.001:
			break
		if piece_alive[pid] == 1:
			remove_piece(pid)
			out.append(pid)
	return out


## Pieces in cells already removed while the cell was not materialized never existed; a cell
## whose numbers say clean but whose ledger says otherwise is settled here.
func settle(cell: int) -> void:
	if materialized[cell] == 0:
		hex_left[cell] = cells.junk[cell] if cells.is_dirty(cell) else 0.0
		hex_total[cell] = 1.0
	if not cells.is_dirty(cell) and hex_clean[cell] == 0:
		hex_clean[cell] = 1
		cleaned_count += 1


func find_scoop_target(origin: Vector3, forward: Vector3, reach: float, width: float) -> int:
	var u: Vector3 = origin.normalized()
	var fwd: Vector3 = (forward - u * forward.dot(u)).normalized()
	var right: Vector3 = fwd.cross(u)
	var best: int = -1
	var best_d: float = INF
	var near: Dictionary = {}
	for o: Vector3 in [Vector3.ZERO, fwd * reach, fwd * reach * 0.5 + right * width, fwd * reach * 0.5 - right * width]:
		near[hex_at(origin + o)] = true
	for hid: int in near:
		if locked.has(hid):
			continue
		for pid: int in pieces_in(hid):
			if piece_alive[pid] == 0:
				continue
			var d: Vector3 = piece_pos[pid] - origin
			var z: float = d.dot(fwd)
			if z < -0.3 or z > reach:
				continue
			if absf(d.dot(u)) > 2.5:
				continue
			var x: float = absf(d.dot(right))
			if x > width * 0.5 + maxf(z, 0.0) * 0.25:
				continue
			var dist: float = z * z + x * x * 1.5
			if dist < best_d:
				best_d = dist
				best = pid
	return best


func pieces_within(pos: Vector3, r: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2: float = r * r
	for hid: int in hexes_near(pos, 1 + int(r / hex_size)):
		if locked.has(hid):
			continue
		for pid: int in pieces_in(hid):
			if piece_alive[pid] == 1 and piece_pos[pid].distance_squared_to(pos) <= r2:
				out.append(pid)
	return out


func nearest_alive(pos: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for ring: int in range(1, 8):
		for hid: int in hexes_near(pos, ring):
			for pid: int in pieces_in(hid):
				if piece_alive[pid] == 0:
					continue
				var d: float = piece_pos[pid].distance_squared_to(pos)
				if d < best_d:
					best_d = d
					best = pid
		if best >= 0:
			return best
	return best


func ground_height(_id: int, _pos: Vector3) -> float:
	return 0.0
