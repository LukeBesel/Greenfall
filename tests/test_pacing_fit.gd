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


# --- The first robot: a hauler, early ----------------------------------------------------------

func _objective_ids() -> Array[String]:
	var ids: Array[String] = []
	for o: Variant in Economy.planet_table("tutorial").get("objectives", []):
		ids.append(str((o as Dictionary)["id"]))
	return ids


func test_first_robot_is_a_hauler_that_costs_parts_only() -> void:
	var haul: Dictionary = Economy.robots["haulbug"]
	assert_eq(str(haul["role"]), "haul", "it carries bales to the scale")
	assert_eq(float(haul["cost"]), 0.0, "robots cost no cubes")
	assert_eq(float(haul["parts"]), 6.0, "Parts the bot has found by about minute 6")
	assert_lt(float(haul["parts"]), float(Economy.robots["scoopie"]["parts"]), "the first helper is the cheaper one")
	assert_eq(Research.robot_requirement("haulbug"), "haul_rig")
	var plans: Dictionary = Research.def("haul_rig")
	assert_has(plans.get("when", []), ["bench_tier", 2.0], "its plans come with the Bot Bay")
	assert_eq(Research.robot_requirement("scoopie"), "scoopie_rig", "the cleaner's plans come later")


## The tower is asked for as soon as the base has power (while the card asked for 7 hexes first,
## nobody saved for it and it came anywhere from minute 6.7 to minute 11), and the first robot
## follows the Bot Bay at once.
func test_card_asks_for_the_tower_first_and_the_robot_right_after_the_bot_bay() -> void:
	var ids: Array[String] = _objective_ids()
	for pair: Array in [["power", "tower"], ["tower", "glim"], ["glim", "street"], ["street", "bench2"], ["bench2", "robot"]]:
		assert_eq(ids.find(pair[1]), ids.find(pair[0]) + 1, "%s is the step after %s" % [pair[1], pair[0]])


func test_bot_bay_waits_for_the_tower_and_six_hexes() -> void:
	var bay: Dictionary = BenchTiers.def(2)
	assert_has(bay.get("requires", []), ["tower", 1.0])
	assert_has(bay.get("requires", []), ["stat", "hexes_cleaned", 6.0], "six clean hexes: about minute 7 to 9 for the bot")
	assert_has(bay.get("grants_research", []), "salvage_logic")
	assert_lte(float((bay["cost"] as Dictionary)["cubes"]), 340.0, "under 100 s of the bot's income at minute 8, so the wait stays short")
	var tower: Dictionary = (Economy.planet_table("signal_tower")["tiers"] as Array)[0]
	assert_lte(float((tower["cost"] as Dictionary)["cubes"]), 120.0, "the tower is asked for near minute 3, at 1 to 2 cubes a second")


## Fetching the seed tin takes Lumi off the work; a purchase saved for at the same time was a
## wait of 144 to 190 s in four bot runs. The Research Desk is offered once the tin is found.
func test_research_desk_waits_for_base_two_and_the_seed_tin() -> void:
	var desk: Dictionary = BenchTiers.def(3)
	assert_has(desk.get("requires", []), ["hub_level", 2.0])
	assert_has(desk.get("requires", []), ["flag", "seeds_unlocked"])
	var ids: Array[String] = _objective_ids()
	assert_lt(ids.find("seed"), ids.find("research1"), "the card asks for the seed before it asks for research")


func test_base_level_three_waits_for_the_research_desk_and_24_hexes() -> void:
	var level: Dictionary = {}
	for row: Variant in Economy.planet_table("hub").get("levels", []):
		if int((row as Dictionary)["level"]) == 3:
			level = row
	assert_has(level.get("requires", []), ["bench_tier", 3.0])
	assert_has(level.get("requires", []), ["stat", "hexes_cleaned", 24.0], "not on offer in the first 20 minutes: saving 1,100 for it stopped every other purchase")


# --- The targets, on the simulator (the bot confirms them: docs/reviews/M3-21_PACING_FIT.md) ----

func test_simulator_meets_the_first_city_targets() -> void:
	var result: Dictionary = PaceSim.run(Planets.first_shipped().id, 22.0)
	assert_true(result["ok"], str(result["error"]))
	var fit: Dictionary = PaceSimReport.city_fit(result["model"] as PaceSimModel)
	assert_between(float(fit["first_hex_s"]), 1.0, 90.0, "first clean hex under 90 s")
	assert_between(float(fit["first_robot_s"]), 420.0, 720.0, "first robot by minute 12, and not before minute 7")
	assert_lte(float(fit["purchase_gap_s"]), 120.0, "no wait between purchases over 120 s in the first 20 minutes")
	assert_lt(float(fit["most_held"]), 5000.0, "most cubes held")
	assert_lt(float(fit["largest_price"]), 4200.0, "largest price paid")
	var gaps: Array = fit["hex_gaps_s"]
	assert_gt(gaps.size(), 8, "hexes through minute 15")
	var total: float = 0.0
	for g: Variant in gaps:
		total += float(g)
	assert_between(total / float(gaps.size()), 60.0, 90.0, "a hex about every 60 to 90 s through minute 15")
