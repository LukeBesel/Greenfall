class_name RimeSite
extends TidewellEnv
## [p_seas] Rime's placeable hub-site prefabs for the walkable globe, same API shape as TideSite:
## compact local scenes (about 80-90 m across) on their own ice patch, no world-origin
## assumptions. (Extends TidewellEnv only to share its prop helpers: _lumpy, _blob_slab,
## _scatter_models and the SeasKit / TideProps paints; nothing of the sea is built.)
##   RimeSite.place(site_id, root, stage, restoration, opts) -> RimeSite
##     site_id      one of SITES
##     stage        0 ruin, 1 restored, 2 futuristic
##     restoration  0..1: rust, moss, thawed pools, lit windows
##     opts         {"radius": m (ground patch), "seed": int}
##   set_state(stage, restoration) re-dresses a built site.
## Sites: hub_camp (the drill camp: cabins on skids, greenhouse dome, tanks, comms mast, snowcat),
## derrick (a Ledger core-drill derrick frozen into the ice), borehole (the shaft with its
## headframe), hot_springs (geothermal pools and a bathhouse).
## Ground: drifts, pressure ridges, cracks and hollows (rime_ice.gdshader masks), a compacted pad
## with steel plates, timber kerbs and grit; never a flat slab. Colliders: the ice (WORLD) and
## every structure (PROP).

const SITES: Dictionary = {
	"hub_camp": {"kind": "hub", "radius": 44.0, "pad": 20.0},
	"derrick": {"kind": "landmark", "radius": 42.0, "pad": 12.0},
	"borehole": {"kind": "landmark", "radius": 46.0, "pad": 18.0},
	"hot_springs": {"kind": "landmark", "radius": 40.0, "pad": 9.0},
}
const ICE_SHADER := preload("res://planet/planets/rime/rime_ice.gdshader")
const PROP_ICE_SHADER := preload("res://planet/planets/rime/rime_prop_ice.gdshader")
const POOL_SHADER := preload("res://planet/planets/rime/rime_pool.gdshader")

var kit_dry: bool = true
var site_id: String = ""
var radius: float = 44.0
var pad_r: float = 16.0
var ground_mat: ShaderMaterial
var _hn := FastNoiseLite.new()
var _rn := FastNoiseLite.new()
var _pools_mi: Array[MeshInstance3D] = []
var _steam: Array[CPUParticles3D] = []
var _decks: Array[Vector3] = []


static func place(p_site: String, root: Node3D, p_stage: int = 0, p_restoration: float = 0.0, opts: Dictionary = {}) -> RimeSite:
	var s := RimeSite.new()
	s.name = "RimeSite_" + p_site
	root.add_child(s)
	s._make(p_site, int(opts.get("seed", hash(p_site) % 100000)), float(opts.get("radius", float(SITES.get(p_site, {}).get("radius", 44.0)))))
	s.set_state(p_stage, p_restoration)
	return s


func _process(_delta: float) -> void:
	pass


func _make(p_site: String, seed_v: int, r: float) -> void:
	site_id = p_site
	radius = r
	pad_r = float(SITES.get(p_site, {}).get("pad", 14.0))
	_rng.seed = seed_v
	_hn.seed = seed_v + 7
	_hn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hn.frequency = 0.045
	_hn.fractal_octaves = 3
	_rn.seed = seed_v + 19
	_rn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rn.frequency = 0.03
	_rn.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_rn.fractal_octaves = 2
	for g: String in ["always", "ruin", "green", "mid", "future"]:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	_ground()
	_pad_dressing()
	_ice_rocks()
	match site_id:
		"hub_camp":
			_site_camp()
		"derrick":
			_site_derrick()
		"borehole":
			_site_borehole()
		"hot_springs":
			_site_springs()


func set_state(p_stage: int, p_restoration: float) -> void:
	stage = clampi(p_stage, 0, 2)
	restore = clampf(p_restoration, 0.0, 1.0)
	var vis: Dictionary = {"always": true, "ruin": stage == 0, "green": stage >= 1, "mid": stage == 1, "future": stage == 2}
	for g: String in _groups:
		(_groups[g] as Node3D).visible = vis[g]
	var warm: float = restore if stage >= 1 else restore * 0.3
	if ground_mat:
		ground_mat.set_shader_parameter("restore", warm)
	for mi: MeshInstance3D in _pools_mi:
		mi.set_instance_shader_parameter("thaw", warm)
	for st: CPUParticles3D in _steam:
		st.emitting = stage >= 1
	TideProps.set_rust(self, stage, restore)


# --- Ground ----------------------------------------------------------------------------------------

## Height and masks (crevasse, drift, ridge, hollow) at local x, z.
func _hm(x: float, z: float) -> Array:
	var d: float = Vector2(x, z).length()
	var pad: float = smoothstep(pad_r, pad_r + 7.0, d)
	var edge: float = 1.0 - smoothstep(radius * 0.8, radius, d)
	var n: float = _hn.get_noise_2d(x, z)
	var rg: float = _rn.get_noise_2d(x * 1.3, z)
	var drift: float = clampf(n * 0.9 + 0.35, 0.0, 1.0)
	var ridge: float = smoothstep(0.55, 0.9, rg)
	var h: float = (drift * 1.6 + ridge * 2.2) * pad * edge
	h += 0.25 * pad * edge * _hn.get_noise_2d(x * 4.0, z * 4.0)
	var crev: float = smoothstep(0.86, 0.97, _rn.get_noise_2d(x * 2.2 + 40.0, z * 2.2)) * pad
	var hollow: float = clampf(-n, 0.0, 1.0) * pad
	h -= crev * 0.5
	# The rim blends down to the globe surface (y = 0).
	return [h, crev, drift * pad, ridge * pad, hollow]


func _ground() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = ICE_SHADER
	ground_mat.set_shader_parameter("snow_tex", AssetLib.tex("snow_02", "diff"))
	ground_mat.set_shader_parameter("snow_nrm", AssetLib.tex("snow_02", "nor_gl"))
	ground_mat.set_shader_parameter("moss_tex", AssetLib.tex("leafy_grass", "diff"))
	var pal: Dictionary = (PlanetEnvs.entry("rime") as Dictionary).get("palette", {})
	for k: Array in [["ice", "ice_col"], ["ice_deep", "ice_deep"], ["snow", "snow_tint"], ["crevasse", "crev_col"], ["moss", "moss_col"]]:
		if pal.has(k[0]):
			var c: Array = pal[k[0]]
			ground_mat.set_shader_parameter(k[1], Color(float(c[0]), float(c[1]), float(c[2])))
	var gp: Vector3 = global_position if is_inside_tree() else Vector3.ZERO
	ground_mat.set_shader_parameter("moss_centre", Vector2(gp.x, gp.z))
	ground_mat.set_shader_parameter("moss_off", 0.0)
	ground_mat.set_shader_parameter("moss_r", radius * 1.4)
	var sv: Array = []
	for i: int in 8:
		sv.append(Vector4(gp.x, gp.z, pad_r * 1.5, 0.7) if i == 0 and site_id in ["derrick", "borehole"] else Vector4(0, 0, -1, 0))
	ground_mat.set_shader_parameter("sites", sv)
	var rings: int = 40
	var spokes: int = 96
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings + 1:
		var rr: float = radius * pow(float(i) / rings, 0.85)
		for j: int in spokes:
			var ang: float = TAU * float(j) / spokes
			var x: float = cos(ang) * rr
			var z: float = sin(ang) * rr
			var a: Array = _hm(x, z)
			st.set_color(Color(float(a[1]), float(a[2]), float(a[3]), float(a[4])))
			st.add_vertex(Vector3(x, float(a[0]), z))
	for i: int in rings:
		for j: int in spokes:
			var j1: int = (j + 1) % spokes
			var a0: int = i * spokes + j
			var a1: int = i * spokes + j1
			var b0: int = (i + 1) * spokes + j
			var b1: int = (i + 1) * spokes + j1
			for idx: int in [a0, a1, b0, a1, b1, b0]:
				st.add_index(idx)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "SiteIce"
	mi.mesh = mesh
	mi.material_override = ground_mat
	_groups["always"].add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = PhysLayers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	_groups["always"].add_child(body)


