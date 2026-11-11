extends GutTest

var _cur: Dictionary
var _flags: Dictionary
var _world: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}
	GameState.currencies = {}
	_world = GameState.world
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.world = _world


func test_upgrade_needs_materials() -> void:
	var hub := Hub.new()
	add_child_autofree(hub)
	var flags: Dictionary = GameState.flags
	GameState.flags = {}
	GameState.add_currency("cubes", BigNum.from_float(10000))
	assert_false(hub.upgrade(), "level 2 waits for the Bot Bay")
	assert_ne(hub.block_reason(), "")
	GameState.flags["bench_tier"] = 2
	assert_eq(hub.block_reason(), "")
	var cost: Dictionary = hub.level_def(2).get("cost", {})
	for k: String in cost:
		if k != "cubes":
			GameState.add_currency(k, BigNum.from_float(float(cost[k])))
	assert_true(hub.upgrade())
	assert_eq(hub.level, 2)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 10000.0 - float(cost.get("cubes", 0.0)), 0.01)
	assert_eq(hub.sell_mult(), 0.0, "a base level does not raise what a bale sells for")
	GameState.flags = flags


func test_scrubber_requires_level_and_scales() -> void:
	var hub := Hub.new()
	add_child_autofree(hub)
	for k: String in Currencies.IDS:  # [money]
		GameState.add_currency(k, BigNum.from_float(1.0e6))
	assert_false(hub.build_scrubber(), "locked at level 1")
	var flags: Dictionary = GameState.flags.duplicate(true)
	GameState.flags["bench_tier"] = 2
	hub.upgrade()
	GameState.flags = flags
	var m0: float = hub.scrubber_cost_mult()
	assert_true(hub.build_scrubber())
	assert_gt(hub.scrubber_cost_mult(), m0)
