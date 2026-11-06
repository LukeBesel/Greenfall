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

const CYAN := Color(0.45, 0.92, 1.0)
const WARM := Color(1.0, 0.62, 0.3)

var district: FrontierDistrict
var world: Node
var field: HexField
var kid: String = ""
var level: int = 1
var restore: float = 0.0

var _groups: Dictionary = {}       # name -> Node3D
var _mats: Dictionary = {}
var _hex_mesh: ArrayMesh
var _ice_mm: MultiMesh
var _ice_slot: Dictionary = {}     # hex id -> instance index
var _heaters: Dictionary = {}      # hex id -> Node3D
var _greenhouses: Dictionary = {}  # hex id -> Node3D
var _storm: CPUParticles3D
var _storm_amt: float = 0.0
var _flood: MeshInstance3D
var _flood_mat: ShaderMaterial
var _sink: float = 0.0
var _rotors: Array[Node3D] = []
var _pad_ring: MeshInstance3D
var _pad_mat: StandardMaterial3D
var _pylon_lamps: Array[MeshInstance3D] = []
var _beams: Node3D
var _ark: Node3D
var _ark_y: float = 620.0
var _cradle: Dictionary = {}
var _pumps_fx: Array[Vector3] = []
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


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
	set_level(level, false)
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


func set_restore(r: float) -> void:
	restore = r


func _process(delta: float) -> void:
	_t += delta
	for r: Node3D in _rotors:
		if is_instance_valid(r) and r.is_visible_in_tree():
			r.rotate_object_local(Vector3.FORWARD, delta * 0.9)
	if _storm:
		var p: Node3D = world.get("patch")
		if p:
			_storm.global_position = p.global_position + Vector3(-18.0, 3.0, 0.0)
		_storm.emitting = _storm_amt > 0.08
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
			l.emission_energy_multiplier = 1.6
			m = l
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
			var i := StandardMaterial3D.new()
			i.albedo_color = Color(1, 1, 1, 1)
			i.vertex_color_use_as_albedo = true
			i.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			i.roughness = 0.07
			i.metallic = 0.05
			i.rim_enabled = true
			i.rim = 0.4
			i.normal_enabled = true
			i.normal_texture = AssetLib.tex("snow_02", "nor_gl")
			i.normal_scale = 0.35
			i.uv1_triplanar = true
			i.uv1_scale = Vector3.ONE * 0.25
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
	var len: float = d.length()
	var y: Vector3 = d / maxf(len, 0.0001)
	var x: Vector3 = y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Transform3D(Basis(x * thick, y * len, z * thick), (a + b) * 0.5)


var _unit_box: BoxMesh


func _box() -> BoxMesh:
	if _unit_box == null:
		_unit_box = ProcMesh.box(Vector3.ONE)
	return _unit_box


func _add_box(b: Batch, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	b.add(_box(), _xf(pos, rot_deg, size), mat)


func _add_beam(b: Batch, a: Vector3, c: Vector3, thick: float, mat: Material) -> void:
	b.add(_box(), _beam_xf(a, c, thick), mat)


func _model(id: String, pos: Vector3, yaw: float, scl: float = 1.0, parent: Node3D = null, tilt: Vector3 = Vector3.ZERO, overlay: Material = null) -> MeshInstance3D:
	if not AssetLib.has_model(id):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh_lite(id, 6000)
	mi.transform = Transform3D(Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)).scaled(Vector3.ONE * scl), pos)
	if overlay:
		mi.material_overlay = overlay
	(parent if parent else _groups["always"]).add_child(mi)
	return mi


func _edge() -> float:
	return field.hex_size * (float(field.radius) + 0.55) * Hex.SQRT3


## A point at angle (radians, 0 = +x, -PI/2 = -z, the default view) and distance from the base.
static func _polar(ang: float, dist: float, y: float = 0.0) -> Vector3:
	return Vector3(cos(ang) * dist, y, sin(ang) * dist)


