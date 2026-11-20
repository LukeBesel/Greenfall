class_name WalkJump
extends RefCounted
## [v11jump] Owner, 20 Nov: "Also build in jump mechanic". Lumi's hop played with real key events
## (and a controller's A), as a player presses them:
##   - in the start yard while the restart checklist runs: Space held = the full hop (height and
##     time as data/patch.json "jump"), straight up along his own up, one landing, the camera
##     barely moves; a tap = a small hop; a press just before landing hops again on landing;
##   - while the scoop is held; with the map open (no hop, and no hop when it closes);
##   - a bale: E picks it up, he hops with it and still has it; put down, he hops onto it, hops
##     from it, and walks off it;
##   - a controller: A hops where there is nothing to use, and uses (picks the bale up) where there is;
##   - shut in a pen with no way out, he is lifted to open ground after a few seconds of trying
##     (the safety net under the hop, Patch._pocket_watch); a pen with an open side: no lift;
##   - on the far side of the globe (the antipode's nearest dry ground): the same hop, along the
##     up there, and back home.
## --walk-jump[=S] (after S s, default 8): prints [walk-jump] lines, exit 1 on a failure.
## --walk-jump-shots=/abs/dir (a rendered run with --fixed-fps 30): saves every frame of a standing
## hop, a tapped hop and a running hop from the play camera (a_NN, b_NN, c_NN.png), to look at.
## tools/check_exit.sh runs it with the tests.

const TAG: String = "[walk-jump]"

static var _fails: Array[String] = []
static var _tree: SceneTree
static var _so: SliceOrbit
static var _p: Patch
static var _hops: int = 0
static var _lands: int = 0


