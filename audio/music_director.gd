extends RefCounted
## Generative, layered score for Greenfall.
##
## Two kinds of pieces share one sequencer:
## - Generative pieces (MOODS): a slow chord progression drives an evolving pad, a soft bass, a
##   felt-piano / kalimba melody built from call-and-answer phrases, bell shimmer and (only at
##   high intensity) a brushed shaker and a felted kick. Verdance's explore / night / base.
## - [sound] Composed tracks (audio/music_tracks.gd): an 8-chord progression, a motif (the hook)
##   re-fitted to each chord, a groove, a bassline and a form. Every planet has a rotating pool of
##   calm and active tracks; Verdance adds upbeat cleaning tracks. Busy play (`pulse_activity`)
##   picks the active ones and pushes their drums; night and base pick calm ones.
## Pieces rotate with silence gaps between them (only the air bed plays), like the quiet moments
## between tracks in a sandbox game. Layers fade with `intensity` (0..1) and `mood`; harmony and
## tempo switch at the next bar so changes always land musically.
##
## The director is backend-agnostic: it only calls `start(sample, pitch, gain) -> id`,
## `set_gain(id, gain)` and `stop(id)` on `backend`. At runtime that is audio/music_voices.gd
## (a pool of AudioStreamPlayers); tools/render_music.gd uses audio/music_offline_mixer.gd.

const Themes := preload("res://audio/planet_themes.gd")  # [sound]
const Tracks := preload("res://audio/music_tracks.gd")  # [sound]

const KEY_ROOT: int = 50  # D3: the generative score lives in D major so moods can crossfade.
const MAJOR: Array[int] = [0, 2, 4, 5, 7, 9, 11]
const STEPS: int = 16  # eighth notes per chord (2 bars of 4/4)

# Linear base gains (samples are normalized to 0.9 peak). Kept low: music sits under the SFX.
const G_PAD: float = 0.032  # per pad note
const G_BASS: float = 0.13
const G_MEL: float = 0.12
const G_BELL: float = 0.045
const G_SHAKER: float = 0.03
const G_KICK: float = 0.11
const G_AIR: float = 0.05
const G_STING: float = 0.12
const G_TEX: float = 0.06  # [sound] arpeggio / twinkle layer
const G_BLOOM: float = 0.022  # [sound] warm low pad that fills in as a planet is restored
const G_SNARE: float = 0.05  # [sound] track drums
const G_HAT: float = 0.026
const G_PERC: float = 0.05
const G_HIT: float = 0.05
const FADE_TIME: float = 4.0  # seconds for a layer to fade fully in or out

const LAYERS: Array[String] = ["pad", "air", "bass", "melody", "bell", "shaker", "kick", "texture"]
## [sound] Moods that rotate pieces (with gaps); the rest play one piece until the mood changes.
const THEMED_MOODS: Array[String] = ["explore", "base", "night"]
## [sound] Build-up multipliers per pass (cycle) for "build" tracks: slow, warm swells.
const BUILD: Dictionary = {
	"kick": [0.0, 0.0, 0.6, 1.0], "shaker": [0.0, 0.5, 0.8, 1.0], "bass": [0.0, 0.8, 1.0, 1.0],
	"bell": [0.5, 0.8, 1.0, 1.2], "bloom": [0.0, 0.5, 1.0, 1.2], "texture": [0.6, 0.9, 1.0, 1.0],
	"melody": [0.9, 1.0, 1.0, 1.1], "pad": [0.85, 1.0, 1.05, 1.15],
}
## [sound] The Greenfall motif (D major), as the intro's opening sting ("motif"). The homecoming
## track (audio/music_tracks.gd) quotes it in full.
const MOTIF_CALL: Array = [[0, 69], [2, 74], [6, 73], [8, 71], [10, 69], [14, 66]]

