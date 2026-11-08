class_name SphereGrid
extends RefCounted
## [sgrid] Hex globe grid: a Goldberg polyhedron (dual of a subdivided icosahedron), 12 pentagons
## plus hexagons, 10 * 4^level + 2 cells. Pure data, fast to query, cached on disk.
##
## Cell ids are the icosphere vertex ids of core/geosphere.gd (same subdivision order), so they
## are stable across runs and versions, match PlanetData/GeoSphere at the same level, and are
## hierarchical: cell i < 10 * 4^k + 2 is also cell i of every coarser level k. Chunks use that:
## chunk c is the region nearest to coarse cell c of level (level - CHUNK_DROP).
##
## Per cell (unit sphere): centre (= surface normal), neighbours in counter-clockwise order seen
## from outside, and corners (corner k lies between neighbour k and k + 1). A corner is the
## normalised centroid of one icosphere triangle, so neighbouring cells share exact corner points.
## Scale with radius_m (metres).
##
## Sizes at hex circumradius 10 m (the flat districts' hex_size): see docs/SPHERE_GRID.md.

const MAX_N: int = 6       # neighbour / corner stride
const CHUNK_DROP: int = 4  # chunk = cell of level (level - 4): ~256 cells per chunk
const CACHE_VERSION: int = 2

var level: int = 6
var radius_m: float = 1.0
var centers := PackedVector3Array()
var nbr_count := PackedByteArray()     # 5 or 6
var nbr := PackedInt32Array()          # cell * 6 + k (unused 6th slot of a pentagon = -1)
var cell_tri := PackedInt32Array()     # cell * 6 + k -> triangle whose centroid is corner k
var tris := PackedInt32Array()         # icosphere triangles, CCW from outside (3 per tri)
var tri_center := PackedVector3Array() # normalised triangle centroids (the polygon corners)
# Chunks
var chunk_level: int = 2
var cell_chunk := PackedInt32Array()
var chunk_start := PackedInt32Array()  # CSR: cells of chunk c = chunk_cells[chunk_start[c] .. chunk_start[c + 1])
var chunk_cells := PackedInt32Array()
var chunk_radius := PackedFloat32Array()  # angular radius (rad) of each chunk around its centre
# Point lookup: cube-map buckets -> a nearby cell, then a short greedy walk.
var _bucket_m: int = 1
var _bucket := PackedInt32Array()


static func cells_at_level(lv: int) -> int:
	return 10 * int(pow(4, lv)) + 2


## Grid with radius_m chosen so a hex of circumradius hex_m covers the same area as a flat hex.
static func for_hex_size(lv: int, hex_m: float = 10.0) -> SphereGrid:
	var g: SphereGrid = cached(lv)
	g.radius_m = radius_for(lv, hex_m)
	return g


static func radius_for(lv: int, hex_m: float) -> float:
	return sqrt(2.598076 * hex_m * hex_m * cells_at_level(lv) / (4.0 * PI))


## Loaded from user://sphere_grid_<level>.bin when present, else generated and saved.
## Generated grids are shared per level within a run.
static var _mem: Dictionary = {}


static func cached(lv: int) -> SphereGrid:
	if _mem.has(lv):
		var src: SphereGrid = _mem[lv]
		return src._shallow()
	var g := SphereGrid.new()
	var path: String = "user://sphere_grid_%d.bin" % lv
	if not g.load_cache(path, lv):
		g.generate(lv)
		g.save_cache(path)
	_mem[lv] = g
	return g._shallow()


## Shares the (read-only) packed arrays; only radius_m is per instance.
func _shallow() -> SphereGrid:
	var g := SphereGrid.new()
	g.level = level
	g.radius_m = radius_m
	g.centers = centers
	g.nbr_count = nbr_count
	g.nbr = nbr
	g.cell_tri = cell_tri
	g.tris = tris
	g.tri_center = tri_center
	g.chunk_level = chunk_level
	g.cell_chunk = cell_chunk
	g.chunk_start = chunk_start
	g.chunk_cells = chunk_cells
	g.chunk_radius = chunk_radius
	g._bucket_m = _bucket_m
	g._bucket = _bucket
	return g


# --- Basic queries ----------------------------------------------------------------------

func cell_count() -> int:
	return centers.size()


func chunk_count() -> int:
	return chunk_start.size() - 1


func is_pentagon(i: int) -> bool:
	return nbr_count[i] == 5


func neighbors(i: int) -> PackedInt32Array:
	return nbr.slice(i * MAX_N, i * MAX_N + nbr_count[i])


func center(i: int) -> Vector3:
	return centers[i]


