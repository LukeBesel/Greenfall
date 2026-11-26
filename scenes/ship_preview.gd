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
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true
	match _view:
		"hero":
			_hero()
		"solo":
			var t1: int = int(DevHooks.get_f("ship-tier", 1.0))
			_row([t1] as Array[int], 0.0, 32.0)
			_cam.fov = 30.0
			_cam.position = Vector3(-1.5, 4.2, 12.5)
			_cam.look_at(Vector3(0.3, 0.9, 0.4), Vector3.UP)
		"ark", "ark_below":
			var ark := CradleShip.new()
			add_child(ark)
			ark.position = Vector3(0, 14.0, 0)
			_cam.fov = 38.0
			if _view == "ark":
				_cam.position = Vector3(-52.0, 32.0, -46.0)
				_cam.look_at(Vector3(0, 13.0, 1.0), Vector3.UP)
			else:
				var under := DirectionalLight3D.new()  # light the belly and the pod rack
				under.rotation_degrees = Vector3(55, 30, 0)
				under.light_energy = 1.3
				under.light_color = Color(0.85, 0.9, 1.0)
				add_child(under)
				_cam.position = Vector3(40.0, -18.0, -46.0)
				_cam.look_at(Vector3(0, 9.0, -1.0), Vector3.UP)
		"pair":
			var w2: float = _row([1, 7] as Array[int], 10.5, 32.0)
			_frame(w2, 27.0, 26.0)
		"lineup":
			var w: float = _row(LINEUP, 9.6, 32.0)
			_frame(w, 57.0, 24.0)
		_:
			_lineup()
	if _out == "":
		_self_check()
		get_tree().quit()


func _env() -> void:
	if _view in ["lineup", "pair", "solo", "ark", "ark_below"]:
		_studio()
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.turbidity = 4.0
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
	env.fog_density = 0.0008
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


## Dark studio for the lineup and the pair: deep blue-black, a warm key, a cool rim, glossy floor.
func _studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.03, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.44)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 28, 0)
	key.light_energy = 2.0
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 120.0
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 200, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.55, 0.8, 1.0)
	rim.light_specular = 0.4
	add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -70, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.8, 0.85, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.05, 0.055, 0.065)
	gm.roughness = 0.85
	gm.metallic = 0.0
	gm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED  # the rim light glinting off the floor bloomed across the frame
	pm.material = gm
	ground.mesh = pm
	if not _view.begins_with("ark"):
		add_child(ground)


## Display scale: every tier at roughly the same screen size (the growth shows in the parts).
static func _disp_scale(t: int) -> float:
	var e: Vector2 = ShipModel.extent(t)
	return 8.0 / maxf(e.x, e.y * 2.0) * (1.0 + 0.04 * float(t - 1))


func _row(tiers: Array[int], spacing: float, yaw_deg: float) -> float:
	for i: int in tiers.size():
		var t: int = tiers[i]
		var m := ShipModel.new()
		add_child(m)
		m.build(t)
		var sc: float = _disp_scale(t)
		m.scale = Vector3.ONE * sc
		m.rotation.y = deg_to_rad(yaw_deg)
		var e: Vector2 = ShipModel.extent(t)
		var centre_z: float = (3.1 + ShipModel.front_shift(t) - e.x * 0.5) * sc
		m.position = Vector3(i * spacing, 0, 0) - Basis(Vector3.UP, m.rotation.y) * Vector3(0, 0, centre_z)
		var l := Label3D.new()
		l.text = ShipTiers.mark(t)
		l.font_size = 110
		l.pixel_size = 0.009
		l.modulate = Color(0.4, 1.0, 1.4)
		l.outline_size = 0
		l.shaded = false
		l.rotation_degrees = Vector3(-22, 0, 0)
		l.position = Vector3(i * spacing, 0.5, 5.4)
		add_child(l)
	return (tiers.size() - 1) * spacing


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
		l.position = Vector3(x, 0.02, (3.1 + ShipModel.front_shift(t) * 0.5) * sc + 1.8)
		add_child(l)
	var left: float = centres[0] - ShipModel.extent(LINEUP[0]).y * ShipTiers.scale_of(LINEUP[0])
	var mid: float = (left + x + prev_half) * 0.5
	var w: float = x + prev_half - left
	if _view == "top":
		_cam.position = Vector3(mid, w * 1.1, 4.0)
		_cam.look_at(Vector3(mid, 0, 0), Vector3.FORWARD)
	else:
		_cam.fov = 26.0
		var d: float = w * 1.32
		var az: float = deg_to_rad(DevHooks.get_f("az", 4.0))
		var el: float = deg_to_rad(DevHooks.get_f("el", 15.0))
		var tgt := Vector3(mid, 0.4, 2.0)
		_cam.position = tgt + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * d
		_cam.look_at(tgt, Vector3.UP)


func _frame(w: float, dist: float, fov: float) -> void:
	_cam.fov = fov
	var tgt := Vector3(w * 0.5, 0.9, 0.6)
	_cam.position = tgt + Vector3(0, dist * 0.42, dist)
	_cam.look_at(tgt, Vector3.UP)


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
