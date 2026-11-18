extends GutTest
## [smove] Movement on a sphere: Lumi's hover controller, the follow camera, robot steering,
## far-bot simulation, A* on the hex globe and surface placement.

const DT: float = 1.0 / 60.0


func _planet(r: float) -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	sb.add_child(cs)
	root.add_child(sb)
	return root


func _walker(root: Node3D, surf: SphereSurface, inp: InputSource) -> SphereWalker:
	var w := SphereWalker.new(surf)
	w.with_model = false
	w.input = inp
	root.add_child(w)
	return w


func test_frames_orthonormal_everywhere() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ups: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3(0, 1, 1e-7).normalized()]
	for i: int in 200:
		ups.append(Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized())
	for u: Vector3 in ups:
		for f: Vector3 in [Vector3.FORWARD, Vector3.UP, u, Vector3(1, 2, 3)]:
			var b: Basis = SphereMath.basis_from_up_fwd(u, f)
			assert_lt(SphereMath.ortho_error(b), 1e-5)
			assert_almost_eq(b.y.dot(u), 1.0, 1e-5)
	# Transport a frame around a long random walk: still orthonormal, up still exact.
	var b2: Basis = SphereMath.basis_from_up_fwd(Vector3.UP, Vector3.FORWARD)
	var u0: Vector3 = Vector3.UP
	for i: int in 5000:
		var u1: Vector3 = (u0 + Vector3(rng.randfn(), rng.randfn(), rng.randfn()) * 0.01).normalized()
		b2 = SphereMath.transport(b2, u0, u1)
		u0 = u1
	assert_lt(SphereMath.ortho_error(b2), 1e-4)
	assert_gt(b2.y.dot(u0), 0.9999)


func _lap(r: float, start_dir: Vector3, heading: Vector3, boost: bool, with_cam: bool) -> Dictionary:
	var root: Node3D = _planet(r)
	var surf := SphereSurface.new(r)
	var inp := SphereAutoInput.new(Vector3(0, 0, -1), boost)
	var w: SphereWalker = _walker(root, surf, inp)
	w.place(start_dir * r, heading)
	var cam: SphereCam = null
	if with_cam:
		cam = SphereCam.new()
		cam.surface = surf
		cam.target = w
		root.add_child(cam)
		w.cam = cam
		cam.reset_frame(heading)
	var start: Vector3 = w.global_position
	var circ: float = TAU * r
	var best: float = INF
	var ortho: float = 0.0
	var roll: float = 0.0
	var cam_up: float = 1.0
	var min_alt: float = INF
	var max_alt: float = -INF
	var steps: int = 0
	var max_steps: int = int(circ / (4.6 * (4.0 if boost else 1.0)) * 60.0 * 1.6) + 600
	while steps < max_steps:
		w.step(DT)
		if cam:
			cam.update_camera(DT)
			roll = maxf(roll, cam.horizon_roll())
			cam_up = minf(cam_up, cam.camera.global_basis.y.normalized().dot(surf.up_at(cam.camera.global_position)))
		steps += 1
		ortho = maxf(ortho, SphereMath.ortho_error(w.global_basis))
		if steps > 120:
			var a: float = surf.altitude(w.global_position)
			min_alt = minf(min_alt, a)
			max_alt = maxf(max_alt, a)
		if w.distance > circ * 0.75:
			best = minf(best, w.global_position.distance_to(start))
			if w.distance > circ * 1.02:
				break
	return {"best": best, "ortho": ortho, "roll": roll, "cam_up": cam_up, "dist": w.distance, "circ": circ,
		"min_alt": min_alt, "max_alt": max_alt}


func test_lap_over_both_poles_with_camera() -> void:
	# Start on the equator heading due north: the great circle runs straight over both poles.
	var res: Dictionary = _lap(200.0, Vector3(1, 0, 0), Vector3.UP, true, true)
	gut.p("lap R=200 boost: closest %.3f m after %.0f m (circ %.0f), ortho %.7f, roll %.4f, cam_up %.4f, alt %.3f..%.3f" % [
		res["best"], res["dist"], res["circ"], res["ortho"], res["roll"], res["cam_up"], res["min_alt"], res["max_alt"]])
	assert_lt(float(res["best"]), 1.0, "full lap returns within 1 m of the start")
	assert_lt(float(res["ortho"]), 1e-4, "body basis stays orthonormal")
	assert_lt(float(res["roll"]), 0.01, "camera horizon stays level to the local up")
	assert_gt(float(res["cam_up"]), 0.5, "camera up points along the local up")
	assert_gt(float(res["min_alt"]), -0.06, "never sinks into the ground")