func ground_y(x: float, z: float) -> float:
	return float(_hm(x, z)[0])


func _ice_mat(key: String) -> ShaderMaterial:
	if _mats.has("ice:" + key):
		return _mats["ice:" + key]
	var s := ShaderMaterial.new()
	s.shader = PROP_ICE_SHADER
	if key == "clear":
		s.set_shader_parameter("snow_top", 0.15)
	if key == "frost":
		s.set_shader_parameter("rough_add", 0.3)
	_mats["ice:" + key] = s
	return s


## The compacted pad: steel deck plates and walkway gratings, timber kerbs round its edge, grit
## and boot-trodden snow, marker poles with flags.
func _pad_dressing() -> void:
	var a := FrontierView.Batch.new()
	var o := Vector3.ZERO
	var bs := Basis()
	var n: int = int(pad_r * pad_r * 0.06)
	for k: int in n:
		var ang: float = _rng.randf() * TAU
		var d: float = sqrt(_rng.randf()) * pad_r * 0.9
		var p := Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		var s := Vector3(_rng.randf_range(1.6, 2.6), 0.08, _rng.randf_range(1.2, 2.0))
		SeasKit.box(a, o, bs, p + Vector3(0, 0.03, 0), s, TideProps.m(self, "steel"), Vector3(_rng.randf_range(-1, 1), _rng.randf() * 180.0, _rng.randf_range(-1, 1)), 0.03)
	var kerb_n: int = int(TAU * pad_r / 2.6)
	for k: int in kerb_n:
		if k % 7 == 3:
			continue  # gaps for paths out
		var ang: float = TAU * (float(k) + 0.5) / kerb_n
		var p := Vector3(cos(ang), 0, sin(ang)) * (pad_r + 0.6)
		p.y = ground_y(p.x, p.z) + 0.15
		SeasKit.box(a, o, bs, p, Vector3(2.3, 0.35, 0.4), TideProps.m(self, "timber2"), Vector3(_rng.randf_range(-3, 3), -rad_to_deg(ang) + 90.0, _rng.randf_range(-4, 4)), 0.06)
	for k: int in 8:
		var ang: float = TAU * k / 8.0 + 0.2
		var p := Vector3(cos(ang), 0, sin(ang)) * (pad_r + 4.0)
		p.y = ground_y(p.x, p.z)
		SeasKit.pipe(a, o, bs, p + Vector3(0, -0.3, 0), p + Vector3(0, 2.2, 0), 0.04, TideProps.m(self, "orange"), 6)
		SeasKit.box(a, o, bs, p + Vector3(0.22, 1.95, 0), Vector3(0.42, 0.28, 0.02), TideProps.m(self, "red"), Vector3(0, _rng.randf() * 360.0, 0), 0.005)
	a.flush(_groups["always"])


## Ice boulders and tilted pressure slabs round the pad (glassy prop ice).
func _ice_rocks() -> void:
	var a := FrontierView.Batch.new()
	for k: int in 22:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(pad_r + 6.0, radius * 0.85)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		p.y = ground_y(p.x, p.z) - 0.3
		var s: float = _rng.randf_range(0.8, 2.6)
		if k % 3 == 0:
			SeasKit.box(a, p, Basis(), Vector3.ZERO, Vector3(s * 2.2, s * 0.5, s * 1.6), _ice_mat("clear"), Vector3(_rng.randf_range(-35, 35), _rng.randf() * 360.0, _rng.randf_range(-30, 30)), 0.12)
		else:
			a.add(_lumpy(k % 5, 0.4, 1.8), _lxf(p, Vector3(0, _rng.randf() * 360.0, 0), Vector3(s * 1.2, s * 0.7, s)), _ice_mat("frost" if k % 2 == 0 else "ice"))
	a.flush(_groups["always"])


func _steam_at(p: Vector3, r: float) -> void:
	var st := CPUParticles3D.new()
	st.amount = 10
	st.lifetime = 5.0
	st.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	st.emission_sphere_radius = r
	st.direction = Vector3.UP
	st.spread = 12.0
	st.gravity = Vector3(0, 0.25, 0)
	st.initial_velocity_min = 0.3
	st.initial_velocity_max = 0.7
	st.scale_amount_min = 2.0
	st.scale_amount_max = 4.0
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.5))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = gt
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.35)
	q.material = m
	st.mesh = q
	var cr := Curve.new()
	cr.add_point(Vector2(0, 0.4))
	cr.add_point(Vector2(1, 1.0))
	st.scale_amount_curve = cr
	st.position = p
	st.emitting = false
	_groups["always"].add_child(st)
	_steam.append(st)


# --- Pieces ----------------------------------------------------------------------------------------

