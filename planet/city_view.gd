class_name CityView
extends Node3D
## Builds the city around the play field from a CityLayout: sidewalks with curbs, buildings
## assembled from the modular facade kits, street furniture, and a hazy skyline backdrop.
## Static presentation; batched as MultiMeshes per block per kit piece.

const APT: String = "modular_urban_apartments_facade"
const FAC: String = "modular_factory_facade"
const FLOOR_H: float = 3.0
const BAY: float = 3.0

var layout: CityLayout
var ground_material: Material
var play_radius: float = 60.0

var _kit: Dictionary = {}  # kit id -> {name -> Mesh}
var _batches: Dictionary = {}  # "blockkey|kit|piece" -> Array[Transform3D]
var _rng := RandomNumberGenerator.new()
var _curb_mat: StandardMaterial3D
var _detail := BuildingDetail.new()
## Per-block merged building geometry (BuildingDetail.Geo): body (always drawn) and detail
## (rooftop props, balconies, fire escapes, awnings; culled beyond DETAIL_RANGE).
var _body: BuildingDetail.Geo
var _det: BuildingDetail.Geo
const DETAIL_RANGE: float = 240.0
## [deck] Static city batches: sidewalk tops / curbs / fences merged per 72 m cell (world ==
## object space for these, so merging is exact), fire escapes instanced per cell.
var _static := MeshBatch.new()
var _props := MeshBatch.new()
## [worlds2] A Cradle Mode world's facade tint (systems/world_look.gd): frosted, sun-bleached,
## coastal, overgrown or corroded cities. White on Verdance.
var look_tint := Color.WHITE
var _prop_body: StaticBody3D  # [world2] street furniture and lot fences (PhysLayers.PROP)
## [orbD] A hub site prefab on the globe (planet/sites/verdance_site.gd): no skyline backdrop
## (the globe's own far shell is the horizon).
var skyline: bool = true
## [orbD] false: sidewalks, kerbs, fences and street furniture only (the site places kit buildings).
var buildings: bool = true
## [orbD] Flush sidewalks (2 cm, no slab or kerb colliders): on a globe site loose junk lies on the
## cells under them, and a 12 cm slab hid it and snagged Lumi along the kerb.
var flush_walks: bool = false
## [v3city] Globe hub towns (planet/sites/verdance_site.gd): blocks within detail_ring get the
## kit facades, the rest proxies; proxy_collide gives every proxy building a box collider (the
## town is walkable, not a backdrop); street props reach prop_ring blocks within prop_radius m.
var detail_ring: int = DETAIL_RING
var proxy_collide: bool = false
var prop_ring: int = DETAIL_RING
var prop_radius: float = INF
var _bld_body: StaticBody3D  # [v3city] one body for every proxy building's box
## [v3city] func(x, z) -> bool: site-local point on a lake cell (globe towns): no props there.
var water_fn: Callable


func _wet(x: float, z: float) -> bool:
	return water_fn.is_valid() and bool(water_fn.call(x, z))


func _walk_h() -> float:  # [orbD] the sidewalk top street furniture stands on
	return 0.02 if flush_walks else CityLayout.CURB_H



func build(p_layout: CityLayout, p_ground_material: Material) -> void:
	layout = p_layout
	ground_material = p_ground_material
	_rng.seed = layout.seed_value + 1234
	look_tint = WorldLook.city_tint(WorldLook.current())  # [worlds2]
	_detail.world_tint = look_tint
	_static.cell = CityLayout.PITCH * 2.0
	_props.cell = CityLayout.PITCH * 2.0
	_props.visibility_end = 260.0
	_props.visibility_margin = StreetDressing.VIS_MARGIN  # [v8bld] hysteresis
	await _load_kit(APT)
	await _load_kit(FAC)
	if buildings:  # [v5load] the fire escape's file and its light mesh (130 ms inside the first apartment block)
		var fe: Resource = await BuildBudget.fetch(AssetLib.MODEL_DIR % ["modular_fire_escape", "modular_fire_escape"])
		await BuildBudget.check("city:fire escape")
		AssetLib.lite(_fire_escape_mesh("modular_fire_escape_platform_middle"), 800)
		fe = null
	_curb_mat = AssetLib.pbr_material("concrete_pavement", 1.2, Color(0.82, 0.8, 0.78), true)
	var bi: int = 0
	for key: Vector2i in layout.blocks:
		bi += 1
		BuildBudget.sub(0.6 * float(bi) / layout.blocks.size())
		await BuildBudget.check("city:block")  # [leftovers] time-sliced behind the loading screen
		await _build_block(key, layout.blocks[key])
	await BuildBudget.check("city:batches")
	await _flush_batches()
	if not layout.wild:
		await BuildBudget.check("city:props")
		await _build_street_props()
		if skyline:  # [orbD]
			await BuildBudget.check("city:skyline")
			await _build_skyline()  # wilderness has its own horizon (FieldView hills and biome wrecks)
	await BuildBudget.check("city:static")
	await _static.flush_async(self)
	await BuildBudget.check("city:props flush")
	await _props.flush_async(self)


