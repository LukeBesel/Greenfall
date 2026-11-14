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
	assert_gt(int(r5["bonus_parts"]), 0, "[money] Parts every few levels (was tokens)")
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

func test_notify_stack_queues_and_merges() -> void:  # [v9d] one line at a time, nothing important dropped
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for i: int in 5:
		ns.push("Message %d" % i)
	assert_eq(ns.count(), 1, "a burst shows one line first")
	assert_lte(ns.pending(), NotifyStack.QUEUE_MAX, "the rest wait their turn")
	ns.push("Message 4")
	assert_lte(ns.pending(), NotifyStack.QUEUE_MAX, "a repeat merges instead of queueing again")
	ns.push("")
	ns.push("A story line", "story")
	for k: int in 40:
		ns._process(0.25)
	assert_eq(ns.pending(), 0, "the queue drains")
	assert_lte(ns.count(), NotifyStack.MAX)


func test_notify_burst_keeps_story_lines() -> void:
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for i: int in 3:
		ns.push("Story %d" % i, "story")
	for i: int in 6:
		ns.push("Info %d" % i, "info")
	var seen: Dictionary = {}
	for k: int in 80:
		ns._process(0.25)
		for r: Dictionary in ns._rows:
			seen[str(r["text"])] = true
	for i: int in 3:
		assert_true(seen.has("Story %d" % i), "story line %d was shown" % i)
	assert_gt(ns.skipped, 0, "extra info lines in a burst are skipped")


func test_currency_chip_appears_on_change() -> void:
	var cc := CurrencyCluster.new()
	add_child_autofree(cc)
	cc._warm = 0.0
	GameState.add_currency("parts", BigNum.from_float(5))
	assert_eq(cc.chip_count(), 1)
	GameState.add_currency("parts", BigNum.from_float(2))
	assert_eq(cc.chip_count(), 1, "same currency updates its chip")
	GameState.add_currency("cubes", BigNum.from_float(100))
	assert_eq(cc.chip_count(), 1, "cubes have their own big readout, no chip")
	GameState.add_currency("seeds", BigNum.from_float(3))
	assert_eq(cc.chip_count(), 2, "[money] seeds get a chip too")
	Currencies.warn_legacy = false
	GameState.add_currency("bolts", BigNum.from_float(1))
	Currencies.warn_legacy = true
	assert_eq(cc.chip_count(), 2, "a legacy id lands on the Parts chip, no new chip")


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
