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
## Hooks for the Future Layer (planet/future_layer.gd): a restored district clears its own air
## (added to the haze reduction) and tints the night fog toward its aurora (rgb, a = strength).
var clear_bonus: float = 0.0
var night_tint := Color(0, 0, 0, 0)
## [biomes] Frontier colour grade (data/frontiers.json "grade") and a sandstorm amount 0..1
## (planet/frontier_district.gd). The grade eases off as the district is restored (grade_amt).
var grade: Dictionary = {}
var grade_amt: float = 1.0
var storm: float = 0.0
## [worlds2] Long Nights (systems/world_look.gd): how much darker nights are, 0..1.
var night_dark: float = 0.0
## [worlds2] The binary star (planet/binary_sun.gd): the companion's disc and warm fill light.
var binary: BinarySun


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
	_stars_img = _star_image()  # [vqa2] stars fade with the sun (see _apply_stars)
	_stars_tex = ImageTexture.create_from_image(_stars_img)
	sky_mat.night_sky = _stars_tex
	binary = BinarySun.new()  # [worlds2] every planet sees both suns
	binary.name = "BinarySun"
	add_child(binary)
	binary.setup(current_planet_id(), sky_mat)
	time_of_day = float(GameState.flags.get("time_of_day", 0.32))


## [worlds2] The planet this sky belongs to (data/solar_system.json ids): Verdance, or the current
## world's planet / world type.
static func current_planet_id() -> String:
	if PlanetCfg.current != "":  # [v7planet] on a globe, the globe's planet (its suns, data/solar_system.json)
		return PlanetCfg.current
	if CradleMode.profile.is_empty() or CradleMode.current_index() <= 0:
		return "verdance"
	var pid: String = WorldLook.planet_id()
	return pid if pid != "" else str(CradleMode.current_world().get("type", "verdance"))


## [vqa2] Night sky: sparse stars on a near-black sky. PhysicalSkyMaterial adds `night_sky`
## under the sun too (multiplied by the reddish extinction), so the stars showed in the day sky
## as faint orange/tan dots. The texture is scaled by how dark it is, in a few steps (only the
## 2600 star pixels are rewritten when the step changes).
const STAR_STEPS: int = 6
const SKY_BASE := Color(0.004, 0.006, 0.012)
var _stars_img: Image
var _stars_tex: ImageTexture
var _stars_step: int = -1
var _star_px := PackedInt32Array()  # x, y pairs
var _star_col := PackedColorArray()


static func star_level(sun_up: float) -> float:
	return 1.0 - smoothstep(0.0, 0.35, sun_up)


