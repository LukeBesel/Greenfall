class_name CollectIcon
extends Control
## [eggs2] A small drawn silhouette for a collectible (data/museum.json "shape"): coloured once it
## is in Lumi's collection, a dark outline-less silhouette while it is still missing.

var shape: String = "dot"
var found: bool = false
var tint: Color = Color(0.95, 0.75, 0.35)


func _init(shape_: String = "dot", found_: bool = false, tint_: Color = Color(0.95, 0.75, 0.35), px: float = 34.0) -> void:
	shape = shape_
	found = found_
	tint = tint_
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var o: Vector2 = (size - Vector2(s, s)) * 0.5
	var c: Color = tint if found else Color(0.2, 0.22, 0.25, 0.95)
	var c2: Color = c.lightened(0.25) if found else Color(0.28, 0.3, 0.33, 0.95)
	var u := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match shape:
		"gnome":
			draw_colored_polygon(PackedVector2Array([u.call(0.5, 0.05), u.call(0.68, 0.42), u.call(0.32, 0.42)]), c)
			draw_circle(u.call(0.5, 0.5), s * 0.12, c2)
			draw_colored_polygon(PackedVector2Array([u.call(0.3, 0.58), u.call(0.7, 0.58), u.call(0.78, 0.95), u.call(0.22, 0.95)]), c)
		"cat":
			draw_circle(u.call(0.5, 0.62), s * 0.3, c)
			draw_colored_polygon(PackedVector2Array([u.call(0.24, 0.45), u.call(0.3, 0.15), u.call(0.45, 0.36)]), c)
			draw_colored_polygon(PackedVector2Array([u.call(0.76, 0.45), u.call(0.7, 0.15), u.call(0.55, 0.36)]), c)
		"capsule":
			draw_set_transform(u.call(0.5, 0.5), -0.6, Vector2.ONE)
			draw_rect(Rect2(Vector2(-0.38, -0.14) * s, Vector2(0.76, 0.28) * s), c)
			draw_rect(Rect2(Vector2(-0.42, -0.16) * s, Vector2(0.1, 0.32) * s), c2)
			draw_rect(Rect2(Vector2(0.32, -0.16) * s, Vector2(0.1, 0.32) * s), c2)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"tv":
			draw_rect(Rect2(u.call(0.12, 0.25), Vector2(0.76, 0.56) * s), c)
			draw_rect(Rect2(u.call(0.2, 0.33), Vector2(0.5, 0.4) * s), c2)
			draw_line(u.call(0.4, 0.25), u.call(0.28, 0.05), c, 2.0)
			draw_line(u.call(0.6, 0.25), u.call(0.72, 0.05), c, 2.0)
		"duck":
			draw_circle(u.call(0.45, 0.65), s * 0.26, c)
			draw_circle(u.call(0.62, 0.35), s * 0.16, c)
			draw_colored_polygon(PackedVector2Array([u.call(0.74, 0.33), u.call(0.92, 0.38), u.call(0.74, 0.42)]), c2)
		"star":
			var pts := PackedVector2Array()
			for k: int in 10:
				var a: float = -PI * 0.5 + PI * k / 5.0
				var r: float = 0.45 if k % 2 == 0 else 0.2
				pts.append(u.call(0.5 + cos(a) * r, 0.53 + sin(a) * r))
			draw_colored_polygon(pts, c)
		"cube":
			draw_colored_polygon(PackedVector2Array([u.call(0.5, 0.1), u.call(0.88, 0.3), u.call(0.5, 0.5), u.call(0.12, 0.3)]), c2)
			draw_colored_polygon(PackedVector2Array([u.call(0.12, 0.3), u.call(0.5, 0.5), u.call(0.5, 0.92), u.call(0.12, 0.72)]), c)
			draw_colored_polygon(PackedVector2Array([u.call(0.88, 0.3), u.call(0.5, 0.5), u.call(0.5, 0.92), u.call(0.88, 0.72)]), c.darkened(0.2))
		"shard":
			draw_colored_polygon(PackedVector2Array([u.call(0.5, 0.05), u.call(0.72, 0.4), u.call(0.55, 0.95), u.call(0.3, 0.45)]), c)
			draw_colored_polygon(PackedVector2Array([u.call(0.5, 0.05), u.call(0.72, 0.4), u.call(0.52, 0.45)]), c2)
		"box":
			draw_rect(Rect2(u.call(0.15, 0.35), Vector2(0.7, 0.5) * s), c)
			draw_rect(Rect2(u.call(0.1, 0.25), Vector2(0.8, 0.14) * s), c2)
			draw_rect(Rect2(u.call(0.45, 0.25), Vector2(0.1, 0.6) * s), c.darkened(0.25))
		"gem":
			draw_colored_polygon(PackedVector2Array([u.call(0.25, 0.3), u.call(0.75, 0.3), u.call(0.9, 0.45), u.call(0.5, 0.92), u.call(0.1, 0.45)]), c)
			draw_colored_polygon(PackedVector2Array([u.call(0.25, 0.3), u.call(0.75, 0.3), u.call(0.62, 0.45), u.call(0.38, 0.45)]), c2)
		_:
			draw_circle(u.call(0.5, 0.5), s * 0.35, c)
