extends GutTest
## [v10ui] Owner playtest 3, items 89, 93, 95, 96, 109:
##   - Lumi's eyes rest on one shape (never the arc drawn over the disc),
##   - the goal card never cuts a line: every step's text, in every language, wraps and fits,
##   - a balance reads the same on the HUD, the card and the panels (one formatter, rounded down),
##   - a new install starts on High; a saved choice is kept,
##   - the map's progress card: whole-number %, areas done, one row per base area.

const LOCALES: Array[String] = ["en", "de", "fr", "es", "pt_BR", "zh_CN", "ja", "pseudo"]
## The smallest logical screen: 720 px tall at the largest interface scale (150%).
const MIN_SCREEN_H: float = 720.0 / 1.5

var _locale: String
var _cubes: BigNum
var _quality: int


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	_cubes = GameState.get_currency("cubes")
	_quality = Settings.quality


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	GameState.currencies["cubes"] = _cubes
	Settings.quality = _quality


# --- 89: the eyes ---------------------------------------------------------------------------

func test_eyes_rest_on_one_shape_for_every_mood() -> void:
	var m := PatchModel.new()
	add_child_autofree(m)
	for k: int in 21:
		var mood: float = float(k) / 20.0
		m.set_happy(mood)
		for f: int in 40:
			m._process(0.05)
		m._eye_flash = 0.0
		m._process(0.05)
		var h: float = float(m._face_mat.get_shader_parameter("happy"))
		assert_true(is_equal_approx(h, 0.0) or is_equal_approx(h, 1.0), "mood %.2f rests on round eyes or arcs, not a blend (%.2f)" % [mood, h])
		assert_eq(h >= 0.5, mood >= PatchModel.HAPPY_ARCS_FROM, "mood %.2f: arcs only from %.2f" % [mood, PatchModel.HAPPY_ARCS_FROM])


func test_face_shader_never_mixes_the_two_eye_shapes() -> void:
	var src: String = (load("res://art/shaders/bot_face.gdshader") as Shader).code
	assert_false(src.contains("mix(core, arc, happy)"), "no cross-fade of the disc and the arc")
	assert_true(src.contains("s_open") and src.contains("a_open"), "the round eye shuts before the arc opens")


func test_title_lumi_has_the_round_eyes() -> void:
	var src: String = (load("res://ui/main_menu.gd") as GDScript).source_code
	var re := RegEx.create_from_string("_model\\.set_happy\\(([0-9.]+)\\)")
	var hit: RegExMatch = re.search(src)
	assert_not_null(hit, "the title sets Lumi's mood")
	if hit:
		assert_lt(hit.get_string(1).to_float(), PatchModel.HAPPY_ARCS_FROM, "the title shows the eyes Lumi has in play")


# --- 93: the card never cuts a line ------------------------------------------------------------

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Every text the card's title can show: [source id, msgid].
func _title_texts() -> Array:
	var out: Array = []
	for d: Dictionary in _json("res://data/objectives.json")["objectives"]:
		out.append(["objective %s" % d["id"], str(d.get("text", ""))])
		if d.has("short"):
			out.append(["objective %s short" % d["id"], str(d["short"])])
	for d: Dictionary in _json("res://data/goals.json")["goals"]:
		out.append(["goal %s" % d["id"], str(d.get("text", ""))])
		if d.has("short"):
			out.append(["goal %s short" % d["id"], str(d["short"])])
	for s: Dictionary in Tutorial.STEPS:
		out.append(["checklist %s" % s["id"], str(s["text"])])
	out.append(["checklist done", Tutorial.DONE_TEXT])
	out.append(["first seed: water", "Press  {tool_water}  for the watering can, then hold  {scoop}  to water the seed"])
	out.append(["first seed: plant", "Press  {tool_plant}  for the seed. Then hold  {scoop}  on a greenhouse bed"])
	return out


func _small_texts() -> Array:
	var out: Array = []
	for d: Dictionary in _json("res://data/objectives.json")["objectives"]:
		for k: String in ["why", "hint"]:
			if d.has(k):
				out.append(["objective %s %s" % [d["id"], k], str(d[k])])
	out.append(["hint", "Too heavy. Upgrade Lift at the bench."])
	return out


func _shown(msgid: String) -> String:
	# As ui/goals_panel.gd hands a checklist line to the card: glyphs in, BBCode out.
	return ChecklistCard._strip_bb(Tutorial.glyphs_bb(TranslationServer.translate(msgid))).strip_edges().replace("  ", " ")


