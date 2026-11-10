class_name RocketPicker
extends CanvasLayer
## [v2map] The rocket's destination list (owner note 40: travel only at the rocket, never in the
## map). E at the parked rocket on a hub's pad (planet/sites/orbit_sites.gd) opens it: the other
## hubs on this globe (nearest first, each with a Fly button). Esc / B closes. Pad: the first Fly
## button takes focus.

signal closed
signal picked(site: int)

var is_open: bool = false
## Rows to offer: [{"site": int, "name": String, "km": float}], nearest first.
var entries_fn: Callable = func() -> Array: return []
## "" when the rocket can fly now, else why not (shown instead of the buttons).
var blocker_fn: Callable = func() -> String: return ""

var _root: Control
var _list: VBoxContainer
var _first: Button

const INK := Color(0.47, 0.86, 0.78)  # seed-keeper teal
const CREAM := Color(0.98, 0.93, 0.8)


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.04, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.11, 0.1, 0.92), Color(INK, 0.55), 1, 10, 18))
	pc.custom_minimum_size = Vector2(380, 0)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	vb.add_child(UITheme.label(tr("ROCKET"), 22, CREAM))
	vb.add_child(UITheme.label(tr("Where to?"), 13, Color(INK, 0.9)))
	var line := ColorRect.new()
	line.color = Color(INK, 0.4)
	line.custom_minimum_size = Vector2(0, 1)
	vb.add_child(line)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	vb.add_child(_list)
	var hint := PromptLabel.new(tr("{ui_cancel}  close"), 12)
	hint.align_center = true
	vb.add_child(hint)


func open() -> void:
	if is_open:
		return
	is_open = true
	_rebuild()
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("blip", 1.0, -8.0)
	if _first:
		_first.call_deferred("grab_focus")


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


## Hub rows shown right now (site indices), for tests and the dev hook.
func offered_sites() -> Array:
	var out: Array = []
	for e: Dictionary in entries_fn.call():
		out.append(int(e["site"]))
	return out


func _rebuild() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_first = null
	var why: String = str(blocker_fn.call())
	if why != "":
		var l := UITheme.label(why, 13, UITheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
	var entries: Array = entries_fn.call()
	if entries.is_empty():
		_list.add_child(UITheme.label(tr("No other hubs found yet."), 13, UITheme.MUTED))
	for e: Dictionary in entries:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.box(Color(INK, 0.07), Color(INK, 0.22), 1, 8, 8))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 0)
		tv.add_child(UITheme.label(str(e["name"]), 15, CREAM))
		tv.add_child(UITheme.label(tr("%.1f km") % float(e["km"]), 12, UITheme.MUTED))
		hb.add_child(tv)
		var b := _button(tr("Fly"))
		b.disabled = why != ""
		var site: int = int(e["site"])
		b.pressed.connect(func() -> void:
			close()
			picked.emit(site))
		hb.add_child(b)
		_list.add_child(row)
		if _first == null and not b.disabled:
			_first = b


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 36)
	b.add_theme_stylebox_override("normal", UITheme.box(Color(INK, 0.18), Color(INK, 0.6), 1, 8, 8))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(INK, 0.32), Color(CREAM, 0.8), 1, 8, 8))
	b.add_theme_stylebox_override("focus", UITheme.box(Color(INK, 0.32), CREAM, 2, 8, 8))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(INK, 0.45), CREAM, 1, 8, 8))
	b.add_theme_stylebox_override("disabled", UITheme.box(Color(INK, 0.05), Color(INK, 0.15), 1, 8, 8))
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.4))
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
