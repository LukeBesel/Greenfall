class_name AnvilSites
extends RefCounted
## [planet-anvil] Anvil's placeable site prefabs: compact local scenes (60-100 m across) built on a
## locally flat patch around the site root's origin, local +Y up. No world origin, no horizon, no
## far terrain: a sphere placer orients `site_root` on the globe and calls
##   AnvilSites.build(site_root, site_id, stage, restoration)
## stage = base level 1..5 (ruin 1, mid 2-3, restored 4-5), restoration = 0..1 (mean hex level / 5).
## Sites (listed in planets/anvil/data/sites.json):
##   foundry_yard    hub base: casting hall, two stacks, conveyor truss, ore spur, ember slag; keeps
##                   a 12 m clear core for the hub's own depot/workbench/pad
##   foundry_tower   landmark: the Ledger's colossal foundry stack, buttresses, a lattice crane
##   lava_forge      landmark: a running furnace pouring molten slag down a channel to a pool
##   ruined_smelter  landmark: a collapsed smelter hall, tipped pots, a toppled stack
## Every site is fully trashed while ruined (junk MultiMeshes with the rust/soot coat, scrap
## mounds); restoration clears the trash, cools the lava, greens the ground and plants it, and
## stage 4-5 adds vertical gardens, domes and thin warm-white light lines.

const Batch = FrontierView.Batch
const SITES: Array[String] = ["foundry_yard", "foundry_tower", "lava_forge", "ruined_smelter"]
const TRASH: Array[String] = ["rusted_wheel_rim_02", "Barrel_01", "old_tyre", "tire_pump", "wooden_crate_02", "metal_jerrycan", "can_rusted", "oil_tin", "propane_tank"]


static func build(site_root: Node3D, site_id: String, stage: int, restoration: float) -> Node3D:
	var kit: AnvilEnv = AnvilEnv.kit()
	site_root.add_child(kit)
	var root := Node3D.new()
	root.name = "AnvilSite_" + site_id
	site_root.add_child(root)
	stage = clampi(stage, 1, 5)
	restoration = clampf(restoration, 0.0, 1.0)
	kit.level = stage
	kit.restore = restoration
	# The ground only lichens and reddens; the grass, flowers and thickets are real plants.
	kit.terrain_mat.set_shader_parameter("restore", restoration * 0.55)
	kit.slag_mat.set_shader_parameter("restore", restoration * 0.8)
	match site_id:
		"foundry_yard":
			_foundry_yard(kit, root, stage, restoration)
		"foundry_tower":
			_foundry_tower(kit, root, stage, restoration)
		"lava_forge":
			_lava_forge(kit, root, stage, restoration)
		"ruined_smelter":
			_ruined_smelter(kit, root, stage, restoration)
		_:
			push_warning("AnvilSites: unknown site " + site_id)
	KitBatch.merge(root)  # [orbE] perf: the site's kit buildings as one surface per material
	PropBatch.merge(root)  # [orbE] and its static loose pieces
	root.set_meta("site", site_id)
	root.set_meta("stage", stage)
	root.set_meta("restoration", restoration)
	return root


## [orbE] build() behind the globe's loading screen: the hub yard yields between its steps
## (BuildBudget) so no frame runs over ~1 s; the landmarks build at once, as before. Same result.
static func build_async(site_root: Node3D, site_id: String, stage: int, restoration: float) -> Node3D:
	if site_id != "foundry_yard" or not BuildBudget.active():
		return build(site_root, site_id, stage, restoration)
	var kit: AnvilEnv = AnvilEnv.kit()
	site_root.add_child(kit)
	var root := Node3D.new()
	root.name = "AnvilSite_" + site_id
	site_root.add_child(root)
	stage = clampi(stage, 1, 5)
	restoration = clampf(restoration, 0.0, 1.0)
	kit.level = stage
	kit.restore = restoration
	kit.terrain_mat.set_shader_parameter("restore", restoration * 0.55)
	kit.slag_mat.set_shader_parameter("restore", restoration * 0.8)
	for step: Callable in _foundry_yard_steps(kit, root, stage, restoration):
		step.call()
		await BuildBudget.check("anvil:yard")
	KitBatch.merge(root)  # [orbE]
	PropBatch.merge(root)
	root.set_meta("site", site_id)
	root.set_meta("stage", stage)
	root.set_meta("restoration", restoration)
	return root


## Restoration actually shown (a high base stage counts too: a rebuilt base is never grim).
static func eff(stage: int, restoration: float) -> float:
	return maxf(restoration, float(stage - 1) / 4.0 * 0.8)


# --- Shared pieces ------------------------------------------------------------------------------

