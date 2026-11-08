class_name OchreEnv
extends Node3D
## [planet-ochre] Ochre, the Desert World: the Ledger's first open-pit strip mine, closest planet
## to the binary star. The play field sits on a wide haul bench low inside an enormous terraced
## pit (planet/planets/ochre/pit.gd): stepped walls of layered ochre, terracotta and cream rock
## climb ~100 m to the rim, haul roads spiral between the benches, abandoned bucket-wheel
## excavators tower over the field, and beyond the rim layered mesas stand on a plateau of salt
## pans under a hot white-gold sky with two big suns.
##   ruined (base 1)   sludge pond, salt crust, rusted slumped excavators, dust devils, heavy haze
##   mid (2-3)         excavators repainted and booms raised, patched shade sails, the pond clears
##   futuristic (4-5)  solar sails with thin light seams, excavators as planters and wind wheels,
##                     a wind-catcher tower, a light seam along each terrace crest
##   restoration       (hex levels 0..1) terraced farms, water channels, palms and succulents
##                     climb the pit from the floor up; the sky clears from dusty to blue
## Entry points: prepare(kind) before the field is generated, apply(world, field, kind) after.

const DIR: String = "res://planet/planets/ochre/"
const SUN_DEG: float = 1.25          # disc radius (degrees) of a size-1.0 star
const SPOKES: int = 416
const SECTORS: int = 16

var world: Node
var field: HexField
var kind: Dictionary = {}
var pit: OchrePit
var level: int = 1
var restore: float = 0.0
var restore_shown: float = 0.0
var r_clip: float = 60.0

var _groups: Dictionary = {}
var _mats: Dictionary = {}
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _shimmer: MeshInstance3D
var _shimmer_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _sun_b: DirectionalLight3D
var _suns: Dictionary = {}
var _paint: Array = []
var _wheels: Array = []
var _future_bits: Array[Node3D] = []
var _plants: Array = []       # [MultiMesh, PackedFloat32Array of sorted levels]
var _junk: Array = []         # [MultiMesh, PackedFloat32Array of -levels, ascending]
var _sail_mats: Array[ShaderMaterial] = []
var _devils: Array[CPUParticles3D] = []
var _fall_mat: ShaderMaterial
var _grit: CPUParticles3D
var _fluff: CPUParticles3D
var _keep_out: Array = []     # [Vector2 xz, radius] for plant placement
var _t: float = 0.0
var _poll: float = 0.0
var _rng := RandomNumberGenerator.new()


# --- Entry points --------------------------------------------------------------------------------

## Before the district's field is generated: the procedural junk models and the junk biome set.
static func prepare(k: Dictionary) -> void:
	var meshes: Dictionary = OchreProps.junk_meshes()
	for id: String in meshes:
		AssetLib._meshes[id] = meshes[id]
		AssetLib._aabbs[id] = (meshes[id] as Mesh).get_aabb()
	var biome: String = str(k.get("junk_biome", "ochre_pit"))
	var set_path: String = DIR + "junk_biome.json"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(set_path))
	if d is Dictionary:
		Economy.biome_sets[biome] = d


## PlanetEnvs contract (planet/planets/planet_envs.gd): the dev hook's district, a wild hub that is
## not a frontier, preferring the entry's prefer_biome (a dust hub).
static func dev_hub(planet: PlanetData) -> int:
	var want: String = str(PlanetEnvs.entry("ochre").get("prefer_biome", "dust_dunes"))
	var skip: Array = planet.frontier_hubs.values()
	var pick: int = 0
	for i: int in planet.hubs.size():
		var c: int = planet.hubs[i]
		if i == 0 or i in skip or planet.city[c] >= 0 or planet.state[c] == PlanetData.State.WATER:
			continue
		if pick == 0:
			pick = i
		if PlanetData.BIOMES[planet.biome[c]] == want:
			return i
	return pick


## Before HexField.generate: Ochre's junk models and biome set; marks the field as a planet env's
## (FutureLayer then skips its city spires).
static func prepare_field(f: HexField) -> void:
	var k: Dictionary = PlanetEnvs.entry("ochre")
	prepare(k)
	f.biome = str(k.get("junk_biome", "ochre_pit"))
	f.biome_set = Economy.biome_set(f.biome)
	f.set_meta("planet_env", "ochre")


## Before FieldView.setup: desert ground layers (red laterite, ochre sand, red gravel, cracked
## crust), light wind ripples; the env builds the horizon itself.
static func dress_view(view: FieldView) -> void:
	view.layer_swap = {"4": "red_laterite_soil_stones", "5": "sand_01", "6": "terrain_red_01", "7": "mud_cracked_dry_03"}
	view.ground_fx = Vector4(0.25, 0.0, 0.0, 0.0)
	view.skip_horizon = true


static func apply(p_world: Node, p_field: HexField, k: Dictionary) -> void:
	prepare(k)
	var old: Node = p_world.get_node_or_null("OchreEnv")
	if old:
		old.free()
	var e := OchreEnv.new()
	e.name = "OchreEnv"
	e.world = p_world
	e.field = p_field
	e.kind = k
	p_world.add_child(e)
	e.build()


# --- Build ---------------------------------------------------------------------------------------

func build() -> void:
	var t0: int = Time.get_ticks_msec()
	process_priority = 50  # after the SkyDirector (it rewrites fog and sky every frame)
	_rng.seed = field.seed_value + 4242
	pit = OchrePit.new(field.seed_value)
	level = int(world.hub.level) if world.get("hub") != null else 1
	r_clip = field.hex_size * (float(field.radius) + 0.55) * Hex.SQRT3 + 4.0
	for g: String in ["always", "ruin", "mid", "up", "future"]:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	_suns = suns()
	_open_camera()
	_setup_sky()
	_setup_ground()
	_build_terrain()
	_build_mesas()
	_build_pond()
	_build_ramps()
	_build_excavators()
	_build_trucks()
	_build_sails()
	_build_ruin_junk()
	_build_falls()
	_build_plants()
	_build_fx()
	for n: Node in find_children("WheelFuture", "Node3D", true, false):
		_future_bits.append(n as Node3D)
	restore = _measure_restore()
	restore_shown = restore
	set_level(level, false)
	if world.get("hub") != null:
		world.hub.level_changed.connect(func(l: int) -> void: set_level(l, true))
	if DevHooks.has("ochre-cam"):
		_dev_camera.call_deferred(DevHooks.get_s("ochre-cam", "0,60,120,0,0,-150"))
	var counts: Array[String] = []
	for g: String in _groups:
		counts.append("%s=%d" % [g, (_groups[g] as Node).find_children("*", "GeometryInstance3D", true, false).size()])
	print("[ochre] env built in %d ms, level %d restore %.2f: %s" % [Time.get_ticks_msec() - t0, level, restore, " ".join(counts)])


## Dev: --ochre-cam=x,y,z,tx,ty,tz frames a fixed camera (overviews and landmark shots).
func _dev_camera(spec: String) -> void:
	var v: PackedStringArray = spec.split(",")
	if v.size() < 6:
		return
	var cam := Camera3D.new()
	cam.name = "OchreDevCam"
	cam.far = 2600.0
	cam.fov = DevHooks.get_f("ochre-fov", 60.0)
	add_child(cam)
	var rig: Node = world.get("cam")
	var rc: Camera3D = rig.get("camera") if rig else null
	if rc:
		cam.attributes = rc.attributes
	cam.look_at_from_position(Vector3(float(v[0]), float(v[1]), float(v[2])), Vector3(float(v[3]), float(v[4]), float(v[5])))
	cam.make_current()


