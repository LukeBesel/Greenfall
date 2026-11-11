extends GutTest
## [events] World event director scheduling (systems/events.gd), the cleaning streak
## (systems/streak.gd), contracts (systems/contracts.gd) incl. persistence, and the Collection.

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


# --- Contracts -----------------------------------------------------------------------------------

func _offer_fn(_i: int) -> Dictionary:
	return Contracts.make_offer(Contracts.template("scoop"), 0)


func test_offer_uses_tier_numbers() -> void:
	var tpl: Dictionary = Contracts.template("clean_hexes")
	var o0: Dictionary = Contracts.make_offer(tpl, 0)
	var o3: Dictionary = Contracts.make_offer(tpl, 3)
	assert_eq(o0["state"], "offer")
	assert_eq(int(o0["n"]), int(tpl["n"][0]))
	assert_eq(int(o3["n"]), int(tpl["n"][3]))
	assert_eq(str(o0["pay"]), "parts", "[money] clean-hex requests pay parts")
	assert_true(int(o3["parts"]) > int(o0["parts"]), "later tiers pay a bit more")
	assert_eq(Contracts.tier_for(0), 0)
	assert_eq(Contracts.tier_for(500), 3)


func test_contract_requirements_filter_templates() -> void:
	var ids: Array = Contracts.available_templates({}, []).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_false("plant" in ids, "planting contracts wait for seeds")
	assert_true("scoop" in ids)
	var ids2: Array = Contracts.available_templates({"seeds_unlocked": true, "first_sprout": true}, ["scoop"]).map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_true("plant" in ids2 and "sustain" in ids2)
	assert_false("scoop" in ids2, "no duplicates on the board")


func test_contract_lifecycle_done_and_failed() -> void:
	Contracts.auto_accept = false  # [ui2] the old Accept / Pass flow (kept behind the flag)
	var st: Dictionary = Contracts.state()
	var stats: Dictionary = {"junk_scooped": 50.0}
	var vf := func(s: Dictionary) -> float: return Contracts.value_of(s, stats, 0)
	Contracts.step(st, 0.0, vf, _offer_fn)
	assert_eq(st["slots"].size(), int(Contracts.cfg()["slots"]), "board fills to its slot count")
	for s: Dictionary in st["slots"]:
		assert_eq(s["state"], "offer")
	var a: Dictionary = st["slots"][0]
	Contracts.accept_slot(a, vf.call(a))
	assert_eq(a["state"], "active")
	assert_eq(float(a["base"]), 50.0, "progress counts from when it was accepted")
	stats["junk_scooped"] = 50.0 + float(a["n"]) - 1.0
	Contracts.step(st, 1.0, vf, _offer_fn)
	assert_eq(a["state"], "active")
	stats["junk_scooped"] = 50.0 + float(a["n"])
	var ev: Array[Dictionary] = Contracts.step(st, 1.0, vf, _offer_fn)
	assert_eq(a["state"], "done")
	assert_eq(ev[0]["kind"], "done")
	# A second one runs out of time: it fails softly into a cooldown, then a new offer appears.
	var b: Dictionary = st["slots"][1]
	Contracts.accept_slot(b, vf.call(b))
	var evs: Array[Dictionary] = Contracts.step(st, float(b["time_s"]) + 1.0, vf, _offer_fn)
	assert_eq(st["slots"][1]["state"], "wait")
	assert_true(evs.any(func(e: Dictionary) -> bool: return e["kind"] == "failed"))
	Contracts.step(st, float(Contracts.cfg()["fail_cooldown_s"]) + 1.0, vf, _offer_fn)
	assert_eq(st["slots"][1]["state"], "offer")
	# Unaccepted offers rotate when they expire.
	var c: Dictionary = st["slots"][2]
	c["offer_left"] = 1.0
	var ev3: Array[Dictionary] = Contracts.step(st, 2.0, vf, _offer_fn)
	assert_true(ev3.any(func(e: Dictionary) -> bool: return e["kind"] == "offer" and e["i"] == 2))
	Contracts.auto_accept = true


## [ui2] The simple board: requests start on their own, count from when they were posted, never
## expire, and only need a Claim.
func test_requests_start_on_their_own_and_never_expire() -> void:
	assert_true(Contracts.auto_accept)
	var st: Dictionary = Contracts.state()
	st["slots"] = []
	var stats: Dictionary = {"junk_scooped": 10.0}
	var vf := func(s: Dictionary) -> float: return Contracts.value_of(s, stats, 0)
	Contracts.step(st, 0.0, vf, _offer_fn)
	for s: Dictionary in st["slots"]:
		assert_eq(s["state"], "active", "no Accept step")
		assert_eq(float(s["base"]), 10.0)
	var a: Dictionary = st["slots"][0]
	Contracts.step(st, float(a["time_s"]) * 3.0, vf, _offer_fn)
	assert_eq(a["state"], "active", "no time limit")
	stats["junk_scooped"] = 10.0 + float(a["n"])
	Contracts.step(st, 1.0, vf, _offer_fn)
	assert_eq(a["state"], "done")
	# An old save's open offer starts on the next tick.
	st["slots"][1] = Contracts.make_offer(Contracts.template("scoop"), 0)
	Contracts.step(st, 0.5, vf, _offer_fn)
	assert_eq(st["slots"][1]["state"], "active")


