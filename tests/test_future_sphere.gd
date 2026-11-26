extends GutTest
## [orbE] The Future Layer on the globe: per-cell plans from SphereCells.level are deterministic,
## grow with the level and never shrink, clamp above Thriving, and sit on the cell's ground plane
## in its local frame (local up, not world up).


func test_plan_grows_with_level_and_is_deterministic() -> void:
	var last: int = 0
	for lv: int in range(0, 6):
		var n: int = FutureLayer.count(FutureLayerSphere.plan_cell(4242, lv, 5.8))
		assert_true(n >= last, "level %d keeps every piece of level %d" % [lv, lv - 1])
		last = n
	assert_gt(last, 10)
	assert_eq(FutureLayer.count(FutureLayerSphere.plan_cell(4242, 0, 5.8)), 0)
	assert_eq(FutureLayer.count(FutureLayerSphere.plan_cell(4242, 4, 5.8)), FutureLayer.count(FutureLayerSphere.plan_cell(4242, 4, 5.8)))


func test_show_level_clamps() -> void:
	assert_eq(FutureLayerSphere.show_level(0), 0)
	assert_eq(FutureLayerSphere.show_level(3), 3)
	assert_eq(FutureLayerSphere.show_level(15), 5)


func test_to_world_uses_the_local_frame() -> void:
	var up := Vector3(1, 1, 0).normalized()
	var f: Basis = SphereGrid.frame(up)
	var plane: Array = [f, up * 1840.0, 0.0, 0.0]
	var t := Transform3D(Basis.IDENTITY, Vector3(0, 2.0, 0))  # 2 m above the cell centre
	var w: Transform3D = FutureLayerSphere.to_world(plane, t)
	assert_almost_eq(w.origin.length(), 1842.0, 0.01)
	assert_gt(w.basis.y.normalized().dot(up), 0.999, "piece up = local up")
	var side: Transform3D = FutureLayerSphere.to_world([f, up * 1840.0, 0.1, 0.0], Transform3D(Basis.IDENTITY, Vector3(3.0, 0, 0)))
	assert_almost_eq((side.origin - up * 1840.0).dot(up), 0.3, 0.001, "follows the ground slope")


func test_cell_slots_inside_the_hex() -> void:
	for p: Vector3 in FutureLayerSphere.cell_slots(99, 5.8):
		assert_lt(p.length(), 5.8 * 0.7)
