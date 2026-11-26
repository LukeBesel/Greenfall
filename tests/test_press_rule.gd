extends GutTest
## [orbC] Regression: a chest just under the press threshold with nothing near that fits must not
## leave Lumi (or the bot) stuck. The rule says "press" then, and the player may always press.


func test_press_at_threshold_or_when_nothing_fits() -> void:
	assert_true(Pace.press_rule(0.9, false), "full enough")
	assert_false(Pace.press_rule(0.85, false), "room left and junk to take: keep scooping")
	assert_true(Pace.press_rule(0.85, true), "the softlock case: just under 90%, nothing near fits -> press")
	assert_false(Pace.press_rule(0.2, true), "a near-empty chest on clean ground: just walk on")


func test_liftable_near_respects_lift_strength() -> void:
	var g := SphereGrid.new()
	g.generate(4)
	g.radius_m = SphereGrid.radius_for(4, 10.0)
	var t := SphereTerrain.new(g, 7)
	var cells := SphereCells.new(g.cell_count())
	var f := SphereField.new(g, t, cells, 7)
	var c: int = 50
	f.materialize(c)
	var at: Vector3 = t.ground(g.centers[c])
	var any_light: bool = false
	for pid: int in f.pieces_in(c):
		any_light = any_light or Pace.can_lift(f, pid)
	assert_eq(Pace.liftable_near(f, at, 9.0), any_light)
	for pid: int in f.pieces_in(c):
		if Pace.can_lift(f, pid):
			f.remove_piece(pid)
	assert_false(Pace.liftable_near(f, at, 9.0), "only pieces too heavy for Lift Strength left: nothing fits")
