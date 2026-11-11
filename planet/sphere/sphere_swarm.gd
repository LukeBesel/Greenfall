class_name SphereSwarm
extends RefCounted
## [smove] Neighbour lookup for SphereBots plus static obstacles. A coarse bucket grid on the
## unit cube (direction -> face cell) keeps it O(n) for a few hundred nearby bots; far bots are
## records in SphereCrewSim, not here.

var surface: SphereSurface
var bots: Array[SphereBot] = []
## Static obstacles: [[unit dir, radius_m], ...] (rocks, buildings, Lumi).
var obstacles: Array = []
var bucket_m: float = 16.0
## Below this angle (radians) the straight distance between two directions stands in for the arc
## between them (0.2 rad: the two differ by under 0.2%).
const CHORD_LIMIT: float = 0.2
var _buckets: Dictionary = {}
var _frame: int = -1


func _init(p_surface: SphereSurface) -> void:
	surface = p_surface


func add(b: SphereBot) -> void:
	bots.append(b)
	b.swarm = self


func remove(b: SphereBot) -> void:
	bots.erase(b)
	if b.swarm == self:
		b.swarm = null


func _key(d: Vector3) -> Vector3i:
	var s: float = surface.radius / bucket_m
	return Vector3i(floori(d.x * s), floori(d.y * s), floori(d.z * s))


func _rebuild() -> void:
	var f: int = Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	_buckets.clear()
	for b: SphereBot in bots:
		var k: Vector3i = _key(b.dir)
		if not _buckets.has(k):
			_buckets[k] = []
		(_buckets[k] as Array).append(b)


## Unit directions of other bots within `radius_m` (bucketed; exact distance filtered later).
func neighbors(me: SphereBot, radius_m: float) -> Array:
	_rebuild()
	var out: Array = []
	var k: Vector3i = _key(me.dir)
	var lim: float = radius_m / surface.radius
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			for dz: int in [-1, 0, 1]:
				var arr: Variant = _buckets.get(k + Vector3i(dx, dy, dz))
				if arr == null:
					continue
				for b: SphereBot in arr:
					if b != me and me.dir.angle_to(b.dir) < lim:
						out.append(b.dir)
	return out


## [orbC] Like neighbors(), but the bots themselves (their heading and speed matter for avoidance).
func neighbor_bots(me: SphereBot, radius_m: float) -> Array[SphereBot]:
	_rebuild()
	var out: Array[SphereBot] = []
	var lim: float = radius_m / surface.radius
	# Only the buckets the search radius reaches (usually one or two per axis, not all 27).
	var lo: Vector3i = _key(me.dir - Vector3(lim, lim, lim))
	var hi: Vector3i = _key(me.dir + Vector3(lim, lim, lim))
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var arr: Variant = _buckets.get(Vector3i(x, y, z))
				if arr == null:
					continue
				for b: SphereBot in arr:
					# For the few metres this looks at, the chord is the arc: no arccosine per pair.
					if b != me and me.dir.distance_squared_to(b.dir) < lim * lim:
						out.append(b)
	return out


func obstacles_near(d: Vector3, radius_m: float) -> Array:
	var out: Array = []
	var lim: float = radius_m / surface.radius
	for o: Array in obstacles:
		var reach: float = lim + float(o[1]) / surface.radius
		if reach >= CHORD_LIMIT:
			if d.angle_to(o[0]) < reach:
				out.append(o)
		elif d.distance_squared_to(o[0]) < reach * reach:  # chord for arc: exact enough below CHORD_LIMIT
			out.append(o)
	return out
