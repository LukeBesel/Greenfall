class_name SettingsPanel
extends Control
## Reusable settings screen (title menu and pause menu). Tabs: Audio, Graphics, Controls, Gameplay.
## Every change is applied immediately and written with Settings.save_settings().
## Controller: up/down moves between rows, left/right changes a value, Q/E or the shoulders switch
## tabs, B / Esc closes.

signal closed

const TABS: Array[String] = ["Audio", "Graphics", "Controls", "Gameplay"]
const ROW_W: float = 300.0
const BINDINGS: Array = [
	["Move", ["move_forward", "move_left", "move_back", "move_right"]],
	["Scoop junk", ["scoop"]],
	["Press a cube", ["cube"]],
	["Interact", ["interact"]],
	["Drop", ["drop"]],
	["Tools: scoop / plant / water", ["tool_scoop", "tool_plant", "tool_water"]],
	["Upgrades", ["open_upgrades"]],
	["Lens view", ["lens_view"]],
	["Globe map", ["open_globe"]],
	["Command view", ["open_command"]],
	["Zoom", ["zoom_in", "zoom_out"]],
	["Pause", ["pause"]],
]
const JOY_NAMES: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

## Darken whatever is behind the panel (off when the host already dims).
var dim_background: bool = true
var is_open: bool = false

var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _tab: int = 0
var _scroll: ScrollContainer
var _back: Button
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if dim_background:
		var dim := ColorRect.new()
		dim.color = Color(0.03, 0.035, 0.04, 0.55)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(860, 0)
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.88), UITheme.RUST, 1, 6, 22))
	center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := UITheme.label("SETTINGS", 30, UITheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := UITheme.label("Q / E  switch tabs", 13, UITheme.MUTED)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	var group := ButtonGroup.new()
	for i: int in TABS.size():
		var b := Button.new()
		b.text = TABS[i].to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", UITheme.box(Color(0.2, 0.14, 0.05, 0.9), UITheme.GOLD, 1, 2, 8))
		b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
		b.add_theme_font_size_override("font_size", 15)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_show_tab(i))
		UITheme.juice(b, 1.02)
		tabs.add_child(b)
		_tab_buttons.append(b)
	var rule := ColorRect.new()
	rule.color = UITheme.RUST
	rule.custom_minimum_size = Vector2(0, 1)
	vb.add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 400)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	vb.add_child(_scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(stack)
	for i: int in TABS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 4)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(page)
		_pages.append(page)
	_build_audio(_pages[0])
	_build_graphics(_pages[1])
	_build_controls(_pages[2])
	_build_gameplay(_pages[3])

	var foot := HBoxContainer.new()
	vb.add_child(foot)
	var saved := UITheme.label("Changes are saved automatically.", 13, UITheme.MUTED)
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(saved)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(150, 44)
	_back.pressed.connect(close_panel)
	UITheme.juice(_back)
	foot.add_child(_back)
	_tab_buttons[0].button_pressed = true
	_show_tab(0)
	visible = false


# --- Open / close -------------------------------------------------------------------

func open_panel() -> void:
	is_open = true
	visible = true
	modulate.a = 0.0
	_panel.scale = Vector2(0.97, 0.97)
	_panel.pivot_offset = _panel.size * 0.5
	var tw: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22)
	_tab_buttons[_tab].call_deferred("grab_focus")


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	Settings.save_settings()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		var step: int = 1 if event.is_action_pressed("ui_tab_next") else -1
		var i: int = wrapi(_tab + step, 0, TABS.size())
		_tab_buttons[i].button_pressed = true
		_tab_buttons[i].grab_focus()
		get_viewport().set_input_as_handled()


func select_tab(i: int) -> void:
	_tab_buttons[clampi(i, 0, TABS.size() - 1)].button_pressed = true


func _show_tab(i: int) -> void:
	_tab = i
	for p: int in _pages.size():
		_pages[p].visible = p == i
	_scroll.scroll_vertical = 0
	_link_focus()


## Vertical focus chain: tabs -> rows of the visible page -> Back.
func _link_focus() -> void:
	var focusables: Array[Control] = []
	for c: Node in _pages[_tab].find_children("*", "Control", true, false):
		var ctl: Control = c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.has_meta("row_ctl"):
			focusables.append(ctl)
	var tab_btn: Button = _tab_buttons[_tab]
	var first: Control = focusables[0] if not focusables.is_empty() else _back
	var last: Control = focusables[-1] if not focusables.is_empty() else tab_btn
	for b: Button in _tab_buttons:
		b.focus_neighbor_bottom = b.get_path_to(first)
		b.focus_neighbor_top = b.get_path_to(_back)
	for k: int in focusables.size():
		var c: Control = focusables[k]
		c.focus_neighbor_top = c.get_path_to(tab_btn if k == 0 else focusables[k - 1])
		c.focus_neighbor_bottom = c.get_path_to(_back if k == focusables.size() - 1 else focusables[k + 1])
	_back.focus_neighbor_top = _back.get_path_to(last)
	_back.focus_neighbor_bottom = _back.get_path_to(tab_btn)


