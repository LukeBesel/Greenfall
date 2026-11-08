extends GutTest
## [orbE] The intro's in-world shots on a round planet: the flat shot coordinates map into the
## pod anchor's frame, so cameras stay level on the local up; identity on the flat game.


func test_identity_on_flat() -> void:
	var it := Intro.new()
	var v := Vector3(3, 4, 5)
	assert_eq(it._w(v), v)
	assert_eq(it._v(v), v)
	assert_eq(it._up(), Vector3.UP)
	it._shot(Vector3(0, 2, 5), Vector3.ZERO, Vector3(0, 2, 6), Vector3.ZERO, 1.0)
	assert_almost_eq(it._cam_from.basis.y.dot(Vector3.UP), 0.92, 0.1)
	it.free()


func test_shots_level_on_the_globe() -> void:
	var it := Intro.new()
	var up := Vector3(0.3, 0.5, 0.81).normalized()
	var anchor := Transform3D(SphereGrid.frame(up), up * 1840.0)
	it.site_xf = Intro.site_for_anchor(anchor)
	assert_almost_eq(it._w(Intro.POD_POS).distance_to(anchor.origin), 0.0, 0.01, "the pod spot lands on the anchor")
	assert_almost_eq(it._up().dot(up), 1.0, 0.0001)
	var p := Vector3(10, 3, -4)
	assert_almost_eq(it._v(it._w(p)).distance_to(p), 0.0, 0.001)
	# A level shot (camera and target at the same height) has no roll: its right axis is horizontal.
	it._shot(Intro.POD_POS + Vector3(-11, 1.5, 13), Intro.POD_POS + Vector3(0, 1.5, 0), Intro.POD_POS + Vector3(-9, 1.5, 11), Intro.POD_POS + Vector3(0, 1.5, 0), 2.0)
	assert_almost_eq(it._cam_from.basis.x.dot(up), 0.0, 0.001, "no roll against the local horizon")
	assert_almost_eq(it._cam_from.basis.z.dot(up), 0.0, 0.001, "looking level along the ground")
	it.free()