## The binary star as seen from Ochre (closest planet: both suns large and bright), from
## SolarSystem.suns_for("ochre") (data/solar_system.json). {a: {color, size, energy}, b: {...}}.
func suns() -> Dictionary:
	var r: Dictionary = SolarSystem.suns_for("ochre", _sun_a_dir())
	return {"a": r["a"], "b": r["b"]}


static func _col(a: Variant, fallback: Color) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


func _pal(key: String, fallback: Color) -> Color:
	return _col((kind.get("palette", {}) as Dictionary).get(key, []), fallback)


func _open_camera() -> void:
	var rig: Node = world.get("cam")
	var cam: Camera3D = rig.get("camera") if rig else null
	if cam == null:
		return
	cam.far = 2400.0
	var attrs: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = 320.0
		attrs.dof_blur_far_transition = 500.0
		attrs.dof_blur_amount = 0.025


# --- Sky, suns, fog ------------------------------------------------------------------------------

func _setup_sky() -> void:
	var env: Environment = world.get("_env")
	if env == null:
		return
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = preload("res://planet/planets/ochre/ochre_sky.gdshader")
	var sky: Dictionary = kind.get("sky", {})
	for k: String in ["haze", "night_zenith", "night_horizon"]:
		if sky.has(k):
			var c: Color = _col(sky[k], Color.WHITE)
			_sky_mat.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
	_sky_mat.set_shader_parameter("halo", float(sky.get("halo", 0.35)))
	var a: Dictionary = _suns["a"]
	var b: Dictionary = _suns["b"]
	_sky_mat.set_shader_parameter("sun_a_col", _v3(a["color"]))
	_sky_mat.set_shader_parameter("sun_b_col", _v3(b["color"]))
	_sky_mat.set_shader_parameter("sun_a_size", float(a["size"]) * SUN_DEG)
	_sky_mat.set_shader_parameter("sun_b_size", float(b["size"]) * SUN_DEG)
	_sky_mat.set_shader_parameter("ground", _v3(_pal("terracotta", Color(0.66, 0.34, 0.2)) * 0.7))
	env.sky.sky_material = _sky_mat
	env.sky.process_mode = Sky.PROCESS_MODE_REALTIME
	# The companion's own (unshadowed) warm fill light.
	_sun_b = DirectionalLight3D.new()
	_sun_b.name = "CompanionSun"
	_sun_b.light_color = b["color"]
	_sun_b.shadow_enabled = false
	_sun_b.light_specular = 0.6
	add_child(_sun_b)


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Direction toward the primary (the main DirectionalLight shines along -Z).
func _sun_a_dir() -> Vector3:
	var sun: DirectionalLight3D = world.get("_sun")
	if sun == null:
		return Vector3(0.3, 0.8, 0.2).normalized()
	return sun.global_transform.basis.z.normalized()


## The companion: SolarSystem turns the primary by Ochre's separation, so the pair rise and set
## together.
func _sun_b_dir(a: Vector3) -> Vector3:
	return (SolarSystem.suns_for("ochre", a)["b"]["dir"] as Vector3).normalized()


## SkyDirector's sun path (planet/sky_director.gd _apply) as a direction toward the sun.
static func _path_dir(tod: float) -> Vector3:
	var day_t: float = (tod - 0.25) / 0.5
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI) * 70.0
	if day_t < 0.0 or day_t > 1.0:
		elev = -10.0 - absf(day_t - clampf(day_t, 0.0, 1.0)) * 120.0
	var b := Basis.from_euler(Vector3(deg_to_rad(-elev), deg_to_rad(-30.0 + day_t * 60.0), 0.0))
	return b.z.normalized()


func _grade(_delta: float) -> void:
	var env: Environment = world.get("_env")
	var sun: DirectionalLight3D = world.get("_sun")
	if env == null or sun == null:
		return
	var a: Vector3 = _sun_a_dir()
	var bdir: Vector3 = _sun_b_dir(a)
	var up_a: float = smoothstep(-0.02, 0.2, a.y)
	var up_b: float = smoothstep(-0.02, 0.2, bdir.y)
	var night: float = 1.0 - maxf(up_a, up_b * 0.7)
	# How clean the air is: restoration and the base level both clear the dust.
	var clear: float = clampf(restore_shown * 0.85 + float(level - 1) * 0.06, 0.0, 1.0)
	var dust: float = 1.0 - clear
	var sky: Dictionary = kind.get("sky", {})
	var fog: Dictionary = kind.get("fog", {})
	var hz: Color = _col(sky.get("horizon_ruined", []), Color(1, 0.86, 0.62)).lerp(_col(sky.get("horizon_restored", []), Color(1, 0.93, 0.78)), clear)
	var zn: Color = _col(sky.get("zenith_ruined", []), Color(0.82, 0.72, 0.55)).lerp(_col(sky.get("zenith_restored", []), Color(0.34, 0.55, 0.86)), clear)
	if _sky_mat:
		_sky_mat.set_shader_parameter("sun_a_dir", a)
		_sky_mat.set_shader_parameter("sun_b_dir", bdir)
		_sky_mat.set_shader_parameter("horizon", _v3(hz))
		_sky_mat.set_shader_parameter("zenith", _v3(zn))
		_sky_mat.set_shader_parameter("dust", dust)
		_sky_mat.set_shader_parameter("sun_a_energy", 1.0 - dust * 0.2)
		_sky_mat.set_shader_parameter("sun_b_energy", 0.6 * (1.0 - dust * 0.2))
		_sky_mat.set_shader_parameter("energy", float(sky.get("energy", 0.8)) * lerpf(0.9, 1.0, up_a))
	# Light: the primary keeps SkyDirector's dawn-to-noon colour, tinted hot gold; the companion
	# adds a warm orange-red fill from a little behind it.
	var sa: Dictionary = _suns["a"]
	sun.light_color = sun.light_color * Color(sa["color"]) * Color(1.0, 0.97, 0.9)
	sun.light_energy *= float(kind.get("sun", {}).get("energy", 3.4)) / 3.0 * (1.0 - dust * 0.1)
	if _sun_b:
		_sun_b.look_at_from_position(Vector3.ZERO, -bdir, Vector3.UP if absf(bdir.y) < 0.98 else Vector3.FORWARD)
		_sun_b.light_energy = float(kind.get("sun", {}).get("b_energy", 0.9)) * clampf(float(_suns["b"]["energy"]) / 0.45, 0.5, 1.5) * up_b
		_sun_b.visible = _sun_b.light_energy > 0.01
	# Fog: thick warm dust while ruined, a clean pale heat haze when restored; dust pools low
	# in the pit.
	var fc: Color = _col(fog.get("color_ruined", []), Color(0.93, 0.74, 0.5)).lerp(_col(fog.get("color_restored", []), Color(0.86, 0.84, 0.8)), clear)
	env.fog_light_color = env.fog_light_color.lerp(fc, 1.0 - night * 0.6)
	env.fog_density = lerpf(float(fog.get("density_ruined", 0.0028)), float(fog.get("density_restored", 0.0011)), clear) * lerpf(1.0, 0.7, night)
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = float(fog.get("aerial", 0.55)) * (0.4 + 0.6 * clear)
	var hf: Array = fog.get("height_fog", [])
	if hf.size() >= 2:
		env.fog_height = float(hf[0])
		env.fog_height_density = float(hf[1]) * (0.3 + 0.7 * dust)
	env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(fc, 0.7)
	env.volumetric_fog_density = lerpf(0.0007, 0.0003, clear)
	env.adjustment_saturation = lerpf(1.3, 1.36, clear)
	env.adjustment_contrast = 1.2
	env.tonemap_exposure *= float(kind.get("exposure", 0.82))
	var amb: Dictionary = kind.get("ambient", {})
	env.ambient_light_energy *= float(amb.get("energy", 1.15))
	# Shader clocks and night.
	for m: ShaderMaterial in [_terrain_mat, _water_mat, _shimmer_mat, _fall_mat, OchreProps.foliage_mat()]:
		if m:
			m.set_shader_parameter("time_s", _t)
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("night", night)
	for sm: ShaderMaterial in _sail_mats:
		sm.set_shader_parameter("night", night)
	if _shimmer:
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			_shimmer.global_position = cam.global_position
		var heat: float = up_a * lerpf(1.0, 0.45, clear) * (0.6 + 0.4 * a.y)
		if cam and cam.global_position.y - pit.height_at(cam.global_position.x, cam.global_position.z) > 30.0:
			heat = 0.0  # only near the ground
		_shimmer_mat.set_shader_parameter("amount", heat)
		_shimmer.visible = heat > 0.03


