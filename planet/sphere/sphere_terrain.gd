class_name SphereTerrain
extends RefCounted
## [sgrid] True-scale terrain on a SphereGrid: per-planet height noise (gentle rolling ground plus
## small detail), hub sites flattened to their tangent plane, and surface frames. Pure data and
## read-only after setup, so chunk builders on worker threads can call height() freely.
## (Add or remove sites only on the main thread, then rebuild the touched chunks.)

var grid: SphereGrid
var R: float = 1840.0
var seed_value: int = 4471
## Rolling ground: wavelength ~ 1 / freq metres, amplitude in metres.
var macro_amp: float = 7.0
var macro_freq: float = 1.0 / 420.0
var detail_amp: float = 0.9
var detail_freq: float = 1.0 / 48.0
## Water cells sit this far below the ground (their surface is drawn by the ground shader).
var water_drop: float = 0.6
var _macro := FastNoiseLite.new()
var _detail := FastNoiseLite.new()

## Flattened hub sites: {id, cell, dir, n (plane normal), h0 (plane height at centre), flat, blend,
## cos_out (cos of the outer angular radius), cells}.
var sites: Array[Dictionary] = []
var _next_site: int = 1


func _init(p_grid: SphereGrid, p_seed: int = 4471) -> void:
	grid = p_grid
	R = grid.radius_m
	seed_value = p_seed
	_macro.seed = p_seed + 77
	_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_macro.fractal_type = FastNoiseLite.FRACTAL_FBM
	_macro.fractal_octaves = 3
	_macro.frequency = macro_freq
	_detail.seed = p_seed + 91
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.fractal_type = FastNoiseLite.FRACTAL_NONE
	_detail.frequency = detail_freq


## Change the noise (per planet). Call before building any chunk.
func set_noise(m_amp: float, m_freq: float, d_amp: float, d_freq: float) -> void:
	macro_amp = m_amp
	macro_freq = m_freq
	detail_amp = d_amp
	detail_freq = d_freq
	_macro.frequency = m_freq
	_detail.frequency = d_freq


## Per-cell elevation layer (e.g. PlanetData.elevation): metres = (value - offset) * scale,
## interpolated smoothly (barycentric over the icosphere triangle) and added to the noise.
var cell_elevation := PackedFloat32Array()
var elevation_scale: float = 0.0
var elevation_offset: float = 0.0


## Raise or lower the macro terrain from per-cell values at the grid's level (ids match
## PlanetData at the same level). Lakes then sit low: pass e.g. PlanetData.elevation with
## offset = its sea level. Call before building chunks; values is kept by reference.
func set_cell_elevation(values: PackedFloat32Array, scale_m: float, offset: float = 0.0) -> void:
	cell_elevation = values if values.size() == grid.cell_count() else PackedFloat32Array()
	elevation_scale = scale_m
	elevation_offset = offset


## Interpolated per-cell elevation at a direction (m), 0 without a layer.
func elevation_at(dir: Vector3) -> float:
	if cell_elevation.is_empty():
		return 0.0
	var c: int = grid.cell_at(dir)
	var b6: int = c * SphereGrid.MAX_N
	for k: int in grid.nbr_count[c]:
		var t: int = grid.cell_tri[b6 + k] * 3
		var ia: int = grid.tris[t]
		var ib: int = grid.tris[t + 1]
		var ic: int = grid.tris[t + 2]
		var a: Vector3 = grid.centers[ia]
		var b: Vector3 = grid.centers[ib]
		var cc: Vector3 = grid.centers[ic]
		var wa: float = dir.dot(b.cross(cc))
		var wb: float = dir.dot(cc.cross(a))
		var wc: float = dir.dot(a.cross(b))
		if wa >= -1e-7 and wb >= -1e-7 and wc >= -1e-7:
			var sum: float = maxf(wa + wb + wc, 1e-12)
			var v: float = (cell_elevation[ia] * wa + cell_elevation[ib] * wb + cell_elevation[ic] * wc) / sum
			return (v - elevation_offset) * elevation_scale
	return (cell_elevation[c] - elevation_offset) * elevation_scale


## Natural height (m above R) without sites.
func raw_height(dir: Vector3) -> float:
	var p: Vector3 = dir * R
	var h: float = _macro.get_noise_3dv(p) * macro_amp + _detail.get_noise_3dv(p) * detail_amp
	if not cell_elevation.is_empty():
		h += elevation_at(dir)
	return h


## Terrain height (m above R) for a unit direction, sites included.
func height(dir: Vector3) -> float:
	var h: float = raw_height(dir)
	for s: Dictionary in sites:
		var sd: Vector3 = s["dir"]
		var c: float = sd.dot(dir)
		if c < float(s["cos_out"]):
			continue
		var dist: float = acos(clampf(c, -1.0, 1.0)) * R
		# The pad is the site's tangent plane: the ray along dir meets it at (R + h0) / (dir . n).
		var hp: float = (R + float(s["h0"])) / maxf(c, 0.5) - R
		var fl: float = float(s["flat"])
		var k: float = smoothstep(fl, fl + float(s["blend"]), dist)
		h = lerpf(hp, h, k)
	return h


