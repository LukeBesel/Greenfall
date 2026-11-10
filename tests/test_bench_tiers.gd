extends GutTest
## [v1guide] Owner playtest 2026-11-08: workbench tiers open the later tabs (#24, #28), upgrade rows
## keep a fixed order (#27), the Baler and the signal tower are findable (#20, #23), and the
## objectives only ask for what the workbench offers.

var _flags: Dictionary
var _stats: Dictionary
var _ups: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_ups = GameState.upgrades.duplicate(true)
	_cur = GameState.currencies.duplicate(true)
	GameState.flags = {}
	GameState.stats = {}
	GameState.upgrades = {}
	GameState.currencies["cubes"] = BigNum.from_float(0.0)
	GameState.currencies["parts"] = BigNum.from_float(0.0)


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.upgrades = _ups
	GameState.currencies = _cur


func _ids(rows: Array) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in rows:
		out.append(str(r["id"]))
	return out


func test_fresh_game_is_tier_one_with_only_upgrades_and_build() -> void:
	assert_eq(BenchTiers.tier(), 1)
	assert_true(UpgradesScreen.tab_visible("patch"))
	for tab: String in ["bots", "research", "contracts"]:
		assert_false(UpgradesScreen.tab_visible(tab), "%s is shut on a fresh bench" % tab)


func test_earning_cubes_alone_opens_no_tab() -> void:
	assert_eq(BenchTiers.tier(), 1)  # the save's tier is fixed now
	GameState.stats["cubes_earned_total"] = BigNum.from_float(1.0e6).serialize()
	GameState.stats["robots_built"] = 3.0
	GameState.stats["research_done"] = 2.0
	assert_false(UpgradesScreen.tab_visible("bots"), "only a bench tier opens Bots")
	assert_false(UpgradesScreen.tab_visible("research"), "only a bench tier opens Research")


func test_each_tier_opens_its_tab_in_order() -> void:
	var order: Array[String] = []
	for i: int in range(2, BenchTiers.max_tier() + 1):
		for tab: Variant in BenchTiers.def(i).get("tabs", []):
			order.append(str(tab))
	assert_eq(order, ["bots", "research", "contracts"] as Array[String], "Bots, then Research, then Requests")
	GameState.flags["bench_tier"] = 2
	assert_true(UpgradesScreen.tab_visible("bots"))
	assert_false(UpgradesScreen.tab_visible("research"))
	GameState.flags["bench_tier"] = 3
	assert_true(UpgradesScreen.tab_visible("research"))


func test_tier_two_waits_for_the_tower_and_three_hexes_then_costs() -> void:
	assert_ne(BenchTiers.block_reason(), "", "not before the signal tower")
	GameState.flags["signal_tower"] = 1
	assert_ne(BenchTiers.block_reason(), "", "not before three clean hexes")
	GameState.stats["hexes_cleaned"] = 3.0
	assert_eq(BenchTiers.block_reason(), "")
	assert_false(BenchTiers.buy(), "can't pay yet")
	var cost: Dictionary = BenchTiers.next_cost()
	for k: String in cost:
		GameState.currencies[k] = BigNum.from_float(float(cost[k]))
	assert_true(BenchTiers.buy())
	assert_eq(BenchTiers.tier(), 2)
	assert_true(Research.has("salvage_logic"), "the Bot Bay brings the robot blueprint: a first robot can be built")
	assert_true(UpgradesScreen.tab_visible("bots"))


func test_old_saves_keep_the_tabs_they_used() -> void:
	GameState.flags = {"bench_tabs": ["patch", "bots", "research"]}
	assert_eq(BenchTiers.tier(), 3)
	GameState.flags = {}
	GameState.stats = {"robots_built": 2.0}
	assert_eq(BenchTiers.tier(), 2)


func test_upgrade_rows_keep_a_fixed_order_whatever_you_can_pay() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(5.0)
	var poor: Array[String] = _ids(BenchLists.upgrades(null))
	GameState.currencies["cubes"] = BigNum.from_float(5000.0)
	var rich: Array[String] = _ids(BenchLists.upgrades(null))
	assert_eq(poor, rich, "the same rows in the same order, rich or poor")
	var order: Array[String] = BenchLists.bench_order()
	var last: int = -1
	for id: String in poor:
		var i: int = order.find(id)
		if i < 0:
			continue
		assert_gt(i, last, "%s keeps its place" % id)
		last = i


func test_the_baler_is_listed_from_the_start() -> void:
	var ids: Array[String] = _ids(BenchLists.upgrades(null))
	assert_true("baler" in ids, "the Baler the objective asks to save for is on the bench")
	assert_lt(ids.find("compartment_size"), ids.find("baler"))
	assert_lt(ids.find("multi_lock"), ids.find("baler"))


func test_buying_keeps_the_row_in_place() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(5000.0)
	var before: Array[String] = _ids(BenchLists.upgrades(null))
	Economy.buy_upgrade("baler", 1)
	var after: Array[String] = _ids(BenchLists.upgrades(null))
	assert_eq(after.find("baler"), before.find("baler"), "a maxed upgrade stays where it was (DONE)")


func test_objective_upgrades_and_builds_are_ones_the_bench_has() -> void:
	var cfg: Dictionary = Economy.planet_table("tutorial")
	var ids: Array = (cfg["objectives"] as Array).map(func(d: Dictionary) -> String: return str(d["id"]))
	assert_lt(ids.find("bench2"), ids.find("robot"), "the Bot Bay comes before the first robot")
	assert_lt(ids.find("tower"), ids.find("bench2"))
	for d: Dictionary in cfg["objectives"]:
		if str(d.get("type", "")) == "upgrade":
			assert_true(Economy.upgrade_defs.has(str(d["key"])), "%s names a real upgrade" % d["id"])
			assert_eq(Economy.lock_reason(str(d["key"])), "", "%s is never locked" % d["id"])
	assert_eq(BenchLists.BUILD_CATS[0][0], "story", "the tower's category is the Build tab's first")


func test_bench_objective_reads_the_tier() -> void:
	var o := Objectives.new()
	assert_eq(o.value_of({"type": "bench", "target": 2}), 1.0)
	GameState.flags["bench_tier"] = 2
	assert_eq(o.value_of({"type": "bench", "target": 2}), 2.0)
	o.free()
