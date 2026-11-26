extends Node
## [v10quit] Stress repro for the audio mixer race (signal 11 on the mixer thread copying a freed
## bus StringName). Every per-player volume_db / bus / pitch write on a playing player, and every
## stop or free, makes the AudioServer retire that playback's bus details; the main thread frees
## them two frames later, and a mixer thread stalled mid-copy then reads freed memory. A threaded
## load (all cores busy) with very short main frames is where the game hit it.
## This scene: CPU hog threads on every core + threaded loads of the game scene in a loop + many
## playing players churned every frame (fades, bus swaps, stop/start, free/new), like the music,
## ambience and loops do when a load starts.
##   godot --headless --path . res://tools/audio_race_stress.tscn -- [--seconds=20] [--players=48]
##       [--hogs=N] [--churn=volume,bus,stop,free] [--via=player|bus]
##       [--per-frame=40] [--no-mix-barrier]
## --via=bus fades through AudioServer bus volumes instead of per-player volume_db. Prints
## "[race] PASS ..." and exits 0; a crash is the failure. On its own the race is rare (about one
## game load in twenty on a busy box); tools/audio_race_force.py (gdb) forces it every time, and
## --no-mix-barrier switches off the fix (audio/mix_barrier.gd) to show the crash.

var _players: Array[AudioStreamPlayer] = []
var _hogs: Array[Thread] = []
var _stop_hogs: bool = false
var _stream: AudioStreamWAV
var _t: float = 0.0
var _secs: float = 20.0
var _n: int = 48
var _churn: PackedStringArray = PackedStringArray(["volume", "bus", "stop", "free"])
var _via_bus: bool = false
var _per_frame: int = 40  # players churned per frame: few, so main frames stay very short
var _frames: int = 0
var _writes: int = 0
var _loads: int = 0
var _loading: String = ""
var _rng := RandomNumberGenerator.new()
const BUSES: Array[String] = ["Master", "Music", "SFX", "Ambience", "UI"]
const LOAD_PATH: String = "res://scenes/slice.tscn"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			_secs = float(a.get_slice("=", 1))
		elif a.begins_with("--players="):
			_n = int(a.get_slice("=", 1))
		elif a.begins_with("--churn="):
			_churn = a.get_slice("=", 1).split(",")
		elif a.begins_with("--per-frame="):
			_per_frame = int(a.get_slice("=", 1))
		elif a == "--via=bus":
			_via_bus = true
	var hogs: int = OS.get_processor_count() * 3
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hogs="):
			hogs = int(a.get_slice("=", 1))
	Engine.max_fps = 0  # short main frames: retired bus details are freed two frames later
	_stream = _tone()
	for i: int in _n:
		_spawn()
	for i: int in hogs:
		var th := Thread.new()
		th.start(_hog, Thread.PRIORITY_HIGH)
		_hogs.append(th)
	print("[race] %d players, %d hogs, churn %s, via %s, %.0f s" % [_n, hogs, ",".join(_churn), "bus" if _via_bus else "player", _secs])


func _hog() -> void:
	var x: float = 0.0
	while not _stop_hogs:
		for i: int in 20000:
			x = sin(x + i)


func _tone() -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var b := PackedByteArray()
	b.resize(22050 * 2)
	for i: int in 22050:
		b.encode_s16(i * 2, int(sin(TAU * 220.0 * i / 22050.0) * 3000.0))
	w.data = b
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = 22050
	return w


func _spawn() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _stream
	p.bus = BUSES[_rng.randi() % BUSES.size()]
	add_child(p)
	p.play()
	_players.append(p)


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	# Threaded loads of the game scene, back to back (the loader's cores-busy phase).
	if _loading == "":
		if ResourceLoader.load_threaded_request(LOAD_PATH, "", true, ResourceLoader.CACHE_MODE_IGNORE) == OK:
			_loading = LOAD_PATH
	elif ResourceLoader.load_threaded_get_status(_loading) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		ResourceLoader.load_threaded_get(_loading)
		_loading = ""
		_loads += 1
	for k: int in mini(_per_frame, _players.size()):
		var i: int = _rng.randi() % _players.size()
		var p: AudioStreamPlayer = _players[i]
		if "volume" in _churn:
			if _via_bus:
				var bi: int = AudioServer.get_bus_index(BUSES[i % BUSES.size()])
				if bi > 0:
					AudioServer.set_bus_volume_db(bi, -6.0 * (1.0 + sin(_t * 7.0 + i)))
			else:
				p.volume_db = -6.0 * (1.0 + sin(_t * 7.0 + i))
			_writes += 1
		if "bus" in _churn and _rng.randf() < 0.2:
			p.bus = BUSES[_rng.randi() % BUSES.size()]
			_writes += 1
		if "stop" in _churn and _rng.randf() < 0.1:
			p.stop()
			p.play()
			_writes += 1
	if "free" in _churn:
		for k: int in 3:
			var j: int = _rng.randi() % _players.size()
			_players[j].queue_free()
			_players.remove_at(j)
			_spawn()
	if _t >= _secs:
		_finish()


func _finish() -> void:
	set_process(false)
	_stop_hogs = true
	for th: Thread in _hogs:
		th.wait_to_finish()
	if _loading != "":
		ResourceLoader.load_threaded_get(_loading)
	print("[race] PASS %d frames, %d writes, %d loads" % [_frames, _writes, _loads])
	get_tree().quit()
