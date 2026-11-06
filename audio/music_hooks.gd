class_name MusicHooks
extends Node
## Drives the procedural score from game state: mood (explore / base / night / cinematic),
## intensity from how healed the planet and district are, and stingers on key events.

const BASE_ENTER: float = 9.0
const BASE_LEAVE: float = 13.0

var world: Node
var _near_base: bool = false
var _cinematic: bool = false
var _last_hex_sting: float = -10.0
var _t: float = 0.0


func _ready() -> void:
	EventBus.upgrade_bought.connect(func(_id: String, _lvl: int) -> void: Audio.music_sting("upgrade"))
	EventBus.robot_built.connect(func(_n: String) -> void: Audio.music_sting("robot_built"))
	EventBus.hex_restored.connect(func(_h: int) -> void: Audio.music_sting("level_up"))
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void:
		var now: float = Time.get_ticks_msec() * 0.001
		if now - _last_hex_sting > 6.0:
			_last_hex_sting = now
			Audio.music_sting("hex_clean"))
	Audio.set_music_mood("explore")
	_update_intensity()


## Story beats call this around cutscenes (first sprout, launches).
func set_cinematic(on: bool) -> void:
	_cinematic = on
	_t = 99.0


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0 or world == null or world.get("patch") == null:
		return
	_t = 0.0
	var d: float = world.patch.global_position.distance_to(world.depot.global_position)
	if _near_base and d > BASE_LEAVE:
		_near_base = false
	elif not _near_base and d < BASE_ENTER:
		_near_base = true
	var mood: String = "explore"
	if _cinematic:
		mood = "cinematic"
	elif _near_base:
		mood = "base"
	elif world.get("sky_director") != null:
		var tod: float = world.sky_director.time_of_day
		if tod < 0.22 or tod > 0.8:
			mood = "night"
	if Audio.get_music_mood() != mood:
		Audio.set_music_mood(mood)
	_update_intensity()


func _update_intensity() -> void:
	if world == null:
		return
	var district: float = 0.0
	if world.get("field") != null and world.field.junk_hex_count > 0:
		district = float(world.field.junk_hexes_cleaned()) / float(world.field.junk_hex_count)
	var planet: float = world.planet.restored_fraction() if world.get("planet") != null else 0.0
	var robots: float = minf(1.0, float(world.fleet.robots().size()) / 12.0) if world.get("fleet") != null else 0.0
	Audio.set_music_intensity(clampf(0.12 + 0.45 * district + 0.25 * robots + 0.6 * planet, 0.0, 1.0))
