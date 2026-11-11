extends GutTest
## [v6pace] Verdance's pacing gates and the hub curve (owner notes 57, 58, 61, 63, 64): the rocket's
## gate, the geometric far-hub prices and the trade multiplier, the rocket tiers' hub limits, the
## leave gate by hubs restored, the goal chain's order past base 3, and the play clock behind the
## loading screen. A failing number here means a price or gate moved: update docs/BALANCE.md
## ("Verdance arc") with it.

var _keep: Array


func before_each() -> void:
	_keep = [GameState.flags.duplicate(true), GameState.stats.duplicate(true), GameState.world, GameState.districts, GameState.current_hub]
	GameState.flags = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	GameState.current_hub = 0


func after_each() -> void:
	GameState.flags = _keep[0]
	GameState.stats = _keep[1]
	GameState.world = _keep[2]
	GameState.districts = _keep[3]
	GameState.current_hub = _keep[4]


func _goal_index(id: String) -> int:
	var ch: Array = Economy.read_json("res://data/goals.json").get("goals", [])
	for i: int in ch.size():
		if str(ch[i]["id"]) == id:
			return i
	return -1


func test_rocket_comes_after_the_first_robot_and_seed() -> void:
	assert_eq(Hub.rocket_level(), 1, "no base level stands before the first hop")
	var ch: Array = Economy.read_json("res://data/objectives.json").get("objectives", [])
	var zone: int = -1
	for i: int in ch.size():
		if str(ch[i]["id"]) == "seed":
			zone = i
	assert_gt(zone, 0, "the story still has its 'seed' step")
	GameState.flags["objective_step"] = zone
	assert_false(Hub.rocket_open(1), "not while 'Plant the first seed' is on the card (the seed scene comes before the hop to Garden Row)")
	assert_ne(Hub.rocket_lock_text(1), "")
	GameState.flags["objective_step"] = zone + 1
	assert_true(Hub.rocket_open(1))
	assert_eq(Hub.rocket_lock_text(1), "")


func test_far_hub_prices_multiply() -> void:
	var cfg: Dictionary = Hub.far_cfg()
	assert_eq(Hub.far_level(), 2)
	for n: int in FAR.size():
		assert_eq(float(Hub.far_cost(n)["cubes"]), FAR[n], "far hub %d" % (n + 2))
	for n: int in range(2, FAR.size() - 1):
		var f: float = float(Hub.far_cost(n)["cubes"]) / float(Hub.far_cost(n - 1)["cubes"])
		assert_almost_eq(f, float(cfg["cost_growth"]["cubes"]), 0.3, "one growth factor between steps")
	assert_gte(float(Hub.far_cost(4)["cubes"]), 100000.0, "hub 6 costs hundreds of thousands (owner note 64)")


func test_nice_keeps_two_digits() -> void:
	assert_eq(Hub.nice(4056.0), 4100.0)
	assert_eq(Hub.nice(384000.0), 380000.0)
	assert_eq(Hub.nice(153600.0), 150000.0)
	assert_eq(Hub.nice(1000.0), 1000.0)
	assert_eq(Hub.nice(42.4), 42.0)


func test_trade_multiplier_is_one_without_far_hubs() -> void:
	assert_almost_eq(Hub.trade_mult(), 1.0 / PACE, 0.0001, "only the pace knob before the first far hub")
	assert_gt(float(Hub.far_cfg()["sell_growth"]), 1.5, "each restored hub multiplies income")
	assert_lt(float(Hub.far_cfg()["sell_growth"]), float(Hub.far_cfg()["cost_growth"]["cubes"]), "prices outgrow the multiplier: robots and tiers make up the rest")


