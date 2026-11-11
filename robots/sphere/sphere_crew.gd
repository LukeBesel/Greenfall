class_name SphereCrew
extends Node3D
## [orbC] The robot crew on a round planet (phase C). Near robots are real SphereBots; far robots
## are records. One brain runs both, so a robot behaves the same whether you watch it or not:
## - Jobs by cell id: claim_dirty() (nearest dirty cell of the hub region, or of the painted zone),
##   route() (SpherePath.astar_grid, water blocked except for skimmers), work_cell() (writes
##   SphereCells and the SphereField ledger through SphereOffline.write_cell).
## - Work rate: Offline.unit_rate(), the same per-robot maths as the offline jump (core/offline.gd,
##   core/sphere_offline.gd). One code path for "off-screen" and "offline".
## - Far crews: past DEMOTE_M from the focus (Lumi) a robot is demoted to a record and moved by
##   SphereCrewSim.advance (exact great-circle steps, no nodes); it is promoted back inside PROMOTE_M.
## - Every working near robot registers a streamer centre with its own small near ring, so its
##   cell's junk is real (materialized pieces) while Lumi is near.
## Roles: clean (Scoopie, Multibot) works dirty cells and drops bales when its hopper is full;
## haul (Haul Bug) carries bales to the depot cell and cashes them; plant (Seedling) plants clean
## cells (1 seed each); water (Drip) waters planted cells; skim (Skimmer) waits for lake junk;
## find (Scrounger) digs buried parts out of cleaned ground and carries them to the base
## (robots/sphere/sphere_scrounge.gd, on the ledger in `chain`).

signal cell_cleaned(cell: int)
signal cell_worked(cell: int)
signal bale_cashed(value: float)
signal parts_delivered(parts: float, hub: int)
signal reporting

const DEMOTE_M: float = 320.0
const PROMOTE_M: float = 260.0
const STALL_S: float = 8.0
const SKIP_S: float = 30.0
## Most cells one route search may open (a hub region is a few thousand cells).
const ROUTE_EXPAND_MAX: int = 6000
const RING_M: float = 18.0
const ARRIVE_M: float = 2.5
const PASS_M: float = 4.0
## _reachable looks this many rings past the hub's region (robots may be sent a little outside).
const REACH_MARGIN_RINGS: float = 2.5
const PASS_TIGHT_M: float = 2.5  # beside a building: past a parked robot's separation, short of cutting its corner
## Looking for work is the crew's dear step (a search over the hub's region, then a route). No
## more than this many microseconds of it start in one tick; robots left over ask on the next.
const FIND_BUDGET_US: int = 1500
## After a search of a hub's whole region found nothing for a role, robots of that role and hub
## are told "nothing" for this long without searching again.
const NOTHING_FOUND_S: float = 1.5
## run_far() has no frame to protect: it starts each step this far under the search budget.
const FAR_RUN_HEADROOM_US: int = 1 << 40
## Robots this far from Lumi (metres) animate every 2nd and every 4th frame.
## A near robot in "work" mode thinks once in this many ticks; a near robot's streamer centre is
## refreshed once in CENTRE_EVERY ticks.
const WORK_THINK_EVERY: int = 4
const CENTRE_EVERY: int = 8
## A robot whose routes keep failing waits longer between tries, up to this many times its pause.
const NO_PATH_BACKOFF_MAX: float = 8.0
const ANIM_HALF_M: float = 45.0
const ANIM_QUARTER_M: float = 110.0
const LOG_KEYS: Array[String] = ["junk", "bales", "hauled", "cells", "planted", "watered", "dumps", "refills", "parts", "idle_s", "stall_s", "unstuck"]

var grid: SphereGrid
var cells: SphereCells
var field: SphereField
var surface: SphereSurface
var swarm: SphereSwarm
var streamer: SphereStreamer
var junk_view: Node  # hide_piece(pid)
var focus: Node3D  # Lumi (null: every robot is far)
var hub_cell: int = -1
var depot_cell: int = -1
## Hub region size in rings: scales with the planet's area per hub (SphereOffline.rings_for).
var rings: int = SphereOffline.REGION_RINGS
var planet_id: String = ""  # "" = the planet being played
var visuals: bool = true
## Seconds between far-crew steps (records are cheap; a step can be any length).
var far_every: float = 0.25
var units: Array[Dictionary] = []
var bales: Array[Dictionary] = []  # {id, cell, value, claimed}
## Painted Command zones: role -> {cell: true}. Empty = the whole hub region.
var zones: Dictionary = {}
var cashed: float = 0.0
## Buried parts in cleaned ground, for the parts finders (null: nothing to find).
var chain: CrewChain
## The planet's pollution kinds (systems/pollution.gd): which hexes hold waste a role's own tool
## clears (misting, cleansing plants). Null on a planet without kinds: every hex is plain junk.
var pollution: Pollution
## The hub a newly built robot works for (-1 or unset: the crew's own hub). Set by the robot chain
## to the base of the city Lumi is in.
var new_robot_hub_fn: Callable
var depots: Dictionary = {}  # hub cell -> depot cell
## Exact drop-off points (unit directions) per hub cell, e.g. the Depot's spot on the start pad.
var depot_points: Dictionary = {}
var spend_seeds: bool = true
## Near budget: at most this many real SphereBots; past it the farthest near robots are records
## too (a fleet of hundreds stays cheap even right around Lumi).
var max_near: int = 48
## Dev: the terrain, so the report can recount cleaned hexes the way a reload does.
var terrain_for_recount: SphereTerrain
var _touched: Dictionary = {}  # dev: cells the crew wrote
## Robot looks (owner: designed per type at the Locker, worn by every robot of that type).
## Every globe robot that becomes real is dressed by dress(): the equipped
## livery (systems/liveries.gd, as on the flat fleet) and then each hook here, called as
## hook.call(body: Node3D, visual: Node3D, type_id: String, tier: int). The Locker's per-type
## design registers itself with SphereCrew.dress_hooks.append(...).
static var dress_hooks: Array[Callable] = []

var _claimed: Dictionary = {}  # cell -> unit name
var _left: Dictionary = {}  # cell -> work target (junk left 0..1) while robots work it
var _skip: Dictionary = {}  # cell -> time it may be claimed again
var _bale_seq: int = 0
var _t: float = 0.0
var _report_done: bool = false
var _names: int = 0
var _near_n: int = 0
var _find_us: int = 0  # microseconds of job search started this tick
var _ticks: int = 0
## hub cell -> {cell: true}: the land a robot can drive to from that hub (see _reachable).
var _reach: Dictionary = {}
var _nothing: Dictionary = {}  # "role:hub" -> time until which a search is known to find nothing
## What the crew costs per frame, for the robot report.
var cost := CrewCost.new()
## Site buildings (SphereObstacles): key -> circles [[dir, radius_m], ...]; cells under them.
var _site_obs: Dictionary = {}
var blocked: Dictionary = {}  # cell -> true
## Near bales as real JunkCubes (only with visuals).
var bale_view: SphereBales
var _obs_t: float = 0.0
var _evict: bool = false  # new buildings: move robots that stand inside one out (once)
const OBSTACLE_RANGE_M: float = 500.0


## [v3qa] The crew in play (Goals.zone_hex_count reads its painted zones: the "Send your robot to
## work" step never finished on the globe, its zones aren't in GameState.world.orders).
static var active: SphereCrew = null


## [v3qa] Cells painted into any role's zone.
func zone_cells() -> Dictionary:
	var out: Dictionary = {}
	for r: Variant in zones:
		for c: Variant in (zones[r] as Dictionary):
			out[int(c)] = true
	return out


func _exit_tree() -> void:
	if active == self:
		active = null


