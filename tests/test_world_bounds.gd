extends GutTest
## [orbit] WorldBounds pure checks (the physics path runs in --edge-test).


func test_is_lost() -> void:
	assert_false(WorldBounds.is_lost(Vector3(10, 0.1, 10), 150.0, false))
	assert_true(WorldBounds.is_lost(Vector3(10, -5, 10), 150.0, false), "below ground")
	assert_true(WorldBounds.is_lost(Vector3(160, 0.1, 10), 150.0, false), "outside the square")
	assert_false(WorldBounds.is_lost(Vector3(160, 0.1, 10), 150.0, true), "a wrapping world has no edge")
	assert_true(WorldBounds.is_lost(Vector3(160, -5, 10), 150.0, true), "but still a floor")


func test_clamp_xz() -> void:
	var p: Vector3 = WorldBounds.clamp_xz(Vector3(200, 1, -300), 147.0)
	assert_eq(p, Vector3(147, 1, -147))
	assert_eq(WorldBounds.clamp_xz(Vector3(3, 0, 4), 147.0), Vector3(3, 0, 4))
