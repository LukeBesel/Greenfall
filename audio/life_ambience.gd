class_name LifeAmbience
extends Node
## [v6life] The sound follows the cleaning (owner item 58; and items 32 and 50: no nagging loops, very
## little chirping). This is a planet's local bed, driven by the ground round Lumi (a few rings of
## cells, about 30 m), on top of the planet's own bed (audio/ambience.gd). It is data: data/sound.json
## planets.<id>.ambience.life (see docs/ADJUSTING.md, "Music and sound"); a planet without a "life"
## block gets none. Verdance's:
##   dirty ground  -> a low, gritty wind, and now and then a far-off creak of scrap;
##   green ground  -> a soft breeze in leaves, and now and then one far, quiet bird phrase by day.
## Loops are on the Ambience bus, crossfaded over several seconds as Lumi walks from one to the
## other; in between (clean but bare) it is nearly silent. One-shots are rare: each has its own
## BeepGate slot, and a bird phrase ("song", "chirp") also takes Fauna's shared bird-call clock.
## Loops are synthesized (or loaded, for a res:// file) on a worker thread at start: no hitch.

const Synth := preload("res://audio/ambience_synth.gd")
const BIRDS: Array[String] = ["song", "chirp", "coo"]
## Fallbacks for the life block's "mix", "when" and "min_gap_floor_s" (data/sound.json is the source).
const MIX: Dictionary = {"dirty_from": 0.25, "dirty_full": 0.85, "green_from": 0.12, "green_full": 0.6, "dirty_hushes_green": 0.6}
const WHEN: Dictionary = {"dirty": 0.6, "green": 0.3, "night": 0.3}
## No one-shot of the bed plays twice within this many seconds, whatever its own numbers say
## (owner items 32 and 50: very little chirping). Loops are beds and are not counted.
const MIN_GAP_FLOOR_S: float = 60.0

var cells: SphereCells
var grid: SphereGrid
var world: Node
var bed: Dictionary = {}  # the planet's life block
var dirty: float = 0.0  # share of the land round Lumi still under junk
var green: float = 0.0  # mean green of the land round Lumi
var shots_played: Dictionary = {}  # sound -> plays

var _loops: Array = []  # [{id, db, on, player, vol}]
var _events: Array = []  # [{snd, gap, db, pitch, when, min_gap, t, streams}]
var _shot: AudioStreamPlayer
var _task: int = -1
var _pcm: Dictionary = {}  # worker output: loop id / event sound -> PCM or AudioStream (or an Array of them)
var _poll: float = 0.0
var _cell: int = -1
var _rings: int = 3
var _fade_s: float = 6.0
var _rng := RandomNumberGenerator.new()
var _mix: Dictionary = MIX
var _when: Dictionary = WHEN
var min_gap_floor: float = MIN_GAP_FLOOR_S


## The life block of a planet's ambience in data/sound.json ({} when the planet has none).
static func bed_of(planet_id: String) -> Dictionary:
	var v: Variant = SoundCfg.ambience(planet_id).get("life")
	return v if v is Dictionary else {}


func setup(p_world: Node, globe: OrbitPlanet, planet_id: String = "verdance") -> void:
	name = "LifeAmbience"
	world = p_world
	cells = globe.cells
	grid = globe.grid
	configure(bed_of(planet_id))
	if (_loops.size() > 0 or _events.size() > 0) and (DisplayServer.get_name() != "headless" or DevHooks.has("life-sound")):
		var want: Array = []
		for l: Dictionary in _loops:
			want.append(["loop", l["id"]])
		for e: Dictionary in _events:
			want.append(["shot", e["snd"]])
		_task = WorkerThreadPool.add_task(_synth.bind(want), false, "life ambience")


