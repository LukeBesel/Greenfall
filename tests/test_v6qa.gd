extends GutTest
## [v6qa] Known-glitch list fixes on round Verdance (docs/QA_VERDANCE.md, "Known-glitch list").


func _hinterland() -> Hinterland:
	var grid: SphereGrid = SphereGrid.for_hex_size(7, 10.0)
	var h := Hinterland.new()
	h.grid = grid
	h.terrain = SphereTerrain.new(grid, 4471)
	h.cells = SphereCells.new(grid.cell_count())
	h.seed_value = 4471
	h._zone.seed = 4471 + 811
	h._zone.frequency = 1.0 / 380.0
	h._zone.noise_type = FastNoiseLite.TYPE_SIMPLEX
	h._angle.seed = 4471 + 812
	h._angle.frequency = 1.0 / 600.0
	h._track.seed = 4471 + 813
	h._track.frequency = 1.0 / 300.0
	h._track.noise_type = FastNoiseLite.TYPE_SIMPLEX
	return h


## Q3: a hinterland road that ends (a hub's clearance, a lake, steep ground) ends at a road block,
## and only a dead end gets one.
func test_dead_end_roads_get_a_road_block() -> void:
	var h: Hinterland = _hinterland()
	var ends: int = 0
	var blocks: int = 0
	var wrong: int = 0
	for c: int in h.grid.cells_within(Vector3(0.3, 0.8, 0.2).normalized(), 400.0):
		var mine: Array = h._candidate(c)
		var strips: int = mine.filter(func(e: Array) -> bool: return int(e[0]) == Hinterland.K_TRACK).size()
		var blk: int = mine.filter(func(e: Array) -> bool: return int(e[0]) == Hinterland.K_BARRIER).size()
		if strips == 2:  # one link: two half strips
			ends += 1
			blocks += blk
			if blk != 1:
				wrong += 1
		elif blk > 0:
			wrong += 1
	h.free()
	assert_gt(ends, 0, "the sample region has dead-end roads")
	assert_eq(blocks, ends, "every dead end has one road block")
	assert_eq(wrong, 0, "road blocks only at dead ends")
