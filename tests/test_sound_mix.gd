extends GutTest
## [v6sound] The mix is data (data/sound.json): one bus and one Settings slider each for music,
## ambience, effects and interface sounds; per-sound bus, trim and shortest gap; per-planet score
## theme and ambience bed, the same shape for every planet.

var _vol: Array = []


func before_each() -> void:
	_vol = [Settings.master_volume, Settings.music_volume, Settings.ambience_volume, Settings.sfx_volume, Settings.ui_volume]


func after_each() -> void:
	Settings.master_volume = _vol[0]
	Settings.music_volume = _vol[1]
	Settings.ambience_volume = _vol[2]
	Settings.sfx_volume = _vol[3]
	Settings.ui_volume = _vol[4]
	Audio.apply_volumes()
	SoundCfg._cfg = {}
	Audio.set_planet_theme("verdance")


func test_every_group_has_a_bus_and_a_slider() -> void:
	for bus: String in SoundCfg.BUSES:
		var idx: int = AudioServer.get_bus_index(bus)
		assert_gt(idx, 0, "%s bus exists" % bus)
		assert_eq(str(AudioServer.get_bus_send(idx)), "Master", "%s goes straight to Master (its own slider)" % bus)
	var sliders: Dictionary = {"Music": "music_volume", "Ambience": "ambience_volume", "SFX": "sfx_volume", "UI": "ui_volume"}
	for bus: String in sliders:
		var idx: int = AudioServer.get_bus_index(bus)
		Settings.set(str(sliders[bus]), 0.0)
		Audio.apply_volumes()
		assert_true(AudioServer.is_bus_mute(idx), "%s slider at 0 mutes its bus" % bus)
		Settings.set(str(sliders[bus]), 1.0)
		Audio.apply_volumes()
		assert_false(AudioServer.is_bus_mute(idx))
		assert_almost_eq(AudioServer.get_bus_volume_db(idx), SoundCfg.bus_trim_db(bus), 0.01, "%s slider at full: the bus trim" % bus)
		Settings.set(str(sliders[bus]), 0.5)
		Audio.apply_volumes()
		assert_almost_eq(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5) + SoundCfg.bus_trim_db(bus), 0.01)
		for other: String in sliders:
			if other != bus:
				assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(other)), "%s does not touch %s" % [bus, other])


func test_slider_defaults_come_from_data() -> void:
	for k: String in ["master", "music", "ambience", "sfx", "ui"]:
		assert_true((SoundCfg.cfg()["volumes"] as Dictionary).has(k), "volumes.%s" % k)
		assert_between(SoundCfg.volume_default(k, -1.0), 0.0, 1.0)
	assert_lt(SoundCfg.volume_default("music", 1.0), SoundCfg.volume_default("sfx", 0.0), "music starts under the effects")


func _player_of(sound: String) -> AudioStreamPlayer:
	var k: int = (Audio._next_player + Audio._players.size() - 1) % Audio._players.size()
	var p: AudioStreamPlayer = Audio._players[k]
	return p if p.stream in Audio.streams_of(sound) else null


func test_sounds_play_on_the_bus_the_data_names() -> void:
	Audio.play("click")
	assert_eq(str(_player_of("click").bus), "UI", "menu clicks follow the Interface slider")
	Audio.play("pop")
	assert_eq(str(_player_of("pop").bus), "SFX")
	FaunaSounds.ensure()
	Audio.play("song")
	assert_eq(str(_player_of("song").bus), "Ambience", "birdsong follows the Ambience slider")
	(SoundCfg.cfg()["sound_db"] as Dictionary)["pop"] = -5.0
	Audio.play("pop", 1.0, -2.0)
	assert_almost_eq(_player_of("pop").volume_db, -7.0, 0.01, "a sound's own trim is added")


func test_min_gap_drops_a_sound_that_comes_too_soon() -> void:
	(SoundCfg.cfg()["min_gap_s"] as Dictionary)["pop"] = 4.0
	Audio._last_play.erase("pop")
	var t0: float = Audio.game_t
	Audio.play("pop")
	var k: int = Audio._next_player
	Audio.play("pop")
	Audio.play("pop")
	assert_eq(Audio._next_player, k, "the same sound again at once: dropped")
	Audio.play("thud")
	assert_ne(Audio._next_player, k, "other sounds are not held back")
	k = Audio._next_player
	Audio.game_t = t0 + 4.1
	Audio.play("pop")
	assert_ne(Audio._next_player, k, "after the gap it plays again")
	Audio.game_t = t0


func test_every_planet_has_the_same_sound_block() -> void:
	for p: String in ["verdance", "ochre", "tidewell", "rime", "anvil"]:
		var d: Dictionary = SoundCfg.planet(p)
		assert_true(Audio.PlanetThemes.has(SoundCfg.theme_of(p)), "%s names a score theme" % p)
		var bed: Dictionary = d.get("ambience", {})
		assert_true(bed.get("loops") is Dictionary and bed.get("events") is Array and bed.has("level_db"), "%s has an ambience bed block" % p)
		for e: Array in bed["events"]:
			assert_eq(e.size(), 8, "%s event row %s" % [p, str(e[0])])
			assert_gte(float(e[1]), 4.0, "%s %s: an ambience event never comes round faster than every 4 s" % [p, str(e[0])])
		assert_true(Tunes.cfg()["planets"].has(p), "%s has a playlist block too" % p)


func test_a_new_planet_can_borrow_a_score_and_keep_its_own_songs_and_bed() -> void:
	(SoundCfg.cfg()["planets"] as Dictionary)["nova"] = {"theme": "rime",
		"ambience": {"level_db": -2.0, "loops": {"water": [0.5, 1.0]}, "events": []}}
	assert_true(Audio.set_planet_theme("nova"))
	assert_eq(Audio.get_planet_id(), "nova", "songs, rules and ambience are looked up by the planet")
	assert_eq(Audio.get_planet_theme(), "rime", "the score is the borrowed one")
	assert_eq(str(Audio._ambience.planet), "nova")
	assert_true((Audio._ambience.active_loops() as Array).has("water"))
	assert_false(Audio.set_planet_theme("nowhere"), "an unknown planet is ignored")
	assert_eq(Audio.get_planet_id(), "nova")
	assert_true(Audio.set_planet_theme("verdance"))
	assert_eq((Audio._ambience.active_loops() as Array).size(), 0, "Verdance's planet bed is empty: wildlife and town life are its bed")
