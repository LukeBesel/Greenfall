class_name WreckModel
extends Node3D
## An old robot of one of the six designs, half buried where it stopped working (design spec
## section 13: the six designs once worked on this planet; their wrecks are still out there).
## It is the hero model itself (player/patch_model.gd) in that design's look, so it is plainly
## the same robot family as Lumi: frozen, sunk into the ground and tipped over, its paint rusted
## and mossed, its lights dead, one arm reaching up out of the junk so it shows from far off.
##
## A wreck that can be salvaged still has one eye glowing faintly in its design's colour (the
## glint that draws the player in). Once Lumi has taken its pieces those parts are gone from the
## model and the eye is dark. A wreck that is `ruined` (a design this planet does not hand out)
## is further gone: more rust, an arm missing, no light at all. It still sits up, slumped where it
## stopped, so its head and body read as a robot at a glance and its paint says which design.
##
## Origin on the ground, +Y up. Use: var m := WreckModel.new(); m.design = "sprout";
## m.pose_seed = 7; parent.add_child(m). Later: m.strip(pieces).

const SINK_M: float = 0.34
const RUINED_SINK_M: float = 0.18
## How far a wreck is tipped back (radians, a range): on its back, face to the sky; a ruined one
## sits slumped forward instead, so its outline stays a robot's.
const LEAN := Vector2(0.42, 0.6)
const RUINED_LEAN := Vector2(-0.32, -0.18)
const EYE_ENERGY: float = 2.6
const EYE_RATE: float = 1.7
const LIGHT_RANGE_M: float = 2.2
const LIGHT_ENERGY: float = 0.55
const RUST: float = 0.72
const RUINED_RUST: float = 0.8
const COVERAGE_LOSS: float = 0.16
const RUINED_COVERAGE_LOSS: float = 0.2
## What is left of the paint once the paint set itself has been salvaged.
const BARE_COVERAGE: float = 0.1
const MOSS_MORE: float = 0.3
## Lamp materials of the hero model that are dead on a wreck.
const LAMP_KEYS: Array[String] = ["glow", "glow_soft", "glow_dim", "thruster", "thruster_core", "lamp_accent", "latch", "paddle_edge"]
const DEAD_LAMP := Color(0.07, 0.075, 0.08)

var design: String = "aurora"
var pose_seed: int = 1
var ruined: bool = false
## Pieces already taken off this wreck (ids in data/cosmetics.json).
var stripped: Array[String] = []

var _tilt: Node3D
var _model: PatchModel
var _eye_light: OmniLight3D
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if not eye_lit() or _model == null:
		return
	_t += delta
	# A tired, uneven flicker: two slow waves that seldom line up.
	var k: float = clampf(0.55 + 0.3 * sin(_t * EYE_RATE) + 0.25 * sin(_t * EYE_RATE * 2.63 + 1.1), 0.0, 1.0)
	var face: Variant = _model.get("_face_mat")
	if face is ShaderMaterial:
		(face as ShaderMaterial).set_shader_parameter("energy", EYE_ENERGY * k)
	if _eye_light:
		_eye_light.light_energy = LIGHT_ENERGY * k


## Whether the wreck's one eye still glows (it has something left to give).
func eye_lit() -> bool:
	return not ruined and stripped.is_empty()


## The design's glow colour (the eye, the glint).
func glow() -> Color:
	return PatchModel.glow_of(design)


## Where the eye is, in the world (the glint's spot).
func eye_point() -> Vector3:
	return _model.to_global(_model.lens_point) if _model else global_position


## The hero model inside (tests, tools).
func model() -> PatchModel:
	return _model


## Lumi has salvaged these pieces: they come off the model and the eye goes dark.
func strip(pieces: Array[String]) -> void:
	for p: String in pieces:
		if not (p in stripped):
			stripped.append(p)
	if is_inside_tree():
		_build()


## The look the wreck shows: its design's own, less the held item (long lost) and every piece
## already taken.
func style() -> Dictionary:
	var s: Dictionary = LumiStyle.preset(design)
	_clear_slot(s, "held")
	for piece: String in stripped:
		var d: Dictionary = Looks.def(piece)
		if d.has("option"):
			_clear_slot(s, str(d["slot"]))
	return s


func _clear_slot(s: Dictionary, slot: String) -> void:
	var opts: Array = LumiStyle.options(slot)
	if not opts.is_empty():
		LumiStyle.set_value(s, slot, str((opts[0] as Dictionary)["id"]))


func _paint_taken() -> bool:
	for piece: String in stripped:
		if Looks.slot_of(piece) == LumiStyle.PAINT:
			return true
	return false


func _moss_taken() -> bool:
	for piece: String in stripped:
		if Looks.slot_of(piece) == "pattern":
			return true
	return false


