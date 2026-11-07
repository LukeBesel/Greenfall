extends GutTest
## [vqa2] Junk distance LOD (planet/junk_lod.gd) and the day-time star fade (sky_director.gd).

var field: HexField
var parent: Node3D
var lod: JunkLod


func before_each() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field = HexField.new(5, 3.2, 99)
	field.generate(types)
	parent = Node3D.new()
	add_child_autofree(parent)
	lod = JunkLod.new(field, 1)
	lod.near_radius = 9.0
	var pids := PackedInt32Array()
	for pid: int in field.piece_count():
		pids.append(pid)
	lod.add_group(parent, "Junk_test", "trashbag", AssetLib.model_mesh_lite("trashbag", 500), pids, false, 1)
	for pid: int in field.piece_count():
		lod.show_piece(pid, Transform3D(Basis(), field.piece_pos[pid]))


func test_far_mesh_is_much_lighter() -> void:
	for id: String in ["trashbag", "plastic_crate_01"]:
		if not AssetLib.has_model(id):
			continue
		var near: int = JunkLod._tris(AssetLib.model_mesh_lite(id, 700))
		var far: int = JunkLod._tris(JunkLod.far_mesh(id, 120))
		assert_lt(far, near, id)
		assert_lt(far, 300, id)
		assert_gt(far, 8, id)


func test_starts_near_then_splits_by_distance() -> void:
	var n: int = field.piece_count()
	assert_eq(lod.counts(), Vector2i(n, 0), "all near before the first camera update")
	lod.update(1.0, Vector3.ZERO)
	var c: Vector2i = lod.counts()
	assert_eq(c.x + c.y, n)
	assert_gt(c.x, 0)
	assert_gt(c.y, 0)
	assert_eq(lod.near_mm[0].visible_instance_count, c.x)
	assert_eq(lod.far_mm[0].visible_instance_count, c.y)
	# Every piece sits in the buffer its hex distance says.
	for pid: int in n:
		var d: float = field.hex_center(field.piece_hex[pid]).length()
		if d < 9.0:
			assert_eq(lod._where[pid], 1)
		elif d > 9.0 + JunkLod.HYSTERESIS:
			assert_eq(lod._where[pid], 2)


func test_hide_and_show_keep_buffers_packed() -> void:
	lod.update(1.0, Vector3.ZERO)
	var c0: Vector2i = lod.counts()
	var hidden: int = 0
	for pid: int in range(0, field.piece_count(), 3):
		lod.hide_piece(pid)
		hidden += 1
	var c1: Vector2i = lod.counts()
	assert_eq(c1.x + c1.y, c0.x + c0.y - hidden)
	assert_eq(lod.near_mm[0].visible_instance_count + lod.far_mm[0].visible_instance_count, c1.x + c1.y)
	# Live instances keep their own transforms after the swaps.
	for pid: int in field.piece_count():
		if lod.is_shown(pid):
			assert_almost_eq(lod._current_xf(pid).origin, field.piece_pos[pid], Vector3.ONE * 0.001)
	lod.show_piece(0, Transform3D(Basis(), Vector3(1, 2, 3)))
	assert_true(lod.is_shown(0))
	assert_almost_eq(lod._current_xf(0).origin, Vector3(1, 2, 3), Vector3.ONE * 0.001)


func test_camera_move_swaps_and_back() -> void:
	lod.update(1.0, Vector3.ZERO)
	var c0: Vector2i = lod.counts()
	lod.update(1.0, Vector3(500, 0, 0))
	assert_eq(lod.counts(), Vector2i(0, c0.x + c0.y), "all far from 500 m")
	lod.update(1.0, Vector3.ZERO)
	var expect_near: int = 0
	for pid: int in field.piece_count():
		if field.hex_center(field.piece_hex[pid]).length() < lod.near_radius:
			expect_near += 1
	assert_eq(lod.counts(), Vector2i(expect_near, c0.x + c0.y - expect_near), "coming back in, only hexes inside the radius turn near")


func test_stars_fade_out_by_day() -> void:
	assert_almost_eq(SkyDirector.star_level(0.0), 1.0, 0.001)
	assert_almost_eq(SkyDirector.star_level(1.0), 0.0, 0.001)
	assert_lt(SkyDirector.star_level(0.5), 0.05)
