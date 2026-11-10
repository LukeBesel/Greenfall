extends GutTest
## [orbB] The globe's save tree: the game's only one, and none of it reaches Steam Cloud.


func test_one_save_tree() -> void:
	var legacy: String = SaveManager.legacy_flat_root()
	assert_eq(SaveManager.root_dir(), legacy + SaveManager.ROUND_SUFFIX, "the globe's tree (existing saves keep loading)")
	assert_true(SaveManager.slot_path().begins_with(legacy + SaveManager.ROUND_SUFFIX + "/"))
	assert_true(CradleMode.profile_path().begins_with(legacy + SaveManager.ROUND_SUFFIX + "/"), "the Cradle profile too")
	assert_eq(SaveManager.legacy_flat_profile_dir(1), legacy.path_join("p1"), "the pre-globe tree is still reachable (Steam Cloud sync)")


func test_no_round_planets_switch_left() -> void:
	var src: String = FileAccess.get_file_as_string("res://autoload/Settings.gd")
	assert_false(src.contains("round_planets"), "no flat/round toggle in the settings")
	assert_false(SaveManager.has_method("round_planets"), "no flat/round switch in the save manager")


func test_globe_saves_never_reach_steam_cloud() -> void:
	assert_true(SteamService._round_preview(SaveManager.slot_path()))
	assert_true(SteamService._round_preview(CradleMode.profile_path()))
	assert_false(SteamService._round_preview(SaveManager.legacy_flat_profile_dir(1).path_join("slot_1.save")), "the pre-globe tree syncs as before")
