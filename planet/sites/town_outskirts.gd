class_name TownOutskirts
extends Node3D
## [v3city] The city round a hub town, past its flat pad (owner item 42: "a skyline of taller
## buildings behind it"). The town's street grid carries on over the real, curved ground: blocks
## of BuildingDetail proxy buildings (the flat district's far buildings: setbacks, cornices,
## shopfronts, roof clutter) stand on concrete plinths that follow the slope, towers close to the
## pad, mid-rise and works further out, some lots left open. The streets out here lie under the
## trash (no road mesh), so the gaps between the blocks are junk ground to clean.
##
## Geometry is grouped in TILE_M tiles; each tile is one mesh in its own ground frame (the site's
## east/south carried over the sphere to the tile), so the city shader runs in object space there
## (building_city.gdshader local_space). Every building has a box collider. The hex cells a
## building stands on are cleared (hub ground, F_HUB) when the site is built, so no junk lies
## inside a building and outposts keep off them. Nothing stands on lake cells or steep ground.
##
## Positions are "site metres": the exponential map round the hub (x east, z south, distances
## along the ground), the same layout the town's pad uses near the hub.

const TILE_M: float = 72.0
const R_IN: float = 128.0      # blocks whose near corner is inside the pad town's reach are the pad's
const R_OUT: float = 330.0     # outer edge (SiteManager builds a site at 420 m: cells clear before junk lays)
const TOWER_R: float = 230.0   # towers inside this, mid-rise beyond
const MAX_SLOPE_M: float = 4.0
const DETAIL_RANGE: float = 260.0

var R: float = 1840.0
var site_xf: Transform3D
var terrain: SphereTerrain
var grid: SphereGrid
var cells: SphereCells
var clear_cell: Callable       # func(cell: int)
var town_r: float = 136.0
var seed_value: int = 4471
var stats: Dictionary = {}

var _detail := BuildingDetail.new()
var _lay := CityLayout.new(1, 1.0)  # only for its perimeter-building generator
static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = BuildingDetail.material().duplicate()
		_mat.set_shader_parameter("local_space", true)
	return _mat


# --- Site metres on the sphere ----------------------------------------------------------------

func _dir(x: float, z: float) -> Vector3:
	var up: Vector3 = site_xf.basis.y.normalized()
	var d: float = sqrt(x * x + z * z)
	if d < 0.0001:
		return up
	var a: float = d / R
	var t: Vector3 = (site_xf.basis.x.normalized() * x + site_xf.basis.z.normalized() * z) / d
	return (up * cos(a) + t * sin(a)).normalized()


## The ground frame at a point in site metres: y up there, x and z the site's east and south
## carried along the great circle from the hub (so the grid keeps its heading).
func _frame(x: float, z: float) -> Transform3D:
	var up0: Vector3 = site_xf.basis.y.normalized()
	var fx: Vector3 = site_xf.basis.x.normalized()
	var fz: Vector3 = site_xf.basis.z.normalized()
	var dir: Vector3 = _dir(x, z)
	var d: float = sqrt(x * x + z * z)
	if d > 0.001:
		var t: Vector3 = (fx * x + fz * z) / d
		var a: float = d / R
		var t2: Vector3 = -up0 * sin(a) + t * cos(a)
		var n: Vector3 = up0.cross(t)
		fx = t2 * fx.dot(t) + n * fx.dot(n)
		fz = t2 * fz.dot(t) + n * fz.dot(n)
	var b := Basis(fx, dir, fz).orthonormalized()
	return Transform3D(b, terrain.ground(dir))


func _wet(x: float, z: float) -> bool:
	return cells.state[grid.cell_at(_dir(x, z))] == 5


# --- Build ------------------------------------------------------------------------------------

