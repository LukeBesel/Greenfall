class_name TideSite
extends TidewellEnv
## [planet-tidewell] Tidewell's placeable site prefabs for the walkable globe: compact local scenes
## (about 60-100 m across) built on a locally flat patch. No world-origin or flat-horizon
## assumptions: everything is local to the node, the sea patch is shaded in its own mesh space
## (ocean.gdshader local_space) and its bed map is baked from the site's own islands.
##   TideSite.place(site_id, root, stage, restoration, opts) -> TideSite
##     site_id      one of SITES (data/planets.json "tidewell".sites lists them)
##     root         any Node3D; the site is added as a child at its origin (sea level y = 0.14)
##     stage        0 ruin, 1 restored, 2 futuristic
##     restoration  0..1: water clarity, how much floating junk is left, greenery
##     opts         {"water_radius": m (default: the site's own), "seed": int}
##   set_state(stage, restoration) re-dresses a built site (groups + sea + junk).
## Sites: hub_raft (anchored raft base), hub_stilts (stilt yard on a sandy islet), wreck (the
## half-sunk ore barge), dredge_rig (a Ledger jack-up rig), reef_garden, buoy_field.

const SITES: Dictionary = {
	"hub_raft": {"kind": "hub", "radius": 46.0},
	"hub_stilts": {"kind": "hub", "radius": 48.0},
	"wreck": {"kind": "landmark", "radius": 50.0},
	"dredge_rig": {"kind": "landmark", "radius": 44.0},
	"reef_garden": {"kind": "landmark", "radius": 42.0},
	"buoy_field": {"kind": "landmark", "radius": 40.0},
}
const FLOATERS: Array[String] = ["plastic_bottle_gallon", "bleach_bottle", "plastic_jerrycan", "lifebuoy", "old_tyre", "wooden_crate_02", "Barrel_01", "trashbag", "trashbag", "multi_cleaner_bottle", "rubber_boots", "cardboard_box_01", "plastic_jerrycan", "old_tyre"]

var site_id: String = ""
var radius: float = 50.0
var _junk: Array[MultiMeshInstance3D] = []
var _junk_full: Array = []  # per MultiMeshInstance3D: Array[Transform3D]


static func place(p_site: String, root: Node3D, p_stage: int = 0, p_restoration: float = 0.0, opts: Dictionary = {}) -> TideSite:
	var s := TideSite.new()
	s.name = "TideSite_" + p_site
	root.add_child(s)
	s._make(p_site, int(opts.get("seed", hash(p_site) % 100000)), float(opts.get("water_radius", float(SITES.get(p_site, {}).get("radius", 50.0)))))
	s.set_state(p_stage, p_restoration)
	return s


func _process(_delta: float) -> void:
	pass


func _make(p_site: String, seed_v: int, water_r: float) -> void:
	site_id = p_site
	radius = water_r
	_rng.seed = seed_v
	_bed_noise.seed = seed_v + 33
	_bed_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_bed_noise.frequency = 0.006
	_bed_noise.fractal_octaves = 3
	_field_edge = -400.0  # no play-field bank
	kind = TidewellEnv.entry()
	for g: String in ["always", "ruin", "green", "mid", "future"]:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	match site_id:
		"hub_raft":
			islands = []
			TideProps.raft(self)  # [p_seas] was _site_raft()
		"hub_stilts":
			islands = [{"c": Vector2(6, 4), "r": 20.0, "h": 2.6, "kind": "isle", "yaw": 0.6, "stretch": 1.4}]
			_site_stilts()
		"wreck":
			islands = [{"c": Vector2(-24, 18), "r": 12.0, "h": 0.35, "kind": "bar", "yaw": 1.1, "stretch": 2.0}]
			_barge(Vector3(0, SEA_Y, 0), 0.7)
		"dredge_rig":
			islands = []
			var a := FrontierView.Batch.new()
			var m := FrontierView.Batch.new()
			var f := FrontierView.Batch.new()
			_rig(0, Vector3(0, SEA_Y, 0), 0.4, a, m, f, _groups["always"])
			a.flush(_groups["always"])
			m.flush(_groups["mid"])
			f.flush(_groups["future"])
		"reef_garden":
			islands = [{"c": Vector2(0, 0), "r": 22.0, "h": -0.9, "kind": "reef", "yaw": 0.0, "stretch": 1.3}, {"c": Vector2(18, -14), "r": 8.0, "h": 0.4, "kind": "bar", "yaw": 0.4, "stretch": 1.8}]
			_site_reef()
		"buoy_field":
			islands = []
			_site_buoys()
	_site_water(water_r)
	_site_junk(float(SITES.get(site_id, {}).get("radius", 50.0)))


## Re-dress for a stage (0 ruin, 1 restored, 2 future) and a restoration amount.
func set_state(p_stage: int, p_restoration: float) -> void:
	stage = clampi(p_stage, 0, 2)
	restore = clampf(p_restoration, 0.0, 1.0)
	var vis: Dictionary = {"always": true, "ruin": stage == 0, "green": stage >= 1, "mid": stage == 1, "future": stage == 2}
	for g: String in _groups:
		(_groups[g] as Node3D).visible = vis[g]
	if ocean_mat:
		ocean_mat.set_shader_parameter("restore", restore)
		ocean_mat.set_shader_parameter("future", 1.0 if stage == 2 else 0.0)
	# Floating junk thins out with restoration (gone when fully restored).
	for i: int in _junk.size():
		var mm: MultiMesh = _junk[i].multimesh
		var full: Array = _junk_full[i]
		mm.visible_instance_count = int(round(full.size() * clampf(1.0 - restore * 1.15, 0.0, 1.0)))
		_junk[i].visible = mm.visible_instance_count > 0
	TideProps.set_rust(self, stage, restore)  # [p_seas]


# --- Shared site pieces -----------------------------------------------------------------------

