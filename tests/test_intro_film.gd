extends GutTest
## [v9intro] The opening film's shot table (data/intro_shots.json) and its timeline: every shot can
## be played, every story line is said once and has its reading time in all six languages, the
## cues exist, and the film's off-world part never comes back once it is on the planet.

const LANGS: Array[String] = ["en", "de", "fr", "es", "pt_BR", "zh_CN", "ja"]
var _locale: String


func before_all() -> void:
	_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_locale)


func test_table_loads_and_every_shot_has_its_code() -> void:
	var table: Dictionary = Intro.load_table()
	var shots: Array = table.get("shots", [])
	assert_gt(shots.size(), 12, "a film, not a slide")
	var it := Intro.new()
	var seen: Dictionary = {}
	var on_planet: bool = false
	for s: Dictionary in shots:
		var id: String = str(s["id"])
		assert_false(seen.has(id), "shot ids are unique: %s" % id)
		seen[id] = true
		assert_true(str(s["set"]) in ["space", "vault", "world"], "%s: a known set" % id)
		assert_true(it.has_method("_in_" + id), "%s: _in_%s sets the shot up" % [id, id])
		if str(s["set"]) == "world":
			on_planet = true
		else:
			assert_false(on_planet, "%s: the film never goes back off-world after the landing (the game's pod is placed there)" % id)
		for c: Variant in s.get("cues", []):
			assert_true(it.has_method("_cue_" + str(c[1])), "%s: cue %s exists" % [id, c[1]])
		var cam: Dictionary = s.get("cam", {})
		if cam.has("fov"):
			for f: Variant in cam["fov"]:
				assert_between(float(f), 20.0, 75.0, "%s: a sane lens" % id)
		if cam.has("from") and cam.has("look_from") and str(cam.get("anchor", "")) == str(cam.get("look_anchor", "")):
			assert_gt(Intro._v3(cam["from"]).distance_to(Intro._v3(cam["look_from"])), 0.5, "%s: the camera looks at something" % id)
		assert_true(str(cam.get("ease", "inout")) in ["linear", "in", "out", "inout", "in_cubic", "out_cubic", "out_quint", "inout_cubic", "smoother"], "%s: a known ease" % id)
	for id: String in Intro.PHASE_SHOTS:
		assert_true(seen.has(id), "--intro-from phase shot %s exists" % id)
	assert_true(on_planet)
	assert_eq(str(shots[-1]["id"]), "handoff", "the film ends on the hand-off to the game camera")
	assert_eq(str((shots[-1]["cam"] as Dictionary).get("mode", "")), "handoff")
	it.free()


func test_every_line_is_said_once_in_story_order() -> void:
	var said: Array[String] = []
	for s: Dictionary in Intro.load_table()["shots"]:
		for l: Variant in s.get("lines", []):
			said.append(str(l[1]))
	var want: Array[String] = []
	for key: String in Intro.lines():
		want.append(key)
	assert_eq(said, want, "the shot table says every line of Intro.lines(), once, in order")


func test_lines_have_their_reading_time_in_every_language() -> void:
	for lang: String in LANGS:
		TranslationServer.set_locale(lang)
		var tl: Array = Intro.timeline(Intro.load_table())
		var free_at: float = 0.0  # when the one subtitle line is free again (film time)
		for s: Dictionary in tl:
			assert_gte(float(s["d"]), float(s["dur"]) - 0.001, "%s %s: a shot only grows" % [lang, s["id"]])
			for l: Variant in s.get("lines", []):
				var start: float = float(s["t0"]) + float(l[0])
				assert_gte(start, free_at - 0.001, "%s %s: %s starts after the line before it" % [lang, s["id"], l[1]])
				free_at = maxf(start, free_at) + Intro.line_time(str(l[1]))
				assert_lte(free_at, float(s["t1"]) + 0.001, "%s %s: %s is read before the cut" % [lang, s["id"], l[1]])
			for c: Variant in s["cues"]:
				assert_between(float(c[0]), 0.0, float(s["d"]), "%s %s: cue %s inside its shot" % [lang, s["id"], c[1]])
		var total: float = float(tl[-1]["t1"])
		assert_between(total, 100.0, 150.0, "%s: the film runs about two minutes (%.1f s)" % [lang, total])
	TranslationServer.set_locale("en")
	assert_between(Intro.film_length(), 105.0, 128.0, "English length")


func test_timeline_grows_a_shot_for_a_long_line() -> void:
	var table: Dictionary = {"shots": [
		{"id": "a", "set": "space", "dur": 4.0, "lines": [[0.5, "x"], [1.0, "y"]], "cues": [[-1.0, "late"], [0.5, "early"]]},
		{"id": "b", "set": "world", "dur": 3.0},
	]}
	var tl: Array = Intro.timeline(table, func(_k: String) -> float: return 3.0)
	# x: 0.5..3.5, y waits for it: 3.5..6.5, plus a breath.
	assert_almost_eq(float(tl[0]["d"]), 6.75, 0.001)
	assert_almost_eq(float(tl[1]["t0"]), 6.75, 0.001)
	assert_almost_eq(float(tl[1]["t1"]), 9.75, 0.001)
	# Cues are sorted, and a negative second counts back from the (grown) end.
	assert_eq(str(tl[0]["cues"][0][1]), "early")
	assert_almost_eq(float(tl[0]["cues"][1][0]), 5.75, 0.001)


func test_eases_start_and_end_clean() -> void:
	for e: String in ["linear", "in", "out", "inout", "in_cubic", "out_cubic", "out_quint", "inout_cubic", "smoother"]:
		assert_almost_eq(Intro.eased(e, 0.0), 0.0, 0.0001, e)
		assert_almost_eq(Intro.eased(e, 1.0), 1.0, 0.0001, e)
		var prev: float = 0.0
		for i: int in 21:
			var v: float = Intro.eased(e, i / 20.0)
			assert_gte(v, prev - 0.0001, "%s never runs backwards" % e)
			prev = v
	# Out of range is clamped: a late frame cannot overshoot a camera move.
	assert_almost_eq(Intro.eased("inout", 1.7), 1.0, 0.0001)
	assert_almost_eq(Intro.eased("out_cubic", -0.4), 0.0, 0.0001)


func test_fire_fades_in_from_nothing() -> void:
	var fire: Node3D = Intro.build_fire()
	add_child_autofree(fire)
	Intro.set_fire(fire, 0.0, 1.0)
	assert_false(fire.visible, "no fire at all at zero")
	Intro.set_fire(fire, 0.02, 1.0)
	assert_true(fire.visible)
	var light: OmniLight3D = fire.get_node("Glow")
	assert_lt(light.light_energy, 0.3, "it starts faint, it does not pop")
	Intro.set_fire(fire, 1.0, 1.0)
	assert_gt(light.light_energy, 4.0)
