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
	# Previous rig: right claw tip about (0.34, 0.35, -0.33) in model space (hover bob included).
	assert_almost_eq(local.x, 0.335, 0.04)
	assert_almost_eq(local.z, -0.31, 0.06)
	assert_true(local.y > 0.25 and local.y < 0.45, "claw height %.2f" % local.y)
	var chest: Vector3 = m.to_local(m.chest_world())
	assert_true(chest.z < -0.2 and chest.y > 0.38 and chest.y < 0.5, "chest hopper on the plate")


func test_eye_shapes() -> void:
	var m := _model()
	for i: int in PatchModel.EYE_SHAPES.size():
		m.set_eye_shape(PatchModel.EYE_SHAPES[i])
		assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), i)
	m.set_eye_shape("nope")
	assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), PatchModel.EYE_SHAPES.size() - 1)