# --- Kit --------------------------------------------------------------------------

func _load_kit(id: String) -> void:
	var keep: Resource = await BuildBudget.fetch(AssetLib.MODEL_DIR % [id, id])  # [leftovers]
	await BuildBudget.check("city:kit")
	var ps: PackedScene = keep if keep is PackedScene else load(AssetLib.MODEL_DIR % [id, id])
	var root: Node = ps.instantiate()
	var d: Dictionary = {}
	for c: Node in root.get_children():
		if c is MeshInstance3D:
			d[String(c.name)] = (c as MeshInstance3D).mesh
	root.free()
	_kit[id] = d


## Random piece whose name starts with prefix (e.g. "window_centered_large_").
func _pick(kit: String, prefix: String) -> String:
	var names: Array = []
	for n: String in _kit[kit]:
		if n.begins_with(prefix):
			names.append(n)
	if names.is_empty():
		return ""
	return names[_rng.randi() % names.size()]


func _place(_block: Vector2i, kit: String, piece: String, xf: Transform3D) -> void:
	if piece == "" or not (_kit[kit] as Dictionary).has(piece):
		return
	# [deck] One MultiMesh per kit piece for the whole detail ring (was one per block per piece).
	var key: String = "%s|%s" % [kit, piece]
	if not _batches.has(key):
		_batches[key] = []
	var arr: Array = _batches[key]
	arr.append(xf)
	_batches[key] = arr


func _flush_batches() -> void:
	for key: String in _batches:
		await BuildBudget.check("city:batch")
		var parts: PackedStringArray = key.split("|")
		var mesh: Mesh = AssetLib.lite(_kit[parts[0]][parts[1]], 600)
		var xfs: Array = _batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.set_meta("inst_xf", xfs)  # [world2] for the collider audit
		mmi.visibility_range_end = 420.0
		mmi.visibility_range_end_margin = StreetDressing.VIS_MARGIN  # [v8bld]
		# [v5load] Facade pieces that lie flat on the wall (windows, doors, panels, trims: under
		# FLAT_PIECE_M deep) don't cast: the building's body behind them does, and at the sun's
		# shadow resolution a few centimetres of relief never showed. Balconies, awnings and the
		# like keep their shadows. About a third of the town's shadow draws.
		var bb: Vector3 = mesh.get_aabb().size
		if minf(bb.x, minf(bb.y, bb.z)) < FLAT_PIECE_M and not DevHooks.has("no-shadow-trim"):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_batches.clear()


const FLAT_PIECE_M: float = 0.3
const CORE_IN: float = 0.03  # [v9bld] the dark core inside the shell walls


# --- Blocks -------------------------------------------------------------------------

## Blocks within this Chebyshev distance of the hub get full kit detail; the rest are proxies.
const DETAIL_RING: int = 1


func _build_block(key: Vector2i, b: Dictionary) -> void:
	var rect: Rect2 = b["rect"]
	if layout.wild:
		return  # the hub yard's fence belongs to StreetDressing (it is ruined, then repaired)
	var detailed: bool = maxi(absi(key.x), absi(key.y)) <= detail_ring  # [v3city]
	_build_sidewalks(rect, detailed)
	match int(b["type"]):
		CityLayout.Block.BUILDINGS:
			_body = BuildingDetail.Geo.new()
			_det = BuildingDetail.Geo.new()
			for bd: Dictionary in (b["buildings"] if buildings else []):  # [orbD]
				if detailed:
					_build_building(key, bd)
				else:
					_detail.proxy_building(bd, _body, _det)
					if proxy_collide:  # [v3city]
						_proxy_box(bd)
				await BuildBudget.check("city:building")  # [v5load] a detailed block was one 150 ms slice
			_flush_block(key)
		CityLayout.Block.HUB:
			pass  # yard fence: StreetDressing
		CityLayout.Block.PARKING, CityLayout.Block.VACANT:
			_build_fence(rect, false)


## [v3city] A proxy building's collider: its footprint up to the roof (tiers set back above).
func _proxy_box(bd: Dictionary) -> void:
	if _bld_body == null:
		_bld_body = StaticBody3D.new()
		_bld_body.name = "ProxyBuildings"
		add_child(_bld_body)
	var r: Rect2 = bd["rect"]
	var h: float = float(bd["floors"]) * FLOOR_H
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r.size.x, h, r.size.y)
	cs.shape = box
	cs.position = Vector3(r.get_center().x, h * 0.5, r.get_center().y)
	_bld_body.add_child(cs)


