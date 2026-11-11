extends GutTest
## The cube economy's rules (design spec sections 14, 16 and 17; task M3-19): a hex has a cube
## value and a unit of waste does not, a pressed bale always beats tipping, robots earn no cubes,
## goals pay when they complete, no reward is larger than 3 minutes of income, numbers are whole.
## Tests that can run on any planet take the planet id: the first planet and the dummy planet
## (which has no districts table and no tiers: the fallbacks).

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const CLEAN_SHARE: float = 1.0 - SphereCells.CLEAN_LEFT

var _saved: Dictionary = {}
var _fx: DistrictFixture
var _nodes: Array[Node] = []


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.set_current(Planets.first_shipped().id)
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = {"currencies": GameState.currencies, "flags": GameState.flags, "stats": GameState.stats,
		"upgrades": GameState.upgrades, "world": GameState.world}
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.upgrades = {}
	GameState.world = {}


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if _fx:
		_fx.free_systems()
	_fx = null
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.stats = _saved["stats"]
	GameState.upgrades = _saved["upgrades"]
	GameState.world = _saved["world"]
	Planets.set_current(Planets.first_shipped().id)


func _cubes() -> float:
	return GameState.get_currency("cubes").to_float()


## The worth of the start district's hexes of a planet on the fixture globe.
func _worth(planet_id: StringName) -> HexWorth:
	Planets.set_current(planet_id)
	_fx = DistrictFixture.new(planet_id, false)
	return HexWorth.for_planet(_fx.def, _fx.grid, _fx.site_cells)


## A hex next to the start site (a first hex) and one at the edge of open play.
func _sample_cells(w_fx: DistrictFixture) -> Array[int]:
	var rings: Array[PackedInt32Array] = HexWorth.rings_around(w_fx.grid, w_fx.site_cells[0], 4)
	return [rings[1][0], rings[2][0], rings[4][0]]


## Cleans one hex by hand in scoop pulses down to the clean line, the chest emptied by `empty`
## (called with the load's contents, its worth and the chest's capacity) each time it fills.
## Returns the cubes paid in all.
func _clean_hex(worth: HexWorth, cell: int, capacity: float, pulse: float, empty: Callable) -> float:
	var total: float = worth.work(cell)
	var left: float = total
	var comp := Compartment.new()
	var paid: float = 0.0
	while left > total * (1.0 - CLEAN_SHARE) + 0.0001:
		var vol: float = minf(pulse, left)
		comp.add("plastic", vol, worth.share(cell, vol, left, total, CLEAN_SHARE))
		left -= vol
		if not comp.can_accept(capacity):
			var load_worth: float = comp.worth
			paid += float(empty.call(comp.take_all(), load_worth, capacity))
	if not comp.is_empty():
		var last_worth: float = comp.worth
		paid += float(empty.call(comp.take_all(), last_worth, capacity))
	return paid


func _tip(contents: Dictionary, worth: float, _capacity: float) -> float:
	return Economy.pay_whole_cubes(Pace.dump_value(contents, worth))


func _press(contents: Dictionary, worth: float, capacity: float) -> float:
	var info: Dictionary = Economy.evaluate_cube(contents, capacity, 1.0, worth)
	return Economy.pay_whole_cubes((info["value"] as BigNum).to_float())


# --- A hex has a cube value ---------------------------------------------------------------------

