extends GutTest
## [v7play] Release check for Verdance: the planets this release has not built stay closed
## (data/homeward.json planets[k].open, "closed"), with a friendly line on the map, no goal that
## asks for them, and a "to be continued" beat when the drive is built.

var _profile: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_profile = CradleMode.profile.duplicate(true)
	_flags = GameState.flags.duplicate(true)
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()


func after_each() -> void:
	CradleMode.profile = _profile
	GameState.flags = _flags


func test_only_verdance_is_open_in_this_release() -> void:
	assert_true(Homeward.planet_open(0), "Verdance")
	for k: int in range(1, Homeward.planets().size()):
		assert_false(Homeward.planet_open(k), "%s is closed until it is built" % Homeward.planet_name(k))
	assert_eq(Homeward.current_planet(), 0)
	assert_true(Homeward.next_closed())


func test_closed_planet_cannot_be_launched_to_even_with_the_drive() -> void:
	(Homeward.state()["pct"] as Dictionary)["verdance"] = 0.9
	Homeward.state()["drive"] = 5
	assert_true(Homeward.discovered(1), "Ochre still shows on the map")
	var why: String = SystemMap.launch_blocker(null, 1)
	assert_eq(why, str(Homeward.closed_cfg()["map_line"]), "the map says why, in friendly words")
	assert_false(HomewardDirector.launch_planet(null, 1), "no launch goes there")


func test_goals_for_other_planets_leave_the_chain() -> void:
	var g := Goals.new()
	autofree(g)
	g.load_chain()
	var ids: Array = g.chain.map(func(d: Dictionary) -> String: return str(d["id"]))
	assert_true("home_drive_5" in ids, "the drive stays: it is Verdance's last big buy")
	for id: Variant in Homeward.closed_cfg()["hide_goals"]:
		assert_false(str(id) in ids, "%s needs a planet that is not open" % id)
	var raw: Array = Economy.read_json("res://data/goals.json")["goals"]
	var raw_ids: Array = raw.map(func(d: Dictionary) -> String: return str(d["id"]))
	for id: Variant in Homeward.closed_cfg()["hide_goals"]:
		assert_true(str(id) in raw_ids, "hide_goals names a real goal: %s" % id)


func test_closed_text_is_there_and_translated() -> void:
	var c: Dictionary = Homeward.closed_cfg()
	var texts: Array = [str(c["map_line"]), str(c["toast"])]
	texts.append_array(c["drive_lines"])
	assert_gt((c["drive_lines"] as Array).size(), 0)
	var was: String = TranslationServer.get_locale()
	for loc: String in ["de", "fr", "es", "pt_BR", "zh_CN", "ja"]:
		TranslationServer.set_locale(loc)
		for t: Variant in texts:
			assert_ne(TranslationServer.translate(str(t)), str(t), "%s has a %s translation" % [t, loc])
	TranslationServer.set_locale(was)


func test_codex_hides_achievements_for_closed_planets() -> void:
	var shown: Array = Achievements.shown_defs().map(func(a: Dictionary) -> String: return str(a["id"]))
	var all: Array = Achievements.defs().map(func(a: Dictionary) -> String: return str(a["id"]))
	for id: Variant in Homeward.closed_cfg()["hide_achievements"]:
		assert_true(str(id) in all, "hide_achievements names a real achievement: %s" % id)
		assert_false(str(id) in shown, "%s can't be earned in this release" % id)
	assert_true("hub_5" in shown, "Verdance's own achievements stay")


func test_robot_stuck_flag_is_recent_not_lifetime() -> void:
	var crew := SphereCrew.new()
	autofree(crew)
	var u: Dictionary = {"stall_t": 0.0, "log": {"unstuck": 5.0}}
	crew._t = 1000.0
	assert_false(crew.is_stuck(u), "old escapes don't keep a robot red in the Command view")
	u["unstuck_at"] = 990.0
	assert_true(crew.is_stuck(u), "just freed from a stall")
	u["unstuck_at"] = 900.0
	assert_false(crew.is_stuck(u))
	u["stall_t"] = SphereCrew.STALL_S
	assert_true(crew.is_stuck(u), "stalled right now")


func test_robot_arm_settles_on_long_frames() -> void:
	var v := RobotVisual.new()
	autofree(v)
	var arm := Node3D.new()
	v.add_child(arm)
	v.set("_arm", arm)
	for i: int in 200:
		v.animate(0.0, false, 0.7)
	assert_true(arm.transform.is_finite(), "a 0.7 s frame no longer drives the arm to NaN")


func test_exit_beat_waits_for_the_six_stations_not_the_core() -> void:
	# Verdance's stored % is the Bloom Core charge: at 50% with 5 stations awake, WREN said
	# "Six stations awake, Lumi" a minute before the sixth woke (full autoplay, 143 bot min).
	(Homeward.state()["pct"] as Dictionary)["verdance"] = 0.6
	assert_gt(Homeward.leave_hubs(0).x, 0, "Verdance leaves by its stations")
	assert_false(StoryArc.leave_open(0), "the core at 60% alone does not open the exit beat")