func _hex_prism() -> ArrayMesh:
	if _hex_mesh:
		return _hex_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = field.hex_size * 0.985
	var c: Array[Vector3] = []
	for k: int in 6:
		var a: float = deg_to_rad(30.0 + 60.0 * k)
		c.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for k: int in 6:
		var a0: Vector3 = c[k]
		var a1: Vector3 = c[(k + 1) % 6]
		st.add_vertex(Vector3(0, 1, 0))
		st.add_vertex(a1 + Vector3(0, 1, 0))
		st.add_vertex(a0 + Vector3(0, 1, 0))
		st.add_vertex(a0)
		st.add_vertex(a0 + Vector3(0, 1, 0))
		st.add_vertex(a1 + Vector3(0, 1, 0))
		st.add_vertex(a0)
		st.add_vertex(a1 + Vector3(0, 1, 0))
		st.add_vertex(a1)
	st.generate_normals()
	_hex_mesh = st.commit()
	return _hex_mesh


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
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	pm.material = _flood_mat
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- Dust Flats ------------------------------------------------------------------------------

func _build_desert() -> void:
	var e: float = _edge()
	var always := Batch.new()
	var coat: Material = _coat(Color(0.9, 0.74, 0.5, 0.55))
	# Long dunes beyond the field, crests across the wind.
	var dune := SphereMesh.new()
	dune.radius = 1.0
	dune.height = 1.0
	dune.is_hemisphere = true
	dune.radial_segments = 32
	dune.rings = 10
	for i: int in 30:
		var ang: float = TAU * i / 30.0 + _rng.randf_range(-0.08, 0.08)
		var dist: float = e + _rng.randf_range(16.0, 90.0)
		var w: float = _rng.randf_range(18.0, 34.0)
		always.add(dune, Transform3D(Basis(Vector3.UP, 0.6 + _rng.randf_range(-0.2, 0.2)).scaled(Vector3(w, _rng.randf_range(3.0, 9.0) * (1.0 + (dist - e) / 120.0), w * 0.38)), _polar(ang, dist, -0.6)), _mat("sand"))
	always.flush(_groups["always"])
	# A trading ship, half-buried in the sand, listing hard. The flats were a sea once.
	var ship: MeshInstance3D = _model("dutch_ship_medium", _polar(-1.95, e + 26.0, -3.2), 0.9, 1.0, null, Vector3(0.0, 0, 0.22), coat)
	if ship:
		ship.rotation = Vector3(0.05, 0.9, 0.24)
	# Cars and drums buried to the windows near the edge, quiver trunks and rocks.
	for i: int in 7:
		var p: Vector3 = _polar(_rng.randf() * TAU, e + _rng.randf_range(3.0, 14.0), -_rng.randf_range(0.45, 0.8))
		_model("covered_car", p, _rng.randf() * TAU, 1.0, null, Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.2, 0.2)), coat)
	for i: int in 10:
		_model("dead_quiver_trunk", _polar(_rng.randf() * TAU, e + _rng.randf_range(4.0, 40.0)), _rng.randf() * TAU, _rng.randf_range(1.6, 2.6))
	for i: int in 12:
		_model("namaqualand_rocks_01", _polar(_rng.randf() * TAU, e + _rng.randf_range(2.0, 30.0)), _rng.randf() * TAU, _rng.randf_range(2.0, 4.0))
	# The solar farm: three blocks of panel rows.
	for f: Array in [[-1.15, e + 12.0], [-2.45, e + 16.0], [2.6, e + 14.0]]:
		_solar_farm(_polar(float(f[0]), float(f[1])), float(f[0]) + PI * 0.5)
	# Futuristic: tall white wind turbines on the far dunes.
	for a: float in [-1.4, -1.75, -0.95, 2.2]:
		_turbine(_polar(a, e + 85.0 + _rng.randf_range(-8.0, 12.0), 2.0))
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
	var basis := Basis(Vector3.UP, yaw)
	var rows: int = 4
	var cols: int = 9
	var pw: float = 2.0
	var ph: float = 1.2
	for r: int in rows:
		for k: int in cols:
			var local := Vector3((k - cols * 0.5) * (pw + 0.25), 0, (r - rows * 0.5) * 4.2)
			var p: Vector3 = c + basis * local
			# Restored: posts, a tilted panel in an aluminium frame, facing south (+z after yaw).
			var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-28.0))
			_add_box(up, p + Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), _mat("alu"))
			up.add(_box(), Transform3D(tilt.scaled(Vector3(pw, 0.05, ph)), p + Vector3(0, 1.15, 0)), _mat("panel"))
			up.add(_box(), Transform3D(tilt.scaled(Vector3(pw + 0.06, 0.035, ph + 0.06)), p + Vector3(0, 1.13, 0)), _mat("alu"))
			# Future: one thin light line along the top edge of every panel.
			var top: Vector3 = p + Vector3(0, 1.15, 0) + tilt * Vector3(0, 0.03, -ph * 0.5)
			fut.add(_box(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(pw, 0.025, 0.025)), top), _mat("line"))
			# Ruin: some panels gone, the rest dusty, cracked off their posts at odd angles.
			if _rng.randf() < 0.22:
				continue
			var fallen: bool = _rng.randf() < 0.35
			var rt := Basis(Vector3.UP, yaw + _rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(-70.0, -5.0) if not fallen else _rng.randf_range(-8.0, 8.0))) * Basis(Vector3.FORWARD, _rng.randf_range(-0.25, 0.25))
			var y: float = 1.1 if not fallen else 0.12
			_add_box(ruin, p + Vector3(0, 0.45, 0), Vector3(0.08, 0.9 * _rng.randf_range(0.5, 1.0), 0.08), _mat("alu"), Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12)))
			ruin.add(_box(), Transform3D(rt.scaled(Vector3(pw, 0.05, ph)), p + Vector3(0, y, 0)), _mat("panel_dusty"))
	# Inverter cabinets at the row ends.
	for r: int in rows:
		var p2: Vector3 = c + basis * Vector3(-(cols * 0.5 + 1.2) * (pw + 0.25), 0, (r - rows * 0.5) * 4.2)
		_add_box(up, p2 + Vector3(0, 0.7, 0), Vector3(0.9, 1.4, 0.6), _mat("white"))
		_add_box(fut, p2 + Vector3(0, 1.0, 0.31), Vector3(0.5, 0.03, 0.01), _mat("line"))
		_add_box(ruin, p2 + Vector3(0, 0.6, 0), Vector3(0.9, 1.2, 0.6), _paint(Color(0.7, 0.68, 0.6), 0.4, 0.8), Vector3(0, 0, _rng.randf_range(-15, 15)))
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])
	fut.flush(_groups["future"], false)


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
	var quay_x: float = e - 4.0
	# Sea ice on the harbour side (ruin and mid), open water once the port is futuristic.
	var ice_plane: MeshInstance3D = _flood_plane(1.0, quay_x, 0.08)
	ice_plane.reparent(_groups["ruin"])
	var mid_ice: MeshInstance3D = _flood_plane(1.0, quay_x, 0.08)
	mid_ice.reparent(_groups["mid"])
	var open: MeshInstance3D = _flood_plane(0.0, quay_x, 0.05)
	_flood_mat.set_shader_parameter("clarity", 0.8)
	open.reparent(_groups["future"])
	_flood_mat = null
	# The quay wall along the harbour edge.
	var always := Batch.new()
	_add_box(always, Vector3(quay_x - 2.0, -0.6, -40.0), Vector3(4.0, 1.4, 200.0), _mat("concrete"))
	for z: float in range(-130, 60, 9):
		always.add(ProcMesh.cyl(0.25, 0.3, 0.6, 10), _xf(Vector3(quay_x - 0.6, 0.35, z)), _mat("dark"))
	always.flush(_groups["always"])
	# Ship-to-shore cranes on the quay, booms out over the harbour.
	var zs: Array[float] = [-70.0, -38.0, -6.0]
	for i: int in zs.size():
		_crane(Vector3(quay_x - 6.0, 0, zs[i]), i)
	# Container yard: stacks to the west and north.
	var palette: Array[Color] = [Color(0.15, 0.32, 0.55), Color(0.62, 0.15, 0.12), Color(0.18, 0.42, 0.28), Color(0.85, 0.45, 0.12), Color(0.55, 0.55, 0.55), Color(0.8, 0.7, 0.2)]
	for blk: Array in [[-2.6, e + 14.0], [-2.1, e + 18.0], [-1.65, e + 16.0], [2.4, e + 16.0]]:
		_container_block(_polar(float(blk[0]), float(blk[1])), float(blk[0]) + PI * 0.5, palette)
	# Snowy junk heaps and gas bottles out on the ice.
	for i: int in 8:
		_model("small_lpg_tank", _polar(_rng.randf_range(-2.8, -0.6), e + _rng.randf_range(3.0, 12.0)), _rng.randf() * TAU, 1.6, null, Vector3(1.4 if _rng.randf() < 0.5 else 0.0, 0, 0))
	_build_ice_slabs()


