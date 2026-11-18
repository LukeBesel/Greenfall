extends Node
## Procedural audio. Every SFX is synthesized at startup (original, no external files) with
## at least 3 variations. Final assets can replace any sound by name via `override(name, streams)`.
##
## Music: a generative, layered ambient score (audio/music_director.gd, instruments from
## audio/music_synth.gd) on the "Music" bus. Drive it with `set_music_mood()` ("explore",
## "night", "base", "cinematic", "menu", "homecoming"), `set_music_intensity(0..1)` and `music_sting(name)`.
##
## [sound] Planets: `set_planet_theme(id)` re-voices the score and swaps the ambience bed for a
## solar-system planet ("verdance", "ochre", "tidewell", "rime", "anvil"); `set_restoration(0..1)`
## blooms both from ruined to restored. `hold_theme()` / `release_theme()` let the radio preview
## a theme without fighting the planet. `duck(seconds)` dips music and ambience under WREN lines.
## See docs/AUDIO.md.

const RATE: int = 22050
const PENTATONIC: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]

var _sounds: Dictionary = {}  # name -> Array[AudioStreamWAV]
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _rng := RandomNumberGenerator.new()
var _loops: Dictionary = {}  # name -> AudioStreamWAV (looping)
var _loop_players: Dictionary = {}  # name -> AudioStreamPlayer

const MusicSynth := preload("res://audio/music_synth.gd")
const MusicDirector := preload("res://audio/music_director.gd")
const MusicVoices := preload("res://audio/music_voices.gd")
const PlanetSynth := preload("res://audio/planet_synth.gd")  # [sound]
const PlanetThemes := preload("res://audio/planet_themes.gd")  # [sound]
const MusicTracks := preload("res://audio/music_tracks.gd")  # [sound]
const AmbienceBeds := preload("res://audio/ambience.gd")  # [sound]
const AmbienceSynth := preload("res://audio/ambience_synth.gd")  # [sound]
const TunesDirector := preload("res://audio/tunes_director.gd")  # [tunes]
## [sound] Mix: how far music / ambience dip while WREN speaks, and the attack / release times.
## [v6sound] Fallbacks only: the values in use are "duck" in data/sound.json.
const DUCK_MUSIC_DB: float = -7.0
const DUCK_AMB_DB: float = -4.5
const DUCK_ATTACK_S: float = 0.25
const DUCK_RELEASE_S: float = 0.9

## When false the score fades out (stingers still play; they are feedback).
var music_enabled: bool = true
var _music: RefCounted  # MusicDirector
var _music_voices: Node
var _music_lpf: AudioEffectLowPassFilter
var _music_last_us: int = 0
var _music_samples: Dictionary = {}
var _ambience: Node  # [sound] audio/ambience.gd
var _theme_world: String = "verdance"  # [sound] what the planet asked for
var _resto_world: float = 0.0
var _hold_id: String = ""  # [sound] radio preview (wins over the world while set)
var _hold_resto: float = 0.0
var _duck_until_us: int = 0
var _duck: float = 0.0  # 0..1, smoothed
## [eggs2] Hush: a source that plays its own music in the world (the jukebox) fades the whole
## score out (mood layers, stingers, radio tracks: everything on the Music bus) while it plays.
const HUSH_FADE_S: float = 1.5
var _hush_by: Dictionary = {}  # owner -> true
var _hush: float = 0.0  # 0..1, smoothed
var _tunes_hush: bool = false  # [tunes] a song (or the quiet between songs) owns the music
## [v6sound] Game seconds (follows the time scale): the per-sound gap gate and the sound log.
var game_t: float = 0.0
var _last_play: Dictionary = {}  # sound -> game_t of its last play
var _last_take: Dictionary = {}  # [v9s] sound -> index of the take it played last
var _rep: Dictionary = {}  # [v9s] key -> [game_t of its last play, repeats in the run]
var _ladder_root: int = 0  # [v9s] semitones the current scoop ladder starts on
var _planet_id: String = "verdance"  # the planet itself (its theme may be another planet's)
var sound_log: Node  # audio/sound_log.gd, only with --sound-log


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_setup_buses()
	_generate_all()
	for i: int in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	var music_samples: Dictionary = MusicSynth.build_all()
	music_samples.merge(PlanetSynth.build("groove", music_samples))  # [sound] Verdance's upbeat tracks
	_music_samples = music_samples
	_music_voices = MusicVoices.new()
	_music_voices.name = "MusicVoices"
	add_child(_music_voices)
	_music_voices.call("setup", music_samples, "Music", 56)  # [sound] 56: room for the restoration bloom
	_music = MusicDirector.new(music_samples, _music_voices)
	_music_last_us = Time.get_ticks_usec()
	_ambience = AmbienceBeds.new()
	_ambience.name = "Ambience"
	add_child(_ambience)
	var tunes: Node = TunesDirector.new()  # [tunes] the owner's songs (systems/tunes.gd)
	tunes.name = "TunesDirector"
	add_child(tunes)
	apply_volumes()
	for a: String in OS.get_cmdline_user_args():  # [v6sound] dev: --sound-log[=file]
		if a == "--sound-log" or a.begins_with("--sound-log="):
			sound_log = (load("res://audio/sound_log.gd") as GDScript).new()
			sound_log.name = "SoundLog"
			sound_log.set("out_path", a.substr(12) if a.begins_with("--sound-log=") else "")
			add_child(sound_log)
		if a == "--audio-capture" or a.begins_with("--audio-capture="):  # [v8snd] dev: record the mix
			var cap: Node = (load("res://audio/audio_capture.gd") as GDScript).new()
			cap.name = "AudioCapture"
			cap.set("out_dir", a.substr(16) if a.begins_with("--audio-capture=") else "")
			add_child.call_deferred(cap)  # deferred: the Songs bus is added by the TunesDirector


