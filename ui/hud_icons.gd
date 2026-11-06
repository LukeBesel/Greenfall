class_name HudIcons
extends RefCounted
## Thin line icons for the HUD (hotbar tools, currencies, lock), drawn in code onto any
## CanvasItem: draw(ci, kind, centre, radius, colour). Hairline strokes, no fills heavier than
## a soft tint, so they match the thin-glow look.


static func draw(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color, w: float = 1.6) -> void:
	match kind:
		"scoop":
			# Tractor emitter: a dish over three converging beam lines and a falling piece.
			ci.draw_arc(c + Vector2(0, -r * 0.35), r * 0.62, PI * 0.08, PI * 0.92, 18, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.7, -r * 0.42), c + Vector2(r * 0.7, -r * 0.42), col, w, true)
			for k: int in 3:
				var x: float = (k - 1) * r * 0.42
				ci.draw_line(c + Vector2(x * 0.45, -r * 0.05), c + Vector2(x, r * 0.55), Color(col, 0.55), w * 0.8, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.16, r * 0.52), Vector2(r * 0.32, r * 0.28)), col, false, w)
		"plant":
			# Sprout: stem and two leaves out of a soil line.
			ci.draw_line(c + Vector2(-r * 0.62, r * 0.68), c + Vector2(r * 0.62, r * 0.68), Color(col, 0.6), w, true)
			ci.draw_line(c + Vector2(0, r * 0.68), c + Vector2(0, -r * 0.1), col, w, true)
			_leaf(ci, c + Vector2(0, -r * 0.05), Vector2(-r * 0.62, -r * 0.5), col, w)
			_leaf(ci, c + Vector2(0, -r * 0.25), Vector2(r * 0.58, -r * 0.62), col, w)
		"water":
			# Droplet: a round bottom that tapers to a point.
			var cc: Vector2 = c + Vector2(0, r * 0.22)
			var rr: float = r * 0.5
			var tip: Vector2 = c + Vector2(0, -r * 0.78)
			ci.draw_arc(cc, rr, -PI / 6.0, PI + PI / 6.0, 20, col, w, true)
			ci.draw_line(cc + Vector2(cos(-PI / 6.0), sin(-PI / 6.0)) * rr, tip, col, w, true)
			ci.draw_line(cc + Vector2(cos(PI + PI / 6.0), sin(PI + PI / 6.0)) * rr, tip, col, w, true)
			ci.draw_arc(cc, rr * 0.6, PI * 0.55, PI * 0.95, 8, Color(col, 0.6), w * 0.8, true)
		"cube":
			var t := c + Vector2(0, -r * 0.8)
			var l := c + Vector2(-r * 0.72, -r * 0.4)
			var rr := c + Vector2(r * 0.72, -r * 0.4)
			var m := c
			var b := c + Vector2(0, r * 0.8)
			ci.draw_colored_polygon(PackedVector2Array([t, rr, m, l]), Color(col, 0.22))
			ci.draw_polyline(PackedVector2Array([t, rr, rr + Vector2(0, r * 0.8), b, l + Vector2(0, r * 0.8), l, t]), col, w, true)
			ci.draw_polyline(PackedVector2Array([l, m, rr]), col, w, true)
			ci.draw_line(m, b, col, w, true)
		"seed":
			ci.draw_arc(c, r * 0.5, 0.0, TAU, 20, col, w, true)
			ci.draw_line(c + Vector2(0, -r * 0.5), c + Vector2(r * 0.25, -r * 0.85), col, w, true)
		"compost":
			for k: int in 3:
				ci.draw_arc(c + Vector2((k - 1) * r * 0.42, r * 0.2 - (k % 2) * r * 0.32), r * 0.3, 0.0, TAU, 12, col, w, true)
		"data":
			for k: int in 3:
				var h: float = r * (0.5 + k * 0.35)
				ci.draw_line(c + Vector2((k - 1) * r * 0.5, r * 0.65), c + Vector2((k - 1) * r * 0.5, r * 0.65 - h), col, w * 1.3, true)
		"token":
			var hex := PackedVector2Array()
			for k: int in 7:
				var a: float = TAU * k / 6.0 + PI / 6.0
				hex.append(c + Vector2(cos(a), sin(a)) * r * 0.72)
			ci.draw_polyline(hex, col, w, true)
			ci.draw_circle(c, r * 0.18, col)
		"part":
			ci.draw_arc(c, r * 0.42, 0.0, TAU, 20, col, w, true)
			for k: int in 6:
				var a: float = TAU * k / 6.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * r * 0.5, c + d * r * 0.78, col, w * 1.4, true)
			ci.draw_circle(c, r * 0.14, col)
		"lock":
			ci.draw_arc(c + Vector2(0, -r * 0.15), r * 0.3, PI, TAU, 12, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.3, -r * 0.15), c + Vector2(-r * 0.3, 0), col, w, true)
			ci.draw_line(c + Vector2(r * 0.3, -r * 0.15), c + Vector2(r * 0.3, 0), col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.45, 0), Vector2(r * 0.9, r * 0.62)), col, false, w)
		"star":
			var s := PackedVector2Array()
			for k: int in 11:
				var a: float = -PI * 0.5 + TAU * k / 10.0
				s.append(c + Vector2(cos(a), sin(a)) * (r * 0.8 if k % 2 == 0 else r * 0.35))
			ci.draw_polyline(s, col, w, true)
		_:
			ci.draw_arc(c, r * 0.5, 0.0, TAU, 16, col, w, true)


static func _leaf(ci: CanvasItem, base: Vector2, tip_off: Vector2, col: Color, w: float) -> void:
	var tip: Vector2 = base + tip_off
	var n: Vector2 = Vector2(-tip_off.y, tip_off.x).normalized() * tip_off.length() * 0.28
	var a := PackedVector2Array()
	var b := PackedVector2Array()
	for k: int in 9:
		var t: float = k / 8.0
		var p: Vector2 = base.lerp(tip, t)
		var bulge: float = sin(t * PI)
		a.append(p + n * bulge)
		b.append(p - n * bulge)
	ci.draw_colored_polygon(_join(a, b), Color(col, 0.22))
	ci.draw_polyline(a, col, w, true)
	ci.draw_polyline(b, col, w, true)


static func _join(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(a)
	for i: int in range(b.size() - 1, -1, -1):
		out.append(b[i])
	return out


## Icon kind for a currency id.
static func currency_kind(id: String) -> String:
	match id:
		"cubes": return "cube"
		"seeds": return "seed"
		"compost": return "compost"
		"data": return "data"
		"tokens": return "token"
	return "part"
