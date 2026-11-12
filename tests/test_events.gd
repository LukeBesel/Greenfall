extends GutTest
## [events] World event director scheduling (systems/events.gd), the cleaning streak
## (systems/streak.gd) and the Collection.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _parts: Array


func before_each() -> void:
	_parts = GameState.parts.duplicate(true)  # [money] the reward track prints robot parts
	GameState.parts = []
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	GameState.parts = _parts


# --- Director scheduling ------------------------------------------------------------------------

func test_next_delay_stays_in_range() -> void:
	var s: Dictionary = {"every_s": [240, 480]}
	assert_eq(WorldEvents.next_delay(0.0, s), 240.0)
	assert_eq(WorldEvents.next_delay(1.0, s), 480.0)
	assert_eq(WorldEvents.next_delay(0.5, s), 360.0)
	assert_eq(WorldEvents.next_delay(7.0, s), 480.0, "clamped")
	var real: Dictionary = WorldEvents.sched()
	assert_true(float(real["every_s"][0]) >= 180.0, "events stay a few minutes apart (not a flood)")
	assert_true(float(real["every_s"][1]) <= 600.0)


func test_pick_event_respects_eligibility_and_recent() -> void:
	var defs: Array = [{"id": "a", "weight": 1}, {"id": "b", "weight": 1}, {"id": "c", "weight": 1}]
	var elig: Dictionary = {"a": true, "b": false, "c": true}
	for r: float in [0.0, 0.3, 0.6, 0.99]:
		var id: String = WorldEvents.pick_event(defs, elig, [], r)
		assert_true(id in ["a", "c"], "never picks an ineligible event")
	# "a" was just played: with no_repeat it is skipped while another eligible one exists.
	for r: float in [0.0, 0.5, 0.99]:
		assert_eq(WorldEvents.pick_event(defs, elig, ["a"], r, 1), "c")
	# Only a recent one left: it is allowed again rather than nothing.
	assert_eq(WorldEvents.pick_event(defs, {"a": true}, ["a"], 0.5, 2), "a")
	assert_eq(WorldEvents.pick_event(defs, {}, [], 0.5), "", "nothing eligible -> no event")


func test_pick_event_is_weighted() -> void:
	var defs: Array = [{"id": "x", "weight": 3}, {"id": "y", "weight": 1}]
	var elig: Dictionary = {"x": true, "y": true}
	assert_eq(WorldEvents.pick_event(defs, elig, [], 0.0), "x")
	assert_eq(WorldEvents.pick_event(defs, elig, [], 0.74), "x")
	assert_eq(WorldEvents.pick_event(defs, elig, [], 0.76), "y")


func test_eligibility_from_context() -> void:
	var early: Dictionary = WorldEvents.eligible_ids({"junk_hexes": 30, "planted": 0, "robots": 0, "max_hex_level": 1, "ledger_resolved": false, "parts_left": 3, "flags": {"has_baler": true, "has_signal_finder": true}})
	assert_false(early["supply_drop"], "[pace] no crates out of the sky")
	assert_true(early["salvage_surge"])
	assert_true(early["rare_part_signal"])
	assert_false(early["rain_shower"], "rain needs plants")
	assert_false(early["robot_hiccup"], "hiccup needs a robot")
	assert_false(early["wildlife_visit"], "wildlife needs a Sustained hex")
	assert_false(early["ledger_audit"], "audit waits for the Ledger arc")
	var fresh: Dictionary = WorldEvents.eligible_ids({"junk_hexes": 30, "parts_left": 3, "flags": {}})  # [pace]
	assert_false(fresh["rare_part_signal"], "the violet beam needs the Signal Finder")
	assert_false(fresh["salvage_surge"], "bale bonuses need the Baler")
	var late: Dictionary = WorldEvents.eligible_ids({"junk_hexes": 0, "planted": 40, "robots": 6, "max_hex_level": 5, "ledger_resolved": true, "parts_left": 0})
	assert_false(late["supply_drop"])
	assert_false(late["rare_part_signal"])
	assert_true(late["rain_shower"])
	assert_true(late["robot_hiccup"])
	assert_true(late["wildlife_visit"])
	assert_false(late["ledger_audit"], "the audit needs junk to race over")


