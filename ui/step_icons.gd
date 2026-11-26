class_name StepIcons
extends RefCounted
## [v9d] The objective card's picture of the thing a step is about (owner, 13 Nov: "It all needs to
## be visual and easy to understand"). Line pictures drawn in code, in the HUD's hairline style:
## the ones below are new (bin, chest, bale, tower, lantern = Glim, hex, flag = a station's
## landmark, house = the base, haulbug, flask = research, heart); every other kind is drawn by
## ResearchIcons (bot, gear, rocket, sprout, flower, drop, wave, press, recycle, book, trophy, star,
## map) or HudIcons (scoop, seed, cube, part, data, plant, water).

const OWN: Array[String] = ["bin", "chest", "bale", "tower", "lantern", "hex", "flag", "house", "haulbug", "flask", "heart"]
const RESEARCH: Array[String] = ["bot", "gear", "rocket", "sprout", "flower", "drop", "wave", "press", "recycle", "book", "trophy", "map", "star", "check", "junk"]


static func draw(ci: CanvasItem, kind: String, c: Vector2, r: float, col: Color, w: float = 2.0) -> void:
	if kind in RESEARCH:
		ResearchIcons.draw(ci, kind, c, r, col, w)
		return
	if not kind in OWN:
		HudIcons.draw(ci, kind, c, r, col, w)
		return
	var dim: Color = Color(col, 0.35)
	match kind:
		"bin":  # a trash can: tapered body, ribs, a lid with a handle
			var body := PackedVector2Array([c + Vector2(-r * 0.55, -r * 0.45), c + Vector2(r * 0.55, -r * 0.45), c + Vector2(r * 0.42, r * 0.8), c + Vector2(-r * 0.42, r * 0.8), c + Vector2(-r * 0.55, -r * 0.45)])
			ci.draw_colored_polygon(body.slice(0, 4), dim)
			ci.draw_polyline(body, col, w, true)
			for k: int in 3:
				var x: float = (float(k) - 1.0) * r * 0.25
				ci.draw_line(c + Vector2(x, -r * 0.25), c + Vector2(x * 0.85, r * 0.62), col, w * 0.7, true)
			ci.draw_line(c + Vector2(-r * 0.7, -r * 0.58), c + Vector2(r * 0.7, -r * 0.58), col, w * 1.3, true)
			ci.draw_arc(c + Vector2(0, -r * 0.62), r * 0.18, PI, TAU, 8, col, w, true)
		"chest":  # Lumi's chest: a box, its lid open a little, the latch
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.15), Vector2(r * 1.4, r * 0.85)), dim, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.15), Vector2(r * 1.4, r * 0.85)), col, false, w)
			ci.draw_line(c + Vector2(-r * 0.7, -r * 0.15), c + Vector2(-r * 0.55, -r * 0.65), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.55, -r * 0.65), c + Vector2(r * 0.85, -r * 0.55), col, w, true)
			ci.draw_line(c + Vector2(r * 0.85, -r * 0.55), c + Vector2(r * 0.7, -r * 0.15), col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.1, r * 0.05), Vector2(r * 0.2, r * 0.25)), col, true)
		"bale":  # a pressed cube with two straps
			HudIcons.draw(ci, "cube", c, r * 0.9, col, w)
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.05), c + Vector2(0, r * 0.3), Color(col, 0.8), w * 0.8, true)
			ci.draw_line(c + Vector2(0, r * 0.3), c + Vector2(r * 0.6, -r * 0.05), Color(col, 0.8), w * 0.8, true)
		"tower":  # the signal tower: a lattice mast and two signal arcs
			var top: Vector2 = c + Vector2(0, -r * 0.45)
			ci.draw_line(top, c + Vector2(-r * 0.45, r * 0.85), col, w, true)
			ci.draw_line(top, c + Vector2(r * 0.45, r * 0.85), col, w, true)
			for k: int in 3:
				var y: float = r * (-0.1 + 0.32 * float(k))
				var hw: float = r * 0.45 * (y + r * 0.45) / (r * 1.3)
				ci.draw_line(c + Vector2(-hw, y), c + Vector2(hw, y), col, w * 0.7, true)
			ci.draw_circle(top, r * 0.1, col)
			ci.draw_arc(top, r * 0.35, -PI * 0.85, -PI * 0.15, 10, col, w * 0.8, true)
			ci.draw_arc(top, r * 0.6, -PI * 0.8, -PI * 0.2, 12, Color(col, 0.7), w * 0.8, true)
		"lantern":  # Glim: a small round lantern, its handle and its glow
			ci.draw_circle(c + Vector2(0, r * 0.15), r * 0.42, dim)
			ci.draw_arc(c + Vector2(0, r * 0.15), r * 0.42, 0.0, TAU, 20, col, w, true)
			ci.draw_circle(c + Vector2(0, r * 0.15), r * 0.14, col)
			ci.draw_arc(c + Vector2(0, -r * 0.3), r * 0.22, PI, TAU, 10, col, w, true)
			for k: int in 5:
				var a: float = -PI * 0.5 + (float(k) - 2.0) * 0.55 + PI
				var d: Vector2 = Vector2(cos(a), sin(a))
				ci.draw_line(c + Vector2(0, r * 0.15) + d * r * 0.58, c + Vector2(0, r * 0.15) + d * r * 0.8, Color(col, 0.7), w * 0.7, true)
		"hex":  # a ground hex, a sparkle inside (clean ground)
			var pts := PackedVector2Array()
			for k: int in 7:
				var a: float = TAU * float(k) / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.8)
			ci.draw_colored_polygon(pts.slice(0, 6), dim)
			ci.draw_polyline(pts, col, w, true)
			ci.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.3), col, w, true)
			ci.draw_line(c + Vector2(-r * 0.3, 0), c + Vector2(r * 0.3, 0), col, w, true)
		"flag":  # a station's landmark: a pole and its pennant
			ci.draw_line(c + Vector2(-r * 0.35, r * 0.8), c + Vector2(-r * 0.35, -r * 0.75), col, w * 1.2, true)
			var fl := PackedVector2Array([c + Vector2(-r * 0.35, -r * 0.75), c + Vector2(r * 0.6, -r * 0.5), c + Vector2(-r * 0.35, -r * 0.2)])
			ci.draw_colored_polygon(fl, Color(col, 0.6))
			ci.draw_line(c + Vector2(-r * 0.7, r * 0.8), c + Vector2(r * 0.2, r * 0.8), col, w, true)
		"house":  # the base
			var hs := PackedVector2Array([c + Vector2(-r * 0.65, -r * 0.05), c + Vector2(0, -r * 0.7), c + Vector2(r * 0.65, -r * 0.05), c + Vector2(r * 0.5, -r * 0.05), c + Vector2(r * 0.5, r * 0.75), c + Vector2(-r * 0.5, r * 0.75), c + Vector2(-r * 0.5, -r * 0.05), c + Vector2(-r * 0.65, -r * 0.05)])
			ci.draw_colored_polygon(hs.slice(0, 7), dim)
			ci.draw_polyline(hs, col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.15, r * 0.3), Vector2(r * 0.3, r * 0.45)), col, false, w * 0.8)
		"haulbug":  # a low robot carrying a bale
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, r * 0.05), Vector2(r * 1.4, r * 0.4)), col, false, w)
			ci.draw_circle(c + Vector2(-r * 0.4, r * 0.58), r * 0.16, col)
			ci.draw_circle(c + Vector2(r * 0.4, r * 0.58), r * 0.16, col)
			HudIcons.draw(ci, "cube", c + Vector2(0, -r * 0.35), r * 0.42, col, w * 0.8)
		"flask":  # research
			var fk := PackedVector2Array([c + Vector2(-r * 0.15, -r * 0.75), c + Vector2(-r * 0.15, -r * 0.2), c + Vector2(-r * 0.6, r * 0.75), c + Vector2(r * 0.6, r * 0.75), c + Vector2(r * 0.15, -r * 0.2), c + Vector2(r * 0.15, -r * 0.75)])
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.38, r * 0.3), c + Vector2(-r * 0.6, r * 0.75), c + Vector2(r * 0.6, r * 0.75), c + Vector2(r * 0.38, r * 0.3)]), Color(col, 0.6))
			ci.draw_polyline(fk, col, w, true)
			ci.draw_line(c + Vector2(-r * 0.3, -r * 0.75), c + Vector2(r * 0.3, -r * 0.75), col, w, true)
		"heart":
			ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.15), r * 0.3, col)
			ci.draw_circle(c + Vector2(r * 0.25, -r * 0.15), r * 0.3, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.53, -r * 0.05), c + Vector2(r * 0.53, -r * 0.05), c + Vector2(0, r * 0.65)]), col)


## A picture as a Control: a soft tile with the line drawing in it.
class Picture extends Control:
	var kind: String = "star"
	var col: Color = Color(0.55, 0.9, 1.0)

	func _init(p_kind: String = "star", px: float = 56.0, p_col: Color = Color(0.55, 0.9, 1.0)) -> void:
		kind = p_kind
		col = p_col
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func set_kind(k: String) -> void:
		if k != kind:
			kind = k
			queue_redraw()

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		var c: Vector2 = size * 0.5
		draw_circle(c, r, Color(col, 0.1))
		draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(col, 0.45), 1.5, true)
		StepIcons.draw(self, kind, c, r * 0.62, col, maxf(1.6, r * 0.07))
