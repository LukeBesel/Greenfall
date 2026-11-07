class_name RobotPersona
extends Node3D
## [drones] A robot's personality in the world: a small name tag (name + trait) that shows when
## Lumi is near, trait idle animations while parked (look-around, spin, hops, dozing, dust
## shake, head tilt, humming sway), a little lean while driving, and beeps in the trait's voice
## (only from robots near Lumi, quieter with distance). Motion goes through the RobotKit's
## anim_dy / anim_rot so it adds to the part lift instead of fighting RobotVisual.animate().

const NODE_NAME: String = "Persona"
const TAG_Y: float = 1.34
const HEAR_M: float = 9.0

var robot: Robot
var trait_id: String = ""
var _def: Dictionary = {}
var _tag: Label3D
var _emote: Label3D
var _emote_t: float = -1.0
var _t: float = 0.0
var _beep_t: float = 0.0
var _act_t: float = 0.0
var _greet_t: float = 0.0
var _modal: bool = false
var _seed: float = 0.0


static func ensure(r: Robot) -> RobotPersona:
	var p: RobotPersona = r.get_node_or_null(NODE_NAME) as RobotPersona
	if p == null:
		p = RobotPersona.new()
		p.name = NODE_NAME
		p.robot = r
		r.add_child(p)
	p.refresh()
	return p


func _ready() -> void:
	_seed = randf() * 10.0
	_beep_t = randf_range(2.0, 8.0)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.font_size = 30
	_tag.outline_size = 8
	_tag.pixel_size = 0.0027
	_tag.modulate = Color(0.95, 0.95, 0.92, 0.92)
	_tag.outline_modulate = Color(0.02, 0.03, 0.04, 0.75)
	_tag.position = Vector3(0, TAG_Y, 0)
	_tag.visibility_range_end = 11.0
	_tag.visibility_range_end_margin = 2.0
	_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tag.font = UITheme.font()
	add_child(_tag)
	_emote = Label3D.new()
	_emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_emote.font_size = 44
	_emote.outline_size = 8
	_emote.pixel_size = 0.004
	_emote.visible = false
	_emote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_emote)
	EventBus.ui_modal_changed.connect(_on_modal)
	refresh()


func _on_modal(open: bool) -> void:
	_modal = open


func refresh() -> void:
	if robot == null:
		return
	trait_id = RobotBuilder.trait_of(robot)
	_def = RobotBuilder.trait_def(trait_id)
	if _tag:
		_tag.text = "%s\n%s" % [robot.robot_name, str(_def.get("name", "")).to_upper()]
		_tag.position.y = TAG_Y + (0.12 if robot.tier >= 3 else 0.0) + (0.16 if robot.build.has("topper") else 0.0) + (0.15 if str(robot.build.get("head", "")) == "periscope" else 0.0)


func _kit() -> RobotKit:
	return RobotKit.of(robot.visual) if robot and robot.visual else null


func _patch_dist() -> float:
	var w: Node = robot.world
	var p: Node3D = w.get("patch") if w else null
	return robot.global_position.distance_to(p.global_position) if p else INF


func _process(delta: float) -> void:
	if robot == null or robot.visual == null:
		return
	_t += delta
	var k: RobotKit = _kit()
	if k == null:
		return
	var idle: bool = robot.visual.idle
	var spd: float = Vector3(robot.velocity.x, 0, robot.velocity.z).length()
	var dy: float = 0.0
	var rot := Vector3.ZERO
	if idle:
		_act_t += delta
		match str(_def.get("idle", "")):
			"look":
				# Slow, wide look left and right with pauses.
				rot.y = sin(_act_t * 0.9 + _seed) * 0.55 * clampf(absf(sin(_act_t * 0.31)) * 2.0, 0.0, 1.0)
			"spin":
				var ph: float = fmod(_act_t + _seed, 6.0)
				if ph < 0.9:
					rot.y = ease(ph / 0.9, -2.2) * TAU
			"hop":
				var ph2: float = fmod(_act_t * 1.4 + _seed, 3.2)
				if ph2 < 0.9:
					dy = absf(sin(ph2 / 0.3 * PI)) * 0.06
			"doze":
				var d: float = clampf(_act_t / 3.0, 0.0, 1.0)
				dy = -0.035 * d + sin(_act_t * 1.2) * 0.008 * d
				rot.x = 0.1 * d
				if d >= 1.0 and fmod(_act_t, 4.0) < delta:
					_show_emote("z", Color(0.75, 0.85, 1.0))
			"shake":
				var ph3: float = fmod(_act_t + _seed, 5.0)
				if ph3 < 0.6:
					rot.z = sin(ph3 * 50.0) * 0.06 * (1.0 - ph3 / 0.6)
					if ph3 < delta:
						Vfx.burst("dust", robot.global_position + Vector3(0, 0.3, 0), Color(0.8, 0.75, 0.65), 0.35)
			"tilt":
				rot.z = sin(_act_t * 0.7 + _seed) * 0.16
				if fmod(_act_t + _seed, 7.0) < delta:
					_show_emote("?", Color(1.0, 0.85, 0.4))
			"sway":
				rot.z = sin(_act_t * 2.2) * 0.07
				dy = absf(sin(_act_t * 2.2)) * 0.015
				if fmod(_act_t + _seed, 6.0) < delta:
					_show_emote("~", Color(0.6, 1.0, 0.8))
	else:
		_act_t = 0.0
		# Driving flavour: speedy units lean into it, cautious ones creep and glance around.
		match trait_id:
			"speedy":
				rot.x = -clampf(spd * 0.04, 0.0, 0.09)
			"cautious":
				rot.y = sin(_t * 0.8 + _seed) * 0.12 * clampf(spd, 0.0, 1.0)
	k.anim_dy = dy
	k.anim_rot = rot
	_tick_emote(delta)
	_tick_beep(delta, idle)


func _tick_beep(delta: float, idle: bool) -> void:
	if _modal or get_tree().paused:
		return
	_beep_t -= delta
	_greet_t -= delta
	var dist: float = _patch_dist()
	if trait_id == "chatty" and dist < 3.0 and _greet_t <= 0.0:
		_greet_t = 25.0
		_beep(dist, 2)
		_show_emote("!", Color(1.0, 0.75, 0.3))
		return
	if _beep_t > 0.0:
		return
	var every: float = float(_def.get("every", 10.0))
	_beep_t = every * randf_range(0.7, 1.4) * (0.7 if idle else 1.3)
	if dist < HEAR_M:
		_beep(dist, 1 if trait_id != "chatty" else 2)


func _beep(dist: float, n: int) -> void:
	var snd: String = str(_def.get("beep", "blip"))
	var pitch: float = float(_def.get("pitch", 1.0)) * randf_range(0.92, 1.1)
	var vol: float = -16.0 - dist * 1.3
	Audio.play(snd, pitch, vol)
	if n > 1:
		get_tree().create_timer(0.14).timeout.connect(func() -> void: Audio.play(snd, pitch * 1.18, vol - 1.0))


func _show_emote(text: String, col: Color) -> void:
	if _emote == null or _patch_dist() > HEAR_M:
		return
	_emote.text = text
	_emote.modulate = col
	_emote.visible = true
	_emote_t = 0.0


func _tick_emote(delta: float) -> void:
	if _emote_t < 0.0:
		return
	_emote_t += delta
	var f: float = _emote_t / 1.6
	_emote.position = Vector3(0.25, TAG_Y - 0.2 + f * 0.35, 0)
	_emote.modulate.a = clampf(1.0 - f, 0.0, 1.0)
	if f >= 1.0:
		_emote.visible = false
		_emote_t = -1.0