func test_reward_scaling_is_a_spike_not_a_flood() -> void:
	assert_eq(WorldEvents.scaled_cubes(0.0, 0.0, 90.0, 0.004, 40.0), 40.0, "floor early on")
	assert_eq(WorldEvents.scaled_cubes(100.0, 0.0, 90.0, 0.004, 40.0), 9000.0, "about income_s of income")
	assert_eq(WorldEvents.scaled_cubes(1.0, 1.0e7, 90.0, 0.004, 40.0), 40000.0, "lifetime floor")


func test_director_state_persists_in_flags() -> void:
	var st: Dictionary = WorldEvents.persist_state()
	assert_almost_eq(float(st["next_in"]), float(WorldEvents.sched()["first_after_s"]), 0.01)
	st["next_in"] = 77.0
	st["recent"] = ["salvage_surge"]
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(d)
	assert_almost_eq(float(WorldEvents.persist_state()["next_in"]), 77.0, 0.01)
	assert_eq(WorldEvents.persist_state()["recent"], ["salvage_surge"])


# --- Streak --------------------------------------------------------------------------------------

func test_streak_tiers_and_bonus() -> void:
	var s := Streak.new({"per_tier": 10, "max_tier": 3, "bonus_per_tier": 0.05, "grace_s": 2.0, "drain_per_s": 5.0, "cap_extra": 0.5})
	assert_eq(s.tier(), 0)
	var ups: Array[int] = []
	for i: int in 40:
		var u: int = s.add_scoop()
		if u > 0:
			ups.append(u)
	assert_eq(ups, [1, 2, 3], "tier-up reported once per tier")
	assert_eq(s.tier(), 3, "capped at max tier")
	assert_almost_eq(s.points, 35.0, 0.001, "points capped at max + cap_extra")
	assert_almost_eq(s.bonus(), 0.15, 0.0001)
	assert_eq(s.fill(), 1.0)


func test_streak_drains_gently_after_grace() -> void:
	var s := Streak.new({"per_tier": 10, "max_tier": 5, "grace_s": 2.0, "drain_per_s": 5.0})
	s.add_scoop(25.0)
	assert_eq(s.tier(), 2)
	s.tick(1.9)
	assert_eq(s.points, 25.0, "no drain inside the grace period (e.g. while baling)")
	s.tick(1.0)
	assert_true(s.points < 25.0 and s.points > 15.0, "drains slowly, not a hard reset")
	for i: int in 20:
		s.tick(1.0)
	assert_eq(s.points, 0.0)
	assert_eq(s.tier(), 0)
	assert_false(s.active())


func test_streak_bale_peak() -> void:
	var s := Streak.new({"per_tier": 10, "max_tier": 5, "bonus_per_tier": 0.04, "grace_s": 0.5, "drain_per_s": 100.0})
	s.add_scoop(30.0)
	s.tick(1.0)  # drained to zero while walking to the scale
	assert_eq(s.tier(), 0)
	assert_almost_eq(s.take_bale_peak(), 0.12, 0.0001, "bale keeps the best tier reached while it filled")
	assert_eq(s.take_bale_peak(), 0.0, "peak resets after a bale")


# --- Collection ----------------------------------------------------------------------------------

func test_collection_roll_and_grant() -> void:
	assert_eq(Collection.count(), 0)
	var all: Array[String] = Collection.unfound("capsule")
	assert_true(all.size() >= 3)
	var id: String = Collection.roll("capsule", 0.0)
	assert_true(Collection.grant(id, true))
	assert_false(Collection.grant(id, true), "no duplicates")
	assert_false(id in Collection.unfound("capsule"))
	for t: String in Collection.unfound("capsule"):
		Collection.grant(t, true)
	assert_eq(Collection.roll("capsule", 0.5), "", "complete source rolls nothing")
	for t: Dictionary in Collection.defs():
		assert_ne(Collection.source_name(str(t["source"])), "", "every trinket has a source")
