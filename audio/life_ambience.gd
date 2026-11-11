class_name LifeAmbience
extends Node
## [v6life] The sound follows the cleaning (owner item 58; and items 32 and 50: no nagging loops, very
## little chirping). Verdance has no ambience bed of its own (audio/ambience.gd), so this is its
## local one, driven by the ground round Lumi (3 rings of cells, about 30 m):
##   dirty ground  -> a low, gritty wind, and now and then a far-off creak of scrap;
##   green ground  -> a soft breeze in leaves, and now and then one far, quiet bird phrase by day.
## Both beds are quiet noise loops on the Ambience bus (under the SFX slider), crossfaded over
## several seconds as Lumi walks from one to the other; in between (clean but bare) it is nearly
## silent. One-shots are rare: each has its own BeepGate slot (30 s and 50 s at least), and the bird
## phrase also takes Fauna's shared bird-call clock, so it never adds to the birds' own calls.
## The loops are synthesized on a worker thread at start (no hitch); until then it is silent.

const Synth := preload("res://audio/ambience_synth.gd")
const RINGS: int = 3
const WIND_DB: float = -25.0   # the dirty bed at full weight
const LEAVES_DB: float = -23.0  # the green bed at full weight
const FADE_S: float = 6.0
const CREAK_GAP: Vector2 = Vector2(35.0, 80.0)
const SONG_GAP: Vector2 = Vector2(50.0, 110.0)

var cells: SphereCells
var grid: SphereGrid
var world: Node
var dirty: float = 0.0  # share of the land round Lumi still under junk
var green: float = 0.0  # mean green of the land round Lumi
var shots_played: Dictionary = {"creak": 0, "song": 0}

var _wind: AudioStreamPlayer
var _leaves: AudioStreamPlayer
var _shot: AudioStreamPlayer
var _vol: Array[float] = [0.0, 0.0]
var _creaks: Array = []
var _task: int = -1
var _pcm: Array = []
var _poll: float = 0.0
var _cell: int = -1
var _creak_t: float = 20.0
var _song_t: float = 30.0
var _rng := RandomNumberGenerator.new()


func setup(p_world: Node, globe: OrbitPlanet) -> void:
	name = "LifeAmbience"
	world = p_world
	cells = globe.cells
	grid = globe.grid
	_rng.seed = 90210
	_wind = _player("LifeWind")
	_leaves = _player("LifeLeaves")
	_shot = _player("LifeCreak")
	if DisplayServer.get_name() != "headless" or DevHooks.has("life-sound"):
		_task = WorkerThreadPool.add_task(_synth, false, "life ambience")


func _player(nm: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = nm
	p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "SFX"
	p.volume_db = -80.0
	add_child(p)
	return p


## Worker thread: the two loops and three creaks as PCM (pure maths, own RNG).
func _synth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var out: Array = [Synth.loop_pcm("wind_dust"), Synth._level(Synth.wind(rng, 8.0, 0.8, 0.0, 0.0))]
	for v: int in 3:
		out.append(Synth.creak(rng, v))
	_pcm = out


## Target bed weights (wind, leaves) for a dirty share and a mean green, both 0..1.
static func weights(p_dirty: float, p_green: float) -> Vector2:
	return Vector2(smoothstep(0.25, 0.85, p_dirty), smoothstep(0.12, 0.6, p_green) * (1.0 - 0.6 * smoothstep(0.4, 0.9, p_dirty)))


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


static func creak_ok(p_dirty: float) -> bool:
	return p_dirty > 0.6


static func song_ok(p_green: float, night: float) -> bool:
	return p_green > 0.3 and night < 0.3


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
		if _pcm.size() >= 5:
			_wind.stream = Synth.MusicSynth.to_wav(_pcm[0], true)
			_leaves.stream = Synth.MusicSynth.to_wav(_pcm[1], true)
			for v: int in 3:
				_creaks.append(Synth.MusicSynth.to_wav(_pcm[2 + v], false))
		_pcm = []
	var dt: float = minf(delta, 0.25)
	_poll -= dt
	if _poll <= 0.0:
		_poll = 1.0
		var patch: Variant = world.get("patch") if world else null
		if patch is Node3D and (patch as Node3D).is_inside_tree():
			_cell = grid.cell_at_from((patch as Node3D).global_position, _cell)
			var m: Vector2 = measure(cells, grid.cells_around(_cell, RINGS))
			dirty = m.x
			green = m.y
	var want: Vector2 = weights(dirty, green)
	_fade(_wind, 0, want.x, WIND_DB, dt)
	_fade(_leaves, 1, want.y, LEAVES_DB, dt)
	_creak_t -= dt
	if _creak_t <= 0.0:
		_creak_t = _rng.randf_range(CREAK_GAP.x, CREAK_GAP.y)
		if creak_ok(dirty) and not _creaks.is_empty() and BeepGate.take("life_creak", 30.0):
			_shot.stream = _creaks[_rng.randi() % _creaks.size()]
			_shot.pitch_scale = _rng.randf_range(0.75, 1.05)
			_shot.volume_db = -27.0
			_shot.play()
			shots_played["creak"] = int(shots_played["creak"]) + 1
	_song_t -= dt
	if _song_t <= 0.0:
		_song_t = _rng.randf_range(SONG_GAP.x, SONG_GAP.y)
		var night: float = _night()
		if song_ok(green, night) and BeepGate.take("life_song", 50.0) and Fauna.bird_call_ok(night):
			FaunaSounds.ensure()
			Audio.play("song", _rng.randf_range(0.95, 1.1), -25.0, 0.03)
			shots_played["song"] = int(shots_played["song"]) + 1


func _fade(p: AudioStreamPlayer, k: int, want: float, full_db: float, dt: float) -> void:
	_vol[k] = move_toward(_vol[k], want, dt / FADE_S)
	if p.stream == null:
		return
	if _vol[k] > 0.01:
		if not p.playing:
			p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.2))
		AudioVol.set_db(p, linear_to_db(_vol[k]) + full_db)
	elif p.playing:
		p.stop()