func _site_water(r: float) -> void:
	ocean_mat = ShaderMaterial.new()
	ocean_mat.shader = preload(DIR + "ocean.gdshader")
	ocean_mat.set_shader_parameter("local_space", true)
	ocean_mat.set_shader_parameter("grid_radius", -1)
	ocean_mat.set_shader_parameter("hex_size", 10.0)
	ocean_mat.set_shader_parameter("wave_nrm", AssetLib.tex("rubble", "nor_gl"))
	ocean_mat.set_shader_parameter("sea_y", SEA_Y)
	ocean_mat.set_shader_parameter("field_r", -200.0)
	ocean_mat.set_shader_parameter("swell_amp", 0.06)
	ocean_mat.set_shader_parameter("detail", 1.0 if Settings.quality >= Settings.Quality.MEDIUM else 0.6)
	var blank := Image.create(4, 4, false, Image.FORMAT_RGBAF)
	blank.fill(Color(0, 0, 0, 0))
	ocean_mat.set_shader_parameter("state_tex", ImageTexture.create_from_image(blank))
	var pal: Dictionary = kind.get("palette", {})
	for pair: Array in [["deep_col", "deep"], ["shallow_col", "shallow"], ["lagoon_col", "lagoon"], ["murky_col", "murky"], ["oil_col", "oil"], ["sand_col", "sand"]]:
		var c: Array = pal.get(pair[1], [])
		if c.size() >= 3:
			ocean_mat.set_shader_parameter(pair[0], Color(float(c[0]), float(c[1]), float(c[2])))
	var size: float = r * 2.0 + 20.0
	var tex: ImageTexture = _bake_local(size, 128 if size < 300.0 else 256)
	ocean_mat.set_shader_parameter("near_tex", tex)
	ocean_mat.set_shader_parameter("near_size", size)
	ocean_mat.set_shader_parameter("far_tex", tex)
	ocean_mat.set_shader_parameter("far_size", size)
	ocean = MeshInstance3D.new()
	ocean.name = "SiteSea"
	ocean.mesh = _polar_mesh(r)
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.position.y = SEA_Y
	_groups["always"].add_child(ocean)
	for isl: Dictionary in islands:
		if str(isl["kind"]) != "reef" and float(isl["h"]) > 0.0:
			_islet_mesh(isl)


func _bake_local(size: float, res: int) -> ImageTexture:
	var img := Image.create(res, res, false, Image.FORMAT_RGH)
	for y: int in res:
		for x: int in res:
			var wx: float = (float(x) + 0.5) / res * size - size * 0.5
			var wz: float = (float(y) + 0.5) / res * size - size * 0.5
			var v: Vector2 = bed_at(wx, wz)
			# Shallower towards the middle of a site (the patch it sits on), deep at its rim.
			v.x = maxf(v.x, lerpf(-2.2, -8.0, smoothstep(0.0, size * 0.5, Vector2(wx, wz).length())))
			img.set_pixel(x, y, Color(v.x, v.y, 0.0))
	return ImageTexture.create_from_image(img)


## A local islet / sandbar heightfield (eroded outline from bed_at), sand + rock + grass.
func _islet_mesh(isl: Dictionary) -> void:
	if _isle_mat == null:
		_isle_mat = ShaderMaterial.new()
		_isle_mat.shader = preload("res://art/shaders/terrain.gdshader")
		_isle_mat.set_shader_parameter("tex_a", AssetLib.tex("sand_01", "diff"))
		_isle_mat.set_shader_parameter("nrm_a", AssetLib.tex("sand_01", "nor_gl"))
		_isle_mat.set_shader_parameter("tex_b", AssetLib.tex("dry_ground_rocks", "diff"))
		_isle_mat.set_shader_parameter("nrm_b", AssetLib.tex("dry_ground_rocks", "nor_gl"))
		_isle_mat.set_shader_parameter("tex_g", AssetLib.tex("leafy_grass", "diff"))
		_isle_mat.set_shader_parameter("tint_a", Vector3(1.05, 1.0, 0.92))
		_isle_mat.set_shader_parameter("tint_g", Vector3(0.55, 0.78, 0.42))
		_isle_mat.set_shader_parameter("slope_lo", 0.22)
		_isle_mat.set_shader_parameter("slope_hi", 0.45)
		_isle_mat.set_shader_parameter("green_amt", 0.9)
		_isle_mat.set_shader_parameter("ripple", 0.4)
	var c: Vector2 = isl["c"]
	var rad: float = float(isl["r"]) * float(isl["stretch"]) * 1.3
	var rings: int = 26
	var spokes: int = 64
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings + 1:
		var rr: float = rad * pow(float(i) / rings, 0.8)
		for j: int in spokes:
			var a: float = TAU * float(j) / spokes
			var x: float = c.x + cos(a) * rr
			var z: float = c.y + sin(a) * rr
			st.add_vertex(Vector3(x, maxf(bed_at(x, z).x, -2.5), z))
	for i: int in rings:
		for j: int in spokes:
			var j1: int = (j + 1) % spokes
			var a0: int = i * spokes + j
			var a1: int = i * spokes + j1
			var b0: int = (i + 1) * spokes + j
			var b1: int = (i + 1) * spokes + j1
			for idx: int in [a0, b0, a1, a1, b0, b1]:
				st.add_index(idx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Islet"
	mi.mesh = st.commit()
	mi.material_override = _isle_mat
	_groups["always"].add_child(mi)


## Floating junk covering the site's water (fully trashed when ruined); thins with restoration.
func _site_junk(r: float) -> void:
	var by: Dictionary = {}
	var n: int = int(r * r * 0.75)
	for k: int in n:
		var a: float = _rng.randf() * TAU
		var d: float = sqrt(_rng.randf()) * r * 0.95
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d)
		if bed_at(p.x, p.z).x > SEA_Y - 0.1 or _on_deck(p):
			continue
		# Clumped: half the pieces drift into rafts.
		if _rng.randf() < 0.5:
			var cl: float = floorf(_rng.randf() * 6.0)
			var cp := Vector3(cos(cl * 1.7 + 0.4) * r * 0.55, 0, sin(cl * 2.3 + 1.0) * r * 0.55)
			p = cp + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 3.5
		var id: String = FLOATERS[_rng.randi() % FLOATERS.size()]
		if not AssetLib.has_model(id):
			continue
		var aabb: AABB = AssetLib.model_aabb(id)
		var lie: bool = id in ["plastic_bottle_gallon", "bleach_bottle", "old_tyre", "wine_bottles_01", "lifebuoy", "plastic_jerrycan", "rubber_boots", "multi_cleaner_bottle"]
		var bs := Basis(Vector3.UP, _rng.randf() * TAU)
		if lie:
			bs = bs * Basis(Vector3.RIGHT, PI * 0.5)
		bs = bs * Basis(Vector3.FORWARD, _rng.randf_range(-0.25, 0.25))
		var low: float = INF
		for e: int in 8:
			low = minf(low, (bs * aabb.get_endpoint(e)).y)
		var xf := Transform3D(bs, Vector3(p.x, SEA_Y - low - 0.08 - aabb.size.y * 0.25, p.z))
		if not by.has(id):
			by[id] = []
		(by[id] as Array).append(xf)
	for id: String in by:
		var arr: Array = by[id]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = AssetLib.model_mesh_lite(id, 400)
		mm.instance_count = arr.size()
		for i: int in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Junk_" + id
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 160.0
		_groups["always"].add_child(mmi)
		_junk.append(mmi)
		_junk_full.append(arr)
	# Ghost-net trash rafts under the clumps.
	var net := ShaderMaterial.new()
	net.shader = preload(DIR + "net.gdshader")
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	var b := FrontierView.Batch.new()
	for cl: int in 18:
		var cp := Vector3(cos(cl * 1.7 + 0.4) * r * 0.55, SEA_Y + 0.015, sin(cl * 2.3 + 1.0) * r * 0.55)
		if cl >= 6:
			var a: float = _rng.randf() * TAU
			var d: float = sqrt(_rng.randf()) * r * 0.9
			cp = Vector3(cos(a) * d, SEA_Y + 0.015, sin(a) * d)
		if bed_at(cp.x, cp.z).x > SEA_Y - 0.1 or _on_deck(cp):
			continue
		var sc: float = _rng.randf_range(2.6, 5.0)
		b.add(pm, _lxf(cp, Vector3(0, _rng.randf() * 360.0, 0), Vector3(sc, 1, sc * 0.8)), net)
	b.flush(_groups["ruin"], false)


