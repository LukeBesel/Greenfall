extends Node3D
## [art3] Junk look-dev (rendered): every junk look, a few dressed scans and the 16 litter kinds on dark
## ground, at the globe's radius so the shaders' planet-up holds.
##   xvfb-run ... godot --path . --rendering-driver opengl3 res://tools/junk_lookdev.tscn -- --out=PNG [--debug]
# Look-dev: the litter kinds and every junk look on a dark ground, R metres from the planet centre
# (so the shaders' "up" works). Saves OUT png.
const R := 6000.0
var out: String = "screenshots/art/junk/lookdev.png"
var frames: int = 0
var root3: Node3D

func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	root3 = self
	var o := Vector3(0, R, 0)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.55, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.58, 0.7)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.shadow_enabled = true
	root3.add_child(sun)
	sun.transform = Transform3D(Basis.looking_at(Vector3(-3, -4, -2), Vector3.UP), o + Vector3(3, 4, 2))
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.13, 0.12, 0.11)
	gm.roughness = 0.6
	g.material_override = gm
	g.position = o
	root3.add_child(g)
	var cam := Camera3D.new()
	cam.fov = 40
	root3.add_child(cam)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, -3.6, -4.2), Vector3.UP), o + Vector3(2.4, 3.6, 6.0))
	cam.current = true
	# junk looks, a row per 6
	var looks: PackedStringArray = JunkLooks.all_looks()
	var models: Array[String] = ["trashbag", "can_rusted", "bleach_bottle", "Television_01", "cardboard_box_01", "plastic_jerrycan"]
	var k: int = 0
	for look: String in looks:
		var mi := MeshInstance3D.new()
		mi.mesh = JunkLooks.look_mesh(look, 0)
		mi.position = o + Vector3((k % 7) * 0.8, 0, (k / 7) * 0.85)
		root3.add_child(mi)
		k += 1
	for m: String in models:
		var mi := MeshInstance3D.new()
		mi.mesh = JunkLooks.dressed(AssetLib.model_mesh_lite(m, 320), m)
		mi.position = o + Vector3((k % 7) * 0.8, -AssetLib.model_aabb(m).position.y, (k / 7) * 0.85)
		root3.add_child(mi)
		k += 1
	# the 16 litter kinds
	var lit := SphereLitter.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	for q: int in 4:
		for p: Vector3 in [pts[q], Vector3(0.06, 0.05, -0.04), pts[(q + 1) % 4]]:
			st.set_color(Color.WHITE)
			st.set_uv(Vector2(p.x + 0.5, p.z + 0.5))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	st.generate_tangents()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = 16
	for i: int in 16:
		var kd: Array = SphereLitter.KINDS[i]
		var b := Basis.from_scale(Vector3(float(kd[0]) * 1.4, 0.3, float(kd[1]) * 1.4))
		mm.set_instance_transform(i, Transform3D(b, Vector3((i % 8) * 0.7, 0.02, 3.6 + (i / 8) * 0.7)))
		mm.set_instance_color(i, Color(0.9, 0.9, 0.9, (i + 0.5) / 16.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = lit._litter_material()
	mmi.position = o
	root3.add_child(mmi)
	print("[lookdev] sheet mesh: surfaces %d, aabb %s; looks %d" % [mm.mesh.get_surface_count(), mm.mesh.get_aabb(), looks.size()])
	if OS.get_cmdline_user_args().has("--debug"):
		var m2: ShaderMaterial = lit._litter_material().duplicate()
		m2.set_shader_parameter("fade_from", 1e6)
		m2.set_shader_parameter("fade_to", 2e6)
		var a := MultiMeshInstance3D.new()
		a.multimesh = mm
		a.material_override = m2
		a.position = o + Vector3(0, 0, -1.6)
		add_child(a)
		var sh := Shader.new()
		sh.code = "shader_type spatial; render_mode cull_disabled, unshaded; varying float k; void vertex(){ k = COLOR.a; } void fragment(){ ALBEDO = vec3(k, fract(k * 16.0), 0.0); }"
		var m3 := ShaderMaterial.new()
		m3.shader = sh
		var b2 := MultiMeshInstance3D.new()
		b2.multimesh = mm
		b2.material_override = m3
		b2.position = o + Vector3(0, 0, -3.2)
		add_child(b2)
	lit.free()

func _process(_d: float) -> void:
	frames += 1
	if frames == 12:
		get_viewport().get_texture().get_image().save_png(out)
		print("[lookdev] saved ", out)
		get_tree().quit()
