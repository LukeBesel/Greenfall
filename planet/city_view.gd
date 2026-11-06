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
var _interior_mat: StandardMaterial3D
var _wall_mats: Array[StandardMaterial3D] = []
var _roof_mat: StandardMaterial3D
var _curb_mat: StandardMaterial3D


func build(p_layout: CityLayout, p_ground_material: Material) -> void:
	layout = p_layout
	ground_material = p_ground_material
	_rng.seed = layout.seed_value + 1234
	_load_kit(APT)
	_load_kit(FAC)
	_interior_mat = StandardMaterial3D.new()
	_interior_mat.albedo_color = Color(0.05, 0.045, 0.045)
	_interior_mat.roughness = 1.0
	_wall_mats = [AssetLib.pbr_material("painted_concrete", 0.4, Color(0.8, 0.76, 0.7), true),
		AssetLib.pbr_material("brick_wall_02", 0.4, Color.WHITE, true),
		AssetLib.pbr_material("red_brick", 0.4, Color(0.9, 0.85, 0.82), true),
		AssetLib.pbr_material("factory_wall", 0.3, Color.WHITE, true)]
	_roof_mat = AssetLib.pbr_material("dirty_concrete", 0.3, Color(0.7, 0.68, 0.66), true)
	_curb_mat = AssetLib.pbr_material("concrete_pavement", 1.2, Color(0.82, 0.8, 0.78), true)
	for key: Vector2i in layout.blocks:
		_build_block(key, layout.blocks[key])
	_flush_batches()
	if not layout.wild:
		_build_street_props()
	_build_skyline()


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


func _place(block: Vector2i, kit: String, piece: String, xf: Transform3D) -> void:
	if piece == "" or not (_kit[kit] as Dictionary).has(piece):
		return
	var key: String = "%d,%d|%s|%s" % [block.x, block.y, kit, piece]
	if not _batches.has(key):
		_batches[key] = []
	var arr: Array = _batches[key]
	arr.append(xf)
	_batches[key] = arr


func _flush_batches() -> void:
	for key: String in _batches:
		var parts: PackedStringArray = key.split("|")
		var mesh: Mesh = AssetLib.lite(_kit[parts[1]][parts[2]], 600)
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
		if int(b["type"]) == CityLayout.Block.HUB:
			var yh := CityLayout.YARD_HALF
			_build_fence(Rect2(Vector2(-yh, -yh), Vector2(yh, yh) * 2.0), true)
		return
	var detailed: bool = maxi(absi(key.x), absi(key.y)) <= DETAIL_RING
	_build_sidewalks(rect, detailed)
	match int(b["type"]):
		CityLayout.Block.BUILDINGS:
			for bd: Dictionary in b["buildings"]:
				if detailed:
					_build_building(key, bd)
				else:
					_build_proxy_building(bd)
		CityLayout.Block.HUB:
			var y := CityLayout.YARD_HALF
			_build_fence(Rect2(Vector2(-y, -y) + Vector2(key) * CityLayout.PITCH, Vector2(y, y) * 2.0), true)
		CityLayout.Block.PARKING, CityLayout.Block.VACANT:
			_build_fence(rect, false)


var _far_mats: Array = []


