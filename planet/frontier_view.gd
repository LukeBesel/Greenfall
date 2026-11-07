class_name FrontierView
extends Node3D
## Visuals for a frontier district (planet/frontier_district.gd owns the state). Each kind has
## its own landmarks around the field, staged with the base level like StreetDressing:
##   ruin (base 1) -> mid (2-3, salvaged and painted) -> future (4-5, white shells, thin light lines)
##   Dust Flats     dunes, a ship half-buried in sand, wrecked cars, a solar farm (dusty and
##                  toppled -> clean rows -> tracking panels with thin edge lights, wind turbines)
##   Frozen Port    the frozen harbour (sea ice -> open water), a quay, ship-to-shore cranes and
##                  container stacks; per-hex ice slabs, heaters and greenhouses in the field
##   Sunken City    the flood beyond the field, a half-sunk ship and buoys, pump houses; the whole
##                  city sits lower while flooded and rises as the pumps drain it
##   Cradle Returns a ring of white towers with green terraces (kept by ground crews), launch
##                  gantries, the landing pad's light ring and pylons, and the ark in the sky
## Static geometry is merged per material (Batch) so each layer is a handful of draw calls.
## [biomes2] Each kind also gets a heightfield terrain from the field edge to the horizon
## (art/shaders/terrain.gdshader: dunes, snowfields and mountains, drowned headlands, lawns and
## hills); the FieldView ground stops at its inner edge. Props beyond the edge sit on it (_gy).

const CYAN := Color(0.62, 0.9, 1.0)
const WARM := Color(1.0, 0.62, 0.3)

var district: FrontierDistrict
var world: Node
var field: HexField
var kid: String = ""
var level: int = 1
var restore: float = 0.0

var _groups: Dictionary = {}       # name -> Node3D
var _mats: Dictionary = {}
var _ice_img: Image               # per hex: R ice 0..1, G water (ice_slab.gdshader)
var _ice_tex: ImageTexture
var _ice_dirty: bool = false
var _heaters: Dictionary = {}      # hex id -> Node3D
var _greenhouses: Dictionary = {}  # hex id -> Node3D
var _storm: CPUParticles3D
var _storm_amt: float = 0.0
var _flood: MeshInstance3D
var _flood_mat: ShaderMaterial
var _sink: float = 0.0
var _rotors: Array[Node3D] = []
var _pad_mat: StandardMaterial3D
var _pylon_lamps: Array[MeshInstance3D] = []
var _beams: Node3D
var _ark: Node3D
var _ark_y: float = 620.0
var _cradle: Dictionary = {}
var _pumps_fx: Array[Vector3] = []
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
# [biomes2] Terrain
var _r_in: float = 0.0
var _quay_x: float = 99999.0
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()
var _terrain_mat: ShaderMaterial
var _farm_c := Vector2(99999, 99999)
var _farm_yaw: float = 0.0
var _farm_half := Vector2(95.0, 60.0)
var _snow: CPUParticles3D


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

	func flush(parent: Node3D, shadows: bool = true) -> void:
		for key: int in sts:
			var st: SurfaceTool = sts[key][0]
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = sts[key][1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
		sts.clear()


func build() -> void:
	world = district.world
	field = world.field
	kid = district.kid
	_rng.seed = field.seed_value + 5150
	level = int(world.hub.level) if world.get("hub") != null else 1
	_r_in = _edge() + 2.0
	_open_camera()
	_quay_x = _edge() - 4.0 if kid == "frozen_port" else 99999.0
	for k: int in 3:
		var nz: FastNoiseLite = [_n1, _n2, _n3][k]
		nz.seed = field.seed_value + 71 * (k + 1)
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.fractal_type = FastNoiseLite.FRACTAL_FBM
		nz.fractal_octaves = 3
		nz.frequency = [0.004, 0.011, 0.0022][k]
	for g: String in ["always", "ruin", "mid", "up", "future"]:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	match kid:
		"dust_flats":
			_build_desert()
		"frozen_port":
			_build_port()
		"sunken_city":
			_build_sunken()
		"cradle_returns":
			_build_cradle()
	_setup_field_water()
	_weather_junk()
	set_level(level, false)
	var counts: Array[String] = []
	for g: String in _groups:
		counts.append("%s=%d" % [g, (_groups[g] as Node).find_children("*", "MeshInstance3D", true, false).size()])
	print("[frontier] view %s level %d: %s" % [kid, level, " ".join(counts)])
	if world.get("hub") != null:
		world.hub.level_changed.connect(func(l: int) -> void: set_level(l, true))


## Shows the layers for a base level. Live: new layers rise in with sparkles.
func set_level(l: int, animate: bool) -> void:
	level = clampi(l, 1, 5)
	var ranges: Dictionary = {"always": Vector2i(1, 5), "ruin": Vector2i(1, 1), "mid": Vector2i(2, 3), "up": Vector2i(2, 5), "future": Vector2i(4, 5)}
	for g: String in _groups:
		var node: Node3D = _groups[g]
		var r: Vector2i = ranges[g]
		var want: bool = level >= r.x and level <= r.y
		if want and not node.visible and animate:
			node.scale = Vector3(1, 0.02, 1)
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		node.visible = want
	# The harbour's water hexes stay sea ice until the port is futuristic (like the flood plane).
	var wm: ShaderMaterial = _water_mat()
	if wm and kid == "frozen_port":
		wm.set_shader_parameter("frozen", 1.0 if level < 4 else 0.0)


func set_restore(r: float) -> void:
	restore = r
	if _terrain_mat:
		_terrain_mat.set_shader_parameter("restore", r)


func _process(delta: float) -> void:
	_t += delta
	if _ice_dirty:
		_ice_dirty = false
		_ice_tex.update(_ice_img)
	for r: Node3D in _rotors:
		if is_instance_valid(r) and r.is_visible_in_tree():
			r.rotate_object_local(Vector3.FORWARD, delta * 0.9)
	if _storm:
		var p: Node3D = world.get("patch")
		if p:
			_storm.global_position = p.global_position + Vector3(-18.0, 3.0, 0.0)
		_storm.emitting = _storm_amt > 0.08
	if _snow:
		var pp: Node3D = world.get("patch")
		if pp:
			_snow.global_position = pp.global_position + Vector3(0, 16.0, 0)
		_snow.emitting = level < 4
	for hid: int in _heaters:
		var hn: Node3D = _heaters[hid]
		if is_instance_valid(hn):
			var coil: MeshInstance3D = hn.get_meta("coil")
			(coil.material_override as StandardMaterial3D).emission_energy_multiplier = 2.2 + sin(_t * 3.0 + hid) * 0.6
			if fmod(_t + hid * 0.37, 1.8) < delta:
				Vfx.burst("steam", hn.global_position + Vector3(0, 1.4, 0), Color(0.95, 0.96, 1.0, 0.5), 0.35)
	if _ark:
		var want: float = lerpf(620.0, 240.0, clampf(float(_cradle.get("pad_level", 0.0)) * 0.5 + float(_cradle.get("district", 0.0)) * 0.5, 0.0, 1.0))
		if district.done:
			want = 150.0
		_ark_y = lerpf(_ark_y, want, clampf(delta * 0.05, 0.0, 1.0))
		_ark.position.y = _ark_y + sin(_t * 0.2) * 2.0
		_ark.rotation.y = sin(_t * 0.03) * 0.04
	if _pad_mat:
		var pc: float = float(_cradle.get("pad_clean", 0.0))
		_pad_mat.emission_energy_multiplier = 0.4 + pc * 2.6 + (sin(_t * 2.0) * 0.4 if district.done else 0.0)


# --- Materials ----------------------------------------------------------------------------

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"white":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.9, 0.91, 0.93)
			w.roughness = 0.26
			w.metallic = 0.05
			w.clearcoat_enabled = true
			w.clearcoat = 0.5
			m = w
		"glass_dark":
			m = Mats.glass(Color(0.04, 0.06, 0.09, 0.92), 0.06)
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.82, 0.92, 0.95, 0.18)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.04
			g.metallic = 0.1
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g
		"line":
			var l := StandardMaterial3D.new()
			l.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			l.albedo_color = CYAN
			l.emission_enabled = true
			l.emission = CYAN
			l.emission_energy_multiplier = 1.0
			m = l
		"line_soft":
			# [biomes2] A faint seam of light (the Cradle's towers and apron): visible, never neon.
			var ls := StandardMaterial3D.new()
			ls.albedo_color = Color(0.86, 0.95, 1.0)
			ls.emission_enabled = true
			ls.emission = Color(0.7, 0.9, 1.0)
			ls.emission_energy_multiplier = 0.55
			ls.roughness = 0.3
			m = ls
		"tower_glass":
			# Opaque dark curtain-wall glass that mirrors the sky.
			var tg := StandardMaterial3D.new()
			tg.albedo_color = Color(0.3, 0.4, 0.48)
			tg.metallic = 0.6
			tg.roughness = 0.12
			tg.metallic_specular = 0.7
			m = tg
		"warm":
			m = Mats.lamp(WARM, 2.0)
		"steel":
			m = Mats.metal("steel")
		"dark":
			m = Mats.metal("dark_steel")
		"sand":
			m = AssetLib.pbr_material("sand_01", 0.08, Color(1.0, 0.93, 0.8), true)
		"concrete":
			m = AssetLib.pbr_material("concrete_wall_008", 0.18, Color(0.78, 0.78, 0.76), true)
		"panel":
			var p := StandardMaterial3D.new()
			p.albedo_color = Color(0.05, 0.08, 0.17)
			p.metallic = 0.55
			p.roughness = 0.1
			m = p
		"panel_dusty":
			var pd := StandardMaterial3D.new()
			pd.albedo_color = Color(0.46, 0.41, 0.34)
			pd.albedo_texture = AssetLib.tex("sand_01", "diff")
			pd.uv1_triplanar = true
			pd.uv1_scale = Vector3.ONE * 0.6
			pd.roughness = 0.85
			m = pd
		"alu":
			var a := StandardMaterial3D.new()
			a.albedo_color = Color(0.72, 0.73, 0.75)
			a.metallic = 0.8
			a.roughness = 0.35
			m = a
		"snow":
			m = AssetLib.pbr_material("snow_02", 0.3, Color(1, 1, 1), true)
		"ice":
			var i := ShaderMaterial.new()
			i.shader = preload("res://art/shaders/ice_slab.gdshader")
			m = i
		"green":
			var gr := StandardMaterial3D.new()
			gr.albedo_color = Color(0.22, 0.42, 0.2)
			gr.albedo_texture = AssetLib.tex("leafy_grass", "diff")
			gr.uv1_triplanar = true
			gr.uv1_scale = Vector3.ONE * 0.5
			gr.roughness = 0.9
			m = gr
		_:
			m = StandardMaterial3D.new()
	_mats[key] = m
	return m


func _paint(col: Color, coverage: float, rust: float, seed_v: float = 0.0) -> Material:
	var key: String = "paint_%s_%.2f_%.2f_%d" % [col.to_html(false), coverage, rust, int(seed_v)]
	if not _mats.has(key):
		_mats[key] = Mats.worn_paint(col, coverage, rust, seed_v, 0.5)
	return _mats[key]


func _corr(col: Color) -> Material:
	var key: String = "corr_" + col.to_html(false)
	if not _mats.has(key):
		_mats[key] = AssetLib.pbr_material("corrugated_iron", 0.35, col, true)
	return _mats[key]


