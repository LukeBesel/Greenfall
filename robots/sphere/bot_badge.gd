class_name BotBadge
extends Node3D
## [v6crew] The small state light over a globe robot, so you can read a crew at a glance:
## a lamp in the robot's role colour (the Command view's legend colours) that pulses while it
## works, glows steady while it carries or travels, turns grey with a "z" when it has nothing to
## do and amber with a "!" when it needs the player (out of seeds, zone done, bales piling up).
## A new robot's lamp flashes white while it says hello. Drips spray water while they water.
## Hidden past FAR_M so hundreds of robots stay cheap.
## Rank: a robot's Mk tier shows as small gold diamonds circling the lamp (Mk II two, Mk III
## three, Mk IV four; Mk I none), on top of the tier's own model look, so growth reads from afar.

const FAR_M: float = 70.0
const GREY := Color(0.62, 0.63, 0.66)
const AMBER := Color(1.0, 0.62, 0.12)
const ROLE_COL: Dictionary = {
	"clean": Color(1.0, 0.72, 0.3), "haul": Color(0.45, 0.72, 1.0), "plant": Color(0.55, 0.9, 0.5),
	"water": Color(0.4, 0.9, 0.95), "skim": Color(0.35, 0.85, 0.75),
}

var state: int = -1
var role: String = "clean"
var _lamp: MeshInstance3D
var _mat: StandardMaterial3D
var _glyph: Label3D
var _spray: CPUParticles3D
var _t: float = 0.0
var tier: int = 0
var _ranks: Node3D
static var _mesh: SphereMesh
static var _pip_mesh: SphereMesh
static var _pip_mat: StandardMaterial3D
const RANK_R: float = 0.17
const RANK_SPIN: float = 1.1  # rad/s


static func role_color(p_role: String) -> Color:
	return ROLE_COL.get(p_role, ROLE_COL["clean"])


## Lamp colour and glyph for a state (CrewTalk's enum): [colour, glyph, pulse Hz].
static func look(p_state: int, p_role: String) -> Array:
	var c: Color = role_color(p_role)
	match p_state:
		CrewTalk.WORK:
			return [c, "", 2.2]
		CrewTalk.CARRY:
			return [c, "", 0.0]
		CrewTalk.MOVE:
			return [c.darkened(0.35), "", 0.0]
		CrewTalk.HELP:
			return [AMBER, "!", 1.2]
		CrewTalk.HELLO:
			return [Color(1, 1, 1), "", 5.0]
	return [GREY, "z", 0.0]


## Height of the top of a robot's model above its origin (the lamp sits just over it).
static func top_of(root: Node3D) -> float:
	var top: float = 0.0
	if root == null:
		return 0.9
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var xf: Transform3D = Transform3D.IDENTITY
		var cur: Node3D = mi
		while cur != null and cur != root:
			xf = cur.transform * xf
			cur = cur.get_parent() as Node3D
		var bb: AABB = xf * mi.mesh.get_aabb()
		if bb.size.y < 2.5:  # beams and tractor fields are not the body
			top = maxf(top, bb.end.y)
	return clampf(top, 0.5, 2.2) if top > 0.0 else 0.9


## Pips shown for a tier index (0 = Mk I).
static func pips_for(p_tier: int) -> int:
	return 0 if p_tier <= 0 else p_tier + 1


func setup(p_role: String, height: float = 1.2, p_tier: int = 0) -> void:
	role = p_role
	position = Vector3(0, height, 0)
	if _mesh == null:
		_mesh = SphereMesh.new()
		_mesh.radius = 0.085
		_mesh.height = 0.17
		_mesh.radial_segments = 10
		_mesh.rings = 5
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp = MeshInstance3D.new()
	_lamp.mesh = _mesh
	_lamp.material_override = _mat
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp.visibility_range_end = FAR_M
	add_child(_lamp)
	_glyph = Label3D.new()
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.font_size = 96
	_glyph.pixel_size = 0.0045
	_glyph.outline_size = 24
	_glyph.outline_modulate = Color(0.05, 0.05, 0.06, 0.9)
	_glyph.position = Vector3(0, 0.3, 0)
	_glyph.visibility_range_end = FAR_M * 0.6
	_glyph.visible = false
	add_child(_glyph)
	set_state(CrewTalk.IDLE)
	set_tier(p_tier)


## [v6crew] The rank pips for a Mk tier (rebuilt on an upgrade).
func set_tier(p_tier: int) -> void:
	tier = p_tier
	if _ranks != null:
		remove_child(_ranks)
		_ranks.queue_free()
		_ranks = null
	var n: int = pips_for(tier)
	if n == 0:
		return
	if _pip_mesh == null:
		_pip_mesh = SphereMesh.new()  # 4 segments, 2 rings: a little diamond
		_pip_mesh.radius = 0.04
		_pip_mesh.height = 0.1
		_pip_mesh.radial_segments = 4
		_pip_mesh.rings = 2
		_pip_mat = StandardMaterial3D.new()
		_pip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pip_mat.albedo_color = UITheme.GOLD
	_ranks = Node3D.new()
	_ranks.name = "Ranks"
	add_child(_ranks)
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		var mi := MeshInstance3D.new()
		mi.mesh = _pip_mesh
		mi.material_override = _pip_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = FAR_M
		mi.position = Vector3(cos(a) * RANK_R, -0.02, sin(a) * RANK_R)
		_ranks.add_child(mi)


func set_state(p_state: int) -> void:
	if p_state == state:
		return
	state = p_state
	var lk: Array = look(state, role)
	_mat.albedo_color = lk[0]
	_glyph.text = str(lk[1])
	_glyph.modulate = lk[0]
	_glyph.visible = str(lk[1]) != ""
	_lamp.scale = Vector3.ONE


## Water spray at `at` (local to the robot) while `on`: a Drip watering.
func set_spray(on: bool, at: Vector3 = Vector3.ZERO) -> void:
	if not on and _spray == null:
		return
	if _spray == null:
		_spray = CPUParticles3D.new()
		_spray.amount = 18
		_spray.lifetime = 0.55
		_spray.direction = Vector3(0, 0.25, -1)
		_spray.spread = 22.0
		_spray.initial_velocity_min = 1.6
		_spray.initial_velocity_max = 2.4
		_spray.gravity = Vector3(0, -6.0, 0)
		var m := SphereMesh.new()
		m.radius = 0.035
		m.height = 0.07
		m.radial_segments = 6
		m.rings = 3
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(0.55, 0.88, 1.0)
		m.material = mm
		_spray.mesh = m
		_spray.visibility_range_end = FAR_M
		add_child(_spray)
	_spray.position = at - position
	_spray.emitting = on


func _process(delta: float) -> void:
	_t += delta
	var hz: float = float(look(state, role)[2])
	if hz > 0.0:
		var k: float = 0.5 + 0.5 * sin(_t * TAU * hz)
		_lamp.scale = Vector3.ONE * lerpf(0.75, 1.3, k)
		if state == CrewTalk.HELLO:
			_mat.albedo_color = Color(1, 1, 1).lerp(role_color(role), k)
	if _glyph.visible:
		_glyph.position.y = 0.3 + 0.04 * sin(_t * 2.0)
	if _ranks != null:
		_ranks.rotation.y = _t * RANK_SPIN
