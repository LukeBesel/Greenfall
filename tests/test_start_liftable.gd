extends GutTest
## [v2feel] Owner items 35 and 36: the start's hexes hold only junk Lumi lifts at Lift Strength 0,
## and a hex that reaches 95% cleared counts as clean, its leftovers swept away.

var _grid: SphereGrid
var _terrain: SphereTerrain


func before_all() -> void:
	_grid = SphereGrid.for_hex_size(7, 10.0)
	_terrain = SphereTerrain.new(_grid, 4471)


func _field() -> SphereField:
	var cells := SphereCells.new(_grid.cell_count())
	for c: int in _grid.cell_count():
		cells.set_junk(c, 1.0)
	return SphereField.new(_grid, _terrain, cells, 4471)


## The early cells as OrbitPlanet.build marks them (every cell within YardKeepOut.SMALL_ONLY_M).
func _early(f: SphereField, c0: int) -> PackedInt32Array:
	var out: PackedInt32Array = _grid.cells_within(_grid.centers[c0], YardKeepOut.SMALL_ONLY_M, c0)
	for c: int in out:
		f.small_only[c] = true
	return out


func test_early_cells_liftable_at_level_0() -> void:
	GameState.new_game()
	assert_eq(Pace.lift_class(), Pace.SIZE_SMALL, "a new game starts at Lift Strength 0")
	var f := _field()
	var early := _early(f, _grid.cell_at(Vector3(0.1, 0.95, 0.2).normalized()))
	assert_gt(early.size(), 6, "the start and the hexes around it")
	var n: int = 0
	for c: int in early:
		for pid: int in f.materialize(c):
			n += 1
			assert_true(Pace.can_lift(f, pid, Pace.SIZE_SMALL), "piece %d (%s, cell %d) liftable at Lift 0" % [pid, f.piece_model[pid], c])
		assert_true(Pace.hex_clearable(f, c, Pace.SIZE_SMALL), "cell %d clearable at Lift 0" % c)
	assert_gt(n, 500, "the early cells are full of junk")


func test_heavy_hex_not_clearable_at_level_0() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(-0.7, 0.2, 0.6).normalized())
	f.materialize(c)
	var heavy: float = 0.0
	for pid: int in f.pieces_in(c):
		if f.piece_size[pid] > Pace.SIZE_SMALL:
			heavy += f.piece_vol[pid]
	assert_eq(Pace.hex_clearable(f, c, Pace.SIZE_SMALL), heavy <= SphereCells.CLEAN_LEFT * f.hex_total[c] + 0.001)
	assert_true(Pace.hex_clearable(f, c, Pace.SIZE_LARGE), "Lift 2 clears anything")


func test_95_percent_clears_the_rest() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(0.5, -0.5, 0.7).normalized())
	var pids: PackedInt32Array = f.materialize(c)
	assert_gt(pids.size(), 20)
	var swept: Array = []
	f.hex_swept.connect(func(cell: int, gone: PackedInt32Array) -> void: swept.append([cell, gone.size()]))
	var flipped: bool = false
	for pid: int in pids:
		if f.piece_alive[pid] == 0:
			continue
		var before: float = f.removed_fraction(c)
		flipped = f.remove_piece(pid)
		if flipped:
			assert_lt(before, 0.95, "not clean before")
			break
	assert_true(flipped, "the hex flips clean")
	assert_gte(f.removed_fraction(c), 0.95)
	assert_almost_eq(f.removed_fraction(c), 1.0, 0.001, "all its junk is gone")
	assert_eq(f.hex_clean[c], 1)
	var alive: int = 0
	for pid: int in pids:
		alive += f.piece_alive[pid]
	assert_eq(alive, 0, "leftovers swept away")
	assert_eq(swept.size(), 1, "one sweep, for the view's poofs")
	assert_true(SphereCells.clean_left(0.05) and not SphereCells.clean_left(0.06), "the shared rule: 5% left is clean")


func test_robots_and_offline_use_the_rule() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(-0.3, -0.8, -0.4).normalized())
	f.materialize(c)
	SphereOffline.write_cell(f.cells, f, c, 0.04)
	assert_false(f.cells.is_dirty(c), "4% left: clean")
	assert_eq(f.hex_clean[c], 1)
	var c2: int = _grid.neighbors(c)[0]
	SphereOffline.write_cell(f.cells, f, c2, 0.045)  # not materialized (offline / far robots)
	assert_false(f.cells.is_dirty(c2))
	f.settle(c2)
	assert_eq(f.hex_clean[c2], 1, "and the save/load ledger agrees")