# --- Geometry helpers -----------------------------------------------------------------------

static func _xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return ProcMesh.xf(pos, rot_deg, scl)


## A transform for a box `size` from a to b (thin beams, struts, cables).
static func _beam_xf(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var d: Vector3 = b - a
	var len_: float = d.length()
	var y: Vector3 = d / maxf(len_, 0.0001)
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * thick, y * len_, z * thick), (a + b) * 0.5)


var _unit_box: BoxMesh


func _box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = ProcMesh.box(Vector3.ONE)
	return _unit_box


func _add_box(b: Batch, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	# [biomes2] Scale in the box's own axes (Basis.scaled() is a parent-space scale and skews
	# rotated boxes).
	b.add(_box(), Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(size), pos), mat)


func _add_beam(b: Batch, a: Vector3, c: Vector3, thick: float, mat: Material) -> void:
	b.add(_box(), _beam_xf(a, c, thick), mat)


func _model(id: String, pos: Vector3, yaw: float, scl: float = 1.0, parent: Node3D = null, tilt: Vector3 = Vector3.ZERO, overlay: Material = null) -> MeshInstance3D:
	if not AssetLib.has_model(id):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh(id) if id == "dutch_ship_medium" else AssetLib.model_mesh_lite(id, 6000)  # the ship loses its rigging when decimated
	mi.transform = Transform3D((Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)) * Basis.from_scale(Vector3.ONE * scl)), pos)
	if overlay:
		mi.material_overlay = overlay
	(parent if parent else _groups["always"]).add_child(mi)
	return mi


func _edge() -> float:
	return field.hex_size * (float(field.radius) + 0.55) * Hex.SQRT3


## A point at angle (radians, 0 = +x, -PI/2 = -z, the default view) and distance from the base.
static func _polar(ang: float, dist: float, y: float = 0.0) -> Vector3:
	return Vector3(cos(ang) * dist, y, sin(ang) * dist)


func _flood_plane(ice: float, half_x: float, y: float) -> MeshInstance3D:
	_flood_mat = ShaderMaterial.new()
	_flood_mat.shader = preload("res://art/shaders/flood.gdshader")
	_flood_mat.set_shader_parameter("grid_radius", field.radius)
	_flood_mat.set_shader_parameter("hex_size", field.hex_size)
	_flood_mat.set_shader_parameter("wave_nrm", AssetLib.tex("rubble", "nor_gl"))
	_flood_mat.set_shader_parameter("ice_nrm", AssetLib.tex("snow_02", "nor_gl"))
	_flood_mat.set_shader_parameter("ice", ice)
	_flood_mat.set_shader_parameter("half_plane_x", half_x)
	_flood_mat.set_shader_parameter("fade_far", 650.0)
	_share_warp(_flood_mat)
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.material = _flood_mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Frontiers are wide open: see the terrain to the horizon, and keep the far blur for the far
## distance (the default 55 m lens blur makes a landscape look like a miniature).
func _open_camera() -> void:
	var rig: Node = world.get("cam")
	var cam: Camera3D = rig.get("camera") if rig else null
	if cam == null:
		return
	cam.far = 2200.0
	var attrs: CameraAttributesPractical = cam.attributes as CameraAttributesPractical
	if attrs:
		attrs.dof_blur_far_distance = 260.0
		attrs.dof_blur_far_transition = 400.0
		attrs.dof_blur_amount = 0.03


# --- Terrain (biomes2) -----------------------------------------------------------------------

## Terrain height at world x, z (beyond the field; 0 or a little below at its inner edge).
func _terrain_h(x: float, z: float) -> float:
	var r: float = sqrt(x * x + z * z)
	var t: float = r - _r_in
	var h: float = 0.0
	match kid:
		"dust_flats":
			h = _dune_h(x, z, t)
		"frozen_port":
			h = _snow_h(x, z, t)
		"sunken_city":
			h = _drowned_h(x, z, t)
		"cradle_returns":
			h = _plain_h(x, z, t)
	# Under the field ground's wandering edge (ground_pbr clip_r) the terrain tucks a little lower
	# so the two never z-fight.
	if t < 0.0:
		h = minf(h, -0.04 - 0.3 * _smooth(0.0, 8.0, -t))
	return h


## Ground height for props: the terrain beyond the field edge, 0 on the field.
func _gy(p: Vector3) -> float:
	if Vector2(p.x, p.z).length() < _r_in + 3.0:
		return 0.0
	return maxf(_terrain_h(p.x, p.z), -0.04)


static func _smooth(a: float, b: float, x: float) -> float:
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 0..1 inside the (soft-edged) flat pad the far solar farm stands on.
func _farm_mask(x: float, z: float) -> float:
	var d := Vector2(x, z) - _farm_c
	var l: Vector2 = d.rotated(-_farm_yaw)
	var ex: float = absf(l.x) - _farm_half.x
	var ez: float = absf(l.y) - _farm_half.y
	return 1.0 - _smooth(0.0, 35.0, maxf(ex, ez))


## Transverse dunes: long crests across the wind with a gentle windward slope and a steep lee
## face, crest heights varying along their length, big draa swells further out, and a flat
## crusted pan where the solar farm stands.
func _dune_h(x: float, z: float, t: float) -> float:
	var ramp: float = _smooth(5.0, 70.0, t)
	if ramp <= 0.0:
		return -0.04
	var warp: float = _n1.get_noise_2d(x, z) * 70.0
	var u: float = (x * 0.83 + z * 0.56 + warp) / 68.0
	var f: float = u - floorf(u)
	var prof: float = _smooth(0.0, 0.78, f) if f < 0.78 else 1.0 - _smooth(0.78, 1.0, f) * 0.92
	prof = prof * prof * (1.4 - 0.4 * prof)
	var along: float = 0.45 + 0.55 * (_n2.get_noise_2d(x * 0.7, z * 0.7) * 0.5 + 0.5)
	var amp: float = lerpf(4.0, 24.0, clampf(t / 300.0, 0.0, 1.0)) * along
	var draa: float = (_n3.get_noise_2d(x, z) * 0.5 + 0.5) * 34.0 * _smooth(60.0, 420.0, t)
	var h: float = 0.6 + prof * amp + draa
	h = lerpf(h, 0.35 + draa * 0.3, _farm_mask(x, z))
	return lerpf(-0.04, h, ramp)


## Snowfields: low drifts near the port, rolling white hills inland (west), and ridged mountains
## on the horizon all round; the harbour side (east of the quay) drops under the sea ice.
func _snow_h(x: float, z: float, t: float) -> float:
	var ramp: float = _smooth(10.0, 110.0, t)
	var hills: float = (_n1.get_noise_2d(x, z) * 0.5 + 0.5) * lerpf(1.5, 26.0, clampf(t / 420.0, 0.0, 1.0))
	var drift: float = (_n2.get_noise_2d(x, z) * 0.5 + 0.5) * 1.6
	var ridge: float = 1.0 - absf(_n3.get_noise_2d(x * 1.3, z * 1.3))
	var mount: float = pow(ridge, 3.0) * 120.0 * _smooth(330.0, 620.0, t)
	var land_h: float = 0.4 + drift + hills * ramp + mount
	var land: float = 1.0 - _smooth(_quay_x - 6.0, _quay_x + 2.0, x)
	var sea_h: float = -3.0 + mount * _smooth(420.0, 700.0, t) * 1.1
	var h: float = lerpf(sea_h, land_h, land)
	return lerpf(-0.04, h, _smooth(2.0, 14.0, t))


## The Sunken City sits in a drowned bay: seabed under the flood, misty headlands far out.
func _drowned_h(x: float, z: float, t: float) -> float:
	var isl: float = _smooth(0.05, 0.55, _n1.get_noise_2d(x * 0.8, z * 0.8)) * _smooth(330.0, 560.0, t)
	var hill: float = (_n2.get_noise_2d(x, z) * 0.5 + 0.5) * 40.0 + 12.0
	# The old sea wall: past the field ground's wandering edge the bed drops away, along a line
	# that wanders too (seen once the pumps have lowered the water).
	var wall: float = 15.0 + (_n2.get_noise_2d(x * 1.7, z * 1.7) + 1.0) * 5.0
	return lerpf(lerpf(-0.04, -6.0, _smooth(wall, wall + 6.0, t)), hill, isl)


## The Cradle's plain: a flat paved apron, then mown lawns with low rolls and green hills far out.
func _plain_h(x: float, z: float, t: float) -> float:
	var roll: float = (_n2.get_noise_2d(x, z) * 0.5 + 0.5) * 3.0 * _smooth(60.0, 260.0, t)
	var hills: float = pow(_n1.get_noise_2d(x, z) * 0.5 + 0.5, 1.6) * 70.0 * _smooth(330.0, 650.0, t)
	return -0.04 + roll + hills


## Builds the heightfield ring from the field edge to the horizon, in sectors for culling.
func _build_terrain(look: Dictionary) -> void:
	var r_out: float = 1300.0
	var nr: int = 96
	var na: int = 320
	var sectors: int = 8
	var rs := PackedFloat32Array()
	for i: int in nr:
		var f: float = float(i) / float(nr - 1)
		rs.append(_r_in - 9.0 + (r_out - _r_in + 9.0) * pow(f, 2.1))
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = preload("res://art/shaders/terrain.gdshader")
	var a_id: String = str(look.get("a", "sand_01"))
	var b_id: String = str(look.get("b", a_id))
	_terrain_mat.set_shader_parameter("tex_a", AssetLib.tex(a_id, "diff"))
	_terrain_mat.set_shader_parameter("nrm_a", AssetLib.tex(a_id, "nor_gl"))
	_terrain_mat.set_shader_parameter("tex_b", AssetLib.tex(b_id, "diff"))
	_terrain_mat.set_shader_parameter("nrm_b", AssetLib.tex(b_id, "nor_gl"))
	_terrain_mat.set_shader_parameter("tex_g", AssetLib.tex("leafy_grass", "diff"))
	for k: String in look:
		if k in ["a", "b"]:
			continue
		var v: Variant = look[k]
		_terrain_mat.set_shader_parameter(k, Vector3(v.r, v.g, v.b) if v is Color else v)
	_terrain_mat.set_shader_parameter("restore", restore)
	var gt: Array = field.biome_set.get("ground_tint", [])
	if gt.size() >= 4 and not look.has("biome_tint"):
		_terrain_mat.set_shader_parameter("biome_tint", Vector4(float(gt[0]), float(gt[1]), float(gt[2]), float(gt[3])))
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
				st.add_vertex(Vector3(x, _terrain_h(x, z), z))
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
		mi.material_override = _terrain_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
	var gm: ShaderMaterial = world.view.ground_material if world.get("view") != null else null
	if gm:
		# The Cradle's paved apron (to _r_in + 30) hides the ground's wandering edge under it.
		gm.set_shader_parameter("clip_r", _r_in + (14.0 if kid == "cradle_returns" else 3.0))


## A low wind-blown sand drift against a wreck (terrain material, so it melts into the dunes).
func _drift(b: Batch, p: Vector3, yaw: float, w: float, h: float) -> void:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 1.0
	m.is_hemisphere = true
	m.radial_segments = 20
	m.rings = 6
	b.add(m, Transform3D((Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, h, w * 0.55))), p + Vector3(0, -h * 0.25, 0)), _terrain_mat)


