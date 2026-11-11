class_name FeelProbe
extends Node
## [v6feel] Scripted feel checks on the round game: a timeline drives Lumi (FeelInput) and the probe
## prints what a player would notice, as `[feel]` lines. Headless, add `-- --fresh --orbit --no-intro`:
##   --feel=carry --orbit-carry=N   gap between the carried bales and Lumi's body, per phase
##                                  (idle, walk, turn, boost, stop, put down, pick up). Exit 1 if a
##                                  bale ever touches a solid part of him.
##   --feel=move                    start / stop times, top speeds, hover height jitter.
##   --feel=cam                     camera arm and jumps along a walk (--feel-walk=x,z;x,z;... in
##                                  metres from the start cell).
##   --feel=snag                    pushes Lumi at the known snag corners; reports ground covered.
##   --feel=walk                    snag walk: Lumi really walks random straight legs through each
##                                  hub town (--feel-hubs=0,1,.. default all, --feel-legs=N per hub,
##                                  --feel-seed=S). "clear" legs keep 0.15 m off everything, "graze"
##                                  legs brush something, "step" legs cross something under 0.5 m
##                                  (kerbs, steps, low planters: he hovers over up to 0.45 m). Then
##                                  glancing pushes past small things (--feel-props=N per hub). Prints each catch (speed under half for
##                                  0.25 s), hop (the ride height kicks) and swerve as `[snag]` lines
##                                  with the collider. Exit 1 (with --feel-quit) on a catch.
##                                  --feel-boost walks the legs boosting. Add --fixed-fps 60 before
##                                  `--` to run faster than real time.
## --feel-quit quits when the timeline ends.

class FeelInput:
	extends InputSource
	var stick := Vector3.ZERO  # camera-local (x right, z back), or world space with world_space
	var world_space: bool = false
	var boost: bool = false
	var scoop: bool = false
	var jump: bool = false
	var cube: bool = false
	var interact: bool = false
	var drop: bool = false

	func get_world_move(_cam_yaw: float) -> Vector3:
		return stick

	func scoop_held() -> bool:
		return scoop

	func boost_held() -> bool:
		return boost

	func jump_pressed() -> bool:
		var j: bool = jump
		jump = false
		return j

	func cube_pressed() -> bool:
		var c: bool = cube
		cube = false
		return c

	func interact_pressed() -> bool:
		var i: bool = interact
		interact = false
		return i

	func drop_pressed() -> bool:
		var d: bool = drop
		drop = false
		return d


var so: Node  # SliceOrbit
var lumi: Patch
var inp := FeelInput.new()
var mode: String = ""
var _t: float = 0.0
var _phase: String = ""
var _steps: Array = []  # [until_s, name, Callable(inp, t_in_phase)]
var _acc: Dictionary = {}
var _fail: bool = false
var _done: bool = false
var _shot_next: float = 0.0
var _shot_n: int = 0
var _verts: Dictionary = {}  # Mesh -> PackedVector3Array (thinned)


static func attach(p_so: Node) -> void:
	var p := FeelProbe.new()
	p.name = "FeelProbe"
	p.so = p_so
	p.mode = DevHooks.get_s("feel", "carry")
	p_so.w.add_child(p)


func _ready() -> void:
	lumi = so.w.get("patch")
	process_physics_priority = 100  # after Lumi's own step
	await get_tree().create_timer(DevHooks.get_f("feel-delay", 3.0)).timeout
	lumi.input = inp
	match mode:
		"carry":
			_steps = _carry_steps()
		"move":
			_steps = _move_steps()
		"tour":
			GameState.upgrades["baler"] = 1
			_steps = _tour_steps()
		"bale":  # press a full chest, pick the bale up on the move, carry, boost, put down
			GameState.upgrades["baler"] = 1
			lumi.compartment.add("plastic", lumi.capacity() * 0.7)
			lumi.compartment.add("metal", lumi.capacity() * 0.25)
			_steps = _bale_steps()
		"map":
			_map()
			return
		"snag":
			_snag()
			return
		"walk":
			_snag_walk()
			return
		"props":
			_props_audit()
			return
		"cam":
			_cam_walk()
			return
		"camwall":
			_cam_wall()
			return
	_t = 0.0
	set_physics_process(true)
	print("[feel] %s: start, design %s, %d bales" % [mode, lumi.model.variant, lumi.carried.size()])


func _fwd(i: FeelInput, _t_in: float) -> void:
	i.stick = Vector3(0, 0, -1)


