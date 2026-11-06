extends GutTest

var _cur: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}
	GameState.currencies = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags


func test_upgrade_needs_materials() -> void:
	var hub := Hub.new()
	add_child_autofree(hub)
	GameState.add_currency("cubes", BigNum.from_float(10000))
	assert_false(hub.upgrade(), "no sheet metal yet")
	GameState.add_currency("sheet_metal", BigNum.from_float(25))
	GameState.add_currency("plastic_stock", BigNum.from_float(10))
	assert_true(hub.upgrade())
	assert_eq(hub.level, 2)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 9400.0, 0.01)
	assert_gt(hub.sell_mult(), 0.0)


func test_scrubber_requires_level_and_scales() -> void:
	var hub := Hub.new()
	add_child_autofree(hub)
	for k: String in ["cubes", "sheet_metal", "plastic_stock", "glass_cullet"]:
		GameState.add_currency(k, BigNum.from_float(1.0e6))
	assert_false(hub.build_scrubber(), "locked at level 1")
	hub.upgrade()
	var m0: float = hub.scrubber_cost_mult()
	assert_true(hub.build_scrubber())
	assert_gt(hub.scrubber_cost_mult(), m0)
