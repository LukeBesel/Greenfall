class_name UITheme
extends RefCounted
## Chunky, rounded, bright theme built in code. Rusty panel frames (warm orange borders on plum).

# Industrial palette: dark translucent slate panels, hairline borders, one amber accent.
const PLUM := Color(0.055, 0.06, 0.065, 0.62)        # panel background
const PLUM_LIGHT := Color(0.1, 0.105, 0.11, 0.78)    # raised / hovered panel
const RUST := Color(1.0, 1.0, 1.0, 0.12)             # hairline border
const CREAM := Color(0.9, 0.9, 0.87)                 # primary text
const TEAL := Color(0.16, 0.17, 0.18, 0.9)           # button
const GOLD := Color(1.0, 0.7, 0.26)                  # accent (amber)
const GREEN := Color(0.62, 0.86, 0.66)               # positive numbers
const MUTED := Color(0.58, 0.6, 0.6)                 # secondary text

static var _theme: Theme


static var _font: FontVariation


## Thin variant of the default UI font.
static func font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = -0.35
		_font.spacing_glyph = 1
	return _font


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0, radius: int = 3, pad: int = 10) -> StyleBoxFlat:
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
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_constant("outline_size", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", box(PLUM, RUST, 1, 3, 12))
	t.set_stylebox("panel", "Panel", box(PLUM, RUST, 1, 3, 12))
	t.set_stylebox("normal", "Button", box(TEAL, RUST, 1, 2, 8))
	t.set_stylebox("hover", "Button", box(PLUM_LIGHT, GOLD, 1, 2, 8))
	t.set_stylebox("pressed", "Button", box(Color(0.2, 0.15, 0.07, 0.9), GOLD, 1, 2, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 1, 2, 8))
	t.set_stylebox("disabled", "Button", box(Color(0.08, 0.085, 0.09, 0.6), Color(1, 1, 1, 0.05), 1, 2, 8))
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.46, 0.46))
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_constant("outline_size", "Button", 0)
	t.set_font_size("font_size", "Button", 16)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOLD, Color(0, 0, 0, 0), 0, 1, 0))
	t.set_color("font_color", "ProgressBar", CREAM)
	t.set_stylebox("panel", "TooltipPanel", box(PLUM_LIGHT, RUST, 1, 2, 8))
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 1, 2))
	t.set_stylebox("grabber_area", "HSlider", box(GOLD, Color(0, 0, 0, 0), 0, 1, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD.lightened(0.2), Color(0, 0, 0, 0), 0, 1, 2))
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_font_size("font_size", "CheckButton", 16)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func label(text: String, size: int = 20, color: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