func _crane(base: Vector3, idx: int) -> void:
	var ruin := Batch.new()
	var mid := Batch.new()
	var fut := Batch.new()
	var h: float = 26.0
	var gauge: float = 14.0  # leg spacing along x
	var span: float = 12.0   # along z
	var cols: Array[Material] = [_paint(Color(0.86, 0.42, 0.12), 0.95, 0.25, idx), _paint(Color(0.55, 0.38, 0.28), 0.25, 0.95, idx), _mat("white")]
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
	var up := Batch.new()
	var fut := Batch.new()
	var sz := Vector3(6.06, 2.59, 2.44)
	var basis := Basis(Vector3.UP, yaw)
	for r: int in 3:
		for k: int in 4:
			var height: int = _rng.randi_range(1, 4)
			var local := Vector3((k - 1.5) * (sz.x + 0.4), 0, (r - 1) * (sz.z + 0.3))
			var p: Vector3 = c + basis * local
			for lv: int in height:
				var col: Color = palette[_rng.randi() % palette.size()]
				var y: float = sz.y * (lv + 0.5)
				up.add(_box(), Transform3D(basis.scaled(sz), p + Vector3(0, y, 0)), _corr(col))
				if lv == height - 1:
					fut.add(_box(), Transform3D(basis.scaled(Vector3(sz.x, 0.04, 0.04)), p + Vector3(0, y + sz.y * 0.5, sz.z * 0.5)), _mat("line"))
				# Ruin: the stacks slumped, tipped and capped with snow.
				if lv > 1 and _rng.randf() < 0.5:
					continue
				var rb := Basis(Vector3.UP, yaw + _rng.randf_range(-0.35, 0.35))
				var ry: float = y
				if lv == 0 and _rng.randf() < 0.18:
					rb = rb * Basis(Vector3.FORWARD, PI * 0.5)
					ry = sz.z * 0.5
				ruin.add(_box(), Transform3D(rb.scaled(sz), p + Vector3(_rng.randf_range(-0.6, 0.6), ry, _rng.randf_range(-0.6, 0.6))), _corr(col.lerp(Color(0.45, 0.33, 0.25), 0.55)))
				if lv == height - 1 or lv == 1:
					ruin.add(_box(), Transform3D(rb.scaled(Vector3(sz.x * 0.95, 0.25, sz.z * 0.9)), p + Vector3(0, ry + sz.y * 0.5 + 0.1, 0)), _mat("snow"))
	ruin.flush(_groups["ruin"])
	up.flush(_groups["up"])
	fut.flush(_groups["future"], false)


