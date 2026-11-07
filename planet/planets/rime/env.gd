class_name RimeEnv
extends Node3D
## [planet-rime] RIME, the ice moon the Ledger core-mined until it froze. The whole environment of
## one district on Rime, self-contained:
##   sky       black-blue thin air, the system's two suns as small distant points (weak light,
##             stars out by day), a huge ringed gas giant low over the crater rim, faint aurora at
##             night (rime_sky.gdshader); giantshine instead of moonlight
##   land      heightfield from the field edge to the horizon: glassy blue ice sheets, shattered
##             pressure ridges (with tilted slabs), deep glowing crevasses, soft snow drifts, ice
##             mesas and the crater rim (rime_ice.gdshader); tall slender ice spires and arches
##             (low gravity), frozen geysers venting vapour
##   ruin      the Ledger's core-drill derricks frozen into the ice and the giant borehole venting
##             cold mist; drill spoil stains the ice; junk is frozen into the field's ice sheet
##   restored  geothermal warmth returns: frozen pools thaw into steaming hot springs, moss carpets
##             spread, hardy alpine flowers, ice-lanterns (thin warm light), greenhouse domes, the
##             borehole glows warm, the derricks become white geothermal taps
## Stages follow the base level like FrontierView (ruin 1, mid 2-3, up 2-5, future 4-5); moss,
## flowers, pools and lanterns follow the district's restoration (hex levels) continuously.
## Entry points (see planet/planets/planet_envs.gd): dev_hub, prepare_field, dress_view, apply.

const ID := "rime"
const BIOME_PATH := "res://planet/planets/rime/rime_biome.json"
const SKY_SHADER := preload("res://planet/planets/rime/rime_sky.gdshader")
const ICE_SHADER := preload("res://planet/planets/rime/rime_ice.gdshader")
const PROP_ICE_SHADER := preload("res://planet/planets/rime/rime_prop_ice.gdshader")
const SHAFT_SHADER := preload("res://planet/planets/rime/rime_shaft.gdshader")
const POOL_SHADER := preload("res://planet/planets/rime/rime_pool.gdshader")
const CYAN := Color(0.62, 0.9, 1.0)
const WARM := Color(1.0, 0.74, 0.46)
## Fallback suns until data/solar_system.json / SolarSystem (home) land: Verdance's values scaled
## for Rime, the farthest planet (small discs, weak light, tight separation).
const FALLBACK_SUNS := {
	"a": {"color": [1.0, 0.95, 0.85], "size": 1.0, "energy": 1.0},
	"b": {"color": [1.0, 0.62, 0.38], "size": 0.55, "energy": 0.25, "separation": 14.0},
}
const RIME_SIZE_MULT: float = 0.32
const RIME_ENERGY_MULT: float = 0.62
const STAGES: Dictionary = {"always": Vector2i(1, 5), "ruin": Vector2i(1, 1), "mid": Vector2i(2, 3), "up": Vector2i(2, 5), "future": Vector2i(4, 5)}

var world: Node
var field: HexField
var kind: Dictionary = {}
var level: int = 1
var restore: float = 0.0
var suns: Dictionary = {}

var _groups: Dictionary = {}
var _mats: Dictionary = {}
var _r_in: float = 60.0
var _n := [FastNoiseLite.new(), FastNoiseLite.new(), FastNoiseLite.new(), FastNoiseLite.new()]
var _rng := RandomNumberGenerator.new()
var _pads: Array[Vector4] = []      # x, z, radius, flat height
var _bore := Vector3.ZERO            # x, z, radius
var _bore_y: float = 0.0
var _sites: Array[Vector4] = []      # drill spoil
var _terrain_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _companion: DirectionalLight3D
var _pools: Array[MeshInstance3D] = []
var _pool_steam: Array[CPUParticles3D] = []
var _bloom_mms: Array[MultiMesh] = []    # flowers, lanterns: shown by restore
var _bloom_full: Array[int] = []
var _bloom_gate: Array[float] = []
var _shards: MultiMesh
var _shard_base: Array[Transform3D] = []
var _vent_mat: ShaderMaterial
var _mist_mat: ShaderMaterial
var _vents: Array[CPUParticles3D] = []
var _mist: CPUParticles3D
var _dust: CPUParticles3D
var _t: float = 0.0
var _slow: float = 99.0


