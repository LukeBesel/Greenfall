extends Node3D
## [orbE] Light preview of the round planet's sky and nights (renders that fit the shared box):
## Lumi's model, Glim and a few junk props on a curved patch of a Verdance-sized globe (its real
## radius from GlobeSize), lit by SkyDirector's sphere mode with the world-space sky shader, the
## binary suns, the moon, clouds and the night lift, exactly as on the globe. No grid, streamer
## or 164k-cell state, so it renders in a fraction of the memory.
##   res://tools/sky_preview.tscn -- --orbit-tour=0.5,0.76,0.97 --tour-shot=screenshots/orbE/sky
##   --preview-planet=anvil (radius), --orbit-clouds=0.45, --orbit-haze=1

var sky: SkyDirector
var lumi: Node3D
var cam: Camera3D
var radius: float = GlobeSize.VERDANCE_R
var site: Node3D  # everything on the ground, built around +Y, then turned to the site's latitude


## Lumi's stand-in: a body Glim sees as standing on a sphere (it reads `sphere` and up()).
class Body extends Node3D:
	var sphere: bool = true

	func up() -> Vector3:
		return global_position.normalized()


func _ready() -> void:
	radius = GlobeSize.radius_m(DevHooks.get_s("preview-planet", "verdance"))
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sk := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://planet/orbit/orbit_sky.gdshader")
	sk.sky_material = mat
	sk.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sk
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.fog_enabled = true
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# 15 degrees north of the equator: a real day/night (at the pole the suns never set).
	site = Node3D.new()
	site.name = "Site"
	site.basis = Basis(Vector3.RIGHT, deg_to_rad(DevHooks.get_f("preview-lat", 15.0) - 90.0))
	add_child(site)
	_build_ground()
	lumi = Body.new()
	lumi.name = "Lumi"
	site.add_child(lumi)
	lumi.position = Vector3(0, radius, 0)
	var model := PatchModel.new()
	lumi.add_child(model)
	_props()
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.far = 6000.0
	site.add_child(cam)
	var up: Vector3 = site.basis.y
	cam.look_at_from_position(site.basis * (lumi.position + Vector3(2.6, 1.7, 4.4)), site.basis * (lumi.position + Vector3(0, 0.9, 0)), up)
	cam.current = true
	sky = SkyDirector.new()
	sky.name = "SkyDirector"
	sky.player_fn = func() -> Vector3: return lumi.global_position
	sky.eye_fn = func() -> Vector3: return cam.global_position
	add_child(sky)
	sky.weather_frozen = true
	sky.setup_sphere(env, sun, mat, radius, 0.5)
	sky.clouds = DevHooks.get_f("orbit-clouds", 0.45)
	sky.haze = DevHooks.get_f("orbit-haze", 1.0)
	sky.frozen = true
	var glim := GlimBot.new()
	add_child(glim)
	glim.target = lumi
	glim.sky = sky
	glim.set_light(Glim.value("light", "range", 6.0), Glim.value("light", "energy", 1.1))
	glim.snap_to_target()
	Settings.apply_quality_to_tree(self)
	OrbitQuality.apply_world(sky, null, Settings.quality)
	var tour := OrbitSkyTour.new()
	tour.sky = sky
	add_child(tour)


## A cap of the planet around the north pole: a real-radius sphere segment with the dirt texture.
func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 60
	var segs: int = 72
	var max_a: float = 900.0 / radius  # 900 m of ground around Lumi: past the horizon
	for i: int in rings:
		for j: int in segs:
			for k: Array in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var a: float = max_a * pow(float(k[0]) / rings, 2.0)  # dense near Lumi
				var b: float = TAU * float(k[1]) / segs
				var d := Vector3(sin(a) * cos(b), cos(a), sin(a) * sin(b))
				st.set_normal(d)
				st.set_uv(Vector2(d.x, d.z) * radius / 4.0)
				st.add_vertex(d * radius)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = AssetLib.tex("dry_ground_rocks", "diff")
	m.albedo_color = Color(0.85, 0.8, 0.72)
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	site.add_child(mi)


## A few junk props around Lumi (scale references for how readable the night is).
func _props() -> void:
	var ids: PackedStringArray = OrbitPreload.model_ids()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n: int = 0
	for id: String in ids:
		if n >= 14 or not AssetLib.has_model(id):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh(id)
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(2.5, 9.0)
		mi.position = Vector3(cos(a) * r, radius - 0.02, sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
		site.add_child(mi)
		n += 1