# --- Dust Flats ------------------------------------------------------------------------------

func _build_desert() -> void:
	var e: float = _edge()
	# The big solar farm stands on a flat crusted pan to the north-west, in full view.
	_farm_yaw = 0.35
	var fc: Vector3 = _polar(-2.05, _r_in + 175.0)
	_farm_c = Vector2(fc.x, fc.z)
	_build_terrain({"a": "sand_01", "b": "mud_cracked_dry_03", "tint_a": Color(1.0, 0.95, 0.88), "tint_b": Color(0.95, 0.9, 0.84),
		"scale_a": 0.16, "scale_b": 0.07, "rough_a": 0.92, "rough_b": 0.95, "low_y": 1.1, "low_soft": 0.6,
		"ripple": 1.0, "green_amt": 0.4, "tint_g": Color(0.62, 0.68, 0.36), "macro": 0.14})
	var always := Batch.new()
	var coat: Material = _coat(Color(0.9, 0.74, 0.5, 0.55))
	# A trading ship, half-buried in the sand, listing hard. The flats were a sea once.
	var sp: Vector3 = _polar(-1.95, e + 16.0)
	sp.y = _gy(sp) - 2.2
	var ship: MeshInstance3D = _model("dutch_ship_medium", sp, 0.9, 1.0, null, Vector3(0.0, 0, 0.22), coat)
	if ship:
		ship.rotation = Vector3(0.05, 0.9, 0.24)
		_drift(always, sp + Vector3(0, 1.2, 0), 0.9, 26.0, 3.2)
		_drift(always, sp + Vector3(4.0, 1.0, 6.0), 0.5, 14.0, 2.6)
	# Cars and drums buried to the windows near the edge and out on the dunes, each with its
	# drift piled on the windward side; quiver trunks and rocks.
	for i: int in 14:
		var p: Vector3 = _polar(_rng.randf() * TAU, e + _rng.randf_range(4.0, 70.0))
		p.y = _gy(p) - _rng.randf_range(0.45, 0.8)
		var yaw: float = _rng.randf() * TAU
		_model("covered_car", p, yaw, 1.0, null, Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.2, 0.2)), coat)
		_drift(always, p + Vector3(-1.2, 0.3, -0.8), 0.6, _rng.randf_range(3.5, 5.0), _rng.randf_range(0.9, 1.4))
	for i: int in 10:
		var q_: Vector3 = _polar(_rng.randf() * TAU, e + _rng.randf_range(4.0, 60.0))
		q_.y = _gy(q_)
		_model("dead_quiver_trunk", q_, _rng.randf() * TAU, _rng.randf_range(1.6, 2.6))
	for i: int in 12:
		var q2: Vector3 = _polar(_rng.randf() * TAU, e + _rng.randf_range(2.0, 40.0))
		q2.y = _gy(q2) - 0.3
		_model("namaqualand_rocks_01", q2, _rng.randf() * TAU, _rng.randf_range(2.0, 4.0))
	always.flush(_groups["always"])
	_desert_wrecks(e)
	# The solar farm: two small blocks by the field edge and the big array on the pan.
	for f: Array in [[-1.55, e + 10.0], [2.6, e + 14.0]]:
		_solar_farm(_polar(float(f[0]), float(f[1])), float(f[0]) + PI * 0.5)
	_big_solar(fc, _farm_yaw)
	# A dead power line marching off over the dunes toward the farm.
	_power_line(_polar(-1.2, e + 8.0), fc + Vector3(60.0, 0, 70.0), 7)
	# Futuristic: tall white wind turbines on the far dunes.
	for a: float in [-1.4, -0.95, -0.55, 2.2, 2.7]:
		var tp: Vector3 = _polar(a, e + 150.0 + _rng.randf_range(-20.0, 40.0))
		tp.y = _gy(tp)
		_turbine(tp)
	# Sandstorm particles (follow Lumi, blow from the west).
	_storm = CPUParticles3D.new()
	_storm.amount = 700
	_storm.lifetime = 3.2
	_storm.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_storm.emission_box_extents = Vector3(4.0, 5.0, 40.0)
	_storm.direction = Vector3(1, 0.05, 0.15)
	_storm.spread = 12.0
	_storm.gravity = Vector3.ZERO
	_storm.initial_velocity_min = 10.0
	_storm.initial_velocity_max = 16.0
	_storm.scale_amount_min = 1.5
	_storm.scale_amount_max = 4.0
	_storm.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.6)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = _soft_dot()
	q.material = sm
	_storm.mesh = q
	_storm.color = Color(0.82, 0.66, 0.45, 0.22)
	_storm.emitting = false
	add_child(_storm)


## Big wrecks the dunes are swallowing: rusted shipping containers buried at angles, a tanker
## truck sunk to its axles, and a toppled water tower. Sand drifts bank up on their windward sides.
func _desert_wrecks(e: float) -> void:
	var b := Batch.new()
	var rust: Material = AssetLib.pbr_material("rusty_metal_02", 0.25, Color(0.86, 0.72, 0.6), true)
	var rust2: Material = AssetLib.pbr_material("rusty_painted_metal", 0.3, Color(0.85, 0.8, 0.72), true)
	var cols: Array[Color] = [Color(0.62, 0.36, 0.26), Color(0.5, 0.46, 0.38), Color(0.36, 0.42, 0.44), Color(0.66, 0.54, 0.36)]
	for i: int in 7:
		var ang: float = -2.4 + i * 0.62 + _rng.randf_range(-0.15, 0.15)
		var p: Vector3 = _polar(ang, e + _rng.randf_range(22.0, 85.0))
		var yaw: float = _rng.randf() * TAU
		var sink: float = _rng.randf_range(0.6, 1.5)
		var tilt := Vector3(_rng.randf_range(-9.0, 9.0), rad_to_deg(yaw), _rng.randf_range(-14.0, 14.0))
		p.y = _gy(p) + 1.3 - sink
		_add_box(b, p, Vector3(12.2, 2.6, 2.44), _corr(cols[i % cols.size()].darkened(0.15)), tilt)
		if i % 3 == 0:  # a second box tipped against the first
			_add_box(b, p + Basis.from_euler(tilt * (PI / 180.0)) * Vector3(2.0, 2.2, 0.4), Vector3(6.06, 2.6, 2.44), _corr(cols[(i + 1) % cols.size()].darkened(0.2)), tilt + Vector3(0, 35.0, 18.0))
		_drift(b, p + Vector3(-2.5, -0.6, -1.0), yaw + 0.3, 9.0, 1.8)
	# Tanker truck, sunk to the axles, nose down into a dune.
	var tp: Vector3 = _polar(-0.35, e + 32.0)
	tp.y = _gy(tp) - 0.5
	var tb := Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, 0.06)
	b.add(ProcMesh.cyl(1.25, 1.25, 9.0, 20), Transform3D(tb * Basis(Vector3.FORWARD, PI * 0.5), tp + tb * Vector3(-1.5, 1.9, 0)), rust2)
	_add_box(b, tp + tb * Vector3(4.6, 1.5, 0), Vector3(2.4, 2.6, 2.5), rust, Vector3(3.4, 40.1, 0))
	_add_box(b, tp + tb * Vector3(0.5, 0.55, 0), Vector3(12.0, 0.4, 1.4), _mat("dark"))
	for k: int in 3:
		for sd: float in [-1.15, 1.15]:
			b.add(ProcMesh.torus(0.3, 0.55, 14, 8), Transform3D(tb * Basis(Vector3.RIGHT, PI * 0.5), tp + tb * Vector3(-4.5 + k * 3.8, 0.4, sd)), _mat("dark"))
	_drift(b, tp + Vector3(1.0, -0.2, 2.0), 0.7, 12.0, 1.6)
	# A water tower that fell over long ago: the tank on its side, legs sticking out of the sand.
	var wp: Vector3 = _polar(2.2, e + 60.0)
	wp.y = _gy(wp)
	b.add(ProcMesh.cyl(4.0, 4.0, 7.0, 24), Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, PI * 0.5 - 0.1), wp + Vector3(0, 2.6, 0)), rust2)
	for k: int in 4:
		var a: float = 0.4 + k * 0.5
		var base: Vector3 = wp + Vector3(cos(0.4), 0, -sin(0.4)) * 5.0 + Vector3(0, 0.2, 0) + Vector3(-sin(0.4), 0, -cos(0.4)) * (k - 1.5) * 1.6
		_add_beam(b, base, base + Vector3(cos(a) * 13.0, 2.5 + k * 0.6, -sin(a) * 13.0), 0.35, rust)
	_drift(b, wp + Vector3(-3.0, 0.0, 1.0), 0.4, 11.0, 2.4)
	b.flush(_groups["always"])


func _soft_dot() -> GradientTexture2D:
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


func _coat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	return m


func _solar_farm(c: Vector3, yaw: float) -> void:
	var ruin := Batch.new()
	var up := Batch.new()
	var fut := Batch.new()
	var basis_ := Basis(Vector3.UP, yaw)
	var rows: int = 4
	var cols: int = 9
	var pw: float = 2.0
	var ph: float = 1.2
	for r: int in rows:
		for k: int in cols:
			var local := Vector3((k - cols * 0.5) * (pw + 0.25), 0, (r - rows * 0.5) * 4.2)
			var p: Vector3 = c + basis_ * local
			# Restored: posts, a tilted panel in an aluminium frame, facing south (+z after yaw).
			var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-28.0))
			_add_box(up, p + Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), _mat("alu"))
			up.add(_box(), Transform3D((tilt * Basis.from_scale(Vector3(pw, 0.05, ph))), p + Vector3(0, 1.15, 0)), _mat("panel"))
			up.add(_box(), Transform3D((tilt * Basis.from_scale(Vector3(pw + 0.06, 0.035, ph + 0.06))), p + Vector3(0, 1.13, 0)), _mat("alu"))
			# Future: one thin light line along the top edge of every panel.
			var top: Vector3 = p + Vector3(0, 1.15, 0) + tilt * Vector3(0, 0.03, -ph * 0.5)
			fut.add(_box(), Transform3D((Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(pw, 0.025, 0.025))), top), _mat("line"))
			# Ruin: some panels gone, the rest dusty, cracked off their posts at odd angles.
			if _rng.randf() < 0.22:
				continue
			var fallen: bool = _rng.randf() < 0.35
			var rt := Basis(Vector3.UP, yaw + _rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-70.0, -5.0) if not fallen else _rng.randf_range(-8.0, 8.0))) * Basis(Vector3.FORWARD, _rng.randf_range(-0.25, 0.25))
			var y: float = 1.1 if not fallen else 0.12
			_add_box(ruin, p + Vector3(0, 0.45, 0), Vector3(0.08, 0.9 * _rng.randf_range(0.5, 1.0), 0.08), _mat("alu"), Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12)))
			ruin.add(_box(), Transform3D((rt * Basis.from_scale(Vector3(pw, 0.05, ph))), p + Vector3(0, y, 0)), _mat("panel_dusty"))
	# Inverter cabinets at the row ends.
	for r: int in rows:
		var p2: Vector3 = c + basis_ * Vector3(-(cols * 0.5 + 1.2) * (pw + 0.25), 0, (r - rows * 0.5) * 4.2)
		_add_box(up, p2 + Vector3(0, 0.7, 0), Vector3(0.9, 1.4, 0.6), _mat("white"))
		_add_box(fut, p2 + Vector3(0, 1.0, 0.31), Vector3(0.5, 0.03, 0.01), _mat("line"))
		_add_box(ruin, p2 + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.6), _paint(Color(0.7, 0.68, 0.6), 0.4, 0.8), Vector3(0, 0, _rng.randf_range(-15, 15)))
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])
	fut.flush(_groups["future"], false)


