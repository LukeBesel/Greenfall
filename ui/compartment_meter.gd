class_name CompartmentMeter
extends Control
## Horizontal compartment gauge with the Perfect band and the fill line.

var fill: float = 0.0
var capacity: float = 10.0
var band: Array = [0.9, 1.0]
var _shake: float = 0.0
var _shown: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(380, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(p_fill: float, p_cap: float) -> void:
	if p_fill >= p_cap and fill >= p_cap and is_equal_approx(p_fill, fill):
		_shake = 0.3  # tried to scoop while full
	fill = p_fill
	capacity = p_cap


func _process(delta: float) -> void:
	_shown = lerpf(_shown, fill / maxf(capacity, 0.01), clampf(delta * 14.0, 0.0, 1.0))
	_shake = maxf(0.0, _shake - delta)
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var off := Vector2(sin(_pulse * 70.0) * 6.0 * _shake, 0)
	var w: float = size.x
	var h: float = size.y
	var scale_max: float = 1.15  # bar shows up to 115% so overflow is visible
	var bg := Rect2(off, Vector2(w, h))
	draw_style_box(UITheme.box(Color(0.1, 0.07, 0.14, 0.95), Color(0.85, 0.48, 0.25), 3, 10, 0), bg)
	var b0: float = float(band[0]) / scale_max * w
	var b1: float = float(band[1]) / scale_max * w
	draw_rect(Rect2(off + Vector2(b0, 3), Vector2(b1 - b0, h - 6)), Color(1.0, 0.82, 0.3, 0.28 + 0.1 * sin(_pulse * 5.0)))
	var r: float = _shown
	var col: Color = Color(0.45, 0.9, 0.5)
	if r > float(band[1]) + 0.0001:
		col = Color(1.0, 0.4, 0.35)
	elif r >= float(band[0]):
		col = Color(1.0, 0.85, 0.3)
	var fw: float = clampf(r / scale_max, 0.0, 1.0) * (w - 8)
	if fw > 1.0:
		draw_style_box(UITheme.box(col, Color(0, 0, 0, 0), 0, 7, 0), Rect2(off + Vector2(4, 4), Vector2(fw, h - 8)))
		draw_rect(Rect2(off + Vector2(6, 6), Vector2(maxf(fw - 4, 0), (h - 8) * 0.3)), Color(1, 1, 1, 0.25))
	# Fill line at 100%.
	draw_line(off + Vector2(b1, -4), off + Vector2(b1, h + 4), Color(1, 1, 1, 0.95), 3.0)
