extends GutTest
## [v6feel] Rules behind Lumi's moment-to-moment feel: the carried stack, the lift path, movement.


func _bale() -> JunkCube:
	var info: Dictionary = Economy.evaluate_cube({"plastic": 8.0, "metal": 2.0}, 10.0)
	return JunkCube.create(info["value"], info)


func _lumi() -> Patch:
	var p := Patch.new()
	add_child_autofree(p)
	return p


# Owner item 22 (twice): a carried bale inside Lumi's body. A bale picked up while he was moving
# stayed at the height it lay at: here he falls (no floor in the test) for the whole lift.
func test_bale_picked_up_on_the_move_reaches_the_stack() -> void:
	var p: Patch = _lumi()
	var c: JunkCube = _bale()
	add_child(c)
	c.global_position = p.global_position + Vector3(0, 0.3, 0.9)
	p.pick_up(c)
	await wait_seconds(0.6)
	assert_gt(p.global_position.distance_to(Vector3.ZERO), 0.5, "the holder moved during the lift")
	var hold: Vector3 = CarryPoint.frame(p.model, p) * CarryPoint.of(p.model, p)
	var y: float = p.to_local(c.global_position).y
	assert_almost_eq(y, hold.y + c.size * 0.5, 0.06, "the bale sits on the hold point, above his head")
	assert_almost_eq(Vector2(p.to_local(c.global_position).x, p.to_local(c.global_position).z).length(), 0.08, 0.08)


# The stack is written whole every tick: a second and third bale stack up, none inside another.
func test_stack_of_three_is_spaced_by_size() -> void:
	var p: Patch = _lumi()
	for k: int in 3:
		var c: JunkCube = _bale()
		add_child(c)
		c.global_position = p.global_position + Vector3(0.8, 0.3, 0)
		p.pick_up(c)
	await wait_seconds(0.6)
	for k: int in 2:
		var gap: float = p.to_local(p.carried[k + 1].global_position).y - p.to_local(p.carried[k].global_position).y
		assert_almost_eq(gap, (p.carried[k].size + p.carried[k + 1].size) * 0.5, 0.05)


# The way up goes round him: below the hold point the bale's middle stays an arm's length out.
func test_lift_path_never_crosses_the_body() -> void:
	var rest := Vector3(0, 0.3, 0)  # stack space: the hold point is the origin
	for ang: float in [0.0, 1.0, PI * 0.5, PI, 4.0, 5.5]:
		for dist: float in [0.8, 1.0, 1.4, 1.9]:  # 0.8 m: a bale touching him
			var from := Vector3(sin(ang) * dist, -1.25, cos(ang) * dist)
			var worst: float = 9.0
			for k: int in 41:
				var q: Vector3 = Patch.lift_point(from, rest, k / 40.0)
				if q.y < 0.2:  # its underside is still below the hold point: beside his head or body
					worst = minf(worst, Vector2(q.x, q.z).length())
			assert_gt(worst, 0.79, "from %.1f rad, %.2f m" % [ang, dist])
			assert_almost_eq(Patch.lift_point(from, rest, 1.0), rest, Vector3.ONE * 0.001)


# The hold point is over the top of his solid parts, also when measured while he is hidden (in the
# rocket, behind the loader), and it is measured again after a rebuild.
func test_carry_point_while_hidden_and_after_rebuild() -> void:
	var p: Patch = _lumi()
	var shown: Vector3 = CarryPoint.of(p.model, p)
	assert_gt(shown.y, 1.2)
	p.model.remove_meta("carry_point")
	p.visible = false
	assert_almost_eq(CarryPoint.of(p.model, p).y, shown.y, 0.001, "hidden: the same point, not 0.8 m")
	p.visible = true
	var key: String = str(p.model.get_meta("carry_key"))
	p.model.set_variant("sprout")
	p.model.variant = "aurora"  # a Character Builder rebuild keeps the design name
	CarryPoint.of(p.model, p)
	assert_ne(str(p.model.get_meta("carry_key")), key, "a rebuild is measured again")


# The stack sways with real acceleration (it read zero before), and a leaning bale rises by what
# its low edge drops.
func test_stack_sways_but_never_dips() -> void:
	var p: Patch = _lumi()
	p.set_physics_process(false)
	var c: JunkCube = _bale()
	add_child(c)
	p.pick_up(c)
	p._lifts.clear()
	p._stack_acc = Vector3.ZERO
	p._update_stack(0.1)
	var rest_y: float = c.position.y
	var low: float = 9.0
	var moved: float = 0.0
	for k: int in 120:
		p._stack_acc = Vector3(12.0, 0, -22.0) if k < 40 else Vector3.ZERO
		p._update_stack(1.0 / 120.0)
		moved = maxf(moved, absf(c.rotation.x) + absf(c.rotation.z))
		low = minf(low, c.position.y - c.size * 0.5 * (absf(sin(c.rotation.x)) + absf(sin(c.rotation.z))))
	assert_gt(moved, 0.03, "it wobbles")
	assert_gt(low, rest_y - 0.005, "its low edge never comes down toward his head")