func setup(p_grid: SphereGrid, p_cells: SphereCells, p_field: SphereField, p_surface: SphereSurface, p_swarm: SphereSwarm = null, p_streamer: SphereStreamer = null, p_planet: String = "") -> void:
	active = self  # [v3qa]
	planet_id = p_planet
	rings = SphereOffline.rings_for(p_grid, p_planet)
	if visuals and bale_view == null:
		bale_view = SphereBales.new()
		bale_view.name = "Bales"
		bale_view.crew = self
		add_child(bale_view)
	grid = p_grid
	cells = p_cells
	field = p_field
	surface = p_surface
	swarm = p_swarm
	streamer = p_streamer


# --- Spawning, queries ----------------------------------------------------------------------

## A new robot of `type_id` on `cell` (its hub = `hub`, default the crew's). Returns its unit.
func spawn(type_id: String, tier: int, cell: int, hub: int = -1, p_name: String = "") -> Dictionary:
	if p_name == "":
		p_name = "%s-%d" % [Fleet.NAMES[_names % Fleet.NAMES.size()], _names]
	_names += 1
	var d: Vector3 = _free_spot(grid.centers[cell])
	var u: Dictionary = {"name": p_name, "type": type_id, "tier": tier, "role": SphereRobotKinds.role_of(type_id),
		"hub": hub if hub >= 0 else hub_cell, "hopper": 0.0, "carry": [], "mode": "idle", "job": -1, "bale": -1,
		"work_t": 0.0, "bot": null, "rec": {"dir": d, "heading": SphereMath.any_perpendicular(d), "goal": Vector3.ZERO,
		"path": [], "speed": SphereRobotKinds.speed(type_id, tier), "cell": cell}, "stall_best": INF, "stall_t": 0.0,
		"idle": "", "rescan": 0.0, "log": {}, "far_at": _t - randf() * far_every}
	for k: String in LOG_KEYS:
		u["log"][k] = 0.0
	units.append(u)
	if _focus_dist(d) < PROMOTE_M and near_count() < max_near:
		_promote(u)
	return u


func robots() -> Array[Dictionary]:
	return units


func count(type_id: String) -> int:
	var n: int = 0
	for u: Dictionary in units:
		if u["type"] == type_id:
			n += 1
	return n


func near_count() -> int:
	return _near_n


func is_near(u: Dictionary) -> bool:
	return u["bot"] != null


func unit_dir(u: Dictionary) -> Vector3:
	return (u["bot"] as SphereBot).dir if u["bot"] != null else (u["rec"] as Dictionary)["dir"]


func unit_cell(u: Dictionary) -> int:
	var hint: int = int((u["rec"] as Dictionary).get("cell", 0))
	var c: int = grid.cell_at_from(unit_dir(u), hint)
	(u["rec"] as Dictionary)["cell"] = c
	return c


func _has_goal(u: Dictionary) -> bool:
	if u["bot"] != null:
		return (u["bot"] as SphereBot).has_goal()
	return (u["rec"] as Dictionary).get("goal", Vector3.ZERO) != Vector3.ZERO


func _go(u: Dictionary, cell_path: PackedInt32Array) -> void:
	var dirs: Array[Vector3] = []
	for i: int in range(1, cell_path.size()):
		dirs.append(grid.centers[cell_path[i]])
	if dirs.is_empty():
		dirs.append(grid.centers[cell_path[cell_path.size() - 1]])
	if u["bot"] != null:
		(u["bot"] as SphereBot).go_via(dirs)
	else:
		var r: Dictionary = u["rec"]
		r["goal"] = dirs.pop_front()
		r["path"] = dirs
	u["stall_best"] = INF
	u["stall_t"] = 0.0


# --- [orbC] Stations, outposts and water on the globe (ORBIT_PARITY) -------------------------

const WATER_PER_CELL: float = 4.0
## Set by the slice: puts a JunkCube into the world (haulers unloading on the conveyor).
var add_cube_fn: Callable
## The world (outposts, stations, depot).
var world: Node


func _tank(u: Dictionary) -> float:
	var t: float = Economy.robot_stat(str(u["type"]), "tank", int(u["tier"]))
	return t if t > 0.0 else 20.0


func _baler() -> Node:
	var st: Stations = Stations.of(self)
	return st.baler if st != null else null


## The hopper is full: tip it into the auto-baler when one stands within its service range (near
## robots, as the flat Stations.claim_dump), else drop a bale here. True if it left for the baler.
func _hopper_full(u: Dictionary) -> bool:
	var bl: Node = _baler()
	if bl != null and u["bot"] != null and str(u["role"]) == "clean":
		var st: Stations = Stations.of(self)
		var rng: float = float(st.def("auto_baler").get("service_range", 34.0))
		var p: Vector3 = (u["bot"] as SphereBot).global_position
		if p.distance_to((bl as Node3D).global_position) <= rng and bl.call("can_accept", float(u["hopper"])):
			_drop_job(u)
			var dp: Vector3 = bl.call("dump_point")
			if _route_to(u, grid.cell_at(dp), "to_baler"):
				_append_goal(u, surface.up_at(dp))
				return true
	_drop_bale(u)
	return false


## Junk units as baler contents (type -> volume), mixed by the junk types' weights.
func _hopper_contents(units: float) -> Dictionary:
	var out: Dictionary = {}
	var wsum: float = 0.0
	for id: String in Economy.junk_ids:
		wsum += float(Economy.junk_types[id].get("weight", 1.0))
	for id: String in Economy.junk_ids:
		out[id] = units * float(Economy.junk_types[id].get("weight", 1.0)) / maxf(wsum, 0.001)
	return out


## Where a hauler unloads: the nearest working scale (the Depot or an outpost's, as the flat
## Outposts.nearest_depot), and for a near hauler the conveyor's hopper when Stations.haul_drop
## says it is closer. Returns a unit direction; sets u["drop"].
func _haul_target(u: Dictionary) -> Vector3:
	u["drop"] = ""
	var d: Vector3 = depot_points.get(int(u["hub"]), Vector3.ZERO)
	if d == Vector3.ZERO:
		d = grid.centers[depot_of(int(u["hub"]))]
	var here: Vector3 = surface.ground(unit_dir(u))
	if world != null and world.get("outposts") is Outposts:
		var dp: Depot = Outposts.nearest_depot(world, here)
		if dp != null:
			d = surface.up_at(dp.global_position)
	if u["bot"] != null:
		var to: Vector3 = Stations.haul_drop(u["bot"], surface.ground(d))
		if to.distance_to(surface.ground(d)) > 0.5:
			u["drop"] = "conveyor"
			return surface.up_at(to)
	return _drop_spot_at(u, d)


## Refill a Drip's tank: the nearest of the barrel by the Depot, a working outpost's drum and a
## clean lake within a few rings (the flat WaterNet's sources).
func _go_refill(u: Dictionary, here: int) -> bool:
	var me: Vector3 = unit_dir(u)
	var best := Vector3.ZERO
	var best_d: float = INF
	var cands: Array[Vector3] = []
	var dp: Vector3 = depot_points.get(int(u["hub"]), Vector3.ZERO)
	if dp != Vector3.ZERO:
		cands.append(dp)
	if world != null and world.get("outposts") is Outposts:
		for p: Dictionary in (world.get("outposts") as Outposts).refill_points():
			cands.append(surface.up_at(p["pos"]))
	for c: int in grid.cells_around(here, 6):
		if cells.state[c] == 5 and not water_dirty(c):
			cands.append(_shore_of(c))
			break
	for c2: Vector3 in cands:
		var dd: float = me.angle_to(c2)
		if dd < best_d:
			best_d = dd
			best = c2
	if best == Vector3.ZERO:
		u["idle"] = "no water"
		return false
	if _route_to(u, grid.cell_at(best), "to_refill"):
		_append_goal(u, best)
		return true
	return false


## A hauler's own spot by the depot (a ring 2.2 m out, one slot per hauler name), clear of
## buildings, so several Haul Bugs unloading at once don't jostle on one point.
func _drop_spot(u: Dictionary) -> Vector3:
	return _drop_spot_at(u, depot_points.get(int(u["hub"]), Vector3.ZERO))


