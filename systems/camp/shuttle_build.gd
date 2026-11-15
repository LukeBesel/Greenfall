class_name ShuttleBuild
extends Node
## [v10pace] The shuttle goes up on the launch pad, piece by piece (owner: "I didnt even build
## this shuttle"). Started when the "shuttle" build is bought at the workbench (Camp._on_built):
## the workbench closes so the player sees it, the ship's parts appear one after another on the
## marked spot with sparks and thuds over BUILD_S seconds, then the machine reveal names it and
## WREN says where it flies. The rocket's E prompt only answers once it is finished.
## State is not saved: a save taken mid-build loads with the finished shuttle standing.

const BUILD_S: float = 7.0

static var building: bool = false

var world: Node
var _ship: Node3D
var _parts: Array[Node3D] = []
var _shown: int = 0
var _t: float = 0.0
var _wait: float = 0.0


static func start(p_world: Node) -> void:
	if p_world == null or not p_world.is_inside_tree():
		return
	var b := ShuttleBuild.new()
	b.name = "ShuttleBuild"
	b.world = p_world
	building = true
	p_world.add_child(b)


func _ready() -> void:
	for scr: String in ["upgrades"]:
		var u: Variant = world.get(scr)
		if u != null and (u as Object).has_method("close_screen"):
			(u as Node).call_deferred("close_screen")


func _exit_tree() -> void:
	building = false


func _sites() -> OrbitSites:
	return OrbitSites.of(world)


func _process(delta: float) -> void:
	if _ship == null:
		_wait += delta
		if world.has_method("any_modal_open") and bool(world.call("any_modal_open")) and _wait < 3.0:
			return
		var os_: OrbitSites = _sites()
		if os_ == null:
			_finish(Vector3.ZERO)
			return
		os_._sync_rocket()
		var s: ShipModel = os_.hop.parked()
		if s == null or not s.visible:
			if _wait > 6.0:
				_finish(Vector3.ZERO)
			return
		_ship = s
		for c: Node in s.get_children():
			if c is Node3D and (c as Node3D).visible and not (c is RocketPlume):
				_parts.append(c as Node3D)
				(c as Node3D).visible = false
		Audio.play("thud", 0.8, -8.0)
		return
	if not is_instance_valid(_ship):
		_finish(Vector3.ZERO)
		return
	_t += delta
	var want: int = int(ceil(clampf(_t / BUILD_S, 0.0, 1.0) * float(_parts.size())))
	while _shown < want and _shown < _parts.size():
		var p: Node3D = _parts[_shown]
		_shown += 1
		if not is_instance_valid(p):
			continue
		p.visible = true
		var at: Vector3 = p.global_position
		Vfx.burst("sparkle", at + OrbitUp.up(at) * 0.6, Color(1.0, 0.8, 0.45), 0.5)
		Audio.play("thud" if _shown % 2 == 0 else "pop", 1.0 + 0.04 * float(_shown % 5), -10.0)
	if _t >= BUILD_S:
		_finish(_ship.global_position)


func _finish(at: Vector3) -> void:
	for p: Node3D in _parts:
		if is_instance_valid(p):
			p.visible = true
	set_process(false)
	if at != Vector3.ZERO:
		Audio.play("chime", 1.0, -6.0)
		MachineReveal.reveal(world, tr(str(YardBuilds.def("shuttle").get("name", "Shuttle"))), at)
	queue_free()