## The site's own ground: a noisy-edged disc of dust with low bumps, dipping under at the rim so it
## melts into whatever surface the site is placed on.
static func ground_patch(kit: AnvilEnv, root: Node3D, radius: float, seed_v: int) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 0.05
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na: int = 96
	var nr: int = 28
	for j: int in na + 1:
		var a: float = TAU * float(j % na) / na
		var edge_r: float = radius * (1.0 + nz.get_noise_1d(a * 9.0) * 0.12)
		for i: int in nr:
			var u: float = float(i) / (nr - 1)
			var rr: float = edge_r * u
			var x: float = cos(a) * rr
			var z: float = sin(a) * rr
			var y: float = nz.get_noise_2d(x, z) * 0.35 * smoothstep(0.15, 0.5, u) - 0.3 * smoothstep(0.85, 1.0, u) - 0.03
			st.add_vertex(Vector3(x, y, z))
	for j: int in na:
		for i: int in nr - 1:
			var a0: int = j * nr + i
			var b0: int = (j + 1) * nr + i
			for idx: int in [a0, a0 + 1, b0, b0, a0 + 1, b0 + 1]:
				st.add_index(idx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	mi.material_override = kit.terrain_mat
	root.add_child(mi)


## A low, broken ring of slag ridges and junk round the site, so its edge never ends in a line.
static func edge_ring(kit: AnvilEnv, root: Node3D, radius: float, restoration: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var b := Batch.new()
	var n: int = int(radius * 0.7)
	for k: int in n:
		var a: float = TAU * k / n + rng.randf_range(-0.08, 0.08)
		if rng.randf() < 0.18:
			continue  # gaps: ways in
		var r: float = radius * rng.randf_range(0.88, 1.12)
		var len_: float = rng.randf_range(5.0, 11.0)
		var hgt: float = rng.randf_range(0.6, 2.2)
		var bs := Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(rng.randf_range(2.0, 3.5), hgt, len_ * 0.5))
		b.add(AnvilProps.slag_mesh(seed_v + k), Transform3D(bs, Vector3(cos(a) * r, -0.35, sin(a) * r)), kit.mat("ridge"))
		if rng.randf() < 0.35:
			var r2: float = r + rng.randf_range(4.0, 9.0)
			b.add(AnvilProps.slag_mesh(seed_v + 400 + k), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(1.2, 3.0) * Vector3(1.0, 0.45, 1.0)), Vector3(cos(a + 0.05) * r2, -0.3, sin(a + 0.05) * r2)), kit.mat("rust") if k % 2 else kit.mat("ridge"))
	b.flush(root)
	trash(kit, root, radius * 1.35, radius * 0.86, 260, restoration * 0.6, seed_v + 77, -0.2, "EdgeTrash_")


