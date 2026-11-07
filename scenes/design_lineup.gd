extends Node3D
## Lineup renderer for Lumi's six designs (systems/designs.gd), side by side on the turnaround set.
##   godot --path . res://scenes/design_lineup.tscn -- --fresh --out=screenshots/designs
## Writes <out>_0.png (front 3/4), _1.png (back 3/4), _2.png (side, ears vs eyes check).

var _cam: Camera3D
var _views: Array = []
var _i: int = -1
var _t: float = 0.0
var _out: String


func _ready() -> void:
	_out = DevHooks.get_s("out", "screenshots/designs")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.turbidity = 12.0
	sm.mie_coefficient = 0.01
	sm.mie_color = Color(0.86, 0.72, 0.6)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_light_color = Color(0.75, 0.66, 0.58)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 1.3
	rim.light_color = Color(0.65, 0.85, 1.0)
	rim.light_specular = 1.2
	add_child(rim)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.material = AssetLib.pbr_material("road_damaged", 8.0)
	ground.mesh = pm
	add_child(ground)
	var ids: Array[String] = Designs.ids()
	var gap: float = 1.25
	for k: int in ids.size():
		var m := PatchModel.new()
		m.preview_variant = ids[k]
		m.position = Vector3(((ids.size() - 1) * 0.5 - k) * gap, 0.0, 0.0)  # Aurora on the left seen from the front
		m.rotation.y = 0.35
		add_child(m)
		var l := Label3D.new()
		l.text = "%s\n%s" % [tr(str(Designs.def(ids[k]).get("name", ""))).to_upper(), tr(str(Designs.def(ids[k]).get("tagline", "")))]
		l.font_size = 40
		l.pixel_size = 0.0022
		l.modulate = PatchModel.glow_of(ids[k]).lightened(0.4)
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.7)
		l.position = m.position + Vector3(0, 1.62, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 30
		l.set_meta("label", true)
		add_child(l)
	_cam = Camera3D.new()
	_cam.fov = 36.0
	add_child(_cam)
	_cam.current = true
	_views = [
		[Vector3(0.9, 1.35, -5.6), Vector3(0, 0.78, 0)],   # front 3/4
		[Vector3(-1.2, 1.5, 5.6), Vector3(0, 0.7, 0)],     # back 3/4
		[Vector3(9.5, 1.1, -1.2), Vector3(0, 0.62, 0)],    # side, down the row
	]


func _process(delta: float) -> void:
	_t += delta
	if _i < 0:
		if _t < 7.0:  # shaders settle; idle props (holo, case) come out after a few seconds
			_set_view(0)
			return
		_i = 0
		_t = 0.0
	if _i >= _views.size():
		get_tree().quit()
		return
	_set_view(_i)
	if _t > 1.5:
		DevHooks.save_viewport("%s_%d.png" % [_out, _i])
		_i += 1
		_t = 0.0


func _set_view(i: int) -> void:
	var v: Array = _views[i]
	_cam.position = v[0]
	_cam.look_at(v[1], Vector3.UP)
	for c: Node in get_children():
		if c is Label3D:
			(c as Label3D).visible = i == 0