# Progressions are [root offset from the key, chord intervals]. All moods share the key.
const MOODS: Dictionary = {
	"explore": {  # Imaj7 - vi7 - IVmaj7 - V sus4
		"bpm": 72.0,
		"prog": [[0, [0, 4, 7, 11]], [9, [0, 3, 7, 10]], [5, [0, 4, 7, 11]], [7, [0, 5, 7, 10]]],
		"mix": {"pad": 1.0, "air": 1.0, "bass": 1.0, "melody": 1.0, "bell": 0.8, "shaker": 1.0, "kick": 1.0},
		"voice": "piano", "mel_lo": 62, "mel_hi": 79, "density": 0.6, "bright": 0.65,
		"pad_attack": 2.5, "lpf": 6500.0, "intensity": -1.0, "tacet": 0.2, "swell": false,
	},
	"night": {  # vi9 - IVmaj7 - ii9 - iii7: sparse, minor colour, darker
		"bpm": 60.0,
		"prog": [[9, [0, 3, 7, 10, 14]], [5, [0, 4, 7, 11]], [2, [0, 3, 7, 10, 14]], [4, [0, 3, 7, 10]]],
		"mix": {"pad": 0.9, "air": 1.3, "bass": 0.7, "melody": 0.75, "bell": 1.2, "shaker": 0.0, "kick": 0.0},
		"voice": "kalimba", "mel_lo": 59, "mel_hi": 74, "density": 0.35, "bright": 0.3,
		"pad_attack": 3.5, "lpf": 3000.0, "intensity": -1.0, "tacet": 0.4, "swell": false,
	},
	"base": {  # IVmaj7 - Imaj7 - ii7 - V sus4: cozy, near the workbench
		"bpm": 76.0,
		"prog": [[5, [0, 4, 7, 11]], [0, [0, 4, 7, 14]], [2, [0, 3, 7, 10]], [7, [0, 5, 7, 10]]],
		"mix": {"pad": 1.0, "air": 0.4, "bass": 1.0, "melody": 1.1, "bell": 0.6, "shaker": 0.8, "kick": 0.5},
		"voice": "piano", "mel_lo": 64, "mel_hi": 79, "density": 0.7, "bright": 0.5,
		"pad_attack": 2.5, "lpf": 5000.0, "intensity": -1.0, "tacet": 0.15, "swell": false,
	},
	"cinematic": {  # vi7 - IVmaj7 - I add9 - V sus4, slow and swelling
		"bpm": 56.0,
		"prog": [[9, [0, 3, 7, 10]], [5, [0, 4, 7, 11]], [0, [0, 4, 7, 14]], [7, [0, 5, 7, 10]]],
		"mix": {"pad": 1.6, "air": 0.3, "bass": 1.2, "melody": 0.7, "bell": 1.3, "shaker": 0.0, "kick": 0.0},
		"voice": "piano", "mel_lo": 66, "mel_hi": 81, "density": 0.35, "bright": 0.85,
		"pad_attack": 4.5, "lpf": 7500.0, "intensity": 0.65, "tacet": 0.1, "swell": true,
	},
	"menu": {  # Imaj7 - IVmaj7 - vi7 - iv6 (borrowed minor iv: hopeful, a little melancholy)
		"bpm": 66.0,
		"prog": [[0, [0, 4, 7, 11]], [5, [0, 4, 7, 11]], [9, [0, 3, 7, 10]], [5, [0, 3, 7, 9]]],
		"mix": {"pad": 1.0, "air": 0.8, "bass": 0.8, "melody": 0.9, "bell": 0.8, "shaker": 0.0, "kick": 0.0},
		"voice": "kalimba", "mel_lo": 62, "mel_hi": 78, "density": 0.45, "bright": 0.5,
		"pad_attack": 3.0, "lpf": 5000.0, "intensity": 0.45, "tacet": 0.25, "swell": false,
	},
	# [sound] The Homecoming ending. Plays the "homecoming" track (audio/music_tracks.gd); these
	# values only stand in until its first bar.
	"homecoming": {
		"bpm": 60.0,
		"prog": [[0, [0, 4, 7, 14]], [9, [0, 3, 7, 10]], [5, [0, 4, 7, 11]], [7, [0, 4, 7, 10]]],
		"mix": {"pad": 1.3, "air": 0.3, "bass": 1.1, "melody": 1.05, "bell": 1.1, "shaker": 0.5, "kick": 0.55},
		"voice": "piano", "mel_lo": 62, "mel_hi": 84, "density": 1.0, "bright": 0.85,
		"pad_attack": 4.0, "lpf": 8000.0, "intensity": 0.8, "tacet": 0.0, "swell": true,
	},
}

# 16-step rhythms ("x" = onset). Calls open a phrase; answers close it with a held note.
const CALLS: Array[String] = [
	"x.x.x.x.x...x...", "x...x.x.x.x.x...", "..x.x.x.x.x.x...", "x.xx..x.x...x...",
	"x...x.x.xx..x...", "x.x...x.x.x.x...", "....x.x.x.x.x.x.", "x..x..x.x...x...",
]
const ANSWERS: Array[String] = [
	"x.x.x.x.x.......", "x...x.x.x.......", "..x.x.x.x.......", "x.xx..x.x.......",
	"x.x.x...x.......", "....x.x.x.x.....",
]

var backend: Object
var samples: Dictionary
var rng := RandomNumberGenerator.new()
var enabled: bool = true
var intensity: float = 0.35
var mood: String = "explore"  # mix targets follow this immediately
var lpf_cutoff: float = 6500.0  # smoothed; the host applies it to the Music bus
var theme: String = "verdance"  # [sound] planet (picks the track pool)
var restoration: float = 0.0  # [sound] 0 ruined .. 1 restored (current planet)
var activity: float = 0.0  # [sound] 0..1, recent cleaning / building; decays over ~a minute
var gaps_enabled: bool = true  # [sound] silence between pieces
var forced_track: String = ""  # [sound] the radio: loop this track, no gaps
var muted: bool = false  # [camp] a song from outside the score plays (Audio.mute_score): stay silent

var _active: String = "explore"  # harmony / tempo follow this (switches on a bar line)
var _active_theme: String = "verdance"
var _track: String = ""  # [sound] current composed track ("" = the generative mood piece)
var _last_track: String = "-"
var _cycles_left: int = 5
var _gap_left: float = 0.0
var _resto_hi: bool = false  # [sound] restored choices (hysteresis around 0.5)
var _target: Dictionary = {}  # live mix targets
var _cur: Dictionary = {}  # harmony and parts, re-resolved per chord cycle
var _dirty: bool = true
var _cycle: int = -1
var _eff: float = 0.35
var _gains: Dictionary = {}
var _clock: float = 0.0
var _next_step_at: float = 0.0
var _step: int = 0
var _chord_i: int = -1
var _chord_pcs: Array[int] = []
var _chord_root_pc: int = 0
var _scale_pcs: Array[int] = []
var _bass_midi: int = 38
var _pads: Array[Dictionary] = []
var _air_id: int = -1
var _mel_line: Array = []
var _phrase_i: int = 0
var _tacet: bool = false
var _last_call: String = ""
var _mel_prev: int = 69
var _mel_dir: int = 1
var _mel_mute_until: float = 0.0
var _queue: Array[Dictionary] = []


func _init(p_samples: Dictionary, p_backend: Object, seed_value: int = 4242) -> void:
	samples = p_samples
	backend = p_backend
	rng.seed = seed_value
	for l: String in LAYERS:
		_gains[l] = 0.0
	_cur = resolve(_active)
	_target = _cur


## The plain generative piece for `p_mood`, with the default instrument keys filled in.
static func resolve(p_mood: String) -> Dictionary:
	var m: Dictionary = (MOODS.get(p_mood, MOODS["explore"]) as Dictionary).duplicate(true)
	m["key"] = KEY_ROOT
	m["mode"] = MAJOR
	m["pad"] = ["pad_warm", "pad_bright"]
	m["bass"] = "bass"
	m["bell"] = "bell"
	m["texture"] = ""
	m["tex_sample"] = ""
	m["bloom"] = 0.0
	m["track"] = ""
	m["swing"] = 0.0
	m["build"] = false
	(m["mix"] as Dictionary)["texture"] = 0.0
	return m


