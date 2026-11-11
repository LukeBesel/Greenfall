extends GutTest
## [extras] Radio unlocks and the music override, the nursery's retire rules and garden bonus,
## album milestones, offline garden growth and the welcome-back summary, and Seed of the Week
## (ISO weeks, same seed for everyone, twists, score, one paint chip per week, decor gating).

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary
var _districts: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	_districts = GameState.districts
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	WeeklyChallenge.path_override = "user://test_weekly.save"
	DirAccess.remove_absolute(WeeklyChallenge.path_override)
	WeeklyChallenge.reset_cache()
	WeeklyChallenge.now_override = -1.0
	WeeklyChallenge.enabled_override = 1  # [v6screens] these tests cover the mode itself


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world
	GameState.districts = _districts
	WeeklyChallenge.active = false
	WeeklyChallenge.enabled_override = -1
	WeeklyChallenge.now_override = -1.0
	DirAccess.remove_absolute(WeeklyChallenge.path_override)
	WeeklyChallenge.path_override = ""
	WeeklyChallenge.reset_cache()
	Audio.stop_track()


# --- Radio ----------------------------------------------------------------------------------

func test_every_song_is_a_track_the_score_knows() -> void:
	var ids: Array[String] = Audio.music_track_ids()
	assert_gte(Radio.songs().size(), 10)
	for s: Dictionary in Radio.songs():
		assert_has(ids, str(s["id"]))
		assert_ne(Radio.title(str(s["id"])), str(s["id"]), "has a title")


func test_songs_unlock_with_progress() -> void:
	assert_true(Radio.is_unlocked("verdance_sprout"), "starter song is on from the start")
	assert_false(Radio.is_unlocked("verdance_sweep"))
	assert_false(Radio.play("verdance_sweep"), "locked songs don't play")
	GameState.stats["hexes_cleaned"] = 12.0
	assert_has(Radio.check_unlocks(), "verdance_sweep")
	assert_true(Radio.check_unlocks().is_empty(), "each song unlocks once")
	Radio.note_planet("ochre", 1)
	var got: Array[String] = Radio.check_unlocks()
	assert_has(got, "ochre_sunbaked", "landing on a planet unlocks its first track")
	assert_false(got.has("ochre_caravan"))
	Radio.note_planet("ochre", 5)
	got = Radio.check_unlocks()
	assert_has(got, "ochre_caravan")
	assert_has(got, "ochre_mirage", "restoring a base there unlocks the rest")
	Radio.note_planet("ochre", 2)
	assert_eq(int(Radio.planets()["ochre"]), 5, "the best level is kept")


func test_playing_a_song_holds_until_reset() -> void:
	assert_true(Radio.play("verdance_sprout"))
	assert_eq(Radio.playing(), "verdance_sprout")
	Radio.play("")
	assert_eq(Radio.playing(), "")


# --- Nursery --------------------------------------------------------------------------------

func test_garden_bonus_is_small_and_capped() -> void:
	assert_almost_eq(Nursery.stat_mult("plant_growth"), 1.0, 0.0001)
	for i: int in 3:
		Nursery.list().append({"name": "Bot-%d" % i})
	assert_almost_eq(Nursery.stat_mult("plant_growth"), 1.03, 0.0001)
	assert_almost_eq(Nursery.stat_mult("scoop_rate"), 1.0, 0.0001, "only plant growth")
	for i: int in 20:
		Nursery.list().append({"name": "More-%d" % i})
	assert_almost_eq(Nursery.stat_mult("plant_growth"), 1.0 + Nursery.BONUS_CAP, 0.0001)


func test_only_old_or_low_tier_robots_retire() -> void:
	var r := Robot.new()
	r.robot_name = "Test-01"
	r.tier = 0
	assert_ne(Nursery.retire_block_reason(r), "", "[camp] no nursery built here yet")
	YardBuilds.mark_built("nursery")
	assert_eq(Nursery.retire_block_reason(r), "", "Mk I can retire")
	r.tier = 3
	GameState.stats["time_played"] = 100.0
	Nursery.service()["Test-01"] = 50.0
	assert_ne(Nursery.retire_block_reason(r), "", "a new Mk IV can't")
	GameState.stats["time_played"] = 50.0 + Nursery.OLD_S + 1.0
	assert_eq(Nursery.retire_block_reason(r), "", "after an hour in service it can")
	assert_gt(Nursery.refund_for(3), Nursery.refund_for(0))
	r.free()


