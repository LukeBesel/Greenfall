extends RefCounted
## [sound] Synthesized ambience loops and one-shots for the planet beds (audio/ambience.gd).
## All noise-based, 22.05 kHz mono, built lazily per planet. Loops have their seam crossfaded
## (like MusicSynth._air) so they repeat without a click.

const MusicSynth := preload("res://audio/music_synth.gd")
const RATE: int = 22050


## The bed loop `lid` (empty for unknown ids). Seeded per id, so it is the same every run.
static func loop_pcm(lid: String) -> PackedFloat32Array:
	return _level(_loop_raw(lid))


static func _loop_raw(lid: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(lid) & 0x7FFFFFFF
	match lid:
		"wind_warm": return wind(rng, 9.0, 0.35, 0.0, 0.35)
		"wind_sea": return wind(rng, 8.0, 0.5, 0.0, 0.0)
		"wind_eerie": return wind(rng, 8.0, 0.22, 640.0, 0.0)
		"wind_dust": return wind(rng, 9.0, 0.18, 0.0, 1.0)
		"heat_buzz": return heat_buzz(rng)
		"waves": return waves(rng)
		"water": return water(rng)
		"cicadas": return cicadas(rng)
	return PackedFloat32Array()


## Loudness match for bed loops: scale to `rms_db` RMS, then soft-knee anything over 0.7 so
## sparse spikes (grit, bubbles) can't clip. Bed weights then set the relative levels.
static func _level(b: PackedFloat32Array, rms_db: float = -20.0) -> PackedFloat32Array:
	if b.is_empty():
		return b
	var sq: float = 0.0
	for i: int in b.size():
		sq += b[i] * b[i]
	var rms: float = sqrt(sq / b.size())
	if rms <= 0.0:
		return b
	var g: float = db_to_linear(rms_db) / rms
	for i: int in b.size():
		var x: float = b[i] * g
		var ax: float = absf(x)
		if ax > 0.7:
			x = signf(x) * (0.7 + 0.25 * tanh((ax - 0.7) / 0.25))
		b[i] = x
	return b


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Crossfades the last `fade_s` into the start and trims it, so the buffer loops seamlessly.
static func _seam(b: PackedFloat32Array, fade_s: float = 0.5) -> PackedFloat32Array:
	var fade: int = int(fade_s * RATE)
	var n: int = b.size() - fade
	for i: int in fade:
		var g: float = float(i) / fade
		b[i] = b[i] * sqrt(g) + b[n + i] * sqrt(1.0 - g)
	b.resize(n)
	return b


## Wind: two-stage low-passed noise with slow gusts. `bright` 0..1 opens the filter, `whistle_hz`
## > 0 adds a resonant, slowly bending whistle (eerie), `grit` adds sand / dust crackle.
static func wind(rng: RandomNumberGenerator, seconds: float, bright: float, whistle_hz: float, grit: float) -> PackedFloat32Array:
	var b := _buf(seconds + 0.5)
	var lp: float = 0.0
	var lp2: float = 0.0
	var a1: float = 0.012 + 0.05 * bright
	var a2: float = 0.04 + 0.12 * bright
	# Resonator state for the whistle.
	var y1: float = 0.0
	var y2: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * a1
		lp2 += (lp - lp2) * a2
		var gust: float = 0.55 + 0.3 * sin(TAU * t / seconds + 0.7) + 0.15 * sin(TAU * 3.0 * t / seconds)
		var s: float = lp2 * gust
		if whistle_hz > 0.0:
			var f: float = whistle_hz * (1.0 + 0.12 * sin(TAU * 2.0 * t / seconds) + 0.04 * sin(TAU * 5.0 * t / seconds))
			var r: float = 0.997
			var c: float = 2.0 * r * cos(TAU * f / RATE)
			var y: float = n * 0.004 + c * y1 - r * r * y2
			y2 = y1
			y1 = y
			s += y * gust * gust * 0.6
		if grit > 0.0 and rng.randf() < 0.004 * grit * gust:
			s += rng.randf_range(-0.5, 0.5) * grit
		b[i] = s
	return MusicSynth._normalize(_seam(b), 0.8)


## Heat buzz: a faint electric shimmer of hot air (narrow high noise, fast flutter, a mains hum).
static func heat_buzz(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds: float = 4.0
	var b := _buf(seconds + 0.5)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.35
		lp2 += ((n - lp) - lp2) * 0.6  # band around 3-5 kHz
		var hp: float = lp2
		var flutter: float = 0.6 + 0.4 * sin(TAU * 19.0 * t) * sin(TAU * 0.5 * t)
		var hum: float = sin(TAU * 120.0 * t) * 0.15 + sin(TAU * 240.0 * t) * 0.08 + sin(TAU * 360.0 * t) * 0.04
		b[i] = hp * 0.25 * flutter + hum * (0.7 + 0.3 * sin(TAU * t / seconds))
	return MusicSynth._normalize(_seam(b), 0.6)


## Waves: two swells of different size per loop: rise, break, then a hissing wash back.
static func waves(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds: float = 13.0
	var b := _buf(seconds + 0.5)
	var lp: float = 0.0
	var lp2: float = 0.0
	var sizes: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(6.2, 0.7)]  # start, size
	for i: int in b.size():
		var t: float = float(i) / RATE
		var env: float = 0.12
		for w: Vector2 in sizes:
			var u: float = fposmod(t - w.x, seconds)
			var e: float = 0.0
			if u < 2.2:
				e = pow(u / 2.2, 2.0)
			elif u < 6.5:
				e = exp(-(u - 2.2) * 0.9)
			env += e * w.y
		var n: float = rng.randf_range(-1.0, 1.0)
		var a: float = 0.02 + 0.25 * clampf(env, 0.0, 1.0)
		lp += (n - lp) * a
		lp2 += (lp - lp2) * 0.3
		b[i] = lp2 * env
	return MusicSynth._normalize(_seam(b, 0.8), 0.8)


## Lumi hovering over water: a bright spray hiss with a quick flutter (2 s loop).
static func spray(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds: float = 2.0
	var b := _buf(seconds + 0.3)
	var lp: float = 0.0
	var prev: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.5
		var hp: float = lp - prev
		prev = lp
		var flutter: float = 0.7 + 0.3 * sin(TAU * 23.0 * t) + 0.15 * sin(TAU * 7.5 * t)
		var drops: float = rng.randf_range(-1.0, 1.0) * 0.8 if rng.randf() < 0.01 else 0.0
		b[i] = (hp * 0.9 + lp * 0.25) * flutter + drops
	return MusicSynth._normalize(_seam(b, 0.3), 0.7)


## Running water: a brook (low wash + many small bubble chirps). 6 s loop.
static func water(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds: float = 6.0
	var b := _buf(seconds + 0.5)
	var lp: float = 0.0
	for i: int in b.size():
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		b[i] = lp * (0.8 + 0.2 * sin(TAU * float(i) / RATE / seconds * 2.0))
	for k: int in 140:
		var start: int = rng.randi_range(0, b.size() - 600)
		var f0: float = rng.randf_range(500.0, 1400.0)
		var len_s: float = rng.randf_range(0.012, 0.03)
		var g: float = rng.randf_range(0.15, 0.4)
		var ph: float = 0.0
		for i: int in int(len_s * RATE):
			var t: float = float(i) / RATE
			ph += TAU * f0 * (1.0 + 2.2 * t / len_s) / RATE
			b[start + i] += sin(ph) * sin(PI * t / len_s) * g
	return MusicSynth._normalize(_seam(b), 0.7)


## Cicadas for warm planets: a pulsing high buzz that swells and fades twice per loop.
static func cicadas(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds: float = 6.0
	var b := _buf(seconds + 0.5)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var swell: float = pow(maxf(0.0, sin(TAU * t / seconds * 2.0)), 1.5)
		var buzz: float = pow(0.5 + 0.5 * sin(TAU * 82.0 * t), 3.0)
		b[i] = (sin(TAU * 5200.0 * t) + 0.4 * sin(TAU * 6100.0 * t)) * buzz * (0.15 + 0.85 * swell) + rng.randf_range(-0.01, 0.01)
	return MusicSynth._normalize(_seam(b), 0.5)


# --- One-shots ----------------------------------------------------------------

## Ice creak: stick-slip clicks speeding up and slowing through a woody resonance.
static func creak(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur: float = 0.7 + 0.25 * v
	var b := _buf(dur)
	var y1: float = 0.0
	var y2: float = 0.0
	var f: float = 320.0 + 140.0 * v
	var r: float = 0.992
	var c: float = 2.0 * r * cos(TAU * f / RATE)
	var ph: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / dur
		var rate: float = 35.0 + 120.0 * sin(PI * x) + 20.0 * sin(TAU * 3.0 * t)
		ph += rate / RATE
		var imp: float = 0.0
		if ph >= 1.0:
			ph -= 1.0
			imp = rng.randf_range(0.6, 1.0)
		var y: float = imp + c * y1 - r * r * y2
		y2 = y1
		y1 = y
		b[i] = y * sin(PI * x)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.8), 0.005, 0.05)


## Geyser: a pressure rumble, then a long hiss that rises and falls.
static func geyser(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var dur: float = 3.4
	var b := _buf(dur)
	var lp: float = 0.0
	var lp2: float = 0.0
	var prev: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.45
		var hiss: float = lp - prev
		prev = lp
		lp2 += (n - lp2) * 0.01
		var env: float = smoothstep(0.3, 0.9, t) * (1.0 - smoothstep(1.6, 3.4, t))
		var rum: float = lp2 * 6.0 * smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.8, 2.0, t))
		b[i] = hiss * env * 1.2 + rum
	return MusicSynth._declick(MusicSynth._normalize(b, 0.8), 0.02, 0.2)


## Buoy bell: a low, inharmonic bell tolling once, with the sea rocking it.
static func buoy_bell(v: int) -> PackedFloat32Array:
	var dur: float = 3.0
	var b := _buf(dur)
	var f0: float = [480.0, 520.0, 455.0][v % 3]
	var parts: Array[Vector3] = [Vector3(1.0, 1.0, 1.1), Vector3(2.0, 0.45, 1.6), Vector3(2.76, 0.3, 2.4), Vector3(5.4, 0.12, 4.0)]
	for p: Vector3 in parts:
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] += p.y * sin(TAU * f0 * p.x * t) * exp(-p.z * t) * (0.85 + 0.15 * sin(TAU * 1.3 * t))
	return MusicSynth._declick(MusicSynth._normalize(b, 0.7), 0.002, 0.3)


## Dust devil: a whirl of grit through a sweeping resonance that passes by.
static func dust_devil(rng: RandomNumberGenerator, v: int) -> PackedFloat32Array:
	var dur: float = 3.8 + 0.4 * v
	var b := _buf(dur)
	var y1: float = 0.0
	var y2: float = 0.0
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var x: float = t / dur
		var n: float = rng.randf_range(-1.0, 1.0)
		var f: float = 300.0 + 900.0 * sin(PI * x) + 120.0 * sin(TAU * (3.0 + v) * t)
		var r: float = 0.985
		var c: float = 2.0 * r * cos(TAU * f / RATE)
		var y: float = n * 0.05 + c * y1 - r * r * y2
		y2 = y1
		y1 = y
		lp += (n - lp) * 0.05
		var grit: float = rng.randf_range(-0.6, 0.6) if rng.randf() < 0.01 else 0.0
		b[i] = (y + lp * 0.6 + grit) * pow(sin(PI * x), 1.5)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.8), 0.02, 0.2)