func _exit_tree() -> void:
	StorySfx.finish_pending()  # [health] an unwaited WorkerThreadPool task crashes the engine at exit
	BuildBudget.finish_pending()  # [leftovers] quitting while a district builds
	# [health] Players stopped on exit only hand their playbacks to the mixer thread for deletion;
	# give it a few mix steps so playbacks and streams aren't leaked at quit. Autoloads exit after
	# the scene, so this runs once, at quit, after every scene player has stopped.
	OS.delay_msec(150)


func _setup_buses() -> void:
	# [v6sound] One bus per slider: Music (and Songs, audio/tunes_director.gd), Ambience, SFX, UI.
	for bus_name: String in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# [sound] A safety limiter on Master: many SFX at once must never clip.
	if AudioServer.get_bus_effect_count(0) == 0:
		# [v8snd] Small-speaker guard first: a high-pass under the whole mix (data/sound.json
		# "master_highpass_hz", 0 = off). Laptop speakers can't play sub-bass and rattle on it.
		var hp_hz: float = float(SoundCfg.cfg().get("master_highpass_hz", 60.0))
		if hp_hz > 0.0:
			var mhp := AudioEffectHighPassFilter.new()
			mhp.cutoff_hz = hp_hz
			mhp.resonance = 0.5
			AudioServer.add_bus_effect(0, mhp)
		var mlim := AudioEffectHardLimiter.new()
		mlim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, mlim)
	var sfx: int = AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.25
		rev.wet = 0.08
		AudioServer.add_bus_effect(sfx, rev)
	# Music: gentle tone filter (mood-driven), a roomy reverb, and a safety limiter.
	var mus: int = AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(mus) == 0:
		_music_lpf = AudioEffectLowPassFilter.new()
		_music_lpf.cutoff_hz = 6500.0
		AudioServer.add_bus_effect(mus, _music_lpf)
		var mrev := AudioEffectReverb.new()
		mrev.room_size = 0.7
		mrev.damping = 0.6
		mrev.hipass = 0.15
		mrev.dry = 1.0
		mrev.wet = 0.22
		mrev.predelay_msec = 40.0
		AudioServer.add_bus_effect(mus, mrev)
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(mus, lim)
	else:
		for i: int in AudioServer.get_bus_effect_count(mus):
			if AudioServer.get_bus_effect(mus, i) is AudioEffectLowPassFilter:
				_music_lpf = AudioServer.get_bus_effect(mus, i)


func apply_volumes() -> void:
	# [sound] A slider at 0 mutes its bus (linear_to_db(0) is -inf); the duck rides on top.
	# [v6sound] Four sliders under Master, each with its own bus; trims and the duck are data/sound.json.
	_set_bus_level(0, Settings.master_volume, 0.0)
	_set_bus_level(AudioServer.get_bus_index("SFX"), Settings.sfx_volume, SoundCfg.bus_trim_db("SFX"))
	_set_bus_level(AudioServer.get_bus_index("UI"), Settings.ui_volume, SoundCfg.bus_trim_db("UI"))
	_set_bus_level(AudioServer.get_bus_index("Music"), Settings.music_volume * (1.0 - _hush),
		SoundCfg.bus_trim_db("Music") + SoundCfg.duck("music_db", DUCK_MUSIC_DB) * _duck)  # [eggs2] hush
	_set_bus_level(AudioServer.get_bus_index("Ambience"), Settings.ambience_volume,
		SoundCfg.bus_trim_db("Ambience") + SoundCfg.duck("ambience_db", DUCK_AMB_DB) * _duck)


func _set_bus_level(idx: int, linear: float, offset_db: float) -> void:
	if idx < 0:
		return
	var v: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0001)
	AudioServer.set_bus_volume_db(idx, maxf(-80.0, linear_to_db(maxf(v, 0.0001))) + offset_db)


## [sound] Dips music (and the ambience bed) for `seconds`, e.g. while a WREN line types out.
## Overlapping calls extend the duck; it eases back in after.
func duck(seconds: float) -> void:
	if is_nan(seconds) or seconds <= 0.0:
		return
	_duck_until_us = maxi(_duck_until_us, Time.get_ticks_usec() + int(minf(seconds, 30.0) * 1000000.0))


func get_duck() -> float:
	return _duck


## [eggs2] Fades all background music out (over HUSH_FADE_S) until every owner has called
## unhush_music(). SFX and the ambience bed keep playing.
func hush_music(owner_id: String) -> void:
	_hush_by[owner_id] = true


func unhush_music(owner_id: String) -> void:
	_hush_by.erase(owner_id)


func is_music_hushed() -> bool:
	return not _hush_by.is_empty()


## 0 = normal music, 1 = fully faded out.
func get_hush() -> float:
	return _hush


## Eases the hush toward its target; _process calls it with real time (tests call it directly).
func step_hush(dt: float) -> void:
	var want: float = 1.0 if not _hush_by.is_empty() else 0.0
	if want != _hush:
		_hush = move_toward(_hush, want, dt / HUSH_FADE_S)
		apply_volumes()


# --- Playback -----------------------------------------------------------------