## A modular cabin on skids: rounded bevel body, snow cap on the roof, window row, door with a
## porch and steps, heater vent, chimney, antenna. Lit windows / porch lamp when restored.
func _cabin(a: FrontierView.Batch, grn: FrontierView.Batch, fut: FrontierView.Batch, c: Vector3, yaw: float, size: Vector3, paint: String) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var o: Vector3 = c + Vector3(0, ground_y(c.x, c.z), 0)
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	for sd: float in [-1.0, 1.0]:
		SeasKit.pipe(a, o, bs, Vector3(-hx - 0.4, 0.25, sd * (hz - 0.5)), Vector3(hx + 0.4, 0.25, sd * (hz - 0.5)), 0.16, TideProps.m(self, "steel"), 8)
		SeasKit.pipe(a, o, bs, Vector3(hx + 0.4, 0.25, sd * (hz - 0.5)), Vector3(hx + 0.75, 0.55, sd * (hz - 0.5)), 0.16, TideProps.m(self, "steel"), 8)
	SeasKit.box(a, o, bs, Vector3(0, 0.55, 0), Vector3(size.x - 0.3, 0.3, size.z - 0.3), TideProps.m(self, "steel"))
	SeasKit.box(a, o, bs, Vector3(0, 0.7 + size.y * 0.5, 0), size, TideProps.m(self, paint), Vector3.ZERO, 0.32)
	SeasKit.box(a, o, bs, Vector3(0, 0.7 + size.y * 0.25, 0), Vector3(size.x + 0.04, 0.14, size.z + 0.04), TideProps.m(self, "navy"), Vector3.ZERO, 0.04)
	SeasKit.box(a, o, bs, Vector3(0, 0.75 + size.y + 0.1, 0), Vector3(size.x - 0.1, 0.32, size.z - 0.1), TideProps.m(self, "snow"), Vector3.ZERO, 0.14)
	a.add(_lumpy(2, 0.3, 1.5), Transform3D(bs * Basis.from_scale(Vector3(hx * 0.7, 0.35, hz * 0.6)), o + bs * Vector3(-hx * 0.2, 0.9 + size.y, 0)), _ice_mat("frost"))
	var nw: int = int(size.x / 1.5)
	for w: int in nw:
		var wx: float = -hx + 1.0 + w * (size.x - 2.0) / maxf(1.0, nw - 1)
		if absf(wx - hx * 0.45) < 0.8:
			continue
		SeasKit.box(a, o, bs, Vector3(wx, 0.7 + size.y * 0.6, hz + 0.02), Vector3(0.9, 0.7, 0.12), TideProps.m(self, "navy"), Vector3.ZERO, 0.05)
		SeasKit.box(a, o, bs, Vector3(wx, 0.7 + size.y * 0.6, hz + 0.08), Vector3(0.7, 0.52, 0.04), TideProps.m(self, "glass"), Vector3.ZERO, 0.01)
		SeasKit.box(grn, o, bs, Vector3(wx, 0.7 + size.y * 0.6, hz + 0.11), Vector3(0.66, 0.48, 0.02), TideProps.m(self, "glass_lit"), Vector3.ZERO, 0.005)
	var dx: float = hx * 0.45
	SeasKit.box(a, o, bs, Vector3(dx, 0.7 + 1.05, hz + 0.03), Vector3(1.1, 2.1, 0.14), TideProps.m(self, "navy"))
	SeasKit.box(a, o, bs, Vector3(dx, 0.62, hz + 0.9), Vector3(1.8, 0.14, 1.5), TideProps.m(self, "steel"), Vector3.ZERO, 0.03)
	for k: int in 3:
		SeasKit.box(a, o, bs, Vector3(dx, 0.45 - k * 0.17, hz + 1.85 + k * 0.32), Vector3(1.2, 0.08, 0.32), TideProps.m(self, "steel"), Vector3.ZERO, 0.02)
	SeasKit.rail(a, o, bs, [Vector3(dx - 0.85, 0.68, hz + 0.2), Vector3(dx - 0.85, 0.68, hz + 1.6)] as Array[Vector3], 0.9, TideProps.m(self, "ledger"), 0.03)
	SeasKit.lamp(a, grn, o, bs, Vector3(dx, 0.7 + 2.45, hz + 0.05), Vector3(0, 0, 1), TideProps.m(self, "steel"), TideProps.m(self, "lamp_warm"))
	SeasKit.vent(a, o, bs, Vector3(-hx - 0.04, 0.7 + size.y * 0.55, 0), 0.9, 0.7, Vector3(-1, 0, 0), TideProps.m(self, "steel"), TideProps.m(self, "dark"))
	SeasKit.pipe(a, o, bs, Vector3(-hx * 0.5, 0.7 + size.y, -hz * 0.4), Vector3(-hx * 0.5, 0.7 + size.y + 1.3, -hz * 0.4), 0.12, TideProps.m(self, "steel"), 8)
	SeasKit.pipe(a, o, bs, Vector3(-hx * 0.5, 0.7 + size.y + 1.3, -hz * 0.4), Vector3(-hx * 0.5, 0.7 + size.y + 1.45, -hz * 0.4), 0.24, TideProps.m(self, "dark"), 8)
	SeasKit.pipe(a, o, bs, Vector3(hx * 0.6, 0.7 + size.y, -hz * 0.3), Vector3(hx * 0.6, 0.7 + size.y + 2.4, -hz * 0.3), 0.03, TideProps.m(self, "steel"), 6)
	SeasKit.decal(_groups["always"], o, bs, Vector3(-hx * 0.45, 0.7 + size.y * 0.55, hz + 0.02), Vector3(0, 0, 1), 0.9, 0.9, SeasKit.decal_mat("emblem", Color(0.95, 0.95, 0.92)))
	SeasKit.box(fut, o, bs, Vector3(0, 0.7 + size.y * 0.5, 0), size + Vector3(0.1, 0.1, 0.1), TideProps.m(self, "white"), Vector3.ZERO, 0.36)
	SeasKit.box(fut, o, bs, Vector3(0, 0.7 + size.y * 0.25, 0), Vector3(size.x + 0.16, 0.04, size.z + 0.16), TideProps.m(self, "lamp_cool"), Vector3.ZERO, 0.01)
	SeasKit.solid_box(_groups["always"], o, bs, Vector3(0, 0.7 + size.y * 0.5, 0), size + Vector3(0.8, 1.4, 0.3))
	_decks.append(Vector3(o.x, o.z, maxf(hx, hz)))


## A horizontal tank on a skid frame with hazard bands and a ladder.
func _tank(a: FrontierView.Batch, c: Vector3, yaw: float, ln: float, r: float, paint: String) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var o: Vector3 = c + Vector3(0, ground_y(c.x, c.z), 0)
	SeasKit.pipe(a, o, bs, Vector3(-ln * 0.5, r + 0.5, 0), Vector3(ln * 0.5, r + 0.5, 0), r, TideProps.m(self, paint), 20)
	SeasKit.pipe(a, o, bs, Vector3(-ln * 0.3, r + 0.5, 0), Vector3(-ln * 0.3 + 0.3, r + 0.5, 0), r + 0.03, TideProps.m(self, "hazard"), 20)
	for x: float in [-ln * 0.32, ln * 0.32]:
		SeasKit.box(a, o, bs, Vector3(x, (r + 0.5) * 0.5, 0), Vector3(0.35, r + 0.5, r * 1.7), TideProps.m(self, "steel"))
	for sd: float in [-1.0, 1.0]:
		SeasKit.pipe(a, o, bs, Vector3(-ln * 0.5, 0.12, sd * r * 0.8), Vector3(ln * 0.5, 0.12, sd * r * 0.8), 0.12, TideProps.m(self, "steel"), 8)
	SeasKit.ladder(a, o, bs, Vector3(ln * 0.2, 0.1, r + 0.15), Vector3(ln * 0.2, r * 2.0 + 0.5, r * 0.4 + 0.15), 0.5, Vector3(0, 0, 1), TideProps.m(self, "steel"))
	SeasKit.pipe(a, o, bs, Vector3(0, r * 2.0 + 0.45, 0), Vector3(0, r * 2.0 + 0.85, 0), 0.25, TideProps.m(self, "steel"), 10)
	a.add(_lumpy(1, 0.3, 1.5), Transform3D(bs * Basis.from_scale(Vector3(ln * 0.35, 0.18, r * 0.6)), o + bs * Vector3(0, r * 2.0 + 0.45, 0)), _ice_mat("frost"))
	SeasKit.solid_box(_groups["always"], o, bs, Vector3(0, r + 0.5, 0), Vector3(ln, r * 2.0 + 1.0, r * 2.0))


