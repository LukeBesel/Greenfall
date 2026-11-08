extends GutTest
## [orbit] SphereShell: the far shell's big-hex map aggregates the fine hexes it covers and
## follows them as they are cleaned and planted.


func _setup(lv: int = 4) -> Array:
	var g := SphereGrid.new()
	g.generate(lv)
	g.radius_m = SphereGrid.radius_for(lv, 10.0)
	var t := SphereTerrain.new(g, 7)
	var cells := SphereCells.new(g.cell_count())
	return [g, t, cells]


func test_every_fine_cell_has_one_owner() -> void:
	var s: Array = _setup()
	var sh := SphereShell.new(s[0], s[2], s[1], 2)
	var total: int = 0
	for c: int in sh.coarse.cell_count():
		total += sh._start[c + 1] - sh._start[c]
		assert_eq(sh.owner_of(c), c, "coarse ids are fine ids")
	assert_eq(total, (s[0] as SphereGrid).cell_count())


func test_shares_follow_cleaning_and_planting() -> void:
	var s: Array = _setup()
	var cells: SphereCells = s[2]
	var sh := SphereShell.new(s[0], cells, s[1], 2)
	var c: int = 5
	var a: Color = sh._img_a.get_pixel(c, 0)
	assert_almost_eq(a.r, 1.0, 0.01, "all junk at first")
	for k: int in range(sh._start[c], sh._start[c + 1]):
		var i: int = sh._members[k]
		cells.set_junk(i, 0.0)
		cells.set_state(i, 4)  # RESTORED
	assert_eq(sh.update(1.0), 1, "one big hex re-aggregated")
	a = sh._img_a.get_pixel(c, 0)
	assert_almost_eq(a.r, 0.0, 0.01, "no junk left")
	assert_almost_eq(a.b, 1.0, 0.01, "fully green")


func test_mesh_is_one_fan_per_hex() -> void:
	var s: Array = _setup()
	var sh := SphereShell.new(s[0], s[2], s[1], 3)
	var m: ArrayMesh = sh.build_mesh()
	var n: int = sh.coarse.cell_count()
	# 12 pentagons (5 tris) + the rest hexagons (6 tris).
	assert_eq(int(sh.stats["tris"]), 12 * 5 + (n - 12) * 6)
	assert_not_null(m)
