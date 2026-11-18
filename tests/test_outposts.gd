extends GutTest
## Outposts (automation/outposts.gd + outpost.gd): seeded placement on the frontier, the clean
## gate and costs for repair, upgrades, nearest-scale delivery, the recharge pad, refill points
## and persistence in GameState.world.

class FakeWorld:
	extends Node3D
	var field: HexField
	var depot: Depot
	var patch: Node3D
	var outposts: Outposts
	var interactables: Interactables

var _cur: Dictionary
var _world_state: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world
	_stats = GameState.stats.duplicate(true)
	GameState.currencies = {}
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world_state
	GameState.stats = _stats


static func _types() -> Array:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	return types


static func _field(seed_v: int, wild: bool) -> HexField:
	var f := HexField.new(3, 10.0, seed_v, CityLayout.new(seed_v, 150.0, wild))
	f.generate(_types(), Vector2i(12, 18))
	return f


func _world(seed_v: int = 4471) -> FakeWorld:
	var w := FakeWorld.new()
	w.field = _field(seed_v, false)
	add_child_autofree(w)
	w.depot = Depot.new()
	w.depot.position = Vector3(0, 0, -1.8)
	w.add_child(w.depot)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	w.interactables = Interactables.new()
	w.add_child(w.interactables)
	w.outposts = Outposts.new()
	w.outposts.world = w
	w.add_child(w.outposts)
	w.outposts.setup()
	return w


func _rich() -> void:
	for k: String in Currencies.IDS:  # [money]
		GameState.add_currency(k, BigNum.from_float(1.0e6))


func _clean_hex(w: FakeWorld, i: int) -> void:
	for pid: int in w.field.hex_pieces[int(w.outposts.spots[i]["hex"])]:
		w.field.remove_piece(pid)


func test_plan_is_deterministic_and_on_the_frontier() -> void:
	for seed_v: int in [4471, 5480, 7498, 9000]:
		for wild: bool in [false, true]:
			var f: HexField = _field(seed_v, wild)
			var a: Array[Dictionary] = Outposts.plan(f)
			var b: Array[Dictionary] = Outposts.plan(f)
			assert_eq(str(a), str(b), "same field, same spots")
			assert_between(a.size(), 3, 4, "3-4 outposts per district (seed %d wild %s)" % [seed_v, wild])
			for s: Dictionary in a:
				var h: int = int(s["hex"])
				var p: Vector3 = s["pos"]
				assert_eq(f.hex_at(p), h, "spot lies in its hex")
				assert_eq(f.hex_hub[h], 0, "a junk hex, not the yard or a building block")
				assert_false(f.is_water(h), "not on a lake")
				assert_gte(Hex.distance(f.hex_axial[h], Vector2i.ZERO), f.radius - 1, "on the outer rings")
				var surf: int = f.layout.surface_at(p.x, p.z)
				assert_false(surf in [CityLayout.Surface.BUILDING, CityLayout.Surface.YARD, CityLayout.Surface.ROAD], "open ground, not blocking a road")
				for o: Dictionary in a:
					if o != s:
						assert_gt((o["pos"] as Vector3).distance_to(p), 10.0, "spread apart")


func test_repair_needs_a_clean_hex_and_materials() -> void:
	var w: FakeWorld = _world()
	var op: Outposts = w.outposts
	assert_eq(op.items.size(), op.spots.size())
	assert_eq(op.level_of(0), 0)
	assert_null(op.items[0].scale_depot, "a ruin has no scale")
	assert_string_starts_with(op.repair_block(0), "Clear the junk")
	assert_string_contains(op.prompt(0), "clear its hex")
	_clean_hex(w, 0)
	assert_eq(op.repair_block(0), "Not enough cubes or parts.")
	assert_false(op.repair(0, false))
	_rich()
	var cubes0: float = GameState.get_currency("cubes").to_float()
	assert_string_contains(op.prompt(0), "Repair outpost")
	assert_true(op.repair(0, false))
	assert_eq(op.level_of(0), 1)
	assert_eq(int(GameState.world["outposts"]["levels"][0]), 1, "saved per district")
	assert_not_null(op.items[0].scale_depot, "a working scale")
	assert_true(op.items[0].working())
	assert_almost_eq(cubes0 - GameState.get_currency("cubes").to_float(), float(op.cfg["repair_cost"]["cubes"]), 0.5)
	assert_eq(int(GameState.stats.get("outposts_repaired", 0)), 1)
	assert_false(op.repair(0, false), "only once")
	# The second repair in a district costs more.
	assert_gt(float(op.repair_cost(1)["cubes"]), float(op.cfg["repair_cost"]["cubes"]))