## A glass greenhouse dome: ribbed white frame on a kerb ring; ruined it has lost most panes,
## restored it is glazed, green inside and warmly lit.
func _dome(a: FrontierView.Batch, ruin: FrontierView.Batch, grn: FrontierView.Batch, c: Vector3, r: float) -> void:
	var o: Vector3 = c + Vector3(0, ground_y(c.x, c.z), 0)
	var bs := Basis()
	SeasKit.pipe(a, o, bs, Vector3(0, 0.0, 0), Vector3(0, 0.5, 0), r + 0.4, TideProps.m(self, "steel"), 32)
	var ribs: int = 10
	for k: int in ribs:
		var ang: float = TAU * k / ribs
		var prev := Vector3(cos(ang) * r, 0.5, sin(ang) * r)
		for j: int in range(1, 7):
			var lat: float = PI * 0.5 * float(j) / 6.0
			var p := Vector3(cos(ang) * r * cos(lat), 0.5 + r * sin(lat), sin(ang) * r * cos(lat))
			SeasKit.pipe(a, o, bs, prev, p, 0.09, TideProps.m(self, "cream"), 6)
			prev = p
	for lat: float in [0.3, 0.65, 1.0]:
		var rr: float = r * cos(lat)
		for k: int in 20:
			var a0: float = TAU * k / 20.0
			var a1: float = TAU * (k + 1) / 20.0
			SeasKit.pipe(a, o, bs, Vector3(cos(a0) * rr, 0.5 + r * sin(lat), sin(a0) * rr), Vector3(cos(a1) * rr, 0.5 + r * sin(lat), sin(a1) * rr), 0.07, TideProps.m(self, "cream"), 6)
	var glass := SphereMesh.new()
	glass.radius = r - 0.05
	glass.height = (r - 0.05) * 2.0
	glass.is_hemisphere = true
	glass.radial_segments = 30
	glass.rings = 10
	grn.add(glass, Transform3D(Basis(), o + Vector3(0, 0.5, 0)), _mat_glass())
	var bed := SphereMesh.new()
	bed.radius = r * 0.8
	bed.height = r * 1.6
	bed.is_hemisphere = true
	bed.radial_segments = 16
	bed.rings = 5
	grn.add(bed, Transform3D(Basis.from_scale(Vector3(1, 0.25, 1)), o + Vector3(0, 0.45, 0)), TideProps.m(self, "leaf"))
	for k: int in 7:
		var ang: float = _rng.randf() * TAU
		var q: Vector3 = Vector3(cos(ang), 0, sin(ang)) * r * _rng.randf_range(0.15, 0.6)
		var s: float = _rng.randf_range(0.6, 1.2)
		grn.add(_lumpy(5 + k % 3, 0.5, 3.0), Transform3D(Basis.from_scale(Vector3(s, s * 1.3, s)), o + q + Vector3(0, 0.9 + s * 0.6, 0)), TideProps.m(self, "leaf"))
	grn.add(glass, Transform3D(Basis.from_scale(Vector3(0.12, 0.12, 0.12)), o + Vector3(0, r + 0.2, 0)), TideProps.m(self, "lamp_warm"))
	# Ruin: a few cracked panes left, broken glass and frame bits in the snow.
	for k: int in 4:
		var ang: float = _rng.randf() * TAU
		var lat: float = _rng.randf_range(0.2, 0.9)
		var p := Vector3(cos(ang) * r * cos(lat), 0.5 + r * sin(lat), sin(ang) * r * cos(lat))
		SeasKit.box(ruin, o, bs, p, Vector3(1.4, 0.04, 1.2), _mat_glass(), Vector3(rad_to_deg(lat) * 0.0, -rad_to_deg(ang), 90.0 - rad_to_deg(lat)), 0.01)
	for k: int in 5:
		var q := Vector3(_rng.randf_range(-r, r), 0.1, _rng.randf_range(-r, r)) * 1.2
		SeasKit.pipe(ruin, o, bs, q, q + Vector3(_rng.randf_range(-1.5, 1.5), 0.05, _rng.randf_range(-1.5, 1.5)), 0.08, TideProps.m(self, "cream"), 6)
	SeasKit.solid_cyl(_groups["always"], o, bs, Vector3.ZERO, Vector3(0, r, 0), r)


func _mat_glass() -> StandardMaterial3D:
	if _mats.has("glassdome"):
		return _mats["glassdome"]
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.82, 0.92, 1.0, 0.25)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.roughness = 0.05
	g.metallic_specular = 0.8
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["glassdome"] = g
	return g


## A lattice comms mast with a dish, guy lines and a red beacon (lit when restored).
func _mast(a: FrontierView.Batch, grn: FrontierView.Batch, c: Vector3, h: float) -> void:
	var o: Vector3 = c + Vector3(0, ground_y(c.x, c.z), 0)
	var bs := Basis()
	SeasKit.box(a, o, bs, Vector3(0, 0.2, 0), Vector3(2.0, 0.4, 2.0), TideProps.m(self, "steel"))
	SeasKit.tower(a, o, bs, Vector3.ZERO, 0.4, h, 0.7, 0.35, 3, TideProps.m(self, "red"), 0.08, 1.6)
	for k: int in 3:
		var y: float = h * (0.3 + k * 0.3)
		if k % 2 == 0:
			SeasKit.tower(a, o, bs, Vector3.ZERO, y, y + 1.4, lerpf(0.72, 0.36, y / h), lerpf(0.72, 0.36, (y + 1.4) / h), 3, TideProps.m(self, "cream"), 0.09, 0.7)
	SeasKit.pipe(a, o, bs, Vector3(0.3, h * 0.72, 0), Vector3(0.9, h * 0.72, 0.3), 0.05, TideProps.m(self, "steel"), 6)
	SeasKit.pipe(a, o, bs, Vector3(1.0, h * 0.72 - 0.05, 0.35), Vector3(1.25, h * 0.72 + 0.05, 0.45), 0.8, TideProps.m(self, "cream"), 18)
	for k: int in 3:
		var ang: float = TAU * k / 3.0 + 0.4
		var g := Vector3(cos(ang), 0, sin(ang)) * h * 0.55
		g.y = ground_y(c.x + g.x, c.z + g.z) - o.y
		SeasKit.pipe(a, o, bs, Vector3(0, h * 0.85, 0), g, 0.015, TideProps.m(self, "dark"), 4)
		SeasKit.box(a, o, bs, g + Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.5), TideProps.m(self, "steel"))
	SeasKit.pipe(a, o, bs, Vector3(0, h, 0), Vector3(0, h + 0.4, 0), 0.06, TideProps.m(self, "steel"), 6)
	SeasKit.pipe(grn, o, bs, Vector3(0, h + 0.4, 0), Vector3(0, h + 0.65, 0), 0.14, TideProps.m(self, "lamp_red"), 8)
	SeasKit.solid_cyl(_groups["always"], o, bs, Vector3.ZERO, Vector3(0, h, 0), 0.9)


