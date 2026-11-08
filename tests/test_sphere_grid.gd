extends GutTest
## [sgrid] Hex globe foundation (planet/sphere/): grid topology, ids, lookups, terrain sites,
## per-hex state and the streaming budget.


func _grid(lv: int) -> SphereGrid:
	var g := SphereGrid.new()
	g.generate(lv)
	g.radius_m = SphereGrid.radius_for(lv, 10.0)
	return g


func test_counts_and_twelve_pentagons() -> void:
	for lv: int in [0, 1, 3, 5]:
		var g: SphereGrid = _grid(lv)
		assert_eq(g.cell_count(), 10 * int(pow(4, lv)) + 2)
		var pent: int = 0
		for i: int in g.cell_count():
			var k: int = g.nbr_count[i]
			assert_true(k == 5 or k == 6)
			if k == 5:
				pent += 1
				assert_lt(i, 12, "pentagons are the 12 icosahedron vertices")
		assert_eq(pent, 12)


func test_ids_match_geosphere_and_are_hierarchical() -> void:
	var g: SphereGrid = _grid(4)
	var gs := GeoSphere.new(4)
	gs.generate()
	assert_eq(g.cell_count(), gs.cell_count())
	var same: bool = true
	for i: int in g.cell_count():
		if not g.centers[i].is_equal_approx(gs.centers[i]):
			same = false
			break
		var a: Array = Array(g.neighbors(i))
		var b: Array = Array(gs.neighbors(i))
		a.sort()
		b.sort()
		if a != b:
			same = false
			break
	assert_true(same, "same cell ids and neighbour sets as GeoSphere")
	var coarse: SphereGrid = _grid(2)
	for i: int in coarse.cell_count():
		assert_true(coarse.centers[i].is_equal_approx(g.centers[i]))
	var again: SphereGrid = _grid(4)
	assert_eq(again.centers, g.centers, "deterministic")
	assert_eq(again.nbr, g.nbr)


func test_neighbours_symmetric_ordered_and_corners_shared() -> void:
	var g: SphereGrid = _grid(4)
	for i: int in g.cell_count():
		var ns: PackedInt32Array = g.neighbors(i)
		var cs: PackedVector3Array = g.corners(i)
		var up: Vector3 = g.centers[i]
		for k: int in ns.size():
			var j: int = ns[k]
			assert_true(i in g.neighbors(j), "symmetric %d-%d" % [i, j])
			# Counter-clockwise from outside.
			var a: Vector3 = cs[k] - up
			var b: Vector3 = cs[(k + 1) % cs.size()] - up
			if a.cross(b).dot(up) <= 0.0:
				fail_test("corners of %d not CCW" % i)
				return
			# Corner k is shared by neighbours k and k + 1.
			var nk1: int = ns[(k + 1) % ns.size()]
			assert_true(_has_point(g.corners(j), cs[k]) and _has_point(g.corners(nk1), cs[k]))


func _has_point(arr: PackedVector3Array, p: Vector3) -> bool:
	for q: Vector3 in arr:
		if q.is_equal_approx(p):
			return true
	return false


func test_point_lookup_round_trip() -> void:
	var g: SphereGrid = _grid(5)
	for i: int in g.cell_count():
		if g.cell_at(g.centers[i] * g.radius_m) != i:
			fail_test("centre of %d maps to %d" % [i, g.cell_at(g.centers[i])])
			return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _n: int in 400:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var best: int = 0
		for i: int in g.cell_count():
			if g.centers[i].dot(d) > g.centers[best].dot(d):
				best = i
		assert_eq(g.cell_at(d * 1234.0), best)
	# Corners belong to one of their three cells.
	var c: Vector3 = g.corners(500)[2]
	assert_true(g.cell_at(c) in [500, g.neighbors(500)[2], g.neighbors(500)[3 % g.neighbors(500).size()]])


func test_distances_and_metrics() -> void:
	var g: SphereGrid = _grid(6)
	var m: Dictionary = g.hex_metrics()
	assert_almost_eq(float(m["corner_m"]), 10.0, 0.6, "hex circumradius ~10 m")
	assert_almost_eq(float(m["spacing_m"]), 17.3, 1.0)
	assert_almost_eq(g.great_circle_m(Vector3.UP, Vector3.DOWN), PI * g.radius_m, 0.01)
	var j: int = g.neighbors(100)[0]
	assert_almost_eq(g.distance_m(100, j), float(m["spacing_m"]), 2.0)


