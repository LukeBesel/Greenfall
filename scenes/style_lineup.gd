extends Node3D
## [style] Lineup renderer for Character Builder looks (systems/lumi_style.gd): four custom looks
## side by side on the turnaround set.
##   godot --path . --rendering-driver vulkan res://scenes/style_lineup.tscn -- --fresh --out=screenshots/style_lineup
## Writes <out>_0.png (front 3/4, with names), <out>_1.png (faces close-up), <out>_2.png (back 3/4).

const LOOKS: Array[Dictionary] = [
	{"name": "Stargazer", "paint": "#1b2233", "trim": "#5c6169", "accent": "#ffd34d", "side": "#ffd34d", "eyes": "#ffd34d", "glow": "#ffd34d", "hover": "#7fb8ff", "laser": "#ffd34d",
		"eye_shape": "round", "head": "halo", "chest": "heart", "held": "none", "shoulders": "none", "companion": "firefly", "pattern": "plain", "wear": 0.2},
	{"name": "Gardener", "paint": "#ede8e0", "trim": "#54593a", "accent": "#85ff5c", "side": "#78873b", "eyes": "#85ff5c", "glow": "#85ff5c", "hover": "#85ff5c", "laser": "#6fe3b0",
		"eye_shape": "happy", "head": "sprout", "chest": "leaf", "held": "watering_can", "shoulders": "none", "companion": "butterfly", "pattern": "moss", "wear": 0.55},
	{"name": "Field Medic", "paint": "#f2efe8", "trim": "#3a3f47", "accent": "#cc2624", "side": "#cc2624", "eyes": "#ff5480", "glow": "#ff5480", "hover": "#ff5480", "laser": "#ff5480",
		"eye_shape": "heart", "head": "catears", "chest": "cross", "held": "medkit", "shoulders": "none", "companion": "drone", "pattern": "plain", "wear": 0.3},
	{"name": "Racer", "paint": "#3d63ff", "trim": "#292630", "accent": "#ff801f", "side": "#ff801f", "eyes": "#4de0ff", "glow": "#4de0ff", "hover": "#ff801f", "laser": "#ff801f",
		"eye_shape": "bar", "head": "antenna", "chest": "recycle", "held": "gear", "shoulders": "pads", "companion": "none", "pattern": "stripes", "wear": 0.65},
]

var _cam: Camera3D
var _views: Array = []
var _i: int = -1
var _t: float = 0.0
var _out: String


static func look_style(i: int) -> Dictionary:
	var d: Dictionary = LOOKS[i]
	var s: Dictionary = LumiStyle.preset("aurora")
	for k: String in d:
		if k != "name":
			LumiStyle.set_value(s, k, d[k])
	s["name"] = str(d["name"])
	return s


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/style_lineup")
	LumiStyle.dev_all = true
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.turbidity = 12.0
	sm.mie_coefficient = 0.01
	sm.mie_color = Color(0.86, 0.72, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.75, 0.66, 0.58)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 1.3
	rim.light_color = Color(0.65, 0.85, 1.0)
	rim.light_specular = 1.2
	add_child(rim)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.material = AssetLib.pbr_material("road_damaged", 8.0)
	ground.mesh = pm
	add_child(ground)
	var gap: float = 1.45
	var n: int = LOOKS.size()
	for k: int in n:
		var st: Dictionary = look_style(k)
		var m := PatchModel.new()
		m.set_meta("lumi_style", st)
		m.preview_variant = "aurora"
		m.position = Vector3(((n - 1) * 0.5 - k) * gap, 0.0, 0.0)
		m.rotation.y = 0.3
		add_child(m)
		m.set_happy(0.6)
		var l := Label3D.new()
		l.text = str(LOOKS[k]["name"]).to_upper()  # dev render: English names
		l.pixel_size = 0.0022
		l.font_size = 30
		l.modulate = LumiStyle.col(st, "glow").lightened(0.3)
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.7)
		l.position = m.position + Vector3(0, 1.7, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	_cam = Camera3D.new()
	_cam.fov = 36.0
	add_child(_cam)
	_cam.current = true
	_views = [
		[Vector3(0.7, 1.35, -6.4), Vector3(0, 0.8, 0), 36.0],
		[Vector3(0.3, 0.95, -4.6), Vector3(0, 0.85, 0), 24.0],
		[Vector3(-1.2, 1.5, 6.2), Vector3(0, 0.72, 0), 36.0],
	]


func _process(delta: float) -> void:
	_t += delta
	if _i < 0:
		if _t < 7.0:
			_set_view(0)
			return
		_i = 0
		_t = 0.0
	if _i >= _views.size():
		get_tree().quit()
		return
	_set_view(_i)
	if _t > 1.5:
		DevHooks.save_viewport("%s_%d.png" % [_out, _i])
		_i += 1
		_t = 0.0


func _set_view(i: int) -> void:
	var v: Array = _views[i]
	_cam.position = v[0]
	_cam.fov = v[2]
	_cam.look_at(v[1], Vector3.UP)
	for c: Node in get_children():
		if c is Label3D:
			(c as Label3D).visible = i == 0