## A little snowcat: body, glazed cab, two rubber track units with tread ribs, a roof light bar.
func _snowcat(a: FrontierView.Batch, grn: FrontierView.Batch, c: Vector3, yaw: float, paint: String) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var o: Vector3 = c + Vector3(0, ground_y(c.x, c.z), 0)
	for sd: float in [-1.0, 1.0]:
		SeasKit.box(a, o, bs, Vector3(sd * 1.15, 0.5, 0), Vector3(0.75, 0.95, 4.0), TideProps.m(self, "dark"), Vector3.ZERO, 0.3)
		for k: int in 12:
			SeasKit.box(a, o, bs, Vector3(sd * 1.15, 0.03, -1.65 + k * 0.3), Vector3(0.8, 0.08, 0.12), TideProps.m(self, "steel"), Vector3.ZERO, 0.02)
		for k: int in 4:
			SeasKit.pipe(a, o, bs, Vector3(sd * 1.55, 0.45, -1.3 + k * 0.86), Vector3(sd * 1.6, 0.45, -1.3 + k * 0.86), 0.3, TideProps.m(self, "steel"), 10)
	SeasKit.box(a, o, bs, Vector3(0, 1.2, -0.2), Vector3(2.4, 0.8, 3.8), TideProps.m(self, paint), Vector3.ZERO, 0.22)
	SeasKit.box(a, o, bs, Vector3(0, 2.05, -0.6), Vector3(2.1, 1.0, 2.0), TideProps.m(self, paint), Vector3.ZERO, 0.25)
	SeasKit.box(a, o, bs, Vector3(0, 2.1, 0.42), Vector3(1.8, 0.7, 0.08), TideProps.m(self, "glass"), Vector3(-15, 0, 0), 0.02)
	for sd: float in [-1.0, 1.0]:
		SeasKit.box(a, o, bs, Vector3(sd * 1.06, 2.1, -0.6), Vector3(0.06, 0.6, 1.5), TideProps.m(self, "glass"), Vector3.ZERO, 0.01)
		SeasKit.pipe(grn, o, bs, Vector3(sd * 0.7, 1.2, 1.72), Vector3(sd * 0.7, 1.2, 1.78), 0.14, TideProps.m(self, "lamp_warm"), 10)
	SeasKit.box(a, o, bs, Vector3(0, 2.62, -0.6), Vector3(1.6, 0.14, 0.3), TideProps.m(self, "steel"))
	SeasKit.box(a, o, bs, Vector3(0, 0.9, 2.1), Vector3(2.8, 0.7, 0.2), TideProps.m(self, "ledger"), Vector3(-20, 0, 0), 0.06)  # plough blade
	SeasKit.solid_box(_groups["always"], o, bs, Vector3(0, 1.3, 0), Vector3(3.0, 2.6, 4.4))


# --- Sites -----------------------------------------------------------------------------------------

## The drill camp hub: three cabins on skids round a plated yard, a greenhouse dome, fuel tanks,
## a comms mast, a snowcat, sleds, crates and drums; string lights between the cabins (restored).
func _site_camp() -> void:
	var a := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var grn := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	_cabin(a, grn, fut, Vector3(-8.0, 0, -6.0), 0.35, Vector3(8.0, 2.8, 3.6), "orange")
	_cabin(a, grn, fut, Vector3(5.0, 0, -9.5), -0.2, Vector3(6.5, 2.6, 3.4), "cream")
	_cabin(a, grn, fut, Vector3(11.0, 0, 1.0), -1.3, Vector3(6.0, 2.6, 3.4), "teal")
	_dome(a, ruin, grn, Vector3(-10.0, 0, 8.0), 5.0)
	_tank(a, Vector3(2.0, 0, 11.5), 0.15, 6.0, 1.0, "red")
	_tank(a, Vector3(5.5, 0, 13.5), 0.25, 5.0, 0.9, "cream")
	_mast(a, grn, Vector3(15.0, 0, -10.0), 14.0)
	_snowcat(a, grn, Vector3(2.0, 0, 2.5), 2.4, "ledger")
	# Covered walkway between the first two cabins.
	var w0 := Vector3(-3.6, ground_y(-3.6, -7.5) + 1.9, -7.5)
	var w1 := Vector3(1.6, ground_y(1.6, -9.0) + 1.9, -9.0)
	SeasKit.pipe(a, Vector3.ZERO, Basis(), w0, w1, 0.95, TideProps.m(self, "cream"), 16)
	for k: int in 4:
		var p: Vector3 = w0.lerp(w1, (k + 0.5) / 4.0)
		SeasKit.pipe(a, Vector3.ZERO, Basis(), p - (w1 - w0).normalized() * 0.08, p + (w1 - w0).normalized() * 0.08, 1.02, TideProps.m(self, "navy"), 16)
	# Clutter: crates, drums, a sled, a workbench, pallets.
	var cols: Array[String] = ["orange", "teal", "red", "ledger", "cream"]
	for k: int in 10:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(4.0, 15.0)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		if _on_deck(p):
			continue
		p.y = ground_y(p.x, p.z)
		var s: float = _rng.randf_range(0.6, 1.1)
		SeasKit.box(a, p, Basis(), Vector3(0, s * 0.35, 0), Vector3(s, s * 0.7, s * 1.3), TideProps.m(self, cols[k % 5]), Vector3(0, _rng.randf() * 90.0, 0))
	var pts: Array[Transform3D] = []
	for k: int in 12:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(3.0, 17.0)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		if _on_deck(p):
			continue
		p.y = ground_y(p.x, p.z)
		pts.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	_scatter_models(["Barrel_01", "barrel_03", "propane_tank", "metal_toolbox", "wooden_crate_02", "small_lpg_tank"], pts, _groups["always"], 200.0)
	var sl := Vector3(-3.0, 0, 6.0)
	sl.y = ground_y(sl.x, sl.z)
	SeasKit.box(a, sl, Basis(Vector3.UP, 0.6), Vector3(0, 0.45, 0), Vector3(1.2, 0.12, 2.6), TideProps.m(self, "timber"))
	for sd: float in [-1.0, 1.0]:
		SeasKit.pipe(a, sl, Basis(Vector3.UP, 0.6), Vector3(sd * 0.55, 0.06, -1.3), Vector3(sd * 0.55, 0.06, 1.5), 0.05, TideProps.m(self, "steel"), 6)
		SeasKit.pipe(a, sl, Basis(Vector3.UP, 0.6), Vector3(sd * 0.55, 0.06, 1.5), Vector3(sd * 0.55, 0.4, 1.75), 0.05, TideProps.m(self, "steel"), 6)
	# Lamp posts and string lights (lit when restored).
	var posts: Array[Vector3] = [Vector3(-4.0, 0, 0.0), Vector3(4.5, 0, -3.0), Vector3(6.0, 0, 6.0), Vector3(-5.0, 0, 5.0)]
	for i: int in posts.size():
		var p: Vector3 = posts[i]
		p.y = ground_y(p.x, p.z)
		posts[i] = p
		SeasKit.pipe(a, p, Basis(), Vector3.ZERO, Vector3(0, 3.6, 0), 0.08, TideProps.m(self, "steel"), 8)
		SeasKit.lamp(a, grn, p, Basis(), Vector3(0, 3.5, 0), Vector3(1, 0, 0), TideProps.m(self, "steel"), TideProps.m(self, "lamp_warm"))
		SeasKit.solid_cyl(_groups["always"], p, Basis(), Vector3.ZERO, Vector3(0, 3.6, 0), 0.15)
	var bulb := SphereMesh.new()
	bulb.radius = 0.08
	bulb.height = 0.16
	bulb.radial_segments = 8
	bulb.rings = 4
	for i: int in posts.size():
		var p0: Vector3 = posts[i] + Vector3(0, 3.5, 0)
		var p1: Vector3 = posts[(i + 1) % posts.size()] + Vector3(0, 3.5, 0)
		for k: int in 10:
			var t: float = (k + 0.5) / 10.0
			grn.add(bulb, Transform3D(Basis(), p0.lerp(p1, t) - Vector3(0, sin(t * PI) * 0.7, 0)), TideProps.m(self, "bulb"))
	# Ruin: drifted junk heaps, a toppled drum stack, snow-buried sheet metal.
	var heap: Array[Transform3D] = []
	for k: int in 40:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(2.0, pad_r + 6.0)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		if _on_deck(p):
			continue
		p.y = ground_y(p.x, p.z) - 0.1
		heap.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5)), p))
	_scatter_models(["Barrel_01", "old_tyre", "trashbag", "wooden_crate_02", "metal_trash_can", "cardboard_box_01", "rusted_wheel_rim_01", "metal_jerrycan"], heap, _groups["ruin"], 200.0)
	for k: int in 8:
		var p := Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-12, 14))
		p.y = ground_y(p.x, p.z) + 0.05
		SeasKit.box(ruin, p, Basis(), Vector3.ZERO, Vector3(_rng.randf_range(1.0, 2.2), 0.06, _rng.randf_range(0.6, 1.3)), TideProps.m(self, ["red", "steel", "orange"][k % 3]), Vector3(_rng.randf_range(-10, 10), _rng.randf() * 360.0, _rng.randf_range(-10, 10)), 0.02)
		a.add(_lumpy(k % 4, 0.35, 1.6), _lxf(p + Vector3(0.4, -0.1, 0.2), Vector3(0, _rng.randf() * 360.0, 0), Vector3(1.2, 0.35, 0.8)), TideProps.m(self, "snow"))
	a.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	grn.flush(_groups["green"])
	fut.flush(_groups["future"])