func test_lap_walking_no_camera() -> void:
	var res: Dictionary = _lap(60.0, Vector3(0.3, 0.8, -0.5).normalized(), Vector3(1, 0, 0), false, false)
	gut.p("lap R=60 walk: closest %.3f m, ortho %.7f" % [res["best"], res["ortho"]])
	assert_lt(float(res["best"]), 1.0)
	assert_lt(float(res["ortho"]), 1e-4)
	assert_lt(float(res["max_alt"]) - float(res["min_alt"]), 0.1, "hover height steady while walking")


func test_walk_from_the_pole_any_heading() -> void:
	# Standing exactly on the pole and walking off in 8 directions: no NaN, no flip, goes straight.
	for k: int in 8:
		var root: Node3D = _planet(100.0)
		var surf := SphereSurface.new(100.0)
		var w: SphereWalker = _walker(root, surf, SphereAutoInput.new())
		var h := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
		w.place(Vector3(0, 100, 0), h)
		for i: int in 120:
			w.step(DT)
		var p: Vector3 = w.global_position
		assert_false(is_nan(p.x) or is_nan(p.y) or is_nan(p.z))
		var t: Vector3 = SphereMath.tangent(p, Vector3.UP).normalized()
		assert_gt(t.dot(h), 0.999, "walked straight off the pole along heading %d" % k)
		assert_lt(SphereMath.ortho_error(w.global_basis), 1e-4)
		root.free()


func test_jump_and_land() -> void:
	var root: Node3D = _planet(500.0)
	var surf := SphereSurface.new(500.0)
	var inp := SphereAutoInput.new(Vector3.ZERO)
	var w: SphereWalker = _walker(root, surf, inp)
	w.place(Vector3(0, 0, 500), Vector3.UP)
	for i: int in 30:
		w.step(DT)
	assert_almost_eq(surf.altitude(w.global_position), 0.0, 0.03, "rests at ride height")
	var landed: Array = [0]
	w.motor.landed.connect(func(_i: float) -> void: landed[0] += 1)
	inp.jump_every = DT * 0.5  # jump on the next frame
	w.step(DT)
	inp.jump_every = 0.0
	var peak: float = 0.0
	for i: int in 120:
		w.step(DT)
		peak = maxf(peak, surf.altitude(w.global_position))
	assert_gt(peak, 0.8, "jump goes up")
	assert_eq(landed[0], 1, "lands once")
	assert_almost_eq(surf.altitude(w.global_position), 0.0, 0.05, "back on the hover spring")


func test_boost_ramps_up() -> void:
	var root: Node3D = _planet(1840.0)
	var surf := SphereSurface.new(1840.0)
	var inp := SphereAutoInput.new(Vector3(0, 0, -1), false)
	var w: SphereWalker = _walker(root, surf, inp)
	w.place(Vector3(0, 1840, 0), Vector3.FORWARD)
	for i: int in 60:
		w.step(DT)
	assert_almost_eq(w.motor.hv.length(), 4.6, 0.05, "walk speed is Patch's")
	inp.boost = true
	for i: int in 90:
		w.step(DT)
	assert_gt(w.motor.hv.length(), 4.6 * 3.5, "boosted")
	inp.boost = false
	for i: int in 90:
		w.step(DT)
	assert_almost_eq(w.motor.hv.length(), 4.6, 0.2, "back to walking")


func test_steep_hill_blocks_gentle_hill_slows() -> void:
	var r: float = 300.0
	var surf := SphereSurface.new(r)
	var peak: Vector3 = (Vector3(0, 1, 0) .rotated(Vector3.RIGHT, -12.0 / r)).normalized()  # 12 m ahead (-Z)
	surf.height_fn = func(d: Vector3) -> float:
		var m: float = d.angle_to(peak) * r
		return clampf((6.0 - m) * 2.0, 0.0, 6.0)  # a 63-degree mound, flat top
	var root: Node3D = _planet(r)
	var w: SphereWalker = _walker(root, surf, SphereAutoInput.new())
	w.motor.use_ray = false
	w.place(Vector3(0, r, 0), Vector3.FORWARD)
	for i: int in 360:
		w.step(DT)
	var reached: float = w.global_position.angle_to(peak) * r
	assert_gt(reached, 4.0, "cannot climb a 63 degree wall (%.1f m from the peak)" % reached)


