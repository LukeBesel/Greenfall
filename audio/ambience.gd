extends Node
## [sound] Planet ambience beds on the "Ambience" bus (which sends to "SFX", so the SFX slider
## governs it). A bed belongs to a music set (PlanetDefinition.music_set) and has a few seamless
## loops plus random one-shot events; every entry has a ruined and a restored weight, so
## restoration crossfades the dead world (wind, groans, creaks) into a living one (birds, insects,
## water). A set without a bed is silent here (the regrowth set: its wildlife ambience is
## fauna/fauna.gd). Driven by Audio.set_planet_theme() / Audio.set_restoration().
##
## Loops and one-shots are synthesized once per bed, the first time it is chosen
## (audio/ambience_synth.gd, plus FaunaSounds' birds / gulls / crickets and Audio's own SFX).

const Synth := preload("res://audio/ambience_synth.gd")
const Tracks := preload("res://audio/music_tracks.gd")
const BUS: String = "Ambience"
const LOOP_DB: float = -14.0  # a loop at weight 1.0 (loops are levelled to -20 dBFS RMS)
const FADE_S: float = 3.0  # crossfade time for planet / restoration changes

## loops: id -> [ruined, restored] weight. events: [sound, min_s, max_s, db, pitch_lo, pitch_hi,
## ruined, restored] (the weight is the chance an event fires when its timer comes up).
const BEDS: Dictionary = {
	"desert_heat": {
		"loops": {"wind_warm": [1.0, 0.55], "heat_buzz": [0.3, 0.12], "cicadas": [0.0, 0.5]},
		"events": [["whoosh", 8.0, 18.0, -15.0, 0.35, 0.5, 1.0, 0.4], ["song", 5.0, 12.0, -19.0, 0.9, 1.1, 0.0, 1.0],
			["chirp", 4.0, 9.0, -21.0, 0.9, 1.15, 0.0, 0.8]],
	},
	"ocean_swell": {
		"loops": {"waves": [1.0, 0.85], "wind_sea": [0.45, 0.25], "crickets": [0.0, 0.4], "water": [0.0, 0.35]},
		"events": [["gull", 5.0, 12.0, -13.0, 0.9, 1.1, 1.0, 1.0], ["amb_buoy", 9.0, 20.0, -17.0, 0.95, 1.05, 1.0, 0.6],
			["song", 6.0, 13.0, -20.0, 0.9, 1.1, 0.0, 0.9], ["frog", 7.0, 15.0, -20.0, 0.9, 1.1, 0.0, 0.6]],
	},
	"glass_ice": {
		"loops": {"wind_eerie": [1.0, 0.5], "water": [0.0, 0.65]},
		"events": [["amb_creak", 4.0, 11.0, -13.0, 0.8, 1.2, 1.0, 0.35], ["amb_geyser", 14.0, 30.0, -12.0, 0.9, 1.1, 1.0, 0.6],
			["song", 6.0, 14.0, -21.0, 1.0, 1.2, 0.0, 0.7], ["chirp", 5.0, 11.0, -22.0, 1.0, 1.2, 0.0, 0.6]],
	},
	"foundry": {
		"loops": {"wind_dust": [1.0, 0.5], "water": [0.0, 0.55], "crickets": [0.0, 0.45]},
		"events": [["groan", 7.0, 16.0, -13.0, 0.45, 0.65, 1.0, 0.2], ["clunk", 10.0, 22.0, -21.0, 0.5, 0.7, 1.0, 0.2],
			["amb_devil", 15.0, 35.0, -11.0, 0.9, 1.1, 1.0, 0.3], ["song", 5.0, 12.0, -19.0, 0.9, 1.1, 0.0, 1.0],
			["chirp", 4.0, 9.0, -21.0, 0.9, 1.15, 0.0, 0.8]],
	},
}

static var _loop_cache: Dictionary = {}  # loop id -> AudioStreamWAV
static var _shot_cache: Dictionary = {}  # amb_* -> Array[AudioStreamWAV]

var planet: String = ""
var restoration: float = 0.0
var _loops: Dictionary = {}  # loop id -> {player, cur, w}
var _timers: Array[float] = []
var _shots: Array[AudioStreamPlayer] = []
var _next_shot: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 5150
	for i: int in 4:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_shots.append(p)


## Switches the bed to a music set's ("" or a set without a bed clears it). Unknown names are
## ignored (returns false).
func set_planet(id: String) -> bool:
	if id != "" and not BEDS.has(id):
		if not Tracks.has_set(id):
			return false
		id = ""
	if id == planet:
		return true
	planet = id
	for lid: String in _loops:
		_loops[lid]["w"] = 0.0
	_timers.clear()
	if planet == "":
		return true
	var bed: Dictionary = BEDS[planet]
	for lid: String in bed["loops"]:
		_loop_stream(lid)  # build now (planet load), not mid-play when restoration brings it in
	for e: Array in bed["events"]:
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
	var defs: Dictionary = BEDS[planet]["loops"]
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
		AudioVol.set_db(p, linear_to_db(cur) + LOOP_DB)  # [qafix] crash fix: no per-frame volume churn
		if not p.playing:
			p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.1))
	for lid: String in gone:
		(_loops[lid]["player"] as Node).queue_free()
		_loops.erase(lid)
	if planet == "":
		return
	var events: Array = BEDS[planet]["events"]
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
	p.volume_db = db + _rng.randf_range(-3.0, 1.0)
	p.play()


func _exit_tree() -> void:
	for lid: String in _loops:
		(_loops[lid]["player"] as AudioStreamPlayer).stop()
	for p: AudioStreamPlayer in _shots:
		p.stop()
