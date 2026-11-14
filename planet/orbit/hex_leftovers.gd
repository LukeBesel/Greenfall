class_name HexLeftovers
extends RefCounted
## [v8hex] Owner item (Nov 13): "This starter hex i cleared but it says 94% and i dont get
## anything". Whether Lumi can find and take a junk piece where it lies. The hex audit
## (--hex-audit) and the leftover rule (SphereField.leftover_check) share this test, so the rule
## sweeps exactly what the audit calls stuck. A piece can't be taken when it is:
##   "locked"   in a locked biome's cell,
##   "big"      above Lumi's Lift Strength (only counted where the hex should hold none: the start area),
##   "building" inside a building footprint (YardKeepOut.in_building),
##   "under"    under a collider less than UNDER_M above it (a planting bed, a slab, a bench seat),
##   "inside"   inside a solid collider (a wall, a bin, a bench),
##   "shut"     with no free dry ground within reach that leads out (out in a lake, walled in).
## The collider tests only work where colliders are loaded (near Lumi); elsewhere they pass.

const UNDER_M: float = 1.0
const BOX_M: float = 0.16
## Colliders are loaded this far round Lumi: past it the leftover rule doesn't judge (robots clear by numbers).
const NEAR_M: float = 60.0

var field: SphereField
var reach: TargetReach
var space: PhysicsDirectSpaceState3D
var lumi: Node3D  # optional: the collider tests run only near him
var last_hit: String = ""
var _ray := PhysicsRayQueryParameters3D.new()
var _pq := PhysicsShapeQueryParameters3D.new()


static func for_world(w: Node) -> HexLeftovers:
	if w == null or not (w.get("field") is SphereField):
		return null
	var h := HexLeftovers.new()
	h.field = w.get("field")
	h.space = (w as Node3D).get_world_3d().direct_space_state if w is Node3D and (w as Node3D).is_inside_tree() else null
	h.reach = TargetReach.for_field(h.field, h.space)
	h.lumi = w.get("patch") as Node3D
	h._ray.collision_mask = PhysLayers.SOLID
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * BOX_M
	h._pq.shape = box
	h._pq.collision_mask = PhysLayers.SOLID
	return h


## Why piece pid can't be taken where it lies ("" when it can). big_counts: a piece above Lift
## Strength 0 counts as stuck (the start area holds none); else big pieces pass (Lumi sees them
## and comes back with more Lift Strength).
## max_size: the biggest size class that counts as takeable when big_counts ([v9c] a far station's
## audit passes the Lift a player has there; -1 = the start area's Lift 0).
func why(pid: int, big_counts: bool = true, phys: bool = true, max_size: int = -1) -> String:
	var f: SphereField = field
	var c: int = f.piece_hex[pid]
	if f.locked.has(c):
		return "locked"
	if big_counts and int(f.piece_size[pid]) > (Pace.SIZE_SMALL if max_size < 0 else max_size):
		return "big"
	var p: Vector3 = f.piece_pos[pid]
	var d: Vector3 = p.normalized()
	if reach.keep_out and reach.keep_out.in_building(d):
		return "building"
	var near: bool = phys and space != null and (lumi == null or not is_instance_valid(lumi) or lumi.global_position.distance_to(p) < NEAR_M)
	if near:
		var k: String = _covered(p, d)
		if k != "":
			return k
	var keep: PhysicsDirectSpaceState3D = reach.space
	if not near:
		reach.space = null
	var r: String = reach.reach(p)
	reach.space = keep
	return "shut" if r != "" else ""


## Whether Lumi can find and take piece pid (the leftover rule's test: big pieces pass outside the
## start area, SphereField.small_only).
func findable(pid: int) -> bool:
	return why(pid, field.small_only.has(field.piece_hex[pid])) == ""


## Whether a world point (a piece's spot) lies under or inside a collider (false without colliders).
func covered(p: Vector3) -> bool:
	return space != null and _covered(p, p.normalized()) != ""


func _covered(p: Vector3, up: Vector3) -> String:
	_ray.from = p + up * UNDER_M
	_ray.to = p + up * 0.1
	var ex: Array[RID] = []
	for t: int in 4:
		_ray.exclude = ex
		var hit: Dictionary = space.intersect_ray(_ray)
		if hit.is_empty():
			break
		var hc: Object = hit.get("collider")
		if is_terrain(hc):
			ex.append(hit["rid"])
			continue
		last_hit = describe(hc)
		return "under"
	_pq.transform = Transform3D(SphereGrid.frame(up), p + up * 0.1)
	for h: Dictionary in space.intersect_shape(_pq, 4):
		var co: Object = h.get("collider")
		if is_terrain(co):
			continue
		last_hit = describe(co)
		return "inside"
	return ""


## The globe's own ground (the streamer's chunk colliders sit at the planet's centre; every prop
## stands out on its surface).
static func is_terrain(o: Object) -> bool:
	return o is Node3D and ((o as Node).is_in_group("ground") or (o as Node3D).global_position.length() < 100.0)


static func describe(o: Object) -> String:
	if not (o is Node):
		return str(o)
	var n: Node = o
	var parts: PackedStringArray = []
	while n and parts.size() < 4:
		parts.insert(0, str(n.name))
		n = n.get_parent()
	return "/".join(parts)
