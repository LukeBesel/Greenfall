class_name StorySfx
extends RefCounted
## Extra synthesized sounds for story beats and easter eggs (original, generated at first use).
## Registered into the Audio autoload by name with Audio.override(), so Audio.play("quack") works.

const RATE: int = 22050
## The jukebox's music-box tune: an original little waltz in C (semitones from C5, beats).
const TUNE: Array = [
	[0, 1], [4, 1], [7, 1], [12, 2], [11, 1], [9, 1], [7, 2], [4, 1],
	[5, 1], [9, 1], [12, 1], [14, 2], [12, 1], [11, 1], [7, 3],
	[0, 1], [4, 1], [7, 1], [9, 2], [7, 1], [5, 1], [4, 2], [2, 1],
	[4, 1], [7, 1], [11, 1], [12, 3], [7, 1.5], [12, 4.5],
]

static var _done: bool = false
static var _streams: Dictionary = {}


static func ensure() -> void:
	if _done:
		return
	_done = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	_reg("quack", [_quack(1.0), _quack(1.12), _quack(0.92)])
	_reg("glitch", [_glitch(rng, 0.35), _glitch(rng, 0.5), _glitch(rng, 0.25)])
	_reg("purr", [_purr(rng)])
	_reg("phone_ring", [_ring()])
	_reg("arcade", [_arcade(0), _arcade(1)])
	_reg("tv_static", [_static(rng)])
	_reg("ledger_tick", [_tick(1400.0), _tick(1250.0), _tick(1550.0)])
	_streams["drone_hum"] = _hum(rng)


static var _box: AudioStreamWAV
static var _box_task: int = -1


## Starts building the (long) music-box tune on a worker thread.
static func prewarm_music_box() -> void:
	if _box == null and _box_task < 0:
		_box_task = WorkerThreadPool.add_task(func() -> void: _box = wav(_music_box()))


static func music_box() -> AudioStreamWAV:
	finish_pending()
	if _box == null:
		_box = wav(_music_box())
	return _box


## [health] Waits for the music-box worker task. WorkerThreadPool keeps a task (and its lambda,
## which holds a reference to this GDScript) until it is waited on; one left over at quit is freed
## after the GDScript language has shut down and crashes the exit (SIGABRT, exit code 134).
## Called from Audio._exit_tree() so every quit path waits before scripting is torn down.
static func finish_pending() -> void:
	if _box_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_box_task)
		_box_task = -1


static func stream(id: String) -> AudioStream:
	ensure()
	return _streams.get(id, null)


static func _reg(id: String, bufs: Array) -> void:
	var list: Array = []
	for b: PackedFloat32Array in bufs:
		list.append(wav(b))
	_streams[id] = list[0]
	if not Audio.has_sound(id):
		Audio.override(id, list)


static func wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	@warning_ignore("integer_division")
	var n: int = mini(int(0.004 * RATE), samples.size() / 2)
	if not loop:
		for i: int in n:
			var g: float = float(i) / n
			samples[i] *= g
			samples[samples.size() - 1 - i] *= g
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


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Rubber duck squeeze: a nasal, pitch-bending buzz with a formant-ish second partial.
static func _quack(p: float) -> PackedFloat32Array:
	var b := _buf(0.32)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var f: float = (620.0 + 380.0 * sin(PI * minf(t / 0.3, 1.0)) - 300.0 * t) * p
		ph += TAU * f / RATE
		var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var env: float = minf(t * 60.0, 1.0) * exp(-t * 6.0)
		b[i] = (saw * 0.5 + sin(ph * 2.0) * 0.35 + sin(ph * 3.0) * 0.2) * env * 0.3
	return b


