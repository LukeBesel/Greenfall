class_name RocketPlume
extends Node3D
## Energy exhaust hanging below a nozzle (this node's origin, pointing down -Y): an outer turbulent
## shell and a hot core with shock diamonds (art/shaders/rocket_plume.gdshader), a bright nozzle
## flare sprite and a light that washes the ground. `power` 0..1 (set by the launch sequence).

const PLUME_SHADER := preload("res://art/shaders/rocket_plume.gdshader")

var power: float = 0.0
var scale_len: float = 1.0
var radius: float = 0.62
var light: OmniLight3D
var _outer: MeshInstance3D
var _core: MeshInstance3D
var _flare: MeshInstance3D
var _outer_mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _flare_mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	var len_o: float = 7.5 * scale_len
	var len_c: float = 3.6 * scale_len
	_outer_mat = _mat(0.0, 2.5, randf() * 10.0)
	_outer_mat.set_shader_parameter("opacity", 1.0)
	_core_mat = _mat(1.0, 7.0, randf() * 10.0)
	_core_mat.set_shader_parameter("opacity", 2.0)
	_core_mat.set_shader_parameter("mid_color", Color(0.75, 0.97, 1.0))
	_core_mat.set_shader_parameter("edge_color", Color(0.3, 0.85, 1.0))
	_outer = _cone(radius * 1.05, radius * 2.9, len_o, _outer_mat)
	_core = _cone(radius * 0.7, radius * 0.35, len_c, _core_mat)
	_flare_mat = StandardMaterial3D.new()
	_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flare_mat.no_depth_test = false
	_flare_mat.albedo_texture = _radial()
	_flare_mat.albedo_color = Color(0.6, 0.95, 1.0, 1.0)
	_flare = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 6.0, radius * 6.0)
	_flare.mesh = q
	_flare.material_override = _flare_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.position = Vector3(0, -0.4 * scale_len, 0)
	add_child(_flare)
	light = OmniLight3D.new()
	light.light_color = Color(0.55, 0.9, 1.0)
	light.omni_range = 16.0 * scale_len
	light.omni_attenuation = 1.2
	light.position = Vector3(0, -1.2, 0)
	light.shadow_enabled = false
	add_child(light)
	_apply()


func _mat(diamonds: float, bright: float, seed_v: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PLUME_SHADER
	m.set_shader_parameter("diamonds", diamonds)
	m.set_shader_parameter("brightness", bright)
	m.set_shader_parameter("seed", seed_v)
	return m


func _cone(r_top: float, r_bot: float, length: float, mat: Material) -> MeshInstance3D:
	# Lathe profile from the nozzle (v=0) down to the tail (v=1), bulging a little at mid-length.
	var prof := PackedVector2Array()
	for i: int in 13:
		var v: float = float(i) / 12.0
		var r: float = lerpf(r_top, r_bot, v) * (1.0 + 0.25 * sin(v * PI))
		prof.append(Vector2(r, -v * length))
	var mi := MeshInstance3D.new()
	mi.mesh = RocketModel.lathe(prof, 20)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The plume is huge and moves fast: a generous AABB keeps it from popping at frame edges.
	mi.custom_aabb = AABB(Vector3(-r_bot * 2.0, -length * 1.2, -r_bot * 2.0), Vector3(r_bot * 4.0, length * 1.3, r_bot * 4.0))
	add_child(mi)
	return mi


func _radial() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.25, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _process(delta: float) -> void:
	_t += delta
	_apply()


func _apply() -> void:
	var on: bool = power > 0.01
	_outer.visible = on
	_core.visible = on
	_flare.visible = on
	light.visible = on
	if not on:
		return
	var flick: float = 1.0 + 0.08 * sin(_t * 53.0) + 0.06 * sin(_t * 31.0 + 1.3)
	_outer_mat.set_shader_parameter("power", power * flick)
	_outer_mat.set_shader_parameter("mid_color", Color(0.25, 0.75, 1.0))
	_outer_mat.set_shader_parameter("edge_color", Color(0.3, 0.4, 1.0))
	_core_mat.set_shader_parameter("power", minf(1.0, power * 1.1) * flick)
	_flare.scale = Vector3.ONE * (0.6 + 0.6 * power) * flick
	_flare_mat.albedo_color = Color(0.6, 0.95, 1.0, clampf(power, 0.0, 1.0))
	light.light_energy = 9.0 * power * flick
