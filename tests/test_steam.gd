extends GutTest
## Steam integration (fake Steam API), cloud conflict rule, demo limits.

const TMP_DIR: String = "user://test_steam_cloud"


## Stand-in for the GodotSteam singleton: records calls, keeps achievements, stats and cloud files.
class FakeSteam:
	extends Object
	var achievements: Dictionary = {}
	var stats: Dictionary = {}
	var stored: int = 0
	var files: Dictionary = {}
	var cloud_on: bool = true
	var overlay_app: int = -1

	func isSteamRunning() -> bool: return true
	func steamInitEx(_app_id: int, _embed: bool) -> Dictionary: return {"status": 0, "verbal": "ok"}
	func run_callbacks() -> void: pass
	func setAchievement(n: String) -> bool:
		achievements[n] = true
		return true
	func getAchievement(n: String) -> Dictionary: return {"ret": true, "achieved": achievements.has(n)}
	func setStatInt(n: String, v: int) -> bool:
		stats[n] = v
		return true
	func setStatFloat(n: String, v: float) -> bool:
		stats[n] = v
		return true
	func storeStats() -> bool:
		stored += 1
		return true
	func isCloudEnabledForAccount() -> bool: return cloud_on
	func isCloudEnabledForApp() -> bool: return cloud_on
	func fileWrite(n: String, data: PackedByteArray, _size: int = 0) -> bool:
		files[n] = data
		return true
	func fileRead(n: String, _size: int) -> Dictionary: return {"ret": files.has(n), "buf": files.get(n, PackedByteArray())}
	func fileExists(n: String) -> bool: return files.has(n)
	func getFileSize(n: String) -> int: return (files.get(n, PackedByteArray()) as PackedByteArray).size()
	func fileDelete(n: String) -> bool: return files.erase(n)
	func getFileCount() -> int: return files.size()
	func getFileNameAndSize(i: int) -> Dictionary: return {"name": files.keys()[i], "size": 0}
	func activateGameOverlayToStore(app: int, _flag: int) -> void: overlay_app = app


var _fake: FakeSteam
var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _world: Dictionary


func before_each() -> void:
	_fake = FakeSteam.new()
	_fake.cloud_on = false  # never touch the real save folder from SteamService.attach
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	_world = GameState.world
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {}
	GameState.world = {}


func after_each() -> void:
	SteamService.detach()
	Demo.override = -1
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	GameState.world = _world
	_fake.free()
	if DirAccess.dir_exists_absolute(TMP_DIR):
		for f: String in DirAccess.get_files_at(TMP_DIR):
			DirAccess.remove_absolute(TMP_DIR.path_join(f))
		DirAccess.remove_absolute(TMP_DIR)


func test_headless_runs_without_steam() -> void:
	# The autoload never starts Steam in tests / CI (no extension, headless).
	assert_ne(SteamService.skip_reason(), "", "headless run skips Steam")
	assert_false(SteamService.active)
	SteamService.store_now()  # no-ops without Steam
	SteamService.push_stats()
	SteamService.on_saved("user://nothing.save")
	assert_true(SteamService.store_url().begins_with("https://store.steampowered.com/app/"))


func test_achievement_unlock_is_mirrored_and_stored() -> void:
	assert_true(SteamService.attach(_fake, true))
	assert_true(SteamService.active)
	EventBus.achievement_unlocked.emit("first_scoop")
	assert_true(_fake.achievements.has("FIRST_SCOOP"))
	SteamService.store_now()
	assert_gt(_fake.stored, 0)


func test_existing_unlocks_sync_on_load() -> void:
	GameState.flags["achievements"] = {"hex_1": 1.0, "cube_1": 2.0}
	SteamService.attach(_fake, false)
	assert_true(_fake.achievements.has("HEX_1"))
	assert_true(_fake.achievements.has("CUBE_1"))


func test_stats_mapping() -> void:
	GameState.stats = {"hexes_cleaned": 12.0, "distance_m": 345.5, "time_played": 600.0}
	SteamService.attach(_fake, false)
	SteamService.push_stats()
	assert_eq(_fake.stats.get("HEXES_CLEANED"), 12)
	assert_almost_eq(float(_fake.stats.get("DISTANCE_M", 0.0)), 345.5, 0.01)
	assert_eq(_fake.stats.get("MINUTES_PLAYED"), 10)
	assert_eq(_fake.stats.get("ROBOTS_BUILT"), 0)


