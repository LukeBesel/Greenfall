class_name HudReadable
extends RefCounted
## [onboard] Readability for in-game HUD text over bright, busy scenes (playtest: "the task bar is
## very hard to read"). The HUD's theme is the shared UI theme with a slightly heavier font and a
## denser dark halo behind every Label, and a soft fading backing for text that sits where no
## corner scrim reaches (the notification stack).

const HALO := Color(0, 0, 0, 0.78)
const HALO_PX: int = 7

static var _theme: Theme
static var _font: FontVariation


## The thin UI font, a touch heavier: hairline strokes vanish over litter at small sizes.
static func font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = -0.12
		_font.spacing_glyph = 1
	return _font


static func theme() -> Theme:
	if _theme:
		return _theme
	var t: Theme = UITheme.get_theme().duplicate() as Theme
	t.default_font = font()
	t.set_color("font_shadow_color", "Label", HALO)
	t.set_constant("shadow_outline_size", "Label", HALO_PX)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("font_shadow_color", "RichTextLabel", HALO)
	t.set_constant("shadow_outline_size", "RichTextLabel", HALO_PX)
	_theme = t
	return t


## A soft dark backing that fades out to the right (left-anchored text rows).
static func fade_backing(alpha: float = 0.5) -> StyleBoxTexture:
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.015, 0.02, alpha))
	g.set_color(1, Color(0.01, 0.015, 0.02, 0.0))
	g.add_point(0.6, Color(0.01, 0.015, 0.02, alpha * 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	var sb := StyleBoxTexture.new()
	sb.texture = gt
	sb.content_margin_left = 8
	sb.content_margin_right = 26
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	return sb


## A rounded dark pill (key hints).
static func pill(alpha: float = 0.66) -> StyleBoxFlat:
	var sb := UITheme.box(Color(0.02, 0.025, 0.03, alpha), Color(1, 1, 1, 0.1), 1, 16, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb
