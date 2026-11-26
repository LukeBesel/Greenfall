extends GutTest
## [v10pace] Owner playtest 3 (docs/OWNER_FEEDBACK.md items 97, 98, 99, 106, 107): the Bot Bay is
## its own machine, no look before the Locker, the first flight comes late and is built by the
## player, whole seeds and parts, a long day.

var _flags: Dictionary
var _stats: Dictionary
var _orbit: Dictionary
var _cur: Dictionary
var _world: Dictionary


func before_each() -> void:
	_flags = GameState.flags
	_stats = GameState.stats
	_orbit = GameState.orbit
	_cur = GameState.currencies
	_world = GameState.world
	GameState.flags = {}
	GameState.stats = {}
	GameState.orbit = {}
	GameState.currencies = {}
	GameState.world = {}
	Designs.pending_toasts.clear()


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.orbit = _orbit
	GameState.currencies = _cur
	GameState.world = _world
	Designs.pending_toasts.clear()


func _ids() -> Array[String]:
	var out: Array[String] = []
	for o: Dictionary in Economy.read_json("res://data/objectives.json").get("objectives", []):
		out.append(str(o["id"]))
	return out


# --- Item 106: whole seeds and parts ------------------------------------------------------------------

func test_seeds_and_parts_are_always_whole() -> void:
	for id: String in ["parts"]:  # [v13goals] seeds are no currency any more
		var total: float = 0.0
		for k: int in 37:
			var amt: float = [0.5, 0.3, 0.12, 1.5, 0.725][k % 5]
			GameState.add_currency(id, BigNum.from_float(amt))
			total += amt
			var v: float = GameState.get_currency(id).to_float()
			assert_almost_eq(v, roundf(v), 0.00001, "%s is whole after +%.3f (%.4f)" % [id, amt, v])
		var have: float = GameState.get_currency(id).to_float() + float((GameState.flags["whole_carry"] as Dictionary)[id])
		assert_almost_eq(have, total, 0.001, "%s: nothing is lost, the rest is carried out of sight" % id)
		assert_eq(GameState.get_currency(id).to_float(), floorf(total + 0.0001), "%s shows the whole part" % id)


func test_a_fraction_price_leaves_a_whole_balance() -> void:
	GameState.add_currency("parts", BigNum.from_float(10.0))
	assert_true(GameState.spend("parts", BigNum.from_float(2.4)))
	assert_eq(GameState.get_currency("parts").to_float(), 7.0)
	assert_true(GameState.spend_all({"parts": 3.0}, 1.25))
	var v: float = GameState.get_currency("parts").to_float()
	assert_almost_eq(v, roundf(v), 0.00001)


func test_cubes_keep_their_fractions() -> void:
	GameState.add_currency("cubes", BigNum.from_float(1.5))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 1.5, 0.0001, "cubes are money, not things: unchanged")


func test_an_old_save_with_half_a_seed_loads_whole() -> void:
	var d: Dictionary = GameState.to_dict()
	d["currencies"] = {"seeds": BigNum.from_float(2.5).serialize(), "parts": BigNum.from_float(30.3).serialize(), "cubes": BigNum.from_float(10.5).serialize()}
	d["flags"] = {}
	GameState.from_dict(d)
	assert_eq(GameState.get_currency("parts").to_float(), 30.0)
	GameState.add_currency("parts", BigNum.from_float(0.7))
	assert_eq(GameState.get_currency("parts").to_float(), 31.0, "the carried part joins the next one")
	_flags = GameState.flags  # from_dict replaced the dictionaries: restore what the suite had
	_stats = GameState.stats
	_orbit = GameState.orbit
	_cur = GameState.currencies
	_world = GameState.world


# --- Item 107: the day -------------------------------------------------------------------------------

func test_the_day_is_long_and_mostly_light() -> void:
	var d: Dictionary = SolarSystem.globe_day("verdance")
	var day_min: float = float(d["turn_min"]) * 0.52 / float(d["day_speed"])
	var night_min: float = float(d["turn_min"]) * 0.48 / float(d["night_speed"])
	assert_between(day_min + night_min, 30.0, 40.0, "a full cycle of 30-40 minutes (%.1f)" % (day_min + night_min))
	assert_gt(day_min, night_min * 2.0, "day is the larger share by far (%.1f day, %.1f night)" % [day_min, night_min])
	var first_dusk: float = (0.76 - float(d["start_time"])) * float(d["turn_min"]) / float(d["day_speed"])
	assert_gt(first_dusk, 18.0, "a new game has well over a quarter hour of light before the first dusk (%.1f min)" % first_dusk)
	assert_eq(SolarSystem.globe_clock_speed("verdance", 0.5), float(d["day_speed"]))
	assert_eq(SolarSystem.globe_clock_speed("verdance", 0.9), float(d["night_speed"]))


# --- Item 98: no look before the Locker ---------------------------------------------------------------

