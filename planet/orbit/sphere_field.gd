class_name SphereField
extends HexField
## [orbit] Phase A: the HexField API on the walkable globe, so Patch, the HUD and the depot run
## unchanged on a round planet. Hex ids are SphereGrid cell ids (163,842 at level 7). Junk lives
## as numbers in SphereCells (junk left per cell); real scoopable pieces are made only for cells
## that enter a near ring (materialize), deterministic per cell, and written back as the cell's
## junk fraction when scooped. Positions are world points on the sphere; "up" is radial.
## Phase B replaces the slice's HexField with this (parts, piles, landmarks, biomes).
## [orbB] Field parity, all per cell id and deterministic per (seed, cell), made on materialize:
## - parts: buried robot parts at the flat field's chance per hex (data/parts.json), found by
##   the detector (nearest_part searches nearby cells only); found parts persist by cell key.
## - piles: 0-2 junk mounds per land cell, Vector4(x, z, radius, height) in the cell's own frame
##   (SphereGrid.frame at its centre); pieces sit on them and settle as the cell is cleaned.
## - landmarks: big wreck props at the flat districts' rate per hex (Economy.landmarks_for).
## - locked: cells of a locked biome (locked_biomes) can't be scooped until unlocked.
## - floating junk on water cells with junk left (lakes count as junk hexes, as on the flat).

const FULL_PIECES: int = 70  # pacing units of an untouched 10 m hex (robots / offline: SphereOffline.UNITS_PER_CELL)
## [v1world] Pieces drawn on an untouched land cell (owner, Nov 8: "way more trash, like the flat
## world"; the flat field lays 260-420 a hex, landfill x2.2). The ledger is in volume (FLAT_HEX_VOL),
## so more pieces are each lighter: a cell still takes the flat hex's scoop pulses to clean.
const DRAW_PIECES: int = 200
## [v1world] Share of loose ground pieces swapped for a black trash bag (the flat sidewalks' bags).
const BAG_SHARE: float = 0.08
const FLOAT_PIECES: int = 22  # floaters on an untouched water cell
const FLAT_DISTRICT_HEXES: float = 61.0  # a radius-4 flat district: landmark counts are per one of these
## [orbB] Pacing (owner decision (b), Nov 8): ~70 light pieces per cell, but a cell holds a flat hex's
## total junk volume, so hexes flip, pay and level at the flat game's pace. Measured on the flat
## Old Town gen-2 field: 407 volume per junk hex (478 pieces of 0.85). A scoop pulse there takes a
## piece and its little cluster, ~1.22 volume: here Lumi takes a heavy piece in bites of that size
## (bite()), so the scoop speed per volume and the chest/bale granularity stay the flat game's.
## Pieces keep their model's size; only their volume (the ledger) is scaled.
const FLAT_HEX_VOL: float = 407.0
const FLAT_LAKE_VOL: float = 75.0  # a flat lake hex: 70-110 floaters of ~0.8
const FLAT_BITE_VOL: float = 1.22
const PILE_EMBED := Vector2(0.55, 1.02)
const FLOATERS: Array = [["plastic", "plastic_bottle_gallon"], ["plastic", "bleach_bottle"], ["plastic", "trashbag"], ["plastic", "multi_cleaner_bottle"], ["rubber", "rubber_duck_toy"], ["rubber", "old_tyre"], ["rubber", "dirty_football"], ["glass", "wine_bottles_01"], ["paper", "cardboard_box_01"], ["plastic", "plastic_crate_01"]]
const LYING_FLOATERS: Array = ["plastic_bottle_gallon", "bleach_bottle", "multi_cleaner_bottle", "old_tyre", "wine_bottles_01"]

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var piece_xf: Array[Transform3D] = []
var materialized := PackedByteArray()
var _type_w: Array[float] = []
var _type_wsum: float = 0.0
var _lift_cache: Dictionary = {}  # model id -> [upright lift, lying lift]
var piece_lift := PackedFloat32Array()  # [orbB] rest offset above the ground (before the pile)
var piece_model_vol := PackedFloat32Array()  # [orbB] the model's own volume (piece_vol is scaled for pacing)
var parts_def: Dictionary = {}  # data/parts.json (set before cells materialize; Economy.parts by default)
var landmark_defs: Array = []   # [{id, count}] (Economy.landmarks_for(biome))
var locked_biomes: Dictionary = {}  # biome index -> true: those cells stay locked
var _cell_parts: Dictionary = {}  # cell -> PackedInt32Array of part ids
var _part_key := PackedInt32Array()  # part id -> cell * 4 + k (save key)
var _found_keys: Dictionary = {}  # saved found parts (cell * 4 + k -> true), applied on materialize
var _cell_landmark: Dictionary = {}  # cell -> index into landmarks
var _saved_unlocked: Dictionary = {}  # cells of a locked biome a save says are open
## [v1yard] func(dir: Vector3) -> bool: ground where no piece may lie (the start yard's pad, the
## pod, building footprints; YardKeepOut). Pieces that land there are re-rolled, then dropped.
var keep_out: Callable
var pile_block: Callable  # [v5look] (cell) -> bool: no junk mounds on this cell (the hinterland's road hexes)
var before_lay: Callable  # [v6qa] (cell) -> void: called before a land cell's pieces are laid (the hinterland decides its roads there)
## [v1yard] Cells with no big items (cell -> true): the start's cells, as the flat game's first hexes.
var small_only: Dictionary = {}
const KEEP_OUT_TRIES: int = 8