func _assert_never_cuts(l: Label, what: String) -> void:
	assert_eq(l.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "%s: no ellipsis" % what)
	assert_eq(l.max_lines_visible, -1, "%s: no line limit" % what)
	assert_false(l.clip_text, "%s: not clipped" % what)
	assert_ne(l.autowrap_mode, TextServer.AUTOWRAP_OFF, "%s: wraps" % what)


func test_card_labels_wrap_and_never_trim() -> void:
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	_assert_never_cuts(card._title, "title")
	_assert_never_cuts(card._hint, "hint")
	_assert_never_cuts(card._why, "why")


func test_every_step_text_shows_in_full_in_every_language() -> void:
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	card.visible = true
	card._hint_row.visible = false
	var titles: Array = _title_texts()
	var smalls: Array = _small_texts()
	assert_gt(titles.size(), 150, "objectives, goals and checklist steps found")
	var bad: PackedStringArray = []
	var tallest: float = 0.0
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		for pair: Array in titles + smalls:
			var small: bool = pair in smalls
			var text: String = _shown(str(pair[1]))
			card.set_title(text if not small else "Clean 10 hexes")
			card._why.text = text if small else ""
			card._why.visible = small
			var l: Label = card._why if small else card._title
			await get_tree().process_frame
			await get_tree().process_frame
			var lines: int = l.get_line_count()
			if l.get_visible_line_count() != lines or text.contains("…") or text.ends_with("..."):
				bad.append("%s [%s]: %d of %d lines show: %s" % [pair[0], loc, l.get_visible_line_count(), lines, text])
			if l.size.y + 0.5 < float(lines) * l.get_line_height():
				bad.append("%s [%s]: %d lines in %.0f px: %s" % [pair[0], loc, lines, l.size.y, text])
			if l.size.x > ObjectiveCard.W:
				bad.append("%s [%s]: wider than the card: %s" % [pair[0], loc, text])
			var h: float = card.get_combined_minimum_size().y
			tallest = maxf(tallest, h)
			if h > MIN_SCREEN_H * 0.5:
				bad.append("%s [%s]: card %.0f px tall, over half the smallest screen: %s" % [pair[0], loc, h, text])
			if not small and loc != "pseudo" and lines > 4:
				bad.append("%s [%s]: %d lines, too long to read at a glance: %s" % [pair[0], loc, lines, text])
	gut.p("tallest card %.0f px of %.0f" % [tallest, MIN_SCREEN_H])
	assert_eq(bad.size(), 0, "card text cut or too long:\n" + "\n".join(bad))


func test_upgrade_step_is_short() -> void:
	var t: String = ""
	for s: Dictionary in Tutorial.STEPS:
		if s["id"] == "upgrade":
			t = str(s["text"])
	assert_eq(t, "Buy an upgrade at the bench")
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	card.visible = true
	card.set_title(t)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lte(card._title.get_line_count(), 2, "fits the card in two lines")
	assert_eq(card._title.get_theme_font_size("font_size"), ObjectiveCard.TITLE_PX, "at the full size")


# --- 95: one number for a balance -----------------------------------------------------------------

func test_a_balance_rounds_down_everywhere() -> void:
	for pair: Array in [[0.0, "0"], [0.4, "0"], [3.5, "3"], [9.99, "9"], [23.6, "23"], [23.999, "23"], [24.0, "24"], [79.99, "79"], [999.6, "999"]]:
		assert_eq(Currencies.have_text(float(pair[0])), str(pair[1]), "%s" % pair[0])
	assert_eq(Currencies.have_text(1234.0), Settings.fmt(BigNum.from_float(1234.0)), "big amounts keep the number format")


func test_hud_and_card_show_the_same_cubes() -> void:
	var hud := CurrencyCluster.new()
	add_child_autofree(hud)
	var chip := ObjectiveCard.CostChip.new("cubes")
	add_child_autofree(chip)
	for v: float in [0.4, 3.5, 12.0, 23.6, 23.4, 79.6, 150.2]:
		GameState.currencies["cubes"] = BigNum.from_float(v)
		for f: int in 80:
			hud._process(0.1)
		chip.set_need(80.0)
		var have: String = chip._l.text.split(" / ")[0]
		var want: String = str(int(floor(minf(v, 80.0))))
		assert_eq(hud._count.text, str(int(floor(v))), "HUD at %.1f" % v)
		assert_eq(have, want, "card at %.1f" % v)
		assert_eq(Currencies.have("cubes"), hud._count.text, "bench and panels at %.1f" % v)
		assert_false(hud._count.text.contains("."), "whole cubes")


