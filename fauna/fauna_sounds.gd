class_name FaunaSounds
extends RefCounted
## [wild] Synthesized animal sounds, registered on the Audio autoload by name the first time a
## district with animals loads (Audio.override), like the rest of the game's SFX: purr, meow,
## coo, chirp, song (a few robin phrases), quack, gull, frog, seal, flutter (a flock taking
## off) and a seamless cricket bed (crickets_loop(), played by Fauna on its own player).

const RATE: int = 22050
const MusicSynth := preload("res://audio/music_synth.gd")

static var _done: bool = false
static var _crickets: AudioStreamWAV


static func ensure() -> void:
	if _done:
		return
	_done = true
	# [v1menu] The synthesis is pure maths: behind the loading screen it runs on a worker thread
	# (one task, so the rng order and the sounds are unchanged) and the loader keeps animating;
	# the streams are registered on the main thread afterwards. Synchronous without a budget.
	var bufs: Dictionary = {}
	if BuildBudget.active():
		var task: int = WorkerThreadPool.add_task(_synth_all.bind(bufs), false, "fauna sounds")
		while not WorkerThreadPool.is_task_completed(task):
			await BuildBudget.pause("sounds (thread)")
		WorkerThreadPool.wait_for_task_completion(task)
	else:
		_synth_all(bufs)
	for name: String in ["purr", "meow", "coo", "chirp", "song", "quack", "gull", "frog", "seal", "flutter"]:
		Audio.override(name, bufs[name])
	await BuildBudget.check("sounds")


