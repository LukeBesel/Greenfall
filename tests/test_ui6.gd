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


## [ui7] A robot type you own keeps its name on the Bots tab even before its research ("? ?" is
## only for types you have never seen).
func test_owned_type_not_masked() -> void:
	var f := Fleet.new()
	add_child_autofree(f)
	var rid: String = ""
	for t: String in Economy.robot_order:
		if not Research.robot_unlocked(t):
			rid = t
			break
	if rid == "":
		pass_test("every type researched")
		return
	f.spawn(rid, 0, Vector3.ZERO, 0.0, "Own-01")
	var row: Dictionary = BenchBots.rows(f, Callable()).filter(func(r: Dictionary) -> bool: return str(r["id"]) == "build_" + rid)[0]
	assert_ne(str(row["state"]), "locked")


## [ui7] Robot looks are per type: a design reaches every robot of the type, new ones too, and
## it survives a save.
func test_type_design_reaches_new_bots_and_saves() -> void:
	Research.grant("salvage_logic")
	var f := Fleet.new()
	add_child_autofree(f)
	var a: Robot = f.spawn("scoopie", 0, Vector3.ZERO, 0.0, "Old-01")
	RobotBuilder.add_part("treads")
	assert_eq(RobotDesign.set_part(f, "scoopie", "mobility", "treads"), "")
	RobotDesign.set_field(f, "scoopie", "glow", "mint")
	assert_eq(str(a.build.get("mobility", "")), "treads", "an existing scoopie wears it")
	var b: Robot = f.spawn("scoopie", 0, Vector3(2, 0, 0), 0.0, "New-02")
	assert_eq(str(b.build.get("mobility", "")), "treads", "a newly built scoopie picks up its type's design")
	var h: Robot = f.spawn("haulbug", 0, Vector3(4, 0, 0), 0.0, "Hauler-03")
	assert_true(h.build.is_empty(), "other types keep their own look")
	var mats: Array = b.visual.get("_glow_mats")
	if not mats.is_empty():
		assert_eq((mats[0] as StandardMaterial3D).emission, RobotDesign.glow_color("mint"), "the type's glow colour")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.flags.erase("robot_designs")
	GameState.from_dict(saved)
	assert_eq(str(RobotDesign.parts("scoopie").get("mobility", "")), "treads", "the design survives save / load")
	assert_eq(str(RobotDesign.of("scoopie").get("glow", "")), "mint")


func test_ship_style_unlocks_and_wear() -> void:
	var paints: Array = ShipStyle.items("paints")
	assert_eq(paints.size(), 6)
	assert_eq(ShipStyle.items("trims").size(), 3)
	assert_true(ShipStyle.unlocked("paints", "pearl"))
	assert_false(ShipStyle.listed("paints", "lunar"), "tier-locked looks stay hidden")
	assert_true(ShipStyle.wear("paints", "sunset"))
	assert_eq(ShipStyle.paint_color(), Color.html("#f2a46b"))
	assert_false(ShipStyle.wear("paints", "coral"), "bought first")
	GameState.currencies["parts"] = BigNum.from_float(1000.0)
	assert_true(ShipStyle.buy("paints", "coral"))
	assert_true(ShipStyle.wear("paints", "coral"))


func test_locker_bot_rows_hide_locked_parts() -> void:
	var f := Fleet.new()
	add_child_autofree(f)
	var rows: Array = LockerEditors.bot_rows(f, "scoopie")
	for r: Dictionary in rows:
		if str(r["cat"]) == "parts":
			var pid: String = str(r["id"]).trim_prefix("part_")
			assert_eq(RobotBuilder.locked_research(pid), "", "%s: research-locked parts stay hidden" % pid)
	assert_gt(rows.filter(func(r: Dictionary) -> bool: return str(r["cat"]) == "glow").size(), 5)


## [ui7] The Fabricator is a Bots category, and globe robots wear the type design too.
func test_globe_robots_get_the_type_design_hook() -> void:
	RobotDesign.register_hooks()
	assert_true(SphereCrew.dress_hooks.has(Callable(RobotDesign.dress_sphere)) or SphereCrew.dress_hooks.size() > 0)
	var body := Node3D.new()
	add_child_autofree(body)
	RobotDesign._all()["scoopie"] = {"livery": ""}
	RobotDesign.dress_sphere(body, null, "scoopie", 0)
	assert_null(body.get_node_or_null(Liveries.NODE_NAME), "a plain design wears no livery")
