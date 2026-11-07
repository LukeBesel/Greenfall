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
var _t: float = 99.0
var _level: int = -1


static func attach(slice: Node) -> WorldLookView:
	var lk: Dictionary = WorldLook.current()
	if lk.is_empty():
		return null
	var v := WorldLookView.new()
	v.name = "WorldLookView"
	v.world = slice
	v.look = lk
	slice.add_child(v)
	v._setup()
	return v


func _setup() -> void:
	var frontier: bool = world.get("frontier") != null
	var sd: SkyDirector = world.get("sky_director")
	if sd:
		sd.night_dark = float(look.get("night_dark", 0.0))
		if not frontier:
			sd.grade = look.get("grade", {})
	if look.has("sky_body") and sd:
		sky_body = SkyBody.make(look["sky_body"], sd)
		world.add_child(sky_body)
	if frontier:
		return
	var wc: Dictionary = (look.get("city", {}) as Dictionary).get("weather", {})
	if not wc.is_empty():
		weather = make_weather(wc)
		_coat_city()
	var lk: String = WorldLook.landmark(look)
	if lk != "" and world.get("layout") != null:
		var seed_v: int = CradleMode.world_seed() if not CradleMode.profile.is_empty() else 1
		var at: Vector3 = WorldLandmark.find_spot(world.layout, world.field, seed_v + int(GameState.current_hub) * 31)
		var yaw: float = atan2(-at.x, -at.z) + PI  # broadside toward the base
		landmark = WorldLandmark.make(lk, at, yaw, seed_v, _hub_level())
		world.add_child(landmark)
		if weather:
			landmark.set_overlay(weather)
		print("[worlds2] %s landmark '%s' at (%.0f, %.0f)" % [str(look.get("type", "")), lk, at.x, at.z])
	_update()


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
	if sd and world.get("frontier") == null:
		sd.grade_amt = WorldLook.grade_amount(look, progress)
		sd.storm = float(look.get("dust", 0.0)) * (1.0 - progress)
	if weather:
		weather.set_shader_parameter("amount", WorldLook.weather_amount(progress))
	if landmark and lv != _level:
		landmark.set_level(lv)
	_level = lv
