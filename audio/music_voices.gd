extends Node
## Runtime voice backend for the music director: a pool of AudioStreamPlayers on one bus.
## Voice ids encode the player index and a generation so stale ids are ignored.

var _streams: Dictionary = {}  # sample name -> AudioStreamWAV
var _lengths: Dictionary = {}  # sample name -> seconds (one-shots)
var _loops: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _gen: PackedInt32Array = PackedInt32Array()
var _busy_until: PackedFloat64Array = PackedFloat64Array()  # INF while a loop holds it
var _started: PackedFloat64Array = PackedFloat64Array()


func setup(samples: Dictionary, bus: String, count: int = 48) -> void:
	add_samples(samples)
	for i: int in count:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	_gen.resize(count)
	_busy_until.resize(count)
	_started.resize(count)


## [sound] Registers more samples (planet instruments are built lazily).
func add_samples(samples: Dictionary) -> void:
	for n: String in samples:
		var e: Dictionary = samples[n]
		_streams[n] = e["stream"]
		_loops[n] = bool(e["loop"])
		_lengths[n] = float((e["pcm"] as PackedFloat32Array).size()) / 22050.0


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func start(sample: String, pitch: float, gain: float) -> int:
	if not _streams.has(sample) or _players.is_empty():
		return -1
	var now: float = _now()
	var idx: int = -1
	var oldest: int = -1
	for i: int in _players.size():
		if _busy_until[i] <= now:
			idx = i
			break
		if _busy_until[i] != INF and (oldest < 0 or _started[i] < _started[oldest]):
			oldest = i
	if idx < 0:
		idx = oldest
	if idx < 0:
		return -1
	var p: AudioStreamPlayer = _players[idx]
	p.stream = _streams[sample]
	p.pitch_scale = maxf(0.05, pitch)
	p.volume_db = _db(gain)
	p.play()
	_gen[idx] += 1
	_started[idx] = now
	_busy_until[idx] = INF if _loops[sample] else now + float(_lengths[sample]) / maxf(0.05, pitch) + 0.05
	return idx * 65536 + (_gen[idx] & 0xFFFF)


func set_gain(id: int, gain: float) -> void:
	var idx: int = _valid(id)
	if idx >= 0:
		AudioVol.set_db(_players[idx], _db(gain))  # [qafix] crash fix


func stop(id: int) -> void:
	var idx: int = _valid(id)
	if idx >= 0:
		_players[idx].stop()
		_busy_until[idx] = 0.0


func _valid(id: int) -> int:
	if id < 0:
		return -1
	@warning_ignore("integer_division")
	var idx: int = id / 65536
	if idx >= _players.size() or (_gen[idx] & 0xFFFF) != id % 65536:
		return -1
	return idx


func _db(gain: float) -> float:
	return maxf(-80.0, linear_to_db(maxf(gain, 0.0)))


func _exit_tree() -> void:
	# Stop playbacks before the AudioServer shuts down so none are leaked at exit.
	for p: AudioStreamPlayer in _players:
		p.stop()
		p.stream = null