var _decks: Array[Vector3] = []  # x, z, radius of decks/hulls (no floating junk there)


func _on_deck(p: Vector3) -> bool:
	for d: Vector3 in _decks:
		if Vector2(p.x - d.x, p.z - d.y).length() < d.z:
			return true
	return false


## Detailed shack: corrugated walls with a plinth, a pitched tin roof with overhang, a door,
## windows, a stove pipe. ruin: rust and a sagging roof; future: white shell, thin light seam.
func _shack(b: FrontierView.Batch, fut: FrontierView.Batch, p: Vector3, yaw: float, size: Vector3) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var xf := func(v: Vector3) -> Vector3: return p + bs * v
	var rot := Vector3(0, rad_to_deg(yaw), 0)
	_box(b, xf.call(Vector3(0, size.y * 0.5, 0)), size, _mat("tin"), rot)
	_box(b, xf.call(Vector3(0, 0.12, 0)), Vector3(size.x + 0.2, 0.24, size.z + 0.2), _mat("rust_dark"), rot)
	for side: float in [-1.0, 1.0]:
		var rp := Vector3(0, size.y + size.z * 0.18, side * size.z * 0.26)
		_box(b, xf.call(rp), Vector3(size.x + 0.7, 0.08, size.z * 0.6), _mat("tin_roof"), rot + Vector3(side * -22.0, 0, 0))
	_box(b, xf.call(Vector3(size.x * 0.25, 1.0, size.z * 0.5 + 0.02)), Vector3(0.95, 2.0, 0.06), _mat("rust_red"), rot)
	for wx: float in [-size.x * 0.25, size.x * 0.05]:
		_box(b, xf.call(Vector3(wx, size.y * 0.62, size.z * 0.5 + 0.03)), Vector3(0.9, 0.7, 0.05), _mat("window"), rot)
	_cyl(b, xf.call(Vector3(-size.x * 0.35, size.y, -size.z * 0.2)), xf.call(Vector3(-size.x * 0.35, size.y + 1.6, -size.z * 0.2)), 0.12, _mat("rust_dark"))
	_box(fut, xf.call(Vector3(0, size.y * 0.5, 0)), size + Vector3(0.12, 0.08, 0.12), _mat("white"), rot)
	_box(fut, xf.call(Vector3(0, size.y + 0.05, 0)), Vector3(size.x + 0.2, 0.04, size.z + 0.2), _mat("lamp"), rot)


## A timber deck of individual planks (slightly uneven, varied tones, gaps) over joists, clipped
## to an irregular outline (rx, rz with noise); top at y.
func _plank_deck(b: FrontierView.Batch, c: Vector3, rx: float, rz: float, y: float, yaw: float, variant: int) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = 4000 + variant
	nz.frequency = 0.9
	var bs := Basis(Vector3.UP, yaw)
	var tones: Array[String] = ["plank_a", "plank_b", "plank_c"]
	# A solid sub-deck under the boards, so the gaps read as shadow lines, not open water.
	b.add(_blob_slab(variant, 0.12, 1.0), _lxf(c + Vector3(0, y - 0.2, 0), Vector3(0, rad_to_deg(yaw), 0), Vector3(rx * 0.99, 0.2, rz * 0.98)), _mat("trunk"))
	var x: float = -rx
	while x < rx:
		var w: float = _rng.randf_range(0.5, 0.62)
		var u: float = x / rx
		if absf(u) < 1.0:
			var half: float = rz * sqrt(maxf(0.0, 1.0 - u * u))
			var a: float = atan2(0.0, u)
			half *= 1.0 + nz.get_noise_2d(u * 2.0, 0.0) * 0.18
			var z0: float = -half
			var z1: float = half
			var z: float = z0
			while z < z1 - 0.4:
				var ln: float = minf(_rng.randf_range(2.0, 4.5), z1 - z)
				var pc := c + bs * Vector3(x + w * 0.5, y - 0.05 + _rng.randf_range(-0.015, 0.015), z + ln * 0.5)
				_box(b, pc, Vector3(w - 0.03, 0.1, ln - 0.04), _mat(tones[_rng.randi() % 3]), Vector3(_rng.randf_range(-0.3, 0.3), rad_to_deg(yaw), _rng.randf_range(-0.3, 0.3)))
				z += ln
			if int(x / 2.2) != int((x + w) / 2.2):  # a joist every couple of metres
				_box(b, c + bs * Vector3(x, y - 0.22, (z0 + z1) * 0.5), Vector3(0.2, 0.22, z1 - z0), _mat("trunk"), Vector3(0, rad_to_deg(yaw), 0))
		x += w


