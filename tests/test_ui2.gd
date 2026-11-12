extends GutTest
## [ui2] The simpler workbench: robot part items are Parts (salvage, fold, save v3), robots and
## Mk tiers cost Parts + cubes, the Locker gate and its editor slot, tab gates, the new cards.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _parts: Array
var _world: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	_parts = GameState.parts.duplicate(true)
	_world = GameState.world
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {"cubes": BigNum.zero(), "parts": BigNum.zero(), "seeds": BigNum.zero()}
	GameState.parts = []
	GameState.world = {"hub_level": 1}
	for rid: String in Economy.robot_order:
		GameState.flags.erase("tier_" + rid)


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	GameState.parts = _parts
	GameState.world = _world
	LockerPanel.remove_editor("lumi")
	UpgradesScreen.clear_tab_gate("contracts")


func _fleet() -> Fleet:
	Research.grant("salvage_logic")  # [pace] helpers need Salvage Logic first
	Research.unlock_story("haul_rig")  # [v4bots] the Haul Bug's plans come later
	Research.unlock_story("scoopie_rig")  # task M3-21: the Scoopie's plans follow the Haul Bug's
	var f := Fleet.new()
	add_child_autofree(f)
	return f


func _parts_now() -> float:
	return GameState.get_currency("parts").to_float()


func test_salvage_pays_parts_by_rarity() -> void:
	var got: Array = []
	var cb := func(t: int, r: int) -> void: got.append([t, r])
	EventBus.part_found.connect(cb)
	var own: Array = RobotParts.salvage_rules()["rarity_parts"]
	assert_almost_eq(RobotParts.salvage(2, 0), float(own[0]), 0.001)
	assert_almost_eq(RobotParts.salvage(3, 3), float(own[3]), 0.001)
	EventBus.part_found.disconnect(cb)
	assert_almost_eq(_parts_now(), float(own[0]) + float(own[3]), 0.001)
	assert_eq(GameState.parts.size(), 0, "no items are stored")
	assert_eq(got.size(), 2, "finds are still announced")
	for r: int in 5:
		assert_almost_eq(RobotParts.value(r), float(own[r]), 0.001, "the planet's own Parts scale")
		assert_lt(RobotParts.value(r), float(Economy.rarity(r)["parts"]), "scarcer than the shared list")


func test_leftover_items_fold_into_parts() -> void:
	GameState.parts = [{"type": 0, "rarity": 1}, {"type": 3, "rarity": 4}]
	var f := _fleet()
	f._process(0.0)
	assert_eq(GameState.parts.size(), 0)
	assert_almost_eq(_parts_now(), RobotParts.value(1) + RobotParts.value(4), 0.001)


func test_save_v4_turns_robot_part_items_into_parts() -> void:
	var d: Dictionary = {"version": 2, "currencies": {"cubes": BigNum.from_float(5).serialize(), "parts": BigNum.from_float(40).serialize(), "seeds": BigNum.zero().serialize()},
		"parts": [{"type": 0, "rarity": 0}, {"type": 3, "rarity": 2}, {"type": 3, "rarity": 3}], "flags": {}}
	var m: Dictionary = SaveManager.migrate(d)
	assert_eq(int(m["version"]), GameState.SAVE_VERSION)
	assert_eq((m["parts"] as Array).size(), 0)
	assert_almost_eq(BigNum.from_serialized(m["currencies"]["parts"]).to_float(), 40.0 + RobotParts.value(0) + RobotParts.value(2) + RobotParts.value(3), 0.001)
	assert_almost_eq(float(m["flags"]["parts_migrated"]), RobotParts.value(0) + RobotParts.value(2) + RobotParts.value(3), 0.001)
	# A v1 save goes through v2 and v3.
	var old: Dictionary = {"version": 1, "currencies": {"cubes": BigNum.from_float(5).serialize(), "bolts": BigNum.from_float(2).serialize()}, "parts": [{"type": 1, "rarity": 1}]}
	var m2: Dictionary = SaveManager.migrate(old)
	assert_eq(int(m2["version"]), GameState.SAVE_VERSION)
	assert_almost_eq(BigNum.from_serialized(m2["currencies"]["parts"]).to_float(), 2.0 * 5.0 + RobotParts.value(1), 0.001)
	assert_eq(GameState.SAVE_VERSION, 6)


func test_robot_build_costs_parts_and_cubes() -> void:
	var f := _fleet()
	assert_eq(f.recipe_status("scoopie"), [], "no part recipe")
	var parts: float = f.build_parts("scoopie").to_float()
	assert_almost_eq(parts, float(Economy.robots["scoopie"]["parts"]), 0.001)
	GameState.currencies["cubes"] = BigNum.from_float(f.build_cost("scoopie").to_float())
	assert_eq(f.build_block_reason("scoopie"), "Not enough parts")
	GameState.currencies["parts"] = BigNum.from_float(parts)
	assert_eq(f.build_block_reason("scoopie"), "")
	var r: Robot = f.build("scoopie", Vector3.ZERO)
	assert_not_null(r)
	assert_almost_eq(_parts_now(), 0.0, 0.001)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 0.0, 0.001)
	assert_almost_eq(r.rarity_bonus, 0.0, 0.0001)
	# Task M3-20: the growth of a price is the table's (1.0 on the first planet: it never compounds).
	assert_almost_eq(f.build_parts("scoopie").to_float(), CrewRules.build_parts(Economy.robot_cfg, Economy.robots["scoopie"], 1, 0), 0.001)


