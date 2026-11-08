class_name OchreSites
extends RefCounted
## [planet-ochre] Ochre's hub sites as placeable prefabs for the walkable globes. Each builds a
## compact local scene (about 60-100 m across) on a locally flat patch under `root`: local +Y is up,
## the origin is the site centre, nothing assumes a world origin, horizon or far terrain.
##   OchreSites.build(id, root, stage, restoration) -> Node3D
##     id           "hub_base" | "toppled_excavator" | "pit_fragment" | "oasis" (data/planets.json ochre.sites)
##     stage        base level 1..5: 1 ruined, 2-3 fixed up, 4-5 futuristic
##     restoration  0..1: how far the site's ground is restored (junk clears, plants and crops spread)
## Rebuild (free the returned node, call build again) when stage or restoration changes much.
## Fully trashed while ruined: tailings, crates, drill scrap and boulders over the whole patch.

const SITES: Array[String] = ["hub_base", "toppled_excavator", "pit_fragment", "oasis"]

static var _mats: Dictionary = {}


static func build(id: String, root: Node3D, stage: int, restoration: float) -> Node3D:
	var site := Node3D.new()
	site.name = "OchreSite_" + id
	root.add_child(site)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + stage * 31
	var st: int = clampi(stage, 1, 5)
	var r: float = clampf(restoration, 0.0, 1.0)
	var tmat: ShaderMaterial = terrain_mat(r, st)
	match id:
		"hub_base":
			_ground(site, tmat, 46.0, 0.0, rng)
			_hub_base(site, st, r, rng)
			_scatter(site, 44.0, 17.0, st, r, rng, 1100)
		"toppled_excavator":
			_ground(site, tmat, 48.0, 0.0, rng)
			_toppled(site, st, r, rng)
			_scatter(site, 46.0, 4.0, st, r, rng, 1100)
		"pit_fragment":
			_pit(site, tmat, st, r, rng)
		"oasis":
			_ground(site, tmat, 40.0, 1.0, rng)
			_oasis(site, st, r, rng)
			_scatter(site, 38.0, 17.0, st, r, rng, 800)
		_:
			push_warning("OchreSites: unknown site %s" % id)
	return site


# --- Materials (static, shared by every site) -------------------------------------------------------

static func _pal(key: String, fb: Color) -> Color:
	var a: Variant = (PlanetEnvs.entry("ochre").get("palette", {}) as Dictionary).get(key, [])
	if a is Array and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fb


