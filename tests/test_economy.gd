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
	assert_almost_eq(Economy.stat("capacity"), 10.0, 0.001)


func test_stat_add_and_mul() -> void:
	GameState.upgrades["compartment_size"] = 3
	assert_almost_eq(Economy.stat("capacity"), 16.0, 0.001)
	GameState.upgrades["tread_speed"] = 2
	assert_almost_eq(Economy.stat("move_speed"), 4.6 * 1.2, 0.001)


func test_cost_growth_and_n() -> void:
	var c0: float = Economy.upgrade_cost("compartment_size").to_float()
	assert_almost_eq(c0, 15.0, 0.001)
	var c3: float = Economy.cost_for_n("compartment_size", 3).to_float()
	assert_almost_eq(c3, 15.0 + 15.0 * 1.55 + 15.0 * 1.55 * 1.55, 0.01)


func test_buy_spends_and_levels() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(100.0)
	var got: int = Economy.buy_upgrade("compartment_size", 1)
	assert_eq(got, 1)
	assert_eq(GameState.level_of("compartment_size"), 1)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 85.0, 0.001)


func test_buy_max_respects_budget_and_cap() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(1.0e9)
	var got: int = Economy.buy_upgrade("auto_compactor", 0)
	assert_eq(got, 0, "locked until compartment_size 2")
	GameState.upgrades["compartment_size"] = 2
	got = Economy.buy_upgrade("auto_compactor", 0)
	assert_eq(got, 1, "max level 1")


func test_cannot_overspend() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(10.0)
	assert_eq(Economy.buy_upgrade("compartment_size", 1), 0)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 10.0, 0.001)


func test_cube_values() -> void:
	var mixed: Dictionary = Economy.evaluate_cube({"metal": 5.0, "plastic": 3.0}, 10.0, 1.0)
	assert_false(mixed["pure"])
	assert_false(mixed["perfect"])
	assert_almost_eq((mixed["value"] as BigNum).to_float(), 5.0 * 1.0 + 3.0 * 0.6, 0.001)
	var pure_perfect: Dictionary = Economy.evaluate_cube({"metal": 9.5}, 10.0, 1.0)
	assert_true(pure_perfect["pure"])
	assert_true(pure_perfect["perfect"])
	assert_almost_eq((pure_perfect["value"] as BigNum).to_float(), 9.5 * 2.0 * 1.5, 0.001)
	var lumpy: Dictionary = Economy.evaluate_cube({"glass": 6.0, "metal": 5.0}, 10.0, 1.0)
	assert_true(lumpy["lumpy"])
	assert_false(lumpy["perfect"])
	assert_almost_eq((lumpy["value"] as BigNum).to_float(), (6.0 * 0.85 + 5.0) * 0.8, 0.001)


func test_skill_beats_idle() -> void:
	# A perfect manual cube is always worth more than the same junk overstuffed.
	var perfect: float = (Economy.evaluate_cube({"metal": 9.4}, 10.0, 1.0)["value"] as BigNum).to_float()
	var lumpy: float = (Economy.evaluate_cube({"metal": 10.6}, 10.0, 1.0)["value"] as BigNum).to_float()
	assert_gt(perfect, lumpy)
