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
	time_of_day = float(GameState.flags.get("time_of_day", 0.32))


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
	if not frozen:
		time_of_day = fmod(time_of_day + delta / DAY_LENGTH_S, 1.0)
		GameState.flags["time_of_day"] = time_of_day
	if world and world.get("planet") != null:
		var target: float = 1.0 - clampf(world.planet.restored_fraction() * 8.0 + float(GameState.stats.get("air_filtered", 0.0)) * 0.0005 + clear_bonus, 0.0, 0.85)
		haze = lerpf(haze, target, clampf(delta * 0.2, 0.0, 1.0))
	_apply()


func _apply() -> void:
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
	if not grade.is_empty() or storm > 0.0:
		_apply_grade(sun_up)


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