func _planter(b: FrontierView.Batch, p: Vector3, r: float) -> void:
	b.add(_blob_slab(_rng.randi() % 4, 0.2, 1.0), _lxf(p + Vector3(0, 0.2, 0), Vector3(0, _rng.randf() * 360.0, 0), Vector3(r, 0.4, r)), _mat("wood"))
	for k: int in 5:
		var o := Vector3(_rng.randf_range(-0.6, 0.6), 0.5, _rng.randf_range(-0.6, 0.6)) * r
		var s: float = _rng.randf_range(0.25, 0.5)
		b.add(_lumpy(5 + k % 3, 0.55, 3.0), _lxf(p + o, Vector3(0, _rng.randf() * 360.0, 0), Vector3(s, s * 0.9, s)), _mat("mangrove"))


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	match key:
		"tin":
			var t := AssetLib.pbr_material("corrugated_iron", 0.5, Color(0.95, 0.9, 0.82), true)
			t.metallic = 0.0  # painted tin: the arm metal channel read as a dark mirror from above
			t.metallic_texture = null
			t.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mats[key] = t
			return t
		"tin_roof":
			var r := AssetLib.pbr_material("corrugated_iron", 0.5, Color(0.86, 0.62, 0.46), true)
			r.metallic = 0.0
			r.metallic_texture = null
			r.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mats[key] = r
			return r
		"plank_a", "plank_b", "plank_c":
			# Sun- and salt-bleached timber: per-plank tones, fine grain from a stretched normal map.
			var tint: Color = {"plank_a": Color(0.74, 0.64, 0.52), "plank_b": Color(0.62, 0.53, 0.43), "plank_c": Color(0.8, 0.74, 0.64)}[key]
			var pl := StandardMaterial3D.new()
			pl.albedo_color = tint
			pl.roughness = 0.88
			pl.normal_enabled = true
			pl.normal_texture = AssetLib.tex("concrete_floor_worn_001", "nor_gl")
			pl.normal_scale = 0.5
			pl.uv1_triplanar = true
			pl.uv1_scale = Vector3(0.3, 0.3, 3.0)
			_mats[key] = pl
			return pl
		"deck":
			var d := AssetLib.pbr_material("dry_decay_leaves", 0.4, Color(0.55, 0.44, 0.33), true)
			d.metallic = 0.0
			d.metallic_texture = null
			_mats[key] = d
			return d
		"coral_dead":
			var cd := AssetLib.pbr_material("dry_ground_rocks", 0.8, Color(0.82, 0.8, 0.74), true)
			cd.metallic = 0.0
			_mats[key] = cd
			return cd
		"coral":
			var cr := StandardMaterial3D.new()
			cr.albedo_color = Color(0.95, 0.5, 0.42)
			cr.roughness = 0.7
			cr.albedo_texture = AssetLib.tex("dry_ground_rocks", "diff")
			cr.normal_enabled = true
			cr.normal_texture = AssetLib.tex("dry_ground_rocks", "nor_gl")
			cr.uv1_triplanar = true
			_mats[key] = cr
			return cr
	return super._mat(key)


# --- Hubs ----------------------------------------------------------------------------------------

