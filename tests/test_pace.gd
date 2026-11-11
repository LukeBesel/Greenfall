extends GutTest
## [pace] The slow start (core/pace.gd): Lift Strength size classes, the Baler unlock, emptying the
## chest loose before the Baler, the tamed early economy, flag-gated events and old-save grants.

var _ups: Dictionary
var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_ups = GameState.upgrades.duplicate()
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	GameState.upgrades = {}
	GameState.currencies = {"cubes": BigNum.zero(), "parts": BigNum.zero(), "seeds": BigNum.zero()}


func after_each() -> void:
	GameState.upgrades = _ups
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats


func test_size_classes_match_world2_thresholds() -> void:
	assert_eq(Pace.size_class(0.3), Pace.SIZE_SMALL)
	assert_eq(Pace.size_class(1.6), Pace.SIZE_MEDIUM)
	assert_eq(Pace.size_class(2.5), Pace.SIZE_LARGE)
	assert_eq(Pace.size_class(3.5), Pace.SIZE_LARGE)


func test_lift_strength_steps_small_medium_large() -> void:
	assert_eq(Pace.lift_class(), Pace.SIZE_SMALL, "a fresh Lumi lifts small junk only")
	GameState.upgrades[Pace.UP_LIFT] = 1
	assert_eq(Pace.lift_class(), Pace.SIZE_MEDIUM)
	GameState.upgrades[Pace.UP_LIFT] = 2
	assert_eq(Pace.lift_class(), Pace.SIZE_LARGE)
	assert_eq(Economy.upgrade_max(Pace.UP_LIFT), 2)


func test_baler_is_an_upgrade() -> void:
	assert_false(Pace.baler_unlocked(), "no bale press at the start")
	assert_true(Pace.dump_allowed(), "the chest can be emptied loose instead")
	GameState.add_currency("cubes", Economy.upgrade_cost(Pace.UP_BALER))
	assert_eq(Economy.buy_upgrade(Pace.UP_BALER), 1)
	assert_true(Pace.baler_unlocked())
	assert_true(bool(GameState.flags.get("has_baler", false)), "sync_flags mirrors it for events/requests")
	assert_false(Pace.dump_allowed(), "after the Baler, junk goes into bales")


func test_dump_pays_less_than_a_bale() -> void:
	var contents: Dictionary = {"metal": 5.0, "plastic": 5.0}
	var loose: float = Pace.dump_value(contents)
	var bale: float = Economy.evaluate_cube(contents, 10.0, 1.0)["value"].to_float()
	assert_gt(loose, 0.0)
	assert_lt(loose, bale, "baling is worth unlocking")


func test_start_is_small_and_slow() -> void:
	assert_lte(Economy.stat("capacity"), 12.0, "a few pieces per chest at first")
	var start_rate: float = Economy.stat("scoop_rate") * Pace.pulse_volume()
	assert_between(start_rate, 4.0, 5.5, "about 4 units a second at the start (the accepted proposal's hand rate)")
	assert_eq(int(Economy.stat("pickup_count")), 1)
	# A few upgrades: a chest of five loads and a scoop more than twice as fast.
	GameState.upgrades["compartment_size"] = 4
	GameState.upgrades["scoop_speed"] = 3
	GameState.upgrades[Pace.UP_SCOOP_SIZE] = 3
	assert_gte(Economy.stat("capacity"), 30.0)
	assert_gte(Economy.stat("scoop_rate") * Pace.pulse_volume(), start_rate * 2.0)


func test_only_one_upgrade_after_two_early_bales() -> void:
	# Two bales from a just-unlocked Baler (chest ~15, mixed, Perfect) buy about one upgrade.
	GameState.upgrades = {"compartment_size": 1, Pace.UP_BALER: 1, Pace.UP_LIFT: 1}
	var bale: float = Economy.evaluate_cube({"metal": 7.0, "plastic": 7.0}, 15.0, 1.0)["value"].to_float()
	var budget: float = bale * 2.0
	var costs: Array[float] = []
	for id: String in Economy.upgrade_order:
		if Economy.upgrade_defs[id].get("tab", "") == "patch" and Economy.is_unlocked(id) and not Economy.is_maxed(id):
			costs.append(Economy.upgrade_cost(id).to_float())
	costs.sort()
	var n: int = 0
	var spent: float = 0.0
	for c: float in costs:
		if spent + c > budget:
			break
		spent += c
		n += 1
	assert_lte(n, 1, "two bales (%.0f cubes) buy at most one upgrade, cheapest %s" % [budget, str(costs.slice(0, 3))])


func test_automation_waits_for_the_base() -> void:
	assert_gte(int(Research.def("conveyor").get("min_base_level", 0)), 2)
	assert_gte(int(Research.def("auto_baler").get("min_base_level", 0)), 2)
	assert_gte(int(Research.def("salvage_logic").get("min_base_level", 0)), 2, "robot assembly")
	for t: String in ["scoopie", "haulbug", "skimmer"]:
		assert_ne(Research.robot_requirement(t), "", "%s needs research" % t)
	assert_eq(str(Economy.upgrade_defs["auto_compactor"].get("requires_research", "")), "auto_baler")
	assert_false(Economy.is_unlocked("auto_compactor"))
	assert_false(Economy.is_unlocked("magnet_arm"))


func test_events_gated_on_unlocks() -> void:
	var ctx: Dictionary = {"junk_hexes": 5, "parts_left": 3, "flags": {}}
	var ok: Dictionary = WorldEvents.eligible_ids(ctx)
	assert_false(bool(ok.get("rare_part_signal", true)), "no violet beam without the Signal Finder")
	assert_false(bool(ok.get("salvage_surge", true)), "no bale bonus before the Baler")
	ctx["flags"] = {"has_signal_finder": true, "has_baler": true}
	ok = WorldEvents.eligible_ids(ctx)
	assert_true(bool(ok.get("rare_part_signal", false)))
	assert_true(bool(ok.get("salvage_surge", false)))


func test_old_saves_keep_their_tools() -> void:
	var d: Dictionary = {"version": 2, "upgrades": {"compartment_size": 2}, "flags": {}, "currencies": {}}
	d = SaveManager.migrate(d)
	assert_eq(int(d["version"]), GameState.SAVE_VERSION)
	assert_eq(int(d["upgrades"][Pace.UP_BALER]), 1)
	assert_eq(int(d["upgrades"][Pace.UP_LIFT]), 2)
	assert_eq(int(d["upgrades"]["compartment_size"]), 6, "the lower base chest is made up")
	GameState.upgrades = d["upgrades"]
	assert_gte(Economy.stat("capacity"), 30.0, "an old save's chest is no smaller than before")
	assert_gte(Economy.stat("scoop_rate"), 7.5, "and the scoop no slower than about before")
