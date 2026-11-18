class_name BenchRow
extends PanelContainer
## [ui3] One compact holo row for the workbench lists (Build tab buildings, Upgrades tab tiers):
## name and tier line on the left with one line of description, the cost (green = affordable,
## red with what's missing) and one button on the right. Call show_entry() to fill or update it;
## nothing is rebuilt when the values haven't changed.

signal pressed

var _title: Label
var _sub: Label
var _desc: Label
var _cost: BenchKit.CostRow
var _why: Label
var _btn: Button
var _sig: String = ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", BenchKit.holo())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)
	var tr_row := HBoxContainer.new()
	tr_row.add_theme_constant_override("separation", 10)
	left.add_child(tr_row)
	_title = UITheme.label("", 20, Color.WHITE)
	_title.add_theme_constant_override("outline_size", 0)
	tr_row.add_child(_title)
	_sub = UITheme.label("", BenchKit.SMALL_SIZE, BenchKit.HOLO)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sub.clip_text = true
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_row.add_child(_sub)
	_desc = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
	left.add_child(_desc)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(190, 0)
	right.add_theme_constant_override("separation", 4)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(right)
	_btn = BenchKit.big_button("")
	_btn.custom_minimum_size = Vector2(190, 44)
	_btn.pressed.connect(func() -> void: pressed.emit())
	right.add_child(_btn)
	_cost = BenchKit.CostRow.new(18, 16)
	_cost.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(_cost)
	_why = UITheme.label("", 13, BenchKit.SHORT)
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size.x = 150
	right.add_child(_why)


func button() -> Button:
	return _btn


## title/sub/desc are already translated. reason: "" = can do it now; short_only: the reason only
## means "can't afford it yet" (the cost row says what's missing, so no extra line).
func show_entry(title: String, sub: String, desc: String, cost: Dictionary, btn_text: String, reason: String, short_only: bool) -> void:
	var sig: String = "|".join([title, sub, desc, btn_text, reason, str(short_only)])
	_cost.set_cost(cost, " ")
	if sig == _sig:
		return
	_sig = sig
	_title.text = title
	_sub.text = sub
	_desc.text = desc
	_desc.visible = desc != ""
	_btn.text = btn_text
	_btn.disabled = reason != ""
	_why.text = "" if reason == "" or short_only else reason
	_why.visible = _why.text != ""
	var ok: bool = reason == ""
	add_theme_stylebox_override("panel", BenchKit.holo(Color(BenchKit.OK, 0.65) if ok else Color(BenchKit.HOLO, 0.22), BenchKit.CARD_BG, 0.9 if ok else 0.2, 10, 12))
