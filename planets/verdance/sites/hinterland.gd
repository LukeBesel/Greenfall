class_name Hinterland
extends Node3D
## [v3city] The land between Verdance's hub towns (owner item 42: "suburbs, outskirts or industrial
## edge, not empty plains"). Past every hub's outskirts (HUB_CLEAR_M from a hub) the ground gets
## scattered buildings and props, decided per fine hex from the planet seed:
##   zones (low-frequency noise): open junk fields, suburbs (detached houses, sheds, poles) and
##   industrial edges (warehouses, works sheds, tanks). Denser just outside the hubs' outskirts.
##   spacing: at most one building a hex (hexes are ~17 m apart), the big works only on a hex that
##   out-rolls its neighbours, so there are always 5+ m walkable gaps; never on water, a shore or a
##   hub site.
## Drawing is cheap: a handful of building archetypes (BuildingDetail proxies in object space,
## building_city local_space) and props as MultiMeshes over the whole ring round Lumi, with a far
## LOD (bare boxes) past NEAR_M; rebuilt when Lumi has moved REBUILD_M. Hexes are decided a few
## hundred per frame and cached. Colliders only for buildings within COLLIDE_M of Lumi. Every
## footprint goes into the junk keep-out (YardKeepOut.add_world) before Lumi gets near, so the
## junk lies round the buildings, not inside them.

const VIEW_M: float = 520.0
const NEAR_M: float = 170.0
const COLLIDE_M: float = 70.0
const REBUILD_M: float = 45.0
const HUB_CLEAR_M: float = 345.0
const CELLS_PER_FRAME: int = 600

## Archetypes: [name, width (along X), depth (Z), floors, style].
const ARCH: Array = [
	["house_a", 9.0, 8.0, 1, "apartments"],
	["house_b", 9.0, 7.5, 2, "apartments"],
	["block", 12.0, 10.0, 3, "apartments"],
	["shed", 9.0, 12.0, 1, "factory"],
	["warehouse", 18.0, 15.0, 2, "factory"],
	["works", 15.0, 12.0, 3, "factory"],
]
const PROPS: Array[String] = ["car", "pole", "tank", "fence"]
const VARIANTS: int = 5  # looks per archetype (paint, roof, shopfront, roof clutter)
## Paint per look: [wall, roof]. Look 0 keeps the building kit's own palette; the others are the
## town's house paints and roof colours, worn by the facade texture on top (style guide 9).
const HOUSE_PAINT: Array = [
	[],
	[Color(0.7, 0.92, 0.8), Color(0.66, 0.26, 0.2)],
	[Color(1.0, 0.88, 0.56), Color(0.26, 0.46, 0.34)],
	[Color(1.0, 0.66, 0.56), Color(0.3, 0.38, 0.54)],
	[Color(0.64, 0.82, 1.0), Color(0.78, 0.42, 0.26)],
]
const WORKS_PAINT: Array = [
	[],
	[Color(0.98, 0.8, 0.36), Color(0.36, 0.38, 0.42)],
	[Color(0.5, 0.68, 0.9), Color(0.62, 0.28, 0.22)],
	[Color(0.9, 0.5, 0.4), Color(0.7, 0.7, 0.68)],
	[Color(0.56, 0.78, 0.7), Color(0.34, 0.44, 0.38)],
]
## Wreck paint: one MultiMesh per colour.
const CAR_PAINT: Array[String] = ["#7a3b30", "#1f8f8a", "#e2b21f", "#e8e4d8", "#c7322a"]

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var keep_out: YardKeepOut
var hub_dirs: Array[Vector3] = []
var seed_value: int = 4471
var focus: Node3D
var stats: Dictionary = {"cells": 0, "buildings": 0, "props": 0, "rebuilds": 0, "last_ms": 0}

