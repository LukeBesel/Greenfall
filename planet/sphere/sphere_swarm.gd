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


func obstacles_near(d: Vector3, radius_m: float) -> Array:
	var out: Array = []
	var lim: float = radius_m / surface.radius
	for o: Array in obstacles:
		if d.angle_to(o[0]) < lim + float(o[1]) / surface.radius:
			out.append(o)
	return out