# --- Ground (the play field's own material) -------------------------------------------------------

func _setup_ground() -> void:
	var view: Node = world.get("view")
	if view == null:
		return
	var gm: ShaderMaterial = view.get("ground_material")
	if gm == null:
		return
	# Desert layers for the bare ground: red laterite, ochre sand, red gravel, cracked crust.
	if (view.get("layer_swap") as Dictionary).is_empty():  # dress_view() wasn't called: swap them now
		var layers: Array[String] = FieldView.GROUND_LAYERS.duplicate()
		layers[4] = "red_laterite_soil_stones"
		layers[5] = "sand_01"
		layers[6] = "terrain_red_01"
		layers[7] = "mud_cracked_dry_03"
		gm.set_shader_parameter("albedo_arr", FieldView._tex_array(layers, "diff"))
		gm.set_shader_parameter("normal_arr", FieldView._tex_array(layers, "nor_gl"))
		gm.set_shader_parameter("arm_arr", FieldView._tex_array(layers, "arm"))
	var gt: Array = kind.get("ground_tint", [0.78, 0.52, 0.3, 0.5])
	gm.set_shader_parameter("biome_tint", Vector4(float(gt[0]), float(gt[1]), float(gt[2]), float(gt[3])))
	gm.set_shader_parameter("frontier_fx", Vector4(0.25, 0.0, 0.0, 0.0))
	gm.set_shader_parameter("clip_r", r_clip)
	# Tailings mounds instead of grey rubble.
	var mounds: Array = view.get("_mounds")
	for list: Variant in mounds:
		if list is Array and not (list as Array).is_empty():
			var mi: MeshInstance3D = (list as Array)[0]
			var mat: StandardMaterial3D = AssetLib.pbr_material("red_laterite_soil_stones", 0.9, Color(0.95, 0.78, 0.6), true)
			(mi.mesh as ArrayMesh).surface_set_material(0, mat)
			break


# --- Terrain -------------------------------------------------------------------------------------

func _tmat() -> ShaderMaterial:
	if _terrain_mat:
		return _terrain_mat
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = preload("res://planet/planets/ochre/ochre_terrain.gdshader")
	_terrain_mat.set_shader_parameter("tex_wall", AssetLib.tex("quarry_wall", "diff"))
	_terrain_mat.set_shader_parameter("nrm_wall", AssetLib.tex("quarry_wall", "nor_gl"))
	_terrain_mat.set_shader_parameter("tex_bench", AssetLib.tex("red_laterite_soil_stones", "diff"))
	_terrain_mat.set_shader_parameter("nrm_bench", AssetLib.tex("red_laterite_soil_stones", "nor_gl"))
	_terrain_mat.set_shader_parameter("tex_sand", AssetLib.tex("sand_01", "diff"))
	_terrain_mat.set_shader_parameter("tex_crack", AssetLib.tex("mud_cracked_dry_03", "diff"))
	_terrain_mat.set_shader_parameter("tex_leaf", AssetLib.tex("leafy_grass", "diff"))
	_terrain_mat.set_shader_parameter("tex_soil", AssetLib.tex("farm_soil", "diff"))
	for k: String in ["ochre", "terracotta", "cream", "plum", "salt", "line"]:
		var u: String = {"ochre": "c_ochre", "terracotta": "c_terra", "cream": "c_cream", "plum": "c_plum", "salt": "c_salt", "line": "c_line"}[k]
		_terrain_mat.set_shader_parameter(u, _v3(_pal(k, Color.WHITE)))
	return _terrain_mat


## The pit and plateau as one ring mesh centred on the pit, in sectors for culling.
func _build_terrain() -> void:
	var rs: PackedFloat32Array = pit.rings()
	var nr: int = rs.size()
	var mat: ShaderMaterial = _tmat()
	@warning_ignore("integer_division")
	var per: int = SPOKES / SECTORS
	var lv_div: float = float(OchrePit.LEVELS - 1)
	for sct: int in SECTORS:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j: int in per + 1:
			var th: float = -PI + TAU * float(sct * per + j) / float(SPOKES)
			var sq: float = OchrePit.squash(th)
			for i: int in nr:
				var rho: float = rs[i]
				var s: Array = pit.sample(th, rho)
				var w: Vector2 = pit.world_at(th, rho)
				var y: float = s[0]
				# Under the play field's ground (and its wandering edge) the terrain tucks lower.
				var rw: float = w.length()
				if rw < r_clip + 12.0:
					y = minf(y, -0.06 - 0.35 * smoothstep(r_clip + 12.0, r_clip - 6.0, rw))
				st.set_color(Color(float(s[1]) / lv_div, s[2], s[3], s[4]))
				st.set_uv(Vector2(th * rho * sq, rho))
				st.add_vertex(Vector3(w.x, y, w.y))
		for j: int in per:
			for i: int in nr - 1:
				var a: int = j * nr + i
				var b: int = (j + 1) * nr + i
				for idx: int in [a, a + 1, b, b, a + 1, b + 1]:
					st.add_index(idx)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Pit%d" % sct
		mi.mesh = st.commit()
		mi.material_override = mat
		(_groups["always"] as Node3D).add_child(mi)


## Layered mesas and buttes on the plateau beyond the rim (same strata as the pit walls).
func _build_mesas() -> void:
	var mat: ShaderMaterial = _tmat()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed: Array[Vector3] = []
	var tries: int = 0
	var spokes: int = 44
	# Profile: [height fraction, radius fraction, flat]: talus apron, cliff, ledge, upper cliff, cap.
	var prof: Array = [[-0.06, 1.75, 0.0], [0.1, 1.3, 0.0], [0.2, 1.06, 0.0], [0.52, 1.0, 0.0], [0.56, 0.86, 1.0], [0.6, 0.8, 0.0], [0.93, 0.76, 0.0], [1.0, 0.7, 1.0], [1.0, 0.0, 1.0]]
	while placed.size() < 24 and tries < 600:
		tries += 1
		var ang: float = _rng.randf() * TAU
		var dist: float = _rng.randf_range(500.0, 1400.0)
		var c := Vector2(cos(ang), sin(ang)) * dist
		var rad: float = _rng.randf_range(45.0, 140.0) * (1.0 + dist / 2000.0)
		var pp: Vector2 = pit.polar_of(c.x, c.y)
		if pp.y < OchrePit.RIM_RHO + rad * 1.9 / OchrePit.squash(pp.x) + 25.0:
			continue
		var ok: bool = true
		for q: Vector3 in placed:
			if Vector2(q.x, q.y).distance_to(c) < (q.z + rad) * 1.5:
				ok = false
				break
		if not ok:
			continue
		placed.append(Vector3(c.x, c.y, rad))
		var hgt: float = _rng.randf_range(70.0, 170.0) * (0.8 + rad / 220.0)
		var y0: float = pit.height_at(c.x, c.y) - 3.0
		var lobes: float = _rng.randf_range(2.0, 4.0)
		var ph: float = _rng.randf() * TAU
		var elong: float = _rng.randf_range(1.0, 1.7)
		var rot: float = _rng.randf() * TAU
		var verts: Array = []
		for j: int in spokes + 1:
			var a: float = TAU * float(j) / spokes
			var col: Array = []
			for k: int in prof.size():
				var pr: Array = prof[k]
				var lob: float = 1.0 + 0.16 * sin(a * lobes + ph) + 0.07 * sin(a * 7.0 + ph * 2.0) + (_rng.randf() - 0.5) * 0.05 * (1.0 if k < 7 else 0.0)
				var rr: float = rad * float(pr[1]) * lob
				var lp := Vector2(cos(a) * rr * elong, sin(a) * rr).rotated(rot)
				var y: float = y0 + hgt * float(pr[0]) + (0.0 if k < 2 else (_rng.randf() - 0.5) * 1.2)
				col.append([Vector3(c.x + lp.x, y, c.y + lp.y), float(pr[2])])
			verts.append(col)
		for j: int in spokes:
			for k: int in prof.size() - 1:
				var q: Array = [verts[j][k], verts[j + 1][k], verts[j + 1][k + 1], verts[j][k + 1]]
				for idx: int in [0, 2, 1, 0, 3, 2]:
					var e: Array = q[idx]
					st.set_color(Color(0.0, e[1], 0.0, 0.0))
					st.set_uv(Vector2.ZERO)
					st.add_vertex(e[0])
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mesas"
	mi.mesh = st.commit()
	mi.material_override = mat
	(_groups["always"] as Node3D).add_child(mi)


