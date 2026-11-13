extends Node
## [sound] Planet ambience beds on the "Ambience" bus (which sends to "SFX", so the SFX slider
## governs it). Each planet has a few seamless loops plus random one-shot events; every entry has
## a ruined and a restored weight, so restoration crossfades the dead world (wind, groans, creaks)
## into a living one (birds, insects, water). Verdance's bed is empty in the data: its wildlife
## ambience is fauna/fauna.gd and the town life's dirty-to-clean bed (v6life), on the same bus. Driven by Audio.set_planet_theme() / Audio.set_restoration().
##
## Loops and one-shots are synthesized once per planet, the first time it is chosen
## (audio/ambience_synth.gd, plus FaunaSounds' birds / gulls / crickets and Audio's own SFX).

const Synth := preload("res://audio/ambience_synth.gd")
const BUS: String = "Ambience"
const LOOP_DB: float = -14.0  # a loop at weight 1.0 (loops are levelled to -20 dBFS RMS)
const FADE_S: float = 3.0  # crossfade time for planet / restoration changes

## [v6sound] The beds are data now: data/sound.json planets.<id>.ambience (core/sound_cfg.gd).
## loops: id -> [ruined, restored] weight. events: [sound, min_s, max_s, db, pitch_lo, pitch_hi,
## ruined, restored] (the weight is the chance an event fires when its timer comes up).
## level_db trims the whole bed of that planet.
static func bed(id: String) -> Dictionary:
	var b: Dictionary = SoundCfg.ambience(id)
	if not (b.get("loops") is Dictionary) or not (b.get("events") is Array):
		return {}
	return b


static var _loop_cache: Dictionary = {}  # loop id -> AudioStreamWAV
static var _shot_cache: Dictionary = {}  # amb_* -> Array[AudioStreamWAV]

var planet: String = ""
var restoration: float = 0.0
var _loops: Dictionary = {}  # loop id -> {player, cur, w}
var _timers: Array[float] = []
var _shots: Array[AudioStreamPlayer] = []
var _next_shot: int = 0
var _rng := RandomNumberGenerator.new()
var _level_db: float = 0.0
var _bed: Dictionary = {}  # the current planet's bed (data/sound.json)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 5150
	for i: int in 4:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_shots.append(p)


## Switches the bed ("" clears it; a planet with an empty bed plays nothing here). Unknown ids are ignored (returns false).
func set_planet(id: String) -> bool:
	if id != "" and bed(id).is_empty():
		return false
	if id == planet:
		return true
	planet = id
	_bed = bed(id) if id != "" else {}
	for lid: String in _loops:
		_loops[lid]["w"] = 0.0
	_timers.clear()
	if planet == "":
		return true
	var b: Dictionary = _bed
	_level_db = float(b.get("level_db", 0.0))
	for lid: String in b["loops"]:
		_loop_stream(lid)  # build now (planet load), not mid-play when restoration brings it in
	for e: Array in b["events"]:
		_ensure_shot(str(e[0]))
		_timers.append(_rng.randf_range(float(e[1]) * 0.3, float(e[2])))
	_retarget()
	return true


func set_restoration(x: float) -> void:
	restoration = clampf(x, 0.0, 1.0)
	_retarget()


func active_loops() -> Array[String]:
	var out: Array[String] = []
	for lid: String in _loops:
		if float(_loops[lid]["w"]) > 0.0:
			out.append(lid)
	return out


func _retarget() -> void:
	if planet == "":
		return
	var defs: Dictionary = _bed["loops"]
	for lid: String in defs:
		var w: Array = defs[lid]
		var target: float = lerpf(float(w[0]), float(w[1]), restoration)
		if target > 0.0:
			_ensure_loop(lid)
		if _loops.has(lid):
			_loops[lid]["w"] = target


func _ensure_loop(lid: String) -> void:
	if not _loops.has(lid):
		var s: AudioStream = _loop_stream(lid)
		if s == null:
			return
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		_loops[lid] = {"player": p, "cur": 0.0, "w": 0.0}


static func _loop_stream(lid: String) -> AudioStream:
	if _loop_cache.has(lid):
		return _loop_cache[lid]
	if lid == "crickets":
		_loop_cache[lid] = FaunaSounds.crickets_loop()
		return _loop_cache[lid]
	var pcm: PackedFloat32Array = Synth.loop_pcm(lid)
	if pcm.is_empty():
		return null
	_loop_cache[lid] = Synth.MusicSynth.to_wav(pcm, true)
	return _loop_cache[lid]


func _ensure_shot(snd: String) -> void:
	if not snd.begins_with("amb_"):
		FaunaSounds.ensure()  # song / chirp / gull / frog live there
		return
	if _shot_cache.has(snd):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(snd) & 0x7FFFFFFF
	var list: Array = []
	for v: int in 3:
		var pcm: PackedFloat32Array
		match snd:
			"amb_creak": pcm = Synth.creak(rng, v)
			"amb_geyser": pcm = Synth.geyser(rng)
			"amb_buoy": pcm = Synth.buoy_bell(v)
			"amb_devil": pcm = Synth.dust_devil(rng, v)
		list.append(Synth.MusicSynth.to_wav(pcm, false))
	_shot_cache[snd] = list


func _process(delta: float) -> void:
	if Audio.is_world_paused():  # [v8pause] runs while paused (PROCESS_MODE_ALWAYS): no fades, no birds
		return
	var dt: float = minf(delta, 0.25)
	var gone: Array[String] = []
	for lid: String in _loops:
		var l: Dictionary = _loops[lid]
		var p: AudioStreamPlayer = l["player"]
		var cur: float = move_toward(float(l["cur"]), float(l["w"]), dt / FADE_S)
		l["cur"] = cur
		if cur <= 0.001:
			if p.playing:
				p.stop()
			if float(l["w"]) <= 0.0:
				gone.append(lid)
			continue
		AudioVol.set_db(p, linear_to_db(cur) + LOOP_DB + _level_db)  # [qafix] crash fix: no per-frame volume churn
		if not p.playing:
			p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.1))
	for lid: String in gone:
		(_loops[lid]["player"] as Node).queue_free()
		_loops.erase(lid)
	if planet == "":
		return
	var events: Array = _bed["events"]
	for i: int in mini(_timers.size(), events.size()):
		_timers[i] -= dt
		if _timers[i] > 0.0:
			continue
		var e: Array = events[i]
		_timers[i] = _rng.randf_range(float(e[1]), float(e[2]))
		if _rng.randf() < lerpf(float(e[6]), float(e[7]), restoration):
			_fire(str(e[0]), float(e[3]), _rng.randf_range(float(e[4]), float(e[5])))


func _fire(snd: String, db: float, pitch: float) -> void:
	var list: Array = _shot_cache.get(snd, []) if snd.begins_with("amb_") else Audio.streams_of(snd)
	if list.is_empty():
		return
	var p: AudioStreamPlayer = _shots[_next_shot]
	_next_shot = (_next_shot + 1) % _shots.size()
	p.stream = list[_rng.randi() % list.size()]
	p.pitch_scale = pitch
	p.volume_db = db + _level_db + _rng.randf_range(-3.0, 1.0)
	p.play()
	if Audio.sound_log:
		Audio.sound_log.call("played", snd, BUS, p.volume_db, p.stream.get_length() / maxf(pitch, 0.05))


func _exit_tree() -> void:
	for lid: String in _loops:
		(_loops[lid]["player"] as AudioStreamPlayer).stop()
	for p: AudioStreamPlayer in _shots:
		p.stop()
