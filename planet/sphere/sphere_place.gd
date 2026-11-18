class_name SpherePlace
extends RefCounted
## [smove] Placing things on a planet and the tractor-beam scoop on curved ground.
## Placement: normal-aligned basis with a yaw about the local up (random or given), optional
## partial tilt onto the terrain normal and a sink depth. Scatter: uniform points in a geodesic
## cap. Scoop: the cone test is done in the scooper's tangent frame with surface (arc) distances,
## and the magnet pull moves pieces along the ground instead of along a flat XZ plane.


## Basis whose +Y is `up` and that is turned `yaw` radians about it. Stable at the poles (no lat/lon).
static func align(up: Vector3, yaw: float, ref_fwd: Vector3 = Vector3.ZERO) -> Basis:
	var f: Vector3 = SphereMath.tangent_dir(ref_fwd if ref_fwd != Vector3.ZERO else SphereMath.any_perpendicular(up), up)
	return SphereMath.basis_from_up_fwd(up, f.rotated(up, yaw))


## Transform for an item on the ground at unit direction `dir`. `tilt` blends the up from the
## radial (0) to the terrain normal (1); `sink` pushes it into the ground (metres); `scale_v`.
static func on_surface(surface: SphereSurface, dir: Vector3, yaw: float, tilt: float = 1.0, sink: float = 0.0, scale_v: float = 1.0) -> Transform3D:
	var n: Vector3 = surface.ground_normal(dir)
	var up: Vector3 = SphereMath.slerp_safe(dir, n, clampf(tilt, 0.0, 1.0))
	var b: Basis = align(up, yaw).scaled_local(Vector3.ONE * scale_v)
	return Transform3D(b, surface.ground(dir) - up * sink)


## Random-yaw version for scattering junk and props.
static func random_on_surface(surface: SphereSurface, dir: Vector3, rng: RandomNumberGenerator, tilt: float = 1.0, sink: float = 0.0, scale_v: float = 1.0) -> Transform3D:
	return on_surface(surface, dir, rng.randf() * TAU, tilt, sink, scale_v)


## Uniformly random unit direction within `radius_m` (surface distance) of `center_dir`.
static func random_in_cap(center_dir: Vector3, radius_m: float, planet_r: float, rng: RandomNumberGenerator) -> Vector3:
	var amax: float = minf(radius_m / planet_r, PI)
	var cos_a: float = lerpf(1.0, cos(amax), rng.randf())  # uniform on the cap's area
	var a: float = acos(clampf(cos_a, -1.0, 1.0))
	var t: Vector3 = SphereMath.any_perpendicular(center_dir).rotated(center_dir, rng.randf() * TAU)
	return (center_dir * cos(a) + t * sin(a)).normalized()


## Position of `p` in the tangent frame at `origin` (x right, y up, z forward, metres), using
## surface distance for the horizontal part so it stays right however far the curve has dropped.
static func local_xyz(surface: SphereSurface, origin: Vector3, fwd: Vector3, p: Vector3) -> Vector3:
	var u: Vector3 = surface.up_at(origin)
	var f: Vector3 = SphereMath.tangent_dir(fwd, u)
	var r: Vector3 = f.cross(u)
	var pu: Vector3 = surface.up_at(p)
	var arc: float = u.angle_to(pu) * surface.radius
	var t: Vector3 = SphereMath.tangent_dir(pu, u, f)
	var flat: Vector3 = t * arc
	return Vector3(flat.dot(r), surface.altitude(p) - surface.altitude(origin), flat.dot(f))


## Is `p` inside the scoop: ahead within `reach` metres and within half-`width` sideways
## (widening a little with distance like Patch's cone), at most `max_rise` above/below.
static func in_scoop(surface: SphereSurface, origin: Vector3, fwd: Vector3, p: Vector3, reach: float, width: float, max_rise: float = 1.6) -> bool:
	var l: Vector3 = local_xyz(surface, origin, fwd, p)
	if l.z < -0.3 or l.z > reach or absf(l.y) > max_rise:
		return false
	return absf(l.x) <= width * 0.5 + maxf(l.z, 0.0) * 0.25


## Best scoop target among `points` (index), nearest-ahead first; -1 if none. Mirrors
## HexField.find_scoop_target for curved ground.
static func find_scoop_target(surface: SphereSurface, origin: Vector3, fwd: Vector3, points: Array, reach: float, width: float) -> int:
	var best: int = -1
	var best_s: float = INF
	for i: int in points.size():
		var p: Vector3 = points[i]
		if p == Vector3.INF or origin.distance_squared_to(p) > (reach + 2.0) * (reach + 2.0):
			continue
		if not in_scoop(surface, origin, fwd, p, reach, width):
			continue
		var l: Vector3 = local_xyz(surface, origin, fwd, p)
		var s: float = l.z + absf(l.x) * 1.5
		if s < best_s:
			best_s = s
			best = i
	return best


## Magnet pull: `p` moved `step_m` metres toward `to` along the ground (great circle), keeping
## its height above the terrain. Returns the new world position.
static func pull_along(surface: SphereSurface, p: Vector3, to: Vector3, step_m: float) -> Vector3:
	var a: Vector3 = surface.up_at(p)
	var b: Vector3 = surface.up_at(to)
	var lift: float = surface.altitude(p)
	var nd: Vector3 = SphereMath.step_toward(a, b, step_m / surface.radius)
	return surface.ground(nd) + nd * lift


## Tractor-beam lift path: a point on an arc from the ground `from` to the hopper `to`, bulging
## along the local up (not world +Y) by `arc_h` metres. t = 0..1.
static func beam_arc(surface: SphereSurface, from: Vector3, to: Vector3, t: float, arc_h: float = 0.8) -> Vector3:
	var u: Vector3 = surface.up_at(from.lerp(to, 0.5))
	return from.lerp(to, t) + u * arc_h * 4.0 * t * (1.0 - t)
