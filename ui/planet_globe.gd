class_name PlanetGlobe
extends Node3D
## [globes] A reusable planet globe for any 3D view (telescope orrery, system map, story shots).
##   var g := PlanetGlobe.new(); add_child(g); g.setup("rime", 0.3)
##   g.set_restoration(0.8)
## Five planets (art/shaders/planet_<id>.gdshader): procedural 3D-noise relief with real normals
## (domain-warped FBM ranges and valleys, canyons, terraces, cracks), a night side, a soft
## terminator, an atmosphere rim shell, cloud layers where fitting, and ring/debris systems as
## MultiMeshes (Ochre's dust ring, Rime's ring of ice spikes, Anvil's fire ring of embers and ash).
## Lit by the binary suns: SolarSystem.suns_for() when that helper exists, else data/solar_system.json,
## else the canon defaults. Light directions come from the view (key light from the upper left of
## the active camera) unless the host calls set_sun_dirs() or track_suns() (orrery: real sun nodes).
## LOD: fewer noise octaves, coarser spheres and fewer debris instances when small on screen.
## Unknown ids get a generic rocky world (the Anvil shader, tinted, no seams).

const IDS: Array[String] = ["ochre", "verdance", "tidewell", "anvil", "rime"]
const SOLAR_PATH := "res://data/solar_system.json"
const OCTAVES: Array[int] = [4, 6, 8]
const SEGS: Array[Vector2i] = [Vector2i(40, 20), Vector2i(72, 36), Vector2i(128, 64)]
const MOTE_SHARE: Array[float] = [0.35, 0.7, 1.0]

## Per-planet look. Colours are linear-ish albedo; tilt in radians; spin in rad/s.
const CFG: Dictionary = {
	"verdance": {"seed": 3.7, "tilt": 0.41, "spin": 0.05, "au": 1.0,
		"clouds": {"col_ruin": Color(0.4, 0.32, 0.24), "col_ok": Color(0.94, 0.95, 0.97), "cover_ruin": 0.44, "cover_ok": 0.37, "opacity_ruin": 0.5, "opacity_ok": 0.88, "scale": 2.0, "band": 0.25, "storms": 1, "swirl": 0.8, "storm_size": 0.28},
		"atmo": {"col_ruin": Color(0.62, 0.45, 0.3), "col_ok": Color(0.32, 0.58, 1.0), "strength_ruin": 0.7, "strength_ok": 1.0, "thickness": 0.07}},
	"ochre": {"seed": 1.3, "face": -0.3, "tilt": 0.22, "spin": 0.035, "au": 0.62,
		"atmo": {"col_ruin": Color(0.95, 0.66, 0.38), "col_ok": Color(0.85, 0.7, 0.55), "strength_ruin": 0.75, "strength_ok": 0.7, "thickness": 0.09, "falloff": 0.45},
		"ring": "dust"},
	"tidewell": {"seed": 5.9, "tilt": 0.3, "spin": 0.06, "au": 1.55,
		"clouds": {"col_ruin": Color(0.72, 0.74, 0.74), "col_ok": Color(0.97, 0.98, 1.0), "cover_ruin": 0.42, "cover_ok": 0.38, "opacity_ruin": 0.8, "opacity_ok": 0.92, "scale": 2.3, "band": 0.45, "storms": 3, "swirl": 0.8, "storm_size": 0.34},
		"atmo": {"col_ruin": Color(0.42, 0.58, 0.8), "col_ok": Color(0.3, 0.56, 1.0), "strength_ruin": 0.9, "strength_ok": 1.05, "thickness": 0.07}},
	"anvil": {"seed": 8.2, "tilt": 0.44, "spin": 0.04, "au": 2.4,
		"clouds": {"col_ruin": Color(0.55, 0.36, 0.26), "col_ok": Color(0.85, 0.78, 0.72), "cover_ruin": 0.22, "cover_ok": 0.2, "opacity_ruin": 0.4, "opacity_ok": 0.5, "scale": 1.6, "band": 0.8, "storms": 0, "sharp": 0.2},
		"atmo": {"col_ruin": Color(0.85, 0.42, 0.25), "col_ok": Color(0.75, 0.55, 0.45), "strength_ruin": 0.55, "strength_ok": 0.6, "thickness": 0.05},
		"ring": "fire"},
	"rime": {"seed": 2.2, "tilt": 0.12, "spin": 0.025, "au": 3.9,
		"atmo": {"col_ruin": Color(0.62, 0.8, 1.0), "col_ok": Color(0.55, 0.85, 1.0), "strength_ruin": 0.5, "strength_ok": 0.6, "thickness": 0.04},
		"ring": "ice"},
}

