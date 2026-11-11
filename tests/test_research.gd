extends GutTest
## Research from field work (design spec section 6; systems/research.gd, systems/field_data.gd):
## nodes cost stock and field data, not time; work earns the data; one node is active and
## switching keeps progress; time away adds nothing; old clock-and-queue saves migrate.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const FIXTURE: String = "res://tests/fixtures/saves/research_clock_v4.json"
## Accepted cap on any city 1 price (docs/DECISIONS.md, M3-19 + M3-02).
const CITY1_PRICE_CAP: float = 4200.0
const CITY1_TIERS: int = 6

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _ups: Dictionary
var _gained: Array = []


class FakeGarden extends Node:
	var species: Array = []


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_ups = GameState.upgrades.duplicate()
	GameState.flags = {}
	GameState.currencies = {}
	GameState.upgrades = {}
	_gained.clear()
	EventBus.field_data_gained.connect(_on_gained)


func after_each() -> void:
	EventBus.field_data_gained.disconnect(_on_gained)
	Planets.set_current(FIRST)
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.upgrades = _ups


func _on_gained(amount: float, kind: String) -> void:
	_gained.append([amount, kind])


func _give_cubes(n: float) -> void:
	GameState.add_currency(Research.CURRENCY, BigNum.from_float(n))


func _cubes() -> float:
	return GameState.get_currency(Research.CURRENCY).to_float()


func test_tree_data_is_consistent() -> void:
	var ids: Array[String] = Research.ids()
	assert_between(ids.size(), 28, 40, "about 30 nodes plus the frontier tiers")  # [biomes] tiers 6-7
	assert_eq(Research.branches().size(), 5)
	for id: String in ids:
		var d: Dictionary = Research.def(id)
		assert_false(d.has("time_s"), "%s: research costs field data, not time" % id)
		assert_gt(Research.data_cost(id), 0.0, "%s costs field data" % id)
		assert_gt(Research.cost(id).to_float(), 0.0, "%s costs stock" % id)
		if int(d["tier"]) < CITY1_TIERS:
			assert_lt(Research.cost(id).to_float(), CITY1_PRICE_CAP, "%s: city 1 prices stay under the cap" % id)
		for r: String in Research.requires(id):
			assert_true(Research.exists(r), "%s requires known %s" % [id, r])
			assert_lt(int(Research.def(r)["tier"]), int(d["tier"]), "%s requires an earlier tier" % id)


func test_start_pays_stock_once_and_needs_prereqs() -> void:
	assert_false(Research.can_start("scoop_beam"), "no cubes yet")
	assert_eq(Research.reason("scoop_beam"), "Not enough cubes")
	_give_cubes(10000.0)
	assert_eq(Research.status("wide_beam"), "locked")
	assert_false(Research.start("wide_beam"), "prereq missing")
	assert_true(Research.start("scoop_beam"))
	assert_almost_eq(_cubes(), 10000.0 - Research.cost("scoop_beam").to_float(), 0.01)
	assert_eq(Research.status("scoop_beam"), "active")
	assert_eq(Research.status("wide_beam"), "locked", "no queue: a node waits for its prerequisites to be researched")


func test_research_needs_work_not_time() -> void:
	_give_cubes(10000.0)
	var n := Research.new()
	add_child_autofree(n)
	Research.start("scoop_beam")
	for i: int in 600:  # five minutes of play with no work done
		n._process(0.5)
	assert_false(Research.has("scoop_beam"), "time alone researches nothing")
	assert_eq(Research.progress("scoop_beam"), 0.0)
	var need: float = Research.data_cost("scoop_beam")
	Research.award_data(need * 0.5)
	assert_almost_eq(Research.progress("scoop_beam"), 0.5, 0.001, "the bar fills as the work comes in")
	Research.award_data(need)
	assert_true(Research.has("scoop_beam"))
	assert_eq(Research.active_id(), "")
	assert_almost_eq(FieldData.bank(), need * 0.5, 0.001, "what the node did not need is banked")


