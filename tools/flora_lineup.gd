extends Node3D
## [art7] The flora kit on its own (art/models/flora, plants/flora_kit.gd), with the real shader:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/flora_lineup.tscn -- \
##     --out=screenshots/flora [--sun-yaw=150] [--sun-pitch=-38]
## Writes <out>_trees.png, _small.png, _back.png (the trees against a low sun) and _lod.png (the far twins).

var _out: String
var _cam: Camera3D
var _sun: DirectionalLight3D
var _step: int = 0
var _wait: int = 0
const VIEWS: Array = [["trees", Vector3(13, 5.5, 26), Vector3(13, 2.6, 0), 150.0, -38.0], ["small", Vector3(4.6, 2.4, 9.4), Vector3(4.6, 0.3, 3.4), 150.0, -38.0],
	["back", Vector3(13, 3.0, 24), Vector3(13, 3.0, 0), 5.0, -14.0], ["lod", Vector3(53, 5.5, 26), Vector3(53, 2.6, 0), 150.0, -38.0]]


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/flora")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.4, 0.56, 0.8)
	sm.sky_horizon_color = Color(0.82, 0.8, 0.74)
	sm.ground_horizon_color = Color(0.5, 0.46, 0.4)
	sm.ground_bottom_color = Color(0.3, 0.27, 0.22)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.light_energy = 2.6
	_sun.light_color = Color(1.0, 0.9, 0.76)
	_sun.shadow_enabled = true
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 80)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.28, 0.22)
	gm.roughness = 0.95
	pm.material = gm
	ground.mesh = pm
	ground.position = Vector3(13, 0, 0)
	add_child(ground)
	# The plants stand on a big sphere's north pole, as in the game (the shader's up is the position).
	var holder := Node3D.new()
	add_child(holder)
	var kit: Dictionary = FloraKit.meshes()
	var x: float = 0.0
	for sp: int in 4:
		for age: int in 3:
			_put(holder, FloraKit.tree(sp, age, false), Vector3(x, 0, 0), 1.0)
			if age > 0:
				_put(holder, FloraKit.tree(sp, age, true), Vector3(x + 40.0, 0, 0), 1.0)
			x += 1.2 + age * 1.3
	x = 0.0
	for nm: String in ["grass_a", "grass_b", "grass_lod", "moss", "weed", "fern", "flower_daisy", "flower_poppy", "flower_umbel", "flower_lupin", "flower_aster"]:
		_put(holder, nm, Vector3(x, 0, 6), 0.45, Color(1.0, 0.75, 0.2) if nm == "weed" else Color(0.75, 0.5, 1.0) if nm.ends_with("lupin") or nm.ends_with("aster") else Color(1.0, 0.25, 0.15) if nm.ends_with("poppy") else Color.WHITE)
		x += 0.75
	for nm: String in FloraKit.BUSHES:
		_put(holder, nm, Vector3(x + 0.6, 0, 5.2), 1.0, Color(1.0, 0.8, 0.9))
		x += 2.0
	print("[flora] kit meshes: ", kit.size())
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.current = true
	_view()


func _put(holder: Node3D, nm: String, at: Vector3, sc: float, tint: Color = Color.WHITE) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = FloraKit.mesh(nm)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), at))
	mm.set_instance_custom_data(0, Color(tint.r, tint.g, tint.b, fposmod(at.x * 0.37 + at.z * 0.11, 1.0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = FloraKit.material()
	mi.position = Vector3(0, 0, 0)
	holder.add_child(mi)


func _view() -> void:
	var v: Array = VIEWS[_step]
	_cam.look_at_from_position(v[1], v[2])
	_sun.rotation_degrees = Vector3(float(v[4]), float(v[3]), 0)
	_wait = 6


func _process(_delta: float) -> void:
	_wait -= 1
	if _wait > 0:
		return
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, VIEWS[_step][0]])
	_step += 1
	if _step >= VIEWS.size():
		get_tree().quit()
		return
	_view()
