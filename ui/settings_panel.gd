class_name SettingsPanel
extends Control
## Reusable settings screen (title menu and pause menu). [ui2] Opens on Basics (volume, quality,
## fullscreen, sensitivity, language); "More settings" reveals the full tabs: Audio, Graphics,
## Controls, Gameplay, Accessibility. Controls holds key / controller rebinding (stored by Settings).
## Every change is applied immediately and written with Settings.save_settings().
## Controller: up/down moves between rows, left/right changes a value, Q/E or the shoulders switch
## tabs, B / Esc closes.

signal closed

const TABS: Array[String] = ["Basics", "Audio", "Graphics", "Controls", "Gameplay", "Accessibility"]  # l10n
const ROW_W: float = 300.0
const BIND_W: float = 190.0
## Seconds a rebind capture waits before giving up (pad-only players have no Esc).
const CAPTURE_TIMEOUT: float = 8.0
const UI_SCALES: Array[float] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.4, 1.5]

## Darken whatever is behind the panel (off when the host already dims).
var dim_background: bool = true
var is_open: bool = false

var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []
var _tab: int = 0
var _scroll: ScrollContainer
var _back: Button
var _panel: PanelContainer
## action -> [keyboard Button, pad Button]
var _bind_buttons: Dictionary = {}
var _bind_warning: Label
var _capture_action: String = ""
var _capture_pad: bool = false
var _capture_t: float = 0.0
## [ui2] The full tabs (everything but Basics) show once "More settings" is pressed.
var _more: bool = false
var _tabs_hint: Control
var _back_hint: Control


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
	_panel.add_theme_stylebox_override("panel", BenchKit.holo(Color(BenchKit.HOLO, 0.5), Color(0.02, 0.035, 0.045, 0.9), 1.0, 12, 22))  # [ui2] holo
	center.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := UITheme.label(tr("SETTINGS"), 28, BenchKit.HOLO)  # [ui2]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := PromptLabel.new(tr("{ui_tab_prev}{ui_tab_next}  switch tabs     {ui_cancel}  back"), 13)  # [deck]
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	_tabs_hint = hint
	_back_hint = PromptLabel.new(tr("{ui_cancel}  back"), 13)  # [ui5] Basics has one tab: no "switch tabs"
	_back_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_back_hint)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	_tabs_row = tabs  # [v1menu]
	var group := ButtonGroup.new()
	for i: int in TABS.size():
		var b := Button.new()
		b.text = tr(TABS[i]).to_upper()
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
	_build_all()

	var foot := HBoxContainer.new()
	vb.add_child(foot)
	var saved := UITheme.label(tr("Changes are saved automatically."), 13, UITheme.MUTED)
	saved.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(saved)
	_back = Button.new()
	_back.text = tr("Back")
	_back.custom_minimum_size = Vector2(150, 44)
	_back.pressed.connect(close_panel)
	UITheme.juice(_back)
	foot.add_child(_back)
	_tab_buttons[0].button_pressed = true
	_show_tab(0)
	_set_more(false)
	visible = false
	_fit()
	get_viewport().size_changed.connect(_fit)


## [l10n] Rebuilds the pages after a language change so every row shows the new language, and
## puts focus back on the language picker.
func _relocalize() -> void:
	_end_capture()
	_bind_buttons.clear()
	for page: VBoxContainer in _pages:
		for c: Node in page.get_children():
			page.remove_child(c)
			c.queue_free()
	_build_all()
	for i: int in TABS.size():
		_tab_buttons[i].text = tr(TABS[i]).to_upper()
	_back.text = tr("Back")
	_show_tab(_tab)
	for c: Node in _pages[_tab].find_children("*", "Button", true, false):
		if (c as Control).has_meta("row_ctl"):
			(c as Control).grab_focus()
			break


## Keeps the panel inside the visible area at large UI scales.
func _fit() -> void:
	var vs: Vector2 = get_viewport_rect().size
	_panel.custom_minimum_size.x = minf(860.0, vs.x - 24.0)
	_scroll.custom_minimum_size.y = clampf(vs.y - 240.0, 220.0, 470.0)  # [ui5] tall enough for every Basics row at 720 p


# --- Open / close -------------------------------------------------------------------

func open_panel() -> void:
	is_open = true
	visible = true
	if _tab == 0:
		_set_more(false)  # [ui2] start simple; the full tabs stay open if you were in one
	modulate.a = 0.0
	_panel.scale = Vector2(0.97, 0.97)
	_panel.pivot_offset = _panel.size * 0.5
	var tw: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22)
	_first_focus().call_deferred("grab_focus")  # [v6screens] Basics alone hides the tab row: focus its first row