## The Ochre terrain material for one site (its own restore / stage uniforms).
static func terrain_mat(restore: float, stage: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://planet/planets/ochre/ochre_terrain.gdshader")
	for pair: Array in [["tex_wall", "quarry_wall", "diff"], ["nrm_wall", "quarry_wall", "nor_gl"], ["tex_bench", "red_laterite_soil_stones", "diff"],
			["nrm_bench", "red_laterite_soil_stones", "nor_gl"], ["tex_sand", "sand_01", "diff"], ["tex_crack", "mud_cracked_dry_03", "diff"],
			["tex_leaf", "leafy_grass", "diff"], ["tex_soil", "farm_soil", "diff"]]:
		m.set_shader_parameter(pair[0], AssetLib.tex(pair[1], pair[2]))
	for k: String in ["ochre", "terracotta", "cream", "plum", "salt", "line"]:
		var u: String = {"ochre": "c_ochre", "terracotta": "c_terra", "cream": "c_cream", "plum": "c_plum", "salt": "c_salt", "line": "c_line"}[k]
		var c: Color = _pal(k, Color.WHITE)
		m.set_shader_parameter(u, Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("restore", restore)
	m.set_shader_parameter("stage", float(stage))
	# Salt crust reads as crust, not a white glare (it was overbright under the closest suns).
	m.set_shader_parameter("c_salt", Vector3(0.74, 0.7, 0.62))
	return m


static func mat(key: String) -> Material:
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
		"rust_wall":
			m = Mats.worn_paint(Color(0.55, 0.42, 0.3), 0.35, 0.95, 7.0, 0.9)
		"wall_mid":
			m = Mats.worn_paint(_pal("cream", Color(0.9, 0.8, 0.62)).darkened(0.05), 0.9, 0.2, 7.0, 0.4)
		"corr_ruin":
			m = AssetLib.pbr_material("rusted_shutter", 0.3, Color(0.85, 0.7, 0.6), true)
		"corr":
			m = AssetLib.pbr_material("corrugated_iron", 0.3, Color(0.95, 0.9, 0.82), true)
		"steel":
			m = Mats.metal("steel")
		"dark":
			m = Mats.metal("dark_steel")
		"glass":
			m = Mats.glass(Color(0.08, 0.1, 0.12, 0.95), 0.08)
		"glass_broken":
			m = Mats.glass(Color(0.1, 0.1, 0.1, 0.35), 0.6)
		"concrete":
			m = AssetLib.pbr_material("concrete_wall_008", 0.25, Color(0.85, 0.78, 0.68), true)
		"slab":
			m = AssetLib.pbr_material("dirty_concrete", 0.2, Color(0.9, 0.8, 0.7), true)
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
		"panel":
			var p := StandardMaterial3D.new()
			p.albedo_color = Color(0.06, 0.08, 0.17)
			p.metallic = 0.5
			p.roughness = 0.15
			m = p
		"vane":
			m = sail_mat(_pal("cream", Color(0.9, 0.8, 0.62)).lightened(0.25), 0.0, 0.0, 0.0)
		"rubber":
			m = Mats.rubber()
		"water":
			var wm := ShaderMaterial.new()
			wm.shader = preload("res://planet/planets/ochre/ochre_water.gdshader")
			var oa: Color = _pal("oasis", Color(0.1, 0.55, 0.54))
			wm.set_shader_parameter("oasis_deep", Vector3(oa.r, oa.g, oa.b) * 0.45)
			wm.set_shader_parameter("oasis_shallow", Vector3(oa.r, oa.g, oa.b) * 1.3 + Vector3(0.1, 0.1, 0.1))
			m = wm
		_:
			m = StandardMaterial3D.new()
	_mats[key] = m
	return m


static func sail_mat(cloth: Color, solar: float, wear: float, line: float) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://planet/planets/ochre/ochre_sail.gdshader")
	sm.set_shader_parameter("cloth", Vector3(cloth.r, cloth.g, cloth.b))
	sm.set_shader_parameter("solar", solar)
	sm.set_shader_parameter("wear", wear)
	sm.set_shader_parameter("line_amt", line)
	var lc: Color = _pal("line", Color(0.78, 0.94, 1.0))
	sm.set_shader_parameter("line_col", Vector3(lc.r, lc.g, lc.b))
	return sm


static func machine_mats(stage: int) -> Dictionary:
	var d: Dictionary = {}
	for k: String in ["steel", "dark", "glass", "concrete", "terra", "cream", "leaf", "line", "vane"]:
		d[k] = mat(k)
	d["paint"] = mat("paint_ruin" if stage <= 1 else ("paint_mid" if stage <= 3 else "paint_future"))
	return d


static func _paint(stage: int) -> Material:
	return mat("paint_ruin" if stage <= 1 else ("paint_mid" if stage <= 3 else "paint_future"))


# --- Ground and scatter -----------------------------------------------------------------------------------

## A round ground patch (terrain material): flat in the middle, low wind-built drifts and ripples
## toward the rim, which tucks a little below 0 so it melts into whatever surrounds it.
## in_mine: 1 = the mine's red gravel and salt crust (crops when restored), 0 = ochre sand.
static func _ground(site: Node3D, tmat: ShaderMaterial, radius: float, in_mine: float, rng: RandomNumberGenerator) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.05
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 26
	var spokes: int = 72
	for j: int in spokes + 1:
		var a: float = TAU * float(j % spokes) / spokes
		for i: int in rings + 1:
			var f: float = float(i) / rings
			var rr: float = radius * f * (1.0 + 0.08 * nz.get_noise_1d(a * 30.0) * f)
			var p := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			var drift: float = (nz.get_noise_2d(p.x, p.z) * 0.5 + 0.5) * 0.9 * smoothstep(0.45, 0.85, f)
			var ripple: float = sin((p.x * 0.8 + p.z * 0.6) * 0.9 + nz.get_noise_2d(p.x * 3.0, p.z * 3.0) * 3.0) * 0.06 * smoothstep(0.3, 0.6, f)
			p.y = drift + ripple - 0.6 * smoothstep(0.85, 1.0, f)
			st.set_color(Color(0.0 if in_mine > 0.5 else 0.3, 1.0, 0.5, in_mine))
			st.set_uv(Vector2(a * rr, rr))
			st.add_vertex(p)
	for j: int in spokes:
		for i: int in rings:
			var a0: int = j * (rings + 1) + i
			var b0: int = (j + 1) * (rings + 1) + i
			for idx: int in [a0, a0 + 1, b0, b0, a0 + 1, b0 + 1]:
				st.add_index(idx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	mi.material_override = tmat
	site.add_child(mi)


## Junk, scrap and boulders over the whole patch (fully trashed at restoration 0, clearing as it
## rises), and palms / succulents taking their place. Keeps clear of a central radius.
static func _scatter(site: Node3D, radius: float, clear_r: float, stage: int, restore: float, rng: RandomNumberGenerator, n_junk: int) -> void:
	var junk: Dictionary = OchreProps.junk_meshes()
	var ids: Array = junk.keys()
	var lists: Dictionary = {}
	var keep: int = int(float(n_junk) * (1.0 - restore) * (1.0 if stage <= 1 else 0.55))
	for i: int in keep:
		var a: float = rng.randf() * TAU
		var d: float = lerpf(clear_r, radius * 0.97, sqrt(rng.randf()))
		var id: String = ids[0] if rng.randf() < 0.3 else ids[rng.randi() % ids.size()]
		var big: float = rng.randf_range(1.0, 2.4) if str(id).begins_with("ochre_tailings") else rng.randf_range(0.9, 1.4)
		if rng.randf() < 0.05:
			id = ids[0]
			big = rng.randf_range(4.0, 9.0)
		var lie: Basis = Basis(Vector3.FORWARD, PI * 0.5) if id == "ochre_drill_rod" else Basis()
		if not lists.has(id):
			lists[id] = []
		(lists[id] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * lie * Basis.from_scale(Vector3(big, big * (0.6 if big > 3.0 else 1.0), big)), Vector3(cos(a) * d, -0.05, sin(a) * d)))
	for id: String in lists:
		_mm(site, junk[id], lists[id], 300.0, false)
	# Boulders stay (natural); a ring of them where the patch meets the land.
	var rocks: Array = [[], [], []]
	for i: int in 90:
		var a: float = rng.randf() * TAU
		var d: float = radius * lerpf(0.55, 1.0, sqrt(rng.randf()))
		var s: float = pow(rng.randf(), 2.0) * 2.6 + 0.4
		(rocks[i % 3] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * s), Vector3(cos(a) * d, -s * 0.15, sin(a) * d)))
	for k: int in 3:
		_mm(site, OchreProps.boulder(k + 1), rocks[k], 500.0, true, _pal(["ochre", "terracotta", "cream"][k], Color(0.8, 0.5, 0.3)).lerp(Color(0.8, 0.6, 0.42), 0.25))
	_plants(site, radius, clear_r, restore, rng)


