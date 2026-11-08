extends GutTest
## [orbB] Phase B skeleton: the slice's globe pieces (scenes/slice_orbit.gd, planet/orbit/orbit_planet.gd).

var _g: OrbitPlanet


func before_all() -> void:
	_g = OrbitPlanet.new()
	_g.grid = SphereGrid.for_hex_size(7, 10.0)
	_g.terrain = SphereTerrain.new(_g.grid, 4471)


func after_all() -> void:
	_g.free()


func test_direction_height_round_trip() -> void:
	for d: Vector3 in [Vector3(0.3, 0.8, -0.2).normalized(), Vector3(0, -1, 0), Vector3(1, 0.001, 0).normalized()]:
		var p: Vector3 = _g.terrain.ground(d) + d * 1.25
		var a: Array = _g.to_dirh(p)
		assert_eq(a.size(), 4, "direction (3) + height (1)")
		assert_almost_eq(float(a[3]), 1.25, 0.002, "height above the ground")
		assert_lt(_g.from_dirh(a).distance_to(p), 0.01, "back within 1 cm")


func test_hub_ground_flag_survives_a_reload() -> void:
	var cells := SphereCells.new(_g.grid.cell_count())
	var hub: int = _g.grid.cell_at(Vector3(0.2, 0.9, 0.1).normalized())
	var nb: int = _g.grid.neighbors(hub)[0]
	cells.set_flag(hub, SphereCells.F_SITE)
	cells.set_flag(nb, SphereCells.F_SITE)
	cells.set_flag(hub, SphereCells.F_HUB)
	cells.set_state(hub, 1)
	cells.set_junk(hub, 0.0)
	cells.set_junk(nb, 0.0)  # cleaned by Lumi on the pad: a junk hex, not hub ground
	var f := SphereField.new(_g.grid, _g.terrain, cells, 4471)
	assert_eq(f.hex_hub[hub], 1, "F_HUB cell is hub ground")
	assert_eq(f.hex_hub[nb], 0, "a cleaned site cell stays a junk hex")
	assert_eq(f.cleaned_count, 1, "and counts as cleaned")


func test_junk_view_is_the_slice_view() -> void:
	var v := SphereJunkView.new()
	assert_true(v is FieldView, "fits the slice's typed `view`")
	v.free()


func test_wanted_only_for_the_orbit_slice() -> void:
	assert_false(SliceOrbit.wanted(), "off without --orbit: the flat game is unchanged")
