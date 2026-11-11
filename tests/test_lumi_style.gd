extends GutTest
## Lumi's look (systems/lumi_style.gd, data/style_parts.json): serialization, what may be worn
## (found pieces only), preset equivalence (each design's preset style reproduces
## PatchModel.VARIANTS), the applicator on a real PatchModel, and the Locker's page for Lumi.

const CUSTOM_PIECES: Array[String] = ["tin_royal", "eyes_heart", "head_halo", "held_medkit", "companion_drone", "chest_heart", "companion_firefly"]

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
	Looks.dev_all = false


func _find(pieces: Array[String]) -> void:
	for id: String in pieces:
		Looks.grant(id, "", true)


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
	_find(CUSTOM_PIECES)
	GameState.flags["lumi_style"] = s.duplicate(true)  # an old save's mixed colours stay wearable
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
	for s: Dictionary in LumiStyle.swatches():
		assert_true(Color.html_is_valid(str(s["color"])), str(s["id"]))


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
	LumiStyle.set_current(s)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(GameState.flags))
	GameState.flags = saved
	assert_true(LumiStyle.same(LumiStyle.current(), s))


func test_only_found_pieces_can_be_worn() -> void:
	assert_true(LumiStyle.allowed(LumiStyle.preset("aurora")), "the starting look is wearable")
	for piece: String in Looks.ids():
		if Looks.is_starter(piece):
			continue
		var s: Dictionary = LumiStyle.preset("aurora")
		LumiStyle.wear_piece(s, piece)
		assert_eq(LumiStyle.piece_in(s, Looks.slot_of(piece)), piece, "%s reads back from its slot" % piece)
		assert_false(LumiStyle.allowed(s), "%s cannot be worn before it is found" % piece)
		Looks.grant(piece, "", true)
		assert_true(LumiStyle.allowed(s), "%s can be worn once found" % piece)
		Looks.found().clear()
	# A colour no piece stands for cannot be put on.
	var odd: Dictionary = LumiStyle.preset("aurora")
	LumiStyle.set_value(odd, "paint", Color(0.123, 0.456, 0.789))
	assert_eq(LumiStyle.piece_in(odd, "paint"), "")
	assert_false(LumiStyle.allowed(odd))
	# Random looks use found pieces only.
	_find(["tin_sky", "chip_mint", "head_halo"])
	var rng := RandomNumberGenerator.new()
	for i: int in 30:
		rng.seed = i
		assert_true(LumiStyle.allowed(LumiStyle.randomized(rng)), "random look %d is wearable" % i)


func test_a_slot_can_be_emptied_only_where_empty_is_not_a_piece() -> void:
	for slot: String in ["pattern", "head", "ears", "shoulders", "held", "hip", "companion"]:
		assert_true(LumiStyle.can_clear(slot), slot)
	for slot: String in ["paint", "glow", "eye_shape", "chest"]:
		assert_false(LumiStyle.can_clear(slot), slot)
	var s: Dictionary = LumiStyle.preset("aurora")
	LumiStyle.clear_slot(s, "head")
	assert_eq(s["head"], "none")
	assert_eq(LumiStyle.piece_in(s, "head"), "")
	assert_true(LumiStyle.allowed(s), "an empty slot is always wearable")


func test_every_set_piece_reads_back_from_its_design() -> void:
	for id: String in Designs.ids():
		var p: Dictionary = LumiStyle.preset(id)
		for piece: String in Looks.set_ids(id):
			assert_eq(LumiStyle.piece_in(p, Looks.slot_of(piece)), piece, "%s wears %s" % [id, piece])
		assert_eq(LumiStyle.worn_set(p), id, "the design's own look is its complete set")
		var built: Dictionary = LumiStyle.with_set(LumiStyle.preset("aurora"), id)
		assert_eq(LumiStyle.worn_set(built), id, "%s put on piece by piece is the set" % id)
		for k: String in LumiStyle.BODY_SLOTS + LumiStyle.GLOW_SLOTS:
			assert_true(LumiStyle._close(LumiStyle.col(built, k), LumiStyle.col(p, k)), "%s %s" % [id, k])


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


func test_worn_style_and_its_base_design() -> void:
	_find(Looks.set_ids("nova"))
	_find(CUSTOM_PIECES)
	var s: Dictionary = LumiStyle.with_set(LumiStyle.preset("aurora"), "nova")
	LumiStyle.wear_piece(s, "head_halo")
	var changes: Array = []
	var on_change := func() -> void: changes.append(1)
	EventBus.look_changed.connect(on_change)
	LumiStyle.set_current(s)
	EventBus.look_changed.disconnect(on_change)
	assert_eq(changes.size(), 1, "look_changed fires once")
	assert_eq(Designs.current(), "nova", "the paint set's design is the base")
	assert_eq(Designs.worn_set(), "", "one piece swapped: a mixed look")
	assert_true(LumiStyle.same(LumiStyle.current(), s))
	assert_true(LumiStyle.same(LumiStyle.for_variant("nova"), s))
	assert_true(LumiStyle.same(LumiStyle.for_variant("aurora"), LumiStyle.preset("aurora")))
	# A paint set that is not found cannot become the base.
	var b: Dictionary = LumiStyle.preset("bolt")
	LumiStyle.set_current(b)
	assert_eq(Designs.current(), "nova")
	assert_true(LumiStyle.wear_set("aurora"))
	assert_eq(Designs.worn_set(), "aurora")
	assert_false(LumiStyle.wear_set("bolt"))
	# Title screen reads the save's flags.
	var fl: Dictionary = {"lumi_style": s.duplicate(true), "patch_skin": "nova"}
	assert_eq(LumiStyle.from_save_flags(fl, "nova")["head"], "halo")
	assert_eq(LumiStyle.from_save_flags(fl, "aurora")["head"], "fin")


