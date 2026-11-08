class_name OrbitDay
extends Node
## [orbB] Sky, suns and the real day/night sides of a globe (phase A's VerdanceGlobe day code as
## its own node; orbE merges SkyDirector into this). Two suns fixed in space light one side of
## the planet; the planet turns once every day_min minutes, so walking far changes local time.
## The sky shader (orbit_sky.gdshader) works in world space with the local up under the camera.
## Dev: --orbit-day=MIN (rotation period, default 24), --orbit-time=0..1 (local time at the
## start hub, 0.5 = noon).

const DECLINATION: float = 0.25

var env: Environment
var sun: DirectionalLight3D
var sun2: DirectionalLight3D
var sky_mat: ShaderMaterial
var lamp: OmniLight3D
var day_min: float = 24.0
var stats: Dictionary = {}
## Who stands where: the body whose local up decides daylight, and the camera for the sky.
var body: Node3D
var camera_pos: Callable  # -> Vector3
var space_view: bool = false
var _phi0: float = 0.0
var _elapsed: float = 0.0


## Environment + lights under `root`. home: the start hub's direction (its local time is set).
func build(root: Node3D, home: Vector3) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()  # world-space sky: zenith = local up, suns fixed in space
	sky_mat.shader = preload("res://planet/orbit/orbit_sky.gdshader")
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.62, 0.66)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.name = "OrbitEnvironment"
	we.environment = env
	root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	root.add_child(sun)
	sun2 = DirectionalLight3D.new()
	sun2.name = "SecondSun"
	sun2.light_color = Color(1.0, 0.72, 0.5)
	sun2.shadow_enabled = false
	sun2.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	root.add_child(sun2)
	day_min = DevHooks.get_f("orbit-day", 24.0)
	_phi0 = atan2(home.x, home.z) + (DevHooks.get_f("orbit-time", 0.42) - 0.5) * TAU


## Lumi's own light: nights stay readable (Glim takes this over).
func add_lamp(on: Node3D) -> void:
	lamp = OmniLight3D.new()
	lamp.name = "LumiLamp"
	lamp.omni_range = 11.0
	lamp.light_color = Color(0.75, 0.88, 1.0)
	lamp.shadow_enabled = false
	on.add_child(lamp)
	lamp.position = Vector3(0, 2.4, 0.4)


## The quality pass sets the flat-world fog density; on the globe that is several times too thick.
func after_quality(command_view: bool) -> void:
	env.fog_density = 0.0003 if command_view else 0.0011


## World direction toward a sun at rotation phase phi (the planet's spin axis is world +Y).
static func sun_dir(phi: float, decl: float) -> Vector3:
	return Vector3(sin(phi) * cos(decl), sin(decl), cos(phi) * cos(decl)).normalized()


func phase() -> float:
	return _phi0 + TAU * _elapsed / (day_min * 60.0)


## Local time 0..1 (0.5 = noon) at a point.
func local_time(p: Vector3) -> float:
	return fposmod(0.5 + (phase() - atan2(p.x, p.z)) / TAU, 1.0)


## Elapsed seconds of planet rotation (saved, so the day carries on after a load).
func elapsed() -> float:
	return _elapsed


func set_elapsed(t: float) -> void:
	_elapsed = maxf(0.0, t)


func _process(delta: float) -> void:
	if env == null or body == null or not is_instance_valid(body):
		return
	_elapsed += delta
	var phi: float = phase()
	var s1: Vector3 = sun_dir(phi, DECLINATION)
	var s2: Vector3 = sun_dir(phi + 0.42, DECLINATION - 0.12)
	var u: Vector3 = body.global_position.normalized()
	var d1: float = smoothstep(-0.06, 0.14, s1.dot(u))
	var d2: float = smoothstep(-0.06, 0.14, s2.dot(u))
	var day: float = maxf(d1, d2 * 0.8)
	sun.global_basis = _toward(s1)
	sun.light_energy = 1.2 * d1
	sun.shadow_enabled = d1 > 0.05
	sun2.global_basis = _toward(s2)
	sun2.light_energy = 0.45 * d2
	var cp: Vector3 = camera_pos.call() if camera_pos.is_valid() else body.global_position
	sky_mat.set_shader_parameter("up_dir", cp.normalized())
	sky_mat.set_shader_parameter("sun1_dir", s1)
	sky_mat.set_shader_parameter("sun2_dir", s2)
	sky_mat.set_shader_parameter("day", day)
	sky_mat.set_shader_parameter("star_phi", phi)
	sky_mat.set_shader_parameter("space", 1.0 if space_view else 0.0)
	env.ambient_light_energy = lerpf(0.75, 1.1, day)
	env.ambient_light_sky_contribution = lerpf(0.25, 1.0, day)
	env.ambient_light_color = Color(0.36, 0.44, 0.62)
	env.tonemap_exposure = lerpf(1.55, 1.25, day)
	if lamp:
		lamp.light_energy = lerpf(2.2, 0.0, day)
		lamp.visible = day < 0.98
	stats["local_time"] = local_time(body.global_position)
	stats["daylight"] = day


static func _toward(d: Vector3) -> Basis:
	var ref: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	return Basis.looking_at(-d, ref)