## Visual radius (local units). The globe node itself is never scaled, so labels and markers that
## a host parents to it keep their size.
var radius: float = 1.0:
	set(v):
		radius = maxf(v, 0.001)
		if _tilt:
			_tilt.scale = Vector3.ONE * radius
## Highest LOD allowed (0..2); hosts lower it on weak hardware. lod_fixed >= 0 pins a level.
var max_lod: int = 2
var lod_fixed: int = -1
## Multiplies the planet's spin, cloud drift and ring rotation (0 freezes, e.g. for screenshots).
var spin_scale: float = 1.0

var planet_id: String = ""
var restoration: float = 0.0
var lod: int = -1

var _tilt: Node3D
var _body: Node3D
var _cloud_pivot: Node3D
var _ring_pivot: Node3D
var _surface: MeshInstance3D
var _clouds: MeshInstance3D
var _atmo: MeshInstance3D
var _mats: Array[ShaderMaterial] = []
var _surface_mat: ShaderMaterial
var _cloud_mat: ShaderMaterial
var _ring_mats: Array[ShaderMaterial] = []
var _multis: Array[MultiMeshInstance3D] = []
var _sun_nodes: Array[Node3D] = []
var _dirs_fixed: bool = false
var _dir_a: Vector3 = Vector3(-0.6, 0.35, 0.72).normalized()
var _dir_b: Vector3 = Vector3(-0.45, 0.3, 0.84).normalized()
var _col_a: Color = Color(1.0, 0.95, 0.85)
var _col_b: Color = Color(0.25, 0.155, 0.095)
var _sep_deg: float = 14.0
var _lod_t: float = 0.0
var _cfg: Dictionary = {}

static var _sphere_cache: Dictionary = {}
static var _shard_mesh: ArrayMesh
static var _sun_cache: Dictionary = {}


