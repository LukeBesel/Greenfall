extends GutTest
## Lumi's Bloom Core (story/core_charge.gd): charge from blooms / hex levels / Verdance Bloom
## progress, never drops, 100% only with the Verdance Bloom, milestones recorded once in flags.

var _flags: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}


func after_each() -> void:
	GameState.flags = _flags


func test_compute_starts_low_and_caps_below_full() -> void:
	assert_almost_eq(CoreCharge.compute(0.0, 0.0, 0.0, false), CoreCharge.START, 0.0001)
	var most: float = CoreCharge.compute(1.0e6, 1.0e6, 0.999, false)
	assert_true(most < 1.0, "never full before the Verdance Bloom")
	assert_eq(CoreCharge.compute(0.0, 0.0, 0.0, true), 1.0)


func test_compute_grows_with_each_input() -> void:
	var base: float = CoreCharge.compute(0.0, 0.0, 0.0, false)
	assert_gt(CoreCharge.compute(20.0, 0.0, 0.0, false), base)
	assert_gt(CoreCharge.compute(0.0, 100.0, 0.0, false), base)
	assert_gt(CoreCharge.compute(0.0, 0.0, 0.3, false), base)


func test_bloom_progress_uses_thriving_hexes() -> void:
	assert_eq(CoreCharge.bloom_progress({}), 0.0)
	var half: float = CoreCharge.bloom_progress({"thriving_hexes": 207, "thriving_districts": 0, "planet_pct": 0.0})
	assert_almost_eq(half, 0.5, 0.01)
	assert_eq(CoreCharge.bloom_progress({"thriving_hexes": 0, "thriving_districts": 3, "planet_pct": 0.0}), 1.0)


func test_store_never_drops_and_records_beats_once() -> void:
	assert_eq(CoreCharge.store(0.2), [] as Array[int])
	assert_eq(CoreCharge.store(0.3), [25] as Array[int])
	assert_eq(CoreCharge.store(0.1), [] as Array[int])
	assert_almost_eq(CoreCharge.stored(), 0.3, 0.0001)
	assert_eq(CoreCharge.store(0.8), [50, 75] as Array[int])
	assert_eq(CoreCharge.store(1.0), [100] as Array[int])
	assert_eq(CoreCharge.beats_done(), [25, 50, 75, 100])


func test_glow_brightens_after_half_charge() -> void:
	assert_eq(CoreCharge.glow_for_flags(), CoreCharge.GLOW_DIM)
	CoreCharge.store(0.5)
	assert_eq(CoreCharge.glow_for_flags(), CoreCharge.GLOW_BRIGHT)