## Merges primitive meshes per material into one ArrayMesh each.
class Batch:
	var sts: Dictionary = {}

	func add(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
		var key: int = mat.get_instance_id()
		if not sts.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[key] = [st, mat]
		for s: int in mesh.get_surface_count():
			(sts[key][0] as SurfaceTool).append_from(mesh, s, xf)

	func flush(parent: Node3D, shadows: bool = true, vis_end: float = 0.0) -> void:
		for key: int in sts:
			var st: SurfaceTool = sts[key][0]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = sts[key][1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = vis_end
			parent.add_child(mi)
		sts.clear()


# --- Entry points (static) ------------------------------------------------------------------

## Dev hook: the first wild (non-city, non-frontier, dry) hub, so the moon gets open land.
static func dev_hub(planet: PlanetData) -> int:
	var skip: Array = planet.frontier_hubs.values()
	for i: int in planet.hubs.size():
		var c: int = planet.hubs[i]
		if i in skip or planet.city[c] >= 0 or planet.state[c] == PlanetData.State.WATER:
			continue
		return i
	return 0


## Rime's junk set (rime_biome.json) as Economy.biome_sets["rime"].
static func register_biome() -> Dictionary:
	if not Economy.biome_sets.has(ID) and FileAccess.file_exists(BIOME_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(BIOME_PATH))
		if d is Dictionary:
			Economy.biome_sets[ID] = d
	return Economy.biome_sets.get(ID, {})


## Before HexField.generate: mining junk and wrecks frozen into the ice.
static func prepare_field(f: HexField) -> void:
	var b: Dictionary = register_biome()
	if b.is_empty():
		return
	f.biome = ID
	f.biome_set = b


## Before FieldView.setup: snow ground layers, light frost, the glassy ice sheet (ground_pbr fx.w).
static func dress_view(view: FieldView) -> void:
	view.layer_swap = {"4": "snow_02", "5": "snow_02", "6": "snow_02"}
	view.ground_fx = Vector4(0.0, 0.45, 0.0, 1.0)
	view.skip_horizon = true


## Once the scene is built: adds the RimeEnv node to the world and builds everything.
static func apply(p_world: Node, p_field: HexField, p_kind: Dictionary) -> void:
	var old: Node = p_world.get_node_or_null("RimeEnv")
	if old:
		old.free()
	var env := RimeEnv.new()
	env.name = "RimeEnv"
	env.world = p_world
	env.field = p_field
	env.kind = p_kind if not p_kind.is_empty() else PlanetEnvs.entry(ID)
	p_world.add_child(env)
	env.build()


## Which look group a base level shows.
static func stages_for(l: int) -> Array[String]:
	var out: Array[String] = []
	for g: String in STAGES:
		var r: Vector2i = STAGES[g]
		if l >= r.x and l <= r.y:
			out.append(g)
	return out


## District restoration 0..1 from hex levels (0..5 each), as the frontiers count it.
static func restore_from_levels(levels: Dictionary) -> float:
	if levels.is_empty():
		return 0.0
	var s: float = 0.0
	for h: Variant in levels:
		s += clampf(float(levels[h]), 0.0, 5.0)
	return s / (float(levels.size()) * 5.0)


## The two suns as seen from Rime: {a: {color, size, energy}, b: {color, size, energy, separation}}.
## SolarSystem.suns_for("rime") (home's systems/solar_system.gd) wins when it exists; the fallback
## is Verdance's pair scaled down for Rime's distance.
static func suns_for_rime() -> Dictionary:
	var path := "res://systems/solar_system.gd"
	if ResourceLoader.exists(path):
		var scr: Script = load(path)
		if scr:
			for m: Dictionary in scr.get_script_method_list():
				if str(m.get("name", "")) == "suns_for":
					var r: Variant = scr.call("suns_for", ID)
					if r is Dictionary and (r as Dictionary).has("a") and (r as Dictionary).has("b"):
						return _norm_suns(r, 1.0, 1.0)
					break
	return _norm_suns(FALLBACK_SUNS, RIME_SIZE_MULT, RIME_ENERGY_MULT)


static func _norm_suns(src: Dictionary, size_k: float, energy_k: float) -> Dictionary:
	var out: Dictionary = {}
	for k: String in ["a", "b"]:
		var s: Dictionary = src.get(k, {})
		var fb: Dictionary = FALLBACK_SUNS[k]
		var c: Variant = s.get("color", fb["color"])
		var col: Color = c if c is Color else Color(float(c[0]), float(c[1]), float(c[2]))
		out[k] = {
			"color": col,
			"size": float(s.get("size", fb["size"])) * size_k,
			"energy": float(s.get("energy", fb["energy"])) * energy_k,
			"separation": float(s.get("separation", fb.get("separation", 14.0))) * (size_k if k == "b" else 1.0),
		}
		if s.has("dir"):
			out[k]["dir"] = s["dir"]
	return out


# --- Build ------------------------------------------------------------------------------------

func build() -> void:
	process_priority = 50  # after SkyDirector: our sky, fog and light win
	var t0: int = Time.get_ticks_msec()
	_rng.seed = field.seed_value + 9091
	level = int(world.hub.level) if world.get("hub") != null else 1
	_r_in = field.hex_size * (float(field.radius) + 0.55) * Hex.SQRT3 + 2.0
	for k: int in 4:
		var nz: FastNoiseLite = _n[k]
		nz.seed = field.seed_value + 313 * (k + 1)
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = 3
		nz.frequency = [0.0035, 0.012, 0.0045, 0.006][k]
	for g: String in STAGES:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	suns = suns_for_rime()
	_layout_sites()
	_setup_sky()
	_open_camera()
	_build_terrain()
	_build_borehole()
	for i: int in _derricks.size():
		_derrick(_derricks[i], i)
	_build_geysers()
	_build_ridge_slabs()
	_build_spires()
	_build_pools()
	_build_blooms()
	_build_greenhouses()
	_build_air()
	_dress_field()
	set_level(level, false)
	if world.get("hub") != null:
		world.hub.level_changed.connect(func(l: int) -> void: set_level(l, true))
	_dev_hooks()
	_dev_hooks.call_deferred()
	_update_light()
	var meshes: int = find_children("*", "MeshInstance3D", true, false).size()
	print("[rime] env built in %d ms: level %d, %d mesh nodes, %d pads" % [Time.get_ticks_msec() - t0, level, meshes, _pads.size()])


var _derricks: Array[Vector3] = []   # x, z, height
var _geysers: Array[Vector3] = []    # x, z, size
var _domes: Array[Vector3] = []      # x, z, radius
var _pool_sites: Array[Vector3] = [] # x, z, radius


static func _polar(ang: float, dist: float) -> Vector2:
	return Vector2(cos(ang) * dist, sin(ang) * dist)


## Fixed composition (angle 0 = +x, -PI/2 = -z = the default view): the borehole front-left under
## the gas giant, derricks around it, geysers and pools spread round the field.
func _layout_sites() -> void:
	var gd: Array = kind.get("sky", {}).get("giant_dir", [-0.38, 0.17, -0.91])
	var giant_az: float = atan2(float(gd[2]), float(gd[0]))
	var b: Vector2 = _polar(giant_az - 0.1, _r_in + 105.0)
	_bore = Vector3(b.x, b.y, 30.0)
	_pads.append(Vector4(b.x, b.y, 0.0, 0.0))  # placeholder slot 0: the borehole flattens itself
	_sites.append(Vector4(b.x, b.y, 95.0, 1.0))
	var da: Array = [[giant_az + 0.55, 34.0, 36.0], [giant_az - 0.75, 52.0, 42.0], [giant_az + 1.5, 46.0, 30.0], [giant_az + 3.4, 40.0, 38.0], [giant_az - 1.9, 70.0, 33.0]]
	for d: Array in da:
		var p: Vector2 = _polar(float(d[0]), _r_in + float(d[1]))
		_derricks.append(Vector3(p.x, p.y, float(d[2])))
		_pads.append(Vector4(p.x, p.y, 13.0, 0.0))
		_sites.append(Vector4(p.x, p.y, 30.0, 0.85))
	var ga: Array = [[giant_az + 0.25, 22.0, 1.0], [giant_az + 1.05, 75.0, 1.3], [giant_az + 2.3, 30.0, 0.9], [giant_az - 1.25, 26.0, 1.1], [giant_az + 2.9, 95.0, 1.5], [giant_az - 0.4, 175.0, 1.6]]
	for g: Array in ga:
		var p: Vector2 = _polar(float(g[0]), _r_in + float(g[1]))
		_geysers.append(Vector3(p.x, p.y, float(g[2])))
		_pads.append(Vector4(p.x, p.y, 9.0 * float(g[2]), 0.0))
		# A hot-spring pool beside each geyser.
		var off: Vector2 = Vector2(6.5, 0.0).rotated(_rng.randf() * TAU) * float(g[2])
		_pool_sites.append(Vector3(p.x + off.x, p.y + off.y, _rng.randf_range(2.2, 3.4) * float(g[2])))
	# More pools in the hollows just past the field edge.
	for i: int in 9:
		var a: float = giant_az + PI + (float(i) - 4.0) * 0.6 + _rng.randf_range(-0.15, 0.15)
		var p: Vector2 = _polar(a, _r_in + _rng.randf_range(7.0, 18.0))
		_pool_sites.append(Vector3(p.x, p.y, _rng.randf_range(1.8, 3.2)))
	for ps: Vector3 in _pool_sites:
		_pads.append(Vector4(ps.x, ps.y, ps.z + 3.0, 0.0))
	for d: Array in [[giant_az + 1.25, 20.0, 9.0], [giant_az + 2.65, 16.0, 7.5], [giant_az - 1.55, 22.0, 10.0], [giant_az + 4.1, 24.0, 8.0]]:
		var p: Vector2 = _polar(float(d[0]), _r_in + float(d[1]))
		_domes.append(Vector3(p.x, p.y, float(d[2])))
		_pads.append(Vector4(p.x, p.y, float(d[2]) + 4.0, 0.0))
	# Pads sit at the natural height at their centre.
	for i: int in range(1, _pads.size()):
		var pd: Vector4 = _pads[i]
		pd.w = _raw_h(pd.x, pd.y)[0]
		_pads[i] = pd
	_bore_y = 0.6


# --- Terrain ------------------------------------------------------------------------------------

static func _smooth(a: float, b: float, x: float) -> float:
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## [height, crevasse, drift, ridge, hollow] before pads and the borehole.
func _raw_h(x: float, z: float) -> Array:
	var r: float = sqrt(x * x + z * z)
	var t: float = r - _r_in
	if t < 0.0:
		return [minf(0.0, -0.04 - 0.3 * _smooth(0.0, 8.0, -t)), 0.0, 0.0, 0.0, 0.0]
	var n0: FastNoiseLite = _n[0]
	var n1: FastNoiseLite = _n[1]
	var n2: FastNoiseLite = _n[2]
	var n3: FastNoiseLite = _n[3]
	var ramp: float = _smooth(2.0, 30.0, t)
	var sw: float = n0.get_noise_2d(x, z) * 0.5 + 0.5
	var swell: float = sw * lerpf(0.6, 9.0, clampf(t / 420.0, 0.0, 1.0))
	# Snow drifts: long soft waves across the wind.
	var u: float = (x * 0.8 + z * 0.6 + n1.get_noise_2d(x, z) * 38.0) / 21.0
	var wave: float = pow(0.5 + 0.5 * sin(u * TAU), 2.0)
	var drift: float = wave * (0.5 + 0.5 * n1.get_noise_2d(x * 0.5 + 77.0, z * 0.5)) * _smooth(4.0, 40.0, t)
	# Pressure ridges: shattered ice walls along wandering lines.
	var rn: float = n2.get_noise_2d(x * 0.8, z * 0.8)
	var ridge: float = (1.0 - _smooth(0.0, 0.075, absf(rn))) * _smooth(14.0, 50.0, t) * (1.0 - _smooth(330.0, 460.0, t))
	var jag: float = n3.get_noise_2d(x * 6.0, z * 6.0) * 0.5 + 0.5
	var h_ridge: float = ridge * (2.2 + 5.5 * jag)
	# Crevasses: narrow, deep cuts (kept clear of the ridges).
	var cn: float = n3.get_noise_2d(x * 0.55 + 300.0, z * 0.55 - 120.0)
	var crev: float = (1.0 - _smooth(0.0, 0.03, absf(cn))) * _smooth(22.0, 45.0, t) * (1.0 - _smooth(260.0, 320.0, t)) * (1.0 - ridge)
	# Ice mesas (terraced), then the crater rim on the horizon.
	var pn: float = n0.get_noise_2d(x * 0.55 + 900.0, z * 0.55)
	var mesa_raw: float = _smooth(0.05, 0.22, pn) * 36.0 * _smooth(210.0, 360.0, t)
	var step_h: float = 9.0
	var mesa: float = floorf(mesa_raw / step_h) * step_h + _smooth(0.0, 1.0, fmod(mesa_raw, step_h) / step_h) * step_h * 0.9 if mesa_raw > 0.01 else 0.0
	var rr: float = n2.get_noise_2d(x * 1.4 + 40.0, z * 1.4)
	var rim: float = (pow(1.0 - sqrt(rr * rr + 0.002), 3.0) * 95.0 + 25.0) * _smooth(420.0, 700.0, t)
	var h: float = 0.35 + (swell + drift * 1.5 + h_ridge + mesa + rim) * ramp - crev * 7.5 * ramp
	h = lerpf(-0.04, h, _smooth(0.5, 8.0, t))
	return [h, crev, clampf(drift, 0.0, 1.0), ridge, 1.0 - sw]


## Height and masks with the pads flattened and the borehole berm.
func _hm(x: float, z: float) -> Array:
	var a: Array = _raw_h(x, z)
	var h: float = a[0]
	for i: int in range(1, _pads.size()):
		var pd: Vector4 = _pads[i]
		var d: float = Vector2(x - pd.x, z - pd.y).length()
		if d < pd.z * 1.8:
			var k: float = 1.0 - _smooth(pd.z * 0.7, pd.z * 1.8, d)
			h = lerpf(h, pd.w, k)
			a[1] = float(a[1]) * (1.0 - k)
			a[3] = float(a[3]) * (1.0 - k)
	var db: float = Vector2(x - _bore.x, z - _bore.y).length()
	if db < _bore.z + 60.0:
		var flat: float = 1.0 - _smooth(_bore.z + 22.0, _bore.z + 60.0, db)
		h = lerpf(h, _bore_y, flat)
		a[1] = float(a[1]) * (1.0 - flat)
		a[3] = float(a[3]) * (1.0 - flat)
		var berm: float = 3.0 * exp(-pow((maxf(db, _bore.z) - _bore.z - 7.0) / 7.0, 2.0))
		h += berm
	a[0] = h
	return a


## Ground height for props.
func ground_y(x: float, z: float) -> float:
	if Vector2(x, z).length() < _r_in - 2.0:
		return 0.0
	return maxf(float(_hm(x, z)[0]), -0.04)


func _build_terrain() -> void:
	var r_out: float = 1400.0
	var nr: int = 150
	var na: int = 420
	var sectors: int = 12
	var rs := PackedFloat32Array()
	for i: int in nr:
		var f: float = float(i) / float(nr - 1)
		rs.append(_r_in - 9.0 + (r_out - _r_in + 9.0) * pow(f, 2.0))
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = ICE_SHADER
	_terrain_mat.set_shader_parameter("snow_tex", AssetLib.tex("snow_02", "diff"))
	_terrain_mat.set_shader_parameter("snow_nrm", AssetLib.tex("snow_02", "nor_gl"))
	_terrain_mat.set_shader_parameter("moss_tex", AssetLib.tex("leafy_grass", "diff"))
	var pal: Dictionary = kind.get("palette", {})
	for k: Array in [["ice", "ice_col"], ["ice_deep", "ice_deep"], ["snow", "snow_tint"], ["crevasse", "crev_col"], ["moss", "moss_col"]]:
		if pal.has(k[0]):
			var c: Array = pal[k[0]]
			_terrain_mat.set_shader_parameter(k[1], Color(float(c[0]), float(c[1]), float(c[2])))
	_terrain_mat.set_shader_parameter("hole", Vector4(_bore.x, _bore.y, _bore.z, 0.0))
	var sv: Array = []
	for i: int in 8:
		sv.append(_sites[i] if i < _sites.size() else Vector4(0, 0, -1, 0))
	_terrain_mat.set_shader_parameter("sites", sv)
	@warning_ignore("integer_division")
	var per: int = na / sectors
	for sct: int in sectors:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j: int in per + 1:
			var ang: float = TAU * float(sct * per + j) / float(na)
			var c: float = cos(ang)
			var sn: float = sin(ang)
			for i: int in nr:
				var x: float = c * rs[i]
				var z: float = sn * rs[i]
				var a: Array = _hm(x, z)
				st.set_color(Color(float(a[1]), float(a[2]), float(a[3]), float(a[4])))
				st.add_vertex(Vector3(x, float(a[0]), z))
		for j: int in per:
			for i: int in nr - 1:
				var a0: int = j * nr + i
				var b0: int = (j + 1) * nr + i
				for idx: int in [a0, a0 + 1, b0, b0, a0 + 1, b0 + 1]:
					st.add_index(idx)
		st.generate_normals()
		_collide_sector(st)
		var mi := MeshInstance3D.new()
		mi.name = "Ice%d" % sct
		mi.mesh = st.commit()
		mi.material_override = _terrain_mat
		add_child(mi)
	var gm: ShaderMaterial = world.view.ground_material if world.get("view") != null else null
	if gm:
		gm.set_shader_parameter("clip_r", _r_in + 3.0)


## Walkable ice near the field (Lumi may wander past the edge): a collision copy of the inner
## rings, so nobody walks through drifts and ridges. The borehole keeps an invisible lid.
func _collide_sector(st: SurfaceTool) -> void:
	var r_max: float = _r_in + 120.0
	var arrays: Array = st.commit_to_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	var n: int = (idx as PackedInt32Array).size() if idx is PackedInt32Array else verts.size()
	for k: int in range(0, n, 3):
		var a: Vector3 = verts[idx[k]] if idx is PackedInt32Array else verts[k]
		if Vector2(a.x, a.z).length() > r_max:
			continue
		for m: int in 3:
			faces.append(verts[idx[k + m]] if idx is PackedInt32Array else verts[k + m])
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "IceBody"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# --- Materials ----------------------------------------------------------------------------------

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"ice", "ice_glow", "ice_clear":
			var s := ShaderMaterial.new()
			s.shader = PROP_ICE_SHADER
			if key == "ice_glow":
				s.set_shader_parameter("glow", 0.12)
			if key == "ice_clear":
				s.set_shader_parameter("snow_top", 0.15)
			m = s
		"rust":
			m = Mats.worn_paint(Color(0.36, 0.22, 0.16), 0.35, 0.9, 3.0, 0.7)
		"ledger":
			m = Mats.worn_paint(Color(0.86, 0.42, 0.12), 0.8, 0.45, 5.0, 0.5)
		"steel":
			m = Mats.metal("dark_steel")
		"white":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.9, 0.92, 0.95)
			w.roughness = 0.24
			w.clearcoat_enabled = true
			w.clearcoat = 0.5
			m = w
		"line":
			var l := StandardMaterial3D.new()
			l.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			l.albedo_color = CYAN
			l.emission_enabled = true
			l.emission = CYAN
			l.emission_energy_multiplier = 1.0
			m = l
		"warm_line":
			var l2 := StandardMaterial3D.new()
			l2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			l2.albedo_color = WARM
			m = l2
		"lantern_core":
			var c := StandardMaterial3D.new()
			c.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			c.albedo_color = Color(1.0, 0.8, 0.55) * 1.6
			m = c
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.82, 0.92, 1.0, 0.22)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.04
			g.metallic_specular = 0.8
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g
		"moss":
			var mo := StandardMaterial3D.new()
			mo.albedo_texture = AssetLib.tex("leafy_grass", "diff")
			mo.albedo_color = Color(0.55, 0.75, 0.38)
			mo.uv1_triplanar = true
			mo.uv1_scale = Vector3(0.4, 0.4, 0.4)
			mo.roughness = 0.9
			m = mo
		"snowcoat":
			var sc := ShaderMaterial.new()
			sc.shader = preload("res://art/shaders/junk_coat.gdshader")
			sc.set_shader_parameter("coat", Color(0.92, 0.96, 1.0))
			sc.set_shader_parameter("top_amt", 0.95)
			sc.set_shader_parameter("film", 0.22)
			sc.set_shader_parameter("roughness", 0.5)
			m = sc
		_:
			m = StandardMaterial3D.new()
	_mats[key] = m
	return m