## The anchored raft base: an irregular timber deck (about 32 m) on rusted pontoons, a workshop
## shack and a store, a deck crane, fuel tank, net piles and mooring lines out to buoys.
func _site_raft() -> void:
	var b := FrontierView.Batch.new()
	var ruin := FrontierView.Batch.new()
	var grn := FrontierView.Batch.new()
	var fut := FrontierView.Batch.new()
	var deck_r: float = 16.0
	var deck_y: float = 0.75
	_decks.append(Vector3(0, 0, deck_r + 1.5))
	_plank_deck(b, Vector3.ZERO, deck_r, deck_r * 0.84, deck_y, 0.35, 3)
	# Pontoons under the rim, bollards and a railing of posts and rope.
	for k: int in 14:
		var a: float = TAU * k / 14.0 + 0.1
		var pr := Vector3(cos(a) * deck_r * 0.92, 0.25, sin(a) * deck_r * 0.8)
		var t := Vector3(-sin(a), 0, cos(a))
		_cyl(b, pr - t * 1.6, pr + t * 1.6, 0.55, _mat("pontoon"))
		var post := Vector3(cos(a) * deck_r * 0.97, deck_y, sin(a) * deck_r * 0.83)
		_cyl(b, post, post + Vector3(0, 1.1, 0), 0.06, _mat("rust_dark"))
		var a2: float = TAU * (k + 1) / 14.0 + 0.1
		var post2 := Vector3(cos(a2) * deck_r * 0.97, deck_y, sin(a2) * deck_r * 0.83)
		_cyl(b, post + Vector3(0, 1.0, 0), post2 + Vector3(0, 0.95, 0), 0.025, _mat("trunk"))
	_shack(b, fut, Vector3(-5.0, deck_y, -4.0), 0.3, Vector3(6.0, 3.0, 4.5))
	_shack(b, fut, Vector3(6.5, deck_y, -1.5), -0.5, Vector3(3.6, 2.6, 3.2))
	# Deck crane and a fuel tank on cradles.
	var cr := Vector3(4.0, deck_y, 7.0)
	_cyl(b, cr, cr + Vector3(0, 4.0, 0), 0.45, _mat("rust"))
	_cyl(b, cr + Vector3(0, 4.0, 0), cr + Vector3(7.0, 7.0, 3.0), 0.2, _mat("rust"))
	_cyl(b, cr + Vector3(7.0, 7.0, 3.0), cr + Vector3(7.0, 1.0, 3.0), 0.02, _mat("rust_dark"))
	_cyl(b, Vector3(-9.0, deck_y + 1.1, 5.0), Vector3(-4.0, deck_y + 1.1, 7.0), 1.0, _mat("rust_red"))
	for e: float in [0.2, 0.8]:
		var cp: Vector3 = Vector3(-9.0, deck_y, 5.0).lerp(Vector3(-4.0, deck_y, 7.0), e)
		_box(b, cp + Vector3(0, 0.3, 0), Vector3(0.4, 0.6, 1.8), _mat("rust_dark"), Vector3(0, 22, 0))
	# Mooring lines to two buoys.
	var pts: Array[Transform3D] = []
	for k: int in 2:
		var a: float = 2.4 + k * 2.2
		var bp := Vector3(cos(a) * (deck_r + 12.0), SEA_Y - 0.3, sin(a) * (deck_r + 12.0))
		pts.append(Transform3D(Basis(Vector3.UP, a), bp))
		_cyl(b, Vector3(cos(a) * deck_r * 0.95, deck_y + 0.2, sin(a) * deck_r * 0.82), bp + Vector3(0, 0.8, 0), 0.03, _mat("trunk"))
	_scatter_models(["ocean_buoy"], pts, _groups["always"], 300.0)
	# Ruin: junk heaped on the deck, a collapsed net pile, drums.
	var heap: Array[Transform3D] = []
	for k: int in 46:
		var hp := Vector3(_rng.randf_range(-11, 11), deck_y, _rng.randf_range(-9, 9))
		if Vector2(hp.x + 5, hp.z + 4).length() < 4.0 or Vector2(hp.x - 6.5, hp.z + 1.5).length() < 2.5:
			continue
		heap.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5)), hp))
	_scatter_models(["Barrel_01", "old_tyre", "trashbag", "wooden_crate_02", "plastic_jerrycan", "metal_trash_can", "cardboard_box_01", "lifebuoy"], heap, _groups["ruin"], 200.0)
	for k: int in 4:
		ruin.add(_lumpy(k, 0.5, 2.0), _lxf(Vector3(_rng.randf_range(-10, 10), deck_y + 0.2, _rng.randf_range(-8, 8)), Vector3(0, _rng.randf() * 360, 0), Vector3(1.6, 0.4, 1.3)), _mat("rust_dark"))
	# Restored: planters, solar panels on the store, string lamps.
	for k: int in 5:
		_planter(grn, Vector3(_rng.randf_range(-10, 10), deck_y, _rng.randf_range(2, 10)), _rng.randf_range(0.8, 1.4))
	for k: int in 3:
		_box(grn, Vector3(6.5 + (k - 1) * 1.1, deck_y + 2.9, -1.5), Vector3(1.0, 0.05, 2.6), _mat("solar"), Vector3(14, -29, 0))
	for k: int in 10:
		var a: float = TAU * k / 10.0
		var lp := Vector3(cos(a) * deck_r * 0.97, deck_y + 1.15, sin(a) * deck_r * 0.83)
		var lamp := SphereMesh.new()
		lamp.radius = 0.07
		lamp.height = 0.14
		grn.add(lamp, _lxf(lp), _mat("lamp_warm"))
	# Future: a white canopy sail over the deck on slim masts.
	for k: int in 3:
		var a: float = TAU * k / 3.0
		_cyl(fut, Vector3(cos(a) * 9.0, deck_y, sin(a) * 8.0), Vector3(cos(a) * 9.0, deck_y + 6.5, sin(a) * 8.0), 0.12, _mat("white"))
	fut.add(_blob_slab(12, 0.12, 1.0, 3), _lxf(Vector3(0, deck_y + 6.6, 0), Vector3(4, 30, 0), Vector3(10.5, 0.08, 9.0)), _mat("white"))
	b.flush(_groups["always"])
	ruin.flush(_groups["ruin"])
	grn.flush(_groups["green"])
	fut.flush(_groups["future"])