## Builds (or rebuilds) the globe for a planet id. tint only matters for unknown ids.
func setup(id: String, restoration_: float = 0.0, tint: Color = Color(0.0, 0.0, 0.0, 0.0)) -> PlanetGlobe:
	planet_id = id.to_lower()
	restoration = clampf(restoration_, 0.0, 1.0)
	_cfg = config(planet_id)
	_clear()
	_tilt = Node3D.new()
	_tilt.name = "Tilt"
	_tilt.rotation = Vector3(0.0, 0.0, float(_cfg.get("tilt", 0.3)))
	_tilt.scale = Vector3.ONE * radius
	add_child(_tilt)
	_body = Node3D.new()
	_body.name = "Body"
	_body.rotation.y = float(_cfg.get("face", float(_cfg.get("seed", 0.0)) * 1.3))
	_tilt.add_child(_body)
	_surface = _sphere_node(1.0, _surface_shader(planet_id))
	_surface_mat = _surface.material_override as ShaderMaterial
	_surface_mat.set_shader_parameter("seed", float(_cfg.get("seed", 0.0)))
	if not IDS.has(planet_id):
		var t: Color = tint if tint.a > 0.0 else Color(0.75, 0.7, 0.65)
		_param(_surface_mat, "tint", Color(t.r * 1.6, t.g * 1.6, t.b * 1.6))
		_surface_mat.set_shader_parameter("seams", 0.0)
	_body.add_child(_surface)
	var cl: Dictionary = _cfg.get("clouds", {})
	if not cl.is_empty():
		_cloud_pivot = Node3D.new()
		_cloud_pivot.name = "Clouds"
		_tilt.add_child(_cloud_pivot)
		_clouds = _sphere_node(1.012, preload("res://art/shaders/planet_clouds.gdshader"))
		_cloud_mat = _clouds.material_override as ShaderMaterial
		_cloud_mat.render_priority = 1
		_cloud_mat.set_shader_parameter("seed", float(_cfg.get("seed", 0.0)) + 2.0)
		for k: String in cl:
			_param(_cloud_mat, k, cl[k])
		_cloud_pivot.add_child(_clouds)
	var at: Dictionary = _cfg.get("atmo", {})
	var th: float = float(at.get("thickness", 0.06))
	_atmo = _sphere_node(1.0 + th, preload("res://art/shaders/planet_atmo.gdshader"))
	var am: ShaderMaterial = _atmo.material_override as ShaderMaterial
	am.render_priority = 2
	for k: String in at:
		_param(am, k, at[k])
	_tilt.add_child(_atmo)
	_ring_pivot = Node3D.new()
	_ring_pivot.name = "Ring"
	_tilt.add_child(_ring_pivot)
	match str(_cfg.get("ring", "")):
		"dust":
			_build_dust_ring()
		"ice":
			_build_ice_ring()
		"fire":
			_build_fire_ring()
	_load_suns()
	lod = -1
	_apply_lod(lod_fixed if lod_fixed >= 0 else 1)
	set_restoration(restoration)
	_sync()
	return self


func set_restoration(f: float) -> void:
	restoration = clampf(f, 0.0, 1.0)
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("restoration", restoration)
	# Anvil's fire ring cools as the foundries go quiet; Ochre's dust settles a little.
	var ring: String = str(_cfg.get("ring", ""))
	for mm: MultiMeshInstance3D in _multis:
		var mat: ShaderMaterial = mm.material_override as ShaderMaterial
		if ring == "fire":
			mat.set_shader_parameter("intensity", lerpf(1.6, 0.7, restoration))
	for m: ShaderMaterial in _ring_mats:
		if ring == "dust":
			m.set_shader_parameter("opacity", lerpf(0.34, 0.24, restoration))
		elif ring == "fire":
			_param(m, "ember", Color(0.09, 0.025, 0.006) * lerpf(1.0, 0.4, restoration))


## Fixed light directions (world space, pointing from the planet towards each sun).
func set_sun_dirs(a: Vector3, b: Vector3) -> void:
	_dirs_fixed = true
	_sun_nodes.clear()
	_dir_a = a.normalized()
	_dir_b = b.normalized()
	_sync()


## Light from two nodes in the same world (the orrery's sun meshes); re-aimed every frame.
func track_suns(a: Node3D, b: Node3D) -> void:
	_sun_nodes = [a, b]
	_dirs_fixed = true
	_sync()


func set_sun_colors(a: Color, b: Color) -> void:
	_col_a = a
	_col_b = b
	_sync()


## Pins a LOD level (0 low .. 2 high); -1 returns to automatic (screen size).
func set_lod(level: int) -> void:
	lod_fixed = level
	if level >= 0:
		_apply_lod(level)


static func config(id: String) -> Dictionary:
	if CFG.has(id):
		return CFG[id]
	return {"seed": float(absi(id.hash()) % 97) * 0.1, "tilt": 0.25, "spin": 0.04, "au": 2.0,
		"atmo": {"col_ruin": Color(0.6, 0.62, 0.7), "col_ok": Color(0.45, 0.65, 1.0), "strength_ruin": 0.5, "strength_ok": 0.7, "thickness": 0.05}}


static func _surface_shader(id: String) -> Shader:
	match id:
		"verdance":
			return preload("res://art/shaders/planet_verdance.gdshader")
		"ochre":
			return preload("res://art/shaders/planet_ochre.gdshader")
		"tidewell":
			return preload("res://art/shaders/planet_tidewell.gdshader")
		"rime":
			return preload("res://art/shaders/planet_rime.gdshader")
	return preload("res://art/shaders/planet_anvil.gdshader")


