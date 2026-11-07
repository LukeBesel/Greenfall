class_name JunkCube
extends RigidBody3D
## A compacted junk cube. Physical, stackable, wobbly. Its value is cashed at a Depot.

static var _mesh: ArrayMesh
static var _strap_mesh: ArrayMesh

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
	collision_mask = 1 | 2 | 4 | PhysLayers.PROP | PhysLayers.MOUND  # [world2] props and junk mounds
	mass = 20.0 + 25.0 * float(info.get("fill", 1.0))
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.04
	pm.friction = 0.9
	physics_material_override = pm
	if _mesh == null:
		_mesh = ProcMesh.rounded_box(Vector3.ONE, 0.05, 3)
	_visual = MeshInstance3D.new()
	_visual.mesh = _mesh
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/cube.gdshader")
	var cols: Array = info.get("colors", [])
	var c0: Color = cols[0] if cols.size() > 0 else Color(0.55, 0.52, 0.5)
	_mat.set_shader_parameter("color_a", c0)
	_mat.set_shader_parameter("color_b", cols[1] if cols.size() > 1 else c0.darkened(0.2))
	_mat.set_shader_parameter("color_c", cols[2] if cols.size() > 2 else c0.lightened(0.15))
	_mat.set_shader_parameter("mix_b", 0.0 if info.get("pure", false) else 0.35)
	_mat.set_shader_parameter("mix_c", 0.0 if info.get("pure", false) else 0.18)
	_mat.set_shader_parameter("perfect", 1.0 if info.get("perfect", false) else 0.0)
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_mat.set_shader_parameter("detail_nrm", AssetLib.tex("rubble", "nor_gl"))
	_visual.material_override = _mat
	_visual.scale = Vector3.ONE * size
	if info.get("lumpy", false):
		_visual.scale = Vector3(size * 1.08, size * 0.9, size * 1.02)
		_visual.rotation_degrees = Vector3(4, 7, -5)
	add_child(_visual)
	# Two steel strapping bands with crimp seals.
	if _strap_mesh == null:
		var parts: Array = []
		for side: Array in [[Vector3(0, 0, 0.505), Vector3(1.02, 1.02, 0.012)], [Vector3(0, 0, -0.505), Vector3(1.02, 1.02, 0.012)]]:
			pass
		for x: float in [-0.25, 0.25]:
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 1.025, 0.012)), ProcMesh.xf(Vector3(x, 0, 0.506))))
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 1.025, 0.012)), ProcMesh.xf(Vector3(x, 0, -0.506))))
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.012, 1.025)), ProcMesh.xf(Vector3(x, 0.506, 0))))
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.012, 1.025)), ProcMesh.xf(Vector3(x, -0.506, 0))))
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.07, 0.05, 0.02)), ProcMesh.xf(Vector3(x, 0.15, 0.51))))
		_strap_mesh = ProcMesh.merge(parts)
	var straps := MeshInstance3D.new()
	straps.mesh = _strap_mesh
	straps.material_override = Mats.metal("dark_steel")
	_visual.add_child(straps)
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
		GameState.inc_stat("cubes_fell")  # [beat] counted so long autoplay runs report it


func _on_body_entered(_body: Node) -> void:
	if carried or _land_cooldown > 0.0:
		return
	var speed: float = linear_velocity.length()
	if speed > 1.2:
		_land_cooldown = 0.15
		Audio.play("clunk", clampf(1.3 - size, 0.7, 1.2), linear_to_db(clampf(speed / 5.0, 0.15, 1.0)))
		Vfx.burst("dust", global_position - Vector3(0, size * 0.45, 0), Color(0.6, 0.55, 0.5, 0.5), 0.6)


func squish(_amount: float) -> void:
	pass  # Realism pass: bales don't squash; impacts are told by sound and dust.


func flash() -> void:
	_mat.set_shader_parameter("flash", 1.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.3)


## Switches between physical and carried (kinematic, no collision).
func set_carried(on: bool) -> void:
	carried = on
	if on:
		# Off the ground: a hauler's reservation no longer applies (Patch may grab a bale a
		# Haul Bug was heading for, and put it down somewhere else).
		set_meta("reserved", false)
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
		"dominant": str(info.get("dominant", "")), "volume": float(info.get("volume", 0.0)),
	}


static func from_dict(d: Dictionary) -> JunkCube:
	var cols: Array[Color] = []
	for h: Variant in d.get("colors", []):
		cols.append(Color.html(str(h)))
	var info_d: Dictionary = {
		"pure": d.get("pure", false), "perfect": d.get("perfect", false),
		"lumpy": d.get("lumpy", false), "fill": float(d.get("fill", 1.0)), "colors": cols,
		"dominant": str(d.get("dominant", "")),
	}
	# Only when saved: pre-fix saves fall back to fill * 12 in the recycler (0.0 would pay nothing).
	if d.has("volume") and float(d["volume"]) > 0.0:
		info_d["volume"] = float(d["volume"])
	return JunkCube.create(BigNum.from_serialized(d.get("value", [0.0, 0])), info_d)
