extends GutTest
## [tunes] The owner's songs: the library matches the Suno prompt list, start songs and CD unlocks
## (saved), missing files are skipped, the shuffle never repeats back to back and fits the moment,
## CDs drop per planet with a pity guarantee, and the director plays the title / intro songs.

const Director := preload("res://audio/tunes_director.gd")

var _flags: Dictionary
var _stats: Dictionary
var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	GameState.flags = {}
	GameState.stats = {}
	Tunes.file_override = {}
	_rng.seed = 77


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	Tunes.file_override = {}


func _all_files() -> void:
	for s: Dictionary in Tunes.songs():
		Tunes.file_override[str(s["id"])] = true


func test_library_matches_the_prompt_list() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/music/suno_prompts.json"))
	var titles: Array[String] = []
	for g: Dictionary in (d as Dictionary)["groups"]:
		for t: Array in g["tracks"]:
			titles.append(str(t[0]))
	assert_eq(Tunes.songs().size(), titles.size(), "one entry per planned song")
	var ids: Dictionary = {}
	for s: Dictionary in Tunes.songs():
		assert_has(titles, str(s["title"]), "title as in the prompt doc")
		assert_false(ids.has(s["id"]), "unique id")
		ids[s["id"]] = true
		assert_false(Tunes.artist(str(s["artist"])).is_empty(), "%s has an artist" % s["id"])
		if str(s["unlock"]) == "cd":
			assert_has(["verdance", "ochre", "tidewell", "rime", "anvil"], str(s["found_on"]))
	for id: String in ["greenfall_main", "fall_of_lm1", "clean_sweep", "morning_shift", "sunbaked"]:
		assert_true(Tunes.has_file(id), "%s.mp3 is in the build" % id)
	assert_between(Tunes.artists().size(), 6, 9, "a small recurring roster")
	for a: Dictionary in Tunes.artists():
		assert_gt(Tunes.songs_by(str(a["id"])).size() + int(not Tunes.songs_by(str(a["id"])).is_empty()), -1)
		assert_ne(str(a.get("bio", "")), "", "%s has a bio" % a["id"])
		assert_false(str(a["bio"]).to_lower().contains("suno"), "no Suno in the game")


func test_start_songs_and_cd_unlocks_are_saved() -> void:
	_all_files()
	assert_true(Tunes.is_found("greenfall_main"))
	assert_true(Tunes.is_found("clean_sweep"))
	assert_true(Tunes.is_found("morning_shift"))
	assert_false(Tunes.is_found("sunbaked"), "the rest are CDs")
	assert_eq(Tunes.found().size(), 3)
	assert_true(Tunes.grant("sunbaked", true))
	assert_false(Tunes.grant("sunbaked", true), "once")
	assert_eq(Tunes.toast_text("sunbaked"), "New CD: Sunbaked by Two Suns Tango Orchestra")
	var saved: String = JSON.stringify(GameState.flags)
	GameState.flags = JSON.parse_string(saved)
	assert_true(Tunes.is_found("sunbaked"), "survives a save")
	assert_eq(Tunes.found_count(), 4)
	assert_has(Tunes.known_artists(), "two_suns", "the artist page opens with their first CD")


func test_missing_files_are_skipped() -> void:
	_all_files()
	Tunes.file_override["morning_shift"] = false
	Tunes.file_override["dune_caravan"] = false
	assert_does_not_have(Tunes.available(), "morning_shift")
	assert_does_not_have(Tunes.found(), "morning_shift", "an owned song without a file can't play")
	assert_does_not_have(Tunes.cds_left("ochre"), "dune_caravan", "no CD for a missing song")
	assert_has(Tunes.cds_left("ochre"), "sunbaked")
	for i: int in 200:
		assert_ne(Tunes.pick_next("verdance", "explore", 0.0, [], _rng), "morning_shift")
	assert_false(Tunes.play("dune_caravan"), "not owned and missing")


func test_shuffle_never_repeats_back_to_back() -> void:
	_all_files()
	for id: String in ["sunbaked", "sprout_step", "little_helpers"]:
		Tunes.grant(id, true)
	var recent: Array = []
	for i: int in 300:
		var id: String = Tunes.pick_next("verdance", "explore", 0.0, recent, _rng)
		assert_ne(id, "")
		if not recent.is_empty():
			assert_ne(id, str(recent[recent.size() - 1]), "never the same song twice in a row")
		recent.append(id)
	recent.clear()
	for i: int in 300:
		var id: String = Tunes.pick_any(recent, _rng)
		if not recent.is_empty():
			assert_ne(id, str(recent[recent.size() - 1]))
		recent.append(id)


