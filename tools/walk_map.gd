class_name WalkMap
extends RefCounted
## [v10ui] Owner, 2026-11-20: "on map view it looks great but I should be able to manipulate globe
## with mouse". The map (ui/globe_view.gd) played with real input events, as a player's mouse,
## trackpad and keys send them through the window:
##   0. (critic 7) on the start pad the HUD's ground line names the base Lumi stands at;
##   1. the map key opens it looking at Lumi, with the one-line "drag to turn" hint;
##   2. a left-button drag turns the globe so the ground under the cursor follows it; let go while
##      moving, it coasts a little and stops; let go standing still, it stays; it never tips over a pole;
##   3. the wheel, a two-finger scroll and a pinch zoom, inside the limits, and the game's own
##      camera behind the map does not move;
##   4. a drag that starts on the card does not turn the globe;
##   5. the Find Lumi button, its key and a double-click all turn back to the opening view;
##   6. the move keys turn it too (keyboard only); standing at the map, Lumi does not doze off;
##   7. the map key closes it: the game's camera, the HUD and walking are back; opening it again
##      looks at Lumi again, without the first-time hint.
## --walk-map[=S] (after S s, default 8): prints [walk-map] lines, exit 1 on a failure.
## --walk-map-shots=/abs/dir (rendered) saves a frame at each stage. In tools/check_exit.sh.

static var _fails: Array[String] = []
static var so: SliceOrbit
static var tree: SceneTree
static var gv: GlobeView
static var _shot_n: int = 0