## A Ledger core-drill derrick frozen into the ice: a lattice tower on a drill floor, drawworks
## shed, pipe rack, mud tanks, icicles; the ice grips its feet when ruined; restored it is a
## geothermal tap with a warm vent.
func _site_derrick() -> void:
	var a := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var grn := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var o := Vector3(0, ground_y(0, 0), 0)
	var bs := Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, deg_to_rad(3.0))
	SeasKit.box(a, o, bs, Vector3(0, 1.0, 0), Vector3(8.0, 2.0, 8.0), TideProps.m(self, "navy"))
	SeasKit.box(a, o, bs, Vector3(0, 2.1, 0), Vector3(8.6, 0.25, 8.6), TideProps.m(self, "steel"))
	SeasKit.box(a, o, bs, Vector3(0, 0.15, 0), Vector3(8.2, 0.3, 8.2), TideProps.m(self, "hazard"), Vector3.ZERO, 0.06)
	SeasKit.rail(a, o, bs, [Vector3(-4.1, 2.2, -4.1), Vector3(4.1, 2.2, -4.1), Vector3(4.1, 2.2, 4.1), Vector3(-4.1, 2.2, 4.1)] as Array[Vector3], 1.0, TideProps.m(self, "ledger"))
	SeasKit.tower(a, o, bs, Vector3.ZERO, 2.2, 28.0, 3.0, 0.9, 4, TideProps.m(self, "orange"), 0.2, 2.8, PI * 0.25)
	SeasKit.box(a, o, bs, Vector3(0, 28.8, 0), Vector3(2.4, 1.6, 2.4), TideProps.m(self, "ledger"))
	SeasKit.box(a, o, bs, Vector3(0, 17.0, 0), Vector3(3.4, 0.2, 3.4), TideProps.m(self, "steel"))
	SeasKit.pipe(a, o, bs, Vector3(0, -2.0, 0), Vector3(0, 27.0, 0), 0.2, TideProps.m(self, "steel"), 10)
	SeasKit.pipe(a, o, bs, Vector3(0, 9.0, 0), Vector3(0, 11.0, 0), 0.6, TideProps.m(self, "ledger"), 12)  # travelling block
	for k: int in 3:
		var y: float = 6.0 + k * 7.0
		var r: float = lerpf(3.0, 0.9, (y - 2.2) / 25.8)
		for c: int in 4:
			var ang: float = TAU * c / 4.0 + PI * 0.25
			var q := Vector3(cos(ang) * r, y, sin(ang) * r)
			var ic := CylinderMesh.new()
			ic.top_radius = _rng.randf_range(0.1, 0.2)
			ic.bottom_radius = 0.0
			ic.height = _rng.randf_range(0.8, 2.4)
			ic.radial_segments = 5
			ruin.add(ic, Transform3D(bs, o + bs * (q + Vector3(0, -ic.height * 0.5 - 0.15, 0))), _ice_mat("clear"))
	# Drawworks shed, pipe rack with drill pipe, mud tanks.
	_cabin(a, grn, fut, Vector3(7.5, 0, -2.0), 0.4 + PI * 0.5, Vector3(5.0, 2.6, 3.2), "orange")
	var rk := Vector3(-8.0, ground_y(-8.0, 2.0), 2.0)
	for x: float in [-2.5, 0.0, 2.5]:
		SeasKit.box(a, rk, Basis(Vector3.UP, 0.4), Vector3(x, 0.5, 0), Vector3(0.3, 1.0, 3.0), TideProps.m(self, "steel"))
	for k: int in 9:
		SeasKit.pipe(a, rk, Basis(Vector3.UP, 0.4), Vector3(-4.0, 1.15 + (k / 3) * 0.24, -0.6 + (k % 3) * 0.3 + (k / 3) * 0.15), Vector3(4.0, 1.15 + (k / 3) * 0.24, -0.6 + (k % 3) * 0.3 + (k / 3) * 0.15), 0.11, TideProps.m(self, "steel" if k % 2 == 0 else "red"), 8)
	_tank(a, Vector3(-3.0, 0, -9.0), 0.4, 5.0, 1.0, "ledger")
	_tank(a, Vector3(1.5, 0, -10.5), 0.4, 4.0, 0.9, "teal")
	# Ruin: ice grips the drill floor, a fallen crown block, junk.
	ruin.add(_lumpy(3, 0.35, 1.6), Transform3D(bs * Basis.from_scale(Vector3(6.5, 2.6, 6.0)), o + Vector3(0, -0.8, 0)), _ice_mat("ice"))
	SeasKit.box(ruin, o, Basis(), Vector3(6.0, 0.8, 6.0), Vector3(2.4, 1.6, 2.4), TideProps.m(self, "ledger"), Vector3(20, 35, 40))
	var heap: Array[Transform3D] = []
	for k: int in 26:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(6.0, 20.0)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		p.y = ground_y(p.x, p.z) - 0.1
		heap.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	_scatter_models(["Barrel_01", "rusted_wheel_rim_02", "old_tyre", "metal_jerrycan", "can_rusted"], heap, _groups["ruin"], 200.0)
	# Restored: a warm geothermal vent at the foot, lamps; future: white tap pod with light lines.
	SeasKit.pipe(grn, o, bs, Vector3(0, 2.3, 0), Vector3(0, 2.5, 0), 1.2, TideProps.m(self, "lamp_warm"), 18)
	_steam_at(o + Vector3(0, 3.0, 0), 1.2)
	SeasKit.pipe(fut, o, bs, Vector3(0, 29.5, 0), Vector3(0, 33.0, 0), 1.5, TideProps.m(self, "white"), 18)
	for c: int in 2:
		var ang: float = PI * c + PI * 0.25
		SeasKit.pipe(fut, o, bs, Vector3(cos(ang) * 3.05, 2.3, sin(ang) * 3.05), Vector3(cos(ang) * 0.95, 27.5, sin(ang) * 0.95), 0.04, TideProps.m(self, "lamp_cool"), 4)
	a.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	grn.flush(_groups["green"])
	fut.flush(_groups["future"])
	SeasKit.solid_box(_groups["always"], o, bs, Vector3(0, 1.5, 0), Vector3(8.6, 3.0, 8.6))
	SeasKit.solid_box(_groups["always"], rk, Basis(Vector3.UP, 0.4), Vector3(0, 0.8, 0), Vector3(8.0, 1.6, 3.0))


