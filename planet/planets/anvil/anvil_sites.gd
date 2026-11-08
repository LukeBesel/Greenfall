class_name AnvilSites
extends RefCounted
## [planet-anvil] Anvil's placeable site prefabs: compact local scenes (60-100 m across) built on a
## locally flat patch around the site root's origin, local +Y up. No world origin, no horizon, no
## far terrain: a sphere placer orients `site_root` on the globe and calls
##   AnvilSites.build(site_root, site_id, stage, restoration)
## stage = base level 1..5 (ruin 1, mid 2-3, restored 4-5), restoration = 0..1 (mean hex level / 5).
## Sites (listed in data/planets.json anvil.sites):
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
	kit.terrain_mat.set_shader_parameter("restore", restoration)
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
			var y: float = nz.get_noise_2d(x, z) * 0.35 * smoothstep(0.15, 0.5, u) - 0.9 * smoothstep(0.8, 1.0, u) - 0.03
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


## An irregular cracked slab (yard apron, furnace floor): a noisy polygon, never a rectangle.
static func slab(b: Batch, m: Material, c: Vector3, size: Vector2, yaw: float, seed_v: int) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 40
	st.add_vertex(Vector3(0, 0.12, 0))
	for k: int in n + 1:
		var a: float = TAU * float(k % n) / n
		var sq: float = 1.0 / maxf(absf(cos(a)), absf(sin(a)))  # squarish, chipped outline
		var r: float = minf(sq, 1.25) * (1.0 + nz.get_noise_1d(a * 30.0) * 0.08)
		st.add_vertex(Vector3(cos(a) * r * size.x * 0.5, 0.1 + nz.get_noise_1d(a * 11.0) * 0.04, sin(a) * r * size.y * 0.5))
	for k: int in n:
		for idx: int in [0, k + 1, k + 2]:
			st.add_index(idx)
	st.generate_normals()
	b.add(st.commit(), Transform3D(Basis(Vector3.UP, yaw), c), m)


