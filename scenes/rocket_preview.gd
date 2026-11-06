extends Node3D
## Quick look at the rocket, its pad and the launch effects without loading a district (fast to
## render on software Vulkan). Usage:
##   godot --path . --rendering-driver vulkan res://scenes/rocket_preview.tscn -- --rocket-tier=2 --out=screenshots/rp
## Saves <out>_N.png: pad at rest (wide), countdown steam, ignition (low), lift-off, climb, construction hologram.

var _rocket: Rocket
var _holo: LaunchPad
var _cam: Camera3D
var _views: Array = []
var _i: int = -1
var _t: float = 0.0
var _out: String


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/rocket_preview")
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
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.78, 0.74, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 2.0
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	pm.material = AssetLib.pbr_material("road_damaged", 20.0)
	ground.mesh = pm
	add_child(ground)
	_rocket = Rocket.new()
	add_child(_rocket)
	_rocket.setup(true)
	_rocket._build_fx()
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true
	var hy: float = LaunchPad.TOP_Y
	_views = [
		["rest", Vector3(11.0, 3.4, 14.0), Vector3(0, 5.5, -1.0)],
		["steam", Vector3(5.8, 1.5, 3.6), Vector3(-0.6, 5.0, 0)],
		["ignite", Vector3(6.0, 0.9, 3.8), Vector3(0, 2.0, 0)],
		["liftoff", Vector3(8.5, 1.0, 3.8), Vector3(0, 9.0, 0)],
		["climb", Vector3(-14.0, 4.0, 34.0), Vector3(3.0, 40.0, -2.0)],
		["holo", Vector3(11.0, 3.4, 14.0), Vector3(0, 5.5, -1.0)],
	]
	_set_state("rest")
	print("[preview] tier=%d deck=%.2f" % [_rocket.tier, hy])


func _set_state(s: String) -> void:
	var m: RocketModel = _rocket.model
	var pad: LaunchPad = _rocket.pad
	match s:
		"steam":
			pad.set_alarm(true)
			pad.vent_steam(true)
			pad.set_hoses(1.0)
			pad.set_gangway(1.0)
			m.set_charge(0.8)
		"ignite":
			pad.vent_steam(false)
			pad.billow(true)
			pad.set_clamps(1.0)
			m.set_charge(0.0)
			m.plume.power = 0.8
		"liftoff":
			m.position.y = LaunchPad.TOP_Y + 6.0
			m.plume.power = 1.05
			if DevHooks.has("trail-amount"):
				_rocket._trail.amount = int(DevHooks.get_f("trail-amount", 40))
				_rocket._trail.lifetime = DevHooks.get_f("trail-life", 2.2)
			_rocket._trail.emitting = not DevHooks.has("no-trail")
			if DevHooks.has("no-flare"):
				for c: Node in m.plume.get_children():
					if c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh:
						(c as Node3D).visible = false
						c.set_process(false)
				m.plume.set_process(false)
		"climb":
			pad.billow(false)
			m.position = Vector3(3.0, 40.0, -2.0)
			m.rotation = Vector3(0, 0, -0.3)
			_rocket._dot.visible = true
			(_rocket._dot.material_override as StandardMaterial3D).albedo_color.a = 0.8
		"holo":
			_rocket.visible = false
			_holo = LaunchPad.new()
			_holo.construction = true
			add_child(_holo)


func _process(delta: float) -> void:
	_t += delta
	if _i < 0:
		_set_view(0)
		if _t < 4.0:
			return
		_i = 0
		_t = 0.0
	if _i >= _views.size():
		get_tree().quit()
		return
	_set_view(_i)
	if _t > DevHooks.get_f("wait", 2.5):
		DevHooks.save_viewport("%s_%d.png" % [_out, _i])
		_i += 1
		_t = 0.0
		if _i < _views.size():
			_set_state(_views[_i][0])


func _set_view(i: int) -> void:
	var v: Array = _views[i]
	_cam.position = v[1]
	_cam.look_at(v[2], Vector3.UP)
