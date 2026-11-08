class_name SphereMath
extends RefCounted
## [smove] Small, allocation-free helpers for moving things on a sphere. No latitude/longitude
## anywhere: frames are built from (up, forward) and parallel-transported between ups, so
## nothing degenerates at the poles and there is no gimbal lock.


## Component of `v` in the tangent plane of `up` (up must be unit length).
static func tangent(v: Vector3, up: Vector3) -> Vector3:
	return v - up * v.dot(up)


## Unit tangent direction of `v` at `up`; `fallback` (also projected) if `v` is (anti)parallel to up.
static func tangent_dir(v: Vector3, up: Vector3, fallback: Vector3 = Vector3.FORWARD) -> Vector3:
	var t: Vector3 = tangent(v, up)
	if t.length_squared() > 1e-10:
		return t.normalized()
	t = tangent(fallback, up)
	if t.length_squared() > 1e-10:
		return t.normalized()
	return any_perpendicular(up)


static func any_perpendicular(up: Vector3) -> Vector3:
	var a: Vector3 = Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	return up.cross(a).normalized()


## Orthonormal basis with +Y = up and -Z = forward (Godot's "looking at" convention).
static func basis_from_up_fwd(up: Vector3, fwd: Vector3) -> Basis:
	var f: Vector3 = tangent_dir(fwd, up)
	var x: Vector3 = f.cross(up).normalized()  # right = fwd x up
	return Basis(x, up, -f)


## Rotates `b` by the minimal rotation that takes `from_up` to `to_up` (parallel transport along
## the great circle between them). This is what keeps a walking frame from spinning.
static func transport(b: Basis, from_up: Vector3, to_up: Vector3) -> Basis:
	var d: float = from_up.dot(to_up)
	if d > 0.999999999:
		return b
	if d < -0.9999:  # antipodal jump (teleport): rotate about any perpendicular axis
		return Basis(any_perpendicular(from_up), PI) * b
	return Basis(Quaternion(from_up, to_up)) * b


## Same as transport() for a single vector.
static func transport_vec(v: Vector3, from_up: Vector3, to_up: Vector3) -> Vector3:
	var d: float = from_up.dot(to_up)
	if d > 0.999999999:
		return v
	if d < -0.9999:
		return Basis(any_perpendicular(from_up), PI) * v
	return Quaternion(from_up, to_up) * v


## Moves unit direction `dir` toward unit direction `goal` by at most `angle` radians along the
## great circle. Returns the new unit direction.
static func step_toward(dir: Vector3, goal: Vector3, angle: float) -> Vector3:
	var a: float = dir.angle_to(goal)
	if a <= angle or a < 1e-9:
		return goal
	return slerp_safe(dir, goal, angle / a)


## Moves unit direction `dir` along tangent heading `heading` by `angle` radians (exact rotation).
## Returns [new_dir, new_heading] so the heading stays the great-circle tangent.
static func advance(dir: Vector3, heading: Vector3, angle: float) -> Array:
	var axis: Vector3 = dir.cross(heading)
	if axis.length_squared() < 1e-12:
		return [dir, heading]
	axis = axis.normalized()
	var q := Quaternion(axis, angle)
	return [(q * dir).normalized(), (q * heading).normalized()]


## Great-circle (surface) distance in metres between two points on a sphere of radius `r`
## centred at `c` (points need not lie exactly on it).
static func arc_dist(a: Vector3, b: Vector3, r: float, c: Vector3 = Vector3.ZERO) -> float:
	return (a - c).angle_to(b - c) * r


## Initial great-circle heading (unit tangent at `from_dir`) toward `to_dir`.
static func heading_to(from_dir: Vector3, to_dir: Vector3, fallback: Vector3 = Vector3.FORWARD) -> Vector3:
	return tangent_dir(to_dir, from_dir, fallback)


## Frame-rate independent smoothing factor (1 - e^(-rate*dt)).
static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## Largest deviation of a basis from orthonormal (0 = perfect). Used by tests.
static func ortho_error(b: Basis) -> float:
	var e: float = 0.0
	e = maxf(e, absf(b.x.length() - 1.0))
	e = maxf(e, absf(b.y.length() - 1.0))
	e = maxf(e, absf(b.z.length() - 1.0))
	e = maxf(e, absf(b.x.dot(b.y)))
	e = maxf(e, absf(b.y.dot(b.z)))
	e = maxf(e, absf(b.z.dot(b.x)))
	return e


## Vector3.slerp that is safe for (nearly) identical unit vectors (Godot's slerp normalises a
## near-zero cross product there and complains about the axis). Returns a unit vector.
static func slerp_safe(a: Vector3, b: Vector3, t: float) -> Vector3:
	var d: float = a.dot(b)
	if d > 0.9999:
		return a.lerp(b, t).normalized()
	if d < -0.9999:
		var ax: Vector3 = any_perpendicular(a)
		return a.rotated(ax, PI * t).normalized()
	return a.slerp(b, t).normalized()
