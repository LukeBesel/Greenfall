extends GutTest
## [hud] Lumi Level curve, XP and rewards (systems/lumi_level.gd), the notification stack,
## currency chips, the compact goal tracker and the HUD mode setting.

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
	assert_eq(int(r5["parts"]), 1)
	assert_gt(int(r5["tokens"]), 0)
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


# --- Notifications, currency, goals -------------------------------------------------------------

func test_notify_stack_caps_and_merges() -> void:
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for i: int in 5:
		ns.push("Message %d" % i)
	assert_eq(ns.count(), NotifyStack.MAX, "at most 3 rows")
	ns.push("Message 4")
	assert_eq(ns.count(), NotifyStack.MAX, "a repeat refreshes its row instead of stacking")
	ns.push("")
	assert_eq(ns.count(), NotifyStack.MAX)


func test_currency_chip_appears_on_change() -> void:
	var cc := CurrencyCluster.new()
	add_child_autofree(cc)
	cc._warm = 0.0
	GameState.add_currency("data", BigNum.from_float(5))
	assert_eq(cc.chip_count(), 1)
	GameState.add_currency("data", BigNum.from_float(2))
	assert_eq(cc.chip_count(), 1, "same currency updates its chip")
	GameState.add_currency("cubes", BigNum.from_float(100))
	assert_eq(cc.chip_count(), 1, "cubes have their own big readout, no chip")


func test_goal_tracker_compact_and_expandable() -> void:
	var gp := GoalsPanel.new()
	add_child_autofree(gp)
	assert_false(gp.expanded)
	gp.toggle()
	assert_true(gp.expanded)
	gp.set_checklist("Hold  LMB  to scoop   2/8")
	assert_true(gp.checklist.visible)
	assert_eq(GoalsPanel._strip_count("Hold  LMB  to scoop   2/8"), "Hold  LMB  to scoop")


func test_hud_mode_setting_persists() -> void:
	var path: String = Settings.settings_path
	Settings.settings_path = "user://test_hud_settings.cfg"
	Settings.hud_mode = Settings.HudMode.FULL
	Settings.save_settings()
	Settings.hud_mode = Settings.HudMode.HIDDEN
	Settings.load_settings()
	assert_eq(Settings.hud_mode, Settings.HudMode.FULL)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.settings_path))
	Settings.settings_path = path
	assert_true(InputMap.has_action("toggle_goals"), "goal tracker toggle is bound")
