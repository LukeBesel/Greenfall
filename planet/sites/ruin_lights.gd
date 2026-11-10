class_name RuinLights
extends Node3D
## A ruined town's last lights. A share of its street lamp heads still glow after dark on their
## dying emergency cells: warm, a little unsteady, so dusk and night keep pools of colour before any
## street power is repaired. StreetPower still owns the real, steady street light and its repair
## moment; these never replace it and are off by day.
## Cost is capped: every glowing head is one instance of a single MultiMesh, and only the few
## nearest the camera carry a real light (`max_lights`, moved as the camera moves, no shadows).
## Nothing is saved: the picks come from the seed.

const POLL_S: float = 0.4
const LIGHT_RANGE_M: float = 18.0
const LIGHT_ENERGY: float = 6.0
const LIGHT_DROP_M: float = 1.2  # under the head, so the post does not swallow the light
const BULB_SCALE: float = 2.4
const WARM := Color(1.0, 0.72, 0.4)

var max_lights: int = 6
var _points: PackedVector3Array = PackedVector3Array()
var _lights: Array[OmniLight3D] = []
var _mat: ShaderMaterial
var _bulbs: MultiMeshInstance3D
var _poll: float = 0.0
var _dark: float = -1.0


## heads: [Transform3D, Color] per lamp head in this node's parent frame (CityView.lamp_bulbs).
## share: 0..1 of them that stay alive. Returns how many do.
func setup(heads: Array, share: float, seed_v: int, p_max_lights: int) -> int:
	max_lights = maxi(0, p_max_lights)
	var xfs: Array[Transform3D] = []
	for i: int in heads.size():
		if float(hash([seed_v, i, 5519]) & 0xFFFF) / 65535.0 >= share:
			continue
		var xf: Transform3D = (heads[i] as Array)[0]
		xfs.append(Transform3D(xf.basis.scaled(Vector3.ONE * BULB_SCALE), xf.origin))
		_points.append(xf.origin)
	if xfs.is_empty():
		return 0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ProcMesh.sphere(0.055, 10, 6)
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, WARM)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/neon.gdshader")
	_mat.set_shader_parameter("energy", 3.5)
	_mat.set_shader_parameter("twinkle", 1.0)
	_mat.set_shader_parameter("instance_seed", true)
	_mat.set_shader_parameter("power", 0.0)
	_bulbs = MultiMeshInstance3D.new()
	_bulbs.name = "Heads"
	_bulbs.multimesh = mm
	_bulbs.material_override = _mat
	_bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bulbs.visibility_range_end = 220.0
	_bulbs.visible = false
	add_child(_bulbs)
	for k: int in mini(max_lights, _points.size()):
		var l := OmniLight3D.new()
		l.name = "Pool%d" % k
		l.light_color = WARM
		l.omni_range = LIGHT_RANGE_M
		l.omni_attenuation = 1.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	return _points.size()


func light_count() -> int:
	return _lights.size()


func alive_count() -> int:
	return _points.size()


## How dark it is at the player, 0 (day) .. 1 (night), from the local time the sky publishes.
static func darkness(time_of_day: float) -> float:
	var sun: float = cos((time_of_day - 0.5) * TAU)  # 1 at noon, 0 at dawn and dusk, -1 at midnight
	return 1.0 - smoothstep(-0.08, 0.22, sun)


func _process(delta: float) -> void:
	if _bulbs == null:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_S
	apply(darkness(float(GameState.flags.get("time_of_day", 0.5))), _camera_local())


## Sets the glow for a darkness and puts the real lights on the heads nearest `eye` (local).
func apply(dark: float, eye: Vector3) -> void:
	if _bulbs == null:
		return
	if not is_equal_approx(dark, _dark):
		_dark = dark
		_mat.set_shader_parameter("power", dark)
		_bulbs.visible = dark > 0.02
	var on: bool = dark > 0.02
	if not on:
		for l: OmniLight3D in _lights:
			l.visible = false
		return
	var order: Array[int] = []
	for i: int in _points.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return _points[a].distance_squared_to(eye) < _points[b].distance_squared_to(eye))
	for k: int in _lights.size():
		var l: OmniLight3D = _lights[k]
		l.position = _points[order[k]] - Vector3(0.0, LIGHT_DROP_M, 0.0)
		l.light_energy = LIGHT_ENERGY * dark
		l.visible = true


func _camera_local() -> Vector3:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null or not is_inside_tree():
		return Vector3.ZERO
	return global_transform.affine_inverse() * cam.global_position
