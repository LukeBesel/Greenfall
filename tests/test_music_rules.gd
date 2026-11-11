extends GutTest
## [v1menu] The owner's music rules (2026-11-08 playtest): the main theme first when the game opens,
## the most common song, other songs mixed in, never the main theme twice in a row, longer quiet
## gaps between songs, and a few quiet minutes after the pod lands in a new game.

const Director := preload("res://audio/tunes_director.gd")
const MAIN: String = "greenfall_main"

var _flags: Dictionary
var _opened: bool
var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_opened = Tunes._title_opened
	GameState.flags = {}
	Tunes.file_override = {}
	for s: Dictionary in Tunes.songs():
		Tunes.file_override[str(s["id"])] = true
	_rng.seed = 1108


func after_each() -> void:
	GameState.flags = _flags
	Tunes._title_opened = _opened
	Tunes.file_override = {}


func _director() -> Node:
	var d: Node = Director.new()
	d.manual = true
	add_child_autofree(d)
	return d


## Plays `n` songs back to back on the title screen and returns them in order.
func _title_run(d: Node, n: int) -> Array[String]:
	var out: Array[String] = []
	d.tick(0.1)
	out.append(d.current())
	for i: int in n - 1:
		d._slot[d._main]["t"] = float(d._slot[d._main]["len"])  # jump to the song's end
		d.tick(0.1)
		out.append(d.current())
	return out


func test_main_theme_first_whenever_the_game_opens() -> void:
	for launch: int in 3:  # not only on the very first launch
		Tunes._title_opened = false
		var d: Node = _director()
		var pool: Array[String] = [MAIN, "clean_sweep", "morning_shift", "sunbaked"]
		d.set_menu_pool(pool, MAIN if not Tunes._title_opened else "")
		Tunes._title_opened = true
		d.set_context("menu")
		d.tick(0.1)
		assert_eq(d.current(), MAIN, "launch %d opens on the main theme" % launch)
		d.set_context("none")


func test_setup_title_puts_main_first_once_per_launch() -> void:
	Tunes._title_opened = false
	Tunes.setup_title({})
	var d: Node = Tunes.director()
	if d == null:
		pass_test("no director in this run")
		return
	assert_eq(d.get("menu_first"), MAIN, "first title of the launch: main theme first")
	Tunes.setup_title({})
	assert_eq(d.get("menu_first"), "", "back to the title later: the usual mix")
	Tunes.set_context("none")


func test_never_main_back_to_back_and_main_most_common() -> void:
	var d: Node = _director()
	var pool: Array[String] = [MAIN, "clean_sweep", "morning_shift", "sunbaked", "dune_caravan"]
	d.set_menu_pool(pool, MAIN)
	d.set_context("menu")
	var run: Array[String] = _title_run(d, 400)
	var count: Dictionary = {}
	for i: int in run.size():
		count[run[i]] = int(count.get(run[i], 0)) + 1
		if i > 0:
			assert_false(run[i] == MAIN and run[i - 1] == MAIN, "never the main theme twice in a row (at %d)" % i)
			if run[i] == MAIN and run[i - 1] == MAIN:
				break
	for id: String in count:
		if id != MAIN:
			assert_gt(int(count[MAIN]), int(count[id]), "main theme beats %s" % id)
	assert_gt(count.size(), 3, "the other songs are mixed in")
	d.set_context("none")


func test_pick_rule_skips_the_intro_song_when_checking_repeats() -> void:
	var pool: Array[String] = [MAIN, "clean_sweep", "morning_shift"]
	for i: int in 50:
		var id: String = Tunes.pick_main_rule(pool, [MAIN, "fall_of_lm1"], _rng, func(_x: String) -> float: return 1.0)
		assert_ne(id, MAIN, "title main theme, then the intro: the game's first song is not the main theme again")
	assert_eq(Tunes.pick_main_rule([MAIN] as Array[String], [MAIN], _rng, func(_x: String) -> float: return 1.0), "", "only the main theme and it just played: silence")


func test_background_shuffle_follows_the_rules() -> void:
	var recent: Array = []
	var count: Dictionary = {}
	for i: int in 300:
		var id: String = Tunes.pick_next("verdance", "explore", 0.0, recent, _rng)
		assert_ne(id, "")
		if not recent.is_empty():
			assert_false(id == MAIN and recent[-1] == MAIN, "never the main theme twice in a row in play")
		recent.append(id)
		count[id] = int(count.get(id, 0)) + 1
	for id: String in count:
		if id != MAIN:
			assert_gt(int(count[MAIN]), int(count[id]), "the main theme is the most common in play too (vs %s)" % id)