## Junk everywhere (outside keep_r), rust/soot coated; restoration clears it piece by piece.
static func trash(kit: AnvilEnv, root: Node3D, radius: float, keep_r: float, count: int, restoration: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var coat := ShaderMaterial.new()
	coat.shader = preload("res://planet/planets/anvil/anvil_coat.gdshader")
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
			p.y = -aabb.position.y * 0.6 - 0.05
			mm.set_instance_transform(i, Transform3D(bs, p))
		mm.visible_instance_count = int(per * left)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trash_" + id
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


## Hardy restoration planting: red-leaf and lichen clumps.
static func plants(kit: AnvilEnv, root: Node3D, radius: float, keep_r: float, count: int, restoration: float, seed_v: int) -> void:
	if restoration < 0.08:
		return
	var defs: Array = kit.look.get("plants", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for d: Dictionary in defs:
		var mesh: Mesh = AnvilEnv.tinted_mesh(str(d["id"]), AnvilEnv.col(d.get("tint"), Color.WHITE), 500)
		if mesh == null:
			continue
		var n: int = int(count * restoration / defs.size())
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = n
		var sc: Array = d.get("scale", [1.0, 1.5])
		for i: int in n:
			var a: float = rng.randf() * TAU
			var r: float = lerpf(keep_r, radius * 0.9, sqrt(rng.randf()))
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(float(sc[0]), float(sc[1]))), Vector3(cos(a) * r, -0.05, sin(a) * r)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Plants_" + str(d["id"])
		mmi.multimesh = mm
		mmi.visibility_range_end = 120.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


## A sawtooth-roofed casting hall: corrugated walls, beveled frames, roof panels missing when ruined.
static func hall(kit: AnvilEnv, b: Batch, fut: Batch, c: Vector3, yaw: float, len_: float, w: float, h: float, broken: bool, seed_v: int) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# Walls as panels (not one box): a few missing or sagging when ruined.
	var panels: int = int(len_ / 4.0)
	for side: float in [-1.0, 1.0]:
		for k: int in panels:
			if broken and rng.randf() < 0.18:
				continue
			var lx: float = -len_ * 0.5 + (k + 0.5) * len_ / panels
			var sag: float = rng.randf_range(-0.04, 0.04) if broken else 0.0
			var ph: float = h * rng.randf_range(0.93, 1.0)
			AnvilProps.add_plate(b, basis * Basis(Vector3.RIGHT, sag), c + basis * Vector3(lx, ph * 0.5, side * w * 0.5), Vector3(len_ / panels * 0.98, ph, 0.25), kit.mat("corr"))
	for side: float in [-1.0, 1.0]:
		AnvilProps.add_plate(b, basis, c + basis * Vector3(side * len_ * 0.5, h * 0.5, 0), Vector3(0.25, h, w), kit.mat("corr"))
	# Frame columns and the sawtooth roof.
	for k: int in panels + 1:
		var lx: float = -len_ * 0.5 + k * len_ / panels
		for side: float in [-1.0, 1.0]:
			AnvilProps.add_beam(b, c + basis * Vector3(lx, 0, side * (w * 0.5 + 0.3)), c + basis * Vector3(lx, h + 0.4, side * (w * 0.5 + 0.3)), 0.45, kit.mat("rust"))
	var teeth: int = int(len_ / 6.0)
	for k: int in teeth:
		if broken and rng.randf() < 0.3:
			continue
		var lx: float = -len_ * 0.5 + (k + 0.5) * len_ / teeth
		AnvilProps.add_plate(b, basis * Basis(Vector3.FORWARD, 0.45), c + basis * Vector3(lx, h + 1.4, 0), Vector3(len_ / teeth * 1.05, 0.3, w), kit.mat("corr"))
		AnvilProps.add_plate(b, basis, c + basis * Vector3(lx + len_ / teeth * 0.45, h + 1.3, 0), Vector3(0.3, 2.8, w), kit.mat("stack"))
	# A loading door, dark inside.
	AnvilProps.add_plate(b, basis, c + basis * Vector3(0, h * 0.3, w * 0.5 + 0.08), Vector3(6.0, h * 0.6, 0.3), kit.mat("soot"))
	for side: float in [-1.0, 1.0]:
		fut.add(AnvilProps.box(), Transform3D(basis * Basis.from_scale(Vector3(len_, 0.12, 0.12)), c + basis * Vector3(0, h - 0.3, side * (w * 0.5 + 0.45))), kit.mat("line"))
		fut.add(AnvilProps.box(), Transform3D(basis * Basis.from_scale(Vector3(len_ * 0.95, 0.7, 0.5)), c + basis * Vector3(0, h * 0.62, side * (w * 0.5 + 0.5))), kit.mat("green"))


static func turbine(kit: AnvilEnv, root: Node3D, base: Vector3, h: float, k: int) -> void:
	AnvilProps.turbine(kit, root, base, h, k)


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
	m.shader = preload("res://planet/planets/anvil/anvil_lava.gdshader")
	m.set_shader_parameter("heat", heat)
	return m


static func _flush_stage(root: Node3D, stage: int, always: Batch, ruin: Batch, high: Batch, fut: Batch) -> void:
	always.flush(root)
	if stage == 1:
		ruin.flush(root)
	if stage >= 3:
		high.flush(root)
	if stage >= 4:
		fut.flush(root)


# --- Sites ------------------------------------------------------------------------------------

static func _foundry_yard(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	ground_patch(kit, root, 48.0, 101)
	var b := Batch.new()
	var ruin := Batch.new()
	var high := Batch.new()
	var fut := Batch.new()
	slab(b, kit.mat("concrete"), Vector3(0, 0, -2), Vector2(26, 22), 0.08, 5)
	hall(kit, b, fut, Vector3(-2, 0, -27), 0.05, 34.0, 15.0, 11.0, stage <= 2, 7)
	AnvilProps._stack(kit, b, fut, Vector3(-22, -5.5, -31), 44.0, 3.2, 1)
	AnvilProps._stack(kit, b, fut, Vector3(19, -5.5, -35), 36.0, 2.7, 4)
	AnvilProps._truss(kit, b, fut, Vector3(14, 0, -22), Vector3(30, 0, 6), 9.0)
	# Hopper tower at the truss end.
	b.add(AnvilProps.noisy_cyl(2.6, 1.0, 5.0, 16, 4, 0.03, 12), Transform3D(Basis(), Vector3(30, 9.0, 6)), kit.mat("shell"))
	for sx: float in [-1.6, 1.6]:
		for sz: float in [-1.6, 1.6]:
			AnvilProps.add_beam(b, Vector3(30 + sx * 1.4, 0, 6 + sz * 1.4), Vector3(30 + sx, 7.0, 6 + sz), 0.35, kit.mat("rust"))
	# Ember slag tip and a buried hauler.
	b.add(AnvilProps.slag_mesh(21), Transform3D(Basis(Vector3.UP, 1.2) * Basis.from_scale(Vector3(9.0, 4.8, 7.5)), Vector3(-30, -0.2, 10)), kit.slag_mat)
	AnvilProps._hauler(kit, b, high, Transform3D(Basis(Vector3.UP, 2.1) * Basis(Vector3.FORWARD, 0.14) * Basis.from_scale(Vector3.ONE * 0.62), Vector3(31, -1.6, 26)), 0)
	# Ore spur with carts along the south side.
	_cart_line(kit, b, Vector3(-30, 0, 24), Vector3(6, 0, 30), 3)
	# Ruin: a fallen stack section across the yard edge.
	ruin.add(AnvilProps.noisy_cyl(2.4, 2.6, 18.0, 24, 6, 0.04, 77), Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.FORWARD, PI * 0.5 - 0.06), Vector3(-26, 2.2, -10)), kit.mat("shell"))
	if stage >= 3:
		AnvilProps._dome(kit, high, Vector3(-26, 0, 28), 8.0, 3)
	_flush_stage(root, stage, b, ruin, high, fut)
	if stage >= 2:
		turbine(kit, root, Vector3(38, 0, -24), 30.0, 0)
	if stage >= 4:
		turbine(kit, root, Vector3(-40, 0, -6), 34.0, 1)
	trash(kit, root, 46.0, 12.0, 900, r, 501)
	plants(kit, root, 46.0, 12.0, 500, r, 601)


