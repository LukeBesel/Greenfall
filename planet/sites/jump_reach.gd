class_name JumpReach
extends RefCounted
## [v11jump] What Lumi's hop changes in a town (owner, 20 Nov: "Also build in jump mechanic"; the
## rule: a hop must never take the player somewhere they cannot leave, or past a gate).
## On a STEP grid over a site it finds every height Lumi can stand at in each cell (the ground, the
## tops of props, kerbs, low roofs: rays down from TOP_M, then his body must fit there), and floods
## from the start three ways:
##   WALK   what walking reaches (steps up to max_step, any drop),
##   HOP    what hopping can reach at the most (GENEROUS: up to the hop's reach + a margin, leaps
##          from an edge over what is in the way and across gaps, a boosted run-up),
##   HOME   the spots that lead back to the start (STRICT: a hop a little lower than the real one,
##          short leaps only).
## A TRAP is a spot the generous hop reaches that has no strict way back: reachable by jumping but
## not leavable. Also listed: the ground a hop adds to walking (a fenced lot is a gate skipped) and
## what he can get onto (by collider), so the jump height is chosen knowing what it opens.
## Junk heaps are left out (they are walls at any height for Lumi and go as the town is cleaned),
## lake cells are closed (no Hover Jets), bales add nothing (no hop from a bale: SphereMotor).
## Used by --city-walk (the start town) and --target-reach (every hub): planet/sites/city_walk.gd,
## target_audit.gd. `--jump-reach-h=M` tries another hop height; `--jump-reach-debug` lists more.

const STEP: float = 0.5
const TOP_M: float = 6.0
const BODY_R: float = 0.45
const BODY_H: float = 0.9
const BODY_LIFT: float = 0.25   # his body rides this far off what he stands on
const MAX_LV: int = 4
enum { WALK, STRICT, GENEROUS }

var space: PhysicsDirectSpaceState3D
var terrain: SphereTerrain
var field: SphereField
var xf: Transform3D
var half: float
var n: int
## The hop: apex above what he stands on, and walking's step.
var hop_h: float = 0.7
var max_step: float = 0.45
## Cells a leap can cross: GENEROUS (a boosted run-up: 4x walking speed for the hop's time), STRICT.
var leap_gen: int = 17
var leap_strict: int = 2

var _lv: Array = []             # per cell: PackedFloat32Array of standable heights (highest first), or null
var _free: Dictionary = {}      # cell * 64 + height step -> bool
var _q: PhysicsShapeQueryParameters3D
var _ray: PhysicsRayQueryParameters3D
var _owner_at: Dictionary = {}  # node id -> what he stands on there (collider path)
var _skip: Array[RID] = []
## Every surface under 2.5 m the rays met in the cells looked at: {owner: [cells, lowest, highest, cells he could stand on]}.
var surfaces: Dictionary = {}
## Cells looked at: [all, lake, nowhere to stand].
var looked: Array[int] = [0, 0, 0]
## What stands within 0.4 m above the hop's reach, next to where he can be: {owner: [count, least, most above what he stands on]}.
var near_miss: Dictionary = {}


static func hop_height() -> float:
	if DevHooks.has("jump-reach-h"):
		return DevHooks.get_f("jump-reach-h", 0.7)
	return float(Economy.read_json("res://data/patch.json").get("jump", {}).get("height_m", 0.7))


func _init(p_space: PhysicsDirectSpaceState3D, p_terrain: SphereTerrain, p_field: SphereField, p_xf: Transform3D, half_m: float) -> void:
	space = p_space
	terrain = p_terrain
	field = p_field
	xf = p_xf
	half = half_m
	n = int(half_m * 2.0 / STEP) + 1
	_lv.resize(n * n)
	hop_h = hop_height()
	max_step = float(Economy.read_json("res://data/patch.json").get("move", {}).get("max_step", 0.45))
	var cyl := CylinderShape3D.new()
	cyl.radius = BODY_R
	cyl.height = BODY_H
	_q = PhysicsShapeQueryParameters3D.new()
	_q.shape = cyl
	_q.collision_mask = PhysLayers.SOLID
	_q.margin = 0.0