func _drop_spot_at(u: Dictionary, dp: Vector3) -> Vector3:
	if dp == Vector3.ZERO:
		return Vector3.ZERO
	var slot: float = float(absi(hash(str(u["name"]))) % 6) / 6.0 * TAU
	var side: Vector3 = SphereMath.any_perpendicular(dp).rotated(dp, slot)
	var at: Vector3 = SphereMath.advance(dp, side, 2.2 / surface.radius)[0]
	if swarm != null and _inside_building(at):
		at = surface.up_at(_approach(surface.ground(at), surface.ground(dp)))
	return at


## One more waypoint at the end of the current route (a point inside the last cell).
func _append_goal(u: Dictionary, d: Vector3) -> void:
	if d == Vector3.ZERO:
		return
	if u["bot"] != null:
		var b: SphereBot = u["bot"]
		if b.has_goal():
			b.path.append(d)
		else:
			b.goal = d
	else:
		var r: Dictionary = u["rec"]
		if r.get("goal", Vector3.ZERO) != Vector3.ZERO:
			(r["path"] as Array).append(d)
		else:
			r["goal"] = d


func _stop(u: Dictionary) -> void:
	if u["bot"] != null:
		var b: SphereBot = u["bot"]
		b.goal = Vector3.ZERO
		b.path.clear()
	else:
		(u["rec"] as Dictionary)["goal"] = Vector3.ZERO
		(u["rec"] as Dictionary)["path"] = []


## The hub cell a robot built now is given.
func hub_for_new_robot() -> int:
	var h: int = int(new_robot_hub_fn.call()) if new_robot_hub_fn.is_valid() else -1
	return h if h >= 0 else hub_cell


## A land cell beside `hub` to set a new robot down on (the hub's depot for the crew's own hub).
func delivery_cell(hub: int) -> int:
	var at: int = depot_of(hub)
	var land: Array[int] = []
	for c: int in grid.cells_around(at, 1):
		if c != at and cells.state[c] != 5 and not blocked.has(c):
			land.append(c)
	return land[randi() % land.size()] if not land.is_empty() else at


## Seconds a robot has had nothing to do without a break (0 while it works or travels).
func idle_for(u: Dictionary) -> float:
	var from: float = float(u.get("idle_from", -1.0))
	return _t - from if from >= 0.0 else 0.0


## Moves a robot to another hub's crew. It is shipped: set down beside that hub (as a far record;
## it becomes real again if Lumi is there) and works that hub's region from now on.
func reassign(u: Dictionary, hub: int) -> void:
	if int(u["hub"]) == hub:
		return
	_drop_job(u)
	if u["bot"] != null:
		_demote(u)
	u["hub"] = hub
	u["idle_from"] = -1.0
	var cell: int = delivery_cell(hub)
	var rec: Dictionary = u["rec"]
	rec["dir"] = _free_spot(grid.centers[cell])
	rec["cell"] = cell
	rec["goal"] = Vector3.ZERO
	rec["path"] = []


## Routes a robot to `c` in `mode` (a helper for the role scripts beside this file).
func send_to(u: Dictionary, c: int, mode: String) -> bool:
	return _route_to(u, c, mode)


func add_waypoint(u: Dictionary, d: Vector3) -> void:
	_append_goal(u, d)


## A robot's own spot by its hub's drop-off point (ZERO when the hub has none).
func base_spot(u: Dictionary) -> Vector3:
	return _drop_spot(u)


## Direct order (Command view): drop the current job and work `cell` next.
func order(u: Dictionary, cell: int) -> void:
	_drop_job(u)
	_claimed[cell] = u["name"]
	u["job"] = cell
	_route_to(u, cell, "go")


# --- Graph: jobs by cell id -----------------------------------------------------------------

## Next dirty cell for a robot at `from` working for `hub` (BFS outward, so nearest first),
## inside the hub region (or the role's painted zone). -1 if none.
func claim_dirty(from: int, hub: int, p_rings: int = -1, role: String = "clean", who: String = "") -> int:
	var zone: Dictionary = zones.get(role, {})
	var lim: float = ((p_rings if p_rings >= 0 else rings) + 0.5) * 17.35
	var nothing_key: String = "%s:%d" % [role, hub]
	if float(_nothing.get(nothing_key, -1.0)) > _t:
		return -1
	if zone.is_empty() and grid.distance_m(from, hub) >= lim:
		from = hub  # outside its region (just built, or ordered away): search from the hub
	# Land robots only take work they can drive to (across a lake a route search would fail, at
	# the price of a full search each time). Painted zone hexes are the player's word: always tried.
	var reach: Dictionary = _reachable(hub) if role != "skim" else {}
	var seen: Dictionary = {from: true}
	var front := PackedInt32Array([from])
	var steps: int = 0
	while not front.is_empty() and steps < 4000:
		var nxt := PackedInt32Array()
		for c: int in front:
			steps += 1
			if (zone.is_empty() or zone.has(c)) and not _claimed.has(c) and float(_skip.get(c, -1.0)) < _t and wants(role, c) \
					and (role == "skim" or reach.has(c) or zone.has(c)):
				_claimed[c] = who
				return c
			for k: int in grid.nbr_count[c]:
				var j: int = grid.nbr[c * SphereGrid.MAX_N + k]
				if seen.has(j):
					continue
				seen[j] = true
				if grid.distance_m(j, hub) < lim or zone.has(j):
					nxt.append(j)
		front = nxt
	if steps < 4000:  # the whole region was looked at, not a search cut short
		_nothing[nothing_key] = _t + NOTHING_FOUND_S
	return -1


## The land cells a robot can drive to from `hub` (its depot), inside the hub's region and a
## little beyond: found once by flooding out over land that is not under a building, and kept
## until the buildings change.
func _reachable(hub: int) -> Dictionary:
	if _reach.has(hub):
		return _reach[hub]
	var lim: float = (rings + REACH_MARGIN_RINGS) * 17.35
	var start: int = depot_of(hub)
	if cells.state[start] == 5 or blocked.has(start):
		for c: int in grid.cells_around(start, 3):
			if cells.state[c] != 5 and not blocked.has(c):
				start = c
				break
	var seen: Dictionary = {start: true}
	var front := PackedInt32Array([start])
	while not front.is_empty():
		var nxt := PackedInt32Array()
		for c: int in front:
			for k: int in grid.nbr_count[c]:
				var j: int = grid.nbr[c * SphereGrid.MAX_N + k]
				if seen.has(j) or cells.state[j] == 5 or blocked.has(j) or grid.distance_m(j, hub) >= lim:
					continue
				seen[j] = true
				nxt.append(j)
		front = nxt
	_reach[hub] = seen
	return seen


## Is `c` work for `role`? (lake junk for skimmers is a SphereField feature still to come)
func wants(role: String, c: int) -> bool:
	match role:
		"plant":
			return (cells.state[c] == 1 and not cells.has_flag(c, SphereCells.F_SITE)) or _held_work(role, c)
		"water":
			return cells.state[c] == 2 or _held_work(role, c)
		"skim":
			return water_dirty(c)
		SphereScrounge.ROLE:
			return chain != null and chain.has_stock(c)
	return cells.workable(c)


## Whether hex `c` holds waste that `role` clears with its own tool (not by scooping).
func _held_work(role: String, c: int) -> bool:
	return pollution != null and pollution.robot_wants(role, c)


## Floating junk on a lake hex (SphereField: water cells with junk left).
func water_dirty(c: int) -> bool:
	return cells.state[c] == 5 and cells.junk[c] > SphereCells.CLEAN_LEFT  # [v2feel]


## Junk units in an untouched cell: a land hex, or a lake hex's floaters.
func units_per(c: int) -> float:
	return SphereOffline.UNITS_PER_WATER_CELL if cells.state[c] == 5 else SphereOffline.UNITS_PER_CELL


