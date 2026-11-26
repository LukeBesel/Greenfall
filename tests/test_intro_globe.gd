extends GutTest
## [orbE] The intro's in-world shots on a round planet: the shot coordinates (flat, around the pod)
## map into the pod anchor's frame, so cameras and Lumi stay level on the local up.


func test_identity_on_flat() -> void:
	var it := Intro.new()
	var v := Vector3(3, 4, 5)
	assert_eq(it._w(v), v)
	assert_eq(it._v(v), v)
	assert_eq(it._up(), Vector3.UP)
	it.free()


func test_site_frame_on_the_globe() -> void:
	var it := Intro.new()
	var up := Vector3(0.3, 0.5, 0.81).normalized()
	var anchor := Transform3D(SphereGrid.frame(up), up * 1840.0)
	it.site_xf = Intro.site_for_anchor(anchor)
	assert_almost_eq(it._w(Intro.POD_POS).distance_to(anchor.origin), 0.0, 0.01, "the pod spot lands on the anchor")
	assert_almost_eq(it._up().dot(up), 1.0, 0.0001)
	var p := Vector3(10, 3, -4)
	assert_almost_eq(it._v(it._w(p)).distance_to(p), 0.0, 0.001)
	it.free()


func test_pod_frame_points_stay_level() -> void:
	# A point given in the landed pod's frame keeps its height over the pad wherever the door faces.
	var it := Intro.new()
	var up := Vector3(-0.2, 0.9, 0.38).normalized()
	it.site_xf = Intro.site_for_anchor(Transform3D(SphereGrid.frame(up), up * 1840.0))
	for yaw: float in [0.0, 0.5, 1.0, 2.6]:
		it._pod_yaw = yaw
		var q: Vector3 = it._pod_pt(Vector3(1.2, 0.8, -4.0))
		assert_almost_eq(q.y, 0.8, 0.0001)
		assert_almost_eq((q - Intro.POD_POS).length(), Vector3(1.2, 0.8, -4.0).length(), 0.001)
		# -z is out of the door.
		assert_almost_eq((it._pod_pt(Vector3(0, 0, -1)) - Intro.POD_POS).dot(it._door()), 1.0, 0.0001)
		var h: float = (it._w(q) - it._w(Intro.POD_POS)).dot(up)
		assert_almost_eq(h, 0.8, 0.001, "height over the pad along the local up")
	it.free()


func test_pod_falls_base_first() -> void:
	var dir := Vector3(0.7, -0.55, -0.46).normalized()
	for t: float in [0.0, 1.3, 4.0]:
		var b: Basis = Intro.fall_basis(dir, t, 0.0, 0.8)
		assert_almost_eq(b.y.dot(-dir), 1.0, 0.0001, "the base leads, the fire trails up the pod")
		assert_almost_eq(b.determinant(), 1.0, 0.0001)
	# The wobble is small: the base still leads.
	assert_gt(Intro.fall_basis(dir, 2.0, 0.15, 0.8).y.dot(-dir), 0.98)