static func _cart_line(kit: AnvilEnv, b: Batch, a: Vector3, c: Vector3, carts: int) -> void:
	var d: Vector3 = c - a
	var n: int = int(d.length() / 1.2)
	var side := Vector3(-d.z, 0, d.x).normalized()
	for k: int in n:
		var p: Vector3 = a + d * (float(k) / n)
		AnvilProps.add_box(b, p + Vector3(0, 0.06, 0), Vector3(0.35, 0.16, 2.4), kit.mat("soot"), Vector3(0, rad_to_deg(atan2(-d.z, d.x)) + 90.0, 0))
	for off: float in [-0.75, 0.75]:
		AnvilProps.add_beam(b, a + side * off + Vector3(0, 0.25, 0), c + side * off + Vector3(0, 0.25, 0), 0.14, kit.mat("rust"))
	for k: int in carts:
		var p: Vector3 = a + d * (0.2 + 0.25 * k)
		var tip: float = 0.5 if k == 1 else 0.0
		var xf := Transform3D(Basis(Vector3.UP, atan2(-d.z, d.x)) * Basis(Vector3.RIGHT, tip), p + side * (1.6 if tip > 0.0 else 0.0))
		b.add(AnvilProps.box(), xf * Transform3D(Basis.from_scale(Vector3(2.4, 0.35, 1.5)), Vector3(0, 0.55, 0)), kit.mat("rust"))
		b.add(AnvilProps.noisy_cyl(1.25, 0.95, 1.5, 14, 2, 0.05, 50 + k), xf * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.75)), Vector3(0, 1.5, 0)), kit.mat("cart"))
		b.add(AnvilProps.slag_mesh(60 + k), xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.6, 0.7)), Vector3(0, 2.0, 0)), kit.mat("ore"))