func cell_of(lx: float, lz: float) -> int:
	var ix: int = int(round((lx + half) / STEP))
	var iz: int = int(round((lz + half) / STEP))
	return -1 if ix < 0 or iz < 0 or ix >= n or iz >= n else iz * n + ix


func local_of(c: int) -> Vector2:
	return Vector2((c % n) * STEP - half, floori(float(c) / n) * STEP - half)


func _in_disc(c: int) -> bool:
	var l: Vector2 = local_of(c)
	return l.length_squared() <= half * half


func _up(c: int) -> Vector3:
	var l: Vector2 = local_of(c)
	return (xf * Vector3(l.x, 0, l.y)).normalized()


func _ignored(co: Object) -> bool:
	if not (co is CollisionObject3D):
		return true
	var o: CollisionObject3D = co
	return o.is_in_group("ground") or (o.collision_layer & PhysLayers.MOUND) != 0 or o is CharacterBody3D or o is RigidBody3D


## His body fits at height h (above the ground) in cell c.
func free_at(c: int, h: float) -> bool:
	var key: int = c * 64 + clampi(int(round(h * 8.0)), 0, 63)
	if _free.has(key):
		return _free[key]
	var up: Vector3 = _up(c)
	_q.transform = Transform3D(SphereGrid.frame(up), terrain.ground(up) + up * (h + BODY_LIFT + BODY_H * 0.5 + 0.02))
	var ok: bool = true
	for hit: Dictionary in space.intersect_shape(_q, 8):
		if not _ignored(hit.get("collider")):
			ok = false
			break
	_free[key] = ok
	return ok


## The heights he can stand at in cell c, highest first (empty: nowhere, e.g. inside a wall, water).
func levels(c: int) -> PackedFloat32Array:
	if _lv[c] != null:
		return _lv[c]
	var out := PackedFloat32Array()
	var up: Vector3 = _up(c)
	var cell: int = field.grid.cell_at(up) if field else 0
	looked[0] += 1
	if cell < 0 or (field and field.is_water(cell)):
		looked[1] += 1
		_lv[c] = out
		return out
	var g: Vector3 = terrain.ground(up)
	var y: float = TOP_M
	var owners: Array[String] = []
	var lowest: float = TOP_M  # the lowest surface the rays met
	for k: int in 8:
		if y <= 0.1:
			break
		if _ray == null:
			_ray = PhysicsRayQueryParameters3D.new()
			_ray.collision_mask = PhysLayers.SOLID
			_ray.hit_back_faces = false
			_ray.hit_from_inside = false
		_ray.from = g + up * y
		_ray.to = g - up * 0.3
		_ray.exclude = _skip
		var hit: Dictionary = space.intersect_ray(_ray)
		if hit.is_empty():
			break
		var co: Object = hit.get("collider")
		var h: float = ((hit["position"] as Vector3) - g).dot(up)
		if co is CollisionObject3D and ((co as CollisionObject3D).collision_layer & PhysLayers.MOUND) != 0 or co is CharacterBody3D or co is RigidBody3D:
			_skip.append((co as CollisionObject3D).get_rid())  # heaps, bales, Lumi: not part of the town
			continue
		if h < 0.08 or (co is Node and (co as Node).is_in_group("ground")):
			break
		# A surface less than his ride height above this one buries it (a pad's slab over the
		# ground, a plate on a crate): the body test alone would not see that.
		var buried: bool = lowest - h < BODY_LIFT + 0.02
		lowest = h
		var stand: bool = not buried and (hit["normal"] as Vector3).dot(up) > 0.5 and out.size() < MAX_LV - 1 and free_at(c, h)
		if h < 2.5:  # what there is to get onto, standable or not (for the report)
			var nm: String = _name(co)
			var e: Array = surfaces.get(nm, [0, 99.0, 0.0, 0])
			surfaces[nm] = [int(e[0]) + 1, minf(float(e[1]), h), maxf(float(e[2]), h), int(e[3]) + (1 if stand else 0)]
		if stand:
			out.append(h)
			owners.append(_name(co))
		y = h - 0.06
	if lowest >= BODY_LIFT + 0.02 and free_at(c, 0.0):
		out.append(0.0)
		owners.append("")
	for i: int in out.size():
		if owners[i] != "":
			_owner_at[c * MAX_LV + i] = owners[i]
	if out.is_empty():
		looked[2] += 1
	_lv[c] = out
	return out


