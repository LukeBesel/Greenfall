class_name Hex
extends RefCounted
## Axial hex-grid helpers for flat (pointy-top) hex layouts.
## `size` is the hex circumradius (center to corner) in world units.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const SQRT3: float = 1.7320508075688772


static func axial_to_world(axial: Vector2i, size: float) -> Vector2:
	var x: float = size * (SQRT3 * axial.x + SQRT3 * 0.5 * axial.y)
	var y: float = size * (1.5 * axial.y)
	return Vector2(x, y)


static func world_to_axial(p: Vector2, size: float) -> Vector2i:
	var q: float = (SQRT3 / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var r: float = (2.0 / 3.0 * p.y) / size
	return cube_round(q, r)


static func cube_round(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: float = round(q)
	var rr: float = round(r)
	var rs: float = round(s)
	var dq: float = absf(rq - q)
	var dr: float = absf(rr - r)
	var ds: float = absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	@warning_ignore("integer_division")
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


static func neighbors(a: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRECTIONS:
		out.append(a + d)
	return out


## All axial coords within `radius` of the origin, ordered ring by ring (center first).
static func spiral(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i.ZERO]
	for k: int in range(1, radius + 1):
		var h: Vector2i = DIRECTIONS[4] * k
		for side: int in 6:
			for _step: int in k:
				out.append(h)
				h += DIRECTIONS[side]
	return out


static func count_in_radius(radius: int) -> int:
	return 3 * radius * (radius + 1) + 1
