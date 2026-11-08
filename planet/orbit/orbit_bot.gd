class_name OrbitBot
extends Node3D
## [orbit] Prototype crew robot on the globe. Navigation is the hex graph itself: BFS to the
## nearest unclaimed dirty cell around its hub, then cell-centre to cell-centre along great
## circles; on arrival it works the cell down (one state texel per update). Kinematic (no
## physics body), like a far-LOD robot would be. Far crews are not nodes at all (OrbitWorld).

const SPEED: float = 3.2
const WORK_RATE: float = 0.06  # cell fraction per second

var world: OrbitWorld
var globe: OrbitGlobe
var hub_cell: int = 0
var cell: int = 0
var visual: RobotVisual
var _path := PackedInt32Array()
var _target: int = -1
var _dir := Vector3.UP
var _fwd := Vector3.FORWARD
var _working: bool = false
var cleaned: int = 0
var _retry: float = 0.0


func setup(p_world: OrbitWorld, p_cell: int, hub: int, type_id: String) -> void:
	world = p_world
	globe = world.globe
	cell = p_cell
	hub_cell = hub
	_dir = globe.grid.centers[cell]
	visual = RobotVisual.new()
	add_child(visual)
	visual.build(type_id, "salvage")


func _process(delta: float) -> void:
	if globe == null:
		return
	var moving: float = 0.0
	_retry -= delta
	if _target < 0 and _retry <= 0.0:
		_target = world.claim_dirty(cell, hub_cell, 9)
		if _target < 0:
			_retry = 3.0  # nothing left nearby: look again later, not every frame
		_path = world.path(cell, _target) if _target >= 0 else PackedInt32Array()
	if not _path.is_empty():
		var goal: Vector3 = globe.grid.centers[_path[0]]
		var ang: float = _dir.angle_to(goal)
		var step: float = SPEED * delta / globe.R
		if ang <= step:
			_dir = goal
			cell = _path[0]
			_path.remove_at(0)
		else:
			var nd: Vector3 = _dir.slerp(goal, step / ang).normalized()
			_fwd = (nd - _dir).normalized()
			_dir = nd
			moving = SPEED
	elif _target >= 0:
		_working = true
		var left: float = globe.planet.junk[_target] - WORK_RATE * delta
		world.work_cell(_target, left)
		if left <= 0.0:
			world.release(_target)
			cleaned += 1
			_target = -1
			_working = false
	var p: Vector3 = globe.ground(_dir)
	var u: Vector3 = _dir
	var f: Vector3 = (_fwd - u * _fwd.dot(u))
	if f.length() < 0.01:
		f = OrbitGlobe.frame(u).z
	global_transform = Transform3D(Basis.looking_at(f.normalized(), u), p)
	visual.animate(moving, _working, delta)
