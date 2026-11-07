class_name AnvilEnv
extends Node3D
## [planet-anvil] Anvil, the Rust World: the Ledger's foundry world and the last planet.
## A thin butterscotch sky with two small, dim suns (the system's binary star, far out here) and
## twin tiny moons; iron-oxide dust plains, layered mesas and a canyon; colossal foundry stacks,
## slag heaps, conveyor gantries and the depleted core shaft (a vast, dimly glowing pit) as the
## landmark; rusted mining haulers half-buried in the dust; dust devils and drifting red haze.
## Restored, the dust gives way to lichen, red-leaf plants and green, domed greenhouses and wind
## turbines go up, the stacks become vertical gardens with thin warm-white light lines, the core
## glows warm again and the sky clears toward a pale terraformed blue.
##
## Entry points (static):
##   prepare_field(field, kind)  before HexField.generate(): Anvil's junk models and landmarks
##   prepare_view(view, kind)    before FieldView.setup(): ground layers, dust ripples, no hills
##   apply(world, field, kind)   once the district is built: everything else (works without the
##                               two above, minus junk swaps and the default horizon hills)
## Stages follow the base level like FrontierView (ruin 1, mid 2-3, up 2-5, high 3-5, future
## 4-5); terrain greening, plants, sky, haze and the core glow follow the district's mean hex
## level (`restore`, 0..1). Pure helpers (restore_of, stage_visible) are unit tested.

const ID := "anvil"
const BIOME := "anvil_foundry"
const DATA_PATH := "res://planet/planets/anvil/anvil.json"
const PLANETS_PATH := "res://data/planets.json"
const STAGES := {"always": Vector2i(1, 5), "ruin": Vector2i(1, 1), "mid": Vector2i(2, 3), "up": Vector2i(2, 5), "high": Vector2i(3, 5), "future": Vector2i(4, 5)}
const EMBER := Color(1.0, 0.36, 0.12)
const CORE_WARM := Color(1.0, 0.82, 0.55)
const PIT_R: float = 78.0
const SHAFT_K: float = 0.42
const PIT_DEPTH: float = 62.0
const RIM_Y: float = 1.2

var world: Node
var field: HexField
var kind: Dictionary = {}
var entry: Dictionary = {}   # data/planets.json "anvil"
var look: Dictionary = {}    # anvil.json
var level: int = 1
var restore: float = 0.0
var shown: float = -1.0      # eased restore actually shown
var r_in: float = 55.0
var pit_c := Vector3.ZERO
var groups: Dictionary = {}
var mats: Dictionary = {}
var rotors: Array[Node3D] = []
var stacks: Array[Dictionary] = []
var terrain_mat: ShaderMaterial
var slag_mat: ShaderMaterial

var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()
var _core_mat: ShaderMaterial
var _core_floor: StandardMaterial3D
var _plants: Array[MultiMeshInstance3D] = []
var _plant_n: PackedInt32Array = PackedInt32Array()
var _devils: Array[Dictionary] = []
var _haze: CPUParticles3D
var _motes: CPUParticles3D
var _moons: Array[Node3D] = []
var _sun_b: DirectionalLight3D
var _suns: Dictionary = {}
var _t: float = 0.0
var _tick: float = 99.0
var _rng := RandomNumberGenerator.new()


# --- Static entry points ---------------------------------------------------------------------

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


static func planet_entry() -> Dictionary:
	return load_json(PLANETS_PATH).get(ID, {})


static func prepare_field(p_field: HexField, _kind: Dictionary = {}) -> void:
	var lk: Dictionary = load_json(DATA_PATH)
	Economy.biome_sets[BIOME] = lk.get("biome_set", {})
	p_field.biome = BIOME
	p_field.biome_set = Economy.biome_set(BIOME)


static func prepare_view(view: FieldView, _kind: Dictionary = {}) -> void:
	var lk: Dictionary = load_json(DATA_PATH)
	view.layer_swap = lk.get("ground_layers", {})
	var fx: Array = lk.get("fx", [0, 0, 0, 0])
	view.ground_fx = Vector4(float(fx[0]), float(fx[1]), float(fx[2]), float(fx[3]))
	view.skip_horizon = true


static func apply(p_world: Node, p_field: HexField, p_kind: Dictionary) -> void:
	var env := AnvilEnv.new()
	env.name = "AnvilEnv"
	env.world = p_world
	env.field = p_field
	env.kind = p_kind
	p_world.add_child(env)
	env.build()


