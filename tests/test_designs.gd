extends GutTest
## Lumi's six designs as sets of found pieces (systems/designs.gd, data/designs.json,
## PatchModel.VARIANTS): no unlock from a counter, and the set's small bonus only while every
## piece of the set is worn.

var _flags: Dictionary
var _stats: Dictionary
var _global: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_global = GameState.global.duplicate(true)
	GameState.flags = {}
	GameState.stats = {}
	GameState.global = {}
	Looks.dev_all = false


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.global = _global


## Finds every piece of a design (no event) and wears the whole set.
func _wear_whole(design: String) -> void:
	for piece: String in Looks.set_ids(design):
		Looks.grant(piece, "", true)
	assert_true(LumiStyle.wear_set(design), "%s: the whole set is worn" % design)


func test_six_designs_match_the_model() -> void:
	var ids: Array[String] = Designs.ids()
	assert_eq(ids, ["aurora", "bolt", "sprout", "pixel", "nova", "patch"] as Array[String])
	for id: String in ids:
		assert_true(PatchModel.VARIANTS.has(id), id)
		var d: Dictionary = Designs.def(id)
		assert_ne(str(d.get("tagline", "")), "", id)
		assert_ne(str(d.get("buff", {}).get("text", "")), "", id)
		var amt: float = float(d["buff"]["amount"])
		assert_true(amt > 0.0 and amt <= 0.1, "%s bonus is slight (%.2f)" % [id, amt])
		assert_false(d.has("unlock"), "%s opens from no counter" % id)
		assert_false(Looks.set_ids(id).is_empty(), "%s is a set of pieces" % id)


func test_a_new_game_wears_aurora_and_holds_no_other_design() -> void:
	assert_eq(Designs.current(), "aurora")
	assert_eq(Designs.worn_set(), "aurora")
	assert_true(Designs.is_collected("aurora"))
	for id: String in ["bolt", "sprout", "pixel", "nova", "patch"]:
		assert_false(Designs.is_collected(id), id)
		assert_false(Designs.has_base(id), id)
		assert_false(Designs.select(id), "%s cannot be worn before its paint is found" % id)
		assert_false(LumiStyle.wear_set(id), id)
	assert_eq(Designs.current(), "aurora")
	GameState.flags["patch_skin"] = "nonsense"
	assert_eq(Designs.current(), "aurora")


func test_no_counter_level_or_price_opens_a_design() -> void:
	GameState.stats = {"cubes_made": 100000, "plants_bloomed": 100000, "trinkets_found": 100000, "contracts_done": 100000}
	GameState.flags["lumi"] = {"level": 99, "xp": 0, "total": 0}
	for rid: String in Economy.robot_order:
		GameState.flags["tier_" + rid] = 9
	GameState.currencies["parts"] = BigNum.from_float(1.0e9)
	GameState.currencies["cubes"] = BigNum.from_float(1.0e9)
	for id: String in ["bolt", "sprout", "pixel", "nova", "patch"]:
		assert_false(Designs.is_collected(id), id)
		assert_false(Designs.has_base(id), id)
	assert_eq(Looks.found_count(), 0, "nothing is found by counting")
	GameState.currencies["parts"] = BigNum.zero()
	GameState.currencies["cubes"] = BigNum.zero()


func test_the_bonus_needs_every_piece_of_the_set_worn() -> void:
	assert_almost_eq(Designs.mult("detector_range"), 1.08, 0.0001, "Aurora's set: detector range")
	assert_almost_eq(Designs.mult("plant_growth"), 1.0, 0.0001)
	_wear_whole("sprout")
	assert_eq(Designs.worn_set(), "sprout")
	assert_almost_eq(Designs.mult("plant_growth"), 1.08, 0.0001)
	assert_almost_eq(Designs.mult("detector_range"), 1.0, 0.0001)
	assert_almost_eq(Economy.stat("plant_growth"), Economy.base_stat("plant_growth") * 1.08, 0.0001)
	assert_eq(Designs.breakdown("plant_growth").size(), 1)
	# One piece swapped for another: a mixed look, no bonus at all.
	var mixed: Dictionary = LumiStyle.current()
	LumiStyle.wear_piece(mixed, "head_fin")
	LumiStyle.set_current(mixed)
	assert_eq(Designs.worn_set(), "", "a mixed look is no set")
	assert_almost_eq(Designs.mult("plant_growth"), 1.0, 0.0001)
	assert_almost_eq(Designs.mult("detector_range"), 1.0, 0.0001)
	assert_eq(Designs.breakdown("plant_growth").size(), 0)
	_wear_whole("patch")
	assert_almost_eq(Designs.mult("scoopie.work_rate"), 1.06, 0.0001, "every robot type")
	assert_almost_eq(Designs.mult("work_rate"), 1.0, 0.0001)


func test_looks_only_turns_the_bonus_off() -> void:
	_wear_whole("nova")
	var d: float = Research.duration("salvage_logic")
	Designs.set_looks_only(true)
	assert_almost_eq(Research.duration("salvage_logic"), d * 1.08, 0.01, "looks only: no research bonus")
	assert_almost_eq(Designs.mult("research_speed"), 1.0, 0.0001)


func test_streak_grace_bonus() -> void:
	var s := Streak.new({"grace_s": 2.0, "drain_per_s": 10.0})
	LumiStyle.set_current(LumiStyle.preset("aurora"))
	s.add_scoop(10.0)
	s.tick(2.1)
	assert_true(s.points < 10.0, "plain grace has run out")
	_wear_whole("pixel")
	var s2 := Streak.new({"grace_s": 2.0, "drain_per_s": 10.0})
	s2.add_scoop(10.0)
	s2.tick(2.1)
	assert_almost_eq(s2.points, 10.0, 0.0001, "Pixel holds the streak a little longer")


func test_every_design_builds_with_its_add_ons() -> void:
	for id: String in Designs.ids():
		var m := PatchModel.new()
		m.preview_variant = id
		add_child_autofree(m)
		assert_eq(m.variant, id)
		for a: String in PatchModel.VARIANTS[id].get("acc", []):
			if a.begins_with("acc_") or a == "antenna":
				assert_true(PatchModel._parts.has(a), "%s: part %s in the glb" % [id, a])
		m._process(0.1)
		m._idle_t = 10.0
		m._process(0.5)
	assert_true(PatchModel._parts.has("acc_icon_leaf") and PatchModel._parts.has("acc_icon_cross"))