## `tag` names where the sound comes from ("scoop", "lumi", "lights"...): data/sound.json can then
## trim, gap or mute "tag:sound" there without touching the same sound elsewhere.
func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0, jitter: float = 0.04, tag: String = "") -> void:
	var list: Array = _sounds.get(sound, [])
	if list.is_empty():
		return
	var key: String = sound if tag == "" else tag + ":" + sound
	var trim: float = SoundCfg.sound_db(sound, tag)
	if trim <= SoundCfg.OFF_DB:  # [v6sound] muted in data/sound.json
		if sound_log:
			sound_log.call("dropped", key)
		return
	# [v6sound] The same sound never sooner than its min_gap_s (data/sound.json), so nothing stacks.
	var gap: float = SoundCfg.min_gap(sound, tag)
	if gap > 0.0:
		if game_t - float(_last_play.get(key, -1000.0)) < gap:
			if sound_log:
				sound_log.call("dropped", key)
			return
		_last_play[key] = game_t
	# [v9s] Owner, 2026-11-13: "super annoying to hear the same bird chirp so many times over and
	# over". data/sound.json "variety": at most max_voices of one sound at once, the 2nd..nth play
	# within a short window comes softer (fast scooping is a patter, not a hammer), a pitch spread
	# floor, and never the same take twice running.
	var vcap: int = SoundCfg.max_voices(sound, tag)
	if vcap > 0 and _voices_of(list) >= vcap:
		if sound_log:
			sound_log.call("dropped", key)
		return
	volume_db -= _soften_db(key, SoundCfg.soften(sound, tag))
	jitter = maxf(jitter, SoundCfg.pitch_spread(sound, tag))
	# [v8pause] Don't steal a sound held by the pause (it resumes on unpause) unless all are held.
	for i: int in _players.size():
		if not _players[_next_player].stream_paused:
			break
		_next_player = (_next_player + 1) % _players.size()
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream_paused = false
	p.stream = list[pick_take(sound, list.size())]
	p.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-jitter, jitter)))
	p.volume_db = volume_db + trim
	p.bus = SoundCfg.bus_of(sound)  # UI sounds and animal calls have their own sliders
	p.play()
	if sound_log:
		sound_log.call("played", key, p.bus, p.volume_db, p.stream.get_length() / p.pitch_scale, str(p.stream.get_instance_id()), p.pitch_scale)


## [v9s] Which take of a sound plays: random, never the same as last time (when it has more than one).
func pick_take(sound: String, n: int) -> int:
	if n <= 1:
		return 0
	var last: int = int(_last_take.get(sound, -1))
	var k: int = _rng.randi() % (n - 1 if last >= 0 and last < n else n)
	if last >= 0 and last < n and k >= last:
		k += 1
	_last_take[sound] = k
	return k


## [v9s] How many of these streams are sounding now in the one-shot pool.
func _voices_of(list: Array) -> int:
	var n: int = 0
	for p: AudioStreamPlayer in _players:
		if p.playing and not p.stream_paused and p.stream in list:
			n += 1
	return n


## [v9s] dB taken off a play that follows the last one of the same key within soft[0] seconds:
## soft[1] per repeat in the run, at most soft[2]. A pause longer than the window resets the run.
func _soften_db(key: String, soft: Array) -> float:
	if soft.size() < 3:
		return 0.0
	var r: Array = _rep.get(key, [-1000.0, 0])
	var n: int = int(r[1]) + 1 if game_t - float(r[0]) < float(soft[0]) else 0
	_rep[key] = [game_t, n]
	return minf(float(n) * float(soft[1]), float(soft[2]))


## [v9s] A one-shot at a place in the world: full level within near_m of the listener (the camera,
## else Lumi's spot is the caller's job), 6 dB softer per doubling of distance past it, and not
## played at all past far_m (0: no limit). For world events that also happen far away (a robot's
## hex coming clean, a hex levelling up): the player hears the near ones, not every one on the map.
func play_at(sound: String, at: Vector3, pitch: float = 1.0, volume_db: float = 0.0, jitter: float = 0.04,
		tag: String = "", near_m: float = 14.0, far_m: float = 0.0) -> void:
	var d: float = listener_distance(at)
	if far_m > 0.0 and d > far_m:
		return
	play(sound, pitch, volume_db - 20.0 * log(maxf(d, near_m) / near_m) / log(10.0), jitter, tag)


## Distance from the listener (the current 3D camera) to a world point; 0 with no camera.
func listener_distance(at: Vector3) -> float:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	return cam.global_position.distance_to(at) if cam else 0.0


## Plays a sound pitched up a pentatonic scale; step grows with combos.
func play_scale(sound: String, step: int, volume_db: float = 0.0) -> void:
	var s: int = PENTATONIC[clampi(step, 0, PENTATONIC.size() - 1)]
	play(sound, pow(2.0, s / 12.0), volume_db, 0.0)


## [first] A gentle combo ladder: steps climb one octave of the pentatonic scale, then hold there
## with a soft alternation so a long combo never gets shrill; high notes sit a little quieter.
func play_ladder(sound: String, step: int, volume_db: float = 0.0, tag: String = "") -> void:
	# [v9s] Each new combo starts the ladder on another root (data/sound.json variety.ladder_roots),
	# so a long scooping session is not the same arpeggio over and over.
	if step <= 0:
		var roots: Array = SoundCfg.ladder_roots()
		if roots.size() > 0:
			_ladder_root = int(roots[pick_take("ladder_root:" + sound, roots.size())])
	var s: int = ladder_semitones(step) + _ladder_root
	play(sound, pow(2.0, s / 12.0), volume_db - 0.25 * float(s) / 2.0, 0.0, tag)


