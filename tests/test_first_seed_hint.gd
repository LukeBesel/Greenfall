extends GutTest
## [v4grow] Owner playtest 3 #48: the first seed was hard to find. On the seed step the beacon
## stands on the tin once its signal is in; without the signal, it comes by itself after
## FirstSeed.HINT_AFTER_S on the step. After the tin, planting needs no dirty-hex outline.

class FakeField:
	extends RefCounted
	var cleaned_count: int = 0


class FakeGarden:
	extends RefCounted
	var cfg: Dictionary = {"first_seed": {"hexes_needed": 7}}


class FakeWorld:
	extends Node
	var field: FakeField = FakeField.new()
	var garden: FakeGarden = FakeGarden.new()
	var objectives: Objectives
	var first_seed: FirstSeed
	var patch: Variant = null


var _flags: Dictionary
var _w: FakeWorld
var _fs: FirstSeed
var _ob: Objectives


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	GameState.flags.erase("seed_signal")
	GameState.flags.erase("seeds_unlocked")
	_w = FakeWorld.new()
	add_child(_w)
	_ob = Objectives.new()
	_ob.world = _w
	_ob.chain = (JSON.parse_string(FileAccess.get_file_as_string("res://data/objectives.json")) as Dictionary)["objectives"]
	_ob.revealed = true
	_ob.step = _ob.chain.map(func(d: Dictionary) -> String: return str(d["id"])).find("seed")
	_w.objectives = _ob
	_fs = FirstSeed.new()
	_fs.world = _w
	_fs.set_process(false)
	_w.add_child(_fs)
	_w.first_seed = _fs


func after_each() -> void:
	GameState.flags = _flags
	_ob.free()
	_w.free()


func test_signal_comes_after_a_while_on_the_seed_step() -> void:
	assert_false(_fs.ready_to_find(), "no clean hexes yet: no signal")
	_fs._hint_tick(FirstSeed.HINT_AFTER_S - 1.0)
	assert_false(GameState.flags.get("seed_signal", false), "not yet")
	_fs._hint_tick(2.0)
	assert_true(GameState.flags.get("seed_signal", false), "the signal comes by itself")
	assert_true(_fs.ready_to_find(), "the tin can be taken once the signal is in")


func test_no_timer_off_the_seed_step() -> void:
	_ob.step = 0
	_fs._hint_tick(FirstSeed.HINT_AFTER_S * 3.0)
	assert_false(GameState.flags.get("seed_signal", false), "only the seed step counts")


func test_beacon_on_the_seed_step() -> void:
	var def: Dictionary = _ob.current()
	assert_eq(str(def.get("id")), "seed")
	assert_eq(str(_ob.step_target(def).get("to")), "hex", "before the signal: keep cleaning")
	GameState.flags["seed_signal"] = true
	var t: Dictionary = _ob.step_target(def)
	assert_eq(str(t.get("to")), "place", "with the signal: the beacon leads to the tin")
	assert_true(t.get("pos") is Vector3)
	GameState.flags["seeds_unlocked"] = true
	t = _ob.step_target(def)
	assert_eq(str(t.get("to")), "", "planting: no dirty-hex outline, no beam")
	assert_eq(t.get("pos", null), null)