func route(from: int, to: int, role: String = "clean") -> PackedInt32Array:
	if from == to:
		return PackedInt32Array([to])
	var pass_fn: Callable = func(c: int) -> bool: return cells.state[c] != 5 and not blocked.has(c)
	if role == "skim":
		pass_fn = func(c: int) -> bool: return not blocked.has(c)  # skimmers float: lakes and shore alike
	var p: PackedInt32Array = SpherePath.astar_grid(grid, from, to, pass_fn, ROUTE_EXPAND_MAX)
	if not p.is_empty() or blocked.is_empty():
		return p
	# Blocked cells are building footprints, inflated so routes keep off the walls: not walls
	# themselves. A robot nudged into a pocket between them (or sent to a bale in one) had no route
	# out and idled there for good. When no tidy route exists the cells may be crossed; a near
	# robot still steers round the real walls. Water stays shut to everything but a Skimmer.
	if role == "skim":
		return SpherePath.astar_grid(grid, from, to, Callable(), ROUTE_EXPAND_MAX)
	return SpherePath.astar_grid(grid, from, to, func(c: int) -> bool: return cells.state[c] != 5, ROUTE_EXPAND_MAX)


func _real_left(c: int) -> float:
	if field != null and field.materialized[c] == 1:
		return 1.0 - field.removed_fraction(c) if field.hex_clean[c] == 0 else 0.0
	return cells.junk[c] if cells.is_dirty(c) or water_dirty(c) else 0.0


func junk_left(c: int) -> float:
	var real: float = _real_left(c)
	if not _left.has(c):
		return real
	if real <= 0.0:
		return 0.0
	# Work target, less anything someone else (Lumi) took since the crew's last write.
	var a: Array = _left[c]
	return clampf(float(a[0]) - maxf(0.0, float(a[1]) - real), 0.0, 1.0)


## Robots work in small steps; a materialized cell loses whole pieces, so the work target is the
## account (the pieces follow it, a piece ahead or behind) - otherwise a step smaller than one
## piece would never add up, and a big piece would lose junk nobody baled.
func work_cell(c: int, left: float) -> void:
	_touched[c] = true
	var was_dirty: bool = cells.is_dirty(c) or water_dirty(c)
	var before: float = cells.junk[c]
	var gone: PackedInt32Array = SphereOffline.write_cell(cells, field, c, left)
	if pollution != null and was_dirty:
		pollution.robot_scooped(c, before - cells.junk[c])
	if left > SphereCells.CLEAN_LEFT and (cells.is_dirty(c) or water_dirty(c)):  # [v2feel]
		_left[c] = [left, _real_left(c)]
	else:
		_left.erase(c)
	if junk_view != null and not gone.is_empty():
		for pid: int in gone:
			junk_view.call("hide_piece", pid)
		if junk_view.has_method("refresh_hex"):
			junk_view.call("refresh_hex", c)
	cell_worked.emit(c)
	if was_dirty and not (cells.is_dirty(c) or water_dirty(c)):
		cell_cleaned.emit(c)


func release(c: int) -> void:
	_claimed.erase(c)


# --- Command zones ----------------------------------------------------------------------------

# --- Buildings ------------------------------------------------------------------------------

## The solid shapes of a site (or any building group) under `key`: routes and claims avoid the
## cells under them, near robots steer round them. Pass [] to clear.
func set_obstacles(key: Variant, circles: Array) -> void:
	if circles.is_empty():
		_site_obs.erase(key)
	else:
		_site_obs[key] = circles
	blocked.clear()
	_reach.clear()
	for k: Variant in _site_obs:
		for c: int in SphereObstacles.blocked_cells(grid, _site_obs[k], -2.0):  # inflated: routes keep 2 m off walls
			blocked[c] = true
	_obs_t = INF  # refresh the swarm's list on the next tick
	_evict = true


## Near robots only meet the buildings of sites close to Lumi (avoidance is linear in obstacles).
func _refresh_swarm_obstacles(delta: float) -> void:
	_obs_t += delta
	if swarm == null or _obs_t < 2.0:
		return
	_obs_t = 0.0
	var list: Array = []
	var fd: Vector3 = surface.up_at(focus.global_position) if focus != null and is_instance_valid(focus) else Vector3.ZERO
	for k: Variant in _site_obs:
		var circ: Array = _site_obs[k]
		if circ.is_empty():
			continue
		if fd != Vector3.ZERO and fd.angle_to((circ[0] as Array)[0]) * surface.radius > OBSTACLE_RANGE_M:
			continue
		list.append_array(circ)
	swarm.obstacles = list
	if _evict:
		_evict = false
		for u: Dictionary in units:
			var d: Vector3 = unit_dir(u)
			if not _inside_building(d):
				continue
			var q: Vector3 = _free_spot(d)
			(u["rec"] as Dictionary)["dir"] = q
			if u["bot"] != null:
				var b: SphereBot = u["bot"]
				b.dir = q
				b.goal = Vector3.ZERO
				b.path.clear()
			if str(u["mode"]) != "idle":
				_drop_job(u)


func set_zone_cell(role: String, cell: int, on: bool) -> void:
	_nothing.clear()  # a new area: look again at once
	if not zones.has(role):
		zones[role] = {}
	if on:
		(zones[role] as Dictionary)[cell] = true
	else:
		(zones[role] as Dictionary).erase(cell)


func clear_zone(role: String) -> void:
	_nothing.clear()
	zones.erase(role)


# --- Loop -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	tick(delta)
	cost.add(Time.get_ticks_usec() - t0, SphereBot.take_step_usec())
	_maybe_report()


## One crew step: near robots think every frame (their SphereBots move themselves), far robots
## are stepped every far_every seconds, each on its own clock so their steps spread over the
## frames instead of all landing on one; demotion and promotion with hysteresis.
func tick(delta: float) -> void:
	_t += delta
	_find_us = 0
	_refresh_swarm_obstacles(delta)
	_ticks += 1
	var slot: int = _ticks
	for u: Dictionary in units:
		slot += 1  # each robot has its own turn, so the staggered steps below spread over the ticks
		var near: bool = u["bot"] != null
		if near:
			var d: float = _focus_dist(unit_dir(u))
			if d > DEMOTE_M:
				_demote(u)
				near = false
			else:
				(u["bot"] as SphereBot).anim_every = 1 if d < ANIM_HALF_M else (2 if d < ANIM_QUARTER_M else 4)
				# A robot at work only counts time: it thinks every few ticks, with the time since.
				if str(u["mode"]) == "work" and slot % WORK_THINK_EVERY != 0:
					u["think_dt"] = float(u.get("think_dt", 0.0)) + delta
					continue
				_think(u, delta + float(u.get("think_dt", 0.0)))
				u["think_dt"] = 0.0
				if slot % CENTRE_EVERY == 0:
					_update_centre(u)
				continue
		var far_dt: float = _t - float(u["far_at"])
		if far_dt < far_every:
			continue
		u["far_at"] = _t
		SphereCrewSim.advance(u["rec"], far_dt, surface.radius)
		_think(u, far_dt)
		if _focus_dist(unit_dir(u)) < PROMOTE_M and near_count() < max_near:
			_promote(u)
	_enforce_budget()


## Manually advance every robot as a far record (dev and tests: a crew with no frame loop).
func run_far(seconds: float, step_s: float = 1.0) -> void:
	var left: float = seconds
	while left > 0.0:
		var dt: float = minf(step_s, left)
		left -= dt
		_t += dt
		_find_us = -FAR_RUN_HEADROOM_US  # no frame to keep smooth here: every robot may look for work
		for u: Dictionary in units:
			if u["bot"] == null:
				u["far_at"] = _t
				SphereCrewSim.advance(u["rec"], dt, surface.radius)
				_think(u, dt)