## The big solar farm on the pan: rows of single-axis tracker tables. Ruin: dusty panels, many
## missing or slumped, sand drifted along the rows. Restored: clean dark glass in bright frames.
func _big_solar(c: Vector3, yaw: float) -> void:
	var ruin := Batch.new()
	var up := Batch.new()
	var basis_ := Basis(Vector3.UP, yaw)
	var tl: float = 9.0
	var tw: float = 3.0
	for r: int in 15:
		for k: int in 17:
			var local := Vector3((k - 8) * (tl + 1.0), 0, (r - 7) * 7.2)
			var p: Vector3 = c + basis_ * local
			p.y = _gy(p)
			var tilt := basis_ * Basis(Vector3.RIGHT, deg_to_rad(-24.0))
			_add_box(up, p + Vector3(0, 0.75, 0), Vector3(0.14, 1.5, 0.14), _mat("alu"))
			up.add(_box(), Transform3D((tilt * Basis.from_scale(Vector3(tl, 0.06, tw))), p + Vector3(0, 1.6, 0)), _mat("panel"))
			up.add(_box(), Transform3D((tilt * Basis.from_scale(Vector3(tl + 0.1, 0.04, tw + 0.1))), p + Vector3(0, 1.57, 0)), _mat("alu"))
			if _rng.randf() < 0.3:
				_add_box(ruin, p + Vector3(0, 0.6, 0), Vector3(0.14, 1.2, 0.14), _mat("alu"), Vector3(_rng.randf_range(-15, 15), 0, _rng.randf_range(-15, 15)))
				continue
			var slump: float = _rng.randf_range(-8.0, 8.0) if _rng.randf() < 0.7 else _rng.randf_range(-60.0, -35.0)
			var rt := Basis(Vector3.UP, yaw + _rng.randf_range(-0.08, 0.08)) * Basis(Vector3.RIGHT, deg_to_rad(-24.0 + slump)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.06, 0.06))
			_add_box(ruin, p + Vector3(0, 0.7, 0), Vector3(0.14, 1.4, 0.14), _mat("alu"))
			ruin.add(_box(), Transform3D((rt * Basis.from_scale(Vector3(tl, 0.06, tw))), p + Vector3(0, 1.5 + slump * 0.01, 0)), _mat("panel_dusty"))
		# A long sand drift along each row in the ruin.
		var rp: Vector3 = c + basis_ * Vector3(0, 0, (r - 7) * 7.2 + 1.6)
		rp.y = _gy(rp)
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 1.0
		m.is_hemisphere = true
		m.radial_segments = 16
		m.rings = 4
		ruin.add(m, Transform3D((basis_ * Basis.from_scale(Vector3(80.0 + _rng.randf_range(-10.0, 10.0), 0.7, 1.6))), rp - Vector3(0, 0.15, 0)), _terrain_mat)
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])


## A line of lattice pylons from a toward b: leaning and broken (ruin), upright with cables (up).
func _power_line(a: Vector3, b: Vector3, n: int) -> void:
	var ruin := Batch.new()
	var up := Batch.new()
	var rust: Material = _paint(Color(0.5, 0.38, 0.3), 0.2, 0.95, 21)
	var tops: Array[Vector3] = []
	var dir: Vector3 = (b - a).normalized()
	var yaw: float = atan2(dir.x, dir.z)
	for i: int in n:
		var p: Vector3 = a.lerp(b, float(i) / float(n - 1))
		p.y = _gy(p) - 0.6
		var h: float = 24.0
		for v: int in 2:
			var bt: Batch = [ruin, up][v]
			var m: Material = rust if v == 0 else _mat("steel")
			var lean := Basis()
			if v == 0:
				lean = Basis(Vector3.RIGHT, _rng.randf_range(-0.12, 0.12)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12))
				if i == 2:
					lean = Basis(Vector3.FORWARD, 1.35)
			var xf := Transform3D(Basis(Vector3.UP, yaw) * lean, p)
			var legs: Array[Vector3] = [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
			for k: int in 4:
				var l0: Vector3 = legs[k] * 3.0
				var l1: Vector3 = legs[k] * 0.7 + Vector3(0, h, 0)
				_add_beam(bt, xf * l0, xf * l1, 0.28, m)
				var n0: Vector3 = legs[(k + 1) % 4]
				for y: float in [0.25, 0.5, 0.75]:
					var pa: Vector3 = (legs[k] * lerpf(3.0, 0.7, y)) + Vector3(0, h * y, 0)
					var pb: Vector3 = (n0 * lerpf(3.0, 0.7, y + 0.25)) + Vector3(0, h * (y + 0.25), 0)
					_add_beam(bt, xf * pa, xf * pb, 0.12, m)
			for arm: float in [h * 0.78, h * 0.95]:
				_add_beam(bt, xf * Vector3(-5.5, arm, 0), xf * Vector3(5.5, arm, 0), 0.32, m)
			if v == 1:
				tops.append(xf * Vector3(5.2, h * 0.78 - 0.8, 0))
				tops.append(xf * Vector3(-5.2, h * 0.78 - 0.8, 0))
	# Cables sag between the restored pylons.
	for i: int in tops.size() - 2:
		var c0: Vector3 = tops[i]
		var c1: Vector3 = tops[i + 2]
		var prev: Vector3 = c0
		for s: int in range(1, 9):
			var t: float = float(s) / 8.0
			var q: Vector3 = c0.lerp(c1, t) - Vector3(0, sin(t * PI) * 3.0, 0)
			_add_beam(up, prev, q, 0.05, _mat("dark"))
			prev = q
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])


func _turbine(base: Vector3) -> void:
	var fut := Batch.new()
	var h: float = 46.0
	fut.add(ProcMesh.cyl(0.9, 1.6, h, 16), _xf(base + Vector3(0, h * 0.5, 0)), _mat("white"))
	_add_box(fut, base + Vector3(0, h + 0.6, 0.6), Vector3(1.6, 1.6, 4.2), _mat("white"))
	_add_box(fut, base + Vector3(0, h * 0.62, 0.0), Vector3(1.9, 0.08, 1.9), _mat("line"))
	fut.flush(_groups["future"])
	var hub := Node3D.new()
	hub.position = base + Vector3(0, h + 0.6, -1.7)
	_groups["future"].add_child(hub)
	var blades := Batch.new()
	blades.add(ProcMesh.sphere(0.7, 12, 6), _xf(Vector3.ZERO), _mat("white"))
	for k: int in 3:
		var a: float = TAU * k / 3.0
		var tip := Vector3(cos(a), sin(a), 0) * 20.0
		blades.add(_box(), _beam_xf(Vector3.ZERO, tip, 1.0) * Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.18)), Vector3.ZERO), _mat("white"))
	blades.flush(hub)
	_rotors.append(hub)


# --- Frozen Port -----------------------------------------------------------------------------

func _build_port() -> void:
	var e: float = _edge()
	var quay_x: float = _quay_x
	_build_terrain({"a": "snow_02", "b": "dry_ground_rocks", "tint_a": Color(0.96, 0.98, 1.03), "tint_b": Color(0.62, 0.66, 0.72),
		"scale_a": 0.12, "scale_b": 0.05, "rough_a": 0.62, "rough_b": 0.9, "slope_lo": 0.42, "slope_hi": 0.62,
		"sparkle": 1.0, "green_amt": 0.5, "tint_g": Color(0.5, 0.62, 0.42), "macro": 0.08})
	# Sea ice on the harbour side (ruin and mid), open water once the port is futuristic.
	var ice_plane: MeshInstance3D = _flood_plane(1.0, quay_x, 0.08)
	ice_plane.reparent(_groups["ruin"])
	var mid_ice: MeshInstance3D = _flood_plane(1.0, quay_x, 0.08)
	mid_ice.reparent(_groups["mid"])
	var open: MeshInstance3D = _flood_plane(0.0, quay_x, 0.05)
	_flood_mat.set_shader_parameter("clarity", 0.8)
	_flood_mat.set_shader_parameter("mirror", 0.5)
	open.reparent(_groups["future"])
	_flood_mat = null
	# The quay wall along the harbour edge, bollards and a snowbank along its back.
	var always := Batch.new()
	_add_box(always, Vector3(quay_x - 2.0, -0.6, -40.0), Vector3(4.0, 1.4, 240.0), _mat("concrete"))
	for z: float in range(-150, 80, 9):
		always.add(ProcMesh.cyl(0.25, 0.3, 0.6, 10), _xf(Vector3(quay_x - 0.6, 0.35, z)), _mat("dark"))
	always.flush(_groups["always"])
	# Ship-to-shore cranes along the quay, booms out over the harbour.
	var zs: Array[float] = [-118.0, -86.0, -54.0, -22.0, 10.0]
	for i: int in zs.size():
		_crane(Vector3(quay_x - 6.0, 0, zs[i]), i)
	# A coaster frozen fast in the harbour ice, snow on her decks.
	var snowcoat: Material = _coat(Color(0.93, 0.96, 1.0, 0.6))
	var ship: MeshInstance3D = _model("dutch_ship_medium", Vector3(quay_x + 48.0, -1.4, -70.0), 0.2, 1.0, _groups["always"], Vector3.ZERO, snowcoat)
	if ship:
		ship.rotation = Vector3(0.04, 1.75, -0.05)
	# Container yard: stacks to the west and north, and two more lines behind the quay.
	var palette: Array[Color] = [Color(0.2, 0.32, 0.45), Color(0.58, 0.18, 0.14), Color(0.22, 0.38, 0.3), Color(0.78, 0.44, 0.16), Color(0.52, 0.52, 0.5), Color(0.72, 0.62, 0.24), Color(0.85, 0.85, 0.82)]
	for blk: Array in [[-2.6, e + 14.0], [-2.1, e + 18.0], [-1.65, e + 16.0], [2.4, e + 16.0], [-1.25, e + 22.0], [-0.95, e + 18.0]]:
		var bc: Vector3 = _polar(float(blk[0]), float(blk[1]))
		if bc.x > quay_x - 18.0:
			bc.x = quay_x - 18.0
		bc.y = _gy(bc)
		_container_block(bc, float(blk[0]) + PI * 0.5, palette)
	# Snowy junk heaps and gas bottles out on the ice.
	for i: int in 8:
		_model("small_lpg_tank", _polar(_rng.randf_range(-2.8, -0.6), e + _rng.randf_range(3.0, 12.0)), _rng.randf() * TAU, 1.6, null, Vector3(1.4 if _rng.randf() < 0.5 else 0.0, 0, 0))
	_build_ice_slabs()
	# Light snow drifting down around Lumi.
	_snow = CPUParticles3D.new()
	_snow.amount = 600
	_snow.lifetime = 7.0
	_snow.preprocess = 7.0
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(30.0, 1.0, 30.0)
	_snow.direction = Vector3(0.3, -1.0, 0.1)
	_snow.spread = 15.0
	_snow.gravity = Vector3(0.0, -0.6, 0.0)
	_snow.initial_velocity_min = 1.2
	_snow.initial_velocity_max = 2.0
	_snow.scale_amount_min = 0.04
	_snow.scale_amount_max = 0.09
	_snow.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_texture = _soft_dot()
	sm.albedo_color = Color(1, 1, 1, 0.85)
	q.material = sm
	_snow.mesh = q
	add_child(_snow)