func test_upgrades_bigger_skip_then_recharge_pad() -> void:
	var w: FakeWorld = _world()
	var op: Outposts = w.outposts
	_rich()
	assert_eq(op.upgrade_block(0), "Repair it first.")
	op.repair(0, false, true)
	var d: Depot = op.items[0].scale_depot
	var r1: float = d.pad_radius
	assert_eq(d.value_bonus, 0.0)
	assert_true(op.upgrade(0, false))
	assert_eq(op.level_of(0), 2)
	assert_gt(d.pad_radius, r1, "Big Skip: wider plate")
	assert_gt(d.value_bonus, 0.0, "Big Skip: better price")
	assert_almost_eq(d.sell_factor(), (1.0 + d.value_bonus) * Hub.trade_mult(), 0.001)  # [v6pace] far_hub.pace
	assert_true(op.upgrade(0, false))
	assert_eq(op.level_of(0), 3)
	assert_eq(op.upgrade_block(0), "Fully upgraded.")
	assert_false(op.upgrade(0, false))
	assert_eq(int(GameState.stats.get("outpost_pads", 0)), 1)


func test_haulers_deliver_to_the_nearest_working_scale() -> void:
	var w: FakeWorld = _world()
	var op: Outposts = w.outposts
	var far: Vector3 = op.items[0].global_position + Vector3(0.5, 0, 0.5)
	assert_eq(Outposts.nearest_depot(w, far), w.depot, "ruins don't take bales")
	assert_eq(Outposts.idle_spot(w, far, 0), Vector3.INF, "no outpost to park at")
	op.repair(0, false, true)
	assert_eq(Outposts.nearest_depot(w, far), op.items[0].scale_depot, "outpost is closer")
	assert_eq(Outposts.nearest_depot(w, Vector3(0, 0, 1)), w.depot, "the base is closer")
	assert_true(Outposts.on_pad(w, op.items[0].pad_world()))
	assert_false(Outposts.on_pad(w, Vector3.ZERO))
	assert_ne(Outposts.idle_spot(w, far, 0), Vector3.INF, "idle robots park at the outpost")
	var pts: Array[Dictionary] = op.refill_points()
	assert_eq(pts.size(), 1, "the drum is a Drip refill point")
	assert_eq(pts[0]["kind"], "outpost")


func test_recharge_pad_speeds_up_robots() -> void:
	var w: FakeWorld = _world()
	var op: Outposts = w.outposts
	var bot := Node3D.new()
	w.add_child(bot)
	op.repair(0, false, true)
	bot.global_position = op.items[0].charger_world()
	assert_eq(Outposts.charge_mult(bot, w, 0.1), 1.0, "level 1: no pad")
	op.upgrade(0, false, true)
	op.upgrade(0, false, true)
	assert_gt(Outposts.charge_mult(bot, w, 0.1), 1.0, "on the pad: charged")
	bot.global_position = Vector3(0, 0, 0)
	assert_gt(Outposts.charge_mult(bot, w, 1.0), 1.0, "the charge lasts a while")
	bot.set_meta("charge_t", 0.0)
	assert_eq(Outposts.charge_mult(bot, w, 0.1), 1.0, "spent")


func test_levels_persist_into_a_new_district_load() -> void:
	var w: FakeWorld = _world()
	w.outposts.repair(1, false, true)
	w.outposts.upgrade(1, false, true)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.world))  # ints come back as floats
	GameState.world = saved
	var w2: FakeWorld = _world()
	assert_eq(w2.outposts.level_of(1), 2)
	assert_eq(w2.outposts.items[1].level, 2)
	assert_not_null(w2.outposts.items[1].scale_depot)
	assert_eq(w2.outposts.items[0].level, 0)
	assert_string_contains(w2.outposts.hex_note(int(w2.outposts.spots[1]["hex"])), "BIG SKIP")


func test_outpost_achievements_and_wren_lines_exist() -> void:
	var ach: Dictionary = Economy.read_json("res://data/achievements.json")
	var ids: Array = []
	for a: Dictionary in ach["achievements"]:
		ids.append(a["id"])
	assert_has(ids, "outpost_1")
	var lines: Dictionary = Economy.read_json("res://data/wren_lines.json")
	assert_true(lines.has("outpost_repaired"))
	assert_eq((lines["outpost_repaired"] as Array).size(), 3, "one pool per WREN stage")
