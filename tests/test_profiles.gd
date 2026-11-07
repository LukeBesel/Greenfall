extends GutTest
## [worlds2] Save profiles (autoload/SaveManager.gd profile folders, systems/profile_slots.gd,
## ui/profile_picker.gd): migrating pre-profile saves into profile 1, profiles kept apart (worlds,
## Heirlooms, slots), summaries, rename and delete, and per-profile Steam Cloud names.

const SCRATCH: String = "user://test_profiles_scratch"

var _keep: Array


func before_each() -> void:
	_keep = [SaveManager.dev_dir, SaveManager.profile_slot, SaveManager.slot, CradleMode.profile.duplicate(true), CradleMode.persist,
		CradleMode.path_override, GameState.flags.duplicate(true), GameState.stats.duplicate(true), GameState.world, GameState.districts,
		GameState.currencies.duplicate()]
	SaveManager.dev_dir = "profiles_test"
	_wipe(SaveManager.root_dir())
	CradleMode.path_override = ""
	CradleMode.persist = true
	SaveManager.set_profile(1)
	CradleMode.profile = CradleMode.default_profile()
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	ProfileSlots.dev_summaries = {}


func after_each() -> void:
	_wipe(SaveManager.root_dir())
	_wipe(SCRATCH)
	SaveManager.dev_dir = _keep[0]
	SaveManager.profile_slot = _keep[1]
	SaveManager.slot = _keep[2]
	CradleMode.profile = _keep[3]
	CradleMode.persist = _keep[4]
	CradleMode.path_override = _keep[5]
	GameState.flags = _keep[6]
	GameState.stats = _keep[7]
	GameState.world = _keep[8]
	GameState.districts = _keep[9]
	GameState.currencies = _keep[10]
	SteamService.detach()


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _save(path: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_true(SaveManager.write_dict(path, d))


# --- Migration -------------------------------------------------------------------------------

func test_old_saves_move_into_profile_one() -> void:
	_save(SCRATCH.path_join("slot_0.save"), {"saved_unix": 5.0, "flags": {"m": "verdance"}})
	_save(SCRATCH.path_join("slot_1.save"), {"saved_unix": 6.0})
	_save(SCRATCH.path_join("profile.save"), {"starseeds": 12.0, "worlds": [{"index": 0, "seed": 4471, "slot": 0}]})
	assert_eq(SaveManager.migrate_to_profiles(SCRATCH), 3)
	for nm: String in ["slot_0.save", "slot_1.save", "profile.save"]:
		assert_false(FileAccess.file_exists(SCRATCH.path_join(nm)), "%s left the root" % nm)
		assert_true(FileAccess.file_exists(SCRATCH.path_join("p1").path_join(nm)), "%s is in p1" % nm)
	assert_eq(str(SaveManager.read_dict(SCRATCH.path_join("p1/slot_0.save"))["flags"]["m"]), "verdance", "contents intact")
	assert_eq(SaveManager.migrate_to_profiles(SCRATCH), 0, "runs once")


func test_migration_never_overwrites_profile_one() -> void:
	_save(SCRATCH.path_join("p1/slot_0.save"), {"flags": {"m": "new"}})
	_save(SCRATCH.path_join("slot_0.save"), {"flags": {"m": "old"}})
	assert_eq(SaveManager.migrate_to_profiles(SCRATCH), 0)
	assert_eq(str(SaveManager.read_dict(SCRATCH.path_join("p1/slot_0.save"))["flags"]["m"]), "new")
	assert_eq(SaveManager.migrate_to_profiles(SCRATCH + "_missing"), 0)


func test_migrated_profile_loads_as_profile_one() -> void:
	var root: String = SaveManager.root_dir()
	CradleMode.profile = CradleMode.default_profile()
	CradleMode.profile["starseeds"] = 33.0
	_save(root.path_join("profile.save"), CradleMode.to_dict())
	_save(root.path_join("slot_0.save"), GameState.to_dict())
	SaveManager.migrate_to_profiles(root)
	SaveManager.set_profile(1)
	CradleMode.reload_for_profile()
	assert_almost_eq(CradleMode.starseeds(), 33.0, 0.001)
	assert_true(SaveManager.has_save(0))
	assert_eq(SaveManager.slot_path(0), root.path_join("p1/slot_0.save"))


# --- Isolation --------------------------------------------------------------------------------

func test_profiles_keep_their_own_worlds_and_heirlooms() -> void:
	CradleMode.profile["starseeds"] = 50.0
	(CradleMode.profile["heirlooms"] as Dictionary)["deep_hopper"] = 2
	CradleMode._add_world()
	assert_true(CradleMode.save_profile())
	GameState.flags["marker"] = "p1"
	assert_true(SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict()))
	# Profile 2 starts empty: just Verdance, no Heirlooms, no save.
	SaveManager.set_profile(2)
	CradleMode.reload_for_profile()
	assert_eq(CradleMode.worlds().size(), 1)
	assert_eq(CradleMode.heirloom_total(), 0)
	assert_eq(CradleMode.starseeds(), 0.0)
	assert_false(SaveManager.has_save(0), "profile 2 does not see profile 1's slot")
	CradleMode.profile["starseeds"] = 3.0
	CradleMode.save_profile()
	GameState.flags["marker"] = "p2"
	SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict())
	# Back to profile 1: as it was.
	SaveManager.set_profile(1)
	CradleMode.reload_for_profile()
	assert_eq(CradleMode.worlds().size(), 2)
	assert_eq(CradleMode.heirloom_level("deep_hopper"), 2)
	assert_almost_eq(CradleMode.starseeds(), 50.0, 0.001)
	assert_true(SaveManager.load_game())
	assert_eq(str(GameState.flags["marker"]), "p1")
	assert_eq(SaveManager.read_profile_choice(), 1, "the choice is remembered")
	SaveManager.set_profile(2)
	assert_eq(SaveManager.read_profile_choice(), 2)