## The two suns' colours as this planet sees them: SolarSystem.suns_for() if present, else the solar
## system file, else the canon (warm primary, cooler orange companion, 14 degrees apart). Energies
## fall off with orbit distance, softened for a UI view (Rime still reads, Ochre doesn't blow out).
static func sun_light(id: String) -> Dictionary:
	if _sun_cache.has(id):
		return _sun_cache[id]
	var ca := Color(1.0, 0.95, 0.85)
	var cb := Color(1.0, 0.62, 0.38)
	var ea: float = 1.0
	var eb: float = 0.25
	var sep: float = 14.0
	var au: float = float(config(id).get("au", 1.0))
	var have: bool = false
	var ss: Variant = _solar_system_suns(id)
	if ss is Dictionary and (ss as Dictionary).has("a") and (ss as Dictionary).has("b"):
		var a: Dictionary = ss["a"] if ss["a"] is Dictionary else {}
		var b: Dictionary = ss["b"] if ss["b"] is Dictionary else {}
		if a.get("color") is Color:
			ca = a["color"]
		if b.get("color") is Color:
			cb = b["color"]
		ea = float(a.get("energy", ea))
		eb = float(b.get("energy", eb))
		if a.get("dir") is Vector3 and b.get("dir") is Vector3 and (a["dir"] as Vector3).length() > 0.0 and (b["dir"] as Vector3).length() > 0.0:
			sep = clampf(rad_to_deg((a["dir"] as Vector3).angle_to(b["dir"])), 2.0, 40.0)
		have = true
	if not have:
		var d: Dictionary = {}
		if FileAccess.file_exists(SOLAR_PATH):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOLAR_PATH))
			d = j if j is Dictionary else {}
		var sa: Dictionary = d.get("star_a", {}) if d.get("star_a") is Dictionary else {}
		var sb: Dictionary = d.get("star_b", {}) if d.get("star_b") is Dictionary else {}
		ca = _col(sa.get("color"), ca)
		cb = _col(sb.get("color"), cb)
		ea = float(sa.get("energy", sa.get("base_intensity", ea)))
		eb = float(sb.get("energy", sb.get("base_intensity", eb)))
		var pl: Variant = d.get("planets", null)
		var pd: Dictionary = {}
		if pl is Dictionary and (pl as Dictionary).get(id) is Dictionary:
			pd = (pl as Dictionary)[id]
		elif pl is Array:
			for e: Variant in pl:
				if e is Dictionary and str((e as Dictionary).get("id", "")).to_lower() == id:
					pd = e
		au = float(pd.get("orbit_au", au))
		sep = float(pd.get("sun_separation", pd.get("sun_separation_deg", sep)))
		var k: float = clampf(1.0 / pow(maxf(au, 0.3), 0.6), 0.35, 1.5)
		ea *= k
		eb *= k
	# Soften for a UI view: half the falloff, then a floor so the far worlds still read.
	var ui_a: float = clampf(lerpf(1.0, ea, 0.45), 0.72, 1.3)
	var ui_b: float = clampf(eb / maxf(ea, 0.01), 0.1, 0.6) * ui_a
	var r: Dictionary = {"a": Color(ca.r * ui_a, ca.g * ui_a, ca.b * ui_a), "b": Color(cb.r * ui_b, cb.g * ui_b, cb.b * ui_b), "sep": sep}
	_sun_cache[id] = r
	return r


static func _solar_system_suns(id: String) -> Variant:
	for gc: Dictionary in ProjectSettings.get_global_class_list():
		if str(gc.get("class", "")) == "SolarSystem":
			var scr: Variant = load(str(gc["path"]))
			if scr is GDScript:
				for m: Dictionary in (scr as GDScript).get_script_method_list():
					if str(m.get("name", "")) == "suns_for":
						return (scr as GDScript).call("suns_for", id)
			break
	return null


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is String and (v as String).begins_with("#"):
		return Color(str(v))
	return fallback


