class_name SpherePath
extends RefCounted
## [smove] A* over a GeoSphere cell graph (neighbours in CSR form), heuristic = great-circle
## angle. `passable.call(cell) -> bool` (optional) blocks cells (water, buildings).
## A path across a level-7 globe (~1.7 km between hubs, ~170 hops) expands a few thousand cells.


static func astar(grid: GeoSphere, from: int, to: int, passable: Callable = Callable(), max_expand: int = 60000) -> PackedInt32Array:
	if from == to:
		return PackedInt32Array([to])
	var goal: Vector3 = grid.centers[to]
	var g := {from: 0.0}
	var came := {}
	var closed := {}
	var heap_f := PackedFloat32Array([grid.centers[from].angle_to(goal)])
	var heap_c := PackedInt32Array([from])
	var expanded: int = 0
	while not heap_c.is_empty():
		var cur: int = _pop(heap_f, heap_c)
		if cur == to:
			return _rebuild(came, to)
		if closed.has(cur):
			continue
		closed[cur] = true
		expanded += 1
		if expanded > max_expand:
			break
		var gc: float = g[cur]
		var cdir: Vector3 = grid.centers[cur]
		for k: int in range(grid.neighbor_start[cur], grid.neighbor_start[cur + 1]):
			var nb: int = grid.neighbor_list[k]
			if closed.has(nb):
				continue
			if passable.is_valid() and nb != to and not passable.call(nb):
				continue
			var ng: float = gc + cdir.angle_to(grid.centers[nb])
			if g.has(nb) and ng >= g[nb]:
				continue
			g[nb] = ng
			came[nb] = cur
			_push(heap_f, heap_c, ng + grid.centers[nb].angle_to(goal), nb)
	return PackedInt32Array()


## Cell path -> unit directions, dropping the start cell.
static func to_dirs(grid: GeoSphere, cells: PackedInt32Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i: int in range(1, cells.size()):
		out.append(grid.centers[cells[i]])
	return out


static func _rebuild(came: Dictionary, to: int) -> PackedInt32Array:
	var out := PackedInt32Array([to])
	var c: int = to
	while came.has(c):
		c = came[c]
		out.append(c)
	out.reverse()
	return out


static func _push(hf: PackedFloat32Array, hc: PackedInt32Array, f: float, c: int) -> void:
	hf.append(f)
	hc.append(c)
	var i: int = hf.size() - 1
	while i > 0:
		var p: int = (i - 1) >> 1
		if hf[p] <= hf[i]:
			break
		var tf: float = hf[p]
		hf[p] = hf[i]
		hf[i] = tf
		var tc: int = hc[p]
		hc[p] = hc[i]
		hc[i] = tc
		i = p


static func _pop(hf: PackedFloat32Array, hc: PackedInt32Array) -> int:
	var top: int = hc[0]
	var last: int = hf.size() - 1
	hf[0] = hf[last]
	hc[0] = hc[last]
	hf.resize(last)
	hc.resize(last)
	var i: int = 0
	var n: int = last
	while true:
		var l: int = i * 2 + 1
		var r: int = l + 1
		var m: int = i
		if l < n and hf[l] < hf[m]:
			m = l
		if r < n and hf[r] < hf[m]:
			m = r
		if m == i:
			break
		var tf: float = hf[m]
		hf[m] = hf[i]
		hf[i] = tf
		var tc: int = hc[m]
		hc[m] = hc[i]
		hc[i] = tc
		i = m
	return top
