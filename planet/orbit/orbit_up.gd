class_name OrbitUp
extends RefCounted
## [orbB] Helpers that let flat-game code run on the walkable globe unchanged on the flat game:
## local up, distance along the ground, and "the hexes around here" (every hex of a flat district,
## the nearby cells of a 164k-cell globe). On the flat game they return exactly what the flat code
## used (Vector3.UP, the x/z distance, range(hex_count)).

## Cells within this many rings of a point count as "the field" for globe-wide scans (~310 m:
## the hub region, SiteManager.REGION_RINGS).
const RINGS: int = 18


static func on_globe() -> bool:
	return JunkCube.planet_radius > 0.0


## Local up at a world point.
static func up(p: Vector3) -> Vector3:
	return p.normalized() if on_globe() and p.length_squared() > 0.0 else Vector3.UP


## Distance along the ground (the flat game's x/z distance).
static func ground_dist(a: Vector3, b: Vector3) -> float:
	if on_globe():
		var d: Vector3 = b - a
		var u: Vector3 = a.normalized()
		return (d - u * d.dot(u)).length()
	return Vector2(b.x - a.x, b.z - a.z).length()


## The hex ids a field-wide scan should visit: all of a flat field, or the cells within `rings`
## of `around` on a globe.
static func hexes(f: HexField, around: Vector3, rings: int = RINGS) -> Variant:
	if f is SphereField:
		var sf: SphereField = f
		return sf.grid.cells_around(sf.grid.cell_at(around), rings)
	return f.hex_count()