## The stilt yard ([p_seas] kit): a sandy islet with a plank deck on braced timber piles out over the
## water, two huts on it, a boardwalk with rope rails to the beach, a net-drying rack, a beached
## skiff, crates and a lamp post. Ruined: junk banks on the beach, snags; restored: mangroves, palms.
func _site_stilts() -> void:
	var a: KitMesh.Builder = TideProps.builder(self, "always")
	var ruin: KitMesh.Builder = TideProps.builder(self, "ruin")
	var grn: KitMesh.Builder = TideProps.builder(self, "green")
	var fut: KitMesh.Builder = TideProps.builder(self, "future")
	var nat := FrontierView.Batch.new()
	var nat_ruin := FrontierView.Batch.new()
	var nat_grn := FrontierView.Batch.new()
	var deck_y: float = 1.9
	var deck_c := Vector3(-14.0, 0, -10.0)
	var bs := Basis(Vector3.UP, 0.6)
	var sx: float = 15.0
	var sz: float = 11.0
	_decks.append(Vector3(deck_c.x, deck_c.z, 11.0))
	# Plank deck in two tones over joists, a rim beam, steel corner plates.
	var x: float = -sx * 0.5 + 0.3
	var i: int = 0
	while x < sx * 0.5 - 0.35:
		var z: float = -sz * 0.5 + 0.3
		while z < sz * 0.5 - 0.35:
			var ln: float = minf(_rng.randf_range(2.2, 4.2), sz * 0.5 - 0.3 - z)
			TideProps.box(a, deck_c, bs, Vector3(x + 0.25, deck_y - 0.07, z + ln * 0.5), Vector3(0.45, 0.14, ln - 0.05), TideProps.m(self, "timber" if (i + int(z)) % 3 != 0 else "timber2"), Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4)), 0.035)
			z += ln
		x += 0.5
		i += 1
	for sd: float in [-1.0, 1.0]:
		TideProps.side_wall(a, deck_c, bs, Vector3(0, deck_y - 0.55, sd * (sz * 0.5 - 0.05)), Vector3(0, 0, sd), sx, 0.5, TideProps.m(self, "timber2"), {"panel": Vector2(2.0, 0.5), "depth": 0.1})
		TideProps.side_wall(a, deck_c, bs, Vector3(sd * (sx * 0.5 - 0.05), deck_y - 0.55, 0), Vector3(sd, 0, 0), sz, 0.5, TideProps.m(self, "timber2"), {"panel": Vector2(2.0, 0.5), "depth": 0.1})
	# Piles with cross bracing under the deck.
	for px: int in 5:
		for pz: int in 4:
			var pp := Vector3(-sx * 0.5 + 0.6 + px * (sx - 1.2) / 4.0, 0, -sz * 0.5 + 0.6 + pz * (sz - 1.2) / 3.0)
			TideProps.pipe(a, deck_c, bs, pp + Vector3(0, -2.5, 0), pp + Vector3(0, deck_y - 0.3, 0), 0.2, TideProps.m(self, "timber2"), 10)
			if px < 4:
				var q := Vector3(-sx * 0.5 + 0.6 + (px + 1) * (sx - 1.2) / 4.0, 0, pp.z)
				TideProps.pipe(a, deck_c, bs, pp + Vector3(0, -0.2, 0), q + Vector3(0, deck_y - 0.5, 0), 0.07, TideProps.m(self, "timber2"), 6)
	TideProps.solid_box(_groups["always"], deck_c, bs, Vector3(0, deck_y - 0.6, 0), Vector3(sx, 1.2, sz), Vector3.ZERO, PhysLayers.WORLD)
	for k: int in 6:
		TideProps.solid_cyl(_groups["always"], deck_c, bs, Vector3(-sx * 0.5 + 0.6 + (k % 3) * (sx - 1.2) / 2.0, -2.5, -sz * 0.5 + 0.6 + (k / 3) * (sz - 1.2)), Vector3(-sx * 0.5 + 0.6 + (k % 3) * (sx - 1.2) / 2.0, deck_y - 1.2, -sz * 0.5 + 0.6 + (k / 3) * (sz - 1.2)), 0.3)
	TideProps.rail(a, deck_c, bs, [Vector3(-sx * 0.5 + 0.2, deck_y, sz * 0.5 - 0.2), Vector3(-sx * 0.5 + 0.2, deck_y, -sz * 0.5 + 0.2), Vector3(sx * 0.5 - 0.2, deck_y, -sz * 0.5 + 0.2)] as Array[Vector3], 1.0, TideProps.m(self, "ledger"))
	# Huts on the deck.
	TideProps.shack(self, a, grn, fut, deck_c + bs * Vector3(-3.0, deck_y, -1.5), 0.6, Vector3(5.0, 2.7, 3.8), "cream", "teal")
	TideProps.shack(self, a, grn, fut, deck_c + bs * Vector3(3.6, deck_y, -2.2), 0.6, Vector3(3.4, 2.5, 3.0), "orange", "cream")
	# Boardwalk from the deck to the beach, with posts and a rope rail.
	var w0: Vector3 = deck_c + bs * Vector3(sx * 0.5, deck_y, sz * 0.3)
	var w1 := Vector3(-2.0, 1.4, 0.0)
	var n: int = int(w0.distance_to(w1) / 0.42)
	var wyaw: float = atan2(w1.x - w0.x, w1.z - w0.z)
	var wb := Basis(Vector3.UP, wyaw)
	for k: int in n:
		var pp: Vector3 = w0.lerp(w1, (k + 0.5) / n)
		TideProps.box(a, pp, wb, Vector3(0, -0.05, 0), Vector3(1.6, 0.1, 0.38), TideProps.m(self, "timber" if k % 4 else "timber2"), Vector3(0, 0, _rng.randf_range(-2, 2)), 0.03)
		if k % 5 == 0:
			for sd: float in [-0.8, 0.8]:
				TideProps.pipe(a, pp, wb, Vector3(sd, -2.0, 0), Vector3(sd, 1.0, 0), 0.09, TideProps.m(self, "timber2"), 6)
	for sd: float in [-0.8, 0.8]:
		a.rod(TideProps.m(self, "rope_line"), w0 + wb * Vector3(sd, 0.95, 0), w1 + wb * Vector3(sd, 0.95, 0), 0.025, 5)
	var wz: Vector3 = (w1 - w0).normalized()
	var wx: Vector3 = Vector3.UP.cross(wz).normalized()
	TideProps.solid_box(_groups["always"], (w0 + w1) * 0.5, Basis(wx, wz.cross(wx), wz), Vector3(0, -0.25, 0), Vector3(1.6, 0.4, w0.distance_to(w1)), Vector3.ZERO, PhysLayers.WORLD)
	# Beach: rocks (natural), a beached skiff, a net rack, crates, a lamp post.
	var c: Vector2 = islands[0]["c"]
	var rock_mat: StandardMaterial3D = AssetLib.pbr_material("dry_ground_rocks", 0.45, Color(0.7, 0.68, 0.62), true)
	rock_mat.metallic = 0.0
	for k: int in 16:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(16.0, 26.0)
		var p := Vector3(c.x + cos(ang) * d * 1.3, 0, c.y + sin(ang) * d * 0.8)
		p.y = bed_at(p.x, p.z).x - 0.2
		var s: float = _rng.randf_range(0.6, 1.8)
		nat.add(_lumpy(k % 5, 0.42), _lxf(p, Vector3(_rng.randf() * 30, _rng.randf() * 360, 0), Vector3(s * 1.3, s * 0.6, s)), rock_mat)
	var skiff := Vector3(c.x + 13.0, 0, c.y + 11.0)
	skiff.y = bed_at(skiff.x, skiff.z).x + 0.1
	TideProps.add_mesh(a, TideProps.m(self, "accent"), TideProps.hull_mesh(5.0, 1.8, 0.9, 0.35, 1.3, 0.15), Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, 0.18), skiff), 0)
	TideProps.add_mesh(a, TideProps.m(self, "red"), TideProps.hull_mesh(5.0, 1.8, 0.9, 0.35, 1.3, 0.15), Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, 0.18), skiff), 1)
	TideProps.solid_box(_groups["always"], skiff, Basis(Vector3.UP, 0.9), Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 5.0))
	var rack := Vector3(c.x - 4.0, 0, c.y + 6.0)
	rack.y = bed_at(rack.x, rack.z).x
	for sd: float in [-2.0, 2.0]:
		a.rod(TideProps.m(self, "timber2"), rack + Vector3(sd, -0.3, 0), rack + Vector3(sd, 2.2, 0), 0.08, 6)
	a.rod(TideProps.m(self, "timber2"), rack + Vector3(-2.2, 2.1, 0), rack + Vector3(2.2, 2.1, 0), 0.06, 6)
	TideProps.box(a, rack, Basis(), Vector3(0, 1.3, 0), Vector3(3.8, 1.5, 0.05), TideProps.m(self, "rope"), Vector3(0, 0, 0), 0.01)
	for k: int in 4:
		var cp := Vector3(c.x + _rng.randf_range(-6, 6), 0, c.y + _rng.randf_range(-3, 4))
		cp.y = bed_at(cp.x, cp.z).x
		if cp.y > SEA_Y:
			KitProps.crate_stack(a, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), cp), 3, a.state)
	var lp := Vector3(c.x - 1.0, 0, c.y - 1.0)
	lp.y = bed_at(lp.x, lp.z).x
	KitProps.lamp_post(grn, Transform3D(Basis(), lp), 4.0, "restored", "warm")
	grn.lights.append({"pos": lp + Vector3(0, 3.8, 0), "color": KitMat.GLOW["warm"], "range": 8.0, "energy": 1.4})
	# Ruined: junk banks; restored: mangroves and palms (natural meshes).
	var heap: Array[Transform3D] = []
	for k: int in 70:
		var ang: float = _rng.randf() * TAU
		var d: float = _rng.randf_range(4.0, 24.0)
		var p := Vector3(c.x + cos(ang) * d * 1.3, 0, c.y + sin(ang) * d * 0.7)
		p.y = bed_at(p.x, p.z).x
		if p.y > SEA_Y:
			heap.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.6, 0.6)), p))
	_scatter_models(["Barrel_01", "old_tyre", "trashbag", "plastic_jerrycan", "lifebuoy", "wooden_crate_02", "rubber_boots", "plastic_bottle_gallon"], heap, _groups["ruin"], 200.0)
	var trunk_m: Material = _mat("trunk")
	for k: int in 26:
		var ang: float = TAU * k / 26.0
		var p := Vector3(c.x + cos(ang) * 21.0 * 1.25, 0, c.y + sin(ang) * 21.0 * 0.75)
		var gy: float = bed_at(p.x, p.z).x
		if gy < -0.6 or gy > 2.0 or _on_deck(p):
			continue
		p.y = maxf(gy, SEA_Y - 0.4)
		_mangrove(nat_grn, p, _rng.randf_range(0.8, 1.3), trunk_m, _mat("mangrove"))
	for k: int in 6:
		var p := Vector3(c.x + _rng.randf_range(-8, 8), 0, c.y + _rng.randf_range(-5, 5))
		p.y = bed_at(p.x, p.z).x
		if p.y > 0.8:
			_palm(nat_grn, p, _rng.randf_range(5.0, 8.0), trunk_m, _mat("leaf"))
			_snag(nat_ruin, p, _mat("driftwood"))
	TideProps.flush(self, a, "always")
	TideProps.flush(self, ruin, "ruin")
	TideProps.flush(self, grn, "green")
	TideProps.flush(self, fut, "future")
	nat.flush(_groups["always"])
	nat_ruin.flush(_groups["ruin"])
	nat_grn.flush(_groups["green"])


