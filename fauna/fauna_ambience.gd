class_name FaunaAmbience
extends Node
## [fauna2] Frontier soundscapes, quiet and under everything else (SFX bus):
##  - desert (Dust Flats, dune wilds): wind with gusts by day and night, insects by day;
##  - port (Frozen Port, frost wilds): gulls calling far off, sea ice creaking now and then;
##  - sunken (Sunken City): water lapping at the drowned streets, a heron's call now and then.
## Beds are synthesized once (FaunaSounds.loop_stream) and fade with the time of day.

var kind: String = ""  # "", desert, port, sunken
var _beds: Dictionary = {}  # id -> AudioStreamPlayer
var _vol: Dictionary = {}   # id -> current linear volume
var _shot_t: float = 4.0
var _rng := RandomNumberGenerator.new()


static func kind_for(regs: Array) -> String:
	if "dust_flats" in regs or "wild_dust" in regs:
		return "desert"
	if "frozen_port" in regs or "wild_frost" in regs:
		return "port"
	if "sunken_city" in regs:
		return "sunken"
	return ""


## Target bed levels (linear, 0..1) for a soundscape at a night amount (0 day .. 1 night).
static func levels(p_kind: String, night: float) -> Dictionary:
	match p_kind:
		"desert":
			return {"wind": 0.55 + 0.15 * night, "insects": 0.5 * (1.0 - night)}
		"port":
			return {"wind": 0.3}
		"sunken":
			return {"lapping": 0.6}
	return {}


func setup(regs: Array) -> void:
	name = "FaunaAmbience"
	kind = kind_for(regs)
	_rng.seed = hash(kind)
	if kind == "":
		return
	FaunaSounds.ensure_frontier()
	for id: String in levels(kind, 0.0):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = FaunaSounds.loop_stream(id)
		p.volume_db = -80.0
		add_child(p)
		_beds[id] = p
		_vol[id] = 0.0


func tick(delta: float, night: float, sound_at: Callable, lumi: Vector3) -> void:
	if kind == "":
		return
	var want: Dictionary = levels(kind, night)
	for id: String in _beds:
		var p: AudioStreamPlayer = _beds[id]
		_vol[id] = move_toward(float(_vol[id]), float(want.get(id, 0.0)), delta * 0.25)
		var v: float = float(_vol[id])
		if v > 0.01:
			if not p.playing:
				p.play(_rng.randf() * 4.0)
			AudioVol.set_db(p, linear_to_db(v) - 12.0)  # [qafix] crash fix
		elif p.playing:
			p.stop()
	_shot_t -= delta
	if _shot_t > 0.0:
		return
	_shot_t = _rng.randf_range(7.0, 18.0)
	var far: Vector3 = lumi + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(14.0, 26.0)
	match kind:
		"port":
			if _rng.randf() < 0.55 and night < 0.6:
				sound_at.call("gull", far + Vector3(0, 8, 0), -6.0)
			else:
				sound_at.call("ice_creak", far, -2.0)
		"sunken":
			if night < 0.6 and _rng.randf() < 0.6:
				sound_at.call("heron", far, -4.0)
		"desert":
			if night > 0.5 and _rng.randf() < 0.3:
				sound_at.call("chirp", far, -14.0)