static func ladder_semitones(step: int) -> int:
	var up: Array[int] = [0, 2, 4, 7, 9, 12]
	if step < up.size():
		return up[maxi(step, 0)]
	return 12 if (step - up.size()) % 2 == 0 else 9


## Continuous looping sound at `level` 0..1 (0 stops it). Cheap to call every frame; the
## player is created once per loop name. `pitch` follows the call.
func loop(sound: String, level: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loop_players.get(sound)
	if level <= 0.001:
		if p and p.playing:
			p.stop()
		return
	if p == null:
		if not _loops.has(sound) and sound == "hover_spray":  # [sound] Lumi over water (Tidewell)
			var rng := RandomNumberGenerator.new()
			rng.seed = 2323
			_loops[sound] = _wav(AmbienceSynth.spray(rng), true)
		if not _loops.has(sound):
			return
		p = AudioStreamPlayer.new()
		p.bus = SoundCfg.bus_of(sound)
		p.name = "Loop_" + sound
		p.stream = _loops[sound]
		add_child(p)
		_loop_players[sound] = p
	AudioVol.set_db(p, linear_to_db(level) - 22.0)  # [qafix] crash fix: loops are re-levelled every frame
	p.pitch_scale = pitch
	if not p.playing and not holds(p):  # [v8pause] a paused loop stays paused
		p.play()


## [sound] The streams registered under `sound` (empty if none). Used by the ambience beds.
func streams_of(sound: String) -> Array:
	return _sounds.get(sound, [])


func override(sound: String, streams: Array) -> void:
	_sounds[sound] = streams


func has_sound(sound: String) -> bool:
	return _sounds.has(sound)


# --- Music --------------------------------------------------------------------

## 0 = sparse and melancholy (pad, air, a few notes); rising adds bass, fuller melody, bells,
## then a brushed shaker (> ~0.55) and a soft kick (> ~0.75). Layers fade over ~4 s.
func set_music_intensity(x: float) -> void:
	if _music:
		_music.call("set_intensity", x)


## "explore" (default), "night", "base", "cinematic", "menu". The mix crossfades over ~4 s;
## harmony and tempo switch on the next bar line.
func set_music_mood(mood: String) -> void:
	if _music:
		if mood == "homecoming":
			_ensure_instruments("homecoming")  # [sound] the ending's choir
		_music.call("set_mood", mood)


func get_music_mood() -> String:
	return str(_music.get("mood")) if _music else ""


# --- Planets [sound] ----------------------------------------------------------

## Planet theme for music and ambience: "verdance" (default), "ochre", "tidewell", "rime",
## "anvil". Unknown ids are ignored (returns false). The first call for a planet synthesizes its
## instruments and ambience (~0.1-0.3 s), so call it while the planet loads.
func set_planet_theme(id: String) -> bool:
	# [v6sound] A planet may borrow another planet's score (data/sound.json planets.<id>.theme);
	# its songs, rules and ambience are still its own.
	var theme: String = id if PlanetThemes.has(id) else SoundCfg.theme_of(id)
	if not PlanetThemes.has(theme):
		return false
	_planet_id = id
	_theme_world = theme
	if _hold_id == "":
		_apply_theme(theme, _resto_world)
	return true


## [v6sound] The planet the player is on (songs, music rules and ambience are looked up by it).
func get_planet_id() -> String:
	return _planet_id


func get_planet_theme() -> String:
	return str(_music.get("theme")) if _music else _theme_world


## How restored the current planet is, 0..1: the theme blooms fuller and warmer, and the ambience
## swaps wind and groans for birds, insects and water. MusicHooks feeds this from the planet.
func set_restoration(x: float) -> void:
	if is_nan(x):
		return
	_resto_world = clampf(x, 0.0, 1.0)
	if _hold_id == "":
		_apply_resto(_resto_world)


func get_restoration() -> float:
	return float(_music.get("restoration")) if _music else _resto_world


## For the radio: plays planet theme `id` at `restoration` until release_theme(), whatever the
## planet sets meanwhile (that is remembered and restored on release). Unknown ids are ignored.
func hold_theme(id: String, restoration: float = 1.0) -> bool:
	if not PlanetThemes.has(id) or is_nan(restoration):
		return false
	_hold_id = id
	_hold_resto = clampf(restoration, 0.0, 1.0)
	_apply_theme(id, _hold_resto)
	return true


func release_theme() -> void:
	if _hold_id == "":
		return
	_hold_id = ""
	_apply_theme(_theme_world, _resto_world)


## Busy play (cleaning, building) nudges the score toward its upbeat tracks. MusicHooks calls it.
func music_activity(amount: float) -> void:
	if _music:
		_music.call("pulse_activity", amount)


## For the radio: loops composed track `id` (see music_track_ids()) with no gaps until
## stop_track(). Unknown ids are ignored (returns false).
func play_track(id: String) -> bool:
	if _music == null or not MusicTracks.TRACKS.has(id):
		return false
	var planet: String = str(MusicTracks.TRACKS[id]["planet"])
	_ensure_instruments(planet if planet != "" else "homecoming")
	return bool(_music.call("play_track", id))


func stop_track() -> void:
	if _music:
		_music.call("stop_track")


## [camp] For songs played outside the score (recorded song files, the radio's library): true
## silences the mood score and its stingers at once; false fades the score back in from silence.
## Composed radio tracks (play_track) cut the score by themselves.
func mute_score(on: bool) -> void:
	if _music:
		_music.call("set_muted", on)


func is_score_muted() -> bool:
	return bool(_music.get("muted")) if _music else false


## The composed track playing now ("" for a generative piece or a silence gap).
func get_music_track() -> String:
	return "" if _music == null or bool(_music.call("in_gap")) else str(_music.call("current_track"))


## Composed track ids, all or for one planet ("verdance", "ochre", ...; "" = all).
func music_track_ids(planet: String = "") -> Array[String]:
	var out: Array[String] = []
	for id: String in MusicTracks.TRACKS:
		if planet == "" or str(MusicTracks.TRACKS[id]["planet"]) == planet:
			out.append(id)
	return out


## The display title of a track (English data; tr() it at display time). "" if unknown.
func music_track_title(id: String) -> String:
	return str(MusicTracks.TRACKS[id]["title"]) if MusicTracks.TRACKS.has(id) else ""


func planet_theme_ids() -> Array[String]:
	return PlanetThemes.IDS.duplicate()


func _apply_theme(id: String, resto: float) -> void:
	if _music == null:
		return
	_ensure_instruments(id)
	_music.call("set_theme", id)
	if _ambience:
		_ambience.call("set_planet", _planet_id if _hold_id == "" else id)
	_apply_resto(resto)


## Builds instrument group `group` (a planet id, "groove" or "homecoming") if any is missing.
func _ensure_instruments(group: String) -> void:
	for n: String in PlanetSynth.NEEDS.get(group, []):
		if not _music_samples.has(n):
			var extra: Dictionary = PlanetSynth.build(group, _music_samples)
			_music_samples.merge(extra)
			if _music_voices:
				_music_voices.call("add_samples", extra)
			return


func _apply_resto(x: float) -> void:
	if _music:
		_music.call("set_restoration", x)
	if _ambience:
		_ambience.call("set_restoration", x)


## [tunes] The song director (audio/tunes_director.gd) hushes the synth score while a song plays
## or the shuffle owns the quiet between songs. Stingers still play in the gaps.
func tunes_hush(on: bool) -> void:
	_tunes_hush = on


func is_tunes_hushed() -> bool:
	return _tunes_hush


func get_music_intensity() -> float:
	return float(_music.get("intensity")) if _music else 0.0


## Short musical stinger built from the current chord: "upgrade", "hex_clean", "first_sprout",
## "robot_built", "level_up". Routed to the Music bus.
func music_sting(sting_name: String) -> void:
	if _tunes_hush and Tunes.now_playing() != "":  # [tunes] no synth stingers over a song
		return
	if _music:
		_music.call("sting", sting_name)
		if sound_log:
			sound_log.call("played", "sting:" + sting_name, "Music", 0.0, 2.0)


func _process(delta: float) -> void:
	_sync_world_pause()  # [v8pause]
	game_t += delta
	if not _music:
		return
	# Real time, so Engine.time_scale (autoplay) never changes the tempo.
	var now: int = Time.get_ticks_usec()
	var dt: float = (now - _music_last_us) / 1000000.0
	_music_last_us = now
	step_hush(dt)  # [eggs2]
	_music.set("enabled", music_enabled and not _tunes_hush)  # [tunes]
	_music.call("update", dt)
	if _music_lpf:
		_music_lpf.cutoff_hz = float(_music.get("lpf_cutoff"))
	# [sound] Voice ducking: ease toward the target, touching the buses only while it moves.
	var want: float = 1.0 if now < _duck_until_us else 0.0
	if want != _duck:
		_duck = move_toward(_duck, want, dt / maxf(0.01, SoundCfg.duck("attack_s", DUCK_ATTACK_S) if want > _duck else SoundCfg.duck("release_s", DUCK_RELEASE_S)))
		apply_volumes()


# --- [v8pause] Pause: the world goes quiet ------------------------------------------
## Owner item 78: "when i pause there is still sound coming out of game for the animation". This
## autoload (and the ambience beds, the rocket...) runs with PROCESS_MODE_ALWAYS, so Godot's own
## pause never paused its players: one-shots rang out, the beam hum and the ambience beds and
## their birds kept going, and a story cinematic's pause (StoryPause: Engine.time_scale = 0, the
## tree is not paused) paused no sound at all. Now, while the tree is paused or a hold is set
## (hold_world), every playing player on a world bus (anything but PAUSE_KEEP_BUSES) anywhere in
## the tree is stream-paused, and resumes where it was on unpause. Players that start while paused
## (menu feedback) play. Music and songs keep their own design (they play on in the pause menu;
## a paused cinematic holds its song, TunesDirector.set_paused).
const PAUSE_KEEP_BUSES: Array[String] = ["UI", "Music", "Songs"]
var _world_holds: Dictionary = {}  # owner id -> true
var _world_paused: bool = false
var _held: Array[WeakRef] = []


## Holds the world's sound paused for `owner_id` (StoryPause) until released.
func hold_world(owner_id: String, on: bool) -> void:
	if on:
		_world_holds[owner_id] = true
	else:
		_world_holds.erase(owner_id)
	_sync_world_pause()


func is_world_paused() -> bool:
	return _world_paused


## True when `p` is a world player kept quiet by the pause: callers must not play() it then.
func holds(p: Node) -> bool:
	return _world_paused and not str(p.get("bus")) in PAUSE_KEEP_BUSES


func _sync_world_pause() -> void:
	var want: bool = (is_inside_tree() and get_tree().paused) or not _world_holds.is_empty()
	if want == _world_paused:
		return
	_world_paused = want
	if want:
		_held.clear()
		for p: Node in world_players(get_tree().root):
			if bool(p.get("playing")):
				p.set("stream_paused", true)
				_held.append(weakref(p))
	else:
		for w: WeakRef in _held:
			var p: Node = w.get_ref() as Node
			if p != null and is_instance_valid(p):
				p.set("stream_paused", false)
		_held.clear()


## Every AudioStreamPlayer / 2D / 3D under `root` on a world bus (not UI, music or songs).
static func world_players(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if (n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D) and not str(n.get("bus")) in PAUSE_KEEP_BUSES:
			out.append(n)
		stack.append_array(n.get_children())
	return out


# --- Synthesis ----------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop_: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop_:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Fades the first and last few ms to avoid clicks.
func _declick(b: PackedFloat32Array) -> PackedFloat32Array:
	@warning_ignore("integer_division")
	var n: int = mini(int(0.004 * RATE), b.size() / 2)
	for i: int in n:
		var g: float = float(i) / n
		b[i] *= g
		b[b.size() - 1 - i] *= g
	return b


func _add(sound: String, b: PackedFloat32Array) -> void:
	if not _sounds.has(sound):
		_sounds[sound] = []
	(_sounds[sound] as Array).append(_wav(_declick(b)))


func _generate_all() -> void:
	# Beam hum: a soft, loopable sci-fi drone (whole cycles per second so it loops seamlessly).
	var hum := _buf(1.0)
	for i: int in hum.size():
		var t: float = float(i) / RATE
		var trem: float = 0.8 + 0.2 * sin(TAU * 6.0 * t)
		hum[i] = (sin(TAU * 110.0 * t) * 0.3 + sin(TAU * 220.0 * t + 0.3 * sin(TAU * 3.0 * t)) * 0.4 \
			+ sin(TAU * 331.0 * t) * 0.12 + sin(TAU * 662.0 * t) * 0.06) * trem * 0.35
	_loops["beam_hum"] = _wav(hum, true)
	# Clink: small metallic bits flying into the compartment.
	for f: float in [1750.0, 2050.0, 2400.0, 1600.0]:
		var b := _buf(0.2)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.76 * t) + 0.25 * sin(TAU * f * 5.4 * t)) * exp(-t * 28.0) * 0.32
		_add("clink", b)
	# Crunch: compaction. Low thump + crackle.
	for v: int in 3:
		var b := _buf(0.45)
		var lp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			var thump: float = sin(TAU * (90.0 - 50.0 * t) * t) * exp(-t * 9.0) * 0.7
			var n: float = _rng.randf_range(-1.0, 1.0)
			lp += (n - lp) * (0.35 + 0.1 * v)
			var crackle: float = lp * (0.6 if _rng.randf() < 0.08 else 0.18) * exp(-t * 5.0)
			b[i] = thump + crackle
		_add("crunch", b)
	# Steam hiss.
	for v: int in 3:
		var b := _buf(0.6)
		var lp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.55 + 0.1 * v)
			b[i] = lp * minf(t * 40.0, 1.0) * exp(-t * 5.0) * 0.35
		_add("steam", b)
	# Pop: cube pops out of the hatch / sprouts.
	for f0: float in [900.0, 1050.0, 800.0]:
		var b := _buf(0.12)
		var ph: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			ph += TAU * lerpf(f0, 220.0, t / 0.12) / RATE
			b[i] = sin(ph) * exp(-t * 25.0) * 0.6
		_add("pop", b)
	# Chime: hex flips clean (bright arpeggio).
	for root: float in [1046.5, 1174.7, 987.8]:
		var b := _buf(1.4)
		var ratios: Array[float] = [1.0, 1.26, 1.498, 2.0]
		for k: int in ratios.size():
			var start: int = int(k * 0.075 * RATE)
			var f: float = root * ratios[k]
			for i: int in range(start, b.size()):
				var t: float = float(i - start) / RATE
				b[i] += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 3.0 * t)) * exp(-t * 3.2) * 0.16
		_add("chime", b)
	# Coin: cash-in blip.
	for f: float in [988.0, 1046.5, 1108.7]:
		var b := _buf(0.22)
		for i: int in b.size():
			var t: float = float(i) / RATE
			var ff: float = f if t < 0.05 else f * 1.335
			b[i] = (sin(TAU * ff * t) + 0.25 * sin(TAU * ff * 3.0 * t)) * exp(-t * 14.0) * 0.32
		_add("coin", b)
	# Click: UI and button presses.
	for f: float in [2200.0, 2600.0, 1900.0]:
		var b := _buf(0.05)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (sin(TAU * f * t) * 0.5 + _rng.randf_range(-0.5, 0.5)) * exp(-t * 120.0) * 0.5
		_add("click", b)
	# Chunky mechanical buy click.
	for f: float in [140.0, 160.0, 125.0]:
		var b := _buf(0.18)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (sin(TAU * f * t) * exp(-t * 30.0) * 0.8 + _rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.4)
		_add("buy", b)
	# Squeak: treads starting/stopping.
	for f: float in [1300.0, 1500.0, 1150.0]:
		var b := _buf(0.2)
		var ph: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			ph += TAU * (f + 400.0 * t + 60.0 * sin(TAU * 32.0 * t)) / RATE
			b[i] = sin(ph) * sin(PI * t / 0.2) * 0.12
		_add("squeak", b)
	# Buzz: compartment full / can't do that.
	for f: float in [110.0, 98.0, 123.0]:
		var b := _buf(0.16)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (1.0 if sin(TAU * f * t) > 0.0 else -1.0) * 0.12 * exp(-t * 6.0)
		_add("buzz", b)
	# Ding: entering the Perfect band.
	for f: float in [1568.0, 1661.2, 1480.0]:
		var b := _buf(0.5)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.0 * t)) * exp(-t * 7.0) * 0.28
		_add("ding", b)
	# Thud: cube lands.
	for f: float in [140.0, 120.0, 165.0]:
		var b := _buf(0.16)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (sin(TAU * (f - 200.0 * t) * t) * 0.7 + _rng.randf_range(-0.3, 0.3)) * exp(-t * 26.0)
		_add("thud", b)
	# Whoosh: things flying, suction into depot.
	for v: int in 3:
		var b := _buf(0.35)
		var lp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.05 + 0.25 * t / 0.35 + 0.03 * v)
			b[i] = lp * sin(PI * t / 0.35) * 0.6
		_add("whoosh", b)
	# Beep: Patch's voice.
	for pair: Vector2 in [Vector2(880.0, 1320.0), Vector2(1100.0, 990.0), Vector2(740.0, 1175.0), Vector2(990.0, 1480.0)]:
		var b := _buf(0.22)
		for i: int in b.size():
			var t: float = float(i) / RATE
			var f: float = pair.x if t < 0.1 else pair.y
			var s: float = sin(TAU * f * t)
			b[i] = (s + 0.3 * signf(s)) * 0.14 * (1.0 if t < 0.2 else 0.0)
		_add("beep", b)
	# Sparkle: perfect cubes, purchases.
	for v: int in 3:
		var b := _buf(0.7)
		for k: int in 6:
			var start: int = int(_rng.randf_range(0.0, 0.35) * RATE)
			var f: float = _rng.randf_range(2500.0, 4200.0)
			for i: int in range(start, b.size()):
				var t: float = float(i - start) / RATE
				b[i] += sin(TAU * f * t) * exp(-t * 18.0) * 0.1
		_add("sparkle", b)
	# Detector: a clean, slightly sci-fi ping with a quick downward chirp.
	for f: float in [1480.0, 1760.0, 1320.0]:
		var b := _buf(0.12)
		var ph: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			ph += TAU * (f * (1.0 + 0.25 * exp(-t * 60.0))) / RATE
			b[i] = (sin(ph) + 0.25 * sin(ph * 2.0)) * exp(-t * 32.0) * 0.4
		_add("detector", b)
	# Dig: shovel-ish soil crunch.
	for v: int in 3:
		var b := _buf(0.35)
		var lp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			lp += (_rng.randf_range(-1.0, 1.0) - lp) * (0.12 + 0.04 * v)
			b[i] = (lp * 2.2 * (0.6 if _rng.randf() < 0.9 else 1.6) + sin(TAU * 70.0 * t) * 0.3) * exp(-t * 9.0)
		_add("dig", b)
	# Hydraulic: pressure hiss that builds then vents.
	for v: int in 3:
		var b := _buf(1.1)
		var lp: float = 0.0
		var hp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			var n: float = _rng.randf_range(-1.0, 1.0)
			lp += (n - lp) * (0.25 + 0.05 * v)
			hp = lp - hp * 0.2
			var env: float = smoothstep(0.0, 0.15, t) * (0.6 + 0.4 * smoothstep(0.5, 0.8, t)) * (1.0 - smoothstep(0.9, 1.1, t))
			var pump: float = sin(TAU * (48.0 + 10.0 * t) * t) * 0.25 * (1.0 - smoothstep(0.6, 0.9, t))
			b[i] = (hp * 0.35 + pump) * env
		_add("hydraulic", b)
	# Groan: metal under stress (slow, detuned resonances).
	for v: int in 3:
		var b := _buf(1.0)
		var f0: float = 55.0 + v * 9.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			var wob: float = 1.0 + 0.04 * sin(TAU * 3.1 * t) + 0.02 * sin(TAU * 7.3 * t)
			var s1: float = sin(TAU * f0 * wob * t) + 0.5 * sin(TAU * f0 * 2.03 * wob * t) + 0.25 * sin(TAU * f0 * 3.97 * t)
			b[i] = tanh(s1 * 1.6) * 0.22 * smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.7, 1.0, t))
		_add("groan", b)
	# Clunk: bale hitting the hatch lip and ground.
	for v: int in 3:
		var b := _buf(0.4)
		for i: int in b.size():
			var t: float = float(i) / RATE
			var f: float = 70.0 + v * 12.0
			# [v8snd] less sub body, a knock small speakers can play (was 100% under 80 Hz)
			b[i] = (sin(TAU * f * t) * 0.5 + sin(TAU * f * 3.1 * t) * 0.3 * exp(-t * 18.0) \
				+ _rng.randf_range(-0.4, 0.4) * exp(-t * 40.0)) * exp(-t * 11.0)
		_add("clunk", b)
	# Servo: small arm motor whir.
	for v: int in 3:
		var b := _buf(0.3)
		var ph: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			ph += TAU * (380.0 + 220.0 * sin(PI * t / 0.3) + v * 40.0) / RATE
			var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0
			b[i] = saw * 0.06 * sin(PI * t / 0.3)
		_add("servo", b)
	# Blip: WREN's voice, a soft filtered tone per character.
	for f: float in [620.0, 700.0, 780.0, 660.0]:
		var b := _buf(0.07)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = (sin(TAU * f * t) * 0.7 + sin(TAU * f * 1.5 * t) * 0.2) * sin(PI * t / 0.07) * 0.18
		_add("blip", b)
	# Bird: short trills (FM chirps) for returning wildlife.
	for v: int in 4:
		var b := _buf(0.5)
		var ph: float = 0.0
		var notes_: int = 2 + v
		for i: int in b.size():
			var t: float = float(i) / RATE
			var k: int = int(t / 0.5 * notes_)
			var lt: float = fmod(t, 0.5 / notes_) / (0.5 / notes_)
			var f: float = 2600.0 + 900.0 * sin(TAU * lt) + 300.0 * k + 200.0 * v
			ph += TAU * f / RATE
			b[i] = sin(ph) * sin(PI * lt) * 0.18
		_add("bird", b)
	# Fanfare: milestones.
	var fan := _buf(1.6)
	var notes: Array[float] = [523.25, 659.25, 783.99, 1046.5]
	for k: int in notes.size():
		var start: int = int(k * 0.12 * RATE)
		for i: int in range(start, fan.size()):
			var t: float = float(i - start) / RATE
			var f: float = notes[k]
			fan[i] += (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) + 0.15 * sin(TAU * f * 3.0 * t)) * exp(-t * 2.2) * 0.13
	_add("fanfare", fan)
	_generate_rocket()
	_generate_feel()  # [first]


