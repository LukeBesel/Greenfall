class_name BinarySun
extends Node3D
## [worlds2] The binary star every planet sees (owner rule): the warm primary is the SkyDirector's
## sun (DirectionalLight with shadows, the PhysicalSky draws its disc); the smaller, cooler companion
## gets its own disc with a thin halo (art/shaders/sun_disc.gdshader, a far camera-facing quad) and an
## unshadowed warm fill DirectionalLight. Sizes and intensities follow the planet's orbit through
## `SolarSystem.suns_for(planet_id)` (systems/solar_system.gd, data/solar_system.json, owned by the
## "home" branch) when it exists, else the defaults below. The companion keeps a fixed angular
## separation from the primary, so they rise and set together.

const DIST: float = 545.0
const HELPER: String = "res://systems/solar_system.gd"
## Fallback canon (until data/solar_system.json is in): primary and companion.
const DEFAULT_A: Dictionary = {"color": Color(1.0, 0.95, 0.85), "size": 1.0, "energy": 1.0}
const DEFAULT_B: Dictionary = {"color": Color(1.0, 0.62, 0.38), "size": 0.55, "energy": 0.25, "separation": 14.0}

var planet_id: String = ""  # "" = the first shipped planet's orbit
var a: Dictionary = DEFAULT_A.duplicate()
var b: Dictionary = DEFAULT_B.duplicate()
var separation_deg: float = 14.0
var fill: DirectionalLight3D
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _base_disk_scale: float = 1.2


## The suns for a planet: {a: {color, size, energy}, b: {color, size, energy, separation}} from the
## SolarSystem helper when it exists, else the defaults (pure apart from the optional helper).
static func suns_for(id: String) -> Dictionary:
	var out: Dictionary = {"a": DEFAULT_A.duplicate(), "b": DEFAULT_B.duplicate()}
	if not ResourceLoader.exists(HELPER):
		return out
	var sc: Script = load(HELPER) as Script
	if sc == null or not sc.has_method("suns_for"):
		return out
	var r: Variant = sc.call("suns_for", id)
	if not (r is Dictionary):
		return out
	for k: String in ["a", "b"]:
		var src: Variant = (r as Dictionary).get(k)
		if src is Dictionary:
			for f: Variant in src:
				out[k][str(f)] = src[f]
	return out


## Degrees between the two suns: b.separation, else the angle between a.dir and b.dir, else 14.
static func separation_of(s: Dictionary) -> float:
	var bb: Dictionary = s.get("b", {})
	if bb.has("separation"):
		return float(bb["separation"])
	var ad: Variant = (s.get("a", {}) as Dictionary).get("dir")
	var bd: Variant = bb.get("dir")
	if ad is Vector3 and bd is Vector3 and (ad as Vector3).length() > 0.0 and (bd as Vector3).length() > 0.0:
		return rad_to_deg((ad as Vector3).angle_to(bd as Vector3))
	return float(DEFAULT_B["separation"])


static func color_of(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


func setup(p_planet: String, sky_mat: PhysicalSkyMaterial) -> void:
	planet_id = p_planet
	var s: Dictionary = suns_for(planet_id)
	a = s["a"]
	b = s["b"]
	separation_deg = separation_of(s)
	if sky_mat:
		_base_disk_scale = sky_mat.sun_disk_scale
		sky_mat.sun_disk_scale = _base_disk_scale * float(a.get("size", 1.0))
	fill = DirectionalLight3D.new()
	fill.name = "CompanionFill"
	fill.shadow_enabled = false  # performance: the primary carries the shadows
	fill.light_color = color_of(b.get("color"), DEFAULT_B["color"])
	fill.light_energy = 0.0
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # the PhysicalSky draws one disc; ours draws this one
	add_child(fill)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/sun_disc.gdshader")
	_mat.set_shader_parameter("color", fill.light_color)
	var q := QuadMesh.new()
	# The PhysicalSky sun is ~0.5 deg x sun_disk_scale; the companion is b.size of the primary.
	var disc_deg: float = 0.55 * _base_disk_scale * float(a.get("size", 1.0)) * float(b.get("size", 0.55)) / maxf(float(a.get("size", 1.0)), 0.01)
	var quad_deg: float = disc_deg * 8.0
	var half: float = tan(deg_to_rad(quad_deg) * 0.5) * DIST
	q.size = Vector2(half * 2.0, half * 2.0)
	_mat.set_shader_parameter("disc_r", 1.0 / 8.0)
	_quad = MeshInstance3D.new()
	_quad.mesh = q
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 2000.0
	add_child(_quad)


## Direction toward the companion, given the direction toward the primary: the same elevation band,
## turned along the horizon by the separation (so both rise and set together).
func companion_dir(to_a: Vector3) -> Vector3:
	return to_a.rotated(Vector3.UP, deg_to_rad(separation_deg)).normalized()


## Called by SkyDirector._apply each frame with the primary light (already placed and lit).
func update(sun: DirectionalLight3D, sun_up: float) -> void:
	var to_a: Vector3 = sun.global_transform.basis.z.normalized()
	var to_b: Vector3 = companion_dir(to_a)
	# Same height as the primary, so the companion is up exactly when the primary is (the sky parks
	# the primary on the horizon at night: sun_up is what says it has set).
	var b_up: float = minf(smoothstep(-0.02, 0.12, to_b.y), sun_up)
	var ea: float = float(a.get("energy", 1.0))
	sun.light_energy *= ea
	fill.global_transform = Transform3D(Basis.looking_at(-to_b, Vector3.UP if absf(to_b.y) < 0.99 else Vector3.FORWARD), Vector3.ZERO)
	# The companion's warm fill: its share of the primary's daylight, no shadows.
	fill.light_energy = 3.0 * float(b.get("energy", 0.25)) * b_up
	fill.visible = fill.light_energy > 0.01
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam and _quad:
		_quad.global_transform = Transform3D(Basis.looking_at(to_b, Vector3.UP if absf(to_b.y) < 0.99 else Vector3.FORWARD), cam.global_position + to_b * DIST)
		_mat.set_shader_parameter("fade", b_up)
		_mat.set_shader_parameter("energy", clampf(0.6 + float(b.get("energy", 0.25)) * 2.0, 0.6, 2.0))
		_mat.set_shader_parameter("halo", lerpf(0.5, 0.25, sun_up))
	_quad.visible = b_up > 0.001
