class_name EdgeTest
extends Node
## [orbit] Headless check for WorldBounds (--edge-test): Lumi walks into the edge (must stop at the
## soft wall), is dropped outside and under the world (must be rescued onto ground), and a robot
## (with --robots=...) is dropped under the world. Prints [edge] PASS/FAIL and quits (exit 1 on fail).

var world: Node
var bounds: WorldBounds
var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _run() -> void:
	await _wait(1.0)
	var patch: Patch = world.get("patch")
	var old_input: InputSource = patch.input
	var lim: float = bounds.wall()
	# 1. Walk straight at the edge along a street.
	patch.global_position = Vector3(lim - 6.0, 0.2, 18.0)
	patch.input = StraightWalkInput.new(Vector3(1, 0, 0))
	await _wait(3.0)
	print("[edge] walk: x=%.2f wall=%.2f rescues=%d" % [patch.global_position.x, lim, bounds.rescues])
	if patch.global_position.x > lim + 0.05 or patch.global_position.y < -0.5:
		_fails.append("walked past the wall")
	patch.input = old_input
	# 2. Outside the square and under the ground.
	var before: int = bounds.rescues
	patch.global_position = Vector3(bounds.half + 25.0, -12.0, 18.0)
	await _wait(2.0)
	var p: Vector3 = patch.global_position
	print("[edge] rescue: pos=%s rescues=%d" % [str(p.snapped(Vector3.ONE * 0.01)), bounds.rescues])
	if bounds.rescues != before + 1 or absf(p.x) > lim or p.y < -0.5 or p.y > 1.0 or not patch.is_physics_processing():
		_fails.append("rescue did not land Lumi on ground")
	# 3. A robot under the world.
	var bots: Array[Node] = get_tree().get_nodes_in_group("robot")
	if not bots.is_empty():
		var b := bots[0] as Node3D
		b.global_position = Vector3(10.0, -20.0, 10.0)
		await _wait(0.5)
		print("[edge] robot: pos=%s robot_rescues=%d" % [str(b.global_position.snapped(Vector3.ONE * 0.01)), bounds.robot_rescues])
		if b.global_position.y < -0.5:
			_fails.append("robot not rescued")
	print("[edge] %s %s" % ["PASS" if _fails.is_empty() else "FAIL", ", ".join(_fails)])
	get_tree().quit(0 if _fails.is_empty() else 1)
