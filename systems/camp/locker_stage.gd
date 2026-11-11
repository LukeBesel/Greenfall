class_name LockerStage
extends Node3D
## The Locker's turntable (design spec section 13): a low steel disc beside the cabinet. While
## the Locker is open Lumi stands on it, turning, and the view leaves the player's camera for one
## that swings round the turntable on the yard's side, so the look is judged in the real light
## of the place. The Lumi on the disc is a stand-in model wearing the look being edited; the
## real one is hidden meanwhile and never moves, so nothing about the player's position, cargo or
## physics changes.
##
## Local frame: origin on the ground at the disc's centre, +Z toward the open yard.
## Use: begin(world, style); show_style(style) as the look changes; end().

const DISC_R: float = 0.78
const DISC_H: float = 0.09
## Camera: distance and height from the disc, the point it looks at, and how far the view is
## turned aside so Lumi stands in the part of the screen the panel leaves free.
const CAM_DIST: float = 3.3
const CAM_H: float = 1.25
const LOOK_H: float = 0.72
const CAM_FOV: float = 34.0
const CAM_ASIDE_RAD: float = 0.2
## The camera swings between these angles either side of the yard-facing direction.
const SWING_RAD: float = 0.9
const SWING_S: float = 26.0
const SPIN_RAD_S: float = 0.5
const DRAG_RAD_PX: float = 0.01
const IDLE_S: float = 2.0
const ZOOM_MIN: float = 0.55
const ZOOM_STEP: float = 0.08

var _world: Node
var _pivot: Node3D
var _model: PatchModel
var _cam: Camera3D
var _prev_cam: Camera3D
var _lamp: OmniLight3D
var _hidden: Node3D
var _t: float = 0.0
var _idle: float = IDLE_S
var _zoom: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the world is paused while the Locker is open
	var k := YardArt.Kit.new()
	k.cyl(DISC_R + 0.1, 0.05, Vector3(0, 0.025, 0), YardArt.DARK, Vector3.ZERO, 0.01, 28)
	k.cyl(DISC_R, DISC_H, Vector3(0, DISC_H * 0.5, 0), YardArt.STEEL, Vector3.ZERO, 0.015, 28)
	k.glow_cyl(DISC_R * 0.86, 0.012, Vector3(0, DISC_H + 0.004, 0), YardArt.CYAN, Vector3.ZERO, 28)
	k.cyl(DISC_R * 0.8, 0.02, Vector3(0, DISC_H + 0.008, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.004, 28)
	for i: int in 4:  # stencilled quarter marks
		var a: float = TAU * 0.25 * i + TAU * 0.125
		k.hazard(Vector3(0.2, 0.012, 0.07), Vector3(cos(a), 0, sin(a)) * DISC_R * 0.93 + Vector3(0, DISC_H + 0.004, 0), Vector3(0, -rad_to_deg(a) + 90.0, 0))
	var disc: MeshInstance3D = k.mi(0.2, "Turntable")
	add_child(disc)
	YardArt.set_powered(disc, true)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_pivot.position.y = DISC_H + 0.02
	add_child(_pivot)
	set_process(false)


func is_open() -> bool:
	return _cam != null


## The stand-in on the disc (null while the Locker is shut).
func model() -> PatchModel:
	return _model


## Lumi steps onto the turntable: the stand-in appears in `style`, the real Lumi is hidden and
## the view moves to the turntable's camera.
func begin(world: Node, style: Dictionary) -> void:
	if is_open():
		return
	_world = world
	_model = PatchModel.new()
	_model.process_mode = Node.PROCESS_MODE_ALWAYS
	var s: Dictionary = LumiStyle.normalize(style)
	_model.set_meta("lumi_style", s)
	_model.preview_variant = str(s["bonus"])
	_pivot.add_child(_model)
	_model.set_happy(0.7)
	_lamp = OmniLight3D.new()
	_lamp.position = Vector3(0.6, 2.3, 1.6)
	_lamp.light_color = Color(1.0, 0.95, 0.86)
	_lamp.light_energy = 0.9
	_lamp.omni_range = 5.0
	add_child(_lamp)
	var player: Variant = world.get("patch") if world else null
	if player is Node3D and (player as Node3D).visible:
		_hidden = player
		_hidden.visible = false
	_prev_cam = get_viewport().get_camera_3d() if is_inside_tree() else null
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.near = 0.05
	if _prev_cam:
		_cam.far = _prev_cam.far
	add_child(_cam)
	_t = SWING_S * 0.25
	_zoom = 1.0
	_place_camera()
	_cam.make_current()
	set_process(true)


## Show another look on the stand-in.
func show_style(style: Dictionary) -> void:
	if _model:
		LumiStyle.apply(_model, style)


## Turn the disc by hand (a drag of dx pixels); it rests a moment before turning on its own again.
func turn(dx_px: float) -> void:
	_pivot.rotation.y += dx_px * DRAG_RAD_PX
	_idle = 0.0


## Move the camera in (steps > 0) or back out.
func zoom(steps: float) -> void:
	_zoom = clampf(_zoom - steps * ZOOM_STEP, ZOOM_MIN, 1.0)


## Lumi steps off: the stand-in goes, the real Lumi shows again, the player's camera returns.
func end() -> void:
	if not is_open():
		return
	set_process(false)
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	for n: Node in [_cam, _model, _lamp]:
		if n and is_instance_valid(n):
			n.queue_free()
	_cam = null
	_model = null
	_lamp = null
	if _hidden and is_instance_valid(_hidden):
		_hidden.visible = true
	_hidden = null


func _exit_tree() -> void:
	end()


func _process(delta: float) -> void:
	_idle += delta
	if _idle >= IDLE_S and not Settings.reduced_motion:
		_pivot.rotation.y += SPIN_RAD_S * delta
		_t += delta
	_place_camera()


func _place_camera() -> void:
	if _cam == null:
		return
	var a: float = sin(_t / SWING_S * TAU) * SWING_RAD
	var dist: float = CAM_DIST * _zoom
	var look_h: float = lerpf(LOOK_H + 0.2, LOOK_H, _zoom)
	_cam.position = Vector3(sin(a) * dist, lerpf(LOOK_H + 0.35, CAM_H, _zoom), cos(a) * dist)
	_cam.look_at_from_position(_cam.global_position, to_global(Vector3(0, look_h, 0)), global_basis.y)
	_cam.rotate_object_local(Vector3.UP, -CAM_ASIDE_RAD * _zoom)
