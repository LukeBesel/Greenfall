class_name ModelPreview
extends SubViewportContainer
## [ui7] A small turntable for the Locker's detail panel: its own 3D world, a soft key + rim light,
## a dark floor disc with a thin cyan ring, and the model slowly turning. set_model(node) swaps it.

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _t: float = 0.0
var spin: float = 0.5


func _init(px: Vector2i = Vector2i(320, 190)) -> void:
	custom_minimum_size = Vector2(px)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = px
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.045, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.light_energy = 1.25
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.8, 1.0)
	_vp.add_child(rim)
	var ring := MeshInstance3D.new()
	ring.mesh = ProcMesh.torus(1.04, 1.06, 64, 3)
	ring.material_override = Mats.lamp(Color(0.35, 0.85, 1.0), 1.2)
	_vp.add_child(ring)
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	frame(3.0, 0.6)


## Camera distance and the height it looks at (models differ in size).
func frame(dist: float, look_y: float) -> void:
	_cam.position = Vector3(0, look_y + dist * 0.28, dist)
	_cam.look_at_from_position(_cam.position, Vector3(0, look_y, 0), Vector3.UP)


func set_model(n: Node3D) -> void:
	for c: Node in _pivot.get_children():
		_pivot.remove_child(c)
		c.queue_free()
	if n:
		_pivot.add_child(n)


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = _t * spin
