extends GutTest
## [scope] Remote progress maths (systems/remote_progress.gd) and its caps.

const FLEET: Array = [{"type": "scoopie", "tier": 1}, {"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}]

var _keep_world: Dictionary
var _keep_cubes: BigNum
var _keep_last: int
var _keep_saved: float
var _keep_persist: bool


func before_each() -> void:
	_keep_world = GameState.world.duplicate(true)
	_keep_cubes = GameState.get_currency("cubes")
	_keep_last = RemoteProgress.last_world
	_keep_saved = GameState.saved_unix
	_keep_persist = CradleMode.persist
	CradleMode.persist = false


func after_each() -> void:
	GameState.world = _keep_world
	GameState.currencies["cubes"] = _keep_cubes
	RemoteProgress.last_world = _keep_last
	GameState.saved_unix = _keep_saved
	CradleMode.persist = _keep_persist


func test_remote_is_a_fraction_of_offline() -> void:
	var off: Dictionary = Offline.compute(FLEET, 0, 0.0, 3600.0)
	var rem: Dictionary = RemoteProgress.compute(FLEET, 3600.0, INF, 0.0, 1.0, 0.5)
	assert_gt(float(off["cubes"]), 0.0)
	assert_almost_eq(float(rem["cubes"]), float(off["cubes"]) * 0.5, 0.001, "half the offline rate")
	assert_almost_eq(float(rem["units"]), float(off["units"]) * 0.5, 0.001)
	assert_eq(float(rem["air"]), 0.0, "no scrubber payout from afar")


func test_default_factor_from_data() -> void:
	assert_almost_eq(RemoteProgress.factor(), 0.5, 0.0001)
	var a: Dictionary = RemoteProgress.compute(FLEET, 600.0)
	var b: Dictionary = RemoteProgress.compute(FLEET, 600.0, INF, 0.0, 1.0, 0.5)
	assert_almost_eq(float(a["cubes"]), float(b["cubes"]), 0.0001)


func test_capped_by_offline_cap() -> void:
	var a: Dictionary = RemoteProgress.compute(FLEET, Offline.CAP_S)
	var b: Dictionary = RemoteProgress.compute(FLEET, Offline.CAP_S * 20.0)
	assert_almost_eq(float(a["cubes"]), float(b["cubes"]), 0.001, "same 8 h cap as offline")
	assert_almost_eq(float(b["elapsed"]), Offline.CAP_S, 0.001)


func test_capped_by_junk_left_after_scaling() -> void:
	var r: Dictionary = RemoteProgress.compute(FLEET, Offline.CAP_S, 40.0)
	assert_almost_eq(float(r["units"]), 40.0, 0.001, "never bales more than is left")
	var none: Dictionary = RemoteProgress.compute(FLEET, Offline.CAP_S, 0.0)
	assert_eq(float(none["cubes"]), 0.0, "a clean district pays nothing")


func test_no_robots_no_gain() -> void:
	var r: Dictionary = RemoteProgress.compute([], 3600.0)
	assert_eq(float(r["cubes"]) + float(r["waiting_value"]), 0.0)


func test_boost_overlap_and_effective_seconds() -> void:
	assert_almost_eq(RemoteProgress.boost_overlap(0.0, 1000.0, 200.0, 500.0), 300.0, 0.001)
	assert_almost_eq(RemoteProgress.boost_overlap(0.0, 300.0, 200.0, 500.0), 100.0, 0.001)
	assert_eq(RemoteProgress.boost_overlap(600.0, 900.0, 200.0, 500.0), 0.0, "boost before the window")
	assert_almost_eq(RemoteProgress.effective_seconds(1000.0, 300.0, 2.0), 1300.0, 0.001)
	assert_almost_eq(RemoteProgress.effective_seconds(100.0, 300.0, 2.0), 200.0, 0.001, "boost can't exceed time away")
	assert_almost_eq(RemoteProgress.effective_seconds(Offline.CAP_S, 300.0, 2.0), Offline.CAP_S, 0.001, "boost can't pass the cap")
	assert_eq(RemoteProgress.effective_seconds(-50.0), 0.0)


func test_care_package_extra_is_capped_below_its_cost() -> void:
	var big: Array = []
	for i: int in 18:
		big.append({"type": "scoopie", "tier": 3})
	big.append({"type": "haulbug", "tier": 3})
	var base: Dictionary = RemoteProgress.compute(big, 3600.0)
	var boosted: Dictionary = RemoteProgress.compute_boosted(big, 3600.0, INF, 300.0)
	var extra: float = float(boosted["cubes"]) - float(base["cubes"])
	assert_gt(extra, 0.0, "a care package helps")
	assert_true(extra <= RemoteProgress.care_cost() * 0.75 + 0.01, "but never pays back more than 75%% of its cost (%.1f)" % extra)


func test_share_and_hex_states() -> void:
	var clean := PackedByteArray([1, 0, 1, 1, 0, 1])
	var levels := PackedByteArray([0, 0, 1, 3, 0, 0])
	# hex 0 base, 1 junk, 2 clean, 3 green, 4 junk, 5 base/blocked -> 2 of 4 land hexes done
	assert_almost_eq(RemoteProgress.district_share(clean, levels), 0.5, 0.0001)
	assert_eq(RemoteProgress.hex_state(1, 0), -1)
	assert_eq(RemoteProgress.hex_state(0, 0), 0)
	assert_eq(RemoteProgress.hex_state(1, 1), 1)
	assert_eq(RemoteProgress.hex_state(1, 4), 2)


func test_snapshot_from_save_is_read_only_and_complete() -> void:
	var n: int = Hex.spiral(3).size()
	var clean := PackedByteArray()
	clean.resize(n)
	clean[0] = 1
	clean[1] = 1
	var lv := PackedByteArray()
	lv.resize(n)
	lv[1] = 2
	var save: Dictionary = {"saved_unix": 1000.0, "current_hub": 2, "flags": {"ledger_act": 3},
		"districts": {"2": {"hub_level": 4, "offline_units": 12.0, "robots": [{"type": "drip", "tier": 2, "pos": [0, 0, 0]}],
			"field": {"radius": 3, "clean": Marshalls.raw_to_base64(clean)}, "hex_levels": {"levels": Marshalls.raw_to_base64(lv)}}}}
	var before: String = JSON.stringify(save)
	var s: Dictionary = RemoteProgress.snapshot_from_save(save, {"name": "Rime", "index": 3, "type": "ice_moon"})
	assert_eq(JSON.stringify(save), before, "the save dict is not changed")
	assert_eq(int(s["hub_level"]), 4)
	assert_eq(int(s["junk_hexes"]), n - 2)
	assert_eq((s["robots"] as Array).size(), 1)
	assert_eq(int(s["ledger_act"]), 3)
	assert_eq(str(s["name"]), "Rime")
	assert_almost_eq(RemoteProgress.junk_left(s), (n - 2) * RemoteProgress.AVG_HEX_UNITS - 12.0, 0.01)


func test_pending_grows_with_time_and_stops_at_cap() -> void:
	RemoteProgress.make_sample()
	var snap: Dictionary = RemoteProgress.sample["snap"]
	var w: Dictionary = RemoteProgress.sample["world"]
	var t0: float = float(snap["saved_unix"])
	var a: Dictionary = RemoteProgress.pending(snap, w, t0 + 600.0)
	var b: Dictionary = RemoteProgress.pending(snap, w, t0 + 1200.0)
	var c: Dictionary = RemoteProgress.pending(snap, w, t0 + 30.0 * 3600.0)
	var d: Dictionary = RemoteProgress.pending(snap, w, t0 + 60.0 * 3600.0)
	assert_gt(float(b["units"]), float(a["units"]))
	assert_almost_eq(float(c["units"]), float(d["units"]), 0.001)
	RemoteProgress.sample = {}


func test_arrival_pays_only_after_world_travel() -> void:
	GameState.world = {"robots": FLEET.duplicate(true)}
	GameState.currencies["cubes"] = BigNum.from_float(0.0)
	var now: float = 100000.0
	GameState.saved_unix = now - 3600.0
	# Cold start (not reloaded in memory): the offline payout handles it, remote pays nothing.
	RemoteProgress.last_world = CradleMode.current_index() + 1
	assert_true(RemoteProgress.on_district_ready(false, now).is_empty())
	# Rocket travel inside the same world: nothing either.
	RemoteProgress.last_world = CradleMode.current_index()
	assert_true(RemoteProgress.on_district_ready(true, now).is_empty())
	# Arriving from another world: paid once, counted against the junk left.
	RemoteProgress.last_world = CradleMode.current_index() + 1
	var r: Dictionary = RemoteProgress.on_district_ready(true, now)
	assert_false(r.is_empty())
	assert_gt(GameState.get_currency("cubes").to_float(), 0.0)
	assert_almost_eq(float(GameState.world.get("offline_units", 0.0)), float(r["units"]), 0.001)
	assert_eq(RemoteProgress.last_world, CradleMode.current_index())
	# A second district start in the same world pays nothing more.
	var cubes: float = GameState.get_currency("cubes").to_float()
	assert_true(RemoteProgress.on_district_ready(true, now).is_empty())
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cubes, 0.001)


func test_short_absence_pays_nothing() -> void:
	GameState.world = {"robots": FLEET.duplicate(true)}
	var now: float = 50000.0
	GameState.saved_unix = now - 60.0
	RemoteProgress.last_world = CradleMode.current_index() + 1
	assert_true(RemoteProgress.on_district_ready(true, now).is_empty(), "under min_away_s")


func test_care_package_spend_and_one_at_a_time() -> void:
	var w: Dictionary = {"index": 77, "name": "Test"}
	GameState.currencies["cubes"] = BigNum.from_float(RemoteProgress.care_cost() * 3.0)
	assert_eq(RemoteProgress.care_block_reason(w, 1000.0), "")
	assert_true(RemoteProgress.send_care(w, 1000.0))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), RemoteProgress.care_cost() * 2.0, 0.01)
	assert_false(RemoteProgress.send_care(w, 1100.0), "one at a time")
	assert_almost_eq(RemoteProgress.boost_left(w, 1100.0), float(RemoteProgress.care_cfg()["boost_s"]) - 100.0, 0.01)
	assert_true(RemoteProgress.send_care(w, 1000.0 + float(RemoteProgress.care_cfg()["boost_s"]) + 1.0), "again once it's over")
	GameState.currencies["cubes"] = BigNum.from_float(1.0)
	assert_ne(RemoteProgress.care_block_reason({"index": 78}, 0.0), "", "needs cubes")