## Restored ground: zones of meadow grass with flowers, red-leaf thickets, lichen beds and bare
## dust, crossed by gravel paths; grass heights vary by zone and noise.
static func ground_cover(kit: AnvilEnv, root: Node3D, radius: float, keep_r: float, restoration: float, seed_v: int) -> void:
	if restoration < 0.08:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 0.045
	var nz2 := FastNoiseLite.new()
	nz2.seed = seed_v + 5
	nz2.frequency = 0.16
	# Gravel paths out from the core.
	var paths: Array[PackedVector3Array] = []
	var n_paths: int = 3
	for p: int in n_paths:
		var a0: float = TAU * p / n_paths + rng.randf_range(-0.4, 0.4)
		var pts := PackedVector3Array()
		var steps: int = int(radius / 2.0)
		for k: int in steps + 1:
			var t: float = float(k) / steps
			var a: float = a0 + sin(t * 3.0 + p) * 0.25
			var r: float = lerpf(keep_r * 0.8, radius * 0.95, t)
			pts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
		paths.append(pts)
		path_ribbon(kit, root, pts, 1.8, seed_v + p)
	var near_path := func(x: float, z: float, w: float) -> bool:
		for pts: PackedVector3Array in paths:
			for k: int in range(0, pts.size(), 1):
				if Vector2(pts[k].x - x, pts[k].z - z).length() < w:
					return true
		return false
	var q: int = clampi(Settings.quality, 0, 3)
	var grass_n: int = int([1800, 2600, 3600, 4200][q] * restoration)
	var flower_n: int = int([300, 450, 600, 700][q] * restoration)
	var tuft: ArrayMesh = Meadow._tuft_mesh()
	var flower: ArrayMesh = Meadow._flower_mesh()
	var gmat := ShaderMaterial.new()
	gmat.shader = preload("res://planets/anvil/anvil_grass.gdshader")
	for kind: int in 2:
		var want: int = grass_n if kind == 0 else flower_n
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries: int = 0
		while xfs.size() < want and tries < want * 6:
			tries += 1
			var a: float = rng.randf() * TAU
			var r: float = lerpf(keep_r, radius * 0.97, sqrt(rng.randf()))
			var x: float = cos(a) * r
			var z: float = sin(a) * r
			var zone: float = nz.get_noise_2d(x, z)
			# Meadow where zone is low-mid; flowers only in its heart.
			if zone > 0.12 or zone < -0.45:
				continue
			if kind == 1 and (zone > -0.05 or nz2.get_noise_2d(x, z) < 0.1):
				continue
			if near_path.call(x, z, 1.5):
				continue
			var lush: float = clampf(0.5 - zone * 1.6 + nz2.get_noise_2d(x, z) * 0.5, 0.0, 1.0)
			var hgt: float = lerpf(0.25, 0.95, lush) * rng.randf_range(0.7, 1.25) * (0.7 if kind == 1 else 1.0)
			var wid: float = rng.randf_range(0.8, 1.3) * (0.6 if kind == 1 else 1.0)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wid, hgt, wid)), Vector3(x, -0.02, z)))
			var g := Color(0.28, 0.5, 0.17).lerp(Color(0.5, 0.52, 0.2), rng.randf() * (1.0 - lush))
			g = g.lerp(Color(0.62, 0.22, 0.14), 0.25 * rng.randf() * (1.0 - lush))
			cols.append(Color(g.r, g.g, g.b, rng.randf()))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = tuft if kind == 0 else flower
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_custom_data(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Plants_meadow" if kind == 0 else "Plants_flowers"
		mmi.multimesh = mm
		mmi.material_override = gmat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 110.0
		root.add_child(mmi)
	# Red-leaf thickets (zone high) and lichen beds (zone very low): the planet's own models.
	var defs: Array = kit.look.get("plants", [])
	for d: Dictionary in defs:
		var id: String = str(d["id"])
		var mesh: Mesh = AnvilEnv.tinted_mesh(id, AnvilEnv.col(d.get("tint"), Color.WHITE), 500)
		if mesh == null:
			continue
		var lichen: bool = id in ["moss_01", "shrub_01"]
		var want2: int = int(160 * restoration)
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.mesh = mesh
		var xf2: Array[Transform3D] = []
		var sc: Array = d.get("scale", [1.0, 1.5])
		var tries2: int = 0
		while xf2.size() < want2 and tries2 < want2 * 10:
			tries2 += 1
			var a: float = rng.randf() * TAU
			var r: float = lerpf(keep_r, radius * 0.97, sqrt(rng.randf()))
			var x: float = cos(a) * r
			var z: float = sin(a) * r
			var zone: float = nz.get_noise_2d(x, z)
			if (lichen and zone > -0.42) or (not lichen and (zone < 0.14 or zone > 0.5)):
				continue
			if near_path.call(x, z, 1.3):
				continue
			xf2.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(float(sc[0]), float(sc[1]))), Vector3(x, -0.05, z)))
		mm2.instance_count = xf2.size()
		for i: int in xf2.size():
			mm2.set_instance_transform(i, xf2[i])
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.name = "Plants_" + id
		mmi2.multimesh = mm2
		mmi2.visibility_range_end = 110.0
		mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi2)


## A gravel path ribbon (UV in metres) with a scatter of edging stones.
static func path_ribbon(kit: AnvilEnv, root: Node3D, pts: PackedVector3Array, width: float, seed_v: int) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist: float = 0.0
	var stones := Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i: int in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		t.y = 0.0
		t = t.normalized()
		var side := Vector3(-t.z, 0, t.x)
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		var hw: float = width * 0.5 * (1.0 + nz.get_noise_1d(dist * 4.0) * 0.25)
		st.set_uv(Vector2(-hw, dist))
		st.add_vertex(Vector3(p.x, 0.06, p.z) - side * hw)
		st.set_uv(Vector2(hw, dist))
		st.add_vertex(Vector3(p.x, 0.06, p.z) + side * hw)
		for sgn: float in [-1.0, 1.0]:
			if rng.randf() < 0.7:
				var q: Vector3 = p + side * sgn * (hw + rng.randf_range(0.0, 0.25)) + t * rng.randf_range(-0.8, 0.8)
				var g: float = rng.randf_range(0.12, 0.3)
				stones.add(AnvilProps.slag_mesh(seed_v + i * 2 + int(sgn)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(g, g * 0.6, g)), q + Vector3(0, 0.02, 0)), kit.mat("kerb"))
	for i: int in pts.size() - 1:
		var a: int = i * 2
		for idx: int in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.add_index(idx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "GravelPath"
	mi.mesh = st.commit()
	mi.material_override = kit.mat("gravel")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	stones.flush(root)


## Junk everywhere (outside keep_r), rust/soot coated; restoration clears it piece by piece.
static func trash(kit: AnvilEnv, root: Node3D, radius: float, keep_r: float, count: int, restoration: float, seed_v: int, y0: float = 0.0, prefix: String = "Trash_") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var coat := ShaderMaterial.new()
	coat.shader = preload("res://planets/anvil/anvil_coat.gdshader")
	coat.set_shader_parameter("dust", Color(0.5, 0.18, 0.08))
	coat.set_shader_parameter("top_amt", 0.8)
	coat.set_shader_parameter("film", 0.55)
	var left: float = 1.0 - clampf(restoration * 1.1, 0.0, 1.0)
	var per: int = int(float(count) / TRASH.size())
	for id: String in TRASH:
		if not AssetLib.has_model(id):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = AssetLib.model_mesh_lite(id, 420)
		mm.instance_count = per
		var aabb: AABB = mm.mesh.get_aabb()
		for i: int in per:
			# Clumped: most junk lies in drifts, some scattered.
			var a: float = rng.randf() * TAU
			var r: float = lerpf(keep_r, radius * 0.95, pow(rng.randf(), 0.8))
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 1.4)) if rng.randf() < 0.55 else Basis()
			var bs: Basis = Basis(Vector3.UP, rng.randf() * TAU) * tilt * Basis.from_scale(Vector3.ONE * rng.randf_range(1.1, 1.8))
			p.y = -aabb.position.y * 0.6 - 0.05 + y0
			mm.set_instance_transform(i, Transform3D(bs, p))
		mm.visible_instance_count = int(per * left)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = prefix + id
		mmi.multimesh = mm
		mmi.material_overlay = coat
		mmi.visibility_range_end = 140.0
		root.add_child(mmi)
	# Scrap mounds: lumpy heaps of slag and rusted scrap.
	var b := Batch.new()
	var n_m: int = int(22 * left + 0.5)
	for k: int in n_m:
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(keep_r + 4.0, radius * 0.85)
		var w: float = rng.randf_range(2.0, 5.0)
		b.add(AnvilProps.slag_mesh(seed_v + k), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(w, w * rng.randf_range(0.35, 0.6), w * 0.8)), Vector3(cos(a) * r, -0.15, sin(a) * r)), kit.mat("rust") if k % 2 == 0 else kit.mat("ore"))
	b.flush(root)