func _init(p_grid: SphereGrid, p_terrain: SphereTerrain, p_cells: SphereCells, p_seed: int = 4471) -> void:
	super(0, 10.0, p_seed)
	grid = p_grid
	terrain = p_terrain
	cells = p_cells
	clean_threshold = 1.0 - SphereCells.CLEAN_LEFT  # [v2feel] the shared clean rule
	var n: int = grid.cell_count()
	hex_total.resize(n)
	hex_left.resize(n)
	hex_clean.resize(n)
	hex_hub.resize(n)
	hex_water.resize(n)
	materialized.resize(n)
	hex_piles.resize(n)
	hex_piles.fill([])  # shared empty list; materialize assigns a cell its own
	hex_pieces.resize(n)  # [orbB] the HexField layout, so flat code that walks hex_pieces works here
	hex_pieces.fill(PackedInt32Array())
	junk_hex_count = 0
	cleaned_count = 0
	var hub_flags: bool = false  # [orbB] globes that mark hub ground with F_HUB (the orbit slice); else phase A's rule
	for i: int in n:
		if cells.flags[i] & SphereCells.F_HUB:
			hub_flags = true
			break
	# [orbE] Load time: the per-cell pass inlines is_dirty / has_flag / water_dirty over local packed
	# arrays (8 method calls per cell were ~3 s on Anvil's 655k cells). Same rules as before:
	# dirty = JUNK state with junk > SphereCells.CLEAN_LEFT; a lake with floating junk is a junk hex.
	var st: PackedByteArray = cells.state
	var jk: PackedFloat32Array = cells.junk
	var fl: PackedByteArray = cells.flags
	hex_total.fill(1.0)
	for i: int in n:
		var j: float = jk[i]
		if st[i] == 5:
			hex_water[i] = 1
			if j > SphereCells.CLEAN_LEFT:
				hex_left[i] = j
				junk_hex_count += 1
			else:
				hex_left[i] = 0.0
				hex_clean[i] = 1
			continue
		var dirty: bool = st[i] == 0 and j > SphereCells.CLEAN_LEFT
		var f_i: int = fl[i]
		var hub: bool = (f_i & SphereCells.F_HUB) != 0 or ((f_i & SphereCells.F_SITE) != 0 and not dirty and not hub_flags)  # [orbB] F_HUB persists
		hex_hub[i] = 1 if hub else 0
		if dirty:
			hex_left[i] = j
		else:
			hex_clean[i] = 1
		if not hub:
			junk_hex_count += 1
			if not dirty:
				cleaned_count += 1
	for id: String in Economy.junk_ids:
		var w: float = float(Economy.junk_types[id].get("weight", 1.0))
		_type_w.append(w)
		_type_wsum += w
	parts_def = Economy.parts
	landmark_defs = Economy.landmarks_for("")
	_bag_type = Economy.junk_ids.find("plastic") if AssetLib.has_model("trashbag") else -1  # [v1world]


var _bag_type: int = -1  # [v1world] junk type index of the trash bags (plastic)


func water_dirty(i: int) -> bool:
	return cells.state[i] == 5 and cells.junk[i] > SphereCells.CLEAN_LEFT


## Dirty for the field: land junk or floating junk.
func cell_dirty(i: int) -> bool:
	return cells.is_dirty(i) or water_dirty(i)


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
	return hex_pieces[cell]


## Makes the scoopable pieces of a cell (once), with its buried parts, landmark and piles.
## Count follows the cell's junk left, so a hex the crews half cleaned shows half its junk.
## Returns the new piece ids.
func materialize(cell: int) -> PackedInt32Array:
	if _mz_cell == cell:  # [v5load] half made by materialize_step: finish it now
		return _mz_run(0)
	if _mz_cell >= 0:
		_mz_run(0)
	if not _mz_begin(cell):
		return _mz_done
	return _mz_run(0)


