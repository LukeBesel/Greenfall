extends RefCounted
## [sound] Instrument samples for the music sets (audio/music_tracks.gd SETS). Built lazily,
## once per set, the first time Audio.set_planet_theme() picks a planet that uses it, and merged into the
## music director's sample table. Reuses audio/music_synth.gd's pad / normalize / declick helpers.

const MusicSynth := preload("res://audio/music_synth.gd")
const RATE: int = 22050

## Which samples each music set needs (regrowth uses only the base set from MusicSynth).
const NEEDS: Dictionary = {
	"groove": ["marimba", "rim", "hat", "conga_hi", "conga_lo", "clap", "bass_short"],  # built at startup
	"regrowth": [],
	"desert_heat": ["pluck", "pad_reed", "frame"],
	"ocean_swell": ["harp", "pad_ocean", "steelpan"],
	"glass_ice": ["glass", "pad_ice", "choir"],
	"foundry": ["pulse", "forge_strike", "pad_brass", "choir", "synth", "metal", "sub"],
	"homecoming": ["choir"],
}


## Builds the samples `theme` needs that `have` lacks. Returns name -> sample entry.
static func build(theme: String, have: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(theme) & 0x7FFFFFFF
	for n: String in NEEDS.get(theme, []):
		if have.has(n):
			continue
		match n:
			"pluck": out[n] = MusicSynth._entry(_pluck(rng), 69, false)
			"frame": out[n] = MusicSynth._entry(_frame(rng), 69, false)
			"pad_reed": out[n] = MusicSynth._entry(MusicSynth._pad([1.0, 0.04, 0.5, 0.03, 0.28, 0.02, 0.14, 0.01, 0.06], rng), 57, true)
			"harp": out[n] = MusicSynth._entry(_harp(), 69, false)
			"pad_ocean": out[n] = MusicSynth._entry(MusicSynth._pad([1.0, 0.55, 0.3, 0.2, 0.12, 0.08, 0.05, 0.03], rng), 57, true)
			"glass": out[n] = MusicSynth._entry(_glass(), 81, false)
			"pad_ice": out[n] = MusicSynth._entry(MusicSynth._pad([1.0, 0.06, 0.2, 0.32, 0.0, 0.08, 0.0, 0.05], rng), 57, true)
			"pulse": out[n] = MusicSynth._entry(_pulse(rng), 45, false)
			"forge_strike": out[n] = MusicSynth._entry(_forge_strike(rng), 57, false)
			"marimba": out[n] = MusicSynth._entry(_marimba(), 69, false)
			"steelpan": out[n] = MusicSynth._entry(_steelpan(), 69, false)
			"rim": out[n] = MusicSynth._entry(_rim(rng), 69, false)
			"hat": out[n] = MusicSynth._entry(_hat(rng), 69, false)
			"clap": out[n] = MusicSynth._entry(_clap(rng), 69, false)
			"conga_hi": out[n] = MusicSynth._entry(_conga(rng, 1.0), 69, false)
			"conga_lo": out[n] = MusicSynth._entry(_conga(rng, 0.72), 69, false)
			"bass_short": out[n] = MusicSynth._entry(_bass_short(), 45, false)
			"sub": out[n] = MusicSynth._entry(_sub(), 45, false)
			"synth": out[n] = MusicSynth._entry(_synth(), 69, false)
			"metal": out[n] = MusicSynth._entry(_metal(rng), 57, false)
			"choir":
				# An "ah" choir: harmonics of A3 shaped by two vowel formants (~750 Hz, ~1150 Hz).
				var hc: Array = []
				for k: int in range(1, 16):
					var f: float = 220.0 * k
					hc.append((exp(-pow((f - 750.0) / 260.0, 2.0)) + 0.6 * exp(-pow((f - 1150.0) / 300.0, 2.0)) + 0.25 / k) / sqrt(k))
				out[n] = MusicSynth._entry(MusicSynth._pad(hc, rng), 57, true)
			"pad_brass":
				var h: Array = []
				for k: int in range(1, 13):
					h.append(1.0 / k * exp(-(k - 1) * 0.18))
				out[n] = MusicSynth._entry(MusicSynth._pad(h, rng), 57, true)
	return out


static func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## desert_heat: a dry, plucked lute at A4 (bright partials that die fast, a woody body, a pick tick).
static func _pluck(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.6)
	for n: int in 8:
		var k: float = n + 1.0
		var a: float = 1.0 / pow(k, 1.1)
		var dec: float = 3.2 + 2.6 * n
		var f: float = 440.0 * k * (1.0 + 0.0004 * k)
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] += a * sin(TAU * f * t) * exp(-dec * t)
	var lp: float = 0.0
	for i: int in int(0.012 * RATE):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.4
		b[i] += lp * 0.6 * exp(-float(i) / RATE * 300.0)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.0015, 0.15)


