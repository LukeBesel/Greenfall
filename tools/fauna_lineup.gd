extends Node3D
## [fauna2] Close-up renders of the procedural animals (fauna/fauna_models.gd) on their own, with
## the real fauna shader, for model work without loading a district:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 640x480 res://tools/fauna_lineup.tscn -- \
##     --models=deer,seal,pigeon_fly --out=screenshots/lineup [--yaw=0.7] [--phase=1.2] [--coat=0]
## Writes <out>_<model>.png per model (3/4 front view, framed on the mesh bounds).

var _ids: PackedStringArray
var _i: int = -1
var _wait: int = 0
var _out: String
var _cam: Camera3D
var _cur: MultiMeshInstance3D


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/lineup")
	_ids = DevHooks.get_s("models", "cat,deer,deer_stag,seal,fox,rabbit,duck,pigeon,pigeon_fly,sparrow,songbird").split(",")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.7, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 2.0
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.52, 0.45)
	gm.roughness = 0.95
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.near = 0.01
	add_child(_cam)
	_cam.current = true


func _process(_delta: float) -> void:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s_%s.png" % [_out, _ids[_i]])
			print("[lineup] saved ", _ids[_i])
		return
	_i += 1
	if _i >= _ids.size():
		get_tree().quit()
		return
	if _cur:
		_cur.queue_free()
	var id: String = _ids[_i]
	var mesh: Mesh = FaunaModels.mesh(id)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	var flying: bool = id.ends_with("_fly")
	var y0: float = 0.6 if flying else 0.0
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, y0, 0)))
	mm.set_instance_custom_data(0, Fauna.pack_custom(DevHooks.get_f("phase", 1.2 if flying else 0.0), 0.9 if flying else 0.0, 0.0, 0.0, int(DevHooks.get_f("coat", 0.0)), 0.2))
	_cur = MultiMeshInstance3D.new()
	_cur.multimesh = mm
	if Fauna.is_rigged(mesh):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://art/shaders/fauna.gdshader")
		var sid: String = id.trim_suffix("_fly").trim_suffix("_sit").trim_suffix("_curl").trim_suffix("_stag")
		var coats: Array = FaunaRules.def(sid).get("coats", ["#ffffff"])
		var pal := PackedVector3Array()
		for k: int in 8:
			var c: Color = Color.html(str(coats[k % coats.size()]))
			pal.append(Vector3(c.r, c.g, c.b))
		mat.set_shader_parameter("coats", pal)
		_cur.material_override = mat
	add_child(_cur)
	var bb: AABB = mesh.get_aabb()
	var r: float = bb.size.length() * 0.5
	var ctr: Vector3 = bb.get_center() + Vector3(0, y0, 0)
	var yaw: float = DevHooks.get_f("yaw", 0.75)
	var pitch: float = DevHooks.get_f("pitch", 0.22 if not flying else 0.5)
	var dist: float = r / tan(deg_to_rad(_cam.fov * 0.5)) * 1.05
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	_cam.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), ctr + dir * dist)
	_wait = 4