## Mean hex level / 5 over the tracked land hexes (0 ruined .. 1 every hex Thriving).
static func restore_of(levels: Dictionary) -> float:
	if levels.is_empty():
		return 0.0
	var s: float = 0.0
	for h: Variant in levels:
		s += clampf(float(levels[h]), 0.0, 5.0)
	return s / (levels.size() * 5.0)


static func stage_visible(stage: String, lvl: int) -> bool:
	var r: Vector2i = STAGES.get(stage, Vector2i(1, 5))
	return lvl >= r.x and lvl <= r.y


static func _smooth(a: float, b: float, x: float) -> float:
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func polar(ang: float, dist: float, y: float = 0.0) -> Vector3:
	return Vector3(cos(ang) * dist, y, sin(ang) * dist)


static func col(a: Variant, fallback: Color) -> Color:
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if (a as Array).size() > 3 else 1.0)
	return fallback


# --- Build -----------------------------------------------------------------------------------

func build() -> void:
	process_priority = 20  # after SkyDirector: the sun tweaks sit on top of its day cycle
	entry = planet_entry()
	entry.merge(kind, true)
	look = load_json(DATA_PATH)
	_rng.seed = field.seed_value + 7071
	r_in = field.hex_size * (float(field.radius) + 0.55) * Hex.SQRT3 + 2.0
	pit_c = polar(-PI * 0.5 + 0.28, 250.0)
	for k: int in 3:
		var nz: FastNoiseLite = [_n1, _n2, _n3][k]
		nz.seed = field.seed_value + 313 * (k + 1)
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = 3
		nz.frequency = [0.0032, 0.012, 0.006][k]
	for g: String in STAGES:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		groups[g] = n
	level = int(world.hub.level) if world.get("hub") != null else 1
	_open_camera()
	_sky()
	_ground()
	_build_terrain()
	_build_pit()
	AnvilProps.build_all(self)
	_build_plants()
	_build_particles()
	_build_moons()
	set_level(level, false)
	if world.get("hub") != null:
		(world.hub as Hub).level_changed.connect(func(l: int) -> void: set_level(l, true))
	_refresh()
	_dev_hooks()
	var meshes: int = find_children("*", "MeshInstance3D", true, false).size()
	print("[planet-anvil] env ready: level %d restore %.2f meshes %d plants %d" % [level, restore, meshes, _plants.size()])


func set_level(l: int, animate: bool) -> void:
	level = clampi(l, 1, 5)
	for g: String in groups:
		var node: Node3D = groups[g]
		var want: bool = stage_visible(g, level)
		if want and not node.visible and animate:
			node.scale = Vector3(1, 0.02, 1)
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.visible = want


func mat(key: String) -> Material:
	if mats.has(key):
		return mats[key]
	var m: Material = AnvilProps.make_mat(self, key)
	mats[key] = m
	return m


# --- Camera, sky, suns ----------------------------------------------------------------------

func _open_camera() -> void:
	var rig: Node = world.get("cam")
	var cam: Camera3D = rig.get("camera") if rig else null
	if cam == null:
		return
	cam.far = 2600.0
	var attrs: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = 280.0
		attrs.dof_blur_far_transition = 420.0
		attrs.dof_blur_amount = 0.03


## The grade SkyDirector blends over its day cycle (see SkyDirector._apply_grade).
func sky_grade() -> Dictionary:
	var s: Dictionary = entry.get("sky", {})
	var f: Dictionary = entry.get("fog", {})
	var g: Dictionary = {
		"rayleigh": s.get("rayleigh", [0.98, 0.66, 0.42]), "mie": s.get("mie", [0.62, 0.74, 0.98]),
		"sky_amt": float(s.get("sky_amt", 0.85)), "turbidity": float(s.get("turbidity", 5.0)),
		"mie_coef": float(s.get("mie_coef", 0.004)), "sat": float(s.get("sat", 0.95)),
		"exposure": float(s.get("exposure", 1.0)), "contrast": float(s.get("contrast", 1.08)),
		"fog": f.get("color", [0.9, 0.6, 0.44]), "fog_amt": float(f.get("amt", 0.85)),
		"fog_mult": float(f.get("mult", 1.5)), "aerial": float(f.get("aerial", 0.55)),
		"fog_sky": float(f.get("fog_sky", 0.45)), "height_fog": f.get("height_fog", []),
	}
	var sun: Dictionary = entry.get("sun", {})
	if sun.has("tint"):
		g["sun"] = sun["tint"]
	return g


