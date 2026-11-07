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
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	# Soft dark halo so HUD text stays readable over bright litter and sky.
	t.set_constant("shadow_outline_size", "Label", 5)
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


# --- Station panels (map screens): dark card, hazard-stripe top, bold caps title -----------

const ORANGE := Color(1.0, 0.5, 0.15)
const CARD_BG := Color(0.085, 0.09, 0.105, 0.94)
static var _stripe_tex: ImageTexture


static func hazard_strip(height: int = 7) -> TextureRect:
	if _stripe_tex == null:
		var img := Image.create(64, 8, false, Image.FORMAT_RGBA8)
		for y: int in 8:
			for x: int in 64:
				var band: bool = ((x + y) / 6) % 2 == 0
				img.set_pixel(x, y, Color(1.0, 0.72, 0.1) if band else Color(0.08, 0.08, 0.09))
		_stripe_tex = ImageTexture.create_from_image(img)
	var tr_ := TextureRect.new()
	tr_.texture = _stripe_tex
	tr_.stretch_mode = TextureRect.STRETCH_TILE
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.custom_minimum_size = Vector2(0, height)
	tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr_


## A titled card. Returns [PanelContainer, VBoxContainer body].
static func card(title: String, width: float = 300.0, subtitle: String = "") -> Array:
	var pc := PanelContainer.new()
	var sb := box(CARD_BG, Color(1, 1, 1, 0.08), 1, 8, 0)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(width, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	pc.add_child(outer)
	var strip := hazard_strip()
	outer.add_child(strip)
	var mc := MarginContainer.new()
	for side: String in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 14)
	mc.add_theme_constant_override("margin_top", 8)
	mc.add_theme_constant_override("margin_bottom", 12)
	outer.add_child(mc)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	mc.add_child(body)
	if subtitle != "":
		body.add_child(label(subtitle.to_upper(), 11, Color(0.4, 0.75, 1.0)))
	var t := label(title.to_upper(), 21, Color.WHITE)
	t.add_theme_constant_override("outline_size", 0)
	body.add_child(t)
	return [pc, body]


## Row: coloured icon dot, name, right-aligned value.
static func stat_row(col: Color, name: String, value: String = "") -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_theme_stylebox_override("panel", box(col, Color(0, 0, 0, 0), 0, 6, 0))
	hb.add_child(dot)
	var n := label(name, 14, CREAM)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(n)
	var v := label(value, 14, Color.WHITE)
	v.name = "Value"
	hb.add_child(v)
	return hb


static func orange_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(ORANGE, Color(0, 0, 0, 0), 0, 5, 8))
	b.add_theme_stylebox_override("hover", box(ORANGE.lightened(0.15), Color(0, 0, 0, 0), 0, 5, 8))
	b.add_theme_stylebox_override("pressed", box(ORANGE.darkened(0.15), Color(0, 0, 0, 0), 0, 5, 8))
	b.add_theme_stylebox_override("disabled", box(Color(0.3, 0.3, 0.32, 0.8), Color(0, 0, 0, 0), 0, 5, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)


## Dark row box used for list entries (waypoints, destinations, crews).
static func row_box() -> StyleBoxFlat:
	return box(Color(0.05, 0.055, 0.065, 0.9), Color(1, 1, 1, 0.06), 1, 5, 8)


## Subtle hover/focus feedback: the control grows a touch and brightens. Works inside containers
## (only scale and modulate are animated, which containers leave alone).
static func juice(c: Control, grow: float = 1.035) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	var to: Callable = func(s: float, bright: float) -> void:
		if not c.is_inside_tree():
			return
		var tw: Tween = c.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2(s, s), 0.14)
		tw.tween_property(c, "modulate", Color(bright, bright, bright, 1.0), 0.14)
	var on: Callable = func() -> void: to.call(grow, 1.12)
	var off: Callable = func() -> void:
		if c is BaseButton and (c as BaseButton).is_hovered():
			return
		to.call(1.0, 1.0)
	c.mouse_entered.connect(on)
	c.focus_entered.connect(on)
	c.mouse_exited.connect(func() -> void:
		if not c.has_focus():
			to.call(1.0, 1.0))
	c.focus_exited.connect(off)


# --- Colour-blind friendly palette (Settings.colorblind) ------------------------------------
# Okabe-Ito: distinguishable under protanopia, deuteranopia and tritanopia. Every helper returns
# the normal art colour when the option is off.

const OKABE_ORANGE := Color("#E69F00")
const OKABE_SKY := Color("#56B4E9")
const OKABE_GREEN := Color("#009E73")
const OKABE_YELLOW := Color("#F0E442")
const OKABE_BLUE := Color("#0072B2")
const OKABE_VERMILLION := Color("#D55E00")
const OKABE_PURPLE := Color("#CC79A7")

const _PROGRESS: Dictionary = {
	"junk": [Color(1.0, 0.5, 0.2), OKABE_VERMILLION],
	"cleaning": [Color(0.3, 0.6, 1.0), OKABE_SKY],
	"clean": [Color(0.3, 0.8, 0.45), OKABE_GREEN],
	"growing": [Color(0.35, 0.95, 0.4), OKABE_YELLOW],
}
const _CB_RARITY: Array[Color] = [OKABE_VERMILLION, Color(0.78, 0.78, 0.78), OKABE_GREEN, OKABE_SKY, OKABE_YELLOW]
## Globe cell states (PlanetData.State order: JUNK, CLEAN, PLANTED, GROWING, RESTORED, WATER).
const _CB_GLOBE: Dictionary = {
	0: OKABE_VERMILLION, 1: OKABE_SKY, 2: OKABE_GREEN, 3: Color("#7FD6B5"), 4: OKABE_YELLOW,
}


static func colorblind() -> bool:
	return Settings.colorblind


## Hex progress colour: "junk" (untouched), "cleaning", "clean", "growing".
static func progress_color(kind: String) -> Color:
	var pair: Array = _PROGRESS.get(kind, [Color.WHITE, Color.WHITE])
	return pair[1] if colorblind() else pair[0]


## Globe cell colour for a PlanetData.State; `normal` is the regular art colour.
static func globe_state_color(state: int, normal: Color) -> Color:
	return _CB_GLOBE.get(state, normal) if colorblind() else normal


## Hopper meter colours: band (Perfect zone tint), good (fill inside the band), over (overfilled).
static func meter_colors() -> Dictionary:
	if colorblind():
		return {"band": Color(OKABE_SKY, 0.22), "good": OKABE_SKY, "over": OKABE_VERMILLION}
	return {"band": Color(1.0, 0.7, 0.26, 0.18), "good": Color(1.0, 0.7, 0.26), "over": Color(0.95, 0.4, 0.35)}


## Part rarity colour (index into data/parts.json rarities).
static func rarity_color(idx: int) -> Color:
	if colorblind():
		return _CB_RARITY[clampi(idx, 0, _CB_RARITY.size() - 1)]
	return Color.html(str(Economy.rarity(idx).get("color", "#ffffff")))


## Subtitle font sizes for Settings.subtitle_size: [speaker/header, body].
static func subtitle_sizes() -> Array[int]:
	match Settings.subtitle_size:
		Settings.SubtitleSize.SMALL: return [11, 16]
		Settings.SubtitleSize.LARGE: return [15, 25]
	return [12, 19]
