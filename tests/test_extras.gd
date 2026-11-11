extends GutTest
## [extras] Radio unlocks and the music override, the nursery's retire rules and garden bonus,
## album milestones, offline garden growth and the welcome-back summary.

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


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world
	GameState.districts = _districts
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
	assert_does_not_have(kinds, "cubes", "robots earn no cubes while away")
	assert_has(kinds, "plants")
	assert_has(kinds, "seeds")
	assert_true(bool(s["capped"]))
	assert_almost_eq(float(s["away"]), Offline.CAP_S, 0.01)
	assert_string_contains(WelcomeBack.fleet_text(bots), "×2")


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
	assert_gt(float(r2["units"]), 0.0, "the crew cleaned")
	assert_eq(float(r2["cubes"]), 0.0, "and earned no cubes")
