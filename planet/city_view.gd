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


func build(p_layout: CityLayout, p_ground_material: Material) -> void:
	layout = p_layout
	ground_material = p_ground_material
	_rng.seed = layout.seed_value + 1234
	look_tint = WorldLook.city_tint(WorldLook.current())  # [worlds2]
	_detail.world_tint = look_tint
	_static.cell = CityLayout.PITCH * 2.0
	_props.cell = CityLayout.PITCH * 2.0
	_props.visibility_end = 260.0
	_load_kit(APT)
	_load_kit(FAC)
	_curb_mat = AssetLib.pbr_material("concrete_pavement", 1.2, Color(0.82, 0.8, 0.78), true)
	for key: Vector2i in layout.blocks:
		_build_block(key, layout.blocks[key])
	_flush_batches()
	if not layout.wild:
		_build_street_props()
		_build_skyline()  # wilderness has its own horizon (FieldView hills and biome wrecks)
	_static.flush(self)
	_props.flush(self)


# --- Kit --------------------------------------------------------------------------

func _load_kit(id: String) -> void:
	var ps: PackedScene = load(AssetLib.MODEL_DIR % [id, id])
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
		mmi.visibility_range_end = 420.0
		add_child(mmi)
	_batches.clear()


# --- Blocks -------------------------------------------------------------------------

## Blocks within this Chebyshev distance of the hub get full kit detail; the rest are proxies.
const DETAIL_RING: int = 1


func _build_block(key: Vector2i, b: Dictionary) -> void:
	var rect: Rect2 = b["rect"]
	if layout.wild:
		return  # the hub yard's fence belongs to StreetDressing (it is ruined, then repaired)
	var detailed: bool = maxi(absi(key.x), absi(key.y)) <= DETAIL_RING
	_build_sidewalks(rect, detailed)
	match int(b["type"]):
		CityLayout.Block.BUILDINGS:
			_body = BuildingDetail.Geo.new()
			_det = BuildingDetail.Geo.new()
			for bd: Dictionary in b["buildings"]:
				if detailed:
					_build_building(key, bd)
				else:
					_detail.proxy_building(bd, _body, _det)
			_flush_block(key)
		CityLayout.Block.HUB:
			pass  # yard fence: StreetDressing
		CityLayout.Block.PARKING, CityLayout.Block.VACANT:
			_build_fence(rect, false)


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
	var h: float = CityLayout.CURB_H
	var outer := r.grow(w)
	var slabs: Array[Rect2] = [
		Rect2(outer.position, Vector2(outer.size.x, w)),
		Rect2(Vector2(outer.position.x, r.end.y), Vector2(outer.size.x, w)),
		Rect2(Vector2(outer.position.x, r.position.y), Vector2(w, r.size.y)),
		Rect2(Vector2(r.end.x, r.position.y), Vector2(w, r.size.y)),
	]
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
		if detailed:
			add_child(body)
		else:
			body.free()
	# Curb faces (outer edge only, facing the road).
	var curb_parts: Array = []
	for e: Array in [[outer.position, Vector2(outer.end.x, outer.position.y)], [Vector2(outer.position.x, outer.end.y), outer.end],
			[outer.position, Vector2(outer.position.x, outer.end.y)], [Vector2(outer.end.x, outer.position.y), outer.end]]:
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var len_: float = a.distance_to(bb)
		var mid: Vector2 = (a + bb) * 0.5
		var horiz: bool = absf(a.y - bb.y) < 0.01
		curb_parts.append(ProcMesh.part(ProcMesh.box(Vector3(len_, h + 0.02, 0.22) if horiz else Vector3(0.22, h + 0.02, len_)),
			ProcMesh.xf(Vector3(mid.x, h * 0.5 - 0.005, mid.y))))
	_static.merge(ProcMesh.merge(curb_parts), Transform3D.IDENTITY, _curb_mat, true, Vector3(r.get_center().x, 0, r.get_center().y))  # [deck]


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
	_body.mat(BuildingDetail.K_DARK, Color(0.05, 0.045, 0.045))
	_body.abox(Vector3(mass_r.position.x, 0.0, mass_r.position.y), Vector3(mass_r.size.x, mass_h - 0.05, mass_r.size.y))
	var pal: Array = BuildingDetail.APT_PALETTE[(int(bd["seed"]) >> 3) % BuildingDetail.APT_PALETTE.size()]
	var shell_r: Rect2 = BuildingDetail._inset_front(mass_r.grow(-0.02), face, 0.6, 0.0)
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
	# Low chainlink run along part of a lot's edge.
	var mat: StandardMaterial3D = Mats.metal("steel")
	var parts: Array = []
	var edges: Array = [[r.position, Vector2(r.end.x, r.position.y)], [r.position, Vector2(r.position.x, r.end.y)]]
	if not partial:
		edges.append([Vector2(r.end.x, r.position.y), r.end])
	for e: Array in edges:
		var a: Vector2 = e[0]
		var bb: Vector2 = e[1]
		var n: int = int(a.distance_to(bb) / 2.5)
		for k: int in n + 1:
			if partial and _rng.randf() < 0.35:
				continue
			var p: Vector2 = a.lerp(bb, float(k) / n)
			parts.append(ProcMesh.part(ProcMesh.cyl(0.03, 0.03, 1.8, 6), ProcMesh.xf(Vector3(p.x, 0.9, p.y), Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4)))))
		var mid: Vector2 = (a + bb) * 0.5
		var len_: float = a.distance_to(bb)
		var horiz: bool = absf(a.y - bb.y) < 0.01
		parts.append(ProcMesh.part(ProcMesh.cyl(0.02, 0.02, len_, 6), ProcMesh.xf(Vector3(mid.x, 1.78, mid.y), Vector3(0, 0, 90) if horiz else Vector3(90, 0, 0))))
	_static.merge(ProcMesh.merge(parts), Transform3D.IDENTITY, mat, true, Vector3(r.get_center().x, 0, r.get_center().y))  # [deck]


