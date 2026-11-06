class_name JunkCube
extends RigidBody3D
## A compacted junk cube. Physical, stackable, wobbly. Its value is cashed at a Depot.

static var _mesh: ArrayMesh

var value: BigNum = BigNum.zero()
var info: Dictionary = {}
var size: float = 0.55
var carried: bool = false
var claimed: bool = false  # being sucked into a depot

var _visual: MeshInstance3D
var _mat: ShaderMaterial
var _shape: CollisionShape3D
var _land_cooldown: float = 0.0
var _spawn_time: float = 0.0


static func create(p_value: BigNum, p_info: Dictionary) -> JunkCube:
	var c := JunkCube.new()
	c.value = p_value
	c.info = p_info
	var fill: float = clampf(float(p_info.get("fill", 1.0)), 0.25, 1.15)
	c.size = lerpf(0.36, 0.6, clampf(fill, 0.0, 1.0)) * (1.06 if p_info.get("lumpy", false) else 1.0)
	return c


func _ready() -> void:
	add_to_group("junk_cube")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	mass = 1.5
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.22
	pm.friction = 0.9
	physics_material_override = pm
	if _mesh == null:
		_mesh = ProcMesh.rounded_box(Vector3.ONE, 0.09, 3)
	_visual = MeshInstance3D.new()
	_visual.mesh = _mesh
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/cube.gdshader")
	var cols: Array = info.get("colors", [])
	var c0: Color = cols[0] if cols.size() > 0 else Color(0.7, 0.7, 0.7)
	_mat.set_shader_parameter("color_a", c0)
	_mat.set_shader_parameter("color_b", cols[1] if cols.size() > 1 else c0.darkened(0.15))
	_mat.set_shader_parameter("color_c", cols[2] if cols.size() > 2 else c0.lightened(0.2))
	_mat.set_shader_parameter("speckle", 0.0 if info.get("pure", false) else 1.0)
	_mat.set_shader_parameter("perfect", 1.0 if info.get("perfect", false) else 0.0)
	_mat.set_shader_parameter("pure_shine", 1.0 if info.get("pure", false) else 0.0)
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_visual.material_override = _mat
	_visual.scale = Vector3.ONE * size
	if info.get("lumpy", false):
		_visual.scale = Vector3(size * 1.08, size * 0.9, size * 1.02)
		_visual.rotation_degrees = Vector3(4, 7, -5)
	add_child(_visual)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size * 0.98
	_shape.shape = box
	add_child(_shape)
	body_entered.connect(_on_body_entered)
	_spawn_time = Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	_land_cooldown = maxf(0.0, _land_cooldown - delta)
	if global_position.y < -20.0 and not carried:
		# Fell out of the world: put it back near the hub.
		global_position = Vector3(randf_range(-1, 1), 2.0, randf_range(2, 4))
		linear_velocity = Vector3.ZERO


func _on_body_entered(_body: Node) -> void:
	if carried or _land_cooldown > 0.0:
		return
	var speed: float = linear_velocity.length()
	if speed > 1.2:
		_land_cooldown = 0.15
		Audio.play("thud", clampf(1.4 - size, 0.7, 1.3), linear_to_db(clampf(speed / 6.0, 0.15, 1.0)))
		squish(clampf(speed * 0.04, 0.05, 0.25))


func squish(amount: float) -> void:
	var base: Vector3 = _visual.scale
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3(base.x * (1.0 + amount), base.y * (1.0 - amount), base.z * (1.0 + amount)), 0.06)
	tw.tween_property(_visual, "scale", base, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func flash() -> void:
	_mat.set_shader_parameter("flash", 1.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.3)


## Switches between physical and carried (kinematic, no collision).
func set_carried(on: bool) -> void:
	carried = on
	freeze = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_shape.disabled = on
	if not on:
		sleeping = false


func to_dict() -> Dictionary:
	var cols: Array = []
	for c: Color in info.get("colors", []):
		cols.append(c.to_html())
	return {
		"value": value.serialize(),
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": [rotation.x, rotation.y, rotation.z],
		"pure": info.get("pure", false), "perfect": info.get("perfect", false),
		"lumpy": info.get("lumpy", false), "fill": info.get("fill", 1.0), "colors": cols,
	}


static func from_dict(d: Dictionary) -> JunkCube:
	var cols: Array[Color] = []
	for h: Variant in d.get("colors", []):
		cols.append(Color.html(str(h)))
	var info_d: Dictionary = {
		"pure": d.get("pure", false), "perfect": d.get("perfect", false),
		"lumpy": d.get("lumpy", false), "fill": float(d.get("fill", 1.0)), "colors": cols,
	}
	return JunkCube.create(BigNum.from_serialized(d.get("value", [0.0, 0])), info_d)