## Reads a life block (data/sound.json planets.<id>.ambience.life): loops, events, mix, when, floor.
func configure(p_bed: Dictionary) -> void:
	bed = p_bed
	_loops.clear()
	_events.clear()
	_rng.seed = 90210
	_rings = int(bed.get("rings", 3))
	_fade_s = maxf(0.5, float(bed.get("fade_s", 6.0)))
	_mix = _merged(MIX, bed.get("mix"))
	_when = _merged(WHEN, bed.get("when"))
	min_gap_floor = maxf(0.0, float(bed.get("min_gap_floor_s", MIN_GAP_FLOOR_S)))
	var loops: Variant = bed.get("loops")
	if loops is Dictionary:
		for lid: String in loops:
			var d: Variant = loops[lid]
			if d is Array and (d as Array).size() >= 2:
				_loops.append({"id": lid, "db": float(d[0]), "on": str(d[1]), "player": _player("Life_" + lid.get_file()), "vol": 0.0})
	var evs: Variant = bed.get("events")
	if evs is Array:
		for e: Variant in evs:
			if e is Array and (e as Array).size() >= 7:
				var lo: float = maxf(float(e[1]), min_gap_floor)
				var gap := Vector2(lo, maxf(lo, float(e[2])))
				_events.append({"snd": str(e[0]), "gap": gap, "db": float(e[3]), "pitch": Vector2(float(e[4]), float(e[5])),
					"when": str(e[6]), "min_gap": maxf(float(e[7]) if (e as Array).size() > 7 else gap.x, min_gap_floor),
					"t": _rng.randf_range(gap.x * 0.4, gap.y), "streams": []})
				shots_played[str(e[0])] = 0
	if _shot == null:
		_shot = _player("LifeShot")


## What configure() made of the data (tests, --life-report): loop id -> dB, and per event its gaps.
func read_back() -> Dictionary:
	var lo: Dictionary = {}
	for l: Dictionary in _loops:
		lo[l["id"]] = l["db"]
	var ev: Array = []
	for e: Dictionary in _events:
		ev.append({"snd": e["snd"], "gap": e["gap"], "db": e["db"], "min_gap": e["min_gap"], "when": e["when"]})
	return {"rings": _rings, "fade_s": _fade_s, "mix": _mix, "when": _when, "floor": min_gap_floor, "loops": lo, "events": ev}


