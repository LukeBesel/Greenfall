class_name ResearchStrip
extends VBoxContainer
## HUD readout of the research Lumi's work is feeding: "RESEARCH  WIDE BEAM  34/45" over a hairline
## field-data bar, with the last gain ticking beside it ("+4"). With no node active but research
## open it says how much data waits in the bank (amber: needs attention). Hidden until the
## workbench's Research tab exists. Reads Research / FieldData; listens to field_data_gained.

const AMBER := Color(1.0, 0.62, 0.25)
const GAIN_SHOW_S: float = 1.6
const REFRESH_S: float = 0.25

var _label: Label
var _gain: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat
var _gain_t: float = 0.0
var _gain_sum: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	custom_minimum_size = Vector2(200, 0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_gain = UITheme.label("", 12, UITheme.GOLD)
	row.add_child(_gain)
	_label = UITheme.label("", 12, UITheme.CREAM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = StyleBoxFlat.new()
	_fill.bg_color = UITheme.GOLD
	_bar.add_theme_stylebox_override("fill", _fill)
	add_child(_bar)
	EventBus.field_data_gained.connect(_on_gained)
	refresh()


func _exit_tree() -> void:
	if EventBus.field_data_gained.is_connected(_on_gained):
		EventBus.field_data_gained.disconnect(_on_gained)


func _process(delta: float) -> void:
	if _gain_t > 0.0:
		_gain_t -= delta
		if _gain_t <= 0.0:
			_gain_sum = 0.0
			_gain.text = ""
	_t += delta
	if _t >= REFRESH_S:
		_t = 0.0
		refresh()


func refresh() -> void:
	var open: bool = BenchTiers.tab_open("research")
	var aid: String = Research.active_id()
	visible = open
	if not open:
		return
	if aid != "":
		_label.text = tr("RESEARCH  %s  %d/%d") % [tr(str(Research.def(aid).get("name", aid))).to_upper(),
			int(floor(FieldData.put_in(aid))), int(ceil(Research.data_cost(aid)))]
		_label.add_theme_color_override("font_color", UITheme.CREAM)
		_bar.value = Research.progress(aid)
		_bar.visible = true
	else:
		_label.text = tr("RESEARCH  PICK A NODE  ·  %d DATA BANKED") % int(floor(FieldData.bank()))
		_label.add_theme_color_override("font_color", AMBER)
		_bar.visible = false


func _on_gained(amount: float, _kind: String) -> void:
	_gain_sum += amount
	_gain_t = GAIN_SHOW_S
	_gain.text = "+%d" % int(round(_gain_sum)) if _gain_sum >= 1.0 else "+%.1f" % _gain_sum