# --- Pages ----------------------------------------------------------------------------

func _build_audio(p: VBoxContainer) -> void:
	_section(p, "Volume")
	_slider(p, "Master", Settings.master_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.master_volume = v
		Audio.apply_volumes())
	_slider(p, "Music", Settings.music_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.music_volume = v
		Audio.apply_volumes())
	_slider(p, "Sound effects", Settings.sfx_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.sfx_volume = v
		Audio.apply_volumes()
		Audio.play("click", 1.0, -6.0))


func _build_graphics(p: VBoxContainer) -> void:
	_section(p, "Rendering")
	var hint: String = "Low drops GI and fog; Ultra adds reflections." if RenderingServer.get_current_rendering_method() == "forward_plus" \
		else "This renderer always uses the Low preset."
	_cycler(p, "Quality preset", ["Low", "Medium", "High", "Ultra"], Settings.quality, func(i: int) -> void:
		Settings.quality = i
		Settings.apply_quality_to_tree(get_tree().current_scene), hint)
	var scales: Array[float] = [0.5, 0.67, 0.75, 0.85, 1.0]
	var idx: int = 4
	for k: int in scales.size():
		if absf(scales[k] - Settings.render_scale) < 0.02:
			idx = k
	_cycler(p, "Render scale", ["50%", "67%", "75%", "85%", "100%"], idx, func(i: int) -> void:
		Settings.render_scale = scales[i]
		Settings.apply_display(), "Lower renders 3D at a smaller size; the interface stays sharp.")
	_section(p, "Display")
	_toggle(p, "Fullscreen", Settings.fullscreen, func(v: bool) -> void:
		Settings.fullscreen = v
		Settings.apply_display())
	_toggle(p, "V-Sync", Settings.vsync, func(v: bool) -> void:
		Settings.vsync = v
		Settings.apply_display())


func _build_controls(p: VBoxContainer) -> void:
	_section(p, "Camera")
	_slider(p, "Mouse sensitivity", Settings.mouse_sensitivity, 0.001, 0.008, 0.00025,
		func(v: float) -> String: return "x%.1f" % (v / 0.0035),
		func(v: float) -> void: Settings.mouse_sensitivity = v)
	_toggle(p, "Invert look Y", Settings.invert_y, func(v: bool) -> void: Settings.invert_y = v)
	_section(p, "Scooping")
	_cycler(p, "Scoop button", ["Hold", "Toggle"], 0 if Settings.hold_to_scoop else 1, func(i: int) -> void:
		Settings.hold_to_scoop = i == 0)
	_section(p, "Bindings")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 5)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_child(grid)
	p.add_child(m)
	for h: String in ["ACTION", "KEYBOARD / MOUSE", "CONTROLLER"]:
		grid.add_child(UITheme.label(h, 12, UITheme.MUTED))
	for entry: Array in BINDINGS:
		var name_l := UITheme.label(entry[0], 15)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		# Single action: every binding. Several actions (Move, Tools, Zoom): the primary binding
		# of each, so "W A S D" rather than every alternative.
		var actions: Array = entry[1]
		var multi: bool = actions.size() > 1
		var kb: Array[String] = []
		var pad: Array[String] = []
		for action: String in actions:
			if not InputMap.has_action(action):
				continue
			var got_kb: bool = false
			var got_pad: bool = false
			for ev: InputEvent in InputMap.action_get_events(action):
				var n: String = _event_name(ev)
				var is_pad: bool = ev is InputEventJoypadButton or ev is InputEventJoypadMotion
				if n == "" or (multi and (got_pad if is_pad else got_kb)):
					continue
				var target: Array[String] = pad if is_pad else kb
				if not target.has(n):
					target.append(n)
				if is_pad:
					got_pad = true
				else:
					got_kb = true
		var sep: String = " " if multi and kb.all(func(k: String) -> bool: return k.length() == 1) else " / "
		grid.add_child(UITheme.label(sep.join(kb), 15, UITheme.GOLD))
		grid.add_child(UITheme.label(" / ".join(pad), 15, UITheme.CREAM))


