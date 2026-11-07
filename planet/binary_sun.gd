class_name BinarySun
extends Node
## [home] The second sun in every planet's sky (data/solar_system.json, SolarSystem.suns_for).
## The sky director's DirectionalLight carries the primary (Hearth: shadows, the PhysicalSky's sun
## disc); this adds the companion (Ember): an unshadowed warm fill light and a soft disc with a
## thin halo, kept at the planet's separation from the primary so the pair rises and sets
## together. Sizes and light follow the planet's orbital distance. Attached by SkyDirector.setup.

var sky: SkyDirector
var light: DirectionalLight3D
var disc: MeshInstance3D
var _mat: ShaderMaterial
var _suns: Dictionary = {}
var _base_disk: float = 1.0


static func attach(p_sky: SkyDirector) -> BinarySun:
	var b := BinarySun.new()
	b.name = "BinarySun"
	b.sky = p_sky
	p_sky.add_child(b)
	return b


func _ready() -> void:
	light = DirectionalLight3D.new()
	light.name = "CompanionSun"
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(light)
	disc = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	disc.mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = _disc_shader()
	_mat.set_shader_parameter("tex", _disc_tex())
	_mat.render_priority = -10
	disc.material_override = _mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.extra_cull_margin = 16384.0
	add_child(disc)
	if sky and sky.sky_mat:
		_base_disk = sky.sky_mat.sun_disk_scale
	if DevHooks.has("suns-cam"):  # dev shots: look at both suns from beside Lumi
		get_tree().create_timer(1.0).timeout.connect(_suns_cam)


func _suns_cam() -> void:
	var w: Node = sky.world if sky else null
	if w == null or sky.sun == null:
		return
	var to_a: Vector3 = sky.sun.global_transform.basis.z.normalized()
	var mid: Vector3 = (to_a + SolarSystem.suns_for(SolarSystem.current_id(), to_a)["b"]["dir"] as Vector3).normalized()
	var flat := Vector3(mid.x, 0, mid.z).normalized()
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 1500.0
	(w as Node).add_child(cam)
	var p: Vector3 = (w.get("patch") as Node3D).global_position if w.get("patch") != null else Vector3.ZERO
	cam.global_position = p - flat * 6.0 + Vector3(0, 1.6, 0)
	cam.look_at(cam.global_position + flat * 10.0 + Vector3(0, mid.y / maxf(0.2, Vector2(mid.x, mid.z).length()) * 10.0 * 0.75, 0), Vector3.UP)
	cam.current = true
	if w.get("hud") != null:
		w.hud.visible = false


static func _disc_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.38, 1.0);
uniform float energy = 4.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec4 t = texture(tex, UV);
	float core = smoothstep(0.75, 0.95, t.a);
	ALBEDO = tint.rgb * t.a * tint.a * mix(0.6, energy, core);
	ALPHA = 1.0;
}
"""
	return sh


## A bright core with a soft, thin halo (the owner: subtle glow).
static func _disc_tex() -> GradientTexture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.22, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0)])
	g.gradient = grad
	return g


func _process(_delta: float) -> void:
	if sky == null or sky.sun == null:
		return
	var sun: DirectionalLight3D = sky.sun
	var to_a: Vector3 = sun.global_transform.basis.z.normalized()  # a DirectionalLight shines along -Z
	_suns = SolarSystem.suns_for(SolarSystem.current_id(), to_a)
	var a: Dictionary = _suns["a"]
	var b: Dictionary = _suns["b"]
	var to_b: Vector3 = b["dir"]
	# Primary: disc size and light by distance (the sky director already set the time-of-day curve).
	if sky.sky_mat:
		sky.sky_mat.sun_disk_scale = _base_disk * float(a["size"])
	sun.light_energy *= float(a["energy"])
	# Companion: same elevation curve as the primary, its own colour, no shadows.
	var up_k: float = smoothstep(-0.03, 0.2, to_b.y)
	light.visible = up_k > 0.01 and sun.visible
	light.light_color = (b["color"] as Color).lerp(Color(1.0, 0.5, 0.3), 1.0 - smoothstep(0.05, 0.45, to_b.y))
	light.light_energy = 3.0 * float(b["energy"]) * up_k
	if to_b.length() > 0.5:
		light.global_transform = Transform3D(Basis.looking_at(-to_b, Vector3.UP if absf(to_b.y) < 0.98 else Vector3.FORWARD), Vector3.ZERO)
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	disc.visible = cam != null and to_b.y > -0.06
	if cam == null:
		return
	var dist: float = cam.far * 0.85
	disc.global_position = cam.global_position + to_b * dist
	# Angular size: the primary's disc is ~0.55 deg at Verdance; the halo texture is ~6x the core.
	var ang: float = deg_to_rad(0.55) * float(b["size"])
	var core: float = 2.0 * dist * tan(ang * 0.5)
	disc.scale = Vector3.ONE * core * 6.0
	var c: Color = b["color"]
	_mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, clampf(up_k + 0.25, 0.0, 1.0) * (1.0 if sun.visible else 0.5)))
	# HDR core so the disc reads through the dusty haze (the halo stays faint: thin glow).
	_mat.set_shader_parameter("energy", 2.5 + 3.5 * float(sky.haze) if sky else 4.0)
