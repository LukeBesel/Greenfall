class_name Radio
extends Node3D
## [extras] The base radio: a little valve radio on the workbench that plays the score's composed
## planet tracks (audio/music_tracks.gd via Audio.play_track; a restored planet plays the track's
## restored variant). Songs unlock as districts and planets are restored (data/radio.json), with a
## small toast. Picking a song loops it with no gaps until "Back to mood music" (Audio.stop_track).
## State: GameState.flags.radio = {unlocked: [track ids], song: "" (playing), planets: {theme id:
## best base level seen there}}. Pure rules are
## static (tests, the save round trip); the live node is the prop, its interactable and the
## unlock check.

const PATH: String = "res://data/radio.json"
## [camp] Built from the Hub tab (systems/camp/yard_builds.gd) and placed by the fence, well away
## from the workbench (they used to share the E prompt). Position: data/camp.json builds.radio.
const POS := Vector3(6.6, 0.0, 3.4)
const REACH: float = 1.6

static var _cfg: Dictionary = {}

var world: Node
var _cone: Node3D
var _set: Node3D  # [camp] the radio itself, on its crate
var _cone2: Node3D  # [camp] the CD player's right speaker
var _anchor: Node3D  # [camp]
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


## Display title of a song (English; tr() it where shown).
static func title(id: String) -> String:
	var t: String = Audio.music_track_title(id) if Audio.has_method("music_track_title") else ""
	return t if t != "" else id


static func planets() -> Dictionary:
	if not (st().get("planets") is Dictionary):
		st()["planets"] = {}
	var p: Dictionary = st()["planets"]
	for k: Variant in p:  # JSON loads ints back as floats
		p[k] = int(p[k])
	return p


## Notes the planet whose music is playing and the best base level reached there.
static func note_planet(theme: String, hub_level: int) -> void:
	if theme == "":
		return
	planets()[theme] = maxi(int(planets().get(theme, 0)), hub_level)


static func cond_value(c: Dictionary) -> float:
	match str(c.get("type", "")):
		"planet_seen":
			return 1.0 if planets().has(str(c.get("key", ""))) else 0.0
		"planet_level":
			return float(planets().get(str(c.get("key", "")), 0))
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
	if id != "":
		Audio.play_track(id)
	else:
		Audio.stop_track()
	if id != "":
		GameState.inc_stat("radio_plays")
	return true


# --- Live node --------------------------------------------------------------------------

func setup(p_world: Node) -> void:
	world = p_world
	name = "Radio"
	_build()
	position = YardBuilds.pos("radio", POS)
	rotation.y = deg_to_rad(float(YardBuilds.def("radio").get("yaw_deg", 180.0)))
	var anchor := Node3D.new()
	anchor.name = "RadioReach"
	world.add_child(anchor)
	anchor.global_position = position + Basis(Vector3.UP, rotation.y) * Vector3(1.0, 0, 0)  # in front of it
	_anchor = anchor
	if world.get("interactables") != null:
		(world.interactables as Interactables).register(anchor, REACH,
			func() -> String: return tr("E   CD player: %s") % (tr(title(playing())) if playing() != "" else tr("mood music")),  # [camp] owner: it is a CD player
			func() -> void: ExtrasPanel.open_for(world, "radio"),
			func() -> bool: return visible)  # [camp] only once it's built
	set_built(YardBuilds.built("radio"), false)  # [camp]
	# Quietly catch up on songs earned before this build (no toast burst on load).
	_note_here()
	check_unlocks()
	if playing() != "" and is_unlocked(playing()):
		Audio.play_track(playing())


