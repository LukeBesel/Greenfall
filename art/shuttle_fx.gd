class_name ShuttleFx
extends Node3D
## [art5] What the shuttle's lift engines do to the ground on a launch and a landing
## (planet/sites/hub_hop.gd drives it): a skirt of dust and spray blown outward along the ground,
## grit thrown up, the engines' light washing over the pad, a puff on touchdown and a scorch
## left on the pad that fades over SCORCH_S seconds.
## The planet is a sphere: everything is laid out on the LOCAL up the hop passes in (the pad's
## normal), never world Y. Everything is built once and reused (pooled emitters, two scorch quads);
## a frame only sets transforms and a few numbers, so nothing allocates while the ship flies.

const SCORCH_S: float = 80.0
const SCORCH_IN_S: float = 1.0
## The skirt and the wash only show this close to the ground (m).
const NEAR_M: float = 13.0
const SCORCH_SHADER := preload("res://art/shaders/shuttle_scorch.gdshader")

var _dust: CPUParticles3D
var _grit: CPUParticles3D
var _puff: CPUParticles3D
var _wash: MeshInstance3D
var _wash_mat: StandardMaterial3D
var _light: OmniLight3D
var _scorch: Array[MeshInstance3D] = []
var _scorch_t: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _scorch_k: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _scorch_age: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _next: int = 0
var _strength: float = 0.0
var _live: float = 0.0
var _dust_col: Color = Color(0.82, 0.78, 0.72, 0.95)
var _glow: Color = Color(0.5, 0.9, 1.0)


func _ready() -> void:
	name = "ShuttleFx"
	var soft: GradientTexture2D = _radial(Color(1, 1, 1, 1), 0.3)
	# The skirt: big soft billboards born in a ring under the engines and driven outward along the ground.
	_dust = _emitter(120, 1.5, _billboard(soft, false, 1.7))
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_radius = 2.2
	_dust.emission_ring_inner_radius = 0.9
	_dust.emission_ring_height = 0.1
	_dust.direction = Vector3.UP
	_dust.spread = 25.0
	_dust.initial_velocity_min = 0.2
	_dust.initial_velocity_max = 0.9
	_dust.radial_accel_min = 9.0
	_dust.radial_accel_max = 17.0
	_dust.damping_min = 3.0
	_dust.damping_max = 4.5
	_dust.scale_amount_min = 0.9
	_dust.scale_amount_max = 1.8
	_dust.scale_amount_curve = _curve([0.0, 0.35, 0.3, 1.0, 1.0, 1.9])
	_dust.color_ramp = _ramp([0.0, 0.0, 0.1, 0.8, 0.5, 0.45, 1.0, 0.0])
	_dust.angle_min = 0.0
	_dust.angle_max = 360.0
	# Grit: small dark bits kicked up and falling back.
	var bit := BoxMesh.new()
	bit.size = Vector3(0.05, 0.03, 0.04)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.12, 0.11, 0.1)
	bm.roughness = 0.9
	bit.material = bm
	_grit = _emitter(26, 0.9, bit)
	_grit.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_grit.emission_ring_axis = Vector3.UP
	_grit.emission_ring_radius = 2.4
	_grit.emission_ring_inner_radius = 1.2
	_grit.emission_ring_height = 0.05
	_grit.direction = Vector3.UP
	_grit.spread = 50.0
	_grit.initial_velocity_min = 1.5
	_grit.initial_velocity_max = 4.5
	_grit.radial_accel_min = 6.0
	_grit.radial_accel_max = 16.0
	_grit.angular_velocity_min = -400.0
	_grit.angular_velocity_max = 400.0
	_grit.scale_amount_min = 0.5
	_grit.scale_amount_max = 1.6
	# The touchdown / lift-off puff: one burst, low and wide.
	_puff = _emitter(34, 1.9, _billboard(soft, false, 1.6))
	_puff.one_shot = true
	_puff.explosiveness = 0.92
	_puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_puff.emission_ring_axis = Vector3.UP
	_puff.emission_ring_radius = 1.9
	_puff.emission_ring_inner_radius = 0.5
	_puff.emission_ring_height = 0.1
	_puff.direction = Vector3.UP
	_puff.spread = 30.0
	_puff.initial_velocity_min = 0.2
	_puff.initial_velocity_max = 0.8
	_puff.radial_accel_min = 5.0
	_puff.radial_accel_max = 11.0
	_puff.damping_min = 2.0
	_puff.damping_max = 3.0
	_puff.scale_amount_min = 1.0
	_puff.scale_amount_max = 2.0
	_puff.scale_amount_curve = _curve([0.0, 0.4, 0.4, 1.0, 1.0, 1.7])
	_puff.color_ramp = _ramp([0.0, 0.0, 0.1, 0.75, 0.6, 0.35, 1.0, 0.0])
	# The engines' light on the ground: a soft additive pool and one unshadowed lamp.
	_wash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9.0, 9.0)
	q.orientation = PlaneMesh.FACE_Y
	_wash.mesh = q
	_wash_mat = StandardMaterial3D.new()
	_wash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_wash_mat.albedo_texture = _radial(Color(1, 1, 1, 1), 0.12)
	_wash_mat.disable_receive_shadows = true
	_wash_mat.disable_fog = true
	_wash.material_override = _wash_mat
	_wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wash.visible = false
	add_child(_wash)
	_light = OmniLight3D.new()
	_light.omni_range = 15.0
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	for i: int in 2:
		var s := MeshInstance3D.new()
		var sq := QuadMesh.new()
		sq.size = Vector2(7.5, 7.5)
		sq.orientation = PlaneMesh.FACE_Y
		s.mesh = sq
		var sm := ShaderMaterial.new()
		sm.shader = SCORCH_SHADER
		sm.set_shader_parameter("seed", float(i) * 3.7)
		s.material_override = sm
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		add_child(s)
		_scorch.append(s)
	set_process(false)


