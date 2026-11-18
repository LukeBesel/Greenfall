extends GutTest


func test_cell_counts_and_pentagons() -> void:
	for lv: int in [2, 4]:
		var g := GeoSphere.new(lv)
		g.generate()
		assert_eq(g.cell_count(), 10 * int(pow(4, lv)) + 2)
		var pent: int = 0
		for i: int in g.cell_count():
			var n: int = g.neighbors(i).size()
			assert_true(n == 5 or n == 6, "cell %d has %d neighbors" % [i, n])
			if n == 5:
				pent += 1
		assert_eq(pent, 12)


func test_neighbors_symmetric_and_close() -> void:
	var g := GeoSphere.new(3)
	g.generate()
	for i: int in g.cell_count():
		for j: int in g.neighbors(i):
			assert_true(i in g.neighbors(j))
			assert_lt(g.centers[i].angle_to(g.centers[j]), 0.2)


func test_corners_ordered() -> void:
	var g := GeoSphere.new(3)
	g.generate()
	var c: PackedVector3Array = g.corners(100)
	assert_eq(c.size(), g.neighbors(100).size())
	# Corners wind consistently around the center (all cross products point outward).
	var up: Vector3 = g.centers[100]
	for k: int in c.size():
		var a: Vector3 = c[k] - up
		var b: Vector3 = c[(k + 1) % c.size()] - up
		assert_gt(a.cross(b).dot(up), 0.0)


func test_nearest_walk() -> void:
	var g := GeoSphere.new(4)
	g.generate()
	var target: Vector3 = g.centers[1234]
	assert_eq(g.nearest_from(target, 0), 1234)
	assert_eq(g.nearest_from((target + Vector3(0.001, 0, 0)).normalized(), 5), 1234)