func _crane(base: Vector3, idx: int) -> void:
	var ruin := Batch.new()
	var mid := Batch.new()
	var fut := Batch.new()
	var h: float = 26.0
	var gauge: float = 14.0  # leg spacing along x
	var span: float = 12.0   # along z
	var cols: Array[Material] = [_paint(Color(0.9, 0.36, 0.08), 0.95, 0.25, idx), _paint(Color(0.72, 0.28, 0.1), 0.6, 0.75, idx), _mat("white")]
	for v: int in 3:
		var b: Batch = [mid, ruin, fut][v]
		var m: Material = cols[v]
		var droop: float = 0.0 if v != 1 else (18.0 if idx == 1 else 4.0)
		for lx: float in [0.0, gauge]:
			for lz: float in [-span * 0.5, span * 0.5]:
				_add_box(b, base + Vector3(lx, h * 0.5, lz), Vector3(1.0, h, 1.0), m)
			_add_beam(b, base + Vector3(lx, 1.5, -span * 0.5), base + Vector3(lx, h - 2.0, span * 0.5), 0.45, m)
			_add_beam(b, base + Vector3(lx, 1.5, span * 0.5), base + Vector3(lx, h - 2.0, -span * 0.5), 0.45, m)
		for lz: float in [-span * 0.5, span * 0.5]:
			_add_box(b, base + Vector3(gauge * 0.5, h, lz), Vector3(gauge + 1.0, 1.4, 1.0), m)
			_add_box(b, base + Vector3(gauge * 0.5, 2.0, lz), Vector3(gauge, 0.8, 0.8), m)
		# Boom: back-reach over the yard, out-reach over the water (drooping on a wreck).
		var pivot: Vector3 = base + Vector3(gauge, h + 2.5, 0)
		var boom_end: Vector3 = pivot + Vector3(cos(deg_to_rad(-droop)) * 40.0, sin(deg_to_rad(-droop)) * 40.0, 0)
		_add_beam(b, base + Vector3(-14.0, h + 2.5, -1.6), pivot + Vector3(0, 0, -1.6), 1.0, m)
		_add_beam(b, base + Vector3(-14.0, h + 2.5, 1.6), pivot + Vector3(0, 0, 1.6), 1.0, m)
		_add_beam(b, pivot + Vector3(0, 0, -1.6), boom_end + Vector3(0, 0, -1.6), 1.0, m)
		_add_beam(b, pivot + Vector3(0, 0, 1.6), boom_end + Vector3(0, 0, 1.6), 1.0, m)
		for t: float in [0.2, 0.45, 0.7, 0.95]:
			var q: Vector3 = pivot.lerp(boom_end, t)
			_add_box(b, q, Vector3(0.5, 0.5, 3.6), m)
		# A-frame and stays.
		var apex: Vector3 = base + Vector3(gauge * 0.6, h + 14.0, 0)
		_add_beam(b, base + Vector3(0, h, 0), apex, 0.8, m)
		_add_beam(b, base + Vector3(gauge, h, 0), apex, 0.8, m)
		_add_beam(b, apex, boom_end, 0.12, _mat("dark"))
		_add_beam(b, apex, base + Vector3(-14.0, h + 2.5, 0), 0.12, _mat("dark"))
		# Machinery house and the operator cab.
		_add_box(b, base + Vector3(-8.0, h + 4.5, 0), Vector3(7.0, 3.6, 5.0), m)
		_add_box(b, base + Vector3(gauge + 3.0, h - 0.6, 2.4), Vector3(2.4, 2.2, 2.4), _mat("glass_dark") if v != 1 else m)
		if v == 2:
			# Thin light lines along the boom and down the legs.
			_add_beam(fut, pivot + Vector3(0, 0.55, 0), boom_end + Vector3(0, 0.55, 0), 0.06, _mat("line"))
			for lx: float in [0.0, gauge]:
				_add_beam(fut, base + Vector3(lx, 0.4, span * 0.5 + 0.52), base + Vector3(lx, h, span * 0.5 + 0.52), 0.05, _mat("line"))
	ruin.flush(_groups["ruin"])
	mid.flush(_groups["mid"])
	fut.flush(_groups["future"])


func _container_block(c: Vector3, yaw: float, palette: Array[Color]) -> void:
	var ruin := Batch.new()
	var mid := Batch.new()
	var up := Batch.new()
	var fut := Batch.new()
	var sz := Vector3(6.06, 2.59, 2.44)
	var basis_ := Basis(Vector3.UP, yaw)
	for r: int in 3:
		for k: int in 4:
			var height: int = _rng.randi_range(1, 4)
			var local := Vector3((k - 1.5) * (sz.x + 0.4), 0, (r - 1) * (sz.z + 0.3))
			var p: Vector3 = c + basis_ * local
			for lv: int in height:
				var col: Color = palette[_rng.randi() % palette.size()]
				var y: float = sz.y * (lv + 0.5)
				up.add(_box(), Transform3D((basis_ * Basis.from_scale(sz)), p + Vector3(0, y, 0)), _corr(col))
				if lv == height - 1:
					fut.add(_box(), Transform3D((basis_ * Basis.from_scale(Vector3(sz.x, 0.04, 0.04))), p + Vector3(0, y + sz.y * 0.5, sz.z * 0.5)), _mat("line"))
					# Still frozen at levels 2-3: a snow cap on every stack.
					mid.add(_box(), Transform3D((basis_ * Basis.from_scale(Vector3(sz.x * 0.97, 0.22, sz.z * 0.94))), p + Vector3(0, y + sz.y * 0.5 + 0.1, 0)), _mat("snow"))
				# Ruin: the stacks slumped, tipped and capped with snow.
				if lv > 1 and _rng.randf() < 0.5:
					continue
				var rb := Basis(Vector3.UP, yaw + _rng.randf_range(-0.35, 0.35))
				var ry: float = y
				if lv == 0 and _rng.randf() < 0.18:
					rb = rb * Basis(Vector3.FORWARD, PI * 0.5)
					ry = sz.z * 0.5
				ruin.add(_box(), Transform3D((rb * Basis.from_scale(sz)), p + Vector3(_rng.randf_range(-0.6, 0.6), ry, _rng.randf_range(-0.6, 0.6))), _corr(col.lerp(Color(0.45, 0.33, 0.25), 0.55)))
				if lv == height - 1 or lv == 1:
					ruin.add(_box(), Transform3D((rb * Basis.from_scale(Vector3(sz.x * 0.95, 0.25, sz.z * 0.9))), p + Vector3(0, ry + sz.y * 0.5 + 0.1, 0)), _mat("snow"))
	ruin.flush(_groups["ruin"])
	mid.flush(_groups["mid"])
	up.flush(_groups["up"])
	fut.flush(_groups["future"], false)


## [biomes2] The ice: one dense plane over the field whose shader (ice_slab.gdshader) reads the
## per-hex ice at the natural-border warp, so sheets end in wandering margins, not hex edges.
func _build_ice_slabs() -> void:
	var size: int = field.radius * 2 + 1
	_ice_img = Image.create(size, size, false, Image.FORMAT_RGF)
	for h: int in district.ice.size():
		var a: Vector2i = field.hex_axial[h]
		var v: float = float(district.ice[h]) if field.hex_hub[h] == 0 else 0.0
		_ice_img.set_pixel(a.x + field.radius, a.y + field.radius, Color(clampf(v, 0.0, 1.0), 1.0 if field.is_water(h) else 0.0, 0.0))
	_ice_tex = ImageTexture.create_from_image(_ice_img)
	var m: ShaderMaterial = _mat("ice")
	m.set_shader_parameter("ice_n", _ice_tex)
	m.set_shader_parameter("ice_l", _ice_tex)
	m.set_shader_parameter("grid_radius", field.radius)
	m.set_shader_parameter("hex_size", field.hex_size)
	m.set_shader_parameter("water_y", HexField.WATER_Y)
	_share_warp(m)
	var ext: float = (field.radius * 2 + 2) * field.hex_size * Hex.SQRT3
	var pm := PlaneMesh.new()
	pm.size = Vector2(ext, ext)
	var sub: int = int(ext / 0.6)
	pm.subdivide_width = sub
	pm.subdivide_depth = sub
	pm.custom_aabb = AABB(Vector3(-ext * 0.5, -1.0, -ext * 0.5), Vector3(ext, 3.0, ext))
	var mi := MeshInstance3D.new()
	mi.name = "IceSheet"
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for h: Variant in district.heaters:
		add_heater(int(h), false)
	for h: Variant in district.greenhouses:
		add_greenhouse(int(h), false)


## Copies the field ground's natural-border warp (FieldView) onto a frontier shader.
func _share_warp(m: ShaderMaterial) -> void:
	var gm: ShaderMaterial = world.view.ground_material if world.get("view") != null else null
	if gm == null:
		return
	for k: String in ["warp_tex", "warp_size", "warp_amp"]:
		m.set_shader_parameter(k, gm.get_shader_parameter(k))


func set_ice(h: int, v: float) -> void:
	if _ice_img == null or h < 0 or h >= field.hex_count() or field.hex_hub[h] != 0:
		return
	var a: Vector2i = field.hex_axial[h]
	_ice_img.set_pixel(a.x + field.radius, a.y + field.radius, Color(clampf(v, 0.0, 1.0), 1.0 if field.is_water(h) else 0.0, 0.0))
	_ice_dirty = true


func add_heater(h: int, animate: bool) -> void:
	if _heaters.has(h):
		return
	var n := Node3D.new()
	n.name = "Heater%d" % h
	add_child(n)
	n.global_position = field.hex_center(h) + Vector3(field.hex_size * 0.25, 0.0, field.hex_size * 0.2)
	var b := Batch.new()
	var paint: Material = _paint(Color(0.82, 0.3, 0.14), 0.9, 0.35, h)
	b.add(ProcMesh.cyl(0.38, 0.42, 0.95, 20), _xf(Vector3(0, 0.6, 0)), paint)
	b.add(ProcMesh.cyl(0.5, 0.5, 0.12, 20), _xf(Vector3(0, 0.06, 0)), _mat("dark"))
	b.add(ProcMesh.cyl(0.09, 0.09, 0.8, 10), _xf(Vector3(0, 1.45, 0)), _mat("dark"))
	b.add(ProcMesh.cyl(0.16, 0.11, 0.12, 10), _xf(Vector3(0, 1.88, 0)), _mat("dark"))
	for k: int in 4:
		var a: float = TAU * k / 4.0 + 0.4
		b.add(_box(), _beam_xf(Vector3(cos(a) * 0.5, 0.0, sin(a) * 0.5), Vector3(cos(a) * 0.34, 0.5, sin(a) * 0.34), 0.05), _mat("dark"))
	b.flush(n)
	var coil := MeshInstance3D.new()
	coil.mesh = ProcMesh.torus(0.36, 0.42, 24, 6)
	var cm: StandardMaterial3D = Mats.lamp(Color(1.0, 0.45, 0.15), 2.4)
	coil.material_override = cm
	coil.position = Vector3(0, 0.62, 0)
	coil.scale = Vector3(1.04, 3.2, 1.04)
	n.add_child(coil)
	n.set_meta("coil", coil)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.55, 0.25)
	lamp.light_energy = 1.4
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, 0.9, 0)
	n.add_child(lamp)
	_heaters[h] = n
	if animate:
		n.scale = Vector3(1, 0.05, 1)
		n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Vfx.burst("big_sparkle", n.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.3))
		Audio.play("clunk", 0.9, -4.0)
		Audio.play("steam", 0.7, -6.0)


