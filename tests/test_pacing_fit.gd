extends GutTest
## Task M3-21: city 1's pacing fitted to the game's real walking. The simulator walks the measured
## distances of the start yard, the yard keeps the first junk beside the bin, and the first robot
## is a hauler that arrives early.


func before_each() -> void:
	Planets.set_current(Planets.first_shipped().id)
	GameState.new_game()


func after_each() -> void:
	PaceSimData.overrides.clear()


func test_simulator_walks_the_measured_hexes_nearest_the_bin_first() -> void:
	var data := PaceSimData.new()
	var anchors: Dictionary = SitePrefab.START_YARD_ANCHORS
	var bin: Vector3 = (anchors["bin"] as Array)[0]
	var scale: Vector3 = (anchors["depot"] as Array)[0]
	var middles: Array = (data.section("yard_hexes") as Dictionary)["middles"]
	assert_gt(middles.size(), 6, "the hexes round the yard are measured")
	var nearest: float = INF
	var its_scale: float = 0.0
	for raw: Variant in middles:
		var mid := Vector3(float((raw as Array)[0]), 0.0, float((raw as Array)[1]))
		if mid.distance_to(bin) < nearest:
			nearest = mid.distance_to(bin)
			its_scale = mid.distance_to(scale)
	assert_almost_eq(data.hex_distance(0), nearest, 0.01, "the first hex is the one nearest the bin anchor")
	assert_almost_eq(data.scale_distance(0), its_scale, 0.01, "and its bales walk to the scale anchor")
	for n: int in range(1, middles.size()):
		assert_gte(data.hex_distance(n), data.hex_distance(n - 1), "hex %d is no nearer than the one before" % n)
	assert_gte(data.hex_distance(middles.size() + 40), data.hex_distance(middles.size() - 1), "past the measured hexes the walk keeps growing")


func test_simulator_trip_grows_across_a_hex_and_with_the_route() -> void:
	var result: Dictionary = PaceSim.run(Planets.first_shipped().id, 30.0)
	assert_true(result["ok"], str(result["error"]))
	var straight: float = float((result["model"] as PaceSimModel).record.beats["hexes_5"])
	PaceSimData.overrides["path_factor"] = 3.0
	var slow: Dictionary = PaceSim.run(Planets.first_shipped().id, 30.0)
	assert_gt(float((slow["model"] as PaceSimModel).record.beats["hexes_5"]), straight * 1.1, "a longer route makes the fifth hex later")


# --- The yard: the first junk beside the bin ------------------------------------------------

## Junk must start within this of the bin, and the first hex's middle within FIRST_HEX_M of it
## (docs/DECISIONS.md, Nov 11: "the yard is laid out for the first minutes").
const JUNK_START_M: float = 4.0
const FIRST_HEX_M: float = 8.0
## The scale takes the bales of the same hex: no farther than a hex's own width.
const SCALE_M: float = 12.0


func _start_globe() -> OrbitPlanet:
	var def: PlanetDefinition = Planets.current()
	var seed_value: int = def.world_seed
	var globe := OrbitPlanet.new()
	globe.seed_value = seed_value
	globe.planet_id = String(def.id)
	globe.planet = PlanetData.new(seed_value, 7, PlanetDefinition.CELL_M)
	globe.planet.generate()
	globe.grid = SphereGrid.for_hex_size(7, PlanetDefinition.CELL_M)
	globe.terrain = SphereTerrain.new(globe.grid, seed_value)
	globe.cells = SphereCells.from_planet(globe.planet)
	globe._place_hubs(10, true)
	globe.field = SphereField.new(globe.grid, globe.terrain, globe.cells, seed_value)
	globe.field.keep_out = globe.yard_keep_out().blocks
	return globe


func test_first_junk_is_beside_the_bin_and_the_first_hex_a_few_steps_away() -> void:
	var globe: OrbitPlanet = _start_globe()
	var site: Transform3D = globe.terrain.site_transform(globe.sites[0])
	var anchors: Dictionary = SitePrefab.START_YARD_ANCHORS
	var bin: Vector3 = site * ((anchors["bin"] as Array)[0] as Vector3)
	var scale: Vector3 = site * ((anchors["depot"] as Array)[0] as Vector3)
	var rows: Array[Dictionary] = YardReport.rows(globe, bin, scale)
	assert_gt(rows.size(), 3, "there is junk round the yard")
	var first: Dictionary = rows[0]
	assert_lt(float(first["junk_min_m"]), JUNK_START_M, "junk starts within 4 m of the bin")
	assert_lt(float(first["bin_m"]), FIRST_HEX_M, "the first hex's middle is within 8 m of the bin")
	assert_lt(float(first["scale_m"]), SCALE_M, "and the scale is close to the same hex")
	# The simulator's measured middles are this yard's: the nearest one agrees with the globe.
	assert_almost_eq(PaceSimData.new().hex_distance(0), float(first["bin_m"]), 0.3, "calibration yard_hexes matches the globe")
	globe.free()