var _unit_box: BoxMesh


func _box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = ProcMesh.box(Vector3.ONE)
	return _unit_box


static func _beam_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d: Vector3 = b - a
	var len_: float = d.length()
	var y: Vector3 = d / maxf(len_, 0.0001)
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * thick, y * len_, z * thick), (a + b) * 0.5)


func _beam(b: Batch, a: Vector3, c: Vector3, thick: float, mat: Material) -> void:
	b.add(_box(), _beam_xf(a, c, thick), mat)


func _boxp(b: Batch, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	b.add(_box(), Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos), mat)


# --- Borehole ------------------------------------------------------------------------------------

func _build_borehole() -> void:
	var c := Vector3(_bore.x, 0.0, _bore.y)
	var br: float = _bore.z
	var rim_y: float = float(_hm(c.x + br + 0.2, c.z)[0])
	var depth: float = 170.0
	# The shaft: an open cylinder seen from inside, banded strata falling into darkness.
	var cyl := CylinderMesh.new()
	cyl.top_radius = br
	cyl.bottom_radius = br * 0.94
	cyl.height = depth
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = true
	var shaft_mat := ShaderMaterial.new()
	shaft_mat.shader = SHAFT_SHADER
	shaft_mat.set_shader_parameter("top_y", rim_y)
	shaft_mat.set_shader_parameter("depth_m", depth)
	_mats["shaft"] = shaft_mat
	var shaft := MeshInstance3D.new()
	shaft.name = "Borehole"
	shaft.mesh = cyl
	shaft.material_override = shaft_mat
	shaft.position = c + Vector3(0, rim_y - depth * 0.5 + 0.3, 0)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_groups["always"].add_child(shaft)
	# The steel collar round the rim (broken in places while ruined), its bolted ring plates.
	var always := Batch.new()
	var ruin := Batch.new()
	var up := Batch.new()
	var midb := Batch.new()
	var fut := Batch.new()
	var segs: int = 56
	for i: int in segs:
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var p0: Vector3 = c + Vector3(cos(a0), 0, sin(a0)) * (br + 0.9)
		var p1: Vector3 = c + Vector3(cos(a1), 0, sin(a1)) * (br + 0.9)
		var mid: Vector3 = (p0 + p1) * 0.5
		var yaw: float = -(a0 + a1) * 0.5
		var size := Vector3(2.2, 2.4, p0.distance_to(p1) + 0.08)
		var broken: bool = i % 11 == 3 or i % 13 == 7
		if not broken:
			_boxp(ruin, mid + Vector3(0, rim_y - 0.5, 0), size, _mat("rust"), Vector3(0, yaw, 0))
		else:
			_boxp(ruin, mid + Vector3(0, rim_y - 2.2, 0) + (mid - c).normalized() * -1.2, size, _mat("rust"), Vector3(0.5, yaw, 0.35))
		_boxp(up, mid + Vector3(0, rim_y - 0.5, 0), size, _mat("steel"), Vector3(0, yaw, 0))
		_boxp(fut, mid + Vector3(0, rim_y + 0.75, 0), Vector3(2.3, 0.1, size.z), _mat("white"), Vector3(0, yaw, 0))
		_boxp(fut, mid + (mid - c).normalized() * -1.18 + Vector3(0, rim_y + 0.5, 0), Vector3(0.06, 0.06, size.z), _mat("warm_line"), Vector3(0, yaw, 0))
		if i % 4 == 0:
			_boxp(always, mid + Vector3(0, rim_y - 1.2, 0) + (mid - c).normalized() * 1.6, Vector3(1.2, 3.2, 1.6), _mat("ice"), Vector3(0.2, yaw, 0.1))
	# Ice that grew over the collar, a ragged lip.
	for i: int in 22:
		var a: float = _rng.randf() * TAU
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (br + _rng.randf_range(1.5, 6.0))
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 1.0
		s.radial_segments = 10
		s.rings = 5
		always.add(s, Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(_rng.randf_range(2.5, 5.0), _rng.randf_range(1.0, 2.6), _rng.randf_range(2.0, 4.0))), p + Vector3(0, ground_y(p.x, p.z) - 0.2, 0)), _mat("ice"))
	# The headframe: two A-frame towers on opposite rims and a bridge across. Ruined, the bridge
	# has snapped and its halves hang into the hole, the drill string cut.
	var ax: Vector3 = Vector3(cos(0.6), 0, sin(0.6))
	var side: Vector3 = Vector3(-ax.z, 0, ax.x)
	var tower_h: float = 44.0
	for sgn: float in [-1.0, 1.0]:
		var base: Vector3 = c + ax * sgn * (br + 9.0)
		base.y = ground_y(base.x, base.z)
		var top: Vector3 = c + ax * sgn * (br + 2.0) + Vector3(0, rim_y + tower_h, 0)
		for b: Batch in [ruin, midb, fut]:
			var m: Material = _mat("rust") if b == ruin else (_mat("ledger") if b == midb else _mat("white"))
			for s2: float in [-1.0, 1.0]:
				_beam(b, base + side * s2 * 7.0, top + side * s2 * 1.5, 1.1, m)
				_beam(b, base + side * s2 * 7.0 - ax * sgn * 6.0, top + side * s2 * 1.5, 0.8, m)
			for k: int in 6:
				var f: float = float(k + 1) / 7.0
				var w: float = lerpf(7.0, 1.5, f)
				var pk: Vector3 = base.lerp(top, f)
				_beam(b, pk + side * w, pk - side * w, 0.45, m)
			_boxp(b, top + Vector3(0, 1.5, 0), Vector3(5.0, 3.0, 4.0), m, Vector3(0, -0.6, 0))
		_beam(fut, base + side * 7.0 + Vector3(0, 0.6, 0), top + side * 1.5, 0.06, _mat("line"))
	var t0: Vector3 = c - ax * (br + 2.0) + Vector3(0, rim_y + tower_h - 2.0, 0)
	var t1: Vector3 = c + ax * (br + 2.0) + Vector3(0, rim_y + tower_h - 2.0, 0)
	# Intact bridge (mid and up): a box truss, the hoist block and drill string.
	for b: Batch in [midb, fut]:
		var m: Material = _mat("ledger") if b == midb else _mat("white")
		for s2: float in [-1.0, 1.0]:
			_beam(b, t0 + side * s2 * 1.6, t1 + side * s2 * 1.6, 0.9, m)
			_beam(b, t0 + side * s2 * 1.6 + Vector3(0, -3.5, 0), t1 + side * s2 * 1.6 + Vector3(0, -3.5, 0), 0.7, m)
		for k: int in 14:
			var f: float = float(k) / 13.0
			var pk: Vector3 = t0.lerp(t1, f)
			_beam(b, pk + side * 1.6, pk + side * 1.6 + Vector3(0, -3.5, 0), 0.4, m)
			_beam(b, pk - side * 1.6, pk - side * 1.6 + Vector3(0, -3.5, 0), 0.4, m)
		_boxp(b, c + Vector3(0, rim_y + tower_h - 7.5, 0), Vector3(5.0, 4.5, 5.0), _mat("steel") if b == midb else m)
		b.add(ProcMesh.cyl(0.9, 0.9, 60.0, 12), Transform3D(Basis(), c + Vector3(0, rim_y + tower_h - 40.0, 0)), _mat("steel") if b == midb else m)
	# Broken bridge halves hanging into the hole.
	for sgn: float in [-1.0, 1.0]:
		var root: Vector3 = c - ax * sgn * (br + 2.0) + Vector3(0, rim_y + tower_h - 2.0, 0)
		var tip: Vector3 = root + ax * sgn * (br * 0.75) + Vector3(0, -br * 0.65, 0)
		for s2: float in [-1.0, 1.0]:
			_beam(ruin, root + side * s2 * 1.6, tip + side * s2 * 1.6, 0.9, _mat("rust"))
		for k: int in 7:
			var pk: Vector3 = root.lerp(tip, float(k) / 6.0)
			_beam(ruin, pk + side * 1.6, pk - side * 1.6, 0.4, _mat("rust"))
			var ic := CylinderMesh.new()
			ic.top_radius = 0.35
			ic.bottom_radius = 0.0
			ic.height = _rng.randf_range(1.5, 4.0)
			ic.radial_segments = 6
			ruin.add(ic, Transform3D(Basis(), pk + Vector3(0, -ic.height * 0.5 - 0.3, 0)), _mat("ice_clear"))
	# Future: a geothermal plant on the collar, white heat-exchanger pods with thin light seams.
	for k: int in 6:
		var a: float = TAU * float(k) / 6.0 + 0.3
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (br + 11.0)
		p.y = ground_y(p.x, p.z)
		fut.add(ProcMesh.capsule(2.2, 9.0), Transform3D(Basis(), p + Vector3(0, 4.5, 0)), _mat("white"))
		_beam(fut, p + Vector3(0, 1.0, 0), c + Vector3(cos(a), 0, sin(a)) * (br + 1.0) + Vector3(0, rim_y + 0.6, 0), 0.5, _mat("white"))
		_boxp(fut, p + Vector3(0, 4.5, 0) + Vector3(cos(a), 0, sin(a)) * -2.21, Vector3(0.05, 6.0, 0.05), _mat("line"), Vector3(0, -a, 0))
	always.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])
	midb.flush(_groups["mid"])
	fut.flush(_groups["future"])
	# Floating ice shards held in the updraft above the hole (the moon's gravity is weak).
	_shards = MultiMesh.new()
	_shards.transform_format = MultiMesh.TRANSFORM_3D
	_shards.mesh = _shard_mesh()
	_shards.instance_count = 16
	for i: int in 16:
		var a: float = _rng.randf() * TAU
		var rr: float = sqrt(_rng.randf()) * br * 0.8
		var p := c + Vector3(cos(a) * rr, rim_y + _rng.randf_range(6.0, 34.0), sin(a) * rr)
		var s: float = _rng.randf_range(0.8, 2.6)
		var xf := Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)).scaled(Vector3(s, s * 1.6, s)), p)
		_shard_base.append(xf)
		_shards.set_instance_transform(i, xf)
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = _shards
	smi.material_override = _mat("ice_glow")
	smi.visibility_range_end = 600.0
	_groups["always"].add_child(smi)
	# Cold mist venting out of the hole: slow and tall.
	_mist = _vapour(c + Vector3(0, rim_y - 8.0, 0), br * 0.7, 60, 24.0, Vector2(10.0, 24.0), Vector2(1.6, 3.2))
	_mist_mat = _mist.material_override as ShaderMaterial


