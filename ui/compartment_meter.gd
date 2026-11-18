class_name CompartmentMeter
extends Control
## Thin hopper gauge: hairline track, fill, the Perfect band as a faint amber zone, and the fill line.

var fill: float = 0.0
var capacity: float = 10.0
var band: Array = [0.9, 1.0]
var _shake: float = 0.0
var _shown: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(340, 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(p_fill: float, p_cap: float) -> void:
	if p_fill >= p_cap and fill >= p_cap and is_equal_approx(p_fill, fill):
		_shake = 0.25
	fill = p_fill
	capacity = p_cap


func _process(delta: float) -> void:
	_shown = lerpf(_shown, fill / maxf(capacity, 0.01), clampf(delta * 12.0, 0.0, 1.0))
	_shake = maxf(0.0, _shake - delta)
	queue_redraw()


func _draw() -> void:
	var off := Vector2(sin(Time.get_ticks_msec() * 0.08) * 4.0 * _shake, 0)
	var w: float = size.x
	var h: float = 4.0
	var y: float = (size.y - h) * 0.5
	var scale_max: float = 1.15
	draw_rect(Rect2(off + Vector2(0, y), Vector2(w, h)), Color(1, 1, 1, 0.1))
	var b0: float = float(band[0]) / scale_max * w
	var b1: float = float(band[1]) / scale_max * w
	var pal: Dictionary = UITheme.meter_colors()
	draw_rect(Rect2(off + Vector2(b0, y - 2), Vector2(b1 - b0, h + 4)), pal["band"])
	var r: float = _shown
	var col: Color = Color(0.9, 0.9, 0.87)
	if r > float(band[1]) + 0.0001:
		col = pal["over"]
	elif r >= float(band[0]):
		col = pal["good"]
	draw_rect(Rect2(off + Vector2(0, y), Vector2(clampf(r / scale_max, 0.0, 1.0) * w, h)), col)
	draw_line(off + Vector2(b1, y - 4), off + Vector2(b1, y + h + 4), Color(1, 1, 1, 0.7), 1.0)