func _build() -> void:
	if _tilt:
		remove_child(_tilt)
		_tilt.queue_free()
	_rng.seed = hash("wreck/%s/%d" % [design, pose_seed])
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	add_child(_tilt)
	var lean_range: Vector2 = RUINED_LEAN if ruined else LEAN
	var lean: float = _rng.randf_range(lean_range.x, lean_range.y)
	var side: float = _rng.randf_range(-0.28, 0.28)
	_tilt.position = Vector3(0, -(RUINED_SINK_M if ruined else SINK_M), 0)
	_tilt.rotation = Vector3(lean, _rng.randf_range(-0.5, 0.5), side)  # tipped back (face to the sky) or slumped forward
	_model = PatchModel.new()
	_model.name = "Robot"
	_model.preview_variant = design
	_model.set_meta("lumi_style", style())
	_tilt.add_child(_model)  # builds in _ready
	_model.process_mode = Node.PROCESS_MODE_DISABLED  # a wreck does not hover, blink or look around
	_freeze_pose()
	_kill_lights()
	_weather()
	_eye_light = null
	if eye_lit():
		_eye_light = OmniLight3D.new()
		_eye_light.name = "EyeGlow"
		_eye_light.light_color = glow()
		_eye_light.light_energy = LIGHT_ENERGY
		_eye_light.omni_range = LIGHT_RANGE_M
		_eye_light.shadow_enabled = false
		_model.add_child(_eye_light)
		_eye_light.position = _model.lens_point + Vector3(0, 0, -0.18)
	set_process(eye_lit())


## One arm thrown up out of the ground, the head lolling, the claws slack.
func _freeze_pose() -> void:
	var head: Variant = _model.get("_head")
	if head is Node3D:
		(head as Node3D).rotation = Vector3(0.0, _rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.2, 0.2))
	var arm_r: Variant = _model.get("_arm_r")
	var arm_l: Variant = _model.get("_arm_l")
	if arm_r is Node3D:
		(arm_r as Node3D).rotation = Vector3(-2.35, 0.0, 0.5)
		_bend(arm_r as Node3D, 0.35)
	if arm_l is Node3D:
		(arm_l as Node3D).rotation = Vector3(0.5, 0.0, -0.25)
		_bend(arm_l as Node3D, 0.9)
		(arm_l as Node3D).visible = not ruined  # torn off long ago
	var face: Variant = _model.get("_face_mat")
	if face is ShaderMaterial:
		var fm: ShaderMaterial = face
		fm.set_shader_parameter("happy", 0.0)
		fm.set_shader_parameter("look", Vector2.ZERO)
		# One eye open and faint while there is something to salvage; both shut after.
		fm.set_shader_parameter("blink", 0.0 if eye_lit() else 1.0)
		fm.set_shader_parameter("wink", 1.0 if eye_lit() else 0.0)
		fm.set_shader_parameter("energy", EYE_ENERGY if eye_lit() else 0.0)
	for n: Node in _model.find_children("*", "Label3D", true, false):
		(n as Label3D).visible = false


func _bend(shoulder: Node3D, elbow_x: float) -> void:
	var elbow: Variant = shoulder.get_meta("elbow") if shoulder.has_meta("elbow") else null
	if elbow is Node3D:
		(elbow as Node3D).rotation.x = elbow_x


## No hover light, no key lights, no lit strips: the wreck is lit by the sun like any junk.
func _kill_lights() -> void:
	for n: Node in _model.find_children("*", "OmniLight3D", true, false):
		n.get_parent().remove_child(n)
		n.queue_free()
	var mats: Variant = _model.get("_mats")
	if mats is Dictionary:
		for key: String in LAMP_KEYS:
			var m: Variant = (mats as Dictionary).get(key)
			if m is StandardMaterial3D:
				(m as StandardMaterial3D).emission_enabled = false
				(m as StandardMaterial3D).albedo_color = DEAD_LAMP
				(m as StandardMaterial3D).roughness = 0.6
	for n: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		mi.layers = 1  # off the hero's own light layer
		var om: Material = mi.material_override
		if om is StandardMaterial3D and (om as StandardMaterial3D).emission_enabled:  # fill bar, lit icon
			mi.visible = false


## Years outdoors: rust through the paint, grime, moss. The colour stays: a wreck is found by
## its paint.
func _weather() -> void:
	var mats: Variant = _model.get("_paint_mats")
	if not (mats is Array):
		return
	var all: Array = (mats as Array).duplicate()
	var add_ons: Variant = _model.get("_acc_mats")  # the add-ons' own copies of the paint
	if add_ons is Dictionary:
		all.append_array((add_ons as Dictionary).values())
	var bare: bool = _paint_taken()
	for v: Variant in all:
		if not (v is ShaderMaterial):
			continue
		var m: ShaderMaterial = v
		var cover: float = float(m.get_shader_parameter("paint_coverage"))
		m.set_shader_parameter("paint_coverage", BARE_COVERAGE if bare else maxf(0.3, cover - (RUINED_COVERAGE_LOSS if ruined else COVERAGE_LOSS)))
		m.set_shader_parameter("rust_amount", RUINED_RUST if ruined else RUST)
		m.set_shader_parameter("edge_wear", 0.9)
		m.set_shader_parameter("grime", 0.85)
		m.set_shader_parameter("clearcoat", 0.0)
		var moss: float = float(m.get_shader_parameter("moss"))
		m.set_shader_parameter("moss", 0.0 if _moss_taken() else minf(1.0, moss + MOSS_MORE))
