extends GutTest
## QA fixes batch C ([ui2] Haggle's trade is gone): stat breakdown base for robot stats, detector range
## stat, goal titles fitting the HUD goals card.

var _parts: Array
var _flags: Dictionary
var _upgrades: Dictionary


func before_each() -> void:
	_parts = GameState.parts.duplicate(true)
	_flags = GameState.flags.duplicate(true)
	_upgrades = GameState.upgrades.duplicate(true)
	GameState.parts = []
	GameState.upgrades = {}
	for rid: String in Economy.robot_order:
		GameState.flags.erase("tier_" + rid)


func after_each() -> void:
	GameState.parts = _parts
	GameState.flags = _flags
	GameState.upgrades = _upgrades


func test_stat_breakdown_base_for_robot_stats() -> void:
	var rid: String = Economy.robot_order[0]
	var stats: Dictionary = Economy.robots[rid].get("stats", {})
	var stat_name: String = str(stats.keys()[0])
	var sid: String = "%s.%s" % [rid, stat_name]
	assert_almost_eq(Economy.base_stat(sid), float(stats[stat_name]), 0.0001)
	var rows: Array[Dictionary] = Economy.stat_breakdown(sid)
	assert_eq(rows[0]["text"], Economy._fmt_stat(float(stats[stat_name])))
	assert_true(str(rows[0]["source"]).begins_with("Base"))
	assert_eq(Economy.stat_breakdown("capacity")[0]["source"], "Base")


func test_detector_range_is_a_real_stat() -> void:
	assert_eq(str(Economy.upgrade_defs["detector_range"]["stat"]), "detector_range")
	var dm: float = Designs.mult("detector_range")  # [skins] the worn design's small bonus (Aurora: detector)
	assert_almost_eq(Economy.stat("detector_range", {}), 16.0 * dm, 0.001)
	assert_almost_eq(Economy.stat("detector_range", {"detector_range": 1}), 20.0 * dm, 0.001)


func test_goal_titles_fit_goals_card() -> void:
	var font: Font = UITheme.font()
	var max_w: float = GoalsPanel.ROW_W - 22.0
	var goals: Dictionary = Economy.read_json("res://data/goals.json")
	var list: Array = goals.get("goals", [])
	assert_gt(list.size(), 0)
	for g: Dictionary in list:
		var w: float = font.get_string_size(str(g["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		assert_lt(w, max_w, "goal '%s' fits the goals card (%.0f px)" % [g["text"], w])


func test_upgrades_screen_tab_closes_and_focus_follows_tabs() -> void:
	GameState.flags["bench_tabs"] = ["patch", "bots", "hub", "research", "rockets", "contracts", "locker"]  # [ui2] all tabs open
	var scr := UpgradesScreen.new()
	add_child_autofree(scr)
	scr._set_tab("patch")
	scr.open_screen()
	await wait_physics_frames(3)
	var owner_: Control = scr.get_viewport().gui_get_focus_owner()
	assert_not_null(owner_, "a control is focused when the screen opens")
	scr._set_tab("hub")  # [ui2] no Trade tab; Hub is third
	await wait_physics_frames(3)
	owner_ = scr.get_viewport().gui_get_focus_owner()
	assert_not_null(owner_, "a control is focused after switching to Hub")
	if owner_:
		assert_false(owner_.is_queued_for_deletion())
		assert_true(scr._grid.is_ancestor_of(owner_), "focus is inside the hub panel")
	# Active tab lit ([ui2] holo), the others quiet.
	assert_eq(scr._tab_buttons[2].get_theme_color("font_color"), BenchKit.HOLO.lightened(0.5))
	assert_eq(scr._tab_buttons[0].get_theme_color("font_color"), UITheme.MUTED)
	# RB from Bots goes to the next tab on screen (Hub), per TABS order.
	scr._tab = "bots"
	var ev := InputEventAction.new()
	ev.action = "ui_tab_next"
	ev.pressed = true
	scr._input(ev)
	assert_eq(scr._tab, "hub")
	scr._set_tab("research")
	await wait_physics_frames(2)
	var close := InputEventAction.new()
	close.action = "open_upgrades"
	close.pressed = true
	scr._input(close)
	assert_false(scr.is_open, "open_upgrades (Tab) closes the workbench from _input")
	EventBus.ui_modal_changed.emit(false)