## The binary star as seen from Anvil: SolarSystem.suns_for("anvil") once home's helper exists,
## else data/solar_system.json, else the shared fallback scaled for Anvil's distance.
func suns() -> Dictionary:
	if ResourceLoader.exists("res://systems/solar_system.gd"):
		var ss: Script = load("res://systems/solar_system.gd")
		if ss and ss.has_method("suns_for"):
			var v: Variant = ss.call("suns_for", ID)
			if v is Dictionary and (v as Dictionary).has("a"):
				return v
	var sun: Dictionary = entry.get("sun", {})
	var k: float = float(sun.get("fallback_size", 0.72))
	var a := {"color": Color(1.0, 0.95, 0.85), "size": 1.0 * k, "energy": 1.0}
	var b := {"color": Color(1.0, 0.62, 0.38), "size": 0.55 * k, "energy": float(sun.get("fallback_b_energy", 0.2)), "sep_deg": float(sun.get("fallback_sep_deg", 11.0))}
	var sj: Dictionary = load_json("res://data/solar_system.json")
	var pl: Dictionary = (sj.get("planets", {}) as Dictionary).get(ID, {}) if sj.get("planets") is Dictionary else {}
	if sj.has("star_b") and pl.has("orbit_au"):
		var dim: float = 1.0 / maxf(float(pl["orbit_au"]), 0.3)
		var sa: Dictionary = sj.get("star_a", {})
		var sb: Dictionary = sj["star_b"]
		a = {"color": col(sa.get("color"), a["color"]), "size": float(sa.get("size", 1.0)) * dim, "energy": float(sa.get("energy", 1.0)) * sqrt(dim)}
		b = {"color": col(sb.get("color"), b["color"]), "size": float(sb.get("size", 0.55)) * dim, "energy": float(sb.get("energy", 0.25)) * sqrt(dim), "sep_deg": float(pl.get("sun_separation", b["sep_deg"]))}
	return {"a": a, "b": b}


func _sky() -> void:
	_suns = suns()
	var sd: Node = world.get("sky_director")
	if sd:
		sd.set("grade", sky_grade())
	var we: Environment = world.get("_env")
	var s: Dictionary = entry.get("sky", {})
	if we and we.sky and we.sky.sky_material is PhysicalSkyMaterial:
		var sm: PhysicalSkyMaterial = we.sky.sky_material
		sm.rayleigh_coefficient = float(s.get("rayleigh_coef", 1.4))
		sm.mie_eccentricity = float(s.get("mie_eccentricity", 0.9))
		sm.ground_color = col(s.get("ground"), Color(0.42, 0.2, 0.12))
		sm.sun_disk_scale = 1.0
	var sun: DirectionalLight3D = world.get("_sun")
	var a: Dictionary = _suns["a"]
	var b: Dictionary = _suns["b"]
	if sun:
		sun.light_angular_distance = 0.6 * float(a.get("size", 0.72))
	# The companion: its own disc in the sky and a warm unshadowed fill.
	_sun_b = DirectionalLight3D.new()
	_sun_b.name = "CompanionSun"
	_sun_b.shadow_enabled = false
	_sun_b.light_color = b["color"]
	_sun_b.light_angular_distance = 0.6 * float(b.get("size", 0.4))
	_sun_b.light_volumetric_fog_energy = 0.4
	add_child(_sun_b)


func _update_suns() -> void:
	var sun: DirectionalLight3D = world.get("_sun")
	if sun == null:
		return
	var sd: Node = world.get("sky_director")
	var se: Dictionary = entry.get("sun", {})
	# Anvil's suns ride lower (elev_max_deg) and give less light.
	var k: float = float(se.get("elev_max_deg", 52.0)) / 70.0
	if sd:
		sun.rotation_degrees.x *= k
	var a: Dictionary = _suns["a"]
	var b: Dictionary = _suns["b"]
	sun.light_energy *= float(se.get("energy_mult", 0.82)) * float(a.get("energy", 1.0))
	var sep: float = deg_to_rad(float(b.get("sep_deg", 11.0)))
	_sun_b.global_basis = Basis(Vector3.UP, sep) * Basis(sun.global_basis.x, -sep * 0.3) * sun.global_basis
	_sun_b.visible = sun.visible
	# Same day curve as the primary, at the companion's share of the light.
	_sun_b.light_energy = sun.light_energy * float(b.get("energy", 0.2)) / maxf(float(a.get("energy", 1.0)), 0.01)
	var we: Environment = world.get("_env")
	if we:
		we.ambient_light_energy *= float((entry.get("ambient", {}) as Dictionary).get("energy_mult", 0.95))


# --- Ground and terrain -------------------------------------------------------------------

