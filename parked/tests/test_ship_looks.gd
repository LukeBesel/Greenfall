extends GutTest
## Parked in task M3-13 with ship look purchases (parked/side/ship_looks/): cut from tests/test_ui6.gd.
## It does not run.

func test_ship_style_unlocks_and_wear() -> void:
	var paints: Array = ShipStyle.items("paints")
	assert_eq(paints.size(), 6)
	assert_eq(ShipStyle.items("trims").size(), 3)
	assert_true(ShipStyle.unlocked("paints", "pearl"))
	assert_false(ShipStyle.listed("paints", "lunar"), "tier-locked looks stay hidden")
	assert_true(ShipStyle.wear("paints", "sunset"))
	assert_eq(ShipStyle.paint_color(), Color.html("#f2a46b"))
	assert_false(ShipStyle.wear("paints", "coral"), "bought first")
	GameState.currencies["parts"] = BigNum.from_float(1000.0)
	assert_true(ShipStyle.buy("paints", "coral"))
	assert_true(ShipStyle.wear("paints", "coral"))