## One body and one detail MeshInstance per block, centred on the block so the detail mesh's
## visibility range measures from there.
func _flush_block(key: Vector2i) -> void:
	var c := Vector3(key.x * CityLayout.PITCH, 0.0, key.y * CityLayout.PITCH)
	for pass_i: int in 2:
		var g: BuildingDetail.Geo = _body if pass_i == 0 else _det
		if g == null or g.empty():
			continue
		if pass_i == 0:
			# [deck] Bodies merge per 72 m cell (world-space shader: exact); detail meshes stay per
			# block so their 240 m visibility range still measures from the block.
			_static.merge(g.mesh(c), Transform3D(Basis.IDENTITY, c), BuildingDetail.material(), true)
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Buildings%s_%d_%d" % ["" if pass_i == 0 else "Detail", key.x, key.y]
		mi.mesh = g.mesh(c)
		mi.material_override = BuildingDetail.material()
		mi.position = c
		if pass_i == 1:
			mi.visibility_range_end = DETAIL_RANGE
			mi.visibility_range_end_margin = 20.0
		add_child(mi)
	_body = null
	_det = null


func _build_sidewalks(r: Rect2, detailed: bool = true) -> void:
	# Sidewalk ring around the block: 4 slabs; tops use the shared ground shader so hex state
	# and dirt show on them; curb faces are concrete. Collision slopes up so Patch can roll on.
	var w: float = CityLayout.WALK_W
	var h: float = CityLayout.CURB_H if not flush_walks else 0.02  # [orbD]
	var outer := r.grow(w)
	var slabs: Array[Rect2] = [
		Rect2(outer.position, Vector2(outer.size.x, w)),
		Rect2(Vector2(outer.position.x, r.end.y), Vector2(outer.size.x, w)),
		Rect2(Vector2(outer.position.x, r.position.y), Vector2(w, r.size.y)),
		Rect2(Vector2(r.end.x, r.position.y), Vector2(w, r.size.y)),
	]
	if water_fn.is_valid():  # [v3city] a lakeside block: its sidewalk and kerb stop at the shore
		slabs = _dry_pieces(slabs)
	for s: Rect2 in slabs:
		var pm := PlaneMesh.new()
		pm.size = s.size
		pm.subdivide_width = int(s.size.x / 2.0)
		pm.subdivide_depth = int(s.size.y / 2.0)
		pm.material = ground_material
		_static.merge(pm, Transform3D(Basis.IDENTITY, Vector3(s.get_center().x, h, s.get_center().y)), null, false)  # [deck]
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		var x0: float = s.position.x
		var x1: float = s.end.x
		var z0: float = s.position.y
		var z1: float = s.end.y
		var bev: float = 0.35
		shape.points = PackedVector3Array([
			Vector3(x0 - bev, 0, z0 - bev), Vector3(x1 + bev, 0, z0 - bev), Vector3(x1 + bev, 0, z1 + bev), Vector3(x0 - bev, 0, z1 + bev),
			Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)])
		cs.shape = shape
		body.add_child(cs)
		if detailed and not flush_walks:  # [orbD] flush walks: nothing to catch on (globe sites)
			add_child(body)
		else:
			body.free()
	# Curb faces (outer edge only, facing the road).
	var curb_parts: Array = []
	var edges: Array = [[outer.position, Vector2(outer.end.x, outer.position.y)], [Vector2(outer.position.x, outer.end.y), outer.end],
			[outer.position, Vector2(outer.position.x, outer.end.y)], [Vector2(outer.end.x, outer.position.y), outer.end]]
	if water_fn.is_valid():  # [v3city] kerb runs only on dry ground
		var dry: Array = []
		for e0: Array in edges:
			var a0: Vector2 = e0[0]
			var b0: Vector2 = e0[1]
			var k: int = maxi(1, int(ceil(a0.distance_to(b0) / 3.0)))
			for i: int in k:
				var p0: Vector2 = a0.lerp(b0, float(i) / k)
				var p1: Vector2 = a0.lerp(b0, float(i + 1) / k)
				var m0: Vector2 = (p0 + p1) * 0.5
				if not _wet(m0.x, m0.y) and not _wet(p0.x, p0.y) and not _wet(p1.x, p1.y):
					dry.append([p0, p1])
		edges = dry
	for e: Array in edges:
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var len_: float = a.distance_to(bb)
		var mid: Vector2 = (a + bb) * 0.5
		var horiz: bool = absf(a.y - bb.y) < 0.01
		curb_parts.append(ProcMesh.part(ProcMesh.box(Vector3(len_, h + 0.02, 0.22) if horiz else Vector3(0.22, h + 0.02, len_)),
			ProcMesh.xf(Vector3(mid.x, h * 0.5 - 0.005, mid.y))))
	_static.merge(ProcMesh.merge(curb_parts), Transform3D.IDENTITY, _curb_mat, true, Vector3(r.get_center().x, 0, r.get_center().y))  # [deck]


