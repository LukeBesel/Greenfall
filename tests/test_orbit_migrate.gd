extends GutTest
## [orbB] Old flat saves onto the globe (core/save_orbit_migrate.gd), on the saved fixture
## tests/fixtures/flat_v4_oldtown.save (tools/orbit_fixture.tscn writes it).

const FIXTURE := "res://tests/fixtures/flat_v4_oldtown.save"

var _globe: OrbitPlanet


func before_all() -> void:
	_globe = OrbitPlanet.new()
	_globe.seed_value = 4471
	_globe.planet = PlanetData.new(4471, 7, 10.0)
	_globe.planet.generate()
	_globe.grid = SphereGrid.for_hex_size(7, 10.0)
	_globe.terrain = SphereTerrain.new(_globe.grid, 4471)
	_globe.cells = SphereCells.from_planet(_globe.planet)
	_globe._place_hubs(10, true)


func after_all() -> void:
	_globe.free()
	GameState.new_game()


func _load_fixture() -> bool:
	var d: Dictionary = SaveManager.read_dict(ProjectSettings.globalize_path(FIXTURE))
	if d.is_empty():
		return false
	GameState.from_dict(SaveManager.migrate(d))
	return true


func test_fixture_is_a_flat_save() -> void:
	assert_true(_load_fixture(), "fixture readable")
	assert_eq(int(GameState.planet_state.get("level", -1)), 6, "a level-6 survey")
	assert_true(GameState.orbit.is_empty(), "no globe yet")
	assert_true(OrbitMigrate.can_migrate(128), "Verdance's globe takes it")
	assert_false(OrbitMigrate.can_migrate(109), "other sizes start fresh")


func test_parents_follow_the_hierarchy() -> void:
	var par: PackedInt32Array = OrbitMigrate.parents(_globe.grid)
	var g6: GeoSphere = GeoSphere.cached(6)
	assert_eq(par[123], 123, "a level-6 id is the same level-7 id")
	var bad: int = 0
	for i: int in range(40962, _globe.grid.cell_count(), 997):
		var near: int = g6.nearest_from(_globe.grid.centers[i], par[i])
		if near != par[i] and absf(g6.centers[near].dot(_globe.grid.centers[i]) - g6.centers[par[i]].dot(_globe.grid.centers[i])) > 1e-6:
			bad += 1
	assert_eq(bad, 0, "every level-7 cell's parent is its nearest level-6 cell")


func test_old_district_lands_on_the_globe() -> void:
	assert_true(_load_fixture())
	var junk0: float = 0.0
	for c: float in _globe.cells.junk:
		junk0 += c
	var r: Dictionary = OrbitMigrate.apply(_globe)
	assert_true(bool(r["ok"]), "the survey applied")
	assert_gte(int(r["changed6"]), 4, "three cleaned hexes and a half-scooped one changed their planet cells")
	assert_gte(int(r["cleaned"]), 3 * 3, "each cleaned level-6 cell covers ~4 globe cells")
	var junk1: float = 0.0
	for c: float in _globe.cells.junk:
		junk1 += c
	assert_lt(junk1, junk0, "less junk on the globe")
	assert_gt(junk1, junk0 - float(r["cells"]) - 0.5, "only the covered cells changed")
	assert_eq(int((r["hubs"] as Dictionary).get("0", {}).get("level", 0)), 2, "the start base keeps its level")
	var cargo: Dictionary = OrbitMigrate.lumi_cargo()
	assert_almost_eq(float((cargo["compartment"] as Dictionary).get("fill", 0.0)), 2.5, 0.01, "Lumi keeps his chest")
