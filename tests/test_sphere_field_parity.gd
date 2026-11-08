extends GutTest
## [orbB] Field parity on the globe: parts, piles, landmarks, locked cells, floating junk
## (planet/orbit/sphere_field.gd), all per cell id and deterministic.

var _grid: SphereGrid
var _terrain: SphereTerrain


func before_all() -> void:
	_grid = SphereGrid.for_hex_size(7, 10.0)
	_terrain = SphereTerrain.new(_grid, 4471)


func _field(water_cell: int = -1) -> SphereField:
	var cells := SphereCells.new(_grid.cell_count())
	if water_cell >= 0:
		cells.state[water_cell] = 5
		cells.junk[water_cell] = 1.0
	return SphereField.new(_grid, _terrain, cells, 4471)


func _patch_of_cells(n: int) -> PackedInt32Array:
	var start: int = _grid.cell_at(Vector3(0.3, 0.8, 0.2).normalized())
	var ring: PackedInt32Array = _grid.cells_around(start, 14)
	return ring.slice(0, n)


func test_parts_rate_and_detector() -> void:
	var f := _field()
	var cs: PackedInt32Array = _patch_of_cells(400)
	for c: int in cs:
		f.materialize(c)
	var rate: float = float(f.part_pos.size()) / cs.size()
	assert_almost_eq(rate, float(Economy.parts.get("chance_per_hex", 0.45)), 0.12, "parts per hex like the flat field")
	assert_gt(f.part_pos.size(), 0)
	var p: Vector3 = f.part_pos[0]
	var up: Vector3 = p.normalized()
	var near: Vector3 = p + SphereGrid.frame(up).x * 3.0 + up * 0.5
	var i: int = f.nearest_part(near, 16.0)
	assert_ne(i, -1, "the detector finds a part 3 m away")
	assert_almost_eq(f.part_distance(i, near), 3.0, 0.6, "measured along the ground, not through it")
	# Found parts persist by cell key, even before their cell materializes again.
	f.part_found[0] = 1
	var d: Dictionary = f.to_dict()
	var g := _field()
	g.apply_dict(d)
	for c: int in cs:
		g.materialize(c)
	assert_eq(g.part_pos.size(), f.part_pos.size(), "deterministic per cell")
	assert_eq(g.part_found[0], 1, "found stays found")
	assert_eq(g.part_found.count(1), 1)


func test_piles_hold_pieces_and_settle() -> void:
	var f := _field()
	var cell: int = -1
	for c: int in _patch_of_cells(200):
		f.materialize(c)
		if cell < 0 and not (f.hex_piles[c] as Array).is_empty():
			cell = c
	assert_ne(cell, -1, "some cells have heaps")
	var top: int = -1
	var top_h: float = 0.0
	for pid: int in f.pieces_in(cell):
		var alt: float = f.piece_pos[pid].length() - (_grid.radius_m + _terrain.height(f.piece_pos[pid].normalized()))
		if f.piece_embed[pid] > 0.0 and alt > top_h:
			top_h = alt
			top = pid
	assert_gt(top_h, 0.4, "heaped pieces sit up on the mound")
	var pids: PackedInt32Array = f.pieces_in(cell)
	for k: int in int(pids.size() * 0.7):
		if pids[k] != top:
			f.remove_piece(pids[k])
	f.resettle(cell)
	var alt2: float = f.piece_pos[top].length() - (_grid.radius_m + _terrain.height(f.piece_pos[top].normalized()))
	assert_lt(alt2, top_h - 0.1, "the heap shrinks and its pieces settle")


func test_landmarks_rate_and_clearance() -> void:
	var f := _field()
	var cs: PackedInt32Array = _patch_of_cells(600)
	for c: int in cs:
		f.materialize(c)
	var per: float = 0.0
	for d: Dictionary in Economy.landmarks_for(""):
		per += float(d.get("count", 1)) / SphereField.FLAT_DISTRICT_HEXES
	assert_almost_eq(float(f.landmarks.size()) / cs.size(), minf(per, 1.0), 0.12, "wrecks at the flat districts' rate")
	for lm: Dictionary in f.landmarks:
		var cell: int = int(lm["hex"])
		for pid: int in f.pieces_in(cell):
			var dd: float = f.piece_pos[pid].normalized().angle_to((lm["pos"] as Vector3).normalized()) * _grid.radius_m
			assert_gt(dd, float(lm["clear"]) - 0.05, "no junk inside a wreck")


func test_locked_biome_cells() -> void:
	var f := _field()
	var cell: int = _patch_of_cells(1)[0]
	f.locked_biomes[int(f.cells.biome[cell])] = true
	f.materialize(cell)
	assert_true(f.locked.has(cell))
	var pid: int = f.pieces_in(cell)[0]
	var p: Vector3 = f.piece_pos[pid]
	var fwd: Vector3 = SphereGrid.frame(p.normalized()).x
	assert_eq(f.find_scoop_target(p - fwd + p.normalized() * 0.2, fwd, 2.0, 1.5) in f.pieces_in(cell), false, "locked: no scooping")
	f.unlock(cell)
	assert_true(f.find_scoop_target(p - fwd + p.normalized() * 0.2, fwd, 2.0, 1.5) >= 0, "unlocked: scoopable")
	var g := _field()
	g.locked_biomes = f.locked_biomes
	g.apply_dict(f.to_dict())
	g.materialize(cell)
	assert_false(g.locked.has(cell), "an unlocked cell stays unlocked after a load")


func test_floating_junk_on_lakes() -> void:
	var w: int = _patch_of_cells(1)[0]
	var f := _field(w)
	assert_eq(f.hex_water[w], 1)
	assert_eq(f.hex_clean[w], 0, "a lake with junk is a junk hex")
	var pids: PackedInt32Array = f.materialize(w)
	assert_eq(pids.size(), SphereField.FLOAT_PIECES)
	for pid: int in pids:
		var alt: float = f.piece_pos[pid].length() - (_grid.radius_m + _terrain.height(f.piece_pos[pid].normalized()))
		assert_almost_eq(alt, -_terrain.water_drop - 0.06, 0.05, "floating at the lake surface")
	for pid: int in pids:
		f.remove_piece(pid)
	assert_eq(f.hex_clean[w], 1, "a cleared lake flips clean")


func test_cell_holds_a_flat_hex_of_volume_in_bites() -> void:
	var f := _field()
	var cell: int = _patch_of_cells(30)[29]
	var pids: PackedInt32Array = f.materialize(cell)
	var total: float = 0.0
	for pid: int in pids:
		total += f.piece_vol[pid]
	assert_almost_eq(total, SphereField.FLAT_HEX_VOL, 0.5, "a cell holds a flat hex's junk volume")
	assert_almost_eq(f.hex_total[cell], SphereField.FLAT_HEX_VOL, 0.01)
	var pid: int = pids[0]
	var scl: float = f.piece_scale[pid]
	var v0: float = f.piece_vol[pid]
	var bites: int = 0
	var taken: float = 0.0
	while f.piece_alive[pid] == 1 and bites < 50:
		var b: float = f.bite(pid)
		assert_lte(b, SphereField.FLAT_BITE_VOL * 1.25 + 0.001, "a bite is a flat scoop pulse's worth")
		taken += b
		if f.is_whole_take(pid, b):
			f.remove_piece(pid)
		bites += 1
	assert_almost_eq(taken, v0, 0.001, "every bit of the piece's volume is taken once")
	assert_eq(f.piece_scale[pid], scl, "pieces keep their model's size")
	assert_almost_eq(f.hex_left[cell], SphereField.FLAT_HEX_VOL - v0, 0.01, "the ledger follows the bites")