## An irregular ice crystal (a stretched octahedron with jittered tips).
func _shard_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.1, 1.0, -0.05)
	var bot := Vector3(-0.05, -0.8, 0.1)
	var ring: Array[Vector3] = [Vector3(0.45, 0.05, 0.0), Vector3(0.1, -0.1, 0.4), Vector3(-0.4, 0.1, 0.15), Vector3(-0.2, 0.0, -0.4), Vector3(0.25, -0.05, -0.35)]
	for i: int in ring.size():
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		for tri: Array in [[top, b, a], [bot, a, b]]:
			var nrm: Vector3 = ((tri[1] as Vector3) - (tri[0] as Vector3)).cross((tri[2] as Vector3) - (tri[0] as Vector3)).normalized()
			for v: Vector3 in tri:
				st.set_normal(-nrm)
				st.add_vertex(v)
	return st.commit()


# --- Derricks ------------------------------------------------------------------------------------

## A core-drill derrick: a tall slender lattice tower (low gravity) over a drill string into the
## ice. Ruined: rusted, tilted, its crown broken, icicles off every girt, gripped by an ice mound.
## Mid: straightened and painted. Future: a white geothermal tap with thin light lines.
func _derrick(d: Vector3, idx: int) -> void:
	var base := Vector3(d.x, ground_y(d.x, d.y), d.y)
	var h: float = d.z
	var w0: float = 4.2
	var w1: float = 1.1
	var yaw: float = _rng.randf() * TAU
	var tilt_axis: Vector3 = Vector3(cos(yaw + 1.0), 0, sin(yaw + 1.0))
	var tilt: float = deg_to_rad(_rng.randf_range(5.0, 10.0)) * (1.0 if idx != 2 else 1.6)
	var always := Batch.new()
	for v: int in 3:
		var b := Batch.new()
		var m: Material = [_mat("rust"), _mat("ledger"), _mat("white")][v]
		var bas: Basis = Basis(Vector3.UP, yaw)
		if v == 0:
			bas = Basis(tilt_axis, tilt) * bas
		var hh: float = h * (0.82 if v == 0 and idx % 2 == 0 else 1.0)
		var corners: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		var pt := func(cx: float, cz: float, f: float) -> Vector3:
			var w: float = lerpf(w0, w1, f)
			return base + bas * Vector3(cx * w, f * h, cz * w)
		var panels: int = int(h / 5.0)
		var top_f: float = hh / h
		for cc: Vector2 in corners:
			_beam(b, pt.call(cc.x, cc.y, 0.0), pt.call(cc.x, cc.y, top_f), 0.42, m)
		for k: int in panels:
			var f0: float = float(k) / float(panels)
			var f1: float = float(k + 1) / float(panels)
			if f1 > top_f + 0.001:
				break
			for ci: int in 4:
				var a: Vector2 = corners[ci]
				var c2: Vector2 = corners[(ci + 1) % 4]
				_beam(b, pt.call(a.x, a.y, f1), pt.call(c2.x, c2.y, f1), 0.22, m)
				_beam(b, pt.call(a.x, a.y, f0), pt.call(c2.x, c2.y, f1), 0.14, m)
				_beam(b, pt.call(c2.x, c2.y, f0), pt.call(a.x, a.y, f1), 0.14, m)
				if v == 0 and _rng.randf() < 0.55:
					var q: Vector3 = (pt.call(a.x, a.y, f1) as Vector3).lerp(pt.call(c2.x, c2.y, f1), _rng.randf_range(0.15, 0.85))
					var ic := CylinderMesh.new()
					ic.top_radius = _rng.randf_range(0.1, 0.22)
					ic.bottom_radius = 0.0
					ic.height = _rng.randf_range(0.8, 2.8)
					ic.radial_segments = 5
					b.add(ic, Transform3D(Basis(), q + Vector3(0, -ic.height * 0.5 - 0.15, 0)), _mat("ice_clear"))
		var crown: Vector3 = base + bas * Vector3(0, hh, 0)
		if v == 0 and idx % 2 == 0:
			# The crown block fell and lies in the snow beside the tower.
			_boxp(b, base + Vector3(w0 + 3.0, 0.7, 1.0), Vector3(3.0, 1.6, 2.4), m, Vector3(0.3, yaw, 0.6))
		else:
			_boxp(b, crown + bas * Vector3(0, 1.0, 0), Vector3(3.2, 2.0, 3.2), m, bas.get_euler())
		# Drill string down the middle into the ice; the drawworks shed at the foot.
		b.add(ProcMesh.cyl(0.35, 0.35, hh + 6.0, 8), Transform3D(bas, base + bas * Vector3(0, (hh - 6.0) * 0.5, 0)), _mat("steel") if v < 2 else _mat("white"))
		_boxp(b, base + bas * Vector3(w0 + 2.6, 1.6, 0), Vector3(4.0, 3.2, 5.0), m, (Basis(Vector3.UP, yaw)).get_euler())
		if v == 2:
			# Geothermal tap: a white cap pod at the top and light lines up two legs.
			b.add(ProcMesh.capsule(1.6, 5.0), Transform3D(bas, crown + Vector3(0, 3.6, 0)), m)
			for cc: Vector2 in [corners[0], corners[2]]:
				_beam(b, pt.call(cc.x, cc.y, 0.02) + bas * Vector3(cc.x * 0.25, 0, cc.y * 0.25), pt.call(cc.x, cc.y, 0.98) + bas * Vector3(cc.x * 0.25, 0, cc.y * 0.25), 0.05, _mat("line"))
		b.flush(_groups[["ruin", "mid", "future"][v]], true, 900.0)
	# The ice gripping its feet (ruin and mid) and the frozen spoil heap.
	var mound := SphereMesh.new()
	mound.radius = 1.0
	mound.height = 1.0
	mound.radial_segments = 16
	mound.rings = 6
	mound.is_hemisphere = true
	var ruin := Batch.new()
	ruin.add(mound, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w0 * 2.0, 3.6, w0 * 1.7)), base + Vector3(0, -0.4, 0)), _mat("ice"))
	ruin.add(mound, Transform3D(Basis(Vector3.UP, yaw + 1.2) * Basis.from_scale(Vector3(7.0, 2.6, 5.0)), base + Basis(Vector3.UP, yaw) * Vector3(-w0 - 5.0, -0.3, 2.0)), _mat("ice_clear"))
	ruin.flush(_groups["ruin"])
	var mid := Batch.new()
	mid.add(mound, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w0 * 1.6, 1.6, w0 * 1.4)), base + Vector3(0, -0.4, 0)), _mat("ice"))
	mid.flush(_groups["mid"])
	always.flush(_groups["always"])