func test_peak_contract_tracks_streak() -> void:
	var st: Dictionary = Contracts.state()
	st["slots"] = [Contracts.make_offer(Contracts.template("streak"), 0)]
	var s: Dictionary = st["slots"][0]
	Contracts.accept_slot(s, 0.0)
	Contracts.note_peak("streak", 2)
	assert_eq(Contracts.count_of(s, Contracts.value_of(s, {}, 0)), 2.0)
	Contracts.note_peak("streak", 1)
	assert_eq(float(s["peak"]), 2.0, "peak never goes down")


func test_requests_persist() -> void:
	var st: Dictionary = Contracts.state()
	st["slots"] = [Contracts.make_offer(Contracts.template("perfect_bales"), 1), Contracts.wait_slot(33.0)]
	Contracts.accept_slot(st["slots"][0], 4.0)
	st["slots"][0]["left"] = 123.5
	st["done_total"] = 7
	GameState.flags["livery"] = "livery_neon"
	Collection.grant("golden_bolt", true)
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.from_dict(d)
	var st2: Dictionary = Contracts.state()
	assert_eq(st2["slots"][0]["state"], "active")
	assert_almost_eq(float(st2["slots"][0]["left"]), 123.5, 0.01)
	assert_almost_eq(float(st2["slots"][0]["base"]), 4.0, 0.01)
	assert_eq(str(st2["slots"][0]["tpl"]), "perfect_bales")
	assert_almost_eq(float(st2["slots"][1]["wait"]), 33.0, 0.01)
	assert_eq(int(st2["done_total"]), 7)
	assert_eq(Contracts.done_total(), 7)
	assert_eq(Liveries.equipped(), "livery_neon")
	assert_true(Collection.has("golden_bolt"))


func test_claim_pays_cubes_or_parts_and_milestone_trinket() -> void:
	var c := Contracts.new()
	var st: Dictionary = Contracts.state()
	var s: Dictionary = Contracts.make_offer(Contracts.template("scoop"), 0)
	s["state"] = "done"
	var p: Dictionary = Contracts.make_offer(Contracts.template("dig_parts"), 0)
	p["state"] = "done"
	st["slots"] = [s, Contracts.make_offer(Contracts.template("scoop"), 0), p]
	assert_eq(c.claim(1), 0.0, "an offer can't be claimed")
	var paid: float = c.claim(0)
	assert_true(paid >= float(WorldEvents.cfg().get("reward", {}).get("min_cubes", 0.0)), "a cube request pays progress-scaled cubes")
	assert_almost_eq(GameState.get_currency("cubes").to_float(), paid, 0.01)
	assert_eq(st["slots"][0]["state"], "wait")
	assert_true(Collection.has("contract_pen"), "first request unlocks its collectible")
	assert_almost_eq(c.claim(2), float(p["parts"]), 0.01)
	assert_almost_eq(GameState.get_currency("parts").to_float(), float(p["parts"]), 0.01, "a parts request pays parts")
	assert_eq(Contracts.done_total(), 2)
	c.free()


func test_reward_track_pays_capsules_and_parts_never_looks() -> void:
	# Looks are found in the world: the track hands out Curio Capsules and Parts only.
	var c := Contracts.new()
	var pieces_before: int = Looks.found().size()
	for t: Dictionary in Contracts.track():
		assert_true(str(t.get("kind", "")) in ["capsule", "part"], "step %d: %s" % [int(t.get("n", 0)), t.get("kind", "")])
	var before: float = GameState.get_currency("parts").to_float()
	c.count_done(20 + 5)  # past the last step (20): one repeat Vintage part per repeat_every
	assert_true(GameState.get_currency("parts").to_float() >= before + RobotParts.value(4) * 2.0 + RobotParts.value(3) * 2.0 - 0.01, "[ui2] the track's rare robot parts pay Parts")
	assert_eq(GameState.parts.size(), 0, "no robot part items")
	assert_eq(Looks.found().size(), pieces_before, "no look came from the track")
	assert_eq(str(GameState.flags.get("livery", "")), "", "and no fleet mark")
	c.free()


func test_world_events_count_as_requests() -> void:
	var c := Contracts.new()
	GameState.stats["ev_events_done"] = 4.0
	c._count_events()
	assert_eq(Contracts.done_total(), 0, "the first look only sets the baseline")
	GameState.stats["ev_events_done"] = 6.0
	c._count_events()
	assert_eq(Contracts.done_total(), 2)
	c.free()


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
