class_name TargetReach
extends RefCounted
## [v4world] Owner playtest 3 #55: "The objective led me under a building I can't get to. Every
## target must be reachable." One test for every collectible and objective target on the globe
## (memory shards, outposts, eggs, CDs, the First Seed greenhouse, buried parts, the Ledger relay,
## the purple beacon's point), and the nearest reachable open ground when a spot fails it.
##
## A ground point is FREE when it is:
##   - dry (its cell isn't a lake cell),
##   - outside every building footprint (YardKeepOut.in_building: the start town's, every hub
##     town's and outskirts', the hinterland's; footprints are grown 1 m, so Lumi's box fits),
##   - not steep (rise over 1 m below MAX_RISE: Lumi's motor slides back past 42 degrees),
##   - with `space` set (colliders near Lumi): no solid collider (PhysLayers.SOLID) in a slim
##     Lumi-sized probe there, except colliders under `ignore` (the target's own model).
## A target is REACHABLE when a free point within REACH_M of it leads out over free ground to
## ESCAPE_M from it (no courtyard walled in by buildings, no island of dry cells in a lake).
## Footprints that aren't registered yet (a hub town still building, hinterland hexes not
## decided) can't be seen: callers re-check once they are (YardKeepOut.version).
## Audit: godot --headless --path . -- --fresh --orbit --target-reach  (exit 1 if any fails).

const STEP_M: float = 1.0
const REACH_M: float = 2.0
const ESCAPE_M: float = 26.0
const SEARCH_M: float = 64.0
const MAX_RISE: float = 0.62  # tan(32 deg)
const PROBE := Vector3(0.9, 0.7, 0.9)
const PROBE_Y: float = 0.25 + 0.45
const MAX_FLOOD: int = 5000

var field: SphereField
var terrain: SphereTerrain
var keep_out: YardKeepOut
var space: PhysicsDirectSpaceState3D
var ignore: Node
var _q: PhysicsShapeQueryParameters3D


## The test for a field. p_space: also probe colliders (only loaded near Lumi).
static func for_field(f: SphereField, p_space: PhysicsDirectSpaceState3D = null, p_ignore: Node = null) -> TargetReach:
	var t := TargetReach.new()
	t.field = f
	t.terrain = f.terrain
	var kc: Callable = f.keep_out
	t.keep_out = kc.get_object() as YardKeepOut if kc.is_valid() else null
	t.ignore = p_ignore
	t.space = p_space
	return t


static func for_world(w: Node, with_physics: bool = false, p_ignore: Node = null) -> TargetReach:
	if w == null or w.get("field") == null:
		return null
	var sp: PhysicsDirectSpaceState3D = null
	if with_physics and w is Node3D and w.is_inside_tree():
		sp = (w as Node3D).get_world_3d().direct_space_state
	return for_field(w.get("field") as SphereField, sp, p_ignore)


## Why a ground direction isn't free ("" when it is): "water", "building", "steep", "solid".
func why(d: Vector3) -> String:
	d = d.normalized()
	var g: String = why_ground(d)
	if g != "":
		return g
	if space and _solid(d):
		return "solid"
	return ""


## why() without the collider probe (footprints, water, slope only): the walk out uses this.
func why_ground(d: Vector3) -> String:
	var c: int = field.grid.cell_at(d)
	if c < 0 or field.is_water(c):
		return "water"
	if keep_out and keep_out.in_building(d):
		return "building"
	if _steep(d):
		return "steep"
	return ""


func is_free(d: Vector3) -> bool:
	return why(d) == ""


func _steep(d: Vector3) -> bool:
	var f: Basis = SphereGrid.frame(d)
	var R: float = terrain.R
	var h0: float = terrain.height(d)
	for o: Vector3 in [f.x, f.z, -f.x, -f.z]:
		if absf(terrain.height((d * R + o).normalized()) - h0) > MAX_RISE:
			return true
	return false