func _build_ice_slabs() -> void:
	_ice_mm = MultiMesh.new()
	_ice_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ice_mm.use_colors = true
	_ice_mm.mesh = _hex_prism()
	var ids: Array[int] = []
	for h: int in district.ice.size():
		if field.hex_hub[h] == 0:
			ids.append(h)
	_ice_mm.instance_count = ids.size()
	for i: int in ids.size():
		_ice_slot[ids[i]] = i
		set_ice(ids[i], district.ice[ids[i]])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _ice_mm
	mmi.material_override = _mat("ice")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for h: Variant in district.heaters:
		add_heater(int(h), false)
	for h: Variant in district.greenhouses:
		add_greenhouse(int(h), false)


func set_ice(h: int, v: float) -> void:
	if _ice_mm == null or not _ice_slot.has(h):
		return
	var i: int = _ice_slot[h]
	if v <= 0.0:
		_ice_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0)))
		return
	var c: Vector3 = field.hex_center(h)
	var hgt: float = 0.18 + 0.5 * v
	_ice_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.0, hgt, 1.0)), c + Vector3(0, HexField.WATER_Y * 0.5 if field.is_water(h) else -0.02, 0)))
	_ice_mm.set_instance_color(i, Color(0.78, 0.88, 0.96, 0.42 + 0.3 * v))


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
	_flood = _flood_plane(0.0, -99999.0, float(fl.get("sea_y", 0.12)))
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