func add_greenhouse(h: int, animate: bool) -> void:
	if _greenhouses.has(h):
		return
	var n := Node3D.new()
	n.name = "Greenhouse%d" % h
	add_child(n)
	n.global_position = field.hex_center(h)
	var r: float = field.hex_size * 0.86
	var wall: float = 3.0
	var roof: float = 2.2
	var b := Batch.new()
	var c: Array[Vector3] = []
	for k: int in 6:
		var a: float = deg_to_rad(30.0 + 60.0 * k)
		c.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for k: int in 6:
		var a0: Vector3 = c[k]
		var a1: Vector3 = c[(k + 1) % 6]
		_add_beam(b, a0, a0 + Vector3(0, wall, 0), 0.12, _mat("white"))
		_add_beam(b, a0 + Vector3(0, wall, 0), a1 + Vector3(0, wall, 0), 0.1, _mat("white"))
		_add_beam(b, a0 + Vector3(0, 0.05, 0), a1 + Vector3(0, 0.05, 0), 0.16, _mat("white"))
		_add_beam(b, a0 + Vector3(0, wall, 0), Vector3(0, wall + roof, 0), 0.1, _mat("white"))
		_add_beam(b, a0 + Vector3(0, 0.12, 0) + (Vector3.ZERO - a0).normalized() * 0.1, a1 + Vector3(0, 0.12, 0) + (Vector3.ZERO - a1).normalized() * 0.1, 0.03, _mat("line"))
		# Glass: one wall pane and one roof pane per side.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v: Vector3 in [a0, a1, a1 + Vector3(0, wall, 0), a0, a1 + Vector3(0, wall, 0), a0 + Vector3(0, wall, 0),
				a0 + Vector3(0, wall, 0), a1 + Vector3(0, wall, 0), Vector3(0, wall + roof, 0)]:
			st.add_vertex(v)
		st.generate_normals()
		b.add(st.commit(), Transform3D.IDENTITY, _mat("glass"))
	b.flush(n, false)
	_greenhouses[h] = n
	if animate:
		n.scale = Vector3(1, 0.02, 1)
		n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Vfx.burst("big_sparkle", n.global_position + Vector3(0, 2.0, 0), Color(0.7, 1.0, 0.8))
		Audio.play("chime", 1.1, -4.0)


# --- Sunken City -----------------------------------------------------------------------------

func _build_sunken() -> void:
	var e: float = _edge()
	var fl: Dictionary = district.kind.get("flood", {})
	_build_terrain({"a": "damp_sand", "b": "dry_ground_rocks", "tint_a": Color(0.62, 0.68, 0.62), "tint_b": Color(0.6, 0.66, 0.64),
		"scale_a": 0.1, "scale_b": 0.05, "slope_lo": 0.3, "slope_hi": 0.5, "rough_a": 0.8, "rough_b": 0.9,
		"green_amt": 0.85, "tint_g": Color(0.45, 0.6, 0.42), "macro": 0.1, "biome_tint": Vector4.ZERO})
	_terrain_mat.set_shader_parameter("restore", maxf(restore, 0.55))  # the far headlands are always green
	_flood = _flood_plane(0.0, -99999.0, float(fl.get("sea_y", 0.12)))
	# Deep, still flood water: dark teal-green that mirrors the sky, not a murky lake.
	_flood_mat.set_shader_parameter("murky", Color(0.05, 0.1, 0.1, 0.97))
	_flood_mat.set_shader_parameter("clear", Color(0.05, 0.2, 0.22, 0.85))
	_flood_mat.set_shader_parameter("mirror", 0.75)
	_flood_mat.set_shader_parameter("wave_scale", 3.6)
	_flood_mat.set_shader_parameter("fade_far", 1200.0)
	_tune_field_water()
	_sink = Frontiers.sink_for(district.drained, fl)
	_apply_sink()
	_apply_flood_level(false)
	# A coaster that went down with the city, listing, and buoys bobbing over the streets.
	var ship: MeshInstance3D = _model("dutch_ship_medium", _polar(-1.25, e + 34.0, -6.5), 0.0)
	if ship:
		ship.rotation = Vector3(0.12, 2.2, -0.3)
	for i: int in 9:
		_model("ocean_buoy", _polar(_rng.randf() * TAU, e + _rng.randf_range(4.0, 40.0), -0.2), _rng.randf() * TAU, 1.2, null, Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
	for i: int in 6:
		_model("lifebuoy", _polar(_rng.randf() * TAU, e + _rng.randf_range(2.0, 20.0), 0.1), _rng.randf() * TAU, 1.0, null, Vector3(PI * 0.5, 0, 0))
	# Two pump houses at the field edge with outfall pipes into the flood.
	for a: float in [-1.85, -0.8]:
		_pump_house(_polar(a, e + 3.0), a + PI * 0.5)


func _water_mat() -> ShaderMaterial:
	var wv: Node = world.get("water")
	return wv.get("_mat") if wv else null


## Natural borders for the field's water hexes: the shoreline (water.gdshader) and the lakebed
## under it (ground_pbr lake_warp) follow the same warp as the junk, the ice and the flood.
func _setup_field_water() -> void:
	var wm: ShaderMaterial = _water_mat()
	if wm == null:
		return
	_share_warp(wm)
	wm.set_shader_parameter("ice_nrm", AssetLib.tex("snow_02", "nor_gl"))
	var gm: ShaderMaterial = world.view.ground_material if world.get("view") != null else null
	if gm:
		gm.set_shader_parameter("lake_warp", 1.0)
	# Screen-space reflections on High+ where a frontier is mostly water (the flooded towers
	# mirror in the streets); Ultra already has them everywhere.
	var sd: Node = world.get("sky_director")
	if kid == "sunken_city" and sd and sd.get("env") and Settings.quality >= Settings.Quality.HIGH and RenderingServer.get_current_rendering_method() == "forward_plus":
		var env: Environment = sd.env
		env.ssr_enabled = true
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.1
		env.ssr_depth_tolerance = 0.4


## Weathers the junk: sand drifts on it in the Dust Flats, frost and snow in the port, a film of
## dried silt in the Sunken City, a light film of grime in the Cradle (its junk is newer).
func _weather_junk() -> void:
	var looks: Dictionary = {
		"dust_flats": [Color(0.84, 0.7, 0.5), 0.85, 0.3, 0.95],
		"frozen_port": [Color(0.94, 0.96, 1.0), 0.95, 0.18, 0.55],
		"sunken_city": [Color(0.34, 0.35, 0.29), 0.6, 0.42, 0.6],
		"cradle_returns": [Color(0.66, 0.66, 0.64), 0.35, 0.18, 0.9],
	}
	if not looks.has(kid) or world.get("view") == null or not world.view.has_method("set_junk_overlay"):
		return
	var l: Array = looks[kid]
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/junk_coat.gdshader")
	m.set_shader_parameter("coat", l[0])
	m.set_shader_parameter("top_amt", l[1])
	m.set_shader_parameter("film", l[2])
	m.set_shader_parameter("roughness", l[3])
	world.view.set_junk_overlay(m)


## The field's own water hexes (WaterView) get the same deep flood look.
func _tune_field_water() -> void:
	var wm: ShaderMaterial = _water_mat()
	if wm == null:
		return
	# Same numbers as the flood plane (flood.gdshader with mirror 0.75): colour, opacity, gloss.
	wm.set_shader_parameter("murky_col", Vector3(0.05, 0.1, 0.1))
	wm.set_shader_parameter("clear_col", Vector3(0.05, 0.2, 0.22))
	wm.set_shader_parameter("alpha_mc", Vector2(0.97, 0.85))
	wm.set_shader_parameter("rough_mc", Vector2(0.077, 0.0275))
	wm.set_shader_parameter("mirror", 0.75)
	wm.set_shader_parameter("sheen_amt", 0.0)


func _pump_house(p: Vector3, yaw: float) -> void:
	var ruin := Batch.new()
	var up := Batch.new()
	var fut := Batch.new()
	var basis_ := Basis(Vector3.UP, yaw)
	var vs: Array = [[ruin, _paint(Color(0.45, 0.42, 0.38), 0.35, 0.9, 3)], [up, _paint(Color(0.2, 0.42, 0.55), 0.95, 0.25, 4)]]
	for v: Array in vs:
		var b: Batch = v[0]
		var m: Material = v[1]
		b.add(_box(), Transform3D((basis_ * Basis.from_scale(Vector3(7.0, 5.0, 5.0))), p + Vector3(0, 2.5, 0)), _mat("concrete"))
		b.add(_box(), Transform3D((basis_ * Basis.from_scale(Vector3(7.4, 0.4, 5.4))), p + Vector3(0, 5.2, 0)), m)
		for k: int in 2:
			var off: Vector3 = basis_ * Vector3(-1.6 + k * 3.2, 0, 3.2)
			b.add(ProcMesh.cyl(0.8, 0.8, 9.0, 18), Transform3D(basis_ * Basis(Vector3.RIGHT, PI * 0.5), p + off + Vector3(0, 1.4, 3.6)), m)
			b.add(ProcMesh.torus(0.78, 0.98, 18, 6), Transform3D(basis_ * Basis(Vector3.RIGHT, PI * 0.5), p + off + Vector3(0, 1.4, 0.4)), _mat("dark"))
	for k: int in 2:
		_pumps_fx.append(p + basis_ * Vector3(-1.6 + k * 3.2, 1.4, 12.5))
	fut.add(_box(), Transform3D((basis_ * Basis.from_scale(Vector3(7.1, 0.05, 0.05))), p + Vector3(0, 4.2, 0) + basis_ * Vector3(0, 0, -2.53)), _mat("line"))
	fut.add(_box(), Transform3D((basis_ * Basis.from_scale(Vector3(7.6, 0.6, 5.6))), p + Vector3(0, 5.4, 0)), _mat("white"))
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])
	fut.flush(_groups["future"])


func _apply_sink() -> void:
	var city: Node3D = world.get("city")
	if city:
		city.position.y = -_sink


func _apply_flood_level(animate: bool) -> void:
	if _flood == null:
		return
	var fl: Dictionary = district.kind.get("flood", {})
	var st: int = int(fl.get("stages", 3))
	var y: float = float(fl.get("sea_y", 0.12)) - (0.0 if district.drained < st else 1.5)
	_flood_mat.set_shader_parameter("clarity", clampf(float(district.drained) / st, 0.0, 1.0) * 0.8)
	if animate:
		create_tween().tween_property(_flood, "position:y", y, 4.0)
	else:
		_flood.position.y = y


