extends SceneTree
## [sound] Builds every planet ambience loop and one-shot and prints build time, peak and RMS
## (dBFS, before the bed's LOOP_DB). Run: godot --headless --path . -s tools/ambience_levels.gd

const Synth := preload("res://audio/ambience_synth.gd")


func _init() -> void:
	for lid: String in ["wind_warm", "wind_sea", "wind_eerie", "wind_dust", "heat_buzz", "waves", "water", "cicadas"]:
		var t0: int = Time.get_ticks_msec()
		var s: AudioStreamWAV = Synth.MusicSynth.to_wav(Synth.loop_pcm(lid), true)
		_report(lid, s, Time.get_ticks_msec() - t0)
	var rng := RandomNumberGenerator.new()
	var t1: int = Time.get_ticks_msec()
	var shots: Dictionary = {"creak": Synth.creak(rng, 1), "geyser": Synth.geyser(rng), "buoy": Synth.buoy_bell(0), "devil": Synth.dust_devil(rng, 1), "spray": Synth.spray(rng)}
	print("one-shots built in %d ms" % (Time.get_ticks_msec() - t1))
	for n: String in shots:
		_report(n, Synth.MusicSynth.to_wav(shots[n]), 0)
	quit()


func _report(n: String, s: AudioStreamWAV, ms: int) -> void:
	var d: PackedByteArray = s.data
	var peak: float = 0.0
	var sq: float = 0.0
	var count: int = d.size() / 2
	for i: int in count:
		var x: float = d.decode_s16(i * 2) / 32768.0
		peak = maxf(peak, absf(x))
		sq += x * x
	print("%-12s %5.1fs  peak %6.1f  rms %6.1f dBFS  (%d ms)" % [n, count / 22050.0, linear_to_db(peak), linear_to_db(sqrt(sq / count)), ms])
