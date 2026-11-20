extends GutTest
## [v11jump] Owner, 20 Nov: "Also build in jump mechanic". Lumi's hop on a round planet: along his
## own up anywhere on the globe, a held hop reaches the height in data/patch.json, a tap is a small
## one, a press just before landing and just after gliding off an edge still hops, junk heaps stay
## walls in the air, a bale holds him, and Space / A are the keys (A shared with "use").

const R: float = 1840.0
## The tests count in 60ths of a second; the game's physics may tick faster (120 Hz).
var SCALE: int = maxi(1, roundi(Engine.physics_ticks_per_second / 60.0))

var lumi: Patch
var inp: FeelProbe.FeelInput
var _up := Vector3.UP


func before_each() -> void:
	_place(Vector3.UP)


func _place(up: Vector3) -> void:
	if lumi:
		lumi.free()
	_up = up.normalized()
	var surf := SphereSurface.new(R)
	lumi = Patch.new()
	inp = FeelProbe.FeelInput.new()
	inp.world_space = true
	lumi.input = inp
	lumi.enable_sphere(surf, null)
	add_child_autofree(lumi)
	lumi.place_on_sphere(_up * R, SphereMath.any_perpendicular(_up))


func _cfg() -> Dictionary:
	return Economy.read_json("res://data/patch.json").get("jump", {})


func _alt() -> float:
	return lumi.sphere.altitude(lumi.global_position)


