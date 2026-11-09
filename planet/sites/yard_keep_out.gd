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
	return k


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
	return false


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
		var inv: Transform3D = fr.affine_inverse()
		var rad: float = fr.origin.length()
		var nx: int = maxi(1, int(ceil(r.size.x / (WORLD_M * 0.5))))
		var nz: int = maxi(1, int(ceil(r.size.y / (WORLD_M * 0.5))))
		var seen: Dictionary = {}
		for ix: int in nx + 1:
			for iz: int in nz + 1:
				var q := Vector3(r.position.x + r.size.x * ix / nx, 0.0, r.position.y + r.size.y * iz / nz)
				var k: Vector3i = _wkey((fr * q).normalized(), radius)
				if seen.has(k):
					continue
				seen[k] = true
				if not _world.has(k):
					_world[k] = []
				(_world[k] as Array).append([inv, r, rad])
		_world_n += 1
	version += 1  # [v4world]


func _wkey(d: Vector3, rad: float) -> Vector3i:
	var p: Vector3 = d * rad / WORLD_M
	return Vector3i(floori(p.x), floori(p.y), floori(p.z))


func _blocks_world(dir: Vector3) -> bool:
	var d: Vector3 = dir.normalized()
	var base: Vector3 = d * radius / WORLD_M
	var b0 := Vector3i(floori(base.x), floori(base.y), floori(base.z))
	for k: Vector3i in [b0]:
		var lst: Variant = _world.get(k)
		if lst == null:
			continue
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
		if not blocks(d):
			return false
	return true