func test_three_saved_looks() -> void:
	assert_eq(Looks.preset_count(), 3)
	assert_eq(LumiStyle.looks().size(), 3)
	for i: int in 3:
		assert_true(LumiStyle.look(i).is_empty())
	var s: Dictionary = _custom()
	assert_true(LumiStyle.save_look(2, s, "Party"))
	assert_false(LumiStyle.save_look(3, s), "only three")
	assert_eq(LumiStyle.look(2)["name"], "Party")
	assert_true(LumiStyle.same(LumiStyle.look(2), s))
	LumiStyle.delete_look(2)
	assert_true(LumiStyle.look(2).is_empty())
	# A save from when there were five keeps the extra ones it filled, until they are cleared.
	GameState.flags["lumi_looks"] = [{}, {}, {}, {}, s.duplicate(true)]
	assert_eq(LumiStyle.looks().size(), 5)
	LumiStyle.delete_look(4)
	assert_eq(LumiStyle.looks().size(), 3)


func test_the_locker_page_lists_found_pieces_first_and_unfound_as_hints() -> void:
	_find(["tin_sky"])
	var b := LumiBuilder.new()
	add_child_autofree(b)
	await wait_frames(2)
	assert_eq(b.shown_slot(), "paint", "opens on the newest find's slot")
	var rows: Array = b._list.get_children().filter(func(n: Node) -> bool: return n is PieceRow)
	var seen_unfound: bool = false
	for r: PieceRow in rows:
		if not r.found:
			seen_unfound = true
		else:
			assert_false(seen_unfound, "found pieces come before unfound ones (%s)" % r.piece)
	var found_ids: Array = rows.filter(func(r: PieceRow) -> bool: return r.found).map(func(r: PieceRow) -> String: return r.piece)
	assert_eq(found_ids, ["paint_aurora", "tin_sky"])
	var unfound: Array[String] = b.unfound_here()
	assert_has(unfound, "paint_sprout", "this planet's unfound paint shows as a silhouette")
	assert_does_not_have(unfound, "paint_bolt", "other worlds' pieces are not listed")
	for r: PieceRow in rows:
		if r.found:
			continue
		var texts: Array = r.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
		assert_has(texts, "???", "%s is named ???" % r.piece)
		assert_false(texts.any(func(t: String) -> bool: return t.to_lower() == Looks.name_of(r.piece).to_lower()), "its name stays hidden")
		assert_has(texts, b.hint_of(r.piece), "with its one hint line")
		assert_ne(b.hint_of(r.piece), "")
		var before: Dictionary = b.edit.duplicate(true)
		r.pressed.emit()
		assert_true(LumiStyle.same(b.edit, before), "an unfound piece cannot be put on")


func test_the_locker_page_wears_a_found_piece() -> void:
	_find(["tin_sky", "head_halo"])
	var b := LumiBuilder.new()
	add_child_autofree(b)
	await wait_frames(2)
	for slot: String in b._order:
		b.select_slot(slot, false)
	b.select_slot("head", false)
	b._wear_piece("head_halo")
	assert_eq(b.edit["head"], "halo")
	assert_eq(LumiStyle.current()["head"], "fin", "nothing is worn until Wear look")
	assert_string_contains(b._status.text.to_lower(), "not worn")
	assert_string_contains(b._set_line.text.to_lower(), "mixed", "a mixed look says so")
	var got: Array = []
	b.worn.connect(func() -> void: got.append(1))
	assert_true(b.wear())
	assert_eq(got.size(), 1, "worn signal")
	assert_eq(LumiStyle.current()["head"], "halo")
	assert_eq(int(GameState.stats.get(LumiBuilder.WORN_STAT, 0)), 1)
	# Saved looks: three slots, each loads back.
	b.select_slot(LumiBuilder.SAVED, false)
	assert_eq(b._list.find_children("*", "HBoxContainer", false, false).size(), 3, "three saved looks")
	b._save_look(1)
	b._wear_piece("head_fin")
	b._load_look(1)
	assert_eq(b.edit["head"], "halo")
	# A piece that is not found is refused even if asked for directly.
	b._wear_piece("head_catears")
	assert_eq(b.edit["head"], "halo")


func test_a_complete_set_shows_its_name_and_bonus() -> void:
	_find(Looks.set_ids("sprout"))
	var b := LumiBuilder.new()
	add_child_autofree(b)
	await wait_frames(2)
	b.select_slot(LumiBuilder.SETS, false)
	b._wear_set("sprout")
	assert_string_contains(b._set_line.text, "SPROUT")
	assert_string_contains(b._set_line.text.to_lower(), Designs.buff_text("sprout").to_lower())
	b._wear_piece("head_fin")
	assert_string_contains(b._set_line.text.to_lower(), "mixed")
	b._wear_set("bolt")
	assert_eq(LumiStyle.worn_set(b.edit), "", "a set that is not collected cannot be put on")


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