func test_rocket_tiers_reach_more_hubs() -> void:
	assert_eq(RocketTiers.hub_limit(1), 3)
	assert_eq(RocketTiers.hub_limit(2), 5)
	assert_gte(RocketTiers.hub_limit(3), 6)
	var last: float = 0.0
	for t: int in [2, 3]:
		var c: float = float(RocketTiers.def(t)["cost"]["cubes"])
		assert_gt(c, last * 3.0, "each tier costs several times the last")
		last = c
		assert_false(RocketTiers.def(t).has("requires_research"), "the price is the gate inside the arc")
	assert_eq(float(RocketTiers.def(2)["cost"]["cubes"]), MK2)
	assert_eq(float(RocketTiers.def(3)["cost"]["cubes"]), MK3)


func test_leave_gate_counts_hubs_not_cleaning() -> void:
	assert_eq(Homeward.leave_hubs(0), Vector2i(6, 2))
	assert_eq(Homeward.leave_hubs(1), Vector2i.ZERO, "other planets keep their gates for now")
	var d5: Dictionary = Homeward.drive_def(5)
	assert_eq(float(d5["cost"]["cubes"]), DRIVE, "the drive is the biggest number of the arc")
	assert_gt(DRIVE, FAR[FAR.size() - 1])
	assert_ne(str(Homeward.planet_def(0)["leave"]["toast"]), "", "WREN says so when the way opens")


func test_goal_chain_leads_to_the_exit() -> void:
	var b3: int = _goal_index("base_3")
	var drive: int = _goal_index("home_drive_5")
	var land: int = _goal_index("home_land_1")
	assert_gt(b3, 0)
	assert_gt(drive, b3)
	assert_eq(land, drive + 1)
	assert_lte(drive - b3, 12, "a short walk from base 3 to the drive: stations 5 and 6, Mk III, base 4 and 5 and a few garden steps")
	for id: String in ["shards_1", "pet_cat", "extras_radio", "builder_1"]:
		assert_gt(_goal_index(id), land, "%s is not on the way out" % id)
	var ch: Array = Economy.read_json("res://data/goals.json").get("goals", [])
	assert_string_contains(Objectives.goal_reason(ch[land]), "You can fly on now")


func test_hub_steps_sit_between_the_base_steps() -> void:
	var ids: Array = []
	for o: Dictionary in Economy.read_json("res://data/objectives.json").get("objectives", []):
		ids.append(str(o["id"]))
	var order: Array = ["robot", "zone", "seed", "hub_fly_2", "hub_wake_2", "base2", "hub_fly_3", "hub_wake_3", "rocket_tier_2", "base3", "hub_fly_4", "hub_wake_4"]
	for i: int in range(1, order.size()):
		assert_gt(ids.find(order[i]), ids.find(order[i - 1]), "%s comes after %s" % [order[i], order[i - 1]])
		assert_gt(ids.find(order[i - 1]), -1)
	var late: Array = ["base_4", "hub_fly_5", "hub_wake_5", "rocket_tier_3", "base_5", "hub_fly_6", "hub_wake_6"]  # base 4 and 5: an income buy inside each long saving step
	for i: int in late.size():
		assert_gt(_goal_index(late[i]), _goal_index("base_3"))
		assert_lt(_goal_index(late[i]), _goal_index("home_drive_5"))
		if i > 0:
			assert_gt(_goal_index(late[i]), _goal_index(late[i - 1]), "%s comes after %s" % [late[i], late[i - 1]])
	var tabs: Dictionary = Economy.read_json("res://data/workbench.json").get("tabs", {})
	assert_true(str(tabs.get("rockets", "")).contains("hubs_woken"), "the bench's Rocket section opens with the first woken station")


