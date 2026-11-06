class_name CoreMeter
extends VBoxContainer
## Tiny Bloom Core readout (story/core_charge.gd): a caption "BLOOM CORE  37%" over a hairline
## charge bar. Self-contained so any HUD layout can place it; feed it with set_charge(0..1).
## Low charge (< 15%) blinks amber; charged reads green.

const LOW := 0.15
const GREEN := Color(0.45, 1.0, 0.6)
const AMBER := Color(1.0, 0.62, 0.25)

var _label: Label
var _bar: ProgressBar
var _fill: StyleBoxFlat
var _charge: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	custom_minimum_size = Vector2(150, 0)
	_label = UITheme.label("BLOOM CORE", 12, UITheme.MUTED)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill = StyleBoxFlat.new()
	_fill.bg_color = GREEN
	_bar.add_theme_stylebox_override("fill", _fill)
	add_child(_bar)
	set_charge(_charge)


func set_charge(f: float) -> void:
	_charge = clampf(f, 0.0, 1.0)
	if _bar == null:
		return
	_bar.value = _charge
	_label.text = "BLOOM CORE   %d%%" % int(floor(_charge * 100.0 + 0.001))
	_fill.bg_color = AMBER if _charge < LOW else GREEN


func _process(delta: float) -> void:
	_t += delta
	var low: bool = _charge < LOW
	var c: Color = (AMBER if fmod(_t, 1.2) < 0.8 else UITheme.MUTED) if low else GREEN
	_label.add_theme_color_override("font_color", c)