## Every sound's streams, synthesized in the original rng order (name -> Array of AudioStreamWAV).
static func _synth_all(out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	out["purr"] = [purr(rng, 0.0), purr(rng, 0.15), purr(rng, -0.1)]
	out["meow"] = [meow(0.0), meow(0.12), meow(-0.08)]
	# [v9s] Owner: "the same bird chirp so many times over and over". More takes per call, each
	# its own phrase (length, notes, shape), not one call at a few pitches. Audio.play never plays
	# the same take twice running.
	out["coo"] = [coo(0.0), coo(0.1), coo(-0.06), coo3(rng, 0.04), coo3(rng, -0.1)]
	out["chirp"] = []
	for v: int in 8:
		out["chirp"].append(chirp(rng, v))
	out["song"] = []
	for v: int in 8:
		out["song"].append(song(rng, v))
	out["quack"] = [quack(rng, 0.0), quack(rng, 0.08), quack(rng, -0.06), quack(rng, 0.14)]
	out["gull"] = [gull(0.0), gull(0.1), gull(-0.08), gull(0.05, 2), gull(-0.04, 4)]
	out["frog"] = []
	for v: int in 6:
		out["frog"].append(frog(rng, [0.0, 0.12, -0.1, 0.06, -0.05, 0.18][v], v))
	out["seal"] = [seal(0.0), seal(0.1), seal(-0.1)]
	out["flutter"] = [flutter(rng, 0.8), flutter(rng, 1.0), flutter(rng, 1.3)]
	for name: String in out:
		out[name] = (out[name] as Array).map(func(b: PackedFloat32Array) -> AudioStreamWAV: return wav(b))


static func crickets_loop() -> AudioStreamWAV:
	if _crickets == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		_crickets = wav(crickets(rng), true)
	return _crickets


static func wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var n: int = samples.size()
	var fade: int = mini(64, n / 4)
	if not loop:
		for i: int in fade:
			samples[i] *= float(i) / fade
			samples[n - 1 - i] *= float(i) / fade
	var data := PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## A cat's purr: soft breathy noise in the 180 Hz - 1.1 kHz band, gently pulsing at ~25 Hz, in
## and out breaths with a short pause between them.
## [v8snd] Was low-passed noise (most of it under 200 Hz) chopped fully on and off 24 times a
## second at full scale: on laptop speakers that read as a helicopter / blown speaker
## (tools/check_audio.py: sub-80 Hz 32%, 80-200 Hz 30%, tremolo depth 1.3-1.5, peak -0.4 dBFS).
## Now: sub-80 Hz ~0%, gentle pulse, peak -9 dBFS.
static func purr(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var b := _buf(2.4)
	var lp: float = 0.0
	var lp2: float = 0.0
	var prev: float = 0.0
	var hp: float = 0.0
	var hp2: float = 0.0
	var prev2: float = 0.0
	var rate: float = 25.0 * (1.0 + v * 0.3)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.27  # two poles at ~1.1 kHz
		lp2 += (lp - lp2) * 0.27
		hp = 0.95 * (hp + lp2 - prev)  # two poles at ~180 Hz
		prev = lp2
		hp2 = 0.95 * (hp2 + hp - prev2)
		prev2 = hp
		var pulse: float = 0.7 + 0.3 * sin(TAU * rate * t)
		var ph: float = fmod(t, 1.2) / 1.2
		var breath: float = pow(sin(PI * clampf(ph / 0.85, 0.0, 1.0)), 0.8) * (1.0 if ph < 0.45 else 0.75)
		b[i] = hp2 * pulse * breath * smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(2.1, 2.4, t))
	var m: float = 0.0
	for i: int in b.size():
		m = maxf(m, absf(b[i]))
	if m > 0.0:
		for i: int in b.size():
			b[i] *= 0.35 / m
	return b


static func meow(v: float) -> PackedFloat32Array:
	var b := _buf(0.62)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / 0.62
		var f: float = (560.0 + 260.0 * sin(PI * minf(x * 1.3, 1.0)) - 180.0 * x) * (1.0 + v)
		ph += TAU * f / RATE
		var formant: float = 0.6 + 0.4 * sin(PI * x)
		var s: float = sin(ph) * 0.6 + sin(ph * 2.0) * 0.3 * formant + sin(ph * 3.0) * 0.12 * formant
		b[i] = s * sin(PI * pow(x, 0.7)) * 0.16
	return b


## [v9s] A three-part coo (the pigeon's longer call), its own rhythm per take.
static func coo3(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var parts: Array[Vector2] = []  # start, length
	var t0: float = 0.0
	for k: int in 3:
		var ln: float = rng.randf_range(0.18, 0.32) * (1.5 if k == 2 else 1.0)
		parts.append(Vector2(t0, ln))
		t0 += ln + rng.randf_range(0.06, 0.14)
	var b := _buf(t0)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var seg: float = 0.0
		var f: float = 380.0
		for k: int in 3:
			var p: Vector2 = parts[k]
			if t >= p.x and t < p.x + p.y:
				var u: float = (t - p.x) / p.y
				seg = sin(PI * u) * (0.8 + 0.2 * sin(TAU * 9.0 * t))
				f = (370.0 + 50.0 * k) - 70.0 * u * (1.0 if k == 2 else 0.4)
		ph += TAU * f * (1.0 + v) / RATE
		b[i] = (sin(ph) + 0.25 * sin(ph * 2.0)) * seg * 0.14
	return b


static func coo(v: float) -> PackedFloat32Array:
	var b := _buf(1.0)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var seg: float = 0.0
		var f: float = 380.0
		if t < 0.25:
			seg = sin(PI * t / 0.25)
			f = 360.0 + 60.0 * t / 0.25
		elif t > 0.35 and t < 0.95:
			var u: float = (t - 0.35) / 0.6
			seg = sin(PI * u) * (0.8 + 0.2 * sin(TAU * 9.0 * t))
			f = 420.0 - 80.0 * u
		ph += TAU * f * (1.0 + v) / RATE
		b[i] = (sin(ph) + 0.25 * sin(ph * 2.0)) * seg * 0.14
	return b


## A sparrow's call. [v9s] Eight takes that differ in shape, not only pitch: 1-4 notes, falling,
## rising or a chevron, short or drawn out, some with a trill.
static func chirp(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var n: int = [2, 3, 1, 4, 2, 3, 1, 2][v % 8]
	var shape: int = v % 3  # 0 falling, 1 rising, 2 chevron
	var note_s: float = rng.randf_range(0.06, 0.12) * (1.6 if n == 1 else 1.0)
	var rest_s: float = rng.randf_range(0.03, 0.08)
	var dur: float = n * (note_s + rest_s) + 0.03
	var b := _buf(dur)
	var ph: float = 0.0
	var base: float = rng.randf_range(3400.0, 5400.0)
	var sweep: float = rng.randf_range(900.0, 1800.0)
	var trill: float = 0.0 if v < 5 else rng.randf_range(35.0, 60.0)
	var steps: Array[float] = []
	for k: int in n:
		steps.append(rng.randf_range(-250.0, 250.0) - (120.0 * k if v % 2 == 0 else -80.0 * k))
	for i: int in b.size():
		var t: float = float(i) / RATE
		var k: int = int(t / (note_s + rest_s))
		var lt: float = (t - k * (note_s + rest_s)) / note_s
		if k >= n or lt > 1.0:
			b[i] = 0.0
			continue
		var f: float = base + steps[k]
		match shape:
			0: f += sweep * (1.0 - lt)
			1: f += sweep * lt
			_: f += sweep * sin(PI * lt)
		f += 200.0 * sin(TAU * trill * t) if trill > 0.0 else 0.0
		ph += TAU * f / RATE
		b[i] = sin(ph) * sin(PI * lt) * 0.1
	return b


## A robin-like phrase: a few clear whistled notes and warbles, different every variant.
## [v9s] Eight takes: a motif of 2-3 whistled notes, repeated or answered (like a real songbird's
## "tee-tee-too"), 0.7-1.8 s, each take on its own pitches, tempo and slides.
static func song(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var motif: Array[Vector3] = []  # length, pitch, slide
	for k: int in rng.randi_range(2, 3):
		motif.append(Vector3(rng.randf_range(0.06, 0.18), rng.randf_range(2100.0, 4300.0), rng.randf_range(-600.0, 600.0)))
	var reps: int = [2, 3, 1, 2, 3, 2, 1, 2][v % 8]
	var notes: Array = []  # [start, length, pitch, slide]
	var t0: float = 0.02
	var gap: float = rng.randf_range(0.025, 0.08)
	for r: int in reps:
		var up: float = 1.0 + (0.06 * r if v % 2 == 0 else -0.04 * r)  # each repeat a little higher (or lower)
		for m: Vector3 in motif:
			notes.append([t0, m.x, m.y * up, m.z])
			t0 += m.x + gap
		t0 += rng.randf_range(0.05, 0.16)
	if v % 3 == 0:  # an ending flourish
		notes.append([t0, 0.22, rng.randf_range(2600.0, 3600.0), rng.randf_range(-900.0, -400.0)])
		t0 += 0.24
	var b := _buf(minf(t0 + 0.05, 2.0))
	var ph: float = 0.0
	var vib: float = rng.randf_range(4.0, 9.0)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var amp: float = 0.0
		var f: float = 3000.0
		for nt: Array in notes:
			if t >= float(nt[0]) and t < float(nt[0]) + float(nt[1]):
				var u: float = (t - float(nt[0])) / float(nt[1])
				amp = sin(PI * u)
				f = float(nt[2]) * (1.0 + 0.04 * sin(TAU * vib * u)) + float(nt[3]) * (u - 0.5)
				break
		ph += TAU * f / RATE
		b[i] = (sin(ph) + 0.15 * sin(ph * 2.0)) * amp * 0.09
	return b


static func quack(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var b := _buf(0.3)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / 0.3
		ph += TAU * (300.0 - 90.0 * x) * (1.0 + v) / RATE
		var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var nasal: float = saw * (0.6 + 0.4 * sin(TAU * 1100.0 * t)) + rng.randf_range(-0.15, 0.15)
		b[i] = nasal * sin(PI * pow(x, 0.5)) * 0.11
	return b


static func gull(v: float, calls: int = 3) -> PackedFloat32Array:
	var b := _buf(0.3 * calls)  # [v9s] 2, 3 or 4 cries
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var k: float = fmod(t / 0.3, 1.0)
		var f: float = (1500.0 - 700.0 * k + 200.0 * sin(PI * k)) * (1.0 + v)
		ph += TAU * f / RATE
		var s: float = sin(ph) * 0.6 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.1
		b[i] = s * sin(PI * minf(k / 0.85, 1.0)) * 0.08 * (1.0 - t / (0.3 * calls + 0.2))
	return b


## [v9s] Six takes: pulse rate, length and pitch differ; two of them croak twice.
static func frog(rng: RandomNumberGenerator, v: float, take: int = 0) -> PackedFloat32Array:
	var one: float = [0.42, 0.3, 0.5, 0.26, 0.36, 0.45][take % 6]
	var two: bool = take == 3 or take == 5
	var len_s: float = one * (2.0 + 0.25) if two else one
	var rate: float = [32.0, 26.0, 38.0, 30.0, 23.0, 35.0][take % 6]
	var b := _buf(len_s)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var tt: float = t if t < one else t - one * 1.25
		var x: float = clampf(tt / one, 0.0, 1.0) if tt >= 0.0 else 1.0
		ph += TAU * (150.0 + 40.0 * sin(PI * x)) * (1.0 + v) / RATE
		var pulses: float = pow(0.5 + 0.5 * sin(TAU * rate * t), 2.0)
		var s: float = 0.45 * sin(ph) + 0.7 * sin(ph * 2.0) + 0.45 * sin(ph * 3.1) + rng.randf_range(-0.1, 0.1)  # [v8snd] weight up the overtones
		b[i] = s * pulses * sin(PI * x) * 0.13
	return b


static func seal(v: float) -> PackedFloat32Array:
	var b := _buf(0.5)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / 0.5
		ph += TAU * (420.0 - 160.0 * x) * (1.0 + v) / RATE
		var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0
		b[i] = (saw * 0.5 + sin(ph * 2.0) * 0.3) * sin(PI * pow(x, 0.6)) * 0.12
	return b


static func flutter(rng: RandomNumberGenerator, rate: float) -> PackedFloat32Array:
	var b := _buf(0.9)
	var lp: float = 0.0
	var hp: float = 0.0
	var prev: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		# [fauna2] Softer: darker noise, fewer and rounder wingbeats that slow and fade.
		lp += (n - lp) * 0.12
		hp = 0.96 * (hp + lp - prev)  # [v9s] ~140 Hz high-pass: no rumble whatever the noise draws
		prev = lp
		var beat: float = pow(0.5 + 0.5 * sin(TAU * 9.0 * rate * t * (1.0 - 0.3 * t)), 2.0)
		b[i] = hp * 1.3 * beat * 0.3 * (1.0 - smoothstep(0.25, 0.9, t)) * smoothstep(0.0, 0.05, t)
	return b


## Four seconds of crickets: three chirpers at different rates; whole numbers of cycles so it
## loops cleanly.
static func crickets(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 4.0
	var b := _buf(dur)
	var voices: Array[Vector3] = [Vector3(4400.0, 2.0, 0.0), Vector3(4900.0, 2.5, 0.3), Vector3(4150.0, 1.75, 0.6)]
	for i: int in b.size():
		var t: float = float(i) / RATE
		var s: float = 0.0
		for vo: Vector3 in voices:
			var k: float = fmod(t * vo.y + vo.z, 1.0)
			var gate: float = 0.0
			if k < 0.3:
				gate = pow(0.5 + 0.5 * sin(TAU * 60.0 * t), 2.0) * sin(PI * k / 0.3)
			s += sin(TAU * vo.x * t) * gate
		b[i] = s * 0.035 + rng.randf_range(-0.002, 0.002)
	return b


# --- [fauna2] Frontier ambience ------------------------------------------------------------------

static var _loops: Dictionary = {}


## Registers the frontier one-shots (ice creaks, heron calls) with Audio.
static func ensure_frontier() -> void:
	if Audio.has_sound("ice_creak"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 6161
	Audio.override("ice_creak", [wav(ice_creak(rng, 0.0)), wav(ice_creak(rng, 0.25)), wav(ice_creak(rng, -0.2))])
	Audio.override("heron", [wav(heron(rng, 0.0)), wav(heron(rng, 0.08)), wav(heron(rng, -0.06))])


## Seamless ambience beds, made on first use: wind (desert gusts), insects (cicadas and a
## buzz), lapping (water against stones).
static func loop_stream(id: String) -> AudioStreamWAV:
	if not _loops.has(id):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var b := PackedFloat32Array()
		match id:
			"wind": b = wind(rng)
			"insects": b = insects(rng)
			"lapping": b = lapping(rng)
		_loops[id] = wav(b, true)
	return _loops[id]


## Makes a buffer loop seamlessly: its last `fade` seconds are crossfaded into its start and
## then dropped.
static func loopify(b: PackedFloat32Array, fade: float) -> PackedFloat32Array:
	var f: int = int(fade * RATE)
	var n: int = b.size() - f
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		out[i] = b[i]
	for i: int in f:
		var k: float = float(i) / f
		out[i] = b[i] * k + b[n + i] * (1.0 - k)
	return out


## Desert wind: low rumbling noise with slow gusts and a faint whistle on the strong ones.
static func wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 9.0
	var b := _buf(dur + 1.5)
	var lp: float = 0.0
	var lp2: float = 0.0
	var bp: float = 0.0
	var bv: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var gust: float = 0.55 + 0.3 * sin(TAU * t / 4.5) + 0.15 * sin(TAU * t / 1.7 + 1.3)
		var n: float = rng.randf_range(-1.0, 1.0)
		var cut: float = 0.02 + 0.05 * gust
		lp += (n - lp) * cut
		lp2 += (lp - lp2) * cut
		# A resonant band (~700 Hz) for the whistle.
		var w: float = TAU * (650.0 + 120.0 * gust) / RATE
		bv += (n - bp) * w * 0.08 - bv * 0.02
		bp += bv * w
		b[i] = lp2 * 0.9 * gust + bp * 0.01 * maxf(gust - 0.7, 0.0)
	MusicSynth.highpass(b, 100.0)  # [v8snd] was 49% under 80 Hz
	return loopify(b, 1.5)


## Insects: a cicada drone (pulsed high buzz, swelling and fading) and a softer second voice.
static func insects(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 8.0
	var b := _buf(dur)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var swell: float = pow(0.5 + 0.5 * sin(TAU * t / 8.0 - PI * 0.5), 1.5)
		var swell2: float = pow(0.5 + 0.5 * sin(TAU * t / 4.0 + 1.0), 2.0)
		var pulse: float = pow(0.5 + 0.5 * sin(TAU * 110.0 * t), 3.0)
		var pulse2: float = pow(0.5 + 0.5 * sin(TAU * 72.0 * t), 2.0)
		var s: float = sin(TAU * 5200.0 * t) * pulse * swell + sin(TAU * 3800.0 * t) * pulse2 * swell2 * 0.5
		b[i] = s * 0.03 + rng.randf_range(-0.003, 0.003)
	return b


## Water lapping against stones and walls: soft, irregular sloshes with the odd plip.
static func lapping(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 8.0
	var b := _buf(dur + 1.0)
	var lp: float = 0.0
	var lp2: float = 0.0
	var next: float = 0.0
	var env: float = 0.0
	var plips: Array[Vector2] = []
	for k: int in 5:
		plips.append(Vector2(rng.randf_range(0.0, dur), rng.randf_range(900.0, 1600.0)))
	for i: int in b.size():
		var t: float = float(i) / RATE
		if t >= next:
			next = t + rng.randf_range(0.7, 1.8)
			env = rng.randf_range(0.6, 1.0)
		env *= 0.99985
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.08
		lp2 += (lp - lp2) * 0.08
		var s: float = lp2 * env * 1.6
		for pl: Vector2 in plips:
			var d: float = t - pl.x
			if d >= 0.0 and d < 0.12:
				s += sin(TAU * pl.y * (1.0 + d * 3.0) * d) * exp(-d * 40.0) * 0.08
		b[i] = s
	return loopify(b, 1.0)


## Sea ice under strain: a stick-slip groan that speeds up, then a small crack.
static func ice_creak(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var b := _buf(1.4)
	var ph: float = 0.0
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / 1.4
		var f: float = (90.0 + 60.0 * x + rng.randf_range(-6.0, 6.0)) * (1.0 + v)
		ph += TAU * f / RATE
		var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var slip: float = pow(0.5 + 0.5 * sin(TAU * (14.0 + 30.0 * x) * t), 6.0)
		var crack: float = 0.0
		if x > 0.78 and x < 0.86:
			crack = rng.randf_range(-1.0, 1.0) * exp(-(x - 0.78) * 60.0)
		lp += (saw * slip - lp) * 0.3
		b[i] = (lp * 0.5 + crack * 0.6) * sin(PI * minf(x / 0.9, 1.0)) * 0.22
	return b


## A grey heron's harsh "fraank": a rough low call with a noisy edge.
static func heron(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var b := _buf(0.55)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / 0.55
		ph += TAU * (330.0 - 90.0 * x) * (1.0 + v) / RATE
		var saw: float = fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var rough: float = 0.65 + 0.35 * sin(TAU * 48.0 * t)
		var s: float = (saw * 0.6 + sin(ph * 3.0) * 0.25 + rng.randf_range(-0.3, 0.3)) * rough
		b[i] = s * sin(PI * pow(x, 0.4)) * 0.1
	return b
