class_name Radio
extends Node3D
## [extras] The base radio: a little valve radio on the workbench that plays the procedural score's
## moods and the radio arrangements (audio/music_director.gd MOODS "song_*"). Songs unlock as
## districts and planets are restored (data/radio.json), with a small toast. Picking a song
## overrides the mood music (Audio.set_music_override) until "Back to mood music".
## State: GameState.flags.radio = {unlocked: [song ids], song: "" (playing) }. Pure rules are
## static (tests, the save round trip); the live node is the prop, its interactable and the
## unlock check.

const PATH: String = "res://data/radio.json"
## On the end of the workbench (scenes/slice.gd _build_board: the shack opens toward +X).
const POS := Vector3(-5.55, 0.95, 3.35)
const REACH_AT := Vector3(-4.75, 0.0, 3.45)
const REACH: float = 1.15

static var _cfg: Dictionary = {}

var world: Node
var _cone: Node3D
var _dial: MeshInstance3D
var _dial_mat: StandardMaterial3D
var _t: float = 0.0
var _check_t: float = 0.0


# --- Rules (static) ---------------------------------------------------------------------

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func songs() -> Array:
	return cfg().get("songs", [])


static func song(id: String) -> Dictionary:
	for s: Dictionary in songs():
		if str(s["id"]) == id:
			return s
	return {}


static func st() -> Dictionary:
	var v: Variant = GameState.flags.get("radio")
	if not (v is Dictionary):
		v = {"unlocked": [], "song": ""}
		GameState.flags["radio"] = v
	var d: Dictionary = v
	if not (d.get("unlocked") is Array):
		d["unlocked"] = []
	return d


static func districts_l5() -> int:
	var n: int = 0
	for k: Variant in GameState.districts:
		var d: Variant = GameState.world if int(k) == GameState.current_hub else GameState.districts[k]
		if d is Dictionary and int((d as Dictionary).get("hub_level", 1)) >= 5:
			n += 1
	return n


static func cond_value(c: Dictionary) -> float:
	match str(c.get("type", "")):
		"districts_l5":
			return float(districts_l5())
		"districts":
			return float(GameState.districts.size())
	return Achievements.value_of(c)


static func is_unlocked(id: String) -> bool:
	var s: Dictionary = song(id)
	if s.is_empty():
		return false
	return not s.has("cond") or id in (st()["unlocked"] as Array)


static func unlocked_count() -> int:
	var n: int = 0
	for s: Dictionary in songs():
		if is_unlocked(str(s["id"])):
			n += 1
	return n


## Unlocks every song whose condition now holds. Returns the new ids (in data order).
static func check_unlocks() -> Array[String]:
	var out: Array[String] = []
	var ul: Array = st()["unlocked"]
	for s: Dictionary in songs():
		var id: String = str(s["id"])
		if not s.has("cond") or id in ul:
			continue
		var c: Dictionary = s["cond"]
		if cond_value(c) >= float(c.get("target", 1.0)) - 0.000001:
			ul.append(id)
			out.append(id)
	GameState.stats["radio_songs"] = float(unlocked_count())
	return out


static func playing() -> String:
	return str(st().get("song", ""))


## Plays a song ("" = back to the mood music). False if it is still locked.
static func play(id: String) -> bool:
	if id != "" and not is_unlocked(id):
		return false
	st()["song"] = id
	Audio.set_music_override(str(song(id).get("mood", "")) if id != "" else "")
	if id != "":
		GameState.inc_stat("radio_plays")
	return true


# --- Live node --------------------------------------------------------------------------

func setup(p_world: Node) -> void:
	world = p_world
	name = "Radio"
	_build()
	var y: float = 0.0
	position = POS + Vector3(0, y, 0)
	var anchor := Node3D.new()
	anchor.name = "RadioReach"
	world.add_child(anchor)
	anchor.global_position = REACH_AT
	if world.get("interactables") != null:
		(world.interactables as Interactables).register(anchor, REACH,
			func() -> String: return tr("E   Radio: %s") % (tr(str(song(playing()).get("name", ""))) if playing() != "" else tr("mood music")),
			func() -> void: ExtrasPanel.open_for(world, "radio"))
	# Quietly catch up on songs earned before this build (no toast burst on load).
	check_unlocks()
	if playing() != "" and is_unlocked(playing()):
		Audio.set_music_override(str(song(playing()).get("mood", "")))


func _exit_tree() -> void:
	# Leaving the district (title screen, travel): the next scene sets its own music.
	Audio.set_music_override("")


func _process(delta: float) -> void:
	_t += delta
	var on: bool = playing() != ""
	if _cone:
		var beat: float = 0.5 + 0.5 * sin(_t * 9.0) if on else 0.0
		_cone.scale = Vector3.ONE * (1.0 + 0.06 * beat)
	if _dial_mat:
		_dial_mat.emission_energy_multiplier = (1.6 + 0.4 * sin(_t * 2.0)) if on else 0.7
	_check_t += delta
	if _check_t < 2.0:
		return
	_check_t = 0.0
	for id: String in check_unlocks():
		EventBus.toast.emit(tr("New song on the radio: %s") % tr(str(song(id).get("name", id))), "info")
		Audio.play("chime", 1.3, -8.0)


func _build() -> void:
	var body_mat: StandardMaterial3D = DecorProps.paint(Color(0.55, 0.32, 0.2), 0.5)
	var trim: StandardMaterial3D = DecorProps.paint(Color(0.86, 0.8, 0.66), 0.4, 0.2)
	var dark: StandardMaterial3D = DecorProps.paint(Color(0.08, 0.08, 0.08), 0.8)
	add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.24, 0.2, 0.36), 0.035, 3), body_mat, Vector3(0, 0.1, 0)))
	add_child(EggProps.mesh(ProcMesh.box(Vector3(0.012, 0.15, 0.3)), trim, Vector3(0.121, 0.1, 0)))
	# Speaker grille (front faces +X, the yard) and a cone that pulses with the music.
	_cone = Node3D.new()
	_cone.position = Vector3(0.128, 0.1, 0.07)
	add_child(_cone)
	_cone.add_child(EggProps.mesh(ProcMesh.cyl(0.062, 0.062, 0.006, 20), dark, Vector3.ZERO, Vector3(0, 0, 90)))
	_cone.add_child(EggProps.mesh(ProcMesh.cyl(0.02, 0.02, 0.008, 12), trim, Vector3(0.003, 0, 0), Vector3(0, 0, 90)))
	# Tuning dial: a warm lit strip and two knobs.
	_dial_mat = Mats.lamp(Color(1.0, 0.72, 0.38), 0.8)
	_dial = EggProps.mesh(ProcMesh.box(Vector3(0.006, 0.035, 0.1)), _dial_mat, Vector3(0.129, 0.13, -0.09))
	add_child(_dial)
	for z: float in [-0.12, -0.055]:
		add_child(EggProps.mesh(ProcMesh.cyl(0.018, 0.018, 0.02, 12), trim, Vector3(0.13, 0.055, z), Vector3(0, 0, 90)))
	# Telescopic antenna.
	add_child(EggProps.strut(Vector3(-0.05, 0.2, -0.13), Vector3(-0.14, 0.52, -0.2), 0.004, Mats.metal("chrome")))
	add_child(EggProps.mesh(ProcMesh.sphere(0.009, 8, 4), trim, Vector3(-0.14, 0.52, -0.2)))
