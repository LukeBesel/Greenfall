extends GutTest
## [style] Character Builder looks (systems/lumi_style.gd, data/style_parts.json): serialization,
## unlock gating, preset equivalence (each design's preset style reproduces PatchModel.VARIANTS)
## and the applicator on a real PatchModel.

var _flags: Dictionary
var _stats: Dictionary
var _parts_bal: BigNum


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_parts_bal = GameState.get_currency("parts")
	GameState.flags = {}
	GameState.stats = {}
	LumiStyle.dev_all = false


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies["parts"] = _parts_bal
	LumiStyle.dev_all = false


func _custom() -> Dictionary:
	var s: Dictionary = LumiStyle.preset("aurora")
	LumiStyle.set_value(s, "paint", Color("#3d63ff"))
	LumiStyle.set_value(s, "laser", Color("#ff5480"))
	LumiStyle.set_value(s, "hover", Color("#85ff5c"))
	LumiStyle.set_value(s, "eyes", Color("#ffd34d"))
	LumiStyle.set_value(s, "wear", 0.2)
	s["eye_shape"] = "heart"
	s["head"] = "halo"
	s["held"] = "medkit"
	s["companion"] = "drone"
	s["chest"] = "heart"
	return s


func test_data_is_complete() -> void:
	for slot: String in LumiStyle.PART_SLOTS:
		assert_false(LumiStyle.options(slot).is_empty(), slot)
		assert_false(LumiStyle.slot_def(slot).is_empty(), "%s listed in slots" % slot)
	for slot: String in LumiStyle.COLOR_SLOTS:
		assert_eq(str(LumiStyle.slot_def(slot).get("kind", "")), "color", slot)
	assert_true(LumiStyle.swatches().size() >= 20)
	# Owner's list is all there.
	for pair: Array in [["eye_shape", "crescent"], ["eye_shape", "round"], ["eye_shape", "happy"], ["eye_shape", "bar"], ["eye_shape", "heart"],
			["head", "none"], ["head", "fin"], ["head", "sprout"], ["head", "catears"], ["head", "wings"], ["head", "antenna"], ["head", "halo"],
			["chest", "recycle"], ["chest", "leaf"], ["chest", "cross"], ["chest", "heart"],
			["held", "none"], ["held", "gear"], ["held", "medkit"], ["held", "toolbox"], ["held", "watering_can"],
			["companion", "none"], ["companion", "butterfly"], ["companion", "firefly"], ["companion", "drone"]]:
		assert_false(LumiStyle.option(pair[0], pair[1]).is_empty(), "%s:%s" % pair)
	# Every distinguishing piece of the six designs is its own wearable option (stable ids).
	for pair: Array in [["head", "fin"], ["head", "sprout"], ["head", "wings"], ["head", "catears"],
			["ears", "plain"], ["ears", "heart"], ["ears", "leaf"], ["ears", "nut"], ["ears", "radio"], ["shoulders", "pads"],
			["held", "gear"], ["held", "bottle"], ["held", "holo"], ["held", "toolbox"], ["hip", "none"], ["hip", "satchel"],
			["pattern", "plain"], ["pattern", "stripes"], ["pattern", "moss"], ["pattern", "seams"], ["pattern", "twotone"]]:
		assert_false(LumiStyle.option(pair[0], pair[1]).is_empty(), "%s:%s" % pair)
	# Every unlock names something real.
	for slot: String in LumiStyle.PART_SLOTS:
		for o: Dictionary in LumiStyle.options(slot):
			_check_unlock(o.get("unlock", {}), "%s:%s" % [slot, o["id"]])
	for s: Dictionary in LumiStyle.swatches():
		_check_unlock(s.get("unlock", {}), "swatch " + str(s["id"]))
		assert_true(Color.html_is_valid(str(s["color"])), str(s["id"]))


func _check_unlock(u: Dictionary, what: String) -> void:
	if u.has("design"):
		assert_false(Designs.def(str(u["design"])).is_empty(), what)
	if u.has("achievement"):
		assert_false(Achievements.def(str(u["achievement"])).is_empty(), what)
	if u.has("cost"):
		for k: String in u["cost"]:
			assert_true(k in ["cubes", "parts", "seeds"], "%s costs only cubes, parts or seeds" % what)
	if u.has("cond"):
		assert_ne(str(u.get("text", "")), "", what)


