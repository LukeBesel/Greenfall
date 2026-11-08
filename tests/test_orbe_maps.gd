extends GutTest
## [orbE] Maps of the round planet: globe sizes follow the owner's decision (or data), the big-hex
## colours follow the cell shares (junk, cleaned, green, water), the PlanetGlobe overlay leaves
## untouched junk to the procedural look, and the map mesh has one fan per big hex.


func test_globe_sizes() -> void:
	assert_almost_eq(GlobeSize.scale_of("verdance"), 1.0, 0.001)
	assert_lt(GlobeSize.scale_of("ochre"), 1.0)
	assert_gt(GlobeSize.scale_of("anvil"), GlobeSize.scale_of("rime"))
	assert_gt(GlobeSize.cells_of("anvil"), 290000, "Anvil is the largest globe (~300k hexes)")
	assert_almost_eq(GlobeSize.radius_m("verdance"), 1840.0, 0.5)


func test_survey_colours_follow_shares() -> void:
	var junk: Color = SphereMapMesh.survey_color(Color(1, 0, 0, 0))
	var clean: Color = SphereMapMesh.survey_color(Color(0, 1, 0, 0))
	var water: Color = SphereMapMesh.survey_color(Color(0, 0, 0, 1))
	assert_gt(clean.g, junk.g, "cleaned land reads greener than junk")
	assert_gt(water.b, water.r, "water reads blue")


func test_overlay_leaves_junk_alone() -> void:
	assert_almost_eq(PlanetGlobe.overlay_color(Color(1, 0, 0, 0)).a, 0.0, 0.001)
	assert_gt(PlanetGlobe.overlay_color(Color(0, 0.2, 0.8, 0)).a, 0.4)
	assert_almost_eq(PlanetGlobe.overlay_color(Color(0, 0, 0, 1)).a, 0.0, 0.001, "water stays the planet's own")


func test_map_mesh_one_fan_per_hex() -> void:
	var g: SphereGrid = SphereGrid.cached(2)
	var m: ArrayMesh = SphereMapMesh.build(g, func(_c: int) -> Color: return Color.WHITE)
	var tris: int = m.surface_get_array_len(0) / 3
	var want: int = 0
	for c: int in g.cell_count():
		want += g.corners(c).size()
	assert_eq(tris, want)


func test_world_up_flat_and_sphere() -> void:
	assert_eq(WorldUp.at(null, Vector3(5, 0, 0)), Vector3.UP)
	var w := Node.new()
	assert_eq(WorldUp.at(w, Vector3(5, 0, 0)), Vector3.UP, "no surface: flat game")
	w.free()