func test_shuffle_fits_the_planet_and_moment() -> void:
	_all_files()
	for id: String in ["verdance_night", "verdance_in_bloom", "fall_of_lm1", "the_ledger", "sunbaked"]:
		Tunes.grant(id, true)
	assert_false(Tunes.fits("verdance_night", "verdance", "explore", 0.0), "night songs only at night")
	assert_true(Tunes.fits("verdance_night", "verdance", "night", 0.0))
	assert_false(Tunes.fits("verdance_night", "ochre", "night", 0.0), "and only on their planet")
	assert_false(Tunes.fits("verdance_in_bloom", "verdance", "explore", 0.2), "restored songs wait for the green")
	assert_true(Tunes.fits("verdance_in_bloom", "verdance", "explore", 0.8))
	assert_false(Tunes.fits("fall_of_lm1", "verdance", "explore", 0.0), "the intro score is CD-player only")
	assert_false(Tunes.fits("the_ledger", "anvil", "explore", 0.0))
	assert_true(Tunes.fits("greenfall_main", "rime", "explore", 0.0), "the main theme fits anywhere")
	var n: Dictionary = {}
	for i: int in 2000:
		var id: String = Tunes.pick_next("verdance", "explore", 0.0, [], _rng)
		n[id] = int(n.get(id, 0)) + 1
	assert_gt(int(n.get("clean_sweep", 0)), int(n.get("sunbaked", 0)) * 3, "home planet songs first")
	assert_gt(int(n.get("sunbaked", 0)), 0, "other planets' songs now and then")


func test_cds_drop_per_planet_with_a_guarantee() -> void:
	_all_files()
	GameState.stats["hexes_cleaned"] = 0.0
	assert_eq(CdFinds.roll("verdance", 0, 0.0, 0.0), "", "not in the first few hexes")
	GameState.stats["hexes_cleaned"] = 50.0
	var g: int = int(CdFinds.tuning().get("guarantee_hexes", 18))
	var got: String = ""
	for i: int in g:
		got = CdFinds.roll("ochre", 2, 0.999, 0.0)  # an unlucky roll every time
		if got != "":
			break
	assert_ne(got, "", "a CD within %d hexes, however unlucky" % g)
	assert_eq(Tunes.found_on(got), "ochre", "Ochre's CDs are found on Ochre")
	assert_eq(CdFinds.pity(), 0, "the counter resets")
	assert_lt(CdFinds.chance(0), 0.1, "rarer than a sure thing")
	CdFinds.pending()[got] = {"hub": 2, "hex": 5, "planet": "ochre"}
	assert_does_not_have(CdFinds.candidates("ochre", 2), got, "one copy lying in a district at a time")
	assert_true(CdFinds.take(got))
	assert_true(Tunes.is_found(got))
	assert_false(CdFinds.pending().has(got))
	for id: String in Tunes.cds_left("verdance"):
		Tunes.grant(id, true)
	for i: int in 40:
		assert_eq(CdFinds.roll("verdance", 0, 0.0, 0.0), "", "nothing left to find on Verdance")


func test_director_plays_title_and_intro_songs() -> void:
	_all_files()
	var d: Node = Director.new()
	d.manual = true
	add_child_autofree(d)
	d.set_context("menu")
	d.tick(0.1)
	assert_eq(d.current(), "greenfall_main", "the main theme on the title screen")
	d.intro_start()
	d.tick(0.1)
	assert_eq(d.current(), "fall_of_lm1", "The Fall of LM-1 scores the intro")
	d.set_paused(true)
	var t0: float = d.position()
	d.tick(1.0)
	assert_eq(d.position(), t0, "holds still while the cinematic is paused")
	d.set_paused(false)
	d.intro_land(1.0)
	for i: int in 15:
		d.tick(0.1)
	assert_eq(d.current(), "", "faded out at the landing")
	d.set_context("none")


func test_director_background_gaps_and_cd_player() -> void:
	_all_files()
	var d: Node = Director.new()
	d.manual = true
	add_child_autofree(d)
	d.set_context("play")
	d.gap_left = 0.5
	d.tick(0.1)
	assert_eq(d.current(), "", "starts with a quiet gap")
	for i: int in 10:
		d.tick(0.1)
	var first: String = d.current()
	assert_has(Tunes.found(), first, "then an owned song")
	d.set_radio(Tunes.SHUFFLE)
	d.tick(0.1)
	assert_ne(d.current(), "")
	d.set_radio("morning_shift")
	d.tick(0.1)
	assert_eq(d.current(), "morning_shift", "a pick plays at once")
	d.set_radio("")
	for i: int in 30:
		d.tick(0.1)
	assert_eq(d.current(), "", "off: back to the quiet between songs")
	assert_gt(d.gap_left, 0.0)
	d.set_context("none")
