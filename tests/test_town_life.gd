extends GutTest
## [v6life] Streets wake up block by block, small life over planted cells, and the local ambience:
## the rules that turn cell state into stages, counts and bed weights.


func test_a_block_wakes_in_stages_clean_then_planted() -> void:
	assert_eq(TownLife.rate(0, 0, 0).x, -1, "no ground of its own: follows its neighbours")
	assert_eq(TownLife.rate(10, 0, 0).x, 0)
	assert_eq(TownLife.rate(10, 5, 0).x, 0, "half clean is not swept yet")
	assert_eq(TownLife.rate(10, 6, 0).x, 1, "mostly clean: swept")
	assert_eq(TownLife.rate(10, 8, 3).x, 1, "planting does not skip the cleaning")
	assert_eq(TownLife.rate(10, 9, 0).x, 2, "clean: awake")
	assert_eq(TownLife.rate(10, 10, 1).x, 3, "clean and planted: alive")
	assert_eq(TownLife.rate(10, 7, 0).y, 700, "the clean share drives the grime")


func test_more_windows_glow_with_every_stage_and_only_from_dusk() -> void:
	for s: int in range(1, TownLife.LIT.size()):
		assert_gt(TownLife.LIT[s], TownLife.LIT[s - 1])
	assert_eq(TownLife.LIT[0], 0.0, "a dirty block is dark")
	assert_lt(TownLife.LIT[3], 0.7, "never every window")
	assert_eq(TownLife.dusk(0.5), 0.0, "noon")
	assert_eq(TownLife.dusk(0.9), 1.0, "night")
	assert_eq(TownLife.dusk(0.0), 1.0, "midnight")
	assert_between(TownLife.dusk(0.75), 0.2, 0.8, "they come on through dusk")


func test_lamps_come_on_before_signs() -> void:
	assert_lt(TownLife.LAMP_STAGE, TownLife.SIGN_STAGE)


func test_butterflies_only_over_planted_clean_land() -> void:
	assert_eq(Flutter.count_for(0, 0, 0), 0, "junk")
	assert_eq(Flutter.count_for(1, 1, 0), 0, "clean but bare")
	assert_eq(Flutter.count_for(1, 2, 0), 1, "planted")
	assert_eq(Flutter.count_for(1, 3, SphereCells.F_HUB), 0, "hub ground")
	assert_eq(Flutter.count_for(5, 3, 0), 0, "water")
	assert_gt(Flutter.count_for(1, 5, 0), Flutter.count_for(1, 2, 0))
	var total: int = 0
	for lv: int in 6:
		total = maxi(total, Flutter.count_for(1, lv, 0))
	assert_lte(total, 3, "sparse")


func test_ambience_is_wind_over_junk_leaves_over_green_and_quiet_between() -> void:
	var junk: Vector2 = LifeAmbience.weights(1.0, 0.0)
	assert_gt(junk.x, 0.9, "wind over the dump")
	assert_eq(junk.y, 0.0)
	var bare: Vector2 = LifeAmbience.weights(0.0, 0.0)
	assert_eq(bare.x, 0.0)
	assert_eq(bare.y, 0.0, "clean but bare ground is quiet")
	var lush: Vector2 = LifeAmbience.weights(0.0, 0.7)
	assert_eq(lush.x, 0.0, "no dump wind in the garden")
	assert_gt(lush.y, 0.9)
	var bed: Dictionary = LifeAmbience.bed_of("verdance")
	assert_false(bed.is_empty(), "Verdance's life bed is in data/sound.json")
	var ons: Array = []
	for lid: String in bed["loops"]:
		assert_lt(float(bed["loops"][lid][0]), -20.0, "beds stay under everything: " + lid)
		ons.append(str(bed["loops"][lid][1]))
	assert_has(ons, "dirty")
	assert_has(ons, "green")


func test_one_shots_are_rare_and_tied_to_the_ground() -> void:
	assert_false(LifeAmbience.when_ok("dirty", 0.3, 0.0, 0.0))
	assert_true(LifeAmbience.when_ok("dirty", 0.9, 0.0, 0.0))
	assert_false(LifeAmbience.when_ok("green_day", 0.0, 0.1, 0.0), "no birdsong over bare ground")
	assert_true(LifeAmbience.when_ok("green_day", 0.0, 0.5, 0.0))
	assert_false(LifeAmbience.when_ok("green_day", 0.0, 0.5, 1.0), "none at night")
	assert_false(LifeAmbience.when_ok("typo", 1.0, 1.0, 0.0), "an unknown condition never plays")
	for e: Array in LifeAmbience.bed_of("verdance")["events"]:
		assert_gte(float(e[1]), 30.0, "owner items 32 and 50: very little chirping: " + str(e[0]))
		assert_gte(float(e[7]), 30.0)


func test_ambience_measures_the_land_round_lumi() -> void:
	var c := SphereCells.new(16)
	for i: int in 4:
		c.set_junk(i, 0.0)
		c.set_green(i, 255)
	c.set_state(15, 5)  # water: not land
	var m: Vector2 = LifeAmbience.measure(c, PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 15]))
	assert_almost_eq(m.x, 0.5, 0.001, "half the land is still junk")
	assert_almost_eq(m.y, 0.5, 0.001, "half of it is fully green")


func test_life_values_come_from_data() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/life.json"))
	assert_true(raw is Dictionary, "data/life.json parses")
	var d: Dictionary = raw["planets"]["_default"]
	assert_eq(TownLife.LIT.size(), 4)
	assert_almost_eq(TownLife.CLEAN_2, float(d["town"]["awake_at"]), 0.0001)
	assert_eq(CellVerdure.TARGET.size(), 6)
	assert_almost_eq(CellVerdure.TARGET[1], float(d["ground"]["green_per_level"][1]), 0.0001)
	assert_eq(Flutter.MAX_N, int(d["flutter"]["max"]))
	assert_eq(Flutter.COLORS.size(), (d["flutter"]["colors"] as Array).size())


func test_a_planet_block_overrides_only_what_it_names() -> void:
	LifeCfg.cfg()
	var keep: Dictionary = LifeCfg._cfg
	LifeCfg._cfg = {"planets": {"_default": {"town": {"swept_at": 0.5, "awake_at": 0.9}}, "ochre": {"town": {"awake_at": 0.8}}}}
	LifeCfg.use_planet("ochre")
	assert_almost_eq(LifeCfg.num("town", "awake_at", 0.0), 0.8, 0.0001)
	assert_almost_eq(LifeCfg.num("town", "swept_at", 0.0), 0.5, 0.0001, "the rest from _default")
	assert_eq(LifeCfg.floats("town", "lit_windows", [0.0, 1.0], 4), [0.0, 1.0] as Array[float], "a missing list falls back")
	LifeCfg._cfg = keep
	LifeCfg.use_planet("verdance")
	TownLife.configure()
