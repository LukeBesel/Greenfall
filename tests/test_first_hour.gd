extends GutTest
## [first] First-hour polish: restart checklist (one thing per step, card, in-world marker), the
## scoop combo ladder, the sale coin flight hold, and the early seed scarcity data.

var _saved_pad: bool


func before_each() -> void:
	_saved_pad = Settings.last_input_pad
	Settings.last_input_pad = false


func after_each() -> void:
	Settings.last_input_pad = _saved_pad


func test_steps_teach_one_thing_and_stay_short() -> void:
	var ids: Array[String] = []
	for s: Dictionary in Tutorial.STEPS:
		ids.append(str(s["id"]))
		var t: String = Tutorial.glyphs(str(s["text"]))
		assert_lt(t.length(), 44, "step '%s' is one short line" % s["id"])
		assert_false(t.contains(". "), "step '%s' has a single sentence" % s["id"])
	assert_eq(ids, ["repair", "scoop", "dump", "upgrade"])  # [onboard2] no bales before the Baler  # [onboard] the hex step is the "Clean a hex" objective


func test_glyphs_bb_colours_keys() -> void:
	var bb: String = Tutorial.glyphs_bb("Hold  {scoop}  to scoop")
	assert_true(bb.contains("[color="))
	assert_true(bb.contains("LMB"))
	assert_eq(ChecklistCard._strip_bb(bb), "Hold  LMB  to scoop")


func test_tutorial_progress_counts_scoops() -> void:
	var t := Tutorial.new()
	t.step = 1
	t._count = 3
	var pr: Array = t.step_progress()
	assert_almost_eq(float(pr[0]), 3.0 / 8.0, 0.001)
	assert_eq(str(pr[1]), "3 / 8")
	t.step = 2
	assert_eq(float(t.step_progress()[0]), -1.0, "one-shot steps have no bar")
	t.step = Tutorial.STEPS.size()
	assert_true(t.done())
	assert_eq(t.current_text(), "")
	t.free()


func test_checklist_card_shows_and_finishes() -> void:
	var card := ChecklistCard.new()
	add_child_autofree(card)
	card.set_text("Hold  LMB  to scoop junk")
	assert_true(card.visible)
	assert_eq(card._cap.text, "NEXT STEP", "without a tutorial it is a plain next-step hint")
	card.set_text("")
	assert_eq(card._current, "")


func test_marker_follows_target_and_hides() -> void:
	var m := TutorialMarker.new()
	add_child_autofree(m)
	m.set_target(Vector3(3, 0, 4), "piece")
	assert_true(m._has)
	assert_eq(m._kind, "piece")
	m.set_target(Vector3(40, 0, 4), "pad")
	assert_eq(m._pos, Vector3(40, 0, 4), "a far jump snaps instead of streaking")
	m.clear()
	assert_false(m._has)


func test_scoop_ladder_stays_gentle() -> void:
	var prev: int = -1
	for i: int in 6:
		var s: int = Audio.ladder_semitones(i)
		assert_gt(s, prev, "climbs for the first notes")
		prev = s
	for i: int in range(6, 30):
		assert_lte(Audio.ladder_semitones(i), 12, "never above one octave")


func test_coin_flight_hold_and_land() -> void:
	assert_eq(CoinFlight.coin_count(1.0), 3)
	assert_eq(CoinFlight.coin_count(1.0e7), 8)
	var cc := CurrencyCluster.new()
	add_child_autofree(cc)
	cc.in_flight = 30.0
	cc.land(10.0)
	assert_almost_eq(cc.in_flight, 20.0, 0.001)
	cc.land(50.0)
	assert_eq(cc.in_flight, 0.0, "never negative")


func test_first_seed_is_one_early_seed() -> void:
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/plants.json"))
	var fs: Dictionary = f["first_seed"]
	assert_eq(int(fs["seeds_given"]), 1, "one special Maker seed")
	assert_lte(int(fs["hexes_needed"]), 10, "found around minute 10-15")
	var hl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/hex_levels.json"))
	var planted: Dictionary = hl["levels"][2]["reward"]
	assert_lte(int(planted.get("seeds", 0)), 1, "planting a hex must not refund its own seeds")


func test_seed_finds_locked_until_tin_then_rate_limited() -> void:
	var had: Variant = GameState.flags.get("seeds_unlocked", null)
	var sf := SeedFinds.new()
	add_child_autofree(sf)
	GameState.flags["seeds_unlocked"] = false
	assert_eq(sf.chance_for("metal"), 0.0, "no finds before the seed tin")
	GameState.flags["seeds_unlocked"] = true
	assert_gt(sf.chance_for("metal"), 0.0)
	assert_gt(sf.chance_for("paper"), sf.chance_for("metal"), "organic junk likelier")
	assert_lt(sf.chance_for("paper"), 0.05, "rare")
	sf._cooldown = 10.0
	assert_eq(sf.chance_for("paper"), 0.0, "cooldown between finds")
	if had == null:
		GameState.flags.erase("seeds_unlocked")
	else:
		GameState.flags["seeds_unlocked"] = had