## [v3city] Slabs cut into pieces of at most 3 m, keeping only the dry ones.
func _dry_pieces(slabs: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in slabs:
		var along_x: bool = r.size.x >= r.size.y
		var length: float = r.size.x if along_x else r.size.y
		var k: int = maxi(1, int(ceil(length / 3.0)))
		var step: float = length / k
		for i: int in k:
			var pr: Rect2 = Rect2(r.position + Vector2(i * step, 0), Vector2(step, r.size.y)) if along_x \
				else Rect2(r.position + Vector2(0, i * step), Vector2(r.size.x, step))
			var wet: bool = false
			for q: Vector2 in [pr.get_center(), pr.position, pr.end, Vector2(pr.position.x, pr.end.y), Vector2(pr.end.x, pr.position.y)]:
				if _wet(q.x, q.y):
					wet = true
					break
			if not wet:
				out.append(pr)
	return out


func _build_building(block: Vector2i, bd: Dictionary) -> void:
	var r: Rect2 = bd["rect"]
	var face: Vector2 = bd["face"]
	var floors: int = int(bd["floors"])
	var kit: String = FAC if bd["style"] == "factory" else APT
	var bays: int = int(bd["bays"])
	_rng.seed = int(bd["seed"])
	var height: float = floors * FLOOR_H
	# Facade line and direction along it.
	var along: Vector2
	var origin: Vector2
	if face.y < 0:
		along = Vector2(1, 0)
		origin = Vector2(r.position.x, r.position.y)
	elif face.y > 0:
		along = Vector2(-1, 0)
		origin = Vector2(r.end.x, r.end.y)
	elif face.x < 0:
		along = Vector2(0, -1)
		origin = Vector2(r.position.x, r.end.y)
	else:
		along = Vector2(0, 1)
		origin = Vector2(r.end.x, r.position.y)
	# Kit modules span local x in [-3, 0] and face local +Z. Build a basis: local +X = along, +Z = face.
	var bx := Vector3(along.x, 0, along.y)
	var bz := Vector3(face.x, 0, face.y)
	var basis_ := Basis(bx, Vector3.UP, bz)
	var ruin_from: int = floors
	if bd.get("ruined", false):
		ruin_from = maxi(1, floors - _rng.randi_range(1, 3))
	for i: int in bays:
		var bay_floors: int = floors if i % 3 != 1 or ruin_from == floors else ruin_from
		var o2: Vector2 = origin + along * (i + 1) * BAY
		for f: int in bay_floors:
			var o := Vector3(o2.x, f * FLOOR_H, o2.y)
			var xf := Transform3D(basis_, o)
			var opening: String
			if f == 0:
				opening = ["door_centered_large", "door_centered_small", "door_offset_small", "window_centered_large", "window_centered_double"][_rng.randi() % 5] if kit == APT \
					else ["door_centered_large", "window_tall_large", "window_tall_small", "door_recessed_large"][_rng.randi() % 4]
			else:
				opening = ["window_centered_large", "window_centered_small", "window_centered_double", "window_offset_small"][_rng.randi() % 4] if kit == APT \
					else ["window_centered_large", "window_centered_medium", "window_centered_small", "window_centered_double"][_rng.randi() % 4]
			var wall: String = _pick(kit, "wall_" + opening + "_")
			if wall == "":
				wall = _pick(kit, "wall_standard_standard_")
				opening = ""
			_place(block, kit, wall, xf)
			if opening != "":
				# Boarded/broken windows: sometimes the frame is missing entirely (dark hole).
				if _rng.randf() > 0.12:
					_place(block, kit, _pick(kit, opening + "_"), xf)
			if f > 0 and f == bay_floors - 1:
				_place(block, kit, _pick(kit, "crown_standard_standard_"), Transform3D(basis_, o + Vector3(0, FLOOR_H, 0)))
			elif f < bay_floors - 1 and (f == 0 or _rng.randf() < 0.3):
				_place(block, kit, _pick(kit, "cornice_standard_standard_") if kit == APT else _pick(kit, "cornice02_standard_standard_"), Transform3D(basis_, o + Vector3(0, FLOOR_H, 0)))
		_place(block, kit, _pick(kit, "base_standard_"), Transform3D(basis_, Vector3(o2.x, 0, o2.y)))
	# Interior/back mass, set just behind the facade so windows read as dark rooms.
	var inset: float = 0.35
	var mass_r: Rect2 = r
	if face.y < 0:
		mass_r = Rect2(r.position + Vector2(0, inset), r.size - Vector2(0, inset))
	elif face.y > 0:
		mass_r = Rect2(r.position, r.size - Vector2(0, inset))
	elif face.x < 0:
		mass_r = Rect2(r.position + Vector2(inset, 0), r.size - Vector2(inset, 0))
	else:
		mass_r = Rect2(r.position, r.size - Vector2(inset, 0))
	var mass_h: float = float(maxi(ruin_from, 1) if ruin_from < floors else floors) * FLOOR_H
	# Interior mass (dark rooms behind the windows), side/back walls with windows, and the
	# roof (membrane, parapets, bulkheads, HVAC, tanks...) all go into the block's merged mesh.
	# [v9bld] The dark core sits CORE_IN m inside the shell's side and back walls (its front stays just
	# behind the kit facade). It used to stand 2 cm outside them, so every near building's sides and
	# back were flat black slabs (the start yard looked straight at one).
	var core_r: Rect2 = BuildingDetail._inset_front(mass_r.grow(-CORE_IN), face, -CORE_IN, 0.0)
	_body.mat(BuildingDetail.K_DARK, Color(0.05, 0.045, 0.045))
	_body.abox(Vector3(core_r.position.x, 0.0, core_r.position.y), Vector3(core_r.size.x, mass_h - 0.05, core_r.size.y))
	var pal: Array = BuildingDetail.APT_PALETTE[(int(bd["seed"]) >> 3) % BuildingDetail.APT_PALETTE.size()]
	# The shell: the side and back walls on the footprint's edges, its front a little behind the
	# core's (the core's front is what the kit windows show).
	var shell_r: Rect2 = BuildingDetail._inset_front(r, face, inset + 0.05, 0.0)
	_body.uv = BuildingDetail._bay_uv(r, int(bd["seed"]) & 0xffff)
	_body.mat(BuildingDetail.K_FACADE, pal[1] * look_tint, pal[0], BuildingDetail.F_RIBBON if kit == FAC else 0)  # [worlds2] tint
	_body.abox(Vector3(shell_r.position.x, 0.0, shell_r.position.y), Vector3(shell_r.size.x, height, shell_r.size.y), BuildingDetail.K_ROOF if ruin_from < floors else -2)
	_detail.kit_roof(_body, _det, r, face, mass_h, floors, kit == FAC, int(bd["seed"]), ruin_from < floors)
	# Fire escape on some apartment facades.
	if kit == APT and floors >= 3 and _rng.randf() < 0.45:
		var bay: int = _rng.randi_range(0, maxi(bays - 2, 0))
		var o2: Vector2 = origin + along * (bay + 1.5) * BAY + face * 0.7
		for f: int in range(1, floors):
			_static.instance(AssetLib.lite(_fire_escape_mesh("modular_fire_escape_platform_middle"), 800), Transform3D(basis_, Vector3(o2.x, f * FLOOR_H, o2.y)))  # [deck]
	# Collision for the whole building footprint.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r.size.x, height, r.size.y)
	cs.shape = box
	cs.position = Vector3(r.get_center().x, height * 0.5, r.get_center().y)
	body.add_child(cs)
	add_child(body)


var _fe_cache: Dictionary = {}


func _fire_escape_mesh(node: String) -> Mesh:
	if _fe_cache.has(node):
		return _fe_cache[node]
	var ps: PackedScene = load(AssetLib.MODEL_DIR % ["modular_fire_escape", "modular_fire_escape"])
	var root: Node = ps.instantiate()
	var mesh: Mesh = null
	for c: Node in root.get_children():
		if c is MeshInstance3D and String(c.name) == node:
			mesh = (c as MeshInstance3D).mesh
	root.free()
	_fe_cache[node] = mesh
	return mesh


func _build_fence(r: Rect2, partial: bool) -> void:
	# [world2] Broken chain-link runs along a lot's edges: a few panels standing, then a gap where
	# the fence is down, so a lot is never boxed in. Each standing run gets one thin box collider.
	var mat: StandardMaterial3D = Mats.metal("steel")
	var parts: Array = []
	if _prop_body == null:
		_prop_body = PropColliders.body(self, "StreetProps")
	var edges: Array = [[r.position, Vector2(r.end.x, r.position.y)], [r.position, Vector2(r.position.x, r.end.y)]]
	if not partial:
		edges.append([Vector2(r.end.x, r.position.y), r.end])
	for e: Array in edges:
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var n: int = int(a.distance_to(bb) / 2.5)
		var k: int = _rng.randi_range(0, 2)  # start a little way in: corners stay open
		while k < n:
			var run: int = mini(_rng.randi_range(1, 3), n - k)
			var p0: Vector2 = a.lerp(bb, float(k) / n)
			var p1: Vector2 = a.lerp(bb, float(k + run) / n)
			if _wet(p0.x, p0.y) or _wet(p1.x, p1.y):  # [v3city] no fence out in the lake
				k += run + 2
				continue
			for q: int in run + 1:
				var p: Vector2 = a.lerp(bb, float(k + q) / n)
				parts.append(ProcMesh.part(ProcMesh.cyl(0.03, 0.03, 1.8, 6), ProcMesh.xf(Vector3(p.x, 0.9, p.y), Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4)))))
			var mid: Vector2 = (p0 + p1) * 0.5
			var len_: float = p0.distance_to(p1)
			var horiz: bool = absf(a.y - bb.y) < 0.01
			for y: float in [1.78, 0.9]:
				parts.append(ProcMesh.part(ProcMesh.cyl(0.02, 0.02, len_, 6), ProcMesh.xf(Vector3(mid.x, y, mid.y), Vector3(0, 0, 90) if horiz else Vector3(90, 0, 0))))
			# Chain-link suggested by a diagonal lattice of thin wires.
			for q: int in int(len_ / 0.6):
				var t0: float = float(q) / int(len_ / 0.6)
				var t1: float = minf(t0 + 0.6 / len_, 1.0)
				var x0: Vector2 = p0.lerp(p1, t0)
				var x1: Vector2 = p0.lerp(p1, t1)
				var d3 := Vector3(x1.x - x0.x, 1.6, x1.y - x0.y)
				var c3 := Vector3((x0.x + x1.x) * 0.5, 0.88, (x0.y + x1.y) * 0.5)
				parts.append(ProcMesh.part(ProcMesh.cyl(0.006, 0.006, d3.length(), 3), Transform3D(_align_y(d3), c3)))
				var d4 := Vector3(x0.x - x1.x, 1.6, x0.y - x1.y)
				parts.append(ProcMesh.part(ProcMesh.cyl(0.006, 0.006, d4.length(), 3), Transform3D(_align_y(d4), c3)))
			PropColliders.add_run(_prop_body, Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y), 1.8, 0.16)
			k += run + _rng.randi_range(2, 3)  # the gap: two or three panels down
	_static.merge(ProcMesh.merge(parts), Transform3D.IDENTITY, mat, true, Vector3(r.get_center().x, 0, r.get_center().y))  # [deck]