## The hub, wake and rocket steps take their why line from data/story_reasons.json: a desc of their
## own would hide it.
func test_hub_steps_carry_no_desc() -> void:
	var steps: Array = Economy.read_json("res://data/objectives.json").get("objectives", []) + Economy.read_json("res://data/goals.json").get("goals", [])
	var n: int = 0
	for o: Dictionary in steps:
		var id: String = str(o["id"])
		if id.begins_with("hub_fly_") or id.begins_with("hub_wake_") or id.begins_with("rocket_tier_"):
			n += 1
			assert_false(o.has("desc"), "%s has no desc of its own" % id)
			assert_ne(Objectives.goal_reason(o), str(Economy.read_json("res://data/story_reasons.json")["goal_reasons"]["default"]), "%s has a story reason" % id)
	assert_eq(n, 5 + 5 + 2, "hub_fly_2..6, hub_wake_2..6, rocket_tier_2..3")


# --- Every step can be done on the round planet ----------------------------------------------------

## Goal types the globe can complete (story/goals.gd value_of). The flat world's frontier types
## (frontier_base, frontier_growing, bases_l5) are not here: nothing on the globe moves them.
const GLOBE_TYPES: Array[String] = ["stat", "earned", "upgrade", "robot", "tier", "zone", "hub_level", "hex_level", "flag", "districts", "research"]
## Stats and flags the round game writes in a way the scan below can't see (written through a variable).
const WRITTEN_BY_NAME: Dictionary = {}
## Scripts that only run in the flat world: a stat written only here never moves on the globe (the
## flat Robot wrote robot_bales; the globe's crews are robots/sphere/). A bot run stalled 23 min on it.
const FLAT_ONLY: Array[String] = ["res://robots/robot.gd", "res://robots/fleet.gd"]