func test_mk_tier_costs_parts_no_core() -> void:
	var f := _fleet()
	GameState.flags[Economy.FLAG_TIERS_OPEN] = 2  # task M3-20: tier steps open with the second city
	var req: Dictionary = f.tier_requirements("scoopie")
	assert_false(req["ok"])
	var step: float = CrewRules.tier_parts(Economy.robot_cfg, Economy.robots["scoopie"], 0, 0)
	assert_almost_eq((req["parts"] as BigNum).to_float(), step, 0.001)
	GameState.currencies["cubes"] = BigNum.from_float((req["cost"] as BigNum).to_float())
	GameState.currencies["parts"] = BigNum.from_float(step)
	req = f.tier_requirements("scoopie")
	assert_true(req["ok"], "cubes + parts are enough: no Control Core")
	assert_true(f.upgrade_tier("scoopie"))
	assert_eq(f.tier_of("scoopie"), 1)
	assert_almost_eq(_parts_now(), 0.0, 0.001)


func test_locker_opens_once_the_cabinet_is_built() -> void:  # [ui6]
	assert_false(LockerPanel.is_open_for(null))
	YardBuilds.mark_built("locker")
	assert_true(LockerPanel.is_open_for(null))


func test_locker_hosts_a_registered_lumi_editor_and_the_robot_editor() -> void:
	YardBuilds.mark_built("locker")  # [ui6]
	var made: Array = []
	LockerPanel.add_editor("lumi", func(_w: Node) -> Control:
		var c := Label.new()
		c.text = "lumi editor"
		made.append(c)
		return c)
	var f := _fleet()
	var r := Robot.new()
	r.type_id = "scoopie"
	r.robot_name = "Locker-01"
	f.add_child(r)
	var lp := LockerPanel.new()
	lp.fleet = f
	add_child_autofree(lp)
	assert_eq(lp.editing(), "target:lumi")
	assert_eq(made.size(), 1, "the registered Lumi editor is used")
	assert_true(lp.is_ancestor_of(made[0]))
	var whos: Array[String] = []
	for b: Button in lp._who_btns:
		whos.append(str(b.get_meta("who")))
	assert_true("bots:scoopie" in whos, "a tab per robot type (one design per type), not one per robot")
	assert_false("Locker-01" in whos)
	lp.set_editing("bots:scoopie")
	assert_true(lp._editor is LockerEditors.BotEditor)
	assert_eq((lp._editor as LockerEditors.BotEditor).type_id, "scoopie")
	lp.set_editing("target:lumi")
	assert_eq(made.size(), 2)


func test_locker_locked_before_hub_level() -> void:
	var lp := LockerPanel.new()
	add_child_autofree(lp)
	assert_null(lp._list, "no editor while locked")
	assert_null(lp.first_button())


func test_tab_gate() -> void:
	var open: Array = [false]
	UpgradesScreen.set_tab_gate("contracts", func() -> bool: return open[0], "Opens later")
	assert_false(UpgradesScreen.tab_open("contracts"))
	assert_true(UpgradesScreen.tab_open("hub"))
	open[0] = true
	assert_true(UpgradesScreen.tab_open("contracts"))


func test_tabs_are_the_simple_five() -> void:
	var ids: Array[String] = []
	for t: Dictionary in UpgradesScreen.TABS:
		ids.append(str(t["id"]))
	assert_eq(ids, ["patch", "build", "bots", "research", "rigs"] as Array[String])  # [ui3] [ui6]; M3-08 adds the Rig tab, M3-13 parks Requests
	assert_eq(UpgradesScreen.TAB_ALIASES["builder"], "patch")
	assert_eq(UpgradesScreen.TAB_ALIASES["cosmetics"], "patch")


func test_robot_card_builds_with_parts() -> void:
	var f := _fleet()
	var rc := RobotCard.new("haulbug", f, func() -> Vector3: return Vector3.ZERO)
	add_child_autofree(rc)
	assert_true(rc._build.disabled)
	GameState.currencies["cubes"] = BigNum.from_float(1.0e6)
	GameState.currencies["parts"] = BigNum.from_float(1.0e4)
	rc.refresh()
	assert_false(rc._build.disabled)
	rc._on_build()
	assert_eq(f.count("haulbug"), 1)


func test_hub_gains_list_the_next_level() -> void:
	var h := Hub.new()
	add_child_autofree(h)
	var g: Array[String] = HubPanel.level_gains(h, 3)
	assert_false(g.any(func(s: String) -> bool: return "Locker" in s), "the Locker comes from a found piece, not a base level")


func test_tabs_appear_once_open_and_stay() -> void:
	GameState.flags.erase("bench_tabs")
	assert_true(UpgradesScreen.tab_visible("patch"))
	GameState.flags["bench_tier"] = 1  # [v1guide] Bots opens with the workbench's Mk II (ui/bench_tiers.gd)
	assert_false(UpgradesScreen.tab_visible("bots"), "hidden on a fresh game")
	GameState.flags["bench_tier"] = 2
	assert_true(UpgradesScreen.tab_visible("bots"))
	assert_true("bots" in GameState.flags.get("bench_tabs", []), "an opened tab is remembered")


func test_pause_menu_has_no_save_button() -> void:
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	var texts: Array[String] = []
	for b: Node in pm.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	assert_false(texts.has("Save game"))
	assert_true(texts.has("Quit"))
	assert_true(texts.has("Keepsakes"))


func test_settings_start_simple() -> void:
	var sp := SettingsPanel.new()
	add_child_autofree(sp)
	assert_eq(SettingsPanel.TABS[0], "Basics")
	assert_true(sp._tab_buttons[0].visible)
	assert_false(sp._tab_buttons[1].visible, "the full tabs hide behind More settings")
	sp.select_tab(2)
	assert_true(sp._tab_buttons[2].visible)
