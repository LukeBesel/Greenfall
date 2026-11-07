extends Node
## Procedural audio. Every SFX is synthesized at startup (original, no external files) with
## at least 3 variations. Final assets can replace any sound by name via `override(name, streams)`.
##
## Music: a generative, layered ambient score (audio/music_director.gd, instruments from
## audio/music_synth.gd) on the "Music" bus. Drive it with `set_music_mood()` ("explore",
## "night", "base", "cinematic", "menu"), `set_music_intensity(0..1)` and `music_sting(name)`.

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

## When false the score fades out (stingers still play; they are feedback).
var music_enabled: bool = true
var _music: RefCounted  # MusicDirector
var _music_voices: Node
var _music_lpf: AudioEffectLowPassFilter
var _music_last_us: int = 0


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
	_music_voices = MusicVoices.new()
	_music_voices.name = "MusicVoices"
	add_child(_music_voices)
	_music_voices.call("setup", music_samples, "Music", 48)
	_music = MusicDirector.new(music_samples, _music_voices)
	_music_last_us = Time.get_ticks_usec()
	apply_volumes()


func _exit_tree() -> void:
	StorySfx.finish_pending()  # [health] an unwaited WorkerThreadPool task crashes the engine at exit


func _setup_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
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
	AudioServer.set_bus_volume_db(0, linear_to_db(Settings.master_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(Settings.sfx_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(Settings.music_volume))


# --- Playback -----------------------------------------------------------------

func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0, jitter: float = 0.04) -> void:
	var list: Array = _sounds.get(sound, [])
	if list.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = list[_rng.randi() % list.size()]
	p.pitch_scale = maxf(0.05, pitch * (1.0 + _rng.randf_range(-jitter, jitter)))
	p.volume_db = volume_db
	p.play()


## Plays a sound pitched up a pentatonic scale; step grows with combos.
func play_scale(sound: String, step: int, volume_db: float = 0.0) -> void:
	var s: int = PENTATONIC[clampi(step, 0, PENTATONIC.size() - 1)]
	play(sound, pow(2.0, s / 12.0), volume_db, 0.0)


## Continuous looping sound at `level` 0..1 (0 stops it). Cheap to call every frame; the
## player is created once per loop name. `pitch` follows the call.
func loop(sound: String, level: float, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = _loop_players.get(sound)
	if level <= 0.001:
		if p and p.playing:
			p.stop()
		return
	if p == null:
		if not _loops.has(sound):
			return
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = _loops[sound]
		add_child(p)
		_loop_players[sound] = p
	p.volume_db = linear_to_db(level) - 22.0
	p.pitch_scale = pitch
	if not p.playing:
		p.play()


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
		_music.call("set_mood", mood)


func get_music_mood() -> String:
	return str(_music.get("mood")) if _music else ""


func get_music_intensity() -> float:
	return float(_music.get("intensity")) if _music else 0.0


## Short musical stinger built from the current chord: "upgrade", "hex_clean", "first_sprout",
## "robot_built", "level_up". Routed to the Music bus.
func music_sting(sting_name: String) -> void:
	if _music:
		_music.call("sting", sting_name)


func _process(_delta: float) -> void:
	if not _music:
		return
	# Real time, so Engine.time_scale (autoplay) never changes the tempo.
	var now: int = Time.get_ticks_usec()
	var dt: float = (now - _music_last_us) / 1000000.0
	_music_last_us = now
	_music.set("enabled", music_enabled)
	_music.call("update", dt)
	if _music_lpf:
		_music_lpf.cutoff_hz = float(_music.get("lpf_cutoff"))


# --- Synthesis ----------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
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
		hum[i] = (sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 220.0 * t + 0.3 * sin(TAU * 3.0 * t)) * 0.3 \
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
			b[i] = (sin(TAU * f * t) * 0.9 + _rng.randf_range(-0.4, 0.4) * exp(-t * 40.0)) * exp(-t * 11.0)
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
		var notes: int = 2 + v
		for i: int in b.size():
			var t: float = float(i) / RATE
			var k: int = int(t / 0.5 * notes)
			var lt: float = fmod(t, 0.5 / notes) / (0.5 / notes)
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
