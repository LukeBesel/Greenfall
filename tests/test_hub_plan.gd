extends GutTest
## [v6hubs] Every hub's purpose (planet/sites/hub_plan.gd, data/planets.json "verdance".hubs): the
## data is whole, the rocket lists the right hubs, a wake gives what the hub gives, boosts apply,
## and the picker's rows say why to go.

const LANDMARKS: Array[String] = ["water_tower", "crane", "ferris_wheel", "radio_mast", "smokestack", "old_bus", "windpump", "lighthouse", "tower_crane"]

var _orbit: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _research: Variant
var _active: String


func before_each() -> void:
	_orbit = GameState.orbit
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate(true)
	_research = Research.state().duplicate(true)
	_active = HubPlan.active_planet
	GameState.orbit = {"schema": 1}
	HubPlan.active_planet = "verdance"


func after_each() -> void:
	GameState.orbit = _orbit
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	var st: Dictionary = Research.state()
	st.clear()
	st.merge(_research)
	Research.reload()
	HubPlan.active_planet = _active
	HubPlan.reload()


func test_data_is_whole() -> void:
	var es: Array = HubPlan.entries("verdance")
	assert_eq(es.size(), 10, "one entry per Verdance hub")
	var sites: Dictionary = {}
	var orders: Dictionary = {}
	var pieces: Dictionary = {}
	for e: Dictionary in es:
		var s: int = int(e["site"])
		assert_false(sites.has(s), "site %d listed once" % s)
		sites[s] = true
		assert_false(orders.has(int(e["order"])), "order %d used once" % int(e["order"]))
		orders[int(e["order"])] = true
		assert_true(s >= 0 and s < 10)
		assert_ne(str(e.get("name", "")), "", "hub %d has a name" % s)
		assert_ne(str(e.get("desc", "")), "", "hub %d says why to go" % s)
		assert_true(HubPlan.TOWN_NAMES.has(str(e.get("town", ""))), "hub %d town type" % s)
		assert_true(VerdanceSite.KINDS.has(str(e.get("town", ""))), "hub %d town is a look the site can build" % s)
		assert_true(HubPlan.landmark_kind("verdance", s) in LANDMARKS, "hub %d landmark kind" % s)
		assert_ne(str((e["landmark"] as Dictionary).get("name", "")), "")
		if HubPlan.is_home("verdance", s):
			assert_eq(s, 0, "home is the start site")
			assert_true(HubPlan.chain("verdance", s).is_empty())
			continue
		var ch: Array = HubPlan.chain("verdance", s)
		assert_eq(str((ch[ch.size() - 1] as Dictionary)["do"]), "wake", "hub %d's chain ends in the wake" % s)
		assert_true(e.get("gift") is Dictionary, "hub %d gives something" % s)
		if HubPlan.is_main("verdance", s):
			var pid: String = str((e["piece"] as Dictionary)["id"])
			assert_false(pieces.has(pid), "one rocket piece per hub")
			pieces[pid] = true
			assert_false(e.has("boosts"), "Verdance's per-hub multiplier is Hub.trade_mult, not a boost")
			assert_ne(str(e.get("hint", "")), "", "main hub %d has an arrival line" % s)
		var g: Dictionary = e["gift"]
		if g.has("research"):
			assert_true(Research.exists(str(g["research"])), "gift research exists")
		if g.has("design"):
			assert_false(Designs.def(str(g["design"])).is_empty(), "gift design exists")
	assert_eq(HubPlan.main_total("verdance"), 6)
	assert_eq(pieces.size(), 5, "hubs 2-6 each give a rocket piece")


func test_rocket_lists_home_restored_and_next() -> void:
	var first: int = HubPlan.next_site("verdance")
	assert_eq(first, 9, "Garden Row is the first stop")
	var listed: Array = []
	for i: int in 10:
		if HubPlan.listed("verdance", i):
			listed.append(i)
	assert_eq(listed, [0, 9], "home and the next stop only")
	assert_eq(HubPlan.restored_main("verdance"), 1)
	HubPlan.wake("verdance", 9)
	assert_eq(HubPlan.restored_main("verdance"), 2)
	assert_eq(HubPlan.next_site("verdance"), 7)
	assert_true(HubPlan.listed("verdance", 9) and HubPlan.listed("verdance", 7))
	assert_false(HubPlan.listed("verdance", 5), "extras wait for the main path")
	for s: int in [7, 8, 2, 4]:
		HubPlan.wake("verdance", s)
	assert_eq(HubPlan.restored_main("verdance"), 6)
	assert_true(HubPlan.listed("verdance", 5), "extras open once six bases stand")
	assert_eq(int(GameState.flags.get("rocket_pieces", 0)), 5)


