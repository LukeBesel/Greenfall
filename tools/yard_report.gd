class_name YardReport
extends RefCounted
## What the start yard's layout costs in walking: where the bin and the scale stand, how far the
## nearest hexes and their junk are from them. The bot prints it when it takes control, and
## tests/test_yard_distance.gd holds the layout to the cadence rule (junk within reach of the bin,
## the first hex's middle a few steps away). Distances are metres along the ground.

## Hexes listed, nearest the bin first.
const LISTED: int = 18


## One row per hex near the bin: {hex, bin_m, scale_m, x, z (site-local metres of its middle),
## pieces, junk_min_m, junk_mean_m (its junk against the bin; -1 without junk)}.
static func rows(globe: OrbitPlanet, bin: Vector3, scale: Vector3, count: int = LISTED) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var field: SphereField = globe.field
	var site_inv: Transform3D = globe.terrain.site_transform(globe.sites[0]).affine_inverse()
	for c: int in globe.grid.cells_around(globe.start_cell(), 2):
		if not globe.cells.is_dirty(c) or field.hex_water[c] == 1:
			continue
		var mid: Vector3 = field.hex_center(c)
		var local: Vector3 = site_inv * mid
		var row: Dictionary = {"hex": c, "bin_m": mid.distance_to(bin), "scale_m": mid.distance_to(scale), "x": local.x, "z": local.z,
			"pieces": 0, "junk_min_m": -1.0, "junk_mean_m": -1.0}
		field.materialize(c)
		var sum: float = 0.0
		var nearest: float = INF
		var n: int = 0
		for pid: int in field.pieces_in(c):
			if field.piece_alive[pid] == 0:
				continue
			var d: float = field.piece_pos[pid].distance_to(bin)
			sum += d
			nearest = minf(nearest, d)
			n += 1
		if n > 0:
			row["pieces"] = n
			row["junk_min_m"] = nearest
			row["junk_mean_m"] = sum / float(n)
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["bin_m"]) < float(b["bin_m"]))
	return out.slice(0, count)


static func lines(globe: OrbitPlanet, bin: Vector3, scale: Vector3) -> PackedStringArray:
	var site_inv: Transform3D = globe.terrain.site_transform(globe.sites[0]).affine_inverse()
	var b: Vector3 = site_inv * bin
	var s: Vector3 = site_inv * scale
	var out: PackedStringArray = ["[yard] bin at (%.1f, %.1f), scale at (%.1f, %.1f), %.1f m apart" % [b.x, b.z, s.x, s.z, bin.distance_to(scale)]]
	for row: Dictionary in rows(globe, bin, scale):
		out.append("[yard] hex %d middle (%.1f, %.1f): bin %.1f m, scale %.1f m; %d pieces, nearest %.1f m, mean %.1f m from the bin" % [
			row["hex"], row["x"], row["z"], row["bin_m"], row["scale_m"], row["pieces"], row["junk_min_m"], row["junk_mean_m"]])
	return out
