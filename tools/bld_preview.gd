extends Node3D
## [art3] A street of BuildingDetail proxy buildings on their own (no globe: loads in seconds), to
## judge the shared building shader and the mesh builders.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 res://tools/bld_preview.tscn -- --out=PREFIX [--seed=N] [--clean=0..1]
## Saves PREFIX_street.png (eye height, along the row), PREFIX_front.png (one facade square on),
## PREFIX_far.png (the row from 220 m), PREFIX_dusk.png and PREFIX_night.png, then quits.

var _sun: DirectionalLight3D
var _env: Environment
var _cam: Camera3D


func _arg(key: String, def: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return a.get_slice("=", 1)
	return def


func _ready() -> void:
	var seed_v: int = int(_arg("seed", "4471"))
	var det := BuildingDetail.new()
	var body := BuildingDetail.Geo.new()
	var dg := BuildingDetail.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# Two rows facing each other across a 16 m street, then a row of towers behind.
	for row: int in 3:
		var x: float = -60.0
		while x < 60.0:
			var bays: int = rng.randi_range(3, 6)
			var w: float = float(bays) * 3.0
			var floors: int = rng.randi_range(2, 6) if row < 2 else rng.randi_range(8, 22)
			var z: float = [-20.0, 8.0, -52.0][row]
			var bd: Dictionary = {"rect": Rect2(x, z, w, 12.0), "face": Vector2(0, 1) if row != 1 else Vector2(0, -1), "bays": bays,
				"floors": floors, "style": "factory" if rng.randf() < 0.2 and floors < 8 else "apartments", "seed": rng.randi(),
				"ruined": rng.randf() < 0.25, "trim": rng.randi() % 8}
			det.proxy_building(bd, body, dg)
			x += w + (0.0 if rng.randf() < 0.7 else 4.0)
	var mat: ShaderMaterial = BuildingDetail.material().duplicate()
	var clean: float = float(_arg("clean", "0"))
	mat.set_shader_parameter("life_flat", Vector3(clean, clean, 0.0))
	for g: BuildingDetail.Geo in [body, dg]:
		var mi := MeshInstance3D.new()
		mi.mesh = g.mesh()
		mi.material_override = mat
		add_child(mi)
	# The kit fronts' cut-out ivy, here over the first 30 m of the near row.
	var ivy := MeshInstance3D.new()
	ivy.mesh = BuildingDetail.ivy_card(Vector3(-30, 0, -8), Vector3.LEFT, Vector3.BACK, 30.0, 9.0, seed_v)
	ivy.material_override = BuildingDetail.ivy_material()
	ivy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ivy)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.19, 0.18)
	gm.roughness = 0.7
	ground.material_override = gm
	add_child(ground)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 160.0
	add_child(_sun)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	sky.sky_material = psm
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = 0.0014
	_env.fog_light_color = Color(0.72, 0.74, 0.76)
	we.environment = _env
	add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 2000.0
	add_child(_cam)
	_cam.make_current()
	_run(mat, psm)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.look_at_from_position(from, at, Vector3.UP)


func _light(elev_deg: float, col: Color, energy: float, psm: ProceduralSkyMaterial, sky_top: Color, sky_hor: Color, amb: float) -> void:
	_sun.rotation = Vector3(deg_to_rad(-elev_deg), deg_to_rad(215.0), 0.0)
	_sun.light_color = col
	_sun.light_energy = energy
	psm.sky_top_color = sky_top
	psm.sky_horizon_color = sky_hor
	psm.ground_horizon_color = sky_hor
	psm.ground_bottom_color = Color(0.12, 0.11, 0.1)
	_env.ambient_light_energy = amb
	_env.fog_light_color = sky_hor


func _shot(path: String) -> void:
	for k: int in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[bld-preview] ", path)


func _run(mat: ShaderMaterial, psm: ProceduralSkyMaterial) -> void:
	var out: String = _arg("out", "screenshots/bld_preview")
	_light(38.0, Color(1.0, 0.93, 0.82), 2.4, psm, Color(0.25, 0.42, 0.7), Color(0.74, 0.78, 0.82), 1.0)
	_look(Vector3(-34.0, 2.2, 2.0), Vector3(10.0, 7.0, -8.0))
	await _shot(out + "_street.png")
	_look(Vector3(-8.0, 5.0, 5.0), Vector3(-8.0, 6.5, -8.0))
	await _shot(out + "_front.png")
	_look(Vector3(-20.0, 3.0, 230.0), Vector3(0.0, 22.0, 0.0))
	await _shot(out + "_far.png")
	_light(7.0, Color(1.0, 0.6, 0.32), 2.2, psm, Color(0.2, 0.26, 0.45), Color(0.95, 0.62, 0.4), 0.7)
	_look(Vector3(-34.0, 2.2, 2.0), Vector3(10.0, 7.0, -8.0))
	await _shot(out + "_dusk.png")
	_light(40.0, Color(0.6, 0.7, 1.0), 0.25, psm, Color(0.02, 0.03, 0.08), Color(0.08, 0.11, 0.2), 0.5)
	mat.set_shader_parameter("life_night", 1.0)
	await _shot(out + "_night.png")
	get_tree().quit()