func test_wake_gives_the_hubs_gift_once() -> void:
	var seeds0: float = GameState.get_currency("seeds").to_float()
	var lines: Array[String] = HubPlan.wake("verdance", 9)
	assert_true(HubPlan.woken(9))
	assert_true(bool(GameState.flags.get("rocket_piece_seeds", false)))
	assert_true(bool(GameState.flags.get("hub_woken_9", false)))
	assert_almost_eq(GameState.get_currency("seeds").to_float() - seeds0, 30.0, 0.01)
	assert_true(Research.has("wild_mint"), "Garden Row brings the mint seeds")
	assert_gt(lines.size(), 2)
	assert_true(HubPlan.wake("verdance", 9).is_empty(), "a second wake gives nothing")
	assert_almost_eq(GameState.get_currency("seeds").to_float() - seeds0, 30.0, 0.01)


func test_boosts_apply_only_while_woken() -> void:
	# No hub on Verdance has boosts (the per-hub multiplier is Hub.trade_mult); the mechanism stays
	# for other planets, so it is tested on made-up data.
	HubPlan._data = {"testworld": {"hubs": [
		{"site": 0, "order": 1, "home": true, "name": "A"},
		{"site": 1, "order": 2, "name": "B", "boosts": [{"stat": "cube_value_mult", "mult": 1.5, "text": "t"}]},
		{"site": 2, "order": 3, "name": "C", "boosts": [{"stat": "*.speed", "mult": 1.3, "text": "t"}]}]}}
	HubPlan.active_planet = "testworld"
	assert_almost_eq(HubPlan.stat_mod("cube_value_mult", 2.0), 2.0, 0.0001)
	HubPlan.wake("testworld", 1)
	assert_almost_eq(HubPlan.stat_mod("cube_value_mult", 2.0), 3.0, 0.0001)
	assert_almost_eq(HubPlan.stat_mod("scoopie.speed", 1.0), 1.0, 0.0001)
	HubPlan.wake("testworld", 2)
	assert_almost_eq(HubPlan.stat_mod("scoopie.speed", 1.0), 1.3, 0.0001, "every robot's speed")
	assert_almost_eq(HubPlan.stat_mod("scoop_rate", 1.0), 1.0, 0.0001, "Lumi's own stats are not robot stats")
	assert_eq(HubPlan.breakdown("cube_value_mult").size(), 1)
	HubPlan.active_planet = ""
	assert_almost_eq(HubPlan.stat_mod("cube_value_mult", 2.0), 2.0, 0.0001)


func test_town_label_tells_a_harbour() -> void:
	assert_eq(HubPlan.town_name("verdance", 9), "Suburb")
	assert_eq(HubPlan.town_name("verdance", 9, "harbour"), "Harbour town", "the lake's override shows in the label")
	assert_true(VerdanceSite.is_harbour(func(_x: float, _z: float) -> bool: return true))
	assert_false(VerdanceSite.is_harbour(func(_x: float, _z: float) -> bool: return false))
	assert_false(VerdanceSite.is_harbour(Callable()))


func test_wake_cost_grows() -> void:
	var c0: float = float(HubPlan.wake_cost("verdance").get("cubes", 0.0))
	assert_gt(c0, 0.0)
	HubPlan.wake("verdance", 9)
	assert_gt(float(HubPlan.wake_cost("verdance").get("cubes", 0.0)), c0, "each base costs more than the last")


func test_state_reads_never_touch_a_save_without_a_plan() -> void:
	GameState.orbit = {}
	assert_false(HubPlan.woken(3))
	assert_false(HubPlan.seen(3))
	assert_almost_eq(HubPlan.stat_mod("cube_value_mult", 1.0), 1.0, 0.0001)
	assert_true(GameState.orbit.is_empty(), "reading state adds no key")


func test_picker_rows_say_why_to_go() -> void:
	var p := RocketPicker.new()
	add_child_autofree(p)
	p.entries_fn = func() -> Array: return [
		{"site": 0, "name": "Landing Yard", "km": 1.2, "town": "Old town", "offer": "Home.", "state": "Home: 12% clean", "robots": "3 robots working", "tag": "HOME"},
		{"site": 7, "name": "Gantry Works", "km": 2.5, "town": "Industrial town", "offer": "Hull plates for the rocket.", "state": "New", "robots": "", "tag": "NEXT STOP"},
		{"site": 8, "name": "Signal Heights", "km": 3.0, "locked": "Upgrade the rocket first"}]
	p.planet_line_fn = func() -> String: return "Bases restored: 2 of 6"
	p.open()
	var texts: Array = []
	for l: Node in p._root.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	for want: String in ["Landing Yard", "HOME", "NEXT STOP", "Hull plates for the rocket.", "Bases restored: 2 of 6"]:
		assert_true(texts.has(want), "the list shows '%s'" % want)
	assert_true(texts.has("Home: 12% clean  ·  3 robots working"), "state and robots on one line")
	assert_eq(p.offered_sites(), [0, 7, 8], "home first")
	var fly: Array = p._list.find_children("*", "Button", true, false)
	assert_false((fly[1] as Button).disabled)
	assert_true((fly[2] as Button).disabled, "a hub past the rocket's limit can't be flown to")
	assert_true(texts.has("Upgrade the rocket first"))
	p.close()