func _solid(d: Vector3) -> bool:
	if _q == null:
		_q = PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = PROBE
		_q.shape = box
		_q.collision_mask = PhysLayers.SOLID
	var g: Vector3 = terrain.ground(d)
	_q.transform = Transform3D(SphereGrid.frame(d), g + d * PROBE_Y)
	for hit: Dictionary in space.intersect_shape(_q, 8):
		var co: Object = hit.get("collider")
		if co is Node:
			if ignore and (ignore == co or ignore.is_ancestor_of(co as Node)):
				continue
			if (co as Node).is_in_group("ground"):
				continue
		return true
	return false


## Whether free ground from d leads out to ESCAPE_M from it (a walk on a STEP_M grid in d's
## tangent frame, outward first, so open ground answers in a few dozen steps).
func escapes(d: Vector3) -> bool:
	d = d.normalized()
	if not is_free(d):
		return false
	var f: Basis = SphereGrid.frame(d)
	var R: float = terrain.R
	var lim: int = int(ESCAPE_M / STEP_M)
	var seen: Dictionary = {Vector2i.ZERO: true}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	var n: int = 0
	var nb: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty() and n < MAX_FLOOD:
		var at: Vector2i = stack.pop_back()
		n += 1
		if at.x * at.x + at.y * at.y >= lim * lim:
			return true
		# Push the neighbours, the most outward last (it's popped first).
		var nxt: Array[Vector2i] = []
		for o: Vector2i in nb:
			var q: Vector2i = at + o
			if seen.has(q):
				continue
			seen[q] = true
			var qd: Vector3 = (d * R + (f.x * q.x + f.z * q.y) * STEP_M).normalized()
			if why_ground(qd) == "":
				nxt.append(q)
		nxt.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
		stack.append_array(nxt)
	return n >= MAX_FLOOD  # a big walled area is still a lot of ground: count it as open


## "" when the target at p can be reached (a free point within REACH_M leads out), else why
## not: the reason at p itself ("building", "water", ...) or "shut" (walled in).
func reach(p: Vector3) -> String:
	var d: Vector3 = p.normalized()
	var f: Basis = SphereGrid.frame(d)
	var R: float = terrain.R
	var w0: String = why(d)
	for r: float in [0.0, 1.0, REACH_M]:
		var k_n: int = 1 if r == 0.0 else 8
		for k: int in k_n:
			var a: float = TAU * k / k_n
			var q: Vector3 = (d * R + (f.x * cos(a) + f.z * sin(a)) * r).normalized()
			if escapes(q):
				return ""
	return w0 if w0 != "" else "shut"


## The nearest ground point to p that is free and leads out (p's own ground point when it does),
## searched on rings STEP_M apart out to SEARCH_M. p's ground point when nothing is found.
## avoid: optional Callable(world_point) -> bool for spots the caller rules out too.
func open_spot(p: Vector3, avoid: Callable = Callable()) -> Vector3:
	var d: Vector3 = p.normalized()
	if escapes(d) and not (avoid.is_valid() and bool(avoid.call(terrain.ground(d)))):
		return terrain.ground(d)
	var f: Basis = SphereGrid.frame(d)
	var R: float = terrain.R
	var r: float = STEP_M * 1.5
	while r <= SEARCH_M:
		var k_n: int = maxi(8, int(TAU * r / (STEP_M * 1.5)))
		var a0: float = float(hash(Vector2i(int(r * 10.0), 7)) % 360) * PI / 180.0  # no fixed bias toward +x
		for k: int in k_n:
			var a: float = a0 + TAU * k / k_n
			var q: Vector3 = (d * R + (f.x * cos(a) + f.z * sin(a)) * r).normalized()
			if not is_free(q):
				continue
			if avoid.is_valid() and bool(avoid.call(terrain.ground(q))):
				continue
			if escapes(q):
				return terrain.ground(q)
		r += STEP_M * 1.5
	return terrain.ground(d)


## [v4world] Where the purple beacon may stand for a target at p: p itself unless it lies inside
## a building footprint or a collider (or on water, or walled in), else the nearest open ground.
static func beacon_point(w: Node, p: Vector3) -> Vector3:
	var t: TargetReach = for_world(w, true)
	if t == null:
		return p
	var d: Vector3 = p.normalized()
	var reason: String = t.why(d)
	if reason == "" and t.escapes(d):
		return p
	return t.open_spot(p)
