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
## A scratched CD: plays once, then breaks (Tunes.break_scratched on finish).
signal scratch_started(id: String)
signal scratch_finished(id: String)

const BUS: String = "Songs"
const SONG_DB: float = -7.0  # fallback for cfg "song_db": the songs are mastered much louder than the synth score
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
var scratch: String = ""  # the scratched CD playing its one play
## The title screen's songs (set_menu_pool): a random one each time, crossfading to the next.
var menu_pool: Array[String] = []
var menu_first: String = ""  # plays first (the main theme on the very first launch)
var menu_main_weight: float = 1.0
var _scratch_t: float = 0.0
## [v6sound] A story moment's song ("launch", "ending", "base_restored") playing once over the shuffle.
var moment: String = ""
var _moment_id: String = ""
var _ending_played: bool = false
var _crackle: AudioStreamPlayer

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
	_crackle = AudioStreamPlayer.new()
	_crackle.bus = BUS
	_crackle.name = "Crackle"
	_crackle.stream = crackle_stream()
	add_child(_crackle)
	_last_us = Time.get_ticks_usec()


## A gentle disc crackle: a soft hiss with a few pops and two skips (the scratched CD starting).
static func crackle_stream() -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * 1.6)
	var rng_ := RandomNumberGenerator.new()
	rng_.seed = 7171
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp: float = 0.0
	for i: int in n:
		var t: float = float(i) / rate
		lp += (rng_.randf_range(-1.0, 1.0) - lp) * 0.3
		var env: float = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(1.1, 1.6, t))
		var v: float = lp * 0.05 * env
		if rng_.randf() < 0.0016:
			v += rng_.randf_range(-0.55, 0.55) * env
		for skip: float in [0.42, 0.78]:
			if t > skip and t < skip + 0.03:
				v += sin(TAU * 1900.0 * t) * 0.12 * (1.0 - (t - skip) / 0.03)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


## A scratched CD's one play: the other music fades out, a crackle, the song once, then it breaks.
func play_once(id: String) -> bool:
	if scratch != "" or not Tunes.has_file(id) or Tunes.stream(id) == null:
		return false
	scratch = id
	_scratch_t = 0.0
	_crackle.play()
	_start(id, 1.6, false)
	print("[tunes] scratched CD: %s (last play)" % id)
	scratch_started.emit(id)
	return true


func _finish_scratch() -> void:
	var id: String = scratch
	scratch = ""
	_fade_all(1.2)
	Tunes.break_scratched(id)
	print("[tunes] scratched CD broke: %s" % id)
	scratch_finished.emit(id)
	if context == "play" and radio == "":
		_start_gap(false)


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
	var was: String = context
	context = c
	print("[tunes] context %s" % c)
	if c == "play":
		_start_gap(true)
		if was == "intro":  # [v1menu] the pod has landed: a few quiet minutes before any song
			_start_gap_cfg("landing_gap_s", [150, 240])
	elif c != "intro":
		_fade_all(1.5)


## The CD player / Glim: "" (background), "shuffle" or an owned song id.
func set_radio(mode: String) -> void:
	if mode == radio:
		return
	radio = mode
	print("[tunes] CD player: %s" % (mode if mode != "" else "off"))
	if scratch != "":
		return  # the scratched CD finishes its one play first
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
	var pool: Array[String] = Tunes.moment_songs("intro", _planet())
	if not pool.is_empty():
		_start(pool[0], 0.25, false)


## [v6sound] Plays a song marked for a story moment ("launch", "ending", "base_restored") once,
## whatever the shuffle is doing. False when no song with a file is marked for it here.
func play_moment(m: String) -> bool:
	if scratch != "":
		return false
	var pool: Array[String] = Tunes.moment_songs(m, _planet())
	while not pool.is_empty():
		var id: String = Tunes._weighted(pool, recent, rng, func(x: String) -> float: return float(Tunes.song(x).get("weight", 1.0)))
		if _start(id, 2.0, false):
			moment = m
			_moment_id = id
			return true
		pool.erase(id)
	return false


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
		if scratch != "":
			_finish_scratch()
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
	if scratch != "":
		_scratch_t += dt
		if _scratch_t > 1.0 and (str(s["id"]) != scratch or float(s["t"]) >= float(s["len"]) - 1.5):
			_finish_scratch()
		return
	if moment != "":  # [v6sound] a story moment's song plays to its end, then the usual quiet
		if str(s["id"]) == _moment_id and playing and float(s["t"]) < float(s["len"]) - 3.0:
			return
		moment = ""
		_moment_id = ""
		_fade_all(3.0)
		_start_gap(false)
		return
	match context:
		"menu":
			if not playing or float(s["t"]) >= float(s["len"]) - xf:
				var id: String = _pick_menu()
				if id != "":
					_start(id, xf if playing else 2.5, false)
		"play":
			if not THEMED.has(Audio.get_music_mood()):
				if Audio.get_music_mood() == "homecoming" and not _ending_played:  # [v6sound]
					_ending_played = true
					if play_moment("ending"):
						return
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
			if id == "" or not _start(id, 2.0, false):
				gap_left = 5.0  # nothing fits (yet), or the file would not load: look again soon


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


