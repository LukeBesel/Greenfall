extends GutTest
## [art6] The Blender-built worker bodies (Scoopie, Haul Bug): every look builds, keeps the nodes
## and points other code uses, stays inside its triangle budget and animates without blowing up.

const LOOKS: Array[String] = ["salvage", "restored", "modern", "hover"]


func test_every_look_builds_with_the_hooks_other_code_uses() -> void:
	for t: String in ["scoopie", "haulbug", "seedling", "drip", "multibot"]:
		for l: String in LOOKS:
			var v := RobotVisual.new()
			add_child_autofree(v)
			v.build(t, l)
			assert_not_null(v._body, "%s/%s body" % [t, l])
			assert_not_null(v._head, "%s/%s head" % [t, l])
			assert_not_null(v._eye, "%s/%s eye (blinks)" % [t, l])
			assert_not_null(v._arm, "%s/%s tool arm (Builder tools hang on it)" % [t, l])
			assert_eq(v.hover, l == "hover")
			assert_eq(v._wheels.is_empty(), l == "hover", "%s/%s wheels, or pods at Mk IV" % [t, l])
			assert_false(v._glow_mats.is_empty(), "%s/%s lights the Locker can recolour" % [t, l])
			var top: float = BotBadge.top_of(v)
			assert_between(top, 0.8, 1.5, "%s/%s height %.2f" % [t, l, top])
			for i: int in 200:
				v.animate(2.5 if i < 80 else 0.0, i > 100, 0.033)
			assert_true(v._body.transform.is_finite() and v._arm.transform.is_finite() and v._head.transform.is_finite(), "%s/%s stays finite" % [t, l])
			v.animate(0.0, true, 0.7)
			assert_true(v._arm.transform.is_finite(), "a long frame does not blow the springs up")


func test_triangle_and_draw_budget() -> void:
	for t: String in ["scoopie", "haulbug"]:
		for l: String in LOOKS:
			var c: Dictionary = RobotVisual.worker_cost(t, l)
			assert_lt(int(c["near"]), 15000, "%s/%s near triangles %d" % [t, l, c["near"]])
			assert_lt(int(c["far"]), 800, "%s/%s far triangles %d" % [t, l, c["far"]])
			assert_lt(int(c["near_draws"]), 50, "%s/%s near draws %d" % [t, l, c["near_draws"]])


func test_far_mesh_takes_over_beyond_far_m() -> void:
	var v := RobotVisual.new()
	add_child_autofree(v)
	v.build("scoopie", "salvage")
	assert_eq(v._far.visibility_range_begin, RobotVisual.FAR_M)
	for mi: MeshInstance3D in v._near:
		assert_eq(mi.visibility_range_end, RobotVisual.FAR_M)
	assert_eq(v._far.mesh.get_surface_count(), 1, "one draw far away")


func test_haul_bug_bed_takes_the_bales() -> void:
	var v := RobotVisual.new()
	add_child_autofree(v)
	v.build("haulbug", "salvage")
	# SphereBales puts the stack 0.12 m above the hopper point: that is the deck.
	assert_almost_eq(v.hopper_point.y + 0.12, RobotVisual.HB["bed"].y, 0.001)
	for i: int in 60:
		v.animate(0.0, false, 0.033)
	var empty: float = v._body.position.y
	assert_almost_eq(v._clamps[1].rotation.z, RobotVisual.CLAMP_OPEN, 0.05, "clamps open when empty")
	v.set_load(6)
	var low: float = 0.0
	for i: int in 120:
		v.animate(0.0, false, 0.033)
		low = minf(low, v._body.position.y)
	assert_lt(v._body.position.y, empty - 0.02, "six bales sag the body")
	assert_lt(low, v._body.position.y - 0.003, "it dipped below where it settled (a bounce)")
	assert_gt(v._clamps[1].rotation.z, 0.0, "clamps shut on the load")
	assert_almost_eq(v._meter.scale.x, 1.0, 0.05, "load meter full at six")


func test_scoop_throws_over_the_head_and_comes_back() -> void:
	var v := RobotVisual.new()
	add_child_autofree(v)
	v.build("scoopie", "restored")
	var top: float = 0.0
	for i: int in int(RobotVisual.SCOOP_S / 0.02):
		v.animate(0.0, true, 0.02)
		top = maxf(top, v._arm.rotation.x)
	assert_gt(top, 2.0, "the booms go over the head")
	for i: int in 150:
		v.animate(0.0, false, 0.02)
	assert_almost_eq(v._arm.rotation.x, 0.0, 0.05, "and settle back down")
