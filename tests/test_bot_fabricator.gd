extends GutTest
## [orbC] The Bot Fabricator (robots/fabricator/bot_fabricator.gd) and the crew's near budget.

var _g5: SphereGrid
var _t5: SphereTerrain
var _flags: Dictionary
var _cur: Dictionary


func before_all() -> void:
	_g5 = SphereGrid.new()
	_g5.generate(5)
	_g5.radius_m = SphereGrid.radius_for(5, 10.0)
	_t5 = SphereTerrain.new(_g5, 7)


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_cur = {}
	for id: String in ["cubes", "parts"]:
		_cur[id] = GameState.get_currency(id).to_float()


func after_each() -> void:
	GameState.flags = _flags
	for id: String in _cur:
		GameState.currencies[id] = BigNum.from_float(float(_cur[id]))


func _crew() -> SphereCrew:
	var cells := SphereCells.new(_g5.cell_count())
	var surface := SphereSurface.new(_g5.radius_m)
	surface.height_fn = _t5.height
	surface.cell_fn = func(p: Vector3, _h: int) -> int: return _g5.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return _g5.centers[c]
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(_g5, cells, null, surface, SphereSwarm.new(surface))
	crew.hub_cell = 100
	crew.depot_cell = 100
	return crew


func _fab(crew: SphereCrew, sites: Array) -> BotFabricator:
	var f := BotFabricator.new()
	add_child_autofree(f)
	f.planet_id = "test_planet"
	f.set_process(false)
	BotFabricator.state("test_planet")["built"] = true
	f.cap = 6
	f.only_types = ["scoopie", "haulbug"]
	f.count_fn = func() -> int: return crew.robots().size()
	f.spawn_fn = func(t: String, tier: int) -> bool: return BotFabricator.spawn_on_globe(crew, sites, t, tier)
	return f


func _give(cubes: float, parts: float) -> void:
	GameState.currencies["cubes"] = BigNum.from_float(cubes)
	GameState.currencies["parts"] = BigNum.from_float(parts)


func test_mix_order_follows_the_weights() -> void:
	var mix: Dictionary = {"scoopie": 3, "haulbug": 1}
	var made: Dictionary = {}
	var allowed: Array[String] = ["scoopie", "haulbug", "seedling"]
	for i: int in 8:
		var t: String = BotFabricator.next_type(mix, made, allowed)
		made[t] = int(made.get(t, 0)) + 1
	assert_eq(int(made.get("scoopie", 0)), 6)
	assert_eq(int(made.get("haulbug", 0)), 2)
	assert_false(made.has("seedling"), "weight 0 is never built")
	assert_eq(BotFabricator.next_type({}, {}, allowed), "", "empty mix builds nothing")


func test_fleet_cap_scales_with_planet_size_into_the_hundreds() -> void:
	var caps: Dictionary = {}
	for id: String in ["verdance", "ochre", "tidewell", "rime", "anvil"]:
		caps[id] = BotFabricator.cap_for_cells(GlobeSpec.cells_for(int(GlobeSpec.of(id)["frequency"])))
	assert_lt(int(caps["ochre"]), int(caps["verdance"]))
	assert_lt(int(caps["verdance"]), int(caps["tidewell"]))
	assert_lt(int(caps["tidewell"]), int(caps["rime"]))
	assert_lt(int(caps["rime"]), int(caps["anvil"]))
	assert_gte(int(caps["tidewell"]), 100, "hundreds from the Fabricator's planet on")
	assert_gte(int(caps["anvil"]), 300)


func test_builds_robots_pays_and_stops_at_the_cap() -> void:
	var crew: SphereCrew = _crew()
	var sites: Array = [{"cell": 100}, {"cell": 3000}]
	var f: BotFabricator = _fab(crew, sites)
	_give(1e7, 1e6)
	var c0: float = GameState.get_currency("cubes").to_float()
	var bs: float = float(BotFabricator.cfg()["build_s"])
	for i: int in 10:
		f.tick(bs * 0.5)
		f.tick(bs * 0.5 + 0.01)
	assert_eq(crew.robots().size(), 6, "stops at the fleet cap")
	assert_eq(f.status, "Fleet full.")
	var per: float = float(BotFabricator.robot_cost("scoopie")["cubes"])
	assert_lt(GameState.get_currency("cubes").to_float(), c0 - per * 3.0, "paid cubes for its robots")
	var hubs: Dictionary = {}
	for u: Dictionary in crew.robots():
		hubs[int(u["hub"])] = int(hubs.get(int(u["hub"]), 0)) + 1
	assert_eq(int(hubs.get(100, 0)), 3, "new robots spread over the hubs")
	assert_eq(int(hubs.get(3000, 0)), 3)
	assert_eq(int((BotFabricator.state("test_planet")["made"] as Dictionary).get("scoopie", 0)), 5, "3:1 mix after 6 robots: 5 + 1 (ties go to the bigger share)")


func test_waits_for_money_and_pauses() -> void:
	var crew: SphereCrew = _crew()
	var f: BotFabricator = _fab(crew, [{"cell": 100}])
	_give(0.0, 0.0)
	f.tick(100.0)
	assert_eq(crew.robots().size(), 0)
	assert_eq(f.status, "Waiting for cubes and parts.")
	_give(1e7, 1e6)
	f.set_paused(true)
	f.tick(100.0)
	assert_eq(crew.robots().size(), 0)
	assert_eq(f.status, "Paused.")
	f.set_paused(false)
	f.tick(1.0)
	f.tick(100.0)
	assert_eq(crew.robots().size(), 1)