## A molten channel along a polyline (local points, y ignored): ribbon with UV.x = metres along,
## UV.y across, set a little into the ground, lined with slag banks.
static func lava_channel(kit: AnvilEnv, root: Node3D, pts: PackedVector3Array, width: float, lava: Material, seed_v: int) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dist: float = 0.0
	var banks := Batch.new()
	for i: int in pts.size():
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)])
		t.y = 0.0
		t = t.normalized()
		var side := Vector3(-t.z, 0, t.x)
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		var hw: float = width * 0.5 * (1.0 + nz.get_noise_1d(dist * 3.0) * 0.3)
		st.set_uv(Vector2(dist, 0.0))
		st.add_vertex(Vector3(p.x, 0.12, p.z) - side * hw)
		st.set_uv(Vector2(dist, 1.0))
		st.add_vertex(Vector3(p.x, 0.12, p.z) + side * hw)
		if i % 2 == 0:
			for sgn: float in [-1.0, 1.0]:
				var q: Vector3 = p + side * sgn * (hw + 0.6)
				var w: float = 1.1 + absf(nz.get_noise_1d(dist * 5.0 + sgn * 40.0)) * 1.6
				banks.add(AnvilProps.slag_mesh(seed_v + i * 2 + int(sgn)), Transform3D(Basis(Vector3.UP, dist) * Basis.from_scale(Vector3(w, w * 0.32, w * 0.8)), Vector3(q.x, -0.1, q.z)), kit.slag_mat)
	for i: int in pts.size() - 1:
		var a: int = i * 2
		for idx: int in [a, a + 2, a + 1, a + 1, a + 2, a + 3]:
			st.add_index(idx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "LavaChannel"
	mi.mesh = st.commit()
	mi.material_override = lava
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	banks.flush(root)


## A noisy-edged pool disc; UV.x in metres, UV.y across (hot in the middle).
static func lava_pool_mesh(rx: float, rz: float, seed_v: int) -> ArrayMesh:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 48
	st.set_uv(Vector2(0.0, 0.5))
	st.add_vertex(Vector3.ZERO)
	for k: int in n + 1:
		var a: float = TAU * float(k % n) / n
		var e: float = 1.0 + nz.get_noise_1d(a * 25.0) * 0.18
		var v := Vector3(cos(a) * rx * e, 0.0, sin(a) * rz * e)
		st.set_uv(Vector2(v.x, 0.5 + v.z / (rz * 2.6)))
		st.add_vertex(v)
	for k: int in n:
		for idx: int in [0, k + 1, k + 2]:
			st.add_index(idx)
	st.generate_normals()
	return st.commit()


static func lava_material(heat: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://planets/anvil/anvil_lava.gdshader")
	m.set_shader_parameter("heat", heat)
	return m


# --- Sites (built from the art kit: AnvilKit + KitBuilding) ------------------------------------

static func _b(stage: int, seed_v: int, palette: Dictionary) -> KitMesh.Builder:
	return KitMesh.Builder.new(seed_v, palette, AnvilKit.kit_state(stage))


static func _kit_patch(root: Node3D, size: Vector2, stage: int, seed_v: int, pos: Vector3, yaw_deg: float = 0.0) -> void:
	var gp: Node3D = KitMesh.ground_patch(size, AnvilKit.kit_state(stage), seed_v)
	gp.position = pos + Vector3(0, 0.02, 0)
	gp.rotation_degrees.y = yaw_deg
	root.add_child(gp)


## A kit wind turbine (scaled up to Anvil size) with its spinning rotor.
static func turbine(root: Node3D, stage: int, base: Vector3, scl: float, k: int) -> void:
	var st: String = AnvilKit.kit_state(stage)
	var b := _b(stage, 70 + k, AnvilKit.HABITAT)
	var t := Transform3D(Basis(Vector3.UP, k * 0.9).scaled(Vector3.ONE * scl), base)
	KitProps.wind_turbine(b, t, 14.0, st)
	AnvilKit.node(b, root, "Turbine%d" % k, stage >= 2)
	var rot := AnvilRotor.new()
	rot.name = "TurbineRotor%d" % k
	rot.speed = 0.6 + 0.1 * (k % 3)
	rot.transform = Transform3D(t.basis, t * KitProps.turbine_hub(14.0))
	var mi := MeshInstance3D.new()
	mi.mesh = KitProps.turbine_rotor(st, 6.0, AnvilKit.HABITAT)
	KitMat.apply(mi, st, stage >= 2)
	rot.add_child(mi)
	root.add_child(rot)


## Lived-in clutter: crate stacks, barrels (some tipped), a lamp post, debris when broken.
static func _clutter(b: KitMesh.Builder, spots: Array, lamp_at: Array) -> void:
	var st: String = b.state
	for k: int in spots.size():
		var p: Vector3 = spots[k]
		var yaw: float = b.rng.randf_range(0, 360)
		match k % 3:
			0:
				KitProps.crate_stack(b, AnvilKit.x(p, Vector3(0, yaw, 0)), 3 + k % 3, st)
			1:
				for q: int in 3:
					KitProps.barrel(b, AnvilKit.x(p + Vector3(q * 0.75, 0, b.rng.randf_range(-0.3, 0.3)), Vector3(0, yaw, 0)), "paint:barrel", st == "broken" and q == 1)
			_:
				if st == "broken":
					KitProps.debris(b, AnvilKit.x(p), 3.0, 10)
				else:
					KitProps.crate(b, AnvilKit.x(p, Vector3(0, yaw, 0)))
	for lp: Vector3 in lamp_at:
		KitProps.lamp_post(b, AnvilKit.x(lp), 5.5, st)


static func _foundry_yard(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	for step: Callable in _foundry_yard_steps(kit, root, stage, restoration):
		step.call()


## [orbE] The foundry yard as steps, so the globe's loading screen can yield between them
## (build_async). Same pieces in the same order as before; build() runs them back to back.
static func _foundry_yard_steps(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> Array[Callable]:
	var r: float = eff(stage, restoration)
	var pw: bool = stage >= 2
	var steps: Array[Callable] = []
	steps.append(func() -> void:
		ground_patch(kit, root, 48.0, 101)
		_kit_patch(root, Vector2(26, 22), stage, 5, Vector3(0, 0, -2)))
	# Kit buildings: the casting hall, an office module, a machine house and a tank farm.
	steps.append(func() -> void: AnvilKit.building(root, "hangar", stage, 11, AnvilKit.FOUNDRY, Vector3(-2, 0, -29), 0.0, 1.6))
	steps.append(func() -> void: AnvilKit.building(root, "module_medium", stage, 12, AnvilKit.HABITAT, Vector3(-27, 0, 4), 70.0, 1.2))
	steps.append(func() -> void: AnvilKit.building(root, "machine_housing", stage, 13, AnvilKit.FOUNDRY, Vector3(25, 0, -12), -80.0, 1.3))
	steps.append(func() -> void: AnvilKit.building(root, "tank_farm", stage, 14, AnvilKit.FOUNDRY, Vector3(27, 0, 16), -120.0, 1.15))
	steps.append(func() -> void:
		var b := _b(stage, 15, AnvilKit.FOUNDRY)
		AnvilKit.stack(b, AnvilKit.x(Vector3(-24, 0, -40)), 40.0, 3.0, 1)
		AnvilKit.stack(b, AnvilKit.x(Vector3(20, 0, -42)), 33.0, 2.6, 4)
		AnvilKit.truss(b, Vector3(10, 0, -22), Vector3(30, 0, 2), 8.0)
		var hop := PackedVector3Array([Vector3(0.6, 0, 1), Vector3(2.4, 3.0, 0), Vector3(2.6, 3.1, 1), Vector3(2.6, 3.4, 1), Vector3(0.6, 3.4, 0)])
		b.add("paint:main", KitMesh.lathe(hop, 16), AnvilKit.x(Vector3(31, 6.0, 4)))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.rod("paint:accent", Vector3(31 + sx * 1.8, 0.2, 4 + sz * 1.8), Vector3(31 + sx * 1.3, 6.2, 4 + sz * 1.3), 0.14, 6)
		AnvilKit.track(b, Vector3(-30, 0, 26), Vector3(6, 0, 31))
		for k: int in 3:
			var tp: Vector3 = Vector3(-30, 0, 26).lerp(Vector3(6, 0, 31), 0.2 + 0.28 * k)
			AnvilKit.ore_cart(b, Transform3D(Basis(Vector3.UP, atan2(36.0, 5.0) + PI * 0.5), tp + Vector3(0, 0.3, 0)), stage == 1 and k == 1)
		for k: int in 3:
			KitProps.cable(b, Transform3D.IDENTITY, Vector3(-21.6, 14.0 + k * 1.3, -38.0), Vector3(-10.0 + k * 3.0, 13.5, -23.0), 1.4 + k * 0.4, 0.06)
		_clutter(b, [Vector3(-8, 0, 12), Vector3(9, 0, 11), Vector3(-15, 0, -12), Vector3(15, 0, -6), Vector3(-6, 0, 20), Vector3(18, 0, 22)], [Vector3(-13.5, 0, 8.5), Vector3(13.5, 0, 8.5)])
		AnvilKit.node(b, root, "Foundry", pw))
	steps.append(func() -> void:
		if stage >= 3:
			AnvilKit.building(root, "dome", stage, 61, AnvilKit.HABITAT, Vector3(-28, 0, 28), 40.0, 1.08)
		var hb := _b(stage, 16, AnvilKit.LEDGER)
		AnvilKit.hauler(hb, Transform3D(Basis(Vector3.UP, 2.1), Vector3(32, 0, 30)))
		AnvilKit.node(hb, root, "Hauler", pw)
		var sb := Batch.new()
		sb.add(AnvilProps.slag_mesh(21), Transform3D(Basis(Vector3.UP, 1.2) * Basis.from_scale(Vector3(9.0, 4.8, 7.5)), Vector3(-34, -0.2, 14)), kit.slag_mat)
		sb.flush(root))
	steps.append(func() -> void:
		if stage >= 4:
			AnvilKit.building(root, "greenhouse", stage, 66, AnvilKit.HABITAT, Vector3(-38, 0, 14), 75.0, 1.0)
		if stage >= 2:
			turbine(root, stage, Vector3(40, 0, -26), 1.7, 0)
		if stage >= 4:
			turbine(root, stage, Vector3(-42, 0, -10), 1.9, 1))
	steps.append(func() -> void: edge_ring(kit, root, 46.0, r, 1501))
	steps.append(func() -> void: trash(kit, root, 46.0, 13.0, 700, r, 501))
	steps.append(func() -> void: ground_cover(kit, root, 46.0, 13.0, r, 601))
	return steps


static func _foundry_tower(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	var pw: bool = stage >= 2
	ground_patch(kit, root, 42.0, 202)
	_kit_patch(root, Vector2(28, 28), stage, 9, Vector3.ZERO, 20.0)
	var b := _b(stage, 21, AnvilKit.FOUNDRY)
	AnvilKit.stack(b, AnvilKit.x(Vector3.ZERO), 118.0, 7.0, 3)
	# Buttresses: four lattice legs braced to the first gallery, on concrete feet.
	for k: int in 4:
		var a: float = TAU * k / 4.0 + 0.4
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x)
		var foot: Vector3 = d * 21.0
		var top: Vector3 = d * 7.8 + Vector3(0, 42.0, 0)
		for sgn: float in [-1.0, 1.0]:
			b.rod("paint:accent", foot + side * 2.0 * sgn + Vector3(0, 1.0, 0), top + side * 0.9 * sgn, 0.42, 8)
		for j: int in 7:
			var t0: float = float(j) / 7.0
			var t1: float = float(j + 1) / 7.0
			b.rod("paint:main", foot.lerp(top, t0) + side * lerpf(2.0, 0.9, t0) + Vector3(0, 1.0, 0), foot.lerp(top, t1) - side * lerpf(2.0, 0.9, t1) + Vector3(0, 1.0, 0), 0.16, 6)
		b.box("concrete", Vector3(5.5, 1.6, 4.0), AnvilKit.x(foot + Vector3(0, 0.8, 0), Vector3(0, rad_to_deg(-a), 0)), 0.25)
		b.decal("chevrons", Vector2(2.2, 0.8), AnvilKit.x(foot + d * 2.76 + Vector3(0, 0.9, 0), Vector3(0, rad_to_deg(atan2(d.x, d.z)), 0)))
	# Pipes snaking out of the plinth into the ground.
	for k: int in 4:
		var a2: float = 0.9 + k * 0.4
		KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(cos(a2) * 10.5, 2.2, sin(a2) * 10.5), Vector3(cos(a2) * 18.0, 2.2, sin(a2) * 18.0), Vector3(cos(a2) * 22.0, 0.3, sin(a2) * 22.0)]), 0.45, "paint:pipe")
	if stage == 1:
		b.add("paint:main", KitMesh.bevel_cylinder(3.6, 18.0, 0.3, 28), Transform3D(Basis(Vector3.UP, 2.2) * Basis(Vector3.FORWARD, PI * 0.5 + 0.06), Vector3(-26, 3.4, 18)))
		KitProps.debris(b, AnvilKit.x(Vector3(-20, 0, 22)), 6.0, 18)
	_clutter(b, [Vector3(14, 0, 14), Vector3(-15, 0, 12), Vector3(16, 0, -14), Vector3(-12, 0, -16)], [Vector3(11, 0, 9), Vector3(-11, 0, -9)])
	AnvilKit.node(b, root, "Tower", pw)
	AnvilKit.building(root, "module_medium", stage, 22, AnvilKit.HABITAT, Vector3(24, 0, 16), -40.0, 1.15)
	AnvilKit.building(root, "machine_housing", stage, 23, AnvilKit.FOUNDRY, Vector3(-23, 0, -16), 130.0, 1.2)
	var sb := Batch.new()
	for k: int in 3:
		var a3: float = 3.6 + k * 0.9
		sb.add(AnvilProps.slag_mesh(30 + k), Transform3D(Basis(Vector3.UP, a3) * Basis.from_scale(Vector3(8.0, 4.0 + k, 6.5)), Vector3(cos(a3) * 30.0, -0.2, sin(a3) * 30.0)), kit.slag_mat)
	sb.flush(root)
	if stage >= 3:
		AnvilKit.building(root, "dome", stage, 62, AnvilKit.HABITAT, Vector3(28, 0, -20), 80.0, 1.00)
	if stage >= 4:
		turbine(root, stage, Vector3(-34, 0, 22), 1.7, 2)
	edge_ring(kit, root, 40.0, r, 1503)
	trash(kit, root, 40.0, 15.0, 650, r, 503)
	ground_cover(kit, root, 40.0, 15.0, r, 603)


static func _lava_forge(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	var pw: bool = stage >= 2
	ground_patch(kit, root, 46.0, 303)
	var heat: float = 1.0 - 0.9 * smoothstep(0.1, 0.85, r)
	var lava: ShaderMaterial = lava_material(heat)
	var f := Vector3(-6, 0, -18)
	_kit_patch(root, Vector2(24, 12), stage, 13, f + Vector3(0, 0, 14))
	var b := _b(stage, 31, AnvilKit.FOUNDRY)
	AnvilKit.furnace(b, AnvilKit.x(f))
	# The pour: a channel winding out to a cooling pool, a ladle crane straddling it.
	var pts := PackedVector3Array()
	for k: int in 34:
		var t: float = float(k) / 33.0
		pts.append(f + Vector3(sin(t * 4.2) * 6.0 + t * 26.0, 0, 9.5 + t * 34.0))
	lava_channel(kit, root, pts, 2.6, lava, 7)
	var pool_c: Vector3 = pts[pts.size() - 1] + Vector3(3, 0, 4)
	var pool := MeshInstance3D.new()
	pool.name = "LavaPool"
	pool.mesh = lava_pool_mesh(7.5, 6.0, 88)
	pool.position = pool_c + Vector3(0, 0.1, 0)
	pool.material_override = lava
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	var sb := Batch.new()
	for k: int in 9:
		var a: float = TAU * k / 9.0
		sb.add(AnvilProps.slag_mesh(120 + k), Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(2.6, 1.2, 2.0)), pool_c + Vector3(cos(a) * 7.6, -0.2, sin(a) * 6.2)), kit.slag_mat)
	sb.flush(root)
	var cc: Vector3 = pts[14]
	AnvilKit.crane(b, Vector3(cc.x, 0, cc.z), 15.0, 12.0, 0.35)
	_clutter(b, [Vector3(-20, 0, -2), Vector3(-16, 0, 8), Vector3(6, 0, -24), Vector3(-24, 0, -18)], [Vector3(-12, 0, 2), Vector3(4, 0, -6)])
	AnvilKit.node(b, root, "Forge", pw)
	# The tap hole: lava light, whatever the power state.
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.2, 0.05, 0.02)
	hole.emission_enabled = true
	hole.emission = Color(1.0, 0.45, 0.12)
	hole.emission_energy_multiplier = 2.5 * heat + 0.3
	var hm := MeshInstance3D.new()
	hm.name = "TapHole"
	hm.mesh = ProcMesh.sphere(1.3, 16, 8)
	hm.scale = Vector3(1.0, 0.7, 0.5)
	hm.position = f + Vector3(0, 2.2, 7.3)
	hm.material_override = hole
	root.add_child(hm)
	AnvilKit.building(root, "machine_housing", stage, 32, AnvilKit.FOUNDRY, Vector3(16, 0, -26), -30.0, 1.2)
	AnvilKit.building(root, "tank_farm", stage, 33, AnvilKit.FOUNDRY, Vector3(-30, 0, -4), 80.0, 1.0)
	if stage >= 3:
		AnvilKit.building(root, "dome", stage, 63, AnvilKit.HABITAT, Vector3(-28, 0, 22), 120.0, 1.08)
	if stage >= 4:
		turbine(root, stage, Vector3(34, 0, -22), 1.6, 3)
	edge_ring(kit, root, 44.0, r, 1505)
	trash(kit, root, 44.0, 8.0, 650, r, 505)
	ground_cover(kit, root, 44.0, 10.0, r, 605)


