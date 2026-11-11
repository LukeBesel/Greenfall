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
	assert_lt(LifeAmbience.WIND_DB, -20.0, "beds stay under everything")
	assert_lt(LifeAmbience.LEAVES_DB, -20.0)


func test_one_shots_are_rare_and_tied_to_the_ground() -> void:
	assert_false(LifeAmbience.creak_ok(0.3))
	assert_true(LifeAmbience.creak_ok(0.9))
	assert_false(LifeAmbience.song_ok(0.1, 0.0), "no birdsong over bare ground")
	assert_true(LifeAmbience.song_ok(0.5, 0.0))
	assert_false(LifeAmbience.song_ok(0.5, 1.0), "none at night")
	assert_gte(LifeAmbience.CREAK_GAP.x, 30.0)
	assert_gte(LifeAmbience.SONG_GAP.x, 45.0, "owner items 32 and 50: very little chirping")


func test_ambience_measures_the_land_round_lumi() -> void:
	var c := SphereCells.new(16)
	for i: int in 4:
		c.set_junk(i, 0.0)
		c.set_green(i, 255)
	c.set_state(15, 5)  # water: not land
	var m: Vector2 = LifeAmbience.measure(c, PackedInt32Array([0, 1, 2, 3, 4, 5, 6, 7, 15]))
	assert_almost_eq(m.x, 0.5, 0.001, "half the land is still junk")
	assert_almost_eq(m.y, 0.5, 0.001, "half of it is fully green")
