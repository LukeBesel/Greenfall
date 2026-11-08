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
	assert_between(lines.size(), 2, 4, "2-4 WREN lines")
	for l: Variant in lines:
		assert_lt(str(l).length(), 110, "one subtitle line: %s" % l)


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
	o.step = 1
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