## [sound] Composed track `id` as played in `p_mood` at restoration `resto` (numbers lerp; the
## mode, progression and instruments switch to the restored ones when `resto_hi`).
static func resolve_track(id: String, p_mood: String, resto: float, resto_hi: bool) -> Dictionary:
	var tr: Dictionary = Tracks.TRACKS[id]
	var r: Dictionary = tr.get("restored", {})
	var m: Dictionary = {
		"track": id, "key": 50, "tonic": 62, "mode": MAJOR, "bpm": 90.0, "swing": 0.0, "cycles": 2,
		"form": ["A", "B", "A", "E"], "motif": [], "motif2": [], "fit": true, "build": false,
		"voice": "piano", "lead2": "bell", "pad": ["pad_warm", "pad_bright"], "bass": "bass", "bell": "bell",
		"bassline": "r.......f.......", "drums": {}, "arp": "", "arp_sample": "harp",
		"arp_lo": 60, "arp_hi": 84, "texture": "", "tex_sample": "", "lpf": 6000.0, "bright": 0.6,
		"bloom": 0.0, "density": 0.6, "tacet": 0.0, "pad_attack": 2.0, "swell": false, "intensity": -1.0,
		"energy": "calm",
	}
	for k: String in tr:
		if k != "restored" and k != "lead" and k != "kit" and k != "mix":
			m[k] = tr[k]
	m["voice"] = tr.get("lead", "piano")
	var kit: Dictionary = {"kick": "kick", "snare": "rim", "hat": "hat", "perc": ["conga_hi", "conga_lo"], "hit": "metal"}
	kit.merge(tr.get("kit", {}), true)
	if resto_hi:
		for k: String in ["mode", "prog", "lead2", "pad", "bass", "bell", "arp_sample", "texture"]:
			if r.has(k):
				m[k] = r[k]
		if r.has("lead"):
			m["voice"] = r["lead"]
		kit.merge(r.get("kit", {}), true)
	m["kit"] = kit
	var x: float = clampf(resto, 0.0, 1.0)
	for k: String in ["bpm", "lpf", "bright", "bloom"]:
		m[k] = lerpf(float(m[k]), float(r.get(k, m[k])), x)
	var base_mix: Dictionary = tr.get("mix", {})
	var r_mix: Dictionary = r.get("mix", {})
	var mix: Dictionary = {}
	for l: String in LAYERS:
		var a: float = float(base_mix.get(l, 0.0 if l == "texture" else 1.0))
		mix[l] = lerpf(a, float(r_mix.get(l, a)), x)
	m["mix"] = mix
	var t: int = int(m["tonic"])
	m["mel_lo"] = t - 3
	m["mel_hi"] = t + 15
	match p_mood:
		"night":
			m["bpm"] = float(m["bpm"]) * 0.88
			m["lpf"] = float(m["lpf"]) * 0.65
			m["bright"] = float(m["bright"]) * 0.7
			mix["kick"] = float(mix["kick"]) * 0.3
			mix["shaker"] = float(mix["shaker"]) * 0.4
			mix["air"] = float(mix["air"]) * 1.2 + 0.2
		"base":
			mix["kick"] = float(mix["kick"]) * 0.7
			mix["air"] = float(mix["air"]) * 0.5
	return m


# --- Public -------------------------------------------------------------------

func set_intensity(x: float) -> void:
	intensity = clampf(x, 0.0, 1.0)


func set_mood(m: String) -> void:
	if not MOODS.has(m):
		push_warning("Music: unknown mood '%s'" % m)
		return
	mood = m
	_dirty = true


## [sound] Planet id ("verdance", "ochre", "tidewell", "rime", "anvil"). Unknown ids are ignored
## (returns false). The new planet's pool takes over at the next bar line.
func set_theme(id: String) -> bool:
	if not Themes.has(id):
		return false
	if id != theme:
		theme = id
		_dirty = true
	return true


## [sound] 0 ruined .. 1 restored. Numbers glide; mode and progression flip past 0.55 / back
## under 0.45, at the start of the next chord cycle.
func set_restoration(x: float) -> void:
	if is_nan(x):
		return
	x = clampf(x, 0.0, 1.0)
	if absf(x - restoration) < 0.002:
		return
	restoration = x
	if x >= 0.55:
		_resto_hi = true
	elif x <= 0.45:
		_resto_hi = false
	_dirty = true


## [sound] Something busy happened (a hex cleaned, a robot built): favours the upbeat tracks and
## pushes their drums. Decays back over about a minute.
func pulse_activity(amount: float) -> void:
	if not is_nan(amount):
		activity = clampf(activity + amount, 0.0, 1.0)


## [sound] The radio: loop composed track `id` (no gaps) until stop_track(). Unknown ids are
## ignored (returns false). Its instruments must be built (Audio.play_track() does that).
func play_track(id: String) -> bool:
	if not Tracks.TRACKS.has(id):
		return false
	forced_track = id
	_gap_left = 0.0
	if _track != id:
		_cut()  # [camp] the radio replaces the score: nothing of the mood piece keeps playing
	return true


func stop_track() -> void:
	if forced_track != "":
		forced_track = ""
		_active = ""  # pick a fresh piece on the next bar line
		_cut()  # [camp] the song stops; the score fades back in from silence


## [camp] Silences the score for a song played outside it (a recorded song file): cuts what is
## sounding now and keeps every layer and stinger quiet until unmuted, then fades back in.
func set_muted(on: bool) -> void:
	if on == muted:
		return
	muted = on
	_cut()


## [camp] Ends whatever is sounding now (pads fade out in under a second, the melody line and
## any queued stingers are dropped, every layer restarts from silence and fades in) and starts
## the next piece on the very next step instead of waiting for the bar line.
func _cut() -> void:
	for p: Dictionary in _pads:
		p["release"] = true
		p["fast"] = true
	_mel_line.clear()
	_queue.clear()
	for l: String in LAYERS:
		_gains[l] = 0.0
	_active = ""
	_step = 0
	_next_step_at = _clock


func current_track() -> String:
	return _track


