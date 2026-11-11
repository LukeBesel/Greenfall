class_name ObjectiveCard
extends PanelContainer
## [onboard] The current story objective (story/objectives.gd) as a compact HUD card, top-right
## above the restart checklist, in the same glass style:
##   caption   "OBJECTIVE" and its progress ("1 / 3", "42%")
##   title     what to do ("Power the base: sell 3 bales")
##   why       one short line of reasoning, muted
##   bar       a hairline progress line
## A finished objective ticks green for a beat, then the next one slides in; after the last one the
## card fades away.

const W: float = 300.0
const ACCENT := Color(0.55, 0.9, 1.0)
const WHY := Color(0.78, 0.8, 0.79)
const HINT := Color(1.0, 0.82, 0.45)  # [v3clear] a situation hint (amber)

var objectives: Objectives
var _cap: Label
var _count: Label
var _title: Label
var _why: Label
var _hint: Label
var _bar: Control
var _shown: float = 0.0
var _progress: float = -1.0
var _flash: float = 0.0
var _busy: bool = false
var _index: int = -1
## [v2guide] Owner playtest 2 #33: one card. A sub-step (the restart checklist's "Empty your chest
## into the trash bin", the first seed's "water it") replaces the card's text while it lasts.
var substep: String = ""
var substep_progress: Array = [-1.0, ""]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	var sb := UITheme.box(Color(0.025, 0.035, 0.045, 0.66), Color(0.55, 0.9, 1.0, 0.2), 1, 11, 0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 11
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	_cap = UITheme.label(tr("OBJECTIVE"), 12, ACCENT)
	_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_cap)
	_count = UITheme.label("", 13, UITheme.CREAM)
	head.add_child(_count)
	_title = UITheme.label("", 18, UITheme.CREAM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_title.custom_minimum_size = Vector2(W - 28.0, 0)
	vb.add_child(_title)
	_why = UITheme.label("", 14, WHY)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD
	_why.custom_minimum_size = Vector2(W - 28.0, 0)
	vb.add_child(_why)
	_hint = UITheme.label("", 14, HINT)  # [v6story] the situation line, under the reason
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size = Vector2(W - 28.0, 0)
	_hint.visible = false
	vb.add_child(_hint)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	vb.add_child(_bar)
	visible = false
	modulate.a = 0.0


func bind(o: Objectives) -> void:
	objectives = o
	o.changed.connect(func(_i: int) -> void: refresh(true))
	o.completed.connect(_on_completed)
	refresh(false)


## Shows the current objective (fading it in), or fades the card out when there is none.
func refresh(animate: bool) -> void:
	if objectives == null or _busy:
		return
	var def: Dictionary = objectives.current()
	if def.is_empty():
		_index = -1
		if visible:
			var tw := create_tween().set_ignore_time_scale(true)
			tw.tween_property(self, "modulate:a", 0.0, 0.6)
			tw.tween_callback(func() -> void:
				if _index < 0:
					visible = false)
		return
	if objectives.position() == _index and visible:  # [v1guide] goal steps keep step: use the timeline position
		return
	_index = objectives.position()
	_flash = 0.0
	_title.add_theme_color_override("font_color", UITheme.CREAM)
	_set_texts(def)
	_shown = maxf(0.0, float(objectives.progress()[0]))
	visible = true
	if animate:
		modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(self, "modulate:a", 1.0, 0.45)


func _set_texts(def: Dictionary) -> void:
	# [v3clear] Owner item 41: the player's situation (full chest, too heavy, short of cubes, lost...)
	# takes the why line, in amber, so the card always says the one next thing.
	var hint: String = objectives.situation if objectives else ""
	_why.add_theme_color_override("font_color", HINT if hint != "" else WHY)
	_hint.visible = false  # [v6story]
	if substep != "":  # [v2guide]
		_title.text = substep
		_why.text = hint
		_why.visible = hint != ""
		return
	var t: Array[String] = Objectives.texts(def)
	_title.text = t[0]
	# [v6story] Owner item 60: the reason stays on the card; the situation line goes under it (it
	# used to replace the reason, so a save-up step only showed its why once it was done).
	_why.add_theme_color_override("font_color", WHY)
	_why.text = t[1]
	_hint.text = hint
	_hint.visible = hint != ""
	_why.visible = _why.text != ""


## [v2guide] Sets (or clears, with "") the sub-step shown in place of the objective; plain text.
func set_substep(text: String, pr: Array = [-1.0, ""]) -> void:
	substep_progress = pr
	if text == substep:
		return
	substep = text
	if visible and not _busy:
		_title.modulate.a = 0.0
		create_tween().set_ignore_time_scale(true).tween_property(_title, "modulate:a", 1.0, 0.3)


func _on_completed(_i: int) -> void:
	_busy = true
	_title.add_theme_color_override("font_color", UITheme.GREEN)
	_count.text = tr("DONE")
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(t: float) -> void:
		_flash = t
		_bar.queue_redraw(), 0.0, 1.0, 0.25)
	tw.tween_interval(Objectives.NEXT_DELAY_S - 0.75)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		_busy = false
		_index = -1
		visible = false
		refresh(true))


func _process(delta: float) -> void:
	if not visible or _busy or objectives == null:
		return
	var def: Dictionary = objectives.current()
	if def.is_empty():
		return
	_set_texts(def)  # the why can change (a wait flag), and the language
	var pr: Array = objectives.progress() if substep == "" else substep_progress  # [v2guide]
	_progress = float(pr[0])
	_count.text = str(pr[1])
	_shown = lerpf(_shown, maxf(_progress, 0.0), clampf(delta * 6.0, 0.0, 1.0))
	_bar.visible = _progress >= 0.0
	_bar.queue_redraw()


func _draw_bar() -> void:
	var w: float = _bar.size.x
	var y: float = _bar.size.y * 0.5 - 1.0
	_bar.draw_rect(Rect2(0, y, w, 2.0), Color(1, 1, 1, 0.16))
	_bar.draw_rect(Rect2(0, y, w * clampf(_shown if _flash <= 0.0 else 1.0, 0.0, 1.0), 2.0), ACCENT.lerp(UITheme.GREEN, _flash))
