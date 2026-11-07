class_name ChecklistCard
extends PanelContainer
## [first] The restart checklist as a compact HUD card (top-right, above the goal tracker), styled
## like the hotbar slots: soft glass backing, a hairline border, rounded corners.
##   caption   "RESTART CHECKLIST" + one dot per step (done green, current ringed)
##   text      the one thing to do now, key glyphs in amber (Tutorial.glyphs_bb)
##   progress  a hairline bar + "3 / 8" for counted steps (scoops, hex %)
## A finished step ticks green for a beat, then the next one slides in. After the last step the
## card says so and fades away. Other systems can borrow it for a one-off "NEXT STEP" (first seed).

const W: float = 300.0
const CYAN := Color(0.55, 0.9, 1.0)
const DONE_HOLD_S: float = 2.6

var tutorial: Tutorial
var _cap: Label
var _dots: Control
var _text: RichTextLabel
var _bar: Control
var _bar_label: Label
var _progress: float = -1.0
var _shown: float = 0.0
var _flash: float = 0.0
var _pending: String = ""
var _busy: bool = false
var _current: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	var sb := UITheme.box(Color(0.03, 0.04, 0.05, 0.55), Color(0.9, 0.9, 0.85, 0.14), 1, 11, 0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 11
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	_cap = UITheme.label("", 11, UITheme.MUTED)
	_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_cap)
	_dots = Control.new()
	_dots.custom_minimum_size = Vector2(84, 12)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	head.add_child(_dots)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.custom_minimum_size = Vector2(W - 28.0, 0)
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.add_theme_color_override("default_color", UITheme.CREAM)
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_text.add_theme_constant_override("shadow_outline_size", 4)
	vb.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	row.add_child(_bar)
	_bar_label = UITheme.label("", 12, UITheme.MUTED)
	row.add_child(_bar_label)
	visible = false
	modulate.a = 0.0


## EventBus.tutorial_changed: the new step text ("" = checklist finished or hint cleared).
func set_text(text: String) -> void:
	if text == _current and visible:
		return
	if _busy:
		_pending = text
		return
	var had: bool = visible and _current != ""
	if text == "":
		var finished: bool = tutorial != null and tutorial.done() and had and _cap.text.begins_with(tr("RESTART"))
		_current = ""
		if finished:
			_tick_then(func() -> void: _show_done())
		elif visible:
			_fade_out(0.5)
		return
	if had:
		_tick_then(func() -> void: _show(text, true))
	else:
		_show(text, false)


func _show(text: String, slide: bool) -> void:
	_current = text
	_text.text = text
	_flash = 0.0
	var in_tutorial: bool = tutorial != null and not tutorial.done()
	_cap.text = tr("RESTART CHECKLIST") if in_tutorial else tr("NEXT STEP")
	_dots.visible = in_tutorial
	_dots.queue_redraw()
	_shown = 0.0
	_refresh_progress()
	visible = true
	var tw := create_tween().set_ignore_time_scale(true).set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	if slide:
		_text.modulate.a = 0.0
		tw.tween_property(_text, "modulate:a", 1.0, 0.3)
	else:
		_text.modulate.a = 1.0


## Green tick on the finished line for a beat, then run `next`.
func _tick_then(next: Callable) -> void:
	_busy = true
	_text.text = "[color=#9edba8]%s[/color]" % _strip_bb(_current)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(t: float) -> void:
		_flash = t
		_bar.queue_redraw()
		_dots.queue_redraw(), 0.0, 1.0, 0.25)
	tw.tween_interval(0.45)
	tw.tween_property(_text, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		_busy = false
		next.call()
		if _pending != "":
			var p: String = _pending
			_pending = ""
			set_text(p))


func _show_done() -> void:
	_text.text = "[color=#9edba8]%s[/color]" % tr(Tutorial.DONE_TEXT)
	_text.modulate.a = 1.0
	_cap.text = tr("RESTART CHECKLIST  ·  DONE")
	_progress = -1.0
	_bar.get_parent().visible = false
	_dots.queue_redraw()
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(DONE_HOLD_S)
	tw.tween_callback(func() -> void: _fade_out(0.9))


func _fade_out(d: float) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(self, "modulate:a", 0.0, d)
	tw.tween_callback(func() -> void:
		if _current == "":
			visible = false)


static func _strip_bb(t: String) -> String:
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	return re.sub(t, "", true)


func _refresh_progress() -> void:
	var pr: Array = tutorial.step_progress() if tutorial != null and not tutorial.done() else [-1.0, ""]
	_progress = float(pr[0])
	_bar_label.text = str(pr[1])
	_bar.get_parent().visible = _progress >= 0.0


func _process(delta: float) -> void:
	if not visible or _busy:
		return
	_refresh_progress()
	if _progress >= 0.0:
		_shown = lerpf(_shown, _progress, clampf(delta * 8.0, 0.0, 1.0))
		_bar.queue_redraw()


func _draw_bar() -> void:
	var w: float = _bar.size.x
	var y: float = _bar.size.y * 0.5 - 1.0
	_bar.draw_rect(Rect2(0, y, w, 2.0), Color(1, 1, 1, 0.14))
	_bar.draw_rect(Rect2(0, y, w * clampf(_shown if _flash <= 0.0 else 1.0, 0.0, 1.0), 2.0), CYAN.lerp(UITheme.GREEN, _flash))


func _draw_dots() -> void:
	if tutorial == null:
		return
	var n: int = Tutorial.STEPS.size()
	var cur: int = tutorial.step
	var gap: float = 13.0
	var x0: float = _dots.size.x - gap * (n - 1) - 4.0
	var y: float = _dots.size.y * 0.5
	for i: int in n:
		var c := Vector2(x0 + i * gap, y)
		var done_i: bool = i < cur or (i == cur and _flash > 0.0) or tutorial.done()
		if done_i:
			_dots.draw_circle(c, 3.2, UITheme.GREEN)
		elif i == cur:
			_dots.draw_arc(c, 3.6, 0.0, TAU, 16, UITheme.CREAM, 1.3, true)
		else:
			_dots.draw_circle(c, 2.4, Color(1, 1, 1, 0.22))
