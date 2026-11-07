class_name LumiPreview
extends SubViewportContainer
## [style] The Character Builder's big turntable: Lumi in a style (LumiStyle.apply) on a dark
## studio floor (so the hover glow shows), drag / right stick to turn, wheel / triggers to zoom,
## auto-spin when left alone, and demo_beam() fires the real pickup show (PickupFx) at a small
## piece of junk so the laser colour can be judged.

signal zoom_changed(z: float)

var model: PatchModel
var spin_speed: float = 0.35
var zoom: float = 0.0  # 0 = full body, 1 = face close-up
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _fx: PickupFx
var _yaw: float = -0.45
var _yaw_vel: float = 0.0
var _idle: float = 99.0
var _drag: bool = false
var _beam_t: float = -1.0
var _junk_meshes: Array[Mesh] = []


func _init(px: Vector2i = Vector2i(640, 640)) -> void:
	stretch = true
	custom_minimum_size = Vector2(px) * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = px
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.04, 0.05)
	env.fog_density = 0.09
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.35
	key.light_color = Color(1.0, 0.94, 0.86)
	key.rotation_degrees = Vector3(-40, 150, 0)
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-18, -25, 0)
	_vp.add_child(rim)
	# Studio floor: a soft dark disc that catches the hover light.
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.6
	disc.bottom_radius = 2.6
	disc.height = 0.02
	disc.radial_segments = 64
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.11, 0.115, 0.125)
	fm.roughness = 0.55
	fm.metallic_specular = 0.4
	floor_mi.material_override = fm
	floor_mi.position.y = -0.01
	_vp.add_child(floor_mi)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	for sz: Vector3 in [Vector3(0.16, 0.09, 0.12), Vector3(0.12, 0.12, 0.12), Vector3(0.2, 0.06, 0.1)]:
		var b := BoxMesh.new()
		b.size = sz
		var jm := StandardMaterial3D.new()
		jm.albedo_color = Color(0.45, 0.42, 0.38)
		jm.roughness = 0.8
		b.material = jm
		_junk_meshes.append(b)
	_place_camera()


func show_style(style: Dictionary) -> void:
	if model == null:
		model = PatchModel.new()
		model.set_meta("lumi_style", LumiStyle.normalize(style))
		model.preview_variant = str(LumiStyle.normalize(style)["bonus"])
		_pivot.add_child(model)
		model.set_happy(0.7)
		_fx = PickupFx.new()
		_fx.model = model
		_vp.add_child(_fx)
	else:
		LumiStyle.apply(model, style)


## Fire the pickup laser at a piece of junk in front of Lumi (pulls it into the chest hopper).
func demo_beam() -> void:
	if model == null or _fx == null:
		return
	_idle = 0.0
	var fwd: Vector3 = -model.global_transform.basis.z
	var side: Vector3 = model.global_transform.basis.x
	var p: Vector3 = model.global_position + fwd * 0.95 + side * randf_range(-0.25, 0.35) + Vector3(0, 0.05, 0)
	var xf := Transform3D(Basis.from_euler(Vector3(0, randf() * TAU, 0)), p)
	_fx.launch(_junk_meshes[randi() % _junk_meshes.size()], xf, 0.55, false, Color(0.7, 0.66, 0.6))
	_beam_t = 0.0


func set_zoom(z: float) -> void:
	zoom = clampf(z, 0.0, 1.0)
	_place_camera()
	zoom_changed.emit(zoom)


func _place_camera() -> void:
	var dist: float = lerpf(3.1, 1.15, zoom)
	var look_y: float = lerpf(0.62, 0.86, zoom)
	var cam_y: float = lerpf(1.02, 0.9, zoom)
	_cam.position = Vector3(0, cam_y, -dist)
	_cam.look_at_from_position(_cam.position, Vector3(0, look_y, 0), Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_idle = 0.0
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom + 0.08)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom - 0.08)
			accept_event()
	elif event is InputEventMouseMotion and _drag:
		_yaw += (event as InputEventMouseMotion).relative.x * 0.01
		_yaw_vel = (event as InputEventMouseMotion).relative.x * 0.6
		_idle = 0.0
		accept_event()


func _process(delta: float) -> void:
	if model == null:
		return
	# Right stick turns, triggers zoom (the builder's left stick moves focus).
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	if absf(rx) > 0.2:
		_yaw += rx * delta * 2.6
		_idle = 0.0
	var zt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(zt) > 0.15:
		set_zoom(zoom + zt * delta * 1.2)
	_idle += delta
	if not _drag:
		_yaw += _yaw_vel * delta
		_yaw_vel = move_toward(_yaw_vel, 0.0, delta * 3.0)
		if _idle > 2.5:
			_yaw += delta * spin_speed * clampf((_idle - 2.5) / 1.5, 0.0, 1.0)
	_pivot.rotation.y = _yaw
	if _beam_t >= 0.0:
		_beam_t += delta
		if _beam_t > 0.9:
			_beam_t = -1.0