# --- Geysers, ridges, spires --------------------------------------------------------------------

## Frozen geysers: stacked ice cones around a vent and a frozen fountain column (tall in the weak
## gravity), venting vapour. Restored, the vapour turns to warm steam over their thawed pools.
func _build_geysers() -> void:
	var b := Batch.new()
	for g: Vector3 in _geysers:
		var s: float = g.z
		var base := Vector3(g.x, ground_y(g.x, g.y), g.y)
		for k: int in 4:
			var cone := CylinderMesh.new()
			cone.top_radius = (2.4 - k * 0.5) * s
			cone.bottom_radius = (5.6 - k * 1.1) * s
			cone.height = (1.6 + k * 0.2) * s
			cone.radial_segments = 18
			cone.rings = 1
			var y: float = base.y - 0.3 + (k * 1.25) * s
			b.add(cone, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(1.0, 1.0, _rng.randf_range(0.8, 1.0))), Vector3(base.x, y + cone.height * 0.5, base.z)), _mat("ice"))
		var top_y: float = base.y + 5.0 * s
		var ch: float = _rng.randf_range(9.0, 15.0) * s
		var col := CylinderMesh.new()
		col.top_radius = 0.25 * s
		col.bottom_radius = 1.1 * s
		col.height = ch
		col.radial_segments = 10
		b.add(col, Transform3D(Basis(Vector3(1, 0, 0), _rng.randf_range(-0.06, 0.06)), Vector3(base.x, top_y + ch * 0.5, base.z)), _mat("ice_glow"))
		for k: int in 5:
			var bulb := SphereMesh.new()
			bulb.radius = 1.0
			bulb.height = 2.0
			bulb.radial_segments = 10
			bulb.rings = 5
			var f: float = _rng.randf_range(0.15, 0.95)
			var r: float = lerpf(1.3, 0.45, f) * s * _rng.randf_range(0.8, 1.2)
			var off := Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4)) * s
			b.add(bulb, Transform3D(Basis.from_scale(Vector3(r, r * 1.5, r)), Vector3(base.x, top_y + ch * f, base.z) + off), _mat("ice_glow"))
		# A frozen splash crown at the top.
		for k: int in 6:
			var a: float = TAU * k / 6.0 + _rng.randf() * 0.5
			var p := Vector3(base.x, top_y + ch, base.z) + Vector3(cos(a), -0.3, sin(a)) * 0.9 * s
			b.add(_shard_mesh(), Transform3D(Basis(Vector3(-sin(a), 0, cos(a)), 0.9).scaled(Vector3(0.7, 1.4, 0.7) * s), p), _mat("ice_clear"))
		_vents.append(_vapour(Vector3(base.x, top_y + 0.5, base.z), 1.0 * s, 14, 9.0, Vector2(2.0, 6.0) * s, Vector2(1.0, 2.0)))
	b.flush(_groups["always"], true, 1100.0)


