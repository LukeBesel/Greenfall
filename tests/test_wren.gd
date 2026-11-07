extends GutTest

var wren: Wren
var _flags: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}
	wren = Wren.new()
	add_child_autofree(wren)


func after_each() -> void:
	GameState.flags = _flags


func test_silent_until_awake() -> void:
	wren.say("perfect", 1.0, true)
	assert_eq(wren._queue.size(), 0)


func test_wake_on_first_hex_then_lines() -> void:
	wren._on_hex(0, Vector3.ZERO, BigNum.zero())
	assert_true(wren.awake())
	assert_eq(wren._queue.size(), 1)
	assert_string_contains(str(wren._queue[0]["text"]), "Hello")


func test_no_repeats_until_pool_exhausted() -> void:
	GameState.flags["wren_awake"] = true
	var pool: Array = wren.lines["hex_clean"][0]
	var seen: Dictionary = {}
	for i: int in pool.size():
		wren.say("hex_clean", 1.0, true)
	for q: Dictionary in wren._queue:
		seen[q["text"]] = true
	assert_eq(seen.size(), pool.size())


func test_vars_formatted() -> void:
	GameState.flags["wren_awake"] = true
	GameState.flags["stage_override"] = 1
	wren.say("robot_built", 1.0, true, {"robot": "Rivet-07"})
	assert_false(str(wren._queue[0]["text"]).contains("{robot}"))
