extends GutTest
## [v14travel] The rocket's list (ui/rocket_picker.gd) with each way a player picks a base: a mouse
## click on Fly, the keyboard (arrows, Enter) and a controller (d-pad, A). On a controller A is both
## "interact" (the key that opens the list at the rocket) and "ui_accept" (press the focused button).

var _p: RocketPicker
var _picked: Array[int] = []


func before_each() -> void:
	_picked.clear()
	_p = RocketPicker.new()
	add_child_autofree(_p)
	_p.entries_fn = func() -> Array:
		return [{"site": 0, "name": "Landing Yard", "km": 2.0, "tag": "HOME", "home": true}, {"site": 9, "name": "Garden Row", "km": 1.5, "tag": "NEXT STOP"}]
	_p.picked.connect(func(s: int) -> void: _picked.append(s))
	await get_tree().process_frame


func _ev(action: String, joy: bool) -> InputEvent:
	for ev: InputEvent in InputMap.action_get_events(action):
		if joy and ev is InputEventJoypadButton:
			return ev.duplicate()
		if not joy and ev is InputEventKey:
			return ev.duplicate()
	return null


func _tap(action: String, joy: bool) -> void:
	var ev: InputEvent = _ev(action, joy)
	assert_not_null(ev, "%s has a %s binding" % [action, "controller" if joy else "key"])
	if ev == null:
		return
	for down: bool in [true, false]:
		var e: InputEvent = ev.duplicate()
		if e is InputEventJoypadButton:
			(e as InputEventJoypadButton).pressed = down
		elif e is InputEventKey:
			(e as InputEventKey).pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await get_tree().process_frame
		await get_tree().process_frame


func _open() -> void:
	_p.open()
	await get_tree().process_frame
	await get_tree().process_frame


func test_controller_a_on_the_focused_fly_flies() -> void:
	await _open()
	var f: Control = get_viewport().gui_get_focus_owner()
	assert_true(f is Button and (f as Button).text == "Fly", "the first Fly takes the focus on open")
	await _tap("ui_down", true)
	f = get_viewport().gui_get_focus_owner()
	assert_true(f is Button and f != null, "d-pad down keeps the focus on a button")
	await _tap("ui_accept", true)
	assert_eq(_picked, [9], "d-pad down, A: flies to the second row's base (list open after: %s)" % _p.is_open)


func test_keyboard_enter_on_the_focused_fly_flies() -> void:
	await _open()
	await _tap("ui_accept", false)
	assert_eq(_picked, [0], "Enter on the focused Fly flies")


func test_e_closes_the_list_without_flying() -> void:
	await _open()
	await _tap("interact", false)
	assert_false(_p.is_open, "E closes the list")
	assert_eq(_picked, [], "and flies nowhere")