# --- Album ----------------------------------------------------------------------------------

func test_album_milestones() -> void:
	assert_eq(PhotoAlbum.reached(0.2, 0.0, 1), [] as Array[String])
	assert_eq(PhotoAlbum.reached(0.6, 0.3, 5), ["m50", "thriving", "base5"] as Array[String])
	var e: Dictionary = PhotoAlbum.entry(3)
	e["before"] = "user://x_before.jpg"
	assert_eq(PhotoAlbum.districts(), [3] as Array[int])
	assert_eq(PhotoAlbum.latest_after(3), "")
	e["m50"] = "user://x_m50.jpg"
	e["base5"] = "user://x_b5.jpg"
	assert_eq(PhotoAlbum.latest_after(3), "base5")
	assert_eq(PhotoAlbum.shots_taken(), 3)
	assert_true(PhotoAlbum.dir().begins_with("user://"))


# --- Welcome back ---------------------------------------------------------------------------

func _garden(n: int) -> Garden:
	var g := Garden.new()
	g.species = [{"grow_s": 40, "seed_yield": 1.0}]
	g.slot_species.resize(n)
	g.slot_stage.resize(n)
	g.slot_progress.resize(n)
	g.slot_water.resize(n)
	g.slot_hex.resize(n)
	for i: int in n:
		g.slot_species[i] = 0
		g.slot_stage[i] = 0
		g.slot_progress[i] = 0.0
		g.slot_water[i] = 0.0
		g.slot_hex[i] = i
	return g


func test_garden_grows_offline_once() -> void:
	var g: Garden = _garden(4)
	var dry: Dictionary = WelcomeBack.grow_garden(g, 3600.0, false)
	assert_eq(int(dry["grew"]), 0, "dry plants don't grow without a waterer")
	var wet: Dictionary = WelcomeBack.grow_garden(g, 3600.0, true)
	assert_eq(int(wet["grew"]), 4)
	assert_eq(int(wet["bloomed"]), 4)
	assert_almost_eq(float(wet["seeds"]), 4.0, 0.001)
	var again: Dictionary = WelcomeBack.grow_garden(g, 3600.0, true)
	assert_eq(int(again["bloomed"]), 0, "a bloomed plant can't be farmed by reopening the game")
	g.free()


func test_watered_slots_grow_for_their_water_only() -> void:
	var g: Garden = _garden(1)
	g.slot_water[0] = 40.0
	var r: Dictionary = WelcomeBack.grow_garden(g, 3600.0, false)
	assert_eq(int(r["bloomed"]), 0)
	assert_gt(g.slot_progress[0] + float(g.slot_stage[0]), 0.0, "it grew while the water lasted")
	assert_eq(g.slot_water[0], 0.0)
	g.free()


func test_summary_rows_and_cap() -> void:
	var bots: Array = [{"type": "scoopie", "tier": 0}, {"type": "scoopie", "tier": 0}, {"type": "haulbug", "tier": 0}]
	var res: Dictionary = Offline.compute(bots, 1, 1.0, 20.0 * 3600.0, 300.0)
	res["away_raw"] = 20.0 * 3600.0
	var s: Dictionary = WelcomeBack.build_summary(res, {"grew": 5, "bloomed": 2, "seeds": 3.0}, bots)
	var kinds: Array = (s["rows"] as Array).map(func(r: Dictionary) -> String: return str(r["kind"]))
	assert_has(kinds, "robots")
	assert_has(kinds, "cubes")
	assert_has(kinds, "plants")
	assert_has(kinds, "seeds")
	assert_true(bool(s["capped"]))
	assert_almost_eq(float(s["away"]), Offline.CAP_S, 0.01)
	assert_string_contains(WelcomeBack.fleet_text(bots), "×2")


# --- Seed of the Week -----------------------------------------------------------------------

func _unix(y: int, m: int, d: int) -> float:
	return float(Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0}))