func test_no_design_unlocks_before_the_locker() -> void:
	GameState.stats = {"robots_built": 500.0, "cubes_made": 5000.0, "cats_petted": 500.0, "plants_bloomed": 500.0}
	assert_false(LockerCabinet.owned())
	assert_eq(Designs.check_unlocks(false), [] as Array[String], "nothing unlocks, whatever was done")
	assert_true(Designs.pending_toasts.is_empty(), "and nothing is announced")
	YardBuilds.mark_built("locker")
	assert_true(LockerCabinet.owned())
	assert_false(Designs.check_unlocks(true).is_empty(), "with a Locker the looks that were earned are there")


func test_first_robot_brings_no_look_before_the_locker() -> void:
	var rb := RobotBuilder.new()
	add_child_autofree(rb)
	var said: Array[String] = []
	var on_toast := func(t: String, _k: String) -> void: said.append(t)
	EventBus.toast.connect(on_toast)
	GameState.stats["robots_built"] = 1.0
	rb._on_robot_built("Bolt-01")
	assert_false(RobotBuilder.count("treads") > 0 or RobotBuilder.count("bobble_plant") > 0, "no robot look with the first robot")
	assert_true(said.is_empty(), "and no message about looks (%s)" % str(said))
	YardBuilds.mark_built("locker")
	rb._starter_looks()
	assert_true(RobotBuilder.count("treads") > 0 and RobotBuilder.count("bobble_plant") > 0, "they are in the Locker once it stands")
	assert_true(said.is_empty(), "without a word")
	EventBus.toast.disconnect(on_toast)


func test_the_clover_is_rare() -> void:
	var sc: Dictionary = RobotBuilder.cfg().get("salvage", {})
	var robot_hours: float = 1.0 / float(sc["base_per_s"]) * float(sc["clover_one_in"]) / 3600.0
	assert_gt(robot_hours, 20.0, "a Lucky Clover takes over 20 robot-hours on average (%.1f)" % robot_hours)


# --- Item 97: the Bot Bay is its own machine ------------------------------------------------------------

func test_bot_bay_is_a_build_not_a_bench_upgrade() -> void:
	assert_eq(str(BenchTiers.def(2).get("build", "")), "bot_bay")
	assert_true("bot_bay" in HubBuilds.ids() and HubBuilds.kind_now("bot_bay") == "one_time", "it is bought in the Build tab")
	assert_false(BotBay.built())
	GameState.flags["signal_tower"] = 1
	GameState.stats["hexes_cleaned"] = 1.0
	assert_true(BenchLists._bench_tier(null).is_empty(), "the Upgrades tab does not offer it as a workbench upgrade")
	var e: Dictionary = HubBuilds.entry(null, "bot_bay")
	assert_eq(str(e["name"]), "Bot Bay")
	assert_eq(e["cost"], BenchTiers.def(2)["cost"])
	assert_ne(str(e["reason"]), "", "not while it can't be paid")
	for k: String in e["cost"]:
		GameState.currencies[k] = BigNum.from_float(float(e["cost"][k]))
	var built: Array[String] = []
	var on_built := func(id: String) -> void: built.append(id)
	YardBuilds.events.built.connect(on_built)
	YardBuilds.state()["bench"] = true
	assert_true(HubBuilds.build(null, "bot_bay"))
	YardBuilds.events.built.disconnect(on_built)
	assert_true(BotBay.built() and YardBuilds.built("bot_bay") and HubBuilds.is_built(null, "bot_bay"))
	assert_eq(built, ["bot_bay"] as Array[String], "the yard hears it and shows the machine")
	assert_true(Research.has("salvage_logic"), "it brings the Scoopie's plans")
	assert_false(HubBuilds.listed(null, "bot_bay"), "built once")
	assert_false(BenchLists._bench_tier(null).is_empty(), "then the workbench's next upgrade is the Research Desk")
	assert_false(UpgradesScreen.tab_visible("bots"), "and the workbench never gets a Bots tab")


func test_a_far_base_has_its_own_bot_bay_state() -> void:
	assert_false(BotBay.built("3"))
	BotBay.mark_built("3")
	assert_true(BotBay.built("3"))
	assert_false(BotBay.built("4"), "per base")
	assert_false(BotBay.built(), "the start yard's is its own")


func test_bot_bay_screen_is_robots_only() -> void:
	var scr := UpgradesScreen.new()
	scr.solo = "bots"
	add_child_autofree(scr)
	assert_eq(scr._tab, "bots")
	scr._set_tab("patch")
	assert_eq(scr._tab, "bots", "no other tab")
	for b: Button in scr._tab_buttons:
		assert_false(b.is_visible_in_tree(), "no tab row")
	var bench := UpgradesScreen.new()
	add_child_autofree(bench)
	bench._set_tab("bots")
	assert_ne(bench._tab, "bots", "the workbench cannot show robots")