func test_new_game_in_one_profile_leaves_the_others() -> void:
	CradleMode.profile["name"] = "Mira"
	CradleMode.profile["starseeds"] = 9.0
	CradleMode.save_profile()
	SaveManager.set_profile(2)
	CradleMode.reload_for_profile()
	CradleMode.profile["starseeds"] = 4.0
	CradleMode.save_profile()
	SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict())
	ProfilePicker.start_new_game()
	assert_eq(CradleMode.starseeds(), 0.0)
	assert_false(SaveManager.has_save(0))
	SaveManager.set_profile(1)
	CradleMode.reload_for_profile()
	assert_almost_eq(CradleMode.starseeds(), 9.0, 0.001)
	assert_eq(str(CradleMode.profile.get("name")), "Mira")


func test_delete_profile_erases_only_that_one() -> void:
	SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict())
	CradleMode.save_profile()
	SaveManager.set_profile(3)
	SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict())
	SaveManager.delete_profile(3)
	assert_false(SaveManager.has_save(0))
	assert_true(ProfileSlots.summary(3)["empty"])
	SaveManager.set_profile(1)
	assert_true(SaveManager.has_save(0))
	assert_false(ProfileSlots.summary(1)["empty"])


# --- Summaries, names -----------------------------------------------------------------------

func test_summary_from_profile_and_save() -> void:
	var prof: Dictionary = {"current": 1, "name": "Mira", "worlds": [
		{"name": "Verdance", "slot": 0, "stats": {"time_played": 3600.0}},
		{"name": "Quinaris", "slot": 1, "stats": {"time_played": 999999.0}}]}
	var ms: Array = Bloom.milestones()
	var done: Array = [str(ms[0]["id"])] if not ms.is_empty() else []
	var save: Dictionary = {"stats": {"time_played": 1800.0}, "flags": {"last_district": "Upton Ferry", "bloom_done": done}, "saved_unix": 77.0}
	var s: Dictionary = ProfileSlots.summary_from(prof, save, 1)
	assert_false(s["empty"])
	assert_eq(s["name"], "Mira")
	assert_almost_eq(float(s["time_s"]), 5400.0, 0.01, "archived worlds + the current save (not its stale archive)")
	assert_eq(int(s["worlds"]), 2)
	assert_eq(s["world"], "Quinaris")
	assert_eq(s["district"], "Upton Ferry")
	assert_eq(int(s["bloom_pct"]), int(round(100.0 / maxf(ms.size(), 1))))
	assert_true(ProfileSlots.summary_from({}, {}, 3)["empty"])
	assert_eq(ProfileSlots.summary_from({}, {}, 3)["name"], TranslationServer.translate("Profile %d") % 3)
	var lines: Array[String] = ProfilePicker.summary_text(s)
	assert_string_contains(lines[0], "Quinaris")
	assert_string_contains(lines[1], "Upton Ferry")


