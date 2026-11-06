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


func setup() -> void:
	_wing_mesh = _make_wing()
	EventBus.hex_restored.connect(_on_restored)
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
		var node := Node3D.new()
		add_child(node)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BUTTERFLY_COLORS[randi() % BUTTERFLY_COLORS.size()]
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.6
		var wings: Array[MeshInstance3D] = []
		for side: float in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			w.mesh = _wing_mesh
			w.material_override = mat
			w.scale = Vector3(side, 1, 1)
			node.add_child(w)
			wings.append(w)
		node.position = c + Vector3(randf_range(-6, 6), randf_range(0.4, 1.2), randf_range(-6, 6))
		_flies.append({"node": node, "wings": wings, "home": c, "target": node.position, "phase": randf() * TAU})
	if _birds.size() < 8 and randf() < 0.6:
		var bird := MeshInstance3D.new()
		bird.mesh = _wing_mesh
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.15, 0.15, 0.18)
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bird.material_override = bm
		bird.scale = Vector3(6, 6, 6)
		add_child(bird)
		_birds.append({"node": bird, "center": c, "r": randf_range(12, 25), "h": randf_range(14, 22), "a": randf() * TAU, "s": randf_range(0.25, 0.4)})


func _process(delta: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	for f: Dictionary in _flies:
		var n: Node3D = f["node"]
		var target: Vector3 = f["target"]
		if n.position.distance_to(target) < 0.3:
			var home: Vector3 = f["home"]
			f["target"] = home + Vector3(randf_range(-7, 7), randf_range(0.3, 1.4), randf_range(-7, 7))
		var dir: Vector3 = (target - n.position).normalized()
		n.position += (dir * 1.1 + Vector3(0, sin(t * 6.0 + float(f["phase"])) * 0.6, 0)) * delta
		n.look_at(n.position + Vector3(dir.x, 0, dir.z) + Vector3(0.001, 0, 0), Vector3.UP)
		var flap: float = sin(t * 28.0 + float(f["phase"])) * 1.1
		var wings: Array = f["wings"]
		(wings[0] as MeshInstance3D).rotation.z = flap
		(wings[1] as MeshInstance3D).rotation.z = -flap
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
