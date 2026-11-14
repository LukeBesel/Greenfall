class_name UIIcon
extends Control
## Simple vector icons drawn in code (no image assets needed). Kinds: cube, box, scoop, tread,
## stack, press, speed, auto, magnet, lock, hex.

@export var kind: String = "cube"
@export var color: Color = Color(1.0, 0.85, 0.35)


func _init(p_kind: String = "cube", p_size: float = 48.0, p_color: Color = Color(1.0, 0.85, 0.35)) -> void:
	kind = p_kind
	color = p_color
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s: Vector2 = size
	var c: Vector2 = s * 0.5
	var r: float = minf(s.x, s.y) * 0.5
	var outline := Color(0.12, 0.07, 0.18)
	draw_circle(c, r, Color(color, 0.18))
	match kind:
		"cube":
			var top := PackedVector2Array([c + Vector2(0, -r * 0.75), c + Vector2(r * 0.65, -r * 0.38), c + Vector2(0, 0), c + Vector2(-r * 0.65, -r * 0.38)])
			var left := PackedVector2Array([c + Vector2(-r * 0.65, -r * 0.38), c, c + Vector2(0, r * 0.75), c + Vector2(-r * 0.65, r * 0.38)])
			var right := PackedVector2Array([c, c + Vector2(r * 0.65, -r * 0.38), c + Vector2(r * 0.65, r * 0.38), c + Vector2(0, r * 0.75)])
			draw_colored_polygon(top, color.lightened(0.3))
			draw_colored_polygon(left, color)
			draw_colored_polygon(right, color.darkened(0.25))
		"box":
			draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.45), Vector2(r * 1.2, r * 0.9)), color)
			draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.45), Vector2(r * 1.2, r * 0.25)), color.lightened(0.3))
			draw_rect(Rect2(c + Vector2(r * 0.2, -r * 0.1), Vector2(r * 0.18, r * 0.45)), outline)
		"scoop":
			draw_arc(c + Vector2(0, -r * 0.1), r * 0.6, 0.2, PI - 0.2, 16, color, r * 0.25)
			draw_line(c + Vector2(-r * 0.7, -r * 0.6), c + Vector2(r * 0.7, -r * 0.6), color.lightened(0.3), r * 0.12)
		"tread":
			draw_rect(Rect2(c - Vector2(r * 0.75, r * 0.3), Vector2(r * 1.5, r * 0.6)), color.darkened(0.2))
			for k: int in 3:
				draw_circle(c + Vector2((k - 1) * r * 0.48, 0), r * 0.2, color.lightened(0.3))
		"stack":
			for k: int in 3:
				draw_rect(Rect2(c + Vector2(-r * 0.32 + (k % 2) * r * 0.06, r * 0.35 - k * r * 0.42), Vector2(r * 0.64, r * 0.38)), color.lightened(k * 0.12))
		"press":
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.75), Vector2(r * 1.2, r * 0.25)), color.darkened(0.2))
			draw_rect(Rect2(c + Vector2(-r * 0.1, -r * 0.5), Vector2(r * 0.2, r * 0.4)), color.darkened(0.3))
			draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.05), Vector2(r * 0.9, r * 0.55)), color)
		"speed":
			for k: int in 3:
				draw_line(c + Vector2(-r * 0.7, (k - 1) * r * 0.35), c + Vector2(r * (0.2 + k * 0.15), (k - 1) * r * 0.35), color, r * 0.15)
		"auto":
			draw_arc(c, r * 0.55, 0.3, TAU - 0.6, 24, color, r * 0.18)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.55, -r * 0.45), c + Vector2(r * 0.9, -r * 0.05), c + Vector2(r * 0.25, -r * 0.05)]), color)
		"magnet":
			draw_arc(c + Vector2(0, -r * 0.05), r * 0.45, 0.0, PI, 16, color, r * 0.3)
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.6), Vector2(r * 0.3, r * 0.5)), Color(0.95, 0.3, 0.3))
			draw_rect(Rect2(c + Vector2(r * 0.3, -r * 0.6), Vector2(r * 0.3, r * 0.5)), Color(0.95, 0.3, 0.3))
		"lock":
			draw_arc(c + Vector2(0, -r * 0.2), r * 0.3, PI, TAU, 12, color, r * 0.14)
			draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.2), Vector2(r * 0.9, r * 0.7)), color)
		"hex":
			var pts := PackedVector2Array()
			for k: int in 6:
				var a: float = TAU * k / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.75)
			draw_colored_polygon(pts, color)
		_:
			draw_circle(c, r * 0.5, color)