func _player(nm: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nm
	p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "SFX"
	p.volume_db = -80.0
	add_child(p)
	return p


## Worker thread: loops and local one-shots as PCM (pure maths, own RNG), or files loaded.
func _synth(want: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var out: Dictionary = {}
	for w: Array in want:
		var id: String = w[1]
		if id.begins_with("res://"):
			out[id] = ResourceLoader.load(id) if ResourceLoader.exists(id) else null
		elif w[0] == "loop":
			out[id] = Synth._level(Synth.wind(rng, 8.0, 0.8, 0.0, 0.0)) if id == "leaves" else Synth.loop_pcm(id)
		elif id == "amb_creak":
			var list: Array = []
			for v: int in 3:
				list.append(Synth.creak(rng, v))
			out[id] = list
	_pcm = out


static func _stream(v: Variant, loop: bool) -> AudioStream:
	if v is AudioStream:
		return v
	if v is PackedFloat32Array and not (v as PackedFloat32Array).is_empty():
		return Synth.MusicSynth.to_wav(v, loop)
	return null


static func _merged(base: Dictionary, over: Variant) -> Dictionary:
	var out: Dictionary = base.duplicate()
	if over is Dictionary:
		for k: String in over:
			if (over[k] is float or over[k] is int) and out.has(k):
				out[k] = float(over[k])
	return out


## Target bed weights (dirty bed, green bed) for a dirty share and a mean green, both 0..1.
## `mix`: the life block's "mix" (dirty_from/full: the junk share that starts / fills the dirty bed;
## green_from/full: the same for the mean green; dirty_hushes_green: how much junk quiets the green bed).
static func weights(p_dirty: float, p_green: float, mix: Dictionary = MIX) -> Vector2:
	var dw: float = smoothstep(float(mix["dirty_from"]), float(mix["dirty_full"]), p_dirty)
	var gw: float = smoothstep(float(mix["green_from"]), float(mix["green_full"]), p_green)
	return Vector2(dw, gw * (1.0 - float(mix["dirty_hushes_green"]) * smoothstep(0.4, 0.9, p_dirty)))


## (dirty share, mean green) of the land cells in a list.
static func measure(p_cells: SphereCells, list: PackedInt32Array) -> Vector2:
	var land: int = 0
	var d: int = 0
	var g: float = 0.0
	for i: int in list:
		if p_cells.state[i] == 5:
			continue
		land += 1
		if p_cells.is_dirty(i):
			d += 1
		elif (p_cells.flags[i] & SphereCells.F_HUB) == 0:
			g += float(p_cells.green[i]) / 255.0
	return Vector2(float(d) / land, g / land) if land > 0 else Vector2.ZERO


## Whether a one-shot's "when" holds: dirty (mostly junk round Lumi), green, green_day (green, not night), always.
## `th`: the life block's "when" (dirty: junk share, green: mean green, night: darkness 0..1 above which it is night).
static func when_ok(when: String, p_dirty: float, p_green: float, night: float, th: Dictionary = WHEN) -> bool:
	match when:
		"dirty": return p_dirty > float(th["dirty"])
		"green": return p_green > float(th["green"])
		"green_day": return p_green > float(th["green"]) and night < float(th["night"])
		"always": return true
	return false


func _night() -> float:
	var sky: Variant = world.get("sky_director") if world else null
	if not (sky is Object):
		return 0.0
	var tod: float = float((sky as Object).get("time_of_day"))
	return maxf(1.0 - smoothstep(0.19, 0.27, tod), smoothstep(0.75, 0.83, tod))


func _process(delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for l: Dictionary in _loops:
			(l["player"] as AudioStreamPlayer).stream = _stream(_pcm.get(l["id"]), true)
		for e: Dictionary in _events:
			var v: Variant = _pcm.get(e["snd"])
			for x: Variant in (v if v is Array else [v]):
				var s: AudioStream = _stream(x, false)
				if s:
					(e["streams"] as Array).append(s)
		_pcm = {}
	var dt: float = minf(delta, 0.25)
	_poll -= dt
	if _poll <= 0.0:
		_poll = 1.0
		var patch: Variant = world.get("patch") if world else null
		if patch is Node3D and (patch as Node3D).is_inside_tree():
			_cell = grid.cell_at_from((patch as Node3D).global_position, _cell)
			var m: Vector2 = measure(cells, grid.cells_around(_cell, _rings))
			dirty = m.x
			green = m.y
	var want: Vector2 = weights(dirty, green, _mix)
	for l: Dictionary in _loops:
		var on: String = l["on"]
		_fade(l, want.x if on == "dirty" else (want.y if on == "green" else (1.0 if on == "always" else 0.0)), dt)
	for e: Dictionary in _events:
		e["t"] = float(e["t"]) - dt
		if float(e["t"]) > 0.0:
			continue
		var gap: Vector2 = e["gap"]
		e["t"] = _rng.randf_range(gap.x, gap.y)
		var snd: String = e["snd"]
		var night: float = _night()
		if not when_ok(e["when"], dirty, green, night, _when) or not BeepGate.take("life_" + snd, float(e["min_gap"])):
			continue
		var pitch: float = _rng.randf_range((e["pitch"] as Vector2).x, (e["pitch"] as Vector2).y)
		var streams: Array = e["streams"]
		if not streams.is_empty():
			_shot.stream = streams[_rng.randi() % streams.size()]
			_shot.pitch_scale = pitch
			_shot.volume_db = float(e["db"])
			_shot.play()
		elif snd.begins_with("amb_") or snd.begins_with("res://"):
			continue  # not synthesized / loaded (yet, or headless)
		else:
			if snd in BIRDS and not Fauna.bird_call_ok(night):
				continue
			FaunaSounds.ensure()
			Audio.play(snd, pitch, float(e["db"]), 0.03)
		shots_played[snd] = int(shots_played.get(snd, 0)) + 1


func _fade(l: Dictionary, want: float, dt: float) -> void:
	l["vol"] = move_toward(float(l["vol"]), want, dt / _fade_s)
	var p: AudioStreamPlayer = l["player"]
	if p.stream == null:
		return
	var v: float = l["vol"]
	if v > 0.01:
		if not p.playing:
			p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.2))
		AudioVol.set_db(p, linear_to_db(v) + float(l["db"]))
	elif p.playing:
		p.stop()
