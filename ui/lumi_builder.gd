class_name LumiBuilder
extends Control
## [style] Character Builder: a full-screen editor for Lumi's look (systems/lumi_style.gd).
## Left: slot list (presets, colours, face, add-ons, lights, bonus, saved looks). Middle: a big
## turntable (LumiPreview: drag / right stick turns, wheel / triggers zoom, demo laser). Right:
## the selected slot's editor (curated swatches + advanced HSV, part options with how to unlock
## the locked ones, wear slider, bonus picker, 5 saved looks). Footer: Randomize (Y), Reset to
## preset, Test laser (X), Cancel, Done (wears the look). LB / RB step through the slots;
## B / Esc = Done. Opened from the workbench Cosmetics tab (or --lumi-builder).
##
## Self-contained Control, two ways to host it:
##   Embedded (the Locker):  var b := LumiBuilder.new(); b.world = world; container.add_child(b)
##       Fills its parent (size flags expand), no backdrop, no Esc / LB / RB capture (the host owns
##       those); "Done" becomes "Wear look" and the builder stays open. Emits `worn` and `closed`
##       (Cancel = revert the edit to the worn look).
##   Overlay:  LumiBuilder.open(world, parent) -> wraps it in its own CanvasLayer (layer 100) with a
##       backdrop; Esc / B = Done, LB / RB step slots; frees itself on close.

signal closed
signal worn

## Overlay mode (set by open()): backdrop, input capture, Done closes.
var standalone: bool = false

const SIDE_W: float = 236.0
const EDIT_W: float = 400.0

var world: Node
var edit: Dictionary = {}
var _orig: Dictionary = {}
var _slot: String = "presets"
var _order: Array[String] = []
var _root: Control
var _preview: LumiPreview
var _side: VBoxContainer
var _side_btns: Dictionary = {}  # slot -> Button
var _side_vals: Dictionary = {}  # slot -> Control (Label or ColorRect)
var _editor: VBoxContainer
var _ed_title: Label
var _info: Label
var _status: Label
var _done_btn: Button
var _rng := RandomNumberGenerator.new()
var _dirty: bool = false
var _apply_t: float = 0.0
var _laser_cool: float = 0.0
var _hsv: Array[HSlider] = []
var _hsv_lbl: Label
var _adv_open: bool = false
var _first_editor: Control


static func open(w: Node, parent: Node) -> LumiBuilder:
	var cl := CanvasLayer.new()
	cl.layer = 100  # above the HUD and the workbench
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	var b := LumiBuilder.new()
	b.world = w
	b.standalone = true
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(b)
	parent.add_child(cl)
	b.closed.connect(cl.queue_free)
	return b


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not standalone:
		custom_minimum_size = Vector2(1000, 560)
	_rng.randomize()
	edit = LumiStyle.current()
	_orig = edit.duplicate(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_select("presets")
	Audio.play("click", 1.1, -6.0)


# --- Layout -----------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UITheme.get_theme()
	add_child(_root)
	if standalone:
		var bg := ColorRect.new()
		bg.color = Color(0.018, 0.02, 0.026, 0.96)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.add_child(bg)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k: String in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(k, 28 if standalone else 0)
	for k: String in ["margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(k, 18 if standalone else 0)
	_root.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	mc.add_child(vb)

	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UITheme.label(tr("CHARACTER BUILDER"), 22, UITheme.CREAM)
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_status = UITheme.label("", 15, UITheme.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.custom_minimum_size = Vector2(300, 0)
	head.add_child(_status)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	vb.add_child(body)

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(SIDE_W, 0)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(side_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 1)
	side_scroll.add_child(_side)
	_build_side()

	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.035, 0.045, 1.0), Color(1, 1, 1, 0.07), 1, 10, 0))
	body.add_child(frame)
	_preview = LumiPreview.new(Vector2i(720, 720))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_preview)
	_preview.show_style(edit)
	var hint := UITheme.label(tr("Drag to turn  ·  Wheel to zoom"), 13, Color(1, 1, 1, 0.35))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(hint)
	hint.position = Vector2(0, -26)
	hint.set_deferred("size", Vector2(0, 20))
	_preview.resized.connect(func() -> void:
		hint.position = Vector2(0, _preview.size.y - 28)
		hint.size = Vector2(_preview.size.x, 20))

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(EDIT_W, 0)
	right.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.065, 0.95), Color(1, 1, 1, 0.07), 1, 10, 14))
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	_ed_title = UITheme.label("", 20, Color.WHITE)
	rv.add_child(_ed_title)
	var ed_scroll := ScrollContainer.new()
	ed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ed_scroll.follow_focus = true
	rv.add_child(ed_scroll)
	_editor = VBoxContainer.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 8)
	ed_scroll.add_child(_editor)
	_info = UITheme.label("", 14, UITheme.GOLD)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(EDIT_W - 30, 40)
	rv.add_child(_info)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	vb.add_child(foot)
	foot.add_child(_foot_btn(tr("Randomize"), "Y", _randomize))
	foot.add_child(_foot_btn(tr("Reset to preset"), "", _reset))
	foot.add_child(_foot_btn(tr("Test laser"), "X", func() -> void: _preview.demo_beam()))
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp2)
	foot.add_child(_foot_btn(tr("Cancel"), "", _cancel))
	_done_btn = _foot_btn(tr("Done"), "B", _done) if standalone else _foot_btn(tr("Wear look"), "", _done)
	UITheme.orange_button(_done_btn)
	foot.add_child(_done_btn)


