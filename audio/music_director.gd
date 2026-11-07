extends RefCounted
## Generative, layered ambient score for Greenfall.
##
## A slow chord progression drives an evolving pad, a soft bass, a felt-piano / kalimba melody
## built from call-and-answer phrases, bell shimmer accents and (only at high intensity) a
## brushed shaker and a felted kick. Layers fade with `intensity` (0..1) and `mood`; harmony and
## tempo switch to the new mood at the next bar so changes always land musically.
##
## The director is backend-agnostic: it only calls `start(sample, pitch, gain) -> id`,
## `set_gain(id, gain)` and `stop(id)` on `backend`. At runtime that is audio/music_voices.gd
## (a pool of AudioStreamPlayers); tools/render_music.gd uses audio/music_offline_mixer.gd.

const KEY_ROOT: int = 50  # D3: the whole score lives in D major so moods can crossfade.
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
const FADE_TIME: float = 4.0  # seconds for a layer to fade fully in or out

const LAYERS: Array[String] = ["pad", "air", "bass", "melody", "bell", "shaker", "kick"]

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
	# [extras] Radio songs (systems/extras/radio.gd, data/radio.json): arrangements the player picks
	# on the base radio. Same key and layers as the moods, so they crossfade in like any mood.
	"song_rust_lullaby": {  # vi7 - V sus4 - IVmaj7 - I: slow kalimba, a music box in a scrapyard
		"bpm": 58.0,
		"prog": [[9, [0, 3, 7, 10]], [7, [0, 5, 7, 10]], [5, [0, 4, 7, 11]], [0, [0, 4, 7, 14]]],
		"mix": {"pad": 1.0, "air": 1.1, "bass": 0.7, "melody": 1.0, "bell": 1.2, "shaker": 0.0, "kick": 0.0},
		"voice": "kalimba", "mel_lo": 64, "mel_hi": 81, "density": 0.4, "bright": 0.4,
		"pad_attack": 3.0, "lpf": 3800.0, "intensity": 0.45, "tacet": 0.3, "swell": false,
	},
	"song_sprout_shuffle": {  # I - IVmaj7 - ii7 - V7: bright and bouncy
		"bpm": 92.0,
		"prog": [[0, [0, 4, 7, 14]], [5, [0, 4, 7, 11]], [2, [0, 3, 7, 10]], [7, [0, 4, 7, 10]]],
		"mix": {"pad": 0.8, "air": 0.4, "bass": 1.1, "melody": 1.1, "bell": 0.7, "shaker": 1.2, "kick": 1.0},
		"voice": "piano", "mel_lo": 64, "mel_hi": 81, "density": 0.75, "bright": 0.7,
		"pad_attack": 1.8, "lpf": 6800.0, "intensity": 0.82, "tacet": 0.1, "swell": false,
	},
	"song_rooftops": {  # ii9 - V sus4 - Imaj7 - vi7: late-evening jazz over the roofs
		"bpm": 78.0,
		"prog": [[2, [0, 3, 7, 10, 14]], [7, [0, 5, 7, 10]], [0, [0, 4, 7, 11]], [9, [0, 3, 7, 10]]],
		"mix": {"pad": 1.0, "air": 0.6, "bass": 1.2, "melody": 1.0, "bell": 0.6, "shaker": 0.9, "kick": 0.6},
		"voice": "piano", "mel_lo": 62, "mel_hi": 79, "density": 0.6, "bright": 0.55,
		"pad_attack": 2.2, "lpf": 5200.0, "intensity": 0.7, "tacet": 0.15, "swell": false,
	},
	"song_greenline": {  # I - iii7 - IVmaj7 - V sus4: a quick kalimba groove, the trains are running
		"bpm": 100.0,
		"prog": [[0, [0, 4, 7, 11]], [4, [0, 3, 7, 10]], [5, [0, 4, 7, 11]], [7, [0, 5, 7, 10]]],
		"mix": {"pad": 0.9, "air": 0.5, "bass": 1.1, "melody": 1.1, "bell": 0.9, "shaker": 1.1, "kick": 1.1},
		"voice": "kalimba", "mel_lo": 66, "mel_hi": 83, "density": 0.8, "bright": 0.75,
		"pad_attack": 1.6, "lpf": 7000.0, "intensity": 0.9, "tacet": 0.1, "swell": false,
	},
	"song_far_shore": {  # IVmaj7 - I add9 - V sus4 - vi9: wide and airy, the next district over the hill
		"bpm": 64.0,
		"prog": [[5, [0, 4, 7, 11]], [0, [0, 4, 7, 14]], [7, [0, 5, 7, 10]], [9, [0, 3, 7, 10, 14]]],
		"mix": {"pad": 1.2, "air": 1.4, "bass": 0.9, "melody": 0.9, "bell": 1.0, "shaker": 0.4, "kick": 0.0},
		"voice": "kalimba", "mel_lo": 62, "mel_hi": 79, "density": 0.45, "bright": 0.6,
		"pad_attack": 3.2, "lpf": 4600.0, "intensity": 0.55, "tacet": 0.25, "swell": false,
	},
	"song_bloom": {  # I add9 - vi7 - IVmaj7 - V sus4: the whole planet in flower
		"bpm": 84.0,
		"prog": [[0, [0, 4, 7, 14]], [9, [0, 3, 7, 10]], [5, [0, 4, 7, 11]], [7, [0, 5, 7, 10]]],
		"mix": {"pad": 1.2, "air": 0.8, "bass": 1.0, "melody": 1.1, "bell": 1.1, "shaker": 1.0, "kick": 0.8},
		"voice": "piano", "mel_lo": 64, "mel_hi": 83, "density": 0.65, "bright": 0.85,
		"pad_attack": 2.4, "lpf": 7500.0, "intensity": 0.85, "tacet": 0.12, "swell": false,
	},
	"song_starseed": {  # Imaj7 - II (lydian lift) - IVmaj7 - I: a new world on the horizon
		"bpm": 70.0,
		"prog": [[0, [0, 4, 7, 11]], [2, [0, 4, 7, 14]], [5, [0, 4, 7, 11]], [0, [0, 4, 7, 14]]],
		"mix": {"pad": 1.3, "air": 1.0, "bass": 0.9, "melody": 0.9, "bell": 1.4, "shaker": 0.5, "kick": 0.3},
		"voice": "piano", "mel_lo": 66, "mel_hi": 84, "density": 0.5, "bright": 0.9,
		"pad_attack": 3.0, "lpf": 7800.0, "intensity": 0.62, "tacet": 0.2, "swell": true,
	},
	"song_cradle_choir": {  # vi7 - IVmaj7 - I add9 - V sus4, slow swells: the ark comes home
		"bpm": 52.0,
		"prog": [[9, [0, 3, 7, 10]], [5, [0, 4, 7, 11]], [0, [0, 4, 7, 14]], [7, [0, 5, 7, 10]]],
		"mix": {"pad": 1.7, "air": 0.7, "bass": 1.1, "melody": 0.8, "bell": 1.3, "shaker": 0.0, "kick": 0.0},
		"voice": "piano", "mel_lo": 64, "mel_hi": 81, "density": 0.35, "bright": 0.8,
		"pad_attack": 4.5, "lpf": 7200.0, "intensity": 0.7, "tacet": 0.12, "swell": true,
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

var _active: String = "explore"  # harmony / tempo follow this (switches on a bar line)
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


# --- Public -------------------------------------------------------------------

func set_intensity(x: float) -> void:
	intensity = clampf(x, 0.0, 1.0)


func set_mood(m: String) -> void:
	if not MOODS.has(m):
		push_warning("Music: unknown mood '%s'" % m)
		return
	mood = m


func sting(name: String) -> void:
	var tones: Array[int] = _chord_tones_in(60, 86)
	if tones.is_empty():
		tones = [62, 66, 69, 74, 78, 81]
	var t: float = _clock + 0.01
	match name:
		"upgrade":
			var seq: Array[int] = _pick_from(tones, 66, 4)
			for k: int in seq.size():
				_sched(t + k * 0.09, "piano", seq[k], 0.85 - 0.05 * k)
			_sched(t + seq.size() * 0.09, "bell", seq[seq.size() - 1] + 12 if seq[seq.size() - 1] < 80 else seq[seq.size() - 1], 0.6)
		"hex_clean":
			var seq: Array[int] = _pick_from(tones, 72, 2)
			_sched(t, "bell", seq[0], 0.55)
			_sched(t + 0.14, "bell", seq[1], 0.6)
			_sched(t + 0.14, "kalimba", seq[1] - 12, 0.4)
		"first_sprout":
			var scale: Array[int] = _scale_in(62, 84)
			var start: int = scale.find(_nearest(scale, 64))
			for k: int in 5:
				var n: int = scale[mini(start + [0, 1, 2, 4, 5][k], scale.size() - 1)]
				_sched(t + k * 0.15, "kalimba", n, 0.75)
			_sched(t + 0.8, "bell", _nearest(tones, 81), 0.55)
			_sched(t + 0.8, "piano", _nearest(tones, 69), 0.45)
		"robot_built":
			_sched(t, "bass", _bass_midi, 0.8)
			var seq: Array[int] = _pick_from(tones, 62, 5)
			for k: int in seq.size():
				_sched(t + k * 0.065, "piano", seq[k], 0.85)
			_sched(t + 0.4, "bell", _nearest(tones, 79), 0.6)
			_sched(t + 0.55, "bell", _nearest(tones, 86), 0.5)
		"level_up":
			var seq: Array[int] = _pick_from(tones, 62, 5)
			for k: int in seq.size():
				_sched(t + k * 0.07, "kalimba", seq[k], 0.8)
			_sched(t + 0.35, "piano", seq[seq.size() - 1], 0.7)
			_sched(t + 0.35, "bell", seq[seq.size() - 1] + 12 if seq[seq.size() - 1] < 79 else seq[seq.size() - 1], 0.55)
		_:
			push_warning("Music: unknown sting '%s'" % name)
			return
	_mel_mute_until = _clock + 1.6


## Advance by `dt` real seconds. Call every frame (or every mix block offline).
func update(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.25)
	_clock += dt
	if _chord_i < 0:
		_next_step_at = _clock
	var target_int: float = intensity
	var mi: float = float(MOODS[mood]["intensity"])
	if mi >= 0.0:
		target_int = mi
	_eff = move_toward(_eff, target_int, dt / FADE_TIME)
	var mix: Dictionary = MOODS[mood]["mix"]
	for l: String in LAYERS:
		var target: float = float(mix[l]) * _curve(l, _eff) if enabled else 0.0
		_gains[l] = move_toward(float(_gains[l]), target, dt / FADE_TIME * maxf(1.0, target))
	lpf_cutoff = lerpf(lpf_cutoff, float(MOODS[mood]["lpf"]) * (0.8 + 0.2 * _eff), 1.0 - exp(-dt / 1.5))
	# Sequencer: catch up on steps, dropping notes if we fell far behind (frame hitch).
	while _clock >= _next_step_at:
		var late: bool = _clock - _next_step_at > 0.12
		_do_step(not late)
		_next_step_at += 60.0 / float(MOODS[_active]["bpm"]) / 2.0
	# Scheduled sting notes.
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
	return 0.0


func _pitch(sample: String, midi: float) -> float:
	return pow(2.0, (midi - float(samples[sample]["ref"])) / 12.0)


func _note(sample: String, midi: int, gain: float) -> void:
	if gain < 0.002:
		return
	backend.call("start", sample, _pitch(sample, midi), gain)


func _sched(at: float, sample: String, midi: int, g: float) -> void:
	_queue.append({"at": at, "s": sample, "m": midi, "g": g})


func _update_air() -> void:
	if _air_id < 0:
		_air_id = backend.call("start", "air", 1.0, 0.0)
	backend.call("set_gain", _air_id, G_AIR * float(_gains["air"]))


func _update_pads(dt: float) -> void:
	var m: Dictionary = MOODS[mood]
	var bright: float = float(m["bright"]) * (0.6 + 0.4 * _eff)
	var chord_len: float = STEPS * 60.0 / float(MOODS[_active]["bpm"]) / 2.0
	var breath: float = 1.0 + 0.08 * sin(_clock * TAU * 0.07)
	var i: int = 0
	while i < _pads.size():
		var p: Dictionary = _pads[i]
		var env: float = float(p["env"])
		if p["release"]:
			env -= dt / 4.0
		else:
			env = minf(1.0, env + dt / float(p["attack"]))
		p["env"] = env
		if env <= 0.0 and p["release"]:
			for id: int in p["ids"]:
				backend.call("stop", id)
			_pads.remove_at(i)
			continue
		var shaped: float = env * env * (3.0 - 2.0 * env)
		var swell: float = 1.0
		if p["swell"]:
			swell = 0.75 + 0.4 * clampf((_clock - float(p["start"])) / chord_len, 0.0, 1.0)
		var base: float = G_PAD * shaped * float(_gains["pad"]) * breath * swell
		var ids: Array = p["ids"]
		@warning_ignore("integer_division")
		for k: int in ids.size() / 2:
			var morph: float = clampf(0.5 + 0.5 * sin(_clock * TAU * 0.045 + k * 1.7), 0.0, 1.0) * bright
			backend.call("set_gain", ids[k * 2], base * (1.0 - 0.6 * morph))
			backend.call("set_gain", ids[k * 2 + 1], base * morph)
		i += 1


# --- Sequencer ----------------------------------------------------------------

func _do_step(audible: bool) -> void:
	if _step == 0 or (_step == 8 and mood != _active):
		if mood != _active:
			_active = mood
			_chord_i = -1
			_phrase_i = 0
		_step = 0
		_chord_i = (_chord_i + 1) % (MOODS[_active]["prog"] as Array).size()
		_on_chord()
	if audible:
		_play_step()
	_step = (_step + 1) % STEPS


func _on_chord() -> void:
	var m: Dictionary = MOODS[_active]
	var chord: Array = (m["prog"] as Array)[_chord_i]
	var root: int = int(chord[0])
	_chord_root_pc = (KEY_ROOT + root) % 12
	_chord_pcs.clear()
	for iv: int in chord[1]:
		var pc: int = (KEY_ROOT + root + iv) % 12
		if not _chord_pcs.has(pc):
			_chord_pcs.append(pc)
	# Scale: the major key, with any chromatic chord tone replacing its neighbour.
	_scale_pcs.clear()
	for d: int in MAJOR:
		_scale_pcs.append((KEY_ROOT + d) % 12)
	for pc: int in _chord_pcs:
		if not _scale_pcs.has(pc):
			_scale_pcs.erase((pc + 1) % 12)
			_scale_pcs.erase((pc + 11) % 12)
			_scale_pcs.append(pc)
	_bass_midi = 33 + posmod(KEY_ROOT + root - 33, 12)
	# Pads: release the old chord, start the new one.
	for p: Dictionary in _pads:
		p["release"] = true
	var voicing: Array[int] = []
	for pc: int in _chord_pcs:
		voicing.append(52 + posmod(pc - 52, 12))
	voicing.append(64 + posmod(_chord_pcs[1] - 64, 12))  # open top voice (3rd / sus)
	var ids: Array[int] = []
	for n: int in voicing:
		ids.append(backend.call("start", "pad_warm", _pitch("pad_warm", n), 0.0))
		ids.append(backend.call("start", "pad_bright", _pitch("pad_bright", n), 0.0))
	_pads.append({"ids": ids, "env": 0.0, "attack": float(m["pad_attack"]), "release": false, "start": _clock, "swell": bool(m["swell"])})
	_compose_melody()


func _play_step() -> void:
	var m: Dictionary = MOODS[_active]
	var g: Dictionary = _gains
	# Bass: root on the downbeat; a fifth and an approach note when things are livelier.
	if _step == 0:
		_note("bass", _bass_midi, G_BASS * float(g["bass"]))
	elif _step == 8 and _eff > 0.5 and rng.randf() < 0.6:
		_note("bass", _bass_midi + (7 if _bass_midi + 7 <= 45 else -5), G_BASS * 0.7 * float(g["bass"]))
	elif _step == 14 and _eff > 0.7 and rng.randf() < 0.35:
		_note("bass", _bass_midi + (2 if rng.randf() < 0.5 else -1), G_BASS * 0.5 * float(g["bass"]))
	# Melody.
	var ev: Variant = _mel_line[_step] if _step < _mel_line.size() else null
	var mel_playing: bool = false
	if ev != null and _clock >= _mel_mute_until:
		var e: Array = ev
		_note(str(m["voice"]), int(e[0]), G_MEL * float(e[1]) * float(g["melody"]))
		mel_playing = true
		if bool(e[2]) and rng.randf() < 0.4:  # double a phrase ending with a bell
			_note("bell", int(e[0]) + 12, G_BELL * 0.6 * float(g["bell"]))
	# Bell shimmer.
	var bell_g: float = float(g["bell"])
	if bell_g > 0.01:
		if _step == 0 and bool(m["swell"]):
			var arp: Array[int] = _chord_tones_in(74, 90)
			for k: int in mini(4, arp.size()):
				_sched(_clock + k * 0.32, "bell", arp[k], 0.35 * bell_g * G_BELL / G_STING)
		elif _step == 0 and rng.randf() < 0.55:
			_note("bell", _pick_bell(), G_BELL * bell_g * rng.randf_range(0.7, 1.0))
		elif not mel_playing and _step % 2 == 1 and rng.randf() < 0.05:
			_note("bell", _pick_bell(), G_BELL * 0.6 * bell_g)
	# Percussion.
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


func _pick_bell() -> int:
	var tones: Array[int] = _chord_tones_in(76, 88)
	return tones[rng.randi_range(0, tones.size() - 1)] if not tones.is_empty() else 81


# --- Melody -------------------------------------------------------------------

func _compose_melody() -> void:
	var m: Dictionary = MOODS[_active]
	_mel_line.clear()
	_mel_line.resize(STEPS)
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
			if last and (c % 12 == _chord_root_pc or c % 12 == _chord_pcs[1]):
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