func in_gap() -> bool:
	return _gap_left > 0.0


func sting(name: String) -> void:
	if forced_track != "" or muted:
		return  # [camp] a radio song plays alone
	var tones: Array[int] = _chord_tones_in(60, 86)
	if tones.is_empty():
		tones = [62, 66, 69, 74, 78, 81]
	var t: float = _clock + 0.01
	# [sound] Stingers speak in the current track's lead / bell voices.
	var lead: String = str(_cur["voice"]) if _track != "" and samples.has(str(_cur["voice"])) else "piano"
	var bell_s: String = str(_cur["bell"]) if samples.has(str(_cur["bell"])) else "bell"
	match name:
		"motif":  # [sound] the Greenfall motif's opening phrase (the intro; homecoming quotes it)
			for e: Array in MOTIF_CALL:
				_sched(t + int(e[0]) * 0.17, "piano", int(e[1]), 0.75)
			_sched(t, "bell", 81, 0.45)
			_sched(t + 14 * 0.17, "bell", 78, 0.5)
			_sched(t + 14 * 0.17, "bass", 38, 0.5)
		"upgrade":
			var seq: Array[int] = _pick_from(tones, 66, 4)
			for k: int in seq.size():
				_sched(t + k * 0.09, lead, seq[k], 0.85 - 0.05 * k)
			_sched(t + seq.size() * 0.09, bell_s, seq[seq.size() - 1] + 12 if seq[seq.size() - 1] < 80 else seq[seq.size() - 1], 0.6)
		"hex_clean":
			var seq: Array[int] = _pick_from(tones, 72, 2)
			_sched(t, bell_s, seq[0], 0.55)
			_sched(t + 0.14, bell_s, seq[1], 0.6)
			_sched(t + 0.14, "kalimba", seq[1] - 12, 0.4)
		"first_sprout":
			var scale: Array[int] = _scale_in(62, 84)
			var start: int = scale.find(_nearest(scale, 64))
			for k: int in 5:
				var n: int = scale[mini(start + [0, 1, 2, 4, 5][k], scale.size() - 1)]
				_sched(t + k * 0.15, "kalimba", n, 0.75)
			_sched(t + 0.8, bell_s, _nearest(tones, 81), 0.55)
			_sched(t + 0.8, lead, _nearest(tones, 69), 0.45)
		"robot_built":
			_sched(t, "bass", _bass_midi, 0.8)
			var seq: Array[int] = _pick_from(tones, 62, 5)
			for k: int in seq.size():
				_sched(t + k * 0.065, lead, seq[k], 0.85)
			_sched(t + 0.4, bell_s, _nearest(tones, 79), 0.6)
			_sched(t + 0.55, bell_s, _nearest(tones, 86), 0.5)
		"level_up":
			var seq: Array[int] = _pick_from(tones, 62, 5)
			for k: int in seq.size():
				_sched(t + k * 0.07, "kalimba", seq[k], 0.8)
			_sched(t + 0.35, lead, seq[seq.size() - 1], 0.7)
			_sched(t + 0.35, bell_s, seq[seq.size() - 1] + 12 if seq[seq.size() - 1] < 79 else seq[seq.size() - 1], 0.55)
		_:
			push_warning("Music: unknown sting '%s'" % name)
			return
	_mel_mute_until = _clock + 1.6


## Advance by `dt` real seconds. Call every frame (or every mix block offline).
func update(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.25)
	_clock += dt
	activity = maxf(0.0, activity - dt / 70.0)
	if _chord_i < 0 and _gap_left <= 0.0:
		_next_step_at = maxf(_next_step_at, _clock)
	# [sound] Silence between pieces: only the air bed plays. A story mood or the radio ends it.
	if _gap_left > 0.0:
		_gap_left -= dt
		if _gap_left <= 0.0 or not THEMED_MOODS.has(mood) or forced_track != "":
			_gap_left = 0.0
			_active = ""  # pick the next piece on the next step
			_next_step_at = _clock
	if _dirty:
		_dirty = false
		_target = _resolve_piece(_track, mood)
	var target_int: float = intensity
	var mi: float = float(_target["intensity"])
	if mi >= 0.0:
		target_int = mi
	_eff = move_toward(_eff, target_int, dt / FADE_TIME)
	var mix: Dictionary = _target["mix"]
	var tracked: bool = str(_target["track"]) != ""
	for l: String in LAYERS:
		var target: float = 0.0
		if enabled and not muted and (_gap_left <= 0.0 or l == "air"):  # [camp] muted: silent
			target = float(mix[l]) * (_track_curve(l) if tracked else _curve(l, _eff))
		# Composed tracks come in quicker, so the hook's first statement is heard.
		var fade: float = FADE_TIME * (0.35 if tracked and target > float(_gains[l]) else 1.0)
		_gains[l] = move_toward(float(_gains[l]), target, dt / fade * maxf(1.0, target))
	lpf_cutoff = lerpf(lpf_cutoff, float(_target["lpf"]) * (0.8 + 0.2 * _eff), 1.0 - exp(-dt / 1.5))
	# Sequencer: catch up on steps, dropping notes if we fell far behind (frame hitch).
	var guard: int = 0
	while _clock >= _next_step_at and guard < 64:
		guard += 1
		var late: bool = _clock - _next_step_at > 0.12
		_do_step(not late)
		var e8: float = 60.0 / float(_cur["bpm"]) / 2.0
		var sw: float = float(_cur.get("swing", 0.0))
		# [sound] Swing: the off-beat eighth arrives late (long-short pairs).
		_next_step_at += e8 * (1.0 + sw if _step % 2 == 1 else 1.0 - sw)
	# Scheduled notes (stingers, twinkles).
	var i: int = 0
	while i < _queue.size():
		var e: Dictionary = _queue[i]
		if _clock >= float(e["at"]):
			_note(e["s"], int(e["m"]), G_STING * float(e["g"]))
			_queue.remove_at(i)
		else:
			i += 1
	_update_pads(dt)
	_update_air()


# --- Pieces [sound] -----------------------------------------------------------