## Plans the blocks, clears their cells and builds the tiles under this node (which must sit at
## the site's transform, like VerdanceSite).
func build() -> void:
	R = terrain.R
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5153
	var tiles: Dictionary = {}  # Vector2i -> Array[Dictionary] (buildings in site metres)
	var n: int = int(ceil(R_OUT / CityLayout.PITCH))
	var half: float = CityLayout.PITCH * 0.5 - CityLayout.ROAD_W * 0.5 - CityLayout.WALK_W
	var lots: int = 0
	for bx: int in range(-n, n + 1):
		for bz: int in range(-n, n + 1):
			var c := Vector2(bx, bz) * CityLayout.PITCH
			var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
			var near := Vector2(clampf(0.0, rect.position.x, rect.end.x), clampf(0.0, rect.position.y, rect.end.y))
			var far: float = Vector2(maxf(absf(rect.position.x), absf(rect.end.x)), maxf(absf(rect.position.y), absf(rect.end.y))).length()
			if far <= town_r or near.length() < R_IN or c.length() > R_OUT:
				continue  # the pad town's own block, or beyond the outskirts
			var dist: float = c.length()
			if rng.randf() < (0.12 if dist < TOWER_R else 0.3):
				lots += 1
				continue  # an open lot
			var blds: Array = []
			if dist < TOWER_R and rng.randf() < 0.55:
				blds = _tower_block(rect, c, rng)
			else:
				blds = _lay._make_buildings(rect, rng, Vector2i(bx, bz))
				for bd: Dictionary in blds:
					var f: int = rng.randi_range(6, 12) if dist < TOWER_R else rng.randi_range(2, 7)
					bd["floors"] = f
					bd["ruined"] = rng.randf() < 0.2
					if dist > TOWER_R and rng.randf() < 0.3:
						bd["style"] = "factory"
			var tk := Vector2i(floori((c.x + TILE_M * 0.5) / TILE_M), floori((c.y + TILE_M * 0.5) / TILE_M))
			if not tiles.has(tk):
				tiles[tk] = []
			(tiles[tk] as Array).append_array(blds)
	stats = {"tiles": 0, "buildings": 0, "skipped_wet": 0, "skipped_slope": 0, "lots": lots, "cells_cleared": 0, "tallest": 0}
	var cleared: Dictionary = {}
	for tk: Vector2i in tiles:
		await BuildBudget.check("town:outskirts")
		_build_tile(tk, tiles[tk], cleared)
	for c2: int in cleared:
		if clear_cell.is_valid():
			clear_cell.call(c2)
	stats["cells_cleared"] = cleared.size()


