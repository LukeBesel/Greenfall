extends GutTest
## [v4calm] Owner playtest 3, items 45/47/49/50: one-off lines once per save, reward chatter cut,
## one message at a time with spacing, and much less beeping.

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	BeepGate.reset()


func after_each() -> void:
	GameState.from_dict(_saved)
	BeepGate.reset()


func test_once_is_once_and_survives_save_load() -> void:
	assert_true(Once.take("wren_lake_clear"))
	assert_false(Once.take("wren_lake_clear"), "second time: no")
	assert_true(Once.done("wren_lake_clear"))
	var d: Dictionary = GameState.to_dict()
	GameState.new_game()
	assert_false(Once.done("wren_lake_clear"), "a fresh game starts clean")
	GameState.from_dict(JSON.parse_string(JSON.stringify(d)))  # through text, like a save file
	assert_true(Once.done("wren_lake_clear"), "kept across save and load")
	assert_false(Once.take("wren_lake_clear"))
	assert_true(Once.take("another_key"), "keys are independent")


func test_lake_line_plays_once_for_many_lake_hexes() -> void:
	var w := Wren.new()
	add_child_autofree(w)
	var heard: Array[String] = []
	w.line_started.connect(func(t: String, _s: int) -> void: heard.append(t))
	# The guard the lake sites use (planet/sites/sphere_water.gd, water/water_view.gd).
	for i: int in 6:
		if Once.take("wren_lake_clear"):
			w.line_started.emit("The water... I can see the bottom.", 1)
	assert_eq(heard.size(), 1)


func test_wren_robot_line_once_and_chatter_muted() -> void:
	assert_true("robot_built" in Wren.ONCE)
	for t: String in ["hex_clean", "perfect", "upgrade", "milestone", "idle"]:
		assert_true(t in Wren.MUTED, t)
	var w := Wren.new()
	add_child_autofree(w)
	# The queue is what say() fills; awake() needs a tower, so check the gates by hand.
	assert_true(Once.take("wren_robot_built"))
	assert_false(Once.take("wren_robot_built"), "the 'another voice' line never repeats")


func test_reward_chatter_is_cut() -> void:
	assert_true(Subtitles.cut("Salvaged: Rusty Arm  +10 parts", "reward"))
	assert_true(Subtitles.cut("Achievement: First Scoop. Scoop your first piece of junk.", "story"), "achievements arrive as story")
	assert_true(Subtitles.cut("Lumi reached level 3", "level"))
	assert_false(Subtitles.cut("Build the signal tower", "goal"))
	assert_false(Subtitles.cut("Ledger drone inbound, south!", "story"))
	assert_false(Subtitles.cut("Chest full.", "info"), "warnings still show")


func test_cut_toasts_never_queue() -> void:
	var s := Subtitles.new()
	add_child_autofree(s)
	await get_tree().process_frame
	s.queue_toast("Hex Lv 1  Clean.   +25 cubes", "reward")
	s.queue_toast("Achievement: Tinkerer. Buy your first upgrade.", "story")
	assert_eq(s.current_text(), "")
	s.queue_toast("New goal: build the tower", "goal")
	assert_eq(s.current_text(), "New goal: build the tower")


func test_one_message_at_a_time_with_spacing() -> void:
	var s := Subtitles.new()
	add_child_autofree(s)
	await get_tree().process_frame
	s.queue_toast("First warning.", "info")
	s.queue_toast("Second warning.", "info")
	assert_eq(s.current_text(), "First warning.", "only one on screen")
	assert_gte(Subtitles.gap_after("toast:info", false), 2.0, "a toast leaves room after it")
	assert_gte(Subtitles.gap_after("wren", true), 2.0, "and before it")
	assert_almost_eq(Subtitles.gap_after("wren", false), Subtitles.GAP_S, 0.001, "speech keeps its short beat")


func test_beep_talk_is_one_soft_chirp_for_wren_only() -> void:
	assert_eq(Subtitles.beeps_for("wren", true), 1)
	assert_eq(Subtitles.beeps_for("wren", false), 0, "not again on the next chunk")
	assert_eq(Subtitles.beeps_for("", true), 0, "narration: none")
	assert_lte(Subtitles.CHIRP_DB, -18.0)


func test_detector_is_silent_unless_very_close() -> void:
	assert_false(PartDetector.beep_allowed(5.0, 0.0), "5 m: silent")
	assert_true(PartDetector.beep_allowed(2.5, 0.0), "2.5 m: one beep")
	assert_false(PartDetector.beep_allowed(2.5, 0.5), "not before the gap runs out")
	assert_gte(PartDetector.SOUND_GAP_S, 2.0)
	assert_lte(PartDetector.SOUND_NEAR_M, 3.0)


func test_beep_gate_shares_one_slot() -> void:
	assert_true(BeepGate.take("bot", 8.0))
	assert_false(BeepGate.take("bot", 8.0), "a second bot right after: silent")
	assert_true(BeepGate.take("other", 8.0), "slots are separate")