## Demote the farthest near robots while there are more than max_near.
func _enforce_budget() -> void:
	if _near_n <= max_near:
		return
	var near: Array[Dictionary] = []
	for u: Dictionary in units:
		if u["bot"] != null:
			near.append(u)
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _focus_dist(unit_dir(a)) > _focus_dist(unit_dir(b)))
	for i: int in near.size() - max_near:
		_demote(near[i])


func _focus_dist(d: Vector3) -> float:
	if focus == null or not is_instance_valid(focus):
		return INF
	return surface.up_at(focus.global_position).angle_to(d) * surface.radius


func _promote(u: Dictionary) -> void:
	var rec: Dictionary = u["rec"]
	var b := SphereBot.new()
	b.name = "Bot_%s" % u["name"]
	add_child(b)
	b.setup(surface, rec["dir"], rec.get("heading", Vector3.ZERO))
	b.from_record(rec)
	if visuals:
		b.add_visual(str(u["type"]), str(Economy.robot_tiers[clampi(int(u["tier"]), 0, Economy.robot_tiers.size() - 1)].get("look", "salvage")) if not Economy.robot_tiers.is_empty() else "salvage")
	SphereRobotKinds.apply(b, str(u["type"]), int(u["tier"]))
	dress(b, str(u["type"]), int(u["tier"]))
	b.swarm = swarm
	if swarm:
		swarm.add(b)
	u["bot"] = b
	_near_n += 1
	SphereBales.dress_cargo(b, (u["carry"] as Array).size())
	u["stall_best"] = INF
	u["stall_t"] = 0.0


## Same looks as a workbench-built robot of this type (see dress_hooks).
static func dress(b: Node3D, type_id: String, tier: int) -> void:
	var want: String = Liveries.equipped()
	var cur: Node = b.get_node_or_null(Liveries.NODE_NAME)
	if cur and str(cur.get_meta("livery", "")) != want:
		b.remove_child(cur)
		cur.queue_free()
		cur = null
	if cur == null and want != "":
		var n: Node3D = Liveries.build(want)
		if n:
			b.add_child(n)
	var vis: Node3D = b.get("visual") as Node3D if "visual" in b else null
	for h: Callable in dress_hooks:
		if h.is_valid():
			h.call(b, vis, type_id, tier)


func _demote(u: Dictionary) -> void:
	var b: SphereBot = u["bot"]
	var keep_cell: int = int((u["rec"] as Dictionary).get("cell", 0))
	u["rec"] = SphereCrewSim.demote(b)
	u["far_at"] = _t
	(u["rec"] as Dictionary)["cell"] = keep_cell
	u["bot"] = null
	_near_n -= 1
	if streamer:
		streamer.remove_centre("bot:" + str(u["name"]))


func _update_centre(u: Dictionary) -> void:
	if streamer == null:
		return
	var key: String = "bot:" + str(u["name"])
	if u["mode"] == "work" or u["mode"] == "go":
		streamer.set_centre(key, (u["bot"] as SphereBot).global_position, SphereStreamer.BODY, RING_M)
	else:
		streamer.remove_centre(key)


# --- The brain (near and far alike) ----------------------------------------------------------

func _think(u: Dictionary, dt: float) -> void:
	var b: SphereBot = u["bot"]
	if b:
		b.working = u["mode"] == "work"
		# Piece work: the stand points are outside the walls, so only the last couple of metres skip
		# building avoidance (it would keep a robot off a piece lying against a wall).
		b.avoid_static = not b.working or b.distance_to_goal() > 2.5
	match str(u["mode"]):
		"go", "to_bale", "to_depot", "to_baler", "to_refill", SphereScrounge.MODE_HOME:
			if _has_goal(u):
				# A cell is 17 m across: close to its centre counts (another robot may be parked
				# right on it, and separation would keep this one circling).
				if b != null and not b.path.is_empty():
					var wd: float = b.dir.angle_to(b.goal) * surface.radius
					# Orbit breaker: a waypoint that gets no closer for 3 s (steering round a wall
					# or a parked robot) is passed; the next one leads on.
					if wd < float(u.get("wp_best", INF)) - 0.3:
						u["wp_best"] = wd
						u["wp_t"] = 0.0
					else:
						u["wp_t"] = float(u.get("wp_t", 0.0)) + dt
					if wd < _pass_for(u, b.goal) or float(u["wp_t"]) > 3.0:
						b.goal = b.path.pop_front()  # waypoints are cell centres: pass near, a bot may sit on one
						u["wp_best"] = INF
						u["wp_t"] = 0.0
				if b != null and b.path.is_empty() and b.distance_to_goal() < ARRIVE_M:
					_stop(u)
				else:
					_check_stall(u, dt)
					return
			_arrive(u)
		"work":
			_work(u, dt)
		"refill":
			u["work_t"] = float(u["work_t"]) + dt
			var tank: float = _tank(u)
			if float(u["work_t"]) * maxf(Economy.robot_stat(str(u["type"]), "refill_rate", int(u["tier"])), 1.0) >= tank:
				u["water"] = tank
				u["log"]["refills"] = float(u["log"].get("refills", 0.0)) + 1.0
				u["mode"] = "idle"
				u["rescan"] = 0.0
		_:
			u["rescan"] = float(u["rescan"]) - dt
			if float(u["rescan"]) > 0.0 or _find_us > FIND_BUDGET_US:
				u["log"]["idle_s"] = float(u["log"]["idle_s"]) + dt
				return
			var t0: int = Time.get_ticks_usec()
			var found: bool = _find_job(u)
			_find_us += Time.get_ticks_usec() - t0
			if not found:
				u["log"]["idle_s"] = float(u["log"]["idle_s"]) + dt
				u["rescan"] = (0.6 + randf() * 0.4) * float(u.get("backoff", 1.0))
				if float(u.get("idle_from", -1.0)) < 0.0:
					u["idle_from"] = _t
			else:
				u["idle_from"] = -1.0


func _find_job(u: Dictionary) -> bool:
	var role: String = u["role"]
	var here: int = unit_cell(u)
	if role == "haul":
		return _find_haul(u, here)
	if role == SphereScrounge.ROLE:
		return SphereScrounge.find_job(self, u, here)
	if role == "clean" and float(u["hopper"]) >= _capacity(u):
		_drop_bale(u)
	if role == "water" and float(u.get("water", _tank(u))) < WATER_PER_CELL:
		return _go_refill(u, here)
	if role == "plant" and spend_seeds and not GameState.can_afford("seeds", BigNum.from_float(1.0)):
		u["idle"] = "out of seeds"
		return false
	var c: int = claim_dirty(here, int(u["hub"]), rings, role, str(u["name"]))
	if c < 0:
		if role == "clean" and float(u["hopper"]) > 0.0:
			_drop_bale(u)  # nothing left: bale what it has so the haulers can take it
		u["idle"] = {"clean": "zone clean", "plant": "nothing to plant", "water": "nothing to water", "skim": "no lake junk"}.get(role, "idle")
		return false
	u["job"] = c
	u["idle"] = ""
	return _route_to(u, c, "go")


func _route_to(u: Dictionary, c: int, mode: String) -> bool:
	var here: int = unit_cell(u)
	var p: PackedInt32Array = route(here, c, str(u["role"]))
	if p.is_empty():
		_skip[c] = _t + SKIP_S
		if mode == "go":
			release(c)
			u["job"] = -1
		u["mode"] = "idle"
		u["idle"] = "no path"
		u["backoff"] = minf(float(u.get("backoff", 1.0)) * 2.0, NO_PATH_BACKOFF_MAX)
		return false
	_go(u, p)
	u["mode"] = mode
	u["backoff"] = 1.0
	return true


