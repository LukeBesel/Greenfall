extends GutTest

class FakeFleet:
	extends Node
	var counts: Dictionary = {}
	func count(type_id: String) -> int:
		return int(counts.get(type_id, 0))
	func robots() -> Array:
		return []

class FakeWorld:
	extends Node
	var fleet: FakeFleet
	var hex_levels: HexLevels

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	GameState.flags = {}
	GameState.currencies = {}
	GameState.stats = {}
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world


func _make() -> Goals:
	var w := FakeWorld.new()
	w.fleet = FakeFleet.new()
	w.add_child(w.fleet)
	add_child_autofree(w)
	var g := Goals.new()
	g.world = w
	w.add_child(g)
	g.set_process(false)
	return g


func test_chain_is_long_and_ids_unique() -> void:
	var g: Goals = _make()
	assert_gte(g.chain.size(), 40)
	var ids: Dictionary = {}
	for e: Dictionary in g.chain:
		assert_false(ids.has(e["id"]), "duplicate goal id " + str(e["id"]))
		ids[e["id"]] = true
		assert_true(e.has("text") and e.has("type") and e.has("reward"))
	assert_eq(g.current().size(), 3)


func test_complete_pays_reward_and_advances() -> void:
	var g: Goals = _make()
	var first: int = g.current()[0]
	assert_eq(g.check(), -1, "nothing done yet")
	GameState.stats["junk_scooped"] = 100.0
	assert_eq(g.check(), first)
	assert_true(g.is_done(first))
	var r: Dictionary = g.reward_of(first)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), float(r["cubes"]), 0.01)
	assert_false(g.current().has(first))
	assert_eq(g.current().size(), 3, "next goal slides in")
	assert_eq((GameState.flags["goals_done"] as Array).size(), 1)


func test_one_completion_per_beat() -> void:
	var g: Goals = _make()
	GameState.stats["junk_scooped"] = 100.0
	GameState.stats["cubes_made"] = 5.0
	GameState.stats["cubes_cashed"] = 5.0
	GameState.stats["junk_dumps"] = 5.0  # [pace] the second goal empties the chest
	GameState.stats["upgrades_bought"] = 5.0
	assert_gte(g.check(), 0)
	assert_eq(g.done_count(), 1)
	g.check()
	g.check()
	assert_eq(g.done_count(), 3)


func test_progress_persists_via_flags() -> void:
	var g: Goals = _make()
	GameState.stats["junk_scooped"] = 100.0
	g.check()
	var g2: Goals = _make()
	assert_eq(g2.done_count(), 1)
	assert_eq(g2.current()[0], g.current()[0])


func test_value_types() -> void:
	var g: Goals = _make()
	var by_id: Dictionary = {}
	for i: int in g.chain.size():
		by_id[str(g.chain[i]["id"])] = i
	(g.world as FakeWorld).fleet.counts["scoopie"] = 1
	assert_eq(g.value_of(by_id["scoopie_1"]), 1.0)
	GameState.world["hub_level"] = 2
	assert_eq(g.value_of(by_id["base_2"]), 2.0)
	GameState.world["orders"] = {"groups": {"clean": {"zone": [3, 4], "mode": "stay"}}, "bots": {"Bolt-01": {"zone": [4, 5]}}}
	assert_eq(Goals.zone_hex_count(), 3, "painted zones still count (the zone goal type stays for data that wants it)")  # [v8bot] no zone goal in the chain
	assert_false(by_id.has("zone_1"), "the game does not ask for a work zone")
	GameState.flags["seeds_unlocked"] = true
	assert_eq(g.value_of(by_id["seeds"]), 1.0)
	GameState.flags["tier_drip"] = 2
	assert_eq(g.value_of(by_id["tier_1"]), 2.0)
	assert_eq(g.value_of(by_id["hexlv_4"]), 0.0, "no hex levels node -> 0")
	GameState.add_currency("cubes", BigNum.from_float(1500))
	assert_gte(g.value_of(by_id["earn_1k"]), 1500.0)
	assert_almost_eq(g.progress(by_id["earn_1k"]), 1.0, 0.001)
