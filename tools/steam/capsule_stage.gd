extends Node3D
## Store-art stage (Steam capsules / library hero). Lumi hovers on the seam between the dusty junk
## lot (screen left) and a restored green district (screen right) with the future city rising
## behind it. No UI: the logo is composited afterwards by tools/steam/capsules.gd.
##
## Run (render gating applies, see docs/steam/TRAILER.md):
##   xvfb-run -a -s "-screen 0 3840x2160x24" godot --path . --rendering-driver vulkan \
##     --resolution 2560x1440 res://tools/steam/capsule_stage.tscn -- --fresh --quality=2 \
##     --frame=wide --shot=screenshots/steam/master_wide.png --shot-delay=90 --quit-after=95
## Frames: wide (16:9 master for header/main/small/vertical/library capsules), hero (library hero,
## 3840x1240, room for the library logo on the left), tall (portrait).

var _cam: Camera3D
var _pivot: Node3D
var _model: PatchModel
var _t: float = 0.0
var _frame: String = "wide"


## Where the green side begins (world x; green is x < seam). Wavy and wider towards the back.
static func seam_x(z: float) -> float:
	return -0.25 + z * 0.16 + sin(z * 0.9) * 0.35 + sin(z * 2.3 + 1.0) * 0.12


func _ready() -> void:
	_frame = DevHooks.get_s("frame", "wide")
	SaveManager.enabled = false
	_build_env()
	_build_ground()
	_scatter_junk()
	_scatter_green()
	_build_skyline()
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.34, 0)
	add_child(_pivot)
	_model = PatchModel.new()
	_pivot.add_child(_model)
	_model.set_happy(1.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_place_camera()


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_coefficient = 3.0
	sm.rayleigh_color = Color(0.3, 0.45, 0.85)
	sm.mie_coefficient = 0.01
	sm.mie_eccentricity = 0.86
	sm.mie_color = Color(1.0, 0.74, 0.5)
	sm.turbidity = 9.0
	sm.sun_disk_scale = 2.0
	sm.ground_color = Color(0.3, 0.28, 0.22)
	sm.energy_multiplier = 1.35
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.3
	env.glow_intensity = 0.4
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.95, 0.72, 0.52)
	env.fog_sun_scatter = 0.3
	env.fog_sky_affect = 0.2
	env.fog_density = 0.006
	env.volumetric_fog_density = 0.003
	env.volumetric_fog_albedo = Color(0.95, 0.82, 0.7)
	env.volumetric_fog_anisotropy = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	Settings.apply_render_quality(env, get_viewport())
	env.ambient_light_energy *= 0.85
	# Low golden sun behind and a little right of the robot: rims Lumi, lights the meadow.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-11, -24, 0)
	sun.light_color = Color(1.0, 0.7, 0.45)
	sun.light_energy = 2.3
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	Settings.apply_sun_quality(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 200, 0)
	fill.light_color = Color(0.64, 0.74, 1.0)
	fill.light_energy = 0.75
	add_child(fill)


