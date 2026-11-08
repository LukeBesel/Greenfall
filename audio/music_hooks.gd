class_name MusicHooks
extends Node
## Drives the procedural score from game state: mood (explore / base / night / cinematic),
## intensity from how healed the planet and district are, and stingers on key events.

## [sound] Story moods the hooks never override; whoever set one ends it with set_music_mood().
const STICKY_MOODS: Array[String] = ["homecoming"]
const BASE_ENTER: float = 9.0
const BASE_LEAVE: float = 13.0

var world: Node
var _near_base: bool = false
var _cinematic: bool = false
var _last_hex_sting: float = -10.0
var _t: float = 0.0
var _pinned_resto: float = -1.0  # [sound] dev --restoration


func _ready() -> void:
	EventBus.upgrade_bought.connect(func(_id: String, _lvl: int) -> void:
		Audio.music_activity(0.06)  # [sound] busy play picks the upbeat tracks
		Audio.music_sting("upgrade"))
	EventBus.robot_built.connect(func(_n: String) -> void:
		Audio.music_activity(0.15)
		Audio.music_sting("robot_built"))
	EventBus.hex_restored.connect(func(_h: int) -> void:
		Audio.music_activity(0.1)
		Audio.music_sting("level_up"))
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void:
		Audio.music_activity(0.07)
		var now: float = Time.get_ticks_msec() * 0.001
		if now - _last_hex_sting > 6.0:
			_last_hex_sting = now
			Audio.music_sting("hex_clean"))
	Audio.set_music_mood("explore")
	_tunes_setup()  # [tunes]
	# [sound] Dev: --planet-theme=ochre|tidewell|rime|anvil and --restoration=0..1 (pins it).
	if DevHooks.has("planet-theme"):
		var ok: bool = Audio.set_planet_theme(DevHooks.get_s("planet-theme", "verdance"))
		print("[sound] planet theme %s (%s)" % [Audio.get_planet_theme(), "ok" if ok else "unknown id ignored"])
	if DevHooks.has("restoration"):
		_pinned_resto = clampf(DevHooks.get_f("restoration", 0.0), 0.0, 1.0)
	_update_intensity()


## [tunes] The owner's songs in play: the background shuffle (unless the intro is about to take
## over), the CDs in the rubble and the quick-select (N, with Glim's Music upgrade).
## Dev: --cds=id,id grants CDs, --scratched=id,id puts scratched CDs in the case, --cd-drop makes
## the next cleaned hex turn up a CD.
func _tunes_setup() -> void:
	for id: String in DevHooks.get_s("cds", "").split(",", false):
		Tunes.grant(id.strip_edges(), true)
	for id: String in DevHooks.get_s("scratched", "").split(",", false):
		Tunes.hold(id.strip_edges())
	if DevHooks.has("cd-play"):  # --cd-play=shuffle|song id: the CD player plays it
		Radio.play(DevHooks.get_s("cd-play", "shuffle"))
	if DevHooks.has("cd-drop"):
		Tunes.st()["pity"] = 999
	if Tunes.context() != "intro":
		Tunes.set_context("play")
	if world == null:
		return
	var cd := CdFinds.new()
	cd.world = world
	add_child(cd)
	var pk := TunesPicker.new()
	pk.world = world
	world.add_child.call_deferred(pk)
	var sc := ScratchedCdUI.new()
	sc.world = world
	world.add_child.call_deferred(sc)
	var d: Node = Tunes.director()
	if d and world.get("patch") != null:
		d.set("listener", world.patch)


func _exit_tree() -> void:
	if Tunes.context() == "play":
		Tunes.set_context("none")  # [tunes] the next scene picks its own music


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
	if Audio.get_music_mood() != mood and not STICKY_MOODS.has(Audio.get_music_mood()):
		Audio.set_music_mood(mood)
	_update_intensity()


func _update_intensity() -> void:
	if world == null:
		return
	var district: float = 0.0
	if world.get("field") != null and world.field.junk_hex_count > 0:
		district = float(world.field.junk_hexes_cleaned()) / float(world.field.junk_hex_count)
	var planet: float = world.planet.restored_fraction() if world.get("planet") != null else 0.0
	Audio.set_restoration(_pinned_resto if _pinned_resto >= 0.0 else planet)  # [sound] themes and ambience bloom with it
	var robots: float = minf(1.0, float(world.fleet.robot_total()) / 12.0) if world.get("fleet") != null else 0.0
	Audio.set_music_intensity(clampf(0.12 + 0.45 * district + 0.25 * robots + 0.6 * planet, 0.0, 1.0))
