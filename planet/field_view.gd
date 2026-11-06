class_name FieldView
extends Node3D
## Presentation of a HexField: restoration ground + MultiMesh junk (one MultiMesh per shape)
## + a decorative junk-mountain horizon. Reads the sim; never owns game state.

var field: HexField
var clock: float = 0.0

var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _state_img: Image
var _state_tex: ImageTexture
var _mm_by_shape: Dictionary = {}  # shape -> MultiMeshInstance3D
var _piece_slot := PackedInt32Array()  # pid -> instance index inside its shape's multimesh
var _dirty_tex: bool = false


func setup(p_field: HexField) -> void:
	field = p_field
	_build_ground()
	_build_junk()
	_build_horizon()
	for id: int in field.hex_count():
		_write_hex(id, -100.0)
	_flush()


func _process(delta: float) -> void:
	clock += delta
	if _ground_mat:
		_ground_mat.set_shader_parameter("time_now", clock)
	if _dirty_tex:
		_flush()


func _build_ground() -> void:
	var size: int = field.radius * 2 + 1
	_state_img = Image.create(size, size, false, Image.FORMAT_RGBAF)
	_state_tex = ImageTexture.create_from_image(_state_img)
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://art/shaders/ground.gdshader")
	_ground_mat.set_shader_parameter("state_tex", _state_tex)
	_ground_mat.set_shader_parameter("grid_radius", field.radius)
	_ground_mat.set_shader_parameter("hex_size", field.hex_size)
	var plane := PlaneMesh.new()
	var extent: float = (field.radius + 6) * field.hex_size * 2.2
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	plane.material = _ground_mat
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	_ground.mesh = plane
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)
	# Collision: a big static floor.
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(extent, 1.0, extent)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)


func _build_junk() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/junk.gdshader")
	var by_shape: Dictionary = {}
	for pid: int in field.piece_count():
		var s: String = field.piece_shape[pid]
		if not by_shape.has(s):
			by_shape[s] = PackedInt32Array()
		(by_shape[s] as PackedInt32Array).append(pid)
	_piece_slot.resize(field.piece_count())
	for s: String in by_shape:
		var pids: PackedInt32Array = by_shape[s]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = JunkMeshes.get_mesh(s)
		mm.instance_count = pids.size()
		for i: int in pids.size():
			var pid: int = pids[i]
			_piece_slot[pid] = i
			mm.set_instance_transform(i, piece_transform(pid) if field.piece_alive[pid] == 1 else _hidden())
			mm.set_instance_custom_data(i, field.piece_color[pid])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Junk_" + s
		mmi.multimesh = mm
		mmi.material_override = mat
		add_child(mmi)
		_mm_by_shape[s] = mmi


func piece_transform(pid: int) -> Transform3D:
	var b := Basis(Vector3.UP, field.piece_yaw[pid]).scaled(Vector3.ONE * field.piece_scale[pid])
	return Transform3D(b, field.piece_pos[pid])


func piece_mesh(pid: int) -> Mesh:
	return JunkMeshes.get_mesh(field.piece_shape[pid])


func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))


func hide_piece(pid: int) -> void:
	var mmi: MultiMeshInstance3D = _mm_by_shape[field.piece_shape[pid]]
	mmi.multimesh.set_instance_transform(_piece_slot[pid], _hidden())


func move_piece(pid: int, pos: Vector3) -> void:
	field.piece_pos[pid] = pos
	var mmi: MultiMeshInstance3D = _mm_by_shape[field.piece_shape[pid]]
	mmi.multimesh.set_instance_transform(_piece_slot[pid], piece_transform(pid))


## Call when a piece is removed (partial clean tint) or a hex flips (ripple from now).
func refresh_hex(id: int, flipped_now: bool = false) -> void:
	_write_hex(id, clock if flipped_now else -1.0)
	_dirty_tex = true


func _write_hex(id: int, flip_time: float) -> void:
	var a: Vector2i = field.hex_axial[id]
	var x: int = a.x + field.radius
	var y: int = a.y + field.radius
	var prev: Color = _state_img.get_pixel(x, y)
	var ft: float = prev.g if flip_time == -1.0 else flip_time
	_state_img.set_pixel(x, y, Color(field.removed_fraction(id), ft, float(field.hex_clean[id]), float(field.hex_hub[id])))


func _flush() -> void:
	_state_tex.update(_state_img)
	_dirty_tex = false


func set_focus_hex(id: int) -> void:
	var v: Vector2 = Vector2(9999, 9999) if id < 0 else Vector2(field.hex_axial[id])
	_ground_mat.set_shader_parameter("focus_axial", v)


func _build_horizon() -> void:
	# Soft junk mountains ringing the field: colorful lumps that read as "more to clean out there".
	var rng := RandomNumberGenerator.new()
	rng.seed = field.seed_value + 99
	var r0: float = (field.radius + 1.5) * field.hex_size * 1.75
	var palette: Array[Color] = [Color("#e8463c"), Color("#ff7eb6"), Color("#5ee6c8"), Color("#ffd23f"), Color("#9d7cff"), Color("#f2a03d"), Color("#4cc9f0")]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/toon.gdshader")
	mat.set_shader_parameter("albedo", Color(1, 1, 1))
	mat.set_shader_parameter("rust_amount", 0.35)
	mat.set_shader_parameter("rust_scale", 0.6)
	var parts: Array = []
	for i: int in 70:
		var ang: float = TAU * i / 70.0 + rng.randf_range(-0.03, 0.03)
		var dist: float = r0 + rng.randf_range(0.0, 22.0)
		var h: float = rng.randf_range(3.0, 11.0) * (1.0 + dist / r0 * 0.3)
		var w: float = rng.randf_range(7.0, 14.0)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var c: Color = palette[rng.randi() % palette.size()].lerp(Color(0.55, 0.42, 0.55), 0.45)
		parts.append(ProcMesh.part(ProcMesh.hemisphere(1.0, 12, 5), ProcMesh.xf(pos, Vector3(0, rng.randf() * 360.0, 0), Vector3(w, h, w * 0.8)), c))
		# A few big recognisable silhouettes poking out (tires, cans, a fridge).
		if rng.randf() < 0.35:
			var top := pos + Vector3(0, h * 0.8, 0)
			var kind: int = rng.randi() % 3
			var cc: Color = palette[rng.randi() % palette.size()]
			match kind:
				0: parts.append(ProcMesh.part(ProcMesh.torus(1.0, 2.2, 14, 6), ProcMesh.xf(top, Vector3(rng.randf_range(40, 90), rng.randf() * 360.0, 0)), Color(0.25, 0.23, 0.3)))
				1: parts.append(ProcMesh.part(ProcMesh.cyl(1.0, 1.0, 3.5, 10), ProcMesh.xf(top, Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(30, 80))), cc))
				_: parts.append(ProcMesh.part(ProcMesh.box(Vector3(2.5, 4.5, 2.2)), ProcMesh.xf(top, Vector3(rng.randf_range(-25, 25), rng.randf() * 360.0, rng.randf_range(-25, 25))), Color(0.92, 0.9, 0.86)))
	var mi := MeshInstance3D.new()
	mi.name = "JunkHorizon"
	mi.mesh = ProcMesh.merge(parts)
	mi.material_override = mat
	add_child(mi)