## Dry rocky ground blending into leafy grass across the seam.
func _build_ground() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D dry_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float seam(float z) { return -0.25 + z * 0.16 + sin(z * 0.9) * 0.35 + sin(z * 2.3 + 1.0) * 0.12; }
void fragment() {
	vec2 uv = wp.xz * 0.25;
	float n = texture(noise, wp.xz * 0.05).r;
	float d = seam(wp.z) - wp.x + (n - 0.5) * 1.6;
	float g = smoothstep(-0.35, 0.55, d);
	vec3 dry = texture(dry_a, uv).rgb;
	vec3 gr = texture(grass_a, uv * 1.3).rgb * vec3(0.95, 1.05, 0.9);
	ALBEDO = mix(dry, gr, g);
	NORMAL_MAP = mix(texture(dry_n, uv).rgb, texture(grass_n, uv * 1.3).rgb, g);
	ROUGHNESS = mix(0.92, 0.85, g);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("dry_a", AssetLib.tex("dry_ground_rocks", "diff"))
	m.set_shader_parameter("dry_n", AssetLib.tex("dry_ground_rocks", "nor_gl"))
	m.set_shader_parameter("grass_a", AssetLib.tex("leafy_grass", "diff"))
	m.set_shader_parameter("grass_n", AssetLib.tex("leafy_grass", "nor_gl"))
	var nt := NoiseTexture2D.new()
	nt.noise = FastNoiseLite.new()
	nt.seamless = true
	m.set_shader_parameter("noise", nt)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	pm.subdivide_depth = 4
	pm.subdivide_width = 4
	ground.mesh = pm
	ground.material_override = m
	add_child(ground)


func _add_multimesh(id: String, xs: Array, max_tris: int = 900) -> void:
	if xs.is_empty() or not AssetLib.has_model(id):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = AssetLib.model_mesh_lite(id, max_tris)
	mm.instance_count = xs.size()
	for j: int in xs.size():
		mm.set_instance_transform(j, xs[j])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## The junk lot: a carpet of litter and heaps on the dry side, thinning out at the seam.
func _scatter_junk() -> void:
	var ids: Array[String] = []
	for t: Dictionary in Economy.junk_types.values():
		for m: Dictionary in t.get("models", []):
			if AssetLib.has_model(str(m["id"])):
				ids.append(str(m["id"]))
	if ids.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var per: Dictionary = {}
	for i: int in 2200:
		var p := Vector3(rng.randf_range(-6.0, 34.0), 0, rng.randf_range(-6.0, 34.0))
		var d: float = p.x - seam_x(p.z)
		if d < 0.2 or (d < 1.6 and rng.randf() > (d - 0.2) / 1.4):
			continue
		if Vector2(p.x, p.z).length() < 1.2:
			continue  # a little clearing under the robot
		var id: String = ids[rng.randi() % ids.size()]
		var lie: bool = rng.randf() < 0.6
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		if lie:
			b = b * Basis(Vector3.RIGHT if rng.randf() < 0.5 else Vector3.FORWARD, PI * 0.5)
		if not per.has(id):
			per[id] = []
		(per[id] as Array).append(Transform3D(b.scaled(Vector3.ONE * rng.randf_range(0.85, 1.2)), p + Vector3(0, 0.03 if lie else 0.0, 0)))
	for h: int in 8:
		var c := Vector3(rng.randf_range(3.0, 22.0), 0, rng.randf_range(2.0, 24.0))
		if c.x - seam_x(c.z) < 2.5:
			continue
		for k: int in 80:
			var off := Vector3(rng.randf_range(-1.7, 1.7), 0, rng.randf_range(-1.7, 1.7))
			var y: float = maxf(0.0, 1.2 - off.length() * 0.65) * rng.randf()
			var id2: String = ids[rng.randi() % ids.size()]
			if not per.has(id2):
				per[id2] = []
			(per[id2] as Array).append(Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)), c + off + Vector3(0, y, 0)))
	for id3: String in per:
		_add_multimesh(id3, per[id3])
	for spec: Array in [
		["old_tyre", Vector3(1.6, 0.08, 0.6), Vector3(90, 0, 20)],
		["Barrel_01", Vector3(2.7, 0, 1.9), Vector3(0, 0, 0)],
		["covered_car", Vector3(8.5, 0, 7.0), Vector3(0, 35, 0)],
		["dead_tree_trunk", Vector3(6.5, 0, 12.0), Vector3(0, 60, 0)],
		["street_lamp_01", Vector3(4.2, 0, 9.0), Vector3(0, 0, 0)],
		["concrete_road_barrier", Vector3(10.5, 0, 3.0), Vector3(0, -20, 0)],
	]:
		if AssetLib.has_model(spec[0]):
			var mi := MeshInstance3D.new()
			mi.mesh = AssetLib.model_mesh(spec[0])
			mi.position = spec[1]
			mi.rotation_degrees = spec[2]
			add_child(mi)


