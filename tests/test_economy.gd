extends GutTest

var _saved_upgrades: Dictionary
var _saved_cubes: BigNum


func before_each() -> void:
	_saved_upgrades = GameState.upgrades.duplicate()
	_saved_cubes = GameState.get_currency("cubes")
	GameState.upgrades = {}
	GameState.currencies["cubes"] = BigNum.zero()


func after_each() -> void:
	GameState.upgrades = _saved_upgrades
	GameState.currencies["cubes"] = _saved_cubes


func test_data_loaded() -> void:
	assert_gt(Economy.junk_ids.size(), 4)
	assert_true(Economy.upgrade_defs.has("compartment_size"))
	assert_almost_eq(Economy.stat("capacity"), float(Economy.patch_base["capacity"]), 0.001)


func test_stat_add_and_mul() -> void:
	GameState.upgrades["compartment_size"] = 3
	var per: float = float(Economy.upgrade_defs["compartment_size"]["amount"])  # [pace] data-driven
	assert_almost_eq(Economy.stat("capacity"), float(Economy.patch_base["capacity"]) + 3.0 * per, 0.001)
	GameState.upgrades["tread_speed"] = 2
	var tread: float = float(Economy.upgrade_defs["tread_speed"]["amount"])
	assert_almost_eq(Economy.stat("move_speed"), Economy.base_stat("move_speed") * (1.0 + 2.0 * tread), 0.001)


func test_cost_growth_and_n() -> void:
	# A track: its first tier starts at base_cost and climbs by the tier's ratio, each level rounded
	# to a whole cube (Economy.track_cost).
	var b: float = float(Economy.upgrade_defs["compartment_size"]["base_cost"])
	var g: float = float((Economy.track_tiers["ratio"] as Array)[0])
	var c0: float = Economy.upgrade_cost("compartment_size").to_float()
	assert_almost_eq(c0, b, 0.001)
	var c3: float = Economy.cost_for_n("compartment_size", 3).to_float()
	assert_almost_eq(c3, b + roundf(b * g) + roundf(b * g * g), 0.01)
	# A one-off keeps base_cost x growth^level.
	var lift: Dictionary = Economy.upgrade_defs["lift_strength"]
	assert_almost_eq(Economy.upgrade_cost("lift_strength", 1).to_float(), float(lift["base_cost"]) * float(lift["growth"]), 0.001)


func test_buy_spends_and_levels() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(100.0)
	var got: int = Economy.buy_upgrade("compartment_size", 1)
	assert_eq(got, 1)
	assert_eq(GameState.level_of("compartment_size"), 1)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 100.0 - float(Economy.upgrade_defs["compartment_size"]["base_cost"]), 0.001)


func test_buy_max_respects_budget_and_cap() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(1.0e9)
	var got: int = Economy.buy_upgrade("auto_compactor", 0)
	assert_eq(got, 0, "locked until its requirements are met")
	GameState.upgrades["compartment_size"] = 6
	GameState.upgrades["baler"] = 1
	var done: Array = Research.done_list()
	var had: bool = "auto_baler" in done
	if not had:
		done.append("auto_baler")  # [pace] auto-cubing waits for the Auto-Baler research
	got = Economy.buy_upgrade("auto_compactor", 0)
	if not had:
		done.erase("auto_baler")
	assert_eq(got, 1, "max level 1")


func test_cannot_overspend() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(float(Economy.upgrade_defs["compartment_size"]["base_cost"]) - 5.0)
	assert_eq(Economy.buy_upgrade("compartment_size", 1), 0)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), float(Economy.upgrade_defs["compartment_size"]["base_cost"]) - 5.0, 0.001)


func test_cube_values() -> void:
	var mixed: Dictionary = Economy.evaluate_cube({"metal": 5.0, "plastic": 3.0}, 10.0, 1.0)
	assert_false(mixed["pure"])
	assert_false(mixed["perfect"])
	assert_eq(str(mixed["quality"]), Economy.PRESS_GOOD, "80% full: a good press")
	assert_almost_eq((mixed["value"] as BigNum).to_float(), (5.0 * 1.0 + 3.0 * 0.6) * Economy.press_mult(Economy.PRESS_GOOD), 0.001)
	var pure_perfect: Dictionary = Economy.evaluate_cube({"metal": 9.5}, 10.0, 1.0)
	assert_true(pure_perfect["pure"])
	assert_true(pure_perfect["perfect"])
	assert_almost_eq((pure_perfect["value"] as BigNum).to_float(), 9.5 * Economy.press_mult(Economy.PRESS_PERFECT), 0.001, "one waste type pays no more: the press quality is the only multiplier")
	var lumpy: Dictionary = Economy.evaluate_cube({"glass": 6.0, "metal": 5.0}, 10.0, 1.0)
	assert_true(lumpy["lumpy"])
	assert_false(lumpy["perfect"])
	assert_almost_eq((lumpy["value"] as BigNum).to_float(), (6.0 * 0.85 + 5.0) * Economy.press_mult(Economy.PRESS_PLAIN), 0.001, "overstuffed: a plain bale, still above tipping")


func test_skill_beats_idle() -> void:
	# A perfect manual cube is always worth more than the same junk overstuffed.
	var perfect: float = (Economy.evaluate_cube({"metal": 9.4}, 10.0, 1.0)["value"] as BigNum).to_float()
	var lumpy: float = (Economy.evaluate_cube({"metal": 10.6}, 10.0, 1.0)["value"] as BigNum).to_float()
	assert_gt(perfect, lumpy)
