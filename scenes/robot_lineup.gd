extends Node3D
## Robot lineup renderer: all helper variants (Scoopie + Haul Bug x Mk I-IV) in a row on a road,
## with Patch at the end for scale. Saves a wide shot and close shots per tier.
##   godot --path . --rendering-driver vulkan res://scenes/robot_lineup.tscn -- --fresh [--out=screenshots/robots_v2]

const LOOKS: Array[String] = ["salvage", "restored", "modern", "hover"]

var _cam: Camera3D
var _views: Array = []
var _i: int = -1
var _t: float = 0.0
var _out: String
var _visuals: Array[RobotVisual] = []
var _beam_bot: RobotVisual
var _can: Node3D


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/robots_v2")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.turbidity = 10.0
	sm.mie_coefficient = 0.008
	sm.mie_color = Color(0.86, 0.75, 0.62)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssil_enabled = true
	env.sdfgi_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.8, 0.72, 0.65)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -150, 0)
	sun.light_energy = 2.3
	sun.light_color = Color(1.0, 0.9, 0.78)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.material = AssetLib.pbr_material("road_damaged", 8.0)
	ground.mesh = pm
	add_child(ground)

	var x: float = 4.9
	for look: String in LOOKS:
		for type_id: String in ["scoopie", "haulbug"]:
			var holder := Node3D.new()
			holder.position = Vector3(x, 0.05 if look == "hover" else 0.0, 0)
			holder.rotation_degrees.y = -20.0
			add_child(holder)
			var v := RobotVisual.new()
			holder.add_child(v)
			v.build(type_id, look)
			_visuals.append(v)
			if type_id == "haulbug" and look in ["restored", "hover"]:
				_add_bale(holder, v.fork_point)
			elif look == "hover":
				_beam_bot = v
			x -= 1.4
	# The beam target: a rusted can lifted in front of the Mk IV Scoopie.
	if _beam_bot:
		_can = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh("can_rusted")
		_can.add_child(mi)
		_beam_bot.get_parent().add_child(_can)
		_can.position = Vector3(0, 0.35, -1.0)
	# Patch for scale.
	if ResourceLoader.exists("res://player/patch_model.gd"):
		var scr: GDScript = load("res://player/patch_model.gd")
		if scr and scr.can_instantiate():
			var patch: Node3D = scr.new()
			patch.position = Vector3(6.4, 0, 0)
			patch.rotation_degrees.y = -20.0
			add_child(patch)
	for spec: Array in [["old_tyre", Vector3(5.6, 0.08, -1.2)], ["trashbag", Vector3(-6.2, 0, 0.6)], ["plastic_bottle_gallon", Vector3(2.8, 0, -1.0)], ["can_rusted", Vector3(0.0, 0, -1.1)]]:
		var m := MeshInstance3D.new()
		m.mesh = AssetLib.model_mesh(spec[0])
		m.position = spec[1]
		if spec[0] == "old_tyre":
			m.rotation_degrees = Vector3(90, 0, 0)
		add_child(m)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.current = true
	_views = [
		["wide", Vector3(-0.2, 2.6, -9.0), Vector3(0.2, 0.5, 0), 45.0],
		["mk1", Vector3(3.2, 1.35, -2.7), Vector3(4.2, 0.55, 0), 40.0],
		["mk2", Vector3(0.4, 1.35, -2.7), Vector3(1.4, 0.55, 0), 40.0],
		["mk3", Vector3(-2.4, 1.35, -2.7), Vector3(-1.4, 0.6, 0), 40.0],
		["mk4", Vector3(-5.2, 1.5, -3.0), Vector3(-4.2, 0.75, 0), 40.0],
		["scale", Vector3(5.0, 1.0, -2.3), Vector3(5.6, 0.45, 0), 42.0],
	]


func _add_bale(holder: Node3D, at: Vector3) -> void:
	var b := Node3D.new()
	b.position = at + Vector3(0, 0.25, 0)
	holder.add_child(b)
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.rounded_box(Vector3(0.5, 0.5, 0.5), 0.03, 2)
	body.material_override = Mats.worn_paint(Color(0.45, 0.42, 0.38), 0.45, 0.85, 3.0, 0.7)
	b.add_child(body)
	# Crushed bits poking out of the faces.
	var cols: Array[Color] = [Color(0.2, 0.4, 0.8), Color(0.85, 0.2, 0.15), Color(0.9, 0.88, 0.8), Color(0.2, 0.6, 0.3), Color(0.95, 0.7, 0.1)]
	for i: int in 14:
		var bit := MeshInstance3D.new()
		bit.mesh = ProcMesh.box(Vector3(randf_range(0.06, 0.16), randf_range(0.03, 0.08), 0.02))
		bit.material_override = Mats.worn_paint(cols[i % cols.size()], 0.8, 0.5, float(i), 0.5)
		var face: int = i % 4
		var off := Vector3(randf_range(-0.18, 0.18), randf_range(-0.18, 0.18), 0.25)
		bit.position = off.rotated(Vector3.UP, face * PI * 0.5)
		bit.rotation = Vector3(0, face * PI * 0.5, randf_range(-0.6, 0.6))
		b.add_child(bit)
	for y: float in [-0.13, 0.13]:
		var s := MeshInstance3D.new()
		s.mesh = ProcMesh.box(Vector3(0.515, 0.025, 0.515))
		s.material_override = Mats.rubber(Color(0.1, 0.1, 0.11))
		s.position = Vector3(0, y, 0)
		b.add_child(s)


func _process(delta: float) -> void:
	for v: RobotVisual in _visuals:
		v.animate(0.0, false, delta)
	if _beam_bot and _can:
		_can.rotation += Vector3(0.6, 0.9, 0.3) * delta
		_can.position.y = 0.35 + sin(Time.get_ticks_msec() * 0.002) * 0.05
		_beam_bot.beam_to(_can.global_position)
	_t += delta
	if _i < 0:
		if _t < 6.0:
			_set_view(0)
			return
		_i = 0
		_t = 0.0
	if _i >= _views.size():
		get_tree().quit()
		return
	_set_view(_i)
	if _t > 1.2:
		DevHooks.save_viewport("%s_%s.png" % [_out, _views[_i][0]])
		_i += 1
		_t = 0.0


func _set_view(i: int) -> void:
	var v: Array = _views[i]
	_cam.fov = v[3]
	_cam.position = v[1]
	_cam.look_at(v[2], Vector3.UP)