static func run_dev(p_so: SliceOrbit) -> void:
	so = p_so
	tree = so.w.get_tree()
	await tree.create_timer(DevHooks.get_f("walk-map", 8.0)).timeout
	var w: Node = so.w
	for k: int in 240:
		if not bool(w.get("building")) and w.get("patch") != null and so.layers != null and so.layers.survey != null:
			break
		await tree.create_timer(0.5).timeout
	var p: Patch = w.get("patch") as Patch
	gv = so.layers.survey if so.layers else null
	if p == null or gv == null:
		print("[walk-map] FAIL: no Lumi / map")
		tree.quit(1)
		return
	GameState.flags["onboard_brief"] = true
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	await tree.create_timer(1.0).timeout
	var headless: bool = DisplayServer.get_name() == "headless"
	var cam0: Camera3D = tree.root.get_camera_3d()
	var dist0: float = so.cam.distance
	var lens0: bool = so.cam.lens_view
	_check(not bool(GameState.flags.get("map_turned", false)), "a new game has not turned the map yet")
	# (critic 7) Standing on the start pad, the HUD's ground line names this base, as the map's row does.
	var site: Transform3D = so.globe.sites[0]["transform"]
	var hud0: Node = w.get("hud")
	var bn: String = so.base_name_here()
	var seen: String = ""
	var on_base: bool = false
	for spot: Vector3 in [Vector3(3, 0, 3), Vector3(-3, 0, -3), Vector3(-4, 0, 4), Vector3(5, 0, -2), Vector3(0, 0, 6)]:
		var pad: Vector3 = so.globe.terrain.ground((site * spot).normalized())
		var pad_up: Vector3 = pad.normalized()
		var north: Vector3 = -SphereGrid.frame(pad_up).z
		p.place_on_sphere(pad, (north - pad_up * north.dot(pad_up)).normalized())
		await tree.create_timer(1.0).timeout
		var fh: int = p.focus_hex()
		seen = "hex %d hub %s signal \"%s\" carried %d" % [fh, str(so.globe.field.hex_hub[fh]) if fh >= 0 else "-", str(hud0.get("_signal_text")) if hud0 else "", p.carried.size()]
		on_base = hud0 != null and fh >= 0 and so.globe.field.hex_hub[fh] != 0 and p.carried.is_empty()
		if on_base:
			break
	if on_base:
		var line: String = str(hud0.call("_ground_line")) if hud0.has_method("_ground_line") else ""
		_check(bn != "" and line == TranslationServer.translate("%s  BASE") % bn.to_upper(), "on the pad the HUD's ground line names this base (\"%s\", base \"%s\")" % [line, bn])
		for k: int in 150:  # (frames: until no spoken line or part signal covers it)
			if (hud0.get("_context") as Label).text == line and (hud0.get("_context") as Label).modulate.a > 0.7:
				break
			await tree.create_timer(0.2).timeout
		_check((hud0.get("_context") as Label).text == line, "and the line on screen is that one (\"%s\")" % (hud0.get("_context") as Label).text)
	else:
		print("[walk-map] note: Lumi is not on base ground here, the HUD's base line is not checked (%s)" % seen)
	await _shot("hud")
	var pos0: Vector3 = p.global_position
	# 1. Open.
	await _tap("open_globe")
	await _until(func() -> bool: return gv.is_open, 4.0)
	_check(gv.is_open, "%s opens the map" % Settings.glyph("open_globe"))
	if not gv.is_open:
		_done()
		return
	await _settle()
	var st: Dictionary = gv.view_state()
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse pointer shows while the map is up")
	_check(bool(st["hint"]) and _hint_text().contains("Drag") or TranslationServer.get_locale() != "en" and bool(st["hint"]), "the first time, one line says how (%s)" % _hint_text())
	_check(_near(st["yaw"], st["home_yaw"]) and _near(st["pitch"], st["home_pitch"]) and is_equal_approx(float(st["zoom"]), GlobeView.ZOOM_HOME), "it opens at the view that looks at Lumi")
	var r_px: float = _globe_r_px()
	var off: float = (_lumi_px() - _globe_px()).length()
	_check(off < r_px * 0.2, "Lumi's glyph is in the middle of the globe (%.0f px from its middle, globe radius %.0f px)" % [off, r_px])
	_check(_globe_px().x > gv._left_card.get_global_rect().end.x + r_px * 0.5, "the globe's middle is clear of the card")
	await _shot("open")

	# 2. Drag: the ground under the cursor follows the cursor.
	var grab: Vector3 = _front_dir()  # the globe's own point that faces the camera now
	var a: Vector2 = _dir_px(grab)
	await _press(a)
	_check(bool(gv.view_state()["drag"]), "a left press on the globe takes hold of it")
	await _drag_by(a, Vector2(60, 0), 12)
	var b: Vector2 = _dir_px(grab)
	_check(absf((b.x - a.x) - 60.0) < 12.0 and absf(b.y - a.y) < 8.0, "dragged 60 px right, the ground under the cursor went %.0f px right (%.0f px down)" % [b.x - a.x, b.y - a.y])
	var yaw_drag: float = float(gv.view_state()["yaw"])
	_check(yaw_drag > float(st["yaw"]) + 0.05, "the globe turned with it (%.2f rad)" % (yaw_drag - float(st["yaw"])))
	await _release(a + Vector2(60, 0))  # let go while moving
	await _pframes(2)
	_check(not bool(gv.view_state()["drag"]), "letting go lets go")
	await _until(func() -> bool: return (gv.view_state()["spin"] as Vector2) == Vector2.ZERO, 4.0)
	var coast: float = float(gv.view_state()["yaw"]) - yaw_drag
	_check(coast > 0.003 and coast < 1.2, "let go while moving, it coasts a little and stops (%.2f rad more)" % coast)
	var y1: float = float(gv.view_state()["yaw"])
	await tree.create_timer(0.6).timeout
	_check(is_equal_approx(float(gv.view_state()["yaw"]), y1), "left alone it stands still (it does not turn by itself)")
	_check(bool(GameState.flags.get("map_turned", false)), "the game remembers the player has turned it")
	await _shot("dragged_right")
	# Up-down, let go standing still: no coast.
	grab = _front_dir()
	a = _dir_px(grab)
	await _press(a)
	await _drag_by(a, Vector2(0, 40), 8)
	b = _dir_px(grab)
	_check(absf((b.y - a.y) - 40.0) < 10.0 and absf(b.x - a.x) < 8.0, "dragged 40 px down, the ground under the cursor went %.0f px down (%.0f px right)" % [b.y - a.y, b.x - a.x])
	await tree.create_timer(0.4).timeout
	var p1: float = float(gv.view_state()["pitch"])
	await _release(a + Vector2(0, 40))
	await tree.create_timer(0.4).timeout
	_check(is_equal_approx(float(gv.view_state()["pitch"]), p1) and (gv.view_state()["spin"] as Vector2) == Vector2.ZERO, "let go standing still, it stays where it was put")
	# Far past the pole: it stops short and stays the right way up.
	a = _globe_px()
	await _press(a)
	await _drag_by(a, Vector2(0, 1500), 15)
	await _release(a + Vector2(0, 1500))
	await _until(func() -> bool: return (gv.view_state()["spin"] as Vector2) == Vector2.ZERO, 4.0)
	_check(is_equal_approx(float(gv.view_state()["pitch"]), GlobeView.PITCH_MAX) and _north_up(), "dragged far past the pole it stops short of it, the right way up (tip %.2f rad)" % float(gv.view_state()["pitch"]))
	await _press(a)
	await _drag_by(a, Vector2(0, -3000), 15)
	await _release(a + Vector2(0, -3000))
	await _until(func() -> bool: return (gv.view_state()["spin"] as Vector2) == Vector2.ZERO, 4.0)
	_check(is_equal_approx(float(gv.view_state()["pitch"]), -GlobeView.PITCH_MAX) and _north_up(), "and the same at the other pole (tip %.2f rad)" % float(gv.view_state()["pitch"]))
	await _shot("pole")

	# 3. Zoom.
	await _click_ctl(gv._find_btn)
	await _until(func() -> bool: return not bool(gv.view_state()["homing"]), 4.0)
	await _settle()
	var cam_d0: float = _cam_dist()
	for k: int in 3:
		await _wheel(MOUSE_BUTTON_WHEEL_UP)
	await _settle()
	var want: float = GlobeView.ZOOM_HOME * pow(0.9, 3.0)
	_check(absf(float(gv.view_state()["zoom"]) - want) < 0.01 and _cam_dist() < cam_d0 - 0.02, "three wheel notches up zoom in (%.2f, camera %.2f m -> %.2f m)" % [float(gv.view_state()["zoom"]), cam_d0, _cam_dist()])
	for k: int in 40:
		await _wheel(MOUSE_BUTTON_WHEEL_UP)
	await _settle()
	_check(is_equal_approx(float(gv.view_state()["zoom"]), GlobeView.ZOOM_MIN), "zooming in stops at the near limit (%.2f)" % float(gv.view_state()["zoom"]))
	_check(_cam_clear(), "zoomed all the way in, the camera is not inside Lumi or the globe")
	await _shot("zoom_in")
	for k: int in 60:
		await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _settle()
	_check(is_equal_approx(float(gv.view_state()["zoom"]), GlobeView.ZOOM_MAX), "zooming out stops at the far limit (%.2f)" % float(gv.view_state()["zoom"]))
	await _shot("zoom_out")
	var pan := InputEventPanGesture.new()  # two fingers on a trackpad
	pan.position = _win(_globe_px())
	pan.delta = Vector2(0, -1.0)
	for k: int in 5:
		Input.parse_input_event(pan.duplicate())
		Input.flush_buffered_events()
		await _pframes(1)
	await _settle()
	var z_pan: float = float(gv.view_state()["zoom"])
	_check(absf(z_pan - GlobeView.ZOOM_MAX * exp(-0.08 * 5.0)) < 0.05, "a two-finger scroll zooms too, each move counted once (%.2f)" % z_pan)
	var mag := InputEventMagnifyGesture.new()  # pinch
	mag.position = _win(_globe_px())
	mag.factor = 1.25
	Input.parse_input_event(mag)
	Input.flush_buffered_events()
	await _settle()
	_check(absf(float(gv.view_state()["zoom"]) - z_pan / 1.25) < 0.02, "a pinch zooms too, counted once (%.2f)" % float(gv.view_state()["zoom"]))
	_check(is_equal_approx(so.cam.distance, dist0), "the game's own camera behind the map did not zoom (%.2f m)" % so.cam.distance)

	# 4. A drag that starts on the card.
	var y_ui: float = float(gv.view_state()["yaw"])
	var on_card: Vector2 = _ctl_px(gv._pct)
	await _press(on_card)
	_check(not bool(gv.view_state()["drag"]), "a press on the card does not take hold of the globe")
	await _drag_by(on_card, Vector2(120, 30), 8)
	await _release(on_card + Vector2(120, 30))
	await tree.create_timer(0.3).timeout
	_check(is_equal_approx(float(gv.view_state()["yaw"]), y_ui), "a drag that starts on the card does not turn it")

	# 5. Find Lumi: button, key, double-click.
	await _turn_away()
	_check(not _near(gv.view_state()["yaw"], gv.view_state()["home_yaw"]), "(turned away from Lumi)")
	await _click_ctl(gv._find_btn)
	await _until(func() -> bool: return not bool(gv.view_state()["homing"]) and is_equal_approx(float(gv.view_state()["zoom"]), GlobeView.ZOOM_HOME), 5.0)
	await _settle()
	_check(_at_home(), "the Find Lumi button turns back to him, at the opening zoom (%.0f px from the middle)" % (_lumi_px() - _globe_px()).length())
	_check(is_equal_approx(float(gv.view_state()["yaw"]), float(gv.view_state()["home_yaw"])), "clicking the button did not also turn the globe")
	await _shot("found")
	await _turn_away()
	await _tap("lens_view")
	await _until(func() -> bool: return not bool(gv.view_state()["homing"]), 5.0)
	await _settle()
	_check(_at_home(), "%s turns back to him too" % Settings.glyph("lens_view"))
	_check(so.cam.lens_view == lens0, "and that key did nothing to the game behind the map")
	await _turn_away()
	var c: Vector2 = _globe_px() + Vector2(10, 10)
	await _press(c)
	await _release(c)
	await _press(c, true)
	await _release(c)
	await _until(func() -> bool: return not bool(gv.view_state()["homing"]), 5.0)
	await _settle()
	_check(_at_home(), "a double-click on the globe turns back to him too")

	# 6. Keyboard: the move keys.
	var y_k: float = float(gv.view_state()["yaw"])
	await _hold("move_right", 0.5)
	_check(float(gv.view_state()["yaw"]) > y_k + 0.3, "the move keys turn the globe (%.2f rad in half a second)" % (float(gv.view_state()["yaw"]) - y_k))
	_check(p.global_position.distance_to(pos0) < 0.05, "Lumi did not walk meanwhile")
	await tree.create_timer(2.5).timeout
	_check(not bool(gv.view_state()["hint"]), "the first-time line is gone once the globe has been turned")
	# Long at the map without walking (a rendered run showed a snore's "z" floating over the globe):
	# standing still counts as idle, holding the map does not.
	p.set("_idle_time", 50.0)
	for k: int in 3:
		await tree.physics_frame
	await _pframes(2)
	_check(not p.model.sleeping and float(p.get("_idle_time")) < 1.0, "Lumi does not doze off with the map in his hands (idle %.1f s)" % float(p.get("_idle_time")))

	# 7. Close; play is back.
	await _tap("open_globe")
	await _until(func() -> bool: return not gv.is_open, 4.0)
	await _pframes(4)
	_check(not gv.is_open, "%s closes it" % Settings.glyph("open_globe"))
	_check(tree.root.get_camera_3d() == cam0, "the game's camera is back")
	_check((p.input as PlayerInput).enabled and so.cam.input_enabled, "Lumi and the camera take input again")
	var hud: Node = so.w.get("hud")
	_check(hud == null or bool(hud.get("visible")), "the HUD is back")
	if not headless and not so.w.get("bot"):
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the mouse is the camera's again")
	_check(is_equal_approx(so.cam.distance, dist0) and so.cam.lens_view == lens0, "the game's camera is as it was (%.2f m)" % so.cam.distance)
	var stack: Node3D = p.get_node_or_null("Stack") as Node3D
	_check(stack == null or stack.visible, "what Lumi carries shows again")
	await _hold("move_forward", 1.2)
	_check(p.global_position.distance_to(pos0) > 0.3, "the move key walks Lumi again (%.1f m)" % p.global_position.distance_to(pos0))
	await _shot("closed")
	# Open again: at Lumi, no first-time line.
	await _tap("open_globe")
	await _until(func() -> bool: return gv.is_open, 4.0)
	await _settle()
	_check(gv.is_open and _at_home(), "opened again, it looks at Lumi again")
	_check(not bool(gv.view_state()["hint"]), "and the first-time line does not come back")
	await _shot("reopened")
	await _tap("open_globe")
	await _until(func() -> bool: return not gv.is_open, 4.0)
	_done()


