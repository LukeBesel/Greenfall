extends GutTest
## [orbE] SkyDirector's round-planet mode: the local clock follows the spin and the player's
## longitude, the inverse sets it back, the moon lights the night side, nights stay readable
## (ambient and exposure never drop to the flat sky's darkest), and the radius comes from the
## planet (globes differ in size).

var _flags: Dictionary
var _sd: SkyDirector
var _pos := Vector3(0, 1840, 0)


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}
	_sd = SkyDirector.new()
	add_child_autofree(_sd)


func after_each() -> void:
	GameState.flags = _flags


func _setup(radius: float, p: Vector3, t: float) -> void:
	_pos = p
	var env := Environment.new()
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://planet/orbit/orbit_sky.gdshader")
	_sd.player_fn = func() -> Vector3: return _pos
	_sd.weather_frozen = true
	_sd.setup_sphere(env, sun, mat, radius, t)


func test_local_time_round_trip() -> void:
	var p := Vector3(0.3, 0.8, -0.5).normalized() * 1840.0
	for t: float in [0.0, 0.1, 0.25, 0.5, 0.8, 0.99]:
		var s: float = SkyDirector.spin_for_local_time(t, p)
		assert_almost_eq(SkyDirector.local_time_at(s, p), t, 0.0001)


func test_noon_sun_overhead_and_quarter_lap_is_six_hours() -> void:
	var p := Vector3(0, 0, 1840)  # on the equator
	var s: float = SkyDirector.spin_for_local_time(0.5, p)
	assert_gt(SkyDirector.sphere_sun_dir(s).dot(p.normalized()), 0.9, "noon: sun high")
	var east := Vector3(1840, 0, 0)  # a quarter of the way round
	var dt: float = absf(SkyDirector.local_time_at(s, east) - 0.5)
	assert_almost_eq(dt, 0.25, 0.001)


func test_moon_on_the_night_side() -> void:
	var p := Vector3(0, 0, 1840)
	var s: float = SkyDirector.spin_for_local_time(0.0, p)  # midnight
	assert_gt(SkyDirector.sphere_moon_dir(s).dot(p.normalized()), 0.5)
	assert_lt(SkyDirector.sphere_sun_dir(s).dot(p.normalized()), 0.0)


func test_night_is_readable_and_day_is_lit() -> void:
	_setup(1840.0, Vector3(0, 0, 1840), 0.0)
	assert_almost_eq(_sd.time_of_day, 0.0, 0.001)
	assert_lt(_sd.daylight, 0.05)
	assert_gt(_sd.moon.light_energy, 0.3, "moonlight on the night side")
	assert_gt(_sd.env.ambient_light_energy, 0.85)
	assert_gt(_sd.env.tonemap_exposure, 1.5)
	_sd.time_of_day = 0.5  # photo mode / --time move the planet so the player's spot gets it
	_sd._process(0.0)
	assert_almost_eq(_sd.time_of_day, 0.5, 0.001)
	assert_gt(_sd.daylight, 0.95)
	assert_gt(_sd.sun.light_energy, 1.5)
	assert_false(_sd.moon.visible)


func test_clock_saves_and_advances() -> void:
	_setup(1840.0, Vector3(0, 0, 1840), 0.3)
	_sd.day_period_s = 100.0
	var t0: float = _sd.time_of_day
	_sd._process(10.0)
	assert_true(GameState.flags.has("orbit_spin"))
	assert_gt(_sd.time_of_day, t0)
	var spin: float = float(GameState.flags["orbit_spin"])
	var sd2 := SkyDirector.new()
	add_child_autofree(sd2)
	sd2.player_fn = func() -> Vector3: return _pos
	var sun := DirectionalLight3D.new()
	add_child_autofree(sun)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://planet/orbit/orbit_sky.gdshader")
	sd2.setup_sphere(Environment.new(), sun, mat, 1840.0)  # no forced time: restore from the save
	assert_almost_eq(sd2.spin, spin, 0.0001)


func test_radius_comes_from_the_planet() -> void:
	_setup(2484.0, Vector3(0, 2484, 0), 0.5)  # Anvil-sized globe
	assert_almost_eq(float(_sd.sky_shader.get_shader_parameter("planet_r")), 2484.0, 0.01)
	assert_almost_eq(_sd.planet_radius, 2484.0, 0.01)


func test_one_turn_per_day_period() -> void:
	_setup(1840.0, Vector3(0, 0, 1840), 0.3)
	_sd.day_period_s = 1000.0
	Glim.set_found(true)  # no early-day clock multiplier
	var s0: float = _sd.spin
	for i: int in 100:
		_sd._process(1.0)  # 100 s = a tenth of a turn
	var turned: float = fposmod(_sd.spin - s0, TAU) / TAU
	assert_almost_eq(turned, 0.1, 0.01, "the spin is the only clock (daytime, Glim found)")