func _arrive(u: Dictionary) -> void:
	match str(u["mode"]):
		"go":
			u["mode"] = "work"
			u["work_t"] = 0.0
		"to_bale":
			var bi: int = _bale_index(int(u["bale"]))
			if bi >= 0:
				(u["carry"] as Array).append(float(bales[bi]["value"]))
				if bale_view:
					bale_view.take(int(bales[bi]["id"]))
				bales.remove_at(bi)
			u["bale"] = -1
			SphereBales.dress_cargo(u["bot"], (u["carry"] as Array).size())
			u["mode"] = "idle"
			u["rescan"] = 0.0
		"to_depot":
			var v: float = 0.0
			for x: float in u["carry"]:
				v += x
			u["log"]["hauled"] = float(u["log"]["hauled"]) + (u["carry"] as Array).size()
			if str(u.get("drop", "")) == "conveyor" and add_cube_fn.is_valid() and u["bot"] != null:
				# Real bales onto the conveyor's hopper; the belt carries them to the Depot.
				var at: Vector3 = (u["bot"] as SphereBot).global_position
				for x: float in u["carry"]:
					var cube := JunkCube.create(BigNum.from_float(x), SphereBales.bale_info(10.0))
					add_cube_fn.call(cube)
					cube.global_position = at + surface.up_at(at) * 0.9
			else:
				cash(v)
			(u["carry"] as Array).clear()
			u["drop"] = ""
			SphereBales.dress_cargo(u["bot"], 0)
			u["mode"] = "idle"
			u["rescan"] = 0.0
		"to_baler":
			var bl: Node = _baler()
			if bl != null and float(u["hopper"]) > 0.0 and bl.call("can_accept", float(u["hopper"])):
				var from: Vector3 = (u["bot"] as SphereBot).global_position if u["bot"] != null else surface.ground(unit_dir(u))
				bl.call("accept", _hopper_contents(float(u["hopper"])), from + surface.up_at(from) * 0.8)
				u["log"]["dumps"] = float(u["log"].get("dumps", 0.0)) + 1.0
				GameState.inc_stat("robot_dumps")
				u["hopper"] = 0.0
			elif float(u["hopper"]) > 0.0:
				_drop_bale(u)  # the baler filled up meanwhile
			u["mode"] = "idle"
			u["rescan"] = 0.0
		"to_refill":
			u["mode"] = "refill"
			u["work_t"] = 0.0
		SphereScrounge.MODE_HOME:
			parts_delivered.emit(SphereScrounge.unload(u), int(u["hub"]))
			u["mode"] = "idle"
			u["rescan"] = 0.0


func _work(u: Dictionary, dt: float) -> void:
	var c: int = int(u["job"])
	var role: String = u["role"]
	if c < 0:
		u["mode"] = "idle"
		return
	if role == SphereScrounge.ROLE:
		if SphereScrounge.dig(self, u, dt):
			_finish_job(u)
		return
	if role == "plant" or role == "water":
		var rate: float = maxf(Economy.robot_stat(str(u["type"]), "work_rate", int(u["tier"])), 0.1)
		u["work_t"] = float(u["work_t"]) + dt * rate
		if float(u["work_t"]) < 3.0:
			return
		if _held_work(role, c):
			if pollution.robot_work(role, c, spend_seeds):
				cell_cleaned.emit(c)
			if role == "water":
				u["water"] = maxf(0.0, float(u.get("water", _tank(u))) - WATER_PER_CELL)
		elif role == "plant" and cells.state[c] == 1:
			if not spend_seeds or GameState.spend("seeds", BigNum.from_float(1.0)):
				cells.set_state(c, 2)
				u["log"]["planted"] = float(u["log"]["planted"]) + 1.0
		elif role == "water" and cells.state[c] == 2:
			cells.set_state(c, 3)
			u["water"] = maxf(0.0, float(u.get("water", _tank(u))) - WATER_PER_CELL)
			u["log"]["watered"] = float(u["log"]["watered"]) + 1.0
		cell_worked.emit(c)
		_finish_job(u)
		return
	if u["bot"] != null and field != null and field.materialized[c] == 1 and field.hex_clean[c] == 0:
		_work_pieces(u, c, dt)
		return
	var upc: float = units_per(c)
	var held: float = cells.floor_of(c)  # waste another tool clears: not this robot's to take
	var have: float = maxf(0.0, junk_left(c) - held) * upc
	var take: float = minf(have, Offline.unit_rate(str(u["type"]), int(u["tier"])) * dt)
	work_cell(c, held + (have - take) / upc)
	u["hopper"] = float(u["hopper"]) + take
	u["log"]["junk"] = float(u["log"]["junk"]) + take
	if float(u["hopper"]) >= _capacity(u) and _hopper_full(u):
		return
	if not (cells.workable(c) or water_dirty(c)):
		u["log"]["cells"] = float(u["log"]["cells"]) + 1.0
		_finish_job(u)


## A near robot on a hex with real pieces: it drives to the nearest piece, scoops it (the arm
## animates while `working`) and takes it whole, at the same Offline.unit_rate as everywhere else
## (work time accrues while it drives, as in the flat game's rate: travel + pick).
const REACH_M: float = 1.1
const PIECE_GIVEUP_S: float = 6.0


func _work_pieces(u: Dictionary, c: int, dt: float) -> void:
	_left.erase(c)  # the pieces are the account here
	var b: SphereBot = u["bot"]
	var pid: int = int(u.get("pid", -1))
	if pid < 0 or field.piece_alive[pid] == 0 or field.piece_hex[pid] != c:
		pid = _nearest_piece(c, b.global_position)
		u["pid"] = pid
		u["piece_t"] = 0.0
		if pid < 0:
			work_cell(c, 0.0)  # nothing left to see: settle the hex clean
			u["log"]["cells"] = float(u["log"]["cells"]) + 1.0
			_finish_job(u)
			return
		b.stop_m = REACH_M * 0.6
		u["reach_at"] = _approach(field.piece_pos[pid], b.global_position)
		b.go_to_point(u["reach_at"])
	var per_unit: float = units_per(c) / maxf(field.hex_total[c], 0.001)
	var units: float = field.piece_vol[pid] * per_unit
	u["acc"] = minf(float(u.get("acc", 0.0)) + Offline.unit_rate(str(u["type"]), int(u["tier"])) * dt, units * 2.0)
	u["piece_t"] = float(u.get("piece_t", 0.0)) + dt
	var at: Vector3 = u.get("reach_at", field.piece_pos[pid])
	var near: bool = b.global_position.distance_to(at) <= REACH_M + 0.4
	if not near and float(u["piece_t"]) < PIECE_GIVEUP_S:
		if not b.has_goal():
			b.go_to_point(at)
		return
	if float(u["acc"]) < units:
		return
	u["acc"] = float(u["acc"]) - units
	_touched[c] = true
	var was_dirty: bool = cells.is_dirty(c) or water_dirty(c)
	if field.remove_piece(pid) and (field.hex_hub[c] == 1 or field.hex_water[c] == 1):
		field.cleaned_count -= 1  # HexField counts every hex; the globe's load rule skips hub ground and lakes
	if junk_view != null:
		junk_view.call("hide_piece", pid)
		if junk_view.has_method("refresh_hex"):
			junk_view.call("refresh_hex", c)
	var left: float = 1.0 - field.removed_fraction(c) if field.hex_clean[c] == 0 else 0.0
	var before: float = cells.junk[c]
	SphereOffline.write_cell(cells, field, c, left)
	if pollution != null:
		pollution.robot_scooped(c, before - cells.junk[c])
	cell_worked.emit(c)
	u["pid"] = -1
	u["hopper"] = float(u["hopper"]) + units
	u["log"]["junk"] = float(u["log"]["junk"]) + units
	if float(u["hopper"]) >= _capacity(u) and _hopper_full(u):
		return
	if not (cells.is_dirty(c) or water_dirty(c)):
		if was_dirty:
			cell_cleaned.emit(c)
		u["log"]["cells"] = float(u["log"]["cells"]) + 1.0
		b.stop_m = 0.5
		_finish_job(u)