# [v5load] A cell's pieces in steps. Laying ~70 pieces (keep-out tests, heights, bases) is 12-40 ms,
# and the near ring's deferred fill (OrbitPlanet._drain_fill) did a whole cell at a time: a long
# frame every few metres walked. materialize_step lays one cell across frames under a time budget;
# materialize() is the same work in one call (and finishes a half-made cell). One cell at a time is
# in progress; until it is done its pieces are not in hex_pieces, so nothing sees half a cell.
var _mz_cell: int = -1
var _mz: Dictionary = {}
var _mz_done := PackedInt32Array()


## Lays cell's pieces for at most budget_us this call. True once the cell is made.
func materialize_step(cell: int, budget_us: int) -> bool:
	if _mz_cell != cell:
		if materialized[cell] == 1:
			return true
		if _mz_cell >= 0:
			_mz_run(0)
		if not _mz_begin(cell):
			return true
	_mz_run(budget_us)
	return _mz_cell != cell


## The part before the pieces. False when the cell needs none (made already, water, clean).
func _mz_begin(cell: int) -> bool:
	var out := PackedInt32Array()
	_mz_done = out
	if materialized[cell] == 1:
		return false
	materialized[cell] = 1
	if locked_biomes.has(int(cells.biome[cell])) and not _saved_unlocked.has(cell):
		locked[cell] = true
	if hex_water[cell] == 1:
		return _float_begin(cell)
	if before_lay.is_valid():  # [v6qa]
		before_lay.call(cell)
	if hex_hub[cell] == 0:
		_roll_parts(cell)
		if not cells.has_flag(cell, SphereCells.F_SITE):  # [orbD] no wreck landmarks in a hub site's streets
			_roll_landmark(cell)
	if not cells.is_dirty(cell):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, 911])
	var left: float = cells.junk[cell]
	var count: int = int(round(DRAW_PIECES * left))  # [v1world]
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	var piles: Array = [] if cells.has_flag(cell, SphereCells.F_SITE) or (pile_block.is_valid() and bool(pile_block.call(cell))) else _roll_piles(cell)  # [orbD] mounds wedged against kerbs and kit walls stalled Lumi; site cells keep loose junk only
	hex_piles[cell] = piles
	var lm: Dictionary = landmarks[_cell_landmark[cell]] if _cell_landmark.has(cell) else {}
	var lm_at: Vector2 = cell_local(cell, lm["pos"]) if not lm.is_empty() else Vector2.ZERO
	var lm_clear: float = float(lm.get("clear", 2.2)) + 0.3
	materialized[cell] = 0  # until its pieces are all laid (_mz_run), the cell counts as not made
	_mz_cell = cell
	_mz = {"rng": rng, "left": left, "count": count, "ctr": ctr, "f": f, "piles": piles, "lm": lm, "lm_at": lm_at, "lm_clear": lm_clear,
		"vol_sum": 0.0, "k": 0, "out": out}
	return true