## Basis whose Y axis points along d (for rods between two points).
static func _align_y(d: Vector3) -> Basis:
	var y: Vector3 = d.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


# --- Street furniture ---------------------------------------------------------------

## [deck] Street props are instanced per model and 72 m cell (MeshBatch); collision stays as
## plain StaticBody3D nodes with the same transform.
func _mesh_prop(model: String, pos: Vector3, yaw: float, collide: bool, scl: float = 1.0, roll: float = 0.0) -> void:
	if _wet(pos.x, pos.z):
		return  # [v3city] not on the lake
	var mesh: Mesh = AssetLib.lite(AssetLib.model_part(model.get_slice("::", 0), model.get_slice("::", 1)) if "::" in model else AssetLib.model_mesh(model), 2500)
	var xf := Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)) * Basis.from_scale(Vector3.ONE * scl), pos)
	# [v5load] Props that lie on the ground (manhole covers, grates: under 12 cm tall) cast no shadow.
	_props.instance(mesh, xf, null, mesh.get_aabb().size.y * scl >= 0.12 or DevHooks.has("no-shadow-trim"))
	if collide:
		# [world2] One shared PROP body, shared shapes; lamp posts get a slim post (their heads and
		# arms are overhead), everything else a box of its bounds.
		if _prop_body == null:
			_prop_body = PropColliders.body(self, "StreetProps")
		var aabb: AABB = mesh.get_aabb()
		var rot := Basis.from_euler(Vector3(0.0, yaw, roll))
		if "lamp" in model:
			# [v6feel] A round pole (a 0.3 m box's corners caught Lumi and narrowed the gap to walls).
			PropColliders.add_cyl(_prop_body, pos, 0.12, aabb.end.y * scl)
		else:
			PropColliders.add_box(_prop_body, Transform3D(rot, pos + rot * (aabb.get_center() * scl)), Vector3(maxf(aabb.size.x, 0.2), aabb.size.y, maxf(aabb.size.z, 0.2)) * scl * 0.9)


