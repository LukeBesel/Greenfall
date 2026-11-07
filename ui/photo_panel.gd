class_name PhotoPanel
extends Control
## [photo] Photo mode side panel: a slim, collapsible column of sections (Camera, Lens, Look,
## World, Lumi, Frame) in the UITheme style. Every row is one focus stop, so the D-pad / stick
## walks the column; left/right changes the focused value. Values live on the owner (PhotoMode):
## the panel reads them with get_value(key) and writes them with set_value(key, value).

signal capture_pressed
signal close_pressed
signal collapsed_changed(collapsed: bool)

const W: float = 336.0
const ROW_H: float = 34.0

var owner_mode: Node  # PhotoMode: get_value(key) / set_value(key, v)
var collapsed: bool = false
var _panel: PanelContainer
var _tab: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _rows: Dictionary = {}   # key -> {"kind", "ctl", "val", "opts"}
var _sections: Dictionary = {}  # name -> [header Button, VBox]
var _first: Control
var _capture: Button
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.get_theme()
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.045, 0.05, 0.055, 0.82), Color(1, 1, 1, 0.1), 1, 6, 0))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -W - 16.0
	_panel.offset_right = -16.0
	_panel.offset_top = 16.0
	_panel.offset_bottom = -16.0
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_panel.add_child(outer)
	var strip := UITheme.hazard_strip(5)
	outer.add_child(strip)
	var head := MarginContainer.new()
	for s: String in ["margin_left", "margin_right"]:
		head.add_theme_constant_override(s, 14)
	head.add_theme_constant_override("margin_top", 10)
	head.add_theme_constant_override("margin_bottom", 6)
	outer.add_child(head)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(UITheme.label(tr("CAPTURE  ·  LM-1 LENS"), 11, Color(0.4, 0.75, 1.0)))
	var title := UITheme.label(tr("PHOTO MODE"), 22, Color.WHITE)
	hv.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	outer.add_child(_scroll)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s: String in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(s, 10)
	mc.add_theme_constant_override("margin_bottom", 6)
	_scroll.add_child(mc)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 3)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(_body)
	var foot := MarginContainer.new()
	for s: String in ["margin_left", "margin_right"]:
		foot.add_theme_constant_override(s, 12)
	foot.add_theme_constant_override("margin_top", 8)
	foot.add_theme_constant_override("margin_bottom", 10)
	outer.add_child(foot)
	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 6)
	foot.add_child(fv)
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 6)
	fv.add_child(fh)
	_capture = Button.new()
	_capture.text = tr("Capture")
	_capture.custom_minimum_size = Vector2(0, 42)
	_capture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capture.add_theme_font_size_override("font_size", 17)
	UITheme.orange_button(_capture)
	_capture.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color.WHITE, 2, 5, 8))
	_capture.pressed.connect(func() -> void: capture_pressed.emit())
	fh.add_child(_capture)
	var close := Button.new()
	close.text = tr("Exit")
	close.custom_minimum_size = Vector2(84, 42)
	close.pressed.connect(func() -> void: close_pressed.emit())
	fh.add_child(close)
	_hint = UITheme.label("", 11, UITheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fv.add_child(_hint)
	# Collapsed tab (shown instead of the panel).
	_tab = PanelContainer.new()
	_tab.add_theme_stylebox_override("panel", UITheme.box(Color(0.045, 0.05, 0.055, 0.75), Color(1, 1, 1, 0.1), 1, 5, 8))
	_tab.anchor_left = 1.0
	_tab.anchor_right = 1.0
	_tab.offset_left = -190.0
	_tab.offset_right = -16.0
	_tab.offset_top = 16.0
	_tab.offset_bottom = 52.0
	_tab.mouse_filter = Control.MOUSE_FILTER_STOP
	_tab.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			set_collapsed(false))
	_tab.visible = false
	add_child(_tab)
	_tab.add_child(UITheme.label("", 13, UITheme.CREAM))
	Settings.input_device_changed.connect(func(_p: bool) -> void: _update_hints())


## --- Building -------------------------------------------------------------------------------

func section(name: String, open: bool = true) -> VBoxContainer:
	var hb := Button.new()
	hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.custom_minimum_size = Vector2(0, 30)
	hb.add_theme_font_size_override("font_size", 13)
	hb.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 1, 0.0), Color(0, 0, 0, 0), 0, 3, 6))
	hb.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 3, 6))
	hb.add_theme_stylebox_override("focus", UITheme.box(Color(1, 0.7, 0.26, 0.08), UITheme.GOLD, 1, 3, 6))
	hb.add_theme_color_override("font_color", UITheme.GOLD)
	_body.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_body.add_child(vb)
	_sections[name] = [hb, vb]
	var show: Callable = func() -> void: hb.text = ("▾  " if vb.visible else "▸  ") + name.to_upper()
	vb.visible = open
	show.call()
	hb.pressed.connect(func() -> void:
		vb.visible = not vb.visible
		show.call()
		Audio.play("click", 1.0, -10.0))
	if _first == null:
		_first = hb
	return vb


func open_section(name: String, open: bool) -> void:
	if _sections.has(name):
		var vb: VBoxContainer = _sections[name][1]
		vb.visible = open
		var hb: Button = _sections[name][0]
		hb.text = ("▾  " if open else "▸  ") + name.to_upper()