func _mz_run(budget_us: int) -> PackedInt32Array:
	if _mz.has("float"):
		return _float_run(budget_us)
	var t0: int = Time.get_ticks_usec()
	var cell: int = _mz_cell
	var rng: RandomNumberGenerator = _mz["rng"]
	var left: float = _mz["left"]
	var count: int = _mz["count"]
	var ctr: Vector3 = _mz["ctr"]
	var f: Basis = _mz["f"]
	var piles: Array = _mz["piles"]
	var lm: Dictionary = _mz["lm"]
	var lm_at: Vector2 = _mz["lm_at"]
	var lm_clear: float = _mz["lm_clear"]
	var vol_sum: float = _mz["vol_sum"]
	var out: PackedInt32Array = _mz["out"]
	var k: int = int(_mz["k"]) - 1
	while k + 1 < count:
		k += 1
		if budget_us > 0 and (k & 3) == 0 and Time.get_ticks_usec() - t0 > budget_us:
			_mz["k"] = k
			_mz["vol_sum"] = vol_sum
			_mz["out"] = out
			return out
		var r: float = sqrt(rng.randf()) * hex_size * 0.92
		var a: float = rng.randf() * TAU
		var lx: float = cos(a) * r
		var lz: float = sin(a) * r
		var in_pile: bool = not piles.is_empty() and rng.randf() < 0.6
		if in_pile:  # on a heap: inside its footprint
			var pile: Vector4 = piles[rng.randi() % piles.size()]
			var rr: float = sqrt(rng.randf()) * pile.z
			lx = pile.x + cos(a) * rr
			lz = pile.y + sin(a) * rr
		if not lm.is_empty():  # pushed off the wreck, radially from it
			var dv := Vector2(lx, lz) - lm_at
			if dv.length() < lm_clear:
				dv = (dv if dv.length() > 0.01 else Vector2(cos(a), sin(a))).normalized() * lm_clear
				lx = lm_at.x + dv.x
				lz = lm_at.y + dv.y
		var d: Vector3 = (ctr + (f.x * lx + f.z * lz) / grid.radius_m).normalized()
		if keep_out.is_valid() and bool(keep_out.call(d)):  # [v1yard] off the pad: another spot in the cell, else none
			var tries: int = 0
			while tries < KEEP_OUT_TRIES and bool(keep_out.call(d)):
				var r2: float = sqrt(rng.randf()) * hex_size * 0.92
				var a2: float = rng.randf() * TAU
				d = (ctr + (f.x * cos(a2) * r2 + f.z * sin(a2) * r2) / grid.radius_m).normalized()
				tries += 1
			if bool(keep_out.call(d)):
				continue
			in_pile = false
		var ti: int = _pick_type(rng)
		var models: Array = Economy.junk_types[Economy.junk_ids[ti]].get("models", [])
		var mdl: Dictionary = _pick_model(rng, models) if not models.is_empty() else {}
		if small_only.has(cell) and float(mdl.get("vol", 0.5)) >= Pace.MEDIUM_VOL:  # [v1yard] no big items at the start; [v2feel] nor medium: all liftable at Lift 0
			mdl = _tiny_model(Economy.junk_types[Economy.junk_ids[ti]], Economy.junk_ids[ti], piece_pos.size())
		var mid: String = str(mdl.get("id", ""))
		var vol: float = float(mdl.get("vol", 0.5))
		var lie: bool = rng.randf() < float(mdl.get("lie", 0.3))
		if not in_pile and rng.randf() < BAG_SHARE and _bag_type >= 0:  # [v1world] black bags everywhere, as on the flat streets
			ti = _bag_type
			mid = "trashbag"
			vol = 1.4
			lie = false
		var sc: float = rng.randf_range(0.9, 1.1)
		var lf: Basis = SphereGrid.frame(d)
		var b := Basis(lf.y, rng.randf() * TAU) * lf
		if lie:
			b = Basis(b.x, PI * 0.5) * b
		if in_pile:  # heaped junk leans every which way
			b = Basis(b.z, rng.randf_range(-0.5, 0.5)) * b
		b = b.scaled(Vector3.ONE * sc)
		var lift: float = float(_lifts(mid)[1 if lie else 0]) * sc - 0.02
		var pid: int = _add_piece(cell, d, b, lift, ti, mid, 1 if lie else 0, vol, sc, rng.randf_range(PILE_EMBED.x, PILE_EMBED.y) if in_pile else 0.0)
		out.append(pid)
		vol_sum += vol
	hex_pieces[cell] = out
	# The cell's ledger in volume: total so that left / total stays the cell's junk fraction.
	_scale_cell(out, vol_sum, FLAT_HEX_VOL * left)
	hex_left[cell] = FLAT_HEX_VOL * left
	hex_total[cell] = FLAT_HEX_VOL
	materialized[cell] = 1
	_mz_cell = -1
	_mz = {}
	_mz_done = out
	if _mz_recheck:  # [v6qa] (before the view draws them)
		_mz_recheck = false
		relocate_blocked(cell)
	return out


## [v2feel] A small-class model (liftable at Lift Strength 0) of a junk type, else a trash bag.
func _tiny_model(t: Dictionary, type_id: String, pid: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, pid, 4142])
	var pool: Array = []
	for m: Variant in (biome_set.get("models", {}) as Dictionary).get(type_id, []) + t.get("models", []):
		if float((m as Dictionary).get("vol", 1.0)) < Pace.MEDIUM_VOL:
			pool.append(m)
	if pool.is_empty():
		return {"id": "trashbag", "vol": 1.4, "lie": 0.0}
	return _pick_model(r, pool)


## [v2feel] Owner item 36: a cell that reaches 95% cleared is clean (SphereCells.CLEAN_LEFT) and its
## leftover pieces sweep away. Every removal path (Lumi, robots, outposts, fauna) goes through here;
## the junk view hides the swept pieces with a poof (hex_swept). Their cubes are simply dropped.
signal hex_swept(cell: int, pids: PackedInt32Array)


