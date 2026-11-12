extends GutTest
## [onboard] First minutes: WREN's brief and the story objectives, the hex outline contour, the
## key-hint strip and the part detector's gate.

var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats


func _cfg() -> Dictionary:
	return Economy.planet_table("tutorial")


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
		assert_true(d.has("desc") and str(d["desc"]) != "", "%s has a why" % d["id"])
		assert_lt(str(d["desc"]).length(), 60, "%s: the why is one short line" % d["id"])
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
	var g: Dictionary = Economy.planet_table("goals")
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
	assert_lte(float(c.get("cubes", 0)), 500.0, "the first tier at the accepted price")
	assert_false(c.has("parts"), "a build costs cubes only")
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
	add_child_autofree(gp)
	gp._process(100.0)
	assert_eq(gp.modulate.a, 1.0, "the goal column stays fully readable")
	assert_eq(gp.readout.modulate.a, 1.0, "and so do the three goals beside the card")
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