func _star_image() -> Image:
	var img := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	img.fill(SKY_BASE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 2600:
		var b: float = pow(rng.randf(), 4.0)
		var c := Color(0.6 + b * 0.4, 0.65 + b * 0.35, 0.8 + b * 0.2) * (0.25 + b * 0.9)
		var x: int = rng.randi() % 1024
		var y: int = rng.randi() % 512
		_star_px.append(x)
		_star_px.append(y)
		_star_col.append(c)
		img.set_pixel(x, y, c)
	return img


func _apply_stars(level: float) -> void:
	if _stars_tex == null:
		return
	var step: int = clampi(roundi(level * STAR_STEPS), 0, STAR_STEPS)
	if step == _stars_step:
		return
	_stars_step = step
	var k: float = float(step) / STAR_STEPS
	for i: int in _star_col.size():
		_stars_img.set_pixel(_star_px[i * 2], _star_px[i * 2 + 1], SKY_BASE.lerp(_star_col[i], k) if k > 0.0 else SKY_BASE)
	_stars_tex.update(_stars_img)


func _process(delta: float) -> void:
	if env == null:
		return
	if sphere:  # [orbE] the round planet: its own clock (the spin), lights and sky shader
		_process_sphere(delta)
		return
	if not frozen:
		# [late] Long Nights; [buddy] longer days and quicker nights until Glim is found
		time_of_day = fmod(time_of_day + delta / DAY_LENGTH_S * CradleMode.day_speed(time_of_day) * Glim.clock_mult(time_of_day), 1.0)
		GameState.flags["time_of_day"] = time_of_day
	if world and world.get("planet") != null:
		var target: float = 1.0 - clampf(world.planet.restored_fraction() * 8.0 + float(GameState.stats.get("air_filtered", 0.0)) * 0.0005 + clear_bonus, 0.0, 0.85)
		haze = lerpf(haze, target, clampf(delta * 0.2, 0.0, 1.0))
	_apply()


func _apply() -> void:
	if sphere:  # [orbE] photo mode and dev hooks call _apply() after setting time_of_day / haze
		_apply_sphere()
		return
	# Sun path: rises at 0.25, sets at 0.75; kept high at midday (max elevation ~70 deg).
	var day_t: float = (time_of_day - 0.25) / 0.5
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI) * 70.0
	sun.rotation_degrees = Vector3(-maxf(elev, -10.0), -30.0 + day_t * 60.0, 0.0)
	var sun_up: float = smoothstep(0.0, 12.0, elev)
	sun.light_energy = 3.0 * sun_up
	sun.visible = sun_up > 0.01
	sun.light_color = Color(1.0, 0.7, 0.45).lerp(Color(1.0, 0.93, 0.8), smoothstep(8.0, 40.0, elev))
	# Moon: opposite side of the sky, bright enough to keep playing.
	var night_t: float = fmod(time_of_day + 0.25, 1.0) / 0.5
	var m_elev: float = sin(clampf(night_t, 0.0, 1.0) * PI) * 60.0
	moon.rotation_degrees = Vector3(-maxf(m_elev, -10.0), 150.0 - night_t * 60.0, 0.0)
	moon.light_energy = 0.55 * smoothstep(0.0, 10.0, m_elev) * (1.0 - sun_up)
	var lift: float = night_lift() * (1.0 - sun_up)  # [buddy] brighter early nights
	if lift > 0.0:
		# A low moon still lights the street a little (no "pitch black" between moonset and dawn).
		moon.light_energy = maxf(moon.light_energy, 0.2 * (1.0 - sun_up)) + 0.4 * lift * smoothstep(-5.0, 10.0, m_elev)
		moon.light_color = Color(0.62, 0.72, 1.0).lerp(Color(0.78, 0.84, 1.0), lift * 0.6)
	moon.visible = moon.light_energy > 0.01
	_apply_stars(star_level(sun_up))  # [vqa2]
	# Haze drives sky scattering, fog and saturation.
	sky_mat.turbidity = lerpf(3.0, 6.0, haze)
	sky_mat.mie_coefficient = lerpf(0.003, 0.006, haze)
	# Dusty but sunlit: the haze is warm and golden, the sky above it still clearly blue.
	sky_mat.rayleigh_color = Color(0.24, 0.48, 0.98).lerp(Color(0.3, 0.47, 0.9), haze)
	sky_mat.mie_color = Color(1.0, 0.92, 0.84).lerp(Color(1.0, 0.86, 0.7), haze)
	env.fog_density = lerpf(0.0010, 0.0022, haze)
	env.fog_light_color = Color(0.72, 0.82, 1.0).lerp(Color(0.98, 0.88, 0.76), haze * sun_up * 0.7)
	if night_tint.a > 0.0:
		env.fog_light_color = env.fog_light_color.lerp(Color(night_tint.r, night_tint.g, night_tint.b), night_tint.a * (1.0 - sun_up))
	env.volumetric_fog_density = lerpf(0.0015, 0.0045, haze)
	env.volumetric_fog_albedo = Color(0.88, 0.91, 0.96).lerp(Color(0.97, 0.92, 0.86), haze)
	env.adjustment_saturation = lerpf(1.28, 1.22, haze)
	env.adjustment_contrast = 1.1
	env.ambient_light_energy = lerpf(0.55, 1.25 if env.sdfgi_enabled else 1.7, maxf(sun_up, 0.35))
	env.tonemap_exposure = lerpf(1.6, 1.3, sun_up)
	if lift > 0.0:  # [buddy] more ambient and exposure at night; the sky stays dark and starry
		env.ambient_light_energy *= 1.0 + 0.45 * lift
		env.tonemap_exposure *= 1.0 + 0.2 * lift
	if not grade.is_empty() or storm > 0.0:
		_apply_grade(sun_up)
	if night_dark > 0.0:  # [worlds2] Long Nights: a dimmer moon, less ambient, a darker sky
		var nd: float = clampf(night_dark, 0.0, 1.0) * (1.0 - sun_up)
		moon.light_energy *= 1.0 - 0.45 * nd
		env.ambient_light_energy *= 1.0 - 0.4 * nd
		env.tonemap_exposure *= 1.0 - 0.22 * nd
		sky_mat.energy_multiplier = 1.0 - 0.5 * nd
	if binary:  # [worlds2] the companion sun follows the primary; orbit-scaled energies
		binary.update(sun, sun_up)