func test_serialization_round_trip() -> void:
	var s: Dictionary = _custom()
	var txt: String = JSON.stringify(s)
	var back: Dictionary = LumiStyle.normalize(JSON.parse_string(txt))
	assert_true(LumiStyle.same(s, back), "JSON round trip keeps the look")
	assert_eq(back["head"], "halo")
	assert_almost_eq(LumiStyle.col(back, "laser").r, Color("#ff5480").r, 0.001)
	# Missing / bad values fall back to the preset.
	var bad: Dictionary = LumiStyle.normalize({"preset": "nova", "head": "top_hat", "paint": "nope", "wear": 7.0})
	assert_eq(bad["head"], LumiStyle.preset("nova")["head"])
	assert_true(LumiStyle._close(LumiStyle.col(bad, "paint"), LumiStyle.col(LumiStyle.preset("nova"), "paint")))
	assert_eq(float(bad["wear"]), 1.0)
	assert_true(LumiStyle.same(LumiStyle.normalize(null), LumiStyle.preset("aurora")))
	# Through the save flags.
	GameState.flags["skins_unlocked"] = ["aurora"]
	LumiStyle.set_current(s)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.flags))
	GameState.flags = saved
	assert_true(LumiStyle.same(LumiStyle.current(), s))


func test_unlock_gating() -> void:
	assert_true(LumiStyle.option_unlocked("head", "fin"))
	assert_true(LumiStyle.option_unlocked("eye_shape", "crescent"))
	assert_false(LumiStyle.option_unlocked("eye_shape", "round"), "round eyes come with Lumi Level 3")
	assert_false(LumiStyle.option_unlocked("head", "catears"))
	assert_false(LumiStyle.swatch_unlocked("violet"))
	GameState.flags["skins_unlocked"] = ["aurora", "nova"]
	assert_true(LumiStyle.option_unlocked("head", "catears"), "designs unlock their parts")
	assert_true(LumiStyle.swatch_unlocked("violet"), "and their colours")
	# Condition (Requests) and achievement unlocks.
	assert_false(LumiStyle.option_unlocked("companion", "firefly"))
	GameState.stats["contracts_done"] = 3
	assert_true(LumiStyle.option_unlocked("companion", "firefly"))
	assert_false(LumiStyle.option_unlocked("head", "halo"))
	Achievements.unlocked_map()["restored_1"] = 1.0
	assert_true(LumiStyle.option_unlocked("head", "halo"))
	# Cost unlock: bought once with parts.
	GameState.currencies["parts"] = BigNum.from_float(50.0)
	assert_false(LumiStyle.buy("companion", "drone"), "can't afford 120 parts")
	assert_false(LumiStyle.option_unlocked("companion", "drone"))
	GameState.currencies["parts"] = BigNum.from_float(200.0)
	assert_true(LumiStyle.buy("companion", "drone"))
	assert_almost_eq(GameState.get_currency("parts").to_float(), 80.0, 0.01)
	assert_true(LumiStyle.option_unlocked("companion", "drone"))
	assert_false(LumiStyle.buy("companion", "drone"), "only once")
	assert_false(LumiStyle.buy("head", "fin"), "free parts aren't for sale")
	# Advanced picker gates free colours.
	var s: Dictionary = LumiStyle.preset("aurora")
	LumiStyle.set_value(s, "paint", Color(0.123, 0.456, 0.789))
	assert_false(LumiStyle.allowed(s), "an off-swatch colour needs the advanced picker")
	assert_true(LumiStyle.buy("", "advanced_picker"))
	assert_true(LumiStyle.allowed(s))
	# A locked part makes a look unwearable; random looks only use unlocked things.
	var s2: Dictionary = LumiStyle.preset("aurora")
	s2["held"] = "watering_can"
	assert_false(LumiStyle.allowed(s2))
	var rng := RandomNumberGenerator.new()
	for i: int in 30:
		rng.seed = i
		assert_true(LumiStyle.allowed(LumiStyle.randomized(rng)), "random look %d is wearable" % i)


func test_presets_reproduce_the_designs() -> void:
	for id: String in Designs.ids():
		var v: Dictionary = PatchModel.VARIANTS[id]
		assert_eq(LumiStyle.unmapped_acc(id), [], "%s: every add-on maps to a slot option" % id)
		var p: Dictionary = LumiStyle.preset(id)
		var d: Dictionary = LumiStyle.variant_dict(p, v)
		for k: String in ["paint", "trim", "accent", "glow"]:
			assert_true(LumiStyle._close(d[k], v[k], 0.0002), "%s %s" % [id, k])
		assert_true(LumiStyle._close(d["lamp"], v.get("lamp", v["accent"]), 0.0002), id + " lamp")
		assert_eq(d["icon"], str(v.get("icon", "recycle")), id + " icon")
		assert_almost_eq(float(d["coverage"]), float(v.get("coverage", 0.9)), 0.0002, id)
		assert_almost_eq(float(d["grime"]), float(v.get("grime", 0.6)), 0.0002, id)
		assert_almost_eq(float(d["moss"]), float(v.get("moss", 0.0)), 0.0002, id)
		assert_almost_eq(float(d["stripes"]), float(v.get("stripes", 0.0)), 0.0002, id)
		assert_almost_eq(float(d["metal"]), float(v.get("metal", 0.0)), 0.0002, id)
		assert_almost_eq(float(d["happy"]), 1.0 if float(v.get("happy", 0.5)) >= 0.99 else 0.5, 0.0002, id)
		var want: Array = (v.get("acc", []) as Array).duplicate()
		var got: Array = (d["acc"] as Array).duplicate()
		want.sort()
		got.sort()
		assert_eq(got, want, id + " add-ons")
		# The preset leaves eyes, hover ring and laser on the design glow.
		for slot: String in ["eyes", "hover", "laser"]:
			assert_true(LumiStyle._close(LumiStyle.col(p, slot), v["glow"], 0.0002), "%s %s" % [id, slot])
		assert_true(LumiStyle.is_preset(p))


