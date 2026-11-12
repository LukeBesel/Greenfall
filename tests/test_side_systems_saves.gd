extends GutTest
## Task M3-13: a save from before the side systems were trimmed still loads now that the Requests
## board, trinkets, Garden Mode, the robot nursery, Lumi Level and ship look purchases are parked
## and three world events are cut. The fixture (tests/fixtures/saves/side_systems_v4, written by
## tools/side_save_fixture.gd) is a real version 4 globe save that used all of them.
## Rule under test: the game ignores what they kept, and the save keeps it untouched.

const FIXTURE: String = "res://tests/fixtures/saves/side_systems_v4/slot_0.save"
const SCRATCH: String = "test_side_v4"
const Fixture: GDScript = preload("res://tools/side_save_fixture.gd")

var _state: Dictionary
var _dev_dir: String
var _profile: int
var _slot: int
var _raw: Dictionary


func before_each() -> void:
	_state = GameState.to_dict()
	_dev_dir = SaveManager.dev_dir
	_profile = SaveManager.profile_slot
	_slot = SaveManager.slot
	SaveManager.dev_dir = SCRATCH
	SaveManager.profile_slot = 0
	SaveManager.slot = 0
	_wipe()
	DirAccess.make_dir_recursive_absolute(SaveManager.slot_path().get_base_dir())
	assert_eq(DirAccess.copy_absolute(FIXTURE, SaveManager.slot_path()), OK, "fixture copied")
	_raw = SaveManager.read_dict(FIXTURE)


func after_each() -> void:
	_wipe()
	SaveManager.dev_dir = _dev_dir
	SaveManager.profile_slot = _profile
	SaveManager.slot = _slot
	GameState.from_dict(_state)


func _wipe() -> void:
	var dir: String = SaveManager.slot_path().get_base_dir()
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))


func _json(v: Variant) -> String:
	return JSON.stringify(v, "", true)


func test_the_fixture_used_every_parked_side_system() -> void:
	assert_false(_raw.is_empty(), "the fixture decodes")
	assert_eq(int(_raw["version"]), 4, "an old save: it goes through the migrations")
	for k: String in Fixture.SIDE_FLAGS:
		assert_true((_raw["flags"] as Dictionary).has(k), "fixture flag %s" % k)
	for k: String in Fixture.SIDE_STATS:
		assert_true((_raw["stats"] as Dictionary).has(k), "fixture stat %s" % k)


func test_old_save_loads_and_keeps_the_parked_data_untouched() -> void:
	assert_true(SaveManager.load_game(), "the old save loads")
	var cubes: BigNum = BigNum.from_serialized(_raw["currencies"]["cubes"])
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cubes.to_float(), 0.001, "cubes kept")
	assert_eq(float(GameState.stats["hexes_cleaned"]), float(_raw["stats"]["hexes_cleaned"]), "progress kept")
	for k: String in Fixture.SIDE_FLAGS:
		if k == "bench_tier":
			continue
		assert_eq(_json(GameState.flags[k]), _json(_raw["flags"][k]), "flag %s is carried as it was" % k)
	for k: String in Fixture.SIDE_STATS:
		assert_eq(float(GameState.stats[k]), float(Fixture.SIDE_STATS[k]), "stat %s is carried as it was" % k)
	assert_eq(int(GameState.flags["bench_tier"]), 4, "the Mk IV bench is remembered")
	assert_eq(BenchTiers.tier(), BenchTiers.max_tier(), "and read as the top tier there is now")
	assert_false(UpgradesScreen.TABS.any(func(t: Dictionary) -> bool: return str(t["id"]) == "contracts"), "no Requests tab")
	GameState.use_orbit_world(((GameState.orbit["hub_worlds"] as Dictionary)["0"] as Dictionary).duplicate(true))
	var decor: Array = (GameState.world["decor"] as Dictionary)["items"]
	assert_eq(decor.size(), Fixture.SIDE_DECOR.size(), "the decorations stay in the save")
	assert_false("nursery" in YardBuilds.IDS, "the nursery build is not offered or shown")


func test_parked_bonuses_and_achievements_do_not_count() -> void:
	assert_true(SaveManager.load_game())
	GameState.use_orbit_world(((GameState.orbit["hub_worlds"] as Dictionary)["0"] as Dictionary).duplicate(true))
	var growth: float = Economy.stat("plant_growth")
	var saved_world: Dictionary = GameState.world
	var bare: Dictionary = saved_world.duplicate(true)
	bare.erase("decor_charm")
	GameState.world = bare
	var nursery: Variant = GameState.flags["nursery"]
	GameState.flags.erase("nursery")
	assert_almost_eq(Economy.stat("plant_growth"), growth, 0.000001, "caretakers and decor charm no longer speed plants up")
	GameState.flags["nursery"] = nursery
	GameState.world = saved_world
	for id: String in Fixture.SIDE_ACHIEVEMENTS:
		assert_true(Achievements.def(id).is_empty(), "%s is hidden on this planet" % id)
		assert_true(Achievements.is_unlocked(id), "but the save still remembers it")
	assert_lte(Achievements.unlocked_count(), (GameState.flags["achievements"] as Dictionary).size() - Fixture.SIDE_ACHIEVEMENTS.size(),
		"hidden achievements are not counted")


func test_the_cut_events_in_the_directors_memory_are_skipped() -> void:
	assert_true(SaveManager.load_game())
	var st: Dictionary = WorldEvents.persist_state()
	assert_has(st["recent"] as Array, "wildlife_visit", "the save remembers a cut event")
	var all: Dictionary = {}
	for e: Dictionary in WorldEvents.defs():
		all[str(e["id"])] = true
	for r: float in [0.0, 0.3, 0.6, 0.99]:
		var id: String = WorldEvents.pick_event(WorldEvents.defs(), all, st["recent"], r)
		assert_false(WorldEvents.def(id).is_empty(), "the director only picks events the planet still has (%s)" % id)


func test_saving_and_loading_again_keeps_the_parked_data() -> void:
	assert_true(SaveManager.load_game())
	GameState.add_currency("cubes", BigNum.from_float(50.0))
	assert_true(SaveManager.save_game(false), "the loaded game saves")
	GameState.new_game()
	assert_true(SaveManager.load_game(), "and loads again")
	for k: String in Fixture.SIDE_FLAGS:
		assert_eq(_json(GameState.flags[k]), _json(_raw["flags"][k]), "flag %s survives a save and load" % k)
	for k: String in Fixture.SIDE_STATS:
		assert_eq(float(GameState.stats[k]), float(Fixture.SIDE_STATS[k]), "stat %s survives a save and load" % k)
