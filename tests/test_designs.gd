extends GutTest
## Lumi's unlockable designs (systems/designs.gd, data/designs.json, PatchModel.VARIANTS).

var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	GameState.flags = {}
	GameState.stats = {}
	Designs.pending_toasts.clear()


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	Designs.pending_toasts.clear()


func test_six_designs_match_the_model() -> void:
	var ids: Array[String] = Designs.ids()
	assert_eq(ids, ["aurora", "bolt", "sprout", "pixel", "nova", "patch"] as Array[String])
	for id: String in ids:
		assert_true(PatchModel.VARIANTS.has(id), id)
		var d: Dictionary = Designs.def(id)
		assert_ne(str(d.get("tagline", "")), "", id)
		assert_ne(str(d.get("buff", {}).get("text", "")), "", id)
		var amt: float = float(d["buff"]["amount"])
		assert_true(amt > 0.0 and amt <= 0.1, "%s buff is slight (%.2f)" % [id, amt])
		if id != "aurora":
			assert_false(Designs.conds(id).is_empty(), "%s has an unlock" % id)


func test_default_is_aurora_and_unlocked() -> void:
	assert_eq(Designs.current(), "aurora")
	assert_true(Designs.is_unlocked("aurora"))
	assert_false(Designs.is_unlocked("bolt"))
	assert_false(Designs.select("bolt"), "locked designs can't be worn")
	assert_eq(Designs.current(), "aurora")
	GameState.flags["patch_skin"] = "nonsense"
	assert_eq(Designs.current(), "aurora")


func test_unlock_needs_the_full_hard_target() -> void:
	GameState.stats["cubes_made"] = 320
	assert_almost_eq(Designs.progress("bolt"), 0.8, 0.001)
	assert_eq(Designs.check_unlocks(true), [] as Array[String])
	GameState.stats["cubes_made"] = 400
	assert_eq(Designs.check_unlocks(true), ["bolt"] as Array[String])
	assert_true(Designs.is_unlocked("bolt"))
	assert_eq(Designs.check_unlocks(true), [] as Array[String], "unlocks once")
	GameState.stats["trinkets_found"] = 5
	assert_eq(Designs.check_unlocks(true), [] as Array[String], "a handful of finds is not enough for a rare design")
	GameState.stats["trinkets_found"] = 20
	assert_eq(Designs.check_unlocks(true), ["pixel"] as Array[String])
	assert_true(Designs.select("pixel"))
	assert_eq(Designs.current(), "pixel")


func test_progress_text_and_unlock_text() -> void:
	GameState.stats["cubes_made"] = 12
	assert_eq(Designs.progress_text("bolt"), "12 / 400 bales")
	assert_ne(Designs.unlock_text("sprout"), "")
	assert_eq(Designs.progress_text("aurora"), "")


func test_buff_applies_only_to_worn_design_and_respects_looks_only() -> void:
	assert_almost_eq(Designs.mult("detector_range"), 1.08, 0.0001, "Aurora: detector range")
	assert_almost_eq(Designs.mult("plant_growth"), 1.0, 0.0001)
	GameState.flags["skins_unlocked"] = ["aurora", "sprout", "patch", "nova"]
	Designs.select("sprout")
	assert_almost_eq(Designs.mult("plant_growth"), 1.08, 0.0001)
	assert_almost_eq(Designs.mult("detector_range"), 1.0, 0.0001)
	assert_almost_eq(Economy.stat("plant_growth"), Economy.base_stat("plant_growth") * 1.08, 0.0001)
	Designs.select("patch")
	assert_almost_eq(Designs.mult("scoopie.work_rate"), 1.06, 0.0001, "every robot type")
	assert_almost_eq(Designs.mult("work_rate"), 1.0, 0.0001)
	Designs.select("nova")
	var d: float = Research.duration("salvage_logic")
	Designs.set_looks_only(true)
	assert_almost_eq(Research.duration("salvage_logic"), d * 1.08, 0.01, "looks only: no research bonus")
	assert_almost_eq(Designs.mult("research_speed"), 1.0, 0.0001)


func test_streak_grace_buff() -> void:
	var s := Streak.new({"grace_s": 2.0, "drain_per_s": 10.0})
	s.add_scoop(10.0)
	s.tick(2.1)
	assert_true(s.points < 10.0, "plain grace has run out")
	GameState.flags["skins_unlocked"] = ["aurora", "pixel"]
	Designs.select("pixel")
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