func _ground() -> void:
	var v: FieldView = world.get("view")
	if v == null or v.ground_material == null:
		return
	var gm: ShaderMaterial = v.ground_material
	var bs: Dictionary = look.get("biome_set", {})
	var gt: Array = bs.get("ground_tint", [0.84, 0.38, 0.21, 0.74])
	gm.set_shader_parameter("biome_tint", Vector4(float(gt[0]), float(gt[1]), float(gt[2]), float(gt[3])))
	var gr: Array = bs.get("grass_tint", [0.86, 1.0, 0.74])
	gm.set_shader_parameter("grass_tint", Vector3(float(gr[0]), float(gr[1]), float(gr[2])))
	if v.layer_swap.is_empty():  # applied without prepare_view: swap the dust layers in now
		var layers: Array[String] = FieldView.GROUND_LAYERS.duplicate()
		var sw: Dictionary = look.get("ground_layers", {})
		for k: Variant in sw:
			layers[int(str(k))] = str(sw[k])
		gm.set_shader_parameter("albedo_arr", FieldView._tex_array(layers, "diff"))
		gm.set_shader_parameter("normal_arr", FieldView._tex_array(layers, "nor_gl"))
		gm.set_shader_parameter("arm_arr", FieldView._tex_array(layers, "arm"))
		var fx: Array = look.get("fx", [0.35, 0, 0, 0])
		gm.set_shader_parameter("frontier_fx", Vector4(float(fx[0]), float(fx[1]), float(fx[2]), float(fx[3])))
	gm.set_shader_parameter("clip_r", r_in + 3.0)
	# Junk: rust dust on top, soot down the sides.
	var jt: Color = col(entry.get("junk_tint"), Color(0.6, 0.27, 0.14, 0.55))
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://planet/planets/anvil/anvil_coat.gdshader")
	cm.set_shader_parameter("dust", Color(jt.r, jt.g, jt.b))
	cm.set_shader_parameter("top_amt", 0.6 + jt.a * 0.4)
	cm.set_shader_parameter("film", 0.55)
	v.set_junk_overlay(cm)
	# Lakes: iron-red mine drainage while murky, clearing to teal.
	var wv: Node = world.get("water")
	var wm: Variant = wv.get("_mat") if wv else null
	if wm is ShaderMaterial:
		(wm as ShaderMaterial).set_shader_parameter("murky_col", Vector3(0.3, 0.12, 0.06))
		(wm as ShaderMaterial).set_shader_parameter("clear_col", Vector3(0.09, 0.36, 0.38))


## Anvil's land: rolling dust plains, layered mesas past ~110 m, a canyon to the west, flat
## foundry pads under the stacks, and the core pit (a hole here; its benches are their own mesh).
func height(x: float, z: float) -> float:
	var r: float = sqrt(x * x + z * z)
	var t: float = r - r_in
	var h: float = 0.25 + (_n2.get_noise_2d(x, z) * 0.5 + 0.5) * 2.0 * _smooth(6.0, 70.0, t) + (_n1.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5) * 10.0 * _smooth(90.0, 420.0, t)
	var pd: float = Vector2(x - pit_c.x, z - pit_c.z).length()
	var keep: float = _smooth(PIT_R + 30.0, PIT_R + 130.0, pd)
	for s: Dictionary in stacks:
		keep *= _smooth(float(s["r"]) * 4.0, float(s["r"]) * 4.0 + 50.0, Vector2(x - (s["pos"] as Vector3).x, z - (s["pos"] as Vector3).z).length())
	# Mesas: plateaus with stepped strata on their walls.
	var m: float = _n1.get_noise_2d(x, z) + _n3.get_noise_2d(x, z) * 0.18
	var mask: float = _smooth(0.1, 0.19, m) * _smooth(105.0, 210.0, t) * keep
	var mh: float = lerpf(34.0, 82.0, _n3.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.5) * mask
	h += _terrace(mh, 9.0)
	# Buttes: smaller, taller towers further out.
	var bt: float = _smooth(0.42, 0.5, _n2.get_noise_2d(x * 0.33, z * 0.33)) * _smooth(260.0, 380.0, t) * keep
	h += _terrace(bt * 95.0, 12.0)
	# The canyon: a meandering cut west of the base, stepped walls.
	var cw: float = absf(x + 185.0 + _n1.get_noise_2d(z * 0.6, 33.0) * 70.0)
	var canyon: float = (1.0 - _smooth(14.0, 42.0, cw + _n2.get_noise_2d(x, z) * 6.0)) * _smooth(40.0, 110.0, t)
	h -= _terrace(canyon * (36.0 + mh * 0.6), 7.0)
	# Pit rim: flat at RIM_Y round the bench mesh, a hole inside it.
	h = lerpf(RIM_Y, h, _smooth(PIT_R + 14.0, PIT_R + 40.0, pd))
	if pd < PIT_R + 2.0:
		h = -440.0
	if t < 0.0:
		h = minf(h, -0.04 - 0.3 * _smooth(0.0, 8.0, -t))
	return lerpf(-0.04, h, _smooth(0.0, 10.0, t)) if t >= 0.0 else h


