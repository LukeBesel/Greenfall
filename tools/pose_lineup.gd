extends Node3D
## [photo] Renders every photo-mode pose side by side (front and 3/4 views) to check the joint
## angles quickly:
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1600x900 res://tools/pose_lineup.tscn -- --fresh --out=screenshots/poses
## Writes <out>_0.png (front) and <out>_1.png (3/4 from the right).

var _cam: Camera3D
var _t: float = 0.0
var _i: int = 0
var _out: String
var _views: Array = []


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/poses")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.34, 0.37)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.35, 0.33)
	ground.material_override = gm
	add_child(ground)
	var ids: Array[String] = PhotoPoser.pose_ids()
	var cols: int = 7
	for i: int in ids.size():
		var m := PatchModel.new()
		var row: int = i / cols
		var col: int = i % cols
		m.position = Vector3((col - (cols - 1) * 0.5) * 1.35 + row * 0.6, 0, row * 2.2)
		add_child(m)
		var p := PhotoPoser.new()
		add_child(p)
		p.attach(m)
		p.pose = ids[i]
		var l := Label3D.new()
		l.text = ids[i]
		l.font_size = 48
		l.pixel_size = 0.004
		l.position = m.position + Vector3(0, 0.02, -0.75)
		l.rotation_degrees = Vector3(-90, 0, 0)
		add_child(l)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.current = true
	_views = [[Vector3(0.3, 2.0, -9.0), Vector3(0.3, 0.6, 1.0)], [Vector3(6.5, 2.4, -6.5), Vector3(0.3, 0.6, 1.0)]]
	for p: Node in get_children():
		if p is PhotoPoser:
			(p as PhotoPoser).camera_pos = _views[0][0]


func _process(delta: float) -> void:
	_t += delta
	var v: Array = _views[mini(_i, _views.size() - 1)]
	_cam.position = v[0]
	_cam.look_at(v[1], Vector3.UP)
	if _t > 4.0:
		DevHooks.save_viewport("%s_%d.png" % [_out, _i])
		_i += 1
		_t = 2.5
		if _i >= _views.size():
			get_tree().quit()
