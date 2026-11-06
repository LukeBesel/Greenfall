class_name SkyDirector
extends Node
## Day/night cycle and the planet's haze. The sun stays high through most of the day so play
## areas are sunlit; nights are moonlit (bright, cool) with stars. Haze (dust in the air) lifts
## as the planet is restored and as air scrubbers run: the sky shifts from dusty to clear blue.

const DAY_LENGTH_S: float = 1200.0  # one full day in game seconds

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: PhysicalSkyMaterial
var world: Node
var time_of_day: float = 0.3  # 0 = midnight, 0.25 = sunrise, 0.5 = noon
var haze: float = 1.0          # 1 = Act 1 dusty, 0 = fully clear
var frozen: bool = false


func setup(p_env: Environment, p_sun: DirectionalLight3D) -> void:
	env = p_env
	sun = p_sun
	sky_mat = env.sky.sky_material as PhysicalSkyMaterial
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 50.0
	add_child(moon)
	sky_mat.night_sky = _star_texture()
	time_of_day = float(GameState.flags.get("time_of_day", 0.32))


static func _star_texture() -> ImageTexture:
	var img := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.006, 0.012))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 2600:
		var b: float = pow(rng.randf(), 4.0)
		var c := Color(0.6 + b * 0.4, 0.65 + b * 0.35, 0.8 + b * 0.2) * (0.25 + b * 0.9)
		img.set_pixel(rng.randi() % 1024, rng.randi() % 512, c)
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if env == null:
		return
	if not frozen:
		time_of_day = fmod(time_of_day + delta / DAY_LENGTH_S, 1.0)
		GameState.flags["time_of_day"] = time_of_day
	if world and world.get("planet") != null:
		var target: float = 1.0 - clampf(world.planet.restored_fraction() * 8.0 + float(GameState.stats.get("air_filtered", 0.0)) * 0.0005, 0.0, 0.85)
		haze = lerpf(haze, target, clampf(delta * 0.2, 0.0, 1.0))
	_apply()


func _apply() -> void:
	# Sun path: rises at 0.25, sets at 0.75; kept high at midday (max elevation ~70 deg).
	var day_t: float = (time_of_day - 0.25) / 0.5
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI) * 70.0
	var is_day: bool = day_t > 0.0 and day_t < 1.0
	sun.rotation_degrees = Vector3(-maxf(elev, -10.0), -30.0 + day_t * 60.0, 0.0)
	var sun_up: float = smoothstep(0.0, 12.0, elev)
	sun.light_energy = 2.6 * sun_up
	sun.visible = sun_up > 0.01
	sun.light_color = Color(1.0, 0.75, 0.55).lerp(Color(1.0, 0.94, 0.84), smoothstep(5.0, 30.0, elev))
	# Moon: opposite side of the sky, bright enough to keep playing.
	var night_t: float = fmod(time_of_day + 0.25, 1.0) / 0.5
	var m_elev: float = sin(clampf(night_t, 0.0, 1.0) * PI) * 60.0
	moon.rotation_degrees = Vector3(-maxf(m_elev, -10.0), 150.0 - night_t * 60.0, 0.0)
	moon.light_energy = 0.55 * smoothstep(0.0, 10.0, m_elev) * (1.0 - sun_up)
	moon.visible = moon.light_energy > 0.01
	# Haze drives sky scattering, fog and saturation.
	sky_mat.turbidity = lerpf(3.0, 9.0, haze)
	sky_mat.mie_coefficient = lerpf(0.003, 0.009, haze)
	sky_mat.rayleigh_color = Color(0.26, 0.48, 0.95).lerp(Color(0.38, 0.45, 0.72), haze)
	env.fog_density = lerpf(0.0012, 0.0035, haze)
	env.volumetric_fog_density = lerpf(0.002, 0.008, haze)
	env.adjustment_saturation = lerpf(1.28, 1.12, haze)
	env.ambient_light_energy = lerpf(0.55, 1.25 if env.sdfgi_enabled else 1.7, maxf(sun_up, 0.35))
	env.tonemap_exposure = lerpf(1.6, 1.3, sun_up)