static func _plants(site: Node3D, radius: float, clear_r: float, restore: float, rng: RandomNumberGenerator) -> void:
	if restore < 0.05:
		return
	var kinds: Array = [[OchreProps.palm(1), 0.18], [OchreProps.palm(2), 0.18], [OchreProps.agave(1), 0.25], [OchreProps.agave(2), 0.15], [OchreProps.aloe(1), 0.12], [OchreProps.barrel_cactus(), 0.12]]
	var lists: Array = []
	for k: Array in kinds:
		lists.append([])
	var n: int = int(220.0 * restore)
	for i: int in n:
		var a: float = rng.randf() * TAU
		var d: float = lerpf(clear_r + 1.0, radius * 0.95, sqrt(rng.randf()))
		var r: float = rng.randf()
		var k: int = 0
		var acc: float = 0.0
		for j: int in kinds.size():
			acc += float(kinds[j][1])
			if r <= acc:
				k = j
				break
		var s: float = rng.randf_range(0.8, 1.25) * (1.0 if k < 2 else 1.4)
		(lists[k] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * s), Vector3(cos(a) * d, -0.05, sin(a) * d)))
	for k: int in kinds.size():
		_mm(site, kinds[k][0], lists[k], 400.0, k < 2)


static func _mm(site: Node3D, mesh: Mesh, xfs: Array, vis: float, shadows: bool, tint: Color = Color(-1, 0, 0)) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tint.r >= 0.0
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, tint)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.visibility_range_end = vis
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	site.add_child(mmi)


# --- Kit helpers (art/kit, Moon Sweepers bar) -------------------------------------------------------------

## Ochre's kit palette: sand-white shells, oxide-red accents, ledger-yellow rails.
const KIT_PALETTE: Dictionary = {"main": "#ece2d0", "accent": "#b8452a", "pipe": "orange", "rail": "yellow", "pole": "slate",
	"crate": "#c8743a", "barrel": "red", "broken_main": "#8a7a64", "broken_accent": "#5e3426", "flower_a": "#e86a3a", "flower_b": "#f2d8a0"}


static func kit_state(stage: int) -> String:
	return "broken" if stage <= 1 else ("repaired" if stage <= 3 else "restored")


## A ready-made kit building (with its own plates, clutter and lamps), lit from stage 2.
static func _kb(site: Node3D, kind: String, pos: Vector3, yaw_deg: float, stage: int, seed_v: int) -> KitBuilding:
	var k: KitBuilding = KitBuilding.create(kind, kit_state(stage), seed_v, KIT_PALETTE, stage >= 2)
	k.position = pos
	k.rotation_degrees.y = yaw_deg
	site.add_child(k)
	return k


## Commits a site builder into a MeshInstance3D and adds its prop lights when powered.
static func _kit_commit(site: Node3D, b: KitMesh.Builder, stage: int, name_: String) -> void:
	var mi: MeshInstance3D = KitMesh.instance(b, kit_state(stage), stage >= 2)
	mi.name = name_
	site.add_child(mi)
	if stage >= 2:
		for l: Dictionary in b.lights:
			var o := OmniLight3D.new()
			o.position = l["pos"]
			o.light_color = l["color"]
			o.omni_range = float(l["range"])
			o.light_energy = float(l["energy"])
			o.shadow_enabled = false
			site.add_child(o)


static func _plates(site: Node3D, size: Vector2, pos: Vector3, yaw_deg: float, stage: int, seed_v: int) -> void:
	var g: Node3D = KitMesh.ground_patch(size, kit_state(stage), seed_v, {"palette": KIT_PALETTE})
	g.position = pos
	g.rotation_degrees.y = yaw_deg
	site.add_child(g)


## The Ledger ore silo in kit parts: bevelled drum on a braced frame, ribs, a cone hopper, a
## caged ladder, a conveyor gallery to the yard, hazard bands, a label decal. Broken: rust
## patches, the gallery fallen, the roof cap missing.
static func ore_silo(b: KitMesh.Builder, t: Transform3D, stage: int) -> void:
	var broken: bool = stage <= 1
	var X := func(p: Vector3, r: Vector3 = Vector3.ZERO) -> Transform3D: return t * KitMesh.xf(p, r)
	b.add("concrete", KitMesh.bevel_cylinder(5.0, 0.7, 0.12, 12), X.call(Vector3.ZERO))
	for x: float in [-2.7, 2.7]:
		for z: float in [-2.7, 2.7]:
			b.box("dark_steel", Vector3(0.45, 6.2, 0.45), X.call(Vector3(x, 3.8, z)))
			b.box("concrete", Vector3(0.9, 0.5, 0.9), X.call(Vector3(x, 0.95, z)))
	for z: float in [-2.7, 2.7]:
		b.rod("dark_steel", t * Vector3(-2.7, 1.2, z), t * Vector3(2.7, 6.4, z), 0.09)
		b.rod("dark_steel", t * Vector3(z, 1.2, -2.7), t * Vector3(z, 6.4, 2.7), 0.09)
	b.add("paint:main" if not broken else "rusty", KitMesh.lathe(PackedVector3Array([Vector3(0.7, 0, 0), Vector3(4.2, 3.8, 1), Vector3(4.2, 4.0, 1)]), 24), X.call(Vector3(0, 3.2, 0)))
	b.add("paint:main", KitMesh.bevel_cylinder(4.2, 10.0, 0.12, 28), X.call(Vector3(0, 7.2, 0)))
	for k: int in 5:
		b.add("paint:accent" if k % 2 == 0 else "dark_steel", KitMesh.bevel_cylinder(4.32, 0.28, 0.06, 28), X.call(Vector3(0, 7.6 + k * 2.2, 0)))
	for k: int in 12:
		var a: float = TAU * k / 12.0
		b.box("dark_steel", Vector3(0.16, 9.6, 0.16), X.call(Vector3(cos(a) * 4.24, 12.2, sin(a) * 4.24), Vector3(0, -rad_to_deg(a), 0)))
	b.add("hazard", KitMesh.bevel_cylinder(4.25, 0.35, 0.04, 28), X.call(Vector3(0, 7.25, 0)))
	if not broken:
		b.add("paint:accent", KitMesh.lathe(PackedVector3Array([Vector3(4.4, 0, 0), Vector3(4.4, 0.3, 1), Vector3(1.0, 1.9, 1), Vector3(0.6, 2.1, 0)]), 28), X.call(Vector3(0, 17.2, 0)))
		KitProps.vent(b, X.call(Vector3(0, 19.3, 0.6), Vector3(-90, 0, 0)), Vector2(0.9, 0.6))
	KitProps.ladder(b, X.call(Vector3(0, 0.7, 4.35)), 16.4)
	for k: int in 6:
		b.rod("paint:rail", t * Vector3(-0.5, 3.0 + k * 2.6, 4.35), t * Vector3(-0.5, 3.0 + k * 2.6, 5.0), 0.04)
		b.rod("paint:rail", t * Vector3(0.5, 3.0 + k * 2.6, 4.35), t * Vector3(0.5, 3.0 + k * 2.6, 5.0), 0.04)
	b.decal("label_scrap", Vector2(3.0, 0.75), X.call(Vector3(0, 13.5, 4.33)))
	b.decal("num_01", Vector2(1.2, 1.2), X.call(Vector3(-2.2, 10.5, 3.7), Vector3(0, -30, 0)))
	# Conveyor gallery: a boxed truss with a walkway, down to a transfer tower by the yard.
	var g0 := Vector3(-1.5, 16.0, 0)
	var g1 := Vector3(-16.0, 4.0, 2.0) if not broken else Vector3(-14.0, 0.4, 4.5)
	var d: Vector3 = (g1 - g0)
	var n: int = 7
	for k: int in n + 1:
		var p: Vector3 = g0 + d * (float(k) / n)
		for z: float in [-0.9, 0.9]:
			if k < n:
				var q: Vector3 = g0 + d * (float(k + 1) / n)
				b.rod("paint:accent", t * (p + Vector3(0, 0, z)), t * (q + Vector3(0, 0, z)), 0.1)
				b.rod("paint:accent", t * (p + Vector3(0, 1.4, z)), t * (q + Vector3(0, 1.4, z)), 0.08)
				b.rod("dark_steel", t * (p + Vector3(0, 0, z)), t * (q + Vector3(0, 1.4, z)), 0.05)
		b.box("paint:main", Vector3(0.3, 1.5, 2.0), X.call(p + Vector3(0, 0.7, 0)))
		if not broken and k > 0 and k < n and k % 2 == 0:
			b.box("dark_steel", Vector3(0.6, p.y, 0.6), X.call(Vector3(p.x, p.y * 0.5, p.z)))
	b.tube("rubber", PackedVector3Array([t * (g0 + Vector3(0, 0.25, 0)), t * (g1 + Vector3(0, 0.25, 0))]), 0.35, 8)
	b.box("paint:main", Vector3(3.0, 5.2, 3.0), X.call(Vector3(-17.0, 2.6, 2.0)))
	b.box("paint:accent", Vector3(3.2, 0.3, 3.2), X.call(Vector3(-17.0, 5.3, 2.0)))
	if broken:
		KitProps.debris(b, X.call(Vector3(-8.0, 0, 4.0)), 6.0, 18)


