class_name StoryPause
extends CanvasLayer
## [intro2] Space (or pad A) pauses a story cinematic and resumes it (owner playtest #2). Esc / B
## skip. Pausing freezes the cinematic's clock (Engine.time_scale = 0: its timers, tweens, camera
## moves and the subtitle line all hold still) and shows a small "Paused" card.

var paused: bool = false
var _prev_scale: float = 1.0
var _card: Control


func _ready() -> void:
	layer = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.025, 0.035, 0.82), Color(1, 1, 1, 0.08), 1, 14, 16))
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(vb)
	var t := UITheme.label(tr("Paused"), 26, Color(0.95, 0.94, 0.9))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var h := UITheme.label("", 13, Color(1, 1, 1, 0.6))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Settings.bind_text(h, func() -> String:
		return tr("%s  resume   ·   %s  skip") % ([tr("Space"), tr("Esc")] if not Settings.last_input_pad else [Settings.glyph("ui_accept"), Settings.glyph("ui_cancel")]))
	vb.add_child(h)
	_card = c
	c.visible = false


## Hint text for the cinematic's corner label.
static func hint() -> String:
	if Settings.last_input_pad:
		return TranslationServer.translate("%s  pause   ·   %s  skip") % [Settings.glyph("ui_accept"), Settings.glyph("ui_cancel")]
	return TranslationServer.translate("Space  pause   ·   Esc  skip")


## True for the pause/resume key (Space, Enter, pad A).
static func is_pause_event(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		return (event as InputEventKey).keycode == KEY_SPACE
	return event.is_action_pressed("ui_accept")


## True for skip (Esc, pad B, the pause action).
static func is_skip_event(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")


func toggle() -> void:
	set_paused(not paused)


func set_paused(on: bool) -> void:
	if on == paused:
		return
	paused = on
	if on:
		_prev_scale = Engine.time_scale
		Engine.time_scale = 0.0
	else:
		Engine.time_scale = _prev_scale if _prev_scale > 0.0 else 1.0
	_card.visible = on


func _exit_tree() -> void:
	if paused:
		set_paused(false)
