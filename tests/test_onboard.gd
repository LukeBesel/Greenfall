extends GutTest
## [onboard] First minutes: WREN's brief and the story objectives, the hex outline contour, the
## Requests board unlock, the key-hint strip and the part detector's gate.

var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats


func _cfg() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/objectives.json"))


func test_brief_is_short() -> void:
	var lines: Array = _cfg()["brief"]["lines"]
	assert_between(lines.size(), 1, 2, "one last message (two subtitle lines at most)")
	for l: Variant in lines:
		assert_lt(str(l).length(), 115, "one subtitle line: %s" % l)


func test_objectives_have_a_short_why() -> void:
	var list: Array = _cfg()["objectives"]
	assert_eq(str(list[0]["text"]), "Power the base: sell 3 bales")
	assert_true(list.any(func(d: Dictionary) -> bool: return str(d["text"]) == "Build your first robot"))
	var font: Font = HudReadable.font()
	for d: Dictionary in list:
		assert_true(d.has("desc") and str(d["desc"]) != "", "%s has a why" % d["id"])
		assert_lt(str(d["desc"]).length(), 60, "%s: the why is one short line" % d["id"])
		assert_false(str(d["text"]).to_lower().contains("this hex"), "no 'this hex'")
		assert_lt(font.get_string_size(str(d["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, (ObjectiveCard.W - 28.0) * 2.0, "title fits two lines")
	var hex_ones: Array = list.filter(func(d: Dictionary) -> bool: return d.get("hex", false))
	assert_eq(hex_ones.size(), 1)
	assert_eq(str(hex_ones[0]["text"]), "Clean a hex")


func test_checklist_has_no_this_hex() -> void:
	for s: Dictionary in Tutorial.STEPS:
		assert_false(str(s["text"]).to_lower().contains("this hex"))


func test_objective_values_and_progress() -> void:
	var o := Objectives.new()
	o.chain = _cfg()["objectives"]
	o.revealed = true
	o.step = 0
	GameState.stats["cubes_cashed"] = 1
	assert_eq(o.value_of(o.current()), 1.0)
	var pr: Array = o.progress()
	assert_almost_eq(float(pr[0]), 1.0 / 3.0, 0.001)
	assert_eq(str(pr[1]), "1 / 3")
	o.revealed = false
	assert_true(o.current().is_empty(), "nothing on the card before the brief")
	o.free()


func test_wait_flag_shows_hint() -> void:
	var d: Dictionary = {"text": "Plant the first seed", "desc": "Why.", "hint": "Wait.", "wait_flag": "seed_signal"}
	GameState.flags["seed_signal"] = false
	assert_eq(Objectives.texts(d)[1], "Wait.")
	GameState.flags["seed_signal"] = true
	assert_eq(Objectives.texts(d)[1], "Why.")


func _field() -> HexField:
	var f := HexField.new(4, 3.2, 99)
	f.hex_axial = Hex.spiral(4)
	for i: int in f.hex_axial.size():
		f.axial_to_id[f.hex_axial[i]] = i
	return f


func test_contour_is_a_closed_loop_around_the_hex() -> void:
	var f := _field()
	var h: int = int(f.axial_to_id[Vector2i(1, 0)])
	for natural: bool in [false, true]:
		f.natural_borders = natural
		var loops: Array[PackedVector2Array] = ObjectiveHex.contour(f, h)
		assert_gt(loops.size(), 0)
		var c3: Vector3 = f.hex_center(h)
		var c := Vector2(c3.x, c3.z)
		var biggest: PackedVector2Array = loops[0]
		for l: PackedVector2Array in loops:
			if l.size() > biggest.size():
				biggest = l
		var per: float = 0.0
		for i: int in biggest.size():
			per += biggest[i].distance_to(biggest[(i + 1) % biggest.size()])
			var p := Vector3(biggest[i].x, 0, biggest[i].y)
			var got: int = f.hex_at(p + f.border_warp(p)) if natural else f.hex_at(p)
			assert_lt(absf(ObjectiveHex.inside_value(f, h, biggest[i])), 0.12, "points sit on the border")
			if i % 9 == 0 and not natural:
				assert_lt(c.distance_to(biggest[i]), f.hex_size + 0.2, "straight hex: within the corners")
			if got != h and got != -1:
				pass  # on the border either side is fine
		assert_gt(per, 6.0 * f.hex_size * 0.8, "about a hex perimeter (natural: %s)" % natural)
	if not f.natural_borders:
		return
	assert_gt(ObjectiveHex.inside_value(f, h, Vector2(f.hex_center(h).x, f.hex_center(h).z)), -10.0)


func test_inside_value_signs_on_a_straight_grid() -> void:
	var f := _field()
	f.natural_borders = false
	var h: int = int(f.axial_to_id[Vector2i(0, 0)])
	assert_gt(ObjectiveHex.inside_value(f, h, Vector2.ZERO), 0.0)
	assert_lt(ObjectiveHex.inside_value(f, h, Vector2(f.hex_size * 2.0, 0)), 0.0)


func test_requests_unlock_later() -> void:
	var st: Dictionary = {"slots": [], "done_total": 0}
	assert_false(Contracts.unlock_due(1, 600.0, st), "not in the first minutes")
	assert_false(Contracts.unlock_due(2, 1800.0, st))
	assert_true(Contracts.unlock_due(3, 60.0, st), "base level 3")
	assert_true(Contracts.unlock_due(1, 2700.0, st), "or 45 minutes")
	assert_true(Contracts.unlock_due(1, 10.0, {"slots": [{"state": "active"}], "done_total": 0}), "a save already using it")
	assert_true(Contracts.unlock_due(1, 10.0, {"slots": [], "done_total": 2}))


func test_key_hints_show_first_minutes_and_on_demand() -> void:
	assert_true(KeyHints.want_shown(Settings.HudMode.MINIMAL, 30.0, false, false), "first minutes")
	assert_false(KeyHints.want_shown(Settings.HudMode.MINIMAL, 3600.0, false, false), "later: hidden")
	assert_true(KeyHints.want_shown(Settings.HudMode.MINIMAL, 3600.0, false, true), "hold Tab")
	assert_true(KeyHints.want_shown(Settings.HudMode.FULL, 3600.0, false, false))
	assert_false(KeyHints.want_shown(Settings.HudMode.HIDDEN, 10.0, true, false))
	assert_gte(KeyHints.NAME_PX, 14, "readable size")


func test_key_hints_strip_builds() -> void:
	var k := KeyHints.new(KeyHints.Mode.PAUSE)
	add_child_autofree(k)
	assert_gt(k._flow.get_child_count(), 6)
	assert_true(k.visible)


func test_detector_waits_for_the_checklist() -> void:
	GameState.flags["tutorial_step"] = 0
	assert_false(PartDetector.active())
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	assert_true(PartDetector.active())


func test_objective_card_shows_current() -> void:
	var o := Objectives.new()
	o.chain = _cfg()["objectives"]
	o.revealed = true
	o.step = 2
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	card.objectives = o
	card.refresh(false)
	assert_true(card.visible)
	assert_eq(card._title.text, "Clean a hex")
	o.step = o.chain.size()
	card.refresh(false)
	assert_true(o.current().is_empty())
	o.free()


func test_waypoint_quiet_during_checklist_and_builds() -> void:
	var o := Objectives.new()
	GameState.flags["tutorial_step"] = 0
	assert_eq(o.waypoint_target(), null, "the checklist has its own marker")
	o.free()
	var w := Waypoint.new()
	add_child_autofree(w)
	assert_eq(w._trail.multimesh.instance_count, Waypoint.TRAIL_N)
	w.set_target(Vector3(10, 0, 0))
	assert_eq(w._target, Vector3(10, 0, 0))


func test_shard_goal_wording_is_plain() -> void:
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/goals.json"))
	for d: Dictionary in g["goals"]:
		assert_ne(str(d["text"]), "Read a memory shard", "says what to do: find one (purple marker)")


func test_signal_tower_tiers_and_migration() -> void:
	assert_eq(SignalTower.max_tier(), 4)
	assert_eq(SignalTower.signal_pct(0), 0)
	assert_eq(SignalTower.signal_pct(4), 100)
	assert_eq(SignalTower.migrated_tier(0), 1, "an old save that heard WREN keeps a working tower")
	assert_eq(SignalTower.migrated_tier(10), 2)
	assert_eq(SignalTower.migrated_tier(40), 3)
	GameState.flags["signal_tower"] = 0
	var c: Dictionary = SignalTower.next_cost()
	for k: String in c:
		assert_true(k in ["cubes", "parts", "seeds"], "three currencies only")
	assert_lt(float(c.get("cubes", 0)), 200.0, "the first tier is cheap")
	GameState.flags.erase("signal_tower")
	GameState.flags["wren_awake"] = true
	SignalTower.migrate(null)
	assert_eq(SignalTower.tier(), 1)
	GameState.flags.erase("signal_tower")
	GameState.flags.erase("wren_awake")
	GameState.stats["cubes_cashed"] = 0
	GameState.flags["tutorial_step"] = 0
	SignalTower.migrate(null)
	assert_eq(SignalTower.tier(), 0, "a new game starts silent")


func test_brief_is_wrens_last_message() -> void:
	var lines: Array = _cfg()["brief"]["lines"]
	assert_string_contains(str(lines[0]), "WREN")
	assert_string_contains(str(lines[-1]), "[glitch]", "it breaks up in static")
	assert_string_contains(str(lines[-1]).to_lower(), "signal tower")


# --- [onboard2] -------------------------------------------------------------------------------

func test_notify_stack_never_shows_ghost_rows() -> void:
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for i: int in 6:
		ns.push("Toast number %d with enough words to wrap onto a second line here" % i, "info")
	assert_lte(ns.count(), NotifyStack.MAX, "at most three rows")
	assert_lte(ns.live_count(), 2, "two-line rows: the line budget retires older ones at once")
	ns._process(0.3)
	assert_lte(ns.count(), 2, "rows on their way out are gone within a quarter second")
	for i: int in ns.count():
		ns._process(0.0)
	ns._process(0.31)
	for r: Dictionary in ns._rows:
		assert_true((r["node"] as Control).modulate.a > 0.99, "every row left is fully visible, never half-faded")


func test_notify_short_rows_stack_three() -> void:
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for t: String in ["One", "Two", "Three", "Four"]:
		ns.push(t, "info")
	assert_eq(ns.count(), 3)
	assert_eq(ns.live_count(), 3)


func test_camera_pulls_in_when_a_roof_fills_the_view_edge() -> void:
	var focus := Vector3(5000, 1.1, 0)
	var b: Basis = CameraRig.view_basis(0.0, -0.75)
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	assert_eq(CameraRig.clear_length(space, focus, b, 22.0, 3.5, 70.0, 16.0 / 9.0), 22.0, "open sky: full length")
	# A building roof under the camera's lower-left view edge, close to where the camera would sit.
	var cam_pos: Vector3 = focus + b * Vector3(0, 0, 22.0)
	var body := StaticBody3D.new()
	body.collision_layer = PhysLayers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 1, 8)
	cs.shape = box
	body.add_child(cs)
	add_child_autofree(body)
	body.global_position = cam_pos + Vector3(-3.0, -5.0, 0.0)
	await wait_physics_frames(2)
	var l: float = CameraRig.clear_length(space, focus, b, 22.0, 3.5, 70.0, 16.0 / 9.0)
	assert_lt(l, 22.0, "pulled in past the roof edge")
	assert_gte(l, 3.5)


func test_camera_ignores_the_ground() -> void:
	var focus := Vector3(-5000, 1.1, 0)
	var body := StaticBody3D.new()
	body.collision_layer = PhysLayers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	body.add_child(cs)
	add_child_autofree(body)
	body.global_position = Vector3(-5000, -0.5, 0)
	await wait_physics_frames(2)
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var b: Basis = CameraRig.view_basis(0.0, -0.3)
	assert_eq(CameraRig.clear_length(space, focus, b, 6.2, 3.5, 70.0, 16.0 / 9.0), 6.2, "the ground under Lumi doesn't pull the camera in")


func test_waypoint_edge_point_stays_on_the_border() -> void:
	var r := Rect2(14, 14, 1252, 692)
	assert_eq(Waypoint.edge_point(r, Vector2(1, 0)), Vector2(1266, 360))
	assert_eq(Waypoint.edge_point(r, Vector2(0, -3)), Vector2(640, 14))
	var p: Vector2 = Waypoint.edge_point(r, Vector2(-5, 4))
	assert_true(is_equal_approx(p.x, 14.0) or is_equal_approx(p.y, 706.0))
	var w := Waypoint.new()
	add_child_autofree(w)
	assert_not_null(w.arrow)
	assert_false(w.arrow.visible, "no arrow without a target")
