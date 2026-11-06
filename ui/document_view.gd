class_name DocumentView
extends CanvasLayer
## Reading a Memory Shard: a sheet of paper (or receipt, sign, log) with typewriter text.

signal closed

var is_open: bool = false
var _root: Control
var _paper: PanelContainer
var _title: Label
var _body: Label
var _kind: Label


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_paper = PanelContainer.new()
	_paper.custom_minimum_size = Vector2(520, 0)
	center.add_child(_paper)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_paper.add_child(vb)
	_kind = UITheme.label("", 12, Color(0.35, 0.33, 0.3))
	vb.add_child(_kind)
	_title = UITheme.label("", 20, Color(0.15, 0.14, 0.12))
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	vb.add_child(_title)
	_body = UITheme.label("", 17, Color(0.12, 0.11, 0.1))
	_body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.custom_minimum_size = Vector2(480, 0)
	vb.add_child(_body)
	var hint := PromptLabel.new("{interact}  [k]/ Esc  [/k]close", 13, Color(0.4, 0.38, 0.35))  # [deck]
	vb.add_child(hint)
	_root.visible = false


func show_doc(doc: Dictionary) -> void:
	var paper_col := Color(0.93, 0.9, 0.82)
	match str(doc.get("kind", "note")):
		"receipt": paper_col = Color(0.97, 0.97, 0.95)
		"drawing": paper_col = Color(0.98, 0.97, 0.92)
		"memo": paper_col = Color(0.9, 0.92, 0.94)
		"log": paper_col = Color(0.86, 0.9, 0.86)
		"sign": paper_col = Color(0.85, 0.75, 0.6)
		"poster": paper_col = Color(0.92, 0.85, 0.7)
		"voicemail": paper_col = Color(0.88, 0.9, 0.95)
		"letter": paper_col = Color(0.95, 0.93, 0.86)
		"contract": paper_col = Color(0.92, 0.93, 0.9)
	_paper.add_theme_stylebox_override("panel", UITheme.box(paper_col, Color(0, 0, 0, 0.2), 1, 2, 28))
	_kind.text = str(doc.get("header", "M E M O R Y   S H A R D   ·   %s" % str(doc.get("kind", "")).to_upper()))
	_title.text = str(doc.get("title", ""))
	_body.text = str(doc.get("body", ""))
	is_open = true
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play("whoosh", 1.4, -12.0)


func close_doc() -> void:
	is_open = false
	_root.visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("interact") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close_doc()
		get_viewport().set_input_as_handled()
