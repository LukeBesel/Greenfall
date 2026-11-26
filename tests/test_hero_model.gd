extends GutTest
## [hero] The rebuilt Aurora model (art/models/aurora/aurora.glb, player/patch_model.gd): parts,
## anchors, eye shapes and the gameplay anchor points staying where pickups and baling expect them.


func _model() -> PatchModel:
	var m := PatchModel.new()
	m.preview_variant = "aurora"
	add_child_autofree(m)
	return m


func test_parts_and_recycle_icon() -> void:
	var m := _model()
	for p: String in ["body", "thruster", "hatch", "head", "antenna", "visor", "icon_recycle", "finger", "finger_tip",
			"arm_shoulder_r", "arm_elbow_r", "arm_wrist_r", "arm_shoulder_l", "arm_elbow_l", "arm_wrist_l"]:
		assert_true(PatchModel._parts.has(p), p)
	assert_not_null(m._icon_mesh, "Aurora's chest icon is the modelled recycling symbol")


func test_visor_face_material_only_on_front_surface() -> void:
	# Exactly one surface of the visor carries the face (eyes); its walls/back are plain glass.
	_model()
	var mesh: Mesh = PatchModel._parts["visor"]["mesh"]
	var faces: int = 0
	for i: int in mesh.get_surface_count():
		var mat: Material = mesh.surface_get_material(i)
		if mat and mat.resource_name == "face":
			faces += 1
	assert_eq(faces, 1)
	assert_true(mesh.get_surface_count() >= 2)


func test_anchors() -> void:
	var m := _model()
	for a: String in PatchModel.ANCHORS:
		assert_not_null(m.get_anchor(a), a)
	# hand_r is the claw tip the pickup lasers start from.
	assert_almost_eq(m.get_anchor("hand_r").global_position.distance_to(m.claw_point()), 0.0, 0.001)
	assert_almost_eq(m.get_anchor("hand_l").global_position.distance_to(m.claw_point_l()), 0.0, 0.001)
	assert_true(m.get_anchor("head_top").global_position.y > 1.1, "head_top sits on the crown")


func test_gameplay_points_near_previous_rig() -> void:
	var m := _model()
	m._process(0.0)
	var local: Vector3 = m.to_local(m.claw_point())
	# v2 idle pose: the arms reach out and a little up (portrait); the right claw tip sits out to
	# the side, in front, around torso height, where the pickup lasers start.
	assert_true(local.x > 0.3 and local.x < 0.6, "claw out to the side (%.2f)" % local.x)
	assert_true(local.z < -0.15, "claw in front (%.2f)" % local.z)
	assert_true(local.y > 0.25 and local.y < 0.6, "claw height %.2f" % local.y)
	var chest: Vector3 = m.to_local(m.chest_world())
	assert_true(chest.z < -0.2 and chest.y > 0.38 and chest.y < 0.5, "chest hopper on the plate")


func test_eye_shapes() -> void:
	var m := _model()
	for i: int in PatchModel.EYE_SHAPES.size():
		m.set_eye_shape(PatchModel.EYE_SHAPES[i])
		assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), i)
	m.set_eye_shape("nope")
	assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), PatchModel.EYE_SHAPES.size() - 1)


func test_blink_is_crisp() -> void:
	assert_eq(PatchModel.blink_curve(-1.0), 0.0)
	assert_true(PatchModel.blink_curve(0.035) < 0.5, "eases in")
	assert_eq(PatchModel.blink_curve(PatchModel.BLINK_CLOSE + 0.01), 1.0, "shut by ~70 ms")
	assert_true(PatchModel.BLINK_LEN < 0.3, "whole blink under 0.3 s")
	assert_eq(PatchModel.blink_curve(PatchModel.BLINK_LEN + 0.01), 0.0)
	var m := _model()
	m._blink_timer = 0.0
	var shut: bool = false
	for i: int in 30:
		m._process(0.01)
		shut = shut or float(m._face_mat.get_shader_parameter("blink")) > 0.99
	assert_true(shut, "a blink fully closes")
	assert_true(float(m._face_mat.get_shader_parameter("blink")) < 0.01 or m._blink_double, "and reopens")


func test_happy_face_never_parks_half_way() -> void:
	var m := _model()
	m.set_happy(0.9)
	for i: int in 30:
		m._process(0.02)
	assert_eq(float(m._face_mat.get_shader_parameter("happy")), 1.0)
	m.set_happy(0.5)
	for i: int in 30:
		m._process(0.02)
	assert_eq(float(m._face_mat.get_shader_parameter("happy")), 0.0)


