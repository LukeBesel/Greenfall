extends GutTest
## The fast balance simulator (tools/pace_sim): it runs on any registered planet, leaves the
## game's state alone, gives the same answer twice and is fast enough to tune with.

const FIXTURES: String = "res://tests/fixtures/planets"
const DUMMY: StringName = &"testworld"
const FOUR_HOURS_MIN: float = 240.0
const TIME_LIMIT_MS: int = 10000
## The sensitivity study must cover this many constants.
const SENSITIVE_CONSTANTS: int = 8

## The default player's run of the redesign proposal, played once and shared by the tests below.
var _redesign: Dictionary = {}


func before_each() -> void:
	Planets.register_dir(FIXTURES)


func after_each() -> void:
	Planets.set_current(Planets.first_shipped().id)
	Planets.unregister(DUMMY)


func test_runs_on_the_first_planet_and_reaches_the_early_beats() -> void:
	var result: Dictionary = PaceSim.run(Planets.first_shipped().id, 60.0)
	assert_true(result["ok"], str(result["error"]))
	assert_true(result["content"], "the first planet has content to simulate")
	var model: PaceSimModel = result["model"]
	for beat: String in ["first_payout", "first_upgrade", "hexes_1", "first_robot"]:
		assert_true(model.record.beats.has(beat), "beat '%s' happens in the first hour" % beat)
	assert_gt(model.work.hexes_done, 3, "hexes get cleaned")
	assert_gt((result["report"]["checks"] as Array).size(), 8, "every cadence rule is checked")
	assert_gt(PaceSim.summary(result).size(), 10, "the report prints")


func test_runs_on_the_dummy_planet_without_errors() -> void:
	# The dummy planet has small real tables (so a world can be built from it); the simulator must
	# run on whatever a planet provides and say so plainly if something it needs is missing.
	var result: Dictionary = PaceSim.run(DUMMY, 30.0)
	assert_true(result["ok"], str(result["error"]))
	assert_gt(PaceSim.summary(result).size(), 0, "the report prints")
	if not result["content"]:
		assert_string_contains("\n".join(PaceSim.summary(result)), "no content")


func test_same_seed_gives_the_same_run() -> void:
	var id: StringName = Planets.first_shipped().id
	var a: Dictionary = PaceSim.run(id, 45.0, PaceSim.DEFAULT_POLICY, 7)
	var b: Dictionary = PaceSim.run(id, 45.0, PaceSim.DEFAULT_POLICY, 7)
	assert_eq((a["model"] as PaceSimModel).record.csv(), (b["model"] as PaceSimModel).record.csv(), "the time series match")
	assert_eq((a["model"] as PaceSimModel).record.beats, (b["model"] as PaceSimModel).record.beats, "the beats match")


func test_four_hours_run_in_under_ten_seconds() -> void:
	var result: Dictionary = PaceSim.run(Planets.first_shipped().id, FOUR_HOURS_MIN)
	assert_true(result["ok"], str(result["error"]))
	assert_lt(int(result["real_ms"]), TIME_LIMIT_MS, "a 4-hour game took %d ms" % int(result["real_ms"]))
	assert_eq((result["model"] as PaceSimModel).record.minutes.size(), int(FOUR_HOURS_MIN), "one time-series row per minute")


func test_the_game_state_is_left_as_it_was() -> void:
	GameState.upgrades["pace_sim_marker"] = 3
	GameState.flags["pace_sim_marker"] = true
	var planet_before: StringName = Planets.current_id()
	PaceSim.run(Planets.first_shipped().id, 20.0)
	PaceSim.run(DUMMY, 5.0)
	assert_eq(int(GameState.upgrades.get("pace_sim_marker", 0)), 3, "upgrade levels are put back")
	assert_true(GameState.flags.get("pace_sim_marker", false), "flags are put back")
	assert_eq(Planets.current_id(), planet_before, "the current planet is put back")
	GameState.upgrades.erase("pace_sim_marker")
	GameState.flags.erase("pace_sim_marker")


func test_unknown_planet_or_policy_is_an_error_not_a_crash() -> void:
	assert_false(PaceSim.run(&"no_such_planet", 5.0)["ok"])
	assert_false(PaceSim.run(Planets.first_shipped().id, 5.0, "no_such_policy")["ok"])