func remove_piece(pid: int) -> bool:
	var flipped: bool = super(pid)
	if flipped:
		sweep_cell(piece_hex[pid])
	return flipped


## Removes what is left of a clean cell's pieces. Returns their ids.
func sweep_cell(cell: int) -> PackedInt32Array:
	var gone := PackedInt32Array()
	for p: int in pieces_in(cell):
		if piece_alive[p] == 1:
			piece_alive[p] = 0
			gone.append(p)
	hex_left[cell] = 0.0
	if not gone.is_empty():
		hex_swept.emit(cell, gone)
	return gone


func visual_vol(pid: int) -> float:
	return piece_model_vol[pid]


## Scales a cell's new pieces so their volumes sum to `target` (sizes on screen are untouched).
func _scale_cell(pids: PackedInt32Array, raw_sum: float, target: float) -> void:
	if pids.is_empty() or raw_sum <= 0.0:
		return
	var k: float = target / raw_sum
	for pid: int in pids:
		piece_vol[pid] *= k


## [orbB] Lumi's scoop takes a heavy piece a bite at a time: up to `max_vol` of its volume. Returns
## the volume taken; when it is the piece's last, the caller removes the piece (collect_piece).
func bite(pid: int, max_vol: float = FLAT_BITE_VOL) -> float:
	_last_bite_whole = false
	if pid < 0 or pid >= piece_alive.size() or piece_alive[pid] == 0:
		return 0.0
	var v: float = piece_vol[pid]
	if v <= max_vol * 1.25:  # the rest goes in one go (no crumbs)
		_last_bite_whole = true
		return v
	piece_vol[pid] = v - max_vol
	var id: int = piece_hex[pid]
	hex_left[id] = maxf(0.0, hex_left[id] - max_vol)
	return max_vol


var _last_bite_whole: bool = false


## Whether the last bite() took what was left of the piece (the caller then removes it).
func is_whole_take(_pid: int, _taken: float) -> bool:
	return _last_bite_whole


func _add_piece(cell: int, d: Vector3, b: Basis, lift: float, ti: int, mid: String, pose: int, vol: float, sc: float, embed: float) -> int:
	var pid: int = piece_pos.size()
	piece_pos.append(Vector3.ZERO)
	piece_type.append(ti)
	piece_model.append(mid)
	piece_pose.append(pose)
	piece_vol.append(vol)
	piece_size.append(size_class(vol))
	piece_hex.append(cell)
	piece_yaw.append(0.0)
	piece_scale.append(sc)
	piece_tilt.append(0.0)
	piece_embed.append(embed)
	piece_alive.append(1)
	piece_lift.append(lift)
	piece_model_vol.append(vol)
	piece_xf.append(Transform3D(b, Vector3.ZERO))
	_seat(pid, d)
	return pid


## Puts a piece on the ground (or the lake surface, or its pile) along direction d.
func _seat(pid: int, d: Vector3) -> void:
	var cell: int = piece_hex[pid]
	var base: Vector3 = terrain.ground(d)
	if hex_water[cell] == 1:
		base -= d * SphereWater.BELOW_LAND  # [v1world] floaters ride the lake surface (was the bed, water_drop down)
	var pos: Vector3 = base + d * piece_lift[pid]
	if piece_embed[pid] > 0.0:
		pos += d * ground_height(cell, base) * piece_embed[pid]
	piece_pos[pid] = pos
	var xf: Transform3D = piece_xf[pid]
	xf.origin = pos
	piece_xf[pid] = xf