func _resolve_piece(track: String, p_mood: String) -> Dictionary:
	if track != "" and Tracks.TRACKS.has(track) and (THEMED_MOODS.has(p_mood) or track == forced_track or track == "homecoming"):
		return resolve_track(track, p_mood, restoration, _resto_hi)
	return resolve(p_mood)


## Chooses the next piece for the active mood and planet.
func _pick_track() -> String:
	if forced_track != "":
		return forced_track
	if _active == "homecoming":
		return "homecoming"
	if not THEMED_MOODS.has(_active):
		return ""
	var pool: Array[String] = Tracks.for_planet(_active_theme)
	var want: String = "calm"
	if _active == "explore":
		var energy: float = maxf(activity, intensity * 0.85)
		if rng.randf() < smoothstep(0.15, 0.6, energy):
			want = "active"
	var cand: Array[String] = []
	for id: String in pool:
		if str(Tracks.TRACKS[id]["energy"]) == want:
			cand.append(id)
	if _active_theme == "verdance" and want == "calm":
		cand = [""]  # Verdance's calm pieces are the generative moods
	if cand.is_empty():
		cand = pool if not pool.is_empty() else [""]
	if cand.size() > 1:
		cand.erase(_last_track)
	elif cand[0] == _last_track and cand[0] != "" and pool.size() > 1:
		cand = pool.duplicate()  # never the same track twice in a row
		cand.erase(_last_track)
	return cand[rng.randi_range(0, cand.size() - 1)]


func _start_piece() -> void:
	_track = _pick_track()
	_last_track = _track
	_cycle = -1
	_chord_i = -1
	_phrase_i = 0
	_cycles_left = int(Tracks.TRACKS[_track].get("cycles", 2)) if _track != "" else 5
	_dirty = true


## Ends the piece with a silence gap; false when gaps don't apply (story moods, the radio).
func _start_gap() -> bool:
	if not gaps_enabled or forced_track != "" or not THEMED_MOODS.has(_active):
		return false
	var lo: float = 20.0
	var hi: float = 45.0
	match _active:
		"night":
			lo = 25.0
			hi = 55.0
		"base":
			lo = 18.0
			hi = 40.0
		_:
			var busy: float = maxf(activity, intensity * 0.6)
			lo = lerpf(20.0, 8.0, busy)
			hi = lerpf(45.0, 20.0, busy)
	_gap_left = rng.randf_range(lo, hi)
	for p: Dictionary in _pads:
		p["release"] = true
	_mel_line.clear()
	_step = 0
	return true


## 0..3: how far a "build" track has grown (one stage per half pass, i.e. every 4 chords).
func _stage() -> int:
	@warning_ignore("integer_division")
	return clampi((maxi(_cycle, 0) * 8 + maxi(_chord_i, 0)) / 4, 0, 3)


func _bmul(layer: String) -> float:
	if not bool(_cur.get("build", false)) or not BUILD.has(layer):
		return 1.0
	return float(BUILD[layer][_stage()])


## Layer curve for composed tracks: drums follow the action, the rest stays put.
func _track_curve(layer: String) -> float:
	var energy: float = maxf(activity, _eff)
	match layer:
		"kick", "shaker": return 0.55 + 0.45 * smoothstep(0.1, 0.7, energy)
		"air": return 0.7
	return 1.0


# --- Layers -------------------------------------------------------------------

func _curve(layer: String, x: float) -> float:
	match layer:
		"pad": return 0.75 + 0.25 * x
		"air": return 1.0 - 0.5 * x
		"bass": return smoothstep(0.05, 0.35, x)
		"melody": return 0.55 + 0.45 * smoothstep(0.1, 0.5, x)
		"bell": return smoothstep(0.2, 0.6, x)
		"shaker": return smoothstep(0.55, 0.8, x)
		"kick": return smoothstep(0.72, 0.95, x)
		"texture": return 0.55 + 0.45 * smoothstep(0.1, 0.6, x)
	return 0.0


func _pitch(sample: String, midi: float) -> float:
	if not samples.has(sample):
		return 1.0
	return pow(2.0, (midi - float(samples[sample]["ref"])) / 12.0)


func _note(sample: String, midi: int, gain: float) -> void:
	if gain < 0.002 or not samples.has(sample):
		return
	backend.call("start", sample, _pitch(sample, midi), gain)


func _sched(at: float, sample: String, midi: int, g: float) -> void:
	_queue.append({"at": at, "s": sample, "m": midi, "g": g})


func _update_air() -> void:
	if _air_id < 0:
		_air_id = backend.call("start", "air", 1.0, 0.0)
	backend.call("set_gain", _air_id, G_AIR * float(_gains["air"]))


func _update_pads(dt: float) -> void:
	var bright: float = float(_target["bright"]) * (0.6 + 0.4 * _eff)
	var bloom: float = G_BLOOM * float(_target["bloom"]) * _bmul("bloom")
	var chord_len: float = STEPS * 60.0 / float(_cur["bpm"]) / 2.0
	var breath: float = 1.0 + 0.08 * sin(_clock * TAU * 0.07)
	var pad_g: float = float(_gains["pad"]) * _bmul("pad")
	var i: int = 0
	while i < _pads.size():
		var p: Dictionary = _pads[i]
		var env: float = float(p["env"])
		if p["release"]:
			env -= dt / (0.6 if p.get("fast", false) else 4.0)  # [camp] fast: cut by the radio
		else:
			env = minf(1.0, env + dt / float(p["attack"]))
		p["env"] = env
		if env <= 0.0 and p["release"]:
			for id: int in p["ids"]:
				backend.call("stop", id)
			for id: int in p["bloom_ids"]:
				backend.call("stop", id)
			_pads.remove_at(i)
			continue
		var shaped: float = env * env * (3.0 - 2.0 * env)
		var swell: float = 1.0
		if p["swell"]:
			swell = 0.75 + 0.4 * clampf((_clock - float(p["start"])) / chord_len, 0.0, 1.0)
		var base: float = G_PAD * shaped * pad_g * breath * swell
		var ids: Array = p["ids"]
		@warning_ignore("integer_division")
		for k: int in ids.size() / 2:
			var morph: float = clampf(0.5 + 0.5 * sin(_clock * TAU * 0.045 + k * 1.7), 0.0, 1.0) * bright
			backend.call("set_gain", ids[k * 2], base * (1.0 - 0.6 * morph))
			backend.call("set_gain", ids[k * 2 + 1], base * morph)
		# [sound] Restoration bloom: a warm low voicing under the pad.
		var bg: float = bloom * shaped * pad_g * breath
		for id: int in p["bloom_ids"]:
			backend.call("set_gain", id, bg)
		i += 1