## Where to stand to scoop a piece at `p` (robot at `from`): the piece itself, or the first spot
## clear of the buildings on the way back toward the robot (the arm reaches in; the robot never
## drives into a wall).
func _approach(p: Vector3, from: Vector3) -> Vector3:
	if swarm == null:
		return p
	var d: Vector3 = surface.up_at(p)
	var back: Vector3 = surface.up_at(from)
	var total: float = d.angle_to(back) * surface.radius
	var k: float = 0.0
	while _inside_building(d) and k < total:
		k += 0.5
		d = SphereMath.slerp_safe(surface.up_at(p), back, clampf(k / maxf(total, 0.01), 0.0, 1.0))
	return surface.ground(d)


## _pass_m for a robot's current waypoint, looked up once per waypoint (it scans the buildings).
func _pass_for(u: Dictionary, wp: Vector3) -> float:
	if u.get("pass_wp") != wp:
		u["pass_wp"] = wp
		u["pass_m"] = _pass_m(wp)
	return float(u["pass_m"])


## How close a waypoint must be before the next one: generous in the open (a robot may sit on a
## cell centre), tight next to a building (so corners are not cut through the wall).
func _pass_m(wp: Vector3) -> float:
	if swarm != null and not swarm.obstacles_near(wp, 2.5).is_empty():
		return PASS_TIGHT_M
	return PASS_M


## `d`, or the nearest spot clear of buildings (a robot never starts inside a wall).
func _free_spot(d: Vector3) -> Vector3:
	if swarm == null or not _inside_building(d):
		return d
	for ring_m: float in [3.0, 5.0, 8.0, 12.0, 17.0]:
		for k: int in 12:
			var side: Vector3 = SphereMath.any_perpendicular(d).rotated(d, float(k) / 12.0 * TAU)
			var q: Vector3 = SphereMath.advance(d, side, ring_m / surface.radius)[0]
			if not _inside_building(q):
				return q
	return d


func _inside_building(d: Vector3) -> bool:
	for ob: Array in swarm.obstacles_near(d, 0.4):
		if d.angle_to(ob[0]) * surface.radius < float(ob[1]) + 0.35:
			return true
	return false


func _nearest_piece(c: int, from: Vector3) -> int:
	var best: int = -1
	var bd: float = INF
	for pid: int in field.pieces_in(c):
		if field.piece_alive[pid] == 0:
			continue
		var d: float = from.distance_squared_to(field.piece_pos[pid])
		if d < bd:
			bd = d
			best = pid
	return best


func _finish_job(u: Dictionary) -> void:
	release(int(u["job"]))
	u["job"] = -1
	u["mode"] = "idle"
	u["rescan"] = 0.0


func _drop_job(u: Dictionary) -> void:
	if int(u["job"]) >= 0:
		release(int(u["job"]))
	u["job"] = -1
	var bi: int = _bale_index(int(u["bale"]))
	if bi >= 0:
		bales[bi]["claimed"] = ""
	u["bale"] = -1
	_stop(u)
	u["mode"] = "idle"


## Near robots only (records move exactly): no progress toward the goal for STALL_S seconds =
## stuck. Drop the job, skip that cell for a while and try another.
func _check_stall(u: Dictionary, dt: float) -> void:
	if u["bot"] == null:
		return
	var d: float = (u["bot"] as SphereBot).distance_to_goal()
	if d < float(u["stall_best"]) - 0.5:
		u["stall_best"] = d
		u["stall_t"] = 0.0
		return
	u["stall_t"] = float(u["stall_t"]) + dt
	if float(u["stall_t"]) < STALL_S:
		return
	u["log"]["stall_s"] = float(u["log"]["stall_s"]) + float(u["stall_t"])
	u["log"]["unstuck"] = float(u["log"]["unstuck"]) + 1.0
	if int(u["job"]) >= 0:
		_skip[int(u["job"])] = _t + SKIP_S
	_drop_job(u)
	u["stall_t"] = 0.0


# --- Bales and hauling ---------------------------------------------------------------------

func _capacity(u: Dictionary) -> float:
	var c: float = Economy.robot_stat(str(u["type"]), "capacity", int(u["tier"]))
	return c if c > 0.0 else 12.0


func _drop_bale(u: Dictionary) -> void:
	var units_in: float = float(u["hopper"])
	if units_in <= 0.0:
		return
	u["hopper"] = 0.0
	_bale_seq += 1
	var value: float = 0.0  # robots earn no cubes: the bale is waste on its way out, not money
	# Dropped beside the robot (a little to its side, so a crew's bales don't stack in one spot).
	var d: Vector3 = unit_dir(u)
	var side: Vector3 = SphereMath.any_perpendicular(d).rotated(d, randf() * TAU)
	var at: Vector3 = SphereMath.advance(d, side, 0.9 / surface.radius)[0]
	if swarm != null and _inside_building(at):
		at = surface.up_at(_approach(surface.ground(at), surface.ground(d)))
	if cells.state[grid.cell_at(at)] == 5:  # a Skimmer's bale goes on the nearest shore
		at = _shore_of(grid.cell_at(at))
	bales.append({"id": _bale_seq, "cell": grid.cell_at(at), "dir": at, "value": value, "units": units_in, "claimed": "",
		"info": SphereBales.bale_info(units_in)})
	u["log"]["bales"] = float(u["log"]["bales"]) + 1.0


## Nearest land cell centre to a lake cell (BFS, a few rings), or the cell itself.
func _shore_of(c: int) -> Vector3:
	for k: int in grid.cells_around(c, 4):
		if cells.state[k] != 5 and not blocked.has(k):
			return grid.centers[k]
	return grid.centers[c]


func _bale_index(id: int) -> int:
	for i: int in bales.size():
		if int(bales[i]["id"]) == id:
			return i
	return -1


func _find_haul(u: Dictionary, here: int) -> bool:
	var carry: Array = u["carry"]
	var cap: int = maxi(1, int(Economy.robot_stat(str(u["type"]), "carry", int(u["tier"]))))
	var best: int = -1
	var best_d: float = INF
	if carry.size() < cap:
		for i: int in bales.size():
			if str(bales[i]["claimed"]) != "":
				continue
			# A bale no route led to a moment ago (_route_to marks its cell) is passed over for
			# now: taking the nearest one again and again left every other bale waiting.
			if float(_skip.get(int(bales[i]["cell"]), -1.0)) >= _t:
				continue
			var d: float = grid.distance_m(here, int(bales[i]["cell"]))
			if d < best_d:
				best_d = d
				best = i
	if best >= 0:
		bales[best]["claimed"] = u["name"]
		u["bale"] = int(bales[best]["id"])
		if _route_to(u, int(bales[best]["cell"]), "to_bale"):
			_append_goal(u, bales[best].get("dir", Vector3.ZERO))  # right up to the bale
			return true
		bales[best]["claimed"] = ""
		u["bale"] = -1
		return false
	if not carry.is_empty():
		var drop: Vector3 = _haul_target(u)
		if _route_to(u, grid.cell_at(drop), "to_depot"):
			_append_goal(u, drop)
			return true
		return false
	u["idle"] = "no bales"
	return false


## Where a hub's haulers cash bales: the start hub's depot, or a hub's own cell (each hub site
## gets its depot anchor in phase D: set depots[hub]).
func depot_of(hub: int) -> int:
	if depots.has(hub):
		return int(depots[hub])
	if hub == hub_cell and depot_cell >= 0:
		return depot_cell
	return hub


## A hauler delivered bales worth `value`: only Lumi's own bales are worth anything.
func cash(value: float) -> void:
	if value <= 0.0:
		return
	var paid: float = Economy.pay_whole_cubes(value)
	cashed += paid
	bale_cashed.emit(paid)


# --- Status, report, save ------------------------------------------------------------------