## The pit-floor pond (sludge -> oasis).
func _build_pond() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = preload("res://planet/planets/ochre/ochre_water.gdshader")
	_water_mat.set_shader_parameter("oasis_deep", _v3(_pal("oasis", Color(0.1, 0.55, 0.54)) * 0.45))
	_water_mat.set_shader_parameter("oasis_shallow", _v3(_pal("oasis", Color(0.1, 0.55, 0.54)).lightened(0.3)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 72
	var y: float = OchrePit.FLOOR_Y - 0.28
	for i: int in n:
		var a0: float = TAU * i / n
		var a1: float = TAU * (i + 1) / n
		var c: Vector2 = OchrePit.CENTER
		var p0: Vector2 = pit.world_at(a0, OchrePit.POND_R + 2.0)
		var p1: Vector2 = pit.world_at(a1, OchrePit.POND_R + 2.0)
		for e: Array in [[c, 0.0], [p1, 1.0], [p0, 1.0]]:
			st.set_uv(Vector2(e[1], 0.0))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3((e[0] as Vector2).x, y, (e[0] as Vector2).y))
	var mi := MeshInstance3D.new()
	mi.name = "Pond"
	mi.mesh = st.commit()
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_groups["always"] as Node3D).add_child(mi)


## Haul roads: graded gravel lanes with a safety berm on the drop side and skirts into the rock.
func _build_ramps() -> void:
	var road := StandardMaterial3D.new()
	road.albedo_texture = AssetLib.tex("terrain_red_01", "diff")
	road.normal_enabled = true
	road.normal_texture = AssetLib.tex("terrain_red_01", "nor_gl")
	road.uv1_triplanar = true
	road.uv1_scale = Vector3.ONE * 0.18
	road.vertex_color_use_as_albedo = true
	road.roughness = 0.95
	road.albedo_color = Color(1.7, 1.45, 1.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var road_c := Color(0.95, 0.72, 0.52)
	var berm_c := Color(0.86, 0.62, 0.42)
	for r: Dictionary in pit.ramps:
		var segs: int = 60
		var hw: float = r["hw"]
		var prev: Array = []
		for k: int in segs + 1:
			var th: float = lerpf(float(r["th0"]), float(r["th1"]), float(k) / segs)
			var rr: Array = pit.ramp_at(r, th)
			if rr.is_empty():
				rr = pit.ramp_at(r, float(r["th1"]) - 0.0001)
			var y: float = rr[0]
			var rc: float = rr[1]
			var sq: float = OchrePit.squash(th)
			var cross: Array = []
			for e: Array in [[-hw - 1.2, -6.0, berm_c], [-hw - 0.7, 0.05, berm_c], [-hw - 0.1, 0.85, berm_c], [-hw + 0.6, 0.06, road_c], [hw, 0.06, road_c], [hw + 0.6, -5.0, berm_c]]:
				var w: Vector2 = pit.world_at(th, rc + float(e[0]) / sq)
				cross.append([Vector3(w.x, y + float(e[1]), w.y), e[2]])
			if not prev.is_empty():
				for c: int in cross.size() - 1:
					var q: Array = [prev[c], prev[c + 1], cross[c + 1], cross[c]]
					for idx: int in [0, 1, 2, 0, 2, 3]:
						st.set_color(q[idx][1])
						st.add_vertex(q[idx][0])
			prev = cross
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HaulRoads"
	mi.mesh = st.commit()
	mi.material_override = road
	(_groups["always"] as Node3D).add_child(mi)


# --- Machines --------------------------------------------------------------------------------------

func _m(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"paint_ruin":
			m = Mats.worn_paint(_pal("ledger_yellow", Color(0.86, 0.62, 0.12)), 0.42, 0.9, 3.0, 0.8)
		"paint_mid":
			m = Mats.worn_paint(_pal("ledger_yellow", Color(0.86, 0.62, 0.12)).lerp(Color(0.92, 0.7, 0.3), 0.3), 0.93, 0.18, 3.0, 0.35)
		"paint_future":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.9, 0.87, 0.8)
			w.roughness = 0.32
			w.metallic = 0.15
			w.clearcoat_enabled = true
			w.clearcoat = 0.4
			m = w
		"steel":
			m = Mats.metal("steel")
		"dark":
			m = Mats.metal("dark_steel")
		"glass":
			m = Mats.glass(Color(0.08, 0.1, 0.12, 0.95), 0.08)
		"concrete":
			m = AssetLib.pbr_material("concrete_wall_008", 0.25, Color(0.85, 0.78, 0.68), true)
		"terra":
			m = AssetLib.pbr_material("red_brick", 0.5, Color(0.95, 0.62, 0.48), true)
		"cream":
			var c := StandardMaterial3D.new()
			c.albedo_color = _pal("cream", Color(0.9, 0.8, 0.62)).lightened(0.15)
			c.roughness = 0.6
			m = c
		"leaf":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.5, 0.66, 0.36)
			g.albedo_texture = AssetLib.tex("leafy_grass", "diff")
			g.uv1_triplanar = true
			g.uv1_scale = Vector3.ONE * 0.6
			g.roughness = 0.85
			m = g
		"line":
			var l := StandardMaterial3D.new()
			l.albedo_color = _pal("line", Color(0.78, 0.94, 1.0))
			l.emission_enabled = true
			l.emission = _pal("line", Color(0.78, 0.94, 1.0))
			l.emission_energy_multiplier = 0.7
			m = l
		"vane":
			m = _sail_mat(_pal("cream", Color(0.9, 0.8, 0.62)).lightened(0.25), 0.0, 0.0, 0.0)
		"rubber":
			m = Mats.rubber()
		_:
			m = StandardMaterial3D.new()
	_mats[key] = m
	return m


