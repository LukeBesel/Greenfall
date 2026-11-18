extends GutTest
## [v6screens] Screens driven by a controller alone: real joypad button events through the game's
## input map. The focus is always on a shown control of the open screen, and B closes it. The
## game-wide version (every screen, in the running game) is `--ui-audit --ui-audit-screens=pad`.


func _press(btn: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame
	var r := InputEventJoypadButton.new()
	r.button_index = btn
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame
	await get_tree().process_frame


func _focus_in(root: Node) -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	return f != null and f.is_visible_in_tree() and root.is_ancestor_of(f)


func after_each() -> void:
	get_tree().paused = false


func test_pause_menu_on_a_pad() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var pm := PauseMenu.new()
	host.add_child(pm)
	await get_tree().process_frame
	pm.open_menu()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(_focus_in(pm), "focus on the menu when it opens")
	var seen: Dictionary = {}
	for i: int in 8:
		await _press(JOY_BUTTON_DPAD_DOWN)
		assert_true(_focus_in(pm), "focus stays on a shown button (down x%d)" % (i + 1))
		seen[get_viewport().gui_get_focus_owner()] = true
	assert_gt(seen.size(), 2, "the d-pad moves through the buttons")
	await _press(JOY_BUTTON_B)
	await get_tree().create_timer(0.3, true, false, true).timeout
	assert_false(pm.is_open, "B closes the pause menu")


func test_settings_on_a_pad() -> void:
	var sp := SettingsPanel.new()
	add_child_autofree(sp)
	await get_tree().process_frame
	sp.open_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(_focus_in(sp), "Basics: focus on its first row (the tab row is hidden)")
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	assert_true(_focus_in(sp), "a bumper on Basics alone does not move the focus to a hidden tab")
	for i: int in 6:
		await _press(JOY_BUTTON_DPAD_DOWN)
		assert_true(_focus_in(sp), "down x%d" % (i + 1))
	await _press(JOY_BUTTON_B)
	assert_false(sp.is_open, "B closes Settings")
