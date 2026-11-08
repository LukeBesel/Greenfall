class_name SphereBot
extends Node3D
## [smove] A robot on a planet, kinematic (no physics body): it lives as a unit direction `dir`
## and a tangent `heading`, sits on SphereSurface.ground(dir) and is tilted onto the terrain
## normal. It travels great circles toward a goal (a point, or a path of cell centres from a
## cell graph), with local avoidance of other bots and of static obstacles, and turns smoothly.
## Far from the player a bot can be turned into a record (to_record) and advanced cheaply by
## SphereCrewSim, then rebuilt (from_record) when it streams back in.
##
## Cell-graph hooks (all optional; the orbit prototype's OrbitWorld already has these shapes):
##   graph.claim_dirty(cell: int, hub: int, rings: int) -> int     next work cell or -1
##   graph.path(from_cell: int, to_cell: int) -> PackedInt32Array  cell path (incl. both ends)
##   graph.work_cell(cell: int, left: float)                      write back remaining junk
##   graph.junk_left(cell: int) -> float                           0..1 remaining
##   graph.release(cell: int)
## plus SphereSurface.cell_at / cell_dir for point <-> cell.

signal arrived
signal cell_done(cell: int)

var surface: SphereSurface
var swarm: SphereSwarm
var graph: Object
var dir := Vector3.UP
var heading := Vector3.FORWARD
var speed: float = 3.2
var turn_rate: float = 3.5
var body_radius: float = 0.7
var hover: float = 0.0
var tilt: float = 0.7  # 0 = stand radial, 1 = fully on the terrain normal
var hub_cell: int = -1
var cell: int = -1
var work_rate: float = 0.06
var visual: Node3D
var moving_speed: float = 0.0
var working: bool = false
var cleaned: int = 0
## Current goal (unit direction) and remaining waypoints (unit directions; goal = last).
var goal := Vector3.ZERO
var path: Array[Vector3] = []
var stop_m: float = 0.4
var _target_cell: int = -1
var _normal := Vector3.UP
var _stuck_t: float = 0.0
var _last_d: float = 0.0
var _desired_s := Vector3.ZERO  # [orbC] smoothed steering target
## [orbC] Steer round static obstacles (buildings); off for short moves next to a wall.
var avoid_static: bool = true


func setup(p_surface: SphereSurface, p_dir: Vector3, p_heading: Vector3 = Vector3.ZERO) -> void:
	surface = p_surface
	dir = p_dir.normalized()
	heading = SphereMath.tangent_dir(p_heading if p_heading != Vector3.ZERO else SphereMath.any_perpendicular(dir), dir)
	_normal = surface.ground_normal(dir)
	_apply_transform(0.0)


## Builds a RobotVisual of `type_id` as the body (optional; tests run without visuals).
func add_visual(type_id: String, look: String = "salvage") -> void:
	var rv := RobotVisual.new()
	add_child(rv)
	rv.build(type_id, look)
	visual = rv
	hover = 0.06 if rv.hover else 0.0


## Go to a world point (great circle, avoidance on the way).
func go_to_point(p: Vector3) -> void:
	path.clear()
	goal = surface.up_at(p)


## Go to a far point through waypoints (unit directions), e.g. SpherePath.to_dirs().
func go_via(dirs: Array[Vector3]) -> void:
	path = dirs.duplicate()
	if not path.is_empty():
		goal = path.pop_front()


func distance_to_goal() -> float:
	if goal == Vector3.ZERO:
		return 0.0
	var d: float = dir.angle_to(goal) * surface.radius
	var prev: Vector3 = goal
	for w: Vector3 in path:
		d += prev.angle_to(w) * surface.radius
		prev = w
	return d


