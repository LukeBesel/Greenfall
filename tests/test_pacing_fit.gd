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