# --- The redesign model (--model=redesign) and its proposal data set ---

func _default_redesign() -> Dictionary:
	if _redesign.is_empty():
		_redesign = PaceSimRedesign.run()
	return _redesign


func _assert_checks_pass(checks: Array) -> void:
	for check: Dictionary in checks:
		if bool(check.get("advisory", false)):
			continue
		assert_true(check["pass"], "%s: %s (limit %s) %s" % [check["id"], check["shown"], check["limit_shown"], check["note"]])


func test_redesign_runs_the_same_way_twice() -> void:
	var a: Dictionary = _default_redesign()
	var b: Dictionary = PaceSimRedesign.run()
	assert_true(a["ok"], str(a["error"]))
	assert_eq((a["model"] as PaceSimRdModel).record.csv(), (b["model"] as PaceSimRdModel).record.csv(), "the time series match")
	assert_eq((a["model"] as PaceSimRdModel).record.events, (b["model"] as PaceSimRdModel).record.events, "the events match")
	assert_lt(int(b["real_ms"]), TIME_LIMIT_MS, "a redesign run took %d ms" % int(b["real_ms"]))


func test_redesign_proposal_reaches_the_launch_point_and_passes_its_own_checks() -> void:
	var result: Dictionary = _default_redesign()
	assert_true(result["ok"], str(result["error"]))
	var report: Dictionary = result["report"]
	assert_true(report["ended"], "the default player reaches the launch point")
	assert_gt((report["checks"] as Array).size(), 35, "cadence, design and economy checks all ran")
	_assert_checks_pass(report["checks"])
	assert_gt(PaceSimRedesign.summary(result).size(), 40, "the report prints")


func test_redesign_robots_earn_no_cubes() -> void:
	# Design section 16.1: cubes come only from Lumi's own loads and bales and from city stage payouts.
	var model: PaceSimRdModel = _default_redesign()["model"]
	assert_gt(model.crew_units, model.hand_units, "the crew does most of the cleaning")
	assert_almost_eq(model.earned, model.earned_by_hand + model.earned_by_stages, 0.5, "every cube came from Lumi's hands or a city stage")
	assert_gt(model.earned_by_hand, model.earned_by_stages * 5.0, "Lumi's bales are the income; stage payouts are small")
	var idle: Dictionary = PaceSimRedesign.run(PaceSimRedesign.DEFAULT_PROPOSAL, 40.0, PaceSimRedesign.DEFAULT_POLICY, {"set": {"balance.hand.base_rate": 0.0001}})
	assert_lt((idle["model"] as PaceSimRdModel).earned, 1.0, "with Lumi's hands still, nothing pays")


func test_redesign_rocket_is_built_through_the_last_city() -> void:
	# Design section 16.4: large parts made by the Assembler from Parts, fitted by Lumi, in order.
	var model: PaceSimRdModel = _default_redesign()["model"]
	var events: Dictionary[String, float] = model.record.events
	var parts: int = model.rocket_parts().size()
	assert_gt(parts, 2, "the rocket is a multi-step capstone")
	assert_true(model.rocket_done(), "every rocket part is fitted at the launch point")
	var launch_city: float = model.zones[model.rocket_district()].entered_at
	var last: float = launch_city
	for i: int in parts:
		var at: float = events.get("rocket_fit:%d" % (i + 1), -1.0)
		assert_gt(at, last, "rocket part %d is fitted after the one before, inside the launch city" % (i + 1))
		last = at
	assert_lte(last, events["launch_ready"], "the launch waits for the rocket")
	assert_gt(model.assemblers(), 0, "the parts are made by an Assembler")


func test_redesign_field_data_is_banked_and_seeds_pay_for_cleansing_plants() -> void:
	# Design section 16.9 and 16.10.
	var model: PaceSimRdModel = _default_redesign()["model"]
	var spent: float = 0.0
	for id: String in model.data.nodes:
		if model.owned.has(id):
			spent += float(model.data.nodes[id]["cost"]["data"])
	assert_almost_eq(model.data_earned, spent + model.data_bank, 0.5, "no field data is lost: it is spent on research or still in the bank")
	assert_gt(model.seeds_cleansing, 0.0, "cleansing plants cost seeds")
	assert_almost_eq(model.seeds_earned, model.seeds_planted + model.seeds_cleansing + model.seeds, 0.5, "seeds are planted, spent on cleansing plants or left")
	assert_lt(model.seed_short_s, 60.0, "blight work does not stand waiting for seeds")