static func _done() -> void:
	print("[walk-map] %s" % ("PASS" if _fails.is_empty() else "FAIL: " + "; ".join(_fails)))
	tree.quit(0 if _fails.is_empty() else 1)


# --- What is on screen ---------------------------------------------------------------------------

static func _cam() -> Camera3D:
	return gv._world_cam if gv._handheld else gv._cam


## A point of the 3D view in the pixels the mouse is measured in.
static func _px(world: Vector3) -> Vector2:
	return _cam().unproject_position(world)


static func _globe_px() -> Vector2:
	return _px(gv._pivot.global_position)


static func _dir_px(dir: Vector3) -> Vector2:
	return _px(gv._pivot.to_global(dir))


static func _lumi_px() -> Vector2:
	var pc: int = int(gv.patch_cell_provider.call())
	return _dir_px((gv.sphere_grid.centers[pc] as Vector3).normalized())


static func _globe_r_px() -> float:
	var c: Vector3 = gv._pivot.global_position
	var r: float = gv._pivot.global_basis.x.length()
	return (_px(c + _cam().global_basis.x * r) - _px(c)).length()


## The globe's own direction that faces the camera now.
static func _front_dir() -> Vector3:
	return (gv._pivot.global_basis.orthonormalized().inverse() * (_cam().global_position - gv._pivot.global_position)).normalized()