func _build_proxy_building(bd: Dictionary) -> void:
	if _far_mats.is_empty():
		for spec: Array in [["painted_concrete", Color(0.82, 0.78, 0.72)], ["brick_wall_02", Color(0.9, 0.86, 0.82)], ["red_brick", Color(0.85, 0.8, 0.78)], ["factory_wall", Color(0.85, 0.82, 0.78)]]:
			var m := ShaderMaterial.new()
			m.shader = preload("res://art/shaders/building_far.gdshader")
			m.set_shader_parameter("wall_alb", AssetLib.tex(spec[0], "diff"))
			m.set_shader_parameter("wall_nrm", AssetLib.tex(spec[0], "nor_gl"))
			m.set_shader_parameter("tint", spec[1])
			m.set_shader_parameter("seed", float(_far_mats.size()) * 0.37)
			_far_mats.append(m)
	var r: Rect2 = bd["rect"]
	var h: float = int(bd["floors"]) * FLOOR_H
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.box(Vector3(r.size.x, h, r.size.y))
	mi.material_override = _far_mats[int(bd["seed"]) % _far_mats.size()]
	mi.position = Vector3(r.get_center().x, h * 0.5, r.get_center().y)
	add_child(mi)


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
		var top := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = s.size
		pm.subdivide_width = int(s.size.x / 2.0)
		pm.subdivide_depth = int(s.size.y / 2.0)
		pm.material = ground_material
		top.mesh = pm
		top.position = Vector3(s.get_center().x, h, s.get_center().y)
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(top)
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
		var len: float = a.distance_to(bb)
		var mid: Vector2 = (a + bb) * 0.5
		var horiz: bool = absf(a.y - bb.y) < 0.01
		curb_parts.append(ProcMesh.part(ProcMesh.box(Vector3(len, h + 0.02, 0.22) if horiz else Vector3(0.22, h + 0.02, len)),
			ProcMesh.xf(Vector3(mid.x, h * 0.5 - 0.005, mid.y))))
	var curb := MeshInstance3D.new()
	curb.mesh = ProcMesh.merge(curb_parts)
	curb.material_override = _curb_mat
	add_child(curb)


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
	var basis := Basis(bx, Vector3.UP, bz)
	var ruin_from: int = floors
	if bd.get("ruined", false):
		ruin_from = maxi(1, floors - _rng.randi_range(1, 3))
	for i: int in bays:
		var bay_floors: int = floors if i % 3 != 1 or ruin_from == floors else ruin_from
		var o2: Vector2 = origin + along * (i + 1) * BAY
		for f: int in bay_floors:
			var o := Vector3(o2.x, f * FLOOR_H, o2.y)
			var xf := Transform3D(basis, o)
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
				_place(block, kit, _pick(kit, "crown_standard_standard_"), Transform3D(basis, o + Vector3(0, FLOOR_H, 0)))
			elif f < bay_floors - 1 and (f == 0 or _rng.randf() < 0.3):
				_place(block, kit, _pick(kit, "cornice_standard_standard_") if kit == APT else _pick(kit, "cornice02_standard_standard_"), Transform3D(basis, o + Vector3(0, FLOOR_H, 0)))
		_place(block, kit, _pick(kit, "base_standard_"), Transform3D(basis, Vector3(o2.x, 0, o2.y)))
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
	var inner := MeshInstance3D.new()
	inner.mesh = ProcMesh.box(Vector3(mass_r.size.x, mass_h - 0.05, mass_r.size.y))
	inner.material_override = _interior_mat
	inner.position = Vector3(mass_r.get_center().x, (mass_h - 0.05) * 0.5, mass_r.get_center().y)
	add_child(inner)
	# Plain walls on the sides and back (slightly larger shell) + roof slab.
	var shell := MeshInstance3D.new()
	var shell_r: Rect2 = mass_r.grow(-0.02)
	shell.mesh = ProcMesh.box(Vector3(shell_r.size.x, height, shell_r.size.y) - Vector3(0.0, 0.0, 0.0))
	shell.material_override = _wall_mats[_rng.randi() % _wall_mats.size()]
	shell.position = Vector3(shell_r.get_center().x, height * 0.5, shell_r.get_center().y)
	# The shell would hide the facade windows; push it back from the facade by a little more.
	var back := 0.6
	shell.position -= Vector3(face.x, 0, face.y) * back * 0.5
	shell.scale = Vector3(1.0 - absf(face.x) * back / maxf(shell_r.size.x, 1.0), 1.0, 1.0 - absf(face.y) * back / maxf(shell_r.size.y, 1.0))
	add_child(shell)
	var roof := MeshInstance3D.new()
	roof.mesh = ProcMesh.box(Vector3(r.size.x, 0.2, r.size.y))
	roof.material_override = _roof_mat
	roof.position = Vector3(r.get_center().x, mass_h + 0.1, r.get_center().y)
	add_child(roof)
	# Roof clutter.
	for k: int in _rng.randi_range(0, 3):
		var model: String = ["exterior_aircon_unit", "modular_airduct_rectangular_01", "Barrel_01", "plastic_crate_01"][_rng.randi() % 4]
		var p := Vector2(_rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), _rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
		_mesh_prop(model, Vector3(p.x, mass_h + 0.2, p.y), _rng.randf() * TAU, false)
	# Fire escape on some apartment facades.
	if kit == APT and floors >= 3 and _rng.randf() < 0.45:
		var bay: int = _rng.randi_range(0, maxi(bays - 2, 0))
		var o2: Vector2 = origin + along * (bay + 1.5) * BAY + face * 0.7
		for f: int in range(1, floors):
			var piece: String = "fire_escape"
			var m := MeshInstance3D.new()
			m.mesh = AssetLib.lite(_fire_escape_mesh("modular_fire_escape_platform_middle"), 800)
			m.transform = Transform3D(basis, Vector3(o2.x, f * FLOOR_H, o2.y))
			add_child(m)
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
		var len: float = a.distance_to(bb)
		var horiz: bool = absf(a.y - bb.y) < 0.01
		parts.append(ProcMesh.part(ProcMesh.cyl(0.02, 0.02, len, 6), ProcMesh.xf(Vector3(mid.x, 1.78, mid.y), Vector3(0, 0, 90) if horiz else Vector3(90, 0, 0))))
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.merge(parts)
	mi.material_override = mat
	add_child(mi)