# --- Landmarks -----------------------------------------------------------------------------------

## A reef garden ([p_seas] art pass): coral heads breaking the surface round a sandbar. Every head
## is a cluster: branching staghorn coral, a brain dome, a table plate on a stalk, tube sponges.
## Ruined: the same shapes bleached bone-white among ghost nets; restored: living colours, and
## floating garden rafts (pontoon decks with kit planters) moored round the reef.
func _site_reef() -> void:
	var ruin: KitMesh.Builder = TideProps.builder(self, "ruin")
	var grn: KitMesh.Builder = TideProps.builder(self, "green")
	var live: Array[String] = ["paint:#f2785a", "paint:#ffb347", "paint:#c46bd6", "paint:#4fc3b0", "paint:#f25c8a", "paint:#ffd166"]
	for k: int in 22:
		var a: float = _rng.randf() * TAU
		var d: float = sqrt(_rng.randf()) * 24.0
		var p := Vector3(cos(a) * d * 1.3, SEA_Y - _rng.randf_range(0.25, 0.55), sin(a) * d)
		var s: float = _rng.randf_range(1.0, 1.8)
		var c1: String = live[k % live.size()]
		var c2: String = live[(k * 3 + 1) % live.size()]
		for b: Array in [[ruin, "paint:#e9e3d3", "paint:#d8d0bf"], [grn, c1, c2]]:
			_coral_head(b[0], p, s, str(b[1]), str(b[2]), k)
	# Floating garden rafts round the reef (restored).
	for k: int in 5:
		var a: float = TAU * k / 5.0 + 0.3
		var gp := Vector3(cos(a) * 31.0, SEA_Y, sin(a) * 27.0)
		_decks.append(Vector3(gp.x, gp.z, 3.5))
		var t := Transform3D(Basis(Vector3.UP, a + PI * 0.5), gp)
		for sd: float in [-1.0, 1.0]:
			grn.add("paint:orange", KitMesh.bevel_cylinder(0.42, 4.2, 0.1, 14), t * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(2.1, 0.05, sd * 1.1)))
		grn.box("paint:" + TideProps.TIMBER, Vector3(4.6, 0.14, 3.0), t * KitMesh.xf(Vector3(0, 0.5, 0)), 0.04)
		KitProps.planter(grn, t * KitMesh.xf(Vector3(0, 0.57, -0.5)), 3.2, "restored")
		KitProps.planter(grn, t * KitMesh.xf(Vector3(0, 0.57, 0.7)), 2.4, "restored")
	TideProps.flush(self, ruin, "ruin")
	TideProps.flush(self, grn, "green")


