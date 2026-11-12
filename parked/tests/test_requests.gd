extends GutTest
## Parked in task M3-13 with the Requests board (parked/side/requests/): the contract tests cut
## from tests/test_events.gd. They do not run.

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


# Cut from tests/test_onboard.gd.
func test_requests_unlock_later() -> void:
	var st: Dictionary = {"slots": [], "done_total": 0}
	assert_false(Contracts.unlock_due(1, 600.0, st), "not in the first minutes")
	assert_false(Contracts.unlock_due(2, 1800.0, st))
	assert_true(Contracts.unlock_due(3, 60.0, st), "base level 3")
	assert_true(Contracts.unlock_due(1, 2700.0, st), "or 45 minutes")
	assert_true(Contracts.unlock_due(1, 10.0, {"slots": [{"state": "active"}], "done_total": 0}), "a save already using it")
	assert_true(Contracts.unlock_due(1, 10.0, {"slots": [], "done_total": 2}))


# Cut from tests/test_robot_builder.gd and tests/test_crew_looks.gd: the track gives no looks.
func test_the_track_hands_out_no_looks() -> void:
	for t: Dictionary in Contracts.track():
		assert_true(str(t.get("kind", "")) in ["capsule", "part"], "the Requests track hands out no looks (%s)" % t.get("kind", ""))