## [camp] Shows the radio once it's built (live: it drops onto its crate with a puff).
func set_built(on: bool, animate: bool) -> void:
	visible = on
	if _anchor:
		_anchor.visible = on
	if not on or not animate:
		return
	position.y = 1.4
	create_tween().tween_property(self, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	Vfx.burst("dust", position, Color(0.7, 0.65, 0.6, 0.6), 1.0)
	Audio.play("clunk", 1.1, -6.0)


func _exit_tree() -> void:
	# Leaving the district (title screen, travel): the next scene sets its own music.
	Audio.stop_track()


func _process(delta: float) -> void:
	_t += delta
	var on: bool = playing() != ""
	if _cone:
		var beat: float = 0.5 + 0.5 * sin(_t * 9.0) if on else 0.0
		_cone.scale = Vector3.ONE * (1.0 + 0.06 * beat)
		if _cone2:  # [camp]
			_cone2.scale = _cone.scale
	if _dial_mat:
		_dial_mat.emission_energy_multiplier = (1.6 + 0.4 * sin(_t * 2.0)) if on else 0.7
	_check_t += delta
	if _check_t < 2.0:
		return
	_check_t = 0.0
	_note_here()
	for id: String in check_unlocks():
		EventBus.toast.emit(tr("New song on the radio: %s") % tr(title(id)), "info")
		Audio.play("chime", 1.3, -8.0)


func _note_here() -> void:
	var hb: Variant = world.get("hub") if world else null
	note_planet(Audio.get_planet_theme(), (hb as Hub).level if hb is Hub else int(GameState.world.get("hub_level", 1)))


func _build() -> void:
	# [camp] Its own spot by the fence: a wooden crate with the radio on top (scaled up a little so
	# it reads from the camera), facing into the yard.
	var wood: StandardMaterial3D = DecorProps.wood()
	add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.62, 0.7, 0.8), 0.03, 2), wood, Vector3(0, 0.35, 0)))
	for z: float in [-0.2, 0.2]:
		add_child(EggProps.mesh(ProcMesh.box(Vector3(0.64, 0.05, 0.05)), DecorProps.paint(Color(0.3, 0.22, 0.15), 0.7), Vector3(0, 0.5, z)))
	_set = Node3D.new()
	_set.position = Vector3(0, 0.7, 0)
	add_child(_set)
	# [camp] The CD player (owner): a chunky retro boombox. Front faces +X (the yard): two big
	# speakers, a CD tray in the middle with a disc behind smoked plastic, a lit display strip,
	# a row of chunky keys on top and a chrome carry handle.
	var shell: StandardMaterial3D = DecorProps.paint(Color(0.16, 0.17, 0.19), 0.45, 0.1)
	var face: StandardMaterial3D = DecorProps.paint(Color(0.68, 0.7, 0.72), 0.35, 0.6)
	var trim: StandardMaterial3D = DecorProps.paint(Color(0.86, 0.8, 0.66), 0.4, 0.2)
	var dark: StandardMaterial3D = DecorProps.paint(Color(0.05, 0.05, 0.06), 0.8)
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	var w: float = 0.78
	var h: float = 0.38
	var d: float = 0.26
	_set.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(d, h, w), 0.05, 3), shell, Vector3(0, h * 0.5, 0)))
	_set.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.012, h * 0.84, w * 0.94)), face, Vector3(d * 0.5 + 0.004, h * 0.5, 0)))
	# Speakers: dark cones in chrome rings, one each side; the left one pulses with the music.
	_cone = Node3D.new()
	_cone.position = Vector3(d * 0.5 + 0.012, h * 0.47, -w * 0.31)
	_set.add_child(_cone)
	_cone2 = Node3D.new()
	_cone2.position = Vector3(d * 0.5 + 0.012, h * 0.47, w * 0.31)
	_set.add_child(_cone2)
	for c: Node3D in [_cone, _cone2]:
		c.add_child(EggProps.mesh(ProcMesh.torus(0.118, 0.13, 24, 6), chrome, Vector3.ZERO, Vector3(0, 0, 90)))
		c.add_child(EggProps.mesh(ProcMesh.cyl(0.118, 0.118, 0.008, 24), dark, Vector3.ZERO, Vector3(0, 0, 90)))
		c.add_child(EggProps.mesh(ProcMesh.cyl(0.035, 0.035, 0.012, 14), trim, Vector3(0.004, 0, 0), Vector3(0, 0, 90)))
	# CD tray in the middle: a smoked window with a disc behind it, and an eject key.
	var smoke := StandardMaterial3D.new()
	smoke.albedo_color = Color(0.1, 0.12, 0.14, 0.55)
	smoke.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke.roughness = 0.1
	smoke.metallic = 0.3
	var disc: StandardMaterial3D = Mats.metal("chrome")
	_set.add_child(EggProps.mesh(ProcMesh.cyl(0.07, 0.07, 0.004, 28), disc, Vector3(d * 0.5 + 0.006, h * 0.55, 0), Vector3(0, 0, 90)))
	_set.add_child(EggProps.mesh(ProcMesh.cyl(0.012, 0.012, 0.006, 12), dark, Vector3(d * 0.5 + 0.008, h * 0.55, 0), Vector3(0, 0, 90)))
	_set.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.01, 0.17, 0.17)), smoke, Vector3(d * 0.5 + 0.014, h * 0.55, 0)))
	# Display strip under the tray (glows while a song plays) and the tape-deck-style keys on top.
	_dial_mat = Mats.lamp(Color(0.45, 0.95, 1.0), 0.8)
	_dial = EggProps.mesh(ProcMesh.box(Vector3(0.006, 0.035, 0.16)), _dial_mat, Vector3(d * 0.5 + 0.012, h * 0.2, 0))
	_set.add_child(_dial)
	for k: int in 5:
		_set.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.06, 0.03, 0.06), 0.008, 2), trim if k != 2 else DecorProps.paint(Color(0.85, 0.25, 0.2), 0.4), Vector3(0.02, h + 0.012, -0.16 + k * 0.08)))
	# Carry handle: chrome bar on two posts.
	for z: float in [-w * 0.42, w * 0.42]:
		_set.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.04, 0.1, 0.04)), shell, Vector3(-0.04, h + 0.05, z)))
	_set.add_child(EggProps.strut(Vector3(-0.04, h + 0.1, -w * 0.42), Vector3(-0.04, h + 0.1, w * 0.42), 0.014, chrome))
