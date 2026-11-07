class_name Wildlife
extends Node3D
## Life returns to restored hexes: butterflies flutter over flowers, birds circle overhead, and
## birdsong rises with the number of restored hexes. Simple wander behaviors, cheap meshes.

const MAX_BUTTERFLIES_PER_HEX: int = 6
const BUTTERFLY_COLORS: Array[Color] = [Color(1.0, 0.65, 0.15), Color(0.95, 0.95, 0.85), Color(0.35, 0.55, 1.0), Color(1.0, 0.85, 0.2), Color(0.85, 0.4, 0.7)]

var world: Node
var _flies: Array[Dictionary] = []
var _birds: Array[Dictionary] = []
var _song_t: float = 0.0
var _wing_mesh: ArrayMesh
var _wings: MultiMeshInstance3D  # [deck]
var _bird_mat: StandardMaterial3D


func setup() -> void:
	_wing_mesh = _make_wing()
	EventBus.hex_restored.connect(_on_restored)
	# [wild] Butterflies already flutter over Growing hexes (a few; more when the hex is restored).
	EventBus.hex_level_changed.connect(func(hid: int, lvl: int) -> void:
		if lvl == 3:
			add_butterflies(hid, 3))
	var hl: Node = world.get("hex_levels")
	if hl:
		for hid: Variant in hl.get("levels"):
			if int(hl.get("levels")[hid]) == 3:
				add_butterflies(int(hid), 3)
	for hid: Variant in world.garden.hex_life:
		if float(world.garden.hex_life[hid]) >= 0.8:
			_on_restored(int(hid))


func _make_wing() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [Vector3(0, 0, 0), Vector3(0.05, 0, -0.03), Vector3(0.05, 0, 0.035), Vector3(0, 0, 0), Vector3(0.05, 0, 0.035), Vector3(0.02, 0, 0.05)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
	return st.commit()


func _on_restored(hid: int) -> void:
	var c: Vector3 = world.field.hex_center(hid)
	for i: int in MAX_BUTTERFLIES_PER_HEX:
		var pos: Vector3 = c + Vector3(randf_range(-6, 6), randf_range(0.4, 1.2), randf_range(-6, 6))
		_flies.append({"pos": pos, "basis": Basis.IDENTITY, "home": c, "target": pos, "phase": randf() * TAU,
			"col": BUTTERFLY_COLORS[randi() % BUTTERFLY_COLORS.size()]})
	_sync_wings()
	if _birds.size() < 8 and randf() < 0.6:
		var bird := MeshInstance3D.new()
		bird.mesh = _wing_mesh
		if _bird_mat == null:
			_bird_mat = StandardMaterial3D.new()
			_bird_mat.albedo_color = Color(0.15, 0.15, 0.18)
			_bird_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bird.material_override = _bird_mat
		bird.scale = Vector3(6, 6, 6)
		add_child(bird)
		_birds.append({"node": bird, "center": c, "r": randf_range(12, 25), "h": randf_range(14, 22), "a": randf() * TAU, "s": randf_range(0.25, 0.4)})


## [wild] A few butterflies over a hex (Growing hexes; restored ones get the full set above).
func add_butterflies(hid: int, n: int) -> void:
	var c: Vector3 = world.field.hex_center(hid)
	for i: int in n:
		var pos: Vector3 = c + Vector3(randf_range(-5, 5), randf_range(0.4, 1.1), randf_range(-5, 5))
		_flies.append({"pos": pos, "basis": Basis.IDENTITY, "home": c, "target": pos, "phase": randf() * TAU,
			"col": BUTTERFLY_COLORS[randi() % BUTTERFLY_COLORS.size()]})
	_sync_wings()


## [deck] All butterfly wings are one MultiMesh (two instances per butterfly, colour per
## instance): one draw instead of two nodes and a material per butterfly.
func _sync_wings() -> void:
	if _wings == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.6
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _wing_mesh
		_wings = MultiMeshInstance3D.new()
		_wings.name = "Butterflies"
		_wings.multimesh = mm
		_wings.material_override = mat
		add_child(_wings)
	var mmw: MultiMesh = _wings.multimesh
	if mmw.instance_count != _flies.size() * 2:
		mmw.instance_count = _flies.size() * 2
		for k: int in _flies.size():
			mmw.set_instance_color(k * 2, _flies[k]["col"])
			mmw.set_instance_color(k * 2 + 1, _flies[k]["col"])
	_wings.custom_aabb = AABB(Vector3(-400, -20, -400), Vector3(800, 80, 800))


func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var mmw: MultiMesh = _wings.multimesh if _wings else null
	for k: int in _flies.size():
		var f: Dictionary = _flies[k]
		var pos: Vector3 = f["pos"]
		var target: Vector3 = f["target"]
		if pos.distance_to(target) < 0.3:
			var home: Vector3 = f["home"]
			f["target"] = home + Vector3(randf_range(-7, 7), randf_range(0.3, 1.4), randf_range(-7, 7))
		var dir: Vector3 = (target - pos).normalized()
		pos += (dir * 1.1 + Vector3(0, sin(t * 6.0 + float(f["phase"])) * 0.6, 0)) * delta
		f["pos"] = pos
		var fwd := Vector3(dir.x, 0, dir.z) + Vector3(0.001, 0, 0)
		var b: Basis = Basis.looking_at(fwd, Vector3.UP)
		var flap: float = sin(t * 28.0 + float(f["phase"])) * 1.1
		if mmw:
			mmw.set_instance_transform(k * 2, Transform3D(b * Basis(Vector3.BACK, flap) * Basis.from_scale(Vector3(-1, 1, 1)), pos))
			mmw.set_instance_transform(k * 2 + 1, Transform3D(b * Basis(Vector3.BACK, -flap), pos))
	for b: Dictionary in _birds:
		b["a"] = float(b["a"]) + delta * float(b["s"])
		var c: Vector3 = b["center"]
		var a: float = b["a"]
		var bn: MeshInstance3D = b["node"]
		bn.position = c + Vector3(cos(a) * float(b["r"]), float(b["h"]) + sin(a * 3.0), sin(a) * float(b["r"]))
		bn.rotation = Vector3(0, -a, sin(t * 9.0 + a) * 0.6)
	# Birdsong density follows restoration.
	if not _birds.is_empty():
		_song_t -= delta
		if _song_t <= 0.0:
			_song_t = randf_range(1.5, 6.0) / sqrt(float(_birds.size()))
			Audio.play("bird", randf_range(0.85, 1.25), -16.0, 0.0)
