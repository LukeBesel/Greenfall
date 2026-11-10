class_name OrbitUp
extends RefCounted
## Helpers for code that works on the ground of the globe: local up, distance along the ground,
## and "the hexes around here" (the nearby cells of a 164k-cell globe). While no planet is built
## (preview stages, unit tests of single machines) up is +Y and distance is across x/z.

## Cells within this many rings of a point count as "the field" for globe-wide scans (~310 m:
## the ground round a hub, HubFrame.AREA_RINGS).
const RINGS: int = 18


## True once a planet is built (OrbitPlanet sets its radius).
static func on_globe() -> bool:
	return JunkCube.planet_radius > 0.0


## Local up at a world point.
static func up(p: Vector3) -> Vector3:
	return p.normalized() if on_globe() and p.length_squared() > 0.0 else Vector3.UP


## Distance along the ground.
static func ground_dist(a: Vector3, b: Vector3) -> float:
	if on_globe():
		var d: Vector3 = b - a
		var u: Vector3 = a.normalized()
		return (d - u * d.dot(u)).length()
	return Vector2(b.x - a.x, b.z - a.z).length()


## The hex ids a field-wide scan should visit: the cells within `rings` of `around` (every hex of
## a bare HexField in unit tests).
static func hexes(f: HexField, around: Vector3, rings: int = RINGS) -> Variant:
	if f is SphereField:
		var sf: SphereField = f
		return sf.grid.cells_around(sf.grid.cell_at(around), rings)
	return f.hex_count()


## A prop solid on the globe: one box from its meshes' bounds in its own frame (PropColliders.fit
## compares world y, which only works with +Y up). Returns the body (or null without meshes).
static func fit_box(root: Node3D, nm: String = "Props", shrink: float = 0.85) -> StaticBody3D:
	var ab := AABB()
	var first: bool = true
	var inv: Transform3D = root.global_transform.affine_inverse()
	for c: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		ab = b if first else ab.merge(b)
		first = false
	if first:
		return null
	var body: StaticBody3D = PropColliders.body(root, nm)
	PropColliders.add_box(body, Transform3D(root.global_basis.orthonormalized(), root.global_transform * ab.get_center()), ab.size * shrink)
	return body
