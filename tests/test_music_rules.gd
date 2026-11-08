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
	for i: int in 200:
		d.tick(1.0)
	assert_ne(d.current(), "", "then the music starts")
	assert_ne(d.current(), MAIN, "and not the main theme right after the title's")
	d.set_context("none")