## [v6qa] Keep-out added after a cell was made (the hinterland decides its roads and buildings a
## few hundred hexes a frame; a dev spawn or a save loaded right there makes the near cells first):
## every live piece of the cell that now lies in the keep-out moves to a free spot in the cell, or,
## with none, goes as if it was never laid (out of the ledger's total and left alike, so the cell's
## junk fraction holds). Returns [moved pids, dropped pids]; the caller updates the view.
## A cell still being laid (materialize_step) is checked when its last piece is down.
func relocate_blocked(cell: int) -> Array:
	var moved := PackedInt32Array()
	var dropped := PackedInt32Array()
	if cell == _mz_cell:
		_mz_recheck = true
		return [moved, dropped]
	if not keep_out.is_valid() or materialized[cell] == 0 or hex_water[cell] == 1:
		return [moved, dropped]
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	for pid: int in pieces_in(cell):
		if piece_alive[pid] == 0:
			continue
		var d0: Vector3 = piece_pos[pid].normalized()
		if not bool(keep_out.call(d0)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, pid, 6071])
		var d: Vector3 = d0
		for t: int in KEEP_OUT_TRIES * 2:
			var r: float = sqrt(rng.randf()) * hex_size * 0.92
			var a: float = rng.randf() * TAU
			d = (ctr + (f.x * cos(a) * r + f.z * sin(a) * r) / grid.radius_m).normalized()
			if not bool(keep_out.call(d)):
				break
		if bool(keep_out.call(d)):
			piece_alive[pid] = 0
			hex_left[cell] = maxf(0.0, hex_left[cell] - piece_vol[pid])
			hex_total[cell] = maxf(0.001, hex_total[cell] - piece_vol[pid])
			dropped.append(pid)
			continue
		var xf: Transform3D = piece_xf[pid]
		xf.basis = Basis(Quaternion(d0, d)) * xf.basis
		piece_xf[pid] = xf
		piece_embed[pid] = 0.0  # off its heap: on the plain ground
		_seat(pid, d)
		moved.append(pid)
	if not dropped.is_empty():  # out of the cell's list too (a Ledger drop revives dead pieces of a cell)
		var keep := PackedInt32Array()
		for pid: int in pieces_in(cell):
			if not dropped.has(pid):
				keep.append(pid)
		hex_pieces[cell] = keep
	return [moved, dropped]


var _mz_recheck: bool = false  # [v6qa] keep-out grew while the cell in progress was being laid


## Re-seat a cell's remaining pieces on its (shrinking) piles. Returns the pieces that moved.
func resettle(cell: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if (hex_piles[cell] as Array).is_empty():
		return out
	for pid: int in pieces_in(cell):
		if piece_alive[pid] == 1 and piece_embed[pid] > 0.0:
			_seat(pid, piece_pos[pid].normalized())
			out.append(pid)
	return out


## Pile height (m) at a world point of a cell: heaps shrink to 30% as the cell is cleaned.
func ground_height(id: int, pos: Vector3) -> float:
	if id < 0 or hex_clean[id] == 1 or (hex_piles[id] as Array).is_empty():
		return 0.0
	var l: Vector2 = cell_local(id, pos)
	var h: float = 0.0
	for pile: Vector4 in hex_piles[id]:
		var dd: float = Vector2(l.x - pile.x, l.y - pile.y).length() / pile.z
		if dd < 1.0:
			h = maxf(h, pile.w * sqrt(1.0 - dd * dd))
	return h * (0.3 + 0.7 * (1.0 - removed_fraction(id)))


## A world point in a cell's own frame (x east, z south, metres along the ground from its centre).
func cell_local(cell: int, pos: Vector3) -> Vector2:
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	var d: Vector3 = pos.normalized() - ctr
	return Vector2(d.dot(f.x), d.dot(f.z)) * grid.radius_m


## The surface frame of a pile (origin on the ground at its centre, y = local up).
func pile_transform(cell: int, pile: Vector4) -> Transform3D:
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	var d: Vector3 = (ctr + (f.x * pile.x + f.z * pile.y) / grid.radius_m).normalized()
	return Transform3D(SphereGrid.frame(d), terrain.ground(d))


func _roll_piles(cell: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, 31])
	var piles: Array = []
	var roll: float = rng.randf()
	var n: int = 0 if roll < 0.12 else (1 if roll < 0.6 else 2)  # [v1world] was 30% / 50% / 20%: heaps on most cells, as on the flat landfill
	for k: int in n:
		var pc := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35)) * hex_size
		piles.append(Vector4(pc.x, pc.y, rng.randf_range(1.7, 2.6), rng.randf_range(0.8, 1.5)))
	return piles


# --- [orbB] Parts ------------------------------------------------------------------------------

func _roll_parts(cell: int) -> void:
	var rar: Array = parts_def.get("rarities", [])
	var types: Array = parts_def.get("types", [])
	if rar.is_empty() or types.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, 21])
	var chance: float = float(parts_def.get("chance_per_hex", 0.14))
	var n: int = int(floor(chance)) + (1 if rng.randf() < chance - floor(chance) else 0)
	if n == 0:
		return
	var wsum: float = 0.0
	for r: Dictionary in rar:
		wsum += float(r["weight"])
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	var ids := PackedInt32Array()
	for k: int in mini(n, 4):
		var off := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * hex_size * 0.6
		var d: Vector3 = (ctr + (f.x * off.x + f.z * off.y) / grid.radius_m).normalized()
		var roll: float = rng.randf() * wsum
		var ri: int = 0
		for i: int in rar.size():
			roll -= float(rar[i]["weight"])
			if roll <= 0.0:
				ri = i
				break
		var key: int = cell * 4 + k
		ids.append(part_pos.size())
		part_pos.append(_part_ground(d))
		part_type.append(rng.randi() % types.size())
		part_rarity.append(ri)
		part_found.append(1 if _found_keys.has(key) else 0)
		_part_key.append(key)
	_cell_parts[cell] = ids


