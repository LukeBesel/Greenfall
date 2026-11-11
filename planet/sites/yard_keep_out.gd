class_name YardKeepOut
extends RefCounted
## [v1yard] Where the start yard keeps junk off, piece by piece. The pad (the yard's ground
## patch, VerdanceSite's 21 m "yard" lot) and the pod's crash site stay clean. So do the site's
## building footprints, which SiteManager adds once the prefab is built. Every other bit of the
## start site's cells keeps its junk, so the trash starts at the pad's edge. Before this, whole
## 10 m cells within 22 m of the yard centre went clean, which left a bare ring around the pad.
## SphereField.materialize asks blocks(dir) per piece and re-rolls (or drops) the pieces that
## land inside. OrbitPlanet clears only the cells that lie wholly inside (cell_inside).

## Half-size (m) of the pad: the yard's kit ground patch is 21 m square.
const PAD_HALF_M: float = 10.5
## Junk keeps this far off the pad's edge (its kerb lip).
const PAD_MARGIN_M: float = 0.3
## The pod's crash site (crater ring and debris) around the "pod" anchor.
const POD_CLEAR_M: float = 2.6
## Building footprints grow by this (their walls and steps stick out of the 0.8 x footprint).
const FOOT_GROW_M: float = 1.0
## Cells whose centre is within this of the start get no big items (tyres, TVs, stoves), as the
## flat game's starting hexes: Lumi isn't strong enough for them yet.
const SMALL_ONLY_M: float = 40.0

var xf_inv: Transform3D  # world -> site-local
var radius: float = 1.0
var rects: Array[Rect2] = []
var discs: Array[Vector3] = []  # (x, z, radius), site-local
## Places that only loose junk keeps off (a crash furrow, standing water): discs like `discs`, but a
## cell under one stays a junk cell (cell_inside ignores them), so nothing starts clean for them.
var soft_discs: Array[Vector3] = []


## The keep-out for a reserved site (SphereTerrain.reserve_site result) on a terrain.
static func for_site(site: Dictionary, terrain: SphereTerrain) -> YardKeepOut:
	var k := YardKeepOut.new()
	var xf: Transform3D = site["transform"] if site.has("transform") else terrain.site_transform(site)
	k.xf_inv = xf.affine_inverse()
	k.radius = terrain.R + float(site.get("h0", 0.0))
	var h: float = PAD_HALF_M + PAD_MARGIN_M
	k.rects.append(Rect2(-h, -h, h * 2.0, h * 2.0))
	var pod: Array = SitePrefab.START_YARD_ANCHORS["pod"]
	var pp: Vector3 = pod[0]
	k.discs.append(Vector3(pp.x, pp.z, POD_CLEAR_M))
	for d: Vector3 in CrashSite.furrow_discs():  # the trench the pod ploughed stays bare earth
		k.soft_discs.append(Vector3(pp.x + d.x, pp.z + d.y, d.z))
	return k


## Loose junk keeps off the disc (x, z, radius r; site-local metres) from now on.
func add_soft_disc(x: float, z: float, r: float) -> void:
	soft_discs.append(Vector3(x, z, r))


## Building footprints (site-local rects, VerdanceSite.footprints()).
func add_footprints(fp: Array[Rect2]) -> void:
	for r: Rect2 in fp:
		var g: Rect2 = r.grow(FOOT_GROW_M)
		_bin_rect(g)  # [v3city] the start town has a few hundred: binned, not scanned
	_binned = true
	version += 1  # [v4world]


## [v3city] Footprints binned in BIN_M squares (the pad and pod stay in the plain lists).
const BIN_M: float = 8.0
var _bins: Dictionary = {}  # Vector2i -> Array[Rect2]
var _binned: bool = false


func _bin_rect(g: Rect2) -> void:
	for bx: int in range(floori(g.position.x / BIN_M), floori(g.end.x / BIN_M) + 1):
		for bz: int in range(floori(g.position.y / BIN_M), floori(g.end.y / BIN_M) + 1):
			var k := Vector2i(bx, bz)
			if not _bins.has(k):
				_bins[k] = []
			(_bins[k] as Array).append(g)


## Site-local (x, z) of a world direction, on the pad's plane.
func local(dir: Vector3) -> Vector2:
	var p: Vector3 = xf_inv * (dir.normalized() * radius)
	return Vector2(p.x, p.z)


func blocks_local(q: Vector2, soft: bool = true) -> bool:
	if soft:
		for s: Vector3 in soft_discs:
			if q.distance_squared_to(Vector2(s.x, s.y)) < s.z * s.z:
				return true
	for r: Rect2 in rects:
		if r.has_point(q):
			return true
	if _binned:
		var bin: Variant = _bins.get(Vector2i(floori(q.x / BIN_M), floori(q.y / BIN_M)))
		if bin != null:
			for r2: Rect2 in bin:
				if r2.has_point(q):
					return true
	for d: Vector3 in discs:
		if q.distance_squared_to(Vector2(d.x, d.y)) < d.z * d.z:
			return true
	return false