func _game_code() -> String:
	var out: String = ""
	var stack: Array[String] = ["res://"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for d: String in da.get_directories():
			if not d.begins_with(".") and not d in ["addons", "tests", "tools", "locale", "screenshots", "assets"]:
				stack.append(dir.path_join(d))
		for f: String in da.get_files():
			if f.ends_with(".gd") and not dir.path_join(f) in FLAT_ONLY:
				out += FileAccess.get_file_as_string(dir.path_join(f)) + "\n"
	return out


func _written(code: String, key: String) -> bool:
	if WRITTEN_BY_NAME.has(key):
		return true
	var re := RegEx.new()
	var k: String = key  # plain snake_case ids
	re.compile('inc_stat\\(\\s*"%s"|stats\\[\\s*"%s"\\s*\\]\\s*=|flags\\[\\s*"%s"\\s*\\]\\s*=' % [k, k, k])
	return re.search(code) != null


func test_every_step_is_completable_on_the_globe() -> void:
	var code: String = _game_code()
	var steps: Array = []
	for g: Dictionary in Economy.read_json("res://data/goals.json").get("goals", []):
		steps.append(["goal", g])
	for o: Dictionary in Economy.read_json("res://data/objectives.json").get("objectives", []):
		if str(o.get("type", "")) in ["stat", "flag"]:
			steps.append(["story step", o])
	for e: Array in steps:
		var g: Dictionary = e[1]
		var id: String = "%s %s" % [e[0], g["id"]]
		var t: String = str(g.get("type", "stat"))
		var key: String = str(g.get("key", ""))
		assert_true(t in GLOBE_TYPES, "%s: type %s can be done on the globe" % [id, t])
		match t:
			"stat", "flag":
				assert_true(_written(code, key), "%s: something in the game writes %s" % [id, key])
			"research":
				assert_true(Research.exists(key), "%s names real research" % id)
				assert_eq(str(Research.def(key).get("requires_tech", "")), "", "%s needs no tech from another planet (the old frontier unlocks)" % id)
			"upgrade":
				assert_true(Economy.upgrade_defs.has(key), "%s names a real upgrade" % id)
			"robot":
				assert_true(key == "any" or Economy.robots.has(key), "%s names a real robot" % id)
			"hub_level":
				assert_true(str(g.get("hub", "")) in ["", "second"], "%s: the start base or the second-best base" % id)
	for gone: String in ["sandstorms", "hexes_thawed", "heaters_placed", "greenhouses_built", "drain_stages", "frontier_seen_", "cradle_"]:
		for g2: Dictionary in Economy.read_json("res://data/goals.json").get("goals", []):
			assert_false(str(g2.get("key", "")).begins_with(gone), "goal %s is from the flat world's frontiers" % g2["id"])


func test_woken_bases_keep_cleaning() -> void:
	var c: Dictionary = BaseKeepers.cfg()
	assert_gt(float(c.get("cells_per_min", 0.0)), 0.0, "a woken base cleans on its own")
	assert_false(bool(c.get("home", true)), "the start hub's cleaning is the player's and the crews'")
	assert_gt(BaseKeepers.rate(3, 0), BaseKeepers.rate(2, 0), "a higher base level cleans faster")
	assert_gt(BaseKeepers.rate(2, 4), BaseKeepers.rate(2, 0), "robots left there add to it")
	assert_eq(BaseKeepers.rate(1, 0, {"cells_per_min": 2.0, "per_level": 1.0}), 2.0)
	assert_eq(str(Hub.far_cfg().get("pct_over", "")), "all_regions", "the planet % counts the playable world, so it only goes up")


func test_pace_knob_scales_sales() -> void:
	var cfg: Dictionary = Hub._hub_cfg()
	var far: Dictionary = cfg["far_hub"]
	var was: Variant = far.get("pace", 1.0)
	assert_eq(float(was), PACE, "Verdance's pace (docs/BALANCE.md)")
	far["pace"] = 2.0
	assert_almost_eq(Hub.trade_mult(), 0.5, 0.0001, "pace 2: every sale pays half, every cube step takes twice as long")
	far["pace"] = was
	assert_almost_eq(Hub.trade_mult(), 1.0 / PACE, 0.0001)


## [v6pace] The first robot never waits on lucky salvage: the Bot Bay brings the Parts for it.
func test_bot_bay_brings_the_first_robots_parts() -> void:
	var bay: Dictionary = BenchTiers.def(2)
	assert_gte(float((bay.get("grants", {}) as Dictionary).get("parts", 0.0)), float(Economy.robots["scoopie"].get("parts", 0)), "the Bot Bay's kit covers the first Scoopie's Parts")
	assert_lte(float((bay["cost"] as Dictionary)["cubes"]), 1000.0, "the Bot Bay is a short save in the first half hour")


## [v6pace] Verdance opens on its six stations only, not on half its Bloom Core.
func test_verdance_leaves_on_stations_only() -> void:
	assert_false(Homeward.leave_pct_opens(0))
	assert_eq(Homeward.leave_hubs(0), Vector2i(6, 2))


func test_base_prices() -> void:
	var lv: Array = Economy.read_json("res://data/hub.json")["levels"]
	assert_eq(float(lv[1]["cost"]["cubes"]), 1500.0, "base 2: the owner's start stays")
	assert_eq(float(lv[2]["cost"]["cubes"]), BASE3)


func test_clock_stands_still_behind_the_loader() -> void:
	var ld: Node = get_node_or_null("/root/Loader")
	if ld == null:
		pass_test("no Loader autoload in this run")
		return
	var was: bool = bool(ld.get("active"))
	var t0: float = float(GameState.stats.get("time_played", 0.0))
	ld.set("active", true)
	GameState._physics_process(1.0)
	assert_eq(float(GameState.stats.get("time_played", 0.0)), t0, "no play time while the loading screen is up")
	ld.set("active", false)
	GameState._physics_process(1.0)
	assert_gt(float(GameState.stats.get("time_played", 0.0)), t0)
	ld.set("active", was)


# The pinned numbers (cubes).
const FAR: Array[float] = [600.0, 2400.0, 9600.0, 38000.0, 200000.0]  # hub 6: cost_override "4" (a push before the drive)
const MK2: float = 8000.0
const PACE: float = 1.45
const MK3: float = 100000.0
const DRIVE: float = 500000.0
const BASE3: float = 9000.0