func test_every_achievement_has_a_valid_api_name() -> void:
	var seen: Dictionary = {}
	var re := RegEx.create_from_string("^[A-Z0-9_]+$")
	for a: Dictionary in Achievements.defs():
		var n: String = SteamService.api_name(str(a["id"]))
		assert_not_null(re.search(n), n)
		assert_false(seen.has(n), "unique " + n)
		seen[n] = true


func test_store_page_uses_overlay_when_active() -> void:
	SteamService.attach(_fake, false)
	SteamService.open_store_page()
	assert_eq(_fake.overlay_app, SteamService.store_app_id())


func test_cloud_conflict_rule() -> void:
	assert_eq(SteamCloud.pick_newer(false, 0, false, 0), "none")
	assert_eq(SteamCloud.pick_newer(true, 100, false, 0), "local")
	assert_eq(SteamCloud.pick_newer(false, 0, true, 100), "cloud")
	assert_eq(SteamCloud.pick_newer(true, 100, true, 200), "cloud")
	assert_eq(SteamCloud.pick_newer(true, 300, true, 200), "local")
	assert_eq(SteamCloud.pick_newer(true, 200, true, 200), "local", "tie keeps local")


func _write_save(path: String, saved: float, marker: String) -> void:
	assert_true(SaveManager.write_dict(path, {"version": 1, "saved_unix": saved, "flags": {"m": marker}}))


func test_cloud_sync_newest_wins() -> void:
	_fake.cloud_on = true
	var cloud := SteamCloud.new(_fake)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	# Slot 0: cloud is newer -> local replaced (old local kept as .local_bak).
	_write_save(TMP_DIR.path_join("slot_0.save"), 2000.0, "cloud")
	assert_true(cloud.push(TMP_DIR.path_join("slot_0.save")))
	_write_save(TMP_DIR.path_join("slot_0.save"), 1000.0, "local-old")
	# Slot 1: local only -> uploaded.
	_write_save(TMP_DIR.path_join("slot_1.save"), 1500.0, "local-only")
	var res: Dictionary = cloud.sync_dir(TMP_DIR)
	assert_eq(res.get("slot_0.save"), "cloud")
	assert_eq(res.get("slot_1.save"), "local")
	assert_eq(str(SaveManager.read_dict(TMP_DIR.path_join("slot_0.save"))["flags"]["m"]), "cloud")
	assert_true(FileAccess.file_exists(TMP_DIR.path_join("slot_0.save.local_bak")))
	assert_true(_fake.files.has("slot_1.save"))
	# Local newer than cloud -> pushed up, local untouched.
	_write_save(TMP_DIR.path_join("slot_0.save"), 3000.0, "local-new")
	res = cloud.sync_dir(TMP_DIR)
	assert_eq(res.get("slot_0.save"), "local")
	assert_almost_eq(SteamCloud.saved_unix_of_bytes(_fake.files["slot_0.save"]), 3000.0, 0.01)


## [v5load] The round world's saves (user://saves_round/pN) sync under their own cloud prefix.
func test_cloud_names_for_round_saves() -> void:
	assert_eq(SteamCloud.cloud_name("user://saves/p2/slot_0.save"), "p2_slot_0.save")
	assert_eq(SteamCloud.cloud_name("user://saves_round/p2/slot_0.save"), "r_p2_slot_0.save")
	assert_eq(SteamCloud.cloud_name("user://saves_round/p1/profile.save"), "r_p1_profile.save")
	assert_eq(SteamCloud.cloud_name("user://saves_demo_round/p3/slot_4.save"), "r_p3_slot_4.save")
	assert_eq(SteamCloud.profile_prefix(2, true), "r_p2_")
	assert_eq(SteamCloud.profile_prefix(2, false), "p2_")


