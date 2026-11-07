class_name FaunaSounds
extends RefCounted
## [wild] Synthesized animal sounds, registered on the Audio autoload by name the first time a
## district with animals loads (Audio.override), like the rest of the game's SFX: purr, meow,
## coo, chirp, song (a few robin phrases), quack, gull, frog, seal, flutter (a flock taking
## off) and a seamless cricket bed (crickets_loop(), played by Fauna on its own player).

const RATE: int = 22050

static var _done: bool = false
static var _crickets: AudioStreamWAV


static func ensure() -> void:
	if _done:
		return
	_done = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	var reg := func(name: String, bufs: Array) -> void:
		var streams: Array = []
		for b: PackedFloat32Array in bufs:
			streams.append(wav(b))
		Audio.override(name, streams)
	reg.call("purr", [purr(rng, 0.0), purr(rng, 0.15), purr(rng, -0.1)])
	reg.call("meow", [meow(0.0), meow(0.12), meow(-0.08)])
	reg.call("coo", [coo(0.0), coo(0.1), coo(-0.06)])
	reg.call("chirp", [chirp(rng, 0), chirp(rng, 1), chirp(rng, 2), chirp(rng, 3)])
	reg.call("song", [song(rng, 0), song(rng, 1), song(rng, 2), song(rng, 3)])
	reg.call("quack", [quack(rng, 0.0), quack(rng, 0.08), quack(rng, -0.06)])
	reg.call("gull", [gull(0.0), gull(0.1), gull(-0.08)])
	reg.call("frog", [frog(rng, 0.0), frog(rng, 0.12), frog(rng, -0.1)])
	reg.call("seal", [seal(0.0), seal(0.1), seal(-0.1)])
	reg.call("flutter", [flutter(rng, 0.8), flutter(rng, 1.0), flutter(rng, 1.3)])


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


## A cat's purr: ~25 Hz pulses of low, breathy noise, in and out breaths.
static func purr(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var b := _buf(2.4)
	var lp: float = 0.0
	var lp2: float = 0.0
	var rate: float = 24.0 * (1.0 + v * 0.3)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.06
		lp2 += (lp - lp2) * 0.15
		var pulse: float = pow(0.5 + 0.5 * sin(TAU * rate * t), 3.0)
		var breath: float = 0.55 + 0.45 * sin(TAU * t / 1.2 - 1.2)
		var tone: float = sin(TAU * rate * 2.0 * t) * 0.25
		b[i] = (lp2 * 7.0 + tone * lp2 * 4.0) * pulse * breath * 0.5 * smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(2.1, 2.4, t))
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


static func chirp(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var b := _buf(0.32)
	var ph: float = 0.0
	var n: int = 2 + v % 3
	var base: float = rng.randf_range(3800.0, 5200.0)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var k: float = fmod(t * n / 0.32, 1.0)
		var on: float = sin(PI * clampf(k / 0.6, 0.0, 1.0)) if k < 0.6 else 0.0
		ph += TAU * (base + 1400.0 * (1.0 - k)) / RATE
		b[i] = sin(ph) * on * 0.1
	return b


## A robin-like phrase: a few clear whistled notes and warbles, different every variant.
static func song(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var b := _buf(1.6)
	var ph: float = 0.0
	var notes: Array[Vector3] = []  # start, length, pitch
	var t0: float = 0.02
	while t0 < 1.45:
		var ln: float = rng.randf_range(0.07, 0.2)
		notes.append(Vector3(t0, ln, rng.randf_range(2200.0, 4200.0) + 300.0 * v))
		t0 += ln + rng.randf_range(0.02, 0.09)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var amp: float = 0.0
		var f: float = 3000.0
		for nt: Vector3 in notes:
			if t >= nt.x and t < nt.x + nt.y:
				var u: float = (t - nt.x) / nt.y
				amp = sin(PI * u)
				f = nt.z * (1.0 + 0.12 * sin(TAU * u * (2.0 + float(v)))) + 500.0 * (u - 0.5) * (1 if int(nt.z) % 2 == 0 else -1)
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


static func gull(v: float) -> PackedFloat32Array:
	var b := _buf(0.9)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var k: float = fmod(t / 0.3, 1.0)
		var f: float = (1500.0 - 700.0 * k + 200.0 * sin(PI * k)) * (1.0 + v)
		ph += TAU * f / RATE
		var s: float = sin(ph) * 0.6 + sin(ph * 2.0) * 0.25 + sin(ph * 3.0) * 0.1
		b[i] = s * sin(PI * minf(k / 0.85, 1.0)) * 0.08 * (1.0 - t / 1.1)
	return b


static func frog(rng: RandomNumberGenerator, v: float) -> PackedFloat32Array:
	var b := _buf(0.42)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / 0.42
		ph += TAU * (150.0 + 40.0 * sin(PI * x)) * (1.0 + v) / RATE
		var pulses: float = pow(0.5 + 0.5 * sin(TAU * 32.0 * t), 2.0)
		var s: float = sin(ph) + 0.5 * sin(ph * 2.0) + 0.3 * sin(ph * 3.1) + rng.randf_range(-0.1, 0.1)
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
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.35
		var beat: float = pow(0.5 + 0.5 * sin(TAU * 14.0 * rate * t + sin(TAU * 3.0 * t)), 4.0)
		b[i] = lp * beat * 0.4 * (1.0 - smoothstep(0.3, 0.9, t)) * smoothstep(0.0, 0.03, t)
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
