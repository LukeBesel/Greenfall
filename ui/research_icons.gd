class_name ResearchIcons
extends RefCounted
## Little line icons for research nodes, codex entries and achievements, drawn in code.
## Kinds: beam, hopper, sort, magnet, tractor, chip, bot, gear, swarm, sprout, leaf, flower, tree,
## drop, wave, pipe, data, belt, press, recycle, rocket, star, lock, check, book, map, trophy, junk.


static func draw(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color, w: float = 2.0) -> void:
	match kind:
		"beam":
			ci.draw_arc(c + Vector2(0, r * 0.1), r * 0.55, PI * 1.1, PI * 1.9, 14, col, w, true)
			for k: int in 3:
				var a: float = PI * (1.3 + k * 0.2)
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.75, c + Vector2(cos(a), sin(a)) * r * 1.0, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.5, r * 0.55), c + Vector2(r * 0.5, r * 0.55), col, w, true)
		"hopper":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.5), c + Vector2(-r * 0.4, r * 0.6), c + Vector2(r * 0.4, r * 0.6), c + Vector2(r * 0.75, -r * 0.5)]), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.85, -r * 0.5), c + Vector2(r * 0.85, -r * 0.5), col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.2, -r * 0.2), Vector2(r * 0.4, r * 0.4)), Color(col, 0.6))
		"sort":
			for k: int in 3:
				var y: float = (k - 1) * r * 0.5
				ci.draw_line(c + Vector2(-r * 0.7, y), c + Vector2(r * 0.3, y), col, w, true)
				ci.draw_circle(c + Vector2(r * 0.6, y), r * 0.14, Color(col, 0.5 + k * 0.25))
		"magnet":
			ci.draw_arc(c + Vector2(0, -r * 0.05), r * 0.5, 0.0, PI, 14, col, w * 1.6, true)
			ci.draw_line(c + Vector2(-r * 0.5, -r * 0.05), c + Vector2(-r * 0.5, -r * 0.6), col, w * 1.6, true)
			ci.draw_line(c + Vector2(r * 0.5, -r * 0.05), c + Vector2(r * 0.5, -r * 0.6), col, w * 1.6, true)
			ci.draw_line(c + Vector2(-r * 0.68, -r * 0.6), c + Vector2(-r * 0.32, -r * 0.6), Color(1, 0.45, 0.4), w * 1.6, true)
			ci.draw_line(c + Vector2(r * 0.32, -r * 0.6), c + Vector2(r * 0.68, -r * 0.6), Color(1, 0.45, 0.4), w * 1.6, true)
		"tractor":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.2, -r * 0.7), c + Vector2(r * 0.2, -r * 0.7), c + Vector2(r * 0.7, r * 0.6), c + Vector2(-r * 0.7, r * 0.6)]), Color(col, 0.22))
			ci.draw_line(c + Vector2(-r * 0.45, -r * 0.75), c + Vector2(r * 0.45, -r * 0.75), col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.18, r * 0.05), Vector2(r * 0.36, r * 0.36)), col)
		"chip":
			ci.draw_rect(Rect2(c - Vector2(r * 0.45, r * 0.45), Vector2(r * 0.9, r * 0.9)), col, false, w)
			ci.draw_rect(Rect2(c - Vector2(r * 0.18, r * 0.18), Vector2(r * 0.36, r * 0.36)), col)
			for k: int in 3:
				var o: float = (k - 1) * r * 0.3
				ci.draw_line(c + Vector2(o, -r * 0.45), c + Vector2(o, -r * 0.75), col, w, true)
				ci.draw_line(c + Vector2(o, r * 0.45), c + Vector2(o, r * 0.75), col, w, true)
				ci.draw_line(c + Vector2(-r * 0.45, o), c + Vector2(-r * 0.75, o), col, w, true)
				ci.draw_line(c + Vector2(r * 0.45, o), c + Vector2(r * 0.75, o), col, w, true)
		"bot":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.35), Vector2(r * 1.1, r * 0.75)), col, false, w)
			ci.draw_circle(c + Vector2(-r * 0.22, 0.0), r * 0.12, col)
			ci.draw_circle(c + Vector2(r * 0.22, 0.0), r * 0.12, col)
			ci.draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, -r * 0.65), col, w, true)
			ci.draw_circle(c + Vector2(0, -r * 0.72), r * 0.1, col)
			ci.draw_line(c + Vector2(-r * 0.4, r * 0.62), c + Vector2(r * 0.4, r * 0.62), col, w * 1.4, true)
		"gear":
			ci.draw_arc(c, r * 0.45, 0, TAU, 20, col, w * 1.4, true)
			for k: int in 8:
				var a: float = TAU * k / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * r * 0.5, c + Vector2(cos(a), sin(a)) * r * 0.78, col, w * 1.6, true)
			ci.draw_circle(c, r * 0.14, col)
		"swarm":
			for p: Vector2 in [Vector2(-0.45, 0.3), Vector2(0.45, 0.3), Vector2(0, -0.4)]:
				ci.draw_circle(c + p * r, r * 0.2, col)
			ci.draw_arc(c, r * 0.75, 0.0, TAU, 24, Color(col, 0.5), w, true)
		"sprout":
			ci.draw_line(c + Vector2(0, r * 0.7), c + Vector2(0, -r * 0.1), col, w, true)
			_leaf(ci, c + Vector2(0, -r * 0.1), Vector2(-0.6, -0.5) * r, col)
			_leaf(ci, c + Vector2(0, r * 0.1), Vector2(0.65, -0.35) * r, col)
			ci.draw_line(c + Vector2(-r * 0.5, r * 0.7), c + Vector2(r * 0.5, r * 0.7), Color(col, 0.6), w, true)
		"leaf":
			_leaf(ci, c + Vector2(-r * 0.5, r * 0.5), Vector2(r * 1.0, -r * 1.0), col)
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.6), c + Vector2(r * 0.35, -r * 0.35), Color(0, 0, 0, 0.35), w * 0.8, true)
		"flower":
			for k: int in 5:
				var a: float = TAU * k / 5.0 - PI * 0.5
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.36 + Vector2(0, -r * 0.15), r * 0.24, Color(col, 0.85))
			ci.draw_circle(c + Vector2(0, -r * 0.15), r * 0.16, Color(1.0, 0.85, 0.35))
			ci.draw_line(c + Vector2(0, r * 0.2), c + Vector2(0, r * 0.8), col, w, true)
		"tree":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.8), c + Vector2(r * 0.55, r * 0.15), c + Vector2(-r * 0.55, r * 0.15)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.45), c + Vector2(r * 0.7, r * 0.5), c + Vector2(-r * 0.7, r * 0.5)]), Color(col, 0.75))
			ci.draw_line(c + Vector2(0, r * 0.5), c + Vector2(0, r * 0.8), col, w * 1.5, true)
		"drop":
			var pts := PackedVector2Array()
			for k: int in 17:
				var a: float = PI * k / 16.0
				pts.append(c + Vector2(cos(a) * r * 0.48, r * 0.2 + sin(a) * r * 0.48))
			pts.append(c + Vector2(0, -r * 0.8))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c + Vector2(-r * 0.16, r * 0.15), r * 0.09, Color(1, 1, 1, 0.6))
		"wave":
			for k: int in 3:
				var pts := PackedVector2Array()
				for i: int in 13:
					var x: float = -0.75 + i * 0.125
					pts.append(c + Vector2(x * r, (k - 1) * r * 0.42 + sin(x * 7.0) * r * 0.1))
				ci.draw_polyline(pts, Color(col, 1.0 - k * 0.22), w, true)
		"pipe":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.35), c + Vector2(r * 0.1, -r * 0.35), c + Vector2(r * 0.1, r * 0.45), c + Vector2(r * 0.75, r * 0.45)]), col, w * 2.2, true)
			ci.draw_circle(c + Vector2(r * 0.55, r * 0.75), r * 0.1, col)
		"data":
			for k: int in 3:
				ci.draw_arc(c + Vector2(0, (k - 1) * r * 0.42), r * 0.6, 0.0, PI, 14, Color(col, 0.9 - k * 0.15), w, true)
			ci.draw_arc(c + Vector2(0, -r * 0.42), r * 0.6, PI, TAU, 14, col, w, true)
		"belt":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.18), Vector2(r * 1.6, r * 0.36)), col, false, w)
			for k: int in 4:
				ci.draw_circle(c + Vector2(-r * 0.6 + k * r * 0.4, 0), r * 0.08, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.25, -r * 0.62), Vector2(r * 0.4, r * 0.4)), Color(col, 0.7))
		"press":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.75), Vector2(r * 1.2, r * 0.22)), col)
			ci.draw_line(c + Vector2(0, -r * 0.55), c + Vector2(0, -r * 0.15), col, w * 2.0, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.05), Vector2(r * 0.9, r * 0.6)), Color(col, 0.75))
		"recycle":
			for k: int in 3:
				var a0: float = TAU * k / 3.0 - PI * 0.5
				ci.draw_arc(c, r * 0.6, a0 + 0.25, a0 + TAU / 3.0 - 0.25, 10, col, w * 1.3, true)
				var tip: Vector2 = c + Vector2(cos(a0 + TAU / 3.0 - 0.25), sin(a0 + TAU / 3.0 - 0.25)) * r * 0.6
				var tan := Vector2(-sin(a0 + TAU / 3.0 - 0.25), cos(a0 + TAU / 3.0 - 0.25))
				ci.draw_colored_polygon(PackedVector2Array([tip + tan * r * 0.2, tip + (tip - c).normalized() * r * 0.16, tip - (tip - c).normalized() * r * 0.16]), col)
		"rocket":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.28, -r * 0.35), c + Vector2(r * 0.28, r * 0.4), c + Vector2(-r * 0.28, r * 0.4), c + Vector2(-r * 0.28, -r * 0.35)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.28, r * 0.05), c + Vector2(-r * 0.55, r * 0.55), c + Vector2(-r * 0.28, r * 0.4)]), Color(col, 0.7))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.28, r * 0.05), c + Vector2(r * 0.55, r * 0.55), c + Vector2(r * 0.28, r * 0.4)]), Color(col, 0.7))
			ci.draw_circle(c + Vector2(0, -r * 0.15), r * 0.12, Color(0.1, 0.12, 0.15))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.16, r * 0.45), c + Vector2(r * 0.16, r * 0.45), c + Vector2(0, r * 0.85)]), Color(1.0, 0.6, 0.2))
		"star":
			var pts := PackedVector2Array()
			for k: int in 10:
				var a: float = TAU * k / 10.0 - PI * 0.5
				pts.append(c + Vector2(cos(a), sin(a)) * r * (0.8 if k % 2 == 0 else 0.36))
			ci.draw_colored_polygon(pts, col)
		"trophy":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.65), c + Vector2(r * 0.5, -r * 0.65), c + Vector2(r * 0.35, -r * 0.05), c + Vector2(0, r * 0.15), c + Vector2(-r * 0.35, -r * 0.05)]), col)
			ci.draw_arc(c + Vector2(-r * 0.5, -r * 0.4), r * 0.22, PI * 0.5, PI * 1.5, 8, col, w, true)
			ci.draw_arc(c + Vector2(r * 0.5, -r * 0.4), r * 0.22, -PI * 0.5, PI * 0.5, 8, col, w, true)
			ci.draw_line(c + Vector2(0, r * 0.15), c + Vector2(0, r * 0.5), col, w * 1.5, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.35, r * 0.5), Vector2(r * 0.7, r * 0.2)), col)
		"lock":
			ci.draw_arc(c + Vector2(0, -r * 0.15), r * 0.3, PI, TAU, 12, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.3, -r * 0.15), c + Vector2(-r * 0.3, r * 0.05), col, w, true)
			ci.draw_line(c + Vector2(r * 0.3, -r * 0.15), c + Vector2(r * 0.3, r * 0.05), col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, r * 0.05), Vector2(r * 0.9, r * 0.6)), col)
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, 0), c + Vector2(-r * 0.12, r * 0.4), c + Vector2(r * 0.55, -r * 0.4)]), col, w * 1.5, true)
		"book":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.5), Vector2(r * 0.65, r * 1.0)), col, false, w)
			ci.draw_rect(Rect2(c + Vector2(r * 0.05, -r * 0.5), Vector2(r * 0.65, r * 1.0)), col, false, w)
			for k: int in 3:
				ci.draw_line(c + Vector2(-r * 0.55, -r * 0.25 + k * r * 0.25), c + Vector2(-r * 0.2, -r * 0.25 + k * r * 0.25), Color(col, 0.6), w * 0.7, true)
		"map":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.5), c + Vector2(-r * 0.25, -r * 0.65), c + Vector2(r * 0.25, -r * 0.5), c + Vector2(r * 0.75, -r * 0.65), c + Vector2(r * 0.75, r * 0.5), c + Vector2(r * 0.25, r * 0.65), c + Vector2(-r * 0.25, r * 0.5), c + Vector2(-r * 0.75, r * 0.65), c + Vector2(-r * 0.75, -r * 0.5)]), col, w, true)
			ci.draw_circle(c + Vector2(r * 0.1, 0), r * 0.14, Color(1.0, 0.5, 0.35))
		"junk":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 0.5, r * 0.6)), col, false, w)
			ci.draw_circle(c + Vector2(r * 0.3, r * 0.25), r * 0.28, Color(col, 0.7))
			ci.draw_line(c + Vector2(-r * 0.2, -r * 0.6), c + Vector2(r * 0.5, -r * 0.3), col, w * 1.4, true)
		_:
			ci.draw_circle(c, r * 0.4, col)


static func _leaf(ci: CanvasItem, base: Vector2, tip: Vector2, col: Color) -> void:
	var n := Vector2(-tip.y, tip.x).normalized() * tip.length() * 0.3
	var pts := PackedVector2Array()
	for i: int in 9:
		var t: float = i / 8.0
		pts.append(base + tip * t + n * sin(t * PI))
	for i: int in range(7, 0, -1):
		var t: float = i / 8.0
		pts.append(base + tip * t - n * sin(t * PI))
	ci.draw_colored_polygon(pts, col)


## A Control that shows one icon (optionally on a soft disc).
class IconView extends Control:
	var kind: String
	var color: Color
	var disc: bool

	func _init(p_kind: String = "data", p_size: float = 32.0, p_color: Color = Color(1.0, 0.7, 0.26), p_disc: bool = true) -> void:
		kind = p_kind
		color = p_color
		disc = p_disc
		custom_minimum_size = Vector2(p_size, p_size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		if disc:
			draw_circle(size * 0.5, r, Color(color, 0.14))
		ResearchIcons.draw(self, kind, size * 0.5, r * 0.78, color, maxf(1.5, r * 0.09))