## The pumps ran: the city rises out of the water and the new streets steam and drip.
func on_drained(hexes: Array[int], animate: bool) -> void:
	var target: float = Frontiers.sink_for(district.drained, district.kind.get("flood", {}))
	_apply_flood_level(animate)
	if not animate:
		_sink = target
		_apply_sink()
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_sink = v
		_apply_sink(), _sink, target, 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for p: Vector3 in _pumps_fx:
		for k: int in 6:
			get_tree().create_timer(k * 0.8, false).timeout.connect(func() -> void: Vfx.burst("steam", p, Color(0.75, 0.85, 0.9, 0.8), 2.0))
	for i: int in hexes.size():
		var c: Vector3 = field.hex_center(hexes[i])
		get_tree().create_timer(0.4 + i * 0.25, false).timeout.connect(func() -> void:
			Vfx.burst("soil", c + Vector3(0, 0.2, 0), Color(0.55, 0.62, 0.6, 0.8), 2.0)
			Vfx.ring(c, field.hex_size, Color(0.6, 0.85, 1.0, 0.7), 1.2))


# --- Cradle Returns --------------------------------------------------------------------------

func _build_cradle() -> void:
	var e: float = _edge()
	_build_terrain({"a": "leafy_grass", "b": "leafy_grass", "tint_a": Color(0.46, 0.74, 0.36), "tint_b": Color(0.4, 0.66, 0.32),
		"scale_a": 0.12, "scale_b": 0.06, "slope_lo": 0.08, "slope_hi": 0.3, "rough_a": 0.9, "rough_b": 0.9,
		"green_amt": 0.6, "tint_g": Color(0.6, 0.78, 0.48), "macro": 0.12, "biome_tint": Vector4.ZERO})
	_build_plaza(e)
	_build_skyline_cradle(e)
	# Launch gantries behind the pad: rusty lattice (ruin) or white (restored).
	var pad: Dictionary = district.kind.get("pad", {})
	var pc: Array = pad.get("center", [0, -3])
	var pad_c: Vector3 = field.hex_center(int(field.axial_to_id.get(Vector2i(int(pc[0]), int(pc[1])), 0)))
	for g: Vector3 in [pad_c + Vector3(-14.0, 0, -e * 0.9), pad_c + Vector3(16.0, 0, -e * 0.95)]:
		g.z = minf(g.z, -e - 14.0)
		g.y = _gy(g)
		_gantry(g)
	_build_pad(pad_c)
	_build_ark(pad_c)


## A flat ring sector (top, inner and outer faces) from radius r1 to r2, angles a0..a1, h tall.
static func _arc_mesh(r1: float, r2: float, a0: float, a1: float, h: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in segs:
		var t0: float = lerpf(a0, a1, float(k) / segs)
		var t1: float = lerpf(a0, a1, float(k + 1) / segs)
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		var up := Vector3(0, h, 0)
		for tri: Array in [[d0 * r1 + up, d1 * r2 + up, d0 * r2 + up], [d0 * r1 + up, d1 * r1 + up, d1 * r2 + up],
				[d0 * r2, d0 * r2 + up, d1 * r2 + up], [d0 * r2, d1 * r2 + up, d1 * r2],
				[d0 * r1, d1 * r1 + up, d0 * r1 + up], [d0 * r1, d1 * r1, d1 * r1 + up]]:
			for v: Vector3 in [tri[0], tri[2], tri[1]]:  # Godot's front faces wind clockwise
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## The launch city's apron around the field: a clean paved ring with planters, slim lamp posts
## and one faint light inlay. Ground crews kept it swept.
func _build_plaza(_e: float) -> void:
	var b := Batch.new()
	var paving: Material = AssetLib.pbr_material("concrete_pavement", 0.12, Color(1.08, 1.08, 1.1), true)
	var r0: float = _r_in - 1.0
	var r1: float = _r_in + 30.0
	for k: int in 8:
		b.add(_arc_mesh(r0, r1, TAU * k / 8.0, TAU * (k + 1) / 8.0, 0.03, 24), Transform3D.IDENTITY, paving)
	b.add(ProcMesh.torus(r1 - 2.06, r1 - 1.94, 160, 3), Transform3D(Basis().scaled(Vector3(1, 0.04, 1)), Vector3(0, 0.05, 0)), _mat("line_soft"))
	var mb := MeshBatch.new()
	var shrub: Mesh = AssetLib.model_mesh_lite("shrub_01", 1500) if AssetLib.has_model("shrub_01") else null
	var n: int = 44
	for k: int in n:
		var a: float = TAU * (k + 0.5) / n
		var p: Vector3 = _polar(a, _r_in + 14.0)
		b.add(ProcMesh.cyl(1.5, 1.4, 0.7, 20), _xf(p + Vector3(0, 0.35, 0)), _mat("white"))
		b.add(ProcMesh.cyl(1.35, 1.35, 0.05, 20), _xf(p + Vector3(0, 0.7, 0)), _mat("green"))
		if shrub:
			mb.instance(shrub, Transform3D((Basis(Vector3.UP, a * 3.0) * Basis.from_scale(Vector3.ONE * 1.4)), p + Vector3(0, 0.66, 0)))
		if k % 2 == 0:
			var lp: Vector3 = _polar(a + PI / n, _r_in + 24.0)
			b.add(ProcMesh.cyl(0.08, 0.12, 7.0, 8), _xf(lp + Vector3(0, 3.5, 0)), _mat("white"))
			_add_box(b, lp + Vector3(0, 7.05, 0), Vector3(0.9, 0.1, 0.25), _mat("white"), Vector3(0, -rad_to_deg(a), 0))
			_add_box(b, lp + Vector3(0, 6.98, 0), Vector3(0.7, 0.03, 0.12), _mat("line_soft"), Vector3(0, -rad_to_deg(a), 0))
	b.flush(_groups["always"])
	mb.flush(_groups["always"])


## The launch city skyline: slender towers of dark glass behind white fins and floor bands, with
## setbacks, crowns and the odd spire, rising behind the pad; low white pavilions between.
func _build_skyline_cradle(_e: float) -> void:
	var b := Batch.new()
	var white: Material = _mat("white")
	var glass: Material = _mat("tower_glass")
	var placed: Array[Vector2] = []
	var tries: int = 0
	while placed.size() < 34 and tries < 400:
		tries += 1
		var back: bool = placed.size() < 24
		var ang: float = -PI * 0.5 + _rng.randf_range(-1.75, 1.75) if back else _rng.randf() * TAU
		var dist: float = _r_in + _rng.randf_range(150.0, 430.0) + (0.0 if back else 90.0)
		var p: Vector3 = _polar(ang, dist)
		var xz := Vector2(p.x, p.z)
		var ok: bool = true
		for q: Vector2 in placed:
			if q.distance_to(xz) < 58.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(xz)
		p.y = _gy(p) - 0.5
		var h: float = _rng.randf_range(55.0, 175.0) * (1.0 if back else 0.7)
		var w: float = _rng.randf_range(15.0, 26.0)
		var yaw: float = _rng.randf() * TAU
		var bs := Basis(Vector3.UP, yaw)
		var is_round: bool = _rng.randf() < 0.4
		_add_box(b, p + Vector3(0, 4.0, 0), Vector3(w * 1.9, 8.0, w * 1.7), white, Vector3(0, rad_to_deg(yaw), 0))
		_add_box(b, p + Vector3(0, 6.0, 0), Vector3(w * 1.92, 1.2, w * 1.72), glass, Vector3(0, rad_to_deg(yaw), 0))
		var y: float = 8.0
		var cw: float = w
		var tiers: int = 1 + (_rng.randi() % 3 if h > 90.0 else 0)
		for t: int in tiers:
			var th: float = (h - 8.0) / tiers
			var mid: Vector3 = p + Vector3(0, y + th * 0.5, 0)
			if is_round:
				b.add(ProcMesh.cyl(cw * 0.5, cw * 0.5, th, 32), Transform3D(bs, mid), glass)
				for f: int in 10:
					var fa: float = TAU * f / 10.0
					b.add(_box(), Transform3D((Basis(Vector3.UP, -fa) * Basis.from_scale(Vector3(1.4, th, 0.45))), mid + Vector3(cos(fa), 0, sin(fa)) * cw * 0.5), white)
				var fy: float = 0.0
				while fy < th - 2.0:
					fy += 12.0
					b.add(ProcMesh.cyl(cw * 0.5 + 0.35, cw * 0.5 + 0.35, 0.6, 32), Transform3D(bs, p + Vector3(0, y + fy, 0)), white)
			else:
				var d: float = cw * 0.78
				_add_box(b, mid, Vector3(cw, th, d), glass, Vector3(0, rad_to_deg(yaw), 0))
				for cx: float in [-0.5, -0.17, 0.17, 0.5]:
					for cz: float in [-0.5, 0.5]:
						b.add(_box(), Transform3D((bs * Basis.from_scale(Vector3(0.9 if absf(cx) > 0.4 else 0.4, th, 0.9))), mid + bs * Vector3(cx * cw, 0, cz * d)), white)
				var fy2: float = 0.0
				while fy2 < th - 2.0:
					fy2 += 12.0
					b.add(_box(), Transform3D((bs * Basis.from_scale(Vector3(cw + 0.6, 0.6, d + 0.6))), p + Vector3(0, y + fy2, 0)), white)
			y += th
			cw *= _rng.randf_range(0.72, 0.85)
		# Crown: a white cap with one faint light band; some get a spire.
		@warning_ignore("incompatible_ternary")
		b.add(ProcMesh.cyl(cw * 0.62, cw * 0.62, 1.6, 24) if is_round else _box(), Transform3D(bs, p + Vector3(0, y + 0.8, 0)) if is_round else Transform3D((bs * Basis.from_scale(Vector3(cw * 1.08, 1.6, cw * 0.86))), p + Vector3(0, y + 0.8, 0)), white)
		b.add(ProcMesh.torus(cw * 0.55, cw * 0.58, 32, 3), Transform3D(Basis().scaled(Vector3(1, 0.3, 1)), p + Vector3(0, y - 0.6, 0)), _mat("line_soft"))
		if _rng.randf() < 0.35:
			var sh: float = _rng.randf_range(12.0, 30.0)
			b.add(ProcMesh.cyl(0.15, 0.7, sh, 8), _xf(p + Vector3(0, y + 1.6 + sh * 0.5, 0)), white)
	# Low pavilions and hangars between the towers.
	for i: int in 40:
		var ang2: float = -PI * 0.5 + _rng.randf_range(-2.2, 2.2)
		var p2: Vector3 = _polar(ang2, _r_in + _rng.randf_range(80.0, 320.0))
		var near: bool = false
		for q: Vector2 in placed:
			if q.distance_to(Vector2(p2.x, p2.z)) < 30.0:
				near = true
		if near:
			continue
		p2.y = _gy(p2) - 0.3
		var lw: float = _rng.randf_range(14.0, 34.0)
		var lh: float = _rng.randf_range(6.0, 16.0)
		var ly: float = rad_to_deg(ang2) + 90.0
		_add_box(b, p2 + Vector3(0, lh * 0.5, 0), Vector3(lw, lh, lw * 0.6), white, Vector3(0, ly, 0))
		_add_box(b, p2 + Vector3(0, lh * 0.55, 0), Vector3(lw + 0.1, lh * 0.35, lw * 0.6 + 0.1), glass, Vector3(0, ly, 0))
		_add_box(b, p2 + Vector3(0, lh + 0.05, 0), Vector3(lw * 0.9, 0.12, lw * 0.52), _mat("green"), Vector3(0, ly, 0))
	b.flush(_groups["always"])


func _gantry(base: Vector3) -> void:
	var ruin := Batch.new()
	var up := Batch.new()
	var h: float = 62.0
	var w: float = 5.0
	for v: int in 2:
		var b: Batch = [ruin, up][v]
		var m: Material = _paint(Color(0.5, 0.36, 0.28), 0.25, 0.95, 9) if v == 0 else _mat("white")
		for cx: float in [-w, w]:
			for cz: float in [-w, w]:
				_add_box(b, base + Vector3(cx, h * 0.5, cz), Vector3(0.6, h, 0.6), m)
		for y: float in range(4, int(h), 6):
			for s: int in 4:
				var a: Vector3 = [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)][s]
				var c: Vector3 = [Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w), Vector3(-w, 0, -w)][s]
				_add_beam(b, base + a + Vector3(0, y, 0), base + c + Vector3(0, y + 6.0, 0), 0.25, m)
				_add_beam(b, base + a + Vector3(0, y, 0), base + c + Vector3(0, y, 0), 0.3, m)
		_add_box(b, base + Vector3(0, h + 1.0, 0), Vector3(w * 2.6, 2.0, w * 2.6), m)
		if v == 1:
			_add_beam(up, base + Vector3(w + 0.4, 1.0, w + 0.4), base + Vector3(w + 0.4, h, w + 0.4), 0.06, _mat("line"))
			up.add(ProcMesh.sphere(0.6, 10, 6), _xf(base + Vector3(0, h + 2.6, 0)), Mats.lamp(Color(1.0, 0.25, 0.2), 3.0))
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])