func _pump_house(p: Vector3, yaw: float) -> void:
	var ruin := Batch.new()
	var up := Batch.new()
	var fut := Batch.new()
	var basis := Basis(Vector3.UP, yaw)
	var vs: Array = [[ruin, _paint(Color(0.45, 0.42, 0.38), 0.35, 0.9, 3)], [up, _paint(Color(0.2, 0.42, 0.55), 0.95, 0.25, 4)]]
	for v: Array in vs:
		var b: Batch = v[0]
		var m: Material = v[1]
		b.add(_box(), Transform3D(basis.scaled(Vector3(7.0, 5.0, 5.0)), p + Vector3(0, 2.5, 0)), _mat("concrete"))
		b.add(_box(), Transform3D(basis.scaled(Vector3(7.4, 0.4, 5.4)), p + Vector3(0, 5.2, 0)), m)
		for k: int in 2:
			var off: Vector3 = basis * Vector3(-1.6 + k * 3.2, 0, 3.2)
			b.add(ProcMesh.cyl(0.8, 0.8, 9.0, 18), Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), p + off + Vector3(0, 1.4, 3.6)), m)
			b.add(ProcMesh.torus(0.78, 0.98, 18, 6), Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), p + off + Vector3(0, 1.4, 0.4)), _mat("dark"))
	for k: int in 2:
		_pumps_fx.append(p + basis * Vector3(-1.6 + k * 3.2, 1.4, 12.5))
	fut.add(_box(), Transform3D(basis.scaled(Vector3(7.1, 0.05, 0.05)), p + Vector3(0, 4.2, 0) + basis * Vector3(0, 0, -2.53)), _mat("line"))
	fut.add(_box(), Transform3D(basis.scaled(Vector3(7.6, 0.6, 5.6)), p + Vector3(0, 5.4, 0)), _mat("white"))
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
	var always := Batch.new()
	var fut := Batch.new()
	# The launch city: slender white hex towers with green terraces and thin vertical light lines.
	for i: int in 18:
		var ang: float = TAU * i / 18.0 + _rng.randf_range(-0.1, 0.1)
		var dist: float = e + _rng.randf_range(28.0, 95.0)
		var h: float = _rng.randf_range(24.0, 78.0)
		var r: float = _rng.randf_range(3.5, 7.0)
		var p: Vector3 = _polar(ang, dist)
		var yaw: float = _rng.randf() * TAU
		always.add(ProcMesh.cyl(r * 0.92, r, h, 6), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, h * 0.5, 0)), _mat("white"))
		always.add(ProcMesh.cyl(r * 0.94, r * 0.94, h * 0.9, 6), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, h * 0.47, 0)), _mat("glass_dark"))
		for t: float in [0.3, 0.55, 0.8]:
			var ty: float = h * t
			always.add(ProcMesh.cyl(r * 1.35, r * 1.35, 0.5, 6), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, ty, 0)), _mat("white"))
			always.add(ProcMesh.cyl(r * 1.25, r * 1.25, 0.6, 6), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, ty + 0.5, 0)), _mat("green"))
		for k: int in 3:
			var a: float = yaw + TAU * k / 3.0
			always.add(_box(), Transform3D(Basis(), p + Vector3(cos(a) * r * 0.95, h * 0.5, sin(a) * r * 0.95)).scaled_local(Vector3(0.06, h * 0.96, 0.06)), _mat("line"))
	for i: int in 26:
		var p2: Vector3 = _polar(_rng.randf() * TAU, e + _rng.randf_range(6.0, 30.0))
		_model(["shrub_02", "shrub_01", "pine_sapling_small"][i % 3], p2, _rng.randf() * TAU, _rng.randf_range(2.0, 3.5))
	always.flush(_groups["always"])
	fut.flush(_groups["future"])
	# Launch gantries behind the pad: rusty lattice (ruin) or white (restored).
	var pad: Dictionary = district.kind.get("pad", {})
	var pc: Array = pad.get("center", [0, -3])
	var pad_c: Vector3 = field.hex_center(int(field.axial_to_id.get(Vector2i(int(pc[0]), int(pc[1])), 0)))
	for g: Vector3 in [pad_c + Vector3(-14.0, 0, -e * 0.9), pad_c + Vector3(16.0, 0, -e * 0.95)]:
		g.z = minf(g.z, -e - 8.0)
		_gantry(g)
	_build_pad(pad_c)
	_build_ark(pad_c)


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
		b.add(_box(), Transform3D(Basis(Vector3.UP, -a).scaled(Vector3(1.4, 0.02, 0.08)), p + Vector3(0, 0.06, 0)), _pad_mat)
	var root := Node3D.new()
	root.name = "Pad"
	add_child(root)
	b.flush(root, false)
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