func _solid(shape: Shape3D, at: Vector3, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	add_child_autofree(b)
	b.global_position = Vector3(at.x, R + at.y, at.z)
	return b


func _box(size: Vector3, at: Vector3, layer: int = PhysLayers.PROP) -> StaticBody3D:
	var s := BoxShape3D.new()
	s.size = size
	return _solid(s, at, layer)


func _ticks(n: int) -> void:
	for k: int in n * SCALE:
		await get_tree().physics_frame


## Presses the hop for `hold_ticks` physics ticks; returns [peak height, seconds in the air,
## landings, largest sideways drift from the start].
func _hop(hold_ticks: int, max_ticks: int = 120) -> Array:
	var landed: Array = [0]
	var cb := func(_i: float) -> void: landed[0] += 1
	lumi.sphere_motor.landed.connect(cb)
	var a0: float = _alt()
	var p0: Vector3 = lumi.global_position
	inp.jump = true
	inp.jump_hold = hold_ticks > 0
	var peak: float = 0.0
	var air_ticks: int = 0
	var drift: float = 0.0
	for k: int in max_ticks * SCALE:
		await get_tree().physics_frame
		if k + 1 >= hold_ticks * SCALE:
			inp.jump_hold = false
		peak = maxf(peak, _alt() - a0)
		var d: Vector3 = lumi.global_position - p0
		drift = maxf(drift, (d - _up * d.dot(_up)).length())
		if not lumi.sphere_motor.grounded:
			air_ticks += 1
		elif air_ticks > 0:
			break
	lumi.sphere_motor.landed.disconnect(cb)
	return [peak, float(air_ticks) / Engine.physics_ticks_per_second, landed[0], drift]


func test_held_hop_reaches_the_set_height_and_lands_once() -> void:
	await _ticks(20)
	var j: Dictionary = _cfg()
	var r: Array = await _hop(60)
	var h: float = float(j["height_m"])
	assert_almost_eq(float(r[0]), h, 0.08, "a held hop rises %.2f m (rose %.2f)" % [h, float(r[0])])
	assert_almost_eq(float(r[1]), float(j["rise_s"]) + float(j["fall_s"]), 0.08, "in the air %.2f s" % float(r[1]))
	assert_eq(int(r[2]), 1, "lands once")
	await _ticks(20)
	assert_almost_eq(_alt(), 0.0, 0.03, "back on the hover spring")
	assert_true(lumi.sphere_motor.grounded)


func test_height_is_small_on_purpose() -> void:
	# What he can get onto is about height_m + 0.25 m (his body rides 0.25 m up): bales and kerbs,
	# never a 1 m fence or bin. Raising it needs the world audits rerun (docs/ADJUSTING.md).
	assert_between(float(_cfg()["height_m"]), 0.4, 0.65)


func test_tap_is_a_small_hop() -> void:
	await _ticks(20)
	var tap: Array = await _hop(1)
	await _ticks(20)
	var held: Array = await _hop(60)
	assert_between(float(tap[0]), 0.1, float(held[0]) * 0.6, "tap %.2f m, held %.2f m" % [float(tap[0]), float(held[0])])
	assert_lt(float(tap[1]), float(held[1]) - 0.1, "and it is shorter")


func test_hop_is_along_his_own_up_anywhere() -> void:
	for up: Vector3 in [Vector3.DOWN, Vector3(1, 0, 0), Vector3(-0.4, -0.7, 0.6), Vector3(0.2, 0.3, -0.9)]:
		_place(up)
		await _ticks(20)
		var r: Array = await _hop(60)
		assert_almost_eq(float(r[0]), float(_cfg()["height_m"]), 0.08, "height at up %s" % str(up))
		assert_lt(float(r[3]), 0.02, "no sideways drift at up %s (%.3f m)" % [str(up), float(r[3])])
		assert_eq(int(r[2]), 1, "lands once at up %s" % str(up))
		assert_lt(SphereMath.ortho_error(lumi.global_basis), 1e-4)
		assert_gt(lumi.global_basis.y.dot(_up), 0.9999, "he stays upright")


func test_press_just_before_landing_hops_again() -> void:
	await _ticks(20)
	inp.jump = true
	inp.jump_hold = true
	var hops: Array = [0]
	lumi.sphere_motor.jumped.connect(func() -> void: hops[0] += 1)
	await _ticks(4)
	assert_eq(hops[0], 1)
	# Wait until he is on the way down and close to the ground, then press (still in the air).
	for k: int in 60 * SCALE:
		await get_tree().physics_frame
		if lumi.sphere_motor.vv < 0.0 and _alt() < 0.25:
			break
	assert_false(lumi.sphere_motor.grounded, "still in the air at the press")
	inp.jump = true
	await _ticks(12)
	assert_eq(hops[0], 2, "the early press hopped on landing")
	# A press at the top of a hop is too early: no second hop from it.
	await _ticks(60)
	hops[0] = 0
	inp.jump = true
	await _ticks(10)
	inp.jump = true
	await _ticks(60)
	assert_eq(hops[0], 1, "a press at the top is forgotten (no double hop, no hop a second later)")


func test_coyote_hop_after_gliding_off_an_edge() -> void:
	# A platform 1.6 m high that ends 1 m ahead of him.
	_box(Vector3(3, 1.6, 4), Vector3(0, 0.8, 1.0))
	lumi.place_on_sphere(Vector3(0, R + 1.6, 0), Vector3(0, 0, -1))
	lumi.global_position = Vector3(0, R + 1.6, 0)
	await _ticks(30)
	assert_almost_eq(_alt(), 1.6, 0.06, "stands on the platform")
	inp.stick = Vector3(0, 0, -1)
	var hops: Array = [0]
	lumi.sphere_motor.jumped.connect(func() -> void: hops[0] += 1)
	for k: int in 120 * SCALE:
		await get_tree().physics_frame
		if not lumi.sphere_motor.grounded:
			break
	assert_false(lumi.sphere_motor.grounded, "glided off the edge")
	await _ticks(3)  # 0.05 s later, inside coyote_s
	inp.jump = true
	inp.jump_hold = true
	await _ticks(3)
	assert_eq(hops[0], 1, "he still hops just after the edge")
	# Much later in the fall: nothing.
	await _ticks(12)
	inp.jump = true
	await _ticks(3)
	assert_eq(hops[0], 1, "no hop in mid fall")
	await _ticks(90)
	assert_true(lumi.sphere_motor.grounded, "and he lands on the ground below")
	assert_almost_eq(_alt(), 0.0, 0.05)


func test_no_hop_while_pressing_a_bale_or_in_a_film() -> void:
	await _ticks(20)
	lumi._cubing = 1.0
	inp.jump = true
	inp.jump_hold = true
	await _ticks(6)
	assert_true(lumi.sphere_motor.grounded, "pressing a bale: no hop")
	lumi._cubing = 0.0
	lumi.cine_hold = true
	inp.jump = true
	await _ticks(6)
	assert_true(lumi.sphere_motor.grounded, "a film is acting with Lumi: no hop")
	lumi.cine_hold = false
	await _ticks(30)
	assert_true(lumi.sphere_motor.grounded, "and the blocked press does not fire afterwards")


func test_hops_onto_a_low_crate() -> void:
	var h: float = float(_cfg()["height_m"])
	# A crate just under what he can reach (his body rides 0.25 m up), 2 m ahead.
	var top: float = h + 0.1
	_box(Vector3(2.4, top, 2.4), Vector3(0, top * 0.5, -3.0))
	await _ticks(20)
	inp.stick = Vector3(0, 0, -1)
	await _ticks(60)
	assert_almost_eq(_alt(), 0.0, 0.05, "walking does not climb it")
	for k: int in 4:
		inp.jump = true
		inp.jump_hold = true
		await _ticks(40)
		if _alt() > top - 0.1:
			break
	inp.stick = Vector3.ZERO
	await _ticks(30)
	assert_almost_eq(_alt(), top, 0.08, "stands on the %.2f m crate (at %.2f)" % [top, _alt()])
	assert_true(lumi.sphere_motor.grounded)
	assert_lt(lumi.global_position.z, -1.9, "on it, not at its edge")
	# Off the far side: a drop, no harm.
	inp.stick = Vector3(0, 0, -1)
	await _ticks(90)
	inp.stick = Vector3.ZERO
	await _ticks(30)
	assert_almost_eq(_alt(), 0.0, 0.05, "and down the other side")
	assert_true(lumi.sphere_motor.grounded)


func test_cannot_hop_a_fence_or_onto_the_workbench() -> void:
	# The workbench's top is 0.95 m, a fence 1.8 m: both stay out of reach, however often he hops.
	_box(Vector3(12, 0.95, 0.8), Vector3(0, 0.475, -3.0))
	await _ticks(20)
	inp.stick = Vector3(0, 0, -1)
	var top: float = 0.0
	for k: int in 6:
		await _ticks(25)
		inp.jump = true
		inp.jump_hold = true
		for t: int in 20 * SCALE:
			await get_tree().physics_frame
			top = maxf(top, _alt())
	inp.stick = Vector3.ZERO
	await _ticks(40)
	assert_gt(lumi.global_position.z, -2.2, "still on his side (z %.2f)" % lumi.global_position.z)
	assert_almost_eq(_alt(), 0.0, 0.05)
	assert_lt(top, float(_cfg()["height_m"]) + 0.05, "no boost from clipping its top edge (rose %.2f m)" % top)


func test_junk_heap_is_a_wall_in_the_air() -> void:
	# A low heap (0.5 m at its top) dead ahead: on the ground he cannot walk in; hopping he cannot
	# get onto or over it either.
	var holder := Node3D.new()
	add_child_autofree(holder)
	holder.global_position = Vector3(0, R, 0)
	var m: StaticBody3D = MoundColliders.make(holder, Vector4(0.0, -4.0, 1.6, 0.5))
	MoundColliders.update(m, Vector3(1.7, 0.5, 1.7), true, 1.0)
	await _ticks(20)
	inp.stick = Vector3(0, 0, -1)
	await _ticks(150)
	var walked: float = Vector2(lumi.global_position.x, lumi.global_position.z + 4.0).length()
	assert_gt(walked, 1.2, "on the ground the heap stops him (%.2f m from its middle)" % walked)
	var nearest: float = 99.0
	var hops: Array = [0]
	lumi.sphere_motor.jumped.connect(func() -> void: hops[0] += 1)
	for k: int in 8:
		inp.jump = true
		inp.jump_hold = true
		for t: int in 40 * SCALE:
			await get_tree().physics_frame
			nearest = minf(nearest, Vector2(lumi.global_position.x, lumi.global_position.z + 4.0).length())
	inp.stick = Vector3.ZERO
	await _ticks(40)
	assert_gt(hops[0], 5, "he did hop")
	assert_gt(nearest, walked - 0.08, "hopping gets him no further in (nearest %.2f m, walking %.2f m)" % [nearest, walked])
	assert_lt(_alt(), 0.12, "and he ends on the ground, at the heap's foot")


func test_lands_on_a_bale_and_stays_put() -> void:
	# A bale (CUBE layer: the ground ray does not see it) under his landing: he rests on it, with
	# one landing, not a fall every few frames.
	var s := BoxShape3D.new()
	s.size = Vector3(0.6, 0.6, 0.6)
	_solid(s, Vector3(0, 0.3, -1.6), PhysLayers.CUBE)
	await _ticks(20)
	inp.stick = Vector3(0, 0, -1)
	await _ticks(5)
	var landed: Array = [0]
	lumi.sphere_motor.landed.connect(func(_i: float) -> void: landed[0] += 1)
	inp.jump = true
	inp.jump_hold = true
	await _ticks(16)
	inp.stick = Vector3.ZERO
	await _ticks(80)
	if _alt() > 0.2:  # he came down on it
		assert_almost_eq(_alt(), 0.6 - 0.25, 0.08, "resting on the bale's top")
		assert_eq(landed[0], 1, "one landing")
		var a: float = _alt()
		await _ticks(40)
		assert_almost_eq(_alt(), a, 0.01, "no bobbing on it")
		# Walking off it sets him down on the ground.
		inp.stick = Vector3(0, 0, -1)
		await _ticks(60)
		inp.stick = Vector3.ZERO
		await _ticks(30)
	assert_almost_eq(_alt(), 0.0, 0.05, "on the ground at the end")
	assert_true(lumi.sphere_motor.grounded)


func test_space_and_a_are_the_hop_and_rebindable() -> void:
	assert_true(InputMap.has_action("jump"))
	var k: InputEventKey = Settings.binding("jump", false) as InputEventKey
	assert_eq(k.physical_keycode, KEY_SPACE)
	var b: InputEventJoypadButton = Settings.binding("jump", true) as InputEventJoypadButton
	assert_eq(b.button_index, JOY_BUTTON_A)
	var names: Array = Settings.REBINDABLE.map(func(e: Array) -> String: return e[0])
	assert_true(names.has("jump"), "in the Controls list")
	assert_eq(Settings.conflicts(), {}, "A for use and hop is meant (no conflict shown)")
	var sp := InputEventKey.new()
	sp.physical_keycode = KEY_SPACE
	assert_false(InputMap.action_has_event("scoop", sp), "Space no longer scoops")
	assert_eq(Settings.find_conflict("drop", b), "interact", "a third action on A is still a conflict")


func test_use_wins_the_shared_button() -> void:
	await _ticks(20)
	lumi.prompt = "pick_up"
	inp.interact = true
	assert_true(lumi._use_takes_press(), "something to use: the press is 'use'")
	lumi.prompt = ""
	inp.interact = true
	assert_false(lumi._use_takes_press(), "nothing to use: the press is the hop")


func test_camera_leaves_out_most_of_a_hop() -> void:
	var cam := SphereCam.new()
	cam.surface = lumi.sphere
	cam.target = lumi
	cam.input_enabled = false
	add_child_autofree(cam)
	await _ticks(10)
	cam.reset_frame(Vector3(0, 0, -1))
	await _ticks(40)
	var c0: float = cam.camera.global_position.y
	var a0: float = _alt()
	inp.jump = true
	inp.jump_hold = true
	var peak: float = 0.0
	var cam_move: float = 0.0
	for k: int in 70 * SCALE:
		await get_tree().physics_frame
		await get_tree().process_frame
		peak = maxf(peak, _alt() - a0)
		cam_move = maxf(cam_move, absf(cam.camera.global_position.y - c0))
	assert_gt(peak, 0.5, "he hopped")
	assert_lt(cam_move, peak * 0.3, "the camera moved %.2f m for a %.2f m hop" % [cam_move, peak])
	# Three hops in a row: still calm.
	cam_move = 0.0
	for h: int in 3:
		inp.jump = true
		for k: int in 40 * SCALE:
			await get_tree().physics_frame
			await get_tree().process_frame
			cam_move = maxf(cam_move, absf(cam.camera.global_position.y - c0))
	assert_lt(cam_move, peak * 0.3, "hopping again and again: %.2f m" % cam_move)


func test_puff_and_dust_rise_along_the_local_up() -> void:
	# Bursts used the world's Y: sideways or into the ground away from the start.
	var was: float = JunkCube.planet_radius
	JunkCube.planet_radius = R
	for up: Vector3 in [Vector3.DOWN, Vector3(1, 0, 0), Vector3(-0.4, -0.7, 0.6).normalized(), Vector3.UP]:
		for kind: String in ["puff", "dust"]:
			var i0: int = Vfx._pool_idx[kind]
			Vfx.burst(kind, up * R, Color.WHITE, 1.0)
			var p: CPUParticles3D = (Vfx._pools[kind] as Array)[i0]
			assert_gt(p.global_basis.y.dot(up), 0.999, "%s points up at %s" % [kind, str(up)])
			assert_gt(p.gravity.normalized().dot(up), 0.999, "%s drifts up there too" % kind)
	JunkCube.planet_radius = was