## [v6screens] Where the focus starts: the tab, or on Basics alone (no tab row) its first row.
func _first_focus() -> Control:
	if _more:
		return _tab_buttons[_tab]
	for c: Node in _pages[_tab].find_children("*", "Control", true, false):
		var ctl: Control = c as Control
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.has_meta("row_ctl") and ctl.is_visible_in_tree():
			return ctl
	return _back


func close_panel() -> void:
	if not is_open:
		return
	_end_capture()
	is_open = false
	_apply_quality_now()  # [v1menu]
	Settings.save_settings()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_panel()
		get_viewport().set_input_as_handled()
	elif _more and (event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev")):  # [v6screens] Basics alone has no tab row to switch
		var step: int = 1 if event.is_action_pressed("ui_tab_next") else -1
		var i: int = wrapi(_tab + step, 0, TABS.size())
		_tab_buttons[i].button_pressed = true
		_tab_buttons[i].grab_focus()
		get_viewport().set_input_as_handled()


func select_tab(i: int) -> void:
	if i > 0:
		_set_more(true)
	_tab_buttons[clampi(i, 0, TABS.size() - 1)].button_pressed = true


func _build_all() -> void:
	_build_basics(_pages[0])
	_build_audio(_pages[1])
	_build_graphics(_pages[2])
	_build_controls(_pages[3])
	_build_gameplay(_pages[4])
	_build_access(_pages[5])


## [ui2] Shows or hides the full tabs; Basics is always there.
func _set_more(on: bool) -> void:
	_more = on
	for i: int in range(1, _tab_buttons.size()):
		_tab_buttons[i].visible = on
	_tab_buttons[0].visible = true
	if _tabs_row:  # [v1menu] only Basics: no lone "BASICS" tab header
		_tabs_row.visible = on
		_link_focus()
	if _tabs_hint:
		_tabs_hint.visible = on
		_back_hint.visible = not on


## [v6screens] The languages a player can pick: Settings.LANGUAGES without the translators' test
## language (still there with --locale=pseudo, or when it is the saved choice).
static func picker_languages() -> Array:
	return Settings.LANGUAGES.filter(func(l: Array) -> bool:
		return str(l[0]) != "pseudo" or Settings.language == "pseudo" or Settings.locale_override == "pseudo")


## [ui2] The few settings most players want, then a way to everything else.
func _build_basics(p: VBoxContainer) -> void:
	# [ui5] No "Basics" caption (the tab says it), so the last row fits above the footer.
	_slider(p, "Master", Settings.master_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.master_volume = v
		Audio.apply_volumes())
	_slider(p, "Music", Settings.music_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.music_volume = v
		Audio.apply_volumes())
	_cycler(p, tr("Quality preset"), [tr("Low"), tr("Medium"), tr("High"), tr("Ultra")], Settings.quality, _queue_quality)
	_toggle(p, tr("Fullscreen"), Settings.fullscreen, func(v: bool) -> void:
		Settings.fullscreen = v
		Settings.apply_display())
	_slider(p, tr("Mouse sensitivity"), Settings.mouse_sensitivity, 0.001, 0.008, 0.00025,
		func(v: float) -> String: return "x%.1f" % (v / 0.0035),
		func(v: float) -> void: Settings.mouse_sensitivity = v)
	var langs: Array = picker_languages()  # [v6screens] no "Pseudo (test)" for players
	var codes: Array = langs.map(func(l: Array) -> String: return str(l[0]))
	var names: Array = langs.map(func(l: Array) -> String: return tr("System default") if str(l[0]) == "" else str(l[1]))
	_cycler(p, tr("Language"), names, maxi(0, codes.find(Settings.language)), func(i: int) -> void:
		Settings.language = codes[i]
		Settings.apply_language()
		_relocalize.call_deferred())
	var more := Button.new()
	more.text = tr("More settings  (sound, graphics, controls, accessibility)")
	more.custom_minimum_size = Vector2(0, 44)
	more.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # [v6screens] long in some languages
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more.pressed.connect(func() -> void:
		_set_more(true)
		select_tab(1)
		_tab_buttons[1].grab_focus.call_deferred())
	_row(p, tr("Everything else"), more)


func _show_tab(i: int) -> void:
	if i != _tab and _pages.size() == TABS.size() and i != 3:  # [ui2] fresh values (Basics shares rows with the other tabs); Controls keeps its capture state
		for c: Node in _pages[i].get_children():
			_pages[i].remove_child(c)
			c.queue_free()
		[_build_basics, _build_audio, _build_graphics, _build_controls, _build_gameplay, _build_access][i].call(_pages[i])
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
	var tab_btn: Control = _tab_buttons[_tab] if _more else _back  # [v1menu] the tab row is hidden on Basics alone
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
	_back.focus_neighbor_bottom = _back.get_path_to(tab_btn if _more else first)


# --- Pages ----------------------------------------------------------------------------

func _build_audio(p: VBoxContainer) -> void:
	_section(p, tr("Volume"))
	_slider(p, "Master", Settings.master_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.master_volume = v
		Audio.apply_volumes())
	_slider(p, "Music", Settings.music_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.music_volume = v
		Audio.apply_volumes())
	_slider(p, tr("Ambience"), Settings.ambience_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:  # [v6sound]
		Settings.ambience_volume = v
		Audio.apply_volumes())
	_slider(p, tr("Sound effects"), Settings.sfx_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:
		Settings.sfx_volume = v
		Audio.apply_volumes()
		Audio.play("pop", 1.0, -6.0))
	_slider(p, tr("Interface"), Settings.ui_volume, 0.0, 1.0, 0.05, _pct, func(v: float) -> void:  # [v6sound]
		Settings.ui_volume = v
		Audio.apply_volumes()
		Audio.play("click", 1.0, -6.0))


func _build_graphics(p: VBoxContainer) -> void:
	_section(p, tr("Rendering"))
	var hint: String = tr("Low drops GI and fog; Ultra adds reflections.") if RenderingServer.get_current_rendering_method() == "forward_plus" \
		else tr("This renderer always uses the Low preset.")
	if Settings.quality_note != "":  # [deck] auto-detected preset
		hint = (tr("Detected: %s for %s. ") % [QualityDetect.preset_name(Settings.quality), Settings.quality_note]) if Settings.quality_auto \
			else (tr("Your choice (hardware: %s). ") % Settings.quality_note)
		hint += tr("Low drops GI, fog and shadows detail; Ultra adds reflections.")
	_cycler(p, tr("Quality preset"), [tr("Low"), tr("Medium"), tr("High"), tr("Ultra")], Settings.quality, _queue_quality, hint)  # [deck] a manual choice turns auto-detection off
	# [deck] Renderer: Mobile is lighter on old integrated GPUs (always the Low look). Restart needed.
	var methods: Array[String] = ["forward_plus", "mobile"]
	var cur_m: int = 1 if Settings.renderer_override() == "mobile" else 0
	var running: String = RenderingServer.get_current_rendering_method()
	_cycler(p, tr("Renderer"), [tr("Standard (Forward+)"), tr("Light (Mobile)")], cur_m, func(i: int) -> void:
		Settings.set_renderer_override(methods[i]),
		tr("Light suits older integrated graphics. Takes effect after restarting the game (now: %s).") % running.capitalize().replace("_", " "))
	var scales: Array[float] = [0.5, 0.67, 0.75, 0.85, 1.0]
	var idx: int = 4
	for k: int in scales.size():
		if absf(scales[k] - Settings.render_scale) < 0.02:
			idx = k
	_cycler(p, tr("Render scale"), ["50%", "67%", "75%", "85%", "100%"], idx, func(i: int) -> void:
		Settings.render_scale = scales[i]
		Settings.apply_display(), tr("Lower renders 3D at a smaller size; the interface stays sharp."))
	_section(p, tr("Display"))
	_toggle(p, tr("Fullscreen"), Settings.fullscreen, func(v: bool) -> void:
		Settings.fullscreen = v
		Settings.apply_display())
	_toggle(p, tr("V-Sync"), Settings.vsync, func(v: bool) -> void:
		Settings.vsync = v
		Settings.apply_display())


func _build_controls(p: VBoxContainer) -> void:
	_section(p, tr("Bindings"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var h0 := UITheme.label(tr("ACTION   (select a binding to rebind it)"), 12, UITheme.MUTED)
	h0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h0)
	for t: String in [tr("KEYBOARD / MOUSE"), tr("CONTROLLER")]:
		var h := UITheme.label(t, 12, UITheme.MUTED)
		h.custom_minimum_size = Vector2(BIND_W, 0)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(h)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 8)
	hm.add_theme_constant_override("margin_right", 8)
	hm.add_child(head)
	p.add_child(hm)
	for e: Array in Settings.REBINDABLE:
		_binding_row(p, e[0], tr(e[1]))
	_bind_warning = UITheme.label("", 13, Color(1.0, 0.45, 0.35))
	_bind_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(_bind_warning)
	var reset := _value_button()
	reset.text = tr("Reset to defaults")
	reset.pressed.connect(func() -> void:
		_end_capture()
		Settings.reset_bindings()
		Settings.save_settings()
		_refresh_bindings()
		Audio.play("click", 0.9, -8.0))
	_row(p, tr("Bindings"), reset, tr("Restore every key and controller binding."))
	_refresh_bindings()
	_cycler(p, tr("Button prompts"), PadGlyphs.STYLE_NAMES, Settings.glyph_style, func(i: int) -> void:  # [deck]
		Settings.glyph_style = i
		_refresh_bindings(), tr("Controller art: Automatic follows the connected pad."))
	_section(p, tr("Camera"))
	_slider(p, tr("Mouse sensitivity"), Settings.mouse_sensitivity, 0.001, 0.008, 0.00025,
		func(v: float) -> String: return "x%.1f" % (v / 0.0035),
		func(v: float) -> void: Settings.mouse_sensitivity = v)
	_slider(p, tr("Stick look speed"), Settings.stick_sensitivity, 0.5, 2.0, 0.1,  # [deck]
		func(v: float) -> String: return "x%.1f" % v,
		func(v: float) -> void: Settings.stick_sensitivity = v)
	_toggle(p, tr("Invert look Y"), Settings.invert_y, func(v: bool) -> void: Settings.invert_y = v)
	_slider(p, tr("Field of view"), Settings.fov, 50.0, 90.0, 1.0,
		func(v: float) -> String: return "%d°" % roundi(v),
		func(v: float) -> void: Settings.fov = v)
	_toggle(p, tr("Mouse smoothing"), Settings.mouse_smoothing, func(v: bool) -> void: Settings.mouse_smoothing = v,
		tr("Eases mouse look over a few frames."))
	_section(p, tr("Scooping"))
	_cycler(p, tr("Scoop button"), [tr("Hold"), tr("Toggle")], 0 if Settings.hold_to_scoop else 1, func(i: int) -> void:
		Settings.hold_to_scoop = i == 0)


func _binding_row(p: VBoxContainer, action: String, title: String) -> void:
	var row := PanelContainer.new()
	var idle: StyleBoxFlat = UITheme.box(Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0, 4, 6)
	var lit: StyleBoxFlat = UITheme.box(Color(1, 0.7, 0.26, 0.08), Color(1, 0.7, 0.26, 0.35), 1, 4, 6)
	row.add_theme_stylebox_override("panel", idle)
	p.add_child(row)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	var l := UITheme.label(title, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	var btns: Array[Button] = []
	for pad: bool in [false, true]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(BIND_W, 32)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_begin_capture.bind(action, pad))
		b.focus_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", lit))
		b.focus_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", idle))
		hb.add_child(b)
		btns.append(b)
	btns[0].set_meta("row_ctl", true)
	btns[0].focus_neighbor_right = btns[0].get_path_to(btns[1])
	btns[1].focus_neighbor_left = btns[1].get_path_to(btns[0])
	_bind_buttons[action] = btns


func _refresh_bindings() -> void:
	var conf: Dictionary = Settings.conflicts()
	for action: String in _bind_buttons:
		var btns: Array = _bind_buttons[action]
		for k: int in 2:
			var b: Button = btns[k]
			var pad: bool = k == 1
			if action == _capture_action and pad == _capture_pad:
				b.text = tr("press a button…") if pad else tr("press a key…")
				b.add_theme_color_override("font_color", UITheme.GOLD)
				continue
			var ev: InputEvent = Settings.binding(action, pad)
			b.text = (PadGlyphs.event_name(ev) if pad else Settings.event_label(ev)) if ev else "—"  # [deck]
			# Alternatives (e.g. arrow keys next to WASD) in the tooltip.
			var alts: Array[String] = []
			for o: InputEvent in InputMap.action_get_events(action):
				if Settings.is_pad_event(o) == pad and o != ev:
					alts.append(Settings.event_label(o))
			b.tooltip_text = ("Also: " + ", ".join(alts)) if not alts.is_empty() else ""
			var clash: bool = false
			for other: String in conf.get(action, []):
				for o: InputEvent in InputMap.action_get_events(action):
					if Settings.is_pad_event(o) == pad and Settings.find_conflict(action, o) == other:
						clash = true
			var col: Color = Color(1.0, 0.45, 0.35) if clash else (UITheme.GOLD if Settings.is_rebound(action) else UITheme.CREAM)
			b.add_theme_color_override("font_color", col)
	if _bind_warning:
		var lines: Array[String] = []
		var seen: Dictionary = {}
		for action: String in conf:
			for other: String in conf[action]:
				var key: String = "|".join([action, other] if action < other else [other, action])
				if seen.has(key):
					continue
				seen[key] = true
				var shared: String = ""
				for o: InputEvent in InputMap.action_get_events(action):
					if Settings.find_conflict(action, o) == other:
						shared = Settings.event_label(o)
						break
				lines.append(tr("Conflict: %s is used by both %s and %s.") % [shared, Settings.display_name(action), Settings.display_name(other)])
		_bind_warning.text = "\n".join(lines)
		_bind_warning.visible = not lines.is_empty()


func _begin_capture(action: String, pad: bool) -> void:
	_capture_action = action
	_capture_pad = pad
	_capture_t = 0.0
	_refresh_bindings()
	Audio.play("click", 1.1, -8.0)


func _end_capture() -> void:
	if _capture_action == "":
		return
	_capture_action = ""
	_refresh_bindings()


func _process(delta: float) -> void:
	if _capture_action == "":
		return
	_capture_t += delta
	if _capture_t > CAPTURE_TIMEOUT:
		_end_capture()


## Rebind capture: grabs the next key / mouse button (keyboard slot) or pad button / stick /
## trigger (controller slot) before the GUI sees it. Esc cancels.
func _input(event: InputEvent) -> void:
	if _capture_action == "" or not is_open:
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		if event.is_pressed():
			_end_capture()
		get_viewport().set_input_as_handled()
		return
	if _capture_t < 0.15 or event is InputEventMouseMotion:
		return
	var got: InputEvent = null
	if _capture_pad:
		if event is InputEventJoypadButton and event.is_pressed():
			var j := InputEventJoypadButton.new()
			j.button_index = (event as InputEventJoypadButton).button_index
			got = j
		elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
			var m := InputEventJoypadMotion.new()
			m.axis = (event as InputEventJoypadMotion).axis
			m.axis_value = signf((event as InputEventJoypadMotion).axis_value)
			got = m
		elif (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
			_end_capture()  # keyboard / mouse while waiting for a pad button: cancel
			get_viewport().set_input_as_handled()
			return
	else:
		if event is InputEventKey and event.is_pressed() and not (event as InputEventKey).echo:
			var k := InputEventKey.new()
			var src: InputEventKey = event
			k.physical_keycode = src.physical_keycode if src.physical_keycode != KEY_NONE else src.keycode
			got = k
		elif event is InputEventMouseButton and event.is_pressed():
			var mb := InputEventMouseButton.new()
			mb.button_index = (event as InputEventMouseButton).button_index
			got = mb
	if got == null:
		if Settings.is_pad_event(event) != _capture_pad or event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	var action: String = _capture_action
	var btn: Button = _bind_buttons[action][1 if _capture_pad else 0]
	_capture_action = ""
	apply_binding(action, got)
	btn.grab_focus()


## Binds `ev` to `action` (primary binding of its kind), saves, and refreshes the rows; any
## clash with another gameplay action is shown as a warning.
func apply_binding(action: String, ev: InputEvent) -> void:
	Settings.set_binding(action, ev)
	Settings.save_settings()
	_refresh_bindings()
	Audio.play("click", 1.2, -8.0)


func _build_gameplay(p: VBoxContainer) -> void:
	# [l10n] Language picker: System default, English, sample languages, Pseudo (test).
	_section(p, tr("Language"))
	var langs: Array = picker_languages()  # [v6screens] no "Pseudo (test)" for players
	var codes: Array = langs.map(func(l: Array) -> String: return str(l[0]))
	var names: Array = langs.map(func(l: Array) -> String: return tr("System default") if str(l[0]) == "" else str(l[1]))
	_cycler(p, tr("Language"), names, maxi(0, codes.find(Settings.language)), func(i: int) -> void:
		Settings.language = codes[i]
		Settings.apply_language()
		_relocalize.call_deferred())  # [v6screens] the hint named the test language, which players no longer see
	_section(p, tr("Comfort"))
	_slider(p, tr("Camera shake"), Settings.shake_intensity, 0.0, 1.0, 0.05, _pct,
		func(v: float) -> void: Settings.shake_intensity = v)
	_toggle(p, tr("Reduced motion"), Settings.reduced_motion, func(v: bool) -> void: Settings.reduced_motion = v,
		tr("Calmer camera and fewer bouncy effects."))
	_section(p, tr("Interface"))
	# [v6screens] No "Number format" (the HUD, the workbench and the map never used it) and no
	# "Best-value tags" (the workbench lists have no upgrade cards to tag): options that did nothing.
	_cycler(p, tr("HUD"), [tr("Full"), tr("Minimal"), tr("Hidden")], Settings.hud_mode, func(i: int) -> void:  # [hud]
		Settings.hud_mode = i, tr("Minimal fades extras after a few seconds. Hidden keeps only prompts and messages."))


func _build_access(p: VBoxContainer) -> void:
	_section(p, tr("Interface"))
	var idx: int = 2
	for k: int in UI_SCALES.size():
		if absf(UI_SCALES[k] - Settings.ui_scale) < 0.02:
			idx = k
	var names: Array = UI_SCALES.map(func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_cycler(p, tr("Interface scale"), names, idx, func(i: int) -> void:
		Settings.ui_scale = UI_SCALES[i]
		Settings.apply_ui_scale(), tr("Size of menus, HUD and subtitles."))
	_toggle(p, tr("Colour-blind palette"), Settings.colorblind, func(v: bool) -> void: Settings.colorblind = v,
		tr("Okabe-Ito colours for hex progress, the hopper meter and part rarity."))
	_section(p, tr("Subtitles"))
	_toggle(p, tr("Subtitles"), Settings.subtitles_enabled, func(v: bool) -> void: Settings.subtitles_enabled = v,
		tr("WREN and Ledger lines."))
	_cycler(p, tr("Subtitle size"), [tr("Small"), tr("Medium"), tr("Large")], Settings.subtitle_size, func(i: int) -> void:
		Settings.subtitle_size = i)
	_toggle(p, tr("Subtitle background"), Settings.subtitle_background, func(v: bool) -> void: Settings.subtitle_background = v,
		tr("A solid backdrop behind subtitle text."))


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
	var tl: Label = UITheme.label(text, 17)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # [v6screens] long names wrap instead of pushing the panel off a small screen
	lv.add_child(tl)
	if hint != "":
		var h := UITheme.label(hint, 12, UITheme.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(h)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ctl)
	var f: Control = focus_ctl if focus_ctl else ctl
	f.set_meta("row_ctl", true)
	f.set_meta("own_focus_ring", true)  # [v6screens] the whole row lights up (tools/ui_audit.gd)
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
	var show_: Callable = func() -> void: b.text = "‹   %s   ›" % options[state[0]]
	var step: Callable = func(d: int) -> void:
		state[0] = wrapi(state[0] + d, 0, options.size())
		show_.call()
		cb.call(state[0])
		Settings.save_settings()
		Audio.play("click", 1.0 + 0.05 * d, -8.0)
	show_.call()
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
	var show_: Callable = func(v: bool) -> void: b.text = tr("On") if v else tr("Off")
	show_.call(value)
	b.toggled.connect(func(v: bool) -> void:
		show_.call(v)
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


# --- [v1menu] Quality preset changes, applied once the player stops cycling ----------------
# Each preset change makes the renderer rebuild GPU pipelines (MSAA, TAA, SDFGI, shadow filter),
# a stall of up to seconds on a cold driver cache. Cycling Low -> Ultra used to pay it on every
# click; now the label changes at once and the preset applies QUALITY_SETTLE_S after the last click.

const QUALITY_SETTLE_S: float = 0.45
var _quality_timer: Timer
var _tabs_row: HBoxContainer
var _quality_applied: int = -1


func _queue_quality(i: int) -> void:
	if _quality_applied < 0:
		_quality_applied = Settings.quality
	Settings.set_quality_manual(i)
	if _quality_timer == null:
		_quality_timer = Timer.new()
		_quality_timer.one_shot = true
		_quality_timer.process_mode = Node.PROCESS_MODE_ALWAYS  # the pause menu pauses the tree
		_quality_timer.timeout.connect(_apply_quality_now)
		add_child(_quality_timer)
	_quality_timer.start(QUALITY_SETTLE_S)


func _apply_quality_now() -> void:
	if _quality_timer:
		_quality_timer.stop()
	if _quality_applied < 0 or Settings.quality == _quality_applied:
		_quality_applied = -1
		return
	_quality_applied = -1
	Settings.apply_quality_to_tree(get_tree().current_scene)
