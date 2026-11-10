class_name WorldLookView
extends Node
## [worlds2] Puts a Cradle Mode world's look (systems/world_look.gd, data/world_looks.json) into a
## district: the sky grade and dust (planet/sky_director.gd), Long Nights' darker nights, a body
## in the sky (planet/sky_body.gd), the landmark (planet/world_landmark.gd) and the weathering
## overlay on the city (art/shaders/world_weather.gdshader). The grade, dust and weathering ease
## off as the district is restored (WorldLook.progress), so a world starts in its own ruined
## weather and clears into bright air. Attached by systems/late_director.gd; Verdance gets none.
## Frontier districts keep their own grade and landmarks (only the sky body and nights carry over).

var world: Node
var look: Dictionary = {}
var landmark: WorldLandmark
var sky_body: SkyBody
var weather: ShaderMaterial
var progress: float = 0.0
## [worlds2] A planet's own environment (data/planets.json -> planet/planets/<id>/env.gd): when it
## exists it owns the planet's art (landmarks, sky bodies, props) and this view keeps only the
## data-driven sky grade, Long Nights, the city tint and weathering. Its entry point is
## `apply(world, field, kind)` with kind "city" | "wild".
var env_script: String = ""
var env: Object
var _t: float = 99.0
var _level: int = -1


static func attach(slice: Node) -> WorldLookView:
	var lk: Dictionary = WorldLook.current()
	var env: String = WorldLook.env_path(WorldLook.planet_id())
	if lk.is_empty() and env == "":
		return null
	var v := WorldLookView.new()
	v.name = "WorldLookView"
	v.world = slice
	v.look = lk
	v.env_script = env
	slice.add_child(v)
	v._setup()
	return v


func _setup() -> void:
	if env_script != "":
		_apply_env()
	var sd: SkyDirector = world.get("sky_director")
	if sd:
		sd.night_dark = float(look.get("night_dark", 0.0))
		sd.grade = look.get("grade", {})
	if look.has("sky_body") and sd and (env == null or bool(look.get("keep_sky_body", false))):
		sky_body = SkyBody.make(look["sky_body"], sd)
		world.add_child(sky_body)
	var wc: Dictionary = (look.get("city", {}) as Dictionary).get("weather", {})
	if not wc.is_empty():
		weather = make_weather(wc)
		_coat_city()
	var lk: String = WorldLook.landmark(look)
	if lk != "" and world.get("layout") != null and (env == null or bool(look.get("keep_landmark", false))):
		var seed_v: int = CradleMode.world_seed() if not CradleMode.profile.is_empty() else 1
		var at: Vector3 = WorldLandmark.find_spot(world.layout, world.field, seed_v + int(GameState.current_hub) * 31)
		var yaw: float = atan2(-at.x, -at.z) + PI  # broadside toward the base
		landmark = WorldLandmark.make(lk, at, yaw, seed_v, _hub_level())
		world.add_child(landmark)
		if weather:
			landmark.set_overlay(weather)
		print("[worlds2] %s landmark '%s' at (%.0f, %.0f)" % [str(look.get("type", "")), lk, at.x, at.z])
	_update()


## Runs the planet's env script: an instance (a Node joins the district) with apply(world, field, kind).
func _apply_env() -> void:
	var sc: Script = load(env_script) as Script
	if sc == null:
		push_warning("[worlds2] planet env script failed to load: %s" % env_script)
		return
	var lay: Variant = world.get("layout")
	var kind: String = "wild" if lay is CityLayout and (lay as CityLayout).wild else "city"
	# [main] Planet envs (planet/planets/*/env.gd) use a STATIC apply(world, field, kind_def: Dictionary)
	# that builds its own node. Call that once (HomewardDirector may already have) instead of
	# instancing the script: a bare instance has no field and errors every frame.
	if _has_static_apply(sc):
		if not world.has_meta("planet_env_applied"):
			world.set_meta("planet_env_applied", true)
			sc.call("apply", world, world.get("field"), Frontiers.def(Frontiers.world_kind(world)))
		print("[worlds2] planet env %s (static)" % env_script)
		return
	env = sc.new()
	if env is Node:
		(env as Node).name = "PlanetEnv"
		world.add_child(env as Node)
	if env.has_method("apply"):
		env.call("apply", world, world.get("field"), kind)
	print("[worlds2] planet env %s (%s)" % [env_script, kind])


static func _has_static_apply(sc: Script) -> bool:
	for m: Dictionary in sc.get_script_method_list():
		if str(m.get("name", "")) == "apply" and (int(m.get("flags", 0)) & METHOD_FLAG_STATIC) != 0:
			return true
	return false


## The weathering overlay from a look's city.weather block.
static func make_weather(wc: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/world_weather.gdshader")
	m.set_shader_parameter("coat", WorldLook.col(wc.get("coat", []), Color(0.9, 0.9, 0.9)))
	m.set_shader_parameter("top_amt", float(wc.get("top", 0.6)))
	m.set_shader_parameter("film", float(wc.get("film", 0.08)))
	m.set_shader_parameter("low_col", WorldLook.col(wc.get("low", []), Color(0.4, 0.4, 0.4)))
	m.set_shader_parameter("low_amt", float(wc.get("low_amt", 0.0)))
	m.set_shader_parameter("low_h", float(wc.get("low_h", 1.5)))
	m.set_shader_parameter("streak_col", WorldLook.col(wc.get("streak", []), Color(0.4, 0.3, 0.2)))
	m.set_shader_parameter("streak_amt", float(wc.get("streak_amt", 0.0)))
	m.render_priority = 1
	return m


## Every building, skyline and street mesh of the city wears the coat (not the yard dressing:
## the base is where Lumi keeps things tidy).
func _coat_city() -> void:
	var city: Node = world.get("city")
	if city == null:
		return
	var stack: Array[Node] = [city]
	var n: int = 0
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c: Node in nd.get_children():
			stack.append(c)
		if nd is GeometryInstance3D and (nd as GeometryInstance3D).material_overlay == null:
			(nd as GeometryInstance3D).material_overlay = weather
			n += 1
	print("[worlds2] weathering on %d city meshes (%s)" % [n, WorldLook.city_style(look)])


func _hub_level() -> int:
	var h: Variant = world.get("hub")
	if h is Hub:
		return int((h as Hub).level)
	return int(GameState.world.get("hub_level", 1))


func _process(delta: float) -> void:
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	_update()


func _update() -> void:
	var f: HexField = world.get("field")
	var frac: float = float(f.cleaned_count) / float(maxi(f.junk_hex_count, 1)) if f else 0.0
	var lv: int = _hub_level()
	progress = WorldLook.progress(lv, frac)
	var sd: SkyDirector = world.get("sky_director")
	if sd:
		sd.grade_amt = WorldLook.grade_amount(look, progress)
		sd.storm = float(look.get("dust", 0.0)) * (1.0 - progress)
	if weather:
		weather.set_shader_parameter("amount", WorldLook.weather_amount(progress))
	if env and env.has_method("set_progress"):  # planet env scripts may follow restoration too
		env.call("set_progress", progress, lv)
	if landmark and lv != _level:
		landmark.set_level(lv)
	_level = lv
