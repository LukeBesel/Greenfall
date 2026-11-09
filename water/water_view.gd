class_name WaterView
extends Node3D
## Lake surfaces for water hexes, fish that jump in clear water, and the lake-clear moment.

var world: Node
var _mat: ShaderMaterial
var _fish: Array[Dictionary] = []
var _fish_mesh: Mesh


func setup() -> void:
	var f: HexField = world.field
	var any: bool = false
	for id: int in f.hex_count():
		if f.is_water(id):
			any = true
	if not any:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/water.gdshader")
	_mat.set_shader_parameter("state_tex", world.view.state_texture())
	_mat.set_shader_parameter("wave_nrm", AssetLib.tex("rubble", "nor_gl"))
	_mat.set_shader_parameter("grid_radius", f.radius)
	_mat.set_shader_parameter("hex_size", f.hex_size)
	# [vqa] Natural shorelines everywhere (not only frontiers): the lake edge and its lakebed use the
	# same noise-warped border as the ground and the junk, so no straight hex lines at the water.
	var gm: ShaderMaterial = world.view.ground_material if world.view.get("ground_material") != null else null
	if gm and f.natural_borders:
		for k: String in ["warp_tex", "warp_size", "warp_amp"]:
			_mat.set_shader_parameter(k, gm.get_shader_parameter(k))
		gm.set_shader_parameter("lake_warp", 1.0)
	var plane := PlaneMesh.new()
	var ext: float = (f.radius * 2 + 2) * f.hex_size * 1.8
	plane.size = Vector2(ext, ext)
	plane.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position.y = HexField.WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_fish_mesh = ProcMesh.capsule(0.05, 0.28)
	EventBus.hex_cleaned.connect(_on_clean)
	for id: int in f.hex_count():
		if f.is_water(id) and f.is_clean(id):
			_stock_fish(id)


func _process(_delta: float) -> void:
	if _mat:
		_mat.set_shader_parameter("time_now", world.view.clock)
		_mat.set_shader_parameter("clarity_bonus", Economy.stat("lake_clarity"))
	var t: float = Time.get_ticks_msec() * 0.001
	for fish: Dictionary in _fish:
		var n: MeshInstance3D = fish["node"]
		var ph: float = fmod(t * float(fish["speed"]) + float(fish["phase"]), 6.0)
		if ph < 1.0:
			var a: Vector3 = fish["a"]
			var b: Vector3 = fish["b"]
			n.visible = true
			n.global_position = a.lerp(b, ph) + Vector3(0, sin(ph * PI) * 0.9, 0)
			n.rotation = Vector3(0, atan2(b.x - a.x, b.z - a.z), cos(ph * PI) * 1.2)
			# One splash per jump: the shared soil pool only has Vfx.POOL_PER_KIND emitters.
			if ph >= 0.97 and not bool(fish.get("splashed", false)):
				fish["splashed"] = true
				Vfx.burst("soil", b + Vector3(0, 0.1, 0), Color(0.7, 0.85, 1.0, 0.8), 0.4)
		else:
			n.visible = false
			if ph > 5.9:
				_new_jump(fish)


func _on_clean(hid: int, _pos: Vector3, _bonus: BigNum) -> void:
	if not world.field.is_water(hid):
		return
	Audio.play("chime", 0.6, -2.0)
	Audio.play("whoosh", 0.4, -6.0)
	EventBus.shake_requested.emit(0.1)
	if Once.take("wren_lake_clear"):  # [v4calm] item 45
		world.wren.line_started.emit(tr("The water... I can see the bottom. Lumi, there's something moving down there."), 1)
	_stock_fish(hid)


func _stock_fish(hid: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.78, 0.8)
	mat.metallic = 0.6
	mat.roughness = 0.3
	for i: int in 4:
		var n := MeshInstance3D.new()
		n.mesh = _fish_mesh
		n.material_override = mat
		n.visible = false
		add_child(n)
		var fish: Dictionary = {"node": n, "hex": hid, "speed": randf_range(0.6, 1.1), "phase": randf() * 6.0}
		_new_jump(fish)
		_fish.append(fish)


func _new_jump(fish: Dictionary) -> void:
	var c: Vector3 = world.field.hex_center(int(fish["hex"]))
	var a := c + Vector3(randf_range(-6, 6), HexField.WATER_Y, randf_range(-6, 6))
	var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, 2.0)
	fish["a"] = a
	fish["b"] = a + d
	fish["splashed"] = false