# --- Hub base: the Ledger's haul depot ------------------------------------------------------------------

## Kit-built depot (art/kit): plated yard (never a slab), the ore silo with its conveyor gallery
## from the start; the site office (module_medium), workshop (hangar), crusher (machine_housing)
## and fuel/water tank farm arrive as Hub builds from stage 2 (owner: minimal start yard).
## Broken: rust, missing plates, debris, no light. Repaired: patched and lit. Restored: fresh
## paint, planters, solar panels, painted floor lines.
static func _hub_base(site: Node3D, stage: int, _restore: float, _rng: RandomNumberGenerator) -> void:
	var st: String = kit_state(stage)
	_plates(site, Vector2(30.0, 24.0), Vector3(0, 0, 0), 0.0, stage, 41)
	var b := KitMesh.Builder.new(4100 + stage, KIT_PALETTE, st)
	ore_silo(b, KitMesh.xf(Vector3(19.0, 0, -12.0)), stage)
	# Yard clutter: crate stacks, barrels, lamp posts, a hazard barrier line.
	KitProps.crate_stack(b, KitMesh.xf(Vector3(-11.0, 0, 8.5), Vector3(0, 20, 0)), 5, st)
	KitProps.crate_stack(b, KitMesh.xf(Vector3(9.0, 0, 9.0), Vector3(0, -15, 0)), 3, st)
	for k: int in 5:
		KitProps.barrel(b, KitMesh.xf(Vector3(-13.5 + k * 0.75, 0, -9.5)), "paint:barrel", stage <= 1 and k % 2 == 1)
	for p: Vector3 in [Vector3(-14.5, 0, 11.5), Vector3(14.5, 0, -11.0), Vector3(14.0, 0, 11.5)]:
		KitProps.lamp_post(b, KitMesh.xf(p), 4.5, st)
	for k: int in 6:
		b.box("hazard", Vector3(1.6, 0.8, 0.35), KitMesh.xf(Vector3(-6.0 + k * 1.9, 0.4, 12.6), Vector3(0, 0, (8.0 if stage <= 1 and k % 3 == 0 else 0.0))))
	if stage <= 1:
		KitProps.debris(b, KitMesh.xf(Vector3(0, 0, 0)), 13.0, 40)
	if stage >= 4:
		for k: int in 4:
			KitProps.planter(b, KitMesh.xf(Vector3(-9.0 + k * 3.0, 0, 11.0)), 2.2, st)
		for k: int in 6:
			KitProps.solar_panel(b, KitMesh.xf(Vector3(24.0, 0, -2.0 + k * 2.6), Vector3(0, 90, 0)), Vector2(2.4, 1.4), st, 1.2)
		b.decal("arrow", Vector2(1.6, 1.6), KitMesh.xf(Vector3(0, 0.07, 0), Vector3(-90, 0, 0)))
		b.decal("chevrons", Vector2(3.0, 0.8), KitMesh.xf(Vector3(0, 0.07, 6.0), Vector3(-90, 0, 0)))
	_kit_commit(site, b, stage, "Depot")
	# Haul trucks (the detailed Ochre truck).
	var tb := OchreProps.Batch.new()
	OchreSites.truck(tb, Transform3D(Basis(Vector3.UP, 0.4), Vector3(3.0, 0.0, -3.0)), _paint(stage), stage <= 1)
	if stage <= 3:
		OchreSites.truck(tb, Transform3D(Basis(Vector3.UP, 2.1), Vector3(-5.0, 0.0, 3.0)) * (Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-75.0)), Vector3(0, 2.6, 0)) if stage <= 1 else Transform3D()), _paint(stage), stage <= 1)
	tb.flush(site, true, 700.0)
	# Hub builds.
	if stage >= 2:
		_kb(site, "module_medium", Vector3(-19.0, 0, -13.0), 15.0, stage, 51)
		_kb(site, "hangar", Vector3(20.0, 0, 15.0), -100.0, stage, 52)
		_kb(site, "machine_housing", Vector3(8.0, 0, -19.0), 0.0, stage, 53)
		_kb(site, "tank_farm", Vector3(-21.0, 0, 15.0), 70.0, stage, 54)