func test_longer_gaps_between_songs() -> void:
	var gap: Array = Tunes.cfg().get("gap_s", [])
	assert_gte(float(gap[0]), 60.0, "at least a minute of quiet between songs")
	var d: Node = _director()
	for i: int in 20:
		d._start_gap(false)
		assert_between(d.gap_left, float(gap[0]), float(gap[1]))


func test_quiet_minutes_after_the_pod_lands() -> void:
	var d: Node = _director()
	(d.recent as Array[String]).append(MAIN)  # the title screen played the main theme
	d.intro_start()
	d.tick(0.1)
	d.intro_land(1.0)
	d.set_context("play")
	assert_gte(d.gap_left, 120.0, "a few quiet minutes after landing")
	var t: float = 0.0
	while t < 119.0:
		d.tick(1.0)
		t += 1.0
		assert_eq(d.current(), "", "no song yet at %.0f s" % t)
		if d.current() != "":
			break
	for i: int in 200:  # [main] stop at the first song: in headless runs it can end at once
		d.tick(1.0)
		if d.current() != "":
			break
	assert_ne(d.current(), "", "then the music starts")
	assert_ne(d.current(), MAIN, "and not the main theme right after the title's")
	d.set_context("none")


# --- [v6sound] drop-in songs, per-planet lists, missing files --------------------------------

const TMP: String = "user://gf_song_test/"


func _touch(rel: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP.path_join(rel).get_base_dir())
	var f := FileAccess.open(TMP.path_join(rel), FileAccess.WRITE)
	f.store_string("")
	f.close()


func _wipe(dir: String = TMP) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func test_a_dropped_file_needs_no_entry() -> void:
	_touch("My New Song.mp3")
	_touch("ochre/desert_drive.ogg")
	_touch("ochre/notes.txt")
	_touch("clean_sweep.mp3.import")  # an exported game lists only the import stub
	var found: Dictionary = Tunes.scan_files(TMP)
	assert_eq(found.size(), 3, "three songs, the text file is not one")
	assert_true(found.has("my_new_song") and found.has("desert_drive") and found.has("clean_sweep"))
	assert_eq(str(found["desert_drive"]["folder"]), "ochre")
	var ids: Array = Tunes.planet_ids()
	var a: Dictionary = Tunes.default_entry("my_new_song", "My New Song", "", ids)
	assert_eq(str(a["title"]), "My New Song", "title from the file name")
	assert_eq(a["planets"], ["all"], "main folder: plays everywhere")
	assert_eq(str(a["unlock"]), "start", "owned from the start")
	var b: Dictionary = Tunes.default_entry("desert_drive", "desert_drive", "ochre", ids)
	assert_eq(str(b["title"]), "Desert Drive")
	assert_eq(b["planets"], ["ochre"], "a planet folder: plays on that planet")
	_wipe()


func _add(entry: Dictionary) -> void:
	(Tunes.songs() as Array).append(entry)
	Tunes._index[str(entry["id"])] = entry
	Tunes.file_override[str(entry["id"])] = true


func test_planets_moments_weight_and_trim_come_from_the_entry() -> void:
	_add({"id": "t_rime_only", "unlock": "start", "planets": ["rime"], "moments": ["explore"], "volume_db": -3.0})
	_add({"id": "t_all_night", "unlock": "start", "planets": "all", "moments": ["night"]})
	_add({"id": "t_never", "unlock": "start", "planets": ["all"], "moments": ["explore"], "weight": 0.0})
	_add({"id": "t_launch", "unlock": "cd", "found_on": "rime", "moments": ["launch"]})
	assert_true(Tunes.fits("t_rime_only", "rime", "explore", 0.0))
	assert_false(Tunes.fits("t_rime_only", "verdance", "explore", 0.0), "only on its planets")
	assert_false(Tunes.fits("t_rime_only", "rime", "night", 0.0), "only in its moments")
	assert_true(Tunes.fits("t_all_night", "anvil", "night", 0.0), "all: any planet")
	assert_false(Tunes.fits("t_all_night", "anvil", "explore", 0.0))
	assert_false(Tunes.fits("t_launch", "rime", "explore", 0.0), "a launch song is not in the shuffle")
	assert_eq(Tunes.moment_songs("launch", "rime"), ["t_launch"] as Array[String], "story moments need no CD")
	assert_almost_eq(Tunes.trim_db("t_rime_only"), -3.0, 0.001)
	assert_almost_eq(Tunes.weight("t_rime_only", "rime"), 1.0, 0.001)
	for i: int in 200:
		assert_ne(Tunes.pick_next("verdance", "explore", 0.0, [], _rng), "t_never", "weight 0 never plays")
	Tunes.reload()


