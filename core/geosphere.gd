class_name GeoSphere
extends RefCounted
## Geodesic hex sphere (Goldberg polyhedron): the dual of a subdivided icosahedron.
## Cells = icosphere vertices (10 * 4^n + 2): 12 pentagons + hexagons. Unit sphere.
## level 6 -> 40,962 cells, level 7 -> 163,842.
## Data per cell: center (unit vector), neighbors (5 or 6, ordered around the cell), corners
## (polygon vertices = centroids of incident triangles, ordered).

var level: int
var centers := PackedVector3Array()
var neighbor_start := PackedInt32Array()  # CSR layout: neighbors of cell i are
var neighbor_list := PackedInt32Array()   #   neighbor_list[neighbor_start[i] .. neighbor_start[i+1])
var tris := PackedInt32Array()            # icosphere triangles (3 ints each)


func _init(p_level: int = 6) -> void:
	level = p_level


func cell_count() -> int:
	return centers.size()


func neighbors(i: int) -> PackedInt32Array:
	return neighbor_list.slice(neighbor_start[i], neighbor_start[i + 1])


func generate() -> void:
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i: int in verts.size():
		verts[i] = verts[i].normalized()
	var faces: PackedInt32Array = PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	var pts := PackedVector3Array(verts)
	for _l: int in level:
		var cache: Dictionary = {}
		var nf := PackedInt32Array()
		nf.resize(faces.size() * 4)
		var w: int = 0
		for f: int in range(0, faces.size(), 3):
			var a: int = faces[f]
			var b: int = faces[f + 1]
			var c: int = faces[f + 2]
			var ab: int = _mid(a, b, pts, cache)
			var bc: int = _mid(b, c, pts, cache)
			var ca: int = _mid(c, a, pts, cache)
			for tri: Array in [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]:
				nf[w] = tri[0]
				nf[w + 1] = tri[1]
				nf[w + 2] = tri[2]
				w += 3
		faces = nf
	centers = pts
	tris = faces
	_build_neighbors()


static func _mid(a: int, b: int, pts: PackedVector3Array, cache: Dictionary) -> int:
	var key: int = (mini(a, b) << 32) | maxi(a, b)
	if cache.has(key):
		return cache[key]
	pts.append(((pts[a] + pts[b]) * 0.5).normalized())
	var i: int = pts.size() - 1
	cache[key] = i
	return i


func _build_neighbors() -> void:
	var n: int = centers.size()
	var adj: Array = []
	adj.resize(n)
	for i: int in n:
		adj[i] = {}
	for f: int in range(0, tris.size(), 3):
		var a: int = tris[f]
		var b: int = tris[f + 1]
		var c: int = tris[f + 2]
		(adj[a] as Dictionary)[b] = true
		(adj[a] as Dictionary)[c] = true
		(adj[b] as Dictionary)[a] = true
		(adj[b] as Dictionary)[c] = true
		(adj[c] as Dictionary)[a] = true
		(adj[c] as Dictionary)[b] = true
	neighbor_start.resize(n + 1)
	neighbor_list.resize(0)
	for i: int in n:
		neighbor_start[i] = neighbor_list.size()
		var ns: Array = (adj[i] as Dictionary).keys()
		# Order neighbors counter-clockwise around the cell center.
		var up: Vector3 = centers[i]
		var ref: Vector3 = (centers[ns[0]] - up * up.dot(centers[ns[0]])).normalized()
		var side: Vector3 = up.cross(ref)
		ns.sort_custom(func(x: int, y: int) -> bool:
			var vx: Vector3 = centers[x] - up * up.dot(centers[x])
			var vy: Vector3 = centers[y] - up * up.dot(centers[y])
			return atan2(vx.dot(side), vx.dot(ref)) < atan2(vy.dot(side), vy.dot(ref)))
		for j: int in ns:
			neighbor_list.append(j)
	neighbor_start[n] = neighbor_list.size()


## Polygon corners of a cell (unit sphere), ordered like its neighbors: corner k lies between
## neighbor k and neighbor k+1.
func corners(i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var ns: PackedInt32Array = neighbors(i)
	for k: int in ns.size():
		var a: Vector3 = centers[ns[k]]
		var b: Vector3 = centers[ns[(k + 1) % ns.size()]]
		out.append((centers[i] + a + b).normalized())
	return out


## Nearest cell to a unit direction, by greedy walk from a starting cell (fast for local moves).
func nearest_from(dir: Vector3, start: int) -> int:
	var cur: int = clampi(start, 0, centers.size() - 1)
	var best_d: float = centers[cur].dot(dir)
	while true:
		var improved: bool = false
		for j: int in neighbors(cur):
			var d: float = centers[j].dot(dir)
			if d > best_d:
				best_d = d
				cur = j
				improved = true
		if not improved:
			return cur
	return cur


## Saves/loads the generated grid to a compact binary file (generation takes a few seconds).
func save_cache(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_32(level)
	f.store_var(centers)
	f.store_var(neighbor_start)
	f.store_var(neighbor_list)
	f.store_var(tris)


func load_cache(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != level:
		return false
	centers = f.get_var()
	neighbor_start = f.get_var()
	neighbor_list = f.get_var()
	tris = f.get_var()
	return centers.size() == 10 * int(pow(4, level)) + 2


static func cached(p_level: int) -> GeoSphere:
	var g := GeoSphere.new(p_level)
	var path: String = "user://geosphere_%d.bin" % p_level
	if not g.load_cache(path):
		g.generate()
		g.save_cache(path)
	return g