## The glow colour of the engines (the Locker's choice).
func tint(c: Color) -> void:
	_glow = c


## One frame of flight. `at` = the ship, `ground` = the point under it, `up` = the local up there,
## `alt` = metres above the ground, `lift` = the lift engines 0..1.
func fly(at: Vector3, ground: Vector3, up: Vector3, alt: float, lift: float) -> void:
	var near: float = clampf(1.0 - alt / NEAR_M, 0.0, 1.0)
	_strength = lift * pow(near, 1.4)
	var on: bool = _strength > 0.03
	if on:
		var b: Basis = _frame(up)
		var skirt := Transform3D(b, ground + up * 0.25)
		_dust.global_transform = skirt
		_grit.global_transform = skirt
		_dust.gravity = up * 0.6
		_grit.gravity = up * -9.8
		_dust.color = Color(_dust_col.r, _dust_col.g, _dust_col.b, _dust_col.a * minf(_strength * 1.6, 1.0))
		_wash.global_transform = Transform3D(b, ground + up * 0.15)
		_wash_mat.albedo_color = Color(_glow.r, _glow.g, _glow.b, 0.8 * _strength)
		_light.global_position = ground + up * clampf(alt * 0.6, 0.9, 3.0)
		_light.light_color = _glow.lerp(Color.WHITE, 0.35)
		_light.light_energy = 8.0 * _strength
	_dust.emitting = on
	_grit.emitting = _strength > 0.35
	_wash.visible = on
	_light.visible = on
	_live = 3.0
	set_process(true)


## The ship left the pad or came down on it (xf = the pad): a puff, and a fresh scorch under the engines.
func mark(xf: Transform3D, strength: float = 1.0) -> void:
	var up: Vector3 = xf.basis.y.normalized()
	_puff.global_transform = Transform3D(_frame(up), xf.origin + up * 0.2)
	_puff.gravity = up * 0.4
	_puff.color = Color(_dust_col.r, _dust_col.g, _dust_col.b, _dust_col.a * clampf(strength, 0.0, 1.0))
	_puff.restart()
	_puff.emitting = true
	var i: int = _next
	for k: int in 2:  # the same pad again: refresh its mark instead of laying a second one
		if _scorch[k].visible and _scorch[k].global_position.distance_to(xf.origin) < 2.0:
			i = k
	_next = (i + 1) % 2
	_scorch[i].global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + up * 0.085)
	var was: float = scorch_left(i)
	_scorch_k[i] = clampf(was + strength, 0.0, 1.0)
	_scorch_t[i] = SCORCH_S
	# A new mark burns in over a second (no pop); a refreshed one starts from what was left.
	_scorch_age[i] = SCORCH_IN_S * clampf(was / _scorch_k[i], 0.0, 1.0)
	_scorch[i].visible = true
	(_scorch[i].material_override as ShaderMaterial).set_shader_parameter("amount", _scorch_k[i] * _scorch_age[i] / SCORCH_IN_S)
	_live = maxf(_live, 3.0)
	set_process(true)


## The engines are off: the skirt stops (what is in the air drifts on and fades).
func stop() -> void:
	_strength = 0.0
	_dust.emitting = false
	_grit.emitting = false
	_wash.visible = false
	_light.visible = false


## How strongly the skirt blows right now, 0..1 (tests).
func strength() -> float:
	return _strength


## How dark the scorch on pad slot i still is, 0..1 (tests).
func scorch_left(i: int) -> float:
	return _scorch_k[i] * _scorch_t[i] / SCORCH_S if _scorch[i].visible else 0.0


func _process(delta: float) -> void:
	_live -= delta
	var any: bool = _live > 0.0
	for i: int in 2:
		if not _scorch[i].visible:
			continue
		_scorch_t[i] -= delta
		_scorch_age[i] = minf(_scorch_age[i] + delta, SCORCH_IN_S)
		if _scorch_t[i] <= 0.0:
			_scorch[i].visible = false
			_scorch_k[i] = 0.0
			continue
		any = true
		# Dark for the first third, then it weathers away.
		(_scorch[i].material_override as ShaderMaterial).set_shader_parameter("amount", _scorch_k[i] * smoothstep(0.0, 0.66, _scorch_t[i] / SCORCH_S) * _scorch_age[i] / SCORCH_IN_S)
	if _live <= 0.0 and _strength > 0.0:
		stop()
	if not any:
		set_process(false)


## A basis whose Y is the local up.
static func _frame(up: Vector3) -> Basis:
	var x: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, up, x.cross(up).normalized())


func _emitter(amount: int, life: float, mesh: Mesh) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _billboard(tex: Texture2D, additive: bool, size: float) -> QuadMesh:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX  # lit by the sun, the moon and the engines' lamp
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = m
	return q


func _radial(c: Color, mid: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, c)
	g.add_point(0.45, Color(c.r, c.g, c.b, mid))
	g.set_color(g.get_point_count() - 1, Color(c.r, c.g, c.b, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 2.0
	for i: int in range(0, pts.size(), 2):
		c.add_point(Vector2(float(pts[i]), float(pts[i + 1])))
	return c


func _ramp(pts: Array) -> Gradient:
	var g := Gradient.new()
	g.set_offset(0, float(pts[0]))
	g.set_color(0, Color(1, 1, 1, float(pts[1])))
	g.set_offset(1, float(pts[pts.size() - 2]))
	g.set_color(1, Color(1, 1, 1, float(pts[pts.size() - 1])))
	for i: int in range(2, pts.size() - 2, 2):
		g.add_point(float(pts[i]), Color(1, 1, 1, float(pts[i + 1])))
	return g