# --- Build ---------------------------------------------------------------------------------------

func _clear() -> void:
	for c: Node in get_children():
		if c == _tilt:
			remove_child(c)
			c.free()
	_tilt = null
	_mats.clear()
	_ring_mats.clear()
	_multis.clear()
	_clouds = null
	_cloud_mat = null
	_cloud_pivot = null


## Colours go to the shaders as plain linear vec3 (no sRGB conversion).
static func _param(m: ShaderMaterial, k: String, v: Variant) -> void:
	if v is Color:
		var c: Color = v
		m.set_shader_parameter(k, Vector3(c.r, c.g, c.b))
	else:
		m.set_shader_parameter(k, v)


func _sphere_node(r: float, shader: Shader) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere(r, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("globe_r", r)
	var m := ShaderMaterial.new()
	m.shader = shader
	mi.material_override = m
	_mats.append(m)
	return mi


static func _sphere(r: float, level: int) -> SphereMesh:
	var key: String = "%.4f/%d" % [r, level]
	if _sphere_cache.has(key):
		return _sphere_cache[key]
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = SEGS[level].x
	s.rings = SEGS[level].y
	_sphere_cache[key] = s
	return s


func _ring_mesh(r0: float, r1: float, segs: int = 160) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in segs:
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var p00 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		for v: Array in [[p00, 0.0], [p01, 1.0], [p11, 1.0], [p00, 0.0], [p11, 1.0], [p10, 0.0]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(v[1]), 0.0))
			st.add_vertex(v[0])
	return st.commit()