## Songs for the title screen. `first` plays first if set; `main_weight` favours the main theme.
func set_menu_pool(pool: Array[String], first: String = "", main_weight: float = 1.0) -> void:
	menu_pool = pool.duplicate()
	menu_first = first
	menu_main_weight = main_weight


func _pick_menu() -> String:
	var pool: Array[String] = []
	for id: String in menu_pool:
		if Tunes.has_file(id):
			pool.append(id)
	if pool.is_empty():
		return Tunes.main_id() if Tunes.has_file(Tunes.main_id()) else ""
	if menu_first != "" and menu_first in pool:
		var f: String = menu_first
		menu_first = ""
		return f
	return Tunes.pick_main_rule(pool, recent, rng, func(_id: String) -> float: return 1.0)  # [v1menu]


func _planet() -> String:
	return str(Audio.call("get_planet_id")) if Audio.has_method("get_planet_id") else Audio.get_planet_theme()


func _advance(dt: float) -> void:
	var mul: float = 1.0 if Audio.music_enabled else 0.0
	if radio != "" and context == "play" and scratch == "":
		mul *= _radio_falloff()
	for i: int in _p.size():
		var s: Dictionary = _slot[i]
		if str(s["id"]) == "":
			continue
		if not paused:
			s["t"] = float(s["t"]) + dt
		s["gain"] = move_toward(float(s["gain"]), float(s["target"]), dt * float(s["rate"]))
		var p: AudioStreamPlayer = _p[i]
		AudioVol.set_db(p, float(s.get("db", SONG_DB)) + linear_to_db(maxf(float(s["gain"]) * mul, 0.0001)))  # [qafix] crash fix
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
	if scratch != "" or moment != "":
		return true
	for s: Dictionary in _slot:
		if float(s["gain"]) > 0.0 or float(s["target"]) > 0.0:
			return true
	match context:
		"menu":
			return not Tunes.available().is_empty()
		"intro":
			return not Tunes.moment_songs("intro", _planet()).is_empty()
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
	_start_gap_cfg("first_gap_s" if first else "gap_s", [20, 45] if first else [75, 180])


func _start_gap_cfg(key: String, fallback: Array) -> void:
	var r: Array = Tunes.rule(key, _planet(), fallback)  # [v6sound] a planet may set its own gaps
	gap_left = rng.randf_range(float(r[0]), float(r[1]))


func _fade_all(fade: float) -> void:
	for s: Dictionary in _slot:
		if str(s["id"]) != "":
			s["target"] = 0.0
			s["rate"] = 1.0 / maxf(fade, 0.05)


## Starts `id` on the free player and crossfades the old one out over `fade` seconds. False when
## the song has no file or it will not load (Tunes then skips it from now on).
func _start(id: String, fade: float, loop: bool) -> bool:
	if id == "":
		return false
	var st: AudioStream = Tunes.stream(id)
	if st == null:
		return false
	_fade_all(fade)
	var k: int = 1 - _main
	if str(_slot[k]["id"]) != "":
		_p[k].stop()
	_main = k
	var len_s: float = st.get_length()
	_slot[k] = {"id": id, "t": 0.0, "len": len_s if len_s > 1.0 else 180.0, "gain": 0.0, "target": 1.0,
		"rate": 1.0 / maxf(fade, 0.05), "loop": loop,
		"db": float(Tunes.cfg().get("song_db", SONG_DB)) + Tunes.trim_db(id)}
	_p[k].stream = st
	_p[k].stream_paused = paused
	_p[k].volume_db = -80.0
	_p[k].play()
	if recent.is_empty() or recent[recent.size() - 1] != id:
		recent.append(id)
		if scratch != id:
			Tunes.note_play(id)
	while recent.size() > 6:
		recent.remove_at(0)
	print("[tunes] now playing %s (%s%s)" % [id, context, (", CD player " + radio) if radio != "" and context == "play" else ""])
	song_started.emit(id)
	return true
