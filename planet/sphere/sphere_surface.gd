class_name SphereSurface
extends RefCounted
## [smove] What movement needs to know about a planet: centre, base radius, terrain height above
## the base radius, and (optionally) the hex cell under a point. A stand-in sphere is just
## SphereSurface.new(R). The real globe (sphere-grid) plugs in through the Callables:
##   height_fn(dir: Vector3) -> float     metres above `radius` along unit direction `dir`
##   cell_fn(point: Vector3, hint: int) -> int   hex cell id under a world point (-1 = none)
##   center_fn(cell: int) -> Vector3     unit direction of a cell's centre

var center := Vector3.ZERO
var radius: float = 1840.0
var height_fn: Callable
var cell_fn: Callable
var center_fn: Callable
## Finite-difference step for ground normals (metres along the surface).
var normal_step: float = 0.5


func _init(p_radius: float = 1840.0, p_center: Vector3 = Vector3.ZERO) -> void:
	radius = p_radius
	center = p_center


## Local up (unit) at a world point.
func up_at(p: Vector3) -> Vector3:
	var d: Vector3 = p - center
	return d / d.length() if d.length_squared() > 1e-12 else Vector3.UP


func dir_of(p: Vector3) -> Vector3:
	return up_at(p)


func height(dir: Vector3) -> float:
	return height_fn.call(dir) if height_fn.is_valid() else 0.0


## Ground point under unit direction `dir`.
func ground(dir: Vector3) -> Vector3:
	return center + dir * (radius + height(dir))


## Height of world point `p` above the ground beneath it (negative = below the ground).
func altitude(p: Vector3) -> float:
	var d: Vector3 = p - center
	var l: float = d.length()
	return l - (radius + height(d / l))


## Ground point under `p`, offset `lift` metres along the local up.
func project(p: Vector3, lift: float = 0.0) -> Vector3:
	var u: Vector3 = up_at(p)
	return center + u * (radius + height(u) + lift)


## Terrain normal at unit direction `dir` (equals `dir` on a smooth sphere).
func ground_normal(dir: Vector3) -> Vector3:
	if not height_fn.is_valid():
		return dir
	var t1: Vector3 = SphereMath.any_perpendicular(dir)
	var t2: Vector3 = dir.cross(t1)
	var a: float = normal_step / radius
	var p0: Vector3 = ground(dir)
	var p1: Vector3 = ground((dir + t1 * a).normalized())
	var p2: Vector3 = ground((dir + t2 * a).normalized())
	var n: Vector3 = (p1 - p0).cross(p2 - p0)
	if n.dot(dir) < 0.0:
		n = -n
	return n.normalized() if n.length_squared() > 1e-12 else dir


func cell_at(p: Vector3, hint: int = 0) -> int:
	return cell_fn.call(p, hint) if cell_fn.is_valid() else -1


func cell_dir(cell: int) -> Vector3:
	return center_fn.call(cell) if center_fn.is_valid() else Vector3.UP


func circumference() -> float:
	return TAU * radius


## Surface distance (metres, along the base sphere) between two world points.
func arc_dist(a: Vector3, b: Vector3) -> float:
	return SphereMath.arc_dist(a, b, radius, center)