## [v4world] Owner playtest 3 #55: a buried part never lies inside a building, a lake, on steep
## ground or walled in: it moves to the nearest reachable open ground (TargetReach; no rng drawn,
## so the rolls stay as they were).
func _part_ground(d: Vector3) -> Vector3:
	var t: TargetReach = TargetReach.for_field(self)
	return t.open_spot(d) if t else terrain.ground(d)


## Nearest unfound part within range (or -1): only the cells around pos are searched.
func nearest_part(pos: Vector3, max_dist: float) -> int:
	var best: int = -1
	var best_d: float = max_dist
	for c: int in grid.cells_around(grid.cell_at(pos), int(ceil(max_dist / 17.3)) + 1):
		for i: int in _cell_parts.get(c, PackedInt32Array()):
			if part_found[i] == 1:
				continue
			var d: float = part_distance(i, pos)
			if d < best_d:
				best_d = d
				best = i
	return best


func part_distance(i: int, pos: Vector3) -> float:
	var a: Vector3 = part_pos[i]
	var up: Vector3 = a.normalized()
	var v: Vector3 = pos - a
	return (v - up * v.dot(up)).length()  # along the ground, like the flat x/z distance


func parts_in(cell: int) -> PackedInt32Array:
	return _cell_parts.get(cell, PackedInt32Array())


# --- [orbB] Landmarks --------------------------------------------------------------------------

func _roll_landmark(cell: int) -> void:
	if landmark_defs.is_empty() or not cells.is_dirty(cell):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, 7])
	var roll: float = rng.randf()
	for d: Dictionary in landmark_defs:
		roll -= float(d.get("count", 1)) / FLAT_DISTRICT_HEXES
		if roll > 0.0:
			continue
		var ctr: Vector3 = grid.centers[cell]
		var f: Basis = SphereGrid.frame(ctr)
		var off := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)) * hex_size * 0.4
		var dir: Vector3 = (ctr + (f.x * off.x + f.z * off.y) / grid.radius_m).normalized()
		var yaw: float = rng.randf() * TAU
		var model: String = str(d["id"])
		if model in ["covered_car", "concrete_road_barrier", "concrete_road_barrier_02"]:
			yaw = (PI * 0.5 if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.25, 0.25)
		var lf: Basis = SphereGrid.frame(dir)
		var clear: float = 2.2
		if AssetLib.has_model(model):
			var bb: AABB = AssetLib.model_aabb(model)
			clear = maxf(bb.size.x, bb.size.z) * 0.5 + 0.5
		_cell_landmark[cell] = landmarks.size()
		landmarks.append({"model": model, "pos": terrain.ground(dir), "yaw": yaw, "hex": cell, "clear": clear,
			"basis": Basis(lf.y, yaw) * lf})
		return


# --- [orbB] Floating junk ----------------------------------------------------------------------

func _materialize_floating(cell: int) -> PackedInt32Array:
	if not _float_begin(cell):
		return _mz_done
	return _float_run(0)


## [v5load] A lake cell's floating junk through the same stepper as land cells (_mz_run).
func _float_begin(cell: int) -> bool:
	var out := PackedInt32Array()
	_mz_done = out
	if not water_dirty(cell):
		return false
	var by_id: Dictionary = {}
	for i: int in Economy.junk_ids.size():
		by_id[Economy.junk_ids[i]] = i
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, 913])
	var left: float = cells.junk[cell]
	materialized[cell] = 0  # until its pieces are all laid
	_mz_cell = cell
	_mz = {"float": true, "rng": rng, "left": left, "count": int(round(FLOAT_PIECES * float_mult * left)), "by_id": by_id,
		"vol_sum": 0.0, "k": 0, "out": out}
	return true


