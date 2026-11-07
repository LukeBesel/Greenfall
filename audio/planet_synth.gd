extends RefCounted
## [sound] Instrument samples for the planet music themes (audio/planet_themes.gd). Built lazily,
## once per planet, the first time Audio.set_planet_theme() picks that planet, and merged into the
## music director's sample table. Reuses audio/music_synth.gd's pad / normalize / declick helpers.

const MusicSynth := preload("res://audio/music_synth.gd")
const RATE: int = 22050

## Which samples each theme needs (Verdance uses only the base set from MusicSynth).
const NEEDS: Dictionary = {
	"ochre": ["pluck", "pad_reed", "frame"],
	"tidewell": ["harp", "pad_ocean"],
	"rime": ["glass", "pad_ice"],
	"anvil": ["pulse", "anvil", "pad_brass"],
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
			"anvil": out[n] = MusicSynth._entry(_anvil(rng), 57, false)
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


## Ochre: a dry, plucked lute at A4 (bright partials that die fast, a woody body, a pick tick).
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


## Ochre: a frame drum (low skin, pitch drop, a little slap).
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


## Tidewell: a soft harp / glass-marimba at A4 for the flowing arpeggios.
static func _harp() -> PackedFloat32Array:
	var b := _buf(2.0)
	for i: int in b.size():
		var t: float = float(i) / RATE
		b[i] = sin(TAU * 440.0 * t) * exp(-1.6 * t) \
			+ 0.3 * sin(TAU * 880.0 * t) * exp(-3.5 * t) \
			+ 0.12 * sin(TAU * 1320.0 * t) * exp(-6.0 * t) \
			+ 0.05 * sin(TAU * 1761.0 * t) * exp(-9.0 * t)
	return MusicSynth._declick(MusicSynth._normalize(b, 0.9), 0.003, 0.25)


## Rime: a crystalline bell at A5 (inharmonic partials, long shimmering tail).
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


## Anvil: the low industrial pulse at A2 (a muffled thump with a faint metallic tick).
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


## Anvil: a distant hammer-on-metal clank at A3 (inharmonic, fast highs).
static func _anvil(rng: RandomNumberGenerator) -> PackedFloat32Array:
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
