extends GutTest
## [orbit] Prototype globe maths (planet/orbit/orbit_globe.gd).

var _globe: OrbitGlobe


func before_all() -> void:
	var p := PlanetData.new(4471, 6, 10.0)
	p.generate()
	_globe = OrbitGlobe.new(p, 10.0)


func test_size() -> void:
	assert_eq(_globe.planet.cell_count(), 40962)
	assert_almost_eq(_globe.R, 920.0, 5.0, "hex circumradius 10 m -> R ~ 920 m")


func test_frame_is_orthonormal_with_radial_up() -> void:
	for d: Vector3 in [Vector3(0.3, 0.8, -0.2).normalized(), Vector3(0, 1, 0), Vector3(1, 0, 0)]:
		var f: Basis = OrbitGlobe.frame(d)
		assert_almost_eq(f.y.dot(d), 1.0, 0.0001)
		assert_almost_eq(f.x.dot(f.y), 0.0, 0.0001)
		assert_almost_eq(f.x.cross(f.y).dot(f.z), 1.0, 0.0001, "right-handed")


func test_hub_chart_preserves_distance() -> void:
	var hub: int = _globe.planet.hubs[0]
	var c: Vector3 = _globe.grid.centers[hub]
	var d: Vector3 = _globe.planet.local_to_dir(hub, 120.0, 0.0)
	assert_almost_eq(c.angle_to(d) * _globe.R, 120.0, 0.01)


func test_cells_around_and_chunks() -> void:
	assert_eq(_globe.cells_around(_globe.planet.hubs[0], 2).size(), 19)
	var total: int = 0
	for cc: PackedInt32Array in _globe.chunk_cells:
		total += cc.size()
	assert_eq(total, 40962, "every cell in exactly one chunk")


func test_set_cell_marks_clean() -> void:
	var c: int = -1
	for i: int in _globe.planet.cell_count():
		if _globe.is_dirty(i):
			c = i
			break
	_globe.set_cell(c, 0.0)
	assert_false(_globe.is_dirty(c))
	assert_eq(int(_globe.planet.state[c]), PlanetData.State.CLEAN)