## A haul truck (chassis, ribbed dump bed, cab, rails, ladder, stacks, treaded wheels with rims).
static func truck(b: OchreProps.Batch, xf: Transform3D, paint: Material, ruined: bool) -> void:
	var box: BoxMesh = OchreProps.unit_box()
	var put := func(pos: Vector3, size: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> void:
		b.add(box, xf * ProcMesh.xf(pos, rot, size), m)
	for z: float in [-1.1, 1.1]:
		put.call(Vector3(0, 1.9, z), Vector3(11.0, 0.7, 0.5), mat("dark"))
	put.call(Vector3(5.4, 2.2, 0), Vector3(0.6, 1.4, 5.0), paint)
	for i: int in 7:
		put.call(Vector3(5.72, 2.0 + i * 0.16, 0), Vector3(0.04, 0.08, 3.2), mat("dark"))
	b.add(ProcMesh.cyl(0.55, 0.55, 2.2, 12), xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.8, 1.7, 2.35)), mat("steel"))
	var bed := ProcMesh.xf(Vector3(-1.2, 3.0, 0), Vector3(0, 0, -6.0 if not ruined else -16.0))
	b.add(box, xf * bed * ProcMesh.xf(Vector3.ZERO, Vector3.ZERO, Vector3(8.0, 0.3, 5.2)), paint)
	for z: float in [-2.55, 2.55]:
		b.add(box, xf * bed * ProcMesh.xf(Vector3(0, 1.2, z), Vector3(z * 3.0, 0, 0), Vector3(8.0, 2.4, 0.18)), paint)
		for i: int in 6:
			b.add(box, xf * bed * ProcMesh.xf(Vector3(-3.6 + i * 1.45, 1.2, z * 1.04), Vector3.ZERO, Vector3(0.18, 2.4, 0.18)), mat("dark"))
	b.add(box, xf * bed * ProcMesh.xf(Vector3(-4.0, 1.2, 0), Vector3.ZERO, Vector3(0.2, 2.4, 5.2)), paint)
	b.add(box, xf * bed * ProcMesh.xf(Vector3(5.0, 2.5, 0), Vector3(0, 0, 8.0), Vector3(2.4, 0.18, 5.4)), paint)
	put.call(Vector3(4.2, 3.6, 1.2), Vector3(2.2, 2.2, 2.0), paint)
	put.call(Vector3(5.32, 3.95, 1.2), Vector3(0.05, 1.0, 1.6), mat("glass_broken") if ruined else mat("glass"))
	put.call(Vector3(4.2, 3.95, 2.22), Vector3(1.6, 0.9, 0.05), mat("glass"))
	put.call(Vector3(4.6, 2.45, -0.3), Vector3(1.6, 0.12, 4.4), mat("steel"))
	for i: int in 6:
		put.call(Vector3(5.1, 2.5, -2.2 + i * 0.85), Vector3(0.05, 0.9, 0.05), mat("steel"))
	put.call(Vector3(5.1, 2.95, -0.1), Vector3(0.05, 0.05, 4.3), mat("steel"))
	for i: int in 5:
		put.call(Vector3(5.75, 0.5 + i * 0.4, -2.2), Vector3(0.05, 0.05, 0.6), mat("steel"))
	for z: float in [-0.6, 0.0]:
		b.add(ProcMesh.cyl(0.14, 0.16, 2.6, 8), xf * ProcMesh.xf(Vector3(3.2, 4.4, z)), mat("dark"))
	put.call(Vector3(5.5, 4.2, 2.6), Vector3(0.1, 0.6, 0.35), mat("dark"))
	for z: float in [-1.8, 1.8]:
		put.call(Vector3(5.73, 2.6, z), Vector3(0.04, 0.3, 0.5), mat("glass"))
	for x: float in [-3.4, 3.6]:
		for z: float in [-2.4, 2.4]:
			if ruined and x > 0.0 and z > 0.0:
				continue
			var wx := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 1.55, z))
			b.add(ProcMesh.cyl(1.55, 1.55, 1.1, 18), xf * wx, mat("rubber"))
			for g: int in 9:
				var a: float = TAU * g / 9.0
				b.add(box, xf * wx * ProcMesh.xf(Vector3(cos(a) * 1.5, 0, sin(a) * 1.5), Vector3(0, -rad_to_deg(a), 0), Vector3(0.28, 1.14, 0.2)), mat("rubber"))
			b.add(ProcMesh.cyl(0.9, 0.9, 1.16, 14), xf * wx, mat("steel"))
			b.add(ProcMesh.cyl(0.3, 0.3, 1.3, 8), xf * wx, mat("dark"))


# --- Landmark sites ------------------------------------------------------------------------------------

