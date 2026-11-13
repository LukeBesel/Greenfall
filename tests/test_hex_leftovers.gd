extends GutTest
## [v8hex] Owner item (Nov 13): "This starter hex i cleared but it says 94% and i dont get
## anything". The leftover rule, the bite check, the heal's force_clean and the junk-only clear box
## (the First Seed greenhouse's ground). The in-game audit is `--hex-audit` (CLAUDE.md).

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


## Takes pieces of cell c (in list order) until it is at least `upto` cleared. Returns whether it flipped.
func _take_until(f: SphereField, c: int, upto: float) -> bool:
	for pid: int in f.pieces_in(c):
		if f.removed_fraction(c) >= upto:
			break
		if f.piece_alive[pid] == 1 and f.remove_piece(pid):
			return true
	return false


func test_hidden_leftovers_clear_the_hex() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(0.4, 0.6, -0.7).normalized())
	f.materialize(c)
	f.leftover_from = 0.8
	var hidden: Dictionary = {}
	f.leftover_check = func(pid: int) -> bool: return not hidden.has(pid)
	assert_false(_take_until(f, c, 0.85), "findable pieces left: no flip below 95%")
	assert_eq(f.hex_clean[c], 0)
	var flips: Array = []
	f.hex_became_clean.connect(func(id: int) -> void: flips.append(id))
	var last: int = -1
	for pid: int in f.pieces_in(c):  # the rest hide (under a bench, in a wall) except one
		if f.piece_alive[pid] == 1:
			hidden[pid] = true
			last = pid
	hidden.erase(last)
	assert_true(f.remove_piece(last), "the last findable piece taken: the hex is clean")
	assert_eq(f.hex_clean[c], 1)
	assert_eq(flips, [c], "pays like any clean hex (hex_became_clean)")
	var alive: int = 0
	for pid: int in f.pieces_in(c):
		alive += f.piece_alive[pid]
	assert_eq(alive, 0, "hidden leftovers swept")


func test_rule_waits_for_leftover_from() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(-0.2, 0.9, 0.3).normalized())
	f.materialize(c)
	f.leftover_from = 0.8
	f.leftover_check = func(_pid: int) -> bool: return false  # nothing findable
	var pids: PackedInt32Array = f.pieces_in(c)
	assert_false(f.remove_piece(pids[0]), "early in a hex the rule doesn't fire")
	assert_true(_take_until(f, c, 0.99), "it fires once 80% is cleared")
	assert_almost_eq(f.removed_fraction(c), 1.0, 0.001)


func test_lakes_keep_their_floaters() -> void:
	var f := _field()
	var c: int = -1
	for i: int in f.hex_count():
		if f.hex_water[i] == 1 and f.cells.junk[i] > 0.5:
			c = i
			break
	if c < 0:
		pass_test("no lake cell on this grid")
		return
	f.materialize(c)
	f.leftover_check = func(_pid: int) -> bool: return false
	assert_false(f._leftover_flip(c), "lakes wait for Hover Jets (not the leftover rule)")


func test_bite_over_95_flips() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(0.7, -0.1, 0.7).normalized())
	f.materialize(c)
	f.hex_left[c] = f.hex_total[c] * 0.049  # a bite carried it past 95% without a piece going
	assert_true(f.check_clean(c), "check_clean flips it")
	assert_eq(f.hex_clean[c], 1)
	assert_false(f.check_clean(c), "once")


func test_force_clean_for_the_heal() -> void:
	var f := _field()
	var c: int = _grid.cell_at(Vector3(-0.6, -0.6, 0.5).normalized())
	f.cells.set_junk(c, 0.06)  # the owner's save: 94% cleared, saved
	var n0: int = f.cleaned_count
	assert_true(f.force_clean(c))
	assert_eq(f.hex_clean[c], 1)
	assert_eq(f.cleaned_count, n0 + 1)
	assert_false(f.force_clean(c), "a clean hex stays as it is")


func test_clear_box_keeps_junk_off_but_lets_lumi_in() -> void:
	var c0: int = _grid.cell_at(Vector3(0.1, 0.95, 0.2).normalized())
	var xf := Transform3D(SphereGrid.frame(_grid.centers[c0]), _terrain.ground(_grid.centers[c0]))
	var k := YardKeepOut.new()
	k.xf_inv = xf.affine_inverse()
	k.radius = _terrain.R
	var bx := Transform3D(xf.basis.rotated(xf.basis.y.normalized(), 0.5), xf * Vector3(14.0, 0.0, 11.0))
	k.add_clear_box(bx, Vector2(3.7, 5.2))
	var inside: Vector3 = (bx * Vector3(2.0, 0.0, -4.0)).normalized()
	var outside: Vector3 = (bx * Vector3(5.0, 0.0, 0.0)).normalized()
	assert_true(k.blocks(inside), "no junk in the greenhouse")
	assert_false(k.in_building(inside), "but it isn't a building (the seed tin must stay reachable)")
	assert_false(k.blocks(outside))


func test_start_area_data() -> void:
	assert_gte(StartArea.radius_m(), YardKeepOut.SMALL_ONLY_M, "at least the old 40 m")
	assert_between(StartArea.leftover_from(), 0.5, 0.95)
	assert_gte(StartArea.heal_from(), StartArea.leftover_from())
	assert_false((StartArea.cfg().get("junk_look", []) as Array).is_empty())
