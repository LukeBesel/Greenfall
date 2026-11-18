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


# --- The follow camera on a round planet ---------------------------------------------------

class CamTarget:
	extends Node3D
	var model := Node3D.new()

	func _init() -> void:
		add_child(model)


func _cam_rig(wall_behind_m: float, wall_size: Vector3) -> Array:
	var r: float = 1840.0
	var t := CamTarget.new()
	add_child_autofree(t)
	t.global_position = Vector3(0, r, 0)
	var cam := SphereCam.new()
	cam.surface = SphereSurface.new(r)
	cam.target = t
	cam.input_enabled = false
	add_child_autofree(cam)
	cam.set_process(false)
	if wall_behind_m > 0.0:
		var b := StaticBody3D.new()
		b.collision_layer = PhysLayers.WORLD
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_size
		cs.shape = box
		b.add_child(cs)
		add_child_autofree(b)
		b.global_position = Vector3(0, r + wall_size.y * 0.5, wall_behind_m + wall_size.z * 0.5)
	await wait_physics_frames(3)
	cam.reset_frame(Vector3(0, 0, -1))  # looking north: the camera sits to the south (+Z)
	return [cam, t]


# A wall 1.5 m behind Lumi: the camera climbs it and looks down at him from a usable distance,
# instead of sitting 1.2 m away in the back of his head.
func test_camera_climbs_a_wall_close_behind() -> void:
	var rig: Array = await _cam_rig(1.5, Vector3(30, 30, 4))
	var cam: SphereCam = rig[0]
	var first: float = cam._arm
	assert_lt(first, 1.6, "the plain arm is cut short by the wall")
	for k: int in 180:
		cam.update_camera(1.0 / 60.0)
	assert_gt(cam._arm, 2.2, "after a moment the arm is %.2f m" % cam._arm)
	assert_gt(cam._tilt, 0.5)
	assert_lt(cam.camera.global_position.z, 1.5, "and the camera is on Lumi's side of the wall")
	assert_false(cam.hides_target(), "he is in view, not hidden")


# Open ground: full arm, no tilt, nothing hidden.
func test_camera_open_ground_is_untouched() -> void:
	var rig: Array = await _cam_rig(0.0, Vector3.ONE)
	var cam: SphereCam = rig[0]
	for k: int in 60:
		cam.update_camera(1.0 / 60.0)
	assert_almost_eq(cam._arm, cam.distance, 0.01)
	assert_almost_eq(cam._tilt, 0.0, 0.001)


# A post crossing the line between camera and Lumi does not yank the camera in.
func test_camera_ignores_a_small_thing_on_the_line() -> void:
	var rig: Array = await _cam_rig(3.0, Vector3(0.4, 8.0, 0.4))
	var cam: SphereCam = rig[0]
	for k: int in 30:
		cam.update_camera(1.0 / 60.0)
	assert_gt(cam._arm, cam.distance - 0.3, "arm %.2f m" % cam._arm)


# Boxed in on every side (an alcove): the arm has nowhere to go, so Lumi is hidden rather than
# filling the screen, and shown again when there is room.
func test_camera_hides_lumi_only_when_it_is_in_his_head() -> void:
	var rig: Array = await _cam_rig(0.9, Vector3(30, 30, 4))
	var cam: SphereCam = rig[0]
	var t: CamTarget = rig[1]
	var roof := StaticBody3D.new()
	roof.collision_layer = PhysLayers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	cs.shape = box
	roof.add_child(cs)
	add_child_autofree(roof)
	roof.global_position = Vector3(0, 1840.0 + 2.4, 0)
	await wait_physics_frames(3)
	for k: int in 120:
		cam.update_camera(1.0 / 60.0)
	assert_lt(cam._arm, SphereCam.HIDE_IN_M)
	assert_false(t.model.visible, "hidden while the camera is inside him")
	roof.global_position = Vector3(0, 1840.0 + 400.0, 0)
	t.global_position = Vector3(0, 1840.0, -20.0)
	await wait_physics_frames(3)
	for k: int in 240:
		cam.update_camera(1.0 / 60.0)
	assert_true(t.model.visible, "back in view")


# Screen shake reaches the globe's camera, and Reduced motion switches it off.
func test_camera_shake_on_the_globe() -> void:
	var rig: Array = await _cam_rig(0.0, Vector3.ONE)
	var cam: SphereCam = rig[0]
	var was_rm: bool = Settings.reduced_motion
	var was_sh: float = Settings.shake_intensity
	Settings.reduced_motion = false
	Settings.shake_intensity = 1.0
	EventBus.shake_requested.emit(0.5)
	cam.update_camera(1.0 / 60.0)
	assert_gt(absf(cam.camera.h_offset) + absf(cam.camera.v_offset), 0.001)
	for k: int in 120:
		cam.update_camera(1.0 / 60.0)
	assert_almost_eq(cam.camera.h_offset, 0.0, 0.0001, "it dies away")
	Settings.reduced_motion = true
	EventBus.shake_requested.emit(0.5)
	cam.update_camera(1.0 / 60.0)
	assert_almost_eq(cam.camera.h_offset, 0.0, 0.0001)
	Settings.reduced_motion = was_rm
	Settings.shake_intensity = was_sh