## [world3] Street lamp heads, [Transform3D, Color]: dead bulbs that StreetPower lights by hex.
var lamp_bulbs: Array = []
static var _bulb_at: Dictionary = {}


## Centre and size of a lamp model's bulb (its "*_bulb" / "*_glass" surfaces).
static func lamp_head(model: String) -> Array:
	if _bulb_at.has(model):
		return _bulb_at[model]
	var out: Array = [Vector3(0, 3.0, 0), 0.12]
	var m: Mesh = AssetLib.model_mesh(model) if AssetLib.has_model(model) else null
	if m:
		for s: int in m.get_surface_count():
			var mat: Material = m.surface_get_material(s)
			var nm: String = mat.resource_name if mat else ""
			if nm.ends_with("_glass") or nm.ends_with("_bulb"):
				var lo := Vector3(1e9, 1e9, 1e9)
				var hi := -lo
				for v: Vector3 in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
					lo = lo.min(v)
					hi = hi.max(v)
				if nm.ends_with("_bulb"):
					out[0] = (lo + hi) * 0.5
				else:
					out[1] = minf(hi.x - lo.x, hi.y - lo.y) * 0.3
	_bulb_at[model] = out
	return out


func _build_street_props() -> void:
	var lamp_spacing: float = 18.0
	var n: int = int(layout.extent / CityLayout.PITCH)
	var half: float = CityLayout.PITCH * 0.5
	var walk_mid: float = half - CityLayout.ROAD_W * 0.5 - CityLayout.WALK_W * 0.5
	for bx: int in range(-n, n + 1):
		for bz: int in range(-n, n + 1):
			await BuildBudget.check("city:street props")
			var c := Vector2(bx, bz) * CityLayout.PITCH
			if c.length() > (prop_radius if prop_radius < INF else layout.extent):  # [v3city]
				continue
			if prop_radius < INF and not layout.blocks.has(Vector2i(bx, bz)):
				continue  # [v3city] a globe town's dropped blocks (off the pad)
			var near: bool = maxi(absi(bx), absi(bz)) <= prop_ring  # [v3city]
			if not near:
				continue
			# Lamps and poles on two sidewalks of each block.
			for side: int in 2:
				var count: int = int(CityLayout.PITCH / lamp_spacing)
				for k: int in count:
					var t: float = -half + 6.0 + k * lamp_spacing
					var p: Vector2 = c + (Vector2(t, -walk_mid - 0.6) if side == 0 else Vector2(walk_mid + 0.6, t))
					var yaw: float = PI if side == 0 else -PI * 0.5
					if _rng.randf() < 0.75 and not _wet(p.x, p.y):  # [v3city]
						var lamp_model: String = "street_lamp_02" if _rng.randf() < 0.5 else "street_lamp_01"
						var lamp_yaw: float = yaw + _rng.randf_range(-0.05, 0.05)
						var lean: float = _rng.randf_range(-0.15, 0.15) if _rng.randf() < 0.15 else 0.0  # leaning, half-collapsed
						if lean == 0.0 and fmod(absf(p.x * 0.37 + p.y * 0.61), 1.0) < 0.2:
							lean = 0.2 if p.x > p.y else -0.18  # [world3] more of them bent (own hash: the RNG stays as it was)
						_mesh_prop(lamp_model, Vector3(p.x, _walk_h(), p.y), lamp_yaw, near, 1.0, lean)
						if lean == 0.0:  # [world3] standing ones get a (dead) bulb; bent ones are beyond repair
							var head: Array = lamp_head(lamp_model)
							var lxf := Transform3D(Basis.from_euler(Vector3(0.0, lamp_yaw, 0.0)), Vector3(p.x, _walk_h(), p.y))
							var r: float = head[1]
							lamp_bulbs.append([Transform3D(Basis().scaled(Vector3(r, r * 1.2, r) / 0.06), lxf * (head[0] as Vector3)), Color(1.0, 0.86, 0.62)])
			if not near:
				continue
			# Hydrant, manholes, a payphone, benches, utility boxes.
			var q: Vector2 = c + Vector2(_rng.randf_range(-half + 5, half - 5), -walk_mid + 0.7)
			_mesh_prop("fire_hydrant::fire_hydrant_aged", Vector3(q.x, _walk_h(), q.y), _rng.randf() * TAU, true)
			var m: Vector2 = c + Vector2(_rng.randf_range(-6, 6), half)
			_mesh_prop("water_manhole_cover", Vector3(m.x, 0.005, m.y), _rng.randf() * TAU, false)
			if _rng.randf() < 0.4:
				var u: Vector2 = c + Vector2(walk_mid + 0.5, _rng.randf_range(-half + 4, half - 4))
				_mesh_prop("utility_box_01", Vector3(u.x, _walk_h(), u.y), -PI * 0.5, true)
			if _rng.randf() < 0.1:
				var pp: Vector2 = c + Vector2(_rng.randf_range(-half + 4, half - 4), walk_mid + 0.3)
				_mesh_prop("korean_public_payphone_01", Vector3(pp.x, _walk_h(), pp.y), 0.0, true)


