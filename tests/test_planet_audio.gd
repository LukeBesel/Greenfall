extends GutTest
## [sound] Planet music themes, restoration, the homecoming mood, ambience beds, ducking and API
## safety (unknown ids and bad numbers are ignored).

const Director := preload("res://audio/music_director.gd")
const Mixer := preload("res://audio/music_offline_mixer.gd")
const Synth := preload("res://audio/music_synth.gd")
const PlanetSynth := preload("res://audio/planet_synth.gd")
const Themes := preload("res://audio/planet_themes.gd")

static var _samples: Dictionary = {}


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


func test_resolve_voices_moods_per_planet() -> void:
	var v: Dictionary = Director.resolve("explore", "verdance", 1.0, true)
	assert_eq(int(v["key"]), Director.KEY_ROOT)
	assert_eq(str(v["texture"]), "")
	var ruined: Dictionary = Director.resolve("explore", "anvil", 0.0, false)
	var restored: Dictionary = Director.resolve("explore", "anvil", 1.0, true)
	assert_eq(int(ruined["key"]), 48)
	assert_eq(ruined["mode"], Themes.PHRYGIAN)
	assert_eq(restored["mode"], Themes.IONIAN, "Anvil turns hopeful: major once restored")
	assert_gt(float(restored["lpf"]), float(ruined["lpf"]), "restored is brighter")
	assert_gt(float(restored["bloom"]), float(ruined["bloom"]), "restored blooms fuller")
	var cine: Dictionary = Director.resolve("cinematic", "rime", 0.5, false)
	assert_eq(int(cine["key"]), Director.KEY_ROOT, "cinematic is shared by every planet")
	var night: Dictionary = Director.resolve("night", "ochre", 0.0, false)
	assert_lt(float(night["bpm"]), float(Director.resolve("explore", "ochre", 0.0, false)["bpm"]))
	for id: String in Themes.THEMES:
		for r: float in [0.0, 0.5, 1.0]:
			var m: Dictionary = Director.resolve("explore", id, r, r > 0.5)
			assert_lt(int(m["mel_lo"]), int(m["mel_hi"]), "%s melody range" % id)
			assert_eq((m["prog"] as Array).size(), 4, "%s progression" % id)


func test_director_switches_theme_on_a_bar_line() -> void:
	var mixer := Mixer.new(_all_samples())
	var d := Director.new(_all_samples(), mixer, 7)
	_run(d, mixer, 1.0)
	assert_eq(d._active_theme, "verdance")
	assert_true(d.set_theme("rime"))
	assert_false(d.set_theme("bogus"))
	assert_eq(d.theme, "rime")
	_run(d, mixer, 12.0)
	assert_eq(d._active_theme, "rime")
	assert_eq(int(d._cur["key"]), 47)
	# Every scale tone is in B Aeolian (or a chord tone that replaced its neighbour).
	assert_true(d._scale_pcs.has(11), "B is in the scale")
	d.set_restoration(1.0)
	_run(d, mixer, 40.0)
	assert_true(d._resto_hi)
	assert_eq(d._cur["mode"], Themes.LYDIAN, "restored progression lands on a cycle boundary")


func test_homecoming_quotes_the_motif() -> void:
	var mixer := Mixer.new(_all_samples())
	var d := Director.new(_all_samples(), mixer, 3)
	d.set_mood("homecoming")
	_run(d, mixer, 10.0)
	assert_eq(d._active, "homecoming")
	assert_true(bool(d._cur["motif"]))
	var ph: Dictionary = Director.MOTIF[d._chord_i % Director.MOTIF.size()]
	for s: int in ph:
		assert_eq(int((d._mel_line[s] as Array)[0]), int(ph[s]), "motif note at step %d" % s)
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
	assert_eq(amb.planet, "tidewell")
	var ruined: Array[String] = amb.active_loops()
	assert_true(ruined.has("waves"))
	assert_false(ruined.has("water"), "no restored layer while ruined")
	Audio.set_restoration(1.0)
	assert_true(amb.active_loops().has("water"), "restored adds water")
	assert_true(amb.active_loops().has("crickets"), "restored adds insects")
	assert_false(amb.set_planet("mars"), "unknown bed ignored")
	assert_eq(amb.planet, "tidewell")
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