## The toppled bucket-wheel excavator: boom snapped, mast down, wheel on its side; scree and
## scrap round it. Futuristic: overgrown planter wreck (greenery in the buckets and on the house).
static func _toppled(site: Node3D, stage: int, _restore: float, _rng: RandomNumberGenerator) -> void:
	var hidden := Node3D.new()
	hidden.visible = false
	site.add_child(hidden)
	var fut := Node3D.new()
	fut.visible = stage >= 4
	site.add_child(fut)
	var xf := Transform3D(Basis(Vector3.UP, 0.3) * Basis.from_scale(Vector3.ONE * 0.7), Vector3(-6.0, -0.3, 2.0))
	OchreExcavator.build({"always": site, "future": fut}, xf, machine_mats(stage), "fallen", 31)
	for n: Node in site.find_children("WheelFuture", "Node3D", true, false):
		(n as Node3D).visible = stage >= 4
	# Ground scars: dark gouges where the boom slid.
	var g := OchreProps.Batch.new()
	for k: int in 3:
		g.box(Vector3(10.0 + k * 3.0, 0.02, 10.0 + k * 1.5), Vector3(14.0, 0.06, 1.6), mat("dark"), Basis(Vector3.UP, 0.2))
	g.flush(site, false, 300.0)
	# Kit dressing: a cordon round the wreck, salvage clutter, a salvage hut and lamps once
	# the site is worked, planters at the futuristic stage.
	var st: String = kit_state(stage)
	var b := KitMesh.Builder.new(3100 + stage, KIT_PALETTE, st)
	for k: int in 18:
		var a: float = TAU * k / 18.0
		var p := Vector3(cos(a) * 34.0, 0, sin(a) * 30.0)
		var tilt: float = (_rng.randf_range(-35.0, 35.0) if stage <= 1 and k % 3 == 0 else 0.0)
		b.box("hazard", Vector3(1.8, 0.75, 0.3), KitMesh.xf(p + Vector3(0, 0.38, 0), Vector3(tilt, -rad_to_deg(a) + 90.0, 0)))
	KitProps.crate_stack(b, KitMesh.xf(Vector3(18.0, 0, -14.0), Vector3(0, 30, 0)), 5, st)
	for k: int in 4:
		KitProps.barrel(b, KitMesh.xf(Vector3(20.0 + k * 0.8, 0, -10.5)), "paint:barrel", stage <= 1 and k % 2 == 0)
	if stage <= 1:
		KitProps.debris(b, KitMesh.xf(Vector3(4.0, 0, 6.0)), 18.0, 50)
	else:
		for p: Vector3 in [Vector3(26.0, 0, -6.0), Vector3(-24.0, 0, 16.0), Vector3(6.0, 0, 27.0)]:
			KitProps.lamp_post(b, KitMesh.xf(p), 4.5, st)
		_kb(site, "module_small", Vector3(24.0, 0, -20.0), -40.0, stage, 61)
	if stage >= 4:
		for k: int in 5:
			KitProps.planter(b, KitMesh.xf(Vector3(-14.0 + k * 3.0, 0, 22.0), Vector3(0, 10, 0)), 2.2, st)
	_kit_commit(site, b, stage, "Cordon")