func _add_ring_band(r0: float, r1: float, params: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(r0, r1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/planet_ring.gdshader")
	m.render_priority = 3
	m.set_shader_parameter("seed", float(_cfg.get("seed", 0.0)))
	for k: String in params:
		_param(m, k, params[k])
	mi.material_override = m
	_mats.append(m)
	_ring_mats.append(m)
	_ring_pivot.add_child(mi)


## A ring of billboard motes. custom = phase, heat, brightness.
func _add_motes(count: int, r0: float, r1: float, thick: float, size_min: float, size_max: float, params: Dictionary, heat_bias: float, rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = count
	for i: int in count:
		var a: float = rng.randf() * TAU
		var r: float = lerpf(r0, r1, pow(rng.randf(), 0.85))
		var y: float = rng.randfn(0.0, thick)
		var s: float = lerpf(size_min, size_max, pow(rng.randf(), 2.2))
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(cos(a) * r, y, sin(a) * r)))
		mm.set_instance_custom_data(i, Color(rng.randf(), clampf(rng.randf() + heat_bias, 0.0, 1.0), lerpf(0.35, 1.0, rng.randf()), 0.0))
	_add_multi(mm, preload("res://art/shaders/planet_motes.gdshader"), params, 4)


func _add_multi(mm: MultiMesh, shader: Shader, params: Dictionary, prio: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = prio
	for k: String in params:
		_param(m, k, params[k])
	mmi.material_override = m
	mmi.set_meta("count", mm.instance_count)
	_mats.append(m)
	_multis.append(mmi)
	_ring_pivot.add_child(mmi)
	return mmi


func _build_dust_ring() -> void:
	# Ochre: a faint sand/dust ring with a wider haze of drifting grains trailing around it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7101
	_ring_pivot.rotation = Vector3(0.18, 0.0, -0.1)
	_add_ring_band(1.42, 2.55, {"col_a": Color(0.92, 0.72, 0.46), "col_b": Color(0.62, 0.42, 0.24), "opacity": 0.34, "band_freq": 30.0, "gaps": 0.55, "clumps": 0.35, "scatter": 1.6, "outer_fade": 0.5})
	_add_ring_band(1.3, 3.0, {"col_a": Color(0.85, 0.66, 0.44), "col_b": Color(0.7, 0.5, 0.32), "opacity": 0.07, "band_freq": 6.0, "gaps": 0.2, "clumps": 0.7, "scatter": 2.2, "inner_fade": 0.3, "outer_fade": 0.6})
	_add_motes(700, 1.35, 3.0, 0.07, 0.006, 0.018, {"col_hot": Color(1.0, 0.86, 0.62), "col_cool": Color(0.9, 0.7, 0.45), "intensity": 0.55, "flicker": 0.15, "sunlit": 1.0}, 0.0, rng)


func _build_ice_ring() -> void:
	# Rime: an orbiting ring of ice spikes and shards, faint ice dust and glitter.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407
	_ring_pivot.rotation = Vector3(0.3, 0.0, 0.08)
	_add_ring_band(1.5, 2.4, {"col_a": Color(0.85, 0.93, 1.0), "col_b": Color(0.6, 0.75, 0.95), "opacity": 0.13, "band_freq": 40.0, "gaps": 0.6, "clumps": 0.3, "scatter": 1.4})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = shard_mesh()
	var n: int = 520
	mm.instance_count = n
	for i: int in n:
		var a: float = rng.randf() * TAU
		var t: float = rng.randf()
		var r: float = lerpf(1.58, 2.3, t)
		# clumpier near the middle of the band
		r = lerpf(r, 1.94, 0.35 * rng.randf())
		var pos := Vector3(cos(a) * r, rng.randfn(0.0, 0.035), sin(a) * r)
		var big: bool = rng.randf() < 0.12
		var len_: float = rng.randf_range(0.05, 0.12) * (2.2 if big else 1.0)
		var wid: float = len_ * rng.randf_range(0.22, 0.4)
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length() < 0.01:
			axis = Vector3.UP
		var basis := Basis(axis.normalized(), rng.randf() * TAU) * Basis.from_euler(Vector3(rng.randf() * TAU, 0.0, rng.randf() * TAU))
		basis = basis * Basis().scaled(Vector3(wid, len_, wid))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf() * (1.5 if big else 0.6), 0.0, 0.0))
	_add_multi(mm, preload("res://art/shaders/planet_shard.gdshader"), {}, 0)
	_add_motes(500, 1.5, 2.45, 0.05, 0.005, 0.014, {"col_hot": Color(0.85, 0.95, 1.0), "col_cool": Color(0.6, 0.8, 1.0), "intensity": 0.9, "flicker": 0.6, "sunlit": 1.0}, 0.0, rng)


func _build_fire_ring() -> void:
	# Anvil: a band of glowing embers and ash from the foundries; thin and subtle.
	var rng := RandomNumberGenerator.new()
	rng.seed = 9203
	_ring_pivot.rotation = Vector3(-0.22, 0.0, 0.12)
	_add_ring_band(1.38, 2.15, {"col_a": Color(0.36, 0.3, 0.27), "col_b": Color(0.16, 0.13, 0.12), "opacity": 0.22, "band_freq": 26.0, "gaps": 0.5, "clumps": 0.55, "scatter": 0.8, "ember": Color(0.09, 0.025, 0.006)})
	_add_motes(900, 1.4, 2.12, 0.04, 0.008, 0.026, {"col_hot": Color(1.0, 0.62, 0.26), "col_cool": Color(0.75, 0.16, 0.03), "intensity": 1.6, "flicker": 0.7, "sunlit": 0.0}, -0.15, rng)


## A tall faceted ice spike (hexagonal bipyramid, long point up), flat shaded. Unit length.
static func shard_mesh() -> ArrayMesh:
	if _shard_mesh:
		return _shard_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 0.62, 0.0)
	var bot := Vector3(0.0, -0.38, 0.0)
	var ring: Array[Vector3] = []
	for i: int in 6:
		var a: float = TAU * float(i) / 6.0
		ring.append(Vector3(cos(a) * 0.5, 0.0 + 0.04 * float(i % 2), sin(a) * 0.5))
	for i: int in 6:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 6]
		st.add_vertex(top)
		st.add_vertex(p1)
		st.add_vertex(p0)
		st.add_vertex(bot)
		st.add_vertex(p0)
		st.add_vertex(p1)
	st.generate_normals()
	_shard_mesh = st.commit()
	return _shard_mesh