func test_card_follows_the_hud_while_coins_fly() -> void:
	var hud := CurrencyCluster.new()
	add_child_autofree(hud)
	var chip := ObjectiveCard.CostChip.new("cubes")
	add_child_autofree(chip)
	GameState.currencies["cubes"] = BigNum.from_float(10.0)
	for f: int in 80:
		hud._process(0.1)
	GameState.currencies["cubes"] = BigNum.from_float(40.0)
	hud.in_flight = 30.0  # the coins are still in the air
	hud._process(0.016)
	chip.set_need(80.0)
	assert_eq(chip._l.text.split(" / ")[0], hud._count.text, "the card does not run ahead of the corner")
	hud.land(30.0)
	for f: int in 80:
		hud._process(0.1)
	chip.set_need(80.0)
	assert_eq(hud._count.text, "40")
	assert_eq(chip._l.text.split(" / ")[0], "40")


func test_balance_screens_use_the_one_formatter() -> void:
	for path: String in ["res://ui/currency_cluster.gd", "res://ui/upgrades_screen.gd", "res://ui/hotbar.gd", "res://ui/builder_panel.gd",
			"res://ui/glim_panel.gd", "res://ui/hub_panel.gd", "res://ui/stations_panel.gd", "res://ui/research_panel.gd", "res://ui/objective_card.gd"]:
		var src: String = (load(path) as GDScript).source_code
		assert_true(src.contains("Currencies.have"), "%s shows a balance through Currencies.have*" % path)
	for path: String in ["res://ui/currency_cluster.gd", "res://ui/hotbar.gd", "res://ui/builder_panel.gd", "res://ui/glim_panel.gd",
			"res://ui/hub_panel.gd", "res://ui/stations_panel.gd", "res://ui/research_panel.gd"]:
		var src2: String = (load(path) as GDScript).source_code
		assert_false(src2.contains("Settings.fmt(GameState.get_currency("), "%s: no second way to print a balance" % path)
		assert_false(src2.contains("round(_shown)"), "%s: no rounding up" % path)


# --- 96: High on a new install ----------------------------------------------------------------------

func _info(adapter: String, type: int, os_name: String = "macOS", extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"adapter": adapter, "vendor": "", "type": type, "os": os_name, "arch": "arm64",
		"screen": Vector2i(1440, 900), "dpi": 96, "steam_deck_env": false, "method": "forward_plus", "ram_gb": 16.0}
	d.merge(extra, true)
	return d


func test_new_install_starts_on_high() -> void:
	var src: String = (load("res://autoload/Settings.gd") as GDScript).source_code
	assert_true(src.contains("var quality: int = Quality.HIGH"), "the default preset is High")
	for info: Dictionary in [_info("Apple M1", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU), _info("Apple M2 Max", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU),
			_info("Intel(R) UHD Graphics 620", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "Windows", {"arch": "x86_64"}),
			_info("NVIDIA GeForce GTX 1050 Ti", RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "Windows", {"arch": "x86_64"})]:
		assert_eq(QualityDetect.first_run_quality(QualityDetect.pick(info)), QualityDetect.HIGH, str(info["adapter"]))


func test_hardware_that_cannot_run_high_keeps_low() -> void:
	var soft: Dictionary = QualityDetect.pick(_info("llvmpipe (LLVM 15.0.7, 256 bits)", RenderingDevice.DEVICE_TYPE_CPU, "Linux", {"arch": "x86_64"}))
	assert_eq(QualityDetect.first_run_quality(soft), QualityDetect.LOW, "software GPU (this box)")
	var compat: Dictionary = QualityDetect.pick(_info("NVIDIA GeForce RTX 4090", RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "Windows", {"method": "gl_compatibility"}))
	assert_eq(QualityDetect.first_run_quality(compat), QualityDetect.LOW, "Compatibility renderer")
	var deck: Dictionary = QualityDetect.pick(_info("AMD Custom GPU 0405 (RADV VANGOGH)", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "Linux", {"arch": "x86_64", "screen": Vector2i(1280, 800)}))
	assert_eq(QualityDetect.first_run_quality(deck), QualityDetect.LOW, "Steam Deck")