## [buddy] How much early nights are lifted (moon, ambient, exposure): full until Glim (the
## lantern bot) is found, then a gentler lift that stays (nights are moody, never unreadable).
## --night-classic turns it off (before/after renders).
static func night_lift() -> float:
	if DevHooks.has("night-classic"):
		return 0.0
	return 1.0 if not Glim.is_found() else 0.65


## [biomes] Blend the frontier grade over the computed sky and fog; then the storm on top.
func _apply_grade(_sun_up: float) -> void:
	var a: float = clampf(grade_amt, 0.0, 1.0)
	if not grade.is_empty():
		var fog: Color = _col(grade.get("fog", []), env.fog_light_color)
		env.fog_light_color = env.fog_light_color.lerp(fog, float(grade.get("fog_amt", 0.5)) * a)
		env.fog_density *= lerpf(1.0, float(grade.get("fog_mult", 1.0)), a)
		env.volumetric_fog_density *= lerpf(1.0, float(grade.get("fog_mult", 1.0)), a)
		env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(fog, float(grade.get("fog_amt", 0.5)) * a * 0.7)
		var sk: float = float(grade.get("sky_amt", 0.5)) * a
		sky_mat.rayleigh_color = sky_mat.rayleigh_color.lerp(_col(grade.get("rayleigh", []), sky_mat.rayleigh_color), sk)
		sky_mat.mie_color = sky_mat.mie_color.lerp(_col(grade.get("mie", []), sky_mat.mie_color), sk)
		env.adjustment_saturation *= lerpf(1.0, float(grade.get("sat", 1.0)), a)
		env.tonemap_exposure *= lerpf(1.0, float(grade.get("exposure", 1.0)), a)
		# [biomes2] Absolute haze targets (clearer air than the planet's dusty default), a sun
		# tint, and optional low-lying height fog (the Sunken City's mist over the water). These
		# hold as the district is restored (the planet haze only lowers them further).
		var keep: float = clampf(grade_amt + 0.6, 0.0, 1.0)
		if grade.has("fog_density"):
			env.fog_density = minf(env.fog_density, lerpf(env.fog_density, float(grade["fog_density"]), keep))
		if grade.has("vol_density"):
			env.volumetric_fog_density = minf(env.volumetric_fog_density, lerpf(env.volumetric_fog_density, float(grade["vol_density"]), keep))
		if grade.has("turbidity"):
			sky_mat.turbidity = lerpf(sky_mat.turbidity, float(grade["turbidity"]), keep)
			sky_mat.mie_coefficient = lerpf(sky_mat.mie_coefficient, float(grade.get("mie_coef", 0.0028)), keep)
		if grade.has("fog_sky"):
			env.fog_sky_affect = float(grade["fog_sky"])
			env.volumetric_fog_sky_affect = float(grade["fog_sky"]) * 0.6
		# Aerial perspective: distant land takes the sky's own colour (blue over the dunes, cold
		# over the ice) instead of a flat grey wash, the way clear air looks.
		env.fog_aerial_perspective = float(grade.get("aerial", 0.0)) * keep
		if grade.has("contrast"):
			env.adjustment_contrast = float(grade["contrast"])
		if grade.has("sun"):
			sun.light_color = sun.light_color.lerp(_col(grade["sun"], sun.light_color), 0.6 * keep)
		var hf: Array = grade.get("height_fog", [])
		if hf.size() >= 2:
			env.fog_height = float(hf[0])
			env.fog_height_density = float(hf[1]) * keep
	if storm > 0.0:
		var st: float = clampf(storm, 0.0, 1.0)
		var dust := Color(0.78, 0.6, 0.4)
		env.fog_light_color = env.fog_light_color.lerp(dust, st * 0.85)
		env.fog_density = lerpf(env.fog_density, 0.028, st)
		env.volumetric_fog_density = lerpf(env.volumetric_fog_density, 0.03, st)
		env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(dust, st)
		sun.light_energy *= 1.0 - 0.55 * st
		sky_mat.mie_coefficient = lerpf(sky_mat.mie_coefficient, 0.05, st)
		sky_mat.mie_color = sky_mat.mie_color.lerp(dust, st)
		env.adjustment_saturation *= 1.0 - 0.15 * st