func _foot_btn(text: String, pad: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text if pad == "" else "%s  [%s]" % [text, pad]
	b.custom_minimum_size = Vector2(140, 40)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	return b


func _build_side() -> void:
	_order.clear()
	_side_entry("presets", tr("Presets"), "")
	var group: String = ""
	for s: Dictionary in LumiStyle.slot_defs():
		var g: String = str(s.get("group", ""))
		if g != group:
			group = g
			var gl := UITheme.label(tr(g).to_upper(), 12, UITheme.MUTED)
			gl.custom_minimum_size = Vector2(0, 16)
			gl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_side.add_child(gl)
		_side_entry(str(s["id"]), tr(str(s["name"])), str(s.get("kind", "")))
	var gl2 := UITheme.label(tr("Saved").to_upper(), 12, UITheme.MUTED)
	gl2.custom_minimum_size = Vector2(0, 16)
	gl2.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_side.add_child(gl2)
	_side_entry("looks", tr("Saved looks"), "")


func _side_entry(slot: String, text: String, kind: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SIDE_W - 12, 24)
	b.focus_mode = Control.FOCUS_ALL
	b.toggle_mode = false
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -8
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var l := UITheme.label(text, 14, UITheme.CREAM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(l)
	if kind == "color":
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(18, 12)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(chip)
		_side_vals[slot] = chip
	elif kind != "":
		var v := UITheme.label("", 12, UITheme.MUTED)
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(86, 0)
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(v)
		_side_vals[slot] = v
	b.pressed.connect(func() -> void: _select(slot))
	b.focus_entered.connect(func() -> void: _select(slot, false))
	_side.add_child(b)
	_side_btns[slot] = b
	_order.append(slot)


func _style_side() -> void:
	var glow: Color = LumiStyle.col(edit, "glow")
	for slot: String in _side_btns:
		var b: Button = _side_btns[slot]
		var on: bool = slot == _slot
		for st: String in ["normal", "hover", "pressed", "focus"]:
			var bg := Color(1, 1, 1, 0.07) if on else (Color(1, 1, 1, 0.04) if st in ["hover", "focus"] else Color(0, 0, 0, 0))
			var sb := UITheme.box(bg, glow if (on or st == "focus") else Color(0, 0, 0, 0), 0, 6, 0)
			sb.border_width_left = 3 if on else (2 if st == "focus" else 0)
			b.add_theme_stylebox_override(st, sb)
	for slot: String in _side_vals:
		var c: Control = _side_vals[slot]
		if c is ColorRect:
			(c as ColorRect).color = LumiStyle.col(edit, slot)
		elif c is Label:
			(c as Label).text = _value_text(slot)


func _value_text(slot: String) -> String:
	if slot == "wear":
		return "%d%%" % int(round(float(edit.get("wear", 0.6)) * 100.0))
	if slot == "bonus":
		return tr(str(Designs.def(str(edit["bonus"])).get("name", edit["bonus"])))
	var o: Dictionary = LumiStyle.option(slot, str(edit.get(slot, "")))
	return tr(str(o.get("name", ""))) if not o.is_empty() else ""


# --- Editors ----------------------------------------------------------------------------------

func _select(slot: String, focus_editor: bool = true) -> void:
	var changed: bool = slot != _slot or _editor.get_child_count() == 0
	_slot = slot
	if changed:
		_build_editor()
	_style_side()
	_update_status()
	if slot == "laser" and changed:
		_preview.demo_beam()
	if focus_editor and _first_editor and is_instance_valid(_first_editor):
		_first_editor.grab_focus.call_deferred()


func _clear_editor() -> void:
	for c: Node in _editor.get_children():
		c.queue_free()
	_hsv.clear()
	_hsv_lbl = null
	_first_editor = null
	_info.text = ""


func _build_editor() -> void:
	_clear_editor()
	if _slot == "presets":
		_ed_title.text = tr("Presets")
		_build_presets()
		return
	if _slot == "looks":
		_ed_title.text = tr("Saved looks")
		_build_looks()
		return
	var sd: Dictionary = LumiStyle.slot_def(_slot)
	_ed_title.text = tr(str(sd.get("name", _slot)))
	match str(sd.get("kind", "")):
		"color":
			_build_colors()
		"part":
			_build_parts()
		"amount":
			_build_wear()
		"bonus":
			_build_bonus()


func _note(text: String, color: Color = UITheme.MUTED, size: int = 14) -> Label:
	var l := UITheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(EDIT_W - 40, 0)
	_editor.add_child(l)
	return l


func _row_btn(title: String, sub: String, accent: Color, on: bool, locked: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(EDIT_W - 40, 50 if sub != "" else 38)
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = title if sub == "" else "%s\n%s" % [title, sub]
	b.clip_text = true
	for st: String in ["normal", "hover", "pressed", "focus"]:
		var lit: bool = st in ["hover", "focus"]
		var bg := Color(1, 1, 1, 0.09 if on else (0.06 if lit else 0.025))
		var sb := UITheme.box(bg, accent if (on or lit) else Color(1, 1, 1, 0.06), 1, 8, 10)
		sb.border_width_left = 4 if on else (2 if lit else 1)
		b.add_theme_stylebox_override(st, sb)
	var fc: Color = UITheme.MUTED if locked else (Color.WHITE if on else UITheme.CREAM)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_focus_color", Color.WHITE if not locked else UITheme.CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE if not locked else UITheme.CREAM)
	b.add_theme_font_size_override("font_size", 15)
	_editor.add_child(b)
	if _first_editor == null or on:
		_first_editor = b
	return b


func _build_presets() -> void:
	_note(tr("A design's full look. Every slot can be changed afterwards."))
	for id: String in LumiStyle.preset_ids():
		var unlocked: bool = Designs.is_unlocked(id)
		var nm: String = tr(str(Designs.def(id).get("name", id)))
		var sub: String = tr(str(Designs.def(id).get("tagline", ""))) if unlocked else (tr("Locked: %s") % Designs.unlock_text(id))
		var on: bool = LumiStyle.same(edit, LumiStyle.preset(id))
		var b := _row_btn(nm, sub, PatchModel.glow_of(id), on, not unlocked)
		b.pressed.connect(func() -> void:
			if not Designs.is_unlocked(id):
				_locked_feedback(Designs.unlock_text(id), Designs.progress(id))
				return
			_set_style(LumiStyle.preset(id))
			_build_editor())
		b.focus_entered.connect(func() -> void:
			_info.text = "" if Designs.is_unlocked(id) else _lock_line(Designs.unlock_text(id), Designs.progress(id)))


func _build_colors() -> void:
	var cur: Color = LumiStyle.col(edit, _slot)
	var sw_on: Dictionary = LumiStyle.swatch_for(cur)
	var name_l := _note(tr(str(sw_on.get("name", "Custom"))) if not sw_on.is_empty() else tr("Custom colour"), UITheme.CREAM, 15)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_editor.add_child(grid)
	for s: Dictionary in LumiStyle.swatches():
		var id: String = str(s["id"])
		var c: Color = LumiStyle.swatch_color(s)
		var unlocked: bool = LumiStyle.swatch_unlocked(id)
		var on: bool = not sw_on.is_empty() and str(sw_on["id"]) == id
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = tr(str(s.get("name", id)))
		for st: String in ["normal", "hover", "pressed", "focus"]:
			var lit: bool = st in ["hover", "focus"]
			var sb := UITheme.box(c if unlocked else Color(c, 0.22), Color.WHITE if on else (Color(1, 1, 1, 0.75) if lit else Color(1, 1, 1, 0.1)), 3 if on else (2 if lit else 1), 22, 0)
			b.add_theme_stylebox_override(st, sb)
		if not unlocked:
			b.text = "·"
			b.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		grid.add_child(b)
		if _first_editor == null or on:
			_first_editor = b
		var u: Dictionary = s.get("unlock", {})
		var key: String = LumiStyle.key_of("swatch", id)
		b.focus_entered.connect(func() -> void:
			name_l.text = tr(str(s.get("name", id)))
			_info.text = "" if LumiStyle.swatch_unlocked(id) else _lock_line(LumiStyle.unlock_text(u), LumiStyle.unlock_progress(u, key)))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		b.pressed.connect(func() -> void:
			if not LumiStyle.swatch_unlocked(id):
				if u.has("cost") and LumiStyle.buy("swatch", id):
					Audio.play("buy", 1.2, -4.0)
				else:
					_locked_feedback(LumiStyle.unlock_text(u), LumiStyle.unlock_progress(u, key))
					return
			_set_value(_slot, c)
			_build_editor())
	# Advanced HSV picker.
	var adv_u: Dictionary = (LumiStyle.data().get("advanced", {}) as Dictionary).get("unlock", {})
	var sep := HSeparator.new()
	_editor.add_child(sep)
	if not LumiStyle.advanced_unlocked():
		var b2 := _row_btn(tr("Advanced colour picker"), LumiStyle.unlock_text(adv_u), UITheme.GOLD, false, true)
		b2.pressed.connect(func() -> void:
			if LumiStyle.buy("", "advanced_picker"):
				Audio.play("buy", 1.2, -4.0)
				_adv_open = true
				_build_editor()
			else:
				_locked_feedback(LumiStyle.unlock_text(adv_u), LumiStyle.unlock_progress(adv_u, "advanced_picker")))
		return
	var tg := CheckButton.new()
	tg.text = tr("Advanced (hue, saturation, brightness)")
	tg.button_pressed = _adv_open
	tg.focus_mode = Control.FOCUS_ALL
	tg.toggled.connect(func(on: bool) -> void:
		_adv_open = on
		_build_editor())
	_editor.add_child(tg)
	if not _adv_open:
		return
	var names: Array[String] = [tr("Hue"), tr("Saturation"), tr("Brightness")]
	var vals: Array[float] = [cur.h, cur.s, cur.v]
	for i: int in 3:
		var row := HBoxContainer.new()
		_editor.add_child(row)
		var l := UITheme.label(names[i], 14, UITheme.MUTED)
		l.custom_minimum_size = Vector2(96, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.005
		sl.value = vals[i]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.focus_mode = Control.FOCUS_ALL
		sl.value_changed.connect(func(_v: float) -> void: _hsv_changed())
		row.add_child(sl)
		_hsv.append(sl)
	_hsv_lbl = _note("#" + cur.to_html(false), UITheme.MUTED, 13)


func _hsv_changed() -> void:
	if _hsv.size() < 3:
		return
	var c := Color.from_hsv(_hsv[0].value, _hsv[1].value, _hsv[2].value)
	_set_value(_slot, c)
	if _hsv_lbl:
		_hsv_lbl.text = "#" + c.to_html(false)


func _build_parts() -> void:
	for o: Dictionary in LumiStyle.options(_slot):
		var id: String = str(o["id"])
		var unlocked: bool = LumiStyle.option_unlocked(_slot, id)
		var on: bool = str(edit.get(_slot, "")) == id
		var u: Dictionary = o.get("unlock", {})
		var key: String = LumiStyle.key_of(_slot, id)
		var sub: String = tr("Equipped") if on else ("" if unlocked else (tr("Locked: %s") % LumiStyle.unlock_text(u)))
		var b := _row_btn(tr(str(o.get("name", id))), sub, LumiStyle.col(edit, "glow"), on, not unlocked)
		b.focus_entered.connect(func() -> void:
			_info.text = "" if LumiStyle.option_unlocked(_slot, id) else _lock_line(LumiStyle.unlock_text(u), LumiStyle.unlock_progress(u, key)))
		b.pressed.connect(func() -> void:
			if not LumiStyle.option_unlocked(_slot, id):
				if u.has("cost") and LumiStyle.buy(_slot, id):
					Audio.play("buy", 1.2, -4.0)
				else:
					_locked_feedback(LumiStyle.unlock_text(u), LumiStyle.unlock_progress(u, key))
					return
			_set_value(_slot, id)
			_build_editor())


func _build_wear() -> void:
	_note(tr("How weathered the paint looks: fresh from the ark, or three hundred years of dust."))
	var row := HBoxContainer.new()
	_editor.add_child(row)
	row.add_child(UITheme.label(tr("Fresh"), 14, UITheme.MUTED))
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(edit.get("wear", 0.6))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.focus_mode = Control.FOCUS_ALL
	row.add_child(sl)
	row.add_child(UITheme.label(tr("Weathered"), 14, UITheme.MUTED))
	sl.value_changed.connect(func(v: float) -> void: _set_value("wear", v))
	_first_editor = sl


func _build_bonus() -> void:
	_note(tr("A custom look can use the bonus of any design you have unlocked."))
	for id: String in Designs.ids():
		var unlocked: bool = Designs.is_unlocked(id)
		var on: bool = str(edit["bonus"]) == id
		var sub: String = Designs.buff_text(id) if unlocked else (tr("Locked: %s") % Designs.unlock_text(id))
		var b := _row_btn(tr(str(Designs.def(id).get("name", id))), sub, PatchModel.glow_of(id), on, not unlocked)
		b.pressed.connect(func() -> void:
			if not Designs.is_unlocked(id):
				_locked_feedback(Designs.unlock_text(id), Designs.progress(id))
				return
			_set_value("bonus", id)
			_build_editor())
	var looks := CheckButton.new()
	looks.text = tr("Looks only (no bonuses)")
	looks.button_pressed = Designs.looks_only()
	looks.focus_mode = Control.FOCUS_ALL
	looks.toggled.connect(func(on: bool) -> void:
		Designs.set_looks_only(on)
		Audio.play("click", 1.0, -6.0)
		_update_status())
	_editor.add_child(looks)


func _build_looks() -> void:
	_note(tr("Keep up to %d looks. Load one to edit it, then press Done to wear it.") % LumiStyle.MAX_LOOKS)
	for i: int in LumiStyle.MAX_LOOKS:
		var lk: Dictionary = LumiStyle.look(i)
		var nm: String = str(lk.get("name", "")) if not lk.is_empty() else ""
		if nm == "" and not lk.is_empty():
			nm = tr("Look %d") % (i + 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_editor.add_child(row)
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(10, 36)
		chip.color = LumiStyle.col(lk, "glow") if not lk.is_empty() else Color(1, 1, 1, 0.08)
		row.add_child(chip)
		var l := UITheme.label("%d.  %s" % [i + 1, nm if nm != "" else tr("Empty")], 15, UITheme.CREAM if not lk.is_empty() else UITheme.MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(l)
		var ld := Button.new()
		ld.text = tr("Load")
		ld.disabled = lk.is_empty()
		ld.focus_mode = Control.FOCUS_ALL
		ld.pressed.connect(func() -> void:
			_set_style(LumiStyle.look(i))
			_build_editor())
		row.add_child(ld)
		var sv := Button.new()
		sv.text = tr("Save here")
		sv.focus_mode = Control.FOCUS_ALL
		sv.pressed.connect(func() -> void:
			LumiStyle.save_look(i, edit, tr("Look %d") % (i + 1))
			Audio.play("buy", 1.3, -6.0)
			_build_editor())
		row.add_child(sv)
		var cl := Button.new()
		cl.text = tr("Clear")
		cl.disabled = lk.is_empty()
		cl.focus_mode = Control.FOCUS_ALL
		cl.pressed.connect(func() -> void:
			LumiStyle.delete_look(i)
			Audio.play("click", 0.8, -6.0)
			_build_editor())
		row.add_child(cl)
		if _first_editor == null:
			_first_editor = sv


func _lock_line(how: String, p: float) -> String:
	if p > 0.0 and p < 1.0:
		return tr("Locked: %s") % how + "  (%d%%)" % int(p * 100.0)
	return tr("Locked: %s") % how


func _locked_feedback(how: String, p: float) -> void:
	Audio.play("error", 1.0, -6.0)
	_info.text = _lock_line(how, p)


# --- Editing ----------------------------------------------------------------------------------

func _set_value(slot: String, v: Variant) -> void:
	LumiStyle.set_value(edit, slot, v)
	_dirty = true
	if slot == "laser" or slot == "hover":
		if _laser_cool <= 0.0:
			_laser_cool = 0.9
			_preview.demo_beam()
	_style_side()
	_update_status()


func _set_style(s: Dictionary) -> void:
	edit = LumiStyle.normalize(s)
	edit.erase("name")
	_dirty = true
	Audio.play("click", 1.2, -6.0)
	_style_side()
	_update_status()


func _randomize() -> void:
	_set_style(LumiStyle.randomized(_rng, edit))
	_build_editor()
	_preview.demo_beam()


func _reset() -> void:
	_set_style(LumiStyle.preset(str(edit.get("preset", edit["bonus"]))))
	_select("presets")


func _update_status() -> void:
	var b: String = str(edit["bonus"])
	var bt: String = Designs.buff_text(b)
	var bits: Array[String] = []
	bits.append(tr("Bonus: %s") % bt + ("  " + tr("(off: looks only)") if Designs.looks_only() else ""))
	if not LumiStyle.same(edit, _orig):
		bits.append(tr("Unsaved changes"))
	_status.text = "   ·   ".join(bits)


func _process(delta: float) -> void:
	_laser_cool = maxf(0.0, _laser_cool - delta)
	_apply_t -= delta
	if _dirty and _apply_t <= 0.0:
		_dirty = false
		_apply_t = 0.08
		_preview.show_style(edit)


func _done() -> void:
	if not LumiStyle.allowed(edit):
		Audio.play("error", 1.0, -6.0)
		_info.text = tr("Part of this look is still locked.")
		return
	var changed: bool = not LumiStyle.same(edit, _orig) or not LumiStyle.same(edit, LumiStyle.current())
	LumiStyle.set_current(edit)
	if changed:
		LumiStyle.refresh_player(world)
		var p: Variant = world.get("patch") if world else null
		if p is Node3D:
			Vfx.burst("sparkle", (p as Node3D).global_position + Vector3(0, 0.8, 0), LumiStyle.col(edit, "glow"))
		Audio.play("buy", 1.2, -4.0)
	worn.emit()
	if standalone:
		_close()
	else:
		_orig = LumiStyle.current()
		_update_status()


func _cancel() -> void:
	if standalone:
		_close()
		return
	_set_style(LumiStyle.current())
	_dirty = true
	_build_editor()
	closed.emit()


func _close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not standalone:
		# Hosted: the Locker owns Esc and LB / RB; only the pad shortcuts are ours.
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
			var jb2: InputEventJoypadButton = event
			if jb2.button_index == JOY_BUTTON_Y:
				_randomize()
				get_viewport().set_input_as_handled()
			elif jb2.button_index == JOY_BUTTON_X:
				_preview.demo_beam()
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_done()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_upgrades"):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		var i: int = maxi(0, _order.find(_slot))
		var n: int = _order.size()
		var nxt: String = _order[(i + (1 if event.is_action_pressed("ui_tab_next") else n - 1)) % n]
		_select(nxt, false)
		(_side_btns[nxt] as Button).grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var jb: InputEventJoypadButton = event
		if jb.button_index == JOY_BUTTON_Y:
			_randomize()
			get_viewport().set_input_as_handled()
		elif jb.button_index == JOY_BUTTON_X:
			_preview.demo_beam()
			get_viewport().set_input_as_handled()
