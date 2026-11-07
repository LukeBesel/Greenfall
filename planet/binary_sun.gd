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
var _mat: StandardMaterial3D
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
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat.disable_fog = true
	_mat.disable_receive_shadows = true
	_mat.albedo_texture = _disc_tex()
	_mat.render_priority = -10
	disc.material_override = _mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.extra_cull_margin = 16384.0
	add_child(disc)
	if sky and sky.sky_mat:
		_base_disk = sky.sky_mat.sun_disk_scale


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
	_mat.albedo_color = Color(c.r * 1.4, c.g * 1.25, c.b * 1.1, clampf(up_k + 0.25, 0.0, 1.0) * (0.85 if sun.visible else 0.45))
