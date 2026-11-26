extends GutTest
## [v6flat] The one-time import of old flat-world saves (user://saves pN) into the round tree
## (SaveManager.import_flat_tree), on scratch folders. The imported save is still a flat save:
## the round game turns it into a globe save on load (OrbitMigrate, tests/test_orbit_migrate.gd).

const FLAT: String = "user://test_flat_import_flat"
const ROUND: String = "user://test_flat_import_flat_round"
const FIXTURE: String = "res://tests/fixtures/flat_v4_oldtown.save"


func before_each() -> void:
	_wipe(FLAT)
	_wipe(ROUND)


func after_each() -> void:
	_wipe(FLAT)
	_wipe(ROUND)


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _put(path: String, src: String = FIXTURE) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(DirAccess.copy_absolute(ProjectSettings.globalize_path(src), path), OK)


func _put_dict(path: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_true(SaveManager.write_dict(path, d))


func test_flat_profile_copies_into_an_empty_round_profile() -> void:
	_put(FLAT.path_join("p1/slot_0.save"))
	_put_dict(FLAT.path_join("p1/profile.save"), {"heirlooms": ["x"]})
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 2)
	var dst: String = ROUND.path_join("p1/slot_0.save")
	assert_true(FileAccess.file_exists(dst))
	assert_eq(FileAccess.get_file_as_bytes(dst), FileAccess.get_file_as_bytes(FIXTURE), "a byte-for-byte copy")
	assert_true(FileAccess.file_exists(ROUND.path_join("p1/profile.save")), "the Cradle profile comes too")
	assert_true(FileAccess.file_exists(FLAT.path_join("p1/slot_0.save")), "the flat file stays")
	assert_true(FileAccess.file_exists(ROUND.path_join(SaveManager.FLAT_IMPORT_MARKER)), "marker written")
	# The copy is a flat save the globe can take on load.
	var d: Dictionary = SaveManager.read_dict(dst)
	assert_false(d.is_empty(), "readable")
	assert_eq(int((d.get("planet_state", {}) as Dictionary).get("level", -1)), OrbitMigrate.FROM_LEVEL, "flat survey, migrated on load")
	assert_true((d.get("orbit", {}) as Dictionary).is_empty(), "no globe in it yet")


func test_runs_once() -> void:
	_put(FLAT.path_join("p1/slot_0.save"))
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 1)
	DirAccess.remove_absolute(ROUND.path_join("p1/slot_0.save"))
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 0, "the marker stops a second import")
	assert_false(FileAccess.file_exists(ROUND.path_join("p1/slot_0.save")))


func test_never_overwrites_a_round_profile_in_use() -> void:
	_put(FLAT.path_join("p1/slot_0.save"))
	_put(FLAT.path_join("p2/slot_0.save"))
	_put_dict(ROUND.path_join("p2/slot_1.save"), {"round": true})
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 1, "only p1")
	assert_false(FileAccess.file_exists(ROUND.path_join("p2/slot_0.save")), "p2 had a round save: untouched")
	assert_true(bool(SaveManager.read_dict(ROUND.path_join("p2/slot_1.save")).get("round", false)))
	assert_true(FileAccess.file_exists(FLAT.path_join("p2/slot_0.save")))


func test_pre_profile_saves_count_as_profile_one() -> void:
	_put(FLAT.path_join("slot_0.save"))
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 1)
	assert_true(FileAccess.file_exists(ROUND.path_join("p1/slot_0.save")))
	assert_true(FileAccess.file_exists(FLAT.path_join("slot_0.save")), "not moved in the flat tree")
	assert_false(DirAccess.dir_exists_absolute(FLAT.path_join("p1")))


func test_no_flat_saves_leaves_no_marker() -> void:
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 0, "no flat tree")
	DirAccess.make_dir_recursive_absolute(FLAT.path_join("p1"))
	assert_eq(SaveManager.import_flat_tree(FLAT, ROUND), 0, "an empty flat tree")
	assert_false(FileAccess.file_exists(ROUND.path_join(SaveManager.FLAT_IMPORT_MARKER)), "Steam Cloud may still bring old saves down")


func test_round_cloud_names_for_imported_saves() -> void:
	assert_true(SteamCloud.cloud_name("user://saves_round/p1/slot_0.save").begins_with(SteamCloud.ROUND_PREFIX), "an imported save syncs under r_")
	assert_eq(SteamCloud.cloud_name("user://saves/p1/slot_0.save"), "p1_slot_0.save", "the flat original keeps its name")