func test_rename() -> void:
	assert_eq(ProfileSlots.clean_name("  Mira's farm  "), "Mira's farm")
	assert_eq(ProfileSlots.clean_name("a\nb"), "a b")
	assert_eq(ProfileSlots.clean_name("x".repeat(60)).length(), ProfileSlots.NAME_MAX)
	assert_false(ProfileSlots.rename(2, "   "), "no empty names")
	assert_true(ProfileSlots.rename(2, "Second"))
	assert_eq(ProfileSlots.summary(2)["name"], "Second", "written to profile 2's file")
	assert_true(ProfileSlots.rename(1, "First"))
	assert_eq(str(CradleMode.profile["name"]), "First", "the active profile renames in memory too")
	CradleMode.reset_all()
	assert_eq(str(CradleMode.profile["name"]), "First", "New Game keeps the profile's name")


func test_picker_cards_and_focus_grid() -> void:
	CradleMode.save_profile()
	SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict())
	var p := ProfilePicker.new()
	add_child_autofree(p)
	assert_eq(p._grid.size(), SaveManager.PROFILES + 1, "three slots and Back")
	var row1: Array = p._grid[0]
	assert_eq(row1.size(), 4, "Continue / New / Rename / Delete")
	assert_eq((p._grid[1] as Array).size(), 2, "an empty slot: New / Rename")
	var b: Button = row1[3]
	assert_eq(b.get_node(b.focus_neighbor_bottom), (p._grid[1] as Array)[1], "down clamps to the row below")
	assert_eq(b.get_node(b.focus_neighbor_left), row1[2])


# --- Steam Cloud -----------------------------------------------------------------------------

class FakeCloud:
	extends Object
	var files: Dictionary = {}
	func isCloudEnabledForAccount() -> bool: return true
	func isCloudEnabledForApp() -> bool: return true
	func fileWrite(n: String, data: PackedByteArray, _size: int = 0) -> bool:
		files[n] = data
		return true
	func fileRead(n: String, _size: int) -> Dictionary: return {"ret": files.has(n), "buf": files.get(n, PackedByteArray())}
	func fileExists(n: String) -> bool: return files.has(n)
	func getFileSize(n: String) -> int: return (files.get(n, PackedByteArray()) as PackedByteArray).size()
	func getFileCount() -> int: return files.size()
	func getFileNameAndSize(i: int) -> Dictionary: return {"name": files.keys()[i], "size": 0}


func test_cloud_names_keep_profiles_apart() -> void:
	assert_eq(SteamCloud.cloud_name("user://saves/p2/slot_0.save"), "p2_slot_0.save")
	assert_eq(SteamCloud.cloud_name("user://saves/p1/profile.save"), "p1_profile.save")
	assert_eq(SteamCloud.cloud_name("user://saves/slot_0.save"), "slot_0.save")
	var fake := FakeCloud.new()
	var cloud := SteamCloud.new(fake)
	_save(SCRATCH.path_join("p1/slot_0.save"), {"saved_unix": 10.0, "flags": {"m": "one"}})
	_save(SCRATCH.path_join("p2/slot_0.save"), {"saved_unix": 20.0, "flags": {"m": "two"}})
	cloud.sync_dir(SCRATCH.path_join("p1"), "p1_")
	cloud.sync_dir(SCRATCH.path_join("p2"), "p2_")
	assert_true(fake.files.has("p1_slot_0.save") and fake.files.has("p2_slot_0.save"), "same slot, two profiles, two cloud files")
	assert_almost_eq(SteamCloud.saved_unix_of_bytes(fake.files["p1_slot_0.save"]), 10.0, 0.01)
	# A fresh PC pulls each profile back into its own folder.
	_wipe(SCRATCH)
	cloud.sync_dir(SCRATCH.path_join("p2"), "p2_")
	assert_eq(str(SaveManager.read_dict(SCRATCH.path_join("p2/slot_0.save"))["flags"]["m"]), "two")
	assert_false(FileAccess.file_exists(SCRATCH.path_join("p1/slot_0.save")))
	# Cloud saves from before profiles become profile 1's.
	fake.files = {}
	_save(SCRATCH.path_join("legacy/slot_0.save"), {"saved_unix": 30.0, "flags": {"m": "legacy"}})
	fake.files["slot_0.save"] = FileAccess.get_file_as_bytes(SCRATCH.path_join("legacy/slot_0.save"))
	assert_eq(cloud.adopt_legacy("p1_"), 1)
	assert_true(fake.files.has("p1_slot_0.save"))
	assert_eq(cloud.adopt_legacy("p1_"), 0, "once")
	fake.free()
