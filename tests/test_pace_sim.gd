extends GutTest
## The fast balance simulator (tools/pace_sim): it runs on any registered planet, leaves the
## game's state alone, gives the same answer twice and is fast enough to tune with.

const FIXTURES: String = "res://tests/fixtures/planets"
const DUMMY: StringName = &"testworld"
const FOUR_HOURS_MIN: float = 240.0
const TIME_LIMIT_MS: int = 10000


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
