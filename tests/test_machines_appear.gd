extends GutTest
## [camp] Owner bug: "Bought the belt drive and baler hub upgrades and nothing appeared or
## happened." Machine upgrades can't be bought before their machine exists, and building a
## machine puts it in the world at once (with a reveal: effect, toast, waypoint).

var _cur: Dictionary
var _flags: Dictionary
var _world: Dictionary
var _ups: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_world = GameState.world
	_ups = GameState.upgrades.duplicate()
	_stats = GameState.stats.duplicate(true)
	GameState.currencies = {}
	GameState.flags = {}
	GameState.world = {}
	GameState.upgrades = {}
	GameState.stats = {}
	GameState.add_currency("cubes", BigNum.from_float(1.0e7))
	GameState.add_currency("parts", BigNum.from_float(1.0e6))


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.world = _world
	GameState.upgrades = _ups
	GameState.stats = _stats


func test_machine_upgrades_need_their_machine() -> void:
	for id: String in ["belt_speed", "baler_speed", "recycler_yield"]:
		assert_false(Economy.is_unlocked(id), "%s is locked while its machine isn't built" % id)
		assert_eq(Economy.buy_upgrade(id), 0, "%s can't be bought invisibly" % id)


func test_each_machine_spawns_its_node() -> void:
	var st := Stations.new()
	add_child_autofree(st)
	for id: String in ["conveyor", "auto_baler", "recycler"]:
		Research.grant(id)
	GameState.world["hub_level"] = 5
	var revealed: Array = []
	var cb := func(name_: String, _at: Vector3) -> void: revealed.append(name_)
	MachineReveal.events.revealed.connect(cb)
	for pair: Array in [["conveyor", "belt_speed"], ["auto_baler", "baler_speed"], ["recycler", "recycler_yield"]]:
		var id: String = pair[0]
		assert_eq(st.block_reason(id), "", "%s can be built" % id)
		assert_true(st.build(id), "%s built" % id)
		var node: Node3D = {"conveyor": st.conveyor, "auto_baler": st.baler, "recycler": st.recycler}[id]
		assert_not_null(node, "%s spawned" % id)
		if node:
			assert_true(node.is_inside_tree() and node.visible, "%s is in the world and visible" % id)
		assert_true(Economy.is_unlocked(pair[1]), "%s unlocks with its machine" % pair[1])
		assert_eq(Economy.buy_upgrade(pair[1]), 1, "%s can be bought now" % pair[1])
	MachineReveal.events.revealed.disconnect(cb)
	assert_eq(revealed.size(), 3, "each machine got a reveal (effect, toast, waypoint)")