## The borehole: a wide shaft ringed by a concrete collar with a hazard kerb and rail, a headframe
## with sheave wheels over it, a winder house; cold mist when ruined, warm glow when restored.
func _site_borehole() -> void:
	var a := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var grn := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var o := Vector3(0, 0.0, 0)
	var bs := Basis()
	var r: float = 7.0
	# Collar: segmented chunky ring blocks (not one cylinder), hazard kerb, rail.
	var segs: int = 20
	for k: int in segs:
		var ang: float = TAU * (k + 0.5) / segs
		var p := Vector3(cos(ang), 0, sin(ang)) * (r + 1.2)
		SeasKit.box(a, o, bs, p + Vector3(0, 0.4, 0), Vector3(2.0, 1.2, TAU * (r + 1.2) / segs + 0.05), TideProps.m(self, "concrete"), Vector3(0, -rad_to_deg(ang), 0), 0.12)
		SeasKit.box(a, o, bs, p + Vector3(0, 1.05, 0) - Vector3(cos(ang), 0, sin(ang)) * 0.75, Vector3(0.4, 0.14, TAU * (r + 0.4) / segs), TideProps.m(self, "hazard"), Vector3(0, -rad_to_deg(ang), 0), 0.03)
	var rp: Array[Vector3] = []
	for k: int in 25:
		var ang: float = TAU * k / 24.0
		rp.append(Vector3(cos(ang), 0, sin(ang)) * (r + 2.0) + Vector3(0, 1.0, 0))
	SeasKit.rail(a, o, bs, rp, 1.0, TideProps.m(self, "ledger"))
	# The shaft itself: dark walls going down with ring stiffeners, a black bottom.
	SeasKit.pipe(a, o, bs, Vector3(0, -14.0, 0), Vector3(0, -14.2, 0), r + 0.2, TideProps.m(self, "dark"), 32)
	for k: int in 6:
		var y: float = -0.5 - k * 2.2
		for j: int in 24:
			var a0: float = TAU * j / 24.0
			var a1: float = TAU * (j + 1) / 24.0
			SeasKit.box(a, o, bs, Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)) * (r + 0.1) + Vector3(0, y - 1.0, 0), Vector3(0.3, 2.2, TAU * r / 24.0 + 0.05), TideProps.m(self, "concrete" if k < 2 else "dark"), Vector3(0, -rad_to_deg((a0 + a1) * 0.5), 0), 0.04)
	# Headframe: two A-frame trusses, a sheave deck with two wheels, cables down the hole.
	var ht: float = 18.0
	for sd: float in [-1.0, 1.0]:
		SeasKit.truss(a, o, bs, Vector3(sd * (r + 1.5), 1.0, -3.0), Vector3(sd * 1.5, ht, 0), 1.4, 1.2, TideProps.m(self, "ledger"), 0.16)
		SeasKit.truss(a, o, bs, Vector3(sd * (r + 1.5), 1.0, 3.0), Vector3(sd * 1.5, ht, 0), 1.4, 1.2, TideProps.m(self, "ledger"), 0.16)
	SeasKit.box(a, o, bs, Vector3(0, ht + 0.4, 0), Vector3(5.0, 0.8, 3.0), TideProps.m(self, "red"))
	for sd: float in [-0.9, 0.9]:
		var wheel := TorusMesh.new()
		wheel.inner_radius = 1.5
		wheel.outer_radius = 1.75
		wheel.rings = 24
		wheel.ring_segments = 6
		a.add(wheel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), o + Vector3(sd, ht + 1.9, 0)), TideProps.m(self, "steel_plain"))
		SeasKit.pipe(a, o, bs, Vector3(sd, ht + 1.9, -0.3), Vector3(sd, ht + 1.9, 0.3), 0.25, TideProps.m(self, "steel"), 10)
		SeasKit.pipe(a, o, bs, Vector3(sd + 1.6 * signf(sd), ht + 1.9, 0), Vector3(sd + 1.6 * signf(sd), -6.0, 0), 0.04, TideProps.m(self, "dark"), 4)
	SeasKit.box(a, o, bs, Vector3(1.0, -4.0, 0), Vector3(1.6, 2.4, 1.6), TideProps.m(self, "ledger"))  # cage, half way down
	SeasKit.pipe(grn, o, bs, Vector3(0, ht + 0.8, 0), Vector3(0, ht + 1.0, 0), 0.2, TideProps.m(self, "lamp_red"), 8)
	# Winder house with a cable run to the sheaves.
	_cabin(a, grn, fut, Vector3(-15.0, 0, 6.0), 0.6, Vector3(6.0, 3.2, 4.0), "teal")
	SeasKit.pipe(a, Vector3.ZERO, bs, Vector3(-13.0, ground_y(-13.0, 6.0) + 3.8, 5.0), Vector3(-0.9, ht + 1.9, 0), 0.04, TideProps.m(self, "dark"), 4)
	_tank(a, Vector3(12.0, 0, -9.0), -0.5, 5.0, 1.0, "red")
	# Warm glow from the shaft when restored, cold mist when ruined (both steam particles).
	SeasKit.pipe(grn, o, bs, Vector3(0, -12.0, 0), Vector3(0, -11.8, 0), r - 0.5, TideProps.m(self, "lamp_warm"), 28)
	_steam_at(o + Vector3(0, 0.5, 0), r * 0.6)
	var heap: Array[Transform3D] = []
	for k: int in 30:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(r + 4.0, 24.0)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		p.y = ground_y(p.x, p.z) - 0.1
		heap.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	_scatter_models(["Barrel_01", "rusted_wheel_rim_01", "old_tyre", "metal_jerrycan", "concrete_road_barrier"], heap, _groups["ruin"], 200.0)
	for k: int in 6:
		var ang: float = _rng.randf() * TAU
		var p := Vector3(cos(ang), 0, sin(ang)) * (r + 4.5)
		p.y = ground_y(p.x, p.z)
		SeasKit.box(ruin, p, Basis(), Vector3(0, 0.3, 0), Vector3(1.8, 0.6, 1.4), TideProps.m(self, "concrete"), Vector3(_rng.randf_range(-20, 20), _rng.randf() * 360.0, _rng.randf_range(-20, 20)), 0.1)
	SeasKit.pipe(fut, o, bs, Vector3(0, 1.15, 0), Vector3(0, 1.2, 0), r + 0.5, TideProps.m(self, "lamp_cool"), 32)
	a.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	grn.flush(_groups["green"])
	fut.flush(_groups["future"])
	for k: int in 12:
		var ang: float = TAU * k / 12.0
		SeasKit.solid_box(_groups["always"], o, bs, Vector3(cos(ang), 0, sin(ang)) * (r + 1.6), Vector3(2.6, 3.0, TAU * (r + 1.6) / 12.0 + 0.2), Vector3(0, -rad_to_deg(ang), 0))
	SeasKit.solid_box(_groups["always"], o, bs, Vector3(0, 0.5, 0), Vector3(r * 1.6, 1.0, r * 1.6), Vector3.ZERO, PhysLayers.WORLD)  # lid: nobody falls in