static func _col(a: Variant, fallback: Color) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


# --- [orbE] Round planet (--orbit) ------------------------------------------------------
## On a globe the suns are fixed in space and the planet turns (owner: real day and night sides),
## so `spin` (the rotation phase) is the clock and time_of_day is the local time under the
## player: walking a quarter of the way round moves the clock by six hours. The sky is the
## world-space shader planet/orbit/orbit_sky.gdshader, whose zenith is the local up under the
## camera (a PhysicalSkyMaterial cannot follow a local up: the cloud renders were black).
## - The binary-sun look: the primary carries the shadows; the companion (size, colour, energy and
##   separation from BinarySun.suns_for) is a warm unshadowed fill, its disc drawn by the shader.
## - Nights stay readable: a full moon sits opposite the suns (cool light with shadows), the sky
##   stays deep blue with stars, ambient and exposure lift (night_lift), Glim carries the local light.
## - Weather: haze lifts as the planet is cleaned; a cloud deck anchored to the planet drifts and
##   its cover changes every few minutes; storm and Long Nights work as in the flat sky.
## Writing time_of_day (photo mode, --time) moves the planet so that the player's spot gets it.

const SPHERE_DECL: float = 0.25   # the suns' declination (rad)
const SPHERE_DAY_S: float = 1440.0  # one turn of the planet: 24 min (phase A)

var sphere: bool = false
var sky_shader: ShaderMaterial
var companion: DirectionalLight3D
var spin: float = 0.0
var day_period_s: float = SPHERE_DAY_S
var planet_radius: float = 1840.0
var player_fn: Callable  # () -> Vector3: the player's world position (local time, light)
var eye_fn: Callable     # () -> Vector3: the camera position (sky zenith, cloud deck)
var space_fn: Callable   # () -> bool: seen from orbit (black space)
var clean_fn: Callable   # () -> float: 0..1 cleaned share of the planet (haze lifts)
var fog_scale: float = 1.0  # set by the view: Command height wants thinner fog
var clouds: float = 0.35  # cloud cover 0..1
var daylight: float = 1.0  # 0 night .. 1 day under the player
var weather_frozen: bool = false  # renders and tests: cloud cover stays put
var _suns: Dictionary = {}
var _cloud_t: float = 0.0
var _cloud_target: float = 0.35
var _weather_t: float = 120.0
var _tod_out: float = -1.0
var _clean: float = 0.0
var _clean_t: float = 0.0


