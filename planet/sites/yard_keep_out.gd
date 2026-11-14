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
## [v9a] Goal audit: a buried part lay by the bench, so a new player's first E at the bench dug
## instead of opening it. A buried part (E digs it within the detector's dig_range) keeps clear of
## every spot where E means something else: the spot's own E reach + the dig range + a margin, so
## no place Lumi can press E for the bench, the bin, the rocket... also digs. (3.5 m flat was too
## little: the bench answers E from 3.2 m, so a part 3.7 m away dug on CI.)
const DIG_RANGE_M: float = 1.4  # data/parts.json detector.dig_range
const PART_MARGIN_M: float = 0.4
## The E reach (m) of the yard's spots: the bench (slice_orbit BENCH_RANGE), the rocket
## (its interactable), everything else (Interactables radii in the yard are 1.6-3.4 m).
const BENCH_REACH_M: float = 3.2
const ROCKET_REACH_M: float = 6.5
const OTHER_REACH_M: float = 3.4
## The clearance for a spot of reach r.
static func part_clear(r: float) -> float:
	return r + DIG_RANGE_M + PART_MARGIN_M
## Kept for callers: the smallest clearance.
const PART_CLEAR_M: float = OTHER_REACH_M + DIG_RANGE_M + PART_MARGIN_M
## The yard anchors that carry an E prompt, or a job a player walks to (the scale).
const E_ANCHORS: Array[String] = ["pod", "depot", "bin", "shack", "radio", "signal_tower", "telescope", "fabricator",
	"generator", "composter", "locker", "nursery", "camera_bot"]
## Cells whose centre is within this of the start get no big items (tyres, TVs, stoves), as the
## flat game's starting hexes: Lumi isn't strong enough for them yet.
const SMALL_ONLY_M: float = 40.0

var xf_inv: Transform3D  # world -> site-local
var radius: float = 1.0
var rects: Array[Rect2] = []
var discs: Array[Vector3] = []  # (x, z, radius), site-local


## The keep-out for a reserved site (SphereTerrain.reserve_site result) on a terrain.
static func for_site(site: Dictionary, terrain: SphereTerrain) -> YardKeepOut:
	var k := YardKeepOut.new()
	var xf: Transform3D = site["transform"] if site.has("transform") else terrain.site_transform(site)
	k.xf_inv = xf.affine_inverse()
	k.radius = terrain.R + float(site.get("h0", 0.0))
	var h: float = PAD_HALF_M + PAD_MARGIN_M
	k.rects.append(Rect2(-h, -h, h * 2.0, h * 2.0))
	var pod: Array = VerdanceSite.START_YARD_ANCHORS["pod"]
	var pp: Vector3 = pod[0]
	k.discs.append(Vector3(pp.x, pp.z, POD_CLEAR_M))
	for nm: String in E_ANCHORS:
		var a: Vector3 = (VerdanceSite.START_YARD_ANCHORS[nm] as Array)[0]
		k.e_points.append(Vector3(a.x, a.z, OTHER_REACH_M))
	k.e_points.append(Vector3(BENCH_LOCAL.x, BENCH_LOCAL.y, BENCH_REACH_M))
	k.e_points.append(Vector3(ROCKET_LOCAL.x, ROCKET_LOCAL.y, ROCKET_REACH_M))
	return k


## [v9a] The bench (the shack stands over it, 0.65 m in).
const BENCH_LOCAL: Vector2 = Vector2(-8.0, 7.5)
## [v9a] The rocket on its pad (E at the rocket).
const ROCKET_LOCAL: Vector2 = Vector2(0.0, -6.5)
var e_points: Array[Vector3] = []  # site-local (x, z, E reach) of the yard's E spots


## [v9a] Whether a buried part at this direction would lie within PART_CLEAR_M of a yard E spot.
func near_e_point(dir: Vector3) -> bool:
	var q: Vector2 = local(dir)
	if q.length() > PAD_HALF_M + part_clear(ROCKET_REACH_M) + 6.0:
		return false
	for e: Vector3 in e_points:
		if q.distance_to(Vector2(e.x, e.y)) < part_clear(e.z):
			return true
	return false


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


