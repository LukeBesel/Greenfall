extends GutTest
## Rocket tiers (automation/rocket_tiers.gd, data/rockets.json): each tier travels better, upgrades
## pay the cost, Mk III+ need the Rocket Cargo research, recharge follows the tier.

var _cur: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	GameState.currencies = {}
	GameState.flags = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags


func _give(cost: Dictionary) -> void:
	for k: String in cost:
		GameState.add_currency(k, BigNum.from_float(float(cost[k])))


func test_tiers_get_better() -> void:
	assert_eq(RocketTiers.max_tier(), 4)
	for t: int in range(2, 5):
		var a: Dictionary = RocketTiers.def(t - 1)
		var b: Dictionary = RocketTiers.def(t)
		assert_lt(float(b["flight_s"]), float(a["flight_s"]), "faster flight at Mk %d" % t)
		assert_lt(float(b["recharge_s"]), float(a["recharge_s"]), "faster recharge at Mk %d" % t)
		assert_gt(float(b["cargo_mult"]), float(a["cargo_mult"]), "bigger cargo at Mk %d" % t)
	assert_true(bool(RocketTiers.def(4).get("warp", false)))


func test_upgrade_pays_and_persists() -> void:
	assert_eq(RocketTiers.tier(), 1)
	assert_false(RocketTiers.upgrade(), "can't afford Mk II")
	_give(RocketTiers.next_def()["cost"])
	assert_eq(RocketTiers.blocker(), "")
	assert_true(RocketTiers.upgrade())
	assert_eq(RocketTiers.tier(), 2)
	assert_eq(int(GameState.flags["rocket_tier"]), 2)
	assert_false(GameState.get_currency("cubes").gte(BigNum.from_float(1.0)), "cubes spent")


func test_mk3_needs_research() -> void:
	GameState.flags["rocket_tier"] = 2
	_give(RocketTiers.next_def()["cost"])
	assert_ne(RocketTiers.blocker(), "")
	assert_false(RocketTiers.upgrade())
	assert_eq(RocketTiers.tier(), 2)


func test_recharge_follows_tier() -> void:
	RocketTiers.mark_launched()
	var left1: float = RocketTiers.recharge_left()
	assert_almost_eq(left1, float(RocketTiers.def(1)["recharge_s"]), 2.0)
	GameState.flags["rocket_tier"] = 4
	RocketTiers.mark_launched()
	assert_eq(RocketTiers.recharge_left(), 0.0, "Mk IV has no recharge")
