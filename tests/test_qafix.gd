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
	assert_gt(int(plan["parts"]), 0, "level 5 pays a robot part")
	assert_gt(int(plan["bonus_parts"]), 0, "and bonus Parts")
	var lv := LumiLevel.new()
	add_child_autofree(lv)
	var text: String = lv._grant(5)
	var hits: int = 0
	for w: String in text.split(" ", false):
		if w.begins_with("part"):
			hits += 1
	assert_eq(hits, 1, "one Parts amount in '%s'" % text)


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


# #22: Keepsakes offered the CD Player and the Nursery from the first minute.
func test_keepsakes_tabs_wait_for_their_builds() -> void:
	assert_false(ExtrasPanel.tab_open("radio"), "no CD player on a fresh yard")
	assert_false(ExtrasPanel.tab_open("nursery"), "no nursery at the start")
	assert_true(ExtrasPanel.tab_open("weekly"))
	assert_eq(ExtrasPanel.open_tabs()[0], "album" if ExtrasPanel.tab_open("album") else "weekly")
	YardBuilds.mark_built("radio")
	assert_true(ExtrasPanel.tab_open("radio"), "the CD player tab comes with the build")


# #11: a fresh yard is pod, broken bench and bin: no water barrel before waterers exist.
func test_water_barrel_waits_for_waterers() -> void:
	assert_false(WaterNet.barrel_wanted(null))


# #7: the camera hides Lumi when a wall pushes it into his head, and shows him again after.
func test_camera_hides_lumi_only_when_inside() -> void:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	var p := Patch.new()
	p.model = PatchModel.new()
	rig.target = p
	rig._hide_target_when_inside(true)
	assert_false(p.model.visible)
	rig._hide_target_when_inside(false)
	assert_true(p.model.visible)
	p.model.free()
	p.free()


# #36: the trail chevrons blend normally (additive washed out to white on pale ground).
func test_waypoint_trail_is_not_additive() -> void:
	var w := Waypoint.new()
	add_child_autofree(w)
	assert_false((w._mat_trail.shader as Shader).code.contains("blend_add"))
	assert_true((w._mat_trail.shader as Shader).code.contains("blend_mix"))
