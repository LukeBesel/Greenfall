class_name SphereSteer
extends RefCounted
## [smove] Steering on a sphere. Everything works on unit directions from the planet centre and
## unit tangent headings, so the same code runs for a bot next to Lumi and for one 5 km away.


## Great-circle seek: unit tangent at `dir` toward `goal` (keeps `heading` if already there).
static func seek(dir: Vector3, goal: Vector3, heading: Vector3) -> Vector3:
	return SphereMath.heading_to(dir, goal, heading)


## Separation from nearby agents: tangent push away from each one closer than `radius` metres
## (weights grow as they get closer). `others` = unit directions; `r` = planet radius.
static func separation(dir: Vector3, others: Array, radius_m: float, r: float) -> Vector3:
	var push := Vector3.ZERO
	var lim: float = radius_m / r
	for o: Vector3 in others:
		var a: float = dir.angle_to(o)
		if a < 1e-7 or a > lim:
			continue
		var away: Vector3 = SphereMath.tangent_dir(dir - o, dir)
		push += away * (1.0 - a / lim)
	return push


## Avoidance of static round obstacles (rocks, buildings): `obstacles` = [[dir, radius_m], ...].
## Steers around the side the heading already favours, only for obstacles ahead.
static func avoid(dir: Vector3, heading: Vector3, obstacles: Array, look_m: float, body_m: float, r: float) -> Vector3:
	var out := Vector3.ZERO
	for ob: Array in obstacles:
		var od: Vector3 = ob[0]
		var orad: float = float(ob[1]) + body_m
		var to: Vector3 = SphereMath.tangent(od - dir, dir) * r  # ~metres in the tangent plane
		var ahead: float = to.dot(heading)
		if ahead <= 0.0 or ahead > look_m + orad:
			continue
		var side_v: Vector3 = to - heading * ahead
		var lateral: float = side_v.length()
		if lateral >= orad:
			continue
		var side: Vector3 = heading.cross(dir)  # left-hand tangent... sign below picks the free side
		var s: float = -signf(side_v.dot(side)) if lateral > 0.05 else 1.0
		out += side * s * (1.0 - lateral / orad) * (1.0 - ahead / (look_m + orad)) * 2.0
	return out


## Turns `heading` toward `desired` (both tangent at `dir`) by at most `rate * delta` radians.
static func turn(dir: Vector3, heading: Vector3, desired: Vector3, rate: float, delta: float) -> Vector3:
	var d: Vector3 = SphereMath.tangent_dir(desired, dir, heading)
	var a: float = heading.signed_angle_to(d, dir)
	var m: float = rate * delta
	return SphereMath.tangent_dir(heading.rotated(dir, clampf(a, -m, m)), dir, heading)


## Speed factor for arriving: 1 far away, easing down inside `slow_m`, 0 within `stop_m`.
static func arrive(dist_m: float, stop_m: float, slow_m: float) -> float:
	if dist_m <= stop_m:
		return 0.0
	return clampf((dist_m - stop_m) / maxf(slow_m, 0.01), 0.25, 1.0)
