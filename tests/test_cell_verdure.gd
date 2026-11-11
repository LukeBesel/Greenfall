extends GutTest
## [v6life] Clean ground greens over: SphereCells.green and CellVerdure's growth rules.


func _cells() -> SphereCells:
	var c := SphereCells.new(64)
	return c


func _verdure(c: SphereCells) -> CellVerdure:
	var v := CellVerdure.new()
	v.cells = c
	c.cell_changed.connect(v._on_cell)
	autofree(v)
	return v


func test_targets_rise_with_level_and_skip_junk_water_and_hub_ground() -> void:
	assert_eq(CellVerdure.target_of(0, 0, 0), 0.0, "junk")
	assert_eq(CellVerdure.target_of(5, 0, 0), 0.0, "water")
	assert_eq(CellVerdure.target_of(1, 3, SphereCells.F_HUB), 0.0, "hub ground")
	var last: float = 0.0
	for lv: int in range(1, 6):
		var t: float = CellVerdure.target_of(1, lv, 0)
		assert_gt(t, last, "level %d is greener" % lv)
		last = t
	assert_eq(CellVerdure.target_of(1, 0, 0), CellVerdure.target_of(1, 1, 0), "an untracked clean cell counts as Clean")
	assert_eq(last, 1.0)


func test_a_cleaned_cell_grows_in_over_minutes_and_a_level_adds_more() -> void:
	var c: SphereCells = _cells()
	var v: CellVerdure = _verdure(c)
	c.set_junk(3, 0.0)  # junk -> clean
	assert_true(v.growing(3))
	assert_eq(c.green[3], 0, "bare at first")
	v.step(20.0)
	var early: int = c.green[3]
	assert_gt(early, 0)
	assert_lt(early, int(CellVerdure.TARGET[1] * 255.0))
	for k: int in 40:
		v.step(10.0)
	assert_eq(c.green[3], int(CellVerdure.TARGET[1] * 255.0 + 0.5), "full for a clean cell")
	assert_false(v.growing(3))
	c.set_level(3, 2)
	assert_true(v.growing(3), "planting grows it further")
	for k: int in 40:
		v.step(10.0)
	assert_eq(c.green[3], int(CellVerdure.TARGET[2] * 255.0 + 0.5))


func test_green_is_derived_never_saved_and_comes_back_full_on_load() -> void:
	var c: SphereCells = _cells()
	var v: CellVerdure = _verdure(c)
	c.set_junk(5, 0.0)
	c.set_level(5, 3)
	c.set_junk(6, 0.0)
	c.set_flag(6, SphereCells.F_HUB)
	v.step(5.0)
	var d: Dictionary = c.to_dict()
	assert_false(d.has("green"))
	var c2: SphereCells = _cells()
	assert_true(c2.apply_dict(d))
	var v2: CellVerdure = _verdure(c2)
	assert_eq(v2.seed_all(), 1, "one clean land cell")
	assert_eq(c2.green[5], int(CellVerdure.TARGET[3] * 255.0 + 0.5))
	assert_eq(c2.green[6], 0, "hub ground stays bare")
	assert_eq(c2.green[7], 0, "junk stays bare")


func test_hub_ground_and_redirtied_cells_lose_their_green() -> void:
	var c: SphereCells = _cells()
	var v: CellVerdure = _verdure(c)
	c.set_junk(8, 0.0)
	for k: int in 50:
		v.step(10.0)
	assert_gt(c.green[8], 0)
	c.set_flag(8, SphereCells.F_HUB)
	assert_eq(c.green[8], 0)
	assert_false(v.growing(8))


func test_set_green_is_quiet_and_rides_in_the_red_channel_of_clean_cells() -> void:
	var c: SphereCells = _cells()
	var seen: Array = []
	c.cell_changed.connect(func(i: int) -> void: seen.append(i))
	var greens: Array = []
	c.green_changed.connect(func(i: int) -> void: greens.append(i))
	c.set_junk(2, 0.0)
	seen.clear()
	c.set_green(2, 128)
	assert_eq(seen.size(), 0, "no cell_changed")
	assert_eq(greens, [2])
	assert_eq(int(round(c.image.get_pixel(2, 0).r * 255.0)), 128)
	c.set_green(9, 200)  # a junk cell: R stays junk left
	assert_eq(int(round(c.image.get_pixel(9, 0).r * 255.0)), 255)


func test_mask_is_smooth_bounded_and_cover_follows_green() -> void:
	var lo: float = 1.0
	var hi: float = 0.0
	var p := Vector3(1200.0, -300.0, 1300.0)
	var prev: float = CellVerdure.mask(p)
	for k: int in 400:
		p += Vector3(0.21, 0.13, -0.17)
		var m: float = CellVerdure.mask(p)
		assert_lt(absf(m - prev), 0.12, "no jumps between near points")
		prev = m
		lo = minf(lo, m)
		hi = maxf(hi, m)
	assert_between(lo, 0.0, 0.45)
	assert_between(hi, 0.55, 1.0)
	assert_lt(CellVerdure.cover(0.0, 0.0), 0.0, "bare ground has no grass")
	assert_gt(CellVerdure.cover(1.0, 1.0), 0.25, "a thriving cell is covered everywhere")
	var share: Array[int] = [0, 0]
	p = Vector3(900.0, 900.0, 1300.0)
	for k: int in 600:
		p += Vector3(1.7, -0.9, 0.4)
		var m: float = CellVerdure.mask(p)
		if CellVerdure.cover(CellVerdure.TARGET[1], m) > 0.0:
			share[0] += 1
		if CellVerdure.cover(CellVerdure.TARGET[2], m) > 0.0:
			share[1] += 1
	assert_between(share[0] / 600.0, 0.2, 0.6, "a clean cell is patchy")
	assert_gt(share[1] / 600.0, 0.7, "a planted cell is mostly grass")
