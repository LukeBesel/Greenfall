class_name FieldPlate
extends PanelContainer
## A plate of Lumi's field instrument (docs/STYLE.md section 10): a dark slate rectangle with one
## clipped corner, a thin engraved edge and two rivets, drawn here so any container can sit on
## it. Also the instrument's colours and the small widgets built from them (stencilled section
## labels, engraved rules, flat mechanical buttons).

const SLATE := Color(0.098, 0.118, 0.137, 0.9)
const SLATE_RAISED := Color(0.16, 0.185, 0.21, 0.92)
const EDGE := Color(0.72, 0.75, 0.74, 0.34)
const RULE := Color(0.72, 0.75, 0.74, 0.22)
## Warm off-white text, and its quieter step for secondary lines.
const INK := Color(0.95, 0.93, 0.87)
const INK_DIM := Color(0.7, 0.71, 0.68)
## Lumi cyan: interactive and "yours". Hazard amber: needs attention. Growth green: restored.
const CYAN := Color(0.33, 0.87, 0.95)
const AMBER := Color(1.0, 0.72, 0.22)
const GREEN := Color(0.56, 0.87, 0.5)
## An unfound thing: the dark silhouette and its backing.
const SHADOW := Color(0.045, 0.055, 0.065)
const LABEL_PX: int = 16
const SENTENCE_PX: int = 18
const TOUCH_PX: float = 44.0
const EASE_S: float = 0.15

var cut: float = 18.0
var fill: Color = SLATE


func _init(pad: int = 14, p_cut: float = 18.0) -> void:
	cut = p_cut
	var sb := StyleBoxEmpty.new()
	sb.set_content_margin_all(pad)
	add_theme_stylebox_override("panel", sb)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(w - cut, 0), Vector2(w, cut), Vector2(w, h), Vector2(0, h)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, EDGE, 1.0, true)
	for p: Vector2 in [Vector2(7, h - 7), Vector2(w - 7, h - 7)]:
		draw_circle(p, 2.0, EDGE)


## A stencilled section label: capitals, spaced, in the label face.
static func stencil(text: String, color: Color = INK_DIM, px: int = LABEL_PX) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.spacing_glyph = 2
	f.variation_embolden = 0.4
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("shadow_outline_size", 0)
	return l


## A sentence: the readable face, wrapping, never below the sentence size.
static func sentence(text: String, color: Color = INK, px: int = SENTENCE_PX) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", maxi(px, SENTENCE_PX))
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("shadow_outline_size", 0)
	return l


## A thin engraved rule across a plate.
static func rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = RULE
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func flat(bg: Color, border: Color, border_w: int = 1, pad_x: int = 12, pad_y: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
	sb.corner_radius_top_right = 8  # the plate's clipped corner, in small
	sb.corner_detail = 1
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## Dresses a button as one of the instrument's keys. `on` = the chosen one of a group; `accent`
## its colour. Focus and hover always show as a full bright edge.
static func key(b: Button, accent: Color = CYAN, on: bool = false) -> void:
	b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, TOUCH_PX), maxf(b.custom_minimum_size.y, TOUCH_PX))
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", LABEL_PX)
	var rest := flat(Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2, 0.95) if on else SLATE_RAISED, accent if on else EDGE, 2 if on else 1)
	var lit := flat(Color(accent.r * 0.26, accent.g * 0.26, accent.b * 0.26, 0.97), accent, 2)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("focus", lit)
	b.add_theme_stylebox_override("pressed", flat(Color(accent.r * 0.34, accent.g * 0.34, accent.b * 0.34, 0.97), accent, 2))
	b.add_theme_stylebox_override("disabled", flat(Color(0.1, 0.11, 0.12, 0.7), RULE))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", INK_DIM.darkened(0.3))