# --- Sequencer ----------------------------------------------------------------

func _do_step(audible: bool) -> void:
	if _gap_left > 0.0:
		return
	var switch: bool = mood != _active or theme != _active_theme or (forced_track != "" and _track != forced_track)
	if _step == 0 or (_step == 8 and switch):
		if switch:
			_active = mood
			_active_theme = theme
			_start_piece()
		_step = 0
		# Re-resolve at each chord-cycle start (restoration may have moved); end the piece with a
		# gap once its passes are done.
		if _chord_i < 0 or _chord_i + 1 >= (_cur["prog"] as Array).size():
			if _chord_i >= 0:
				_cycles_left -= 1
				if _cycles_left <= 0:
					if _start_gap():
						return
					if _track != "homecoming" and forced_track == "":
						_start_piece()  # story moods: straight into the next piece
			_cur = _resolve_piece(_track, _active)
			_chord_i = -1
			_cycle += 1
		_chord_i += 1
		_on_chord()
	if audible:
		_play_step()
	_step = (_step + 1) % STEPS


func _on_chord() -> void:
	var m: Dictionary = _cur
	var key: int = int(m["key"])
	var chord: Array = (m["prog"] as Array)[_chord_i]
	var root: int = int(chord[0])
	_chord_root_pc = (key + root) % 12
	_chord_pcs.clear()
	for iv: int in chord[1]:
		var pc: int = (key + root + iv) % 12
		if not _chord_pcs.has(pc):
			_chord_pcs.append(pc)
	# Scale: the mode, with any chromatic chord tone replacing its neighbour.
	_scale_pcs.clear()
	for d: int in m["mode"]:
		_scale_pcs.append((key + d) % 12)
	for pc: int in _chord_pcs:
		if not _scale_pcs.has(pc):
			_scale_pcs.erase((pc + 1) % 12)
			_scale_pcs.erase((pc + 11) % 12)
			_scale_pcs.append(pc)
	_bass_midi = 33 + posmod(key + root - 33, 12)
	# Pads: release the old chord, start the new one.
	for p: Dictionary in _pads:
		p["release"] = true
	var voicing: Array[int] = []
	for pc: int in _chord_pcs:
		voicing.append(52 + posmod(pc - 52, 12))
	if _chord_pcs.size() > 1:
		voicing.append(64 + posmod(_chord_pcs[1] - 64, 12))  # open top voice (3rd / sus)
	var ids: Array[int] = []
	var pw: String = str(m["pad"][0]) if samples.has(str(m["pad"][0])) else "pad_warm"
	var pb: String = str(m["pad"][1]) if samples.has(str(m["pad"][1])) else "pad_bright"
	if str(m["track"]) == "homecoming" and _stage() >= 2 and samples.has("choir"):
		pb = "choir"  # [sound] the ending's choir arrives on the third pass
	for n: int in voicing:
		ids.append(backend.call("start", pw, _pitch(pw, n), 0.0))
		ids.append(backend.call("start", pb, _pitch(pb, n), 0.0))
	# [sound] Bloom voices (root, fifth, a tenth) for restored planets and build-ups.
	var bloom_ids: Array[int] = []
	if float(m["bloom"]) > 0.02 and _chord_pcs.size() > 1:
		var lo: int = _bass_midi + 12
		for n: int in [lo, lo + 7, 57 + posmod(_chord_pcs[1] - 57, 12)]:
			bloom_ids.append(backend.call("start", "pad_warm", _pitch("pad_warm", n), 0.0))
	_pads.append({"ids": ids, "bloom_ids": bloom_ids, "env": 0.0, "attack": float(m["pad_attack"]), "release": false, "start": _clock, "swell": bool(m["swell"])})
	_compose_melody()


