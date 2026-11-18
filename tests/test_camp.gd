extends GutTest
## [camp] The landing yard: the upgradeable trash bin, yard builds (radio, nursery), the broken
## workbench on fresh bases, old-save migration, and the 3 m spacing between yard interactables.

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


func test_trash_bin_levels() -> void:
	assert_eq(TrashBin.level(), 1, "a base starts with the dented bin")
	assert_gte(TrashBin.max_level(), 4)
	assert_eq(TrashBin.value_mult(), 1.0, "level 1 pays the plain rate")
	assert_ne(TrashBin.block_reason(5), "", "can't afford it with no cubes")
	assert_false(TrashBin.upgrade(5))
	GameState.add_currency("cubes", BigNum.from_float(1.0e6))
	GameState.add_currency("parts", BigNum.from_float(1.0e4))
	assert_eq(TrashBin.block_reason(1), "", "level 2 only needs cubes")
	var got: Array = []
	var cb := func(l: int) -> void: got.append(l)
	TrashBin.events.changed.connect(cb)
	assert_true(TrashBin.upgrade(1))
	TrashBin.events.changed.disconnect(cb)
	assert_eq(TrashBin.level(), 2)
	assert_eq(got, [2], "the bin's body hears about it")
	assert_ne(TrashBin.block_reason(1), "", "level 3 needs a bigger hub")
	var last: float = TrashBin.value_mult()
	var feed: float = TrashBin.feed_interval()
	while TrashBin.upgrade(5):
		assert_gt(TrashBin.value_mult(), last, "every level pays more")
		assert_lt(TrashBin.feed_interval(), feed, "and swallows faster")
		last = TrashBin.value_mult()
		feed = TrashBin.feed_interval()
	assert_eq(TrashBin.level(), TrashBin.max_level())
	assert_true(TrashBin.next_def().is_empty())
	assert_eq(int(GameState.world["trash_bin"]["level"]), TrashBin.max_level(), "saved with the district")


func test_yard_builds_need_level_flag_and_cubes() -> void:
	GameState.add_currency("cubes", BigNum.from_float(1.0e6))
	assert_false(YardBuilds.built("radio"), "no radio on a fresh base")
	assert_ne(YardBuilds.block_reason("radio", 1), "", "the radio needs hub level 2")
	assert_true(YardBuilds.build("radio", 2))
	assert_true(YardBuilds.built("radio"))
	assert_false(YardBuilds.build("radio", 2), "built once")
	assert_false(YardBuilds.listed("nursery"), "no nursery listed before anything has grown")
	assert_false(YardBuilds.build("nursery", 5))
	GameState.flags["first_sprout"] = true
	assert_true(YardBuilds.listed("nursery"))
	assert_true(YardBuilds.build("nursery", 1))


func test_fresh_bench_is_broken_old_saves_keep_theirs() -> void:
	assert_false(Camp.bench_ok(), "a fresh base's workbench is broken")
	Camp.set_bench_ok(true)
	assert_true(Camp.bench_ok())
	GameState.world = {"field": {}, "hub_level": 2}
	assert_true(Camp.bench_ok(), "an already-played district keeps a working bench")
	Camp.migrate()
	assert_true(YardBuilds.built("radio"), "a level 2 base from an old save keeps its radio")
	assert_false(YardBuilds.built("nursery"), "no caretakers, no nursery")
	GameState.world = {}
	Camp.migrate()
	assert_false(YardBuilds.built("radio"), "fresh districts start bare")


## Every fixed yard interaction point at least min_gap apart (from the data, no scene needed).
func test_yard_interactables_are_spaced() -> void:
	var gap: float = float(YardBuilds.cfg().get("min_gap", 3.0))
	assert_gte(gap, 3.0)
	var radio: Vector3 = YardBuilds.pos("radio", Radio.POS)
	var ryaw: float = deg_to_rad(float(YardBuilds.def("radio").get("yaw_deg", 180.0)))
	var tcfg: Dictionary = RemoteProgress.cfg()
	var tp: Array = tcfg.get("pos", [0, 0])
	var door: Vector3 = Vector3(float(tp[0]), 0, float(tp[1])) + Basis(Vector3.UP, deg_to_rad(float(tcfg.get("yaw_deg", 0.0)))) * Vector3(0, 0, 2.2)
	var pts: Dictionary = {
		"workbench": Vector3(-3.6, 0, 2.2),
		"trash_bin": Camp.BIN_ANCHOR,
		"composter": Composter.POS,
		"flower": Vector3(2.9, 0, 1.4),
		"radio": radio + Basis(Vector3.UP, ryaw) * Vector3(1.0, 0, 0),
		"telescope": door,
	}
	var keys: Array = pts.keys()
	for i: int in keys.size():
		for j: int in range(i + 1, keys.size()):
			var a: Vector3 = pts[keys[i]]
			var b: Vector3 = pts[keys[j]]
			assert_gte(Vector2(a.x - b.x, a.z - b.z).length(), gap, "%s and %s are far enough apart" % [keys[i], keys[j]])
	assert_gte(Vector2(radio.x + 3.6, radio.z - 2.2).length(), 8.0, "the radio is nowhere near the workbench")


## The escape pod's crash site (intro2): the pod, its ~8 m furrow and the door ramp stay clear of
## the yard's things.
func test_yard_keeps_off_the_crash_site() -> void:
	var pod := Vector3(Intro.POD_POS.x, 0, Intro.POD_POS.z)
	var keep: Array = [[pod, 3.0]]
	for t: float in [1.0, 2.0, 3.0, 4.0]:
		keep.append([pod + Vector3(-0.48, 0, -0.88) * t, 1.6])  # door ramp
	for t: float in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]:
		keep.append([pod + Vector3(-0.83, 0, 0.55) * t, 1.6])  # furrow
	var tp: Array = RemoteProgress.cfg().get("pos", [0, 0])
	var things: Dictionary = {
		"workbench": [Vector3(-4.9, 0, 2.2), 2.0],
		"trash_bin": [Vector3(0, 0, -3.2), 2.2],
		"radio": [YardBuilds.pos("radio", Radio.POS), 1.0],
		"nursery": [Nursery.SPOTS[0], 3.0],
		"telescope": [Vector3(float(tp[0]), 0, float(tp[1])), 2.4],
	}
	for k: String in things:
		var p: Vector3 = things[k][0]
		var r: float = things[k][1]
		for z: Array in keep:
			var c: Vector3 = z[0]
			assert_gt(Vector2(p.x - c.x, p.z - c.z).length(), r + float(z[1]), "%s clear of the crash site at (%.1f, %.1f)" % [k, c.x, c.z])
