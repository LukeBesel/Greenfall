extends GutTest
## [orbB] The round world: its own save tree, the globe on New Game / Continue, and nothing of it
## reaches the flat game's saves or Steam Cloud. [v1menu] It is the default now (no title toggle).

var _was: bool


func before_each() -> void:
	_was = Settings.round_planets


func after_each() -> void:
	Settings.round_planets = _was  # (never saved: the setting file stays as it was)


func test_preview_saves_live_apart() -> void:
	Settings.round_planets = false
	var flat_root: String = SaveManager.root_dir()
	var flat_slot: String = SaveManager.slot_path()
	Settings.round_planets = true
	assert_eq(SaveManager.root_dir(), flat_root + SaveManager.ROUND_SUFFIX, "its own tree")
	assert_ne(SaveManager.slot_path(), flat_slot, "never the flat slot")
	assert_true(SaveManager.slot_path().begins_with(flat_root + SaveManager.ROUND_SUFFIX + "/"))
	assert_true(CradleMode.profile_path().begins_with(flat_root + SaveManager.ROUND_SUFFIX + "/"), "the Cradle profile too")
	assert_eq(SaveManager.root_dir(true), flat_root, "the flat tree is still reachable (Steam Cloud sync)")
	assert_eq(SaveManager.profile_dir(1, true), flat_root.path_join("p1"))


func test_round_is_the_default() -> void:
	var fresh: Node = load("res://autoload/Settings.gd").new()
	assert_true(fresh.round_planets, "a first run starts round")
	fresh.free()
	if not "--flat" in OS.get_cmdline_user_args():
		assert_true(SaveManager.round_planets(), "no toggle: round unless the dev hook --flat")
		assert_true(SaveManager.root_dir().ends_with(SaveManager.ROUND_SUFFIX), "saves go to the round tree")


func test_old_preview_off_setting_is_ignored() -> void:
	var src: String = FileAccess.get_file_as_string("res://autoload/Settings.gd")
	assert_false(src.contains("get_value(\"preview\", \"round_planets\""), "an old settings file's round_planets=false is never read back")


func test_preview_starts_on_the_globe() -> void:
	Settings.round_planets = false
	assert_eq(SliceOrbit.wanted(), DevHooks.has("orbit") and not DevHooks.get_s("orbit", "") in ["v1", "globe"])
	if DevHooks.has("orbit"):
		return
	Settings.round_planets = true
	assert_true(SliceOrbit.wanted(), "New Game / Continue build the slice on the globe")


func test_round_saves_have_their_own_cloud_names() -> void:  # [v5load] the round world syncs to Steam Cloud now
	Settings.round_planets = true
	assert_true(SteamCloud.cloud_name(SaveManager.slot_path()).begins_with(SteamCloud.ROUND_PREFIX + "p"))
	assert_true(SteamCloud.cloud_name(CradleMode.profile_path()).begins_with(SteamCloud.ROUND_PREFIX + "p"))
	Settings.round_planets = false
	assert_true(SteamCloud.cloud_name(SaveManager.slot_path()).begins_with("p"), "flat saves keep their names")