## Hot springs: three pools in rocky ice rims (frozen when ruined, steaming and turquoise when
## restored), a bathhouse cabin, a boardwalk, a pipe from a geothermal wellhead.
func _site_springs() -> void:
	var a := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var grn := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var pm := ShaderMaterial.new()
	pm.shader = POOL_SHADER
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 1.0
	disc.radial_segments = 32
	disc.rings = 1
	var pools: Array[Vector3] = [Vector3(-3.0, 0, 2.0), Vector3(5.0, 0, -3.0), Vector3(2.0, 0, 7.5)]
	var radii: Array[float] = [4.0, 3.0, 2.4]
	for i: int in pools.size():
		var c: Vector3 = pools[i]
		c.y = ground_y(c.x, c.z)
		var rr: float = radii[i]
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = pm
		mi.position = c + Vector3(0, 0.12, 0)
		mi.scale = Vector3(rr * 2.0, 0.08, rr * 1.8)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_groups["always"].add_child(mi)
		_pools_mi.append(mi)
		var n: int = int(rr * 4.0)
		for k: int in n:
			var ang: float = TAU * k / n + _rng.randf_range(-0.1, 0.1)
			var p: Vector3 = c + Vector3(cos(ang) * rr, 0, sin(ang) * rr * 0.9)
			var s: float = _rng.randf_range(0.5, 1.0)
			a.add(_lumpy(k % 5, 0.4, 1.8), _lxf(p + Vector3(0, -0.05, 0), Vector3(0, _rng.randf() * 360.0, 0), Vector3(s * 1.2, s * 0.6, s)), _ice_mat("frost" if k % 3 else "ice"))
		_steam_at(c + Vector3(0, 0.4, 0), rr * 0.7)
	# Boardwalk between the pools to the bathhouse.
	var bw: Array[Vector3] = [Vector3(-12.0, 0, -6.0), Vector3(-6.0, 0, -3.0), Vector3(1.0, 0, 0.5), Vector3(8.5, 0, 3.5)]
	for i: int in bw.size() - 1:
		var p0: Vector3 = bw[i]
		var p1: Vector3 = bw[i + 1]
		var n: int = int(p0.distance_to(p1) / 0.45)
		var yaw: float = atan2(p1.x - p0.x, p1.z - p0.z)
		for k: int in n:
			var p: Vector3 = p0.lerp(p1, (k + 0.5) / n)
			p.y = maxf(ground_y(p.x, p.z), 0.0) + 0.35
			SeasKit.box(a, p, Basis(Vector3.UP, yaw), Vector3.ZERO, Vector3(1.6, 0.1, 0.38), TideProps.m(self, "timber" if k % 4 else "timber2"), Vector3(0, 0, _rng.randf_range(-2, 2)), 0.03)
			if k % 5 == 0:
				for sd: float in [-0.7, 0.7]:
					SeasKit.pipe(a, p, Basis(Vector3.UP, yaw), Vector3(sd, -0.8, 0), Vector3(sd, -0.05, 0), 0.08, TideProps.m(self, "timber2"), 6)
	_cabin(a, grn, fut, Vector3(-14.0, 0, -9.0), 0.5, Vector3(5.5, 2.6, 3.6), "red")
	# Geothermal wellhead and its insulated pipe to the pools.
	var wh := Vector3(10.0, 0, -9.0)
	wh.y = ground_y(wh.x, wh.z)
	SeasKit.box(a, wh, Basis(), Vector3(0, 0.4, 0), Vector3(2.2, 0.8, 2.2), TideProps.m(self, "concrete"))
	SeasKit.flanged_pipe(a, wh, Basis(), Vector3(0, 0.8, 0), Vector3(0, 2.6, 0), 0.32, TideProps.m(self, "red"), TideProps.m(self, "steel"), 0.9)
	SeasKit.pipe(a, wh, Basis(), Vector3(-0.6, 2.2, 0), Vector3(0.6, 2.2, 0), 0.22, TideProps.m(self, "red"), 10)
	SeasKit.pipe(a, wh, Basis(), Vector3(0, 2.6, 0), Vector3(0, 2.75, 0), 0.5, TideProps.m(self, "ledger"), 14)
	var prev: Vector3 = wh + Vector3(-0.6, 0.8, 0)
	for k: int in 6:
		var t: float = (k + 1) / 6.0
		var q: Vector3 = (wh + Vector3(-0.6, 0, 0)).lerp(pools[1] + Vector3(3.2, 0, 0), t)
		q.y = ground_y(q.x, q.z) + 0.55
		SeasKit.pipe(a, Vector3.ZERO, Basis(), prev, q, 0.2, TideProps.m(self, "cream"), 10)
		SeasKit.box(a, q + Vector3(0, -0.3, 0), Basis(), Vector3.ZERO, Vector3(0.3, 0.6, 0.6), TideProps.m(self, "steel"), Vector3.ZERO, 0.04)
		prev = q
	_steam_at(wh + Vector3(0, 3.0, 0), 0.4)
	# Ruin: frozen junk at the pool rims; restored: moss tufts and lanterns on posts.
	var heap: Array[Transform3D] = []
	for k: int in 24:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(3.0, 18.0)
		var p := Vector3(cos(ang) * d, 0, sin(ang) * d)
		p.y = ground_y(p.x, p.z) - 0.1
		heap.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	_scatter_models(["Barrel_01", "old_tyre", "trashbag", "metal_jerrycan", "plastic_bottle_gallon"], heap, _groups["ruin"], 200.0)
	for k: int in 6:
		var p: Vector3 = bw[0].lerp(bw[bw.size() - 1], (k + 0.5) / 6.0) + Vector3(0, 0, 1.2)
		p.y = ground_y(p.x, p.z)
		SeasKit.pipe(a, p, Basis(), Vector3.ZERO, Vector3(0, 1.6, 0), 0.06, TideProps.m(self, "timber2"), 6)
		SeasKit.box(a, p, Basis(), Vector3(0, 1.75, 0), Vector3(0.32, 0.4, 0.32), TideProps.m(self, "steel"), Vector3(0, 45, 0), 0.05)
		SeasKit.box(grn, p, Basis(), Vector3(0, 1.75, 0), Vector3(0.24, 0.32, 0.36), TideProps.m(self, "lamp_warm"), Vector3(0, 45, 0), 0.03)
	a.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	grn.flush(_groups["green"])
	fut.flush(_groups["future"])
	SeasKit.solid_box(_groups["always"], wh, Basis(), Vector3(0, 1.3, 0), Vector3(2.2, 2.6, 2.2))


func _on_deck(p: Vector3) -> bool:
	for d: Vector3 in _decks:
		if Vector2(p.x - d.x, p.z - d.y).length() < d.z + 1.2:
			return true
	return false
