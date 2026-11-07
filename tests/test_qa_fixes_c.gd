extends GutTest
## QA fixes batch C: Haggle's spare logic, stat breakdown base for robot stats, detector range
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


func _panel() -> TradePanel:
	var f := Fleet.new()
	add_child_autofree(f)
	var tp := TradePanel.new()
	tp.fleet = f
	add_child_autofree(tp)
	return tp


func _core_keep() -> int:
	var core: int = Fleet.part_index("core")
	var k: int = 0
	for rid: String in Economy.robot_order:
		for part_id: String in Economy.robots[rid].get("recipe", []):
			if Fleet.part_index(part_id) == core:
				k += 1
	return k


func test_spares_never_include_core_needed_for_mk_tier() -> void:
	var core: int = Fleet.part_index("core")
	var chassis: int = Fleet.part_index("chassis")
	var k: int = _core_keep()
	# Rusty cores first, then two Restored cores stored last (beyond the per-type keep count).
	for i: int in k:
		GameState.parts.append({"type": core, "rarity": 0})
	GameState.parts.append({"type": core, "rarity": 2})
	GameState.parts.append({"type": core, "rarity": 2})
	var tp := _panel()
	for i: int in tp._spares():
		var p: Dictionary = GameState.parts[i]
		assert_false(int(p["type"]) == core and int(p["rarity"]) >= 2, "a Restored core (needed for Mk II) is never a spare")
	# Plenty of rusty chassis spares: a swap must consume those, not any core.
	for i: int in 10:
		GameState.parts.append({"type": chassis, "rarity": 0})
	var take: Array[int] = tp.swap_take()
	assert_eq(take.size(), 3)
	for i: int in take:
		assert_eq(int(GameState.parts[i]["rarity"]), 0, "swap takes the lowest rarity first")
	var restored_before: int = 0
	for p: Dictionary in GameState.parts:
		if int(p["type"]) == core and int(p["rarity"]) == 2:
			restored_before += 1
	tp._swap(Fleet.part_index("arm"))
	var restored_after: int = 0
	for p: Dictionary in GameState.parts:
		if int(p["type"]) == core and int(p["rarity"]) == 2:
			restored_after += 1
	assert_eq(restored_after, restored_before, "swapping spares keeps every Restored core")


func test_spares_keep_highest_rarity_of_each_type() -> void:
	var arm: int = Fleet.part_index("arm")
	var keep: int = 0
	for rid: String in Economy.robot_order:
		for part_id: String in Economy.robots[rid].get("recipe", []):
			if Fleet.part_index(part_id) == arm:
				keep += 1
	for i: int in keep:
		GameState.parts.append({"type": arm, "rarity": 0})
	GameState.parts.append({"type": arm, "rarity": 3})
	var tp := _panel()
	var sp: Array[int] = tp._spares()
	assert_eq(sp.size(), 1)
	assert_eq(int(GameState.parts[sp[0]]["rarity"]), 0, "the Vintage arm is kept, a Rusty one is spare")


func test_trade_refresh_updates_in_place() -> void:
	var tp := _panel()
	var b: Button = tp.first_button()
	assert_not_null(b)
	tp.refresh()
	tp.refresh()
	assert_eq(tp.first_button(), b, "refresh keeps the same buttons so focus survives")
	assert_false(b.is_queued_for_deletion())


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
	var scr := UpgradesScreen.new()
	add_child_autofree(scr)
	scr._set_tab("patch")
	scr.open_screen()
	await wait_physics_frames(3)
	var owner_: Control = scr.get_viewport().gui_get_focus_owner()
	assert_not_null(owner_, "a control is focused when the screen opens")
	scr._set_tab("trade")
	await wait_physics_frames(3)
	owner_ = scr.get_viewport().gui_get_focus_owner()
	assert_not_null(owner_, "a control is focused after switching to Trade")
	if owner_:
		assert_false(owner_.is_queued_for_deletion())
		assert_true(scr._grid.is_ancestor_of(owner_), "focus is inside the trade panel")
	# Active tab highlighted in gold.
	assert_eq(scr._tab_buttons[2].get_theme_color("font_color"), UITheme.GOLD)
	assert_eq(scr._tab_buttons[0].get_theme_color("font_color"), UITheme.CREAM)
	# RB from Bots goes to the next tab on screen (Trade), per TABS order.
	scr._tab = "bots"
	var ev := InputEventAction.new()
	ev.action = "ui_tab_next"
	ev.pressed = true
	scr._input(ev)
	assert_eq(scr._tab, "trade")
	scr._set_tab("hub")
	await wait_physics_frames(2)
	var close := InputEventAction.new()
	close.action = "open_upgrades"
	close.pressed = true
	scr._input(close)
	assert_false(scr.is_open, "open_upgrades (Tab) closes the workbench from _input")
	EventBus.ui_modal_changed.emit(false)