func test_preset_model_matches_the_design() -> void:
	for id: String in Designs.ids():
		var m := PatchModel.new()
		m.preview_variant = id
		add_child_autofree(m)
		var g: Color = PatchModel.VARIANTS[id]["glow"]
		assert_true(LumiStyle._close(LumiStyle.laser_of(m), g, 0.0002), id + " laser")
		assert_true(LumiStyle._close(m._face_mat.get_shader_parameter("eye_color"), g, 0.0002), id + " eyes")
		assert_true(LumiStyle._close(m._ring_mat.emission, g, 0.0002), id + " hover ring")
		assert_null(m._face_mat.next_pass, id + ": native eyes, no overlay")
		assert_eq(m.find_children("lumi_*", "", true, false).size(), 0, id + ": no extra add-ons")


func test_custom_style_on_a_model() -> void:
	GameState.flags["skins_unlocked"] = ["aurora"]
	var s: Dictionary = _custom()
	var m := PatchModel.new()
	m.set_meta("lumi_style", s)
	add_child_autofree(m)
	assert_not_null(m.get_node_or_null("LumiStyleRig"))
	# One eye path: the face shader draws the builder's shape itself, with no overlay pass.
	assert_null(m._face_mat.next_pass, "no eye overlay")
	assert_eq(int(m._face_mat.get_shader_parameter("eye_shape")), PatchModel.EYE_SHAPES.find("heart"), "heart eyes in the face shader")
	assert_gt(float(m._face_mat.get_shader_parameter("eye_radius")), 0.0, "native eyes shown")
	for n: String in ["lumi_halo", "lumi_medkit", "lumi_drone"]:
		assert_eq(m.find_children(n, "", true, false).size(), 1, n)
	assert_true(LumiStyle._close(LumiStyle.laser_of(m), Color("#ff5480"), 0.002))
	assert_true(LumiStyle._close(m._ring_mat.emission, Color("#85ff5c"), 0.002))
	assert_false(m._icon.visible, "heart replaces the recycle label")
	m._process(0.1)
	m.get_node("LumiStyleRig")._process(0.1)
	# Colour-only edits apply in place; part edits rebuild.
	LumiStyle.set_value(s, "laser", Color("#4de0ff"))
	LumiStyle.apply(m, s)
	assert_true(LumiStyle._close(LumiStyle.laser_of(m), Color("#4de0ff"), 0.002))
	s["companion"] = "firefly"
	LumiStyle.apply(m, s)
	assert_eq(m.find_children("lumi_firefly", "", true, false).size(), 1)
	assert_eq(m.find_children("lumi_drone", "", true, false).size(), 0)
	# PickupFx reads the laser colour from the model.
	var fx := PickupFx.new()
	fx.model = m
	assert_true(LumiStyle._close(fx._glow(), Color("#4de0ff"), 0.002))
	fx.free()


func test_worn_style_and_bonus() -> void:
	GameState.flags["skins_unlocked"] = ["aurora", "nova"]
	var s: Dictionary = _custom()
	s["bonus"] = "nova"
	LumiStyle.set_current(s)
	assert_eq(Designs.current(), "nova", "the bonus design is worn")
	assert_almost_eq(Designs.mult("research_speed"), 1.08, 0.0001, "and its bonus applies")
	assert_true(LumiStyle.same(LumiStyle.current(), s))
	assert_true(LumiStyle.same(LumiStyle.for_variant("nova"), s))
	assert_true(LumiStyle.same(LumiStyle.for_variant("aurora"), LumiStyle.preset("aurora")))
	Designs.set_looks_only(true)
	assert_eq(Designs.mult("research_speed"), 1.0, "looks only still turns it off")
	Designs.set_looks_only(false)
	# A locked bonus can't be picked.
	s["bonus"] = "bolt"
	LumiStyle.set_current(s)
	assert_eq(Designs.current(), "nova")
	# Wearing a design from the picker = its preset.
	assert_true(LumiStyle.wear_preset("aurora"))
	assert_true(LumiStyle.is_preset(LumiStyle.current()))
	assert_false(LumiStyle.wear_preset("bolt"))
	# Title screen reads the save's flags.
	var fl: Dictionary = {"lumi_style": s.duplicate(true), "patch_skin": "nova"}
	(fl["lumi_style"] as Dictionary)["bonus"] = "nova"
	assert_eq(LumiStyle.from_save_flags(fl, "nova")["head"], "halo")
	assert_eq(LumiStyle.from_save_flags(fl, "aurora")["head"], "fin")