## Ground point (world, planet centred at the origin) for a unit direction.
func ground(dir: Vector3) -> Vector3:
	var d: Vector3 = dir.normalized()
	return d * (R + height(d))


## Ground point under any world point (projected along the radius).
func ground_below(p: Vector3) -> Vector3:
	return ground(p)


## Altitude of a world point above the terrain.
func altitude(p: Vector3) -> float:
	return p.length() - R - height(p.normalized())


## Surface normal from the height field (central differences, ~1.5 m step).
func ground_normal(dir: Vector3) -> Vector3:
	var d: Vector3 = dir.normalized()
	var f: Basis = SphereGrid.frame(d)
	var e: float = 1.5 / R
	var px: Vector3 = ground(d + f.x * e)
	var nx: Vector3 = ground(d - f.x * e)
	var pz: Vector3 = ground(d + f.z * e)
	var nz: Vector3 = ground(d - f.z * e)
	var n: Vector3 = (pz - nz).cross(px - nx)
	return n.normalized() if n.dot(d) > 0.0 else -n.normalized()


## Surface frame at a direction (x east, y up = radial, z south). Same as SphereGrid.frame.
static func frame(dir: Vector3) -> Basis:
	return SphereGrid.frame(dir)


## Exponential-map chart around a cell: local tangent metres (x east, z south) -> direction.
## Distances along the surface are preserved, so a local layout keeps its sizes on the sphere.
func local_to_dir(cell: int, x: float, z: float) -> Vector3:
	var up: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(up)
	var d: float = sqrt(x * x + z * z)
	if d < 0.0001:
		return up
	var a: float = d / R
	var t: Vector3 = (f.x * x + f.z * z) / d
	return (up * cos(a) + t * sin(a)).normalized()


# --- Hub sites ----------------------------------------------------------------------------

## Flatten and reserve a round patch for a hub prefab centred on `cell`.
## flat_m: radius of the level pad (a 60-100 m prefab wants ~ half its size plus a margin);
## blend_m: width of the ring that blends the pad back into the terrain.
## The pad is the tangent plane at the cell centre at the mean natural height of the patch, so a
## flat local prefab sits exactly on it. Returns {} when the patch would overlap another site or
## water (cells: the `blocked` callable, optional, returns true for cells a site may not cover).
## Result: {id, cell, transform (Transform3D: origin on the pad, basis = surface frame, y up),
## cells (PackedInt32Array covered by pad + blend), flat, blend}.
func reserve_site(cell: int, flat_m: float, blend_m: float = 30.0, blocked: Callable = Callable()) -> Dictionary:
	var dir: Vector3 = grid.centers[cell]
	var outer: float = flat_m + blend_m
	for s: Dictionary in sites:
		var sep: float = (s["dir"] as Vector3).angle_to(dir) * R
		if sep < outer + float(s["flat"]) + float(s["blend"]):
			return {}
	var cells: PackedInt32Array = grid.cells_within(dir, outer, cell)
	if blocked.is_valid():
		for c: int in cells:
			if blocked.call(c):
				return {}
	# Mean natural height over the pad.
	var sum: float = 0.0
	var n: int = 0
	for c: int in cells:
		if grid.centers[c].angle_to(dir) * R <= flat_m:
			sum += raw_height(grid.centers[c])
			n += 1
	var h0: float = sum / maxi(n, 1) if n > 0 else raw_height(dir)
	var s := {"id": _next_site, "cell": cell, "dir": dir, "h0": h0, "flat": flat_m, "blend": blend_m,
		"cos_out": cos(outer / R), "cells": cells}
	_next_site += 1
	var ns: Array[Dictionary] = sites.duplicate()  # a new array: chunk builders on worker threads keep reading the old one
	ns.append(s)
	sites = ns
	var out: Dictionary = s.duplicate()
	out["transform"] = site_transform(s)
	return out


## Local transform of a site: origin on the pad at the cell centre, y = surface normal,
## x east, z south. A prefab built in site-local metres goes under a Node3D with this transform.
func site_transform(s: Dictionary) -> Transform3D:
	var dir: Vector3 = s["dir"]
	return Transform3D(SphereGrid.frame(dir), dir * (R + float(s["h0"])))


func release_site(id: int) -> void:
	for i: int in sites.size():
		if int(sites[i]["id"]) == id:
			var ns: Array[Dictionary] = sites.duplicate()
			ns.remove_at(i)
			sites = ns
			return


## Site covering a direction (pad or blend ring), or {}.
func site_at(dir: Vector3) -> Dictionary:
	for s: Dictionary in sites:
		if (s["dir"] as Vector3).dot(dir.normalized()) >= float(s["cos_out"]):
			return s
	return {}


## Chunks touched by a site (rebuild these after reserve_site / release_site).
func site_chunks(s: Dictionary) -> PackedInt32Array:
	return grid.chunks_within(s["dir"], float(s["flat"]) + float(s["blend"]))
