extends GutTest
## [orbB] The title screen's "Round planets (preview)": its own save tree, the globe on New Game /
## Continue, and nothing of it reaches the flat game's saves or Steam Cloud.

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


func test_preview_starts_on_the_globe() -> void:
	Settings.round_planets = false
	assert_eq(SliceOrbit.wanted(), DevHooks.has("orbit") and not DevHooks.get_s("orbit", "") in ["v1", "globe"])
	if DevHooks.has("orbit"):
		return
	Settings.round_planets = true
	assert_true(SliceOrbit.wanted(), "New Game / Continue build the slice on the globe")


func test_preview_never_reaches_steam_cloud() -> void:
	Settings.round_planets = true
	assert_true(SteamService._round_preview(SaveManager.slot_path()))
	assert_true(SteamService._round_preview(CradleMode.profile_path()))
	Settings.round_planets = false
	assert_false(SteamService._round_preview(SaveManager.slot_path()), "flat saves sync as before")