## Digital interference: bit-crushed noise bursts with a falling square tone.
static func _glitch(rng: RandomNumberGenerator, seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var hold: float = 0.0
	var hold_n: int = 0
	for i: int in b.size():
		var t: float = float(i) / RATE
		if hold_n <= 0:
			hold = rng.randf_range(-1.0, 1.0)
			hold_n = rng.randi_range(4, 40)
		hold_n -= 1
		var sq: float = 1.0 if fmod(t * (880.0 - 1200.0 * t), 1.0) < 0.5 else -1.0
		var gate: float = 1.0 if fmod(t * 23.0, 1.0) < 0.7 else 0.2
		b[i] = (hold * 0.5 + sq * 0.18) * gate * exp(-t * 3.0) * 0.32
	return b


## [v8snd] The same soft purr as the wildlife's cats (fauna/fauna_sounds.gd); this one was a
## 24 Hz chop of sub-200 Hz noise plus a 48 Hz tone (a helicopter on laptop speakers).
static func _purr(rng: RandomNumberGenerator) -> PackedFloat32Array:
	return FaunaSounds.purr(rng, 0.0)


static func _ring() -> PackedFloat32Array:
	var b := _buf(1.4)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var on: float = 1.0 if fmod(t, 0.7) < 0.42 else 0.0
		var trem: float = 0.5 + 0.5 * sin(TAU * 18.0 * t)
		b[i] = (sin(TAU * 1180.0 * t) + sin(TAU * 1420.0 * t)) * on * trem * 0.12
	return b


static func _arcade(v: int) -> PackedFloat32Array:
	var b := _buf(0.9)
	var notes: Array = [523.25, 659.25, 783.99, 1046.5, 1318.5] if v == 0 else [392.0, 523.25, 392.0, 659.25, 783.99]
	var step: float = 0.9 / notes.size()
	for i: int in b.size():
		var t: float = float(i) / RATE
		var k: int = mini(int(t / step), notes.size() - 1)
		var lt: float = fmod(t, step)
		var sq: float = 1.0 if fmod(t * float(notes[k]), 1.0) < 0.5 else -1.0
		b[i] = sq * exp(-lt * 9.0) * 0.12
	return b


static func _static(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.8)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = rng.randf_range(-1.0, 1.0) * (0.6 + 0.4 * sin(TAU * 60.0 * t)) * sin(PI * t / 0.8) * 0.12
	return b


static func _tick(f: float) -> PackedFloat32Array:
	var b := _buf(0.04)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * exp(-t * 120.0) * 0.12
	return b


## Looping rotor hum for the Ledger drones (two detuned rotor tones + filtered air noise).
static func _hum(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var seconds: float = 1.0
	var b := _buf(seconds)
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.12
		var r1: float = sin(TAU * 110.0 * t) * (0.6 + 0.4 * sin(TAU * 22.0 * t))
		var r2: float = sin(TAU * 165.0 * t) * 0.4 + sin(TAU * 220.0 * t) * 0.2
		b[i] = (r1 * 0.25 + r2 * 0.18 + lp * 0.5) * 0.4
	# Crossfade the tail into the head so the loop is seamless.
	var xf: int = int(0.05 * RATE)
	for i: int in xf:
		var g: float = float(i) / xf
		b[i] = b[i] * g + b[b.size() - xf + i] * (1.0 - g)
	b.resize(b.size() - xf)
	return wav(b, true)


## Music box: plucked tines (fundamental + inharmonic partials), long decay, gentle tempo.
static func _music_box() -> PackedFloat32Array:
	var beat: float = 0.3
	var total: float = 0.0
	for n: Array in TUNE:
		total += float(n[1]) * beat
	var b := _buf(total + 2.0)
	var start: float = 0.0
	for n: Array in TUNE:
		var f: float = 523.25 * pow(2.0, float(n[0]) / 12.0)
		var s0: int = int(start * RATE)
		var len_s: int = mini(int(1.8 * RATE), b.size() - s0)
		for i: int in len_s:
			var t: float = float(i) / RATE
			var v: float = sin(TAU * f * t) * exp(-t * 3.2)
			v += 0.35 * sin(TAU * f * 2.0 * t) * exp(-t * 6.0)
			v += 0.18 * sin(TAU * f * 5.4 * t) * exp(-t * 14.0)
			v += 0.08 * sin(TAU * f * 8.9 * t) * exp(-t * 30.0)
			b[s0 + i] += v * 0.17
		# A soft lower harmony tine on the downbeats of long notes.
		if float(n[1]) >= 2.0:
			var fl: float = f * 0.5
			for i: int in len_s:
				var t: float = float(i) / RATE
				b[s0 + i] += sin(TAU * fl * t) * exp(-t * 2.5) * 0.08
		start += float(n[1]) * beat
	return b