## A tower block: one tower (podium plus setbacks via the proxy's tiers) on the side facing the
## hub, a low building or two behind it.
func _tower_block(rect: Rect2, c: Vector2, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var to_hub: Vector2 = -c.normalized()
	var face := Vector2(signf(to_hub.x), 0) if absf(to_hub.x) > absf(to_hub.y) else Vector2(0, signf(to_hub.y))
	var tw: float = float(rng.randi_range(5, 6)) * 3.0
	var td: float = rng.randf_range(13.0, 17.0)
	var along_x: bool = absf(face.y) > 0.5
	var size: Vector2 = Vector2(tw, td) if along_x else Vector2(td, tw)
	# Front edge on the block's hub-facing side, slid along it at random.
	var pos: Vector2
	if along_x:
		var x0: float = rng.randf_range(rect.position.x, rect.end.x - size.x)
		pos = Vector2(x0, rect.position.y if face.y < 0 else rect.end.y - size.y)
	else:
		var z0: float = rng.randf_range(rect.position.y, rect.end.y - size.y)
		pos = Vector2(rect.position.x if face.x < 0 else rect.end.x - size.x, z0)
	var f: int = rng.randi_range(14, 30)
	out.append({"rect": Rect2(pos, size), "face": face, "bays": int(tw / 3.0), "floors": f,
		"style": "apartments", "seed": rng.randi(), "ruined": rng.randf() < 0.15})
	# A low wing behind it, along the back edge.
	var back := Rect2(rect.position + (Vector2(0, rect.size.y - 8.0) if face.y < 0 else Vector2.ZERO), Vector2(rect.size.x, 8.0)) if along_x \
		else Rect2(rect.position + (Vector2(rect.size.x - 8.0, 0) if face.x < 0 else Vector2.ZERO), Vector2(8.0, rect.size.y))
	if not back.intersects(Rect2(pos, size).grow(1.0)) and rng.randf() < 0.7:
		var bl: float = back.size.x if along_x else back.size.y
		var bays: int = int(bl / 3.0)
		var br := Rect2(back.position, Vector2(bays * 3.0, back.size.y)) if along_x else Rect2(back.position, Vector2(back.size.x, bays * 3.0))
		out.append({"rect": br, "face": -face, "bays": bays, "floors": rng.randi_range(2, 5),
			"style": "factory" if rng.randf() < 0.5 else "apartments", "seed": rng.randi(), "ruined": rng.randf() < 0.3})
	return out


func _build_tile(tk: Vector2i, blds: Array, cleared: Dictionary) -> void:
	var tc := Vector2(tk) * TILE_M
	var fr: Transform3D = _frame(tc.x, tc.y)
	var inv: Transform3D = fr.affine_inverse()
	var body := BuildingDetail.Geo.new()
	var det := BuildingDetail.Geo.new()
	var sb := StaticBody3D.new()
	sb.name = "Body"
	var placed: int = 0
	for bd: Dictionary in blds:
		var r: Rect2 = bd["rect"]  # site metres
		# On the lake, or too steep: no building.
		var pts: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.get_center()]
		var wet: bool = false
		for q: Vector2 in pts:
			if _wet(q.x, q.y):
				wet = true
				break
		if not wet:
			var gq: Rect2 = r.grow(2.0)
			for q2: Vector2 in [gq.position, Vector2(gq.end.x, gq.position.y), gq.end, Vector2(gq.position.x, gq.end.y)]:
				if _wet(q2.x, q2.y):
					wet = true
		if wet:
			stats["skipped_wet"] += 1
			continue
		var lo: float = INF
		var hi: float = -INF
		for q3: Vector2 in pts:
			var g: Vector3 = inv * terrain.ground(_dir(q3.x, q3.y))
			lo = minf(lo, g.y)
			hi = maxf(hi, g.y)
		if hi - lo > MAX_SLOPE_M:
			stats["skipped_slope"] += 1
			continue
		# Tile-local rect (the exp map is near-isometric across a tile) and a base on a floor line,
		# so the shader's window rows line up with the building's floors.
		var lr := Rect2(r.position - tc, r.size)
		var base: float = ceilf((hi - 0.4) / BuildingDetail.FLOOR_H) * BuildingDetail.FLOOR_H
		var lbd: Dictionary = bd.duplicate()
		lbd["rect"] = lr
		var v0: int = body.v.size()
		var d0: int = det.v.size()
		_detail.proxy_building(lbd, body, det)
		for i: int in range(v0, body.v.size()):
			body.v[i].y += base
		for i2: int in range(d0, det.v.size()):
			det.v[i2].y += base
		# The plinth: weathered concrete from below the low side up to the base.
		body.mat(BuildingDetail.K_PLAIN, Color(0.56, 0.54, 0.5), BuildingDetail.T_CONCRETE)
		body.abox(Vector3(lr.position.x - 0.3, lo - 1.2, lr.position.y - 0.3), Vector3(lr.size.x + 0.6, base - lo + 1.25, lr.size.y + 0.6))
		var top: float = base + float(bd["floors"]) * BuildingDetail.FLOOR_H
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(lr.size.x + 0.6, top - lo + 1.2, lr.size.y + 0.6)
		cs.shape = box
		cs.position = Vector3(lr.get_center().x, (top + lo - 1.2) * 0.5, lr.get_center().y)
		sb.add_child(cs)
		placed += 1
		stats["tallest"] = maxi(int(stats["tallest"]), int(bd["floors"]))
		# Its cells: hub ground from now on.
		var gr: Rect2 = r.grow(1.0)
		var sx: int = maxi(2, int(ceil(gr.size.x / 4.0)))
		var sz: int = maxi(2, int(ceil(gr.size.y / 4.0)))
		for ix: int in sx + 1:
			for iz: int in sz + 1:
				var p := Vector2(gr.position.x + gr.size.x * ix / sx, gr.position.y + gr.size.y * iz / sz)
				var cl: int = grid.cell_at(_dir(p.x, p.y))
				if cells.state[cl] != 5:
					cleared[cl] = true
	if placed == 0:
		sb.free()
		return
	stats["tiles"] += 1
	stats["buildings"] += placed
	var node := Node3D.new()
	node.name = "Tile_%d_%d" % [tk.x, tk.y]
	node.transform = site_xf.affine_inverse() * fr
	add_child(node)
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = body.mesh()
	mi.material_override = material()
	mi.set_meta("no_collide", true)
	node.add_child(mi)
	if not det.empty():
		var dm := MeshInstance3D.new()
		dm.name = "Detail"
		dm.mesh = det.mesh()
		dm.material_override = material()
		dm.visibility_range_end = DETAIL_RANGE
		dm.visibility_range_end_margin = 20.0
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dm.set_meta("no_collide", true)
		node.add_child(dm)
	node.add_child(sb)
