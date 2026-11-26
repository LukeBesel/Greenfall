extends GutTest
## Command View orders: group vs single-robot orders, modes, zone normalisation on load.

var _world: Dictionary


func before_each() -> void:
	_world = GameState.world
	GameState.world = {}


func after_each() -> void:
	GameState.world = _world


func _bot(f: Fleet, type_id: String, rname: String) -> Robot:
	var r := Robot.new()
	r.type_id = type_id
	r.robot_name = rname
	f.add_child(r)
	return r


func test_group_and_bot_orders() -> void:
	var f := Fleet.new()
	add_child_autofree(f)
	var a := _bot(f, "scoopie", "A")
	var b := _bot(f, "scoopie", "B")
	assert_eq(f.mode_of(a), "roam")
	f.toggle_zone_hex("clean", false, 5, true)
	f.toggle_zone_hex("clean", false, 6, true)
	assert_eq(f.mode_of(a), "priority")
	assert_eq(f.zone_hexes(b), [5, 6])
	f.set_mode("B", true, "recall")
	assert_eq(f.mode_of(b), "recall", "a robot's own order overrides its crew's")
	assert_eq(f.mode_of(a), "priority")
	f.toggle_zone_hex("clean", false, 5, false)
	assert_eq(f.zone_hexes(a), [6])
	f.clear_order("clean", false)
	assert_eq(f.mode_of(a), "roam")


func test_zone_ids_normalised_after_json() -> void:
	GameState.world = JSON.parse_string(JSON.stringify({"orders": {"groups": {"clean": {"zone": [3, 4], "mode": "stay"}}, "bots": {}}}))
	var f := Fleet.new()
	add_child_autofree(f)
	f.restore()
	var a := _bot(f, "scoopie", "A")
	assert_true(f.zone_hexes(a).has(3))
	assert_eq(typeof(f.zone_hexes(a)[0]), TYPE_INT)
	assert_eq(f.mode_of(a), "stay")
