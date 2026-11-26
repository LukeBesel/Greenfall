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


# [v9a] The opening walk froze by the bin's lake side: hex_at speckled within centimetres of a
# hex edge (32-bit dot products), and the shore rule stood Lumi in that band.
func test_hex_at_exact_has_one_edge() -> void:
	var a: Vector3 = _grid.centers[_cell] * _grid.radius_m
	var b: Vector3 = _grid.centers[_grid.nbr[_cell * SphereGrid.MAX_N]] * _grid.radius_m
	var mid: Vector3 = (a + b) * 0.5
	var along: Vector3 = (b - a).normalized()
	var flips: int = 0
	var flips32: int = 0
	var last: int = _field.hex_at_exact(mid - along * 0.5)
	var last32: int = _field.hex_at(mid - along * 0.5)
	assert_eq(last, _cell, "half a metre this side of the edge: this hex")
	for i: int in range(1, 1001):  # 1 mm steps across the edge
		var p: Vector3 = mid + along * (float(i) * 0.001 - 0.5)
		var h: int = _field.hex_at_exact(p)
		flips += 1 if h != last else 0
		last = h
		var h32: int = _field.hex_at(p)
		flips32 += 1 if h32 != last32 else 0
		last32 = h32
	assert_eq(flips, 1, "walking across an edge in 1 mm steps the hex changes once (the 32-bit lookup: %d times)" % flips32)
	assert_ne(last, _cell, "and half a metre on it is the neighbour")


## [v14qa] Every piece lies in the hex it counts toward: clearing all that lies inside a hex's
## outline clears the hex (the spots were drawn in a disc wider than the hex: up to 20% of a
## start-area hex's junk lay in its neighbours, so it read "94%" with its outline empty).
func test_pieces_lie_inside_their_own_hex() -> void:
	var cells: PackedInt32Array = _grid.cells_around(_grid.neighbors(_cell)[2], 2)
	var n: int = 0
	var outside: int = 0
	for c: int in cells:
		if _field.materialized[c] == 0:
			_field.materialize(c)
		for pid: int in _field.pieces_in(c):
			n += 1
			if _field.hex_at_exact(_field.piece_pos[pid]) != c:
				outside += 1
	assert_gt(n, 100, "pieces to look at")
	assert_eq(outside, 0, "%d of %d pieces lie outside the hex they count toward" % [outside, n])