func _sail_mat(cloth: Color, solar: float, wear: float, line: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://planet/planets/ochre/ochre_sail.gdshader")
	sm.set_shader_parameter("cloth", _v3(cloth))
	sm.set_shader_parameter("solar", solar)
	sm.set_shader_parameter("wear", wear)
	sm.set_shader_parameter("line_amt", line)
	sm.set_shader_parameter("line_col", _v3(_pal("line", Color(0.78, 0.94, 1.0))))
	_sail_mats.append(sm)
	return sm


func _machine_mats() -> Dictionary:
	var d: Dictionary = {}
	for k: String in ["steel", "dark", "glass", "concrete", "terra", "cream", "leaf", "line", "vane"]:
		d[k] = _m(k)
	d["paint"] = _m("paint_ruin")
	return d


## A frame for a machine at world xz: +X along `fwd`, crawlers along Z.
func _frame(xz: Vector2, fwd: Vector2, sink: float = 0.0) -> Transform3D:
	var x := Vector3(fwd.x, 0, fwd.y).normalized()
	var z: Vector3 = x.cross(Vector3.UP).normalized()
	return Transform3D(Basis(x, Vector3.UP, z) * Basis.from_scale(Vector3.ONE * 1.3), Vector3(xz.x, pit.height_at(xz.x, xz.y) - sink, xz.y))


func _build_excavators() -> void:
	var mats: Dictionary = _machine_mats()
	# E1: on the field bench east of the field, its wheel toward the pit floor.
	var e1 := Vector2(95.0, -20.0)
	var r1: Dictionary = OchreExcavator.build(_groups, _frame(e1, (OchrePit.CENTER - e1).normalized()), mats, "working", 1)
	_keep_out.append([e1 + (OchrePit.CENTER - e1).normalized() * 10.0, 40.0])
	# E2: high on the far wall, parked along its bench (clear of the haul roads).
	var bench_k: int = 4
	var rho2: float = OchrePit.FIELD_OUT + OchrePit.STEP_P * bench_k + OchrePit.WALL_W + (OchrePit.STEP_P - OchrePit.WALL_W) * 0.5
	var th2: float = -0.25
	for i: int in 30:
		var free: bool = OchrePit.squash(th2) > 1.1
		for ri: int in [bench_k, bench_k + 1]:
			if ri < pit.ramps.size():
				for dt: float in [-0.14, 0.0, 0.14, 0.28]:
					if not pit.ramp_at(pit.ramps[ri], th2 + dt).is_empty():
						free = false
		if free:
			break
		th2 -= 0.09
	var p2: Vector2 = pit.world_at(th2, rho2)
	var tan2: Vector2 = pit.world_at(th2 + 0.01, rho2) - p2
	var xf2: Transform3D = _frame(p2, tan2.normalized())
	if (xf2.basis.z.x * (OchrePit.CENTER.x - p2.x) + xf2.basis.z.z * (OchrePit.CENTER.y - p2.y)) < 0.0:
		xf2 = _frame(p2, -tan2.normalized())
	var r2: Dictionary = OchreExcavator.build(_groups, xf2, mats, "working", 2)
	# E3: toppled on the rim behind the field, its boom snapped along the edge.
	var th3: float = PI * 0.5 + 0.55
	var p3: Vector2 = pit.world_at(th3, OchrePit.RIM_RHO + 26.0)
	var tan3: Vector2 = (pit.world_at(th3 + 0.01, OchrePit.RIM_RHO + 26.0) - p3).normalized()
	var r3: Dictionary = OchreExcavator.build({"always": _groups["always"], "future": _groups["future"]}, _frame(p3, tan3, 0.4), mats, "fallen", 3)
	for r: Dictionary in [r1, r2, r3]:
		_paint.append_array(r["paint"])
		_wheels.append_array(r["wheels"])


## Abandoned haul trucks: rusted and tipped while ruined; parked and clean later; their dump beds
## planted up at the futuristic stage.
func _build_trucks() -> void:
	var spots: Array = [[Vector2(-78.0, 18.0), 0.6, false], [Vector2(-60.0, -58.0), 2.2, true], [Vector2(70.0, 42.0), -0.9, false]]
	var ruin := OchreProps.Batch.new()
	var tidy := OchreProps.Batch.new()
	var green := OchreProps.Batch.new()
	for s: Array in spots:
		var xz: Vector2 = s[0]
		if absf(pit.height_at(xz.x, xz.y)) > 0.6 or xz.length() < r_clip + 4.0:
			continue
		_keep_out.append([xz, 10.0])
		var base := Transform3D(Basis(Vector3.UP, float(s[1])), Vector3(xz.x, 0.0, xz.y))
		var tip: bool = s[2]
		_truck(ruin, base * (Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-78.0)), Vector3(0, 2.6, 0)) if tip else Transform3D()), _m("paint_ruin"), true)
		_truck(tidy, base, _m("paint_mid"), false)
		for k: int in 4:
			green.add(ProcMesh.sphere(1.0, 8, 4), base * ProcMesh.xf(Vector3(-2.4 + k * 1.3, 4.3, 0.0), Vector3.ZERO, Vector3(1.0, 0.8, 1.6)), _m("leaf"))
	ruin.flush(_groups["ruin"], true, 900.0)
	tidy.flush(_groups["up"], true, 900.0)
	green.flush(_groups["future"], true, 700.0)


func _truck(b: OchreProps.Batch, xf: Transform3D, paint: Material, ruined: bool) -> void:
	b.add(OchreProps.unit_box(), xf * ProcMesh.xf(Vector3(0, 1.9, 0), Vector3.ZERO, Vector3(11.0, 1.2, 4.6)), _m("dark"))
	b.add(OchreProps.unit_box(), xf * ProcMesh.xf(Vector3(-1.2, 3.6, 0), Vector3(0, 0, -6.0 if not ruined else -16.0), Vector3(8.0, 2.4, 5.2)), paint)
	b.add(OchreProps.unit_box(), xf * ProcMesh.xf(Vector3(4.2, 3.5, 1.2), Vector3.ZERO, Vector3(2.2, 2.4, 2.0)), paint)
	b.add(OchreProps.unit_box(), xf * ProcMesh.xf(Vector3(5.32, 3.9, 1.2), Vector3.ZERO, Vector3(0.05, 1.0, 1.6)), _m("glass"))
	for x: float in [-3.4, 3.6]:
		for z: float in [-2.4, 2.4]:
			if ruined and x > 0.0 and z > 0.0:
				continue
			b.add(ProcMesh.cyl(1.55, 1.55, 1.1, 14), xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 1.55, z)), _m("rubber"))


# --- Sails -----------------------------------------------------------------------------------------

func _ground_ok(p: Vector2, tol: float = 0.6) -> bool:
	return absf(pit.height_at(p.x, p.y)) < tol and p.length() > r_clip + 2.0


