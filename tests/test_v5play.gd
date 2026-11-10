extends GutTest
## [v5play] Play-test fixes on round Verdance: junk never inside a building footprint (keep-out
## buckets), no wedge gaps between hinterland buildings, watering and planting across a hex border.

class FakeView:
	extends RefCounted
	func set_life(_id: int, _life: float) -> void:
		pass

class FakeWorld:
	extends Node
	var field: HexField
	var view := FakeView.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()

var _cur: Dictionary
var _world_state: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world.duplicate(true)
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world_state


# --- Keep-out buckets ---------------------------------------------------------------------------

## Every point inside a registered footprint is blocked, wherever the footprint lies against the
## 16 m buckets (a footprint that only clipped a bucket's corner used to be missed there).
func test_keep_out_covers_whole_footprints() -> void:
	var ko := YardKeepOut.new()
	ko.radius = 1840.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var frames: Array[Transform3D] = []
	var rect := Rect2(-9.0, -7.5, 18.0, 15.0)
	for k: int in 60:
		var d: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var b: Basis = Basis(SphereGrid.frame(d).y, rng.randf() * TAU) * SphereGrid.frame(d)
		var fr := Transform3D(b, d * ko.radius)
		frames.append(fr)
		ko.add_world("t%d" % k, [[fr, rect]])
	var missed: int = 0
	var n: int = 0
	for fr2: Transform3D in frames:
		var x: float = rect.position.x
		while x <= rect.end.x:
			var z: float = rect.position.y
			while z <= rect.end.y:
				n += 1
				if not ko.in_building((fr2 * Vector3(x, 0, z)).normalized()):
					missed += 1
				z += 0.5
			x += 0.5
	assert_eq(missed, 0, "points inside a footprint that the keep-out missed (of %d)" % n)
	# And it stays tight: a point 6 m outside a footprint is free.
	var fr0: Transform3D = frames[0]
	assert_false(ko.in_building((fr0 * Vector3(rect.end.x + 6.0, 0, 0)).normalized()))


# --- Hinterland gaps ----------------------------------------------------------------------------

func test_rect_gap() -> void:
	var a := Transform3D(Basis(), Vector3.ZERO)
	var b := Transform3D(Basis(), Vector3(12.0, 0, 0))
	assert_almost_eq(Hinterland.rect_gap(a, Vector2(10, 6), b, Vector2(10, 6)), 2.0, 0.01)
	assert_almost_eq(Hinterland.rect_gap(a, Vector2(10, 6), Transform3D(Basis(), Vector3(4, 0, 0)), Vector2(10, 6)), 0.0, 0.01, "overlap")
	var turned := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(12.0, 0, 0))  # 6 wide along x now
	assert_almost_eq(Hinterland.rect_gap(a, Vector2(10, 6), turned, Vector2(10, 6)), 4.0, 0.01)


## No two neighbouring hexes' buildings or props closer than Hinterland.MIN_GAP_M (Lumi is 1.1 m
## wide): the 18 x 15 m works used to stand 0.5 m from a house.
func test_hinterland_leaves_no_wedge_gaps() -> void:
	var grid: SphereGrid = SphereGrid.for_hex_size(7, 10.0)
	var terrain := SphereTerrain.new(grid, 4471)
	var cells := SphereCells.new(grid.cell_count())
	var h := Hinterland.new()
	h.grid = grid
	h.terrain = terrain
	h.cells = cells
	h.seed_value = 4471
	h._zone.seed = 4471 + 811
	h._zone.frequency = 1.0 / 380.0
	h._zone.noise_type = FastNoiseLite.TYPE_SIMPLEX
	h._angle.seed = 4471 + 812
	h._angle.frequency = 1.0 / 600.0
	var total: int = 0
	var tight: int = 0
	var worst: float = INF
	var dropped: int = 0
	for base: Vector3 in [Vector3(0.3, 0.8, 0.2), Vector3(-0.6, 0.2, 0.7), Vector3(0.1, -0.5, -0.8), Vector3(0.9, 0.1, 0.3)]:
		var region: PackedInt32Array = grid.cells_within(base.normalized(), 260.0)
		for c: int in region:
			var mine: Array = h._decide(c)
			if mine.is_empty():
				dropped += 0 if h._candidate(c).is_empty() else 1
				continue
			total += 1
			for o: int in grid.neighbors(c):
				var theirs: Array = h._decide(o)
				if theirs.is_empty():
					continue
				var g: float = Hinterland.rect_gap(mine[0][1], mine[0][2], theirs[0][1], theirs[0][2])
				worst = minf(worst, g)
				if g < Hinterland.MIN_GAP_M:
					tight += 1
	h.free()
	assert_gt(total, 100, "the sample regions hold buildings and props")
	assert_eq(tight, 0, "pairs closer than %.1f m (worst %.2f m)" % [Hinterland.MIN_GAP_M, worst])
	assert_lt(float(dropped) / maxf(total, 1.0), 0.15, "only a few yield to a bigger neighbour")


