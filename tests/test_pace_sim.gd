extends GutTest
## The fast balance simulator (tools/pace_sim): it runs on any registered planet, leaves the
## game's state alone, gives the same answer twice and is fast enough to tune with.

const FIXTURES: String = "res://tests/fixtures/planets"
const DUMMY: StringName = &"testworld"
const FOUR_HOURS_MIN: float = 240.0
const TIME_LIMIT_MS: int = 10000
## No player of the redesign may reach the launch point in under this share of the target time.
const REDESIGN_FASTEST_SHARE: float = 0.6


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


func test_runs_on_the_dummy_planet_and_reports_no_content() -> void:
	var result: Dictionary = PaceSim.run(DUMMY, 30.0)
	assert_true(result["ok"], str(result["error"]))
	assert_false(result["content"], "the dummy planet's tables are empty")
	assert_true("pollution" in (result["missing"] as PackedStringArray), "the empty pollution table is named")
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

func test_redesign_runs_the_same_way_twice() -> void:
	var a: Dictionary = PaceSimRedesign.run()
	var b: Dictionary = PaceSimRedesign.run()
	assert_true(a["ok"], str(a["error"]))
	assert_eq((a["model"] as PaceSimRdModel).record.csv(), (b["model"] as PaceSimRdModel).record.csv(), "the time series match")
	assert_eq((a["model"] as PaceSimRdModel).record.events, (b["model"] as PaceSimRdModel).record.events, "the events match")
	assert_lt(int(a["real_ms"]), TIME_LIMIT_MS, "a redesign run took %d ms" % int(a["real_ms"]))


func test_redesign_proposal_reaches_the_launch_point_and_passes_its_own_checks() -> void:
	var result: Dictionary = PaceSimRedesign.run()
	assert_true(result["ok"], str(result["error"]))
	var report: Dictionary = result["report"]
	assert_true(report["ended"], "the default player reaches the launch point")
	assert_gt((report["checks"] as Array).size(), 30, "cadence, design and economy checks all ran")
	for check: Dictionary in report["checks"]:
		if bool(check.get("advisory", false)):
			continue
		assert_true(check["pass"], "%s: %s (limit %s) %s" % [check["id"], check["shown"], check["limit_shown"], check["note"]])
	assert_gt(PaceSimRedesign.summary(result).size(), 40, "the report prints")


func test_redesign_is_finishable_by_every_player_and_never_too_fast() -> void:
	for policy: String in PaceSimRedesign.COMPARE_POLICIES:
		var result: Dictionary = PaceSimRedesign.run(PaceSimRedesign.DEFAULT_PROPOSAL, PaceSimRedesign.MAX_MINUTES, policy)
		assert_true(result["ok"], str(result["error"]))
		var model: PaceSimRdModel = result["model"]
		var aim: float = model.data.num("balance.target_bot_min.aim")
		assert_true(result["report"]["ended"], "the '%s' player reaches the launch point" % policy)
		assert_gt(float(result["report"]["end_min"]), aim * REDESIGN_FASTEST_SHARE, "the '%s' player does not finish in under 60%% of the target" % policy)
		assert_lte(model.robot_total(), model.crew_cap(), "the '%s' player's crew stays inside the cap" % policy)


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