static func _terrace(h: float, step: float) -> float:
	if h <= 0.0:
		return 0.0
	var k: float = h / step
	var f: float = k - floorf(k)
	return (floorf(k) + _smooth(0.55, 0.95, f)) * step


## Ground height for props (0 on the field).
func gy(p: Vector3) -> float:
	if Vector2(p.x, p.z).length() < r_in + 3.0:
		return 0.0
	return maxf(height(p.x, p.z), -0.04)


func _terrain_material(slag: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://planet/planets/anvil/anvil_terrain.gdshader")
	m.set_shader_parameter("tex_a", AssetLib.tex("sand_01", "diff"))
	m.set_shader_parameter("nrm_a", AssetLib.tex("sand_01", "nor_gl"))
	m.set_shader_parameter("tex_b", AssetLib.tex("dry_ground_rocks", "diff"))
	m.set_shader_parameter("nrm_b", AssetLib.tex("dry_ground_rocks", "nor_gl"))
	m.set_shader_parameter("tex_g", AssetLib.tex("leafy_grass", "diff"))
	var pal: Dictionary = entry.get("palette", {})
	for k: String in ["dust", "rock", "band", "lichen", "redleaf", "green"]:
		if pal.has(k):
			var c: Color = col(pal[k], Color.WHITE)
			m.set_shader_parameter(k + "_col", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("slag", slag)
	return m


func _build_terrain() -> void:
	# Stacks first: the terrain flattens their pads.
	stacks = AnvilProps.stack_plan(self)
	terrain_mat = _terrain_material(0.0)
	slag_mat = _terrain_material(1.0)
	slag_mat.set_shader_parameter("strata", 0.0)
	var r_out: float = 1300.0
	var nr: int = 150
	var na: int = 400 if Settings.quality >= 1 else 300
	var sectors: int = 10
	var rs := PackedFloat32Array()
	for i: int in nr:
		var f: float = float(i) / float(nr - 1)
		rs.append(r_in - 9.0 + (r_out - r_in + 9.0) * pow(f, 2.1))
	@warning_ignore("integer_division")
	var per: int = na / sectors
	for sct: int in sectors:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j: int in per + 1:
			var ang: float = TAU * float(sct * per + j) / float(na)
			for i: int in nr:
				var x: float = cos(ang) * rs[i]
				var z: float = sin(ang) * rs[i]
				st.add_vertex(Vector3(x, height(x, z), z))
		for j: int in per:
			for i: int in nr - 1:
				var a: int = j * nr + i
				var b: int = (j + 1) * nr + i
				for idx: int in [a, a + 1, b, b, a + 1, b + 1]:
					st.add_index(idx)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = "Terrain%d" % sct
		mi.mesh = st.commit()
		mi.material_override = terrain_mat
		add_child(mi)


## The depleted core shaft: open-pit benches stepping down to the shaft mouth, the shaft wall
## glowing dimly with depth, an ember floor far below.
func _build_pit() -> void:
	var r0: float = PIT_R * SHAFT_K
	var r1: float = PIT_R + 16.0
	var nr: int = 44
	var na: int = 144
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in na + 1:
		var ang: float = TAU * float(j) / float(na)
		for i: int in nr:
			var rr: float = lerpf(r0, r1, float(i) / float(nr - 1))
			var x: float = pit_c.x + cos(ang) * rr
			var z: float = pit_c.z + sin(ang) * rr
			st.add_vertex(Vector3(x, _bowl_h(rr, ang), z))
	for j: int in na:
		for i: int in nr - 1:
			var a: int = j * nr + i
			var b: int = (j + 1) * nr + i
			for idx: int in [a, b, a + 1, b, b + 1, a + 1]:
				st.add_index(idx)
	st.generate_normals()
	var bowl := MeshInstance3D.new()
	bowl.name = "PitBenches"
	bowl.mesh = st.commit()
	bowl.material_override = terrain_mat
	add_child(bowl)
	# Shaft wall and floor.
	var depth: float = 330.0
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = preload("res://planet/planets/anvil/anvil_core.gdshader")
	_core_mat.set_shader_parameter("top_y", -PIT_DEPTH)
	_core_mat.set_shader_parameter("depth", depth)
	var shaft := MeshInstance3D.new()
	shaft.name = "CoreShaft"
	var cm := CylinderMesh.new()
	cm.top_radius = r0 + 0.3
	cm.bottom_radius = r0 * 0.8
	cm.height = depth + 4.0
	cm.radial_segments = 64
	cm.rings = 8
	cm.cap_top = false
	cm.cap_bottom = false
	shaft.mesh = cm
	shaft.material_override = _core_mat
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shaft.position = Vector3(pit_c.x, -PIT_DEPTH - depth * 0.5 + 2.0, pit_c.z)
	add_child(shaft)
	_core_floor = StandardMaterial3D.new()
	_core_floor.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_floor.albedo_color = EMBER
	var fl := MeshInstance3D.new()
	fl.name = "CoreFloor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(r0 * 2.0, r0 * 2.0)
	fl.mesh = pm
	fl.material_override = _core_floor
	fl.position = Vector3(pit_c.x, -PIT_DEPTH - depth + 4.0, pit_c.z)
	add_child(fl)


## Bench heights: flat rim berm, then six stepped benches down to the shaft mouth.
func _bowl_h(rr: float, ang: float) -> float:
	if rr >= PIT_R:
		var berm: float = (1.0 - absf((rr - PIT_R - 5.0) / 5.0)) if rr < PIT_R + 10.0 else 0.0
		return RIM_Y + 0.15 + maxf(berm, 0.0) * 1.4
	var u: float = (PIT_R - rr) / (PIT_R * (1.0 - SHAFT_K))
	u += _n2.get_noise_2d(cos(ang) * 60.0, sin(ang) * 60.0) * 0.035
	var d: float = clampf(u, 0.0, 1.0) * PIT_DEPTH
	return RIM_Y - _terrace(d, PIT_DEPTH / 6.0) - (2.0 if rr < PIT_R * SHAFT_K + 1.5 else 0.0)


# --- Plants (restored) ---------------------------------------------------------------------

## A model mesh with every surface's albedo multiplied by tint (red-leaf or lichen versions).
static func tinted_mesh(id: String, tint: Color, max_tris: int) -> Mesh:
	var src: Mesh = AssetLib.model_mesh_lite(id, max_tris)
	if src == null:
		return null
	var m: Mesh = src.duplicate()
	for s: int in m.get_surface_count():
		var sm: Material = m.surface_get_material(s)
		if sm is BaseMaterial3D:
			var d: BaseMaterial3D = sm.duplicate()
			d.albedo_color = Color(d.albedo_color.r * tint.r, d.albedo_color.g * tint.g, d.albedo_color.b * tint.b, d.albedo_color.a)
			m.surface_set_material(s, d)
	return m


func _build_plants() -> void:
	var defs: Array = look.get("plants", [])
	var mult: float = [0.45, 0.7, 1.0, 1.0][clampi(Settings.quality, 0, 3)]
	for k: int in defs.size():
		var d: Dictionary = defs[k]
		if not AssetLib.has_model(str(d["id"])):
			continue
		var mesh: Mesh = tinted_mesh(str(d["id"]), col(d.get("tint"), Color.WHITE), 900)
		if mesh == null:
			continue
		var n: int = int(float(d.get("count", 100)) * mult)
		var sc: Array = d.get("scale", [1.0, 1.5])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = n
		var rng := RandomNumberGenerator.new()
		rng.seed = field.seed_value + 900 + k
		for i: int in n:
			# Dense near the field edge, thinning outward; clumped by noise.
			var ang: float = rng.randf() * TAU
			var dist: float = r_in + 1.0 + pow(rng.randf(), 1.8) * 110.0
			var p: Vector3 = polar(ang, dist)
			if _n2.get_noise_2d(p.x * 3.0, p.z * 3.0) < -0.15:
				p = polar(ang + 0.05, dist + 3.0)
			p.y = gy(p) - 0.05
			var s: float = rng.randf_range(float(sc[0]), float(sc[1]))
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Plants_" + str(d["id"])
		mmi.multimesh = mm
		mmi.visibility_range_end = 170.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_plants.append(mmi)
		_plant_n.append(n)


# --- Particles: dust devils, red haze, restored motes ---------------------------------------

static func soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _puff_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.albedo_texture = soft_dot()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	return m


func _fade_ramp(a: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, a))
	g.add_point(0.7, Color(1, 1, 1, a * 0.8))
	return g


func _build_particles() -> void:
	var dust_c: Color = col((entry.get("palette", {}) as Dictionary).get("dust"), Color(0.78, 0.4, 0.24))
	var n_devils: int = 2 if Settings.quality == 0 else 3
	for i: int in n_devils:
		var p := CPUParticles3D.new()
		p.name = "DustDevil%d" % i
		p.amount = 70 if Settings.quality == 0 else 110
		p.lifetime = 5.0
		p.local_coords = false
		var q := QuadMesh.new()
		q.size = Vector2(2.4, 2.4)
		q.material = _puff_mat(Color(dust_c.r * 1.1, dust_c.g * 1.05, dust_c.b, 1.0))
		p.mesh = q
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		p.emission_ring_axis = Vector3.UP
		p.emission_ring_radius = 1.6
		p.emission_ring_inner_radius = 0.6
		p.emission_ring_height = 0.5
		p.direction = Vector3.UP
		p.spread = 8.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, 0.8, 0)
		p.tangential_accel_min = 9.0
		p.tangential_accel_max = 14.0
		p.radial_accel_min = 0.4
		p.radial_accel_max = 1.2
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.5))
		sc.add_point(Vector2(1, 4.5))
		p.scale_amount_curve = sc
		p.color_ramp = _fade_ramp(0.32)
		add_child(p)
		_devils.append({"node": p, "a": TAU * float(i) / float(n_devils) + 0.6, "r": r_in + 25.0 + 45.0 * i, "spd": 0.035 + 0.015 * i})
	_haze = CPUParticles3D.new()
	_haze.name = "RedHaze"
	_haze.amount = 18 if Settings.quality == 0 else 30
	_haze.lifetime = 16.0
	_haze.preprocess = 16.0
	_haze.local_coords = false
	var hq := QuadMesh.new()
	hq.size = Vector2(1, 1)
	hq.material = _puff_mat(Color(dust_c.r * 1.15, dust_c.g * 1.1, dust_c.b * 1.05, 1.0))
	_haze.mesh = hq
	_haze.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_haze.emission_box_extents = Vector3(70, 3, 70)
	_haze.direction = Vector3(0.83, 0.05, 0.56)
	_haze.spread = 15.0
	_haze.initial_velocity_min = 1.5
	_haze.initial_velocity_max = 3.0
	_haze.gravity = Vector3.ZERO
	_haze.scale_amount_min = 14.0
	_haze.scale_amount_max = 26.0
	_haze.color_ramp = _fade_ramp(0.06)
	add_child(_haze)
	_motes = CPUParticles3D.new()
	_motes.name = "SeedMotes"
	_motes.amount = 50
	_motes.lifetime = 9.0
	_motes.local_coords = false
	var mq := QuadMesh.new()
	mq.size = Vector2(0.12, 0.12)
	var mmat := _puff_mat(Color(1.0, 0.95, 0.82, 1.0))
	mmat.emission_enabled = true
	mmat.emission = Color(1.0, 0.9, 0.7)
	mmat.emission_energy_multiplier = 0.6
	mq.material = mmat
	_motes.mesh = mq
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(22, 4, 22)
	_motes.direction = Vector3(0.83, 0.3, 0.56)
	_motes.initial_velocity_min = 0.3
	_motes.initial_velocity_max = 0.9
	_motes.gravity = Vector3(0, 0.05, 0)
	_motes.color_ramp = _fade_ramp(0.85)
	_motes.emitting = false
	add_child(_motes)