## [first] Core-loop feedback: a soft two-note upgrade confirm, a deep bale thunk, a tiny tick for
## count-ups, and a low airy sweep for the ground reveal.
func _generate_feel() -> void:
	for root: float in [659.25, 698.46, 622.25]:
		var b := _buf(0.6)
		for i: int in b.size():
			var t: float = float(i) / RATE
			var v: float = (sin(TAU * root * t) + 0.3 * sin(TAU * root * 2.0 * t)) * exp(-t * 6.0) * 0.18
			if t > 0.075:
				var t2: float = t - 0.075
				var f2: float = root * 1.4983
				v += (sin(TAU * f2 * t2) + 0.25 * sin(TAU * f2 * 2.0 * t2)) * exp(-t2 * 4.5) * 0.2
			b[i] = v
		_add("confirm", _declick(b))
	for f: float in [62.0, 56.0, 68.0]:
		var b := _buf(0.32)
		var lp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.08)
			var body: float = sin(TAU * (f + 50.0 * exp(-t * 30.0)) * t) * exp(-t * 11.0)
			var knock: float = sin(TAU * (f * 2.9 + 80.0 * exp(-t * 30.0)) * t) * exp(-t * 20.0)  # [v8snd] was 100% under 80 Hz
			b[i] = (body * 0.45 + knock * 0.35 + lp * 0.5 * exp(-t * 22.0)) * 0.55
		_add("thunk", _declick(b))
	for f: float in [2400.0, 2550.0, 2300.0]:
		var b := _buf(0.035)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] = sin(TAU * f * t) * exp(-t * 140.0) * 0.16
		_add("tick", b)
	for v: int in 3:
		var b := _buf(1.4)
		var lp: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.03 + 0.02 * v)
			var env: float = sin(PI * clampf(t / 1.4, 0.0, 1.0)) * exp(-t * 0.8)
			b[i] = lp * env * 0.5
		_add("sweep", _declick(b))