func _play_step() -> void:
	var m: Dictionary = _cur
	var g: Dictionary = _gains
	var tracked: bool = str(m["track"]) != ""
	var bass_s: String = str(m["bass"])
	var bell_s: String = str(m["bell"])
	var bass_g: float = G_BASS * float(g["bass"]) * _bmul("bass")
	# Bass.
	if tracked:
		var line: String = str(m["bassline"])
		var c: String = line[_step] if _step < line.length() else "."
		var n: int = _bass_midi
		match c:
			"f": n = _bass_midi + (7 if _bass_midi + 7 <= 45 else -5)
			"o": n = _bass_midi + 12
			"a": n = _bass_midi + 2
		if c != ".":
			_note(bass_s, n, bass_g * (0.9 if _step % 4 == 0 else 0.7))
	elif _step == 0:
		_note(bass_s, _bass_midi, bass_g)
	elif _step == 8 and _eff > 0.5 and rng.randf() < 0.6:
		_note(bass_s, _bass_midi + (7 if _bass_midi + 7 <= 45 else -5), bass_g * 0.7)
	elif _step == 14 and _eff > 0.7 and rng.randf() < 0.35:
		_note(bass_s, _bass_midi + (2 if rng.randf() < 0.5 else -1), bass_g * 0.5)
	# Melody.
	var ev: Variant = _mel_line[_step] if _step < _mel_line.size() else null
	var mel_playing: bool = false
	var mel_g: float = float(g["melody"]) * _bmul("melody")
	if ev != null and _clock >= _mel_mute_until:
		var e: Array = ev
		_note(str(m["voice"]), int(e[0]), G_MEL * float(e[1]) * mel_g)
		mel_playing = true
		if e.size() > 3 and bool(e[3]) and _cycle >= 1:  # [sound] the hook doubles from the 2nd pass
			var l2: String = str(m["lead2"])
			_note(l2, int(e[0]) + (12 if l2 == "bell" or l2 == "glass" else 0), G_MEL * 0.45 * float(e[1]) * mel_g)
		elif bool(e[2]) and rng.randf() < 0.4:  # double a phrase ending with a bell
			_note(bell_s, int(e[0]) + 12, G_BELL * 0.6 * float(g["bell"]))
	# Bell shimmer.
	var bell_g: float = float(g["bell"]) * _bmul("bell")
	if bell_g > 0.01:
		if _step == 0 and bool(m["swell"]):
			var arp: Array[int] = _chord_tones_in(74, 90)
			for k: int in mini(4, arp.size()):
				_sched(_clock + k * 0.32, bell_s, arp[k], 0.35 * bell_g * G_BELL / G_STING)
		elif _step == 0 and rng.randf() < (0.3 if tracked else 0.55):
			_note(bell_s, _pick_bell(), G_BELL * bell_g * rng.randf_range(0.7, 1.0))
		elif not mel_playing and _step % 2 == 1 and rng.randf() < 0.05:
			_note(bell_s, _pick_bell(), G_BELL * 0.6 * bell_g)
	if tracked:
		_play_drums(m)
		_play_arp(m)
		_play_texture(m, float(g["texture"]) * _bmul("texture"))
		return
	# Percussion (generative pieces).
	var sh: float = float(g["shaker"])
	if sh > 0.01:
		var acc: Array[float] = [1.0, 0.45, 0.7, 0.45]
		backend.call("start", "shaker%d" % rng.randi_range(0, 2), rng.randf_range(0.94, 1.06),
			G_SHAKER * acc[_step % 4] * rng.randf_range(0.75, 1.0) * sh)
	var kk: float = float(g["kick"])
	if kk > 0.01 and _step % 4 == 0:
		var kg: Array[float] = [1.0, 0.55, 0.85, 0.55]
		@warning_ignore("integer_division")
		_note("kick", 69, G_KICK * kg[_step / 4] * kk)


## [sound] The track's groove. The first two chords of a piece play without drums (an intro);
## the last bar of every 4 chords gets a small hand-drum fill when things are busy.
func _play_drums(m: Dictionary) -> void:
	if _cycle == 0 and _chord_i < 2 and not bool(m["build"]):
		return
	var dr: Dictionary = m["drums"]
	var kit: Dictionary = m["kit"]
	var kk: float = float(_gains["kick"]) * _bmul("kick")
	var sh: float = float(_gains["shaker"]) * _bmul("shaker")
	var fill: bool = _chord_i % 4 == 3 and _step >= 12 and maxf(activity, _eff) > 0.5
	for part: String in ["kick", "snare", "hat", "perc", "hit"]:
		var pat: String = str(dr.get(part, ""))
		if pat == "":
			continue
		var c: String = pat[_step] if _step < pat.length() else "."
		if part == "perc" and fill:
			c = "x"
		if c == ".":
			continue
		var acc: float = 1.0 if c == "X" else 0.78
		var smp: Variant = kit.get(part, "")
		var s: String = ""
		if smp is Array:
			var arr: Array = smp
			s = str(arr[_step % arr.size()])
		else:
			s = str(smp)
		match part:
			"kick": _note(s, 69, G_KICK * acc * kk)
			"snare": _note(s, 69, G_SNARE * acc * kk * rng.randf_range(0.9, 1.0))
			"hat": _note(s, 69 + rng.randi_range(-1, 1), G_HAT * acc * (1.0 if _step % 2 == 0 else 0.7) * sh)
			"perc": _note(s, 69, G_PERC * acc * sh * rng.randf_range(0.8, 1.0))
			"hit":  # pitched to the chord root, so the clanks / bells sit in the harmony
				var root: int = 57 + posmod(_chord_root_pc - 57, 12)
				_note(s, root if s != "bell" else root + 24, G_HIT * acc * kk)


## [sound] Arpeggio over the chord tones, rolling up then down across the two bars.
func _play_arp(m: Dictionary) -> void:
	var pat: String = str(m["arp"])
	var tx: float = float(_gains["texture"]) * _bmul("texture")
	if pat == "" or tx <= 0.01 or _step >= pat.length() or pat[_step] == ".":
		return
	var tones: Array[int] = _chord_tones_in(int(m["arp_lo"]), int(m["arp_hi"]))
	if tones.is_empty():
		return
	var j: int = _step if _step < 8 else 15 - _step
	var n: int = tones[int(roundf(float(j) / 7.0 * (tones.size() - 1)))]
	_note(str(m["arp_sample"]), n, G_TEX * tx * (0.9 if _step % 4 == 0 else 0.65) * rng.randf_range(0.85, 1.0))


## [sound] Extra track textures: Rime's glass twinkles.
func _play_texture(m: Dictionary, tx: float) -> void:
	if tx <= 0.01 or str(m["texture"]) != "twinkle" or rng.randf() >= 0.09:
		return
	var tones: Array[int] = _chord_tones_in(81, 96)
	if tones.is_empty():
		return
	var start: int = rng.randi_range(0, tones.size() - 1)
	for k: int in rng.randi_range(1, 3):
		_sched(_clock + k * 0.08, str(m["tex_sample"]), tones[(start + k) % tones.size()], G_TEX * tx * 0.55 / G_STING * (1.0 - 0.2 * k))


func _pick_bell() -> int:
	var tones: Array[int] = _chord_tones_in(76, 88)
	return tones[rng.randi_range(0, tones.size() - 1)] if not tones.is_empty() else 81


# --- Melody -------------------------------------------------------------------

