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
	# [beat] Three thriving districts are no longer the finale; the Cradle path is.
	assert_lt(CoreCharge.bloom_progress({"thriving_hexes": 0, "thriving_districts": 3, "planet_pct": 0.0}), 1.0)
	assert_eq(CoreCharge.bloom_progress({"cradle_returned": 1.0}), 1.0)
	assert_almost_eq(CoreCharge.bloom_progress({"campaign": 0.4}), 0.4, 0.001)


func test_campaign_progress_steps_along_the_cradle_path() -> void:
	var fh: Dictionary = {"dust_flats": 50, "frozen_port": 51, "sunken_city": 52, "cradle_returns": 53}
	var saved: Dictionary = GameState.flags.duplicate(true)
	var saved_d: Dictionary = GameState.districts.duplicate(true)
	GameState.flags.erase("cradle_returned")
	for k: String in ["dust_flats", "frozen_port", "sunken_city", "cradle_returns"]:
		GameState.flags.erase("frontier_seen_" + k)
	var p0: float = CoreCharge.campaign_progress(fh)
	GameState.flags["frontier_seen_dust_flats"] = true
	GameState.districts[50] = {"hub_level": 5, "frontier": {"growing_frac": 0.5}}
	var p1: float = CoreCharge.campaign_progress(fh)
	assert_gt(p1 - p0, 0.21, "a finished frontier is worth about a fifth of the path")
	GameState.flags["cradle_returned"] = true
	assert_eq(CoreCharge.campaign_progress(fh), 1.0)
	GameState.flags = saved
	GameState.districts = saved_d


func test_store_never_drops_and_records_beats_once() -> void:
	assert_eq(CoreCharge.store(0.2), [] as Array[int])
	assert_eq(CoreCharge.store(0.3), [25] as Array[int])
	assert_eq(CoreCharge.store(0.1), [] as Array[int])
	assert_almost_eq(CoreCharge.stored(), 0.3, 0.0001)
	# [pace2] On Verdance the core stops at the cap of the tech found so far (later planets).
	var keep: Dictionary = CradleMode.profile.duplicate(true)
	var keep_p: bool = CradleMode.persist
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()
	assert_eq(CoreCharge.store(0.8), [50] as Array[int], "75% waits for the Deep Drill")
	assert_almost_eq(CoreCharge.stored(), Homeward.cap_for(0), 0.0001)
	for t: Dictionary in Homeward.tech_defs():
		Homeward.techs().append(str(t["id"]))
	assert_eq(CoreCharge.store(0.8), [75] as Array[int])
	assert_eq(CoreCharge.store(1.0), [100] as Array[int])
	CradleMode.profile = keep
	CradleMode.persist = keep_p
	assert_eq(CoreCharge.beats_done(), [25, 50, 75, 100])


func test_glow_brightens_after_half_charge() -> void:
	assert_eq(CoreCharge.glow_for_flags(), CoreCharge.GLOW_DIM)
	CoreCharge.store(0.5)
	assert_eq(CoreCharge.glow_for_flags(), CoreCharge.GLOW_BRIGHT)