func test_a_saved_choice_is_kept() -> void:
	var saved_path: String = Settings.settings_path
	var keep: Dictionary = {}
	for k: String in ["quality", "quality_auto", "quality_note", "quality_probe_done"]:
		keep[k] = Settings.get(k)
	Settings.settings_path = "user://test_v10ui_settings.cfg"
	Settings.set_quality_manual(Settings.Quality.LOW)
	Settings.save_settings()
	Settings.quality = Settings.Quality.ULTRA
	Settings.load_settings()
	assert_eq(Settings.quality, Settings.Quality.LOW, "the player's Low stays Low")
	assert_false(Settings.quality_auto)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.settings_path))
	Settings.settings_path = saved_path
	for k: String in keep:
		Settings.set(k, keep[k])


# --- 109: the map's progress card ---------------------------------------------------------------

func _areas() -> Array:
	return [
		{"name": "Old Town", "ok": 37, "n": 120, "kind": "home", "here": true},
		{"name": "Harbour", "ok": 90, "n": 90, "kind": "awake", "here": false},
		{"name": "Mill", "ok": 0, "n": 110, "kind": "asleep", "here": false},
		{"name": "Quarry", "ok": 0, "n": 100, "kind": "locked", "here": false},
		{"name": "Depot", "ok": 0, "n": 100, "kind": "locked", "here": false},
		{"name": "Observatory", "ok": 0, "n": 80, "kind": "locked", "here": false},
	]


func test_progress_numbers_are_whole_and_add_up() -> void:
	assert_eq(GlobeView.whole_pct(0, 100), 0)
	assert_eq(GlobeView.whole_pct(1, 300), 0, "rounded down")
	assert_eq(GlobeView.whole_pct(299, 300), 99, "not done until it is")
	assert_eq(GlobeView.whole_pct(300, 300), 100)
	var pr: Dictionary = GlobeView.progress_of(_areas())
	assert_eq(int(pr["pct"]), int(floor(100.0 * 127.0 / 600.0)), "the headline is the rows' ground together")
	assert_eq(int(pr["done"]), 1)
	assert_eq(int(pr["total"]), 6)


func test_progress_card_fits_every_language_and_screen() -> void:
	var names: Array[String] = ["Old Town", "Harbour Town", "Mill Town", "Verdance Base", "Station", "Greenhouse"]
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		var g := GlobeView.new()
		var areas: Array = _areas()
		for i: int in areas.size():
			areas[i]["name"] = TranslationServer.translate(names[i])
		g.areas_fn = func() -> Array: return areas
		g.planet = PlanetData.new()
		add_child_autofree(g)
		g._root.visible = true
		g._refresh_text()
		await get_tree().process_frame
		await get_tree().process_frame
		var rd: Dictionary = g.read_progress()
		assert_eq(int(rd["shown_rows"]), 6, "%s: six rows, the locked ones too" % loc)
		assert_true(str(rd["big"]).contains(str(int(rd["pct"]))), "%s: the big number is the whole %%: %s" % [loc, rd["big"]])
		assert_false(str(rd["big"]).contains("."), "%s: no decimals: %s" % [loc, rd["big"]])
		assert_false(g._resurvey.visible, "%s: no paid re-survey" % loc)
		var card: Control = g._left_card
		var sz: Vector2 = card.get_combined_minimum_size()
		assert_lte(sz.y + card.position.y, MIN_SCREEN_H, "%s: the card fits a 720p screen at 150%% interface scale (%.0f px)" % [loc, sz.y])
		assert_lte(sz.x, 400.0, "%s: the card stays a side card (%.0f px)" % [loc, sz.x])
		for l: Node in card.find_children("*", "Label", true, false):
			var lb: Label = l as Label
			if lb.is_visible_in_tree():
				assert_eq(lb.get_visible_line_count(), lb.get_line_count(), "%s: '%s' shows in full" % [loc, lb.text])
				assert_ne(lb.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "%s: '%s' is never cut" % [loc, lb.text])
		g._root.visible = false


# --- Critic 14: the card's picture is the thing the step points at ------------------------------

## The thing each checklist step's marker points at (story/tutorial.gd target()).
const STEP_TARGETS: Dictionary = {"repair": "bench", "scoop": "piece", "dump": "pad", "upgrade": "bench"}