func test_work_earns_field_data_from_each_source() -> void:
	var n := Research.new()
	add_child_autofree(n)
	EventBus.hex_cleaned.emit(0, Vector3.ZERO, BigNum.zero())
	EventBus.hex_level_changed.emit(0, 1)
	EventBus.hex_level_changed.emit(0, 3)
	EventBus.mastery_gained.emit("litter", 1)
	EventBus.piece_found.emit("sprout_eyes", "buried")
	EventBus.source_step_done.emit("old_town", 0)
	EventBus.source_shut_down.emit("old_town")
	var kinds: Array[String] = []
	for g: Array in _gained:
		kinds.append(str(g[1]))
	assert_eq(kinds, ["hex_cleaned", "hex_stage", "mastery_level", "piece_found", "source_step", "source_shut"] as Array[String],
		"cleaned hexes, stage changes (not stage 1), mastery, finds and sources all pay")
	var want: float = FieldData.reward("hex_cleaned") + FieldData.stage_reward(3) + FieldData.reward("mastery_level") \
		+ FieldData.reward("piece_found") + FieldData.reward("source_step") + FieldData.reward("source_shut")
	assert_almost_eq(FieldData.bank(), want, 0.001, "with no node active it is all banked")


func test_stage_changes_pay_more_at_higher_stages() -> void:
	for st: int in range(3, 6):
		assert_gt(FieldData.stage_reward(st), FieldData.stage_reward(st - 1), "stage %d pays more than %d" % [st, st - 1])


func test_one_active_and_switching_keeps_progress() -> void:
	_give_cubes(10000.0)
	Research.start("scoop_beam")
	Research.award_data(Research.data_cost("scoop_beam") * 0.4)
	var paid: float = _cubes()
	assert_true(Research.start("soil_survey"), "switching to another node")
	assert_eq(Research.active_id(), "soil_survey", "only one node is active")
	assert_eq(Research.status("scoop_beam"), "paused")
	assert_almost_eq(Research.progress("scoop_beam"), 0.4, 0.001, "the switched-away node keeps its bar")
	var after_soil: float = _cubes()
	assert_almost_eq(after_soil, paid - Research.cost("soil_survey").to_float(), 0.01)
	assert_true(Research.start("scoop_beam"), "switching back")
	assert_almost_eq(_cubes(), after_soil, 0.01, "a paid node costs nothing to pick again")
	assert_almost_eq(Research.progress("scoop_beam"), 0.4, 0.001)


func test_starting_draws_on_the_bank() -> void:
	_give_cubes(10000.0)
	Research.award_data(Research.data_cost("scoop_beam") + 3.0)
	assert_true(Research.start("scoop_beam"))
	assert_true(Research.has("scoop_beam"), "banked data finishes a node at once")
	assert_almost_eq(FieldData.bank(), 3.0, 0.001)


func test_bonuses_raise_field_data() -> void:
	assert_almost_eq(Research.award_data(10.0), 10.0, 0.001)
	Research.grant("soil_survey")
	assert_almost_eq(Research.award_data(10.0), 11.5, 0.001, "Soil Survey: +15% field data")
	Research.grant("field_notebook")
	assert_almost_eq(Research.award_data(10.0), 10.0 * 1.15 * 1.1 * 1.1, 0.001, "Field Notebook: data and research speed")
	assert_almost_eq(_cubes(), 0.0, 0.001, "field data is not money")


func test_time_away_adds_no_research_on_any_planet() -> void:
	for pid: StringName in PLANETS:
		Planets.set_current(pid)
		Research.reload()
		GameState.flags = {}
		Research.award_data(5.0)
		var bank0: float = FieldData.bank()
		var earned0: float = float(GameState.stats.get("data_earned", 0.0))
		GameState.saved_unix = Time.get_unix_time_from_system() - 8.0 * 3600.0
		var n := Research.new()
		add_child_autofree(n)
		n._process(1.0)
		assert_almost_eq(FieldData.bank(), bank0, 0.001, "%s: eight hours away add no field data" % pid)
		assert_almost_eq(float(GameState.stats.get("data_earned", 0.0)), earned0, 0.001)
		n.free()
	Planets.set_current(FIRST)
	Research.reload()


func test_offline_cap_comes_from_planet_data() -> void:
	for pid: StringName in PLANETS:
		Planets.set_current(pid)
		var off: Dictionary = Planets.by_id(pid).table("balance").get("offline", {})
		assert_false(off.is_empty(), "%s states its offline numbers" % pid)
		assert_almost_eq(Offline.cap_s(), float(off["cap_h"]) * 3600.0, 0.01, "%s: the cap on time away is data" % pid)
		assert_almost_eq(Offline.rate(), float(off["rate"]), 0.001)


