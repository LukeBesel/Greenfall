extends GutTest

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _ups: Dictionary


class FakeGarden extends Node:
	var species: Array = []


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_ups = GameState.upgrades.duplicate()
	GameState.flags = {}
	GameState.currencies = {}
	GameState.upgrades = {}
	Research.now_override = 1000.0


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.upgrades = _ups
	Research.now_override = -1.0


## [money] Research costs cubes now (10 per old Data unit, Research.note_cubes()); the tests keep
## counting in the old units so the tree's numbers read the same.
func _give(n: float) -> void:
	GameState.add_currency(Research.CURRENCY, BigNum.from_float(n * Research.note_cubes()))


func _data() -> float:
	return GameState.get_currency(Research.CURRENCY).to_float() / Research.note_cubes()


func test_tree_data_is_consistent() -> void:
	var ids: Array[String] = Research.ids()
	assert_between(ids.size(), 28, 40, "about 30 nodes plus the frontier tiers")  # [biomes] tiers 6-7
	assert_eq(Research.branches().size(), 5)
	for id: String in ["conveyor", "auto_baler", "recycler", "rocket_cargo"]:
		assert_true(Research.exists(id), "logistics node %s" % id)
	for id: String in ids:
		var d: Dictionary = Research.def(id)
		# [biomes] frontier tiers (6-7) are the late-game long tail: up to 15 min.
		var max_s: float = 300.0 if int(d["tier"]) < 6 else 900.0
		assert_between(float(d["time_s"]), 30.0, max_s, "%s takes 30 s - %d min" % [id, int(max_s / 60.0)])
		for r: String in Research.requires(id):
			assert_true(Research.exists(r), "%s requires known %s" % [id, r])
			assert_lt(int(Research.def(r)["tier"]), int(d["tier"]), "%s requires an earlier tier" % id)


func test_start_needs_data_and_prereqs() -> void:
	assert_false(Research.can_start("scoop_beam"), "no cubes yet")
	assert_eq(Research.reason("scoop_beam"), "Not enough cubes")
	_give(1000)
	assert_eq(Research.status("wide_beam"), "locked")
	assert_false(Research.start("bigger_hopper"), "prereq missing")
	assert_true(Research.start("scoop_beam"))
	assert_almost_eq(_data(), 1000.0 - 25.0, 0.01)
	assert_eq(Research.status("scoop_beam"), "active")
	# A node whose prereq is running can be queued behind it.
	assert_eq(Research.status("wide_beam"), "available")
	assert_true(Research.start("wide_beam"))
	assert_eq(Research.status("wide_beam"), "queued")


func test_research_takes_real_time() -> void:
	_give(100)
	Research.start("scoop_beam", 1000.0)
	assert_almost_eq(Research.progress("scoop_beam", 1015.0), 0.5, 0.001)
	assert_almost_eq(Research.remaining(1015.0), 15.0, 0.001)
	assert_true(Research.update(1029.0).is_empty())
	assert_false(Research.has("scoop_beam"))
	var done: Array[String] = Research.update(1031.0)
	assert_eq(done, ["scoop_beam"] as Array[String])
	assert_true(Research.has("scoop_beam"))
	assert_eq(Research.status("scoop_beam"), "researched")
	assert_eq(Research.active_id(), "")


func test_queue_chains_through_offline_time() -> void:
	_give(1000)
	Research.start("scoop_beam", 1000.0)
	Research.start("wide_beam", 1000.0)
	Research.start("soil_survey", 1000.0)
	# Hours later (offline): all three finish in order, back to back.
	var done: Array[String] = Research.update(1000.0 + 3600.0)
	assert_eq(done, ["scoop_beam", "wide_beam", "soil_survey"] as Array[String])
	assert_true(Research.queue().is_empty())
	# Partial: the second one starts exactly when the first ended.
	GameState.flags = {}
	_give(1000)
	Research.start("scoop_beam", 0.0)
	Research.start("wide_beam", 0.0)
	Research.update(40.0)
	assert_eq(Research.active_id(), "wide_beam")
	assert_almost_eq(float(Research.active()["start"]), 30.0, 0.001)
	assert_almost_eq(Research.progress("wide_beam", 60.0), 0.5, 0.001)


func test_queue_limit() -> void:
	_give(10000)
	for id: String in ["scoop_beam", "field_notebook", "soil_survey", "water_testing"]:  # [pace] salvage_logic waits for base 2
		assert_true(Research.start(id), id)
	assert_eq(Research.queue().size(), Research.max_queue())
	assert_false(Research.start("hardy_weeds"))
	assert_eq(Research.reason("hardy_weeds"), "Queue is full")


func test_cancel_refunds_and_cascades() -> void:
	_give(1000)
	Research.start("scoop_beam")
	Research.start("wide_beam")
	Research.start("soil_survey")
	assert_almost_eq(_data(), 1000.0 - 25 - 60 - 25, 0.01)
	assert_true(Research.cancel("scoop_beam"))
	# wide_beam depended on it: dropped and refunded; soil_survey moves up and starts.
	assert_almost_eq(_data(), 1000.0 - 25, 0.01)
	assert_eq(Research.active_id(), "soil_survey")
	assert_true(Research.queue().is_empty())
	assert_false(Research.cancel("scoop_beam"), "nothing to cancel")


