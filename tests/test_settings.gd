extends GutTest
## Key/controller rebinding: persistence, conflicts and reset; new accessibility settings.

## [v7look] Per process: every worktree's tests share one user:// folder, and two runs at once read
## each other's file (test_rebind_persists_through_save_and_load flaked).
var TEST_PATH: String = "user://test_settings_%d.cfg" % OS.get_process_id()

var _saved_path: String
var _saved: Dictionary = {}


func before_each() -> void:
	_saved_path = Settings.settings_path
	Settings.settings_path = TEST_PATH
	for k: String in ["ui_scale", "subtitles_enabled", "subtitle_size", "subtitle_background", "colorblind", "fov", "shake_intensity", "mouse_smoothing"]:
		_saved[k] = Settings.get(k)
	Settings.reset_bindings()


func after_each() -> void:
	Settings.reset_bindings()
	for k: String in _saved:
		Settings.set(k, _saved[k])
	Settings.settings_path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _joy(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


func test_defaults_have_no_conflicts() -> void:
	assert_eq(Settings.conflicts(), {})
	assert_eq(Settings.event_label(Settings.binding("interact", false)), "E")
	assert_eq(Settings.event_label(Settings.binding("interact", true)), "A")


func test_rebind_replaces_primary_only() -> void:
	Settings.set_binding("move_forward", _key(KEY_I))
	assert_eq(Settings.event_label(Settings.binding("move_forward", false)), "I")
	# The arrow-key alternative and the stick stay.
	var labels: Array = InputMap.action_get_events("move_forward").map(func(e: InputEvent) -> String: return Settings.event_label(e))
	assert_true(labels.has("Up"))
	assert_true(labels.has("LS up"))
	assert_false(labels.has("W"))
	assert_true(Settings.is_rebound("move_forward"))


func test_rebind_persists_through_save_and_load() -> void:
	Settings.set_binding("interact", _key(KEY_F))
	Settings.set_binding("drop", _joy(JOY_BUTTON_Y))
	Settings.save_settings()
	Settings.reset_bindings()
	assert_eq(Settings.event_label(Settings.binding("interact", false)), "E")
	Settings.load_settings()
	assert_eq(Settings.event_label(Settings.binding("interact", false)), "F")
	assert_eq(Settings.event_label(Settings.binding("drop", true)), "Y")
	assert_true(InputMap.action_has_event("interact", _key(KEY_F)))


func test_conflict_detected_in_same_context_only() -> void:
	assert_eq(Settings.find_conflict("interact", _key(KEY_Q)), "drop")
	# ui_tab_next also uses E but lives in the UI context: no conflict.
	assert_eq(Settings.find_conflict("interact", _key(KEY_E)), "")
	Settings.set_binding("interact", _key(KEY_Q))
	assert_true(Settings.conflicts().has("interact"))
	assert_true(Settings.conflicts().has("drop"))


func test_reset_to_defaults() -> void:
	Settings.set_binding("scoop", _key(KEY_J))
	Settings.save_settings()
	Settings.reset_bindings()
	Settings.save_settings()
	assert_false(Settings.is_rebound("scoop"))
	assert_eq(Settings.event_label(Settings.binding("scoop", false)), "LMB")
	Settings.load_settings()
	assert_eq(Settings.event_label(Settings.binding("scoop", false)), "LMB")


func test_rebinding_back_to_default_clears_override() -> void:
	Settings.set_binding("cube", _key(KEY_Z))
	assert_true(Settings.is_rebound("cube"))
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	Settings.set_binding("cube", mb)
	assert_false(Settings.is_rebound("cube"))


func test_event_dict_round_trip() -> void:
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_TRIGGER_RIGHT
	m.axis_value = 1.0
	for ev: InputEvent in [_key(KEY_K), _joy(JOY_BUTTON_X), m]:
		assert_true(Settings.same_event(ev, Settings.event_from_dict(Settings.event_to_dict(ev))))


func test_accessibility_settings_persist() -> void:
	Settings.ui_scale = 1.25
	Settings.subtitle_size = Settings.SubtitleSize.LARGE
	Settings.subtitle_background = true
	Settings.subtitles_enabled = false
	Settings.colorblind = true
	Settings.fov = 75.0
	Settings.shake_intensity = 0.4
	Settings.mouse_smoothing = true
	Settings.save_settings()
	Settings.ui_scale = 1.0
	Settings.subtitle_size = 0
	Settings.subtitle_background = false
	Settings.subtitles_enabled = true
	Settings.colorblind = false
	Settings.fov = 62.0
	Settings.shake_intensity = 1.0
	Settings.mouse_smoothing = false
	Settings.load_settings()
	assert_almost_eq(Settings.ui_scale, 1.25, 0.001)
	assert_eq(Settings.subtitle_size, Settings.SubtitleSize.LARGE)
	assert_true(Settings.subtitle_background)
	assert_false(Settings.subtitles_enabled)
	assert_true(Settings.colorblind)
	assert_almost_eq(Settings.fov, 75.0, 0.001)
	assert_almost_eq(Settings.shake_intensity, 0.4, 0.001)
	assert_true(Settings.mouse_smoothing)
	assert_true(Settings.screen_shake)


func test_colorblind_palette_differs() -> void:
	Settings.colorblind = false
	var junk: Color = UITheme.progress_color("junk")
	var rare: Color = UITheme.rarity_color(2)
	Settings.colorblind = true
	assert_ne(UITheme.progress_color("junk"), junk)
	assert_ne(UITheme.rarity_color(2), rare)
	assert_ne(UITheme.progress_color("junk"), UITheme.progress_color("clean"))


func test_glyph_follows_device() -> void:
	var was: bool = Settings.last_input_pad
	Settings.last_input_pad = false
	assert_eq(Settings.glyph("interact"), "E")
	Settings.last_input_pad = true
	assert_eq(Settings.glyph("interact"), "A")
	Settings.last_input_pad = was


## [v7look] A dev run that overrides settings (--ui-scale, --ui-audit, ...) must not write the
## player's settings file; the test path still saves.
func test_dev_runs_do_not_write_the_players_settings() -> void:
	var p: String = ProjectSettings.globalize_path(Settings.SETTINGS_PATH)
	var before: String = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else "<none>"
	Settings.settings_path = Settings.SETTINGS_PATH
	Settings.no_write = true
	var scale0: float = Settings.ui_scale
	Settings.ui_scale = 1.37
	Settings.save_settings()
	Settings.ui_scale = scale0
	Settings.no_write = false
	Settings.settings_path = TEST_PATH
	var after: String = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else "<none>"
	assert_eq(after, before, "the player's settings file is untouched")
	Settings.no_write = true  # the test file is still written
	Settings.save_settings()
	Settings.no_write = false
	assert_true(FileAccess.file_exists(TEST_PATH))
	for f: String in ["ui-scale", "locale", "quality", "ui-audit"]:
		assert_has(DevHooks.NO_SETTINGS_WRITE, f)
