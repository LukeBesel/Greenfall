class_name DemoScoopInput
extends InputSource
## Dev hook (--demo-scoop): Patch holds the scoop and creeps toward the nearest junk so the pickup
## animation plays continuously for screenshots. The hopper is emptied (cheat) whenever it fills
## so the scoop never stops. --demo-speed=X scales the creep (default 0.3).

var world: Node
var _move := Vector3.ZERO


func _init(p_world: Node) -> void:
	world = p_world


func get_world_move(_cam_yaw: float) -> Vector3:
	return _move


func scoop_held() -> bool:
	return true


func update(_delta: float) -> void:
	var p: Patch = world.get("patch")
	if p == null:
		return
	if not p.compartment.can_accept(p.capacity()):
		p.compartment.take_all()
	_move = Vector3.ZERO
	var pid: int = world.field.nearest_alive(p.scoop_origin())
	if pid < 0:
		return
	var d: Vector3 = world.field.piece_pos[pid] - p.global_position
	d.y = 0.0
	if d.length() > 1.1:
		_move = d.normalized() * DevHooks.get_f("demo-speed", 0.3)


## Puts Patch beside the junk nearest to `near`, facing it.
static func place(world_: Node, patch: Patch, near: Vector3) -> void:
	var pid: int = world_.field.nearest_alive(near)
	if pid < 0:
		return
	var piece: Vector3 = world_.field.piece_pos[pid]
	var dir: Vector3 = piece - near
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	patch.global_position = Vector3(piece.x, near.y, piece.z) - dir * 1.3
	patch.rotation.y = atan2(-dir.x, -dir.z)
