extends Node
## [tunes] Plays the owner's songs (systems/tunes.gd) on their own "Songs" bus, next to the synth
## score (audio/music_director.gd). A child of the Audio autoload ("TunesDirector").
##
## Contexts (set_context):
## - "menu": the main theme on the title screen, looping with a crossfade.
## - "intro": The Fall of LM-1 from the intro's first frame (intro_start), paused with the
##   cinematic (set_paused), faded out at the landing (intro_land).
## - "play": the background shuffle. Owned songs that fit the planet and the moment, one at a time,
##   with quiet gaps (only the ambience bed) between them. Story moods (cinematic, homecoming) hand
##   the music back to the synth score. The CD player (set_radio) overrides it: one song on repeat,
##   or the whole collection shuffled back to back with crossfades.
## While a song plays or the shuffle owns the silence, the synth score is hushed
## (Audio.tunes_hush), so the two never play over each other. When no song file fits, nothing is
## hushed and the synth score plays as before (the fallback).
## Real time, so the autoplay time scale never speeds songs up. Nothing plays while the loading
## screen is up.

signal song_started(id: String)

const BUS: String = "Songs"
const SONG_DB: float = -7.0  # the songs are mastered much louder than the synth score
const MAIN: String = "greenfall_main"
const INTRO: String = "fall_of_lm1"
const THEMED: Array[String] = ["explore", "base", "night"]

var context: String = "none"
var radio: String = ""  # "" (background), "shuffle" or a song id
var paused: bool = false
## Pre-Glim: the CD player's songs come from the CD player, softer far from it.
var radio_source: Node3D
var listener: Node3D
var gap_left: float = 0.0
var recent: Array[String] = []
var rng := RandomNumberGenerator.new()
## Tests drive tick() by hand and run without the loading screen.
var manual: bool = false
var hush: bool = false

var _p: Array[AudioStreamPlayer] = []
var _slot: Array[Dictionary] = []  # per player: id, t, len, gain, target, rate, loop
var _main: int = 0
var _last_us: int = 0
var _was_loading: bool = false
var _bus_db: float = 999.0
var _pool_t: float = 0.0
var _pool_ok: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, "Master")
	for i: int in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.name = "Song%d" % i
		add_child(p)
		_p.append(p)
		_slot.append(_empty())
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	for p: AudioStreamPlayer in _p:
		p.stop()
		p.stream = null
	Tunes.clear_cache()  # static caches would outlive the scene tree at quit


static func _empty() -> Dictionary:
	return {"id": "", "t": 0.0, "len": 0.0, "gain": 0.0, "target": 0.0, "rate": 1.0, "loop": false}


# --- Public ------------------------------------------------------------------------------

## "menu", "intro", "play" or "none".
func set_context(c: String) -> void:
	if c == context:
		return
	context = c
	print("[tunes] context %s" % c)
	if c == "play":
		_start_gap(true)
	elif c != "intro":
		_fade_all(1.5)


## The CD player / Glim: "" (background), "shuffle" or an owned song id.
func set_radio(mode: String) -> void:
	if mode == radio:
		return
	radio = mode
	print("[tunes] CD player: %s" % (mode if mode != "" else "off"))
	if mode == "":
		_fade_all(2.0)
		_start_gap(true)
	elif mode != Tunes.SHUFFLE:
		_start(mode, 1.5, true)
	else:
		_start(Tunes.pick_any(recent, rng), 1.5, false)


## The intro's first frame: The Fall of LM-1 from the top.
func intro_start() -> void:
	context = "intro"
	paused = false
	if Tunes.has_file(INTRO):
		_start(INTRO, 0.25, false)


## The pod lands: the score fades out.
func intro_land(fade: float = 4.0) -> void:
	_fade_all(fade)


func set_paused(on: bool) -> void:
	if on == paused:
		return
	paused = on
	for p: AudioStreamPlayer in _p:
		p.stream_paused = on


## The song audible now ("" in a gap or when nothing plays).
func current() -> String:
	var s: Dictionary = _slot[_main] if not _slot.is_empty() else {}
	return str(s.get("id", "")) if float(s.get("target", 0.0)) > 0.0 else ""


func position() -> float:
	return float(_slot[_main]["t"]) if current() != "" else 0.0


# --- Loop --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var dt: float = clampf((now - _last_us) / 1000000.0, 0.0, 0.25)
	_last_us = now
	if not manual:
		tick(dt)


func tick(dt: float) -> void:
	var loading: bool = _loading()
	if loading and not _was_loading:
		_fade_all(0.6)
	if _was_loading and not loading and context == "play":
		_start_gap(true)
	_was_loading = loading
	if not loading:
		_drive(dt)
	_advance(dt)
	_apply_bus()
	var want: bool = _wants_hush()
	if want != hush:
		hush = want
		if Audio.has_method("tunes_hush"):
			Audio.call("tunes_hush", want)


func _loading() -> bool:
	if manual:
		return false
	var ld: Node = get_node_or_null("/root/Loader")
	return ld != null and ld.has_method("busy") and bool(ld.call("busy"))


