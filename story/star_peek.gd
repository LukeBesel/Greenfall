class_name StarPeek
extends Node
## [eggs2] Looking through WREN's brass telescope (egg "stars"): a steady eyepiece camera at the
## telescope (not Lumi's bobbing lens view), aimed straight at the constellation, with a round
## eyepiece mask. The old peek pitched Lumi's own lens camera up: it bobbed with her idle float,
## swung with her yaw, clipped her visor at near 0.32, drew the lens HUD (blinking REC, grain) on
## top and the far DOF blurred the stars; that read as glitchy. E (or Esc) leaves early.

signal finished

const HOLD_S: float = 7.0
const FOV_FROM: float = 34.0
const FOV_TO: float = 15.0

var world: Node
var scope: Node3D
var target: Vector3 = Vector3(110, 170, -190)
var cam: Camera3D
var mask: ShaderMaterial
var _layer: CanvasLayer
var _t: float = 0.0
var _open: float = 0.0  # 0 = closed iris, 1 = full eyepiece
var _closing: bool = false
var _done: bool = false

const MASK_SHADER := """
shader_type canvas_item;
uniform float open = 0.0;
uniform float aspect = 1.7778;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p);
	float rad = 0.46 * open;
	float edge = smoothstep(rad, rad - 0.035, r);
	// A thin warm brass rim, then black.
	float rim = smoothstep(rad + 0.012, rad, r) * (1.0 - edge);
	vec3 col = mix(vec3(0.0), vec3(0.35, 0.26, 0.12), rim);
	COLOR = vec4(col, 1.0 - edge);
}
"""


func start() -> void:
	_t = 0.0
	print("[eggs] looking through the telescope at %s" % str(target))
	_lock(true)
	var eye: Vector3 = eyepiece()
	cam = Camera3D.new()
	cam.name = "StarPeekCam"
	cam.fov = FOV_FROM
	cam.near = 0.05
	cam.far = 1500.0
	cam.attributes = null  # no far DOF: stars stay sharp
	# A night-adapted eyepiece: the bright moonlit haze is dimmed and the fog dropped, so the stars stand out.
	var vp_env: Environment = _world_env()
	if vp_env:
		var e: Environment = vp_env.duplicate()
		e.fog_enabled = false
		e.volumetric_fog_enabled = false
		e.tonemap_exposure = vp_env.tonemap_exposure * 0.3
		e.background_energy_multiplier = vp_env.background_energy_multiplier * 0.35
		e.adjustment_enabled = true
		e.adjustment_saturation = 0.6
		e.glow_enabled = true
		cam.environment = e
	add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	_show_head(false)  # we are at the eyepiece: the tube itself must not fill the view
	if world and world.get("hud") != null and world.hud:
		world.hud.visible = false  # an uncluttered eyepiece
	_layer = CanvasLayer.new()
	_layer.layer = 4  # under the HUD (toasts stay readable)
	add_child(_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MASK_SHADER
	mask.shader = sh
	rect.material = mask
	_layer.add_child(rect)
	cam.current = true
	if DevHooks.has("shot"):  # dev: slow software renders capture the open eyepiece, not the iris
		_open = 1.0
		_t = 2.2


func _world_env() -> Environment:
	if world and world.get("env") is Environment:
		return world.env
	var w3: World3D = get_viewport().find_world_3d() if get_viewport() else null
	return w3.environment if w3 and w3.environment else null


## World position of the eyepiece (back end of the brass tube), a little behind it.
func eyepiece() -> Vector3:
	if scope == null:
		return Vector3(0, 1.4, 0)
	var head: Node3D = scope.get_node_or_null("Anim")
	if head == null:
		return scope.global_position + Vector3(0, 1.3, 0)
	var back: Vector3 = head.to_global(Vector3(-0.5, 0.0, 0.0))
	return back + (back - target).normalized() * 0.15


func close() -> void:
	_closing = true


func _unhandled_input(event: InputEvent) -> void:
	if _t > 0.6 and (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _done or cam == null:
		return
	_t += delta
	if _t >= HOLD_S + (60.0 if DevHooks.has("shot") else 0.0):
		_closing = true
	_open = move_toward(_open, 0.0 if _closing else 1.0, delta / 0.6)
	var e: float = _open * _open * (3.0 - 2.0 * _open)
	cam.fov = lerpf(FOV_FROM, FOV_TO, smoothstep(0.0, 2.2, _t))
	var vs: Vector2 = get_viewport().get_visible_rect().size
	mask.set_shader_parameter("open", e)
	mask.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	if _closing and _open <= 0.0:
		_finish()


func _finish() -> void:
	_done = true
	if world and world.get("cam") != null and (world.cam as CameraRig).camera:
		(world.cam as CameraRig).camera.current = true
	_show_head(true)
	_lock(false)
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	if not _done:
		_done = true
		_show_head(true)
		_lock(false)


func _show_head(on: bool) -> void:
	var head: Node3D = scope.get_node_or_null("Anim") if is_instance_valid(scope) else null
	if head:
		head.visible = on
	# Lumi may be standing in front of the tube: she steps out of the picture while we look.
	if world and world.get("patch") != null and world.patch and world.patch.get("model") != null:
		(world.patch.model as Node3D).visible = on


func _lock(on: bool) -> void:
	if world == null:
		return
	if not on and world.get("hud") != null and world.hud:
		world.hud.visible = true
	if world.get("patch") != null and world.patch and world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = not on
	if world.get("cam") != null and world.cam:
		world.cam.input_enabled = not on