func test_weights_clamp_and_persist_in_flags() -> void:
	var crew: SphereCrew = _crew()
	var f: BotFabricator = _fab(crew, [{"cell": 100}])
	f.set_weight("drip", 99)
	assert_eq(f.weight("drip"), int(BotFabricator.cfg()["max_weight"]))
	f.set_weight("drip", -3)
	assert_eq(f.weight("drip"), 0)
	var st: Variant = JSON.parse_string(JSON.stringify(GameState.flags["fabricator"]["test_planet"]))
	assert_true(st is Dictionary and (st as Dictionary).has("mix"), "plain JSON state (saved with the flags)")


func test_unlock_from_the_third_planet() -> void:
	GameState.flags.erase("fabricator_unlocked")
	assert_eq(Homeward.planet_index(str(BotFabricator.cfg()["unlock_planet"])), 2, "Tidewell is the 3rd planet")
	var w := Node.new()
	add_child_autofree(w)
	if not DevHooks.has("fabricator"):
		assert_false(BotFabricator.unlocked(w), "not on Verdance")
		assert_false(HubBuilds.listed(w, "bot_fabricator"), "no spoilers in the Build tab")
	GameState.flags["fabricator_unlocked"] = true
	assert_true(BotFabricator.unlocked(w))
	var e: Dictionary = HubBuilds.entry(w, "bot_fabricator")
	assert_eq(str(e["name"]), "Bot Fabricator")
	assert_gt(float((e["cost"] as Dictionary).get("parts", 0)), 0.0)


func test_near_budget_keeps_hundreds_cheap() -> void:
	var crew: SphereCrew = _crew()
	var lumi := Node3D.new()
	add_child_autofree(lumi)
	lumi.global_position = crew.surface.ground(_g5.centers[100])
	crew.focus = lumi
	crew.max_near = 20
	var ring: PackedInt32Array = _g5.cells_around(100, 3)
	for i: int in 120:
		crew.spawn("scoopie", 0, ring[i % ring.size()])
	crew.tick(0.3)
	assert_eq(crew.robots().size(), 120)
	assert_lte(crew.near_count(), 20, "only the budget is real")
	var real: int = 0
	for u: Dictionary in crew.robots():
		real += 1 if u["bot"] != null else 0
	assert_eq(real, crew.near_count())


func test_panel_is_one_simple_card() -> void:
	var crew: SphereCrew = _crew()
	var f: BotFabricator = _fab(crew, [{"cell": 100}])
	var p := FabricatorPanel.new()
	p.fab = f
	add_child_autofree(p)
	await get_tree().process_frame
	var buttons: Array[Node] = p.find_children("*", "Button", true, false)
	# - and + per type, and Pause.
	assert_eq(buttons.size(), BotFabricator.types().size() * 2 + 1)
	assert_string_contains(p._status.text, "Fleet 0 / 6")
	var plus: Button = buttons[1] as Button if buttons.size() > 2 else null
	if plus:
		var t: String = BotFabricator.types()[0]
		var w0: int = f.weight(t)
		plus.pressed.emit()
		assert_eq(f.weight(t), mini(w0 + 1, int(BotFabricator.cfg()["max_weight"])))
	(buttons[buttons.size() - 1] as Button).pressed.emit()
	assert_true(f.paused(), "the last button pauses")


func test_queue_comes_before_the_mix_and_api() -> void:
	var crew: SphereCrew = _crew()
	var f: BotFabricator = _fab(crew, [{"cell": 100}])
	_give(1e7, 1e6)
	f.set_mix({"scoopie": 1})
	f.enqueue("haulbug")
	f.enqueue("haulbug")
	assert_eq(f.upcoming(4), ["haulbug", "haulbug", "scoopie", "scoopie"] as Array[String])
	var bs: float = float(BotFabricator.cfg()["build_s"])
	for i: int in 3:
		f.tick(0.01)
		f.tick(bs)
	assert_eq(f.built_count(), 3)
	assert_eq(int((BotFabricator.state("test_planet")["made"] as Dictionary).get("haulbug", 0)), 2)
	assert_true(f.queue().is_empty())
	assert_eq(f.cap_now(), 6)
	assert_eq(f.mix(), {"scoopie": 1})


func test_fabricator_bots_wear_their_types_design() -> void:
	# Locker designs reach every robot of a type through SphereCrew.dress_hooks (no Fabricator option).
	var crew: SphereCrew = _crew()
	var lumi := Node3D.new()
	add_child_autofree(lumi)
	lumi.global_position = crew.surface.ground(_g5.centers[100])
	crew.focus = lumi
	var seen: Array = []
	var hook: Callable = func(_b: Node3D, _v: Node3D, t: String, _tier: int) -> void: seen.append(t)
	SphereCrew.dress_hooks.append(hook)
	var f: BotFabricator = _fab(crew, [{"cell": 100}])
	_give(1e7, 1e6)
	f.tick(0.01)
	f.tick(float(BotFabricator.cfg()["build_s"]))
	SphereCrew.dress_hooks.erase(hook)
	assert_eq(crew.robots().size(), 1)
	assert_eq(seen, ["scoopie"], "the new near robot was dressed as its type")