## Tilted ice slabs heaved up along the pressure ridges (one MultiMesh).
func _build_ridge_slabs() -> void:
	var xfs: Array[Transform3D] = []
	var step: float = 6.0
	var rmax: float = _r_in + 380.0
	var gx: float = -rmax
	while gx <= rmax:
		var gz: float = -rmax
		while gz <= rmax:
			var x: float = gx + _rng.randf_range(-2.5, 2.5)
			var z: float = gz + _rng.randf_range(-2.5, 2.5)
			gz += step
			var r: float = Vector2(x, z).length()
			if r < _r_in + 12.0 or r > rmax:
				continue
			var a: Array = _hm(x, z)
			if float(a[3]) < 0.55 or _rng.randf() > 0.55:
				continue
			var sz := Vector3(_rng.randf_range(2.0, 5.5), _rng.randf_range(0.5, 1.1), _rng.randf_range(1.5, 4.2))
			var bas := Basis.from_euler(Vector3(_rng.randf_range(0.4, 1.2) * (1.0 if _rng.randf() < 0.5 else -1.0), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))) * Basis.from_scale(sz)
			xfs.append(Transform3D(bas, Vector3(x, float(a[0]) - 0.2, z)))
		gx += step
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box()
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RidgeSlabs"
	mmi.multimesh = mm
	mmi.material_override = _mat("ice")
	mmi.visibility_range_end = 520.0
	_groups["always"].add_child(mmi)


## Slender twisted ice spires and two arches out on the plain: shapes only weak gravity allows.
func _build_spires() -> void:
	var b := Batch.new()
	for i: int in 14:
		var a: float = _rng.randf() * TAU
		var p2: Vector2 = _polar(a, _r_in + _rng.randf_range(150.0, 420.0))
		if Vector2(p2.x - _bore.x, p2.y - _bore.y).length() < _bore.z + 50.0:
			continue
		var base := Vector3(p2.x, ground_y(p2.x, p2.y) - 1.0, p2.y)
		var h: float = _rng.randf_range(18.0, 48.0)
		var r0: float = _rng.randf_range(2.0, 4.2)
		var nseg: int = _rng.randi_range(4, 6)
		var p: Vector3 = base
		var lean := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(0.0, 0.18)
		for k: int in nseg:
			var f0: float = float(k) / nseg
			var f1: float = float(k + 1) / nseg
			var seg := CylinderMesh.new()
			seg.bottom_radius = lerpf(r0, r0 * 0.12, f0)
			seg.top_radius = lerpf(r0, r0 * 0.12, f1) * (1.25 if k < nseg - 1 else 0.3)
			seg.height = h / nseg * 1.08
			seg.radial_segments = 9
			var dir := (Vector3.UP + lean + Vector3(sin(k * 1.7 + i), 0, cos(k * 1.3 + i)) * 0.12).normalized()
			var q: Vector3 = p + dir * (h / nseg)
			b.add(seg, Transform3D(Basis(Quaternion(Vector3.UP, dir)), (p + q) * 0.5), _mat("ice"))
			p = q
	for i: int in 2:
		var a: float = [0.9, -2.9][i]
		var p2: Vector2 = _polar(a, _r_in + [190.0, 260.0][i])
		var t := TorusMesh.new()
		t.inner_radius = 15.0 + i * 4.0
		t.outer_radius = 19.0 + i * 5.0
		t.rings = 40
		t.ring_segments = 10
		var y: float = ground_y(p2.x, p2.y) - 5.0
		b.add(t, Transform3D(Basis(Vector3.UP, a + 0.4) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 0.6, 1.0)), Vector3(p2.x, y, p2.y)), _mat("ice"))
	b.flush(_groups["always"], true, 1500.0)


# --- Restored: pools, flowers, lanterns, domes --------------------------------------------------

func _build_pools() -> void:
	var pm := ShaderMaterial.new()
	pm.shader = POOL_SHADER
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 1.0
	disc.radial_segments = 32
	disc.rings = 1
	for ps: Vector3 in _pool_sites:
		var y: float = ground_y(ps.x, ps.y)
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = pm
		mi.position = Vector3(ps.x, y + 0.02, ps.y)
		mi.scale = Vector3(ps.z * 2.0, 0.08, ps.z * 2.0 * _rng.randf_range(0.7, 1.0))
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_instance_shader_parameter("thaw", 0.0)
		_groups["always"].add_child(mi)
		_pools.append(mi)
		var st: CPUParticles3D = _vapour(mi.position + Vector3(0, 0.3, 0), ps.z * 0.6, 6, 6.0, Vector2(1.5, 4.0), Vector2(0.4, 0.9))
		st.emitting = false
		_pool_steam.append(st)


func _mm(mesh: Mesh, xfs: Array[Transform3D], mat: Material, vis: float, gate: float) -> void:
	if mesh == null or xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.visibility_range_end = vis
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_groups["always"].add_child(mmi)
	_bloom_mms.append(mm)
	_bloom_full.append(xfs.size())
	_bloom_gate.append(gate)


## Hardy alpine flowers and moss cushions round the pools and along the field edge, and
## ice-lanterns (thin warm light) on the paths out to the geysers and the borehole.
func _build_blooms() -> void:
	var spots: Array[Vector3] = []
	for ps: Vector3 in _pool_sites:
		for k: int in 26:
			var a: float = _rng.randf() * TAU
			var rr: float = ps.z * _rng.randf_range(1.05, 2.6)
			spots.append(Vector3(ps.x + cos(a) * rr, 0, ps.y + sin(a) * rr))
	for k: int in 420:
		var a: float = _rng.randf() * TAU
		var rr: float = _r_in + pow(_rng.randf(), 1.6) * 40.0 - 4.0
		spots.append(Vector3(cos(a) * rr, 0, sin(a) * rr))
	spots.shuffle()
	var ids: Array[String] = ["crystalline_iceplant", "flower_heliophila", "celandine_01", "moss_01"]
	var per: Dictionary = {}
	for id: String in ids:
		var arr: Array[Transform3D] = []
		per[id] = arr
	for i: int in spots.size():
		var sp: Vector3 = spots[i]
		var id: String = ids[i % ids.size()]
		var s: float = _rng.randf_range(0.8, 1.5) * (2.2 if id == "moss_01" else 1.0)
		(per[id] as Array[Transform3D]).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(sp.x, ground_y(sp.x, sp.z) - 0.02, sp.z)))
	for id: String in ids:
		if AssetLib.has_model(id):
			_mm(AssetLib.model_mesh_lite(id, 400), per[id], null, 90.0, 0.08)
	# Ice-lanterns along paths from the field edge to each geyser and the borehole.
	var lan: Array[Transform3D] = []
	var targets: Array[Vector2] = [Vector2(_bore.x, _bore.y)]
	for g: Vector3 in _geysers:
		targets.append(Vector2(g.x, g.y))
	for tg: Vector2 in targets:
		var dirv: Vector2 = tg.normalized()
		var start: Vector2 = dirv * (_r_in - 2.0)
		var end_: Vector2 = tg - dirv * 12.0
		var n: int = int(start.distance_to(end_) / 8.0)
		for k: int in n + 1:
			var p: Vector2 = start.lerp(end_, float(k) / maxf(n, 1))
			var side: Vector2 = Vector2(-dirv.y, dirv.x) * (2.2 if k % 2 == 0 else -2.2)
			p += side + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
			lan.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(p.x, ground_y(p.x, p.y), p.y)))
	var body := CylinderMesh.new()
	body.top_radius = 0.16
	body.bottom_radius = 0.26
	body.height = 0.9
	body.radial_segments = 7
	var body_xf: Array[Transform3D] = []
	var core_xf: Array[Transform3D] = []
	for xf: Transform3D in lan:
		body_xf.append(xf.translated(Vector3(0, 0.45, 0)))
		core_xf.append(xf.translated(Vector3(0, 0.5, 0)))
	var core := SphereMesh.new()
	core.radius = 0.09
	core.height = 0.3
	core.radial_segments = 6
	core.rings = 3
	_mm(body, body_xf, _mat("ice_clear"), 220.0, 0.3)
	_mm(core, core_xf, _mat("lantern_core"), 260.0, 0.3)


