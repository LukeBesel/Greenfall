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
	assert_eq(str(list[0]["text"]), "Fill the trash bin 3 times")  # [onboard2] nothing early needs the Baler
	var ids: Array = list.map(func(d: Dictionary) -> String: return str(d["id"]))
	assert_lt(ids.find("baler"), ids.find("power"), "the Baler comes before any bale")
	assert_true(list.any(func(d: Dictionary) -> bool: return str(d["text"]) == "Build your first robot"))
	var font: Font = HudReadable.font()
	for d: Dictionary in list:
		assert_true(Objectives.step_why(d) != "", "%s has a why" % d["id"])  # [v6pace] desc, or the story reason
		assert_lt(Objectives.step_why(d).length(), 60 if d.has("desc") else 81, "%s: the why is one short line" % d["id"])  # [v6pace] story reasons fit the goal card (80)
		assert_false(str(d["text"]).to_lower().contains("this hex"), "no 'this hex'")
		assert_lt(font.get_string_size(str(d["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, (ObjectiveCard.W - 28.0) * 2.0, "title fits two lines")
	var hex_ones: Array = list.filter(func(d: Dictionary) -> bool: return d.get("hex", false))
	assert_eq(hex_ones.size(), 1)
	assert_eq(str(hex_ones[0]["text"]), "Clean the glowing hex")


func test_checklist_has_no_this_hex() -> void:
	for s: Dictionary in Tutorial.STEPS:
		assert_false(str(s["text"]).to_lower().contains("this hex"))


func test_objective_values_and_progress() -> void:
	var o := Objectives.new()
	o.chain = _cfg()["objectives"]
	o.revealed = true
	o.step = o.chain.map(func(d: Dictionary) -> String: return str(d["id"])).find("power")
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
	o.step = o.chain.map(func(d: Dictionary) -> String: return str(d["id"])).find("hex")
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	card.objectives = o
	card.refresh(false)
	assert_true(card.visible)
	assert_eq(card._title.text, "Clean the glowing hex")
	o.step = o.chain.size()
	card.refresh(false)
	assert_true(o.current().is_empty())
	o.free()


func test_waypoint_quiet_during_checklist_and_builds() -> void:
	var o := Objectives.new()
	GameState.flags["tutorial_step"] = 0
	assert_eq(o.waypoint_target(), null, "no world, no beam")  # [v2guide] the checklist step now drives the one beacon (places only)
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
		ns.push("Toast number %d with enough words to wrap onto a second line here" % i, "story")
	for k: int in 30:
		ns._process(0.25)
		assert_lte(ns.count(), NotifyStack.MAX, "at most three rows")
		assert_lte(ns.live_count(), NotifyStack.LIVE_MAX, "never more readable rows than the stack allows")
	ns._process(0.31)
	for r: Dictionary in ns._rows:
		if float(r["left"]) > NotifyStack.FADE_OUT_S + 0.31 and float(r["age"]) >= 0.3:
			assert_true((r["node"] as Control).modulate.a > 0.99, "a row that is staying is fully visible, never half-faded")


func test_notify_rows_come_in_turn() -> void:  # [v9d] the toast queue
	var ns := NotifyStack.new()
	add_child_autofree(ns)
	for t: String in ["One", "Two", "Three"]:
		ns.push(t, "hint")
	assert_eq(ns.count(), 1)
	ns._process(NotifyStack.GAP_S + 0.05)
	assert_eq(ns.count(), 2, "the next line once the first was up a moment")


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


# --- [onboard2] One message line ---------------------------------------------------------------

func _bar() -> Subtitles:
	var s := Subtitles.new()
	add_child_autofree(s)
	return s


## Steps the bar in small frames; returns [[text, seconds fully shown], ...] in order shown.
func _run(s: Subtitles, seconds: float) -> Array:
	var seen: Array = []
	var t: float = 0.0
	while t < seconds:
		s._process(0.05)
		t += 0.05
		var cur: String = s.current_text()
		if cur != "":
			if seen.is_empty() or seen[-1][0] != cur:
				seen.append([cur, 0.0])
			if s._phase == 2:
				seen[-1][1] = float(seen[-1][1]) + 0.05
	return seen


func test_two_messages_at_once_never_show_together() -> void:
	var s := _bar()
	s.queue_toast("The drone is heading for a clean hex.", "info")  # [v4calm] sightings are cut now
	s.queue_toast("Workbench fixed. Press E at it to spend cubes on upgrades.", "info")
	var seen: Array = _run(s, 20.0)
	assert_eq(seen.size(), 2, "both shown, one after the other")
	for e: Array in seen:
		assert_gte(float(e[1]) + 0.051, Subtitles.duration_for(str(e[0])), "each stays up its reading time: %s" % e[0])


func test_story_goes_before_info_and_speech_before_both() -> void:
	var s := _bar()
	s.queue_toast("First info line.", "info")  # goes up at once
	s.queue_toast("Second info line.", "info")
	s.queue_toast("A story beat.", "story")
	s.queue_line("WREN speaks.", "wren")
	var order: Array = _run(s, 45.0).map(func(e: Array) -> String: return str(e[0]))  # [v4calm] longer gaps round toasts
	assert_eq(order, ["First info line.", "WREN speaks.", "A story beat.", "Second info line."])


func test_numbers_merge_into_one_line() -> void:
	var s := _bar()
	s.queue_toast("Something else first.", "info")
	s.queue_toast("+12 cubes from robots.", "info")
	s.queue_toast("+15 cubes from robots.", "info")
	s.queue_toast("+19 cubes from robots.", "info")
	var order: Array = _run(s, 20.0).map(func(e: Array) -> String: return str(e[0]))
	assert_eq(order, ["Something else first.", "+19 cubes from robots."])


func test_story_is_never_dropped_low_value_is() -> void:
	var s := _bar()
	for i: int in 12:
		s.queue_toast("Info number %s." % ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"][i], "info")
	s.queue_toast("Important story line.", "story")
	assert_lte(s._queue.size(), Subtitles.TOAST_MAX_QUEUE)
	assert_true(s._queue.any(func(q: Dictionary) -> bool: return q["text"] == "Important story line."))


func test_toasts_do_not_hold_up_cutscenes() -> void:
	var s := _bar()
	s.queue_toast("A reward.", "info")
	assert_false(s.is_busy("*"), "cutscenes wait on speech only")
	s.queue_line("Intro line.", "")
	assert_true(s.is_busy("*"))


func test_goals_never_dim_in_minimal_hud() -> void:  # [onboard2] QA P1
	var mode: int = Settings.hud_mode
	Settings.hud_mode = Settings.HudMode.MINIMAL
	var gp := GoalsPanel.new()
	gp._idle = 100.0
	gp._alpha = 1.0
	var src: String = (gp.get_script() as Script).source_code
	assert_false(src.contains("want = 0.5"), "no dimming branch")
	gp.free()
	Settings.hud_mode = mode


func test_early_objectives_use_what_lumi_has() -> void:  # [onboard2] QA P2
	var o := Objectives.new()
	o.chain = _cfg()["objectives"]
	var old: Dictionary = GameState.stats.duplicate()
	GameState.stats["junk_dumps"] = 2
	o.step = 0
	assert_eq(o.value_of(o.chain[0]), 2.0, "the trash bin count")
	for d: Dictionary in o.chain:
		if str(d["id"]) in ["scoop_size", "compartment", "baler"]:
			assert_eq(str(d["type"]), "upgrade")
			assert_true(Economy.upgrade_cost(str(d["key"])).to_float() > 0.0, "%s is a real upgrade" % d["key"])
	GameState.stats = old
	o.free()


func test_old_save_keeps_its_place_in_the_chain() -> void:  # [onboard2]
	var keep: Dictionary = GameState.flags.duplicate(true)
	GameState.flags = {"objective_step": 3, "onboard_brief": true}
	var o := Objectives.new()
	add_child_autofree(o)
	assert_true(o.step >= 3 + Objectives.EARLY_ADDED, "shifted past the new early objectives")
	assert_true(GameState.flags.get("objectives_v2", false))
	GameState.flags = keep


func test_no_bale_key_before_the_baler() -> void:  # [onboard2] QA P2
	var names: Array = KeyHints.items_for(true, false).map(func(it: Array) -> String: return str(it[0]))
	assert_false("cube" in names)
	names = KeyHints.items_for(true, true).map(func(it: Array) -> String: return str(it[0]))
	assert_true("cube" in names)
