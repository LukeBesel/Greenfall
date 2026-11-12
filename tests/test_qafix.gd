extends GutTest
## [qafix] Fixes from docs/QA_REPORT.md (claude/greenfall-qa); status per item in docs/QA_STATUS.md.

var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	_cur = GameState.currencies.duplicate()
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {"hub_level": 1}
	GameState.currencies = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world
	GameState.currencies = _cur


# #20: "Lumi reached level 5 · +89 cubes +10 parts +5 parts" listed Parts twice.
func test_level_reward_names_parts_once() -> void:
	var plan: Dictionary = LumiLevel.reward_plan(5, 0.0, 0.0, false)
	assert_eq(int(plan["parts"]) + int(plan["bonus_parts"]), 0, "a level pays no Parts on this planet")
	var lv := LumiLevel.new()
	add_child_autofree(lv)
	var text: String = lv._grant(5)
	var hits: int = 0
	for w: String in text.split(" ", false):
		if w.begins_with("part"):
			hits += 1
	assert_lte(hits, 1, "at most one Parts amount in '%s'" % text)


# #14: the Glim discovery line used to end in "He'll…"; the message line splits it into chunks.
func test_long_toast_is_never_cut() -> void:
	var t: String = "Something in the junk blinks back at you: Glim, a little lantern bot! He'll light the way at night."
	var parts: PackedStringArray = Subtitles.chunks(t)
	var joined: String = " ".join(parts)
	assert_true(joined.contains("light the way at night"), "the whole line is shown: %s" % [parts])


# #21: the now-playing Label collapsed to 1 px (clip_text without a width).
func test_title_song_tag_has_room_for_its_text() -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	var tag := TitleSongTag.new()
	host.add_child(tag)
	tag._label.text = TitleSongTag.short("Sunbaked, Two Suns Tango Orchestra")
	await wait_process_frames(3)
	assert_gt(tag._label.size.x, 120.0, "the label is as wide as its text")
	var r: Rect2 = tag._label.get_global_rect()
	assert_lt(r.end.x, 1280.0 + 0.5, "inside the screen")
	assert_gt(r.position.x, 640.0, "bottom right")
	assert_eq(TitleSongTag.short("x".repeat(100)).length(), 56)


# #22: Keepsakes offered the CD Player from the first minute.
func test_keepsakes_tabs_wait_for_their_builds() -> void:
	assert_false(ExtrasPanel.tab_open("radio"), "no CD player on a fresh yard")
	assert_false(ExtrasPanel.tab_open("nursery"), "the nursery is parked")
	assert_false(ExtrasPanel.tab_open("weekly"), "a tab nobody owns is never open")
	YardBuilds.mark_built("radio")
	assert_true(ExtrasPanel.tab_open("radio"), "the CD player tab comes with the build")


# #11: a fresh yard is pod, broken bench and bin: no water barrel before waterers exist.
func test_water_barrel_waits_for_waterers() -> void:
	assert_false(WaterNet.barrel_wanted(null))


# #36: the trail chevrons blend normally (additive washed out to white on pale ground).
func test_waypoint_trail_is_not_additive() -> void:
	var w := Waypoint.new()
	add_child_autofree(w)
	assert_false((w._mat_trail.shader as Shader).code.contains("blend_add"))
	assert_true((w._mat_trail.shader as Shader).code.contains("blend_mix"))


# world3 via main: egg machines are dead on landing (no lit screen, tube, LED or glow light) and
# come back when Lumi pokes them.
func test_egg_machines_start_dead_and_wake() -> void:
	for kind: String in EggPower.KINDS:
		var n: Node3D = EggProps.build(kind)
		add_child_autofree(n)
		EggPower.kill(n)
		assert_true(EggPower.is_dead(n), kind)
		for c: Node in n.find_children("*", "", true, false):
			if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
				assert_false(((c as MeshInstance3D).material_override as StandardMaterial3D).emission_enabled, "%s: %s glows" % [kind, c.name])
			if c is Light3D:
				assert_eq((c as Light3D).light_energy, 0.0, "%s: light off" % kind)
			if c is Label3D and not (c as Label3D).shaded:
				assert_false((c as Label3D).visible, "%s: glowing text hidden" % kind)
		EggPower.wake(n)
		assert_false(EggPower.is_dead(n))
	var v: Node3D = EggProps.build("vending")
	add_child_autofree(v)
	var scr: MeshInstance3D = v.get_node("Screen")
	var lit: Material = scr.material_override
	EggPower.kill(v)
	assert_ne(scr.material_override, lit)
	EggPower.wake(v)
	assert_eq(scr.material_override, lit, "the original lit screen comes back")


# Crash fix (signal 11 on the audio mixer thread): fades don't rewrite a player's volume every frame.
func test_fade_volume_writes_are_throttled() -> void:
	var p := AudioStreamPlayer.new()
	add_child_autofree(p)
	p.volume_db = -20.0
	assert_false(AudioVol.set_db(p, -20.1), "a change under 0.25 dB is skipped")
	assert_true(AudioVol.set_db(p, -19.0))
	assert_false(AudioVol.set_db(p, -18.0), "a second small step within 50 ms waits")
	assert_true(AudioVol.set_db(p, -80.0), "a big jump (fade to silence) goes through at once")
	assert_eq(p.volume_db, -80.0)
	p.set_meta(AudioVol.META, Time.get_ticks_msec() - AudioVol.MIN_GAP_MS - 1)  # 50 ms later
	assert_true(AudioVol.set_db(p, -79.0), "after 50 ms the next step is written")
	var src: String = (load("res://audio/ambience.gd") as Script).source_code
	assert_false(src.contains("p.volume_db = linear_to_db(cur)"), "ambience fades go through AudioVol")


# orbC: autoplay runs stalled with the tree paused. A scratched CD the bot picked up asks
# "Play now?" and pauses the game until someone answers (fine for a person, nobody answers for the
# bot). The autoplay watchdog answers it like a person would and the tree runs again.
func test_pause_watch_answers_the_scratched_cd_choice() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var sc := ScratchedCdUI.new()
	host.add_child(sc)
	var pw := PauseWatch.new()
	pw.world = host
	host.add_child(pw)
	sc.ask("sunbaked")
	assert_true(get_tree().paused, "the choice pauses the game")
	assert_has(pw.open_screens(), "ScratchedCdUI(ask)", "the watchdog sees what holds the pause")
	pw.resolve()
	assert_false(get_tree().paused, "answered: the game runs again")
	assert_eq(pw.open_screens().size(), 0)
	get_tree().paused = false
