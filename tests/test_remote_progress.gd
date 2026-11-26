extends GutTest
## [scope] Remote progress maths (systems/remote_progress.gd) and its caps.

const FLEET: Array = [{"type": "scoopie", "tier": 1}, {"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}]

var _keep_cubes: BigNum
var _keep_persist: bool
var _keep_profile: Dictionary
var _keep_saved: float


func before_each() -> void:
	_keep_cubes = GameState.get_currency("cubes")
	_keep_persist = CradleMode.persist
	_keep_profile = CradleMode.profile.duplicate(true)
	CradleMode.persist = false
	RemoteProgress._acc = 0.0
	_keep_saved = GameState.saved_unix


func after_each() -> void:
	GameState.currencies["cubes"] = _keep_cubes
	CradleMode.persist = _keep_persist
	CradleMode.profile = _keep_profile
	RemoteProgress._acc = 0.0
	RemoteProgress._dirty = false
	GameState.saved_unix = _keep_saved


func test_remote_is_a_fraction_of_the_full_rate() -> void:
	var full: Dictionary = CrewRate.fleet_work(FLEET, 3600.0)
	var rem: Dictionary = RemoteProgress.compute(FLEET, 3600.0, INF, 0.0, 1.0, 0.25)
	assert_gt(float(full["cubes"]), 0.0)
	assert_almost_eq(float(rem["cubes"]), float(full["cubes"]) * 0.25, 0.001, "a quarter of the rate at home")
	assert_almost_eq(float(rem["units"]), float(full["units"]) * 0.25, 0.001)


func test_default_factor_from_data() -> void:
	assert_almost_eq(RemoteProgress.factor(), 0.25, 0.0001)
	var a: Dictionary = RemoteProgress.compute(FLEET, 600.0)
	var b: Dictionary = RemoteProgress.compute(FLEET, 600.0, INF, 0.0, 1.0, 0.25)
	assert_almost_eq(float(a["cubes"]), float(b["cubes"]), 0.0001)


func test_capped_at_eight_hours_of_play_elsewhere() -> void:
	var a: Dictionary = RemoteProgress.compute(FLEET, RemoteProgress.CAP_S)
	var b: Dictionary = RemoteProgress.compute(FLEET, RemoteProgress.CAP_S * 20.0)
	assert_almost_eq(float(a["cubes"]), float(b["cubes"]), 0.001, "one stay elsewhere pays for 8 h of play at most")
	assert_almost_eq(float(b["elapsed"]), RemoteProgress.CAP_S, 0.001)


func test_capped_by_junk_left() -> void:
	var r: Dictionary = RemoteProgress.compute(FLEET, RemoteProgress.CAP_S, 40.0)
	assert_almost_eq(float(r["units"]), 40.0, 0.001, "never bales more than is left")
	var none: Dictionary = RemoteProgress.compute(FLEET, RemoteProgress.CAP_S, 0.0)
	assert_eq(float(none["cubes"]), 0.0, "a clean district pays nothing")


func test_no_robots_no_gain() -> void:
	var r: Dictionary = RemoteProgress.compute([], 3600.0)
	assert_eq(float(r["cubes"]) + float(r["waiting_value"]), 0.0)


func test_effective_seconds() -> void:
	assert_almost_eq(RemoteProgress.effective_seconds(1000.0, 300.0, 2.0), 1300.0, 0.001)
	assert_almost_eq(RemoteProgress.effective_seconds(100.0, 300.0, 2.0), 200.0, 0.001, "boost can't exceed time away")
	assert_almost_eq(RemoteProgress.effective_seconds(RemoteProgress.CAP_S, 300.0, 2.0), RemoteProgress.CAP_S, 0.001, "boost can't pass the cap")
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
		"districts": {"2": {"hub_level": 4, "robots": [{"type": "drip", "tier": 2, "pos": [0, 0, 0]}],
			"field": {"radius": 3, "clean": Marshalls.raw_to_base64(clean)}, "hex_levels": {"levels": Marshalls.raw_to_base64(lv)}}}}
	var before: String = JSON.stringify(save)
	var s: Dictionary = RemoteProgress.snapshot_from_save(save, {"name": "Rime", "index": 3, "type": "ice_moon"})
	assert_eq(JSON.stringify(save), before, "the save dict is not changed")
	assert_eq(int(s["hub_level"]), 4)
	assert_eq(int(s["junk_hexes"]), n - 2)
	assert_eq((s["robots"] as Array).size(), 1)
	assert_false(s.has("ledger_act"), "an old save's Ledger flag is ignored")
	assert_eq(str(s["name"]), "Rime")
	assert_almost_eq(RemoteProgress.junk_left(s), (n - 2) * RemoteProgress.AVG_HEX_UNITS, 0.01)


func test_pending_grows_with_play_time_and_stops_at_cap() -> void:
	RemoteProgress.make_sample()
	var snap: Dictionary = RemoteProgress.sample["snap"]
	var w: Dictionary = (RemoteProgress.sample["world"] as Dictionary).duplicate(true)
	w["away_s"] = 600.0
	var a: Dictionary = RemoteProgress.pending(snap, w)
	RemoteProgress.add_away(w, 600.0)
	var b: Dictionary = RemoteProgress.pending(snap, w)
	RemoteProgress.add_away(w, 30.0 * 3600.0)
	var c: Dictionary = RemoteProgress.pending(snap, w)
	RemoteProgress.add_away(w, 30.0 * 3600.0)
	var d: Dictionary = RemoteProgress.pending(snap, w)
	assert_gt(float(b["units"]), float(a["units"]))
	assert_almost_eq(float(c["units"]), float(d["units"]), 0.001)
	assert_almost_eq(RemoteProgress.away_s(w), RemoteProgress.CAP_S, 0.001)
	RemoteProgress.sample = {}


## Owner item 110: "They work when I am ... on different planets but not when i log off". The
## count is fed by play seconds only: with no tick() nothing moves, whatever the system clock or
## the save's stamp say.
func test_only_play_time_counts_for_the_other_worlds() -> void:
	CradleMode.profile = CradleMode.default_profile()
	var here: Dictionary = CradleMode.current_world()
	RemoteProgress.make_sample()  # one other visited world
	var other: Dictionary = RemoteProgress.sample["world"]
	other.erase("away_s")
	var mine: Dictionary = {"index": 91, "name": "Other", "slot": -1}
	# The sample itself is a picture for screenshots and never counts; a real record does.
	for i: int in 25:
		RemoteProgress.tick(0.1)
	assert_eq(RemoteProgress.away_s(other), 0.0, "the screenshot sample does not count")
	assert_eq(RemoteProgress.away_s(here), 0.0, "the world Lumi stands on never counts as away")
	RemoteProgress.add_away(mine, 2.5)
	assert_almost_eq(RemoteProgress.away_s(mine), 2.5, 0.001)
	# Hours on the wall clock with the game closed or paused (no tick): nothing changes.
	GameState.saved_unix = Time.get_unix_time_from_system() - 86400.0
	assert_almost_eq(RemoteProgress.away_s(mine), 2.5, 0.001)
	assert_eq(float(RemoteProgress.pending({"robots": FLEET, "junk_hexes": 30}, {})["units"]), 0.0, "no play time elsewhere, nothing waiting")
	RemoteProgress.sample = {}


func test_arrival_with_no_crew_pays_nothing_and_clears_the_count() -> void:
	CradleMode.profile = CradleMode.default_profile()
	var w: Dictionary = CradleMode.current_world()
	w["away_s"] = 3600.0
	w["boost_used_s"] = 100.0
	GameState.currencies["cubes"] = BigNum.from_float(0.0)
	assert_true(RemoteProgress.arrive(null).is_empty())
	assert_eq(GameState.get_currency("cubes").to_float(), 0.0)
	assert_false(w.has("away_s"), "the count is used up: it can never pay twice")
	assert_false(w.has("boost_used_s"))


func test_care_package_runs_on_play_time() -> void:
	var w: Dictionary = {"index": 77, "name": "Test"}
	var boost_s: float = float(RemoteProgress.care_cfg()["boost_s"])
	GameState.currencies["cubes"] = BigNum.from_float(RemoteProgress.care_cost() * 3.0)
	assert_eq(RemoteProgress.care_block_reason(w), "")
	assert_true(RemoteProgress.send_care(w))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), RemoteProgress.care_cost() * 2.0, 0.01)
	assert_false(RemoteProgress.send_care(w), "one at a time")
	RemoteProgress.add_away(w, 100.0)
	assert_almost_eq(RemoteProgress.boost_left(w), boost_s - 100.0, 0.01)
	assert_almost_eq(RemoteProgress.boost_used(w), 100.0, 0.01)
	RemoteProgress.add_away(w, boost_s)
	assert_eq(RemoteProgress.boost_left(w), 0.0)
	assert_almost_eq(RemoteProgress.boost_used(w), boost_s, 0.01, "the package worked its seconds and no more")
	assert_true(RemoteProgress.send_care(w), "again once it's over")
	GameState.currencies["cubes"] = BigNum.from_float(1.0)
	assert_ne(RemoteProgress.care_block_reason({"index": 78}), "", "needs cubes")