func blocks_local(q: Vector2) -> bool:
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
	for bx: Array in boxes:  # [v8hex]
		var dq: Vector2 = q - (bx[0] as Vector2)
		var hb: Vector2 = bx[3]
		if absf(dq.dot(bx[1])) < hb.x and absf(dq.dot(bx[2])) < hb.y:
			return true
	return false


## [v8hex] Ground kept clear of junk that is NOT a building (Lumi walks in): a box standing in
## world frame xf, half extents (x, z) m. The First Seed greenhouse: its planting beds hid
## pieces under them and its posts walled others in, so the hex it stands on never cleared.
## Site-local [centre, x axis, z axis, half].
var boxes: Array = []


func add_clear_box(xf: Transform3D, half: Vector2) -> void:
	var o: Vector3 = xf_inv * xf.origin
	var ax: Vector3 = xf_inv.basis * xf.basis.x
	var az: Vector3 = xf_inv.basis * xf.basis.z
	boxes.append([Vector2(o.x, o.z), Vector2(ax.x, ax.z).normalized(), Vector2(az.x, az.z).normalized(), half])
	version += 1


func blocks(dir: Vector3) -> bool:
	return blocks_local(local(dir)) or (_world_n > 0 and _blocks_world(dir))


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
	return _world_n > 0 and _blocks_world(dir, true)


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
## [v5look] soft = true: pieces keep off (blocks) but it is no building (in_building stays false,
## so TargetReach still walks across): the hinterland's road lanes.
func add_world(key: Variant, items: Array, soft: bool = false) -> void:
	if _world_keys.has(key):
		return
	_world_keys[key] = true
	for it: Array in items:
		var fr: Transform3D = it[0]
		var r: Rect2 = (it[1] as Rect2).grow(FOOT_GROW_M)
		var inv: Transform3D = fr.affine_inverse()
		var rad: float = fr.origin.length()
		# [v5play] Every bucket the footprint's box touches. (It used to sample the footprint every
		# 8 m and file it under the samples' buckets: a bucket the footprint only clipped a corner
		# of got nothing, so junk was laid inside buildings there, where nobody can clean it.)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for cq: Vector3 in [Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.0, r.position.y), Vector3(r.end.x, 0.0, r.end.y), Vector3(r.position.x, 0.0, r.end.y), Vector3(r.get_center().x, 0.0, r.get_center().y)]:
			var wp: Vector3 = (fr * cq).normalized() * radius / WORLD_M
			lo = lo.min(wp)
			hi = hi.max(wp)
		var pad := Vector3.ONE * (0.25 / WORLD_M)
		var k0 := Vector3i((lo - pad).floor())
		var k1 := Vector3i((hi + pad).floor())
		for kx: int in range(k0.x, k1.x + 1):
			for ky: int in range(k0.y, k1.y + 1):
				for kz: int in range(k0.z, k1.z + 1):
					var k := Vector3i(kx, ky, kz)
					if not _world.has(k):
						_world[k] = []
					(_world[k] as Array).append([inv, r, rad, soft])
		_world_n += 1
	version += 1  # [v4world]


func _wkey(d: Vector3, rad: float) -> Vector3i:
	var p: Vector3 = d * rad / WORLD_M
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func _blocks_world(dir: Vector3, hard_only: bool = false) -> bool:
	var d: Vector3 = dir.normalized()
	var base: Vector3 = d * radius / WORLD_M
	var b0 := Vector3i(floori(base.x), floori(base.y), floori(base.z))
	for k: Vector3i in [b0]:
		var lst: Variant = _world.get(k)
		if lst == null:
			continue
		for e: Array in lst:
			if hard_only and e[3]:  # [v5look]
				continue
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
		if not blocks(d):
			return false
	return true