# --- Watering and planting across a hex border ---------------------------------------------------

func _garden() -> Array:
	var w := FakeWorld.new()
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	w.field = HexField.new(2, 10.0, 5)
	w.field.generate(types, Vector2i(5, 8))
	w.planet = PlanetData.new(5, 3, 10.0)
	w.planet.generate()
	w.slice_cells.resize(w.field.hex_count())
	for i: int in w.field.hex_count():
		w.slice_cells[i] = i
	add_child_autofree(w)
	var g := Garden.new()
	g.world = w
	w.add_child(g)
	g.setup()
	w.set("garden", g)
	return [w, g]


## Lumi stands in one hex, facing along the border; the plant is in the hex beside him, well
## inside the watering ring. It is in reach, and listed once.
func test_plant_over_the_hex_border_is_in_reach() -> void:
	var made: Array = _garden()
	var w: FakeWorld = made[0]
	var g: Garden = made[1]
	var found: bool = false
	for hid: int in w.field.hex_count():
		if not g.hex_slots.has(hid) or found:
			continue
		for pid: int in w.field.hex_pieces[hid].duplicate():
			w.field.remove_piece(pid)
		for s: int in g.hex_slots[hid]:
			var sp: Vector3 = g.slot_pos[s]
			# A stand 1.6 m from the slot that lies in another hex, facing square to the slot.
			for k: int in 12:
				var a: float = TAU * k / 12.0
				var stand: Vector3 = sp + Vector3(cos(a), 0, sin(a)) * 1.6
				var fwd: Vector3 = Vector3(-sin(a), 0, cos(a))
				var h0: int = w.field.hex_at(stand)
				if h0 < 0 or h0 == hid or w.field.hex_at(stand + fwd * 1.0) == hid:
					continue
				GameState.currencies["seeds"] = BigNum.from_float(5)
				assert_eq(g.free_slot_near(stand, fwd, 2.8) >= 0, true, "a free spot over the border takes a seed")
				assert_true(g.plant(s))
				var near: Array[int] = g.planted_near(stand, fwd)
				assert_eq(near.count(s), 1, "the plant over the border is in reach, listed once")
				found = true
				break
			if found:
				break
	assert_true(found, "found a slot near a hex border to test")


# --- Robots: a way out of a pocket of blocked cells -----------------------------------------------

## A robot standing in a pocket walled off by blocked cells (a town's buildings and street kit on
## the 17 m cells) still gets a route over land: every Haul Bug used to stand "idle: no path".
func test_route_leaves_a_pocket_of_blocked_cells() -> void:
	var g := SphereGrid.new()
	g.generate(5)
	g.radius_m = SphereGrid.radius_for(5, 10.0)
	var cells := SphereCells.new(g.cell_count())
	var surface := SphereSurface.new(g.radius_m)
	surface.cell_fn = func(p: Vector3, _h: int) -> int: return g.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return g.centers[c]
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(g, cells, null, surface, SphereSwarm.new(surface))
	var from: int = 100
	var ring1: PackedInt32Array = g.neighbors(from)
	var around: PackedInt32Array = g.cells_around(from, 2)
	for c: int in around:
		if c != from and not ring1.has(c):
			crew.blocked[c] = true  # the second ring is all walls
	var to: int = -1
	for c2: int in g.cells_around(from, 5):
		if not around.has(c2):
			to = c2
	assert_true(SpherePath.astar_grid(g, from, to, func(c: int) -> bool: return not crew.blocked.has(c), 6000).is_empty(), "the strict route is shut")
	var p: PackedInt32Array = crew.route(from, to, "haul")
	assert_false(p.is_empty(), "the robot still gets a route out")
	assert_eq(p[p.size() - 1], to)
	# Lakes stay shut for land robots, pocket or not.
	for c3: int in around:
		if c3 != from and not ring1.has(c3):
			cells.state[c3] = 5
	crew._loose_to.clear()
	assert_true(crew.route(from, to, "haul").is_empty(), "no route across a lake")
	# An open route is still the strict one (round the walls).
	crew.blocked.clear()
	for c4: int in around:
		cells.state[c4] = 1
	crew.blocked[ring1[0]] = true
	crew._loose_to.clear()
	var q: PackedInt32Array = crew.route(from, to, "haul")
	assert_false(q.is_empty())
	assert_false(q.has(ring1[0]) and q[q.size() - 1] != ring1[0], "an open route keeps off blocked cells")