func blocks(dir: Vector3) -> bool:
	return blocks_local(local(dir)) or (_world_n > 0 and _blocks_world(dir))


## As blocks(), without the soft discs: what is solid or kept clear for good.
func blocks_hard(dir: Vector3) -> bool:
	return blocks_local(local(dir), false) or (_world_n > 0 and _blocks_world(dir))


## [v4world] Whether a direction lies inside a building footprint (grown FOOT_GROW_M): the start
## site's binned footprints and every hub town's, outskirts' and hinterland's, but not the pad or
## the pod's crash site (Lumi walks there). TargetReach uses it (owner playtest 3 #55).
func in_building(dir: Vector3) -> bool:
	if _binned:
		var q: Vector2 = local(dir)
		var bin: Variant = _bins.get(Vector2i(floori(q.x / BIN_M), floori(q.y / BIN_M)))
		if bin != null:
			for r2: Rect2 in bin:
				if r2.has_point(q):
					return true
	return _world_n > 0 and _blocks_world(dir)


## [v4world] Bumped whenever footprints are added: spots checked before can be checked again.
var version: int = 0


# --- [v3city] Town outskirts round any hub: footprints in their own ground frames ----------------
## Buckets of WORLD_M (by direction x planet radius) -> [[frame inverse, Rect2 (frame-local), r]].
const WORLD_M: float = 16.0
var _world: Dictionary = {}
var _world_n: int = 0
var _world_keys: Dictionary = {}  # who added (hub index): added once


## Footprints of buildings standing in ground frames on the sphere: [[frame: Transform3D, rect: Rect2]].
## Pieces keep off them on every hub's outskirts (junk never lies inside a building there).
func add_world(key: Variant, items: Array) -> void:
	if _world_keys.has(key):
		return
	_world_keys[key] = true
	for it: Array in items:
		var fr: Transform3D = it[0]
		var r: Rect2 = (it[1] as Rect2).grow(FOOT_GROW_M)
		var entry: Array = [fr.affine_inverse(), r, fr.origin.length()]
		for k: Vector3i in _world_boxes(fr, r):
			if not _world.has(k):
				_world[k] = []
			(_world[k] as Array).append(entry)
		_world_n += 1
	version += 1  # [v4world]


## Every WORLD_M box a footprint touches, whatever its tilt: the boxes of its bounds on the sphere
## that its ground plane passes through. (Boxes found from sample points missed the ones a tilted
## footprint only clips, and junk was laid there, inside the building.)
func _world_boxes(fr: Transform3D, r: Rect2) -> Array[Vector3i]:
	var mid: Vector3 = (fr * Vector3(r.get_center().x, 0.0, r.get_center().y)).normalized()
	var bounds := AABB(mid * radius, Vector3.ZERO)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		bounds = bounds.expand((fr * Vector3(corner.x, 0.0, corner.y)).normalized() * radius)
	# The ground bulges out of the flat quad through the corners by at most its sagitta.
	var slack: float = r.size.length_squared() / (8.0 * radius) + WORLD_EDGE_M
	bounds = bounds.grow(slack)
	var lo: Vector3i = _wbox(bounds.position)
	var hi: Vector3i = _wbox(bounds.end)
	var reach: float = WORLD_M * 0.5 * sqrt(3.0) + slack  # a box's half diagonal
	var out: Array[Vector3i] = []
	for bx: int in range(lo.x, hi.x + 1):
		for by: int in range(lo.y, hi.y + 1):
			for bz: int in range(lo.z, hi.z + 1):
				var centre: Vector3 = (Vector3(bx, by, bz) + Vector3.ONE * 0.5) * WORLD_M
				if absf((centre - mid * radius).dot(mid)) <= reach:
					out.append(Vector3i(bx, by, bz))
	return out


## Slack (m) on a footprint's bounds: a point on its very edge still finds it.
const WORLD_EDGE_M: float = 0.5


func _wbox(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / WORLD_M), floori(p.y / WORLD_M), floori(p.z / WORLD_M))


func _blocks_world(dir: Vector3) -> bool:
	var d: Vector3 = dir.normalized()
	var lst: Variant = _world.get(_wbox(d * radius))
	if lst == null:
		return false
	for e: Array in lst:
		var lp: Vector3 = (e[0] as Transform3D) * (d * float(e[2]))
		if (e[1] as Rect2).has_point(Vector2(lp.x, lp.z)):
			return true
	return false


## Whether a cell lies wholly in the keep-out: its centre and six points near its rim.
func cell_inside(grid: SphereGrid, c: int) -> bool:
	var ctr: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(ctr)
	for o: Vector2 in SiteManager.PROBE:
		var d: Vector3 = (ctr + (f.x * o.x * 2.0 + f.z * o.y * 2.0) / grid.radius_m).normalized()
		if not blocks_hard(d):
			return false
	return true
