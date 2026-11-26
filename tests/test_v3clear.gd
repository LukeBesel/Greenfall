extends GutTest
## [v3clear] Owner item 41: Verdance clarity pass (bin in its bay, situation hints, plain texts).


func test_bin_body_stands_on_its_bay_anchor() -> void:
	# The start yard's depot anchor and the "bin" anchor the marked bay is drawn round
	# (planet/sites/verdance_site.gd START_YARD_ANCHORS): the bin body must stand on the latter.
	var root := Node3D.new()
	add_child_autofree(root)
	var sp := SitePrefab.new()
	root.add_child(sp)
	var dep_a: Array = VerdanceSite.START_YARD_ANCHORS["depot"]
	var bin_a: Array = VerdanceSite.START_YARD_ANCHORS["bin"]
	sp.set_anchor("depot", dep_a[0], dep_a[1])
	sp.set_anchor("bin", bin_a[0], bin_a[1])
	var d := Depot.new()
	root.add_child(d)
	d.transform = sp.anchor_local("depot")
	var before: float = d.bin_world().distance_to(bin_a[0])
	d.seat_bin(sp)
	assert_gt(before, 3.0, "the old chute stood ~4.3 m off its anchor")
	assert_lt(d.bin_world().distance_to(bin_a[0]), 0.05, "the bin body stands on the bin anchor")
	assert_lt(d.mouth_world().distance_to(bin_a[0]), 2.0, "its mouth is right above it")


func test_short_price_says_what_is_missing_and_how() -> void:
	var had: BigNum = GameState.get_currency("cubes")
	GameState.currencies["cubes"] = BigNum.from_float(10.0)
	var t: String = ListDetail.short_text({"cubes": 50.0})
	assert_true(t.contains("40"), "the missing amount: %s" % t)
	assert_true(t.to_lower().contains("trash"), "and how to get it: %s" % t)
	assert_eq(ListDetail.short_text({"cubes": 1.0}), "", "nothing missing: no line")
	GameState.currencies["cubes"] = had


func test_card_shows_the_situation_hint_under_the_why() -> void:  # [v6story] the reason stays (owner item 60)
	var o := Objectives.new()
	o.chain = [{"id": "dump3", "text": "Fill the trash bin 3 times", "desc": "Hold {scoop} to pick up trash.", "type": "stat", "key": "junk_dumps", "target": 3}]
	o.revealed = true
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	card.objectives = o
	card.refresh(false)
	card._process(0.1)
	assert_false(card._why.text.contains("{"), "key glyphs filled in: %s" % card._why.text)
	o.situation = "Your chest is full. Bring it to the bin."
	card._process(0.1)
	assert_eq(card._hint.text, o.situation)
	assert_true(card._hint.visible)
	assert_eq(card._hint.get_theme_color("font_color"), ObjectiveCard.HINT)
	assert_true(card._why.text.begins_with("Hold"), "the reason stays on the card")
	o.situation = ""
	card._process(ObjectiveCard.HINT_HOLD_S)  # [v9d] a hint holds a moment, then goes
	card._process(2.0)
	assert_false(card._hint.visible)
	assert_true(card._why.text.begins_with("Hold"))
	o.free()


func test_early_texts_are_short_and_verb_first() -> void:
	var cfg: Dictionary = Economy.read_json("res://data/objectives.json")
	for d: Dictionary in cfg["objectives"]:
		assert_lt(str(d["text"]).split(" ").size(), 8, "short title: %s" % d["text"])
	for s: Dictionary in Tutorial.STEPS:
		assert_false(str(s["text"]).to_lower().contains("junk"), "plain words: %s" % s["text"])