var _zone := FastNoiseLite.new()
var _angle := FastNoiseLite.new()
var _decided: Dictionary = {}   # cell -> Array of [kind (archetype index, or -1 - prop index), Transform3D world, size: Vector2]
var _pending := PackedInt32Array()
var _pending_at: int = 0
var _last_pos := Vector3.INF
var _mm_near: Array[MultiMeshInstance3D] = []
var _mm_far: Array[MultiMeshInstance3D] = []
var _mm_props: Array[MultiMeshInstance3D] = []
var _body: StaticBody3D
var _body_pos := Vector3.INF
var _rng := RandomNumberGenerator.new()


func setup(p_grid: SphereGrid, p_terrain: SphereTerrain, p_cells: SphereCells, p_hubs: Array[Vector3], p_seed: int, p_keep_out: YardKeepOut) -> void:
	grid = p_grid
	terrain = p_terrain
	cells = p_cells
	hub_dirs = p_hubs
	seed_value = p_seed
	keep_out = p_keep_out
	_zone.seed = seed_value + 811
	_zone.frequency = 1.0 / 380.0
	_zone.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_angle.seed = seed_value + 812
	_angle.frequency = 1.0 / 600.0
	_build_archetypes()
	_body = StaticBody3D.new()
	_body.name = "Colliders"
	add_child(_body)


# --- Archetype meshes -----------------------------------------------------------------------

func _build_archetypes() -> void:
	var det := BuildingDetail.new()
	var mat: ShaderMaterial = TownOutskirts.material()
	for vi: int in ARCH.size() * VARIANTS:
		var i: int = int(vi / float(VARIANTS))
		var a: Array = ARCH[i]
		var w: float = a[1]
		var d: float = a[2]
		var r := Rect2(-w * 0.5, -d * 0.5, w, d)
		var bd: Dictionary = {"rect": r, "face": Vector2(0, 1), "bays": int(w / 3.0), "floors": int(a[3]), "style": a[4], "seed": 9001 + vi * 7919, "ruined": vi % 2 == 1}
		var paint: Array = (WORKS_PAINT if a[4] == "factory" else HOUSE_PAINT)[vi % VARIANTS]
		if not paint.is_empty():
			bd["tint"] = paint[0]
			bd["roof_tint"] = paint[1]
		var body := BuildingDetail.Geo.new()
		var dg := BuildingDetail.Geo.new()
		det.proxy_building(bd, body, dg)
		body.mat(BuildingDetail.K_PLAIN, Color(0.56, 0.54, 0.5), BuildingDetail.T_CONCRETE)
		body.abox(Vector3(r.position.x - 0.3, -2.6, r.position.y - 0.3), Vector3(w + 0.6, 2.62, d + 0.6))
		# Near: the body and its roof clutter in one mesh. Far: the body alone.
		var near_g := BuildingDetail.Geo.new()
		near_g.v = body.v + dg.v
		near_g.n = body.n + dg.n
		near_g.c = body.c + dg.c
		near_g.u = body.u + dg.u
		near_g.u2 = body.u2 + dg.u2
		_mm_near.append(_mmi("Near_" + str(a[0]), near_g.mesh(), mat, true))
		_mm_far.append(_mmi("Far_" + str(a[0]), body.mesh(), mat, false))
	for p: String in PROPS:
		_mm_props.append(_mmi("Prop_" + p, _prop_mesh(p, CAR_PAINT[0]), null, p != "fence"))
	for ci: int in range(1, CAR_PAINT.size()):  # the other wreck colours, after the base props
		_mm_props.append(_mmi("Prop_car_%d" % ci, _prop_mesh("car", CAR_PAINT[ci]), null, true))


