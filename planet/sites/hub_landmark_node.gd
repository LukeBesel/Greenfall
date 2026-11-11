class_name HubLandmarkNode
extends Node3D
## [v6yard] One hub landmark in the scene (models: planet/sites/hub_landmarks.gd, data/landmarks.json).
## Holds the body mesh, the turning part (fan, wheel, radar) and its lights, and swaps them when the
## hub's level changes: level 1 broken and dark, 2 repaired, lit and turning, 3+ restored.
## Origin on the ground, front +Z.

var kind: String = ""
var planet: String = ""
var seed_i: int = 1
var state: String = ""
var powered: bool = false
var data: HubLandmarks.Data
var _body: MeshInstance3D
var _spin: MeshInstance3D
var _gondolas: Array[MultiMeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _angle: float = 0.0


func _ready() -> void:
	set_process(_turning())  # entering the tree switches _process on by itself


func _turning() -> bool:
	return powered and data != null and data.spin_speed != 0.0 and data.spin_mesh != null


func set_level(level: int) -> void:
	set_state(HubLandmarks.state_for_level(level))


func set_state(st: String) -> void:
	if st == state and data != null:
		return
	state = st
	powered = st != "broken"
	data = HubLandmarks.data_for(kind, st, seed_i, planet)
	if _body == null:
		_body = MeshInstance3D.new()
		_body.name = "Body"
		add_child(_body)
	_body.mesh = data.mesh
	KitMat.apply(_body, st, powered)
	for l: OmniLight3D in _lights:
		l.queue_free()
	_lights.clear()
	if powered:
		for ld: Dictionary in data.lights:
			var o := OmniLight3D.new()
			o.position = ld["pos"]
			o.light_color = ld["color"]
			o.omni_range = float(ld["range"])
			o.light_energy = float(ld["energy"])
			o.omni_attenuation = 1.4
			o.shadow_enabled = false
			o.distance_fade_enabled = true
			o.distance_fade_begin = 70.0
			o.distance_fade_length = 20.0
			add_child(o)
			_lights.append(o)
	if data.spin_mesh:
		if _spin == null:
			_spin = MeshInstance3D.new()
			_spin.name = "Spin"
			add_child(_spin)
		_spin.mesh = data.spin_mesh
		_spin.position = data.spin_at
		KitMat.apply(_spin, st, powered)
	for g: MultiMeshInstance3D in _gondolas:
		g.queue_free()
	_gondolas.clear()
	for k: int in data.gondola_meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = data.gondola_meshes[k]
		var count: int = 0
		for i: int in data.gondola_n:
			if i % data.gondola_meshes.size() == k and not data.gondola_skip.has(i):
				count += 1
		mm.instance_count = count
		var g := MultiMeshInstance3D.new()
		g.name = "Gondolas%d" % k
		g.multimesh = mm
		g.position = data.spin_at
		g.custom_aabb = AABB(Vector3.ONE * -(data.gondola_r + 3.0), Vector3.ONE * (data.gondola_r + 3.0) * 2.0)
		add_child(g)
		for s: int in data.gondola_meshes[k].get_surface_count():  # a MultiMesh draws the mesh's own materials
			data.gondola_meshes[k].surface_set_material(s, KitMat.for_key(data.gondola_meshes[k].surface_get_name(s), st, powered))
		_gondolas.append(g)
	_pose()
	set_process(_turning())


## Puts the turning part and the gondolas at the current angle (gondolas hang level).
func _pose() -> void:
	if _spin:
		_spin.basis = Basis(data.spin_axis, _angle)
	for k: int in _gondolas.size():
		var mm: MultiMesh = _gondolas[k].multimesh
		var j: int = 0
		for i: int in data.gondola_n:
			if i % _gondolas.size() != k or data.gondola_skip.has(i):
				continue
			var a: float = _angle + TAU * i / data.gondola_n
			mm.set_instance_transform(j, Transform3D(Basis(), Vector3(cos(a), sin(a), 0) * data.gondola_r))
			j += 1


func _process(delta: float) -> void:
	_angle = fposmod(_angle + data.spin_speed * delta, TAU)
	_pose()
