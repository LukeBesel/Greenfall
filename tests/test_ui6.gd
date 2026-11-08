extends GutTest
## [ui6] The list + detail workbench (ui/list_detail.gd, ui/bench_lists.gd) and the Locker as a
## yard build (systems/camp/locker_cabinet.gd).

var _flags: Dictionary
var _world: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_world = GameState.world
	_cur = GameState.currencies.duplicate()
	GameState.world = {"hub_level": 1}


func after_each() -> void:
	GameState.flags = _flags
	GameState.world = _world
	GameState.currencies = _cur


func _rows(n_ready: int, n_locked: int) -> Array:
	var out: Array = []
	for i: int in n_ready:
		out.append({"id": "r%d" % i, "cat": "a", "name": "Row %d" % i, "desc": "One line.", "lv": 1, "max": 3,
			"price": {"cubes": 10.0}, "state": "ready", "table": [["Level", "1 / 3"]], "action": "Install",
			"act": func() -> bool: return true})
	for i: int in n_locked:
		out.append({"id": "l%d" % i, "cat": "b", "name": "Secret", "state": "locked", "requires": "Something"})
	return out


func test_list_detail_rows_categories_and_locked_rows() -> void:
	var ld := ListDetail.new()
	ld.categories = [["a", "Alpha"], ["b", "Beta"], ["c", "Empty"]]
	var data: Array = _rows(3, 2)
	ld.provider = func() -> Array: return data
	add_child_autofree(ld)
	assert_eq(ld._rows.size(), 3, "one row per item of the open category")
	assert_eq(ld._cat_btns.size(), 2, "empty categories are not shown")
	assert_eq(ld._sel, "r0")
	assert_eq(ld._d_btn.text, "Install")
	assert_false(ld._d_btn.disabled)
	ld.set_category("b")
	assert_eq(ld._rows.size(), 2)
	var parts: Array = (ld._rows["l0"] as Button).get_meta("parts")
	assert_eq((parts[1] as Label).text, "?  ?", "locked rows hide their name")
	assert_eq(ld._d_name.text, "?  ?")
	assert_false(ld._d_btn.visible, "no action on a locked row")


func test_upgrades_show_few_rows_per_category() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(50.0)
	var items: Array = BenchLists.upgrades(null)
	var lumi: Array = items.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == "lumi")
	assert_gt(lumi.size(), 0)
	assert_lte(lumi.size(), BenchLists.SOON_CAP + BenchLists.LOCKED_SHOWN)
	var locked: int = lumi.filter(func(r: Dictionary) -> bool: return str(r["state"]) == "locked").size()
	assert_lte(locked, BenchLists.LOCKED_SHOWN)
	for r: Dictionary in lumi:
		assert_ne(str(r["state"]), "done", "maxed upgrades drop off")


func test_research_rows_per_branch() -> void:
	var items: Array = BenchLists.research()
	assert_gt(items.size(), 0)
	for b: Array in BenchLists.research_cats():
		var locked: int = items.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == str(b[0]) and str(r["state"]) == "locked").size()
		assert_lte(locked, BenchLists.LOCKED_SHOWN, "%s shows at most two locked rows" % b[0])


func test_locker_is_a_yard_build() -> void:
	assert_true("locker" in YardBuilds.IDS)
	assert_false(HubBuilds.def("locker").is_empty(), "listed in data/builds.json")
	assert_eq(str(HubBuilds.def("locker").get("kind", "")), "one_time")
	assert_gt(float(YardBuilds.def("locker").get("cost", {}).get("parts", 0)), 0.0, "costs parts")
	assert_false(LockerCabinet.is_built())
	YardBuilds.mark_built("locker")
	assert_true(LockerCabinet.is_built())
	assert_true(LockerPanel.is_open_for(null))


func test_no_locker_tab() -> void:
	for t: Dictionary in UpgradesScreen.TABS:
		assert_ne(str(t["id"]), "locker")
	assert_lte(UpgradesScreen.TABS.size(), 5)


## [ui7] The Bots tab in the list pattern, with a hidden Fabricator slot for orbC.
func test_bots_rows_and_fabricator_slot() -> void:
	Research.grant("salvage_logic")
	var f := Fleet.new()
	add_child_autofree(f)
	var rows: Array = BenchBots.rows(f, Callable())
	var builds: Array = rows.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == "build")
	assert_eq(builds.size(), Economy.robot_order.size(), "one build row per robot type")
	assert_true(rows.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == "fabricator").is_empty(), "no Fabricator until it plugs in")
	BenchBots.set_fabricator(func(_w: Node) -> Array: return [{"id": "fab_1", "cat": "fabricator", "name": "Queue", "state": "busy"}])
	rows = BenchBots.rows(f, Callable())
	assert_eq(rows.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == "fabricator").size(), 1)
	BenchBots.set_fabricator(Callable())
	GameState.currencies["cubes"] = BigNum.from_float(1.0e6)
	GameState.currencies["parts"] = BigNum.from_float(1.0e4)
	rows = BenchBots.rows(f, Callable())
	var hb: Dictionary = rows.filter(func(r: Dictionary) -> bool: return str(r["id"]) == "build_haulbug")[0]
	assert_eq(str(hb["state"]), "ready")
	assert_true((hb["act"] as Callable).call())
	assert_eq(f.count("haulbug"), 1)
	rows = BenchBots.rows(f, Callable())
	assert_false(rows.filter(func(r: Dictionary) -> bool: return str(r["id"]) == "tier_haulbug").is_empty(), "a Mk row once you have one")
