class_name DesignPreview
extends SubViewportContainer
## A small turntable of Lumi in one design (the Cosmetics picker and the unlock toast): its own
## World3D in a SubViewport, a camera, a key/rim light pair and a slowly spinning PatchModel.

var spin_speed: float = 0.55
var _vp: SubViewport
var _pivot: Node3D
var _model: PatchModel
var _id: String = ""
var _yaw: float = -0.5


func _init(px: Vector2i = Vector2i(320, 320)) -> void:
	stretch = true
	custom_minimum_size = Vector2(px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = px
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.62)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.94, 0.86)
	key.rotation_degrees = Vector3(-38, 150, 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.9
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-20, -20, 0)
	_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0.82, -2.45)
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.6, 0), Vector3.UP)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


func show_design(id: String) -> void:
	if id == _id or not PatchModel.VARIANTS.has(id):
		return
	_id = id
	if _model == null:
		_model = PatchModel.new()
		_model.preview_variant = id
		_pivot.add_child(_model)
	else:
		_model.set_variant(id)
	_model.set_happy(0.8)


func _process(delta: float) -> void:
	if _model == null:
		return
	_yaw += delta * spin_speed
	_pivot.rotation.y = _yaw
