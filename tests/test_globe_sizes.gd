extends GutTest
## [orbB] Planets differ in size: SphereGrid at any subdivision frequency, GlobeSpec from
## data/planets.json, and the survey (PlanetData) on the same cells.

var _g: SphereGrid


func before_all() -> void:
	_g = SphereGrid.for_freq(109, 10.0)  # Ochre


func test_cell_count_and_pentagons() -> void:
	assert_eq(_g.cell_count(), 10 * 109 * 109 + 2)
	var pent: int = 0
	for i: int in _g.cell_count():
		if _g.is_pentagon(i):
			pent += 1
	assert_eq(pent, 12)
	assert_eq(_g.freq, 109)


func test_neighbours_are_mutual() -> void:
	var bad: int = 0
	for i: int in range(0, _g.cell_count(), 97):
		for j: int in _g.neighbors(i):
			if not _g.neighbors(j).has(i):
				bad += 1
	assert_eq(bad, 0)


func test_hex_size_stays_10m() -> void:
	var m: Dictionary = _g.hex_metrics()
	assert_almost_eq(float(m["corner_m"]), 10.0, 0.6, "corner ~10 m on every planet")
	var v: SphereGrid = SphereGrid.for_freq(128, 10.0)
	assert_almost_eq(_g.radius_m / v.radius_m, 109.0 / 128.0, 0.001, "R grows with f")


func test_cell_lookup_and_chunks() -> void:
	for i: int in range(0, _g.cell_count(), 1013):
		assert_eq(_g.cell_at(_g.centers[i] * _g.radius_m), i)
	var total: int = 0
	for c: int in _g.chunk_count():
		total += _g.cells_in_chunk(c).size()
		for cell: int in _g.cells_in_chunk(c):
			assert_true(_g.chunk_center[c].angle_to(_g.centers[cell]) <= _g.chunk_radius[c] + 0.0001)
	assert_eq(total, _g.cell_count(), "every cell in exactly one chunk")
	assert_eq(_g.chunk_center.size(), _g.chunk_count())


func test_power_of_two_is_the_level_grid() -> void:
	var a: SphereGrid = SphereGrid.for_freq(128, 10.0)
	var b: SphereGrid = SphereGrid.for_hex_size(7, 10.0)
	assert_eq(a.level, 7)
	assert_eq(a.cell_count(), b.cell_count())
	assert_eq(a.centers[5000], b.centers[5000], "same ids: level-6 saves still map by prefix")
	assert_eq(a.chunk_center[3], a.centers[3], "level chunk centres are the id prefix")


func test_globe_spec_from_planets_json() -> void:
	assert_eq(int(GlobeSpec.of("verdance")["frequency"]), 128)
	var sizes: Array = []
	for id: String in ["ochre", "verdance", "tidewell", "rime", "anvil"]:
		sizes.append(int(GlobeSpec.of(id)["frequency"]))
	var sorted_s: Array = sizes.duplicate()
	sorted_s.sort()
	assert_eq(sizes, sorted_s, "Ochre < Verdance < Tidewell < Rime < Anvil")
	assert_almost_eq(float(GlobeSpec.of("anvil")["frequency"]) / 128.0, 1.35, 0.01)
	assert_eq(int(GlobeSpec.of("nowhere")["frequency"]), 128, "unknown planet: Verdance's size")


func test_survey_on_a_lattice_grid() -> void:
	var p := PlanetData.new(77, 0, 10.0, GeoSphere.from_grid(_g))
	p.generate()
	assert_eq(p.cell_count(), _g.cell_count())
	assert_gt(p.hubs.size(), 8)
	var d: Dictionary = p.to_dict()
	assert_eq(int(d["freq"]), 109)
	var q := PlanetData.new(77, 0, 10.0, GeoSphere.from_grid(_g))
	q.generate()
	assert_true(q.apply_dict(d))
	var other := PlanetData.new(77, 7, 10.0)
	assert_false(other.apply_dict(d), "a save from another planet size doesn't apply")