func test_loose_loads_over_a_whole_hex_pay_the_hexs_value(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var worth: HexWorth = _worth(planet_id)
	for cell: int in _sample_cells(_fx):
		for pulse: float in [0.7, 1.22, 3.1]:
			GameState.currencies = {}
			GameState.flags = {}
			var paid: float = _clean_hex(worth, cell, 12.0, pulse, _tip)
			assert_almost_eq(paid, worth.cubes(cell) * Economy.loose_mult(), 1.0, "hex %d at %.2f a pulse pays its value loose" % [cell, pulse])
			assert_almost_eq(_cubes(), paid, 0.001, "what was paid is what the purse holds")
			assert_almost_eq(_cubes(), roundf(_cubes()), 0.0001, "the purse holds whole cubes")


func test_bales_over_a_whole_hex_pay_the_hexs_value_times_the_press(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var worth: HexWorth = _worth(planet_id)
	var cell: int = _sample_cells(_fx)[0]
	# Capacity 10 with 1.0 pulses: every full bale is pressed to the brim, a perfect press. The last,
	# part-full bale is pressed at a lower quality, so the total sits between plain and perfect.
	var paid: float = _clean_hex(worth, cell, 10.0, 1.0, _press)
	var value: float = worth.cubes(cell)
	assert_gt(paid, value * Economy.press_mult(Economy.PRESS_PLAIN) - 1.0, "never under the plain press")
	assert_lt(paid, value * Economy.press_mult(Economy.PRESS_PERFECT) + 1.0, "never over the perfect press")
	GameState.currencies = {}
	GameState.flags = {}
	assert_gt(paid, _clean_hex(worth, cell, 10.0, 1.0, _tip), "baling a hex beats tipping it")


func test_a_heavier_hex_does_not_pay_more(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var worth: HexWorth = _worth(planet_id)
	var cell: int = _sample_cells(_fx)[2]
	var by_weight: Array[float] = []
	for total: float in [120.0, 480.0, 4600.0]:
		var left: float = total
		var paid: float = 0.0
		while left > total * (1.0 - CLEAN_SHARE) + 0.0001:
			var vol: float = minf(1.22, left)
			paid += worth.share(cell, vol, left, total, CLEAN_SHARE)
			left -= vol
		by_weight.append(paid)
	assert_almost_eq(by_weight[0], worth.cubes(cell), 0.01)
	assert_almost_eq(by_weight[1], by_weight[0], 0.01, "four times the waste, the same cubes")
	assert_almost_eq(by_weight[2], by_weight[0], 0.01)


func test_the_swept_remainder_and_a_robots_share_pay_lumi_nothing() -> void:
	var value: float = 100.0
	assert_almost_eq(HexWorth.share_of(value, 5.0, 5.0, 100.0, 0.95), 0.0, 0.0001, "the last 5% sweeps away: no cubes")
	assert_almost_eq(HexWorth.share_of(value, 10.0, 10.0, 100.0, 0.95), value * 5.0 / 95.0, 0.0001, "only the part above the clean line")
	# Robots took the hex from 100 to 50 units; Lumi cleans the rest and is paid for her half.
	var paid: float = 0.0
	var left: float = 50.0
	while left > 5.0001:
		paid += HexWorth.share_of(value, 1.0, left, 100.0, 0.95)
		left -= 1.0
	assert_almost_eq(paid, value * 45.0 / 95.0, 0.01)


func test_the_first_planet_states_each_citys_hex_value_and_first_hexes() -> void:
	var worth: HexWorth = _worth(FIRST)
	var table: Dictionary = _fx.def.table(Districts.TABLE)
	var rows: Array = table["districts"]
	assert_eq(rows.size(), 6)
	var prev: float = 0.0
	for i: int in rows.size():
		var d: Dictionary = rows[i]
		assert_true(d.has("hex_cubes") and d.has("hex_work"), "%s states its hex value and weight" % d["id"])
		assert_gte(float(d["hex_cubes"]), prev, "a later city is never poorer per hex")
		prev = float(d["hex_cubes"])
		var edge: int = HexWorth.rings_around(_fx.grid, _fx.site_cells[int(d["site"])], int(d["rings"]))[int(d["rings"])][0]
		assert_almost_eq(worth.cubes(edge), float(d["hex_cubes"]), 0.001)
		assert_almost_eq(worth.work(edge), float(d["hex_work"]), 0.001)
	var first: Dictionary = (rows[0] as Dictionary)["first_hexes"]
	var near: Array[PackedInt32Array] = HexWorth.rings_around(_fx.grid, _fx.site_cells[0], 3)
	assert_almost_eq(worth.work(near[1][0]), float(first["work"]), 0.001, "the first ring is light")
	assert_almost_eq(worth.work(near[1][0]) / 12.0, 9.0, 0.5, "nine loads of the starting chest (task M3-21: the first hex in about a minute for the bot)")
	assert_gt(worth.work(near[2][0]), worth.work(near[1][0]), "then hexes grow")
	assert_almost_eq(worth.work(near[3][0]), float((rows[0] as Dictionary)["hex_work"]), 0.001, "to the city's full weight")


func test_a_planet_without_hex_values_prices_a_hex_at_its_waste(planet_id: StringName = use_parameters([DUMMY])) -> void:
	var worth: HexWorth = _worth(planet_id)
	var cell: int = _sample_cells(_fx)[0]
	assert_almost_eq(worth.work(cell), HexWorth.DEFAULT_WORK, 0.001)
	assert_almost_eq(worth.cubes(cell), HexWorth.DEFAULT_WORK * HexWorth.mean_waste_value(), 0.001)


# --- Loose never beats a bale --------------------------------------------------------------------

func test_loose_never_beats_a_bale_at_any_fill(planet_id: StringName = use_parameters(PLANETS)) -> void:
	Planets.set_current(planet_id)
	var capacity: float = 12.0
	for fill: float in [0.05, 0.3, 0.59, 0.6, 0.89, 0.9, 1.0, 1.08, 1.4]:
		var contents: Dictionary = {"plastic": capacity * fill * 0.6, "metal": capacity * fill * 0.4}
		for worth: float in [-1.0, 3.0, 44.0]:
			var loose: float = Pace.dump_value(contents, worth)
			var bale: float = (Economy.evaluate_cube(contents, capacity, 1.0, worth)["value"] as BigNum).to_float()
			assert_gt(bale, loose, "a bale at %.0f%% full beats tipping it (worth %.0f)" % [fill * 100.0, worth])


func test_the_first_planet_presses_plain_good_and_perfect() -> void:
	Planets.set_current(FIRST)
	assert_almost_eq(Economy.loose_mult(), 1.0, 0.0001, "tipping pays 1.0x")
	assert_almost_eq(Economy.press_mult(Economy.PRESS_PLAIN), 1.15, 0.0001)
	assert_almost_eq(Economy.press_mult(Economy.PRESS_PERFECT), 1.5, 0.0001)
	assert_gt(Economy.press_mult(Economy.PRESS_GOOD), Economy.press_mult(Economy.PRESS_PLAIN))
	assert_lt(Economy.press_mult(Economy.PRESS_GOOD), Economy.press_mult(Economy.PRESS_PERFECT))
	assert_eq(Economy.press_quality(0.3), Economy.PRESS_PLAIN)
	assert_eq(Economy.press_quality(0.7), Economy.PRESS_GOOD)
	assert_eq(Economy.press_quality(0.95), Economy.PRESS_PERFECT)
	assert_eq(Economy.press_quality(1.2), Economy.PRESS_PLAIN, "an overstuffed chest presses a plain bale")
	var first_bale: float = (Economy.evaluate_cube({"plastic": 12.0}, 12.0, 1.0, 12.0)["value"] as BigNum).to_float()
	assert_between(first_bale, 10.0, 99.0, "a bale sells for tens of cubes")


# --- Robots earn no cubes ------------------------------------------------------------------------

func test_time_away_cleans_but_pays_no_cubes(planet_id: StringName = use_parameters(PLANETS)) -> void:
	Planets.set_current(planet_id)
	var robots: Array = [{"type": "scoopie", "tier": 0}, {"type": "scoopie", "tier": 1}, {"type": "haulbug", "tier": 0}]
	var result: Dictionary = Offline.compute(robots, 0, 0.0, 3600.0, 1.0e6)
	assert_eq(float(result["cubes"]), 0.0)
	assert_eq(float(result["waiting_value"]), 0.0)
	Offline.apply(result)
	assert_eq(_cubes(), 0.0, "robots add no cubes")
	if Economy.robots.has("scoopie"):
		assert_gt(float(result["units"]), 0.0, "but the crew kept cleaning")


func test_a_clean_hex_and_a_field_note_pay_no_cubes() -> void:
	Planets.set_current(FIRST)
	Research.award_data(Research.reward("hex_cleaned"))
	Research.award_data(Research.reward("robot_bale"))
	assert_eq(_cubes(), 0.0, "a field note is knowledge, not money")
	for row: Variant in Economy.planet_table("regrowth").get("levels", []):
		assert_false(((row as Dictionary).get("reward", {}) as Dictionary).has("cubes"), "a hex's stage pays no cubes")
		assert_false(((row as Dictionary).get("bonus", {}) as Dictionary).has("cubes_per_min"), "no garden stipend")
		assert_false(((row as Dictionary).get("bonus", {}) as Dictionary).has("wildlife_cubes_per_min"), "no wildlife trickle")


# --- City stage payouts --------------------------------------------------------------------------

func test_a_city_stage_pays_once_and_never_for_the_past() -> void:
	Planets.set_current(FIRST)
	_fx = DistrictFixture.new(FIRST)
	var payouts := CityPayouts.new()
	_nodes.append(payouts)
	payouts.setup(_fx.def, _fx.districts)
	var id: String = _fx.districts.ids()[0]
	var rule: Dictionary = CityPayouts.rule_of(_fx.def)
	var hex_cubes: float = CityPayouts.hex_cubes_of(_fx.def)[id]
	watch_signals(EventBus)
	_fx.set_district_stage(id, 1)
	assert_eq(_fx.districts.stage_of(id), 1)
	assert_almost_eq(_cubes(), CityPayouts.reward_for(rule, hex_cubes, 1), 0.001, "stage 1 pays its reward")
	assert_signal_emit_count(EventBus, "district_stage_paid", 1)
	_fx.set_district_stage(id, 3)
	var after_three: float = CityPayouts.reward_for(rule, hex_cubes, 1) + CityPayouts.reward_for(rule, hex_cubes, 2) + CityPayouts.reward_for(rule, hex_cubes, 3)
	assert_almost_eq(_cubes(), after_three, 0.001, "two stages at once pay both")
	# A save from before payouts existed: a city already at stage 3 is not paid for it again.
	var saved: Dictionary = payouts.save_state()
	payouts.load_state({})
	assert_eq(payouts.paid_stage(id), 3)
	payouts.load_state(saved)
	assert_eq(payouts.paid_stage(id), 3)
	EventBus.district_stage_changed.emit(id, 3)
	assert_almost_eq(_cubes(), after_three, 0.001, "nothing twice")


func test_a_planet_without_a_stage_rule_pays_nothing(planet_id: StringName = use_parameters([DUMMY])) -> void:
	Planets.set_current(planet_id)
	_fx = DistrictFixture.new(planet_id)
	var payouts := CityPayouts.new()
	_nodes.append(payouts)
	payouts.setup(_fx.def, _fx.districts)
	_fx.set_district_stage(_fx.districts.ids()[0], 2)
	assert_eq(_cubes(), 0.0)


# --- Goals pay when they complete ----------------------------------------------------------------

func _goals() -> Goals:
	var g := Goals.new()
	_nodes.append(g)
	g.load_chain()
	return g


func test_a_goal_completed_off_card_pays_at_once() -> void:
	Planets.set_current(FIRST)
	var g: Goals = _goals()
	g.card_goal = 0  # the card shows the first goal and completes it itself
	var far: int = -1
	for i: int in g.chain.size():
		if str(g.chain[i]["id"]) == "hex_5":
			far = i
	assert_gt(far, 3, "a goal well down the chain")
	GameState.stats["hexes_cleaned"] = 5
	var done: Array[int] = []
	for _beat: int in 6:
		var i: int = g.check()
		if i >= 0:
			done.append(i)
	assert_has(done, far, "it completes although the card is on another step")
	assert_does_not_have(done, 0, "the card's own goal is left to the card")
	var expect: float = 0.0
	for i: int in done:
		expect += float(g.reward_of(i).get("cubes", 0.0))
	assert_almost_eq(_cubes(), expect, 0.001, "and its reward is in the purse at once")
	assert_eq(g.check(), -1, "paid once")


# --- The 3-minute rule ---------------------------------------------------------------------------

func test_no_reward_exceeds_three_minutes_of_city_one_income() -> void:
	Planets.set_current(FIRST)
	var table: Dictionary = Planets.current().table(Districts.TABLE)
	var city: Dictionary = (table["districts"] as Array)[0]
	var limit: float = float(table["income_ref_s"]) * float(city["income_ref"])
	assert_almost_eq(float(table["income_ref_s"]), 180.0, 0.001, "3 minutes")
	var largest: float = 0.0
	for g: Variant in Economy.planet_table("goals").get("goals", []):
		var cubes: float = float(((g as Dictionary).get("reward", {}) as Dictionary).get("cubes", 0.0))
		largest = maxf(largest, cubes)
		assert_lte(cubes, limit, "goal %s" % (g as Dictionary)["id"])
	for o: Variant in Economy.planet_table("tutorial").get("objectives", []):
		assert_false((o as Dictionary).has("reward"), "story steps carry no payout of their own")
	var rule: Dictionary = table[CityPayouts.KEY]
	for stage: int in range(1, Districts.MAX_STAGE + 1):
		var paid: float = CityPayouts.reward_for(rule, float(city["hex_cubes"]), stage)
		largest = maxf(largest, paid)
		assert_lte(paid, limit, "city stage %d" % stage)
	var lumi: Dictionary = Economy.planet_table("robot_level").get("reward", {})
	assert_lte(float(lumi["cube_secs"]), float(table["income_ref_s"]), "a Lumi level pays seconds of income, under the limit")
	assert_eq(int(lumi["part_every"]), 0, "and no Parts: those come from salvage alone")
	assert_eq(int(lumi["bonus_parts_every"]), 0)
	# A level pays cube_secs of current income, between a floor and a cap that both grow with the
	# level. At the first city's measured income (task M3-21: 5 cubes a second, not the proposal's
	# 14) every level stays under the limit; the cap alone passes it only from level 24 (940), and
	# is paid only where 30 s of income is that large, which is 3 minutes of 5,600.
	var income_now: float = float(lumi["cube_secs"]) * float(city["income_ref"])
	for lv: int in [2, 5, 10, 20, 30]:
		var plan: Dictionary = LumiLevel.reward_plan(lv, income_now, 20000.0, true)
		assert_lte(float(plan["cubes"]), limit, "Lumi level %d at the city's income" % lv)
		assert_eq(int(plan["parts"]) + int(plan["bonus_parts"]), 0)
		var rich: Dictionary = LumiLevel.reward_plan(lv, 1.0e9, 20000.0, true)
		if lv <= 20:
			assert_lte(float(rich["cubes"]), limit, "Lumi level %d at its cap" % lv)
	assert_eq(Research.note_pay(), 0.0, "field notes pay no cubes")
	gut.p("largest one-off cube reward in city 1: %d (limit %d)" % [int(largest), int(limit)])


func test_early_goals_pay_small_and_in_the_currency_of_the_action() -> void:
	Planets.set_current(FIRST)
	var goals: Array = Economy.planet_table("goals").get("goals", [])
	for i: int in 12:
		assert_lte(float(((goals[i] as Dictionary).get("reward", {}) as Dictionary).get("cubes", 0.0)), 30.0, "an early goal is a small win")
	for g: Variant in goals:
		var d: Dictionary = g
		var reward: Dictionary = d.get("reward", {})
		if str(d.get("type", "")) in ["robot", "tier", "zone"]:
			assert_true(reward.is_empty(), "%s: crew goals hand out no currency" % d["id"])
		if str(d.get("type", "")) == "hex_level":
			assert_false(reward.has("cubes"), "%s: regrowth pays seeds, not cubes" % d["id"])
		if reward.has("parts"):
			assert_eq(str(d.get("key", "")), "parts_found", "%s: Parts only for digging parts up" % d["id"])


# --- Prices and tiers ----------------------------------------------------------------------------

func test_city_one_tracks_follow_the_accepted_prices() -> void:
	Planets.set_current(FIRST)
	for row: Array in [["scoop_speed", 40.0], ["multi_lock", 40.0], ["compartment_size", 50.0]]:
		var id: String = row[0]
		assert_true(Economy.is_track(Economy.upgrade_defs[id]))
		assert_eq(Economy.upgrade_cap(id), 8, "%s: 8 levels in the first city" % id)
		for lv: int in 8:
			assert_almost_eq(Economy.upgrade_cost(id, lv).to_float(), roundf(float(row[1]) * pow(1.6, lv)), 0.5, "%s level %d" % [id, lv + 1])
	assert_almost_eq(Economy.stat("capacity", {"compartment_size": 1}), 24.0, 0.001, "a chest level adds a starting chest")
	assert_almost_eq(Economy.stat("scoop_rate", {"scoop_speed": 1}) / Economy.base_stat("scoop_rate"), 1.18, 0.001)
	assert_almost_eq(Economy.stat("pickup_count", {"multi_lock": 1}) / Economy.base_stat("pickup_count"), 1.18, 0.001, "the two scoop tracks match")
	# Task M3-21: the Baler is priced from the game's real income, so the wait for it stays short.
	assert_almost_eq(Economy.upgrade_cost("baler", 0).to_float(), 130.0, 0.5)


func test_a_new_city_opens_the_next_tier_of_every_track() -> void:
	Planets.set_current(FIRST)
	GameState.upgrades = {"scoop_speed": 8}
	assert_true(Economy.is_maxed("scoop_speed"), "the first city's levels are sold")
	assert_true(Economy.waits_for_district("scoop_speed"), "more wait for the next city")
	assert_eq(Economy.buy_upgrade("scoop_speed"), 0)
	GameState.flags[Economy.FLAG_TIERS_OPEN] = 2
	assert_false(Economy.is_maxed("scoop_speed"))
	assert_eq(Economy.upgrade_cap("scoop_speed"), 12)
	assert_almost_eq(Economy.upgrade_cost("scoop_speed", 8).to_float(), 650.0, 0.5, "the second tier starts at its own price")
	assert_almost_eq(Economy.upgrade_cost("scoop_speed", 9).to_float(), 845.0, 0.5, "and climbs by its own ratio")
	assert_lt(Economy.upgrade_cost("scoop_speed", 8).to_float(), Economy.upgrade_cost("scoop_speed", 7).to_float(), "a new city's first level is cheaper than the old city's last")
	assert_eq(Economy.upgrade_max("scoop_speed"), 52, "52 levels on this planet")
	GameState.add_currency("cubes", BigNum.from_float(2000.0))
	assert_eq(Economy.buy_upgrade("scoop_speed", 0), 2, "buy-max pays each level's own price: 650 + 845")
	assert_almost_eq(_cubes(), 505.0, 0.5)


func test_nothing_in_city_one_costs_more_than_the_low_thousands() -> void:
	Planets.set_current(FIRST)
	var largest: float = 0.0
	var what: String = ""
	for id: String in Economy.upgrade_order:
		if Economy.upgrade_defs[id].has("robot"):
			continue
		for lv: int in maxi(Economy.upgrade_cap(id), 0):
			var c: float = Economy.upgrade_cost(id, lv).to_float()
			if c > largest:
				largest = c
				what = "%s level %d" % [id, lv + 1]
	for table: Array in [["hub", "levels"], ["signal_tower", "tiers"], ["trash_bin", "levels"]]:
		for row: Variant in Economy.planet_table(table[0]).get(table[1], []):
			var cost: Dictionary = (row as Dictionary).get("cost", {})
			assert_false(cost.has("parts"), "%s: builds and base levels cost cubes only" % table[0])
			if float(cost.get("cubes", 0.0)) > largest:
				largest = float(cost["cubes"])
				what = "%s %s" % [table[0], str((row as Dictionary).get("name", ""))]
	for row: Variant in BenchTiers.tiers():
		var bench: float = float(((row as Dictionary).get("cost", {}) as Dictionary).get("cubes", 0.0))
		if bench > largest:
			largest = bench
			what = str((row as Dictionary).get("name", ""))
	# Research counts too (docs/DECISIONS.md, Nov 11). The first city's research is tiers 0 to 5;
	# tiers 6 and 7 are the frontier nodes of later cities (the research table's _doc).
	for id: String in Research.ids():
		if int(Research.def(id).get("tier", 0)) > CITY_ONE_RESEARCH_TIERS:
			continue
		var price: float = Research.cost(id).to_float()
		if price > largest:
			largest = price
			what = "research %s" % id
	assert_lt(largest, 4200.0, "the dearest cube price reachable in city 1 (%s) stays under the accepted 4,200" % what)
	gut.p("largest cube price in city 1: %d (%s)" % [int(largest), what])


## The last research tier that belongs to the first city.
const CITY_ONE_RESEARCH_TIERS: int = 5


func test_the_first_robot_costs_parts_only_and_parts_are_scarce() -> void:
	Planets.set_current(FIRST)
	var scoopie: Dictionary = Economy.robots["scoopie"]
	assert_eq(float(scoopie["cost"]), 0.0, "robots cost no cubes")
	assert_eq(float(scoopie["parts"]), 10.0, "the first robot's price in Parts")
	var mean: float = 0.0
	var weight: float = 0.0
	var rarities: Array = Economy.parts.get("rarities", [])
	for i: int in rarities.size():
		mean += float((rarities[i] as Dictionary)["weight"]) * RobotParts.value(i)
		weight += float((rarities[i] as Dictionary)["weight"])
		assert_lte(RobotParts.value(i), 3.0, "one find is at most 3 Parts")
	mean /= weight
	var buried: float = RobotParts.buried_per_hex() * mean
	var mix_chance: float = 0.0
	var mix_weight: float = 0.0
	for id: String in Economy.junk_ids:
		var w: float = float(Economy.junk_types[id].get("weight", 1.0))
		mix_weight += w
		mix_chance += w * float((Economy.robot_cfg.get("part_drop", {}) as Dictionary).get(id, 0.0))
	var rules: Dictionary = RobotParts.salvage_rules()
	var stripped: float = mix_chance / mix_weight * float(rules["ref_work"]) * CLEAN_SHARE / float(rules["ref_take"]) * mean
	assert_between(buried + stripped, 0.3, 1.5, "a hand-cleaned hex yields about a Part (%.2f buried + %.2f stripped)" % [buried, stripped])
	assert_almost_eq(RobotParts.strip_scale(1.22, 120.0), 1.0, 0.001)
	assert_almost_eq(RobotParts.strip_scale(1.22, 480.0), 0.25, 0.001, "a hex four times as heavy holds the same Parts, spread thinner")
	assert_almost_eq(RobotParts.strip_scale(2.44, 120.0), 2.0, 0.001, "a bigger scoop finds them at the same rate per unit")


# --- Old saves ----------------------------------------------------------------------------------

func test_a_chest_saved_before_hexes_had_a_value_still_pays() -> void:
	Planets.set_current(FIRST)
	var comp := Compartment.new()
	comp.from_dict({"contents": {"plastic": 6.0, "metal": 4.0}, "fill": 10.0})
	assert_lt(comp.worth, 0.0, "no worth on record")
	var worth: float = comp.worth
	var paid: float = Pace.dump_value(comp.take_all(), worth)
	assert_almost_eq(paid, 6.0 * 0.6 + 4.0 * 1.0, 0.001, "priced by the unit, as it was")
	comp.from_dict({"contents": {"plastic": 6.0}, "fill": 6.0, "worth": 5.5})
	assert_almost_eq(comp.worth, 5.5, 0.0001, "a new save keeps the load's worth")
	comp.from_dict({})
	assert_eq(comp.worth, 0.0, "an empty chest is worth nothing, not unknown")
	comp.add("plastic", 1.0, 0.9)
	assert_almost_eq(comp.worth, 0.9, 0.0001)


func test_whole_cube_payouts_keep_the_remainder() -> void:
	var paid: float = 0.0
	for _i: int in 10:
		paid += Economy.pay_whole_cubes(9.7)
	assert_almost_eq(paid, 97.0, 0.001, "ten loads of 9.7 pay 97 in whole cubes")
	assert_almost_eq(_cubes(), 97.0, 0.001)
	assert_almost_eq(float(GameState.flags[Economy.FLAG_CUBE_CARRY]), 0.0, 0.001)
	assert_eq(Economy.pay_whole_cubes(0.4), 0.0)
	assert_eq(Economy.pay_whole_cubes(0.7), 1.0, "the carried part comes with the next payout")


# --- Number display -------------------------------------------------------------------------------

func test_numbers_are_whole_with_no_suffix_under_100000() -> void:
	for row: Array in [[0.0, "0"], [0.4, "0"], [9.7, "9"], [44.0, "44"], [999.0, "999"], [1000.0, "1000"], [1611.0, "1611"],
			[12400.0, "12400"], [99999.0, "99999"]]:
		for fmt: int in [BigNum.Format.SHORT, BigNum.Format.SCIENTIFIC, BigNum.Format.ENGINEERING]:
			assert_eq(BigNum.from_float(float(row[0])).format(fmt), str(row[1]), "%s in format %d" % [str(row[0]), fmt])
	assert_eq(BigNum.from_float(100000.0).format(BigNum.Format.SHORT), "100K", "abbreviation starts at 100,000")
	assert_eq(BigNum.from_float(2500000.0).format(BigNum.Format.SHORT), "2.5M")
	assert_eq(BigNum.from_float(-250.0).format(BigNum.Format.SHORT), "-250")