## Greenhouse domes (future): glass hemispheres with a thin white frame, green inside.
func _build_greenhouses() -> void:
	var frame := Batch.new()
	var glass := Batch.new()
	for d: Vector3 in _domes:
		var c := Vector3(d.x, ground_y(d.x, d.y), d.y)
		var r: float = d.z
		glass.add(ProcMesh.hemisphere(r, 28, 10), Transform3D(Basis(), c), _mat("glass"))
		for k: int in 6:
			var t := TorusMesh.new()
			t.inner_radius = r - 0.08
			t.outer_radius = r + 0.08
			t.rings = 48
			t.ring_segments = 4
			frame.add(t, Transform3D(Basis(Vector3.UP, PI * k / 6.0) * Basis(Vector3.RIGHT, PI * 0.5), c), _mat("white"))
		for lat: float in [0.35, 0.7]:
			var rr: float = r * cos(asin(lat))
			var t2 := TorusMesh.new()
			t2.inner_radius = rr - 0.08
			t2.outer_radius = rr + 0.08
			t2.rings = 40
			t2.ring_segments = 4
			frame.add(t2, Transform3D(Basis(), c + Vector3(0, r * lat, 0)), _mat("white"))
		var base := TorusMesh.new()
		base.inner_radius = r - 0.3
		base.outer_radius = r + 0.5
		base.rings = 48
		base.ring_segments = 6
		frame.add(base, Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), c + Vector3(0, 0.1, 0)), _mat("white"))
		var lt := TorusMesh.new()
		lt.inner_radius = r + 0.5
		lt.outer_radius = r + 0.56
		lt.rings = 48
		lt.ring_segments = 3
		frame.add(lt, Transform3D(Basis(), c + Vector3(0, 0.3, 0)), _mat("warm_line"))
		frame.add(ProcMesh.hemisphere(r * 0.75, 16, 5), Transform3D(Basis.from_scale(Vector3(1, 0.45, 1)), c), _mat("moss"))
		for k: int in 5:
			var a: float = _rng.randf() * TAU
			var q: Vector3 = c + Vector3(cos(a), 0, sin(a)) * r * _rng.randf_range(0.2, 0.6)
			frame.add(ProcMesh.cyl(0.05, 0.12, r * _rng.randf_range(0.35, 0.6), 5), Transform3D(Basis(), q + Vector3(0, r * 0.3, 0)), _mat("moss"))
	frame.flush(_groups["future"], true, 700.0)
	glass.flush(_groups["future"], false, 700.0)


# --- Air: vapour, diamond dust ------------------------------------------------------------------

func _vapour_material(tint: Color, density: float, bright: float = 0.62) -> ShaderMaterial:
	var nz := FastNoiseLite.new()
	nz.seed = 812
	nz.frequency = 0.03
	nz.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.normalize = true
	tex.generate_mipmaps = true
	tex.noise = nz
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/vapour_puff.gdshader")
	m.set_shader_parameter("noise_tex", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("shade", Color(0.6, 0.68, 0.8))
	m.set_shader_parameter("brightness", bright)
	m.set_shader_parameter("density", density)
	return m


## A slow vapour column: few, big, long-lived puffs drifting up (weak gravity).
func _vapour(pos: Vector3, radius: float, amount: int, life: float, size: Vector2, speed: Vector2) -> CPUParticles3D:
	if _vent_mat == null:
		_vent_mat = _vapour_material(Color(0.86, 0.92, 1.0), 0.42)
	var p := CPUParticles3D.new()
	p.amount = maxi(2, int(amount * Settings.particle_scale()))
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3(0.05, 1.0, 0.02)
	p.spread = 8.0
	p.gravity = Vector3(0.12, 0.05, 0.0)
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.damping_min = 0.02
	p.damping_max = 0.06
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	p.mesh = q
	p.material_override = _vent_mat if size.y < 15.0 else _vapour_material(Color(0.82, 0.9, 1.0), 0.36, 0.58)
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-radius - 20, -5, -radius - 20), Vector3(radius * 2 + 40, life * speed.y + 30, radius * 2 + 40))
	_groups["always"].add_child(p)
	return p


func _build_air() -> void:
	# Diamond dust: tiny ice crystals glinting as they drift slowly down round Lumi.
	_dust = CPUParticles3D.new()
	_dust.amount = 260
	_dust.lifetime = 10.0
	_dust.preprocess = 10.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(26.0, 6.0, 26.0)
	_dust.direction = Vector3(0.4, -1.0, 0.1)
	_dust.spread = 30.0
	_dust.gravity = Vector3(0.05, -0.08, 0.0)
	_dust.initial_velocity_min = 0.2
	_dust.initial_velocity_max = 0.6
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.2
	_dust.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tx := GradientTexture2D.new()
	tx.gradient = g
	tx.fill = GradientTexture2D.FILL_RADIAL
	tx.fill_from = Vector2(0.5, 0.5)
	tx.fill_to = Vector2(1.0, 0.5)
	tx.width = 32
	tx.height = 32
	sm.albedo_texture = tx
	sm.albedo_color = Color(0.85, 0.93, 1.0, 0.7)
	q.material = sm
	_dust.mesh = q
	add_child(_dust)


# --- Field, sky, light -------------------------------------------------------------------------

## The playable field: junk frozen in under a frosty ice coat, tints from the biome set.
func _dress_field() -> void:
	var view: Node = world.get("view")
	if view == null:
		return
	if view.has_method("set_junk_overlay"):
		var jt: Array = kind.get("junk_tint", [0.86, 0.93, 1.0, 0.6])
		var m := ShaderMaterial.new()
		m.shader = preload("res://art/shaders/junk_coat.gdshader")
		m.set_shader_parameter("coat", Color(float(jt[0]), float(jt[1]), float(jt[2])))
		m.set_shader_parameter("top_amt", 0.6)
		m.set_shader_parameter("film", 0.12)
		m.set_shader_parameter("roughness", 0.3)
		_mats["junk_coat"] = m
		view.set_junk_overlay(m)
	# If the view was not dressed before setup, remove its generic dirt-hill horizon.
	if not bool(view.get("skip_horizon")):
		for c: Node in view.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh and ((c as MeshInstance3D).mesh as SphereMesh).is_hemisphere:
				c.queue_free()


func _setup_sky() -> void:
	var env: Environment = world.get("_env")
	if env == null:
		var we: WorldEnvironment = world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we == null:
			for c: Node in world.get_children():
				if c is WorldEnvironment:
					we = c
					break
		env = we.environment if we else null
	if env == null:
		return
	_env = env
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	var sk: Dictionary = kind.get("sky", {})
	if sk.has("zenith"):
		_sky_mat.set_shader_parameter("zenith_col", _v3(sk["zenith"]))
	if sk.has("horizon"):
		_sky_mat.set_shader_parameter("horizon_col", _v3(sk["horizon"]))
	_sky_mat.set_shader_parameter("stars_day", float(sk.get("stars_day", 0.55)))
	var gd: Vector3 = _v3(sk.get("giant_dir", [-0.38, 0.17, -0.91])).normalized()
	_sky_mat.set_shader_parameter("giant_dir", gd)
	_sky_mat.set_shader_parameter("giant_r", sin(deg_to_rad(float(sk.get("giant_radius_deg", 15.0)))))
	var tilt: float = deg_to_rad(float(sk.get("ring_tilt_deg", 0.0)))
	_sky_mat.set_shader_parameter("giant_pole", Basis(Vector3(gd.z, 0, -gd.x).normalized(), tilt) * Basis(gd, 0.25) * Vector3.UP)
	var a: Dictionary = suns["a"]
	var b: Dictionary = suns["b"]
	_sky_mat.set_shader_parameter("sun_a_col", a["color"])
	_sky_mat.set_shader_parameter("sun_a_size", a["size"])
	_sky_mat.set_shader_parameter("sun_b_col", b["color"])
	_sky_mat.set_shader_parameter("sun_b_size", b["size"])
	_sky_mat.set_shader_parameter("sun_b_amt", clampf(float(b["energy"]) / maxf(float(a["energy"]), 0.01), 0.05, 1.0))
	env.sky.sky_material = _sky_mat
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var amb: Dictionary = kind.get("ambient", {})
	env.ambient_light_sky_contribution = float(amb.get("sky_contribution", 0.4))
	env.ambient_light_color = Color(_v3(amb.get("color", [0.6, 0.72, 0.92])).x, _v3(amb.get("color", [0.6, 0.72, 0.92])).y, _v3(amb.get("color", [0.6, 0.72, 0.92])).z)
	# The companion star's warm, unshadowed fill.
	_companion = DirectionalLight3D.new()
	_companion.name = "CompanionSun"
	_companion.shadow_enabled = false
	_companion.light_color = b["color"]
	_companion.light_energy = 0.0
	_companion.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_companion)
	var sd: Node = world.get("sky_director")
	if sd and sd.get("moon") != null:
		(sd.get("moon") as DirectionalLight3D).sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var sun: DirectionalLight3D = world.get("_sun")
	if sun:
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		sun.light_angular_distance = 0.25


var _env: Environment


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


## Open landscape: see to the crater rim, keep the far blur far.
func _open_camera() -> void:
	var rig: Node = world.get("cam")
	var cam: Camera3D = rig.get("camera") if rig else null
	if cam == null:
		return
	cam.far = 2400.0
	var attrs: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = 300.0
		attrs.dof_blur_far_transition = 450.0
		attrs.dof_blur_amount = 0.03


## Shows the look groups for a base level; live upgrades rise in.
func set_level(l: int, animate: bool) -> void:
	level = clampi(l, 1, 5)
	var on: Array[String] = stages_for(level)
	for g: String in _groups:
		var node: Node3D = _groups[g]
		var want: bool = g in on
		if want and not node.visible and animate:
			node.scale = Vector3(1, 0.02, 1)
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.visible = want
	_apply_restore()


func set_restore(r: float) -> void:
	restore = clampf(r, 0.0, 1.0)
	_apply_restore()


## Warmth: base level and restoration together (a level-5 base warms the moon even before
## every hex is green).
func warmth() -> float:
	return clampf(restore * 0.75 + float(level - 1) / 4.0 * 0.45, 0.0, 1.0)