func test_iso_weeks() -> void:
	assert_eq(WeeklyChallenge.iso_week(_unix(2026, 11, 7)), Vector2i(2026, 45))
	assert_eq(WeeklyChallenge.iso_week(_unix(2021, 1, 1)), Vector2i(2020, 53))
	assert_eq(WeeklyChallenge.iso_week(_unix(2024, 12, 30)), Vector2i(2025, 1))
	assert_eq(WeeklyChallenge.iso_week(_unix(2026, 1, 1)), Vector2i(2026, 1))
	assert_eq(WeeklyChallenge.iso_week(_unix(2026, 11, 2)), WeeklyChallenge.iso_week(_unix(2026, 11, 8)), "Monday to Sunday is one week")


func test_same_seed_and_twist_for_everyone() -> void:
	WeeklyChallenge.now_override = _unix(2026, 11, 7)
	var a: int = WeeklyChallenge.current_seed()
	var tw: String = str(WeeklyChallenge.twist()["id"])
	WeeklyChallenge.now_override = _unix(2026, 11, 3)
	assert_eq(WeeklyChallenge.current_seed(), a)
	assert_eq(str(WeeklyChallenge.twist()["id"]), tw)
	assert_eq(WeeklyChallenge.seed_for("2026-W45"), a, "seeded by the week id alone")
	WeeklyChallenge.now_override = _unix(2026, 11, 10)
	assert_ne(WeeklyChallenge.current_seed(), a, "next week is a new seed")


func test_twists_limit_robots_only_in_the_challenge() -> void:
	var t: Dictionary = {"name": "Scoopies Only", "only": ["scoopie"]}
	assert_eq(WeeklyChallenge.robot_block_for(t, "scoopie"), "")
	assert_ne(WeeklyChallenge.robot_block_for(t, "haulbug"), "")
	assert_ne(WeeklyChallenge.robot_block_for({"name": "Dry", "ban": ["drip"]}, "drip"), "")
	WeeklyChallenge.active = false
	assert_eq(WeeklyChallenge.robot_block("haulbug"), "", "the main game is never limited")


func test_score_rewards_speed() -> void:
	var slow: int = WeeklyChallenge.score(30, 5, 4000.0, 3500.0, true)
	var fast: int = WeeklyChallenge.score(30, 5, 4000.0, 1200.0, true)
	assert_gt(fast, slow)
	assert_gt(WeeklyChallenge.score(30, 0, 0.0, 9999.0, true), 0)


func test_one_chip_per_week_and_bests() -> void:
	WeeklyChallenge.now_override = _unix(2026, 11, 7)
	var r1: Dictionary = WeeklyChallenge.record_finish(2400.0, 4000)
	assert_ne(str(r1["chip"]), "")
	var r2: Dictionary = WeeklyChallenge.record_finish(1800.0, 3500)
	assert_eq(str(r2["chip"]), "", "a second finish the same week gives no chip")
	assert_true(bool(r2["new_time"]))
	assert_false(bool(r2["new_score"]))
	assert_almost_eq(float(r2["best_time"]), 1800.0, 0.01)
	assert_eq(int(r2["best_score"]), 4000)
	assert_eq(WeeklyChallenge.chip_count(), 1)


func test_weekly_decor_needs_chips() -> void:
	GameState.add_currency("cubes", BigNum.from_float(100000))
	assert_ne(Decor.buy_block_reason("weekly_pennant"), "")
	WeeklyChallenge.now_override = _unix(2026, 11, 7)
	WeeklyChallenge.record_finish(2000.0, 3000)
	assert_eq(Decor.buy_block_reason("weekly_pennant"), "")
	assert_ne(Decor.buy_block_reason("weekly_arch"), "", "the arch needs three chips")
	var arch: Node3D = DecorProps.build("weekly_arch")
	assert_gt(arch.get_child_count(), 3)
	arch.free()


func test_challenge_hooks_cradle_mode_only_while_active() -> void:
	var home_seed: int = CradleMode.world_seed()
	WeeklyChallenge.active = true
	assert_eq(CradleMode.world_seed(), WeeklyChallenge.current_seed())
	assert_eq(CradleMode.modifiers(), WeeklyChallenge.twist_modifiers())
	assert_eq(CradleMode.bank(), 0, "the challenge never banks Starseeds")
	WeeklyChallenge.active = false
	assert_eq(CradleMode.world_seed(), home_seed)


