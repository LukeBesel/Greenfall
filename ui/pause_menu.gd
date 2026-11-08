class_name PauseMenu
extends CanvasLayer
## Pause menu. Pauses the tree while open. Settings live in the shared SettingsPanel.
## [ui2] Resume, Codex, Photo mode, (Garden / Ark when open), Keepsakes, Settings, Quit (saves, then title).

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
var _center_keys: Control  # [onboard] key hints strip


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
	panel.add_theme_stylebox_override("panel", BenchKit.holo(Color(BenchKit.HOLO, 0.5), Color(0.02, 0.035, 0.045, 0.88), 1.0, 12, 22))  # [ui2] holo
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := UITheme.label(tr("PAUSED"), 28, BenchKit.HOLO)  # [ui2]
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
	buttons.append(_button(vb, tr("Keepsakes"), func() -> void:  # [extras] radio, album, nursery, Seed of the Week
		close_menu()
		ExtrasPanel.open_for(get_parent(), "")))
	_settings_btn = _button(vb, tr("Settings"), _open_settings)
	buttons.append(_settings_btn)
	# [ui2] No Save button: the game autosaves every minute and on quit. Quit saves and goes to
	# the title screen (Quit to desktop lives on the title screen).
	buttons.append(_button(vb, tr("Quit"), _quit_to_title))
	for i: int in buttons.size():
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[wrapi(i - 1, 0, buttons.size())])
		b.focus_neighbor_bottom = b.get_path_to(buttons[wrapi(i + 1, 0, buttons.size())])
	# [onboard] The controls at a glance, under the menu (in game: hold Tab away from the workbench).
	var keys_mc := MarginContainer.new()
	keys_mc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	keys_mc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	keys_mc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_mc.add_theme_constant_override("margin_bottom", 28)
	keys_mc.add_child(KeyHints.new(KeyHints.Mode.PAUSE))
	_center_keys = keys_mc
	_root.add_child(keys_mc)
	_settings = SettingsPanel.new()
	_settings.dim_background = false
	_settings.closed.connect(func() -> void:
		_menu.visible = true
		_center_keys.visible = true  # [onboard]
		_settings_btn.grab_focus())
	_root.add_child(_settings)
	_root.visible = false


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 17)
	BenchKit.style_action(b, BenchKit.HOLO)  # [ui2]
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		cb.call())
	UITheme.juice(b, 1.025)
	parent.add_child(b)
	return b


func _open_settings() -> void:
	_menu.visible = false
	_center_keys.visible = false  # [onboard]
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