## Unit corners of cell i, counter-clockwise from outside.
func corners(i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var k: int = nbr_count[i]
	out.resize(k)
	for j: int in k:
		out[j] = tri_center[cell_tri[i * MAX_N + j]]
	return out


## Corners in metres on the base sphere (no terrain).
func corners_m(i: int) -> PackedVector3Array:
	var out: PackedVector3Array = corners(i)
	for j: int in out.size():
		out[j] *= radius_m
	return out


func cells_in_chunk(c: int) -> PackedInt32Array:
	return chunk_cells.slice(chunk_start[c], chunk_start[c + 1])


## Great-circle distance in metres between two cells, or two unit directions.
func distance_m(a: int, b: int) -> float:
	return centers[a].angle_to(centers[b]) * radius_m


func great_circle_m(a: Vector3, b: Vector3) -> float:
	return a.normalized().angle_to(b.normalized()) * radius_m


## Mean centre-to-corner distance (m) and centre-to-centre spacing (m), measured over the grid.
func hex_metrics() -> Dictionary:
	var cr: float = 0.0
	var sp: float = 0.0
	var n: int = 0
	var step: int = maxi(1, cell_count() / 2000)
	for i: int in range(12, cell_count(), step):
		cr += centers[i].angle_to(tri_center[cell_tri[i * MAX_N]])
		sp += centers[i].angle_to(centers[nbr[i * MAX_N]])
		n += 1
	return {"corner_m": cr / n * radius_m, "spacing_m": sp / n * radius_m}


## Cell nearest to a world point (planet centred at the origin) or direction. O(1): a cube-map
## bucket gives a cell within a few steps, then a greedy walk on the (Delaunay) neighbour graph.
func cell_at(p: Vector3) -> int:
	var d: Vector3 = p.normalized()
	return walk(d, _bucket[_bucket_index(d)])


## Nearest cell by greedy walk from a hint (cheap for things that move a little each frame).
func walk(d: Vector3, start: int) -> int:
	var cur: int = start
	var best: float = centers[cur].dot(d)
	while true:
		var nxt: int = cur
		var b: int = cur * MAX_N
		for k: int in nbr_count[cur]:
			var j: int = nbr[b + k]
			var dd: float = centers[j].dot(d)
			if dd > best:
				best = dd
				nxt = j
		if nxt == cur:
			return cur
		cur = nxt
	return cur


func cell_at_from(p: Vector3, hint: int) -> int:
	if hint < 0 or hint >= centers.size():
		return cell_at(p)
	return walk(p.normalized(), hint)


## Cells within `rings` neighbour steps (BFS), the start cell first.
func cells_around(cell: int, rings: int) -> PackedInt32Array:
	var out := PackedInt32Array([cell])
	var seen: Dictionary = {cell: true}
	var a: int = 0
	for _r: int in rings:
		var b: int = out.size()
		for idx: int in range(a, b):
			var c: int = out[idx]
			for k: int in nbr_count[c]:
				var j: int = nbr[c * MAX_N + k]
				if not seen.has(j):
					seen[j] = true
					out.append(j)
		a = b
	return out


## Cells whose centre lies within `meters` (great circle) of a direction (BFS, so cost ~ result).
func cells_within(dir: Vector3, meters: float, hint: int = -1) -> PackedInt32Array:
	var d: Vector3 = dir.normalized()
	var start: int = cell_at_from(d, hint)
	var lim: float = cos(meters / radius_m)
	var out := PackedInt32Array()
	var seen: Dictionary = {start: true}
	var front := PackedInt32Array([start])
	while not front.is_empty():
		var nxt := PackedInt32Array()
		for c: int in front:
			if centers[c].dot(d) < lim and c != start:
				continue
			out.append(c)
			for k: int in nbr_count[c]:
				var j: int = nbr[c * MAX_N + k]
				if not seen.has(j):
					seen[j] = true
					nxt.append(j)
		front = nxt
	return out


## Chunks that may reach within `meters` of a direction (centre distance minus chunk radius).
func chunks_within(dir: Vector3, meters: float) -> PackedInt32Array:
	var d: Vector3 = dir.normalized()
	var a: float = meters / radius_m
	var out := PackedInt32Array()
	for c: int in chunk_count():
		if centers[c].angle_to(d) - chunk_radius[c] < a:
			out.append(c)
	return out


## A right-handed surface frame at a direction: y = up (radial), x = east, z = south.
## Near the poles (|y| > 0.999) east falls back to +X.
static func frame(dir: Vector3) -> Basis:
	var up: Vector3 = dir.normalized()
	var east: Vector3 = Vector3.UP.cross(up)
	if east.length() < 0.001:
		east = Vector3.RIGHT
	east = east.normalized()
	var south: Vector3 = east.cross(up).normalized()
	return Basis(east, up, south)


# --- Generation -------------------------------------------------------------------------

func generate(lv: int) -> void:
	level = lv
	_gen_mesh(lv)
	_build_topology()
	_build_buckets()
	_build_chunks()


static func _mid(a: int, b: int, pts: PackedVector3Array, cache: Dictionary) -> int:
	var key: int = (mini(a, b) << 32) | maxi(a, b)
	var v: Variant = cache.get(key)
	if v != null:
		return v
	pts.append(((pts[a] + pts[b]) * 0.5).normalized())
	var i: int = pts.size() - 1
	cache[key] = i
	return i


## Neighbours and corners from triangle incidence: every triangle (v, a, b) around v (CCW from
## outside) says "after neighbour a comes b", so a cell's ring is a chain walk, no sorting.
func _build_topology() -> void:
	var n: int = centers.size()
	var nt: int = tris.size() / 3
	# Orientation: the base icosahedron faces are CCW from outside; check once and flip if not.
	var p0: Vector3 = centers[tris[0]]
	var flip: bool = (centers[tris[1]] - p0).cross(centers[tris[2]] - p0).dot(p0) < 0.0
	if flip:
		for f: int in nt:
			var tmp: int = tris[f * 3 + 1]
			tris[f * 3 + 1] = tris[f * 3 + 2]
			tris[f * 3 + 2] = tmp
	tri_center.resize(nt)
	var inc_n := PackedByteArray()
	inc_n.resize(n)
	var inc := PackedInt32Array()  # cell * 6 + k -> triangle
	inc.resize(n * MAX_N)
	for f: int in nt:
		var a: int = tris[f * 3]
		var b: int = tris[f * 3 + 1]
		var c: int = tris[f * 3 + 2]
		tri_center[f] = (centers[a] + centers[b] + centers[c]).normalized()
		inc[a * MAX_N + inc_n[a]] = f
		inc_n[a] += 1
		inc[b * MAX_N + inc_n[b]] = f
		inc_n[b] += 1
		inc[c * MAX_N + inc_n[c]] = f
		inc_n[c] += 1
	nbr_count = inc_n
	nbr.resize(n * MAX_N)
	nbr.fill(-1)
	cell_tri.resize(n * MAX_N)
	cell_tri.fill(-1)
	var nxt_of := PackedInt32Array()
	nxt_of.resize(MAX_N * 2)
	for v: int in n:
		var k: int = inc_n[v]
		var base: int = v * MAX_N
		# For each incident triangle: the vertex after v (a) and the one after a (b).
		for s: int in k:
			var f: int = inc[base + s]
			var i0: int = tris[f * 3]
			var i1: int = tris[f * 3 + 1]
			var i2: int = tris[f * 3 + 2]
			if i0 == v:
				nxt_of[s * 2] = i1
				nxt_of[s * 2 + 1] = i2
			elif i1 == v:
				nxt_of[s * 2] = i2
				nxt_of[s * 2 + 1] = i0
			else:
				nxt_of[s * 2] = i0
				nxt_of[s * 2 + 1] = i1
		var cur: int = 0
		for slot: int in k:
			nbr[base + slot] = nxt_of[cur * 2]
			cell_tri[base + slot] = inc[base + cur]
			var want: int = nxt_of[cur * 2 + 1]
			for s: int in k:
				if nxt_of[s * 2] == want:
					cur = s
					break


func _bucket_index(d: Vector3) -> int:
	var ax: float = absf(d.x)
	var ay: float = absf(d.y)
	var az: float = absf(d.z)
	var face: int
	var u: float
	var w: float
	if ax >= ay and ax >= az:
		face = 0 if d.x > 0.0 else 1
		u = d.y / ax
		w = d.z / ax
	elif ay >= az:
		face = 2 if d.y > 0.0 else 3
		u = d.x / ay
		w = d.z / ay
	else:
		face = 4 if d.z > 0.0 else 5
		u = d.x / az
		w = d.y / az
	var m: int = _bucket_m
	var iu: int = clampi(int((u * 0.5 + 0.5) * m), 0, m - 1)
	var iw: int = clampi(int((w * 0.5 + 0.5) * m), 0, m - 1)
	return (face * m + iu) * m + iw


static func _bucket_dir(face: int, u: float, w: float) -> Vector3:
	match face:
		0: return Vector3(1, u, w).normalized()
		1: return Vector3(-1, u, w).normalized()
		2: return Vector3(u, 1, w).normalized()
		3: return Vector3(u, -1, w).normalized()
		4: return Vector3(u, w, 1).normalized()
	return Vector3(u, w, -1).normalized()


func _build_buckets() -> void:
	# About 4 cells per bucket: a lookup walks 1-2 steps.
	_bucket_m = maxi(2, int(sqrt(float(centers.size()) / 24.0)))
	var m: int = _bucket_m
	_bucket.resize(6 * m * m)
	var hint: int = 0
	for face: int in 6:
		for iu: int in m:
			for iw: int in m:
				var d: Vector3 = _bucket_dir(face, (iu + 0.5) / m * 2.0 - 1.0, (iw + 0.5) / m * 2.0 - 1.0)
				hint = walk(d, hint)
				_bucket[(face * m + iu) * m + iw] = hint


func _build_chunks() -> void:
	chunk_level = maxi(0, level - CHUNK_DROP)
	var nc: int = cells_at_level(chunk_level)
	var n: int = centers.size()
	cell_chunk.resize(n)
	var counts := PackedInt32Array()
	counts.resize(nc)
	var hint: int = 0
	for i: int in n:
		# Coarse cell ids are a prefix of the fine ids: walk the coarse grid to the nearest one.
		hint = _nearest_coarse(centers[i], hint, nc)
		cell_chunk[i] = hint
		counts[hint] += 1
	chunk_start.resize(nc + 1)
	var acc: int = 0
	for c: int in nc:
		chunk_start[c] = acc
		acc += counts[c]
	chunk_start[nc] = acc
	chunk_cells.resize(n)
	var fill := chunk_start.duplicate()
	for i: int in n:
		var c: int = cell_chunk[i]
		chunk_cells[fill[c]] = i
		fill[c] += 1
	chunk_radius.resize(nc)
	chunk_radius.fill(0.0)
	for i: int in n:
		var c: int = cell_chunk[i]
		var a: float = centers[c].angle_to(centers[i])
		if a > chunk_radius[c]:
			chunk_radius[c] = a
	var cell_r: float = centers[12].angle_to(tri_center[cell_tri[12 * MAX_N]])
	for c: int in nc:
		chunk_radius[c] += cell_r


var _coarse: SphereGrid


func _nearest_coarse(d: Vector3, hint: int, nc: int) -> int:
	if nc == centers.size():
		return walk(d, mini(hint, nc - 1))
	if _coarse == null:
		_coarse = SphereGrid.new()
		_coarse.generate_topology_only(chunk_level)
	return _coarse.walk(d, mini(hint, nc - 1))


## A grid without buckets or chunks (used for the coarse chunk grid).
func generate_topology_only(lv: int) -> void:
	level = lv
	_gen_mesh(lv)
	_build_topology()


func _gen_mesh(lv: int) -> void:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var pts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	])
	for i: int in pts.size():
		pts[i] = pts[i].normalized()
	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for _l: int in lv:
		var cache: Dictionary = {}
		var nf := PackedInt32Array()
		nf.resize(faces.size() * 4)
		var w: int = 0
		for f: int in range(0, faces.size(), 3):  # same face list and midpoint order as GeoSphere
			var a: int = faces[f]
			var b: int = faces[f + 1]
			var c: int = faces[f + 2]
			var ab: int = _mid(a, b, pts, cache)
			var bc: int = _mid(b, c, pts, cache)
			var ca: int = _mid(c, a, pts, cache)
			nf[w] = a; nf[w + 1] = ab; nf[w + 2] = ca
			nf[w + 3] = b; nf[w + 4] = bc; nf[w + 5] = ab
			nf[w + 6] = c; nf[w + 7] = ca; nf[w + 8] = bc
			nf[w + 9] = ab; nf[w + 10] = bc; nf[w + 11] = ca
			w += 12
		faces = nf
	centers = pts
	tris = faces


# --- Cache ------------------------------------------------------------------------------

func save_cache(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_32(CACHE_VERSION)
	f.store_32(level)
	for a: Variant in [centers, nbr_count, nbr, cell_tri, tris, tri_center, cell_chunk, chunk_start, chunk_cells, chunk_radius, _bucket]:
		f.store_var(a)
	f.store_32(_bucket_m)
	f.store_32(chunk_level)


func load_cache(path: String, lv: int) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != CACHE_VERSION or f.get_32() != lv:
		return false
	level = lv
	centers = f.get_var()
	nbr_count = f.get_var()
	nbr = f.get_var()
	cell_tri = f.get_var()
	tris = f.get_var()
	tri_center = f.get_var()
	cell_chunk = f.get_var()
	chunk_start = f.get_var()
	chunk_cells = f.get_var()
	chunk_radius = f.get_var()
	_bucket = f.get_var()
	_bucket_m = f.get_32()
	chunk_level = f.get_32()
	return centers.size() == cells_at_level(lv) and _bucket.size() == 6 * _bucket_m * _bucket_m
