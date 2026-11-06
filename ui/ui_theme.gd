class_name UITheme
extends RefCounted
## Chunky, rounded, bright theme built in code. Rusty panel frames (warm orange borders on plum).

const PLUM := Color(0.2, 0.14, 0.28, 0.93)
const PLUM_LIGHT := Color(0.3, 0.22, 0.4, 0.95)
const RUST := Color(0.85, 0.48, 0.25)
const CREAM := Color(1.0, 0.96, 0.88)
const TEAL := Color(0.3, 0.7, 0.64)
const GOLD := Color(1.0, 0.82, 0.3)
const GREEN := Color(0.45, 0.9, 0.5)
const MUTED := Color(0.75, 0.7, 0.8)

static var _theme: Theme


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 14, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", Color(0.12, 0.07, 0.18))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("panel", "PanelContainer", box(PLUM, RUST, 3, 16, 12))
	t.set_stylebox("panel", "Panel", box(PLUM, RUST, 3, 16, 12))
	t.set_stylebox("normal", "Button", box(TEAL, TEAL.darkened(0.35), 3, 12, 8))
	t.set_stylebox("hover", "Button", box(TEAL.lightened(0.15), CREAM, 3, 12, 8))
	t.set_stylebox("pressed", "Button", box(TEAL.darkened(0.2), CREAM, 3, 12, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 4, 12, 8))
	t.set_stylebox("disabled", "Button", box(Color(0.35, 0.32, 0.4), Color(0.25, 0.22, 0.3), 3, 12, 8))
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(0.65, 0.62, 0.7))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_outline_color", "Button", Color(0.1, 0.06, 0.15))
	t.set_constant("outline_size", "Button", 4)
	t.set_font_size("font_size", "Button", 20)
	t.set_stylebox("background", "ProgressBar", box(Color(0.1, 0.07, 0.14), Color(0, 0, 0, 0), 0, 8, 0))
	t.set_stylebox("fill", "ProgressBar", box(GREEN, Color(0, 0, 0, 0), 0, 8, 0))
	t.set_color("font_color", "ProgressBar", CREAM)
	t.set_stylebox("panel", "TooltipPanel", box(PLUM_LIGHT, GOLD, 2, 10, 8))
	t.set_stylebox("slider", "HSlider", box(Color(0.1, 0.07, 0.14), Color(0, 0, 0, 0), 0, 6, 4))
	t.set_stylebox("grabber_area", "HSlider", box(TEAL, Color(0, 0, 0, 0), 0, 6, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(TEAL.lightened(0.2), Color(0, 0, 0, 0), 0, 6, 4))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func label(text: String, size: int = 20, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