func test_every_checklist_step_has_the_picture_of_its_target() -> void:
	for s: Dictionary in Tutorial.STEPS:
		var id: String = str(s["id"])
		assert_true(STEP_TARGETS.has(id), "step %s: its target is known to this test" % id)
		assert_eq(str(Tutorial.STEP_PICS.get(id, "")), str(Tutorial.TARGET_PICS.get(STEP_TARGETS.get(id, ""), "?")), "step %s: picture = its target's" % id)


func test_card_shows_the_checklist_picture_not_the_goal_underneath() -> void:
	var card := ObjectiveCard.new()
	add_child_autofree(card)
	var def: Dictionary = {"id": "dump3", "text": "Fill the bin 3 times"}
	card.set_substep("Fix the Settlers' old bench: press E", [-1.0, ""], "gear")
	card._set_texts(def)
	assert_eq(card._pic.kind, "gear", "the bench step shows the bench's picture, not the bin")
	card.set_substep("", [-1.0, ""], "gear")
	card._set_texts(def)
	assert_eq(card._pic.kind, ObjectiveCard.picture_of(def), "back on the goal: the goal's picture")
	assert_eq(card.substep_pic, "", "no sub-step, no sub-step picture")


func test_checklist_caption_has_no_jargon() -> void:
	var src: String = FileAccess.get_file_as_string("res://ui/checklist_card.gd")
	assert_false(src.contains("tr(\"RESTART CHECKLIST"), "no \"RESTART CHECKLIST\" caption")
	assert_true(src.contains("tr(\"FIRST STEPS\")"), "the caption is \"FIRST STEPS\"")


# --- Critic 7: one word for a base ------------------------------------------------------------

func test_card_steps_say_base() -> void:
	for d: Dictionary in _json("res://data/objectives.json")["objectives"] + _json("res://data/goals.json")["goals"]:
		var t: String = str(d.get("text", "")).to_lower()
		for w: String in ["station", "district", " hub"]:
			assert_false(t.contains(w), "%s: \"%s\" says \"base\", not \"%s\"" % [d["id"], d.get("text", ""), w.strip_edges()])


# --- Owner, 20 Nov: the map is turned with the mouse ----------------------------------------

func test_map_view_brings_any_place_to_the_front() -> void:
	for c: Vector3 in [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0).normalized(), Vector3(-0.4, 0.6, -0.69).normalized(), Vector3(0.3, -0.8, 0.52).normalized()]:
		var v: Vector2 = GlobeView.view_of(c)
		var front: Vector3 = GlobeView.turn_basis(v.x, v.y) * c
		assert_almost_eq(front.z, 1.0, 0.001, "%s faces the viewer (it missed away from the zero meridian)" % str(c))
	var pole: Vector2 = GlobeView.view_of(Vector3.UP)
	assert_almost_eq(pole.y, GlobeView.PITCH_MAX, 0.0001, "the view stops short of the pole")


func test_map_up_down_drag_tips_toward_the_screen_at_any_spin() -> void:
	for yaw: float in [0.0, 1.2, PI * 0.5, 2.9, -2.0]:
		var step: Basis = GlobeView.turn_basis(yaw, 0.5) * GlobeView.turn_basis(yaw, 0.3).inverse()
		var axis: Vector3 = step.get_rotation_quaternion().get_axis()
		assert_almost_eq(absf(axis.x), 1.0, 0.001, "spun %.1f: an up-down drag turns about the screen's left-right line (it rolled sideways)" % yaw)
		var north: Vector3 = GlobeView.turn_basis(yaw, GlobeView.PITCH_MAX) * Vector3.UP
		assert_gt(north.y, 0.1, "spun %.1f: tipped as far as it goes, north is still up" % yaw)


func test_map_drag_keeps_the_ground_under_the_cursor() -> void:
	# A point at the front of a globe of radius r seen from d: turned by k rad it moves r*k sideways,
	# which is r*k / ((d - r) * tan(fov / 2)) * h / 2 pixels. One pixel of drag must move it one pixel.
	for cfg: Array in [[0.38, 2.0, 55.0, 540.0], [1.0, 3.2, 40.0, 720.0], [0.38, 1.3, 55.0, 1080.0]]:
		var r: float = cfg[0]
		var d: float = cfg[1]
		var k: float = GlobeView.turn_per_px(r, d, cfg[2], cfg[3])
		var px: float = r * k / ((d - r) * tan(deg_to_rad(float(cfg[2])) * 0.5)) * float(cfg[3]) * 0.5
		assert_almost_eq(px, 1.0, 0.01, "globe %.2f at %.1f on a %d px screen" % [r, d, int(cfg[3])])


