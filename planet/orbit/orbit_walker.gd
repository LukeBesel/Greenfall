class_name OrbitWalker
extends CharacterBody3D
## [orbit] Prototype Lumi on the globe: gravity toward the planet centre, the floor is "up" along
## the radius, movement in the camera's surface frame (parallel-transported, so a straight stick
## walks a great circle). Uses the real PatchModel; Patch's game logic is not involved.

const ACCEL: float = 16.0
const DECEL: float = 22.0
const GRAVITY: float = 20.0

var input: InputSource
var cam: OrbitCam
var speed: float = 4.6
var model: PatchModel
var distance: float = 0.0
var _fwd := Vector3.FORWARD


func _ready() -> void:
	add_to_group("orbit_walker")
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.2, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	model = PatchModel.new()
	model.name = "Model"
	add_child(model)
	if input == null:
		input = PlayerInput.new()


func up() -> Vector3:
	return global_position.normalized()


func face(fwd: Vector3) -> void:
	var u: Vector3 = up()
	_fwd = (fwd - u * fwd.dot(u)).normalized()
	global_transform.basis = Basis.looking_at(_fwd, u)


func _physics_process(delta: float) -> void:
	input.update(delta)
	var u: Vector3 = up()
	up_direction = u
	var mv: Vector3 = input.get_world_move(0.0)  # camera-local: x right, z back
	var wish: Vector3 = Vector3.ZERO
	if cam:
		wish = cam.frame.x * mv.x + cam.frame.z * mv.z
	wish = (wish - u * wish.dot(u)).limit_length(1.0)
	var vv: float = velocity.dot(u)
	var hv: Vector3 = velocity - u * vv
	var target: Vector3 = wish * speed
	hv = hv.move_toward(target, (ACCEL if target.length() > hv.length() else DECEL) * delta)
	vv = -0.3 if is_on_floor() else vv - GRAVITY * delta
	velocity = hv + u * vv
	move_and_slide()
	u = up()
	var hs: float = hv.length()
	var f: Vector3 = _fwd
	if hs > 0.3:
		f = f.slerp(hv.normalized(), clampf(9.0 * delta, 0.0, 1.0)) if f.dot(hv.normalized()) > -0.95 else hv.normalized()
	face(f)
	distance += hs * delta
	model.set_motion(hs, hs / maxf(speed, 0.1), Vector2.ZERO, delta)
