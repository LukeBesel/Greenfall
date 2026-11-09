class_name OrbitCam
extends Node3D
## [orbit] Prototype follow camera on the globe. `frame` is the camera's surface frame
## (x right, y local up, z back), parallel-transported as the target moves so walking straight
## never spins the view. Yaw from the look actions; fixed dev views via `view`.

var target: Node3D
var frame := Basis()
var distance: float = 6.2
var pitch: float = -0.3
var view: String = "follow"  # follow | low | mid
var planet_r: float = 920.0
var camera: Camera3D
var _focus := Vector3.ZERO


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.05
	camera.far = 12000.0
	add_child(camera)
	camera.current = true


func reset_frame(fwd: Vector3) -> void:
	var u: Vector3 = target.global_position.normalized()
	var back: Vector3 = -(fwd - u * fwd.dot(u)).normalized()
	frame = Basis(u.cross(back).normalized(), u, back)
	_focus = target.global_position + u * 1.1


func _process(delta: float) -> void:
	if target == null:
		return
	var u: Vector3 = target.global_position.normalized()
	var q := Quaternion(frame.y.normalized(), u)
	frame = (Basis(q) * frame).orthonormalized()
	var look: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.x != 0.0:
		frame = (Basis(u, -look.x * 2.6 * delta) * frame).orthonormalized()
	pitch = clampf(pitch - look.y * 1.8 * delta, -1.4, -0.02)
	var want: Vector3 = target.global_position + u * 1.1
	_focus = _focus.lerp(want, clampf(delta * 10.0, 0.0, 1.0)) if _focus != Vector3.ZERO else want
	match view:
		"mid":  # the whole little planet, Lumi's side toward the camera
			var d: Vector3 = (u * 0.82 + frame.z * 0.57).normalized()
			global_position = d * planet_r * 2.55
			camera.look_at_from_position(global_position, Vector3.ZERO + u * planet_r * 0.12, frame.y)
			return
		"low":  # a couple of hundred metres up behind Lumi: the base and the curve
			global_position = _focus + frame.z * distance * cos(pitch) - frame.y * distance * sin(pitch)
			camera.look_at_from_position(global_position, _focus + frame.z * -distance * 0.35, frame.y)
			return
	global_position = _focus + frame.z * distance * cos(pitch) - frame.y * distance * sin(pitch)
	camera.look_at_from_position(global_position, _focus, frame.y)