func _compose_melody() -> void:
	var m: Dictionary = _cur
	_mel_line.clear()
	_mel_line.resize(STEPS)
	if str(m["track"]) != "" and _compose_motif(m):
		return
	var rhythm: String
	if _phrase_i == 0:
		_tacet = rng.randf() < float(m["tacet"]) * (1.3 - _eff)
		if _last_call != "" and rng.randf() < 0.45:
			rhythm = _last_call  # motif returns
		else:
			rhythm = CALLS[rng.randi_range(0, CALLS.size() - 1)]
		_last_call = rhythm
	else:
		rhythm = ANSWERS[rng.randi_range(0, ANSWERS.size() - 1)]
	var answer: bool = _phrase_i == 1
	_phrase_i = 1 - _phrase_i
	if _tacet:
		return
	var onsets: Array[int] = []
	for i: int in STEPS:
		if rhythm[i] == "x":
			onsets.append(i)
	var density: float = clampf(float(m["density"]) * (0.6 + 0.7 * _eff), 0.0, 1.0)
	var lo: int = int(m["mel_lo"])
	var hi: int = int(m["mel_hi"])
	_mel_prev = clampi(_mel_prev, lo, hi)
	var chord_tones: Array[int] = _chord_tones_in(lo, hi)
	var scale_tones: Array[int] = _scale_in(lo, hi)
	if chord_tones.is_empty() or scale_tones.is_empty():
		return
	for j: int in onsets.size():
		var s: int = onsets[j]
		var last: bool = answer and j == onsets.size() - 1
		if j > 0 and not last and rng.randf() < (1.0 - density) * 0.5:
			continue
		var strong: bool = s % 4 == 0
		var pool: Array[int] = chord_tones if (strong or last or j == 0) else scale_tones
		var target: float = _mel_prev + _mel_dir * (1.5 if strong else 2.0)
		var best: int = _mel_prev
		var total: float = 0.0
		var weights: Array[float] = []
		for c: int in pool:
			var w: float = exp(-absf(c - target) / 2.0)
			if c == _mel_prev:
				w *= 0.3
			if absi(c - _mel_prev) > 7:
				w *= 0.15
			if last and (c % 12 == _chord_root_pc or (_chord_pcs.size() > 1 and c % 12 == _chord_pcs[1])):
				w *= 2.5
			weights.append(w)
			total += w
		var r: float = rng.randf() * total
		for k: int in pool.size():
			r -= weights[k]
			if r <= 0.0:
				best = pool[k]
				break
		if absi(best - _mel_prev) > 4:
			_mel_dir = -signi(best - _mel_prev)
		elif best >= hi - 2:
			_mel_dir = -1
		elif best <= lo + 2:
			_mel_dir = 1
		elif rng.randf() < 0.2:
			_mel_dir = -_mel_dir
		_mel_prev = best
		var vel: float = (1.0 if strong else 0.8) * rng.randf_range(0.8, 1.0)
		_mel_line[s] = [best, 0.85 if last else vel, last]


## [sound] Writes this chord's half of the track's current phrase from its motif. Returns false
## for a "B" phrase (left to the generative answer).
func _compose_motif(m: Dictionary) -> bool:
	var form: Array = m["form"]
	@warning_ignore("integer_division")
	var letter: String = str(form[(_chord_i / 2) % form.size()])
	var half: int = _chord_i % 2
	if letter == "B":
		_phrase_i = half
		return false
	if letter == "-":
		return true
	var src: Array = m["motif2"] if letter == "C" and not (m["motif2"] as Array).is_empty() else m["motif"]
	var shift: int = 2 if letter == "H" else 0
	var lift: int = 12 if bool(m["build"]) and _stage() >= 3 and int(m["tonic"]) < 66 else 0
	var notes: Array = []
	if letter == "E" and half == 1:
		notes = [[0, 0], [8, 4] if rng.randf() < 0.5 else [8, 2]]  # the cadence: tonic, then a soft answer
	else:
		for e: Array in src:
			var s: int = int(e[0]) - half * 16
			if s >= 0 and s < STEPS:
				notes.append([s, int(e[1]) + shift])
	for k: int in notes.size():
		var s: int = int(notes[k][0])
		var midi: int = _degree_midi(m, int(notes[k][1])) + lift
		if bool(m["fit"]):
			midi = _fit(midi, s)
		var last: bool = half == 1 and k == notes.size() - 1
		_mel_line[s] = [midi, 0.95 if s % 4 == 0 else 0.8, last, true]
		_mel_prev = midi
	return true


func _degree_midi(m: Dictionary, deg: int) -> int:
	var mode: Array = m["mode"]
	var octave: int = floori(float(deg) / 7.0)
	return int(m["tonic"]) + int(mode[posmod(deg, 7)]) + 12 * octave


## Keeps a motif note in the harmony: strong beats move to the nearest chord tone, other notes
## to the nearest tone of the (chord-adjusted) scale.
func _fit(midi: int, step: int) -> int:
	var pcs: Array[int] = _chord_pcs if step % 4 == 0 else _scale_pcs
	if pcs.is_empty() or pcs.has(posmod(midi, 12)):
		return midi
	for d: int in [-1, 1, -2, 2, -3, 3]:
		if pcs.has(posmod(midi + d, 12)):
			return midi + d
	return midi


# --- Pitch helpers ------------------------------------------------------------

func _chord_tones_in(lo: int, hi: int) -> Array[int]:
	var out: Array[int] = []
	for n: int in range(lo, hi + 1):
		if _chord_pcs.has(n % 12):
			out.append(n)
	return out


func _scale_in(lo: int, hi: int) -> Array[int]:
	var out: Array[int] = []
	var pcs: Array[int] = _scale_pcs if not _scale_pcs.is_empty() else [2, 4, 6, 7, 9, 11, 1]
	for n: int in range(lo, hi + 1):
		if pcs.has(n % 12):
			out.append(n)
	return out


func _nearest(pool: Array[int], target: int) -> int:
	var best: int = pool[0]
	for n: int in pool:
		if absi(n - target) < absi(best - target):
			best = n
	return best


## `count` ascending pool notes starting at the one nearest `from`.
func _pick_from(pool: Array[int], from: int, count: int) -> Array[int]:
	var i: int = maxi(0, mini(pool.find(_nearest(pool, from)), pool.size() - count))
	return pool.slice(i, i + count)
