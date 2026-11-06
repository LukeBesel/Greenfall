class_name PauseMenu
extends CanvasLayer
## Pause menu with a few settings. Pauses the tree while open.

signal closed
signal codex_requested

var is_open: bool = false
var _root: Control
var _first: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.12, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := UITheme.label("PAUSED", 34, UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_first = _button(vb, "Resume", close_menu)
	_button(vb, "Codex  [K]", func() -> void:
		close_menu()
		codex_requested.emit())
	_toggle(vb, "Screen shake", Settings.screen_shake, func(v: bool) -> void: Settings.screen_shake = v)
	_toggle(vb, "Hold to scoop (off = toggle)", Settings.hold_to_scoop, func(v: bool) -> void: Settings.hold_to_scoop = v)
	_toggle(vb, "Reduced motion", Settings.reduced_motion, func(v: bool) -> void: Settings.reduced_motion = v)
	_slider(vb, "Music", Settings.music_volume, func(v: float) -> void:
		Settings.music_volume = v
		Audio.apply_volumes())
	_slider(vb, "Sound effects", Settings.sfx_volume, func(v: float) -> void:
		Settings.sfx_volume = v
		Audio.apply_volumes())
	var fmt_btn := Button.new()
	fmt_btn.custom_minimum_size = Vector2(0, 48)
	var names: Array[String] = ["Short (1.2K)", "Scientific (1.2e3)", "Engineering (1.2e3)"]
	fmt_btn.text = "Numbers: " + names[Settings.number_format]
	fmt_btn.pressed.connect(func() -> void:
		Settings.number_format = (Settings.number_format + 1) % 3
		fmt_btn.text = "Numbers: " + names[Settings.number_format])
	vb.add_child(fmt_btn)
	_button(vb, "Save game", func() -> void:
		if SaveManager.save_game():
			EventBus.toast.emit("Saved.", "info"))
	_button(vb, "Quit", func() -> void:
		SaveManager.save_game()
		get_tree().quit())
	_root.visible = false


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _toggle(parent: Control, text: String, value: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.custom_minimum_size = Vector2(0, 44)
	c.toggled.connect(cb)
	parent.add_child(c)


func _slider(parent: Control, text: String, value: float, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := UITheme.label(text, 18)
	l.custom_minimum_size = Vector2(150, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(0, 40)
	s.value_changed.connect(cb)
	hb.add_child(s)


func open_menu() -> void:
	is_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	_first.call_deferred("grab_focus")


func close_menu() -> void:
	is_open = false
	_root.visible = false
	get_tree().paused = false
	Settings.save_settings()
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close_menu()
		get_viewport().set_input_as_handled()
