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


func test_every_design_piece_is_modelled() -> void:
	# Each add-on a design names is either a mesh in the add-on library or one of the animated
	# held items / the companion, whose meshes must exist too.
	_model()
	var animated: Dictionary = {"gear": ["acc_gear"], "bottle": ["acc_bottle"], "case": ["acc_case"], "holo": ["acc_holo"], "butterfly": ["acc_bfly_body", "acc_wing"]}
	for id: String in PatchModel.VARIANTS:
		for a: String in PatchModel.VARIANTS[id].get("acc", []):
			for part: String in animated.get(a, [a]):
				assert_true(PatchModel._parts.has(part), "%s: %s" % [id, part])
	for icon: String in ["acc_icon_leaf", "acc_icon_cross", "acc_icon_heart"]:
		assert_true(PatchModel._parts.has(icon), icon)


func test_designs_rest_on_the_sheet_expression() -> void:
	# Bolt and Pixel rest on smiling arcs with a small smile; the others on crescents. One eye path:
	# the face shader, never an overlay pass.
	for id: String in PatchModel.VARIANTS:
		var m := PatchModel.new()
		m.preview_variant = id
		add_child_autofree(m)
		m._process(0.016)
		var arcs: bool = id in ["bolt", "pixel"]
		assert_eq(m._happy_bias > 0.5, arcs, id + " resting arcs")
		assert_eq(float(m._face_mat.get_shader_parameter("smile")) > 0.5, arcs, id + " smile")
		assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), 0, id + " crescent shape")
		assert_null(m._face_mat.next_pass, id)


func test_held_items_follow_the_left_claw() -> void:
	for pair: Array in [["bolt", "_gear"], ["sprout", "_bottle"], ["nova", "_holo"], ["patch", "_case"]]:
		var m := PatchModel.new()
		m.preview_variant = pair[0]
		add_child_autofree(m)
		var item: Node3D = m.get(pair[1])
		assert_not_null(item, "%s %s" % pair)
		m._process(0.016)
		assert_lt(item.global_position.distance_to(m.claw_point_l()), 0.45, "%s %s near the claw" % pair)


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
