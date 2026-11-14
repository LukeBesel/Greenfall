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
			_cube(ci, c, r, col, w)  # [ui2]
		"seed":
			_seed(ci, c, r, col, w)  # [ui2]
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
			_gear(ci, c, r, col, w)  # [ui2]
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


# --- [ui2] Currency glyphs: crisp hairlines with a thin glow and soft facet tints -------------

## The same path twice: a wide faint stroke (the glow), then the crisp hairline.
static func _glow(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	ci.draw_polyline(pts, Color(col, 0.13), w * 3.4, true)
	ci.draw_polyline(pts, col, w, true)


## Cube: an isometric cube with three shaded facets, a glowing silhouette, the inner Y edges and
## a small highlight where the top meets the front.
static func _cube(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	var h: float = r * 0.84
	var hw: float = r * 0.74
	var t := c + Vector2(0, -h)
	var tl := c + Vector2(-hw, -h * 0.5)
	var tr := c + Vector2(hw, -h * 0.5)
	var m := c
	var bl := c + Vector2(-hw, h * 0.5)
	var br := c + Vector2(hw, h * 0.5)
	var b := c + Vector2(0, h)
	ci.draw_colored_polygon(PackedVector2Array([t, tr, m, tl]), Color(col, 0.34))
	ci.draw_colored_polygon(PackedVector2Array([tl, m, b, bl]), Color(col, 0.17))
	ci.draw_colored_polygon(PackedVector2Array([m, tr, br, b]), Color(col, 0.07))
	_glow(ci, PackedVector2Array([t, tr, br, b, bl, tl, t]), col, w)
	ci.draw_polyline(PackedVector2Array([tl, m, tr]), Color(col, 0.8), w * 0.85, true)
	ci.draw_line(m, b, Color(col, 0.8), w * 0.85, true)
	ci.draw_circle(m, maxf(w * 0.9, r * 0.07), Color(1, 1, 1, 0.85).lerp(col, 0.3))


## Parts: an eight-tooth gear with a hex bolt hole.
static func _gear(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	var ro: float = r * 0.9
	var ri: float = r * 0.68
	var n: int = 8
	var step: float = TAU / n
	var pts := PackedVector2Array()
	for i: int in n:
		var a: float = i * step - PI * 0.5
		for k: Array in [[ri, -0.32], [ro, -0.19], [ro, 0.19], [ri, 0.32]]:
			var ang: float = a + step * float(k[1])
			pts.append(c + Vector2(cos(ang), sin(ang)) * float(k[0]))
	var fill := PackedVector2Array(pts)
	pts.append(pts[0])
	ci.draw_colored_polygon(fill, Color(col, 0.2))
	_glow(ci, pts, col, w)
	var hexp := PackedVector2Array()
	for k: int in 7:
		var ang2: float = TAU * k / 6.0
		hexp.append(c + Vector2(cos(ang2), sin(ang2)) * r * 0.3)
	ci.draw_colored_polygon(hexp.slice(0, 6), Color(0.02, 0.03, 0.04, 0.55))
	ci.draw_polyline(hexp, col, w * 0.9, true)
	ci.draw_arc(c, r * 0.5, -PI * 0.95, -PI * 0.55, 8, Color(1, 1, 1, 0.5).lerp(col, 0.4), w * 0.8, true)


## Seeds: a plump seed with its seam, and a sprout with one leaf curling out of the top.
static func _seed(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	var body := PackedVector2Array()
	var cc: Vector2 = c + Vector2(0, r * 0.28)
	for k: int in 25:
		var a: float = TAU * k / 24.0
		# An egg: rounder at the bottom, a little pointed at the top, tilted a touch.
		var rr: float = r * (0.5 + 0.06 * sin(a))
		var p := Vector2(cos(a) * rr * 0.82, sin(a) * rr * (1.0 if sin(a) > 0.0 else 1.18))
		body.append(cc + p.rotated(0.32))
	ci.draw_colored_polygon(body.slice(0, 24), Color(col, 0.24))
	_glow(ci, body, col, w)
	var top: Vector2 = cc + Vector2(0, -r * 0.59).rotated(0.32)
	var bot: Vector2 = cc + Vector2(0, r * 0.42).rotated(0.32)
	ci.draw_line(top.lerp(bot, 0.18), top.lerp(bot, 0.85), Color(col, 0.6), w * 0.8, true)
	var stem := PackedVector2Array()
	for k: int in 9:
		var t: float = k / 8.0
		stem.append(top + Vector2(-r * 0.12 * sin(t * PI), -r * 0.42 * t))
	ci.draw_polyline(stem, col, w, true)
	_leaf(ci, stem[stem.size() - 1], Vector2(r * 0.46, -r * 0.16), col, w * 0.9)


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
	return Currencies.icon(id)  # [money] three currencies, one source of truth (data/currencies.json)