## Rocket launch layer: a deep rumbling roar (overlap several for a sustained burn), a two-tone
## launch siren, and an energy charge-up whine.
func _generate_rocket() -> void:
	for v: int in 2:
		var b := _buf(2.6)
		var lp: float = 0.0
		var lp2: float = 0.0
		for i: int in b.size():
			var t: float = float(i) / RATE
			var n: float = _rng.randf_range(-1.0, 1.0)
			lp += (n - lp) * (0.04 + 0.01 * v)
			lp2 += (lp - lp2) * 0.2
			var crackle: float = n * (0.5 if _rng.randf() < 0.012 else 0.04)
			var rum: float = sin(TAU * (38.0 + 4.0 * v) * t + sin(TAU * 3.0 * t) * 2.0) * 0.25
			var env: float = smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(2.0, 2.6, t))
			b[i] = tanh((lp2 * 5.0 + rum + crackle) * 1.4) * 0.55 * env
		_add("roar", b)
	var sb := _buf(1.6)
	var ph: float = 0.0
	for i: int in sb.size():
		var t: float = float(i) / RATE
		var f: float = 620.0 + 330.0 * (0.5 - 0.5 * cos(TAU * t / 1.6))
		ph += TAU * f / RATE
		var sq: float = sin(ph) + 0.3 * sin(ph * 2.0) + 0.15 * sin(ph * 3.0)
		sb[i] = sq * 0.11 * smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(1.5, 1.6, t))
	_add("siren", sb)
	var cb := _buf(2.2)
	var ph2: float = 0.0
	for i: int in cb.size():
		var t: float = float(i) / RATE
		ph2 += TAU * (180.0 + 900.0 * pow(t / 2.2, 1.6)) / RATE
		cb[i] = (sin(ph2) * 0.6 + sin(ph2 * 1.503) * 0.3) * 0.12 * smoothstep(0.0, 1.8, t) * (1.0 - smoothstep(2.1, 2.2, t))
	_add("charge", cb)