## Shade sails (mid on) round the field and over the pond; solar sails (futuristic) on the far
## benches and the rim, all on slim masts.
func _build_sails() -> void:
	var cloths: Array[Color] = [Color(0.95, 0.92, 0.85), _pal("terracotta", Color(0.66, 0.34, 0.2)).lightened(0.25), Color(0.93, 0.74, 0.38)]
	var mats_mid: Array[ShaderMaterial] = []
	var mats_fut: Array[ShaderMaterial] = []
	for c: Color in cloths:
		mats_mid.append(_sail_mat(c, 0.0, 0.7, 0.0))
		mats_fut.append(_sail_mat(c.lightened(0.1), 0.0, 0.0, 0.0))
	var poles := OchreProps.Batch.new()
	var poles_f := OchreProps.Batch.new()
	var mid_st: Array = []
	var fut_st: Array = []
	for i: int in 3:
		mid_st.append(_new_st())
		fut_st.append(_new_st())
	# Round the field, on the bench.
	var n_made: int = 0
	for i: int in 26:
		if n_made >= 9:
			break
		var a: float = TAU * i / 26.0 + 0.2
		var c := Vector2(cos(a), sin(a)) * (r_clip + _rng.randf_range(7.0, 16.0))
		if not _ground_ok(c):
			continue
		var corners: Array[Vector3] = []
		var ok: bool = true
		for k: int in 3:
			var ca: float = a + TAU * k / 3.0 + _rng.randf_range(-0.2, 0.2)
			var cp: Vector2 = c + Vector2(cos(ca), sin(ca)) * _rng.randf_range(4.5, 6.0)
			if not _ground_ok(cp, 0.8) and cp.length() > r_clip:
				ok = false
			corners.append(Vector3(cp.x, [3.2, 4.6, 5.4][(k + i) % 3], cp.y))
		if not ok:
			continue
		n_made += 1
		_keep_out.append([c, 3.0])
		var ci: int = i % 3
		for k: int in 3:
			var cc: Vector3 = corners[k]
			poles.beam(Vector3(cc.x, -0.2, cc.z), cc + Vector3(0, 0.25, 0), 0.12, _m("steel"))
		_sail_into(mid_st[ci], corners, 0.45)
		_sail_into(fut_st[ci], corners, 0.3)
	# Over the pond, on the floor.
	for i: int in 5:
		var a: float = TAU * i / 5.0 + 0.4
		var corners: Array[Vector3] = []
		for k: int in 3:
			var cp: Vector2 = pit.world_at(a + (k - 1) * 0.22, OchrePit.POND_R + 4.0 + float(k % 2) * 5.0)
			corners.append(Vector3(cp.x, OchrePit.FLOOR_Y + [3.5, 5.0, 4.2][k], cp.y))
		for cc: Vector3 in corners:
			poles.beam(Vector3(cc.x, OchrePit.FLOOR_Y - 0.3, cc.z), cc + Vector3(0, 0.25, 0), 0.12, _m("steel"))
		_sail_into(mid_st[i % 3], corners, 0.4)
		_sail_into(fut_st[i % 3], corners, 0.3)
	for i: int in 3:
		_flush_st(mid_st[i], mats_mid[i], _groups["mid"])
		_flush_st(fut_st[i], mats_fut[i], _groups["future"])
	poles.flush(_groups["up"], true, 700.0)
	# Solar sails: big dark membranes facing the pit centre, a thin light seam along each hem.
	var solar := _new_st()
	var solar_mat: ShaderMaterial = _sail_mat(Color(0.2, 0.22, 0.3), 1.0, 0.0, 0.9)
	for k: int in range(2, OchrePit.N_UP):
		var rho: float = OchrePit.FIELD_OUT + OchrePit.STEP_P * (k - 1) + OchrePit.WALL_W + (OchrePit.STEP_P - OchrePit.WALL_W) * 0.55
		var yb: float = OchrePit.STEP_H * k
		var th: float = -PI * 0.5 - 1.1 + _rng.randf() * 0.1
		while th < -PI * 0.5 + 1.1:
			var on_ramp: bool = false
			for r: Dictionary in pit.ramps:
				for dt: float in [-0.05, 0.0, 0.05]:
					if not pit.ramp_at(r, th + dt).is_empty() and absf(float(pit.ramp_at(r, th + dt)[1]) - rho) < 14.0:
						on_ramp = true
			if not on_ramp:
				var sq: float = OchrePit.squash(th)
				var w: float = 13.0 / (rho * sq)
				var p0: Vector2 = pit.world_at(th - w * 0.5, rho - 2.0 / sq)
				var p1: Vector2 = pit.world_at(th + w * 0.5, rho - 2.0 / sq)
				var p2: Vector2 = pit.world_at(th + w * 0.5, rho + 3.0 / sq)
				var p3: Vector2 = pit.world_at(th - w * 0.5, rho + 3.0 / sq)
				var corners: Array[Vector3] = [Vector3(p0.x, yb + 2.2, p0.y), Vector3(p1.x, yb + 2.2, p1.y), Vector3(p2.x, yb + 5.6, p2.y), Vector3(p3.x, yb + 5.6, p3.y)]
				_sail_into(solar, corners, 0.0)
				for cc: Vector3 in corners:
					poles_f.beam(Vector3(cc.x, yb - 0.3, cc.z), cc, 0.16, _m("paint_future"))
			th += 18.0 / (rho * OchrePit.squash(th))
	_flush_st(solar, solar_mat, _groups["future"])
	poles_f.flush(_groups["future"], true, 900.0)


func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _sail_into(st: SurfaceTool, corners: Array[Vector3], sag: float) -> void:
	var m: ArrayMesh = OchreProps.sail_mesh(corners, sag)
	var arr: Array = m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i: int in v.size():
		st.set_uv(uv[i])
		st.set_normal(nr[i])
		st.add_vertex(v[i])


func _flush_st(st: SurfaceTool, mat: Material, parent: Node3D) -> void:
	var m: ArrayMesh = st.commit()
	if m.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)


# --- Junk beyond the field ------------------------------------------------------------------------------

