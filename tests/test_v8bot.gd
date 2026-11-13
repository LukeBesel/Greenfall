extends GutTest
## [v8bot] Owner: "paint the hex to control bot? doesnt make any sense. Dont say anything about
## telling it where to go it just goes on its own for the scoopies". No zone step, no zone goal, and
## old saves on or past the zone step move on cleanly.

var _flags: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags


func _chain() -> Array:
	return Economy.read_json("res://data/objectives.json").get("objectives", [])


func _index(id: String) -> int:
	var ch: Array = _chain()
	for i: int in ch.size():
		if str((ch[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func test_no_step_or_goal_asks_for_a_zone() -> void:
	for d: Dictionary in _chain():
		assert_ne(str(d.get("type", "")), "zone", "%s asks for a zone" % d.get("id", ""))
	for g: Dictionary in Economy.read_json("res://data/goals.json").get("goals", []):
		assert_ne(str(g.get("type", "")), "zone", "%s asks for a zone" % g.get("id", ""))


func test_no_early_text_tells_the_player_to_direct_the_robot() -> void:
	var stop: int = _index("seed")
	assert_gt(stop, 0)
	var ch: Array = _chain()
	for i: int in stop + 1:
		var d: Dictionary = ch[i]
		var all: String = " ".join([str(d.get("text", "")), str(d.get("desc", "")), str(d.get("hint", "")), " ".join(d.get("lines", []))]).to_lower()
		for bad: String in ["paint", "zone", "open_command", "show your robot", "show it where", "where to clean"]:
			assert_false(all.contains(bad), "%s says '%s'" % [d.get("id", ""), bad])
	var after: Dictionary = ch[_index("robot") + 1]
	assert_eq(str(after["id"]), "hex2", "the story goes straight on after the first robot")
	assert_string_contains(" ".join(after.get("lines", [])), "on its own")


func _migrate(step: int, has_step: bool = true) -> int:
	GameState.flags.erase("objectives_v3")
	if has_step:
		GameState.flags["objective_step"] = step
	else:
		GameState.flags.erase("objective_step")
	var o := Objectives.new()
	o.chain = _chain()
	o.step = step
	o._drop_zone_step()
	var out: int = o.step
	o.free()
	return out


func test_old_save_on_the_zone_step_moves_on() -> void:
	var hex2: int = _index("hex2")
	# The old chain had "zone" at hex2's index now: a save sitting on it lands on hex2.
	assert_eq(_migrate(hex2), hex2)
	assert_eq(int(GameState.flags["objective_step"]), hex2)
	# Past it: one step fewer in front.
	assert_eq(_migrate(hex2 + 3), hex2 + 2)
	assert_eq(int(GameState.flags["objective_step"]), hex2 + 2)
	# Before it: unchanged.
	assert_eq(_migrate(hex2 - 1), hex2 - 1)
	assert_true(GameState.flags.get("objectives_v3", false))


func test_migration_runs_once_and_not_for_new_games() -> void:
	var hex2: int = _index("hex2")
	assert_eq(_migrate(0, false), 0)
	assert_false(GameState.flags.has("objective_step"))
	GameState.flags["objective_step"] = hex2 + 4
	var o := Objectives.new()
	o.chain = _chain()
	o.step = hex2 + 4
	o._drop_zone_step()  # the flag is set: a save made by this build keeps its step
	assert_eq(o.step, hex2 + 4)
	o.free()


func test_painted_zones_still_count_and_load() -> void:
	var crew := SphereCrew.new()
	var d: Dictionary = {"v": 1, "robots": [], "bales": [], "cashed": 0.0, "zones": {"clean": [5, 6]}, "hub_log": {}}
	crew.from_dict(d)
	assert_eq(crew.zone_cells().size(), 2, "a save's painted zones load")
	assert_eq(crew.to_dict()["zones"]["clean"].size(), 2, "and save again")
	crew.free()