func test_simulate_caps_and_never_pays_twice() -> void:
	var ws: Dictionary = {"robots": [{"type": "scoopie", "tier": 1}, {"type": "haulbug", "tier": 0}]}
	var a: Dictionary = Offline.simulate(ws, 30.0 * 3600.0, 60.0)
	assert_almost_eq(float(a["seconds"]), Offline.CAP_S, 0.01, "time is capped")
	assert_almost_eq(float(a["units"]), 60.0, 0.001, "and so is the junk")
	var b: Dictionary = Offline.simulate(ws, 30.0 * 3600.0, 60.0)
	assert_eq(float(b["units"]), 0.0, "the same junk never pays twice (telescope + welcome back)")
	var remote: Dictionary = Offline.simulate({"robots": ws["robots"]}, 3600.0)
	assert_eq(float(remote["units"]), 0.0, "a district that never saved its junk_left pays nothing")
	var r2: Dictionary = Offline.simulate({"robots": ws["robots"], "junk_left": 500.0}, 3600.0)
	assert_gt(float(r2["cubes"]), 0.0)


# --- [v6screens] Seed of the Week is switched off on the round world -------------------------

func test_weekly_is_off_in_the_shipped_data() -> void:
	WeeklyChallenge.enabled_override = -1
	assert_false(bool(WeeklyChallenge.cfg().get("enabled", true)), "data/weekly.json enabled must stay false until the mode works on the globe")
	assert_false(WeeklyChallenge.enabled())


func test_weekly_off_hides_every_way_in() -> void:
	WeeklyChallenge.enabled_override = 0
	assert_false(ExtrasPanel.tab_open("weekly"), "no Keepsakes tab")
	assert_false("weekly" in ExtrasPanel.open_tabs())
	assert_true(ExtrasPanel.open_tabs().is_empty(), "a fresh game has no Keepsakes tab at all")
	assert_false(WeeklyChallenge.start(null), "start() refuses")
	assert_false(WeeklyChallenge.active)
	assert_false("weekly_pennant" in Decor.type_ids(), "no paint chip decorations in Garden Mode")
	assert_false("weekly_arch" in Decor.type_ids())
	for a: Dictionary in Achievements.shown_defs():
		assert_ne(str((a.get("cond", {}) as Dictionary).get("key", "")), "weekly_chips", "no weekly achievement in the Codex")
	assert_eq(Achievements.shown_defs().size(), Achievements.defs().size() - 2 - _closed_hidden())  # [v7play] minus those for planets not open yet
	var pm := PauseMenu.new()
	add_child_autofree(pm)
	pm.open_menu()
	var kb: Button = pm.find_child("KeepsakesBtn", true, false) as Button
	assert_not_null(kb)
	assert_false(kb.visible, "Pause hides Keepsakes while it has nothing to show")
	for c: Node in kb.get_parent().get_children():
		if c is Button and (c as Button).visible:
			var up: Control = c.get_node_or_null((c as Button).focus_neighbor_top) as Control
			assert_true(up != null and up.visible, "focus chain skips hidden buttons: " + (c as Button).text)
	pm.close_menu()
	var ep := ExtrasPanel.new()
	add_child_autofree(ep)
	ep.open_panel("weekly")
	assert_false(ep.is_open, "the panel does not open on an empty tab list")
	assert_false(get_tree().paused)


func test_weekly_on_brings_it_back() -> void:
	WeeklyChallenge.enabled_override = 1
	assert_true(ExtrasPanel.tab_open("weekly"))
	assert_true("weekly_pennant" in Decor.type_ids())
	assert_eq(Achievements.shown_defs().size(), Achievements.defs().size() - _closed_hidden())  # [v7play]


## [v7play] Achievements the Codex hides while the next planet is closed (data/homeward.json closed).
func _closed_hidden() -> int:
	return (Homeward.closed_cfg().get("hide_achievements", []) as Array).size() if Homeward.next_closed() else 0