## The whole pit is trashed: tailings heaps, crate dumps, drill scrap and tyres over the field bench,
## the floor, the haul roads and every bench up to the rim. It clears level by level as the
## terraces are restored (from the floor up, like the greening), so the plants take its place.
## Placement works per site (centre + radius in pit space), so it can be repeated per hub.
func _build_ruin_junk() -> void:
	var meshes: Dictionary = OchreProps.junk_meshes()
	var ids: Array[String] = ["ochre_tailings", "ochre_tailings_b", "ochre_crate", "ochre_drill_rod", "ochre_crate_open", "ochre_drill_bit", "ochre_ore_sack", "ochre_bucket_tooth"]
	var lists: Dictionary = {}
	var lv_div: float = float(OchrePit.LEVELS - 1)
	var scale_q: float = [0.55, 0.8, 1.0, 1.0][clampi(Settings.quality, 0, 3)]
	var n_try: int = int(26000 * scale_q)
	for i: int in n_try:
		var th: float = _rng.randf() * TAU - PI
		# Denser near the field and on the floor; thinner up the walls.
		var rho: float = lerpf(OchrePit.FLOOR_R * 0.2, OchrePit.RIM_RHO + 30.0, pow(_rng.randf(), 1.6))
		var s: Array = pit.sample(th, rho)
		if float(s[2]) < 0.5 and rho < OchrePit.RIM_RHO:
			continue
		if rho < OchrePit.POND_R - 2.0:
			continue
		var w: Vector2 = pit.world_at(th, rho)
		if w.length() < r_clip + 0.5:
			continue
		var heap: bool = _rng.randf() < 0.07
		var id: String
		if heap:
			id = ids[_rng.randi() % 2]
		else:
			var r: float = _rng.randf()
			id = ids[0] if r < 0.3 else (ids[1] if r < 0.45 else ids[2 + _rng.randi() % (ids.size() - 2)])
		var big: float = (_rng.randf_range(5.0, 14.0) if heap else (_rng.randf_range(1.0, 2.8) if id.begins_with("ochre_tailings") else _rng.randf_range(1.0, 1.6)))
		var lie: Basis = Basis(Vector3.FORWARD, PI * 0.5) if id == "ochre_drill_rod" else Basis()
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * lie * Basis.from_scale(Vector3(big, big * (0.55 if heap else 1.0), big)), Vector3(w.x, float(s[0]) - (0.3 if heap else 0.05) + (0.1 if id == "ochre_drill_rod" else 0.0), w.y))
		var key: String = id + ("|heap" if heap else "")
		if not lists.has(key):
			lists[key] = []
		(lists[key] as Array).append([float(s[1]) / lv_div + _rng.randf() * 0.03, xf])
	for key: String in lists:
		var list: Array = lists[key]
		# Highest benches first: restoration removes from the end (the floor clears first).
		list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.get_slice("|", 0)]
		mm.instance_count = list.size()
		var lv := PackedFloat32Array()
		for i: int in list.size():
			mm.set_instance_transform(i, list[i][1])
			lv.append(-float(list[i][0]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Junk_%s" % key.replace("|", "_")
		mmi.multimesh = mm
		mmi.visibility_range_end = 900.0 if key.ends_with("heap") else 420.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if key.ends_with("heap") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_groups["always"] as Node3D).add_child(mmi)
		_junk.append([mm, lv])


## Junk stays where the terraces are not yet restored (instances sorted from the rim down).
func _update_junk() -> void:
	var reach: float = restore_shown * 1.15 - 0.04 if restore_shown > 0.01 else -1.0
	for p: Array in _junk:
		var mm: MultiMesh = p[0]
		var lv: PackedFloat32Array = p[1]  # -level, ascending
		var n: int = lv.bsearch(-reach) if reach >= 0.0 else lv.size()
		if mm.visible_instance_count != n:
			mm.visible_instance_count = n


## Futuristic: water spills from the terrace channels down the walls below at a few spots.
func _build_falls() -> void:
	_fall_mat = ShaderMaterial.new()
	_fall_mat.shader = preload("res://planet/planets/ochre/ochre_fall.gdshader")
	var st := _new_st()
	var walls: Array = []
	for b: Array in pit.bands:
		if bool(b[4]) and float(b[0]) > OchrePit.FIELD_OUT - 1.0:
			walls.append(b)
	for wi: int in walls.size():
		var b: Array = walls[wi]
		for n: int in 3:
			var th: float = TAU * (float(n) / 3.0 + float(wi) * 0.137) - PI
			if _on_ramp(th, float(b[0])) or _on_ramp(th, float(b[1]) + 2.0):
				continue
			var sq: float = OchrePit.squash(th)
			var hw: float = 1.3 / (float(b[0]) * sq)
			var rows: Array = []
			for k: int in 7:
				var f: float = float(k) / 6.0
				var rho: float = lerpf(float(b[1]) + 0.4, float(b[0]) - 0.6, f)
				var y: float = float(pit.profile(rho + 0.6)[0]) + 0.15
				var l: Vector2 = pit.world_at(th - hw, rho - 0.5)
				var r: Vector2 = pit.world_at(th + hw, rho - 0.5)
				rows.append([Vector3(l.x, y, l.y), Vector3(r.x, y, r.y), f])
			for k: int in 6:
				var a: Array = rows[k]
				var c: Array = rows[k + 1]
				for e: Array in [[a[0], 0.0, a[2]], [a[1], 1.0, a[2]], [c[1], 1.0, c[2]], [a[0], 0.0, a[2]], [c[1], 1.0, c[2]], [c[0], 0.0, c[2]]]:
					st.set_uv(Vector2(e[1], e[2]))
					st.set_normal(Vector3.UP)
					st.add_vertex(e[0])
	_flush_st(st, _fall_mat, _groups["future"])


# --- Plants (restoration) -----------------------------------------------------------------------------

func _blocked(w: Vector2) -> bool:
	if w.length() < r_clip + 3.0:
		return true
	for k: Array in _keep_out:
		if w.distance_to(k[0]) < float(k[1]):
			return true
	return false


func _on_ramp(th: float, rho: float) -> bool:
	for r: Dictionary in pit.ramps:
		var rr: Array = pit.ramp_at(r, th)
		if not rr.is_empty() and absf(rho - float(rr[1])) * OchrePit.squash(th) < float(r["hw"]) + 3.0:
			return true
	return false


## Palms and succulents on every bench, revealed level by level as the pit is restored (the
## floor and the field bench first). One MultiMesh per species and quarter of the pit.
func _build_plants() -> void:
	var species: Array = [
		["palm", [OchreProps.palm(1), OchreProps.palm(2), OchreProps.palm(3)], 420.0, 0.0],
		["agave", [OchreProps.agave(1), OchreProps.agave(2)], 190.0, 0.0],
		["barrel", [OchreProps.barrel_cactus()], 150.0, 0.0],
		["aloe", [OchreProps.aloe(1)], 170.0, 0.0],
	]
	# buckets[species][variant][quarter] -> Array of [lvl, xf]
	var buckets: Dictionary = {}
	var lv_div: float = float(OchrePit.LEVELS - 1)
	var count: int = 0
	for i: int in 5200:
		var th: float = _rng.randf() * TAU - PI
		var lvl_pick: int = _rng.randi() % OchrePit.LEVELS
		var rho: float
		var across: float
		if lvl_pick == 0:
			rho = _rng.randf_range(OchrePit.POND_R + 1.5, OchrePit.FLOOR_R - 1.0)
		elif lvl_pick == 2:
			rho = _rng.randf_range(OchrePit.FIELD_IN + 2.0, OchrePit.FIELD_OUT - 6.0)
		else:
			var band: Array = []
			for b: Array in pit.bands:
				if not bool(b[4]) and int(b[5]) == lvl_pick:
					band = b
			if band.is_empty():
				continue
			across = _rng.randf_range(0.14, 0.3) if _rng.randf() < 0.7 else _rng.randf_range(0.3, 0.8)
			rho = lerpf(float(band[0]), float(band[1]), across)
		var s: Array = pit.sample(th, rho)
		if float(s[2]) < 0.5 or _on_ramp(th, rho):
			continue
		var w: Vector2 = pit.world_at(th, rho)
		if _blocked(w):
			continue
		var sp: int
		var r: float = _rng.randf()
		if lvl_pick == 0:
			sp = 0 if r < 0.6 else 1
		elif lvl_pick == 2:
			sp = 0 if r < 0.22 else (1 if r < 0.55 else (2 if r < 0.8 else 3))
		else:
			sp = 0 if r < 0.12 else (1 if r < 0.5 else (2 if r < 0.75 else 3))
		var variants: Array = species[sp][1]
		var vi: int = _rng.randi() % variants.size()
		var q: int = int(fposmod(atan2(w.y - OchrePit.CENTER.y, w.x - OchrePit.CENTER.x) + PI, TAU) / (TAU / 4.0)) % 4
		var key: String = "%d|%d|%d" % [sp, vi, q]
		if not buckets.has(key):
			buckets[key] = []
		var scl: float = _rng.randf_range(0.8, 1.25) * (1.0 if sp > 0 else _rng.randf_range(0.85, 1.2))
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * scl), Vector3(w.x, float(s[0]) - 0.08, w.y))
		(buckets[key] as Array).append([float(s[1]) / lv_div + _rng.randf() * 0.02, xf])
		count += 1
	for key: String in buckets:
		var parts: PackedStringArray = key.split("|")
		var sp: int = int(parts[0])
		var list: Array = buckets[key]
		list.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = (species[sp][1] as Array)[int(parts[1])]
		mm.instance_count = list.size()
		var lv := PackedFloat32Array()
		for i: int in list.size():
			mm.set_instance_transform(i, list[i][1])
			lv.append(float(list[i][0]))
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Plants_%s" % str(species[sp][0])
		mmi.multimesh = mm
		mmi.visibility_range_end = float(species[sp][2])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sp == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(_groups["always"] as Node3D).add_child(mmi)
		_plants.append([mm, lv])
	print("[ochre] plants: %d in %d batches" % [count, _plants.size()])


func _update_plants() -> void:
	var reach: float = restore_shown * 1.15 - 0.04
	for p: Array in _plants:
		var mm: MultiMesh = p[0]
		var lv: PackedFloat32Array = p[1]
		var n: int = lv.bsearch(reach) if restore_shown > 0.01 else 0
		if mm.visible_instance_count != n:
			mm.visible_instance_count = n


# --- Particles and heat ------------------------------------------------------------------------------

