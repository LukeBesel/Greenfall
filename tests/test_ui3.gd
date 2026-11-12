extends GutTest
## [ui3] Workbench tabs: Upgrades (everything with levels or tiers) and Build (one-time buildings,
## camp2's HubBuilds list), Hub and Rockets folded in, as few tabs as possible.

var _flags: Dictionary
var _world: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_world = GameState.world
	GameState.world = {"hub_level": 1}


func after_each() -> void:
	GameState.flags = _flags
	GameState.world = _world


func test_five_tabs_with_hub_and_rockets_folded_in() -> void:
	assert_eq(UpgradesScreen.TABS.size(), 5)  # [ui6] no Locker tab; M3-08 adds the Rig tab; M3-13 parks Requests
	assert_eq(str(UpgradesScreen.TABS[0]["name"]), "Upgrades")
	assert_eq(UpgradesScreen.TAB_ALIASES["hub"], "patch")
	assert_eq(UpgradesScreen.TAB_ALIASES["rockets"], "patch")
	for t: Dictionary in UpgradesScreen.TABS:
		assert_false(str(t["id"]) in ["hub", "rockets", "cosmetics", "builder", "trade"])


func test_upgrades_panel_has_lumi_and_base_sections() -> void:
	var h := Hub.new()
	add_child_autofree(h)
	var up := UpgradesPanel.new()
	up.hub = h
	add_child_autofree(up)
	assert_gt(up.cards.size(), 0, "Lumi upgrade cards")
	assert_not_null(up._hub_panel, "the next hub level card")
	assert_true(up._hub_panel.hero_only)
	assert_not_null(up.first_button())


func test_build_panel_lists_one_time_builds_only() -> void:
	var bp := BuildPanel.new()
	add_child_autofree(bp)
	for id: String in bp._rows:
		assert_eq(HubBuilds.kind_now(id), "one_time", "%s is a one-time building" % id)
	var row := BenchRow.new()
	add_child_autofree(row)
	row.show_entry("Lamp", "", "A lamp.", {"cubes": 1.0e12}, "Build", "Not enough cubes or parts.", true)
	assert_true(row.button().disabled)
	assert_false(row._why.visible, "a 'can't afford' reason shows as the red cost, not a second line")
	row.show_entry("Lamp", "", "A lamp.", {}, "Build", "", false)
	assert_false(row.button().disabled)