func has_goal() -> bool:
	return goal != Vector3.ZERO


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if surface == null:
		return
	if graph and not has_goal() and not working:
		_think_graph()
	var desired: Vector3 = heading
	var spd: float = 0.0
	if has_goal():
		var d_m: float = dir.angle_to(goal) * surface.radius
		var last: bool = path.is_empty()
		if (last and d_m <= stop_m) or (not last and d_m <= maxf(1.5, speed * 0.5)):
			if last:
				dir = goal if d_m < 0.05 else dir
				goal = Vector3.ZERO
				arrived.emit()
				_on_arrived()
			else:
				goal = path.pop_front()
		if has_goal():
			# Look one waypoint ahead so corners round off instead of zig-zagging cell to cell.
			var aim: Vector3 = goal
			if not path.is_empty() and d_m < 6.0:
				aim = SphereMath.slerp_safe(goal, path[0], clampf(1.0 - d_m / 6.0, 0.0, 1.0) * 0.5)
			desired = SphereSteer.seek(dir, aim, heading)
			spd = speed * (SphereSteer.arrive(d_m, stop_m, 2.0) if path.is_empty() else 1.0)
	if swarm:
		var near: Array = swarm.neighbors(self, 8.0)
		var sep: Vector3 = SphereSteer.separation(dir, near, body_radius * 2.6, surface.radius)
		# Other bots ahead are steered around like obstacles (both keep right on a head-on).
		var obs: Array = swarm.obstacles_near(dir, 12.0) if avoid_static else []
		# [orbC] Bots driving the same way (a convoy) only keep their spacing; dodging them made
		# both weave side to side. Oncoming and parked bots are still steered round.
		for nb: SphereBot in swarm.neighbor_bots(self, 8.0):
			if nb.moving_speed > 0.3 and nb.heading.dot(heading) > 0.6:
				continue
			obs.append([nb.dir, body_radius])
		var av: Vector3 = SphereSteer.avoid(dir, heading, obs, 4.0, body_radius, surface.radius)
		if spd > 0.0:
			desired = (desired + sep * 1.6 + av).normalized() if (desired + sep * 1.6 + av).length() > 0.01 else desired
		elif sep.length() > 0.05:  # parked bots shuffle apart
			desired = sep.normalized()
			spd = speed * 0.3 * minf(1.0, sep.length())
	# [orbC] Low-pass the steering target so separation / avoidance pushes can't flip it frame to frame.
	if _desired_s == Vector3.ZERO or delta <= 0.0:
		_desired_s = desired
	else:
		_desired_s = SphereMath.tangent_dir(SphereMath.slerp_safe(SphereMath.tangent_dir(_desired_s, dir, heading), desired, SphereMath.damp(10.0, delta)), dir, heading)
	desired = _desired_s
	heading = SphereSteer.turn(dir, heading, desired, turn_rate, delta)
	# Slow down while turning hard so bots carve instead of sliding sideways.
	var align: float = clampf(heading.dot(SphereMath.tangent_dir(desired, dir, heading)), 0.0, 1.0)
	spd *= lerpf(0.35, 1.0, align)
	moving_speed = lerpf(moving_speed, spd, SphereMath.damp(6.0, delta))
	if moving_speed > 0.001:
		var adv: Array = SphereMath.advance(dir, heading, moving_speed * delta / surface.radius)
		dir = adv[0]
		heading = SphereMath.tangent_dir(adv[1], dir, heading)
	if working and _target_cell >= 0 and graph:
		var left: float = float(graph.call("junk_left", _target_cell)) - work_rate * delta
		graph.call("work_cell", _target_cell, maxf(left, 0.0))
		if left <= 0.0:
			graph.call("release", _target_cell)
			cell_done.emit(_target_cell)
			cleaned += 1
			_target_cell = -1
			working = false
	_apply_transform(delta)
	if visual and visual.has_method("animate"):
		visual.call("animate", moving_speed, working, delta)


func _think_graph() -> void:
	var here: int = surface.cell_at(global_position, cell)
	if here >= 0:
		cell = here
	_target_cell = int(graph.call("claim_dirty", cell, hub_cell, 9))
	if _target_cell < 0:
		return
	var cells: PackedInt32Array = graph.call("path", cell, _target_cell)
	var dirs: Array[Vector3] = []
	for i: int in range(1, cells.size()):
		dirs.append(surface.cell_dir(cells[i]))
	if dirs.is_empty():
		dirs.append(surface.cell_dir(_target_cell))
	go_via(dirs)


func _on_arrived() -> void:
	if graph and _target_cell >= 0:
		working = true


func _apply_transform(delta: float) -> void:
	var n: Vector3 = surface.ground_normal(dir)
	_normal = n if delta <= 0.0 else SphereMath.slerp_safe(_normal, n, SphereMath.damp(8.0, delta))
	var up_v: Vector3 = SphereMath.slerp_safe(dir, _normal, tilt)
	global_transform = Transform3D(SphereMath.basis_from_up_fwd(up_v, heading), surface.ground(dir) + dir * hover)


## Compact state for far-away simulation (SphereCrewSim) or saving.
func to_record() -> Dictionary:
	var wps: Array = []
	for w: Vector3 in path:
		wps.append(w)
	return {"dir": dir, "heading": heading, "goal": goal, "path": wps, "speed": speed,
		"cell": cell, "hub": hub_cell, "target": _target_cell, "working": working, "cleaned": cleaned}


func from_record(r: Dictionary) -> void:
	dir = r.get("dir", dir)
	heading = SphereMath.tangent_dir(r.get("heading", heading), dir)
	goal = r.get("goal", Vector3.ZERO)
	path.clear()
	for w: Vector3 in r.get("path", []):
		path.append(w)
	speed = r.get("speed", speed)
	cell = r.get("cell", cell)
	hub_cell = r.get("hub", hub_cell)
	_target_cell = r.get("target", -1)
	working = r.get("working", false)
	cleaned = r.get("cleaned", cleaned)
	_apply_transform(0.0)