func test_round_and_flat_saves_sync_apart() -> void:
	_fake.cloud_on = true
	var cloud := SteamCloud.new(_fake)
	var flat: String = TMP_DIR.path_join("p1")
	var rnd: String = TMP_DIR + SaveManager.ROUND_SUFFIX
	var rnd_p1: String = rnd.path_join("p1")
	DirAccess.make_dir_recursive_absolute(flat)
	DirAccess.make_dir_recursive_absolute(rnd_p1)
	_write_save(flat.path_join("slot_0.save"), 1000.0, "flat")
	_write_save(rnd_p1.path_join("slot_0.save"), 2000.0, "round")
	# What SaveManager.save_game does through SteamService.on_saved: each lands under its own name.
	assert_true(cloud.push(flat.path_join("slot_0.save")))
	assert_true(cloud.push(rnd_p1.path_join("slot_0.save")))
	assert_true(_fake.files.has("p1_slot_0.save"))
	assert_true(_fake.files.has("r_p1_slot_0.save"))
	assert_almost_eq(SteamCloud.saved_unix_of_bytes(_fake.files["p1_slot_0.save"]), 1000.0, 0.01, "the round save did not overwrite the flat one")
	# A new install: the round save comes down into the round tree, the flat one into the flat tree.
	DirAccess.remove_absolute(flat.path_join("slot_0.save"))
	DirAccess.remove_absolute(rnd_p1.path_join("slot_0.save"))
	assert_eq(cloud.sync_dir(rnd_p1, SteamCloud.profile_prefix(1, true)).get("slot_0.save"), "cloud")
	assert_eq(cloud.sync_dir(flat, SteamCloud.profile_prefix(1, false)).get("slot_0.save"), "cloud")
	assert_eq(str(SaveManager.read_dict(rnd_p1.path_join("slot_0.save"))["flags"]["m"]), "round")
	assert_eq(str(SaveManager.read_dict(flat.path_join("slot_0.save"))["flags"]["m"]), "flat")
	# Round saves are never mistaken for pre-profile flat saves.
	assert_eq(cloud.adopt_legacy("p1_"), 0)
	assert_false(_fake.files.has("p1_r_p1_slot_0.save"))
	# The service uploads a round save when it is written, and deletes it with the slot.
	_fake.cloud_on = false  # attach must not sync the real save folder
	SteamService.attach(_fake, false)
	_fake.cloud_on = true
	_fake.files.clear()
	SteamService.on_saved(rnd_p1.path_join("slot_0.save"))
	assert_true(_fake.files.has("r_p1_slot_0.save"), "round saves reach the cloud")
	SteamService.on_deleted(rnd_p1.path_join("slot_0.save"))
	assert_false(_fake.files.has("r_p1_slot_0.save"))
	for d: String in [flat, rnd_p1]:
		for f: String in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)
	DirAccess.remove_absolute(rnd)


func test_cloud_disabled_does_nothing() -> void:
	var cloud := SteamCloud.new(_fake)
	assert_false(cloud.enabled())
	assert_true(cloud.sync_dir(TMP_DIR).is_empty())


func test_demo_flag_and_limits() -> void:
	Demo.override = 0
	assert_false(Demo.is_demo())
	assert_true(Demo.can_raise_base(4))
	assert_true(Demo.rockets_allowed())
	assert_false(Demo.block("rocket"))
	var sfx: String = SaveManager.ROUND_SUFFIX
	assert_eq(SaveManager.root_dir(), SaveManager.SAVE_DIR + sfx)  # [worlds2] profiles live under it
	Demo.override = 1
	assert_true(Demo.is_demo())
	assert_true(Demo.can_raise_base(1))
	assert_false(Demo.can_raise_base(Demo.MAX_BASE_LEVEL))
	assert_false(Demo.rockets_allowed())
	assert_eq(SaveManager.root_dir(), Demo.SAVE_DIR + sfx)
	assert_eq(SaveManager.old_flat_root(), Demo.SAVE_DIR, "the old flat tree")


func test_demo_caps_the_base() -> void:
	Demo.override = 1
	var hub := Hub.new()
	add_child_autofree(hub)
	GameState.add_currency("cubes", BigNum.from_float(1e9))
	for l: int in range(2, 6):
		for k: String in hub.level_def(l).get("cost", {}):
			GameState.add_currency(k, BigNum.from_float(1e9))
	assert_true(hub.upgrade(), "level 1 -> 2 is in the demo")
	assert_eq(hub.level, Demo.MAX_BASE_LEVEL)
	assert_true(hub.demo_finished(), "can pay for level 3: the demo is finished")
	assert_false(hub.upgrade(), "level 3 is full game only")
	assert_eq(hub.level, Demo.MAX_BASE_LEVEL)
	assert_true(GameState.flags.get("demo_end_seen", false), "end-of-demo shown")
	Demo.override = 0
	assert_true(hub.upgrade(), "full game keeps going")
	assert_eq(hub.level, 3)