static func _foundry_tower(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	ground_patch(kit, root, 42.0, 202)
	var b := Batch.new()
	var ruin := Batch.new()
	var high := Batch.new()
	var fut := Batch.new()
	slab(b, kit.mat("concrete"), Vector3.ZERO, Vector2(30, 30), 0.3, 9)
	AnvilProps._stack(kit, b, fut, Vector3(0, -4.0, 0), 128.0, 8.0, 3)
	# Buttresses: leaning lattice legs braced to the first gallery.
	for k: int in 4:
		var a: float = TAU * k / 4.0 + 0.4
		var d := Vector3(cos(a), 0, sin(a))
		var foot: Vector3 = d * 22.0
		var top: Vector3 = d * 9.2 + Vector3(0, 40.0, 0)
		for sgn: float in [-1.0, 1.0]:
			var off: Vector3 = Vector3(-d.z, 0, d.x) * 2.2 * sgn
			AnvilProps.add_beam(b, foot + off, top + off * 0.4, 0.8, kit.mat("rust"))
		for j: int in 6:
			var t0: float = float(j) / 6.0
			var t1: float = float(j + 1) / 6.0
			AnvilProps.add_beam(b, foot.lerp(top, t0) + Vector3(-d.z, 0, d.x) * 2.2, foot.lerp(top, t1) - Vector3(-d.z, 0, d.x) * 2.2 * (1.0 - t1 * 0.6), 0.3, kit.mat("rust"))
		AnvilProps.add_box(b, foot + Vector3(0, 0.8, 0), Vector3(4.0, 1.6, 4.0), kit.mat("concrete"), Vector3(0, rad_to_deg(-a), 0))
		fut.add(AnvilProps.box(), FrontierView._beam_xf(foot + Vector3(0, 0.3, 0), top - Vector3(0, 0.3, 0), 0.1), kit.mat("line"))
	# Pipes snaking out of the plinth into the ground.
	for k: int in 5:
		var a: float = 0.9 + k * 0.35
		var p0 := Vector3(cos(a) * 12.0, 2.5, sin(a) * 12.0)
		var p1 := Vector3(cos(a) * 30.0, -0.4, sin(a) * 30.0)
		b.add(AnvilProps.noisy_cyl(0.7, 0.7, 1.0, 12, 6, 0.02, 90 + k), FrontierView._beam_xf(p0, p1, 1.0), kit.mat("shell"))
	# Slag tips at the base.
	for k: int in 3:
		var a: float = 3.6 + k * 0.9
		b.add(AnvilProps.slag_mesh(30 + k), Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(8.0, 4.0 + k, 6.5)), Vector3(cos(a) * 28.0, -0.2, sin(a) * 28.0)), kit.slag_mat)
	ruin.add(AnvilProps.noisy_cyl(4.0, 4.2, 22.0, 28, 6, 0.05, 15), Transform3D(Basis(Vector3.UP, 2.2) * Basis(Vector3.FORWARD, PI * 0.5 + 0.08), Vector3(-24, 3.6, 18)), kit.mat("shell"))
	if stage >= 3:
		AnvilProps._dome(kit, high, Vector3(26, 0, -18), 7.0, 5)
	_flush_stage(root, stage, b, ruin, high, fut)
	trash(kit, root, 40.0, 14.0, 800, r, 503)
	plants(kit, root, 40.0, 14.0, 420, r, 603)