## desert_heat: a frame drum (low skin, pitch drop, a little slap).
static func _frame(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.45)
	var ph: float = 0.0
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		ph += TAU * (92.0 + 60.0 * exp(-t * 30.0)) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.3
		b[i] = sin(ph) * exp(-t * 9.0) + lp * 0.5 * exp(-t * 45.0)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.002, 0.08)


## ocean_swell: a soft harp / glass-marimba at A4 for the flowing arpeggios.
static func _harp() -> PackedFloat32Array:
	var b := _buf(2.0)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = sin(TAU * 440.0 * t) * exp(-1.6 * t) \
			+ 0.3 * sin(TAU * 880.0 * t) * exp(-3.5 * t) \
			+ 0.12 * sin(TAU * 1320.0 * t) * exp(-6.0 * t) \
			+ 0.05 * sin(TAU * 1761.0 * t) * exp(-9.0 * t)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.003, 0.25)


## glass_ice: a crystalline bell at A5 (inharmonic partials, long shimmering tail).
static func _glass() -> PackedFloat32Array:
	var b := _buf(3.6)
	var parts: Array[Vector3] = [Vector3(1.0, 1.0, 0.7), Vector3(1.0013, 0.45, 0.8), Vector3(2.32, 0.3, 1.6),
		Vector3(4.25, 0.14, 2.8), Vector3(6.63, 0.07, 4.5)]
	for p: Vector3 in parts:
		var f: float = 880.0 * p.x
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] += p.y * sin(TAU * f * t) * exp(-p.z * t)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.004, 0.3)


## foundry: the low industrial pulse at A2 (a muffled thump with a faint metallic tick).
static func _pulse(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.4)
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var body: float = tanh((sin(TAU * 110.0 * t) + 0.4 * sin(TAU * 220.0 * t)) * 1.5) * exp(-t * 10.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.6
		var tick: float = (lp * 0.3 + 0.2 * sin(TAU * 2900.0 * t)) * exp(-t * 120.0)
		b[i] = body + tick
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.002, 0.06)


## foundry: a distant hammer-on-metal clank at A3 (inharmonic, fast highs).
static func _forge_strike(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(1.4)
	var parts: Array[Vector3] = [Vector3(1.0, 1.0, 3.0), Vector3(2.76, 0.6, 5.0), Vector3(5.4, 0.35, 9.0), Vector3(8.93, 0.2, 14.0)]
	for p: Vector3 in parts:
		var f: float = 220.0 * p.x
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] += p.y * sin(TAU * f * t) * exp(-p.z * t)
	var lp: float = 0.0
	for i: int in int(0.02 * RATE):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
		b[i] += lp * 0.8 * exp(-float(i) / RATE * 200.0)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.001, 0.2)


## Marimba at A4: wooden fundamental, the 4th partial a bar gives, a soft mallet knock.
static func _marimba() -> PackedFloat32Array:
	var b := _buf(1.3)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = sin(TAU * 440.0 * t) * exp(-3.2 * t) \
			+ 0.35 * sin(TAU * 1760.0 * 0.995 * t) * exp(-11.0 * t) \
			+ 0.12 * sin(TAU * 4400.0 * 0.98 * t) * exp(-30.0 * t) \
			+ 0.3 * sin(TAU * 220.0 * t) * exp(-60.0 * t)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.0015, 0.15)


## Steel pan at A4: a bright ping (strong octave, a bit of the twelfth) that rings and blooms.
static func _steelpan() -> PackedFloat32Array:
	var b := _buf(1.8)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var bloom: float = 1.0 - exp(-t * 18.0)
		b[i] = sin(TAU * 440.0 * t) * exp(-2.0 * t) \
			+ 0.55 * sin(TAU * 881.5 * t) * exp(-2.8 * t) * bloom \
			+ 0.2 * sin(TAU * 1323.0 * t) * exp(-5.0 * t) \
			+ 0.08 * sin(TAU * 1765.0 * t) * exp(-9.0 * t)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.002, 0.2)