func test_beacon_stays_on_the_head_through_animation() -> void:
	for id: String in PatchModel.VARIANTS:
		var m := PatchModel.new()
		m.preview_variant = id
		add_child_autofree(m)
		var beacon: Node3D = m.get_anchor("beacon")
		assert_not_null(beacon, id)
		var worst: float = 0.0
		for i: int in 180:
			var t: float = i / 60.0
			m.set_motion(3.0, 0.8, Vector2(sin(t * 3.0) * 8.0, cos(t * 2.0) * 8.0), 1.0 / 60.0)
			if i % 40 == 0:
				m.set_scooping(true)
			m.holding = i > 90 and i < 140
			m.look_toward(m.global_position + Vector3(sin(t) * 3.0, 0.5, -2.0))
			m.set_happy(1.0 if i > 120 else 0.5)
			m.squash(0.5)
			m._process(1.0 / 60.0)
			m.set_beacon(0.5 + 0.5 * sin(t * 10.0))
			var want: Vector3 = m._head.to_global(PatchModel.BEACON_LOCAL)
			worst = maxf(worst, beacon.get_child(0).global_position.distance_to(want))
		assert_true(worst < 0.02, "%s beacon within 2 cm of the fin (%.4f m)" % [id, worst])
		# And it really sits on the crown, not floating above or inside the head.
		var local: Vector3 = m._head.to_local(beacon.global_position)
		assert_almost_eq(local.y, PatchModel.BEACON_LOCAL.y, 0.01, id)


## The Locker's colours reach every part: each surface of every part in aurora.glb and designs.glb
## is named after a key of PatchModel._mats (an unknown name would render with the glb's own
## material, outside paint / trim / accent / side / glow). Replaces the old lumi_detail test.
func test_every_surface_maps_to_a_model_material() -> void:
	var m := _model()
	var seen: int = 0
	for path: String in [PatchModel.MODEL_PATH, PatchModel.DESIGNS_PATH]:
		var scene: PackedScene = load(path)
		assert_not_null(scene, path)
		var inst: Node = scene.instantiate()
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			assert_true(PatchModel._parts.has(str(mi.name)), "%s is in the part library" % mi.name)
			for i: int in mi.mesh.get_surface_count():
				var src: Material = mi.mesh.surface_get_material(i)
				var key: String = src.resource_name if src else ""
				assert_true(m._mats.has(key), "%s surface %d: material '%s' is a _mats key" % [mi.name, i, key])
				seen += 1
		inst.free()
	assert_gt(seen, 40, "both files were read")


func test_built_model_has_no_unassigned_surface() -> void:
	for id: String in PatchModel.VARIANTS:
		var m := PatchModel.new()
		m.preview_variant = id
		add_child_autofree(m)
		var shared: Array = m._mats.values() + m._acc_mats.values()
		var lib: Array = []
		for part: String in PatchModel._parts:
			lib.append(PatchModel._parts[part]["mesh"])
		var checked: int = 0
		for n: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			if not lib.has(mi.mesh):
				continue  # procedural bits carry their own material_override
			for i: int in mi.mesh.get_surface_count():
				var got: Material = mi.get_surface_override_material(i)
				assert_true(got != null and shared.has(got), "%s: %s surface %d uses a shared model material" % [id, mi.get_path(), i])
				checked += 1
		assert_gt(checked, 40, id)


## [art2] The side modules' housings take the Locker's "side" colour; the head shell does not.
func test_side_colour_reaches_the_ear_housings() -> void:
	var m := PatchModel.new()
	var st: Dictionary = LumiStyle.preset("aurora")
	LumiStyle.set_value(st, "side", Color(1.0, 0.2, 0.6))
	m.set_meta("lumi_style", st)
	add_child_autofree(m)
	var side: ShaderMaterial = m._mats["side"]
	var c: Color = side.get_shader_parameter("paint_color")
	assert_gt(c.r, c.g + 0.1, "the side material has the Locker's colour")
	var on_ears: int = 0
	var elsewhere: int = 0
	for n: Node in m.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(i) == side:
				if mi.mesh == PatchModel._parts["ears"]["mesh"]:
					on_ears += 1
				else:
					elsewhere += 1
	assert_gt(on_ears, 0, "the ears part uses the side material")
	assert_eq(elsewhere, 0, "only the ears use it")
	assert_ne((m._mats["dark"] as ShaderMaterial).get_shader_parameter("paint_color"), c, "joints keep the dark metal")


## The C ring with one dot is the default eye, inside the eye_shape system (never two shapes).
func test_default_eye_is_the_c_ring() -> void:
	var m := _model()
	assert_eq(PatchModel.EYE_SHAPES[0], "crescent")
	assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), 0)
	assert_gt(float(m._face_mat.get_shader_parameter("eye_radius")), 0.0, "native eyes drawn")
	assert_null(m._face_mat.next_pass, "no overlay eyes on top of the native ones")
	var src: String = (load("res://art/shaders/bot_face.gdshader") as Shader).code
	assert_true(src.contains("gap_dir") and src.contains("ring_inner"), "the default shape is a ring with a gap")