static func _lava_forge(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	ground_patch(kit, root, 46.0, 303)
	var b := Batch.new()
	var ruin := Batch.new()
	var high := Batch.new()
	var fut := Batch.new()
	var heat: float = 1.0 - 0.9 * smoothstep(0.1, 0.85, r)
	var lava: ShaderMaterial = lava_material(heat)
	# The furnace: a squat, bulging shell banded with straps, a hood and a soot-black chimney.
	var f := Vector3(-6, 0, -16)
	slab(b, kit.mat("concrete"), f + Vector3(0, 0, 2), Vector2(22, 18), 0.2, 13)
	b.add(AnvilProps.noisy_cyl(4.6, 7.2, 13.0, 36, 10, 0.035, 41), Transform3D(Basis(), f + Vector3(0, 6.5, 0)), kit.mat("shell"))
	for k: int in 5:
		var y: float = 1.5 + k * 2.6
		var rr: float = lerpf(7.2, 4.6, y / 13.0) + 0.2
		b.add(ProcMesh.torus(rr - 0.18, rr + 0.18, 40, 6), Transform3D(Basis(), f + Vector3(0, y, 0)), kit.mat("rust"))
	b.add(AnvilProps.noisy_cyl(1.6, 4.8, 4.0, 28, 4, 0.03, 42), Transform3D(Basis(), f + Vector3(0, 15.0, 0)), kit.mat("shell"))
	b.add(AnvilProps.noisy_cyl(1.3, 1.7, 26.0, 18, 10, 0.03, 43), Transform3D(Basis(), f + Vector3(0, 30.0, 0)), kit.mat("shell"))
	# Tuyeres: blast pipes ringing the hearth from a bustle main.
	b.add(ProcMesh.torus(8.0, 8.9, 48, 8), Transform3D(Basis(), f + Vector3(0, 5.0, 0)), kit.mat("stack"))
	for k: int in 10:
		var a: float = TAU * k / 10.0
		AnvilProps.add_beam(b, f + Vector3(cos(a) * 8.4, 5.0, sin(a) * 8.4), f + Vector3(cos(a) * 6.6, 2.4, sin(a) * 6.6), 0.45, kit.mat("rust"))
	# Tap hole glow at the front.
	var hole := StandardMaterial3D.new()
	hole.albedo_color = Color(0.2, 0.05, 0.02)
	hole.emission_enabled = true
	hole.emission = Color(1.0, 0.45, 0.12)
	hole.emission_energy_multiplier = 2.5 * heat + 0.3
	b.add(ProcMesh.sphere(1.2, 14, 8), Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 0.5)), f + Vector3(0, 1.0, 7.0)), hole)
	# The pour: a channel winding out to a cooling pool.
	var pts := PackedVector3Array()
	for k: int in 34:
		var t: float = float(k) / 33.0
		pts.append(f + Vector3(sin(t * 4.2) * 6.0 + t * 26.0, 0, 7.5 + t * 34.0))
	lava_channel(kit, root, pts, 2.6, lava, 7)
	var pool_c: Vector3 = pts[pts.size() - 1] + Vector3(3, 0, 4)
	var pool := MeshInstance3D.new()
	pool.name = "LavaPool"
	pool.mesh = lava_pool_mesh(7.5, 6.0, 88)
	pool.position = pool_c + Vector3(0, 0.1, 0)
	pool.material_override = lava
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	for k: int in 9:
		var a: float = TAU * k / 9.0
		b.add(AnvilProps.slag_mesh(120 + k), Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(2.6, 1.2, 2.0)), pool_c + Vector3(cos(a) * 7.6, -0.2, sin(a) * 6.2)), kit.slag_mat)
	# A ladle crane straddling the channel.
	var cc: Vector3 = pts[12]
	for sgn: float in [-1.0, 1.0]:
		var leg: Vector3 = cc + Vector3(-7.0 * sgn, 0, 2.0 * sgn)
		for dz: float in [-2.0, 2.0]:
			var lb: Vector3 = leg + Vector3(0, 0, dz)
			var lt: Vector3 = leg + Vector3(0, 12.0, 0)
			b.add(AnvilProps.noisy_cyl(0.32, 0.4, 1.0, 12, 4, 0.03, 70 + int(dz)), FrontierView._beam_xf(lb, lt, 1.0), kit.mat("rust"))
	AnvilProps.add_beam(b, cc + Vector3(-7.5, 12.4, -2.0), cc + Vector3(7.5, 12.4, 2.0), 1.1, kit.mat("hauler"))
	AnvilProps.add_beam(b, cc + Vector3(0, 12.0, 0), cc + Vector3(0, 6.5, 0), 0.08, kit.mat("soot"))
	b.add(AnvilProps.noisy_cyl(1.6, 1.1, 2.4, 18, 3, 0.05, 55), Transform3D(Basis(Vector3.RIGHT, 0.35), cc + Vector3(0, 5.2, 0)), kit.mat("shell"))
	# Restored: the forge feeds a greenhouse with its heat.
	if stage >= 3:
		AnvilProps._dome(kit, high, Vector3(-28, 0, 16), 8.0, 9)
	fut.add(ProcMesh.torus(7.3, 7.5, 64, 4), Transform3D(Basis(), f + Vector3(0, 0.4, 0)), kit.mat("line"))
	ruin.add(AnvilProps.noisy_cyl(1.3, 1.5, 12.0, 16, 4, 0.04, 66), Transform3D(Basis(Vector3.UP, 0.9) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(14, 1.2, -22)), kit.mat("shell"))
	_flush_stage(root, stage, b, ruin, high, fut)
	if stage >= 4:
		turbine(kit, root, Vector3(32, 0, -20), 28.0, 2)
	trash(kit, root, 44.0, 7.0, 800, r, 505)
	plants(kit, root, 44.0, 10.0, 420, r, 605)


