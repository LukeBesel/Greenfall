extends GutTest
## [v9s] Owner, 2026-11-13: "super annoying to hear the same bird chirp so many times over and over
## and things like that. lively but just peaceful." Repetition is data (data/sound.json "variety"
## and "wildlife"); these pin the rules a player would notice. The live check is
## tools/check_audio.py --repeat on a --sound-log run (tools/check_exit.sh "sound_repeat").


func after_each() -> void:
	Fauna._call_next_s = -1.0
	Fauna._recent.clear()
	Fauna._species_next.clear()
	Fauna.still_s = 0.0


func test_never_the_same_take_twice_running() -> void:
	var seen: Dictionary = {}
	var last: int = -1
	for i: int in 300:
		var k: int = Audio.pick_take("test_take", 4)
		assert_ne(k, last, "never the same take twice in a row")
		assert_between(k, 0, 3)
		seen[k] = true
		last = k
	assert_eq(seen.size(), 4, "every take comes up")
	assert_eq(Audio.pick_take("test_one", 1), 0, "a sound with one take plays it")


func test_fast_repeats_come_softer_then_reset() -> void:
	var soft: Array = [1.0, 1.5, 4.0]
	var t0: float = Audio.game_t
	Audio._rep.erase("test:soft")
	Audio.game_t = t0
	assert_eq(Audio._soften_db("test:soft", soft), 0.0, "the first play is at full level")
	Audio.game_t = t0 + 0.5
	assert_almost_eq(Audio._soften_db("test:soft", soft), 1.5, 0.001, "a quick repeat is softer")
	Audio.game_t = t0 + 0.9
	assert_almost_eq(Audio._soften_db("test:soft", soft), 3.0, 0.001)
	Audio.game_t = t0 + 1.2
	assert_almost_eq(Audio._soften_db("test:soft", soft), 4.0, 0.001, "never softer than the cap")
	Audio.game_t = t0 + 3.0
	assert_eq(Audio._soften_db("test:soft", soft), 0.0, "a pause resets the run")
	Audio.game_t = t0


func test_scooping_is_a_patter_in_the_data() -> void:
	for key: String in ["scoop:clink", "scoop:pop", "tick"]:
		var parts: PackedStringArray = key.split(":")
		var soft: Array = SoundCfg.soften(parts[parts.size() - 1], parts[0] if parts.size() > 1 else "")
		assert_eq(soft.size(), 3, "%s softens its repeats" % key)
		assert_gt(float(soft[1]), 0.0)
	assert_gt(SoundCfg.ladder_roots().size(), 1, "the scoop ladder starts on more than one root")


func test_every_bird_call_has_many_distinct_takes() -> void:
	var out: Dictionary = {}
	FaunaSounds._synth_all(out)
	var want: Dictionary = {"chirp": 8, "song": 8, "coo": 5, "frog": 6, "gull": 5, "quack": 4}
	for nm: String in want:
		var list: Array = out[nm]
		assert_gte(list.size(), int(want[nm]), "%s takes" % nm)
		var sigs: Dictionary = {}
		for w: AudioStreamWAV in list:
			sigs[hash(w.data)] = true
		assert_eq(sigs.size(), list.size(), "%s: every take differs" % nm)
	var lens: Dictionary = {}
	for w: AudioStreamWAV in out["song"]:
		lens[snappedf(w.get_length(), 0.05)] = true
	assert_gte(lens.size(), 4, "songs differ in length, not only pitch")


func test_one_species_never_calls_twice_within_its_gap() -> void:
	assert_true(Fauna.bird_call_ok(0.0, "chirp"))
	Fauna._call_next_s = -1.0  # the shared gap passed; the species gap has not
	assert_false(Fauna.bird_call_ok(0.0, "chirp"), "the same bird call waits its species gap")
	assert_true(Fauna.bird_call_ok(0.0, "song"), "another species may call")


func test_bird_calls_capped_per_minute() -> void:
	var cap: int = int(Fauna.wild_cfg().get("calls_per_min", 3))
	var n: int = 0
	for i: int in 20:
		Fauna._call_next_s = -1.0
		Fauna._species_next.clear()
		n += 1 if Fauna.bird_call_ok(0.0, "song") else 0
	assert_eq(n, cap, "at most %d bird calls in a minute" % cap)


func test_calls_thin_out_while_lumi_stands_still() -> void:
	assert_eq(Fauna.still_mult(0.0), 1.0, "walking: the normal gap")
	assert_gt(Fauna.still_mult(600.0), 1.5, "standing still for long: rarer calls")
	assert_lte(Fauna.still_mult(100.0), Fauna.still_mult(600.0))


func test_frogs_share_a_clock_and_timers_have_jitter() -> void:
	assert_gte(Fauna.sound_gap("frog", 0.0, 0.0), 6.0, "frogs croak in turns, not all at once")
	assert_gt(Fauna.sound_gap("frog", 0.0, 1.0), Fauna.sound_gap("frog", 0.0, 0.0), "a random gap, not a metronome")
	assert_gt(Fauna.sound_gap("call", 0.0, 1.0), Fauna.sound_gap("call", 0.0, 0.0))
