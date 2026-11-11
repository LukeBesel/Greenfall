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


func test_rocket_comes_with_the_first_working_robot() -> void:
	assert_eq(Hub.rocket_level(), 1, "no base level stands before the first hop")
	var ch: Array = Economy.read_json("res://data/objectives.json").get("objectives", [])
	var zone: int = -1
	for i: int in ch.size():
		if str(ch[i]["id"]) == "zone":
			zone = i
	assert_gt(zone, 0, "the story still has its 'zone' step")
	GameState.flags["objective_step"] = zone
	assert_false(Hub.rocket_open(1), "not while the robot-zone step is on the card")
	assert_ne(Hub.rocket_lock_text(1), "")
	GameState.flags["objective_step"] = zone + 1
	assert_true(Hub.rocket_open(1))
	assert_eq(Hub.rocket_lock_text(1), "")


func test_far_hub_prices_multiply() -> void:
	var cfg: Dictionary = Hub.far_cfg()
	assert_eq(Hub.far_level(), 2)
	for n: int in FAR.size():
		assert_eq(float(Hub.far_cost(n)["cubes"]), FAR[n], "far hub %d" % (n + 2))
	for n: int in range(2, FAR.size()):
		var f: float = float(Hub.far_cost(n)["cubes"]) / float(Hub.far_cost(n - 1)["cubes"])
		assert_almost_eq(f, float(cfg["cost_growth"]["cubes"]), 0.3, "one growth factor between steps")
	assert_gte(float(Hub.far_cost(4)["cubes"]), 100000.0, "hub 6 costs hundreds of thousands (owner note 64)")


func test_nice_keeps_two_digits() -> void:
	assert_eq(Hub.nice(4056.0), 4100.0)
	assert_eq(Hub.nice(384000.0), 380000.0)
	assert_eq(Hub.nice(1000.0), 1000.0)
	assert_eq(Hub.nice(42.4), 42.0)


func test_trade_multiplier_is_one_without_far_hubs() -> void:
	assert_eq(Hub.trade_mult(), 1.0)
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
	assert_lte(drive - b3, 6, "a short walk from base 3 to the drive")
	for id: String in ["shards_1", "pet_cat", "extras_radio", "builder_1", "research_dunes", "visit_dust", "base_4", "base_5"]:
		assert_gt(_goal_index(id), land, "%s is not on the way out" % id)
	var ch: Array = Economy.read_json("res://data/goals.json").get("goals", [])
	assert_string_contains(Objectives.goal_reason(ch[land]), "You can fly on now")


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
const FAR: Array[float] = [600.0, 6000.0, 24000.0, 96000.0, 380000.0]
const MK2: float = 20000.0
const MK3: float = 150000.0
const DRIVE: float = 500000.0
const BASE3: float = 9000.0
