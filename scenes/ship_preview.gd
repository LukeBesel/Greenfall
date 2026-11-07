extends Node3D
## [ship] Quick look at Lumi's ship without loading a district (fast on software Vulkan). Usage:
##   godot --path . --rendering-driver vulkan res://scenes/ship_preview.tscn -- --ship-view=lineup --out=screenshots/ship_lineup
## Views: lineup (Mk I, IV, V, VI, VII side by side), hero (Mk I on its pad, 3/4), top (lineup from
## above). --ship-tier=N picks the hero's look; --wait=S wall seconds before the shot.
## Headless (no --out): builds every look, checks parts and prints a summary, then quits.

const LINEUP: Array[int] = [1, 4, 5, 6, 7]

var _cam: Camera3D
var _t: float = 0.0
var _out: String
var _view: String


func _ready() -> void:
	_out = DevHooks.get_s("out", "")
	_view = DevHooks.get_s("ship-view", "lineup")
	_env()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true
	match _view:
		"hero":
			_hero()
		_:
			_lineup()
	if _out == "":
		_self_check()
		get_tree().quit()


func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.turbidity = 6.0
	sm.mie_coefficient = 0.004
	sm.ground_color = Color(0.5, 0.52, 0.55)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	env.fog_enabled = true
	env.fog_density = 0.0025
	env.fog_light_color = Color(0.78, 0.83, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.85, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.56, 0.57, 0.58)
	gm.roughness = 0.55
	gm.metallic = 0.05
	pm.material = gm
	ground.mesh = pm
	add_child(ground)


func _lineup() -> void:
	var x: float = 0.0
	var prev_half: float = 0.0
	var centres: Array[float] = []
	for i: int in LINEUP.size():
		var t: int = LINEUP[i]
		var sc: float = ShipTiers.scale_of(t)
		var half: float = ShipModel.extent(t).y * sc
		if i > 0:
			x += prev_half + half + 1.2
		prev_half = half
		var m := ShipModel.new()
		add_child(m)
		m.build(t)
		m.scale = Vector3.ONE * sc
		m.position = Vector3(x, 0, -ShipModel.front_shift(t) * sc * 0.5)
		centres.append(x)
		var l := Label3D.new()
		l.text = ShipTiers.mark(t)
		l.font_size = 120
		l.pixel_size = 0.01
		l.modulate = Color(0.35, 0.9, 1.3)
		l.shaded = false
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.position = Vector3(x, 0.02, 6.0 + ShipModel.front_shift(t) * sc * 0.5)
		add_child(l)
	var mid: float = (centres[0] + centres[-1]) * 0.5
	if _view == "top":
		_cam.position = Vector3(mid, 70.0, 6.0)
		_cam.look_at(Vector3(mid, 0, 0), Vector3.FORWARD)
	else:
		_cam.fov = 30.0
		_cam.position = Vector3(mid + 16.0, 24.0, 62.0)
		_cam.look_at(Vector3(mid + 1.0, 1.0, 0.0), Vector3.UP)


func _hero() -> void:
	var r := Rocket.new()
	add_child(r)
	r.setup(true)
	var mp: Vector3 = r.model.global_position
	var nose: Vector3 = Basis(Vector3.UP, Rocket.PARK_YAW) * Vector3(0, 0, 1)
	var side: Vector3 = Basis(Vector3.UP, Rocket.PARK_YAW) * Vector3(1, 0, 0)
	var k: float = ShipTiers.scale_of(r.look)
	_cam.fov = 34.0
	_cam.position = mp + (nose * 10.5 - side * 6.5) * k + Vector3(0, 3.0 * k, 0)
	_cam.look_at(mp + nose * 0.6 * k + Vector3(0, 1.0 * k, 0), Vector3.UP)


func _self_check() -> void:
	for t: int in range(1, ShipTiers.MAX_LOOK + 1):
		var m := ShipModel.new()
		add_child(m)
		m.build(t)
		var meshes: int = m.find_children("*", "MeshInstance3D", true, false).size()
		var plumes: int = m.find_children("*", "RocketPlume", true, false).size()
		print("[ship] look %d: %d meshes, %d plumes, canopy=%s, parts=%s" % [t, meshes, plumes, m.hatch != null, ",".join(ShipTiers.parts_for(t))])
	var pad := LaunchPad.new()
	pad.look = 7
	add_child(pad)
	print("[ship] pad radius at Mk VII: %.2f" % pad.radius())


func _process(delta: float) -> void:
	_t += delta
	if _out == "":
		return
	if _t > DevHooks.get_f("wait", 6.0):
		DevHooks.save_viewport("%s.png" % _out)
		get_tree().quit()