func _carry_steps() -> Array:
	return [
		[1.5, "idle", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[4.5, "walk", _fwd],
		[5.5, "stop", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[9.5, "turn", func(i: FeelInput, s: float) -> void: i.stick = Vector3(sin(s * 3.0), 0, -cos(s * 3.0))],
		[11.0, "zigzag", func(i: FeelInput, s: float) -> void: i.stick = Vector3(1.0 if fmod(s, 0.5) < 0.25 else -1.0, 0, 0)],
		[15.0, "boost", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.boost = true],
		[16.5, "boost_stop", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3.ZERO
			i.boost = false],
		[18.5, "scoop_walk", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.scoop = true],
		[19.5, "jump", func(i: FeelInput, s: float) -> void:
			i.scoop = false
			i.stick = Vector3(0, 0, -1)
			i.jump = s < 0.05],
		[20.5, "put_down", func(i: FeelInput, s: float) -> void:
			i.stick = Vector3.ZERO
			i.drop = s < 0.02],
		[22.0, "pick_up", func(i: FeelInput, s: float) -> void: i.interact = s < 0.02],
	]


func _move_steps() -> Array:
	return [
		[1.0, "idle", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[3.0, "start", _fwd],
		[4.5, "stop", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[6.5, "reverse", func(i: FeelInput, _s: float) -> void: i.stick = Vector3(0, 0, 1)],
		[8.0, "stop2", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[12.0, "boost", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.boost = true],
		[14.0, "boost_stop", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3.ZERO
			i.boost = false],
		[20.0, "walk_long", _fwd],
	]


func _physics_process(delta: float) -> void:
	if _steps.is_empty() or _done:
		return
	_t += delta
	var start: float = 0.0
	var cur: Array = []
	for s: Array in _steps:
		if _t < float(s[0]):
			cur = s
			break
		start = float(s[0])
	if cur.is_empty():
		_flush()
		_done = true
		print("[feel] %s: %s" % [mode, "FAIL" if _fail else "PASS"])
		if DevHooks.has("feel-quit"):
			get_tree().quit(1 if _fail else 0)
		return
	if str(cur[1]) != _phase:
		_flush()
		_phase = str(cur[1])
		_acc = {}
	(cur[2] as Callable).call(inp, _t - start)
	if DevHooks.has("feel-shots") and _t >= _shot_next:  # frame sequences (rendered runs)
		_shot_next = _t + DevHooks.get_f("feel-shots", 0.5)
		DevHooks.save_viewport("screenshots/v6feel/%s_%02d_%s.png" % [mode, _shot_n, _phase])
		_shot_n += 1
	match mode:
		"carry", "bale":
			_carry_sample()
		"move":
			_move_sample(delta, _t - start)


func _flush() -> void:
	if _phase == "" or _acc.is_empty():
		return
	match mode:
		"carry", "bale":
			var solid: float = float(_acc.get("solid", 9.0))
			var thin: float = float(_acc.get("thin", 9.0))
			var bad: bool = solid < 0.0
			_fail = _fail or bad
			var ys: Array = []
			for c: JunkCube in lumi.carried:
				ys.append(snappedf(lumi.to_local(c.global_position).y, 0.01))
			print("[feel] carry   bale heights %s, hold point %.2f, sizes %s" % [str(ys), lumi.get_node("Stack").position.y, str(lumi.carried.map(func(c: JunkCube) -> float: return snappedf(c.size, 0.01)))])
			print("[feel] carry %-10s gap to body %+.3f m (%s)  to thin parts %+.3f m (%s)  bales %d%s" % [_phase, solid, str(_acc.get("solid_part", "-")), thin, str(_acc.get("thin_part", "-")), lumi.carried.size(), "  CLIP" if bad else ""])
		"move":
			print("[feel] move %-10s %s" % [_phase, JSON.stringify(_acc)])


# --- carry: how close the bales come to Lumi's own meshes -----------------------------------

func _mesh_verts(m: Mesh) -> PackedVector3Array:
	if _verts.has(m):
		return _verts[m]
	var out := PackedVector3Array()
	var seen: Dictionary = {}
	for v: Vector3 in m.get_faces():
		var k: Vector3i = Vector3i((v * 200.0).round())
		if not seen.has(k):
			seen[k] = true
			out.append(v)
	_verts[m] = out
	return out


## Signed gap (m) between every carried bale's drawn block and Lumi's meshes: below 0 = inside.
func _carry_sample() -> void:
	if lumi.carried.is_empty():
		return
	var holder_inv: Transform3D = lumi.global_transform.affine_inverse()
	for n: Node in lumi.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.top_level:
			continue
		var ab: AABB = (holder_inv * mi.global_transform) * mi.mesh.get_aabb()
		if ab.position.y > 2.5 or ab.end.y < 0.5:
			continue
		var thin: bool = ab.size.x < 0.12 and ab.size.z < 0.12
		var vs: PackedVector3Array = _mesh_verts(mi.mesh)
		for c: JunkCube in lumi.carried:
			var vis: MeshInstance3D = c.get("_visual")
			var xf: Transform3D = vis.global_transform.affine_inverse() * mi.global_transform
			var sc: Vector3 = vis.global_basis.get_scale()
			var best: float = 9.0
			for v: Vector3 in vs:
				var p: Vector3 = xf * v
				# Unit block: distance outside the nearest face, in metres.
				var d: float = maxf(maxf((absf(p.x) - 0.52) * sc.x, (absf(p.y) - 0.52) * sc.y), (absf(p.z) - 0.52) * sc.z)
				if d < best:
					best = d
			var key: String = "thin" if thin else "solid"
			if best < float(_acc.get(key, 9.0)):
				_acc[key] = best
				_acc[key + "_part"] = str(mi.mesh.resource_name if mi.mesh.resource_name != "" else mi.get_parent().name)


# --- move: timings ----------------------------------------------------------------------------

func _move_sample(delta: float, s: float) -> void:
	var m: SphereMotor = lumi.sphere_motor
	var spd: float = m.hv.length()
	_acc["top"] = snappedf(maxf(float(_acc.get("top", 0.0)), spd), 0.01)
	_acc["end"] = snappedf(spd, 0.01)
	var walk: float = lumi.stat("move_speed")
	if not _acc.has("t90") and spd >= walk * 0.9:
		_acc["t90"] = snappedf(s, 0.01)
	if not _acc.has("t_stop") and spd <= 0.05 and s > delta * 2.0:
		_acc["t_stop"] = snappedf(s, 0.01)
	var alt: float = lumi.sphere.altitude(lumi.global_position)
	_acc["alt_min"] = snappedf(minf(float(_acc.get("alt_min", 9.0)), alt), 0.001)
	_acc["alt_max"] = snappedf(maxf(float(_acc.get("alt_max", -9.0)), alt), 0.001)
	_acc["vv_max"] = snappedf(maxf(float(_acc.get("vv_max", 0.0)), absf(m.vv)), 0.01)


# --- tour: every core action in a row, for frame sequences ---------------------------------------

func _tour_steps() -> Array:
	return [
		[1.0, "idle", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[2.5, "walk", _fwd],
		[9.0, "scoop", func(i: FeelInput, s: float) -> void:
			i.stick = Vector3(sin(s * 0.8) * 0.5, 0, -0.5)
			i.scoop = true],
		[11.5, "press", func(i: FeelInput, s: float) -> void:
			i.stick = Vector3.ZERO
			i.scoop = false
			i.cube = s < 0.02],
		[12.5, "turn_back", func(i: FeelInput, _s: float) -> void: i.stick = Vector3(0, 0, 1)],
		[13.5, "pick_up", func(i: FeelInput, s: float) -> void:
			i.stick = Vector3(0, 0, 0.3) if s < 0.5 else Vector3.ZERO
			i.interact = s > 0.3 and lumi.carried.is_empty() and lumi.nearest_loose_cube() != null],
		[16.0, "carry", func(i: FeelInput, s: float) -> void: i.stick = Vector3(sin(s * 2.0), 0, -cos(s * 2.0))],
		[19.0, "boost", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.boost = true],
		[20.0, "stop", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3.ZERO
			i.boost = false],
	]


func _bale_steps() -> Array:
	return [
		[0.6, "idle", func(i: FeelInput, _s: float) -> void: i.stick = Vector3.ZERO],
		[2.8, "press", func(i: FeelInput, s: float) -> void: i.cube = s < 0.02],
		[3.6, "turn_back", func(i: FeelInput, _s: float) -> void: i.stick = Vector3(0, 0, 1)],
		[4.6, "pick_up", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0.4, 0, 0.6)
			i.interact = lumi.carried.is_empty() and lumi.nearest_loose_cube() != null],
		[6.6, "carry", func(i: FeelInput, s: float) -> void: i.stick = Vector3(sin(s * 2.0), 0, -cos(s * 2.0))],
		[8.6, "boost", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3(0, 0, -1)
			i.boost = true],
		[9.4, "stop", func(i: FeelInput, _s: float) -> void:
			i.stick = Vector3.ZERO
			i.boost = false],
		[10.4, "put_down", func(i: FeelInput, s: float) -> void: i.drop = s < 0.02],
	]


# --- placing Lumi (start-site metres, as --orbit-spawn) -------------------------------------------

func _dir_at(x: float, z: float) -> Vector3:
	var g: OrbitPlanet = so.globe
	return g.terrain.local_to_dir(g.start_cell(), x, z)


func _pos_at(x: float, z: float) -> Vector3:
	return so.globe.terrain.ground(_dir_at(x, z))


func _site_xz(p: Vector3) -> Vector2:
	# Inverse of _pos_at by two probes (the cell frame is flat enough near the start).
	var o: Vector3 = _pos_at(0, 0)
	var ex: Vector3 = (_pos_at(1, 0) - o)
	var ez: Vector3 = (_pos_at(0, 1) - o)
	var d: Vector3 = p - o
	return Vector2(d.dot(ex) / ex.length_squared(), d.dot(ez) / ez.length_squared())


func _put(x: float, z: float, toward: Vector2) -> void:
	var from: Vector3 = _pos_at(x, z)
	var to: Vector3 = _pos_at(toward.x, toward.y)
	lumi.place_on_sphere(from, to - from)
	lumi.velocity = Vector3.ZERO
	if so.cam:
		so.cam.reset_frame(to - from)


## Every solid thing on the start site near (x, z): what Lumi and the camera can meet.
func _map() -> void:
	var c: PackedStringArray = DevHooks.get_s("feel-at", "0,0,30").split(",")
	var at := Vector2(float(c[0]), float(c[1]))
	var r: float = float(c[2]) if c.size() > 2 else 30.0
	var n: int = 0
	for node: Node in so.w.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		var body: CollisionObject3D = cs.get_parent() as CollisionObject3D
		if body == null or cs.shape == null or cs.disabled or body == lumi:
			continue
		var xz: Vector2 = _site_xz(cs.global_position)
		if xz.distance_to(at) > r:
			continue
		var sz: String = ""
		if cs.shape is BoxShape3D:
			sz = "box %s" % str(((cs.shape as BoxShape3D).size * cs.global_basis.get_scale()).snappedf(0.1))
		elif cs.shape is CylinderShape3D:
			sz = "cyl r%.2f h%.1f" % [(cs.shape as CylinderShape3D).radius, (cs.shape as CylinderShape3D).height]
		else:
			sz = cs.shape.get_class()
		print("[feel] map (%6.1f,%6.1f) alt %.1f layer %d %s  %s/%s" % [xz.x, xz.y, so.globe.surface.altitude(cs.global_position), body.collision_layer, sz, body.get_parent().name, body.name])
		n += 1
	print("[feel] map: %d shapes within %.0f m of (%.0f, %.0f)" % [n, r, at.x, at.y])
	if DevHooks.has("feel-quit"):
		get_tree().quit(0)


# --- snag: push at a spot from every side, dead on and glancing --------------------------------

func _snag() -> void:
	inp.world_space = true
	var spots: Array = []
	for part: String in DevHooks.get_s("feel-at", "11,12;-7.7,9.3").split(";"):
		var c: PackedStringArray = part.split(",")
		spots.append(Vector2(float(c[0]), float(c[1])))
	var worst: float = 99.0
	for spot: Vector2 in spots:
		var stuck: PackedStringArray = []
		var total: int = 0
		var slid: int = 0
		for h: int in 8:
			var d := Vector2(cos(h * TAU / 8.0), sin(h * TAU / 8.0))
			var side := Vector2(-d.y, d.x)
			for off: float in [-1.5, -0.9, -0.45, 0.45, 0.9, 1.5]:
				var a: Vector2 = spot - d * 5.0 + side * off
				_put(a.x, a.y, a + d)
				await get_tree().physics_frame
				var p0: Vector3 = lumi.global_position
				var w: Vector3 = (_pos_at(a.x + d.x * 20.0, a.y + d.y * 20.0) - p0).normalized()
				inp.stick = w
				var still: float = 0.0
				var t: float = 0.0
				while t < 2.6:
					await get_tree().physics_frame
					t += get_physics_process_delta_time()
					if lumi.sphere_motor.hv.length() < 0.4 and t > 0.4:
						still += get_physics_process_delta_time()
					if DevHooks.get_s("feel-debug", "") == "%d,%.1f" % [h * 45, off] and t < 1.6:
						var dm: SphereMotor = lumi.sphere_motor
						var hs: PackedStringArray = []
						for c: KinematicCollision3D in dm.hits:
							hs.append("%s n%s at%s" % [_walk_name(c.get_collider()), str(_site_xz(lumi.global_position + c.get_normal()) - _site_xz(lumi.global_position)), str(_site_xz(c.get_position()))])
						print("[feel] dbg t%.2f pos%s hv %.2f climb %.2f alt %.2f g %s | %s" % [t, str(_site_xz(lumi.global_position)), dm.hv.length(), dm.get("_climb"), dm.altitude, str(dm.grounded), " ; ".join(hs)])
				inp.stick = Vector3.ZERO
				var gone: float = (lumi.global_position - p0).dot(w)
				total += 1
				# Free ground: about 11.4 m. A glancing hit should slide past the spot (5 m in).
				if still > 0.5 and gone < 7.0:
					stuck.append("h%d off%+.1f: %.1f m, stopped %.1f s" % [h * 45, off, gone, still])
				else:
					slid += 1
				worst = minf(worst, gone)
		print("[feel] snag (%.1f, %.1f): %d of %d glancing pushes got past%s" % [spot.x, spot.y, slid, total, "" if stuck.is_empty() else "; stopped: " + " | ".join(stuck)])
	print("[feel] snag: done, shortest push %.1f m" % worst)
	if DevHooks.has("feel-quit"):
		get_tree().quit(0)


# --- cam: the follow camera along a walk ---------------------------------------------------------

func _cam_walk() -> void:
	inp.world_space = true
	var pts: Array = []
	for part: String in DevHooks.get_s("feel-walk", "0,6;0,-30").split(";"):
		var c: PackedStringArray = part.split(",")
		pts.append(Vector2(float(c[0]), float(c[1])))
	var cam: SphereCam = so.cam
	_put(pts[0].x, pts[0].y, pts[1])
	await get_tree().physics_frame
	for k: int in range(1, pts.size()):
		var goal: Vector3 = _pos_at(pts[k].x, pts[k].y)
		var arm_min: float = 99.0
		var jumps: int = 0
		var big: float = 0.0
		var close_t: float = 0.0
		var t: float = 0.0
		var last_arm: float = float(cam.get("_arm"))
		var last_pos: Vector3 = cam.camera.global_position
		var cam_jump: float = 0.0
		while lumi.global_position.distance_to(goal) > 1.2 and t < 40.0:
			await get_tree().process_frame
			var dt: float = get_process_delta_time()
			t += dt
			var to: Vector3 = goal - lumi.global_position
			inp.stick = (to - lumi.up() * to.dot(lumi.up())).normalized()
			inp.boost = DevHooks.has("feel-boost")
			# A player keeps the camera roughly behind the walk.
			var head: Vector3 = SphereMath.tangent_dir(inp.stick, cam.frame.y, -cam.frame.z)
			cam.add_yaw(clampf((-cam.frame.z).signed_angle_to(head, cam.frame.y), -1.0, 1.0) * minf(1.0, 2.5 * dt))
			var arm: float = float(cam.get("_arm"))
			arm_min = minf(arm_min, arm)
			if absf(arm - last_arm) > 0.6:
				jumps += 1
				big = maxf(big, absf(arm - last_arm))
			# The camera's own move this frame, less what Lumi moved: a pop the player sees.
			var cm: float = cam.camera.global_position.distance_to(last_pos) - lumi.sphere_motor.hv.length() * dt
			cam_jump = maxf(cam_jump, cm)
			if arm < 1.6:
				close_t += dt
			last_arm = arm
			last_pos = cam.camera.global_position
		var at: Vector2 = _site_xz(lumi.global_position)
		print("[feel] cam leg %d to (%.0f, %.0f): %.1f s, reached (%.1f, %.1f), arm min %.1f m, %d jumps over 0.6 m (largest %.1f), camera pop %.2f m, closer than 1.6 m for %.1f s" % [k, pts[k].x, pts[k].y, t, at.x, at.y, arm_min, jumps, big, cam_jump, close_t])
	inp.stick = Vector3.ZERO
	print("[feel] cam: done")
	if DevHooks.has("feel-quit"):
		get_tree().quit(0)


## Lumi beside a wall with the camera on the wall's side: how far the arm pulls in. --feel-at=x,z;tx,tz
## (he stands at x,z facing tx,tz; the camera is behind him).
func _cam_wall() -> void:
	var c: PackedStringArray = DevHooks.get_s("feel-at", "59.5,5;40,5").split(";")
	var a: PackedStringArray = c[0].split(",")
	var b: PackedStringArray = c[1].split(",")
	_put(float(a[0]), float(a[1]), Vector2(float(b[0]), float(b[1])))
	for k: int in 30:
		await get_tree().process_frame
	var cam: SphereCam = so.cam
	var at: Vector2 = _site_xz(lumi.global_position)
	var cp: Vector2 = _site_xz(cam.camera.global_position)
	print("[feel] camwall: Lumi at (%.1f, %.1f), camera at (%.1f, %.1f), arm %.2f of %.2f, altitude %.2f" % [at.x, at.y, cp.x, cp.y, float(cam.get("_arm")), cam.distance, lumi.sphere.altitude(cam.camera.global_position)])
	inp.world_space = true
	inp.stick = -(_pos_at(float(b[0]), float(b[1])) - lumi.global_position).normalized()
	for k: int in 240:
		await get_tree().physics_frame
	at = _site_xz(lumi.global_position)
	print("[feel] camwall: pushed away from the look point for 2 s, now at (%.1f, %.1f)" % [at.x, at.y])
	if DevHooks.has("feel-quit"):
		get_tree().quit(0)


# --- walk: real walks through every hub town, catches and hops ---------------------------------

var _walk_q: PhysicsShapeQueryParameters3D
var _walk_cyl: CylinderShape3D


## Whether Lumi's body, widened by `pad` m, is clear of the town's solid things at site-local (x, z).
func _walk_free(root: Node3D, xf: Transform3D, x: float, z: float, pad: float, skip: Object = null, lift: float = 0.25) -> bool:
	var up: Vector3 = (xf * Vector3(x, 0, z)).normalized()
	var g: Vector3 = so.globe.terrain.ground(up)
	_walk_cyl.radius = Patch.BODY_R + pad
	_walk_q.transform = Transform3D(SphereGrid.frame(up), g + up * (lift + 0.475))
	for hit: Dictionary in lumi.get_world_3d().direct_space_state.intersect_shape(_walk_q, 8):
		var co: Object = hit.get("collider")
		if co == lumi or co is RigidBody3D:
			continue
		if skip != null and co is CollisionObject3D:  # skip one shape (a body holds a whole town's furniture)
			var cob := co as CollisionObject3D
			if cob.shape_owner_get_owner(cob.shape_find_owner(int(hit.get("shape", -1)))) == skip:
				continue
		if co is CollisionObject3D and (root.is_ancestor_of(co as Node) or ((co as CollisionObject3D).collision_layer & (PhysLayers.MOUND | PhysLayers.PROP)) != 0):
			return false
	return true


func _walk_line(root: Node3D, xf: Transform3D, a: Vector2, b: Vector2, pad: float, water: Callable, lift: float = 0.25) -> bool:
	var n: int = maxi(2, int(a.distance_to(b) / 0.4))
	for k: int in n + 1:
		var c: Vector2 = a.lerp(b, float(k) / n)
		if water.is_valid() and (water.call(c.x, c.y) or water.call(c.x + 1.5, c.y) or water.call(c.x - 1.5, c.y) or water.call(c.x, c.y + 1.5) or water.call(c.x, c.y - 1.5)):
			return false  # lakes stop him on purpose (no Hover Jets)
		if not _walk_free(root, xf, c.x, c.y, pad, null, lift):
			return false
	return true


func _walk_name(co: Object) -> String:
	if not co is Node:
		return "?"
	var nd: Node = co as Node
	var s: String = "%s/%s" % [nd.get_parent().name if nd.get_parent() else "", nd.name]
	if co is CollisionObject3D:
		s += " L%d" % (co as CollisionObject3D).collision_layer
	return s


## What else slows Lumi where he stands: water, the shore stop, a slope, a bale press.
func _walk_why() -> String:
	var out: PackedStringArray = []
	var f: Variant = so.w.get("field")
	if f:
		var hx: int = f.hex_at(lumi.global_position)
		if hx >= 0 and f.is_water(hx):
			out.append("in water")
	var m: SphereMotor = lumi.sphere_motor
	var slope: float = rad_to_deg(m.ground_normal.angle_to(lumi.up()))
	if slope > 8.0:
		out.append("slope %.0f deg" % slope)
	if float(lumi.get("_cubing")) > 0.0:
		out.append("pressing a bale")
	out.append("speed %.2f, alt %.2f, grounded %s" % [m.hv.length(), m.altitude, str(m.grounded)])
	return " [" + ", ".join(out) + "]"


func _snag_walk() -> void:
	inp.world_space = true
	_walk_cyl = CylinderShape3D.new()
	_walk_cyl.height = 0.95
	_walk_q = PhysicsShapeQueryParameters3D.new()
	_walk_q.shape = _walk_cyl
	_walk_q.collision_mask = PhysLayers.SOLID | PhysLayers.MOUND
	var sm: SiteManager = so.globe.site_manager
	var hubs: Array[int] = []
	if DevHooks.has("feel-hubs"):
		for h: String in DevHooks.get_s("feel-hubs", "0").split(","):
			hubs.append(int(h))
	else:
		for h: int in sm.sites.size():
			hubs.append(h)
	var legs: int = int(DevHooks.get_f("feel-legs", 40.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(DevHooks.get_f("feel-seed", 7.0))
	var walk: float = lumi.stat("move_speed")
	var catches: int = 0
	var hops: int = 0
	var swerves: int = 0
	var tree: SceneTree = get_tree()
	for hi: int in hubs:
		if hi < 0 or hi >= sm.sites.size():
			continue
		var xf: Transform3D = sm.sites[hi]["transform"]
		var r_town: float = (VerdanceSite.TOWN_R if hi == 0 else VerdanceSite.HUB_TOWN_R) - 6.0
		var pos0: Vector3 = so.globe.terrain.ground((xf * Vector3(0, 0, 6)).normalized())
		lumi.place_on_sphere(pos0, (so.globe.terrain.ground((xf * Vector3(0, 0, -6)).normalized()) - pos0))
		lumi.velocity = Vector3.ZERO
		var waited: float = 0.0
		while waited < 90.0 and (sm.prefab(hi) == null or not sm.prefab(hi).is_built):
			await tree.process_frame
			waited += get_process_delta_time()
		if sm.prefab(hi) == null or not sm.prefab(hi).is_built:
			print("[snag] hub %d: town never built" % hi)
			continue
		await tree.create_timer(2.0).timeout
		var root: Node3D = sm.roots[hi]
		var inv: Transform3D = xf.affine_inverse()
		var wet: Callable = sm.water_fn(hi)
		var n_leg: int = 0
		var n_try: int = 0
		var n_clear: int = 0
		var n_step: int = 0
		var hub_c: int = 0
		var hub_h: int = 0
		var hub_s: int = 0
		var lines: PackedStringArray = []
		while n_leg < legs and n_try < legs * 200:
			n_try += 1
			# Half the legs start in the town's core, where the street furniture is.
			var ra: float = r_town if n_try % 2 == 0 else minf(r_town, 55.0)
			var a := Vector2(rng.randf_range(-ra, ra), rng.randf_range(-ra, ra))
			var ang: float = rng.randf() * TAU
			var b: Vector2 = a + Vector2(cos(ang), sin(ang)) * rng.randf_range(10.0, 26.0)
			if a.length() > r_town or b.length() > r_town:
				continue
			var kind: String = ""
			if _walk_line(root, xf, a, b, 0.0, wet):
				kind = "clear" if _walk_line(root, xf, a, b, 0.15, Callable()) else "graze"
			elif n_step < legs / 3 and _walk_line(root, xf, a, b, 0.0, wet, Patch.BODY_R):
				# Only something lower than the hover-over height (0.45 m) is in the way: a kerb, a step.
				kind = "step"
			else:
				continue
			if kind == "clear" and n_clear >= (legs + 1) / 3:
				continue  # the rest of the legs brush something or step up
			n_step += 1 if kind == "step" else 0
			n_clear += 1 if kind == "clear" else 0
			n_leg += 1
			var pa: Vector3 = so.globe.terrain.ground((xf * Vector3(a.x, 0, a.y)).normalized())
			var pb: Vector3 = so.globe.terrain.ground((xf * Vector3(b.x, 0, b.y)).normalized())
			lumi.place_on_sphere(pa, pb - pa)
			lumi.velocity = Vector3.ZERO
			lumi.sphere_motor.hv = Vector3.ZERO
			if so.cam:
				so.cam.reset_frame(pb - pa)
			for k: int in 3:
				await tree.physics_frame
			var w: Vector3 = (pb - lumi.global_position)
			w = (w - lumi.up() * w.dot(lumi.up())).normalized()
			var t: float = 0.0
			var slow: float = 0.0
			var caught: bool = false
			var hopped: bool = false
			var swerved: bool = false
			var alts: Array[float] = []
			var last_dir := Vector3.ZERO
			var budget: float = a.distance_to(b) / walk * 2.0 + 1.0
			while t < budget:
				var to: Vector3 = pb - lumi.global_position
				to -= lumi.up() * to.dot(lumi.up())
				if to.length() < 0.8:
					break
				inp.stick = to.normalized()
				inp.boost = DevHooks.has("feel-boost")
				await tree.physics_frame
				var dt: float = get_physics_process_delta_time()
				t += dt
				var m: SphereMotor = lumi.sphere_motor
				var spd: float = m.hv.length()
				var lp: Vector3 = inv * lumi.global_position
				var here := "(%.1f, %.1f)" % [lp.x, lp.z]
				var what: PackedStringArray = []
				for c: KinematicCollision3D in m.hits:
					var nm: String = _walk_name(c.get_collider())
					if not what.has(nm):
						what.append(nm)
				if t > 0.4 and spd < walk * 0.5:
					slow += dt
					if slow >= 0.25 and not caught:
						caught = true
						lines.append("[snag] hub %d %s leg %d: CATCH at %s on %s%s" % [hi, kind, n_leg, here, ", ".join(what) if not what.is_empty() else "nothing touched", _walk_why()])
				else:
					slow = 0.0
				var alt: float = lumi.sphere.altitude(lumi.global_position)
				alts.append(alt)
				if alts.size() >= 3 and m.grounded and not hopped:
					var acc: float = alts[-1] - 2.0 * alts[-2] + alts[-3]
					if absf(acc) > 0.03:
						hopped = true
						lines.append("[snag] hub %d %s leg %d: HOP at %s (ride height kick %.3f m, alt %.2f)%s" % [hi, kind, n_leg, here, acc, alt, "" if what.is_empty() else " touching " + ", ".join(what)])
				if spd > 1.0:
					var d: Vector3 = m.hv / spd
					if last_dir != Vector3.ZERO and not swerved and rad_to_deg(last_dir.angle_to(d)) > 20.0:
						swerved = true
						lines.append("[snag] hub %d %s leg %d: SWERVE at %s (%.0f deg in a tick)%s" % [hi, kind, n_leg, here, rad_to_deg(last_dir.angle_to(d)), "" if what.is_empty() else " on " + ", ".join(what)])
					last_dir = d
			inp.stick = Vector3.ZERO
			var lp2: Vector3 = inv * lumi.global_position
			if not caught and Vector2(lp2.x, lp2.z).distance_to(b) > 1.5:
				caught = true
				lines.append("[snag] hub %d %s leg %d: SHORT, stopped at (%.1f, %.1f), %.1f m from the end" % [hi, kind, n_leg, lp2.x, lp2.z, Vector2(lp2.x, lp2.z).distance_to(b)])
			hub_c += 1 if caught else 0
			hub_h += 1 if hopped else 0
			hub_s += 1 if swerved else 0
		var gl: Array = await _walk_glance(hi, root, xf, wet, r_town, rng)
		lines.append_array(gl[0])
		for l: String in lines:
			print(l)
		print("[snag] hub %d: %d small things passed close by, %d of %d glancing pushes got past" % [hi, int(gl[1]), int(gl[2]), int(gl[3])])
		catches += int(gl[3]) - int(gl[2])
		print("[snag] hub %d: %d legs (%d clear, %d graze, %d step), %d catches, %d hops, %d swerves" % [hi, n_leg, n_clear, n_leg - n_clear - n_step, n_step, hub_c, hub_h, hub_s])
		catches += hub_c
		hops += hub_h
		swerves += hub_s
	inp.boost = false
	print("[snag] walk: %d catches, %d hops, %d swerves over %d hubs: %s" % [catches, hops, swerves, hubs.size(), "PASS" if catches == 0 else "FAIL"])
	if DevHooks.has("feel-quit"):
		get_tree().quit(1 if catches > 0 else 0)


## Small solid things in a town (posts, bins, benches, lamps, planters, hydrants): Lumi is pushed past
## each one on a fixed stick, his centre line just missing it on either side, so only his round body
## meets its edge. He should slide round and get on (as `--feel=snag`). Returns
## [lines, things, pushes that got past, pushes].
func _walk_glance(hi: int, root: Node3D, xf: Transform3D, wet: Callable, r_town: float, rng: RandomNumberGenerator) -> Array:
	var tree: SceneTree = get_tree()
	var inv: Transform3D = xf.affine_inverse()
	var want: int = int(DevHooks.get_f("feel-props", 16.0))
	var cands: Array = []  # [shape node, body, half extents (x, z) local, local centre]
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var cs := node as CollisionShape3D
		var body := cs.get_parent() as CollisionObject3D
		if body == null or cs.disabled or cs.shape == null or body is RigidBody3D:
			continue
		if (body.collision_layer & (PhysLayers.PROP | PhysLayers.WORLD)) == 0 or (body.collision_layer & PhysLayers.MOUND) != 0:
			continue
		var he := Vector2.ZERO
		var sc: Vector3 = cs.global_basis.get_scale()
		if cs.shape is BoxShape3D:
			var bs: Vector3 = (cs.shape as BoxShape3D).size * sc * 0.5
			if bs.y < 0.5:
				continue  # a kerb or a slab: the walk legs cover those
			he = Vector2(bs.x, bs.z)
		elif cs.shape is CylinderShape3D:
			var rr: float = (cs.shape as CylinderShape3D).radius * sc.x
			he = Vector2(rr, rr)
		elif cs.shape is CapsuleShape3D:
			var rc: float = (cs.shape as CapsuleShape3D).radius * sc.x
			he = Vector2(rc, rc)
		elif cs.shape is SphereShape3D:
			var rs: float = (cs.shape as SphereShape3D).radius * sc.x
			he = Vector2(rs, rs)
		else:
			continue
		if he.x > 1.4 or he.y > 1.4 or he.x < 0.03:
			continue
		var lc: Vector3 = inv * cs.global_position
		if Vector2(lc.x, lc.z).length() > r_town - 8.0:
			continue
		cands.append([cs, body, he, Vector2(lc.x, lc.z)])
	var lines: PackedStringArray = []
	var things: int = 0
	var ok: int = 0
	var total: int = 0
	var tries: int = 0
	while things < want and not cands.is_empty() and tries < want * 10:
		tries += 1
		var c: Array = cands.pop_at(rng.randi() % cands.size())
		var cs: CollisionShape3D = c[0]
		if not is_instance_valid(cs):
			continue
		var at: Vector2 = c[3]
		var he: Vector2 = c[2]
		# Its own axes in site space, to know how wide it is across each push.
		var ax3: Vector3 = inv.basis * cs.global_basis.x.normalized()
		var ax := Vector2(ax3.x, ax3.z).normalized()
		var az := Vector2(-ax.y, ax.x)
		var did: bool = false
		for h: int in 2:
			var ang: float = rng.randf() * TAU
			var d := Vector2(cos(ang), sin(ang))
			var side := Vector2(-d.y, d.x)
			var ext: float = absf(side.dot(ax)) * he.x + absf(side.dot(az)) * he.y
			for sgn: float in [-1.0, 1.0]:
				var off: float = sgn * (ext + 0.15)
				var a: Vector2 = at - d * 5.0 + side * off
				var e: Vector2 = at + d * 6.0 + side * off
				# Only where nothing else is in the way: the start, the end and the line past it.
				if not _walk_line(root, xf, a, a + d * 2.5, 0.05, wet) or not _walk_line(root, xf, e - d * 3.0, e, 0.05, wet):
					continue
				var mid_ok: bool = true
				for k: int in 9:
					var m: Vector2 = a.lerp(e, float(k) / 8.0)
					if not _walk_free(root, xf, m.x, m.y, 0.0, cs):
						mid_ok = false
						break
				if not mid_ok:
					continue
				did = true
				var pa: Vector3 = so.globe.terrain.ground((xf * Vector3(a.x, 0, a.y)).normalized())
				var pe: Vector3 = so.globe.terrain.ground((xf * Vector3(e.x, 0, e.y)).normalized())
				lumi.place_on_sphere(pa, pe - pa)
				lumi.velocity = Vector3.ZERO
				lumi.sphere_motor.hv = Vector3.ZERO
				for k: int in 3:
					await tree.physics_frame
				var p0: Vector3 = lumi.global_position
				var w: Vector3 = pe - p0
				w = (w - lumi.up() * w.dot(lumi.up())).normalized()
				inp.stick = w
				var t: float = 0.0
				var touched: bool = false
				var last_hit: String = ""
				var still: float = 0.0
				while t < 2.6:
					await tree.physics_frame
					t += get_physics_process_delta_time()
					if t > 0.4 and lumi.sphere_motor.hv.length() < 0.4:
						still += get_physics_process_delta_time()
					for col: KinematicCollision3D in lumi.sphere_motor.hits:
						if col.get_collider() == c[1]:
							touched = true
						last_hit = _walk_name(col.get_collider())
				inp.stick = Vector3.ZERO
				var gone: float = (lumi.global_position - p0).dot(w)
				total += 1
				# Free ground is about 11 m; rounding the thing costs a little. Stopped = held up 0.4 s.
				if gone >= 6.5 and still < 0.4:
					ok += 1
				else:
					var lp: Vector3 = inv * lumi.global_position
					lines.append("[snag] hub %d glance: STUCK by %s (%s %.2fx%.2f m at (%.1f, %.1f)), pushed %+.2f m off its middle, got %.1f m (held up %.1f s), at (%.1f, %.1f)%s%s%s" % [
						hi, _walk_name(c[1]), cs.shape.get_class().replace("Shape3D", ""), he.x * 2.0, he.y * 2.0, at.x, at.y, off, gone, still, lp.x, lp.z,
						"" if touched else " (never touched it)", "" if last_hit == "" else ", last hit " + last_hit, _walk_why()])
		if did:
			things += 1
	return [lines, things, ok, total]


## Every prop collider body (group prop_body): where its shapes are against the planet's surface.
## A body whose shapes sit far under the ground is a ghost: Lumi walks through those props.
func _props_audit() -> void:
	var bad: int = 0
	var n: int = 0
	for b: Node in get_tree().get_nodes_in_group("prop_body"):
		var sb := b as StaticBody3D
		if sb == null or not sb.is_inside_tree():
			continue
		var cnt: int = 0
		var worst: float = 0.0
		for cs: Node in sb.get_children():
			if cs is CollisionShape3D:
				cnt += 1
				var a: float = so.globe.surface.altitude((cs as Node3D).global_position)
				if absf(a) > absf(worst):
					worst = a
		if cnt == 0:
			continue
		n += 1
		var ghost: bool = absf(worst) > 30.0
		bad += 1 if ghost else 0
		if ghost or DevHooks.has("feel-all"):
			print("[feel] props %s: %d shapes, worst altitude %.1f m, top_level %s, parent alt %.1f%s" % [str(sb.get_path()).right(90), cnt, worst, str(sb.top_level),
				so.globe.surface.altitude((sb.get_parent() as Node3D).global_position) if sb.get_parent() is Node3D else 0.0, "  GHOST" if ghost else ""])
	print("[feel] props: %d bodies, %d ghosts" % [n, bad])
	if DevHooks.has("feel-quit"):
		get_tree().quit(1 if bad > 0 else 0)