## Sphere mode setup. Set player_fn / eye_fn (and optionally space_fn, clean_fn) first. The clock
## comes back from the save (flags.orbit_spin) unless `start_local_time` >= 0 forces the local time.
func setup_sphere(p_env: Environment, p_sun: DirectionalLight3D, p_sky: ShaderMaterial, radius_m: float, start_local_time: float = -1.0) -> void:
	sphere = true
	env = p_env
	sun = p_sun
	sky_shader = p_sky
	planet_radius = radius_m
	sky_shader.set_shader_parameter("planet_r", radius_m)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.66, 0.76, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 50.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_suns = BinarySun.suns_for(current_planet_id())
	# The same BinarySun as the flat sky (planet id, the companion's unshadowed warm fill), so
	# everything that reads sky_director.binary works on the globe. Its disc quad stays hidden:
	# the world-space sky shader draws the disc where the companion really is on the curve, and
	# this director drives the fill along the planet's spin (BinarySun.update assumes a flat up).
	binary = BinarySun.new()
	binary.name = "BinarySun"
	add_child(binary)
	binary.setup(current_planet_id(), null)
	if binary._quad:
		binary._quad.visible = false
		binary.set_process(false)
	companion = binary.fill
	companion.light_color = BinarySun.color_of(_suns["b"].get("color"), BinarySun.DEFAULT_B["color"])
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sky_shader.set_shader_parameter("sun1_color", BinarySun.color_of(_suns["a"].get("color"), BinarySun.DEFAULT_A["color"]))
	sky_shader.set_shader_parameter("sun2_color", companion.light_color)
	sky_shader.set_shader_parameter("sun2_size", float(_suns["b"].get("size", 0.55)) / maxf(float(_suns["a"].get("size", 1.0)), 0.01))
	sky_shader.set_shader_parameter("sun2_strength", clampf(0.4 + float(_suns["b"].get("energy", 0.25)), 0.4, 1.0))
	var p: Vector3 = _player_pos()
	if start_local_time >= 0.0 or not GameState.flags.has("orbit_spin"):
		spin = spin_for_local_time(start_local_time if start_local_time >= 0.0 else 0.42, p)
	else:
		spin = float(GameState.flags["orbit_spin"])
	clouds = float(GameState.flags.get("orbit_clouds", 0.35))
	_cloud_target = clouds
	_apply_sphere()


## World direction toward the primary at rotation phase s (the spin axis is world +Y).
static func sphere_sun_dir(s: float, decl: float = SPHERE_DECL) -> Vector3:
	return Vector3(sin(s) * cos(decl), sin(decl), cos(s) * cos(decl)).normalized()


## Local time 0..1 (0.5 = noon) at a point for a rotation phase.
static func local_time_at(s: float, p: Vector3) -> float:
	return fposmod(0.5 + (s - atan2(p.x, p.z)) / TAU, 1.0)


## The rotation phase that gives local time t at point p (inverse of local_time_at).
static func spin_for_local_time(t: float, p: Vector3) -> float:
	return fposmod(atan2(p.x, p.z) + (t - 0.5) * TAU, TAU)


## The full moon: opposite the suns, a little off the ecliptic, so the night side has its light.
static func sphere_moon_dir(s: float) -> Vector3:
	return -sphere_sun_dir(s + 0.18, SPHERE_DECL * 0.4)


## Companion direction: the primary turned about the spin axis by the separation, so both rise
## and set together (BinarySun.companion_dir on the flat sky).
func companion_dir(s1: Vector3) -> Vector3:
	return s1.rotated(Vector3.UP, deg_to_rad(BinarySun.separation_of(_suns))).normalized()


func _player_pos() -> Vector3:
	return player_fn.call() if player_fn.is_valid() else Vector3(0, planet_radius, 0)


