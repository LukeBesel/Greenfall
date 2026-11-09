extends GutTest
## [orbit] Phase A: SphereField (HexField API over globe cells) and the sphere-aware Patch helpers.

var _grid: SphereGrid
var _terrain: SphereTerrain
var _cells: SphereCells
var _field: SphereField
var _cell: int = -1


func before_all() -> void:
	_grid = SphereGrid.for_hex_size(7, 10.0)
	_terrain = SphereTerrain.new(_grid, 4471)
	_cells = SphereCells.new(_grid.cell_count())
	for i: int in _grid.cell_count():
		_cells.junk[i] = 1.0
	_field = SphereField.new(_grid, _terrain, _cells, 4471)
	_cell = _grid.cell_at(Vector3(0.3, 0.8, 0.2).normalized())


func test_ids_are_globe_cells() -> void:
	assert_eq(_field.hex_count(), 163842)
	var c: Vector3 = _field.hex_center(_cell)
	assert_eq(_field.hex_at(c), _cell)
	assert_eq(_field.hexes_near(c, 1).size(), 7)


func test_materialize_is_deterministic_and_matches_junk() -> void:
	var pids: PackedInt32Array = _field.materialize(_cell)
	assert_eq(pids.size(), SphereField.DRAW_PIECES, "an untouched hex gets the full piece count")
	assert_eq(_field.materialize(_cell).size(), 0, "only once")
	assert_almost_eq(_field.removed_fraction(_cell), 0.0, 0.001)
	for pid: int in pids:
		assert_eq(_field.hex_at(_field.piece_pos[pid]) in _field.hexes_near(_field.hex_center(_cell), 1), true)
		var alt: float = _field.piece_pos[pid].length() - (_grid.radius_m + _terrain.height(_field.piece_pos[pid].normalized()))
		assert_true(alt > -0.5 and alt < 2.0, "pieces sit on the ground (alt %.2f)" % alt)


func test_scoop_target_in_front_on_the_sphere() -> void:
	_field.materialize(_cell)
	var pid: int = _field.pieces_in(_cell)[0]
	var p: Vector3 = _field.piece_pos[pid]
	var u: Vector3 = p.normalized()
	var fwd: Vector3 = SphereGrid.frame(u).x
	var origin: Vector3 = p - fwd * 1.0 + u * 0.2
	var got: int = _field.find_scoop_target(origin, fwd, 2.0, 1.5)
	assert_ne(got, -1, "finds a piece right in front")
	assert_eq(_field.find_scoop_target(p + fwd * 1.5, fwd, 1.0, 0.2) == pid, false, "nothing behind the scoop")


func test_reduce_to_follows_robot_work() -> void:
	var c: int = _grid.neighbors(_cell)[0]
	_field.materialize(c)
	var removed: PackedInt32Array = _field.reduce_to(c, 0.5)
	assert_gt(removed.size(), 0)
	assert_almost_eq(_field.removed_fraction(c), 0.5, 0.05)
	_field.reduce_to(c, 0.0)
	assert_eq(_field.hex_clean[c], 1, "a fully worked hex flips clean")
