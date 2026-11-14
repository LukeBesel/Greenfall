extends SceneTree
## Renders the generative score offline to WAVs in screenshots/ and prints peak / RMS / NaN / click
## stats per scenario. Run: godot --headless --path . -s tools/render_music.gd [-- --seconds=60]

const Synth := preload("res://audio/music_synth.gd")
const Director := preload("res://audio/music_director.gd")
const Mixer := preload("res://audio/music_offline_mixer.gd")
const PlanetSynth := preload("res://audio/planet_synth.gd")  # [sound]
const RATE: int = 22050
const BLOCK: int = 512

# name -> list of [time_s, action, arg]
var scenarios: Dictionary = {
	"explore": [[0.0, "mood", "explore"], [0.0, "ramp", [0.1, 1.0]], [20.0, "sting", "upgrade"], [42.0, "sting", "level_up"]],
	"night": [[0.0, "mood", "night"], [0.0, "int", 0.5], [30.0, "sting", "hex_clean"]],
	"base": [[0.0, "mood", "base"], [0.0, "int", 0.85], [25.0, "sting", "robot_built"]],
	"cinematic": [[0.0, "mood", "cinematic"], [40.0, "sting", "robot_built"]],
	"menu": [[0.0, "mood", "menu"], [12.0, "sting", "first_sprout"]],
	"transitions": [[0.0, "mood", "explore"], [0.0, "int", 0.7], [15.0, "mood", "night"], [30.0, "mood", "cinematic"], [45.0, "mood", "base"], [50.0, "sting", "hex_clean"]],
	# [sound] Composed tracks are added in _init() (one scenario per track, plus restored ones).
	"rotation": [[0.0, "theme", "verdance"], [0.0, "int", 0.6], [0.0, "activity", 0.8], [0.0, "gaps", true]],
}


func _init() -> void:
	var seconds: float = 60.0
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	var t0: int = Time.get_ticks_msec()
	var only: String = ""
	var out_dir: String = ""
	var reverb: bool = false  # [sound] --reverb: approximate the Music bus reverb (previews)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
		if a == "--reverb":
			reverb = true
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
	var samples: Dictionary = Synth.build_all()
	print("synth build: %d ms" % (Time.get_ticks_msec() - t0))
	const Tracks := preload("res://audio/music_tracks.gd")  # [sound]
	for id: String in Tracks.TRACKS:
		var secs: float = 150.0 if id == "homecoming" else 50.0
		scenarios[id] = [[0.0, "track", id], [0.0, "int", 0.7], [0.0, "activity", 0.7], [0.0, "len", secs]]
		if (Tracks.TRACKS[id] as Dictionary).has("restored"):
			scenarios[id + "_restored"] = [[0.0, "resto", 1.0], [0.0, "track", id], [0.0, "int", 0.8], [0.0, "activity", 0.7], [0.0, "len", 50.0]]
	for th: String in PlanetSynth.NEEDS:  # [sound]
		var t2: int = Time.get_ticks_msec()
		samples.merge(PlanetSynth.build(th, samples))
		print("planet synth %s: %d ms" % [th, Time.get_ticks_msec() - t2])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	for sname: String in scenarios:
		if only != "" and not sname.begins_with(only):
			continue
		var t1: int = Time.get_ticks_msec()
		var mixer = Mixer.new(samples)
		var d = Director.new(samples, mixer, 99)
		var events: Array = (scenarios[sname] as Array).duplicate()
		var ramp: Array = []
		var ramp_resto: Array = []
		var total: int = int(seconds * RATE)
		for e0: Array in events:
			if str(e0[1]) == "len":
				total = int(float(e0[2]) * RATE)
		d.gaps_enabled = false
		var buf := PackedFloat32Array()
		var pos: int = 0
		var max_voices: int = 0
		while pos < total:
			var t: float = float(pos) / RATE
			while not events.is_empty() and float(events[0][0]) <= t:
				var e: Array = events.pop_front()
				match str(e[1]):
					"mood": d.set_mood(e[2])
					"int": d.set_intensity(e[2])
					"ramp": ramp = e[2]
					"sting": d.sting(e[2])
					"theme": d.set_theme(e[2])
					"track": d.play_track(e[2])
					"activity": d.pulse_activity(e[2])
					"gaps": d.gaps_enabled = e[2]
					"resto": d.set_restoration(e[2])
					"ramp_resto": ramp_resto = e[2]
			if not ramp_resto.is_empty():
				d.set_restoration(lerpf(ramp_resto[0], ramp_resto[1], t / seconds))
			if not ramp.is_empty():
				d.set_intensity(lerpf(ramp[0], ramp[1], t / seconds))
			d.update(float(BLOCK) / RATE)
			buf.append_array(mixer.mix(BLOCK, d.lpf_cutoff))
			max_voices = maxi(max_voices, mixer.voice_count())
			pos += BLOCK
		if reverb:
			buf = _reverb(buf)
		var peak: float = 0.0
		var sq: float = 0.0
		var bad: int = 0
		var max_jump: float = 0.0
		for i: int in buf.size():
			var x: float = buf[i]
			if is_nan(x) or is_inf(x):
				bad += 1
				continue
			peak = maxf(peak, absf(x))
			sq += x * x
			if i > 0:
				max_jump = maxf(max_jump, absf(x - buf[i - 1]))
		var rms: float = sqrt(sq / maxf(1.0, buf.size()))
		print("%-12s peak %6.1f dBFS  rms %6.1f dBFS  max_step %.4f  nan/inf %d  max_voices %d  (%d ms)" % [
			sname, linear_to_db(peak), linear_to_db(rms), max_jump, bad, max_voices, Time.get_ticks_msec() - t1])
		var path: String = "res://screenshots/music_%s.wav" % sname
		if out_dir != "":
			path = out_dir.path_join("music_%s.wav" % sname)
		Synth.to_wav(buf).save_to_wav(path if path.begins_with("/") else ProjectSettings.globalize_path(path))
	quit()



## [sound] A small Schroeder reverb (4 damped combs + 2 allpasses, 40 ms predelay, ~22% wet)
## standing in for the Music bus's AudioEffectReverb, so offline previews sound like the game.
static func _reverb(x: PackedFloat32Array) -> PackedFloat32Array:
	var lens: Array[int] = [558, 594, 638, 678, 278, 220]  # 4 combs, then 2 allpasses
	var off: PackedInt32Array = PackedInt32Array()
	var total: int = 0
	for n: int in lens:
		off.append(total)
		total += n
	var line := PackedFloat32Array()  # one flat buffer: packed arrays copy on assignment
	line.resize(total)
	var pos: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
	var damp: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var pre: int = int(0.04 * RATE)
	var out := PackedFloat32Array()
	out.resize(x.size())
	var hp: float = 0.0
	for i: int in x.size():
		var inp: float = x[i - pre] if i >= pre else 0.0
		hp += (inp - hp) * 0.15  # the bus reverb's hipass: keep the low end dry
		inp = (inp - hp) * 0.25
		var acc: float = 0.0
		for k: int in 4:
			var j: int = off[k] + pos[k]
			var y: float = line[j]
			damp[k] = y * 0.6 + damp[k] * 0.4
			line[j] = inp + damp[k] * 0.82
			pos[k] = (pos[k] + 1) % lens[k]
			acc += y
		for k: int in range(4, 6):
			var j: int = off[k] + pos[k]
			var bo: float = line[j]
			line[j] = acc + bo * 0.5
			pos[k] = (pos[k] + 1) % lens[k]
			acc = bo - acc
		out[i] = x[i] + acc * 0.22
	return out