## One coral head at p (crest about at sea level), scale s, two colours.
func _coral_head(b: KitMesh.Builder, p: Vector3, s: float, c1: String, c2: String, k: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + k  # same shape ruined and restored
	# Rock base and a brain dome.
	TideProps.add_mesh(b, c2, _lumpy(k % 5, 0.35, 2.4), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.6, 0.7, 1.3) * s), p))
	TideProps.add_mesh(b, c1, _lumpy((k + 2) % 5, 0.12, 6.0), Transform3D(Basis().scaled(Vector3(0.8, 0.55, 0.8) * s), p + Vector3(rng.randf_range(-0.6, 0.6), 0.5 * s, rng.randf_range(-0.6, 0.6))))
	# Staghorn: forking rods with rounded tips.
	for br: int in 3:
		var base: Vector3 = p + Vector3(rng.randf_range(-0.9, 0.9), 0.4 * s, rng.randf_range(-0.9, 0.9)) * s
		var dir := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()
		_branch(b, base, dir, 0.9 * s, 0.13 * s, 3, rng, c1)
	# Table coral on a stalk, tube sponges.
	if k % 3 == 0:
		var tp: Vector3 = p + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2)) * s
		b.rod(c2, tp, tp + Vector3(0, 0.9 * s, 0), 0.12 * s, 8)
		b.add(c2, KitMesh.bevel_cylinder(1.1 * s, 0.14 * s, 0.05, 18), Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12)), tp + Vector3(0, 0.9 * s, 0)))
	for t: int in 3:
		var sp: Vector3 = p + Vector3(rng.randf_range(-1.3, 1.3), 0.2 * s, rng.randf_range(-1.3, 1.3)) * s
		var h: float = rng.randf_range(0.5, 1.0) * s
		b.add(c1 if t % 2 else c2, KitMesh.bevel_cylinder(0.14 * s, h, 0.04, 10), Transform3D(Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)), sp))
		b.add("dark_steel", KitMesh.bevel_cylinder(0.09 * s, 0.04, 0.01, 10), Transform3D(Basis(), sp + Vector3(0, h - 0.01, 0)))


func _branch(b: KitMesh.Builder, a: Vector3, dir: Vector3, ln: float, r: float, depth: int, rng: RandomNumberGenerator, key: String) -> void:
	var c: Vector3 = a + dir * ln
	b.rod(key, a, c, r, 6)
	b.add(key, KitMesh.pebble(depth % 4), Transform3D(Basis().scaled(Vector3.ONE * r * 1.1), c))
	if depth <= 0:
		return
	for f: int in 2:
		var nd := (dir + Vector3(rng.randf_range(-0.7, 0.7), 0.25, rng.randf_range(-0.7, 0.7))).normalized()
		_branch(b, c, nd, ln * 0.7, r * 0.75, depth - 1, rng, key)


## A buoy field ([p_seas] kit): rows of navigation buoys (lathe floats in red / white / yellow,
## cage towers with topmarks and radar reflectors) strung with sagging mooring ropes. Ruined:
## ghost nets and junk snag the lines, the lamps are dark; restored: lit lanterns; futuristic:
## thin cool light caps.
func _site_buoys() -> void:
	var a: KitMesh.Builder = TideProps.builder(self, "always")
	var grn: KitMesh.Builder = TideProps.builder(self, "green")
	var fut: KitMesh.Builder = TideProps.builder(self, "future")
	var pos: Array[Vector3] = []
	var cols: Array[String] = ["paint:red", "paint:white", "paint:" + TideProps.LEDGER, "paint:accent"]
	for i: int in 5:
		for j: int in 4:
			var p := Vector3((i - 2) * 11.0 + _rng.randf_range(-2, 2), SEA_Y, (j - 1.5) * 11.0 + _rng.randf_range(-2, 2))
			pos.append(p)
			var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12)), p + Vector3(0, -0.5, 0))
			var col: String = cols[(i + j) % cols.size()]
			a.add(col, KitMesh.lathe(PackedVector3Array([Vector3(0, -0.4, 0), Vector3(0.7, -0.3, 1), Vector3(0.95, 0.2, 1), Vector3(0.95, 0.75, 1), Vector3(0.6, 1.0, 1), Vector3(0, 1.0, 0)]), 16), t)
			a.add("paint:white" if col != "paint:white" else "paint:red", KitMesh.lathe(PackedVector3Array([Vector3(0, 0.35, 0), Vector3(0.97, 0.35, 1), Vector3(0.97, 0.6, 1), Vector3(0, 0.6, 0)]), 16), t)
			for k: int in 3:
				var ang: float = TAU * k / 3.0
				a.rod("dark_steel", t * Vector3(cos(ang) * 0.45, 1.0, sin(ang) * 0.45), t * Vector3(cos(ang) * 0.18, 2.6, sin(ang) * 0.18), 0.04, 5)
			a.add("dark_steel", KitMesh.bevel_cylinder(0.4, 0.06, 0.02, 12), t * Transform3D(Basis(), Vector3(0, 1.8, 0)))
			a.add(col, KitMesh.lathe(PackedVector3Array([Vector3(0, 0, 0), Vector3(0.28, 0, 1), Vector3(0, 0.45, 1)]), 10), t * Transform3D(Basis(), Vector3(0, 2.75, 0)))
			a.box("steel", Vector3(0.3, 0.3, 0.3), t * Transform3D(Basis.from_euler(Vector3(0.6, 0.6, 0)), Vector3(0, 2.2, 0)), 0.02)
			grn.add("trim:warm", KitMesh.bevel_cylinder(0.12, 0.18, 0.02, 10), t * Transform3D(Basis(), Vector3(0, 2.58, 0)))
			fut.add("trim:cool", KitMesh.bevel_cylinder(0.32, 0.03, 0.01, 14), t * Transform3D(Basis(), Vector3(0, 0.62, 0)))
			TideProps.solid_cyl(_groups["always"], p, Basis(), Vector3(0, -1.0, 0), Vector3(0, 1.0, 0), 1.0)
			_decks.append(Vector3(p.x, p.z, 1.6))
	if grn.lights.is_empty():
		for k: int in mini(pos.size(), 10):
			grn.lights.append({"pos": pos[k * 2 % pos.size()] + Vector3(0, 2.2, 0), "color": KitMat.GLOW["warm"], "range": 6.0, "energy": 1.0})
	# Sagging mooring ropes along the rows.
	for i: int in pos.size():
		if i % 4 != 3:
			var q: Vector3 = pos[i + 1]
			KitProps.cable(a, Transform3D.IDENTITY, pos[i] + Vector3(0, 0.6, 0), q + Vector3(0, 0.6, 0), 0.7, 0.035)
	TideProps.flush(self, a, "always")
	TideProps.flush(self, grn, "green")
	TideProps.flush(self, fut, "future")
