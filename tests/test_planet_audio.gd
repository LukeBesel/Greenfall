extends GutTest
## [sound] Planet music themes, restoration, the homecoming mood, ambience beds, ducking and API
## safety (unknown ids and bad numbers are ignored).

const Director := preload("res://audio/music_director.gd")
const Mixer := preload("res://audio/music_offline_mixer.gd")
const Synth := preload("res://audio/music_synth.gd")
const PlanetSynth := preload("res://audio/planet_synth.gd")
const Themes := preload("res://audio/planet_themes.gd")
const Tracks := preload("res://audio/music_tracks.gd")

static var _samples: Dictionary = {}



## The music set a planet's definition names.
func _music_set(planet_id: String) -> String:
	return Planets.by_id(planet_id).music_set


func _all_samples() -> Dictionary:
	if _samples.is_empty():
		_samples = Synth.build_all()
		for th: String in PlanetSynth.NEEDS:
			_samples.merge(PlanetSynth.build(th, _samples))
	return _samples


func _run(d: RefCounted, mixer: RefCounted, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		d.call("update", 512.0 / 22050.0)
		mixer.call("mix", 64)  # keep the voice table small; levels are not checked here
		t += 512.0 / 22050.0


func after_each() -> void:
	Audio.release_theme()
	Audio.set_planet_theme("verdance")
	Audio.set_restoration(0.0)
	Audio.set_music_mood("explore")


func test_unknown_theme_is_ignored() -> void:
	assert_true(Audio.set_planet_theme("ochre"))
	assert_false(Audio.set_planet_theme("no_such_planet"))
	assert_false(Audio.set_planet_theme(""))
	assert_eq(Audio.get_planet_theme(), "ochre", "an unknown id leaves the theme alone")
	assert_false(Audio.hold_theme("nope", 1.0))
	assert_eq(Audio.get_planet_theme(), "ochre")


func test_all_planet_ids_switch() -> void:
	for id: String in Audio.planet_theme_ids():
		assert_true(Audio.set_planet_theme(id), id)
		assert_eq(Audio.get_planet_theme(), id)
	for n: String in ["pluck", "harp", "glass", "pulse", "pad_brass"]:
		assert_true(Audio._music_samples.has(n), "instrument %s built" % n)


func test_restoration_is_clamped_and_nan_safe() -> void:
	Audio.set_planet_theme("anvil")
	Audio.set_restoration(3.0)
	assert_almost_eq(Audio.get_restoration(), 1.0, 0.001)
	Audio.set_restoration(NAN)
	assert_almost_eq(Audio.get_restoration(), 1.0, 0.001, "NaN is ignored")
	Audio.set_restoration(-1.0)
	assert_almost_eq(Audio.get_restoration(), 0.0, 0.001)


func test_hold_and_release_theme() -> void:
	Audio.set_planet_theme("rime")
	Audio.set_restoration(0.2)
	assert_true(Audio.hold_theme("tidewell", 1.0))
	Audio.set_planet_theme("anvil")  # the planet changes while the radio holds
	Audio.set_restoration(0.4)
	assert_eq(Audio.get_planet_theme(), "tidewell")
	assert_almost_eq(Audio.get_restoration(), 1.0, 0.001)
	Audio.release_theme()
	assert_eq(Audio.get_planet_theme(), "anvil")
	assert_almost_eq(Audio.get_restoration(), 0.4, 0.001)


func test_resolve_track_restores_the_same_motif() -> void:
	var v: Dictionary = Director.resolve("cinematic")
	assert_eq(int(v["key"]), Director.KEY_ROOT, "story moods stay in the shared key")
	var ruined: Dictionary = Director.resolve_track("anvil_foundry", "explore", 0.0, false)
	var restored: Dictionary = Director.resolve_track("anvil_foundry", "explore", 1.0, true)
	assert_eq(ruined["mode"], Themes.PHRYGIAN)
	assert_eq(restored["mode"], Themes.IONIAN, "Anvil turns hopeful: major once restored")
	assert_eq(ruined["motif"], restored["motif"], "the same motif, transformed")
	assert_eq(str(ruined["voice"]), "synth")
	assert_eq(str(restored["voice"]), "piano")
	assert_gt(float(restored["lpf"]), float(ruined["lpf"]), "restored is brighter")
	assert_gt(float(restored["bloom"]), float(ruined["bloom"]), "restored blooms fuller")
	var night: Dictionary = Director.resolve_track("ochre_sunbaked", "night", 0.0, false)
	assert_lt(float(night["mix"]["kick"]), float(Director.resolve_track("ochre_sunbaked", "explore", 0.0, false)["mix"]["kick"]), "calmer at night")


func test_every_track_is_well_formed() -> void:
	var smp: Dictionary = _all_samples()
	for id: String in Tracks.TRACKS:
		for hi: bool in [false, true]:
			var m: Dictionary = Director.resolve_track(id, "explore", 1.0 if hi else 0.0, hi)
			assert_eq((m["prog"] as Array).size(), 8, "%s: 8 chords" % id)
			assert_eq((m["mode"] as Array).size(), 7, "%s: mode" % id)
			assert_eq(str(m["bassline"]).length(), 16, "%s: bassline" % id)
			assert_gt((m["motif"] as Array).size(), 6, "%s: has a motif" % id)
			for e: Array in m["motif"]:
				assert_true(int(e[0]) >= 0 and int(e[0]) < 32, "%s: motif step" % id)
			for part: String in m["drums"]:
				assert_eq(str(m["drums"][part]).length(), 16, "%s: %s pattern" % [id, part])
			var names: Array = [m["voice"], m["lead2"], m["pad"][0], m["pad"][1], m["bass"], m["bell"], m["arp_sample"]]
			for part: String in m["drums"]:
				var k: Variant = m["kit"][part]
				names.append_array(k if k is Array else [k])
			for n: Variant in names:
				assert_true(smp.has(str(n)), "%s uses a real instrument: %s" % [id, n])


func test_planet_pools_have_calm_and_active_tracks() -> void:
	for planet: String in ["ochre", "tidewell", "rime", "anvil"]:
		var ids: Array[String] = Tracks.for_set(_music_set(planet))
		assert_between(ids.size(), 2, 3, "%s: 2-3 tracks" % planet)
		var energies: Dictionary = {}
		for id: String in ids:
			energies[Tracks.TRACKS[id]["energy"]] = true
		assert_true(energies.has("calm") and energies.has("active"), "%s: calm and active" % planet)
	assert_eq(Tracks.for_set(_music_set("verdance")).size(), 2, "Verdance: two upbeat cleaning tracks")
	assert_eq(Audio.music_track_ids("anvil").size(), 3)
	assert_eq(Audio.music_track_ids("no_such_planet").size(), 0)
	assert_eq(Audio.music_track_ids().size(), Tracks.TRACKS.size())
	assert_eq(Audio.planet_theme_ids(), ["verdance", "ochre", "tidewell", "rime", "anvil"] as Array[String], "every registered planet names a known music set")
	assert_eq(Audio.music_track_title("anvil_foundry"), "Foundry Heart")
	assert_eq(Audio.music_track_title("nope"), "")


func test_director_switches_planet_on_a_bar_line() -> void:
	var mixer := Mixer.new(_all_samples())
	var d := Director.new(_all_samples(), mixer, 7)
	_run(d, mixer, 1.0)
	assert_eq(d.current_track(), "", "Verdance starts on its generative piece")
	assert_true(d.set_theme(_music_set("rime")))
	assert_false(d.set_theme("bogus"))
	d.pulse_activity(1.0)
	_run(d, mixer, 8.0)
	assert_eq(d._active_theme, _music_set("rime"))
	assert_eq(d.current_track(), "rime_aurora", "busy play picks the active track")
	assert_eq(int(d._cur["key"]), 47)
	d.set_restoration(1.0)
	d._chord_i = 7  # jump to the end of the pass: the restored harmony lands on the next cycle
	_run(d, mixer, 12.0)
	assert_true(d._resto_hi)
	assert_eq(d._cur["mode"], Themes.IONIAN)


func test_silence_gap_between_tracks() -> void:
	var mixer := Mixer.new(_all_samples())
	var d := Director.new(_all_samples(), mixer, 11)
	d.set_theme(_music_set("ochre"))
	_run(d, mixer, 3.0)
	var first: String = d.current_track()
	assert_true(Tracks.for_set(_music_set("ochre")).has(first))
	d._cycles_left = 1
	d._chord_i = 7
	var saw_gap: bool = false
	var t: float = 0.0
	while t < 20.0 and not saw_gap:
		_run(d, mixer, 0.5)
		t += 0.5
		saw_gap = d.in_gap()
	assert_true(saw_gap, "a silence gap follows the track")
	_run(d, mixer, 6.0)
	assert_lt(float(d._gains["melody"]), 0.05, "only the air plays in the gap")
	d._gap_left = 0.01
	_run(d, mixer, 3.0)
	assert_false(d.in_gap())
	assert_ne(d.current_track(), first, "the next track is a different one")


func test_radio_forced_track_loops_without_gaps() -> void:
	var mixer := Mixer.new(_all_samples())
	var d := Director.new(_all_samples(), mixer, 5)
	assert_false(d.play_track("no_such_track"))
	assert_true(d.play_track("anvil_ash"))
	_run(d, mixer, 6.0)
	assert_eq(d.current_track(), "anvil_ash")
	d._cycles_left = 1
	d._chord_i = 7
	_run(d, mixer, 12.0)
	assert_false(d.in_gap(), "the radio never gaps")
	assert_eq(d.current_track(), "anvil_ash")
	d.stop_track()
	_run(d, mixer, 8.0)
	assert_ne(d.current_track(), "anvil_ash")
	assert_false(Audio.play_track("bogus"))


func test_homecoming_quotes_the_motif() -> void:
	var mixer := Mixer.new(_all_samples())
	var d := Director.new(_all_samples(), mixer, 3)
	d.set_mood("homecoming")
	_run(d, mixer, 1.5)
	assert_eq(d._active, "homecoming")
	assert_eq(d.current_track(), "homecoming")
	assert_eq(d._chord_i, 0)
	var expect: Array = Director.MOTIF_CALL
	for e: Array in expect:
		assert_eq(int((d._mel_line[int(e[0])] as Array)[0]), int(e[1]), "the intro motif at step %d" % e[0])
	d.sting("motif")  # no error
	d.sting("unknown_sting")
	assert_push_warning("unknown sting")


func test_homecoming_mood_via_audio() -> void:
	Audio.set_music_mood("homecoming")
	assert_eq(Audio.get_music_mood(), "homecoming")
	assert_true(MusicHooks.STICKY_MOODS.has("homecoming"))


func test_ambience_beds() -> void:
	var amb: Node = Audio._ambience
	assert_not_null(amb)
	Audio.set_planet_theme("tidewell")
	assert_eq(amb.planet, _music_set("tidewell"))
	var ruined: Array[String] = amb.active_loops()
	assert_true(ruined.has("waves"))
	assert_false(ruined.has("water"), "no restored layer while ruined")
	Audio.set_restoration(1.0)
	assert_true(amb.active_loops().has("water"), "restored adds water")
	assert_true(amb.active_loops().has("crickets"), "restored adds insects")
	assert_false(amb.set_planet("mars"), "unknown bed ignored")
	assert_eq(amb.planet, _music_set("tidewell"))
	Audio.set_planet_theme("verdance")
	assert_eq(amb.planet, "")
	assert_eq(amb.active_loops().size(), 0, "Verdance has no planet bed")
	for id: String in ["ochre", "rime", "anvil"]:
		Audio.set_planet_theme(id)
		assert_gt(amb.active_loops().size(), 0, "%s bed" % id)


func test_hover_spray_loop_and_duck() -> void:
	Audio.loop("hover_spray", 0.6)
	assert_true(Audio._loop_players.has("hover_spray"))
	Audio.loop("hover_spray", 0.0)
	assert_false((Audio._loop_players["hover_spray"] as AudioStreamPlayer).playing)
	Audio.duck(NAN)
	Audio.duck(-1.0)
	Audio.duck(2.0)
	assert_gt(Audio._duck_until_us, Time.get_ticks_usec())
	await wait_seconds(0.4)
	assert_gt(Audio.get_duck(), 0.5, "music ducks while WREN speaks")