# --- Runtime -------------------------------------------------------------------------------------

func _load_suns() -> void:
	var s: Dictionary = sun_light(planet_id)
	_col_a = s["a"]
	_col_b = s["b"]
	_sep_deg = float(s["sep"])


func _ready() -> void:
	if planet_id.is_empty() and _tilt == null:
		return
	_sync()


func _process(delta: float) -> void:
	if _tilt == null:
		return
	var sp: float = float(_cfg.get("spin", 0.04)) * spin_scale
	_body.rotation.y += sp * delta
	if _cloud_pivot:
		_cloud_pivot.rotation.y += sp * 1.22 * delta
	if _ring_pivot:
		_ring_pivot.rotate_object_local(Vector3.UP, sp * 0.8 * delta)
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.3
		if lod_fixed < 0:
			_apply_lod(_auto_lod())
	_sync()


## Screen radius in pixels -> LOD level.
func _auto_lod() -> int:
	var vp: Viewport = get_viewport()
	if vp == null:
		return 1
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null or not is_inside_tree():
		return 1
	var h: float = vp.get_visible_rect().size.y
	var rw: float = radius * global_transform.basis.get_scale().x
	var px: float
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		px = rw / maxf(cam.size * 0.5, 1e-3) * h * 0.5
	else:
		var d: float = maxf(cam.global_position.distance_to(global_position) - rw, 0.01)
		px = rw / (d * tan(deg_to_rad(cam.fov) * 0.5)) * h * 0.5
	if px < 48.0:
		return 0
	if px < 190.0:
		return 1
	return 2


func _apply_lod(level: int) -> void:
	level = clampi(level, 0, max_lod)
	if level == lod:
		return
	lod = level
	for mi: MeshInstance3D in [_surface, _clouds, _atmo]:
		if mi:
			mi.mesh = _sphere(float(mi.get_meta("globe_r", 1.0)), level)
	if _surface_mat:
		_surface_mat.set_shader_parameter("octaves", OCTAVES[level])
	if _cloud_mat:
		_cloud_mat.set_shader_parameter("octaves", OCTAVES[level] - 1)
	for mmi: MultiMeshInstance3D in _multis:
		var n: int = int(mmi.get_meta("count", mmi.multimesh.instance_count))
		mmi.multimesh.visible_instance_count = maxi(int(float(n) * MOTE_SHARE[level]), 1)


func _sync() -> void:
	if _tilt == null:
		return
	if _sun_nodes.size() == 2 and is_instance_valid(_sun_nodes[0]) and is_instance_valid(_sun_nodes[1]) and is_inside_tree():
		var c: Vector3 = global_position
		var da: Vector3 = _sun_nodes[0].global_position - c
		var db: Vector3 = _sun_nodes[1].global_position - c
		if da.length() > 1e-4 and db.length() > 1e-4:
			_dir_a = da.normalized()
			_dir_b = db.normalized()
	elif not _dirs_fixed:
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() else null
		var bx: Basis = cam.global_transform.basis if cam else Basis()
		# Key light from the upper left of the view, a little behind the planet's limb.
		_dir_a = (bx * Vector3(-0.82, 0.34, 0.46)).normalized()
		_dir_b = _dir_a.rotated((bx * Vector3.UP).normalized(), deg_to_rad(_sep_deg)).normalized()
	var rw: float = radius * (global_transform.basis.get_scale().x if is_inside_tree() else 1.0)
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("sun_a_dir", _dir_a)
		m.set_shader_parameter("sun_b_dir", _dir_b)
		m.set_shader_parameter("sun_a_col", Vector3(_col_a.r, _col_a.g, _col_a.b))
		m.set_shader_parameter("sun_b_col", Vector3(_col_b.r, _col_b.g, _col_b.b))
		m.set_shader_parameter("planet_r_world", rw)