static func _north_up() -> bool:
	return gv._pivot.global_basis.y.normalized().dot(_cam().global_basis.y) > 0.1


static func _cam_dist() -> float:
	return _cam().global_position.distance_to(gv._pivot.global_position)


## The map's camera stands outside the globe and well clear of Lumi's body.
static func _cam_clear() -> bool:
	var p: Node3D = gv.holder
	var r: float = gv._pivot.global_basis.x.length()
	if not gv._handheld or p == null:
		return _cam_dist() > r * 1.2
	var up: Vector3 = p.global_position.normalized()
	var head: Vector3 = p.global_position + up * 0.9
	return _cam_dist() > r * 1.5 and _cam().global_position.distance_to(head) > 0.9


static func _near(a: Variant, b: Variant) -> bool:
	return absf(angle_difference(float(a), float(b))) < 0.01


static func _at_home() -> bool:
	var st: Dictionary = gv.view_state()
	return _near(st["yaw"], st["home_yaw"]) and _near(st["pitch"], st["home_pitch"]) and is_equal_approx(float(st["zoom"]), GlobeView.ZOOM_HOME) \
		and (_lumi_px() - _globe_px()).length() < _globe_r_px() * 0.2


static func _hint_text() -> String:
	var out: String = ""
	for l: Node in gv._first_hint.find_children("*", "Label", true, false):
		out += (l as Label).text
	return out