func _row(p: VBoxContainer, text: String, ctl: Control, focus_ctl: Control = null) -> void:
	var row := PanelContainer.new()
	var idle: StyleBoxFlat = UITheme.box(Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0, 4, 5)
	var lit: StyleBoxFlat = UITheme.box(Color(1, 0.7, 0.26, 0.08), Color(1, 0.7, 0.26, 0.35), 1, 4, 5)
	idle.content_margin_left = 9
	lit.content_margin_left = 9
	row.add_theme_stylebox_override("panel", idle)
	p.add_child(row)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)
	var l := UITheme.label(text, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(104, 0)
	hb.add_child(l)
	ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ctl)
	var f: Control = focus_ctl if focus_ctl else ctl
	f.focus_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", lit))
	f.focus_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", idle))


func slider(p: VBoxContainer, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(176, ROW_H)
	hb.add_theme_constant_override("separation", 6)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(owner_mode.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 26)
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hb.add_child(s)
	var val := UITheme.label(fmt.call(s.value), 13, UITheme.GOLD)
	val.custom_minimum_size = Vector2(46, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(val)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		owner_mode.set_value(key, v))
	_rows[key] = {"kind": "slider", "ctl": s, "val": val, "fmt": fmt}
	_row(p, text, hb, s)


func cycler(p: VBoxContainer, text: String, key: String, options: Array) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, ROW_H)
	b.add_theme_font_size_override("font_size", 13)
	b.clip_text = true
	var show: Callable = func() -> void: b.text = "‹  %s  ›" % tr(str(options[clampi(int(owner_mode.get_value(key)), 0, options.size() - 1)]))
	var step: Callable = func(d: int) -> void:
		owner_mode.set_value(key, wrapi(int(owner_mode.get_value(key)) + d, 0, options.size()))
		show.call()
		Audio.play("click", 1.0 + 0.05 * d, -10.0)
	show.call()
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event()
		elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			step.call(-1)
			b.accept_event())
	_rows[key] = {"kind": "cycler", "ctl": b, "show": show}
	_row(p, text, b)


func toggle(p: VBoxContainer, text: String, key: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(176, ROW_H)
	b.add_theme_font_size_override("font_size", 13)
	b.toggle_mode = true
	b.button_pressed = bool(owner_mode.get_value(key))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(0.22, 0.15, 0.05, 0.92), UITheme.GOLD, 1, 2, 8))
	b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
	b.text = tr("On") if b.button_pressed else tr("Off")
	b.toggled.connect(func(v: bool) -> void:
		b.text = tr("On") if v else tr("Off")
		owner_mode.set_value(key, v)
		Audio.play("click", 1.1 if v else 0.9, -10.0))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
			b.button_pressed = e.is_action_pressed("ui_right")
			b.accept_event())
	_rows[key] = {"kind": "toggle", "ctl": b}
	_row(p, text, b)


func action(p: VBoxContainer, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -10.0)
		cb.call())
	p.add_child(b)


## Re-read one value (or all) from the owner without firing change callbacks.
func refresh(key: String = "") -> void:
	for k: String in _rows:
		if key != "" and k != key:
			continue
		var r: Dictionary = _rows[k]
		match str(r["kind"]):
			"slider":
				var s: HSlider = r["ctl"]
				s.set_value_no_signal(float(owner_mode.get_value(k)))
				(r["val"] as Label).text = (r["fmt"] as Callable).call(s.value)
			"cycler":
				(r["show"] as Callable).call()
			"toggle":
				var b: Button = r["ctl"]
				b.set_pressed_no_signal(bool(owner_mode.get_value(k)))
				b.text = tr("On") if b.button_pressed else tr("Off")


func set_collapsed(c: bool) -> void:
	collapsed = c
	_panel.visible = not c
	_tab.visible = c
	if c:
		var f: Control = get_viewport().gui_get_focus_owner()
		if f:
			f.release_focus()
	else:
		focus_first()
	_update_hints()
	collapsed_changed.emit(c)


func focus_first() -> void:
	if _first and _panel.visible and is_inside_tree():
		_first.call_deferred("grab_focus")


## True when the mouse is over the panel (camera drags start only outside it).
func covers(pos: Vector2) -> bool:
	return (_panel.visible and _panel.get_global_rect().has_point(pos)) or (_tab.visible and _tab.get_global_rect().has_point(pos))


func flash_capture() -> void:
	if _capture:
		var tw := create_tween()
		_capture.modulate = Color(1.6, 1.6, 1.6)
		tw.tween_property(_capture, "modulate", Color.WHITE, 0.4)


func _update_hints() -> void:
	if _hint == null:
		return
	if Settings.last_input_pad:
		_hint.text = tr("RS orbit · LT/RT distance · LB/RB zoom · D-pad roll/height · X capture · Y hide panel · View orbit/free · B exit")
		(_tab.get_child(0) as Label).text = tr("PHOTO MODE   Y")
	else:
		_hint.text = tr("Drag orbit/look · Wheel distance · WASD move · R/F height · Q/E roll · Z/X zoom · C capture · Tab hide panel · H hide UI · Esc exit")
		(_tab.get_child(0) as Label).text = tr("PHOTO MODE   Tab")