func _drive(dt: float) -> void:
	var s: Dictionary = _slot[_main]
	var playing: bool = str(s["id"]) != "" and float(s["target"]) > 0.0
	var xf: float = float(Tunes.cfg().get("crossfade_s", 4.0))
	match context:
		"menu":
			if not Tunes.has_file(MAIN):
				return
			if not playing:
				_start(MAIN, 2.5, true)
			elif float(s["t"]) >= float(s["len"]) - xf:
				_start(MAIN, xf, true)  # loop with a crossfade
		"play":
			if not THEMED.has(Audio.get_music_mood()):
				if playing:
					_fade_all(2.0)
				gap_left = maxf(gap_left, 4.0)
				return
			if radio != "":
				_drive_radio(s, playing, xf)
				return
			if playing:
				if float(s["t"]) >= float(s["len"]) - 3.0:
					_fade_all(3.0)
					_start_gap(false)
				return
			gap_left -= dt
			if gap_left > 0.0:
				return
			var id: String = Tunes.pick_next(_planet(), Audio.get_music_mood(), Audio.get_restoration(), recent, rng)
			if id == "":
				gap_left = 5.0  # nothing fits (yet): the synth score plays; look again soon
				return
			_start(id, 2.0, false)


func _drive_radio(s: Dictionary, playing: bool, xf: float) -> void:
	if radio == Tunes.SHUFFLE:
		if not playing or float(s["t"]) >= float(s["len"]) - xf:
			var id: String = Tunes.pick_any(recent, rng)
			if id != "":
				_start(id, xf if playing else 1.5, false)
	elif not playing:
		_start(radio, 1.5, true)
	elif float(s["t"]) >= float(s["len"]) - xf:
		_start(radio, xf, true)


func _planet() -> String:
	return Audio.get_planet_theme()


func _advance(dt: float) -> void:
	var mul: float = 1.0 if Audio.music_enabled else 0.0
	if radio != "" and context == "play":
		mul *= _radio_falloff()
	for i: int in _p.size():
		var s: Dictionary = _slot[i]
		if str(s["id"]) == "":
			continue
		if not paused:
			s["t"] = float(s["t"]) + dt
		s["gain"] = move_toward(float(s["gain"]), float(s["target"]), dt * float(s["rate"]))
		var p: AudioStreamPlayer = _p[i]
		p.volume_db = SONG_DB + linear_to_db(maxf(float(s["gain"]) * mul, 0.0001))
		var over: bool = float(s["len"]) > 0.0 and float(s["t"]) >= float(s["len"])
		if (float(s["gain"]) <= 0.0 and float(s["target"]) <= 0.0) or over:
			p.stop()
			p.stream = null
			_slot[i] = _empty()


## Pre-Glim the CD player is a box in the yard: full volume near it, a soft 30% across the map.
func _radio_falloff() -> float:
	if Tunes.glim_music() or radio_source == null or not is_instance_valid(radio_source) \
			or listener == null or not is_instance_valid(listener) or not radio_source.is_inside_tree() or not listener.is_inside_tree():
		return 1.0
	var d: float = radio_source.global_position.distance_to(listener.global_position)
	return lerpf(1.0, 0.3, smoothstep(18.0, 70.0, d))


func _apply_bus() -> void:
	var idx: int = AudioServer.get_bus_index(BUS)
	if idx < 0:
		return
	var v: float = clampf(Settings.music_volume, 0.0, 1.0)
	var db: float = maxf(-80.0, linear_to_db(maxf(v, 0.0001))) - 7.0 * Audio.get_duck()
	if absf(db - _bus_db) > 0.05:
		_bus_db = db
		AudioServer.set_bus_mute(idx, v <= 0.0001)
		AudioServer.set_bus_volume_db(idx, db)


func _wants_hush() -> bool:
	for s: Dictionary in _slot:
		if float(s["gain"]) > 0.0 or float(s["target"]) > 0.0:
			return true
	match context:
		"menu":
			return Tunes.has_file(MAIN)
		"intro":
			return Tunes.has_file(INTRO)
		"play":
			if not THEMED.has(Audio.get_music_mood()):
				return false
			if radio != "":
				return not Tunes.found().is_empty()
			return _pool_has_any()
	return false


## Cached for ~2 s: does any owned song fit the moment (else the synth score fills in)?
func _pool_has_any() -> bool:
	if _pool_t <= 0.0 or manual:
		_pool_t = 2.0
		_pool_ok = false
		for id: String in Tunes.found():
			if Tunes.fits(id, _planet(), Audio.get_music_mood(), Audio.get_restoration()):
				_pool_ok = true
				break
	else:
		_pool_t -= 0.016
	return _pool_ok


func _start_gap(first: bool) -> void:
	var r: Array = Tunes.cfg().get("first_gap_s" if first else "gap_s", [10, 25] if first else [30, 90])
	gap_left = rng.randf_range(float(r[0]), float(r[1]))


func _fade_all(fade: float) -> void:
	for s: Dictionary in _slot:
		if str(s["id"]) != "":
			s["target"] = 0.0
			s["rate"] = 1.0 / maxf(fade, 0.05)


## Starts `id` on the free player and crossfades the old one out over `fade` seconds.
func _start(id: String, fade: float, loop: bool) -> void:
	if id == "":
		return
	var st: AudioStream = Tunes.stream(id)
	if st == null:
		return
	_fade_all(fade)
	var k: int = 1 - _main
	if str(_slot[k]["id"]) != "":
		_p[k].stop()
	_main = k
	var len_s: float = st.get_length()
	_slot[k] = {"id": id, "t": 0.0, "len": len_s if len_s > 1.0 else 180.0, "gain": 0.0, "target": 1.0,
		"rate": 1.0 / maxf(fade, 0.05), "loop": loop}
	_p[k].stream = st
	_p[k].stream_paused = paused
	_p[k].volume_db = -80.0
	_p[k].play()
	if recent.is_empty() or recent[recent.size() - 1] != id:
		recent.append(id)
	while recent.size() > 6:
		recent.remove_at(0)
	print("[tunes] now playing %s (%s%s)" % [id, context, (", CD player " + radio) if radio != "" and context == "play" else ""])
	song_started.emit(id)