func _process_sphere(delta: float) -> void:
	if _tod_out >= 0.0 and absf(time_of_day - _tod_out) > 0.0005:  # someone set the clock
		spin = spin_for_local_time(time_of_day, _player_pos())
	if not frozen:
		spin = fposmod(spin + TAU * delta / day_period_s * CradleMode.day_speed(time_of_day) * Glim.clock_mult(time_of_day), TAU)
		GameState.flags["orbit_spin"] = spin
	_clean_t -= delta  # clean_fn walks every cell (164k+): ask every few seconds, haze eases anyway
	if _clean_t <= 0.0:
		_clean_t = 4.0
		_clean = float(clean_fn.call()) if clean_fn.is_valid() else 0.0
	var clean: float = _clean
	var target: float = 1.0 - clampf(clean * 8.0 + float(GameState.stats.get("air_filtered", 0.0)) * 0.0005 + clear_bonus, 0.0, 0.85)
	haze = lerpf(haze, target, clampf(delta * 0.2, 0.0, 1.0))
	_cloud_t += delta
	if not weather_frozen:
		_weather_t -= delta
		if _weather_t <= 0.0:  # a new spell of weather every few minutes
			_weather_t = randf_range(150.0, 360.0)
			_cloud_target = clampf(randf_range(0.1, 0.75) + (haze - 0.5) * 0.1, 0.05, 0.85)
		clouds = move_toward(clouds, _cloud_target, delta * 0.004)
		GameState.flags["orbit_clouds"] = clouds
	_apply_sphere()


