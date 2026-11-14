class_name SphereObstacles
extends RefCounted
## [orbC] Buildings and big props of a hub site, for globe robots (which are kinematic and never
## touch physics): every collision shape of a SitePrefab (its SiteBody, or a builder's own bodies)
## becomes ground circles. Circles go to SphereSwarm.obstacles (local keep-right avoidance) and the
## cells under them are blocked for SpherePath routes and job claims, so crews drive round the
## kit buildings instead of through them. Any planet's site works (it reads colliders, not
## builder data).

## Shapes lower than this (m) are walked over (kerbs, slabs).
const MIN_H: float = 0.9
## Long shapes are split into circles about this far apart (m).
const STEP_M: float = 3.0


## [[dir, radius_m], ...] for the solid shapes under `root` (a SitePrefab), in world space.
static func circles(root: Node3D, surface: SphereSurface) -> Array:
	var out: Array = []
	for b: Node in root.find_children("*", "StaticBody3D", true, false):
		for c: Node in (b as Node).get_children():
			var cs: CollisionShape3D = c as CollisionShape3D
			if cs == null or cs.shape == null or cs.disabled:
				continue
			var ab: AABB = _shape_aabb(cs.shape)
			if ab.size == Vector3.ZERO:
				continue
			out.append_array(_circles_of(cs.global_transform, ab, surface))
	# Only the site's own ground: shapes far off the pad (sky props, beacons) are not buildings.
	var half: float = float(root.get("size_m")) * 0.75 if root.get("size_m") != null else 80.0
	var at: Vector3 = surface.up_at(root.global_position)
	var kept: Array = []
	for ob: Array in out:
		if at.angle_to(ob[0]) * surface.radius <= half and float(ob[1]) <= half:
			kept.append(ob)
	return kept


static func _shape_aabb(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s: Vector3 = (sh as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if sh is ConcavePolygonShape3D:
		var f: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces()
		if f.is_empty():
			return AABB()
		var ab := AABB(f[0], Vector3.ZERO)
		for p: Vector3 in f:
			ab = ab.expand(p)
		return ab
	if sh is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (sh as ConvexPolygonShape3D).points
		if pts.is_empty():
			return AABB()
		var ab2 := AABB(pts[0], Vector3.ZERO)
		for p: Vector3 in pts:
			ab2 = ab2.expand(p)
		return ab2
	if sh is CylinderShape3D:
		var cy: CylinderShape3D = sh
		return AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
	if sh is SphereShape3D:
		var r: float = (sh as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * r * 2.0)
	return AABB()


## Circles covering an oriented box's ground footprint (local up = the radial direction there).
static func _circles_of(xf: Transform3D, ab: AABB, surface: SphereSurface) -> Array:
	var ctr: Vector3 = xf * ab.get_center()
	var up: Vector3 = surface.up_at(ctr)
	# The box's three axes in world space; the two most horizontal span the footprint.
	var axes: Array[Vector3] = [xf.basis.x * ab.size.x, xf.basis.y * ab.size.y, xf.basis.z * ab.size.z]
	var vert: int = 0
	for i: int in 3:
		if absf(axes[i].normalized().dot(up)) > absf(axes[vert].normalized().dot(up)):
			vert = i
	if absf(axes[vert].dot(up)) < MIN_H:
		return []
	var h: Array[Vector3] = []
	for i: int in 3:
		if i != vert:
			h.append(SphereMath.tangent(axes[i], up))
	var a: Vector3 = h[0] if h[0].length() >= h[1].length() else h[1]
	var b: Vector3 = h[1] if h[0].length() >= h[1].length() else h[0]
	var long_m: float = a.length()
	var short_m: float = b.length()
	if long_m < 0.05:
		return []
	# Tile the footprint with circles at most STEP_M apart: a tight fit, so robots can work right
	# up to a wall instead of keeping off a building's whole bounding circle.
	var na: int = maxi(1, ceili(long_m / STEP_M))
	var nb: int = maxi(1, ceili(short_m / STEP_M))
	var r: float = sqrt(pow(long_m / na * 0.5, 2.0) + pow(short_m / nb * 0.5, 2.0))
	var out: Array = []
	for i: int in na:
		for j: int in nb:
			var p: Vector3 = ctr + a * ((float(i) + 0.5) / na - 0.5) + b * ((float(j) + 0.5) / nb - 0.5)
			out.append([surface.up_at(p), r])
	return out


## Cells whose centre lies inside any circle (shrunk by `margin_m`, so a cell only half under a
## wall stays usable).
static func blocked_cells(grid: SphereGrid, list: Array, margin_m: float = 2.0) -> PackedInt32Array:
	var seen: Dictionary = {}
	for ob: Array in list:
		var d: Vector3 = ob[0]
		var r: float = float(ob[1]) - margin_m
		if r <= 0.0:
			continue
		for c: int in grid.cells_within(d, r):
			if grid.centers[c].angle_to(d) * grid.radius_m <= r:  # cells_within always returns its start cell
				seen[c] = true
	var out := PackedInt32Array()
	for c: int in seen:
		out.append(c)
	return out
