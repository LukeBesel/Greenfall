extends GutTest
## [camp3] Blink, the camera bot: a one-time, game-wide Build-tab build that unlocks photo mode.
## Hidden until hub level 2 or ~25 min of play; costs a chunk of parts; old saves that used photo
## mode get him built; photo mode, its pause button and its key hint wait for him.

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary
var _districts: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	_districts = GameState.districts
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world
	GameState.districts = _districts


func _once() -> Array:
	return HubBuilds.available(null, "one_time").map(func(e: Dictionary) -> String: return str(e["id"]))


func test_hidden_until_unlocked_then_a_one_time_build() -> void:
	assert_eq(HubBuilds.kind_now(CameraBot.ID), "one_time")
	assert_does_not_have(_once(), CameraBot.ID, "not listed at the start")
	assert_false(CameraBot.available(), "no photo mode at the start")
	GameState.stats["time_played"] = 1600.0
	assert_has(_once(), CameraBot.ID, "listed after ~25 min of play")
	GameState.stats["time_played"] = 0.0
	GameState.world["hub_level"] = 2
	assert_has(_once(), CameraBot.ID, "or at hub level 2")
	var cost: Dictionary = HubBuilds.entry(null, CameraBot.ID)["cost"]
	assert_gte(float(cost.get("parts", 0.0)), 50.0, "a good chunk of parts")
	Camp.set_bench_ok(true)
	GameState.add_currency("cubes", BigNum.from_float(1.0e4))
	GameState.add_currency("parts", BigNum.from_float(10))
	assert_false(HubBuilds.build(null, CameraBot.ID), "not without the parts")
	GameState.add_currency("parts", BigNum.from_float(500))
	assert_true(HubBuilds.build(null, CameraBot.ID))
	assert_true(CameraBot.available(), "photo mode opens")
	assert_does_not_have(_once(), CameraBot.ID, "built: off the Build tab")
	assert_has(HubBuilds.built_names(null), "Blink")
	GameState.world = {}  # another base: he is game-wide
	assert_true(CameraBot.available())


func test_photo_hint_waits_for_him() -> void:
	var has_photo := func() -> bool:
		return KeyHints.items_for(true, true).any(func(it: Array) -> bool: return str(it[0]) == "photo_mode")
	assert_false(has_photo.call(), "no photo key hint before Blink")
	YardBuilds.mark_built(CameraBot.ID)
	assert_true(has_photo.call())


func test_old_saves_that_used_photo_mode_keep_him() -> void:
	GameState.stats["photo_mode_opens"] = 3.0
	CameraBot.migrate(false)
	assert_false(CameraBot.available(), "a new game never inherits him")
	GameState.flags.erase("camera_bot_migrated")
	CameraBot.migrate(true)
	assert_true(CameraBot.available(), "an old save that used photo mode has him built")
	GameState.flags = {}
	GameState.stats = {"photo_mode_opens": 0}
	GameState.flags["fauna_photos"] = ["pigeon"]
	CameraBot.migrate(true)
	assert_true(CameraBot.available(), "animal photos count as using photo mode")
