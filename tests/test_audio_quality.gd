extends GutTest
## [v8snd] The sounds that play for minutes at a time, and the cat's sounds, must not make laptop
## speakers rattle: no clipping, no DC, little energy under 80 Hz, no raw single-sample spikes
## (crackle), and the purr no full-depth low chop (it read as a helicopter). The owner heard "a
## rattling noise constantly, like my speakers blew out": the start yard's dust wind (raw spikes,
## ~43 a second, and 57% of it under 80 Hz) and the purr (sub-200 Hz noise chopped 24 times a
## second at full scale). The full audit of every built-in sound is tools/check_audio.py.

const Synth := preload("res://audio/ambience_synth.gd")
const MusicSynth := preload("res://audio/music_synth.gd")
const RATE: int = 22050


## Share of energy under 80 Hz (4-pole Butterworth low-pass, against the whole signal).
static func _sub80(b: PackedFloat32Array) -> float:
	var w0: float = TAU * 80.0 / RATE
	var alpha: float = sin(w0) / (2.0 * 0.7071)
	var a0: float = 1.0 + alpha
	var c0: float = (1.0 - cos(w0)) / 2.0 / a0
	var c1: float = (1.0 - cos(w0)) / a0
	var d1: float = -2.0 * cos(w0) / a0
	var d2: float = (1.0 - alpha) / a0
	var x := b.duplicate()
	for _stage: int in 2:
		var x1: float = 0.0
		var x2: float = 0.0
		var y1: float = 0.0
		var y2: float = 0.0
		for i: int in x.size():
			var xi: float = x[i]
			var y: float = c0 * xi + c1 * x1 + c0 * x2 - d1 * y1 - d2 * y2
			x2 = x1
			x1 = xi
			y2 = y1
			y1 = y
			x[i] = y
	var lo: float = 0.0
	var tot: float = 0.0
	var mean: float = 0.0
	for i: int in b.size():
		mean += b[i]
	mean /= maxf(1.0, b.size())
	for i: int in b.size():
		lo += x[i] * x[i]
		tot += (b[i] - mean) * (b[i] - mean)
	return lo / maxf(tot, 1e-12)


## Single-sample steps over 6x the local (10 ms) average step, per second: raw spikes / crackle.
static func _spikes_per_s(b: PackedFloat32Array) -> float:
	var k: int = int(RATE * 0.01)
	var d := PackedFloat32Array()
	d.resize(b.size() - 1)
	for i: int in d.size():
		d[i] = absf(b[i + 1] - b[i])
	var run: float = 0.0
	for i: int in mini(k, d.size()):
		run += d[i]
	var n: int = 0
	var last: int = -1000
	for i: int in d.size():
		var j: int = i + int(k * 0.5)
		if j < d.size():
			run += d[j]
		if j - k >= 0 and j - k < d.size():
			run -= d[j - k]
		if d[i] > 6.0 * run / k and d[i] > 0.002 and i - last > int(RATE * 0.002):
			n += 1
			last = i
	return n / (b.size() / float(RATE))


static func _peak_dc(b: PackedFloat32Array) -> Vector2:
	var pk: float = 0.0
	var s: float = 0.0
	for i: int in b.size():
		pk = maxf(pk, absf(b[i]))
		s += b[i]
	return Vector2(pk, s / maxf(1.0, b.size()))


func _check_bed(n: String, b: PackedFloat32Array) -> void:
	var pd: Vector2 = _peak_dc(b)
	assert_lt(pd.x, 0.99, "%s does not clip (peak %.3f)" % [n, pd.x])
	assert_lt(absf(pd.y), 0.01, "%s has no DC (%.4f)" % [n, pd.y])
	var sub: float = _sub80(b)
	assert_lt(sub, 0.25, "%s: %.0f%% under 80 Hz (rumble small speakers rattle on)" % [n, sub * 100.0])
	var sp: float = _spikes_per_s(b)
	assert_lt(sp, 2.0, "%s: %.1f raw spikes a second (crackle)" % [n, sp])
	var jump: float = absf(b[b.size() - 1] - b[0])
	assert_lt(jump, 0.08, "%s loops without a click (seam step %.3f)" % [n, jump])


func test_ambience_beds_do_not_rattle() -> void:
	for lid: String in ["wind_dust", "wind_warm", "wind_sea", "wind_eerie"]:
		_check_bed(lid, Synth.loop_pcm(lid))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	_check_bed("leaves", Synth._level(Synth.wind(rng, 8.0, 0.8, 0.0, 0.0)))