# --- Item 99: the first flight ---------------------------------------------------------------------------

func test_base_one_comes_before_the_first_flight() -> void:
	var ids: Array[String] = _ids()
	var order: Array[String] = ["bench2", "robot", "hex3", "robot2", "haul", "hex10", "base2", "shuttle", "hub_fly_2"]  # [v13goals] no seed or map step  # base 2 before the shuttle: something new while saving up (critic 12)
	for i: int in range(1, order.size()):
		assert_gt(ids.find(order[i]), ids.find(order[i - 1]), "%s comes after %s" % [order[i], order[i - 1]])
		assert_gt(ids.find(order[i - 1]), -1, order[i - 1])
	assert_eq(ids.find("hub_fly_2"), ids.find("shuttle") + 1, "the flight is the step right after the shuttle is built")
	var ch: Array = Economy.read_json("res://data/objectives.json").get("objectives", [])
	for i: int in ids.find("shuttle"):
		assert_false(str(ch[i].get("key", "")) in ["hubs_seen", "hubs_woken", "rocket_tier"], "%s: nothing about flying before the shuttle" % ids[i])
	var sh: Dictionary = ch[ids.find("shuttle")]
	assert_eq(str(sh["type"]), "build")
	assert_gte((sh["lines"] as Array).size(), 2, "WREN says why, in more than one line")
	assert_true(bool(sh.get("say_all", false)))
	assert_eq(str(sh["sets_flag"]), str(YardBuilds.def("shuttle")["requires_flag"]), "the step is what lists the Shuttle build")


func test_shuttle_has_a_real_price_and_is_hidden_until_asked() -> void:
	var cost: Dictionary = YardBuilds.def("shuttle").get("cost", {})
	assert_gte(float(cost.get("cubes", 0.0)), 2000.0, "the biggest buy of the first base")
	assert_gt(float(cost.get("cubes", 0.0)), float(Hub.far_cost(0).get("cubes", 0.0)), "more than waking the next station")
	assert_gt(float(cost.get("parts", 0.0)), 0.0)
	YardBuilds.state()["bench"] = true
	assert_false(HubBuilds.listed(null, "shuttle"), "not in the Build tab before WREN asks")
	GameState.flags["shuttle_plans"] = true
	assert_true(HubBuilds.listed(null, "shuttle"))
	assert_false(Hub.rocket_built())
	for k: String in cost:
		GameState.currencies[k] = BigNum.from_float(float(cost[k]))
	assert_true(HubBuilds.build(null, "shuttle"))
	assert_true(Hub.rocket_built() and Hub.rocket_open(1))
	assert_eq(GameState.get_currency("cubes").to_float(), 0.0, "paid")
	assert_false(HubBuilds.listed(null, "shuttle"), "built once")
	var o := Objectives.new()
	assert_eq(o.value_of({"type": "build", "key": "shuttle"}), 1.0)
	o.free()


func test_old_saves_keep_their_place_in_the_new_order() -> void:
	var now: Array[String] = _ids()
	var before: Array[String] = Objectives.ORDER_V3
	for id: String in before:
		assert_true(id in now or id in ["scoop_size", "hex2", "seed"], "%s is still a step (v13goals cut three)" % id)
	# On a step both orders share, with nothing after it moved in front: the same step.
	for id: String in ["dump3", "baler", "bench2", "robot", "hex3"]:
		assert_eq(now[Objectives.remap_step(before.find(id), before, now)], id)
	# The rocket stood but the first flight was not made: back to what base 1 still owes.
	assert_eq(now[Objectives.remap_step(before.find("hub_fly_2"), before, now)], "haul")
	assert_eq(now[Objectives.remap_step(before.find("hex10"), before, now)], "haul")
	# Past the Haul Bug in the old order: nothing is put back in front.
	assert_eq(now[Objectives.remap_step(before.find("tower2"), before, now)], "tower2")
	assert_eq(now[Objectives.remap_step(before.find("hub_wake_4"), before, now)], "hub_wake_4")
	assert_eq(Objectives.remap_step(before.size(), before, now), now.size(), "all done stays all done")
	assert_eq(Objectives.remap_step(before.size() + 3, before, now), now.size() + 3)
	# Never a step earlier than one the save had not finished.
	for i: int in before.size():
		var at: int = Objectives.remap_step(i, before, now)
		for j: int in range(i, before.size()):
			if before[j] in now:
				assert_lte(at, now.find(before[j]), "old step %s: %s is still ahead" % [before[i], before[j]])


func test_haul_plans_come_before_the_first_flight() -> void:
	var when: Array = Research.def("haul_rig").get("when", [])
	for c: Array in when:
		if str(c[0]) == "since_first_robot":
			assert_lte(float(c[1]), 600.0, "minutes, not a third of an hour, after the first robot")
		if str(c[0]) == "stat":
			assert_lt(float(c[2]), 10.0, "before the ten-hex step ends")