func test_old_clock_save_migrates_to_field_data() -> void:
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	old.erase("_doc")
	var keep: Dictionary = GameState.to_dict()
	GameState.from_dict(SaveManager.migrate(old))
	var r: Dictionary = GameState.flags["research"]
	var now: float = Time.get_unix_time_from_system()
	# The fixture's running node had 40% of its clock behind it.
	var act: Dictionary = r["active"]
	act["start"] = now - 0.4 * float(act["dur"])
	var s: Dictionary = Research.state()
	assert_false(s.has("queue"), "the queue is gone")
	assert_eq(Research.active_id(), "wide_beam", "the running node stays the active one")
	assert_almost_eq(Research.progress("wide_beam"), 0.4, 0.01, "it keeps its share of the clock as field data")
	assert_true(Research.is_paid("bigger_hopper"), "a queued node was paid for: it stays paid")
	assert_eq(Research.progress("bigger_hopper"), 0.0)
	assert_true(Research.has("scoop_beam"), "researched nodes stay researched")
	GameState.flags = {"research": {"done": [], "active": {"id": "soil_survey", "start": now - 500.0, "dur": 30.0}, "queue": []}}
	Research.state()
	assert_true(Research.has("soil_survey"), "a node whose time was up is researched, as the old rules did on load")
	assert_eq(Research.active_id(), "")
	GameState.from_dict(keep)


func test_effects_apply_through_economy_stat() -> void:
	var cap0: float = Economy.stat("capacity")
	var reach0: float = Economy.stat("scoop_reach")
	Research.grant("bigger_hopper")
	Research.grant("scoop_beam")
	assert_almost_eq(Economy.stat("capacity"), cap0 * 1.2, 0.001)
	assert_almost_eq(Economy.stat("scoop_reach"), reach0 + 0.5, 0.001)
	var rows: Array[Dictionary] = Economy.stat_breakdown("capacity")
	assert_true(str(rows[rows.size() - 1]["source"]).begins_with("Research"))
	var sp0: float = Economy.robot_stat("haulbug", "speed")
	Research.grant("haul_routes")
	assert_almost_eq(Economy.robot_stat("haulbug", "speed"), sp0 * 1.2, 0.001)
	assert_false(Research.effect_lines("bigger_hopper").is_empty())


func test_robot_types_gated() -> void:
	assert_false(Research.robot_unlocked("scoopie"), "[pace] helpers wait for the Bot Bay")
	assert_false(Research.robot_unlocked("haulbug"))
	Research.grant("salvage_logic")
	assert_false(Research.robot_unlocked("haulbug"), "Salvage Logic alone unlocks no robot: plans arrive by themselves")
	Research.unlock_story("haul_rig")
	assert_true(Research.robot_unlocked("haulbug"), "task M3-21: the hauler is the first helper")
	assert_false(Research.robot_unlocked("scoopie"), "the cleaner comes later")
	assert_false(Research.robot_unlocked("skimmer"), "[v4bots] and the water bot later still (item 44)")
	Research.unlock_story("scoopie_rig")
	assert_true(Research.robot_unlocked("scoopie"))
	assert_false(Research.robot_unlocked("seedling"))
	assert_false(Research.robot_unlocked("multibot"))
	Research.grant("seedling_blueprint")
	assert_true(Research.robot_unlocked("seedling"))


func test_plant_species_gated() -> void:
	var g := FakeGarden.new()
	add_child_autofree(g)
	g.species = (Economy.planet_table("plants")["species"] as Array).duplicate(true)
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


func test_state_survives_save_round_trip() -> void:
	_give_cubes(10000.0)
	Research.start("scoop_beam")
	Research.award_data(Research.data_cost("scoop_beam") * 0.5)
	Research.start("soil_survey")
	Research.grant("water_testing")
	Research.pause()
	Research.award_data(7.0)
	var backup: Dictionary = {"world": GameState.world, "districts": GameState.districts, "parts": GameState.parts, "planet": GameState.planet_state, "hub": GameState.current_hub}
	var d: Dictionary = GameState.to_dict()
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	GameState.world = backup["world"]
	GameState.districts = backup["districts"]
	GameState.parts = backup["parts"]
	GameState.planet_state = backup["planet"]
	GameState.current_hub = backup["hub"]
	assert_true(Research.has("water_testing"))
	assert_eq(Research.active_id(), "")
	assert_almost_eq(Research.progress("scoop_beam"), 0.5, 0.001)
	assert_true(Research.is_paid("soil_survey"))
	assert_almost_eq(FieldData.bank(), 7.0, 0.001)
