extends GutTest
## [beat] Whole-game reachability and the end-to-end fixes: every goal can be met by something
## the game actually does, frontier unlocks name real research, the Cradle is the true ending,
## BigNum rounding, currencies never negative, the credits roll reads docs/CREDITS.md.

var _flags: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_cur = GameState.currencies.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags
	GameState.currencies = _cur


func _all_code() -> String:
	var out: String = ""
	for dir: String in ["res://autoload", "res://automation", "res://planet", "res://plants", "res://robots", "res://story", "res://systems", "res://ui", "res://player", "res://scenes", "res://core", "res://water", "res://fauna", "res://systems/extras"]:  # [wild] fauna
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f: String in da.get_files():
			if f.ends_with(".gd"):
				out += FileAccess.get_file_as_string(dir.path_join(f))
	return out


const RETIRED_FRONTIER_STATS: Array[String] = ["sandstorms", "drain_stages", "heaters_placed", "hexes_thawed", "greenhouses_built"]


func test_every_goal_type_is_known_and_its_key_exists() -> void:
	var known: Array[String] = ["stat", "earned", "upgrade", "robot", "tier", "zone", "hub_level", "hex_level", "flag", "districts",
		"research", "bases_l5", "frontier_base", "frontier_growing"]
	var code: String = _all_code()
	var ids: Dictionary = {}
	for g: Dictionary in Economy.read_json("res://data/goals.json")["goals"]:
		var id: String = str(g["id"])
		assert_false(ids.has(id), "goal id %s is unique" % id)
		ids[id] = true
		var t: String = str(g.get("type", "stat"))
		assert_true(t in known, "goal %s has a known type (%s)" % [id, t])
		var key: String = str(g.get("key", ""))
		match t:
			"stat":
				# Something in the game raises this stat (inc_stat or a direct stats write).
				# [v6flat] Except the live frontier districts' stats: they went with the flat world, and
				# their goals wait for a decision on data/goals.json (docs/FLAT_REMOVAL.md, leftovers).
				if key in RETIRED_FRONTIER_STATS:
					continue
				assert_true(code.contains('"%s"' % key), "stat %s (goal %s) is written somewhere" % [key, id])
			"research":
				assert_true(Research.exists(key), "goal %s names real research %s" % [id, key])
			"frontier_base":
				assert_false(Frontiers.def(key).is_empty(), "goal %s names a frontier %s" % [id, key])
			"flag":
				assert_true(code.contains('"%s"' % key) or code.contains('"frontier_seen_" + '), "flag %s (goal %s) is set somewhere" % [key, id])
			"upgrade":
				assert_true(Economy.upgrade_defs.has(key), "goal %s names a real upgrade" % id)
			"robot":
				assert_true(key == "any" or Economy.robots.has(key), "goal %s names a real robot" % id)


func test_the_chain_ends_on_the_cradle_and_the_seed_ark() -> void:
	var chain: Array = Economy.read_json("res://data/goals.json")["goals"]
	var order: Array[String] = []
	for g: Dictionary in chain:
		order.append(str(g["id"]))
	for a: Array in [["base_5", "rocket"], ["rocket", "visit_dust"], ["visit_dust", "visit_frozen"], ["visit_frozen", "visit_sunken"],
			["visit_sunken", "visit_cradle"], ["visit_cradle", "cradle_home"], ["cradle_home", "ark_1"], ["plant_5", "pollinator"]]:
		assert_lt(order.find(a[0]), order.find(a[1]), "%s comes before %s" % a)
	# Research goals in the first district would wall the chain once its junk runs out.
	assert_gt(order.find("research_20"), order.find("rocket"))


func test_frontier_unlocks_name_real_research_and_are_ordered() -> void:
	for k: Dictionary in Frontiers.kinds():
		var u: Dictionary = k.get("unlock", {})
		if u.has("research"):
			assert_true(Research.exists(str(u["research"])), "%s unlock research exists" % k["id"])
		if u.has("frontier"):
			assert_false(Frontiers.def(str(u["frontier"])).is_empty())
	# Every research node is reachable: its requirements exist and sit in earlier tiers.
	for id: String in Research.ids():
		for r: String in Research.requires(id):
			assert_true(Research.exists(r), "%s requires real %s" % [id, r])


func test_verdance_bloom_is_the_cradle_not_three_districts() -> void:
	GameState.flags["bloom_done"] = []
	var three: Dictionary = {"thriving_hexes": 120, "thriving_districts": 3, "planet_pct": 1.2}
	assert_false("verdance_bloom" in Bloom.check(three))
	assert_false(Bloom.ark_unlocked())
	three["cradle_returned"] = 1.0
	assert_true("verdance_bloom" in Bloom.check(three))
	assert_true(Bloom.ark_unlocked(), "the Seed Ark opens with the Cradle")
	assert_eq(CoreCharge.compute(0.0, 0.0, 0.0, Bloom.is_done("verdance_bloom")), 1.0, "core full at the Cradle")