## The restored side: dense grass, flowers, ferns, shrubs and young trees; a few brave sprouts
## cross the seam into the junk.
func _scatter_green() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var kinds: Array = [
		# id, count, min scale, max scale, depth from seam (min)
		["grass_medium_01", 2600, 0.8, 1.5, 0.0],
		["grass_medium_02", 2200, 0.8, 1.4, 0.0],
		["flower_gazania", 700, 0.9, 1.4, 0.3],
		["celandine_01", 650, 1.0, 1.6, 0.3],
		["flower_heliophila", 600, 0.9, 1.5, 0.2],
		["dandelion_01", 450, 0.9, 1.4, -0.6],
		["fern_02", 260, 0.7, 1.3, 0.8],
		["shrub_01", 90, 0.8, 1.6, 2.0],
		["shrub_02", 90, 0.8, 1.6, 2.0],
		["pine_sapling_small", 70, 1.5, 3.2, 3.0],
	]
	for k: Array in kinds:
		var xs: Array = []
		for i: int in int(k[1]):
			var p := Vector3(rng.randf_range(-34.0, 3.0), 0, rng.randf_range(-6.0, 34.0))
			var d: float = seam_x(p.z) - p.x
			if d < float(k[4]):
				continue
			if d < 1.0 and rng.randf() > (d + 0.6) / 1.6:
				continue
			if Vector2(p.x, p.z).length() < 0.9 and str(k[0]).begins_with("shrub"):
				continue
			var s: float = rng.randf_range(k[2], k[3])
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		_add_multimesh(str(k[0]), xs, 1500)


## Ruined city on the junk side of the horizon, the bright future city on the green side.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ruin := StandardMaterial3D.new()
	ruin.albedo_color = Color(0.36, 0.3, 0.28)
	ruin.roughness = 0.95
	var tower := StandardMaterial3D.new()
	tower.albedo_color = Color(0.86, 0.88, 0.86)
	tower.roughness = 0.35
	tower.metallic = 0.1
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.32, 0.45, 0.5)
	glass.roughness = 0.08
	glass.metallic = 0.6
	var line := StandardMaterial3D.new()
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.albedo_color = Color(0.7, 0.95, 1.0)
	line.emission_enabled = true
	line.emission = Color(0.65, 0.95, 1.0)
	line.emission_energy_multiplier = 1.6
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.3, 0.5, 0.22)
	leaf.roughness = 0.9
	for i: int in 34:
		var z: float = rng.randf_range(34.0, 70.0)
		var x: float = rng.randf_range(-70.0, 60.0)
		var green: bool = x < seam_x(z) * 2.0 - 4.0
		var h: float = rng.randf_range(18, 46) if green else rng.randf_range(8, 30)
		var size := Vector3(rng.randf_range(5, 11), h, rng.randf_range(5, 11))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = Vector3(x, size.y * 0.5 - (0.0 if green else rng.randf_range(0.0, 3.0)), z)
		if not green:
			mi.material_override = ruin
			mi.rotation = Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.06, 0.06))
			add_child(mi)
			continue
		# Future tower: pale body, glass bands, a thin light line at each band, a green roof.
		mi.material_override = tower
		mi.rotation.y = rng.randf_range(-0.3, 0.3)
		add_child(mi)
		var bands: int = int(h / 6.0)
		for b: int in bands:
			var y: float = -h * 0.5 + 4.0 + b * 6.0
			var g := MeshInstance3D.new()
			var gm := BoxMesh.new()
			gm.size = Vector3(size.x + 0.08, 2.2, size.z + 0.08)
			g.mesh = gm
			g.material_override = glass
			g.position = Vector3(0, y, 0)
			mi.add_child(g)
			var l := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(size.x + 0.14, 0.08, size.z + 0.14)
			l.mesh = lm
			l.material_override = line
			l.position = Vector3(0, y + 1.25, 0)
			mi.add_child(l)
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(size.x * 0.9, 0.9, size.z * 0.9)
		roof.mesh = rm
		roof.material_override = leaf
		roof.position = Vector3(0, h * 0.5 + 0.45, 0)
		mi.add_child(roof)


func _place_camera() -> void:
	var look := Vector3(0, 0.66, 0)
	match _frame:
		"hero":
			# 3840x1240: wide meadow-to-junk panorama, Lumi right of centre (the library logo sits left).
			_cam.fov = 26.0
			_cam.position = Vector3(0.9, 1.05, -6.2)
			_cam.h_offset = -1.05
			look = Vector3(0.9, 1.0, 0)
		"tall":
			_cam.fov = 48.0
			_cam.position = Vector3(0.1, 1.0, -3.3)
			look = Vector3(0.1, 1.15, 0)
		_:
			_cam.fov = 38.0
			_cam.position = Vector3(0.15, 1.05, -4.0)
			look = Vector3(0.15, 0.95, 0)
	_cam.look_at(look, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	# Very slow drift only (TAA needs a near-static frame to resolve).
	_pivot.position.y = 0.34 + sin(_t * 0.6) * 0.01
	_model.look_toward(_cam.global_position)