func test_effects_apply_through_economy_stat() -> void:
	var cap0: float = Economy.stat("capacity")
	var reach0: float = Economy.stat("scoop_reach")
	Research.grant("bigger_hopper")
	Research.grant("scoop_beam")
	assert_almost_eq(Economy.stat("capacity"), cap0 * 1.2, 0.001)
	assert_almost_eq(Economy.stat("scoop_reach"), reach0 + 0.5, 0.001)
	var rows: Array[Dictionary] = Economy.stat_breakdown("capacity")
	assert_true(str(rows[rows.size() - 1]["source"]).begins_with("Research"))
	# Robot stats too.
	var sp0: float = Economy.robot_stat("haulbug", "speed")
	Research.grant("haul_routes")
	assert_almost_eq(Economy.robot_stat("haulbug", "speed"), sp0 * 1.2, 0.001)
	assert_false(Research.effect_lines("bigger_hopper").is_empty())


func test_research_speed_shortens_time() -> void:
	var d0: float = Research.duration("wide_beam")
	Research.grant("field_notebook")
	assert_almost_eq(Research.duration("wide_beam"), d0 / 1.1, 0.01)


func test_robot_types_gated() -> void:
	assert_false(Research.robot_unlocked("scoopie"), "[pace] helpers wait for Salvage Logic (base 2)")
	assert_false(Research.robot_unlocked("haulbug"))
	Research.grant("salvage_logic")
	assert_true(Research.robot_unlocked("scoopie"))
	assert_false(Research.robot_unlocked("haulbug"), "[v4bots] the Scoopie comes alone (owner item 46)")
	assert_false(Research.robot_unlocked("skimmer"), "[v4bots] and the water bot later still (item 44)")
	Research.unlock_story("haul_rig")
	assert_true(Research.robot_unlocked("haulbug"))
	assert_false(Research.robot_unlocked("seedling"))
	assert_false(Research.robot_unlocked("multibot"))
	Research.grant("seedling_blueprint")
	assert_true(Research.robot_unlocked("seedling"))


func test_plant_species_gated() -> void:
	var g := FakeGarden.new()
	add_child_autofree(g)
	g.species = (Economy.read_json("res://data/plants.json")["species"] as Array).duplicate(true)
	Research.apply_garden(g)
	var by_id: Dictionary = {}
	for sp: Dictionary in g.species:
		by_id[sp["id"]] = sp
	assert_gt(float(by_id["grass"]["weight"]), 0.0)
	assert_eq(float(by_id["nettle"]["weight"]), 0.0, "locked species never picked")
	assert_eq(float(by_id["pine"]["weight"]), 0.0)
	Research.grant("hardy_weeds")
	Research.apply_garden(g)
	assert_gt(float(by_id["nettle"]["weight"]), 0.0)
	assert_eq(float(by_id["pine"]["weight"]), 0.0)


func test_data_award_and_bonus() -> void:
	GameState.flags["hint_data"] = true
	assert_almost_eq(Research.award_data(10.0), 10.0, 0.001)
	Research.grant("soil_survey")
	assert_almost_eq(Research.award_data(10.0), 11.5, 0.001)
	assert_almost_eq(_data(), 21.5, 0.001)
	assert_almost_eq(float(GameState.stats["data_earned"]), float(_stats.get("data_earned", 0.0)) + 21.5, 0.001)


func test_live_node_awards_data_from_events() -> void:
	GameState.flags["hint_data"] = true
	var n := Research.new()
	add_child_autofree(n)
	EventBus.hex_cleaned.emit(0, Vector3.ZERO, BigNum.zero())
	EventBus.hex_restored.emit(0)
	assert_almost_eq(_data(), Research.reward("hex_cleaned") + Research.reward("hex_restored"), 0.001)
	GameState.inc_stat("shards_found")
	n._process(1.0)
	assert_almost_eq(_data(), Research.reward("hex_cleaned") + Research.reward("hex_restored") + Research.reward("shard_read"), 0.001)


func test_state_survives_save_round_trip() -> void:
	_give(1000)
	Research.start("scoop_beam", 1000.0)
	Research.start("wide_beam", 1000.0)
	Research.grant("water_testing")
	var backup: Dictionary = {"world": GameState.world, "districts": GameState.districts, "parts": GameState.parts, "planet": GameState.planet_state, "hub": GameState.current_hub}
	var d: Dictionary = GameState.to_dict()
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	GameState.world = backup["world"]
	GameState.districts = backup["districts"]
	GameState.parts = backup["parts"]
	GameState.planet_state = backup["planet"]
	GameState.current_hub = backup["hub"]
	assert_true(Research.has("water_testing"))
	assert_eq(Research.active_id(), "scoop_beam")
	assert_eq(Research.queue(), ["wide_beam"])
	Research.update(1000.0 + 500.0)
	assert_true(Research.has("wide_beam"))
