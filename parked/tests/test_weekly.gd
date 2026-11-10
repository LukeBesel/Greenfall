extends GutTest
## Parked with the Seed of the Week (M1-08). These tests were part of tests/test_extras.gd; its
## before_each / after_each set WeeklyChallenge.path_override = "user://test_weekly.save" and reset
## the cache, now_override and active flag around each test.

# --- Seed of the Week -----------------------------------------------------------------------

func _unix(y: int, m: int, d: int) -> float:
	return float(Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0}))


func test_iso_weeks() -> void:
	assert_eq(WeeklyChallenge.iso_week(_unix(2026, 11, 7)), Vector2i(2026, 45))
	assert_eq(WeeklyChallenge.iso_week(_unix(2021, 1, 1)), Vector2i(2020, 53))
	assert_eq(WeeklyChallenge.iso_week(_unix(2024, 12, 30)), Vector2i(2025, 1))
	assert_eq(WeeklyChallenge.iso_week(_unix(2026, 1, 1)), Vector2i(2026, 1))
	assert_eq(WeeklyChallenge.iso_week(_unix(2026, 11, 2)), WeeklyChallenge.iso_week(_unix(2026, 11, 8)), "Monday to Sunday is one week")


func test_same_seed_and_twist_for_everyone() -> void:
	WeeklyChallenge.now_override = _unix(2026, 11, 7)
	var a: int = WeeklyChallenge.current_seed()
	var tw: String = str(WeeklyChallenge.twist()["id"])
	WeeklyChallenge.now_override = _unix(2026, 11, 3)
	assert_eq(WeeklyChallenge.current_seed(), a)
	assert_eq(str(WeeklyChallenge.twist()["id"]), tw)
	assert_eq(WeeklyChallenge.seed_for("2026-W45"), a, "seeded by the week id alone")
	WeeklyChallenge.now_override = _unix(2026, 11, 10)
	assert_ne(WeeklyChallenge.current_seed(), a, "next week is a new seed")


func test_twists_limit_robots_only_in_the_challenge() -> void:
	var t: Dictionary = {"name": "Scoopies Only", "only": ["scoopie"]}
	assert_eq(WeeklyChallenge.robot_block_for(t, "scoopie"), "")
	assert_ne(WeeklyChallenge.robot_block_for(t, "haulbug"), "")
	assert_ne(WeeklyChallenge.robot_block_for({"name": "Dry", "ban": ["drip"]}, "drip"), "")
	WeeklyChallenge.active = false
	assert_eq(WeeklyChallenge.robot_block("haulbug"), "", "the main game is never limited")


func test_score_rewards_speed() -> void:
	var slow: int = WeeklyChallenge.score(30, 5, 4000.0, 3500.0, true)
	var fast: int = WeeklyChallenge.score(30, 5, 4000.0, 1200.0, true)
	assert_gt(fast, slow)
	assert_gt(WeeklyChallenge.score(30, 0, 0.0, 9999.0, true), 0)


func test_one_chip_per_week_and_bests() -> void:
	WeeklyChallenge.now_override = _unix(2026, 11, 7)
	var r1: Dictionary = WeeklyChallenge.record_finish(2400.0, 4000)
	assert_ne(str(r1["chip"]), "")
	var r2: Dictionary = WeeklyChallenge.record_finish(1800.0, 3500)
	assert_eq(str(r2["chip"]), "", "a second finish the same week gives no chip")
	assert_true(bool(r2["new_time"]))
	assert_false(bool(r2["new_score"]))
	assert_almost_eq(float(r2["best_time"]), 1800.0, 0.01)
	assert_eq(int(r2["best_score"]), 4000)
	assert_eq(WeeklyChallenge.chip_count(), 1)


func test_weekly_decor_needs_chips() -> void:
	GameState.add_currency("cubes", BigNum.from_float(100000))
	assert_ne(Decor.buy_block_reason("weekly_pennant"), "")
	WeeklyChallenge.now_override = _unix(2026, 11, 7)
	WeeklyChallenge.record_finish(2000.0, 3000)
	assert_eq(Decor.buy_block_reason("weekly_pennant"), "")
	assert_ne(Decor.buy_block_reason("weekly_arch"), "", "the arch needs three chips")
	var arch: Node3D = DecorProps.build("weekly_arch")
	assert_gt(arch.get_child_count(), 3)
	arch.free()


func test_challenge_hooks_cradle_mode_only_while_active() -> void:
	var home_seed: int = CradleMode.world_seed()
	WeeklyChallenge.active = true
	assert_eq(CradleMode.world_seed(), WeeklyChallenge.current_seed())
	assert_eq(CradleMode.modifiers(), WeeklyChallenge.twist_modifiers())
	assert_eq(CradleMode.bank(), 0, "the challenge never banks Starseeds")
	WeeklyChallenge.active = false
	assert_eq(CradleMode.world_seed(), home_seed)