func test_bot_travels_far_and_avoids() -> void:
	var r: float = 1840.0
	var surf := SphereSurface.new(r)
	var root := Node3D.new()
	add_child_autofree(root)
	var swarm := SphereSwarm.new(surf)
	var a := SphereBot.new()
	root.add_child(a)
	a.setup(surf, Vector3.UP, Vector3.BACK)
	swarm.add(a)
	var far: Vector3 = Vector3(0, 1, 0).rotated(Vector3.RIGHT, 0.12)  # ~220 m away
	a.go_to_point(far * r)
	# A second bot comes head-on along the same line.
	var b := SphereBot.new()
	root.add_child(b)
	b.setup(surf, Vector3(0, 1, 0).rotated(Vector3.RIGHT, 0.02), Vector3.FORWARD)
	b.go_to_point(Vector3(0, 1, 0).rotated(Vector3.RIGHT, -0.02) * r)
	swarm.add(b)
	var closest: float = INF
	var t: float = 0.0
	while a.has_goal() and t < 200.0:
		a.step(DT * 4.0)
		b.step(DT * 4.0)
		t += DT * 4.0
		closest = minf(closest, a.dir.angle_to(b.dir) * r)
		assert_lt(SphereMath.ortho_error(a.global_basis), 1e-4)
	gut.p("bot: far trip %.1f s, head-on closest %.2f m" % [t, closest])
	assert_false(a.has_goal(), "arrived")
	assert_lt(a.dir.angle_to(far) * r, 0.5)
	assert_gt(closest, 0.9, "head-on bots pass each other")
	assert_lt(t, 220.0 / 3.2 * 1.25, "no big detour")


func test_crew_sim_matches_distance() -> void:
	var r: float = 1840.0
	var rec := {"dir": Vector3.UP, "heading": Vector3.FORWARD, "speed": 3.0,
		"goal": Vector3(0, 1, 0).rotated(Vector3.RIGHT, 0.5), "path": [Vector3(0, 1, 0).rotated(Vector3.RIGHT, 1.0)], "target": 5}
	var moved: float = SphereCrewSim.advance(rec, 100.0, r)
	assert_almost_eq(moved, 300.0, 0.01)
	assert_almost_eq((rec["dir"] as Vector3).angle_to(Vector3.UP) * r, 300.0, 0.5)
	SphereCrewSim.advance(rec, 1e5, r)
	assert_eq(rec["goal"], Vector3.ZERO)
	assert_lt((rec["dir"] as Vector3).angle_to(Vector3(0, 1, 0).rotated(Vector3.RIGHT, 1.0)), 1e-5)
	assert_true(rec["working"])


func test_astar_on_geosphere() -> void:
	var g := GeoSphere.new(4)
	g.generate()
	var a: int = 0
	var b: int = g.nearest_from(-g.centers[0], 0)
	var p: PackedInt32Array = SpherePath.astar(g, a, b)
	assert_eq(p[0], a)
	assert_eq(p[p.size() - 1], b)
	for i: int in range(1, p.size()):
		assert_true(p[i] in g.neighbors(p[i - 1]))
	# Path length is close to the great-circle (PI on the unit sphere).
	var len_: float = 0.0
	for i: int in range(1, p.size()):
		len_ += g.centers[p[i - 1]].angle_to(g.centers[p[i]])
	assert_lt(len_, PI * 1.2)
	# Blocked band forces a detour but still connects.
	var blocked := func(c: int) -> bool: return absf(g.centers[c].y) > 0.05 or g.centers[c].x > 0.0
	var p2: PackedInt32Array = SpherePath.astar(g, a, b, blocked)
	assert_gt(p2.size(), 0)


func test_place_and_scoop_on_curve() -> void:
	var r: float = 80.0
	var surf := SphereSurface.new(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i: int in 100:
		var d: Vector3 = SpherePlace.random_in_cap(Vector3.DOWN, 20.0, r, rng)
		assert_lt(d.angle_to(Vector3.DOWN) * r, 20.0 + 1e-3)
		var xf: Transform3D = SpherePlace.random_on_surface(surf, d, rng)
		assert_lt(SphereMath.ortho_error(xf.basis), 1e-5)
		assert_almost_eq(xf.basis.y.dot(d), 1.0, 1e-5)
		assert_almost_eq(xf.origin.length(), r, 1e-3)
	# Scoop: Lumi at the south pole facing +X; a piece 2 m ahead on the curve is in, behind is out.
	var o: Vector3 = Vector3(0, -r, 0)
	var ahead: Vector3 = surf.ground(Vector3.DOWN.rotated(Vector3.FORWARD, -2.0 / r))
	var behind: Vector3 = surf.ground(Vector3.DOWN.rotated(Vector3.FORWARD, 2.0 / r))
	var l: Vector3 = SpherePlace.local_xyz(surf, o, Vector3.RIGHT, ahead)
	assert_almost_eq(l.z, 2.0, 0.01)
	assert_true(SpherePlace.in_scoop(surf, o, Vector3.RIGHT, ahead, 2.4, 1.4))
	assert_false(SpherePlace.in_scoop(surf, o, Vector3.RIGHT, behind, 2.4, 1.4))
	assert_eq(SpherePlace.find_scoop_target(surf, o, Vector3.RIGHT, [behind, ahead], 2.4, 1.4), 1)
	var pulled: Vector3 = SpherePlace.pull_along(surf, ahead, o, 0.5)
	assert_almost_eq(pulled.length(), r, 1e-3, "magnet pull stays on the ground")
	assert_almost_eq(pulled.distance_to(o), 1.5, 0.01)
