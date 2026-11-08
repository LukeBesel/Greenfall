extends Node3D
## [hero] Review renders of Lumi / Aurora against the owner's concept art.
##   --view=portrait : alone at the portrait's 3/4 angle and scale, warm side light, dark warm
##                     backdrop, left claw reaching for a can with the cyan pickup lasers.
##   --view=turn     : front, 3/4, side, back 3/4 and back (the turnaround layout), one PNG each.
##   --view=head / chest : close-ups (eyes and visor; chest plate and claws), portrait lighting.
##   --view=hands    : both claws in the portrait pose, framed between them.
##   --view=blink    : head close-up, a blink at phase 0 (open), 50 ms (closing), 90 ms (shut), 170 ms (opening).
##   --out=screenshots/hero/x  (writes <out>.png or <out>_N.png), --eyes=crescent|round|happy|bar|heart
## Run (software Vulkan is slow, keep the settle time):
##   xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --rendering-driver vulkan --resolution 1280x800 \
##     res://scenes/hero_preview.tscn -- --fresh --view=portrait --out=screenshots/hero/portrait

var _model: PatchModel
var _cam: Camera3D
var _view: String
var _out: String
var _shots: Array = []
var _i: int = -1
var _t: float = 0.0
var _can: Node3D
var _lasers: Array[MeshInstance3D] = []
var _settle: float = 8.0
const BLINK_PHASES := [-1.0, 0.05, 0.09, 0.17]


func _ready() -> void:
	process_priority = 100  # after PatchModel's own _process, so the pose override sticks
	_view = DevHooks.get_s("view", "portrait")
	_out = DevHooks.get_s("out", "screenshots/hero/" + _view)
	_settle = DevHooks.get_f("settle", 8.0)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	# Close-ups use the portrait's warm set too.
	var portrait: bool = _view in ["portrait", "head", "chest", "hands"]
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	if portrait:
		sm.sky_top_color = Color(0.1, 0.06, 0.04)
		sm.sky_horizon_color = Color(0.5, 0.27, 0.13)
		sm.ground_horizon_color = Color(0.42, 0.24, 0.12)
		sm.ground_bottom_color = Color(0.06, 0.04, 0.03)
		sm.sun_angle_max = 30.0
	else:
		sm.sky_top_color = Color(0.06, 0.06, 0.065)
		sm.sky_horizon_color = Color(0.2, 0.17, 0.15)
		sm.ground_horizon_color = Color(0.14, 0.12, 0.11)
		sm.ground_bottom_color = Color(0.04, 0.04, 0.045)
	sm.sky_energy_multiplier = 1.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55 if portrait else 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	if portrait:
		env.fog_enabled = true
		env.fog_light_color = Color(0.55, 0.32, 0.16)
		env.fog_density = 0.022
		env.fog_sky_affect = 0.0
	if not portrait:
		env.background_mode = Environment.BG_COLOR  # plain dark studio backdrop; the sky still lights/reflects
		env.background_color = Color(0.07, 0.065, 0.065)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Warm side key (from the viewer's left, a little behind), a warm back rim and a cool soft fill.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.68, 0.42) if portrait else Color(1.0, 0.86, 0.74)
	key.light_energy = 2.6 if portrait else 1.7
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	add_child(key)
	key.look_at_from_position(Vector3(3.0, 2.2, 0.7), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.6, 0.32) if portrait else Color(0.7, 0.85, 1.0)
	rim.light_energy = 2.6 if portrait else 0.8
	rim.light_specular = 1.2
	add_child(rim)
	rim.look_at_from_position(Vector3(-1.5, 2.6, 3.0), Vector3.ZERO, Vector3.UP)  # [hero v2] sun behind and above (concept)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = 0.35
	add_child(fill)
	fill.look_at_from_position(Vector3(-2.5, 0.8, -3.0), Vector3.ZERO, Vector3.UP)
	# Ground: dusty dirt (portrait) or a dark studio floor (turnaround).
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	if portrait:
		pm.material = AssetLib.pbr_material("road_damaged", 8.0)
	else:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.05, 0.05, 0.055)
		gm.roughness = 0.35
		pm.material = gm
	ground.mesh = pm
	add_child(ground)
	if portrait:
		for spec: Array in [["old_tyre", Vector3(2.4, 0.08, 4.0)], ["trashbag", Vector3(-2.8, 0, 5.0)], ["can_rusted", Vector3(1.2, 0, 2.2)], ["plastic_bottle_gallon", Vector3(-1.6, 0, 3.4)]]:
			if not AssetLib.has_model(spec[0]):
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = AssetLib.model_mesh(spec[0])
			mi.position = spec[1]
			if spec[0] == "old_tyre":
				mi.rotation_degrees = Vector3(90, 20, 0)
			add_child(mi)
	_model = PatchModel.new()
	_model.preview_variant = "aurora"
	add_child(_model)
	_model.set_happy(0.5)
	var eyes: String = DevHooks.get_s("eyes", "")
	if eyes != "":
		_model.set_eye_shape(eyes)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	if _view == "portrait":  # [hero v2] (was `portrait`, which swallowed the head/chest close-ups)
		_cam.fov = 30.0
		# [hero v2] The concept looks down on him a little (the crown and fin read against the sky).
		var a: float = deg_to_rad(31.0)
		var d: float = 2.6
		_shots = [[Vector3(sin(a) * d, 1.5, -cos(a) * d), Vector3(-0.14, 0.72, -0.05)]]
		var cam_attr := CameraAttributesPractical.new()
		cam_attr.dof_blur_far_enabled = true
		cam_attr.dof_blur_far_distance = 4.0
		cam_attr.dof_blur_far_transition = 3.0
		cam_attr.dof_blur_amount = 0.08
		_cam.attributes = cam_attr
		_build_can_and_lasers()
	elif _view == "head":
		_cam.fov = 26.0
		var ah: float = deg_to_rad(34.0)
		_shots = [[Vector3(sin(ah) * 2.15, 1.25, -cos(ah) * 2.15), Vector3(-0.04, 0.84, -0.05)]]
		_build_can_and_lasers()
	elif _view == "hands":
		# [hero v2] Close-up of the reaching claw (framed on it in _set_view, after the pose).
		_cam.fov = 26.0
		_shots = [[Vector3.ZERO, Vector3.ZERO]]
		_build_can_and_lasers()
	elif _view == "chest":
		_cam.fov = 28.0
		var ac: float = deg_to_rad(24.0)
		_shots = [[Vector3(sin(ac) * 1.35, 0.55, -cos(ac) * 1.35), Vector3(-0.02, 0.38, -0.1)]]
		_build_can_and_lasers()
	elif _view == "blink":
		_cam.fov = 18.0
		for k: int in BLINK_PHASES.size():
			_shots.append([Vector3(0.35, 1.0, -2.6), Vector3(0, 0.84, 0)])
	else:
		_cam.fov = 22.0
		var d2: float = 4.6
		var h: float = 0.92
		var tgt := Vector3(0, 0.62, 0)
		for deg: float in [0.0, 40.0, 90.0, 140.0, 180.0]:
			var r: float = deg_to_rad(deg)
			_shots.append([Vector3(sin(r) * d2, h, -cos(r) * d2), tgt])