# --- Twin moons -----------------------------------------------------------------------------

func _build_moons() -> void:
	var root := Node3D.new()
	root.name = "Moons"
	add_child(root)
	# A larger lumpy inner moon and a tiny outer one, high in the default view's sky.
	var defs: Array = [
		{"az": -PI * 0.5 + 0.55, "el": 0.36, "r": 22.0, "scl": Vector3(1.35, 1.0, 1.1), "c": Color(0.5, 0.44, 0.4)},
		{"az": -PI * 0.5 - 0.7, "el": 0.6, "r": 11.0, "scl": Vector3(1.1, 1.0, 1.0), "c": Color(0.62, 0.56, 0.5)},
	]
	for d: Dictionary in defs:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = float(d["r"])
		sm.height = float(d["r"]) * 2.0
		sm.radial_segments = 24
		sm.rings = 12
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = d["c"]
		m.albedo_texture = AssetLib.tex("rubble", "diff")
		m.uv1_scale = Vector3(2, 1, 1)
		m.roughness = 1.0
		m.disable_fog = true
		m.emission_enabled = true
		m.emission = (d["c"] as Color) * 0.25
		m.emission_energy_multiplier = 0.5
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = d["scl"]
		mi.set_meta("az", float(d["az"]))
		mi.set_meta("el", float(d["el"]))
		root.add_child(mi)
		_moons.append(mi)
	_place_moons()