## A fragment of the open pit: five stepped benches carved into a 90 m patch, wandering edges,
## gullies, a haul ramp, sand banked at each wall foot, tailings on every bench. Restored: crops in
## rows along the benches, a water channel at each wall foot, vines (all in the terrain shader).
static func _pit(site: Node3D, tmat: ShaderMaterial, stage: int, restore: float, rng: RandomNumberGenerator) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.02
	var steps: int = 5
	var step_h: float = 5.0
	var pitch: float = 7.0
	var wall: float = 2.2
	var r_floor: float = 9.0
	var r_out: float = r_floor + steps * pitch + 6.0
	# Profile rings (radius, height, flat, across, level).
	var prof: Array = []
	prof.append([0.0, -steps * step_h, 1.0, 0.5, 0])
	prof.append([r_floor * 0.6, -steps * step_h, 1.0, 0.5, 0])
	for k: int in steps:
		var r0: float = r_floor + k * pitch
		var y0: float = -float(steps - k) * step_h
		for f: float in [0.0, 0.15, 0.5, 0.85, 1.0]:
			var w: float = f * f * (3.0 - 2.0 * f)
			prof.append([r0 + f * wall, y0 + w * step_h, 0.0, f, k])
		for f: float in [0.08, 0.25, 0.5, 0.75, 0.95]:
			prof.append([r0 + wall + f * (pitch - wall), y0 + step_h, 1.0, f, k + 1])
	prof.append([r_out, 0.0, 1.0, 0.5, steps])
	prof.append([r_out + 8.0, -0.6, 1.0, 0.5, steps])
	var spokes: int = 120
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gul: Array = []
	for i: int in 7:
		gul.append([rng.randf() * TAU, rng.randf_range(0.04, 0.09), rng.randf_range(1.5, 3.0)])
	var ramp_a0: float = rng.randf() * TAU
	for j: int in spokes + 1:
		var a: float = TAU * float(j % spokes) / spokes
		for p: Array in prof:
			var rr: float = float(p[0])
			var wob: float = nz.get_noise_2d(cos(a) * 60.0, sin(a) * 60.0 + rr * 0.5) * 2.2 * clampf(rr / 15.0, 0.0, 1.0)
			var y: float = float(p[1])
			if float(p[2]) > 0.5 and int(p[4]) > 0:
				y += 0.7 * smoothstep(0.65, 1.0, float(p[3]))
				y += nz.get_noise_2d(cos(a) * 30.0 + 100.0, sin(a) * 30.0) * 0.8
			for g: Array in gul:
				var da: float = absf(wrapf(a - float(g[0]), -PI, PI))
				if da < float(g[1]) * 2.0 and (float(p[2]) < 0.5 or float(p[3]) < 0.25):
					y -= float(g[2]) * exp(-pow(da / float(g[1]), 2.0))
			# Haul ramp: a spiral lane that smooths the steps along one side.
			var dr: float = wrapf(a - ramp_a0, 0.0, TAU)
			if dr < 2.4 and rr > r_floor and rr < r_out - 4.0:
				var t: float = dr / 2.4
				var lane_r: float = lerpf(r_floor + 3.0, r_out - 6.0, t)
				var lane_y: float = lerpf(-steps * step_h, 0.0, t)
				var m: float = 1.0 - smoothstep(2.5, 5.0, absf(rr - lane_r))
				y = lerpf(y, lane_y, m)
			var pos := Vector3(cos(a) * (rr + wob), y, sin(a) * (rr + wob))
			st.set_color(Color(float(p[4]) / float(steps + 1), p[2], p[3], 1.0 if rr < r_out - 1.0 else 0.0))
			st.set_uv(Vector2(a * rr, rr * 2.4))
			st.add_vertex(pos)
	var n: int = prof.size()
	for j: int in spokes:
		for i: int in n - 1:
			var a0: int = j * n + i
			var b0: int = (j + 1) * n + i
			for idx: int in [a0, a0 + 1, b0, b0, a0 + 1, b0 + 1]:
				st.add_index(idx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "PitFragment"
	mi.mesh = st.commit()
	mi.material_override = tmat
	site.add_child(mi)
	# Tailings on every bench, crates and drill scrap; boulders at wall feet.
	var junk: Dictionary = OchreProps.junk_meshes()
	var ids: Array = junk.keys()
	var lists: Dictionary = {}
	var rocks: Array = [[], [], []]
	for k: int in steps + 1:
		var rr0: float = r_floor + (k - 1) * pitch + wall if k > 0 else 0.0
		var y: float = -float(steps - k) * step_h
		for i: int in int(160 * (1.0 - restore)):
			var a: float = rng.randf() * TAU
			var rr: float = rr0 + rng.randf() * (pitch - wall if k > 0 else r_floor)
			var id: String = ids[0] if rng.randf() < 0.35 else ids[rng.randi() % ids.size()]
			var s: float = rng.randf_range(1.0, 2.2)
			if not lists.has(id):
				lists[id] = []
			(lists[id] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * s), Vector3(cos(a) * rr, y + 0.1, sin(a) * rr)))
		for i: int in 26:
			var a: float = rng.randf() * TAU
			var rr: float = r_floor + k * pitch - rng.randf() * 1.5
			var s: float = pow(rng.randf(), 2.0) * 1.6 + 0.3
			(rocks[i % 3] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * s), Vector3(cos(a) * rr, y, sin(a) * rr)))
	for id: String in lists:
		_mm(site, junk[id], lists[id], 300.0, false)
	for k: int in 3:
		_mm(site, OchreProps.boulder(k + 4), rocks[k], 400.0, true, _pal(["ochre", "terracotta", "plum"][k], Color(0.8, 0.5, 0.3)).lerp(Color(0.8, 0.6, 0.42), 0.3))
	# A pond on the floor (sludge -> oasis) and palms on the lower benches once restored.
	var pond := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = r_floor * 0.75
	disc.bottom_radius = r_floor * 0.75
	disc.height = 0.1
	disc.radial_segments = 40
	pond.mesh = disc
	pond.position = Vector3(0, -steps * step_h + 0.15, 0)
	var wm: ShaderMaterial = (mat("water") as ShaderMaterial).duplicate()
	wm.set_shader_parameter("clean", clampf(restore * 2.5, 0.0, 1.0) if stage >= 2 else 0.0)
	pond.material_override = wm
	site.add_child(pond)
	if restore > 0.05:
		var palms: Array = []
		for i: int in int(40 * restore):
			var a: float = rng.randf() * TAU
			var k: int = rng.randi_range(0, mini(steps, int(restore * steps) + 1))
			var rr: float = (r_floor * 0.85 if k == 0 else r_floor + (k - 1) * pitch + wall + 1.0) + rng.randf() * 1.2
			palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cos(a) * rr, -float(steps - k) * step_h, sin(a) * rr)))
		_mm(site, OchreProps.palm(2), palms, 400.0, true)
	# Kit dressing: rim railings and lamps, a pump house on the rim, an irrigation pipe from the
	# floor pond up the ramp once restored; scrap barrels and crates on the benches while ruined.
	var kst: String = kit_state(stage)
	var kb := KitMesh.Builder.new(5100 + stage, KIT_PALETTE, kst)
	var rim: float = r_out - 2.0
	if stage >= 2:
		for k: int in 10:
			var a0: float = TAU * k / 10.0 + 0.1
			var a1: float = a0 + TAU / 14.0
			KitProps.railing(kb, Transform3D.IDENTITY, Vector3(cos(a0) * rim, 0.0, sin(a0) * rim), Vector3(cos(a1) * rim, 0.0, sin(a1) * rim), 1.0, "paint:rail", kst)
		for k: int in 4:
			var a: float = TAU * k / 4.0 + 0.5
			KitProps.lamp_post(kb, KitMesh.xf(Vector3(cos(a) * (rim + 2.0), 0, sin(a) * (rim + 2.0))), 4.5, kst)
		_kb(site, "machine_housing", Vector3(cos(ramp_a0) * (r_out + 6.0), 0, sin(ramp_a0) * (r_out + 6.0)), -rad_to_deg(ramp_a0) - 90.0, stage, 71)
	if stage >= 4:
		var pts := PackedVector3Array()
		for k: int in 9:
			var t: float = float(k) / 8.0
			var a: float = ramp_a0 + t * 2.4
			var rr: float = lerpf(r_floor + 3.0, r_out - 6.0, t)
			pts.append(Vector3(cos(a) * (rr + 3.2), lerpf(-steps * step_h, 0.0, t) + 0.5, sin(a) * (rr + 3.2)))
		KitProps.pipe_run(kb, Transform3D.IDENTITY, pts, 0.18, "paint:pipe")
	if stage <= 1:
		for k: int in 3:
			var a: float = rng.randf() * TAU
			var rr: float = r_floor + (k + 1) * pitch + wall + 2.0
			KitProps.crate_stack(kb, KitMesh.xf(Vector3(cos(a) * rr, -float(steps - k - 1) * step_h, sin(a) * rr), Vector3(0, rng.randf() * 180.0, 0)), 3, kst)
			KitProps.barrel(kb, KitMesh.xf(Vector3(cos(a + 0.05) * rr, -float(steps - k - 1) * step_h, sin(a + 0.05) * rr)), "paint:barrel", true)
	_kit_commit(site, kb, stage, "PitKit")