func _build_gameplay(p: VBoxContainer) -> void:
	_section(p, "Comfort")
	_toggle(p, "Screen shake", Settings.screen_shake, func(v: bool) -> void: Settings.screen_shake = v)
	_toggle(p, "Reduced motion", Settings.reduced_motion, func(v: bool) -> void: Settings.reduced_motion = v,
		"Calmer camera and fewer bouncy effects.")
	_section(p, "Interface")
	_cycler(p, "Number format", ["Short (1.2K)", "Scientific (1.2e3)", "Engineering (1.2e3)"], Settings.number_format,
		func(i: int) -> void: Settings.number_format = i)
	_toggle(p, "Best-value tags", Settings.best_value_tags, func(v: bool) -> void: Settings.best_value_tags = v,
		"Tag the affordable upgrade that gives the most per cube.")


# --- Row widgets ----------------------------------------------------------------------

func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


func _section(p: VBoxContainer, text: String) -> void:
	var l := UITheme.label(text.to_upper(), 12, UITheme.GOLD.darkened(0.1))
	if p.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		p.add_child(gap)
	p.add_child(l)


## A row: label (and optional hint) on the left, the control on the right. The row lights up
## while its control has focus.
func _row(p: VBoxContainer, text: String, ctl: Control, hint: String = "", focus_ctl: Control = null) -> void:
	var row := PanelContainer.new()
	var idle: StyleBoxFlat = UITheme.box(Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0, 4, 8)
	var lit: StyleBoxFlat = UITheme.box(Color(1, 0.7, 0.26, 0.08), Color(1, 0.7, 0.26, 0.35), 1, 4, 8)
	row.add_theme_stylebox_override("panel", idle)
	p.add_child(row)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	row.add_child(hb)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lv)
	lv.add_child(UITheme.label(text, 17))
	if hint != "":
		var h := UITheme.label(hint, 12, UITheme.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(h)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ctl)
	var f: Control = focus_ctl if focus_ctl else ctl
	f.set_meta("row_ctl", true)
	f.focus_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", lit))
	f.focus_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", idle))


func _value_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(ROW_W, 38)
	b.add_theme_font_size_override("font_size", 15)
	return b


## A value picker: press (or right) for next, left for previous. One focus stop per row.
func _cycler(p: VBoxContainer, text: String, options: Array, index: int, cb: Callable, hint: String = "") -> void:
	var b: Button = _value_button()
	var state: Array[int] = [clampi(index, 0, options.size() - 1)]
	var show: Callable = func() -> void: b.text = "‹   %s   ›" % options[state[0]]
	var step: Callable = func(d: int) -> void:
		state[0] = wrapi(state[0] + d, 0, options.size())
		show.call()
		cb.call(state[0])
		Settings.save_settings()
		Audio.play("click", 1.0 + 0.05 * d, -8.0)
	show.call()
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event())
	_row(p, text, b, hint)


func _toggle(p: VBoxContainer, text: String, value: bool, cb: Callable, hint: String = "") -> void:
	var b: Button = _value_button()
	b.toggle_mode = true
	b.button_pressed = value
	var on_box: StyleBoxFlat = UITheme.box(Color(0.22, 0.15, 0.05, 0.92), UITheme.GOLD, 1, 2, 8)
	b.add_theme_stylebox_override("pressed", on_box)
	b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
	var show: Callable = func(v: bool) -> void: b.text = "On" if v else "Off"
	show.call(value)
	b.toggled.connect(func(v: bool) -> void:
		show.call(v)
		cb.call(v)
		Settings.save_settings()
		Audio.play("click", 1.1 if v else 0.9, -8.0))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			b.button_pressed = e.is_action_pressed("ui_right")
			b.accept_event())
	_row(p, text, b, hint)


func _slider(p: VBoxContainer, text: String, value: float, lo: float, hi: float, step: float, fmt: Callable, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(ROW_W, 38)
	hb.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 30)
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hb.add_child(s)
	var val := UITheme.label(fmt.call(value), 15, UITheme.GOLD)
	val.custom_minimum_size = Vector2(52, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		cb.call(v)
		Settings.save_settings())
	_row(p, text, hb, "", s)


func _event_name(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: InputEventKey = ev as InputEventKey
		var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_MIDDLE: return "MMB"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
		return "Mouse"
	if ev is InputEventJoypadButton:
		return str(JOY_NAMES.get((ev as InputEventJoypadButton).button_index, "Button"))
	if ev is InputEventJoypadMotion:
		match (ev as InputEventJoypadMotion).axis:
			JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y: return "Left stick"
			JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y: return "Right stick"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
	return ""