# --- Street furniture ---------------------------------------------------------------

## [deck] Street props are instanced per model and 72 m cell (MeshBatch); collision stays as
## plain StaticBody3D nodes with the same transform.
func _mesh_prop(model: String, pos: Vector3, yaw: float, collide: bool, scl: float = 1.0, roll: float = 0.0) -> void:
	var mesh: Mesh = AssetLib.lite(AssetLib.model_part(model.get_slice("::", 0), model.get_slice("::", 1)) if "::" in model else AssetLib.model_mesh(model), 2500)
	var xf := Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)) * Basis.from_scale(Vector3.ONE * scl), pos)
	_props.instance(mesh, xf)
	if collide:
		var aabb: AABB = mesh.get_aabb()
		var body := StaticBody3D.new()
		body.transform = Transform3D(Basis.from_euler(Vector3(0.0, yaw, roll)), pos)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(aabb.size.x, 0.2), aabb.size.y, maxf(aabb.size.z, 0.2)) * scl * 0.9
		cs.shape = box
		cs.position = aabb.get_center() * scl
		body.add_child(cs)
		add_child(body)


func _build_street_props() -> void:
	var lamp_spacing: float = 18.0
	var n: int = int(layout.extent / CityLayout.PITCH)
	var half: float = CityLayout.PITCH * 0.5
	var walk_mid: float = half - CityLayout.ROAD_W * 0.5 - CityLayout.WALK_W * 0.5
	for bx: int in range(-n, n + 1):
		for bz: int in range(-n, n + 1):
			var c := Vector2(bx, bz) * CityLayout.PITCH
			if c.length() > layout.extent:
				continue
			var near: bool = maxi(absi(bx), absi(bz)) <= DETAIL_RING
			if not near:
				continue
			# Lamps and poles on two sidewalks of each block.
			for side: int in 2:
				var count: int = int(CityLayout.PITCH / lamp_spacing)
				for k: int in count:
					var t: float = -half + 6.0 + k * lamp_spacing
					var p: Vector2 = c + (Vector2(t, -walk_mid - 0.6) if side == 0 else Vector2(walk_mid + 0.6, t))
					var yaw: float = PI if side == 0 else -PI * 0.5
					if _rng.randf() < 0.75:
						var lamp_model: String = "street_lamp_02" if _rng.randf() < 0.5 else "street_lamp_01"
						var lamp_yaw: float = yaw + _rng.randf_range(-0.05, 0.05)
						var lean: float = _rng.randf_range(-0.15, 0.15) if _rng.randf() < 0.15 else 0.0  # leaning, half-collapsed
						_mesh_prop(lamp_model, Vector3(p.x, CityLayout.CURB_H, p.y), lamp_yaw, near, 1.0, lean)
			if not near:
				continue
			# Hydrant, manholes, a payphone, benches, utility boxes.
			var q: Vector2 = c + Vector2(_rng.randf_range(-half + 5, half - 5), -walk_mid + 0.7)
			_mesh_prop("fire_hydrant::fire_hydrant_aged", Vector3(q.x, CityLayout.CURB_H, q.y), _rng.randf() * TAU, true)
			var m: Vector2 = c + Vector2(_rng.randf_range(-6, 6), half)
			_mesh_prop("water_manhole_cover", Vector3(m.x, 0.005, m.y), _rng.randf() * TAU, false)
			if _rng.randf() < 0.4:
				var u: Vector2 = c + Vector2(walk_mid + 0.5, _rng.randf_range(-half + 4, half - 4))
				_mesh_prop("utility_box_01", Vector3(u.x, CityLayout.CURB_H, u.y), -PI * 0.5, true)
			if _rng.randf() < 0.1:
				var pp: Vector2 = c + Vector2(_rng.randf_range(-half + 4, half - 4), walk_mid + 0.3)
				_mesh_prop("korean_public_payphone_01", Vector3(pp.x, CityLayout.CURB_H, pp.y), 0.0, true)


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