## Soft rim / side-stick: a short woody click.
static func _rim(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.12)
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
		b[i] = (sin(TAU * 1700.0 * t) * 0.6 + sin(TAU * 820.0 * t) * 0.5 + lp * 0.5) * exp(-t * 55.0)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.0008, 0.03)


## Closed hat: a tick of bright noise.
static func _hat(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.08)
	var prev: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		var n: float = rng.randf_range(-1.0, 1.0)
		b[i] = (n - prev) * exp(-t * 70.0)
		prev = n * 0.6
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.0005, 0.02)


## Soft clap: three quick noise bursts and a short tail.
static func _clap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(0.3)
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.45
		var env: float = 0.0
		for k: int in 3:
			var u: float = t - k * 0.011
			if u >= 0.0:
				env = maxf(env, exp(-u * 160.0))
		env = maxf(env, 0.5 * exp(-maxf(0.0, t - 0.03) * 22.0) * (1.0 if t > 0.03 else 0.0))
		b[i] = lp * env
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.0005, 0.05)


## Hand drum (conga) at `k` x 330 Hz: a pitched skin with a slap.
static func _conga(rng: RandomNumberGenerator, k: float) -> PackedFloat32Array:
	var b := _buf(0.35)
	var ph: float = 0.0
	var lp: float = 0.0
	for i: int in b.size():
		var t: float = float(i) / RATE
		ph += TAU * 330.0 * k * (1.0 + 0.25 * exp(-t * 50.0)) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		b[i] = sin(ph) * exp(-t * 14.0) + 0.25 * sin(ph * 1.5) * exp(-t * 30.0) + lp * 0.4 * exp(-t * 90.0)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.001, 0.05)


## A shorter, rounder bass at A2 for walking / bouncing lines.
static func _bass_short() -> PackedFloat32Array:
	var b := _buf(0.9)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var s: float = sin(TAU * 110.0 * t) + 0.35 * sin(TAU * 220.0 * t) * exp(-6.0 * t) + 0.1 * sin(TAU * 330.0 * t) * exp(-9.0 * t)
		b[i] = tanh(s * 1.2) * exp(-3.2 * t)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.004, 0.15)


## foundry: a deep, slightly gritty sub bass at A2 that throbs.
static func _sub() -> PackedFloat32Array:
	var b := _buf(1.2)
	for i: int in b.size():
		var t: float = float(i) / RATE
		var s: float = sin(TAU * 110.0 * t + 0.6 * sin(TAU * 55.0 * t)) + 0.3 * sin(TAU * 165.0 * t)
		b[i] = tanh(s * 1.8) * exp(-2.2 * t) * (1.0 - exp(-t * 200.0))
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.004, 0.2)


## foundry: an ominous detuned synth lead at A4 (two band-limited saws a few cents apart, dark).
static func _synth() -> PackedFloat32Array:
	var b := _buf(1.4)
	for k: int in range(1, 9):
		var a: float = 1.0 / k * exp(-(k - 1) * 0.3)
		for det: float in [0.994, 1.006]:
			var f: float = 440.0 * det * k
			for i: int in b.size():
				var t: float = float(i) / RATE
				b[i] += a * sin(TAU * f * t)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] *= minf(t / 0.04, 1.0) * (0.55 * exp(-1.3 * t) + 0.45 * exp(-0.5 * t))
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.003, 0.25)


## foundry: a reverb-drenched metallic hit at A3 (inharmonic, long ringing tail).
static func _metal(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := _buf(3.2)
	var parts: Array[Vector3] = [Vector3(1.0, 1.0, 1.2), Vector3(1.47, 0.6, 1.5), Vector3(2.09, 0.5, 2.0),
		Vector3(2.56, 0.35, 2.6), Vector3(3.9, 0.2, 3.5), Vector3(5.3, 0.12, 5.0)]
	for p: Vector3 in parts:
		var f: float = 220.0 * p.x
		for i: int in b.size():
			var t: float = float(i) / RATE
			b[i] += p.y * sin(TAU * f * t + 0.4 * sin(TAU * 3.3 * t)) * exp(-p.z * t)
	var lp: float = 0.0
	for i: int in int(0.03 * RATE):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.6
		b[i] += lp * exp(-float(i) / RATE * 120.0)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.001, 0.4)