## The landing pad: a thin light ring and chevrons over the pad hexes, and six pylons whose
## lamps light as the pad hexes reach Sustained.
func _build_pad(c: Vector3) -> void:
	var ring_r: float = field.hex_size * (float(district.kind.get("pad", {}).get("ring", 1)) + 0.75) * Hex.SQRT3 * 0.5 * 1.15
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pad_mat.albedo_color = CYAN
	_pad_mat.emission_enabled = true
	_pad_mat.emission = CYAN
	_pad_mat.emission_energy_multiplier = 0.4
	var b := Batch.new()
	for rr: float in [ring_r, ring_r * 0.55]:
		b.add(ProcMesh.torus(rr - 0.06, rr + 0.06, 96, 3), Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), c + Vector3(0, 0.06, 0)), _pad_mat)
	for k: int in 12:
		var a: float = TAU * k / 12.0
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * ring_r * 0.78
		b.add(_box(), Transform3D((Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(1.4, 0.02, 0.08))), p + Vector3(0, 0.06, 0)), _pad_mat)
	var root := Node3D.new()
	root.name = "Pad"
	add_child(root)
	b.flush(root, false)
	# [biomes2] The landing ring itself: a broad, flush ring of white composite plates in 16
	# segments (thin dark joints between them), a faint seam of light on its inner edge, and four
	# tall slender masts. Flush with the ground so it never blocks Lumi or the robots.
	var ring := Batch.new()
	var r1: float = ring_r + 0.9
	var r2: float = ring_r + 4.6
	var gap: float = 0.012
	for k: int in 16:
		var a0: float = TAU * k / 16.0 + gap
		var a1: float = TAU * (k + 1) / 16.0 - gap
		ring.add(_arc_mesh(r1, r2, a0, a1, 0.05, 8), Transform3D(Basis(), c + Vector3(0, 0.0, 0)), _mat("white"))
		var am: float = (a0 + a1) * 0.5
		_add_box(ring, c + Vector3(cos(am), 0, sin(am)) * (r2 - 0.9) + Vector3(0, 0.06, 0), Vector3(0.12, 0.01, 1.2), _mat("dark"), Vector3(0, -rad_to_deg(am), 0))
	ring.add(ProcMesh.torus(r1 + 0.06, r1 + 0.18, 128, 3), Transform3D(Basis().scaled(Vector3(1, 0.04, 1)), c + Vector3(0, 0.07, 0)), _mat("line_soft"))
	ring.add(ProcMesh.torus(r2 + 1.2, r2 + 1.32, 128, 3), Transform3D(Basis().scaled(Vector3(1, 0.04, 1)), c + Vector3(0, 0.04, 0)), _mat("line_soft"))
	# The docking halo: a slim white ring held high on six masts, the shape the ark comes down
	# into. Overhead, so it never blocks Lumi or the robots; one faint seam of light underneath.
	var halo_r: float = r2 + 2.4
	var halo_y: float = 19.0
	for k: int in 6:
		var ma: float = TAU * k / 6.0 + PI / 6.0
		var mp: Vector3 = c + Vector3(cos(ma), 0, sin(ma)) * halo_r
		mp.y = 0.0
		ring.add(ProcMesh.cyl(0.16, 0.38, halo_y, 14), _xf(mp + Vector3(0, halo_y * 0.5, 0)), _mat("white"))
		ring.add(ProcMesh.cyl(0.55, 0.7, 0.4, 14), _xf(mp + Vector3(0, 0.2, 0)), _mat("white"))
		# A slender strut leaning in from each mast to the halo's inner edge.
		_add_beam(ring, mp + Vector3(0, halo_y * 0.62, 0), c + Vector3(cos(ma), 0, sin(ma)) * (halo_r - 2.2) + Vector3(0, halo_y - 0.4, 0), 0.16, _mat("white"))
	ring.add(ProcMesh.torus(halo_r - 1.1, halo_r + 1.1, 160, 10), Transform3D(Basis().scaled(Vector3(1, 0.32, 1)), c + Vector3(0, halo_y, 0)), _mat("white"))
	ring.add(ProcMesh.torus(halo_r - 0.95, halo_r - 0.85, 160, 3), Transform3D(Basis().scaled(Vector3(1, 0.05, 1)), c + Vector3(0, halo_y - 0.36, 0)), _mat("line_soft"))
	ring.flush(root)
	var pyl := Batch.new()
	for k: int in 6:
		var a: float = deg_to_rad(30.0 + 60.0 * k)
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (ring_r + 1.5)
		pyl.add(ProcMesh.cyl(0.18, 0.26, 4.2, 12), _xf(p + Vector3(0, 2.1, 0)), _mat("white"))
		pyl.add(_box(), _xf(p + Vector3(0, 2.0, 0.0), Vector3.ZERO, Vector3(0.04, 3.4, 0.04)), _mat("line"))
		var lamp := MeshInstance3D.new()
		lamp.mesh = ProcMesh.sphere(0.24, 12, 6)
		lamp.material_override = Mats.lamp(Color(0.25, 0.3, 0.32), 0.1)
		lamp.position = p + Vector3(0, 4.35, 0)
		root.add_child(lamp)
		_pylon_lamps.append(lamp)
	pyl.flush(root)
	_beams = Node3D.new()
	_beams.visible = false
	root.add_child(_beams)
	var beam_m := StandardMaterial3D.new()
	beam_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_m.albedo_color = Color(0.5, 0.9, 1.0, 0.25)
	for lamp: MeshInstance3D in _pylon_lamps:
		var bm := MeshInstance3D.new()
		bm.mesh = ProcMesh.cyl(0.12, 0.12, 400.0, 8)
		bm.material_override = beam_m
		bm.position = lamp.position + Vector3(0, 200.0, 0)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beams.add_child(bm)


## The ark Cradle, high over the pad: a long white hull with a habitat ring, seed bays, solar
## wings and engines, and thin running lights. It descends as the district comes alive.
func _build_ark(pad_c: Vector3) -> void:
	_ark = Node3D.new()
	_ark.name = "Cradle"
	add_child(_ark)
	_ark.position = Vector3(pad_c.x + 40.0, _ark_y, pad_c.z - 320.0)
	var b := Batch.new()
	var hull := CapsuleMesh.new()
	hull.radius = 20.0
	hull.height = 230.0
	hull.radial_segments = 32
	hull.rings = 12
	b.add(hull, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), _mat("white"))
	b.add(ProcMesh.torus(46.0, 52.0, 64, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(1, 0.5, 1)), Vector3(20.0, 0, 0)), _mat("white"))
	for k: int in 6:
		var a: float = TAU * k / 6.0
		_add_beam(b, Vector3(20.0, cos(a) * 19.0, sin(a) * 19.0), Vector3(20.0, cos(a) * 47.0, sin(a) * 47.0), 2.2, _mat("white"))
	for k: int in 4:
		var a2: float = TAU * k / 4.0 + PI * 0.25
		b.add(ProcMesh.cyl(7.0, 9.0, 30.0, 16), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-118.0, cos(a2) * 16.0, sin(a2) * 16.0)), _mat("alu"))
		b.add(ProcMesh.cyl(6.0, 6.0, 1.0, 16), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-133.5, cos(a2) * 16.0, sin(a2) * 16.0)), Mats.lamp(Color(0.6, 0.85, 1.0), 2.5))
	for s: float in [-1.0, 1.0]:
		_add_box(b, Vector3(-40.0, 0, s * 70.0), Vector3(60.0, 0.8, 80.0), _mat("panel"))
		_add_beam(b, Vector3(-40.0, 0, s * 20.0), Vector3(-40.0, 0, s * 30.0), 2.0, _mat("alu"))
	for k: int in 8:
		_add_box(b, Vector3(60.0 - k * 12.0, -19.5, 0), Vector3(8.0, 1.5, 14.0), _mat("glass_dark"))
	for a3: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		_add_beam(b, Vector3(-100.0, cos(a3) * 20.3, sin(a3) * 20.3), Vector3(110.0, cos(a3) * 20.3, sin(a3) * 20.3), 0.5, _mat("line"))
	b.flush(_ark, false)
	for x: float in [130.0, -60.0]:
		var bl := MeshInstance3D.new()
		bl.mesh = ProcMesh.sphere(2.0, 10, 6)
		bl.material_override = Mats.lamp(Color(1.0, 0.3, 0.25), 4.0)
		bl.position = Vector3(x, 22.0, 0)
		_ark.add_child(bl)


func set_cradle(p: Dictionary) -> void:
	_cradle = p
	var lit: int = int(floor(float(p.get("pad_level", 0.0)) * 6.0 + 0.001))
	for i: int in _pylon_lamps.size():
		var on: bool = i < lit or district.done
		var m: StandardMaterial3D = _pylon_lamps[i].material_override
		m.emission = CYAN if on else Color(0.25, 0.3, 0.32)
		m.emission_energy_multiplier = 3.0 if on else 0.1
	if _beams:
		_beams.visible = district.done


func celebrate() -> void:
	if _beams:
		_beams.visible = true
	for lamp: MeshInstance3D in _pylon_lamps:
		Vfx.burst("big_sparkle", lamp.global_position, CYAN)
	Vfx.burst("confetti", world.patch.global_position + Vector3(0, 2, 0), Color.WHITE)


# --- Storm -----------------------------------------------------------------------------------

func set_storm(a: float) -> void:
	_storm_amt = a


func dust_hex(h: int) -> void:
	var c: Vector3 = field.hex_center(h)
	for k: int in 5:
		Vfx.burst("dust", c + Vector3(_rng.randf_range(-6, 6), 0.4, _rng.randf_range(-6, 6)), Color(0.85, 0.7, 0.5, 0.8), 2.5)