func test_saved_looks() -> void:
	assert_eq(LumiStyle.looks().size(), LumiStyle.MAX_LOOKS)
	for i: int in LumiStyle.MAX_LOOKS:
		assert_true(LumiStyle.look(i).is_empty())
	var s: Dictionary = _custom()
	assert_true(LumiStyle.save_look(2, s, "Party"))
	assert_false(LumiStyle.save_look(5, s), "only five")
	assert_eq(LumiStyle.look(2)["name"], "Party")
	assert_true(LumiStyle.same(LumiStyle.look(2), s))
	LumiStyle.delete_look(2)
	assert_true(LumiStyle.look(2).is_empty())


func test_builder_opens_and_wears() -> void:
	GameState.flags["skins_unlocked"] = ["aurora", "pixel"]
	var b: LumiBuilder = LumiBuilder.open(null, self)
	await wait_frames(2)
	for slot: String in b._order:
		b._select(slot, false)
	b._select("head", false)
	b._set_value("head", "wings")
	b._randomize()
	b._set_value("laser", Color("#ff5480"))
	b._process(0.2)
	var want: Dictionary = b.edit.duplicate(true)
	b._done()
	await wait_frames(1)
	assert_true(LumiStyle.same(LumiStyle.current(), want))


func test_builder_embeds_as_a_control() -> void:
	# The Locker hosts it: LumiBuilder.new() + world, added to any container.
	GameState.flags["skins_unlocked"] = ["aurora", "pixel"]
	var box := VBoxContainer.new()
	box.size = Vector2(1280, 720)
	add_child_autofree(box)
	var b := LumiBuilder.new()
	box.add_child(b)
	await wait_frames(2)
	assert_false(b.standalone)
	b._set_value("head", "wings")
	b._process(0.2)
	var got: Array = []
	b.worn.connect(func() -> void: got.append(1))
	b._done()
	assert_eq(got.size(), 1, "worn signal")
	assert_true(is_instance_valid(b), "embedded builder stays open")
	assert_eq(LumiStyle.current()["head"], "wings")


func test_cosmetic_targets_registry() -> void:
	assert_true(CosmeticTargets.has("lumi"))
	assert_eq(CosmeticTargets.all()[0]["id"], "lumi")
	var ed: Control = CosmeticTargets.make_editor("lumi", null)
	assert_true(ed is LumiBuilder)
	ed.free()
	var met: Array = [false]
	CosmeticTargets.unregister("test_buddy")
	var n0: int = CosmeticTargets.all().size()  # [buddy] Glim registers himself when a district loads
	assert_false(CosmeticTargets.register("bad", {"name": "Bad"}), "needs an editor")
	assert_true(CosmeticTargets.register("test_buddy", {"name": "Buddy", "order": 20,
		"editor": func(_w: Node) -> Control: return Control.new(),
		"unlocked": func() -> bool: return met[0], "hint": "Meet the light-bot"}))
	assert_eq(CosmeticTargets.all().size(), n0 + 1)
	assert_eq(CosmeticTargets.display_name("test_buddy"), "???", "locked target is ???")
	assert_null(CosmeticTargets.make_editor("test_buddy", null))
	met[0] = true
	assert_eq(CosmeticTargets.display_name("test_buddy"), "Buddy")
	var c: Control = CosmeticTargets.make_editor("test_buddy", null)
	assert_not_null(c)
	c.free()
	CosmeticTargets.unregister("test_buddy")
	assert_false(CosmeticTargets.has("test_buddy"))


func test_locked_design_is_a_silhouette() -> void:
	var p := DesignPreview.new(Vector2i(64, 64))
	add_child_autofree(p)
	p.show_design("nova", true)
	var m: PatchModel = p._model
	assert_true(m.has_meta("lumi_silhouette"))
	for n: Node in m.find_children("*", "MeshInstance3D", true, false):
		assert_not_null((n as MeshInstance3D).material_override, "every mesh is flat")
	for n: Node in m.find_children("*", "Light3D", true, false):
		assert_false((n as Light3D).visible)
	p.show_design("aurora", false)
	assert_false(p._model.has_meta("lumi_silhouette"), "a rebuild clears it")