static func run_dev(so: SliceOrbit) -> void:
	_so = so
	_tree = so.w.get_tree()
	await _tree.create_timer(DevHooks.get_f("walk-jump", 8.0)).timeout
	var w: Node = so.w
	for k: int in 240:
		if not bool(w.get("building")) and w.get("patch") != null and so.hub_frame != null:
			break
		await _tree.create_timer(0.5).timeout
	_p = w.get("patch") as Patch
	if _p == null or _p.sphere_motor == null:
		print("%s FAIL: no Lumi on the globe" % TAG)
		_tree.quit(1)
		return
	for k: int in 240:  # the landing brief (or a film) hands the keys over
		if _input_on():
			break
		await _tree.create_timer(0.5).timeout
	_check(_input_on(), "Lumi takes input")
	_p.sphere_motor.jumped.connect(func() -> void: _hops += 1)
	_p.sphere_motor.landed.connect(func(_i: float) -> void: _lands += 1)
	if DevHooks.has("walk-jump-shots"):
		await _shots()
		_tree.quit(0)
		return
	var j: Dictionary = Economy.read_json("res://data/patch.json").get("jump", {})
	var want_h: float = float(j.get("height_m", 0.7))
	var want_t: float = float(j.get("rise_s", 0.25)) + float(j.get("fall_s", 0.21))
	var key: InputEventKey = WalkGoals._event("jump") as InputEventKey
	_check(key != null and key.physical_keycode == KEY_SPACE, "the hop is on Space (%s in Controls)" % Settings.glyph("jump"))
	var names: Array = Settings.REBINDABLE.map(func(e: Array) -> String: return e[0])
	_check(names.has("jump") and Settings.conflicts().is_empty(), "it is in the Controls list, with no conflict shown")
	# An open spot near the start: sky overhead, clear ground ahead, nothing to "use" in reach.
	var home: Vector3 = await _open_spot(_p.global_position)
	var tut: Tutorial = w.get("tutorial") as Tutorial
	print("%s start: checklist %s" % [TAG, "running (step %s)" % tut.step_id() if tut and not tut.done() else "done"])

	# 1. Held, at home.
	var r: Dictionary = await _hop(0.7)
	_check(absf(float(r["peak"]) - want_h) < 0.1, "home, Space held: rises %.2f m (set %.2f)" % [float(r["peak"]), want_h])
	_check(absf(float(r["air"]) - want_t) < 0.12, "home, Space held: %.2f s in the air (set %.2f)" % [float(r["air"]), want_t])
	_check(float(r["start"]) < 0.08, "home: he leaves the ground at once (%.3f s after the key)" % float(r["start"]))
	_check(int(r["hops"]) == 1 and int(r["lands"]) == 1 and bool(r["down"]), "home: one hop, one landing, back at hover height")
	_check(float(r["drift"]) < 0.05, "home: straight up and down (drift %.3f m)" % float(r["drift"]))
	_check(float(r["cam"]) < float(r["peak"]) * 0.4, "home: the camera stays calm (it moved %.2f m for a %.2f m hop)" % [float(r["cam"]), float(r["peak"])])
	# 2. A tap.
	var t: Dictionary = await _hop(0.0)
	_check(float(t["peak"]) > 0.08 and float(t["peak"]) < float(r["peak"]) * 0.65, "home, Space tapped: a small hop (%.2f m, held %.2f m)" % [float(t["peak"]), float(r["peak"])])
	_check(float(t["air"]) < float(r["air"]) - 0.08, "home, tapped: shorter in the air (%.2f s)" % float(t["air"]))
	# 3. A press just before landing.
	await _buffered()
	# 4. Scooping.
	WalkGoals._send("scoop", true)
	await _secs(0.3)
	var s: Dictionary = await _hop(0.7)
	WalkGoals._send("scoop", false)
	_check(int(s["hops"]) == 1 and float(s["peak"]) > want_h - 0.12, "with the scoop held he hops as well (%.2f m)" % float(s["peak"]))
	# 5. A screen open: no hop, and none when it closes.
	await _menu()
	# 6. A bale: carried, then hopped onto.
	await _bale()
	# 7. A controller's A.
	await _pad()
	_check(_p.rescues == 0, "all that hopping on open ground: no rescue lift (%d)" % _p.rescues)
	# 8. Shut in with no way out: the thrusters lift him to open ground.
	await _pen()
	# 9. The far side of the globe.
	await _far_side(want_h, want_t)
	# Home again, and still fine.
	WalkGoals._stand(so, _p, home, home + SphereGrid.frame(home.normalized()).z * -4.0)
	await _secs(3.0)
	await _open_spot(home)
	var back: Dictionary = await _hop(0.7)
	_check(absf(float(back["peak"]) - want_h) < 0.1 and bool(back["down"]), "home again: the same hop (%.2f m)" % float(back["peak"]))
	_check(int(GameState.stats.get("fell_through", 0)) == 0, "Lumi never fell through the ground")
	print("%s %s" % [TAG, "PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)])
	_tree.quit(0 if _fails.is_empty() else 1)


static func _check(ok: bool, what: String) -> void:
	print("%s %s %s" % [TAG, "PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


static func _input_on() -> bool:
	return _p.input is PlayerInput and (_p.input as PlayerInput).enabled


static func _secs(s: float) -> void:
	await _tree.create_timer(s).timeout


static func _alt() -> float:
	return _p.sphere.altitude(_p.global_position)


## Presses Space for `hold_s` (0 = one physics tick) and follows the hop to its landing.
## peak (m above the start), air (s), start (s from the key to leaving the ground), hops, lands,
## drift (m along the ground), cam (how far the camera moved up or down), down (ended at rest).
static func _hop(hold_s: float, action: String = "jump") -> Dictionary:
	await _settle()
	var m: SphereMotor = _p.sphere_motor
	var a0: float = _alt()
	var p0: Vector3 = _p.global_position
	var u: Vector3 = _p.up()
	var cam: Camera3D = _so.cam.camera if _so.cam else null
	var c0: float = cam.global_position.dot(u) if cam else 0.0
	var h0: int = _hops
	var l0: int = _lands
	var dt: float = 1.0 / Engine.physics_ticks_per_second
	var peak: float = 0.0
	var drift: float = 0.0
	var cam_d: float = 0.0
	var air: float = 0.0
	var start: float = -1.0
	var t: float = 0.0
	await _tree.physics_frame
	WalkGoals._send(action, true)
	var held: bool = true
	while t < 3.0:
		await _tree.physics_frame
		t += dt
		if held and t >= hold_s:
			WalkGoals._send(action, false)
			held = false
		if not m.grounded:
			if start < 0.0:
				start = t - dt
			air += dt
		elif start >= 0.0 and not held:
			break
		peak = maxf(peak, _alt() - a0)
		var d: Vector3 = _p.global_position - p0
		drift = maxf(drift, (d - u * d.dot(u)).length())
		if cam:
			cam_d = maxf(cam_d, absf(cam.global_position.dot(u) - c0))
	if held:
		WalkGoals._send(action, false)
	await _secs(0.5)
	return {"peak": peak, "air": air, "start": maxf(start, 0.0) if start >= 0.0 else 9.0, "hops": _hops - h0, "lands": _lands - l0, "drift": drift, "cam": cam_d,
		"down": m.grounded and absf(_alt() - a0) < 0.06}


## Waits until he stands at rest.
static func _settle() -> void:
	for k: int in 400:
		await _tree.physics_frame
		if _p.sphere_motor.grounded and absf(_p.sphere_motor.vv) < 0.05 and _p.sphere_motor.hv.length() < 0.05:
			return


static func _buffered() -> void:
	await _settle()
	var m: SphereMotor = _p.sphere_motor
	var h0: int = _hops
	WalkGoals._send("jump", true)
	for k: int in 8:
		await _tree.physics_frame
	WalkGoals._send("jump", false)
	var pressed: bool = false
	for k: int in 400:
		await _tree.physics_frame
		if not pressed and not m.grounded and m.vv < 0.0 and m.altitude < 0.2:
			WalkGoals._send("jump", true)  # still in the air: too early for a plain press
			pressed = true
			for q: int in 3:
				await _tree.physics_frame
			WalkGoals._send("jump", false)
		if pressed and m.grounded and absf(m.vv) < 0.05:
			break
	await _secs(0.8)
	_check(pressed and _hops - h0 == 2, "a press just before landing hops again on landing (%d hops)" % (_hops - h0))
	# At the top of a hop a press is too early: it is forgotten (no hop a moment after landing).
	await _settle()
	h0 = _hops
	WalkGoals._send("jump", true)
	for k: int in 400:
		await _tree.physics_frame
		if not m.grounded and m.vv < 0.5:
			break
	WalkGoals._send("jump", false)
	await _tree.physics_frame
	WalkGoals._send("jump", true)
	await _tree.physics_frame
	WalkGoals._send("jump", false)
	await _secs(1.2)
	_check(_hops - h0 == 1 and m.grounded, "a press at the top of a hop is forgotten (no double hop)")


static func _menu() -> void:
	await _settle()
	var sv: Variant = _so.layers.get("survey") if _so.layers else null
	if not (sv is Object):
		print("%s note: no map screen here" % TAG)
		return
	var h0: int = _hops
	await WalkGoals._tap(_tree, "open_globe")
	await _secs(0.6)
	var open: bool = bool((sv as Object).get("is_open"))
	_check(open and not _input_on(), "M opens the map and takes the keys")
	WalkGoals._send("jump", true)
	await _secs(0.4)
	WalkGoals._send("jump", false)
	await _secs(0.3)
	_check(_hops == h0 and _p.sphere_motor.grounded, "with the map open Space does not hop")
	WalkGoals._send("jump", true)  # pressed while it closes
	await _tree.physics_frame
	await WalkGoals._tap(_tree, "open_globe")
	WalkGoals._send("jump", false)
	await _secs(1.0)
	if bool((sv as Object).get("is_open")):
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		Input.parse_input_event(esc)
		await _secs(0.2)
		esc = esc.duplicate()
		esc.pressed = false
		Input.parse_input_event(esc)
		await _secs(1.0)
	_check(not bool((sv as Object).get("is_open")) and _input_on(), "the map closes and Lumi takes input again")
	_check(_hops == h0, "the press made while the map was open does not hop afterwards")
	var r: Dictionary = await _hop(0.7)
	_check(int(r["hops"]) == 1, "and Space hops again")


static func _bale() -> void:
	await _settle()
	await _open_spot(_p.global_position)
	var w: Node = _so.w
	var u: Vector3 = _p.up()
	var fwd: Vector3 = -_p.global_basis.z
	# An open stretch ahead of him for the bale (2.2 m on).
	var at: Vector3 = _so.globe.terrain.ground((_p.global_position + fwd * 2.2).normalized())
	var c: JunkCube = JunkCube.create(BigNum.new(5.0), {"fill": 1.0, "colors": [Color(0.6, 0.5, 0.4)]})
	w.add_child(c)
	c.global_transform = Transform3D(_p.global_basis, at + u * 0.5)
	await _secs(1.5)
	var cap: int = _p.carry_cap()
	# Walk up to it and pick it up with E.
	WalkGoals._send("move_forward", true)
	for k: int in 240:
		await _tree.physics_frame
		if _p.prompt == "pick_up":
			break
	WalkGoals._send("move_forward", false)
	await _settle()
	if _p.prompt != "pick_up" or cap < 1:
		_check(false, "bale: Lumi reaches the bale (prompt '%s', carry %d)" % [_p.prompt, cap])
		c.queue_free()
		return
	var h0: int = _hops
	await WalkGoals._tap(_tree, "interact")
	await _secs(0.8)
	_check(_p.carried.size() == 1 and _hops == h0, "bale: E picks it up (and E does not hop)")
	var r: Dictionary = await _hop(0.7)
	_check(int(r["hops"]) == 1 and float(r["peak"]) > 0.5 and bool(r["down"]), "carrying a bale he hops (%.2f m)" % float(r["peak"]))
	_check(_p.carried.size() == 1 and is_instance_valid(c) and c.carried, "and the bale is still in his arms after landing")
	# Put it down (Q) and hop onto it.
	await WalkGoals._tap(_tree, "drop")
	await _secs(1.5)
	_check(_p.carried.is_empty() and not c.carried, "bale: Q puts it down")
	var top: float = (c.global_position - _so.globe.terrain.ground(c.global_position.normalized())).dot(u) + c.size * 0.5
	var to: Vector3 = c.global_position - _p.global_position
	to = (to - u * to.dot(u))
	var dist: float = to.length()
	WalkGoals._stand(_so, _p, _p.global_position, _p.global_position + to)
	await _settle()
	var m: SphereMotor = _p.sphere_motor
	var on_it: bool = false
	for attempt: int in 3:
		WalkGoals._send("move_forward", true)
		await _secs(0.05)
		WalkGoals._send("jump", true)
		for k: int in 200:
			await _tree.physics_frame
			var d: Vector3 = c.global_position - _p.global_position
			if (d - u * d.dot(u)).length() < 0.25 or (m.grounded and k > 30):
				break
		WalkGoals._send("move_forward", false)
		WalkGoals._send("jump", false)
		await _secs(0.8)
		if m.grounded and m.altitude > 0.08 and m._perch > 0.0:
			on_it = true
			break
		# Missed (it rolled, he overshot): back off and try again.
		WalkGoals._send("move_back", true)
		await _secs(0.9)
		WalkGoals._send("move_back", false)
		await _settle()
		to = c.global_position - _p.global_position
		WalkGoals._stand(_so, _p, _p.global_position, _p.global_position + (to - u * to.dot(u)))
		await _settle()
	_check(on_it, "he hops onto the bale and stands on it (bale top %.2f m, he is %.2f m up, from %.1f m off)" % [top, _surface_alt(), dist])
	if on_it:
		var a: float = _alt()
		var l0: int = _lands
		await _secs(1.0)
		_check(absf(_alt() - a) < 0.02 and _lands == l0, "on the bale he stands still (no bobbing, no landing after landing)")
		h0 = _hops
		var b0: float = _alt()
		var btop: float = 0.0
		WalkGoals._send("jump", true)
		for k: int in 100:
			await _tree.physics_frame
			btop = maxf(btop, _alt() - b0)
		WalkGoals._send("jump", false)
		await _secs(0.6)
		_check(_hops == h0 + 1 and absf(btop - float(Economy.read_json("res://data/patch.json")["jump"]["height_m"])) < 0.12, "from the bale he hops as from the ground (%.2f m above it)" % btop)
		_check(m.grounded, "and lands again (%.2f m up)" % _surface_alt())
		WalkGoals._send("move_forward", true)
		await _secs(1.0)
		WalkGoals._send("move_forward", false)
		await _settle()
		_check(m.grounded and absf(_surface_alt()) < 0.08 and m._perch <= 0.0, "he walks off the bale onto the ground (%.2f m up)" % _surface_alt())
		var r2: Dictionary = await _hop(0.7)
		_check(int(r2["hops"]) == 1, "and hops again on the ground")
	c.queue_free()
	await _secs(0.3)


## Stands Lumi on open ground at or near `near`: nothing solid within reach or for 5 m ahead, open
## sky, dry, and no "use" prompt. Returns where he stands (facing the clear way).
static func _open_spot(near: Vector3) -> Vector3:
	var t: TargetReach = TargetReach.for_world(_so.w, true, _p)
	var R: float = _so.globe.terrain.R
	var d0: Vector3 = near.normalized()
	var f: Basis = SphereGrid.frame(d0)
	var space: PhysicsDirectSpaceState3D = _p.get_world_3d().direct_space_state
	for ring: int in 14:
		for k: int in (1 if ring == 0 else 12):
			var a: float = TAU * k / 12.0 + ring * 0.37
			var d: Vector3 = (d0 * R + (f.x * cos(a) + f.z * sin(a)) * ring * 3.0).normalized()
			var fwd: Vector3 = SphereGrid.frame(d).z * -1.0
			var ok: bool = true
			for step: int in 11:  # 1 m behind to 5 m ahead, and half a metre to each side
				for side: float in [-0.6, 0.0, 0.6]:
					var q: Vector3 = (d * R + fwd * (step * 0.6 - 1.0) + SphereGrid.frame(d).x * side).normalized()
					if t.why(q) != "":
						ok = false
			if not ok:
				continue
			var g: Vector3 = _so.globe.terrain.ground(d)
			var rq := PhysicsRayQueryParameters3D.create(g + d * 1.3, g + d * 5.0, PhysLayers.SOLID, [_p.get_rid()])
			if not space.intersect_ray(rq).is_empty():
				continue  # a roof or an awning over it
			WalkGoals._stand(_so, _p, g, g + fwd * 4.0)
			await _secs(0.6)
			if _p.prompt == "" and _p.sphere_motor.grounded and _p.sphere_motor.hits.is_empty():
				return g
	_check(false, "an open spot near %s" % str(near.snapped(Vector3.ONE)))
	return near


## Height above the ground under him (props counted).
static func _surface_alt() -> float:
	return _p.sphere_motor.altitude


static func _pad_btn(b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = down
	e.device = 0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


static func _pad() -> void:
	await _settle()
	await _open_spot(_p.global_position)
	var w: Node = _so.w
	var u: Vector3 = _p.up()
	_check(_p.prompt == "" and _p.carried.is_empty(), "controller: nothing to use here (prompt '%s')" % _p.prompt)
	var h0: int = _hops
	_pad_btn(JOY_BUTTON_A, true)
	await _secs(0.5)
	_pad_btn(JOY_BUTTON_A, false)
	await _secs(0.8)
	_check(_hops == h0 + 1, "controller: A hops where there is nothing to use (%s in Controls)" % PadGlyphs.event_name(Settings.binding("jump", true)))
	# A bale at his feet: A is "use" (pick up), not a hop.
	var c: JunkCube = JunkCube.create(BigNum.new(5.0), {"fill": 1.0, "colors": [Color(0.6, 0.5, 0.4)]})
	w.add_child(c)
	c.global_transform = Transform3D(_p.global_basis, _so.globe.terrain.ground((_p.global_position - _p.global_basis.z * 1.3).normalized()) + u * 0.5)
	await _secs(1.5)
	if _p.prompt != "pick_up":
		_check(false, "controller: the bale at his feet shows the pick-up prompt (prompt '%s')" % _p.prompt)
	else:
		h0 = _hops
		_pad_btn(JOY_BUTTON_A, true)
		await _secs(0.3)
		_pad_btn(JOY_BUTTON_A, false)
		await _secs(0.8)
		_check(_p.carried.size() == 1 and _hops == h0, "controller: by a bale A picks it up and does not hop")
		_pad_btn(JOY_BUTTON_B, true)
		await _secs(0.2)
		_pad_btn(JOY_BUTTON_B, false)
		await _secs(1.0)
	if is_instance_valid(c):
		if c.carried:
			_p.pop_carried_cube()
		c.queue_free()
	# Back to the keyboard for the rest.
	WalkGoals._send("move_back", true)
	await _secs(0.3)
	WalkGoals._send("move_back", false)
	await _settle()


## A pen of four 1.3 m walls round him (too high to hop): he hops, keeps trying to move, and after a
## few seconds is lifted out to open ground. With a gap in the pen nothing lifts him.
static func _pen() -> void:
	await _settle()
	var c: Vector3 = await _open_spot(_p.global_position)
	var u: Vector3 = c.normalized()
	var fr: Basis = _p.global_basis
	var pen := StaticBody3D.new()
	pen.collision_layer = PhysLayers.PROP
	pen.collision_mask = 0
	_so.w.add_child(pen)
	pen.global_transform = Transform3D(fr, c)
	var gate: CollisionShape3D = null
	for k: int in 4:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.4, 1.3, 0.3)
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, k * PI * 0.5), Basis(Vector3.UP, k * PI * 0.5) * Vector3(0, 0.65, -1.55))
		pen.add_child(cs)
		if k == 0:
			gate = cs
	# First with one side open: hopping about inside is not being stuck.
	gate.disabled = true
	await _secs(0.5)
	var r0: int = _p.rescues
	await _hop(0.3)
	WalkGoals._send("move_right", true)
	await _secs(4.0)
	WalkGoals._send("move_right", false)
	await _hop(0.3)
	WalkGoals._send("move_left", true)
	await _secs(4.0)
	WalkGoals._send("move_left", false)
	_check(_p.rescues == r0, "in a pen with an open side: no lift, he can walk out")
	WalkGoals._stand(_so, _p, c, c - fr.z * 4.0)
	gate.disabled = false
	await _secs(0.6)
	# Shut: he hops and pushes at the walls.
	var h0: int = _hops
	await _hop(0.7)
	_check(_hops == h0 + 1 and (_p.global_position - c).length() < 1.6, "shut in a pen of 1.3 m walls: a hop does not get him out")
	WalkGoals._send("move_forward", true)
	var t: float = 0.0
	while t < 14.0 and _p.rescues == r0:
		await _secs(0.25)
		t += 0.25
		if int(t * 4.0) % 8 == 0:
			WalkGoals._send("jump", true)
			await _secs(0.1)
			WalkGoals._send("jump", false)
	WalkGoals._send("move_forward", false)
	await _settle()
	var out: Vector3 = _p.global_position - c
	out -= u * out.dot(u)
	_check(_p.rescues == r0 + 1, "after %.1f s of trying he is lifted out (once)" % t)
	_check(out.length() > 2.2 and _p.sphere_motor.grounded and absf(_surface_alt()) < 0.08, "he stands on open ground %.1f m from the pen's middle" % out.length())
	var tr2: TargetReach = TargetReach.for_world(_so.w, true, _p)
	_check(not tr2.shut_in(_p.global_position), "and can walk away from there")
	pen.queue_free()
	await _secs(0.3)


static func _far_side(want_h: float, want_t: float) -> void:
	var f: SphereField = _so.globe.field
	var anti: Vector3 = -_p.global_position.normalized()
	# Dry open ground at or near the antipode.
	var spot := Vector3.ZERO
	var fr: Basis = SphereGrid.frame(anti)
	var R: float = _so.globe.terrain.R
	var treach: TargetReach = TargetReach.for_world(_so.w)
	for ring: int in 60:
		for k: int in (1 if ring == 0 else 10):
			var d: Vector3 = (anti * R + (fr.x * cos(TAU * k / 10.0) + fr.z * sin(TAU * k / 10.0)) * ring * 12.0).normalized()
			if treach.why_ground(d) == "" and treach.escapes(d):
				spot = _so.globe.terrain.ground(d)
				break
		if spot != Vector3.ZERO:
			break
	if spot == Vector3.ZERO:
		_check(false, "far side: dry open ground near the antipode")
		return
	WalkGoals._stand(_so, _p, spot, spot + SphereGrid.frame(spot.normalized()).z * -4.0)
	# The ground and what stands on it load round him.
	await _secs(6.0)
	spot = await _open_spot(spot)
	var u: Vector3 = spot.normalized()
	print("%s far side: up there is %s (home was %s), %.0f m from the antipode" % [TAG, str(u.snapped(Vector3.ONE * 0.01)), str((-anti).snapped(Vector3.ONE * 0.01)), anti.angle_to(u) * R])
	_check(f.grid.cell_at(_p.global_position.normalized()) >= 0 and _p.up().dot(u) > 0.999 and _p.global_basis.y.dot(u) > 0.999, "far side: Lumi stands upright there (his up . the ground's up = %.4f)" % _p.global_basis.y.dot(u))
	var r: Dictionary = await _hop(0.7)
	_check(absf(float(r["peak"]) - want_h) < 0.1, "far side, Space held: rises %.2f m along the up there" % float(r["peak"]))
	_check(absf(float(r["air"]) - want_t) < 0.12 and int(r["lands"]) == 1 and bool(r["down"]), "far side: %.2f s in the air, one landing, back at hover height" % float(r["air"]))
	_check(float(r["drift"]) < 0.05, "far side: straight up and down (drift %.3f m)" % float(r["drift"]))
	_check(float(r["cam"]) < float(r["peak"]) * 0.4, "far side: the camera stays calm (%.2f m)" % float(r["cam"]))
	var t: Dictionary = await _hop(0.0)
	_check(float(t["peak"]) > 0.08 and float(t["peak"]) < float(r["peak"]) * 0.65, "far side, tapped: a small hop (%.2f m)" % float(t["peak"]))
	# A running hop: forward speed is kept, he lands on the ground ahead.
	var p0: Vector3 = _p.global_position
	WalkGoals._send("move_forward", true)
	await _secs(0.5)
	var h0: int = _hops
	WalkGoals._send("jump", true)
	await _secs(0.6)
	WalkGoals._send("jump", false)
	WalkGoals._send("move_forward", false)
	await _settle()
	_check(_hops == h0 + 1 and _p.sphere_motor.grounded and _p.global_position.distance_to(p0) > 2.0 and _p.global_basis.y.dot(_p.up()) > 0.999,
		"far side: a running hop carries him forward and he lands upright (%.1f m on)" % _p.global_position.distance_to(p0))


## (rendered, --fixed-fps 30) every frame of three hops, as the player sees them.
static func _shots() -> void:
	var dir: String = DevHooks.get_s("walk-jump-shots", "")
	if dir == "" or DisplayServer.get_name() == "headless":
		print("%s shots need a rendered run and a folder" % TAG)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await _secs(2.0)
	for seq: Array in [["a", 16, false], ["b", 1, false], ["c", 16, true]]:
		await _settle()
		if bool(seq[2]):
			WalkGoals._send("move_forward", true)
			await _secs(0.5)
		WalkGoals._send("jump", true)
		for i: int in 24:
			if i == int(seq[1]):
				WalkGoals._send("jump", false)
			await RenderingServer.frame_post_draw
			var img: Image = _tree.root.get_texture().get_image()
			img.save_png("%s/%s_%02d.png" % [dir, str(seq[0]), i])
			print("%s shot %s_%02d: %.2f m up, vv %.1f, grounded %s" % [TAG, str(seq[0]), i, _alt(), _p.sphere_motor.vv, str(_p.sphere_motor.grounded)])
		WalkGoals._send("jump", false)
		WalkGoals._send("move_forward", false)
		await _secs(1.0)