# --- Skyline ------------------------------------------------------------------------

func _build_skyline() -> void:
	# Far city: real building silhouettes (windows, floor bands, grime) in sun-faded facade colours,
	# with setbacks, rooftop water tanks, masts and AC boxes, a few broken tops. They fade into haze.
	var facades: Array = [["painted_concrete", Color(0.86, 0.78, 0.66)], ["brick_wall_02", Color(0.9, 0.82, 0.76)],
		["red_brick", Color(0.88, 0.72, 0.66)], ["factory_wall", Color(0.8, 0.82, 0.8)], ["painted_concrete", Color(0.7, 0.8, 0.82)],
		["painted_concrete", Color(0.92, 0.86, 0.72)], ["concrete_wall_008", Color(0.78, 0.76, 0.74)]]
	var mats: Array[ShaderMaterial] = []
	for i: int in facades.size():
		var m := ShaderMaterial.new()
		m.shader = preload("res://art/shaders/building_far.gdshader")
		m.set_shader_parameter("wall_alb", AssetLib.tex(facades[i][0], "diff"))
		m.set_shader_parameter("wall_nrm", AssetLib.tex(facades[i][0], "nor_gl"))
		m.set_shader_parameter("tint", facades[i][1] * look_tint)  # [worlds2]
		m.set_shader_parameter("seed", 3.1 + float(i) * 0.61)
		mats.append(m)
	var roof_mat: StandardMaterial3D = AssetLib.pbr_material("concrete_wall_008", 0.2, Color(0.55, 0.53, 0.5), true)
	var rust_mat: StandardMaterial3D = AssetLib.pbr_material("rusty_metal_02", 0.5, Color(0.9, 0.85, 0.8), true)
	var r0: float = layout.extent + 20.0
	# [deck] Batched: far-shader masses merge per material (the shader is world-space), roof
	# props instance per mesh (their triplanar materials are object-space). ~700 nodes -> ~20.
	# Four quadrant cells keep frustum culling useful.
	var batch := MeshBatch.new()
	batch.cell = r0 + 200.0
	var tank_mesh: Mesh = ProcMesh.cyl(1.6, 1.6, 3.0, 12)
	var leg_mesh: Mesh = ProcMesh.cyl(0.12, 0.12, 2.2, 5)
	var ac_mesh: Mesh = ProcMesh.box(Vector3(2.0, 1.2, 1.6))
	# Unique-size slabs and masts merge with world-space triplanar copies (same texture scale; at
	# 200+ m in haze only the projection's phase differs).
	var roof_w: StandardMaterial3D = roof_mat.duplicate()
	roof_w.uv1_world_triplanar = true
	var rust_w: StandardMaterial3D = rust_mat.duplicate()
	rust_w.uv1_world_triplanar = true
	for i: int in 90:
		if i % 10 == 9:
			await BuildBudget.check("city:skyline")
		var ang: float = TAU * i / 90.0 + _rng.randf_range(-0.03, 0.03)
		var dist: float = r0 + _rng.randf_range(0.0, 170.0)
		var w: float = _rng.randf_range(14.0, 28.0)
		var d: float = w * _rng.randf_range(0.7, 1.2)
		var h: float = roundf(_rng.randf_range(24.0, 110.0) / 3.0) * 3.0
		var root := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(cos(ang) * dist, -1.0, sin(ang) * dist))
		var at := func(p: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
			return root * Transform3D(Basis.from_euler(rot), p)
		var mat: ShaderMaterial = mats[_rng.randi() % mats.size()]
		var y: float = 0.0
		var cw: float = w
		var cd: float = d
		var tiers: int = 1 + (_rng.randi() % 3 if h > 50.0 else 0)
		for t: int in tiers:
			var th: float = h / float(tiers) * (1.2 if t == 0 else 0.9)
			batch.merge(ProcMesh.box(Vector3(cw, th, cd)), at.call(Vector3(0, y + th * 0.5, 0)), mat, false)
			y += th
			cw *= _rng.randf_range(0.65, 0.85)
			cd *= _rng.randf_range(0.65, 0.85)
		# Roof: parapet slab plus clutter.
		batch.merge(ProcMesh.box(Vector3(cw / 0.75 * 0.98, 0.6, cd / 0.75 * 0.98)), at.call(Vector3(0, y + 0.3, 0)), roof_w, false)
		if _rng.randf() < 0.6:
			var tp := Vector3(_rng.randf_range(-cw, cw) * 0.25, y + 3.6, _rng.randf_range(-cd, cd) * 0.25)
			batch.instance(tank_mesh, at.call(tp), rust_mat, false)
			for k: int in 4:
				batch.instance(leg_mesh, at.call(tp + Vector3((1.0 if k % 2 == 0 else -1.0) * 1.1, -2.6, (1.0 if k < 2 else -1.0) * 1.1)), rust_mat, true)
		if _rng.randf() < 0.45:
			var mh: float = _rng.randf_range(5.0, 14.0)
			var mast_mesh: Mesh = ProcMesh.cyl(0.15, 0.3, mh, 6)
			batch.merge(mast_mesh, at.call(Vector3(_rng.randf_range(-cw, cw) * 0.3, y + mh * 0.5, _rng.randf_range(-cd, cd) * 0.3)), rust_w, true)
		for k: int in _rng.randi() % 4:
			batch.instance(ac_mesh, at.call(Vector3(_rng.randf_range(-cw, cw) * 0.35, y + 1.2, _rng.randf_range(-cd, cd) * 0.35)), roof_mat, false)
		if _rng.randf() < 0.18:
			# Broken top: a tilted slab of the last floor.
			batch.merge(ProcMesh.box(Vector3(cw * 0.6, 4.0, cd * 0.5)), at.call(Vector3(cw * 0.15, y + 1.2, 0), Vector3(0.0, 0.0, _rng.randf_range(0.25, 0.5))), mat, true)
	var sky := Node3D.new()
	sky.name = "Skyline"
	add_child(sky)
	batch.flush(sky)
