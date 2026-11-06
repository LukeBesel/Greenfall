class_name Rocket
extends Node3D
## The hub rocket: a rusty tube built from junk. Launch sequence (countdown, rumble, smoke,
## liftoff), then a flight arc on the globe, then the destination district loads.

var world: Node
var _body: Node3D
var _flying: bool = false
var _last_exhaust_t: float = -1.0
const EXHAUST_EVERY_S: float = 0.1
const LIFTOFF_S: float = 4.5


func is_flying() -> bool:
	return _flying


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var hull: ShaderMaterial = Mats.worn_paint(Color(0.85, 0.85, 0.82), 0.6, 0.6, 77.0, 0.5)
	var stripe: ShaderMaterial = Mats.worn_paint(Color(0.9, 0.35, 0.2), 0.7, 0.5, 78.0, 0.4)
	_mi(ProcMesh.cyl(0.9, 1.0, 6.0, 20), hull, Vector3(0, 3.6, 0))
	_mi(ProcMesh.cyl(0.0, 0.9, 2.0, 20), stripe, Vector3(0, 7.6, 0))
	_mi(ProcMesh.cyl(0.92, 0.92, 0.4, 20), stripe, Vector3(0, 2.0, 0))
	_mi(ProcMesh.cyl(0.6, 0.8, 0.6, 16), Mats.metal("dark_steel"), Vector3(0, 0.3, 0))
	for k: int in 4:
		var a: float = TAU * k / 4.0
		_mi(ProcMesh.box(Vector3(0.08, 2.0, 1.2)), stripe, Vector3(cos(a) * 1.0, 1.4, sin(a) * 1.0), Vector3(0, -rad_to_deg(a), 0))
	_mi(ProcMesh.cyl(0.3, 0.3, 0.05, 16), Mats.glass(Color(0.2, 0.4, 0.5, 0.8)), Vector3(0, 5.0, -0.92), Vector3(90, 0, 0))
	var label := Mats.stencil("CRADLE RUN 01", 80, Color(0.2, 0.2, 0.2, 0.8))
	label.position = Vector3(0, 3.8, -1.0)
	label.rotation_degrees = Vector3(0, 180, 0)
	_body.add_child(label)


func _mi(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	_body.add_child(m)


func launch(to_hub: int) -> void:
	if _flying:
		return
	_flying = true
	var cam: CameraRig = world.cam
	world.hud.visible = false
	cam.input_enabled = false
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	world.patch.visible = false
	cam.target = self
	cam.distance = 16.0
	cam.pitch = -0.15
	for i: int in 3:
		Audio.play("beep", 1.4 - i * 0.15, -4.0)
		world.wren.line_started.emit(str(3 - i), 2)
		# process_always = false: the countdown waits while the game is paused.
		await get_tree().create_timer(1.0, false).timeout
		if not is_inside_tree():
			return
	Audio.play("crunch", 0.5, 0.0)
	Audio.play("hydraulic", 0.6, -2.0)
	# The steam pool has Vfx.POOL_PER_KIND emitters; more bursts in one frame just restart them.
	for k: int in 6:
		Vfx.burst("steam", global_position + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), Color(0.85, 0.82, 0.78, 0.8), 2.0)
	EventBus.shake_requested.emit(0.6)
	Input.start_joy_vibration(0, 0.8, 1.0, 2.0)
	var start: Vector3 = _body.position
	_last_exhaust_t = -1.0
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		_body.position = start + Vector3(sin(t * 60.0) * 0.05 * (1.0 - t), t * t * 140.0, 0)
		if _last_exhaust_t < 0.0 or (t - _last_exhaust_t) * LIFTOFF_S >= EXHAUST_EVERY_S:
			_last_exhaust_t = t
			Vfx.burst("steam", global_position + _body.position, Color(0.9, 0.88, 0.85, 0.7), 0.8)
		EventBus.shake_requested.emit(0.08 * (1.0 - t)), 0.0, 1.0, LIFTOFF_S)
	await tw.finished
	if not is_inside_tree():
		return
	# Flight on the survey globe.
	world.globe.fly(world.hub_index, to_hub, 5.0)
	await get_tree().create_timer(5.5, false).timeout
	if not is_inside_tree():
		return
	world.travel_to(to_hub)