func test_each_planet_has_its_own_playlist_and_rules() -> void:
	for p: String in ["verdance", "ochre", "tidewell", "rime", "anvil"]:
		assert_true(Tunes.cfg()["planets"].has(p), "%s has a block in data/songs.json" % p)
		var own: int = 0
		for s: Dictionary in Tunes.songs():
			if str(s.get("group", "")) == p and Tunes.fits(str(s["id"]), p, "explore", 0.0):
				own += 1
		assert_gt(own, 5, "%s has its own songs" % p)
	# A planet's block can list extra songs and change the rules for that planet only.
	var pc: Dictionary = Tunes.cfg()["planets"]["rime"]
	pc["songs"] = ["verdance_night"]
	pc["gap_s"] = [300, 400]
	pc["main_share"] = 0.0
	assert_true(Tunes.fits("verdance_night", "rime", "night", 0.0), "listed on Rime by hand")
	assert_false(Tunes.fits("verdance_night", "ochre", "night", 0.0))
	var d: Node = _director()
	Audio.set_planet_theme("rime")
	d._start_gap(false)
	assert_between(d.gap_left, 300.0, 400.0, "Rime's own gap")
	for i: int in 60:
		assert_ne(Tunes.pick_next("rime", "explore", 0.0, [], _rng), MAIN, "Rime's own main-theme share (0)")
	Audio.set_planet_theme("verdance")
	d._start_gap(false)
	assert_lte(d.gap_left, float(Tunes.cfg()["gap_s"][1]), "the others keep the global gap")
	Tunes.reload()


func test_a_file_that_will_not_load_is_skipped_and_never_stalls() -> void:
	_touch("t_broken.mp3")  # zero bytes: the file is there but will not load
	_add({"id": "t_broken", "unlock": "start"})
	_add({"id": "t_nofile", "unlock": "start"})  # listed, said to exist, but there is no file
	Tunes._files["t_broken"] = TMP + "t_broken.mp3"
	var d: Node = _director()
	var bad: Array[String] = ["t_broken", "t_nofile"]
	d.set_menu_pool(bad)
	d.set_context("menu")
	for i: int in 8:
		d.tick(0.1)
	assert_eq(d.current(), MAIN, "nothing in the pool will play: the title falls back to the main theme")
	assert_false(d._start("t_broken", 1.0, false), "a damaged file does not start")
	assert_false(Tunes.has_file("t_broken"), "the damaged file is skipped from now on")
	assert_false(Tunes.has_file("t_nofile"))
	d.set_context("none")
	# In play: a pool of only unplayable songs falls back to quiet (and the synth score), no stall.
	Tunes._broken.clear()
	Tunes._streams.clear()
	for s: Dictionary in Tunes.songs():
		Tunes.file_override[str(s["id"])] = str(s["id"]) in ["t_broken", "t_nofile"]
	var d2: Node = _director()
	d2.context = "play"
	d2.gap_left = 0.0
	for i: int in 30:
		d2.tick(1.0)
	assert_eq(d2.current(), "", "nothing playable: quiet")
	assert_true(Tunes.found().is_empty(), "both are out of the collection until fixed")
	Tunes.reload()
	_wipe()


func test_no_song_over_the_quiet_beats_of_the_intro() -> void:
	var d: Node = _director()
	d.intro_start()
	d.tick(0.1)
	assert_true(Tunes.has_moment(d.current(), "intro"), "the intro's song is the one marked intro")
	d.intro_land(0.5)
	for i: int in 120:  # the wake-up: the context is still the intro
		d.tick(1.0)
		if i > 2:
			assert_eq(d.current(), "", "quiet after the landing (%d s)" % i)
			if d.current() != "":
				break
	d.set_context("none")


func test_story_moment_song_plays_once_then_quiet() -> void:
	var d: Node = _director()
	d.context = "play"
	assert_false(d.play_moment("launch"), "no song marked for the launch: the synth score keeps it")
	_add({"id": "t_moment", "unlock": "cd", "found_on": "verdance", "moments": ["launch"], "file": "clean_sweep.mp3"})
	Tunes._files["t_moment"] = Tunes.path("clean_sweep")
	assert_true(d.play_moment("launch"))
	d.tick(0.1)
	assert_eq(d.current(), "t_moment")
	d._slot[d._main]["t"] = float(d._slot[d._main]["len"])
	d.tick(0.1)
	assert_eq(d.moment, "", "the moment is over")
	assert_gte(d.gap_left, float(Tunes.cfg()["gap_s"][0]) - 1.0, "and the usual long quiet follows")
	d.set_context("none")
	Tunes.reload()
