extends GutTest
## Task M1-08: a save tree from the five-planet game still loads now that the campaign, the
## prestige mode, the weekly seed, the Museum, the Telescope, the Bot Fabricator and the profile
## picker are parked. The fixture (tests/fixtures/saves/parked_v4, written by
## tools/parked_save_fixture.gd) is a real Verdance globe save plus everything those features kept:
## flags, stats, finished goals, achievements, Codex keys, decor, hub state, a second planet's
## slot, a weekly run, the prestige profile and a second save profile.
## Rule under test: Verdance's progress is kept; parked keys are ignored, never migrated or erased.

const FIXTURE: String = "res://tests/fixtures/saves/parked_v4"
const SCRATCH: String = "test_parked_v4"
const FILES: Array[String] = ["p1/slot_0.save", "p1/slot_1.save", "p1/slot_9.save", "p1/weekly.save", "p1/profile.save",
	"p2/slot_0.save", "p2/profile.save", "profiles.cfg"]
const Fixture: GDScript = preload("res://tools/parked_save_fixture.gd")

var _state: Dictionary
var _dev_dir: String
var _profile: int
var _slot: int
var _enabled: bool
var _raw: Dictionary


func before_each() -> void:
	_state = GameState.to_dict()
	_dev_dir = SaveManager.dev_dir
	_profile = SaveManager.profile_slot
	_slot = SaveManager.slot
	_enabled = SaveManager.enabled
	SaveManager.dev_dir = SCRATCH
	_wipe()
	for f: String in FILES:
		DirAccess.make_dir_recursive_absolute(SaveManager.root_dir().path_join(f).get_base_dir())
		assert_eq(DirAccess.copy_absolute(FIXTURE.path_join(f), SaveManager.root_dir().path_join(f)), OK, "fixture file %s copied" % f)
	# What the game does at start: read the remembered profile; the world slot is always the first.
	SaveManager.profile_slot = SaveManager.read_profile_choice()
	SaveManager.slot = 0
	_raw = SaveManager.read_dict(FIXTURE.path_join("p1/slot_0.save"))


func after_each() -> void:
	_wipe()
	SaveManager.dev_dir = _dev_dir
	SaveManager.profile_slot = _profile
	SaveManager.slot = _slot
	SaveManager.enabled = _enabled
	GameState.from_dict(_state)


func _wipe() -> void:
	var root: String = SaveManager.root_dir()
	for d: String in ["p1", "p2", "p3", ""]:
		var dir: String = root.path_join(d)
		if DirAccess.dir_exists_absolute(dir):
			for f: String in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(f))
			DirAccess.remove_absolute(dir)


func _md5(path: String) -> String:
	return FileAccess.get_md5(path)


func test_the_fixture_holds_parked_data() -> void:
	assert_false(_raw.is_empty(), "the fixture save decodes")
	for k: String in Fixture.PARKED_FLAGS:
		assert_true((_raw["flags"] as Dictionary).has(k), "fixture flag %s" % k)
	for k: String in Fixture.PARKED_STATS:
		assert_true((_raw["stats"] as Dictionary).has(k), "fixture stat %s" % k)
	var prof: Dictionary = SaveManager.read_dict(FIXTURE.path_join("p1/profile.save"))
	assert_eq(int(prof["current"]), 1, "the prestige profile last pointed at the second planet")
	assert_true(prof.has("homeward") and prof.has("heirlooms"), "it holds the campaign and the Heirlooms")


func test_old_save_loads_and_keeps_verdance_progress() -> void:
	assert_eq(SaveManager.profile_slot, 1)
	assert_true(SaveManager.has_save())
	assert_true(SaveManager.load_game(), "the old save loads")
	assert_eq(str(GameState.orbit.get("planet_id", "")), str(Planets.current_id()), "the first slot is the current planet's world")
	var cubes: BigNum = BigNum.from_serialized(_raw["currencies"]["cubes"])
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cubes.to_float(), 0.001, "cubes kept")
	assert_eq(float(GameState.stats["hexes_cleaned"]), float(_raw["stats"]["hexes_cleaned"]), "cleaned hexes kept")
	assert_eq(float(GameState.stats["time_played"]), float(_raw["stats"]["time_played"]))
	assert_eq(GameState.upgrades.size(), (_raw["upgrades"] as Dictionary).size(), "upgrades kept")
	for k: String in _raw["upgrades"]:
		assert_eq(GameState.level_of(k), int(_raw["upgrades"][k]), "upgrade %s" % k)
	assert_eq(str(GameState.orbit["cells"]), str(_raw["orbit"]["cells"]), "the globe's cells kept")
	assert_eq(str(GameState.orbit["hex_levels"]), str(_raw["orbit"]["hex_levels"]))
	assert_eq(int(GameState.flags["lumi"]["level"]), int(_raw["flags"]["lumi"]["level"]), "Lumi's level kept")
	assert_false(GameState.currencies.has("starseeds"), "the prestige currency is not a currency")


