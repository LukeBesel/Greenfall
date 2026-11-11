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
		"map":
			_map()
			return
		"snag":
			_snag()
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
		"carry":
			_carry_sample()
		"move":
			_move_sample(delta, _t - start)


func _flush() -> void:
	if _phase == "" or _acc.is_empty():
		return
	match mode:
		"carry":
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