func _place_moons() -> void:
	for i: int in _moons.size():
		var mi: Node3D = _moons[i]
		# The inner moon crosses the sky visibly over a day; the outer barely moves.
		var az: float = float(mi.get_meta("az")) + _t * (0.0016 if i == 0 else 0.0003)
		var el: float = float(mi.get_meta("el"))
		var dist: float = 2000.0
		mi.position = Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)) * dist
		mi.rotation.y = az


# --- Update ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_tick += delta
	if has_meta("nohud"):
		for c: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	if _tick >= 2.0:
		_tick = 0.0
		_refresh()
	if shown < 0.0:
		shown = restore
	shown = move_toward(shown, restore, delta * 0.05)
	_apply_restore()
	_update_suns()
	for r: Node3D in rotors:
		if is_instance_valid(r) and r.is_visible_in_tree():
			r.rotate_object_local(Vector3.FORWARD, delta * (0.7 + 0.1 * float(r.get_meta("k", 0))))
	var focus := Vector3.ZERO
	var p: Node3D = world.get("patch")
	if p:
		focus = p.global_position
	var devil_amt: float = 1.0 - _smooth(0.35, 0.8, shown)
	for d: Dictionary in _devils:
		var node: CPUParticles3D = d["node"]
		d["a"] = float(d["a"]) + delta * float(d["spd"])
		var rr: float = float(d["r"]) + sin(_t * 0.07 + float(d["a"])) * 18.0
		var pos: Vector3 = polar(float(d["a"]), rr)
		pos.y = gy(pos)
		node.global_position = pos
		node.emitting = devil_amt > 0.2
	if _haze:
		_haze.global_position = focus + Vector3(0, 2.5, 0)
		_haze.emitting = shown < 0.85
	if _motes:
		_motes.global_position = focus + Vector3(0, 2.0, 0)
		_motes.emitting = shown > 0.45 and level >= 3
	_place_moons()


