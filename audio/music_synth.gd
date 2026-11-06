extends RefCounted
## Offline synthesis of the instrument samples used by the generative score
## (audio/music_director.gd). Everything is original and built at startup; no files.
## Each instrument is rendered once at a reference pitch and transposed by playback rate.

const RATE: int = 22050


static func build_all(seed_value: int = 777) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Dictionary = {}
	out["pad_warm"] = _entry(_pad([1.0, 0.32, 0.12, 0.04], rng), 57, true)
	var bright: Array = []
	for n: int in range(1, 11):
		bright.append(1.0 / n * exp(-(n - 1) * 0.28))
	out["pad_bright"] = _entry(_pad(bright, rng), 57, true)
	out["piano"] = _entry(_piano(rng), 69, false)
	out["kalimba"] = _entry(_kalimba(rng), 69, false)
	out["bell"] = _entry(_bell(), 81, false)
	out["bass"] = _entry(_bass(), 45, false)
	for v: int in 3:
		out["shaker%d" % v] = _entry(_shaker(rng, v), 69, false)
	out["kick"] = _entry(_kick(), 69, false)
	out["air"] = _entry(_air(rng), 69, true)
	return out


static func _entry(pcm: PackedFloat32Array, ref_midi: int, loop: bool) -> Dictionary:
	return {"pcm": pcm, "ref": ref_midi, "loop": loop, "stream": to_wav(pcm, loop)}


static func to_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
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


static func _normalize(b: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m: float = 0.0
	for i: int in b.size():
		m = maxf(m, absf(b[i]))
	if m > 0.0:
		var g: float = peak / m
		for i: int in b.size():
			b[i] *= g
	return b


## Raised-cosine fade in/out so one-shots never start or stop with a step.
static func _declick(b: PackedFloat32Array, attack_s: float, release_s: float) -> PackedFloat32Array:
	var a: int = mini(int(attack_s * RATE), b.size() / 2)
	var r: int = mini(int(release_s * RATE), b.size() / 2)
	for i: int in a:
		b[i] *= 0.5 - 0.5 * cos(PI * float(i) / a)
	for i: int in r:
		b[b.size() - 1 - i] *= 0.5 - 0.5 * cos(PI * float(i) / r)
	return b


## Seamless 2 s pad loop at A3 (220 Hz): three detuned wavetable voices. Every frequency is a
## multiple of 0.5 Hz, so each voice completes a whole number of cycles in the loop.
static func _pad(harmonics: Array, rng: RandomNumberGenerator) -> PackedFloat32Array:
	const TBL: int = 2048
	var table := PackedFloat32Array()
	table.resize(TBL + 1)
	for i: int in TBL:
		var s: float = 0.0
		for n: int in harmonics.size():
			s += float(harmonics[n]) * sin(TAU * (n + 1) * i / TBL)
		table[i] = s
	table[TBL] = table[0]
	var b := _buf(2.0)
	for f: float in [220.0, 220.5, 219.5]:
		var inc: float = f / RATE * TBL
		var ph: float = float(rng.randi_range(0, TBL - 1))
		for i: int in b.size():
			var idx: int = int(ph)
			var fr: float = ph - idx
			b[i] += table[idx] + (table[idx + 1] - table[idx]) * fr
			ph += inc
			if ph >= TBL:
				ph -= TBL
	return _normalize(b, 0.9)


## Felt piano at A4: slightly inharmonic partials, upper ones decaying faster, a soft hammer.
static func _piano(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(2.6)
	var f: float = 440.0
	var amps: Array[float] = [1.0, 0.42, 0.2, 0.1, 0.05, 0.025]
	for n: int in amps.size():
		var k: float = n + 1.0
		var fn: float = k * f * sqrt(1.0 + 0.00035 * k * k)
		var dec: float = 1.3 + 1.2 * n
		var a: float = amps[n]
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] += a * sin(TAU * fn * t) * (0.55 * exp(-dec * 2.2 * t) + 0.45 * exp(-dec * 0.5 * t))
	# Second string, a hair sharp, for warmth.
	var f2: float = f * 1.0011
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] += 0.45 * sin(TAU * f2 * t) * exp(-1.0 * t)
	var lp: float = 0.0
	for i: int in int(0.05 * RATE):
		var t: float = float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		b[i] += lp * 1.2 * exp(-t * 90.0)
	return _declick(_normalize(b, 0.9), 0.004, 0.2)


## Kalimba at A4: round fundamental, a quick metallic overtone, a tiny thumb tick.
static func _kalimba(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(2.2)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = sin(TAU * 440.0 * t) * exp(-2.1 * t) \
			+ 0.18 * sin(TAU * 2640.0 * t) * exp(-16.0 * t) \
			+ 0.07 * sin(TAU * 880.0 * t) * exp(-5.0 * t)
	var lp: float = 0.0
	for i: int in int(0.02 * RATE):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.15
		b[i] += lp * 0.5 * exp(-float(i) / RATE * 200.0)
	return _declick(_normalize(b, 0.9), 0.002, 0.2)


## Glassy bell at A5 with a slow beating shimmer.
static func _bell() -> PackedFloat32Array:
	var b := _buf(3.4)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = sin(TAU * 880.0 * t) * exp(-0.9 * t) \
			+ 0.4 * sin(TAU * 881.3 * t) * exp(-1.1 * t) \
			+ 0.22 * sin(TAU * 1760.0 * t) * exp(-1.8 * t) \
			+ 0.08 * sin(TAU * 2648.0 * t) * exp(-3.0 * t) \
			+ 0.035 * sin(TAU * 3660.0 * t) * exp(-5.0 * t)
	return _declick(_normalize(b, 0.9), 0.006, 0.3)


## Round bass at A2.
static func _bass() -> PackedFloat32Array:
	var b := _buf(3.0)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var s: float = sin(TAU * 110.0 * t) + 0.28 * sin(TAU * 220.0 * t) * exp(-1.2 * t) + 0.08 * sin(TAU * 330.0 * t) * exp(-2.5 * t)
		b[i] = tanh(s * 1.1) * exp(-0.55 * t)
	return _declick(_normalize(b, 0.9), 0.03, 0.4)


## Brushed shaker: band-limited noise with a soft swell.
static func _shaker(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var b := _buf(0.18)
	var lp1: float = 0.0
	var lp2: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp1 += (n - lp1) * 0.18
		lp2 += ((n - lp1) - lp2) * (0.55 + 0.05 * v)
		b[i] = lp2 * minf(t / (0.012 + 0.004 * v), 1.0) * exp(-t * (28.0 + 4.0 * v))
	return _declick(_normalize(b, 0.9), 0.002, 0.03)


## Soft, felted kick.
static func _kick() -> PackedFloat32Array:
	var b := _buf(0.5)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		ph += TAU * (48.0 + 38.0 * exp(-t * 22.0)) / RATE
		b[i] = sin(ph) * exp(-t * 7.0)
	return _declick(_normalize(b, 0.9), 0.003, 0.1)


## Ambient wind bed; the seam is crossfaded so it loops seamlessly.
static func _air(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds: float = 8.0
	var b := _buf(seconds)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		b[i] = lp2 * (0.6 + 0.4 * sin(TAU * t / seconds) * sin(TAU * 2.0 * t / seconds))
	var fade: int = int(0.5 * RATE)
	var n: int = b.size() - fade
	for i: int in fade:
		var g: float = float(i) / fade
		b[i] = b[i] * sqrt(g) + b[n + i] * sqrt(1.0 - g)
	b.resize(n)
	return _normalize(b, 0.9)