func test_redesign_is_finishable_by_every_player_and_never_too_fast() -> void:
	var study: Dictionary = PaceSimRdStudies.players(PaceSimRedesign.DEFAULT_PROPOSAL, {})
	assert_eq((study["rows"] as Array).size(), PaceSimRedesign.COMPARE_POLICIES.size(), "every player was run")
	_assert_checks_pass(study["checks"])
	for row: Dictionary in study["rows"]:
		assert_false(row["over_cap"], "the '%s' player's crew stays inside the cap" % row["policy"])
	assert_gt(PaceSimRdStudies.players_lines(study).size(), PaceSimRedesign.COMPARE_POLICIES.size(), "the comparison prints")


func test_redesign_rig_loadouts_matter_and_none_wins_everywhere() -> void:
	# Design section 16.8.
	var study: Dictionary = PaceSimRdStudies.rigs(PaceSimRedesign.DEFAULT_PROPOSAL, {})
	assert_gt((study["rows"] as Array).size(), 3, "several sensible loadouts are compared")
	_assert_checks_pass(study["checks"])
	var slots: Dictionary[String, bool] = {}
	var table: Dictionary = (_default_redesign()["model"] as PaceSimRdModel).data.tables["rigs"]
	for id: String in table["modules"]:
		var mods: Dictionary = table["modules"][id].get("mods", {})
		for stat: String in ["crew_rate", "crew_near", "scrounge"]:
			if mods.has(stat):
				slots[str(table["modules"][id]["slot"])] = true
	assert_eq(slots.size(), (table["slots"] as Array).size(), "every rig slot has a module that acts on the crew")


func test_redesign_survives_ten_percent_on_its_most_sensitive_constants() -> void:
	var study: Dictionary = PaceSimRdStudies.sensitivity(PaceSimRedesign.DEFAULT_PROPOSAL, "top", {})
	assert_eq((study["rows"] as Array).size(), SENSITIVE_CONSTANTS, "the eight most sensitive constants are listed")
	assert_almost_eq(float(study["swing"]), 0.1, 0.001, "each is moved by 10 percent")
	_assert_checks_pass(study["checks"])


func test_redesign_reads_its_own_proposal_and_leaves_the_game_alone() -> void:
	GameState.upgrades["pace_sim_marker"] = 3
	var planet_before: StringName = Planets.current_id()
	var base: Dictionary = PaceSimRedesign.run(PaceSimRedesign.DEFAULT_PROPOSAL, 30.0)
	var heavier: Dictionary = PaceSimRedesign.run(PaceSimRedesign.DEFAULT_PROPOSAL, 30.0, PaceSimRedesign.DEFAULT_POLICY,
		{"set": {"districts.districts.0.hex_work": 400.0}})
	assert_lt((heavier["model"] as PaceSimRdModel).hexes_clean, (base["model"] as PaceSimRdModel).hexes_clean, "an override of a proposal value changes the run")
	assert_eq(int(GameState.upgrades.get("pace_sim_marker", 0)), 3, "upgrade levels are put back")
	assert_eq(Planets.current_id(), planet_before, "the current planet is put back")
	GameState.upgrades.erase("pace_sim_marker")
	assert_false(PaceSimRedesign.run("no_such_proposal")["ok"], "an unknown proposal is an error")
	assert_false(PaceSimRedesign.run(PaceSimRedesign.DEFAULT_PROPOSAL, 5.0, "no_such_policy")["ok"], "an unknown policy is an error")
	assert_false(PaceSimRedesign.run(PaceSimRedesign.DEFAULT_PROPOSAL, 5.0, PaceSimRedesign.DEFAULT_POLICY, {"set": {"no.such.path": 1.0}})["ok"],
		"an override of a value that does not exist is an error")