func _name(co: Object) -> String:
	if not (co is Node):
		return "?"
	var parts: PackedStringArray = str((co as Node).get_path()).split("/")
	# The last few names say what it is (…/Content/Furniture/PropBody).
	return "/".join(parts.slice(maxi(0, parts.size() - 3)))


func height_of(node: int) -> float:
	@warning_ignore("integer_division")
	var lv: PackedFloat32Array = levels(node / MAX_LV)
	var i: int = node % MAX_LV
	return lv[i] if i < lv.size() else 0.0


## Nothing in the way between heights lo and hi in cell c (checked every 0.4 m).
func _column_free(c: int, lo: float, hi: float) -> bool:
	var h: float = hi
	while h > lo + 0.2:
		if not free_at(c, h):
			return false
		h -= 0.4
	return true


func _nbs(c: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cx: int = c % n
	@warning_ignore("integer_division")
	var cz: int = c / n
	if cx + 1 < n:
		out.append(c + 1)
	if cx > 0:
		out.append(c - 1)
	if cz + 1 < n:
		out.append(c + n)
	if cz > 0:
		out.append(c - n)
	return out


## The nodes one move away from `node` in a mode (WALK / STRICT / GENEROUS).
func moves(node: int, mode: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	@warning_ignore("integer_division")
	var c: int = node / MAX_LV
	var a: float = height_of(node)
	var up_lim: float = max_step
	if mode == STRICT:
		up_lim = maxf(max_step, hop_h + BODY_LIFT - 0.12)
	elif mode == GENEROUS:
		up_lim = maxf(max_step, hop_h + BODY_LIFT + 0.08)
	var edge: bool = false  # a neighbour he cannot simply step into: a leap may start here
	for nb: int in _nbs(c):
		if not _in_disc(nb):
			continue
		var lv: PackedFloat32Array = levels(nb)
		var entered: bool = false
		for i: int in lv.size():
			var b: float = lv[i]
			var d: float = b - a
			if d > up_lim:
				if mode == GENEROUS and d <= up_lim + 0.4:  # just out of reach: listed, to choose the height knowingly
					var own: String = _owner_at.get(nb * MAX_LV + i, "?")
					var e: Array = near_miss.get(own, [0, 99.0, 0.0])
					near_miss[own] = [int(e[0]) + 1, minf(float(e[1]), d), maxf(float(e[2]), d)]
				continue
			if d > 0.05:
				if not free_at(c, b):  # head room to rise to it
					continue
			elif d < -0.05:
				if not free_at(nb, a) or not _column_free(nb, b, a):
					break  # cannot move over that cell at his height: nothing lower either
			out.append(nb * MAX_LV + i)
			entered = true
			break  # the highest one he can take; lower ones lie under it
		if not entered:
			edge = true
	if edge and mode != WALK:
		_leaps(c, a, mode, out)
	return out


## Leaps from an edge: through the air at about the hop's top, over what is in the way, down onto
## the first thing under him.
func _leaps(c: int, a: float, mode: int, out: PackedInt32Array) -> void:
	var fly: float = a + hop_h + (0.07 if mode == GENEROUS else -0.12)
	var land_up: float = (hop_h + BODY_LIFT + 0.08) if mode == GENEROUS else 0.0
	var rng: int = leap_strict
	if mode == GENEROUS:  # from the ground a leap only crosses what is in the way; from a height it can cross gaps
		rng = leap_gen if a >= BODY_LIFT else 6
	if not free_at(c, fly):
		return
	var seen: Dictionary = {c: 0}
	var q: PackedInt32Array = [c]
	var qi: int = 0
	while qi < q.size():
		var at: int = q[qi]
		qi += 1
		var depth: int = seen[at]
		if depth >= rng:
			continue
		for nb: int in _nbs(at):
			if seen.has(nb) or not _in_disc(nb) or not free_at(nb, fly):
				continue
			var cell: int = field.grid.cell_at(_up(nb)) if field else 0
			if cell < 0 or (field and field.is_water(cell)):
				continue  # the shore stops him in the air too
			seen[nb] = depth + 1
			q.append(nb)
			var lv: PackedFloat32Array = levels(nb)
			for i: int in lv.size():
				if lv[i] <= a + land_up:
					if _column_free(nb, lv[i], fly):
						out.append(nb * MAX_LV + i)
					break


func _flood(start: int, mode: int) -> Dictionary:
	var seen: Dictionary = {start: true}
	var stack: PackedInt32Array = [start]
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		for nx: int in moves(at, mode):
			if not seen.has(nx):
				seen[nx] = true
				stack.append(nx)
	return seen


## The audit from `start` (site-local x, z). Returns:
##   ok, walk_m2, hop_m2, new_ground (clusters [m2, centre]), tops ({owner: [count, lowest, highest]}),
##   traps (clusters [cells, centre, height, owner]), walk_traps (the same for walking alone).
func run(start: Vector2) -> Dictionary:
	var out: Dictionary = {"ok": false, "hop_h": hop_h}
	var s_c: int = cell_of(start.x, start.y)
	if s_c < 0 or levels(s_c).is_empty():
		out["error"] = "the start is not free"
		return out
	var s_node: int = s_c * MAX_LV + (levels(s_c).size() - 1)  # the lowest place to stand there (the ground, or the pad's top)
	var walk: Dictionary = _flood(s_node, WALK)
	var hop: Dictionary = _flood(s_node, GENEROUS)
	# The way home: strict moves, turned round.
	var back: Dictionary = {}
	for node: int in hop:
		for nx: int in moves(node, STRICT):
			if hop.has(nx):
				if not back.has(nx):
					back[nx] = []
				(back[nx] as Array).append(node)
	var home: Dictionary = {s_node: true}
	var stack: PackedInt32Array = [s_node]
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		for pv: int in back.get(at, []):
			if not home.has(pv):
				home[pv] = true
				stack.append(pv)
	var trap_nodes: Array[int] = []
	var walk_trap_nodes: Array[int] = []
	var new_ground: Array[int] = []
	var tops: Dictionary = {}
	var walk_g: int = 0
	var hop_g: int = 0
	for node: int in hop:
		var h: float = height_of(node)
		if h < BODY_LIFT:
			hop_g += 1
			if walk.has(node):
				walk_g += 1
			else:
				new_ground.append(node)
		elif not walk.has(node):
			var own: String = _owner_at.get(node, "?")
			var e: Array = tops.get(own, [0, 99.0, 0.0])
			tops[own] = [int(e[0]) + 1, minf(float(e[1]), h), maxf(float(e[2]), h)]
		if not home.has(node):
			trap_nodes.append(node)
			if walk.has(node):
				walk_trap_nodes.append(node)
	out["walk_m2"] = walk_g * STEP * STEP
	out["hop_m2"] = hop_g * STEP * STEP
	out["new_ground"] = _clusters(new_ground)
	out["tops"] = tops
	out["near_miss"] = near_miss
	out["surfaces"] = surfaces
	out["looked"] = looked
	out["traps"] = _clusters(trap_nodes)
	out["walk_traps"] = _clusters(walk_trap_nodes)
	out["ok"] = (out["traps"] as Array).is_empty()
	return out


## Groups nodes that touch (same or neighbouring cells): [cells, centre (site-local), mean height, what is under].
func _clusters(nodes: Array[int]) -> Array:
	var by_cell: Dictionary = {}
	for node: int in nodes:
		@warning_ignore("integer_division")
		var c: int = node / MAX_LV
		if not by_cell.has(c):
			by_cell[c] = []
		(by_cell[c] as Array).append(node)
	var done: Dictionary = {}
	var out: Array = []
	for c0: int in by_cell:
		if done.has(c0):
			continue
		done[c0] = true
		var stack: PackedInt32Array = [c0]
		var cnt: int = 0
		var sum := Vector2.ZERO
		var hsum: float = 0.0
		var own: String = ""
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for node: int in by_cell[c]:
				cnt += 1
				sum += local_of(c)
				hsum += height_of(node)
				if own == "":
					own = _owner_at.get(node, "")
			for nb: int in _nbs(c):
				if by_cell.has(nb) and not done.has(nb):
					done[nb] = true
					stack.append(nb)
		out.append([cnt, sum / cnt, hsum / cnt, own])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	return out


## The report lines for a result (tag e.g. "[walk]" or "[targets] hub 3").
static func report(tag: String, r: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	if r.has("error"):
		lines.append("%s hop: %s" % [tag, r["error"]])
		return lines
	var ng: Array = r["new_ground"]
	var ng_m2: float = 0.0
	var ng_s: PackedStringArray = []
	for e: Array in ng:
		ng_m2 += int(e[0]) * STEP * STEP
		if ng_s.size() < 8:
			ng_s.append("%.1f m2@(%.0f,%.0f)" % [int(e[0]) * STEP * STEP, (e[1] as Vector2).x, (e[1] as Vector2).y])
	lines.append("%s hop %.2f m (onto things up to %.2f m): ground %d m2 walking, +%.1f m2 more by hopping in %d places%s" % [
		tag, float(r["hop_h"]), float(r["hop_h"]) + BODY_LIFT, int(r["walk_m2"]), ng_m2, ng.size(), "" if ng_s.is_empty() else " (" + ", ".join(ng_s) + ")"])
	var tops: Dictionary = r["tops"]
	var keys: Array = tops.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(tops[a][0]) > int(tops[b][0]))
	var ts: PackedStringArray = []
	for k: String in keys.slice(0, 14 if not DevHooks.has("jump-reach-debug") else 200):
		ts.append("%s x%d %.1f-%.1f m" % [k, int(tops[k][0]), float(tops[k][1]), float(tops[k][2])])
	lines.append("%s hop gets onto %d kinds of thing: %s" % [tag, keys.size(), ", ".join(ts)])
	var nm: Dictionary = r.get("near_miss", {})
	if not nm.is_empty():
		var nk: Array = nm.keys()
		nk.sort_custom(func(a: String, b: String) -> bool: return int(nm[a][0]) > int(nm[b][0]))
		var ns: PackedStringArray = []
		for k: String in nk.slice(0, 10 if not DevHooks.has("jump-reach-debug") else 200):
			ns.append("%s x%d %.2f-%.2f m" % [k, int(nm[k][0]), float(nm[k][1]), float(nm[k][2])])
		lines.append("%s just out of the hop's reach (step up needed): %s" % [tag, ", ".join(ns)])
	if DevHooks.has("jump-reach-debug"):
		var lk: Array = r.get("looked", [0, 0, 0])
		lines.append("%s debug: %d cells looked at, %d lake, %d with nowhere to stand" % [tag, int(lk[0]), int(lk[1]), int(lk[2])])
		var sf: Dictionary = r.get("surfaces", {})
		var sk: Array = sf.keys()
		sk.sort_custom(func(a: String, b: String) -> bool: return int(sf[a][0]) > int(sf[b][0]))
		for k: String in sk.slice(0, 60):
			lines.append("%s debug surface %s: %d cells, %.2f-%.2f m, standable %d" % [tag, k, int(sf[k][0]), float(sf[k][1]), float(sf[k][2]), int(sf[k][3])])
	for which: String in ["walk_traps", "traps"]:
		var tr_: Array = r[which]
		if tr_.is_empty():
			continue
		var s: PackedStringArray = []
		for e: Array in tr_.slice(0, 12):
			s.append("%d cells@(%.1f,%.1f) %.1f m up%s" % [int(e[0]), (e[1] as Vector2).x, (e[1] as Vector2).y, float(e[2]), "" if str(e[3]) == "" else " on " + str(e[3])])
		lines.append("%s %s: %d spots with no way back: %s" % [tag, "walking alone" if which == "walk_traps" else "HOP TRAPS", tr_.size(), ", ".join(s)])
	return lines