func test_map_wheel_steps_and_first_hint_strings() -> void:
	var notch := InputEventMouseButton.new()
	assert_almost_eq(GlobeView._wheel_step(notch), 1.0, 0.001, "a wheel notch is one step")
	notch.factor = 0.2
	assert_almost_eq(GlobeView._wheel_step(notch), 0.2, 0.001, "a smooth wheel's small step is a small step")
	notch.factor = 40.0
	assert_almost_eq(GlobeView._wheel_step(notch), 3.0, 0.001, "a wild step is capped")
	for loc: String in LOCALES:
		TranslationServer.set_locale(loc)
		for t: String in ["Drag to turn the planet. Scroll to zoom.", "Find Lumi", "Play", "New profile", "Start over"]:
			if loc != "en":
				assert_ne(TranslationServer.translate(t), t, "%s: \"%s\" is translated" % [loc, t])
	TranslationServer.set_locale("en")


func test_map_root_reads_the_mouse_itself() -> void:
	var g := GlobeView.new()
	g.planet = PlanetData.new()
	add_child_autofree(g)
	assert_true(g._root.gui_input.is_connected(g._on_root_input), "the map's root hands its mouse events to the globe")
	assert_eq(g._root.mouse_filter, Control.MOUSE_FILTER_STOP, "and keeps them from the game behind")


func test_title_has_no_new_game_button() -> void:
	var src: String = FileAccess.get_file_as_string("res://ui/main_menu.gd") + FileAccess.get_file_as_string("res://ui/profile_picker.gd")
	assert_false(src.contains("tr(\"New Game\")"), "no New Game button on the title or the Profiles page")
	assert_true(src.contains("tr(\"Start over\")"), "starting over is per profile")


## The fault: the map's full-screen root took every mouse press, and the drag code sat in
## _unhandled_input where it never saw one. The root's own mouse handler turns the globe now
## (tools/walk_map.gd sends the events through the window; here: what the handler does with them).
func test_map_root_mouse_turns_the_globe_and_not_from_the_card() -> void:
	var g := GlobeView.new()
	g.areas_fn = func() -> Array: return _areas()
	g.planet = PlanetData.new()
	add_child_autofree(g)
	g._root.visible = true
	g.is_open = true
	g._refresh_text()
	await get_tree().process_frame
	await get_tree().process_frame
	var free_spot: Vector2 = Vector2(g._root.size.x * 0.75, g._root.size.y * 0.7)
	assert_false(g._on_ui(free_spot), "the test's free spot is off the cards")
	for at: Vector2 in [g._pct.get_global_rect().get_center(), free_spot]:
		var on_card: bool = g._on_ui(at)
		var mv := InputEventMouseMotion.new()
		mv.position = at
		mv.global_position = at
		g._on_root_input(mv)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = at
		ev.global_position = at
		g._on_root_input(ev)
		assert_eq(g._drag, not on_card, "a press %s" % ("on the card does not take the globe" if on_card else "on the globe takes hold of it"))
		var y0: float = g._yaw
		var drag := InputEventMouseMotion.new()
		drag.position = at + Vector2(30, 0)
		drag.global_position = drag.position
		drag.relative = Vector2(30, 0)
		drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		g._on_root_input(drag)
		if on_card:
			assert_eq(g._yaw, y0, "and a drag from the card does not turn it")
		else:
			assert_gt(g._yaw, y0, "and the drag turns it")
		ev = ev.duplicate()
		ev.pressed = false
		g._on_root_input(ev)
		assert_false(g._drag, "letting go lets go")
	var pan := InputEventPanGesture.new()
	pan.position = free_spot
	pan.delta = Vector2(0, -1.0)
	g._on_root_input(pan)
	assert_almost_eq(g._zoom_to, GlobeView.ZOOM_HOME * exp(-0.08), 0.001, "a two-finger scroll zooms, once per event")
	var mag := InputEventMagnifyGesture.new()
	mag.position = free_spot
	mag.factor = 1.25
	g._zoom_to = GlobeView.ZOOM_HOME
	g._on_root_input(mag)
	assert_almost_eq(g._zoom_to, GlobeView.ZOOM_HOME / 1.25, 0.001, "a pinch zooms, once per event")
	g.is_open = false