func test_rings_and_within() -> void:
	var g: SphereGrid = _grid(5)
	var r2: PackedInt32Array = g.cells_around(300, 2)
	assert_eq(r2.size(), 19, "1 + 6 + 12 hexes")
	var d: Vector3 = g.centers[300]
	var w: PackedInt32Array = g.cells_within(d, 60.0, 300)
	var brute: int = 0
	for i: int in g.cell_count():
		if g.centers[i].angle_to(d) * g.radius_m <= 60.0:
			brute += 1
	assert_eq(w.size(), brute)


func test_chunks_partition_the_grid() -> void:
	var g: SphereGrid = _grid(6)
	assert_eq(g.chunk_count(), 162)
	assert_eq(g.chunk_cells.size(), g.cell_count())
	var seen := PackedByteArray()
	seen.resize(g.cell_count())
	var mn: int = 1 << 30
	var mx: int = 0
	for c: int in g.chunk_count():
		var cc: PackedInt32Array = g.cells_in_chunk(c)
		mn = mini(mn, cc.size())
		mx = maxi(mx, cc.size())
		for i: int in cc:
			assert_eq(seen[i], 0)
			seen[i] = 1
			assert_eq(g.cell_chunk[i], c)
	assert_gt(mn, 150)
	assert_lt(mx, 330)


