extends GutTest

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary
var _districts: Dictionary

const KNOWN_TYPES: Array[String] = ["stat", "junk_kg", "cubes_earned", "flag", "research", "research_id", "codex", "hub_level", "currency", "achievements", "list"]


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	_districts = GameState.districts
	GameState.flags = {}
	GameState.currencies = {}
	GameState.stats = {"junk_removed": {}, "cubes_earned_total": [0.0, 0]}
	GameState.world = {}
	GameState.districts = {0: GameState.world}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world
	GameState.districts = _districts


func test_definitions() -> void:
	var defs: Array = Achievements.defs()
	assert_gte(defs.size(), 40, "40+ achievements")
	var seen: Dictionary = {}
	for a: Dictionary in defs:
		assert_false(seen.has(a["id"]), "unique id %s" % a["id"])
		seen[a["id"]] = true
		assert_true(str(a.get("name", "")) != "" and str(a.get("desc", "")) != "", "%s has text" % a["id"])
		var c: Dictionary = a["cond"]
		assert_has(KNOWN_TYPES, str(c["type"]), "%s condition type" % a["id"])
		if str(c["type"]) == "research_id":
			assert_true(Research.exists(str(c["key"])), "%s research id exists" % a["id"])


func test_nothing_unlocked_on_a_fresh_game() -> void:
	assert_eq(Achievements.check_all(), [] as Array[String])
	assert_eq(Achievements.unlocked_count(), 0)


func test_stat_achievements_unlock_and_progress() -> void:
	GameState.stats["hexes_cleaned"] = 1
	var got: Array[String] = Achievements.check_all(5.0)
	assert_has(got, "hex_1")
	assert_does_not_have(got, "hex_10")
	assert_true(Achievements.is_unlocked("hex_1"))
	assert_almost_eq(Achievements.progress("hex_10"), 0.1, 0.001)
	assert_eq(float(Achievements.unlocked_map()["hex_1"]), 5.0)
	assert_eq(Achievements.check_all(), [] as Array[String], "no double unlocks")


func test_junk_kg_uses_codex_weights() -> void:
	GameState.add_junk_removed("metal", 100.0)
	var kg: float = 100.0 * Codex.kg_per_unit("metal")
	assert_almost_eq(Codex.junk_kg("metal"), kg, 0.001)
	assert_almost_eq(Codex.junk_kg("*"), kg, 0.001)
	var got: Array[String] = Achievements.check_all()
	assert_has(got, "first_scoop")
	assert_eq(Achievements.is_unlocked("kg_metal"), kg >= 500.0)


func test_research_and_meta_achievements() -> void:
	Research.grant("scoop_beam")
	Research.grant("tractor_beam")
	var got: Array[String] = Achievements.check_all()
	assert_has(got, "research_1")
	assert_has(got, "tractor")
	assert_false(Achievements.is_unlocked("ach_25"))
	for id: String in ["hexes_cleaned", "cubes_made", "perfect_cubes", "pure_cubes", "lumpy_cubes", "upgrades_bought", "robots_built", "plants_planted", "plants_bloomed", "hexes_restored", "shards_found", "parts_found", "distance_m", "time_played", "air_filtered", "data_earned"]:
		GameState.stats[id] = 1.0e6
	Achievements.check_all()
	assert_true(Achievements.is_unlocked("ach_25"), "meta achievement in the same check")


func test_hub_level_reads_all_districts() -> void:
	GameState.districts[3] = {"hub_level": 5}
	assert_eq(Achievements.best_hub_level(), 5)
	assert_has(Achievements.check_all(), "hub_5")


func test_unlocks_persist_through_save() -> void:
	GameState.stats["hexes_cleaned"] = 10
	Achievements.check_all()
	Codex.unlock("junk:metal")
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	assert_true((d["flags"]["achievements"] as Dictionary).has("hex_10"))
	assert_has(d["flags"]["codex"], "junk:metal")


func test_live_node_toasts_and_tracks_restored() -> void:
	var n := Achievements.new()
	add_child_autofree(n)
	watch_signals(EventBus)
	EventBus.hex_restored.emit(4)
	assert_eq(float(GameState.stats["hexes_restored"]), 1.0)
	n._process(1.5)
	assert_signal_emitted_with_parameters(EventBus, "achievement_unlocked", ["restored_1"])
	assert_signal_emitted(EventBus, "toast")


func test_codex_entries_and_scan() -> void:
	var entries: Array[Dictionary] = Codex.entries()
	assert_eq(Codex.total("junk"), Economy.junk_ids.size())
	assert_eq(Codex.total("robots"), Economy.robot_order.size())
	assert_gte(entries.size(), 40)
	for e: Dictionary in entries:
		assert_true(str(e["desc"]) != "", "%s has a description" % e["key"])
	assert_eq(Codex.count(), 0)
	GameState.add_junk_removed("glass", 1.0)
	GameState.flags["shards_found"] = ["receipt"]
	var found: Array[String] = Codex.scan()
	assert_has(found, "junk:glass")
	assert_has(found, "shards:receipt")
	assert_eq(Codex.count("junk"), 1)
	assert_false(Codex.unlock("junk:glass"), "already unlocked")
	assert_false(Codex.unlock("junk:nope"), "unknown key")


func test_screen_builds_every_tab() -> void:
	var s := CodexScreen.new()
	add_child_autofree(s)
	for t: String in ["codex", "achievements", "stats"]:
		s.open_screen(t)
		assert_true(s.is_open)
		s.close_screen()
	assert_false(s.is_open)


func after_all() -> void:
	# The screen test builds the shared UI theme; drop the cached statics so nothing leaks at exit.
	UITheme._theme = null
	UITheme._font = null
	# Unlock chimes may still be playing; stop them so their playbacks don't outlive the run.
	for p: AudioStreamPlayer in Audio._players:
		p.stop()