func _apply_sphere() -> void:
	if env == null or sky_shader == null:
		return
	var p: Vector3 = _player_pos()
	var u: Vector3 = p.normalized()
	time_of_day = local_time_at(spin, p)
	_tod_out = time_of_day
	GameState.flags["time_of_day"] = time_of_day
	var s1: Vector3 = sphere_sun_dir(spin)
	var s2: Vector3 = companion_dir(s1)
	var m: Vector3 = sphere_moon_dir(spin)
	var e1: float = s1.dot(u)
	var sun_up: float = smoothstep(-0.03, 0.2, e1)
	var comp_up: float = smoothstep(-0.03, 0.2, s2.dot(u))
	var moon_up: float = smoothstep(-0.04, 0.16, m.dot(u))
	var day: float = maxf(sun_up, comp_up * 0.8)
	daylight = day
	var night: float = 1.0 - day
	var lift: float = night_lift() * night
	var nd: float = clampf(night_dark, 0.0, 1.0) * night
	# Primary: warm and low at dawn and dusk, white at noon; it carries the shadows.
	sun.global_basis = _toward_dir(s1)
	sun.light_energy = 2.2 * sun_up * float(_suns["a"].get("energy", 1.0)) * (1.0 - 0.55 * storm)
	# [v5look] Dusty air warms the noon sun (flat Verdance's golden light); it whitens as the air clears.
	var noon_col: Color = Color(1.0, 0.95, 0.87).lerp(Color(1.0, 0.92, 0.79), haze)
	sun.light_color = Color(1.0, 0.66, 0.4).lerp(noon_col, smoothstep(0.08, 0.5, e1))
	sun.visible = sun.light_energy > 0.01
	companion.global_basis = _toward_dir(s2)
	companion.light_energy = 3.0 * float(_suns["b"].get("energy", 0.25)) * comp_up * (1.0 - 0.55 * storm)
	companion.visible = companion.light_energy > 0.01
	# The moon: soft cool light on the night side, a little brighter until nights are learned.
	moon.global_basis = _toward_dir(m)
	moon.light_energy = (0.38 + 0.3 * lift) * moon_up * night * (1.0 - 0.45 * nd)
	moon.visible = moon.light_energy > 0.01
	var e: Vector3 = eye_fn.call() if eye_fn.is_valid() else p
	var space: bool = bool(space_fn.call()) if space_fn.is_valid() else false
	sky_shader.set_shader_parameter("up_dir", e.normalized())
	sky_shader.set_shader_parameter("eye_pos", e)
	sky_shader.set_shader_parameter("sun1_dir", s1)
	sky_shader.set_shader_parameter("sun2_dir", s2)
	sky_shader.set_shader_parameter("moon_dir", m)
	sky_shader.set_shader_parameter("day", day)
	sky_shader.set_shader_parameter("star_phi", spin)
	sky_shader.set_shader_parameter("space", 1.0 if space else 0.0)
	sky_shader.set_shader_parameter("haze", haze)
	sky_shader.set_shader_parameter("clouds", clouds)
	sky_shader.set_shader_parameter("cloud_t", _cloud_t)
	sky_shader.set_shader_parameter("storm", clampf(storm, 0.0, 1.0))
	sky_shader.set_shader_parameter("night_lift", night_lift())
	sky_shader.set_shader_parameter("night_dark", clampf(night_dark, 0.0, 1.0))
	# Ambient and exposure: the night side keeps a readable blue fill (owner: nights not too dark).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = lerpf(0.85, 1.1, day) * (1.0 + 0.45 * lift) * (1.0 - 0.4 * nd)
	# [v5look] By day the fill is part sky, part warm bounce off the dusty ground (the blue sky
	# alone gave cold, hard shadows next to flat Verdance); at night the blue fill as before.
	env.ambient_light_sky_contribution = lerpf(0.3, 0.6, day)
	var low_sun: float = day * (1.0 - smoothstep(0.1, 0.45, maxf(e1, 0.0)))  # dawn and dusk
	var amb_day: Color = Color(0.8, 0.86, 0.96).lerp(Color(0.97, 0.9, 0.78), haze).lerp(Color(1.0, 0.72, 0.56), low_sun * 0.5)
	var amb := Color(0.36, 0.44, 0.62).lerp(amb_day, day)
	if night_tint.a > 0.0:
		amb = amb.lerp(Color(night_tint.r, night_tint.g, night_tint.b), night_tint.a * night * 0.5)
	env.ambient_light_color = amb
	env.tonemap_exposure = lerpf(1.55, 1.25, day) * (1.0 + 0.15 * lift) * (1.0 - 0.2 * nd)
	# Fog: dusty and warm in Act 1, clear blue as the air is scrubbed, deep blue at night.
	env.fog_enabled = not space
	# Volumetric fog is for the flat district's short distances: the quality pass turns it on at
	# Medium+ with Godot's default density (0.05), which washed the globe and its sky flat grey
	# (owner: vivid blue sky with the two suns, not haze). Plain depth fog does the aerial haze.
	env.volumetric_fog_enabled = false
	env.fog_density = lerpf(0.0005, 0.0017, haze) * fog_scale  # [v5look] a real haze in Act 1
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = lerpf(1.12, 1.24, day)
	env.adjustment_contrast = lerpf(1.06, 1.1, day)
	# [v5look] Warm golden haze (flat Verdance's fog), orange toward dawn and dusk. The sky shader
	# paints its horizon band in this same colour, so far land fades into the sky, not against it.
	var fog_day: Color = Color(0.62, 0.75, 0.94).lerp(Color(0.97, 0.86, 0.71), haze * 0.85)
	fog_day = fog_day.lerp(Color(0.96, 0.62, 0.42), low_sun * 0.55)
	var fog_night: Color = Color(0.11, 0.14, 0.22) * (1.0 + 0.6 * lift)
	if night_tint.a > 0.0:
		fog_night = fog_night.lerp(Color(night_tint.r, night_tint.g, night_tint.b) * 0.4, night_tint.a)
	env.fog_light_color = fog_night.lerp(fog_day, day)
	env.fog_sky_affect = 0.0
	if storm > 0.0:
		var st: float = clampf(storm, 0.0, 1.0)
		env.fog_light_color = env.fog_light_color.lerp(Color(0.78, 0.6, 0.4) * lerpf(0.35, 1.0, day), st * 0.85)
		env.fog_density = lerpf(env.fog_density, 0.012, st)
	sky_shader.set_shader_parameter("fog_col", env.fog_light_color)  # [v5look]


static func _toward_dir(d: Vector3) -> Basis:
	var ref: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	return Basis.looking_at(-d, ref)