static func _ruined_smelter(kit: AnvilEnv, root: Node3D, stage: int, restoration: float) -> void:
	var r: float = eff(stage, restoration)
	ground_patch(kit, root, 42.0, 404)
	var b := Batch.new()
	var ruin := Batch.new()
	var high := Batch.new()
	var fut := Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	slab(b, kit.mat("concrete"), Vector3(0, 0, -4), Vector2(40, 24), -0.1, 17)
	# The hall's frame: columns standing, leaning or snapped; fallen roof trusses.
	var basis := Basis(Vector3.UP, -0.1)
	for k: int in 8:
		for side: float in [-1.0, 1.0]:
			var base: Vector3 = basis * Vector3(-17.5 + k * 5.0, 0, side * 10.0) + Vector3(0, 0, -4)
			var hgt: float = 12.0 if rng.randf() > 0.3 else rng.randf_range(3.0, 8.0)
			var lean := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)) * (0.0 if hgt > 10.0 and rng.randf() > 0.4 else 1.0)
			AnvilProps.add_beam(b, base, base + lean + Vector3(0, hgt, 0), 0.6, kit.mat("rust"))
			fut.add(AnvilProps.noisy_cyl(0.75, 0.9, 1.0, 10, 4, 0.12, 200 + k), FrontierView._beam_xf(base, base + lean * 0.8 + Vector3(0, hgt * 0.8, 0), 1.0), kit.mat("green"))
			if hgt > 10.0 and k % 2 == 0:
				var top: Vector3 = base + lean + Vector3(0, hgt, 0)
				AnvilProps.add_beam(b, top, top + basis * Vector3(0, 1.5, -side * 10.0), 0.4, kit.mat("rust"))
				fut.add(AnvilProps.box(), FrontierView._beam_xf(top + Vector3(0, -0.4, 0), top + basis * Vector3(0, 1.1, -side * 10.0), 0.1), kit.mat("line"))
	for k: int in 4:
		var p: Vector3 = basis * Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-7, 7)) + Vector3(0, 0, -4)
		var q: Vector3 = p + Vector3(rng.randf_range(-6, 6), rng.randf_range(0.5, 3.0), rng.randf_range(-6, 6))
		AnvilProps.add_beam(b, p + Vector3(0, 0.3, 0), q, 0.5, kit.mat("rust"))
	# Smelting pots: one upright, one tipped, one spilled with a frozen slag tongue.
	var pots: Array = [[Vector3(-10, 0, 16), 0.0], [Vector3(2, 0, 18), 0.6], [Vector3(13, 0, 15), 1.45]]
	for k: int in pots.size():
		var pp: Vector3 = pots[k][0]
		var tilt: float = float(pots[k][1])
		var xf := Transform3D(Basis(Vector3.UP, k * 1.7) * Basis(Vector3.RIGHT, tilt), pp + Vector3(0, 3.0 * cos(tilt) + 0.6, 0))
		b.add(AnvilProps.noisy_cyl(3.2, 2.4, 6.0, 28, 6, 0.04, 300 + k), xf, kit.mat("shell"))
		b.add(ProcMesh.torus(3.1, 3.6, 32, 6), xf * Transform3D(Basis(), Vector3(0, 3.0, 0)), kit.mat("rust"))
		# Solid pot: a base and a crust of set slag inside, not a hollow cup.
		b.add(ProcMesh.cyl(2.4, 2.4, 0.4, 24), xf * Transform3D(Basis(), Vector3(0, -2.9, 0)), kit.mat("rust"))
		b.add(ProcMesh.cyl(3.05, 3.0, 0.5, 24), xf * Transform3D(Basis(), Vector3(0, 2.2, 0)), kit.slag_mat)
		if k == 2:
			b.add(AnvilProps.slag_mesh(310), Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3(8.0, 1.0, 4.0)), pp + Vector3(5.0, -0.1, 2.0)), kit.slag_mat)
	# The toppled stack, broken in two.
	b.add(AnvilProps.noisy_cyl(2.8, 3.2, 20.0, 28, 8, 0.05, 330), Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3.FORWARD, PI * 0.5 - 0.04), Vector3(-22, 3.0, -26)), kit.mat("shell"))
	b.add(AnvilProps.noisy_cyl(2.5, 2.8, 14.0, 28, 6, 0.06, 331), Transform3D(Basis(Vector3.UP, 0.75) * Basis(Vector3.FORWARD, PI * 0.5 + 0.12), Vector3(-5, 2.6, -32)), kit.mat("shell"))
	b.add(AnvilProps.slag_mesh(332), Transform3D(Basis.from_scale(Vector3(6.0, 3.5, 5.0)), Vector3(26, -0.2, -20)), kit.slag_mat)
	ruin.add(AnvilProps.slag_mesh(333), Transform3D(Basis.from_scale(Vector3(4.0, 2.0, 3.0)), Vector3(-28, -0.2, 8)), kit.mat("rust"))
	if stage >= 3:
		AnvilProps._dome(kit, high, Vector3(26, 0, 22), 7.0, 11)
	_flush_stage(root, stage, b, ruin, high, fut)
	trash(kit, root, 40.0, 6.0, 900, r, 507)
	plants(kit, root, 40.0, 6.0, 520, r * (1.2 if stage >= 4 else 1.0), 607)