static func _ruined_smelter(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	var pw: bool = stage >= 2
	ground_patch(kit, root, 42.0, 404)
	_kit_patch(root, Vector2(38, 24), stage, 17, Vector3(0, 0, -4), -6.0)
	var b := _b(stage, 41, AnvilKit.FOUNDRY)
	var broken: bool = stage == 1
	var key: String = "rusty" if broken else "paint:main"
	var basis := Basis(Vector3.UP, -0.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	# The hall's frame: I-beam columns standing, leaning or snapped; roof girders, some fallen.
	for k: int in 8:
		for side: float in [-1.0, 1.0]:
			var base: Vector3 = basis * Vector3(-17.5 + k * 5.0, 0, side * 10.0) + Vector3(0, 0, -4)
			var hgt: float = 11.0 if (not broken or rng.randf() > 0.3) else rng.randf_range(3.0, 7.0)
			var lean := Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2)) if (broken and rng.randf() < 0.4) else Vector3.ZERO
			AnvilKit.i_beam(b, base, base + lean + Vector3(0, hgt, 0), 0.55, key)
			b.box("concrete", Vector3(1.2, 0.5, 1.2), AnvilKit.x(base + Vector3(0, 0.25, 0)), 0.1)
			if hgt > 10.0 and k % 2 == 0 and (not broken or rng.randf() < 0.6):
				var top: Vector3 = base + lean + Vector3(0, hgt, 0)
				AnvilKit.i_beam(b, top, top + basis * Vector3(0, 1.4, -side * 10.0), 0.45, key)
			if stage >= 4:
				KitProps.planter(b, AnvilKit.x(base + Vector3(0.9, 0, 0), Vector3(0, 90, 0)), 1.4, "restored")
				b.add("trim:warm", KitMesh.bevel_box(Vector3(0.05, 0.05, 1.6), 0.02), AnvilKit.x(base + Vector3(0, 3.0, 0.32)))
	if broken:
		for k: int in 4:
			var p: Vector3 = basis * Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-7, 7)) + Vector3(0, 0, -4)
			AnvilKit.i_beam(b, p + Vector3(0, 0.3, 0), p + Vector3(rng.randf_range(-6, 6), rng.randf_range(0.5, 3.0), rng.randf_range(-6, 6)), 0.45, "rusty")
		KitProps.debris(b, AnvilKit.x(Vector3(-6, 0, -2)), 8.0, 24)
	# Smelting pots: upright, tipped, and one spilled with a frozen slag tongue.
	var pots: Array = [[Vector3(-10, 0, 16), 0.0], [Vector3(2, 0, 18), 0.6 if broken else 0.0], [Vector3(13, 0, 15), 1.45 if broken else 0.0]]
	for k: int in pots.size():
		var pp: Vector3 = pots[k][0]
		var tilt: float = float(pots[k][1])
		AnvilKit.pot(b, Transform3D(Basis(Vector3.UP, k * 1.7) * Basis(Vector3.RIGHT, tilt), pp + Vector3(0, 0.6 + (2.6 if tilt > 1.0 else 0.0), 0)))
	# The toppled stack (broken) or a short restored stack.
	if broken:
		AnvilKit.stack(b, Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3.FORWARD, PI * 0.5 - 0.04), Vector3(-30, 3.2, -28)), 22.0, 2.6, 6)
	else:
		AnvilKit.stack(b, AnvilKit.x(Vector3(-26, 0, -30)), 26.0, 2.6, 6)
	_clutter(b, [Vector3(-22, 0, 4), Vector3(20, 0, -2), Vector3(-4, 0, 14), Vector3(22, 0, 10)], [Vector3(-18, 0, 9), Vector3(18, 0, 9)])
	AnvilKit.node(b, root, "Smelter", pw)
	var sb := Batch.new()
	sb.add(AnvilProps.slag_mesh(310), Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3(8.0, 1.0, 4.0)), Vector3(18, -0.1, 17)), kit.slag_mat)
	sb.add(AnvilProps.slag_mesh(332), Transform3D(Basis.from_scale(Vector3(6.0, 3.5, 5.0)), Vector3(26, -0.2, -20)), kit.slag_mat)
	sb.flush(root)
	if stage >= 3:
		AnvilKit.building(root, "dome", stage, 64, AnvilKit.HABITAT, Vector3(26, 0, 24), 160.0, 1.00)
	if stage >= 4:
		turbine(root, stage, Vector3(-34, 0, 18), 1.6, 4)
	edge_ring(kit, root, 40.0, r, 1507)
	trash(kit, root, 40.0, 6.0, 700, r, 507)
	ground_cover(kit, root, 40.0, 6.0, r, 607)
