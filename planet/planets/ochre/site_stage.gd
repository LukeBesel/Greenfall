extends Node3D
## [planet-ochre] Lightweight render stage for the Ochre site prefabs (no game world, so it fits
## on the shared render box): Ochre's two-sun sky, light and haze, a sand ground, the site twice
## (ruined left at stage 1 / restoration 0, restored right at stage 5 / restoration 1) and a camera.
##   godot --path . --rendering-driver vulkan res://planet/planets/ochre/site_stage.tscn -- \
##     --ochre-site=hub_base [--ochre-site-view=0|1|2] --shot=screenshots/x.png --shot-delay=30 --quit-after=34

const SEP: float = 56.0


func _ready() -> void:
	var kind: Dictionary = PlanetEnvs.entry("ochre")
	OchreEnv.prepare(kind)
	var id: String = DevHooks.get_s("ochre-site", "hub_base")
	_environment(kind)
	_ground()
	for k: int in 2:
		var holder := Node3D.new()
		holder.position = Vector3(-SEP if k == 0 else SEP, 0.0, 0.0)
		add_child(holder)
		OchreSites.build(id, holder, 1 if k == 0 else 5, 0.0 if k == 0 else 1.0)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 3000.0
	add_child(cam)
	var pos := Vector3(0.0, 44.0, 92.0)
	var at := Vector3(0.0, -2.0, -2.0)
	match int(DevHooks.get_f("ochre-site-view", 0.0)):
		1:
			pos = Vector3(-SEP, 16.0, 46.0)
			at = Vector3(-SEP, 3.0, 0.0)
		2:
			pos = Vector3(SEP, 16.0, 46.0)
			at = Vector3(SEP, 3.0, 0.0)
	cam.look_at_from_position(pos, at)
	cam.make_current()
	print("[ochre] site stage %s" % id)


func _environment(kind: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://planet/planets/ochre/ochre_sky.gdshader")
	var a := Basis.from_euler(Vector3(deg_to_rad(-48.0), deg_to_rad(-22.0), 0.0)).z.normalized()
	var suns: Dictionary = SolarSystem.suns_for("ochre", a)
	var b: Vector3 = suns["b"]["dir"]
	var sk: Dictionary = kind.get("sky", {})
	var c := func(key: String, fb: Color) -> Vector3:
		var v: Variant = sk.get(key, [])
		var col: Color = Color(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() >= 3 else fb
		return Vector3(col.r, col.g, col.b)
	sm.set_shader_parameter("sun_a_dir", a)
	sm.set_shader_parameter("sun_b_dir", b)
	sm.set_shader_parameter("sun_a_size", float(suns["a"]["size"]) * OchreEnv.SUN_DEG)
	sm.set_shader_parameter("sun_b_size", float(suns["b"]["size"]) * OchreEnv.SUN_DEG)
	sm.set_shader_parameter("horizon", c.call("horizon_restored", Color(0.95, 0.82, 0.62)))
	sm.set_shader_parameter("zenith", c.call("zenith_restored", Color(0.2, 0.42, 0.8)))
	sm.set_shader_parameter("haze", c.call("haze", Color(0.95, 0.66, 0.4)))
	sm.set_shader_parameter("dust", 0.12)
	sm.set_shader_parameter("energy", float(sk.get("energy", 0.75)))
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_intensity = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_density = 0.00016
	env.fog_light_color = Color(0.95, 0.72, 0.48)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.35
	env.adjustment_contrast = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.look_at_from_position(Vector3.ZERO, -a, Vector3.UP)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 3.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	var sun_b := DirectionalLight3D.new()
	sun_b.look_at_from_position(Vector3.ZERO, -b, Vector3.UP)
	sun_b.light_color = Color(1.0, 0.6, 0.36)
	sun_b.light_energy = 0.9
	add_child(sun_b)


## Sand round the two sites, with smooth round holes where they sit (a pit site digs below it).
func _ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var holes: Array[Vector2] = [Vector2(-SEP, 0.0), Vector2(SEP, 0.0)]
	var hr: float = 47.0
	var n := 160
	var half := 400.0
	var cell: float = half * 2.0 / n
	for i: int in n:
		for j: int in n:
			var q: Array = []
			for v: Vector2 in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
				var p := Vector2(-half + v.x * cell, -half + v.y * cell)
				for c: Vector2 in holes:
					if p.distance_to(c) < hr:
						p = c + (p - c).normalized() * hr
				q.append(p)
			for k: int in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = q[k]
				st.set_color(Color(0.3, 1.0, 0.5, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(p.x, -0.05, p.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var gm: ShaderMaterial = OchreSites.terrain_mat(0.0, 1)
	gm.set_shader_parameter("pan_amt", 0.3)
	mi.material_override = gm
	add_child(mi)