func status_text(u: Dictionary) -> String:
	match str(u["mode"]):
		"go":
			return "heading to hex %d" % int(u["job"])
		SphereScrounge.MODE_HOME:
			return "carrying %d parts home" % int(SphereScrounge.carried(u))
		"work":
			return {"plant": "planting", "water": "watering", "skim": "skimming", "find": "digging"}.get(str(u["role"]), "cleaning") + " hex %d" % int(u["job"])
		"to_bale":
			return "fetching a bale"
		"to_depot":
			return "hauling %d bales" % (u["carry"] as Array).size()
		"to_baler":
			return "tipping into the baler"
		"to_refill", "refill":
			return "refilling"
	return "idle: %s" % (str(u["idle"]) if str(u["idle"]) != "" else "waiting")


## A robot is stuck if it is stalled right now, or got stuck more than twice.
func is_stuck(u: Dictionary) -> bool:
	return float(u["stall_t"]) >= STALL_S * 0.5 or float(u["log"]["unstuck"]) > 2.0


func stuck_count() -> int:
	var n: int = 0
	for u: Dictionary in units:
		if is_stuck(u):
			n += 1
	return n


func cells_cleaned() -> int:
	var n: int = 0
	for u: Dictionary in units:
		n += int(u["log"]["cells"])
	return n


func _maybe_report() -> void:
	if _report_done or not (DevHooks.has("bot-report") or DevHooks.has("robots") or DevHooks.has("orbit-far-crew")) or not DevHooks.has("quit-after"):
		return
	if DevHooks._elapsed >= DevHooks.get_f("quit-after", 5.0) - 1.0:
		_report_done = true
		reporting.emit()
		print_report()


func print_report() -> void:
	print("[bots] ---- robot report (%d robots, %d near, %d far, %d hexes cleaned, %d bales waiting, %.0f cubes cashed) ----" % [
		units.size(), near_count(), units.size() - near_count(), cells_cleaned(), bales.size(), cashed])
	for u: Dictionary in units:
		var parts: PackedStringArray = []
		for k: String in LOG_KEYS:
			if k != "stall_s" and k != "idle_s" and float(u["log"][k]) > 0.0:
				parts.append("%s=%s" % [k, str(snappedf(float(u["log"][k]), 0.1))])
		print("[bots] %-12s %-9s %-4s %5.0fm | %s | %s | stalled %.0fs | idle %.0fs" % [u["name"], u["type"], "near" if is_near(u) else "far",
			_focus_dist(unit_dir(u)) if focus else -1.0, ", ".join(parts), status_text(u), float(u["log"]["stall_s"]), float(u["log"]["idle_s"])])
	if field != null and terrain_for_recount != null:  # live ledger vs what a reload would count
		var re := SphereField.new(grid, terrain_for_recount, cells, 7)
		print("[bots] field cleaned live %d, recount from cells %d %s" % [field.cleaned_count, re.cleaned_count, "PASS" if re.cleaned_count == field.cleaned_count else "FAIL"])
		if re.cleaned_count != field.cleaned_count:
			var odd: PackedStringArray = []
			for i: int in field.hex_clean.size():
				if re.hex_clean[i] != field.hex_clean[i] and re.hex_hub[i] == 0 and re.hex_water[i] == 0:
					odd.append("%d(live=%d reload=%d junk=%.3f st=%d mat=%d worked=%s)" % [i, field.hex_clean[i], re.hex_clean[i], cells.junk[i], cells.state[i], field.materialized[i], str(_touched.has(i))])
			print("[bots] mismatched hexes: %s" % ", ".join(odd.slice(0, 8)))
	var c: Dictionary = cost.summary()
	print("[bots] crew cost per frame, %d robots (%d near): %.2f ms on average (thinking %.2f, near robots %.2f), %.2f ms in the best second, worst frame %.1f ms (frame %d of %d)" % [
		units.size(), near_count(), float(c["total_ms"]), float(c["tick_ms"]), float(c["bodies_ms"]), float(c["best_second_ms"]),
		float(c["worst_ms"]), int(c["worst_frame"]), int(c["frames"])])
	var stuck: int = stuck_count()
	print("[bots] stuck=%d %s" % [stuck, "PASS" if stuck == 0 else "FAIL"])


## Saved as directions on the planet (never flat x/z) plus the job state.
func to_dict() -> Dictionary:
	var list: Array = []
	for u: Dictionary in units:
		var rec: Dictionary = (u["bot"] as SphereBot).to_record() if u["bot"] != null else u["rec"]
		var d: Vector3 = rec["dir"]
		var h: Vector3 = rec.get("heading", Vector3.ZERO)
		list.append({"name": u["name"], "type": u["type"], "tier": u["tier"], "hub": u["hub"], "dir": [d.x, d.y, d.z],
			"heading": [h.x, h.y, h.z], "hopper": u["hopper"], "carry": (u["carry"] as Array).duplicate(), "parts": SphereScrounge.carried(u),
				"log": (u["log"] as Dictionary).duplicate()})
	var bl: Array = []
	for b: Dictionary in bales:
		var bd: Vector3 = b.get("dir", grid.centers[int(b["cell"])])
		var bd_rec: Dictionary = {"cell": b["cell"], "dir": [bd.x, bd.y, bd.z], "value": b["value"], "units": b.get("units", 0.0)}
		if b.has("raw"):  # [v4bots] one of Lumi's bales (SphereBales.adopt): his cube's own value
			bd_rec["raw"] = b["raw"]
		bl.append(bd_rec)
	var zd: Dictionary = {}  # [v3qa] painted Command zones survive a reload
	for r: Variant in zones:
		zd[str(r)] = (zones[r] as Dictionary).keys()
	return {"v": 1, "robots": list, "bales": bl, "cashed": cashed, "zones": zd}


func from_dict(d: Dictionary) -> void:
	for u: Dictionary in units:
		if u["bot"] != null:
			_demote(u)
	units.clear()
	bales.clear()
	_claimed.clear()
	for r: Dictionary in d.get("robots", []):
		var dv: Array = r.get("dir", [0, 1, 0])
		var dir := Vector3(float(dv[0]), float(dv[1]), float(dv[2])).normalized()
		var u: Dictionary = spawn(str(r["type"]), int(r.get("tier", 0)), grid.cell_at(dir), int(r.get("hub", hub_cell)), str(r.get("name", "")))
		var hv: Array = r.get("heading", [0, 0, 0])
		var rec: Dictionary = u["rec"]
		rec["dir"] = dir
		rec["heading"] = SphereMath.tangent_dir(Vector3(float(hv[0]), float(hv[1]), float(hv[2])), dir)
		if u["bot"] != null:
			(u["bot"] as SphereBot).from_record(rec)
		u["hopper"] = float(r.get("hopper", 0.0))
		u["parts"] = float(r.get("parts", 0.0))
		u["carry"] = (r.get("carry", []) as Array).duplicate()
		var lg: Dictionary = r.get("log", {})
		for k: String in LOG_KEYS:
			u["log"][k] = float(lg.get(k, 0.0))
	for b: Dictionary in d.get("bales", []):
		_bale_seq += 1
		var dv: Array = b.get("dir", [])
		var bd: Vector3 = Vector3(float(dv[0]), float(dv[1]), float(dv[2])).normalized() if dv.size() == 3 else grid.centers[int(b["cell"])]
		# Only Lumi's own bales (they carry "raw") are worth cubes; a robot's bale from an older save
		# loads as waste.
		bales.append({"id": _bale_seq, "cell": int(b["cell"]), "dir": bd, "value": float(b["value"]) if b.has("raw") else 0.0,
			"units": float(b.get("units", 0.0)), "claimed": ""})
		if b.has("raw"):
			bales[-1]["raw"] = float(b["raw"])
	cashed = float(d.get("cashed", 0.0))
	zones.clear()  # [v3qa]
	var zd: Dictionary = d.get("zones", {})
	for r: Variant in zd:
		var z: Dictionary = {}
		for c: Variant in zd[r]:
			z[int(c)] = true
		zones[str(r)] = z