func test_score_air_bed_is_not_rumble() -> void:
	var air: Dictionary = MusicSynth.build_all()["air"]
	assert_lt(_sub80(air["pcm"]), 0.3, "the score's air bed is not mostly sub-bass")


func test_work_cues_have_headroom_and_little_sub_bass() -> void:
	for sound: String in ["scoop_draw", "bin_spill", "robot_start", "crunch", "roar"]:
		var takes: Array = Audio.streams_of(sound)
		assert_gte(takes.size(), 3, "%s varies between plays" % sound)
		for stream: AudioStreamWAV in takes:
			var pcm: PackedFloat32Array = _pcm_of(stream)
			assert_lt(_peak_dc(pcm).x, 0.75, "%s leaves headroom for other sources" % sound)
			assert_lt(_sub80(pcm), 0.25, "%s still reads on small speakers" % sound)


## The envelope's strongest 15-45 Hz component, relative to its mean (a steady chop's depth).
static func _chop_depth(b: PackedFloat32Array) -> float:
	var hop: int = int(RATE / 400.0)
	var env := PackedFloat32Array()
	for i: int in int(b.size() / float(hop)):
		var s: float = 0.0
		for j: int in hop:
			s += b[i * hop + j] * b[i * hop + j]
		env.append(sqrt(s / hop))
	var mean: float = 0.0
	for e: float in env:
		mean += e
	mean /= maxf(1.0, env.size())
	var best: float = 0.0
	for f: int in range(15, 46):
		var re: float = 0.0
		var im: float = 0.0
		for i: int in env.size():
			var ph: float = TAU * f * i * hop / RATE
			re += (env[i] - mean) * cos(ph)
			im += (env[i] - mean) * sin(ph)
		best = maxf(best, 2.0 * sqrt(re * re + im * im) / env.size() / maxf(mean, 1e-9))
	return best


## [v10snd] Owner, third report: "cats still sound like helicopter". The purr (noise pulsed 25
## times a second) is gone; a petted cat gives a soft mew. No cat sound may beat steadily at
## 15-45 Hz (what a rotor is, whatever its pitch), and none is loud.
func test_cat_sounds_are_not_a_helicopter() -> void:
	var sounds: Dictionary = {}
	FaunaSounds._synth_all(sounds)
	assert_false(sounds.has("purr"), "the purr is gone")
	assert_true(sounds.has("mew") and sounds.has("meow"))
	for nm: String in ["mew", "meow"]:
		for st: AudioStreamWAV in sounds[nm]:
			var b: PackedFloat32Array = _pcm_of(st)
			assert_lt(_peak_dc(b).x, 0.2, "%s is soft" % nm)
			assert_lt(_sub80(b), 0.05, "%s has no sub-bass" % nm)
			assert_lt(_chop_depth(b), 0.15, "%s has no steady 15-45 Hz beat" % nm)
	# The check itself: the old purr's recipe (band noise, 25 Hz pulse at +-30%) must fail it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	var old := PackedFloat32Array()
	old.resize(int(1.2 * RATE))
	var lp: float = 0.0
	for i: int in old.size():
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.27
		old[i] = lp * (0.7 + 0.3 * sin(TAU * 25.0 * i / RATE))
	assert_gt(_chop_depth(old), 0.2, "the check catches a 25 Hz pulsed noise (the old purr)")
	assert_gte(SoundCfg.min_gap("mew"), 4.0, "mashing E can't make a cat mew non-stop")
	assert_eq(SoundCfg.bus_of("mew"), "Ambience")


static func _pcm_of(st: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(st.data.size() / 2)
	for i: int in out.size():
		out[i] = st.data.decode_s16(i * 2) / 32768.0
	return out


func test_master_has_a_small_speaker_high_pass() -> void:
	var found: bool = false
	for i: int in AudioServer.get_bus_effect_count(0):
		var fx: AudioEffect = AudioServer.get_bus_effect(0, i)
		if fx is AudioEffectHighPassFilter:
			found = true
			assert_between((fx as AudioEffectHighPassFilter).cutoff_hz, 30.0, 120.0, "master high-pass sits under the bass")
	assert_true(found, "Master has the high-pass from data/sound.json master_highpass_hz")
