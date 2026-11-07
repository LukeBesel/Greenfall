class_name PauseMenu
extends CanvasLayer
## Pause menu. Pauses the tree while open. Settings live in the shared SettingsPanel.

signal closed
signal codex_requested
signal photo_requested  # [photo]

const TITLE_SCENE: String = "res://scenes/main_menu.tscn"

var is_open: bool = false
var _root: Control
var _menu: Control
var _first: Button
var _settings_btn: Button
var _settings: SettingsPanel


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.035, 0.04, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_menu = center
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.88), UITheme.RUST, 1, 6, 22))
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := UITheme.label(tr("PAUSED"), 32, UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	vb.add_child(gap)
	var buttons: Array[Button] = []
	_first = _button(vb, tr("Resume"), close_menu)
	buttons.append(_first)
	var codex_btn: Button = _button(vb, tr("Codex"), func() -> void:
		close_menu()
		codex_requested.emit())
	Settings.bind_text(codex_btn, func() -> String: return tr("Codex  [%s]") % Settings.glyph("open_codex"))  # [deck]
	buttons.append(codex_btn)
	buttons.append(_button(vb, tr("Photo mode  [%s]") % Settings.glyph("photo_mode"), func() -> void:  # [photo]
		close_menu()
		photo_requested.emit()))
	buttons.append_array(LateMenu.add_buttons(self, vb, _button))  # [late] Garden Mode, Ark Bridge
	_settings_btn = _button(vb, tr("Settings"), _open_settings)
	buttons.append(_settings_btn)
	buttons.append(_button(vb, tr("Save game"), func() -> void:
		if SaveManager.save_game():
			EventBus.toast.emit(tr("Saved."), "info")))
	buttons.append(_button(vb, tr("Quit to title"), _quit_to_title))
	buttons.append(_button(vb, tr("Quit to desktop"), func() -> void:
		SaveManager.save_game()
		get_tree().quit()))
	for i: int in buttons.size():
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[wrapi(i - 1, 0, buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(buttons[wrapi(i + 1, 0, buttons.size())])
	_settings = SettingsPanel.new()
	_settings.dim_background = false
	_settings.closed.connect(func() -> void:
		_menu.visible = true
		_settings_btn.grab_focus())
	_root.add_child(_settings)
	_root.visible = false


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		cb.call())
	UITheme.juice(b, 1.025)
	parent.add_child(b)
	return b


func _open_settings() -> void:
	_menu.visible = false
	_settings.open_panel()


func _quit_to_title() -> void:
	SaveManager.save_game()
	is_open = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Loader.goto(TITLE_SCENE)  # [intro2] loading screen


func open_menu() -> void:
	is_open = true
	_root.visible = true
	_menu.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	LateMenu.refresh(self)  # [late] show Garden Mode / Ark Bridge once they are open
	_first.call_deferred("grab_focus")


func close_menu() -> void:
	is_open = false
	if _settings.is_open:
		_settings.close_panel()
	_root.visible = false
	get_tree().paused = false
	Settings.save_settings()
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and not _settings.is_open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close_menu()
		get_viewport().set_input_as_handled()