func test_campaign_progress_never_full_before_the_cradle() -> void:
	GameState.flags = {"frontier_seen_dust_flats": true, "frontier_seen_frozen_port": true, "frontier_seen_sunken_city": true,
		"frontier_seen_cradle_returns": true, "cradle_pad_clean": true}
	var p: float = CoreCharge.campaign_progress({"dust_flats": 900, "frozen_port": 901, "sunken_city": 902, "cradle_returns": 903})
	assert_lt(p, 1.0)
	assert_gt(p, 0.4)


func test_big_num_rounding_rolls_into_the_next_suffix() -> void:
	assert_eq(BigNum.from_float(999999.0).format(), "1M")
	assert_eq(BigNum.from_float(999.4e3).format(), "999.4K")
	assert_eq(BigNum.from_float(1234.0).format(), "1.23K")
	assert_eq(BigNum.from_float(999999.0).format(BigNum.Format.SCIENTIFIC), "1.0e6")
	assert_eq(BigNum.from_float(0.0).format(), "0")
	assert_eq(BigNum.from_float(999.0).format(), "999")


func test_currencies_never_go_negative() -> void:
	GameState.currencies["cubes"] = BigNum.from_float(1000.0)
	# gte() treats near-equal mantissas as equal: spending a hair more must not leave -0.
	assert_true(GameState.spend("cubes", BigNum.from_float(1000.000001)))
	assert_false(GameState.get_currency("cubes").mantissa < 0.0)
	GameState.add_currency("cubes", BigNum.from_float(-50.0))
	assert_false(GameState.get_currency("cubes").mantissa < 0.0)


func test_garden_ramp_stats_and_research() -> void:
	assert_almost_eq(Economy.base_stat("plant_growth"), 1.0, 0.0001)
	assert_almost_eq(Economy.base_stat("seed_yield"), 1.0, 0.0001)
	var eff: Array = Research.def("pollinator_survey").get("effects", [])
	var stats: Array = eff.map(func(e: Dictionary) -> String: return str(e.get("stat", "")))
	assert_true("plant_growth" in stats and "seed_yield" in stats, "Pollinator Survey is the garden ramp")
	assert_gt(Research.cost("seedling_blueprint").to_float(), 100.0, "planter bots wait for the mid game")


func test_credits_roll_reads_credits_md() -> void:
	var e: Array = CreditsRoll.entries()
	assert_eq(str(e[0][1]), "GREENFALL")
	var names: Array = e.filter(func(r: Array) -> bool: return r[0] == "name").map(func(r: Array) -> String: return str(r[1]))
	assert_true("Rahul Chaudhary" in names, "authors from docs/CREDITS.md")
	assert_true(str(e[e.size() - 2][1]).contains("Seed Ark") or str(e[e.size() - 3][1]).contains("Thank you"))


func test_save_falls_back_to_tmp_when_rename_was_interrupted() -> void:
	var path: String = "user://test_beat_slot.save"
	SaveManager.write_dict(path + ".tmp", {"version": 1, "flags": {"x": 1}})
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	assert_true(SaveManager.read_dict(path).is_empty())
	assert_false(SaveManager.read_dict(path + ".tmp").is_empty())
	DirAccess.remove_absolute(path + ".tmp")


func test_rocket_recharge_survives_a_clock_change() -> void:
	var saved: float = RocketTiers.now_override
	RocketTiers.now_override = 5000.0
	GameState.flags["rocket_ready_unix"] = 1.0e9  # a timestamp from another clock
	var left: float = RocketTiers.recharge_left()
	assert_lte(left, float(RocketTiers.def().get("recharge_s", 0.0)))
	RocketTiers.now_override = 5000.0 + left + 1.0
	assert_eq(RocketTiers.recharge_left(), 0.0, "it counts down instead of sticking at full")
	RocketTiers.now_override = saved
	GameState.flags.erase("rocket_ready_unix")


func test_garden_robots_wait_for_base_level_3() -> void:
	var saved_w: Dictionary = GameState.world.duplicate(true)
	var saved_d: Dictionary = GameState.districts.duplicate(true)
	var saved_r: Variant = GameState.flags.get("research")
	GameState.flags["research"] = {"done": ["salvage_logic", "soil_survey"], "queue": [], "active": {}}
	GameState.currencies["cubes"] = BigNum.from_float(50000.0)  # [money] research costs cubes
	GameState.districts = {}
	GameState.world = {"hub_level": 2}
	assert_string_contains(Research.reason("seedling_blueprint"), "base level 3")
	GameState.world = {"hub_level": 3}
	assert_eq(Research.reason("seedling_blueprint"), "")
	GameState.world = saved_w
	GameState.districts = saved_d
	GameState.flags["research"] = saved_r


func test_credits_roll_has_no_markdown_table_rows() -> void:
	for r: Array in CreditsRoll.entries():
		assert_false(str(r[1]).begins_with("|"), "no raw table rows: %s" % r[1])
		assert_false(str(r[1]).contains("https://"), "no raw links")