func _float_run(budget_us: int) -> PackedInt32Array:
	var t0: int = Time.get_ticks_usec()
	var cell: int = _mz_cell
	var rng: RandomNumberGenerator = _mz["rng"]
	var left: float = _mz["left"]
	var count: int = _mz["count"]
	var by_id: Dictionary = _mz["by_id"]
	var vol_sum: float = _mz["vol_sum"]
	var out: PackedInt32Array = _mz["out"]
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	var k: int = int(_mz["k"]) - 1
	while k + 1 < count:
		k += 1
		if budget_us > 0 and (k & 3) == 0 and Time.get_ticks_usec() - t0 > budget_us:
			_mz["k"] = k
			_mz["vol_sum"] = vol_sum
			_mz["out"] = out
			return out
		var r: float = sqrt(rng.randf()) * hex_size * 0.92
		var a: float = rng.randf() * TAU
		var d: Vector3 = (ctr + (f.x * cos(a) + f.z * sin(a)) * (r / grid.radius_m)).normalized()
		var fl: Array = FLOATERS[rng.randi() % FLOATERS.size()]
		if fl[1] == "old_tyre" and small_only.has(cell):  # [v2feel] no heavy floaters at the start
			fl = FLOATERS[0]
		var tyre: bool = fl[1] == "old_tyre"
		var vol: float = 2.5 if tyre else 0.6 * rng.randf_range(0.8, 1.3)
		var sc: float = rng.randf_range(0.9, 1.1)
		var lie: bool = fl[1] in LYING_FLOATERS
		var lf: Basis = SphereGrid.frame(d)
		var b := Basis(lf.y, rng.randf() * TAU) * lf
		if lie:
			b = Basis(b.x, PI * 0.5) * b
		b = Basis(b.z, rng.randf_range(-0.3, 0.3)) * b
		b = b.scaled(Vector3.ONE * sc)
		var pid: int = _add_piece(cell, d, b, -0.06, int(by_id.get(fl[0], 0)), str(fl[1]), 1 if lie else 0, vol, sc, 0.0)
		out.append(pid)
		vol_sum += vol
	hex_pieces[cell] = out
	_scale_cell(out, vol_sum, FLAT_LAKE_VOL * float_mult * left)
	hex_left[cell] = FLAT_LAKE_VOL * float_mult * left
	hex_total[cell] = FLAT_LAKE_VOL * float_mult
	materialized[cell] = 1
	_mz_cell = -1
	_mz = {}
	_mz_done = out
	return out


# --- [orbB] Locked cells -----------------------------------------------------------------------

func unlock(cell: int) -> void:
	locked.erase(cell)


# --- [orbB] Persistence (inside GameState.orbit; the cells' junk lives in SphereCells) --------

func to_dict() -> Dictionary:
	var found := PackedInt32Array(_found_keys.keys())
	for i: int in part_found.size():
		if part_found[i] == 1 and not _found_keys.has(_part_key[i]):
			found.append(_part_key[i])
	found.sort()
	return {"seed": seed_value, "parts_found": _b64(found), "unlocked": _b64(PackedInt32Array(_unlocked_keys()))}


static func _b64(a: PackedInt32Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array()) if not a.is_empty() else ""


## Applies saved found parts and unlocked cells (before or after cells materialize).
func apply_dict(d: Dictionary) -> bool:
	if int(d.get("seed", seed_value)) != seed_value:
		return false
	_found_keys.clear()
	for k: int in Marshalls.base64_to_raw(str(d.get("parts_found", ""))).to_int32_array():
		_found_keys[k] = true
	for i: int in part_found.size():
		if _found_keys.has(_part_key[i]):
			part_found[i] = 1
	_saved_unlocked.clear()
	for c: int in Marshalls.base64_to_raw(str(d.get("unlocked", ""))).to_int32_array():
		_saved_unlocked[c] = true
		locked.erase(c)
	return true



## Cells of a locked biome that were unlocked (saved, so they stay open).
func _unlocked_keys() -> Array:
	var out: Array = _saved_unlocked.keys()
	if locked_biomes.is_empty():
		return out
	for c: int in grid.cell_count():
		if materialized[c] == 1 and locked_biomes.has(int(cells.biome[c])) and not locked.has(c) and not _saved_unlocked.has(c):
			out.append(c)
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
		hex_left[cell] = cells.junk[cell] if cell_dirty(cell) else 0.0
		hex_total[cell] = 1.0
	if not cell_dirty(cell) and hex_clean[cell] == 0:  # [orbB] lakes too
		hex_clean[cell] = 1
		cleaned_count += 1


func find_scoop_target(origin: Vector3, forward: Vector3, reach: float, width: float) -> int:
	return find_scoop_target_sized(origin, forward, reach, width, 99)


## [orbB] The scoop zone, skipping pieces above a size class (Pace's lift strength).
func find_scoop_target_sized(origin: Vector3, forward: Vector3, reach: float, width: float, max_size: int) -> int:
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
			if dist < best_d and (max_size >= 99 or piece_size[pid] <= max_size):
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
			if locked.has(hid):  # [orbB]
				continue
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