## (No visibility ranges: a MultiMesh spans the whole ring, so near/far is split per instance on
## each rebuild instead.)
func _mmi(nm: String, mesh: Mesh, mat: Material, shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	add_child(mi)
	return mi


func _prop_mesh(p: String, car_paint: String) -> Mesh:
	var b := KitMesh.Builder.new(77, {}, "broken")
	match p:
		"car":
			b.box("paint:" + car_paint, Vector3(1.78, 0.62, 4.2), KitMesh.xf(Vector3(0, 0.6, 0)), 0.09)
			b.box("paint:" + car_paint, Vector3(1.6, 0.5, 2.0), KitMesh.xf(Vector3(0, 1.15, -0.15)), 0.08)
			b.box("glass", Vector3(1.62, 0.36, 1.8), KitMesh.xf(Vector3(0, 1.17, -0.15)), 0.02)
			for sx: float in [-0.78, 0.78]:
				for sz: float in [-1.35, 1.35]:
					b.cyl("paint:#141416", 0.32, 0.22, KitMesh.xf(Vector3(sx - 0.11 * signf(sx), 0.32, sz), Vector3(0, 0, 90)), 0.05, 12)
		"pole":
			b.cyl("paint:#4a3a2a", 0.13, 8.5, KitMesh.xf(Vector3.ZERO), 0.02, 8)
			b.box("paint:#4a3a2a", Vector3(1.9, 0.14, 0.14), KitMesh.xf(Vector3(0, 7.9, 0)), 0.02)
			for sx2: float in [-0.8, 0.0, 0.8]:
				b.cyl("paint:#e6e1d4", 0.05, 0.16, KitMesh.xf(Vector3(sx2, 7.97, 0)), 0.01, 8)
		"tank":
			b.cyl("paint:#9a9488", 2.6, 4.5, KitMesh.xf(Vector3.ZERO), 0.1, 18)
			b.cyl("paint:#7a756c", 2.7, 0.3, KitMesh.xf(Vector3(0, 4.5, 0)), 0.08, 18)
			b.box("paint:#2c2e31", Vector3(0.1, 4.6, 0.6), KitMesh.xf(Vector3(2.62, 2.3, 0)), 0.01)
		"fence":
			for sx3: float in [-3.0, 0.0, 3.0]:
				b.cyl("paint:#6d6f72", 0.04, 1.9, KitMesh.xf(Vector3(sx3, 0, 0)), 0.005, 6)
			b.box("paint:#6d6f72", Vector3(6.0, 0.04, 0.04), KitMesh.xf(Vector3(0, 1.85, 0)), 0.005)
			b.box("paint:#8a8c8e", Vector3(6.0, 1.7, 0.02), KitMesh.xf(Vector3(0, 0.95, 0)), 0.002)
	var mi := KitMesh.instance(b, "broken", false)
	var m: ArrayMesh = mi.mesh
	for s: int in m.get_surface_count():  # bake the kit materials into the mesh (MultiMesh has no per-surface overrides)
		m.surface_set_material(s, mi.get_surface_override_material(s))
	mi.free()
	return m


# --- Deciding hexes -------------------------------------------------------------------------

func _hash01(c: int, salt: int) -> float:
	return float(hash([seed_value, c, salt]) & 0xFFFFFF) / float(0xFFFFFF)


func _hub_m(dir: Vector3) -> float:
	var best: float = INF
	for h: Vector3 in hub_dirs:
		best = minf(best, h.angle_to(dir) * terrain.R)
	return best


## Whether hex c out-rolls every hex within `rings` rings of it.
func _local_max(c: int, rings: int, salt: int) -> bool:
	var v: float = _hash01(c, salt)
	var front: PackedInt32Array = PackedInt32Array([c])
	var seen: Dictionary = {c: true}
	for r: int in rings:
		var nxt := PackedInt32Array()
		for q: int in front:
			for o: int in grid.neighbors(q):
				if seen.has(o):
					continue
				seen[o] = true
				if _hash01(o, salt) >= v:
					return false
				nxt.append(o)
		front = nxt
	return true


func _decide(c: int) -> Array:
	var out: Array = []
	if cells.state[c] == 5 or cells.has_flag(c, SphereCells.F_SITE):
		return out
	var dir: Vector3 = grid.centers[c]
	var hm: float = _hub_m(dir)
	if hm < HUB_CLEAR_M:
		return out
	for o: int in grid.neighbors(c):
		if cells.state[o] == 5:
			return out  # no building on a shore
	var p: Vector3 = dir * terrain.R
	var z: float = _zone.get_noise_3dv(p) + clampf(1.0 - (hm - HUB_CLEAR_M) / 400.0, 0.0, 1.0) * 0.35
	var ind: bool = _zone.get_noise_3dv(p * 1.7 + Vector3(300, 0, 0)) > 0.25
	var zone: int = 0 if z < -0.05 else (2 if ind else 1)
	var roll: float = _hash01(c, 3)
	var kind: int = -99
	if zone == 1 and roll < 0.6:  # hexes are ~17 m apart: a house (<= 12 m) per hex leaves 5+ m gaps
		var r2: float = _hash01(c, 4)
		kind = 0 if r2 < 0.45 else (1 if r2 < 0.8 else (2 if r2 < 0.9 else 3))
		if kind >= 2 and not _local_max(c, 1, 7):
			kind = 0  # the bigger ones only where no neighbour stands close
	elif zone == 2 and roll < 0.8 and _local_max(c, 1, 8):
		var r3: float = _hash01(c, 5)
		kind = 4 if r3 < 0.45 else (5 if r3 < 0.75 else 3)
	if kind == -99:
		# Props on the open ground: wrecks, poles along the suburbs, tanks by the works, fences.
		var pr: float = _hash01(c, 6)
		if zone == 0 and pr < 0.12:  # open junk fields: wrecks, and now and then a tank or a run of fence
			kind = -1 if pr < 0.075 else (-3 if pr < 0.09 else -4)
		elif zone == 1 and pr < 0.07:
			kind = -2 if pr < 0.05 else -1
		elif zone == 2 and pr < 0.1:
			kind = -3 if pr < 0.03 else (-4 if pr < 0.07 else -1)
		else:
			return out
	var f: Basis = SphereGrid.frame(dir)
	var yaw: float = _angle.get_noise_3dv(p) * PI + (PI * 0.5 if _hash01(c, 9) < 0.5 else 0.0)
	var off := Vector2(_hash01(c, 10) - 0.5, _hash01(c, 11) - 0.5) * 1.0
	var d2: Vector3 = (dir + (f.x * off.x + f.z * off.y) / terrain.R).normalized()
	var b := Basis(SphereGrid.frame(d2).y, yaw) * SphereGrid.frame(d2)
	var size := Vector2(2.0, 4.4)
	if kind >= 0:
		size = Vector2(float(ARCH[kind][1]), float(ARCH[kind][2]))
	elif kind == -3:
		size = Vector2(5.4, 5.4)
	elif kind == -2:
		size = Vector2(0.4, 0.4)
	elif kind == -4:
		size = Vector2(6.0, 0.3)
	# Stand on the lowest of the corners (plinths reach 2.6 m down); skip steep ground.
	var lo: float = INF
	var hi: float = -INF
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
		var q: Vector3 = d2 * terrain.R + b.x * s.x * size.x * 0.5 + b.z * s.y * size.y * 0.5
		var hgt: float = terrain.height(q.normalized())
		lo = minf(lo, hgt)
		hi = maxf(hi, hgt)
	if hi - lo > 2.4 and kind >= 0:
		return out
	var base: float = hi if kind >= 0 else (lo + hi) * 0.5
	var xf := Transform3D(b, d2 * (terrain.R + base - (0.05 if kind >= 0 else 0.0)))
	out.append([kind, xf, size, posmod(hash([seed_value, c, 12]), VARIANTS * CAR_PAINT.size())])
	return out


# --- Streaming ------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if focus == null or not is_instance_valid(focus) or not focus.is_inside_tree():
		return
	var pos: Vector3 = focus.global_position
	if _pending_at < _pending.size():
		var t0: int = Time.get_ticks_usec()
		var end: int = mini(_pending.size(), _pending_at + CELLS_PER_FRAME)
		for i: int in range(_pending_at, end):
			var c: int = _pending[i]
			if not _decided.has(c):
				var lst: Array = _decide(c)
				_decided[c] = lst
				stats["cells"] += 1
				_register(c, lst)
			if Time.get_ticks_usec() - t0 > 4000:
				end = i + 1
				break
		_pending_at = end
		if _pending_at >= _pending.size():
			_rebuild(pos)
		return
	if _last_pos == Vector3.INF or pos.distance_to(_last_pos) > REBUILD_M:
		_last_pos = pos
		_pending = grid.cells_within(pos.normalized(), VIEW_M)
		_pending_at = 0
	elif _body_pos == Vector3.INF or pos.distance_to(_body_pos) > 12.0:
		_colliders(pos)


func _register(c: int, lst: Array) -> void:
	if keep_out == null or lst.is_empty():
		return
	var items: Array = []
	for e: Array in lst:
		var sz: Vector2 = e[2]
		if int(e[0]) == -2:
			continue
		var xf: Transform3D = e[1]
		items.append([Transform3D(xf.basis, xf.origin), Rect2(-sz * 0.5, sz)])
	if not items.is_empty():
		keep_out.add_world("hinter%d" % c, items)


func _rebuild(pos: Vector3) -> void:
	var t0: int = Time.get_ticks_msec()
	var near_l: Array = []
	var far_l: Array = []
	var prop_l: Array = []
	for i: int in ARCH.size() * VARIANTS:
		near_l.append([])
		far_l.append([])
	for i2: int in _mm_props.size():
		prop_l.append([])
	var vis2: float = (VIEW_M + 20.0) * (VIEW_M + 20.0)
	var n_b: int = 0
	var n_p: int = 0
	for c: int in _pending:
		var lst: Variant = _decided.get(c)
		if lst == null:
			continue
		for e: Array in lst:
			var xf: Transform3D = e[1]
			var d2: float = xf.origin.distance_squared_to(pos)
			if d2 > vis2:
				continue
			var k: int = e[0]
			if k >= 0:
				var kv: int = k * VARIANTS + int(e[3]) % VARIANTS
				((near_l[kv] if d2 < NEAR_M * NEAR_M else far_l[kv]) as Array).append(xf)
				n_b += 1
			elif d2 < 320.0 * 320.0:
				var paint: int = int(e[3]) % CAR_PAINT.size() if k == -1 else 0
				(prop_l[-k - 1 if paint == 0 else PROPS.size() + paint - 1] as Array).append(xf)
				n_p += 1
	for i3: int in ARCH.size() * VARIANTS:
		_fill(_mm_near[i3], near_l[i3])
		_fill(_mm_far[i3], far_l[i3])
	for i4: int in _mm_props.size():
		_fill(_mm_props[i4], prop_l[i4])
	stats["buildings"] = n_b
	stats["props"] = n_p
	stats["rebuilds"] += 1
	stats["last_ms"] = Time.get_ticks_msec() - t0
	_colliders(pos)


func _fill(mi: MultiMeshInstance3D, xfs: Array) -> void:
	var mm: MultiMesh = mi.multimesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])


## Box colliders for the buildings, tanks and cars near Lumi (one body, shapes reused).
func _colliders(pos: Vector3) -> void:
	_body_pos = pos
	for ch: Node in _body.get_children():
		ch.free()
	var lim2: float = COLLIDE_M * COLLIDE_M
	for c: int in grid.cells_within(pos.normalized(), COLLIDE_M + 20.0):
		var lst: Variant = _decided.get(c)
		if lst == null:
			continue
		for e: Array in lst:
			var xf: Transform3D = e[1]
			if xf.origin.distance_squared_to(pos) > lim2:
				continue
			var k: int = e[0]
			var sz: Vector2 = e[2]
			var h: float = 4.6 if k == -3 else (1.6 if k == -1 else (8.5 if k == -2 else (1.9 if k == -4 else float(ARCH[k][3]) * 3.0 + 1.0)))
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(sz.x, h + 2.6, sz.y)
			cs.shape = box
			cs.transform = xf * Transform3D(Basis(), Vector3(0, h * 0.5 - 1.3, 0))
			_body.add_child(cs)