static func _ctl_px(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size * 0.5)


# --- Real input ------------------------------------------------------------------------------------

static func _win(at: Vector2) -> Vector2:
	return tree.root.get_final_transform() * at


static func _move(at: Vector2, rel: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = _win(at)
	mv.global_position = mv.position
	mv.relative = tree.root.get_final_transform().basis_xform(rel)  # in window pixels, as the position
	mv.screen_relative = mv.relative
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT if rel != Vector2.ZERO else 0
	Input.parse_input_event(mv)
	Input.flush_buffered_events()


static func _button(at: Vector2, down: bool, idx: MouseButton = MOUSE_BUTTON_LEFT, dbl: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = idx
	ev.pressed = down
	ev.double_click = dbl and down
	ev.position = _win(at)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down and idx == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


static func _press(at: Vector2, dbl: bool = false) -> void:
	_move(at, Vector2.ZERO)
	await _pframes(2)
	_button(at, true, MOUSE_BUTTON_LEFT, dbl)
	await _pframes(2)


static func _release(at: Vector2) -> void:
	_button(at, false)
	await _pframes(1)


## The pressed mouse moves by `by` in `steps` motions, one a frame (a hand's drag, not a jump).
static func _drag_by(from: Vector2, by: Vector2, steps: int) -> void:
	for k: int in steps:
		_move(from + by * float(k + 1) / float(steps), by / float(steps))
		await _pframes(1)


static func _wheel(idx: MouseButton) -> void:
	var at: Vector2 = _globe_px()
	_button(at, true, idx)
	_button(at, false, idx)
	await _pframes(1)


static func _click_ctl(c: Control) -> void:
	var at: Vector2 = _ctl_px(c)
	await _press(at)
	await _release(at)
	await _pframes(2)


## A quarter turn away from Lumi and zoomed in, by hand.
static func _turn_away() -> void:
	var a: Vector2 = _globe_px()
	await _press(a)
	await _drag_by(a, Vector2(_globe_r_px() * 1.2, _globe_r_px() * 0.3), 10)
	await tree.create_timer(0.2).timeout
	await _release(a + Vector2(_globe_r_px() * 1.2, _globe_r_px() * 0.3))
	for k: int in 4:
		await _wheel(MOUSE_BUTTON_WHEEL_UP)
	await _settle()


## The zoom glide and the map camera's follow have come to rest.
static func _settle() -> void:
	var last: Vector3 = Vector3.INF
	for k: int in 80:
		await tree.create_timer(0.1).timeout
		var at: Vector3 = _cam().global_position
		var st: Dictionary = gv.view_state()
		if at.distance_to(last) < 0.0005 and is_equal_approx(float(st["zoom"]), float(st["zoom_to"])) and not bool(st["homing"]):
			return
		last = at


static func _until(f: Callable, secs: float) -> void:
	var t: float = 0.0
	while t < secs and not bool(f.call()):
		await tree.create_timer(0.05).timeout
		t += 0.05


static func _event(action: String) -> InputEvent:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev.duplicate()
	return null


static func _send(action: String, down: bool) -> void:
	var ev: InputEvent = _event(action)
	if ev == null:
		_check(false, "no key bound to %s" % action)
		return
	(ev as InputEventKey).pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


static func _tap(action: String) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(0.1).timeout
	_send(action, false)
	await _pframes(2)


static func _hold(action: String, secs: float) -> void:
	await tree.physics_frame
	_send(action, true)
	await tree.create_timer(secs).timeout
	_send(action, false)
	await _pframes(2)


static func _pframes(n: int) -> void:
	for k: int in n:
		await tree.process_frame


static func _check(ok: bool, what: String) -> void:
	print("[walk-map] %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## (rendered runs, --walk-map-shots=DIR) one frame of what the player sees now.
static func _shot(name: String) -> void:
	var dir: String = DevHooks.get_s("walk-map-shots", "")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await tree.create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = "%s/%02d_%s.png" % [dir, _shot_n, name]
	_shot_n += 1
	tree.root.get_texture().get_image().save_png(path)
	print("[walk-map] shot %s" % path)