func test_parked_keys_are_ignored_not_migrated() -> void:
	assert_true(SaveManager.load_game())
	for k: String in Fixture.PARKED_FLAGS:
		assert_eq(JSON.stringify(GameState.flags[k]), JSON.stringify(_raw["flags"][k]), "flag %s is carried as it was" % k)
	for k: String in Fixture.PARKED_STATS:
		assert_eq(float(GameState.stats[k]), float(Fixture.PARKED_STATS[k]), "stat %s is carried as it was" % k)
	# Goals: the chain has no goal of a parked feature, and the finished ones do not count.
	var goals := Goals.new()
	add_child_autofree(goals)
	var chain_ids: Array = goals.chain.map(func(g: Dictionary) -> String: return str(g["id"]))
	for id: String in Fixture.PARKED_GOALS:
		assert_false(id in chain_ids, "goal %s is not in the chain" % id)
	assert_eq(goals.done_count(), (_raw["flags"]["goals_done"] as Array).size() - Fixture.PARKED_GOALS.size(), "only playable goals count as done")
	assert_false(goals.current().is_empty(), "the chain goes on")
	# Research: a finished node the game no longer has is carried and ignored.
	assert_true("observatory" in Research.done_list(), "the old save finished the removed node")
	assert_false(Research.exists("observatory"))
	assert_eq(Research.breakdown("no_such_stat").size(), 0, "walking the finished list copes with the unknown id")
	assert_eq(Research.stat_mod("no_such_stat", 2.0), 2.0)
	# Achievements and the Codex count what the game still has.
	var real_unlocks: int = (_raw["flags"]["achievements"] as Dictionary).size() - Fixture.PARKED_ACHIEVEMENTS.size()
	assert_eq(Achievements.unlocked_count(), real_unlocks, "parked achievements are not counted")
	for id: String in Fixture.PARKED_ACHIEVEMENTS:
		assert_true(Achievements.def(id).is_empty(), "%s is not an achievement any more" % id)
		assert_true(Achievements.is_unlocked(id), "but the save still remembers it")
	assert_eq(Codex.count(), (_raw["flags"]["codex"] as Array).size() - Fixture.PARKED_CODEX.size(), "parked Codex keys are not counted")
	for c: Dictionary in Codex.categories():
		assert_gt(Codex.total(str(c["id"])), 0, "Codex category %s has entries" % c["id"])
	# Builds and decor of parked features are not offered or built.
	for id: String in ["telescope", "museum", "bot_fabricator"]:
		assert_false(id in HubBuilds.ids(), "%s is not a build here" % id)
	GameState.use_orbit_world(((GameState.orbit["hub_worlds"] as Dictionary)["0"] as Dictionary).duplicate(true))
	assert_eq(((GameState.world["decor"] as Dictionary)["items"] as Array).size(), Fixture.PARKED_DECOR.size())
	var decor := Decor.new()
	add_child_autofree(decor)
	decor.setup(null)
	assert_eq(decor.items.size(), 0, "decorations of a parked feature are not placed")


func test_saving_touches_only_the_played_slot() -> void:
	assert_true(SaveManager.load_game())
	var others: Array[String] = FILES.filter(func(f: String) -> bool: return f != "p1/slot_0.save")
	var before: Dictionary = {}
	for f: String in others:
		before[f] = _md5(SaveManager.root_dir().path_join(f))
	GameState.add_currency("cubes", BigNum.from_float(500.0))
	var cubes: float = GameState.get_currency("cubes").to_float()
	assert_true(SaveManager.save_game(false), "the loaded game saves")
	for f: String in others:
		assert_eq(_md5(SaveManager.root_dir().path_join(f)), str(before[f]), "%s is left as it was" % f)
	GameState.new_game()
	assert_true(SaveManager.load_game(), "and loads again")
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cubes, 0.001)
	for k: String in Fixture.PARKED_FLAGS:
		assert_true(GameState.flags.has(k), "flag %s survives a save and load" % k)
	# New Game erases the played slot only.
	SaveManager.delete_save()
	assert_false(SaveManager.has_save())
	for f: String in others:
		assert_true(FileAccess.file_exists(SaveManager.root_dir().path_join(f)), "%s is still there after New Game" % f)
