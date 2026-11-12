extends GutTest
## Parked in task M3-13 with Lumi Level (parked/side/lumi_level/): the tests cut from tests/test_hud.gd
## (they used its before_each / after_each), tests/test_qafix.gd and tests/test_economy_scale.gd.
## They do not run. Its rewards moved to mastery levels: tests/test_mastery_rewards.gd.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _mode: int


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	_mode = Settings.hud_mode
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	Settings.hud_mode = _mode


# --- Lumi Level ---------------------------------------------------------------------------------

func test_curve_is_smooth_and_grows() -> void:
	var prev: int = 0
	for l: int in range(1, 60):
		var n: int = LumiLevel.need(l)
		assert_gt(n, prev, "level %d needs more than the one before" % l)
		prev = n
	# Early levels are quick, later ones a grind (ratio of need(30) to need(2) is large).
	assert_lt(LumiLevel.need(1), 400)
	assert_gt(float(LumiLevel.need(30)) / float(LumiLevel.need(2)), 15.0)
	assert_eq(LumiLevel.total_to(1), 0)
	assert_eq(LumiLevel.total_to(3), LumiLevel.need(1) + LumiLevel.need(2))


func test_apply_xp_crosses_several_levels() -> void:
	var st: Dictionary = {"level": 1, "xp": 0, "total": 0}
	var big: int = LumiLevel.need(1) + LumiLevel.need(2) + 5
	var ups: Array[int] = LumiLevel.apply_xp(st, big)
	assert_eq(ups, [2, 3] as Array[int])
	assert_eq(int(st["level"]), 3)
	assert_eq(int(st["xp"]), 5)
	assert_eq(int(st["total"]), big)
	assert_eq(LumiLevel.apply_xp(st, 0).size(), 0, "no XP, no change")
	assert_eq(LumiLevel.apply_xp(st, -5).size(), 0)


func test_xp_table_covers_the_sources() -> void:
	for src: String in ["scoop", "bale_made", "bale_sold", "part_found", "hex_cleaned", "hex_level", "goal",
			"event_handled", "achievement", "research", "upgrade", "robot_built", "planted", "bloomed"]:
		assert_gt(LumiLevel.xp_for(src), 0, "source %s gives XP" % src)
	assert_eq(LumiLevel.xp_for("nope"), 0)


func test_reward_schedule() -> void:
	var r2: Dictionary = LumiLevel.reward_plan(2, 0.0, 0.0, true)
	assert_gt(float(r2["cubes"]), 0.0, "every level pays cubes (floor)")
	var se: int = int(LumiLevel.cfg().get("reward", {}).get("seeds_every", 3))  # [first] scarce early seeds
	assert_gt(int(LumiLevel.reward_plan(se, 0.0, 0.0, true)["seeds"]), 0, "every seeds_every-th level pays seeds once the garden is open")
	assert_eq(int(LumiLevel.reward_plan(se, 0.0, 0.0, false)["seeds"]), 0, "no seeds before the garden")
	var r5: Dictionary = LumiLevel.reward_plan(5, 0.0, 0.0, false)
	assert_eq(int(r5["parts"]) + int(r5["bonus_parts"]), 0, "a level pays no Parts: those come from salvage alone")
	assert_false(bool(r5["trinket"]))
	assert_true(bool(LumiLevel.reward_plan(10, 0.0, 0.0, false)["trinket"]))
	# Early income spikes are capped; lifetime earnings lift the cap late.
	var spike: Dictionary = LumiLevel.reward_plan(3, 100000.0, 500.0, false)
	assert_lt(float(spike["cubes"]), 300.0)
	var late: Dictionary = LumiLevel.reward_plan(3, 100000.0, 1.0e8, false)
	assert_almost_eq(float(late["cubes"]), 100000.0, 0.5)


func test_state_lives_in_flags() -> void:
	assert_eq(LumiLevel.level(), 1)
	var st: Dictionary = LumiLevel.state()
	LumiLevel.apply_xp(st, LumiLevel.need(1))
	assert_eq(int((GameState.flags["lumi"] as Dictionary)["level"]), 2)
	var d: Dictionary = GameState.to_dict() if GameState.has_method("to_dict") else {}
	if not d.is_empty():
		GameState.flags = {}
		GameState.from_dict(d)
		assert_eq(LumiLevel.level(), 2, "Lumi Level survives a save round trip")


func test_live_node_grants_and_levels() -> void:
	var lv := LumiLevel.new()
	add_child_autofree(lv)
	watch_signals(lv)
	lv.add("scoop")
	assert_signal_emitted(lv, "xp_gained")
	lv.add("dev", LumiLevel.need(1))
	assert_signal_emitted(lv, "leveled")
	assert_eq(LumiLevel.level(), 2)
	assert_gt(GameState.get_currency("cubes").to_float(), 0.0, "the level paid its reward")


# #20: "Lumi reached level 5 · +89 cubes +10 parts +5 parts" listed Parts twice.
func test_level_reward_names_parts_once() -> void:
	var plan: Dictionary = LumiLevel.reward_plan(5, 0.0, 0.0, false)
	assert_eq(int(plan["parts"]) + int(plan["bonus_parts"]), 0, "a level pays no Parts on this planet")
	var lv := LumiLevel.new()
	add_child_autofree(lv)
	var text: String = lv._grant(5)
	var hits: int = 0
	for w: String in text.split(" ", false):
		if w.begins_with("part"):
			hits += 1
	assert_lte(hits, 1, "at most one Parts amount in '%s'" % text)


# Cut from tests/test_economy_scale.gd test_no_reward_exceeds_three_minutes_of_city_one_income (it
# used that test's table, city and limit): the same check now runs on MasteryRewards.
func _three_minute_rule_lines(table: Dictionary, city: Dictionary, limit: float) -> void:
	var lumi: Dictionary = Economy.planet_table("robot_level").get("reward", {})
	assert_lte(float(lumi["cube_secs"]), float(table["income_ref_s"]), "a Lumi level pays seconds of income, under the limit")
	assert_eq(int(lumi["part_every"]), 0, "and no Parts: those come from salvage alone")
	assert_eq(int(lumi["bonus_parts_every"]), 0)
	# A level pays cube_secs of current income, between a floor and a cap that both grow with the
	# level. At the first city's measured income (task M3-21: 5 cubes a second, not the proposal's
	# 14) every level stays under the limit; the cap alone passes it only from level 24 (940), and
	# is paid only where 30 s of income is that large, which is 3 minutes of 5,600.
	var income_now: float = float(lumi["cube_secs"]) * float(city["income_ref"])
	for lv: int in [2, 5, 10, 20, 30]:
		var plan: Dictionary = LumiLevel.reward_plan(lv, income_now, 20000.0, true)
		assert_lte(float(plan["cubes"]), limit, "Lumi level %d at the city's income" % lv)
		assert_eq(int(plan["parts"]) + int(plan["bonus_parts"]), 0)
		var rich: Dictionary = LumiLevel.reward_plan(lv, 1.0e9, 20000.0, true)
		if lv <= 20:
			assert_lte(float(rich["cubes"]), limit, "Lumi level %d at its cap" % lv)
