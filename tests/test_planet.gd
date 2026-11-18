extends GutTest

var planet: PlanetData


func before_all() -> void:
	planet = PlanetData.new(4471, 6, 10.0)
	planet.generate()


func test_size_and_water() -> void:
	assert_eq(planet.cell_count(), 40962)
	var water: int = planet.cell_count() - planet.land_count()
	var frac: float = float(water) / planet.cell_count()
	assert_between(frac, 0.2, 0.3)
	assert_between(planet.radius_m, 800.0, 1100.0)


func test_cities_on_land_and_spread() -> void:
	assert_eq(planet.cities.size(), 24)
	for c: Dictionary in planet.cities:
		assert_ne(planet.state[int(c["cell"])], PlanetData.State.WATER)
	assert_true(planet.cities[-1]["capital"])


func test_local_map_preserves_distance() -> void:
	var a: int = int(planet.cities[0]["cell"])
	var d: Vector3 = planet.local_to_dir(a, 120.0, 0.0)
	var arc: float = planet.grid.centers[a].angle_to(d) * planet.radius_m
	assert_almost_eq(arc, 120.0, 0.5)


func test_save_roundtrip_and_counts() -> void:
	var c: int = int(planet.cities[0]["cell"])
	planet.mark_clean(c)
	var before: int = planet.restored_count()
	var other := PlanetData.new(4471, 6, 10.0)
	other.generate()
	assert_true(other.apply_dict(planet.to_dict()))
	assert_eq(other.restored_count(), before)
	assert_eq(other.state[c], PlanetData.State.CLEAN)