## The oasis: a spring pool ringed with flat stones, terraced garden beds stepping up round it,
## shade sails. Ruined: a salt-crusted sludge pan, palm stumps, scrap in the beds.
static func _oasis(site: Node3D, stage: int, restore: float, rng: RandomNumberGenerator) -> void:
	var b := OchreProps.Batch.new()
	var pond := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 11.0
	disc.bottom_radius = 11.0
	disc.height = 0.1
	disc.radial_segments = 48
	pond.mesh = disc
	pond.position = Vector3(0, 0.05, 0)
	var wm: ShaderMaterial = (mat("water") as ShaderMaterial).duplicate()
	wm.set_shader_parameter("clean", clampf(restore * 2.0, 0.0, 1.0) if stage >= 2 else 0.05)
	pond.material_override = wm
	site.add_child(pond)
	var ost: String = kit_state(stage)
	var okb := KitMesh.Builder.new(6100 + stage, KIT_PALETTE, ost)
	# Rim stones and three low terrace rings of bevelled block walls (garden beds when restored).
	for i: int in 44:
		var a: float = TAU * i / 44.0 + rng.randf_range(-0.03, 0.03)
		var s: float = rng.randf_range(0.6, 1.1)
		b.add(OchreProps.boulder(7), Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(s * 1.3, s * 0.5, s)), Vector3(cos(a) * 11.4, -0.1, sin(a) * 11.4)), mat("concrete"))
	for k: int in 3:
		var r0: float = 15.0 + k * 5.5
		var segs: int = 40
		for i: int in segs:
			var a: float = TAU * (i + 0.5) / segs
			if (i + k * 3) % 13 == 0:
				continue
			okb.box("concrete" if stage >= 2 else "rusty", Vector3(TAU * r0 / segs + 0.02, 0.7 + k * 1.0, 0.6), KitMesh.xf(Vector3(cos(a) * r0, 0.35 + k * 0.5, sin(a) * r0), Vector3(0, -rad_to_deg(a) + 90.0, 0)))
			if restore > 0.3 and (i + k) % 2 == 0:
				b.add(ProcMesh.sphere(0.9, 8, 4), ProcMesh.xf(Vector3(cos(a) * (r0 + 1.6), 0.45 + k * 0.5, sin(a) * (r0 + 1.6)), Vector3.ZERO, Vector3(1.3, 0.6, 1.3)), mat("leaf"))
	# Palms: stumps while ruined, a ring of date palms once restored.
	var palms: Array = []
	for i: int in 18:
		var a: float = TAU * i / 18.0 + rng.randf_range(-0.1, 0.1)
		var p := Vector3(cos(a) * 13.2, 0, sin(a) * 13.2)
		if restore < 0.15 or stage <= 1:
			b.add(ProcMesh.cyl(0.2, 0.3, rng.randf_range(0.6, 2.6), 7), ProcMesh.xf(p + Vector3(0, 0.6, 0), Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))), mat("dark"))
		else:
			palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.9, 1.25)), p))
	_mm(site, OchreProps.palm(3), palms, 400.0, true)
	if stage >= 2:
		for k: int in 3:
			var a: float = TAU * k / 3.0 + 0.5
			var c := Vector3(cos(a) * 24.0, 0, sin(a) * 24.0)
			var corners: Array[Vector3] = [c + Vector3(-3, 4.2, -2), c + Vector3(3, 5.0, -2), c + Vector3(0, 3.6, 3)]
			var mi := MeshInstance3D.new()
			mi.mesh = OchreProps.sail_mesh(corners, 0.35)
			mi.material_override = sail_mat(Color(0.95, 0.92, 0.85) if stage >= 4 else Color(0.93, 0.74, 0.38), 0.0, 0.0 if stage >= 4 else 0.6, 0.6 if stage >= 4 else 0.0)
			site.add_child(mi)
			for cc: Vector3 in corners:
				b.beam(Vector3(cc.x, 0, cc.z), cc, 0.12, mat("steel"))
	b.flush(site, true, 600.0)
	# Kit dressing: the spring's pump house and header tank (Hub builds, stage 2+), pipes out to
	# the beds and planters when restored, lamps; scrap barrels in the dry pan while ruined.
	if stage >= 2:
		_kb(site, "module_small", Vector3(30.0, 0, -12.0), -110.0, stage, 81)
		KitProps.tank(okb, KitMesh.xf(Vector3(25.0, 0, 2.0)), 1.6, 4.0, "paint:main", ost)
		for k: int in 3:
			var a: float = TAU * k / 3.0 + 1.2
			KitProps.lamp_post(okb, KitMesh.xf(Vector3(cos(a) * 32.0, 0, sin(a) * 32.0)), 4.5, ost)
	if stage >= 4:
		for k: int in 3:
			var a: float = TAU * k / 3.0 + 0.2
			KitProps.pipe_run(okb, Transform3D.IDENTITY, PackedVector3Array([Vector3(25.0, 0.4, 2.0), Vector3(cos(a) * 22.0, 0.4, sin(a) * 22.0), Vector3(cos(a) * 12.5, 0.4, sin(a) * 12.5)]), 0.12, "paint:pipe")
			KitProps.planter(okb, KitMesh.xf(Vector3(cos(a + 0.5) * 27.0, 0, sin(a + 0.5) * 27.0), Vector3(0, -rad_to_deg(a + 0.5), 0)), 2.4, ost)
	if stage <= 1:
		KitProps.debris(okb, KitMesh.xf(Vector3(0, 0.05, 0)), 9.0, 22)
		for k: int in 3:
			KitProps.barrel(okb, KitMesh.xf(Vector3(-4.0 + k * 3.0, 0.05, 2.0 - k)), "paint:barrel", true)
	_kit_commit(site, okb, stage, "OasisKit")
