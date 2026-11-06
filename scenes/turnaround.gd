extends Node3D
## Turnaround renderer for robot designs.
##   tools/shot.sh <name> -- with scene: godot --path . res://scenes/turnaround.tscn -- --model=res://player/designs/x.gd --out=screenshots/turn_x
## Renders front, 3/4, side, back, top-3/4 and a close-up of the lens into <out>_N.png, on a realistic
## ground with litter around for scale (a 0.33 L can and a 0.6 m tyre).

var _model: Node3D
var _cam: Camera3D
var _views: Array = []
var _i: int = -1
var _t: float = 0.0
var _out: String


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/turnaround")
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
	env.ssil_enabled = true
	env.sdfgi_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_albedo = Color(0.8, 0.72, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	pm.material = AssetLib.pbr_material("road_damaged", 8.0)
	ground.mesh = pm
	add_child(ground)
	for spec: Array in [["can_rusted", Vector3(1.0, 0, 0.6)], ["old_tyre", Vector3(-1.4, 0, 0.9)], ["trashbag", Vector3(1.3, 0, -1.2)], ["plastic_bottle_gallon", Vector3(-0.9, 0, -1.1)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh(spec[0])
		mi.position = spec[1]
		if spec[0] == "old_tyre":
			mi.rotation_degrees = Vector3(90, 0, 0)
			mi.position.y = 0.08
		add_child(mi)
	var script_path: String = DevHooks.get_s("model", "res://player/patch_model.gd")
	var scr: GDScript = load(script_path)
	_model = scr.new()
	add_child(_model)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true
	var h: float = 0.7
	_views = [
		[Vector3(0, h + 0.2, -3.6), Vector3(0, h, 0)],            # front (model faces -Z)
		[Vector3(2.6, h + 0.7, -2.6), Vector3(0, h, 0)],          # 3/4 front
		[Vector3(3.6, h + 0.2, 0), Vector3(0, h, 0)],             # side
		[Vector3(-1.8, h + 0.6, 3.2), Vector3(0, h, 0)],          # back 3/4
		[Vector3(2.0, 3.4, -2.2), Vector3(0, 0.4, 0)],            # high 3/4 (gameplay camera)
		[Vector3(0.5, h + 0.6, -1.4), Vector3(0, h + 0.45, 0)],   # close-up on the head/lens
	]


func _process(delta: float) -> void:
	_t += delta
	if _i < 0:
		if _t < 6.0:  # let SDFGI and shaders settle
			_set_view(0)
			return
		_i = 0
		_t = 0.0
	if _i >= _views.size():
		get_tree().quit()
		return
	_set_view(_i)
	if _t > 1.2:
		DevHooks.save_viewport("%s_%d.png" % [_out, _i])
		_i += 1
		_t = 0.0


func _set_view(i: int) -> void:
	var v: Array = _views[i]
	_cam.position = v[0]
	_cam.look_at(v[1], Vector3.UP)