func test_cache_round_trip() -> void:
	var g: SphereGrid = _grid(4)
	var path: String = "user://test_sphere_grid_4.bin"
	g.save_cache(path)
	var h := SphereGrid.new()
	assert_true(h.load_cache(path, 4))
	assert_eq(h.centers, g.centers)
	assert_eq(h.cell_chunk, g.cell_chunk)
	assert_eq(h.cell_at(Vector3(0.3, 0.2, -0.9)), g.cell_at(Vector3(0.3, 0.2, -0.9)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_site_is_flat_and_aligned() -> void:
	var g: SphereGrid = _grid(6)
	var t := SphereTerrain.new(g, 4471)
	var cell: int = g.cell_at(Vector3(0.3, 0.8, 0.2))
	var s: Dictionary = t.reserve_site(cell, 45.0, 30.0)
	assert_false(s.is_empty())
	var xf: Transform3D = s["transform"]
	assert_true(xf.basis.y.is_equal_approx(g.centers[cell]), "y = surface normal")
	# Every ground point on the pad lies on the site's local y = 0 plane.
	for x: float in [-40.0, -20.0, 0.0, 25.0, 40.0]:
		for z: float in [-30.0, 0.0, 30.0]:
			var p: Vector3 = t.ground(t.local_to_dir(cell, x, z) if Vector2(x, z).length() < 44.0 else g.centers[cell])
			assert_almost_eq((xf.affine_inverse() * p).y, 0.0, 0.01)
	# Outside the blend ring the natural terrain is back.
	var far: Vector3 = t.local_to_dir(cell, 90.0, 0.0)
	assert_almost_eq(t.height(far), t.raw_height(far), 0.001)
	# Overlapping sites are refused; far ones are fine.
	assert_true(t.reserve_site(g.neighbors(cell)[0], 45.0, 30.0).is_empty())
	assert_false(t.reserve_site(g.cell_at(-g.centers[cell]), 45.0, 30.0).is_empty())
	assert_eq(t.sites.size(), 2)
	t.release_site(int(s["id"]))
	assert_eq(t.sites.size(), 1)


func test_cells_state_and_save() -> void:
	var c := SphereCells.new(2562)
	c.set_junk(10, 0.0)
	assert_eq(c.state[10], 1, "fully cleaned junk hex becomes CLEAN")
	c.set_level(11, 3)
	c.set_flag(12, SphereCells.F_SITE)
	assert_true(c.has_flag(12, SphereCells.F_SITE))
	assert_eq(c.flush(), 3)
	assert_eq(c.image.get_pixel(10, 0).r8, 0)
	assert_eq(c.image.get_pixel(11, 0).a8 >> 4, 3)
	var d: Dictionary = c.to_dict()
	var c2 := SphereCells.new(2562)
	assert_true(c2.apply_dict(d))
	assert_eq(c2.state, c.state)
	assert_eq(c2.level, c.level)
	assert_false(SphereCells.new(100).apply_dict(d), "size mismatch is refused")


func test_lod_borders_match() -> void:
	var g: SphereGrid = _grid(5)
	var t := SphereTerrain.new(g, 4471)
	var jobs: Array[SphereChunkJob] = []
	for l: int in 3:
		var j := SphereChunkJob.new()
		j.chunk = 3
		j.lod = l
		j.grid = g
		j.terrain = t
		j.warp = []
		j.want_collision = l == 0
		j.run()
		jobs.append(j)
	assert_eq(jobs[0].indices.size() / 3, g.cells_in_chunk(3).size() * 24 - 4, "24 tris per hex (pentagon 20)")
	assert_eq(jobs[0].faces.size(), jobs[0].indices.size())
	# Every LOD 1 vertex (centres, corners, edge mids) exists in LOD 0 at the same place.
	var set0: Dictionary = {}
	for v: Vector3 in jobs[0].verts:
		set0[Vector3i(v * 100.0)] = true
	var miss: int = 0
	for v: Vector3 in jobs[1].verts:
		if not set0.has(Vector3i(v * 100.0)):
			miss += 1
	assert_eq(miss, 0)
	assert_eq(jobs[2].indices.size() / 3, g.cells_in_chunk(3).size() * 6 - 1, "6 tris per hex")


func test_streaming_budget() -> void:
	var g: SphereGrid = SphereGrid.for_hex_size(7, 10.0)
	assert_eq(g.chunk_count(), 642)
	var t := SphereTerrain.new(g, 4471)
	var cells := SphereCells.new(g.cell_count())
	var s := SphereStreamer.new()
	add_child_autofree(s)
	s.setup(g, t, cells)
	var cell: int = g.cell_at(Vector3(0.2, 0.9, 0.3))
	var d: Vector3 = g.centers[cell]
	var body: Vector3 = t.ground(d) + d * 1.0
	s.set_centre("lumi", body, SphereStreamer.BODY)
	s.set_centre("view", body + d * 6.0, SphereStreamer.VIEW)
	s.settle()
	var st: Dictionary = s.stats
	gut.p("ground: %s" % [st])
	assert_eq(int(st["pending"]) + int(st["jobs"]), 0)
	assert_between(int(st["lod0"]), 1, 12, "LOD 0 chunks near the eye")
	assert_lt(int(st["lod0"]) + int(st["lod1"]) + int(st["lod2"]), 40, "chunks to the horizon")
	assert_between(int(st["collide"]), 1, 4, "collision only around bodies")
	assert_lt(int(st["chunk_tris"]), 220000, "ground triangle budget")
	assert_eq(s.loaded_lod(g.cell_chunk[cell]), 0)
	assert_true(s.has_collision(g.cell_chunk[cell]))
	assert_between(s.near_cells().size(), 40, 120)
	# Move everything to the far side: the old chunks go, the new ground comes.
	var d2: Vector3 = -d
	s.set_centre("lumi", t.ground(d2) + d2, SphereStreamer.BODY)
	s.set_centre("view", t.ground(d2) + d2 * 7.0, SphereStreamer.VIEW)
	s.settle()
	assert_eq(s.loaded_lod(g.cell_chunk[cell]), -1, "unloaded")
	assert_eq(s.loaded_lod(g.cell_chunk[g.cell_at(d2)]), 0)
	# From orbit only the far shell draws, and nothing collides.
	# Command view (400 m up): far ground to the horizon, still a bounded budget.
	s.set_centre("view", t.ground(d2) + d2 * 400.0, SphereStreamer.VIEW)
	s.settle()
	gut.p("high: %s" % [s.stats])
	assert_lt(int(s.stats["lod0"]) + int(s.stats["lod1"]) + int(s.stats["lod2"]), 130)
	assert_lt(int(s.stats["chunk_tris"]), 400000)
	s.remove_centre("lumi")
	s.set_centre("view", d2 * g.radius_m * 2.5, SphereStreamer.VIEW)
	s.settle()
	assert_eq(int(s.stats["lod0"]) + int(s.stats["lod1"]) + int(s.stats["lod2"]), 0)
	assert_eq(int(s.stats["collide"]), 0)