func _build_fx() -> void:
	# Heat shimmer ring round the camera.
	_shimmer_mat = ShaderMaterial.new()
	_shimmer_mat.shader = preload("res://planet/planets/ochre/ochre_shimmer.gdshader")
	var cyl := CylinderMesh.new()
	cyl.top_radius = 140.0
	cyl.bottom_radius = 140.0
	cyl.height = 160.0
	cyl.radial_segments = 48
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_shimmer = MeshInstance3D.new()
	_shimmer.name = "HeatShimmer"
	_shimmer.mesh = cyl
	_shimmer.material_override = _shimmer_mat
	_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shimmer.extra_cull_margin = 400.0
	add_child(_shimmer)
	var scale_p: float = [0.5, 0.75, 1.0, 1.0][clampi(Settings.quality, 0, 3)]
	# Dust devils wandering the floor and the benches (ruined and mid).
	for i: int in 3:
		var d := CPUParticles3D.new()
		d.name = "DustDevil%d" % i
		d.amount = int(70 * scale_p)
		d.lifetime = 4.0
		d.local_coords = true
		d.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		d.emission_ring_axis = Vector3.UP
		d.emission_ring_radius = 1.2
		d.emission_ring_inner_radius = 0.4
		d.emission_ring_height = 0.5
		d.direction = Vector3.UP
		d.spread = 8.0
		d.gravity = Vector3.ZERO
		d.initial_velocity_min = 3.0
		d.initial_velocity_max = 5.0
		d.orbit_velocity_min = 0.6
		d.orbit_velocity_max = 0.9
		d.radial_accel_min = 0.6
		d.radial_accel_max = 1.2
		d.scale_amount_min = 1.2
		d.scale_amount_max = 3.2
		var crv := Curve.new()
		crv.add_point(Vector2(0, 0.3))
		crv.add_point(Vector2(0.4, 1.0))
		crv.add_point(Vector2(1, 0.0))
		d.scale_amount_curve = crv
		d.mesh = _puff_mesh(Color(0.86, 0.66, 0.44, 0.32))
		var th: float = TAU * i / 3.0 + 0.7
		var rho: float = [OchrePit.FLOOR_R - 10.0, OchrePit.FIELD_OUT - 30.0, OchrePit.FIELD_OUT + OchrePit.STEP_P * 2.6][i]
		var w: Vector2 = pit.world_at(th, rho)
		d.position = Vector3(w.x, pit.height_at(w.x, w.y), w.y)
		d.set_meta("th", th)
		d.set_meta("rho", rho)
		(_groups["always"] as Node3D).add_child(d)
		_devils.append(d)
	# Blowing grit near Lumi while ruined; drifting seed fluff once restored.
	_grit = CPUParticles3D.new()
	_grit.name = "Grit"
	_grit.amount = int(140 * scale_p)
	_grit.lifetime = 3.0
	_grit.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_grit.emission_box_extents = Vector3(4.0, 2.0, 18.0)
	_grit.direction = Vector3(1, 0.05, 0.3)
	_grit.spread = 10.0
	_grit.gravity = Vector3(0, -0.3, 0)
	_grit.initial_velocity_min = 7.0
	_grit.initial_velocity_max = 11.0
	_grit.scale_amount_min = 0.5
	_grit.scale_amount_max = 1.4
	_grit.mesh = _puff_mesh(Color(0.88, 0.7, 0.5, 0.22), 0.25)
	add_child(_grit)
	_fluff = CPUParticles3D.new()
	_fluff.name = "SeedFluff"
	_fluff.amount = int(40 * scale_p)
	_fluff.lifetime = 9.0
	_fluff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fluff.emission_box_extents = Vector3(16.0, 3.0, 16.0)
	_fluff.direction = Vector3(0.4, 0.3, 0.2)
	_fluff.spread = 40.0
	_fluff.gravity = Vector3(0, 0.02, 0)
	_fluff.initial_velocity_min = 0.3
	_fluff.initial_velocity_max = 0.8
	_fluff.scale_amount_min = 0.6
	_fluff.scale_amount_max = 1.0
	_fluff.mesh = _puff_mesh(Color(1.0, 0.97, 0.88, 0.7), 0.035)
	add_child(_fluff)


func _puff_mesh(col: Color, size: float = 1.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	m.albedo_texture = g
	q.material = m
	return q


# --- Stages ---------------------------------------------------------------------------------------------

## Shows the layers for a base level. Live: new layers rise in.
func set_level(l: int, animate: bool) -> void:
	level = clampi(l, 1, 5)
	var ranges: Dictionary = {"always": Vector2i(1, 5), "ruin": Vector2i(1, 1), "mid": Vector2i(2, 3), "up": Vector2i(2, 5), "future": Vector2i(4, 5)}
	for g: String in _groups:
		var node: Node3D = _groups[g]
		var r: Vector2i = ranges[g]
		var want: bool = level >= r.x and level <= r.y
		if want and not node.visible and animate:
			node.scale = Vector3(1, 0.02, 1)
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.visible = want
	var paint: Material = _m("paint_ruin") if level <= 1 else (_m("paint_mid") if level <= 3 else _m("paint_future"))
	for mi: MeshInstance3D in _paint:
		mi.material_override = paint
	for n: Node3D in _future_bits:
		n.visible = level >= 4
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("stage", float(level))


func _measure_restore() -> float:
	if DevHooks.has("ochre-restore"):
		return clampf(DevHooks.get_f("ochre-restore", 0.0), 0.0, 1.0)
	var hl: Node = world.get("hex_levels")
	if hl == null:
		return 0.0
	var levels: Variant = hl.get("levels")
	if not levels is Dictionary or (levels as Dictionary).is_empty():
		return 0.0
	var sum: float = 0.0
	for h: Variant in levels:
		sum += float(levels[h])
	return clampf(sum / maxf(float((levels as Dictionary).size()) * 5.0, 1.0), 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	_poll -= delta
	if _poll <= 0.0:
		_poll = 1.0
		restore = _measure_restore()
	restore_shown = move_toward(restore_shown, restore, delta * 0.08)
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("restore", restore_shown)
	if _water_mat:
		_water_mat.set_shader_parameter("clean", clampf(restore_shown * 3.0, 0.0, 1.0) if level >= 2 else minf(restore_shown * 2.0, 0.3))
	_update_plants()
	_update_junk()
	_grade(delta)
	for w: Node3D in _wheels:
		if level >= 4 and is_instance_valid(w):
			w.rotate_object_local(Vector3.BACK, delta * 0.12)
	var p: Node3D = world.get("patch")
	var dusty: bool = level <= 3 and restore_shown < 0.6
	for d: CPUParticles3D in _devils:
		d.emitting = dusty
		if dusty:
			var th: float = float(d.get_meta("th")) + delta * 0.01
			d.set_meta("th", th)
			var rho: float = float(d.get_meta("rho")) + sin(_t * 0.07 + th * 3.0) * delta * 0.4
			d.set_meta("rho", rho)
			var w2: Vector2 = pit.world_at(th, rho)
			d.position = Vector3(w2.x, pit.height_at(w2.x, w2.y), w2.y)
	if p:
		_grit.global_position = p.global_position + Vector3(-16.0, 1.2, 0.0)
		_fluff.global_position = p.global_position + Vector3(0, 2.5, 0)
	_grit.emitting = level <= 2 and restore_shown < 0.45
	_fluff.emitting = restore_shown > 0.35
	if DevHooks.has("ochre-cam") and world.get("hud") != null:
		(world.get("hud") as CanvasLayer).visible = false
	if DevHooks.has("ochre-debug") and fmod(_t, 5.0) < delta:
		var env: Environment = world.get("_env")
		print("[ochre] t=%.0f fog=%.4f col=%s aerial=%.2f sky=%s sun=%s %.2f amb=%.2f" % [_t, env.fog_density, env.fog_light_color, env.fog_aerial_perspective, env.sky.sky_material, world.get("_sun").light_color, world.get("_sun").light_energy, env.ambient_light_energy])
