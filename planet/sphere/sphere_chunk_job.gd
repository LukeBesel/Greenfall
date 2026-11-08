class_name SphereChunkJob
extends RefCounted
## [sgrid] Builds one ground chunk's arrays (mesh, collision faces, hex outlines) off the main
## thread. Reads only immutable data: the grid, the terrain (sites are copy-on-write) and a
## copy-on-write reference to the per-cell state array taken when the job was made.
##
## LOD 0: each hex is a 24-triangle fan (centre, spoke mids, corners, edge mids); every vertex
##        carries its noise-warped owner cell in UV2.x, so ground borders wander instead of
##        tracing hex edges. Corners and edge mids are shared between hexes (computed once).
## LOD 1: each hex is a 12-triangle fan (centre, corners, edge mids), owner = the hex. Same
##        border vertices as LOD 0, so neighbouring chunks of different LODs meet without cracks.

const WATER: int = 5

var chunk: int
var lod: int
var stamp: int
var want_collision: bool
var want_outlines: bool
var grid: SphereGrid
var terrain: SphereTerrain
var state: PackedByteArray
var warp: Array  # 3 FastNoiseLite (x, y, z warp), or empty for no warp
var warp_amount: float = 0.55  # of a hex circumradius
# Results
var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uv2 := PackedVector2Array()
var indices := PackedInt32Array()
var faces := PackedVector3Array()   # collision triangles (when want_collision)
var lines := PackedVector3Array()   # outline segments (when want_outlines)
var build_us: int = 0
var done: bool = false
var _cell_ang: float = 0.0


func run() -> void:
	var t0: int = Time.get_ticks_usec()
	var R: float = terrain.R
	_cell_ang = grid.centers[12].angle_to(grid.tri_center[grid.cell_tri[12 * SphereGrid.MAX_N]])
	var corner_v: Dictionary = {}  # triangle id -> vertex
	var edge_v: Dictionary = {}    # (min cell << 32 | max cell) -> vertex
	var cells: PackedInt32Array = grid.cells_in_chunk(chunk)
	var full: bool = lod == 0
	for cell: int in cells:
		var k: int = grid.nbr_count[cell]
		var b6: int = cell * SphereGrid.MAX_N
		var ctr: Vector3 = grid.centers[cell]
		var vc: int = _vertex(ctr, cell, full)
		var cv := PackedInt32Array()
		cv.resize(k)
		var ev := PackedInt32Array()
		ev.resize(k)
		var cdir := PackedVector3Array()
		cdir.resize(k)
		for i: int in k:
			var t: int = grid.cell_tri[b6 + i]
			cdir[i] = grid.tri_center[t]
			var v: Variant = corner_v.get(t)
			if v == null:
				v = _vertex(cdir[i], cell, full)
				corner_v[t] = v
			cv[i] = v
		for i: int in k:
			var j: int = (i + 1) % k
			var nb: int = grid.nbr[b6 + j]  # the edge corner i -> corner i+1 is shared with neighbour i+1
			var key: int = (mini(cell, nb) << 32) | maxi(cell, nb)
			var v: Variant = edge_v.get(key)
			if v == null:
				v = _vertex((cdir[i] + cdir[j]).normalized(), cell, full)
				edge_v[key] = v
			ev[i] = v
			if want_outlines and (cell < nb or grid.cell_chunk[nb] != chunk):
				var up: Vector3 = ctr * 0.14
				lines.append(verts[cv[i]] + up)
				lines.append(verts[ev[i]] + up)
				lines.append(verts[ev[i]] + up)
				lines.append(verts[cv[j]] + up)
		if full:
			var sv := PackedInt32Array()
			sv.resize(k)
			for i: int in k:
				sv[i] = _vertex((ctr + cdir[i]).normalized(), cell, true)
			for i: int in k:
				var j: int = (i + 1) % k
				var s0: int = sv[i]
				var s1: int = sv[j]
				var e: int = ev[i]
				# Clockwise from outside (Godot front faces); corners run counter-clockwise.
				indices.append_array(PackedInt32Array([vc, s1, s0, s0, e, cv[i], s0, s1, e, s1, cv[j], e]))
		else:
			for i: int in k:
				var j: int = (i + 1) % k
				indices.append_array(PackedInt32Array([vc, ev[i], cv[i], vc, cv[j], ev[i]]))
	if want_collision:
		faces.resize(indices.size())
		for i: int in indices.size():
			faces[i] = verts[indices[i]]
	build_us = Time.get_ticks_usec() - t0
	done = true


func _vertex(d: Vector3, hint: int, full: bool) -> int:
	var own: int = hint
	if full and not warp.is_empty():
		var p: Vector3 = d * terrain.R
		var w := Vector3((warp[0] as FastNoiseLite).get_noise_3dv(p), (warp[1] as FastNoiseLite).get_noise_3dv(p), (warp[2] as FastNoiseLite).get_noise_3dv(p))
		own = grid.walk((d + w * (_cell_ang * warp_amount)).normalized(), hint)
	var R: float = terrain.R
	var h: float = terrain.height(d)
	var wet: bool = state.size() > own and state[own] == WATER
	if wet:
		h -= terrain.water_drop
	var p0: Vector3 = d * (R + h)
	# Normal from the height field (forward differences, 1.5 m), water stays flat.
	var f: Basis = SphereGrid.frame(d)
	var e: float = 1.5 / R
	var dx: Vector3 = (d + f.x * e).normalized()
	var dz: Vector3 = (d + f.z * e).normalized()
	var off: float = -terrain.water_drop if wet else 0.0
	var px: Vector3 = dx * (R + terrain.height(dx) + off)
	var pz: Vector3 = dz * (R + terrain.height(dz) + off)
	var nrm: Vector3 = (pz - p0).cross(px - p0).normalized()
	if nrm.dot(d) < 0.0:
		nrm = -nrm
	verts.append(p0)
	normals.append(nrm)
	uv2.append(Vector2(float(own), float(hint)))
	return verts.size() - 1