# --- Street furniture ---------------------------------------------------------------

func _mesh_prop(model: String, pos: Vector3, yaw: float, collide: bool, scl: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.lite(AssetLib.model_part(model.get_slice("::", 0), model.get_slice("::", 1)) if "::" in model else AssetLib.model_mesh(model), 2500)
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * scl
	mi.visibility_range_end = 260.0
	add_child(mi)
	if collide:
		var aabb: AABB = mi.mesh.get_aabb()
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(maxf(aabb.size.x, 0.2), aabb.size.y, maxf(aabb.size.z, 0.2)) * scl * 0.9
		cs.shape = box
		cs.position = aabb.get_center() * scl
		body.add_child(cs)
		mi.add_child(body)
	return mi


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
						var lamp: MeshInstance3D = _mesh_prop("street_lamp_02" if _rng.randf() < 0.5 else "street_lamp_01", Vector3(p.x, CityLayout.CURB_H, p.y), yaw + _rng.randf_range(-0.05, 0.05), near)
						if _rng.randf() < 0.15:
							lamp.rotation.z = _rng.randf_range(-0.15, 0.15)  # leaning, half-collapsed
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
	# Tall ruined towers and junk ridges far out, dissolving into the haze.
	var tower_mats: Array = [AssetLib.pbr_material("concrete_wall_008", 0.08, Color(0.75, 0.72, 0.7), true),
		AssetLib.pbr_material("factory_wall", 0.06, Color(0.8, 0.76, 0.72), true)]
	var r0: float = layout.extent + 20.0
	for i: int in 70:
		var ang: float = TAU * i / 70.0 + _rng.randf_range(-0.03, 0.03)
		var dist: float = r0 + _rng.randf_range(0.0, 160.0)
		var w: float = _rng.randf_range(14.0, 30.0)
		var h: float = _rng.randf_range(30.0, 120.0)
		var mi := MeshInstance3D.new()
		mi.mesh = ProcMesh.box(Vector3(w, h, w * _rng.randf_range(0.7, 1.2)))
		mi.material_override = tower_mats[_rng.randi() % tower_mats.size()]
		mi.position = Vector3(cos(ang) * dist, h * 0.5 - 2.0, sin(ang) * dist)
		mi.rotation.y = _rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
