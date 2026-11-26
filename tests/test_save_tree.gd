extends GutTest
## [v6flat] The game's one save tree (the round world's, user://saves_round) and its Steam Cloud
## names. The flat game's tree (user://saves) is only ever read (old-save import, cloud sync down).


func test_saves_go_to_the_round_tree() -> void:
	assert_true(SaveManager.root_dir().ends_with(SaveManager.ROUND_SUFFIX), "the game's saves")
	assert_true(SaveManager.slot_path().begins_with(SaveManager.root_dir() + "/"))
	assert_true(CradleMode.profile_path().begins_with(SaveManager.root_dir() + "/"), "the Cradle profile too")
	assert_eq(SaveManager.profile_dir(2), SaveManager.root_dir().path_join("p2"))


func test_the_old_flat_tree_is_apart() -> void:
	assert_eq(SaveManager.root_dir(), SaveManager.old_flat_root() + SaveManager.ROUND_SUFFIX)
	assert_eq(SaveManager.old_flat_profile_dir(1), SaveManager.old_flat_root().path_join("p1"))
	assert_false(SaveManager.slot_path().begins_with(SaveManager.old_flat_root() + "/"), "never a flat slot")


func test_saves_have_round_cloud_names() -> void:  # [v5load]
	assert_true(SteamCloud.cloud_name(SaveManager.slot_path()).begins_with(SteamCloud.ROUND_PREFIX + "p"))
	assert_true(SteamCloud.cloud_name(CradleMode.profile_path()).begins_with(SteamCloud.ROUND_PREFIX + "p"))
	assert_true(SteamCloud.cloud_name(SaveManager.old_flat_profile_dir(1).path_join("slot_0.save")).begins_with("p1_"), "old flat cloud saves keep their names")


func test_no_mode_switch_is_left() -> void:
	assert_false("round_planets" in Settings, "the preview setting is gone")
	assert_false(SaveManager.has_method("round_planets"))
	assert_false(FileAccess.get_file_as_string("res://autoload/SaveManager.gd").contains("\"--flat\""), "no --flat hook")