func _apply_restore() -> void:
	var w: float = warmth()
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("restore", clampf(restore * 0.8 + w * 0.3, 0.0, 1.0))
		_terrain_mat.set_shader_parameter("moss_r", 220.0)
	if _sky_mat:
		_sky_mat.set_shader_parameter("haze", 1.0 - w)
		_sky_mat.set_shader_parameter("warmth", w * 0.6)
	if _mats.has("shaft"):
		(_mats["shaft"] as ShaderMaterial).set_shader_parameter("warm", _smooth(0.25, 0.85, w))
	for i: int in _pools.size():
		var gate: float = 0.12 + 0.6 * float(i) / maxf(_pools.size(), 1)
		var th: float = _smooth(gate, gate + 0.12, w)
		_pools[i].set_instance_shader_parameter("thaw", th)
		_pool_steam[i].emitting = th > 0.5
	for i: int in _bloom_mms.size():
		var k: float = _smooth(_bloom_gate[i], 1.0, w)
		_bloom_mms[i].visible_instance_count = int(round(_bloom_full[i] * k))
	if _vent_mat:
		_vent_mat.set_shader_parameter("tint", Color(0.86, 0.92, 1.0).lerp(Color(1.0, 0.97, 0.93), w))
		_vent_mat.set_shader_parameter("density", lerpf(0.4, 0.62, w))
	if _mist_mat:
		_mist_mat.set_shader_parameter("tint", Color(0.8, 0.88, 1.0).lerp(Color(1.0, 0.94, 0.86), w))
	if _mats.has("junk_coat"):
		(_mats["junk_coat"] as ShaderMaterial).set_shader_parameter("top_amt", lerpf(0.6, 0.3, w))


## Dev: --rime-cam=dist,pitch,yaw[,fov] (landscape shots), --rime-nohud, --rime-restore=R (holds
## the restoration at R, 0..1, instead of reading the hex levels).
func _dev_hooks() -> void:
	if DevHooks.has("rime-nohud"):
		for c: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	if DevHooks.has("rime-restore"):
		_forced_restore = clampf(DevHooks.get_f("rime-restore", 1.0), 0.0, 1.0)
		set_restore(_forced_restore)
	var pt: Node3D = world.get("patch")
	if pt and Vector2(pt.global_position.x, pt.global_position.z).length() > _r_in - 2.0:
		pt.global_position.y = ground_y(pt.global_position.x, pt.global_position.z) + 0.3
	var cam: Node = world.get("cam")
	if DevHooks.has("rime-cam") and cam:
		var c: PackedStringArray = DevHooks.get_s("rime-cam", "30,-0.3,0").split(",")
		cam.set("max_distance", maxf(float(cam.get("max_distance")), float(c[0])))
		cam.set("distance", float(c[0]))
		cam.set("pitch", float(c[1]) if c.size() > 1 else -0.3)
		if c.size() > 2:
			cam.set("yaw", float(c[2]))
		var arm: SpringArm3D = cam.get("_arm") as SpringArm3D
		if arm:
			arm.collision_mask = 0
		if c.size() > 3:
			Settings.fov = float(c[3])
			(cam.get("camera") as Camera3D).fov = Settings.fov
		if cam.has_method("snap"):
			cam.call("snap")


var _forced_restore: float = -1.0


func _process(delta: float) -> void:
	_t += delta
	_slow += delta
	if DevHooks.has("rime-nohud"):
		for c: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	if _slow >= 2.0 and _forced_restore < 0.0:
		_slow = 0.0
		var hl: Node = world.get("hex_levels")
		if hl != null and hl.get("levels") is Dictionary:
			var r: float = restore_from_levels(hl.get("levels"))
			if absf(r - restore) > 0.002:
				set_restore(r)
	if _shards:
		for i: int in _shard_base.size():
			var b: Transform3D = _shard_base[i]
			var bob := Vector3(sin(_t * 0.21 + i) * 0.6, sin(_t * 0.33 + i * 1.7) * 1.4, cos(_t * 0.17 + i) * 0.6)
			_shards.set_instance_transform(i, Transform3D(b.basis.rotated(Vector3.UP, _t * 0.05 * (1.0 + i % 3)), b.origin + bob))
	var p: Node3D = world.get("patch")
	if _dust and p:
		_dust.global_position = p.global_position + Vector3(0, 5.0, 0)
	_update_light()


## Runs after SkyDirector each frame: Rime's own fog, ambient, exposure, the two suns and
## giantshine, on top of the day cycle it keeps.
func _update_light() -> void:
	var sun: DirectionalLight3D = world.get("_sun")
	if _env == null or sun == null:
		return
	var sd: Node = world.get("sky_director")
	var elev: float = -sun.rotation_degrees.x
	var sun_up: float = _smooth(-2.0, 12.0, elev)
	var night: float = 1.0 - sun_up
	var a: Dictionary = suns["a"]
	var b: Dictionary = suns["b"]
	var w: float = warmth()
	var sun_cfg: Dictionary = kind.get("sun", {})
	# Primary: small, white-gold, weak (Rime is the farthest planet).
	sun.light_energy = 3.0 * float(a["energy"]) * sun_up
	sun.visible = sun_up > 0.01
	sun.light_color = (a["color"] as Color).lerp(Color(1.0, 0.82, 0.7), 1.0 - _smooth(4.0, 25.0, elev))
	if sun_cfg.has("color"):
		sun.light_color = sun.light_color.lerp(Color(_v3(sun_cfg["color"]).x, _v3(sun_cfg["color"]).y, _v3(sun_cfg["color"]).z), 0.4)
	var sdir: Vector3 = sun.global_transform.basis.z.normalized()
	# Companion: same path, offset along it by the separation, a touch lower.
	var sep: float = float(b.get("separation", 4.5))
	_companion.rotation_degrees = sun.rotation_degrees + Vector3(1.2, sep, 0.0)
	if b.has("dir"):
		_companion.look_at_from_position(Vector3.ZERO, -_v3(b["dir"]), Vector3.UP if absf(_v3(b["dir"]).y) < 0.99 else Vector3.RIGHT)
	var c_elev: float = -_companion.rotation_degrees.x
	var c_up: float = _smooth(-2.0, 10.0, c_elev)
	_companion.light_energy = 3.0 * float(b["energy"]) * c_up
	_companion.visible = c_up > 0.01
	var cdir: Vector3 = _companion.global_transform.basis.z.normalized()
	# Giantshine: the gas giant's reflected light replaces the moon at night.
	if sd and sd.get("moon") != null:
		var moon: DirectionalLight3D = sd.get("moon")
		var gd: Vector3 = (_sky_mat.get_shader_parameter("giant_dir") as Vector3) if _sky_mat else Vector3(-0.38, 0.17, -0.91)
		var gl: Vector3 = Vector3(gd.x, maxf(gd.y, 0.6), gd.z).normalized()
		moon.look_at_from_position(Vector3.ZERO, -gl, Vector3.UP)
		moon.light_color = Color(0.86, 0.82, 0.74)
		moon.light_energy = 0.42 * night
		moon.visible = night > 0.02
	if _sky_mat:
		_sky_mat.set_shader_parameter("sun_a_dir", sdir)
		_sky_mat.set_shader_parameter("sun_b_dir", cdir)
		_sky_mat.set_shader_parameter("day", sun_up)
		_sky_mat.set_shader_parameter("aurora", float(kind.get("sky", {}).get("aurora", 0.55)) * (1.0 - w * 0.3))
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("night", night)
	# Thin, clear, cold air.
	var fog: Dictionary = kind.get("fog", {})
	var fc: Vector3 = _v3(fog.get("color", [0.55, 0.68, 0.9]))
	var day_fog := Color(fc.x, fc.y, fc.z)
	_env.fog_light_color = Color(0.03, 0.05, 0.1).lerp(day_fog, sun_up)
	_env.fog_density = float(fog.get("density", 0.0006)) * lerpf(1.25, 0.85, w)
	_env.fog_sky_affect = 0.0
	_env.fog_aerial_perspective = float(fog.get("aerial", 0.35))
	_env.fog_height = float(fog.get("height", 1.6))
	_env.fog_height_density = float(fog.get("height_density", 0.006)) * (1.0 + night)
	_env.volumetric_fog_density = lerpf(0.0012, 0.0006, w)
	_env.volumetric_fog_albedo = Color(0.82, 0.88, 0.98)
	_env.volumetric_fog_sky_affect = 0.0
	var amb: Dictionary = kind.get("ambient", {})
	var ac: Vector3 = _v3(amb.get("color", [0.6, 0.72, 0.92]))
	_env.ambient_light_color = Color(0.22, 0.27, 0.42).lerp(Color(ac.x, ac.y, ac.z), sun_up).lerp(Color(0.75, 0.72, 0.68), w * 0.15)
	_env.ambient_light_energy = lerpf(0.55, float(amb.get("energy", 1.0)), sun_up)
	_env.tonemap_exposure = lerpf(1.55, 1.42, sun_up)
	_env.adjustment_saturation = lerpf(1.02, 1.14, w)
	_env.adjustment_contrast = 1.08