func _refresh() -> void:
	var hl: Node = world.get("hex_levels")
	if hl != null:
		restore = restore_of(hl.get("levels"))
	if DevHooks.has("anvil-restore"):
		restore = clampf(DevHooks.get_f("anvil-restore", 1.0), 0.0, 1.0)


func _apply_restore() -> void:
	var r: float = clampf(shown, 0.0, 1.0)
	terrain_mat.set_shader_parameter("restore", r)
	slag_mat.set_shader_parameter("restore", r * 0.8)
	for i: int in _plants.size():
		_plants[i].multimesh.visible_instance_count = int(float(_plant_n[i]) * _smooth(0.08, 0.85, r))
	var sd: Node = world.get("sky_director")
	if sd:
		sd.set("grade_amt", 1.0 - 0.7 * r)
	# The core: ember red, dim, slowly breathing; rekindled warm white-gold as Anvil recovers.
	var cc: Color = EMBER.lerp(CORE_WARM, _smooth(0.3, 0.9, r))
	var breathe: float = 0.85 + 0.15 * sin(_t * 0.6)
	_core_mat.set_shader_parameter("glow_col", Vector3(cc.r, cc.g, cc.b))
	_core_mat.set_shader_parameter("glow", lerpf(0.9, 1.7, r) * breathe)
	_core_floor.albedo_color = cc * lerpf(0.9, 1.6, r) * breathe


# --- Dev ------------------------------------------------------------------------------------

## --planet-cam=dist,pitch,yaw[,fov] for landscape shots.
func _dev_hooks() -> void:
	if DevHooks.has("planet-nohud"):  # clean landscape shots: hide every overlay (see _process)
		set_meta("nohud", true)
	if DevHooks.has("planet-cam"):
		var c: PackedStringArray = DevHooks.get_s("planet-cam", "30,-0.3,0").split(",")
		var cam: CameraRig = world.get("cam")
		if cam:
			cam.max_distance = maxf(cam.max_distance, float(c[0]))
			cam.distance = float(c[0])
			cam.pitch = float(c[1]) if c.size() > 1 else -0.3
			cam.yaw = float(c[2]) if c.size() > 2 else cam.yaw
			(cam.get("_arm") as SpringArm3D).collision_mask = 0
			if c.size() > 3:
				Settings.fov = float(c[3])
				cam.camera.fov = Settings.fov
			cam.snap()