func _build_can_and_lasers() -> void:
	_can = Node3D.new()
	add_child(_can)
	if AssetLib.has_model("can_rusted"):
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh("can_rusted")
		mi.rotation_degrees = Vector3(-35, 30, 60)
		_can.add_child(mi)
	_can.position = Vector3(-0.95, 0.95, -0.72)
	var glow: Color = PatchModel.glow_of("aurora")
	for k: int in 3:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0022
		c.bottom_radius = 0.0035
		c.height = 1.0
		c.radial_segments = 6
		m.mesh = c
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = glow.lightened(0.25)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color.a = 0.8
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_lasers.append(m)
	var l := OmniLight3D.new()
	l.light_color = glow
	l.light_energy = 0.5
	l.omni_range = 0.35
	l.name = "ClawLight"
	add_child(l)


func _pose() -> void:
	if _view == "blink":
		_model._blink_timer = 100.0
		var ph: float = BLINK_PHASES[clampi(_i, 0, BLINK_PHASES.size() - 1)]
		(_model.get("_face_mat") as ShaderMaterial).set_shader_parameter("blink", PatchModel.blink_curve(ph))
		return
	if not _view in ["portrait", "head", "chest", "hands"]:
		return
	_model._blink_timer = 100.0  # no random blink in a review shot
	_model._blink_t = -1.0
	# [hero v2] Flying pose of the portrait: pitched forward and leaning toward the can.
	_model.rotation_degrees = Vector3(-6.0, 0.0, 7.0)
	var arm_r: Node3D = _model.get("_arm_r")
	arm_r.rotation = Vector3(0.05, 0.1, 1.05)
	(arm_r.get_meta("elbow") as Node3D).rotation = Vector3(0.35, 0.0, 0.0)
	# Left arm raised and reaching toward the can (the portrait's beam arm), claws open.
	var arm: Node3D = _model.get("_arm_l")
	arm.rotation = Vector3(0.35, 0.3, -1.1)
	var el: Node3D = arm.get_meta("elbow")
	el.rotation = Vector3(0.25, 0.0, 0.0)
	for f: Node3D in _model.get("_claws"):
		var dir: Vector2 = f.get_meta("dir")
		f.rotation = Vector3(-dir.y, dir.x, 0) * 0.5
	var a: Vector3 = _model.claw_point_l()
	(get_node("ClawLight") as OmniLight3D).global_position = a
	for k: int in _lasers.size():
		var b: Vector3 = _can.global_position + Vector3(0.0, (k - 1) * 0.025, (k - 1) * 0.02)
		var d: Vector3 = b - a
		var y: Vector3 = d.normalized()
		var x: Vector3 = y.cross(Vector3.UP).normalized()
		var z: Vector3 = x.cross(y)
		_lasers[k].global_transform = Transform3D(Basis(x, y * d.length(), z), a + d * 0.5)


func _process(delta: float) -> void:
	_t += delta
	_pose()
	if _i < 0:
		_set_view(0)
		if _t < _settle:
			return
		_i = 0
		_t = 0.0
	if _i >= _shots.size():
		get_tree().quit()
		return
	_set_view(_i)
	if _t > 1.5:
		var path: String = "%s.png" % _out if _shots.size() == 1 else "%s_%d.png" % [_out, _i]
		DevHooks.save_viewport(path)
		_i += 1
		_t = 0.0


func _set_view(i: int) -> void:
	var v: Array = _shots[i]
	if _view == "hands":
		var c: Vector3 = _model.claw_point_l()
		var r: Vector3 = _model.claw_point()
		_cam.position = (c + r) * 0.5 + Vector3(0.35, 0.25, -1.55)
		_cam.look_at((c + r) * 0.5 + Vector3(0.0, -0.02, 0.0), Vector3.UP)
		return
	_cam.position = v[0]
	_cam.look_at(v[1], Vector3.UP)
