class_name BenchKit
extends RefCounted
## [ui2] Shared pieces for the workbench tabs so every tab reads the same: one card style, one
## title / body size, a big primary button, a cost row with the currency icons (red when short),
## and "spot" pips (crew spots, Mk steps, hub levels).

## [ui2] Holographic look (owner playtest 2: "simple, smaller, futuristic"): dark glass, thin cyan
## frame with a soft outer glow; green = you can afford it, dim / red = you can't (with what's missing).
const HOLO := Color(0.55, 0.9, 1.0)
const GLASS := Color(0.025, 0.05, 0.065, 0.82)
const OK := Color(0.45, 0.95, 0.6)
const TITLE_SIZE: int = 24
const BODY_SIZE: int = 17
const SMALL_SIZE: int = 15
const BTN_SIZE: int = 19
const BTN_H: float = 54.0
const CARD_BG := Color(0.03, 0.055, 0.07, 0.78)
const SHORT := Color(1.0, 0.5, 0.42)
const CYAN := Color(0.45, 0.85, 1.0)


## A glass panel with a thin glowing frame (`glow` 0..1 sets the outer glow).
static func holo(border: Color = Color(HOLO, 0.32), bg: Color = CARD_BG, glow: float = 0.5, radius: int = 10, pad: int = 14) -> StyleBoxFlat:
	var sb: StyleBoxFlat = UITheme.box(bg, border, 1, radius, pad)
	sb.shadow_color = Color(border.r, border.g, border.b, 0.16 * glow)
	sb.shadow_size = int(round(7.0 * glow))
	sb.anti_aliasing = true
	sb.corner_detail = 1  # [ui7] chamfered (cut) corners, the holo frame's look
	return sb


## A card: [PanelContainer, VBoxContainer body]. `accent` tints the thin frame.
static func card(accent: Color = Color(HOLO, 0.28), min_w: float = 0.0) -> Array:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", holo(accent, CARD_BG, 0.4, 10, 14))
	pc.custom_minimum_size = Vector2(min_w, 0)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	return [pc, vb]


static func set_accent(pc: PanelContainer, accent: Color, bg: Color = CARD_BG) -> void:
	pc.add_theme_stylebox_override("panel", holo(accent, bg, 1.0 if accent.a > 0.5 else 0.4, 10, 14))


static func title(text: String, col: Color = Color.WHITE) -> Label:
	var l: Label = UITheme.label(text, TITLE_SIZE, col)
	l.add_theme_constant_override("outline_size", 0)
	return l


static func body(text: String, col: Color = UITheme.MUTED, size: int = BODY_SIZE) -> Label:
	var l: Label = UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120
	return l


## A small caps heading with tracking, e.g. "NEXT LEVEL".
static func caps(text: String, col: Color = CYAN) -> Label:
	var l: Label = UITheme.label(text.to_upper(), 13, col)
	l.add_theme_constant_override("outline_size", 0)
	return l


## The big primary action of a card: green glass with a glow when it can be pressed, dim when not.
static func big_button(text: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", BTN_SIZE)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	style_action(b, OK)
	return b


## Holographic button style in `col` (normal / hover / pressed glow, a dim disabled state).
static func style_action(b: Button, col: Color) -> void:
	b.add_theme_stylebox_override("normal", holo(Color(col, 0.75), Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.85), 0.8, 8, 8))
	b.add_theme_stylebox_override("hover", holo(col, Color(col.r * 0.32, col.g * 0.32, col.b * 0.32, 0.9), 1.2, 8, 8))
	b.add_theme_stylebox_override("pressed", holo(col, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 0.95), 1.4, 8, 8))
	b.add_theme_stylebox_override("disabled", holo(Color(1, 1, 1, 0.1), Color(0.05, 0.06, 0.07, 0.6), 0.0, 8, 8))
	b.add_theme_stylebox_override("focus", holo(Color.WHITE, Color(0, 0, 0, 0), 0.6, 8, 8))
	b.add_theme_color_override("font_color", col.lightened(0.55))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.62, 0.64, 0.8))


## A quieter secondary button (same height as big_button).
static func soft_button(text: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", BTN_SIZE - 1)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	style_action(b, HOLO)
	return b


static func spacer(h: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Cost in the three currencies with their icons: [cube] 1.2K  [part] 40. Amounts the player
## can't afford yet turn red. set_cost({}) shows `free_text`.
class CostRow extends HBoxContainer:
	var px: float = 22.0
	var font_size: int = 20
	var show_missing: bool = true
	var _sig: String = ""

	func _init(p_px: float = 22.0, p_font: int = 20) -> void:
		px = p_px
		font_size = p_font
		add_theme_constant_override("separation", 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_cost(cost: Dictionary, free_text: String = "") -> void:
		var f: Dictionary = Currencies.fold(cost)
		var bits: Array[String] = []
		for id: String in Currencies.IDS:
			var v: float = float(f.get(id, 0.0))
			if v > 0.0:
				var have: float = GameState.get_currency(id).to_float()
				bits.append("%s=%s:%s" % [id, str(v), "ok" if have >= v else str(floorf(have))])
		var sig: String = ",".join(bits) + "|" + free_text
		if sig == _sig:
			return
		_sig = sig
		for c: Node in get_children():
			remove_child(c)
			c.queue_free()
		var any: bool = false
		for id: String in Currencies.IDS:
			var v: float = float(f.get(id, 0.0))
			if v <= 0.0:
				continue
			if any:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(10, 0)
				add_child(gap)
			any = true
			var ok: bool = GameState.can_afford(id, BigNum.from_float(v))
			add_child(CurrencyIcon.new(id, px, CurrencyIcon.tint(id) if ok else BenchKit.SHORT))
			var l: Label = UITheme.label(Settings.fmt(BigNum.from_float(ceilf(v - 0.0001))), font_size, BenchKit.OK if ok else BenchKit.SHORT)
			l.add_theme_constant_override("outline_size", 0)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(l)
			if not ok and show_missing:  # [ui2] say what's missing, not just "red"
				var miss: float = ceilf(v - GameState.get_currency(id).to_float())
				var ml: Label = UITheme.label(TranslationServer.translate("need %s") % Settings.fmt(BigNum.from_float(miss)), maxi(font_size - 4, 12), Color(BenchKit.SHORT, 0.85))
				ml.add_theme_constant_override("outline_size", 0)
				ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				add_child(ml)
		if not any and free_text != "":
			add_child(UITheme.label(free_text, font_size - 2, UITheme.MUTED))


## A row of spot pips: `filled` of `total` lit in `col`, the rest hollow. Round (crew spots) or
## bar-shaped (steps).
class Pips extends Control:
	var total: int = 3
	var filled: int = 0
	var col: Color = UITheme.GOLD
	var bars: bool = false
	var pip: float = 14.0

	func _init(p_total: int = 3, p_bars: bool = false, p_col: Color = UITheme.GOLD) -> void:
		bars = p_bars
		col = p_col
		set_counts(0, p_total)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_counts(p_filled: int, p_total: int) -> void:
		if p_filled == filled and p_total == total and custom_minimum_size.x > 0.0:
			return
		filled = p_filled
		total = maxi(p_total, 0)
		var w: float = (pip * (2.2 if bars else 1.0) + 7.0) * total
		custom_minimum_size = Vector2(maxf(w, 1.0), pip + 4.0)
		queue_redraw()

	func _draw() -> void:
		var step: float = pip * (2.2 if bars else 1.0) + 7.0
		for i: int in total:
			var on: bool = i < filled
			var x: float = i * step
			if bars:
				var r := Rect2(x, 2.0 + pip * 0.25, pip * 2.2, pip * 0.5)
				if on:
					draw_rect(r.grow(2.0), Color(col, 0.18))
					draw_rect(r, col)
				else:
					draw_rect(r, Color(1, 1, 1, 0.28), false, 1.2)
			else:
				var c := Vector2(x + pip * 0.5, 2.0 + pip * 0.5)
				if on:
					draw_circle(c, pip * 0.5 + 2.0, Color(col, 0.18))
					draw_circle(c, pip * 0.5, col)
				else:
					draw_arc(c, pip * 0.5 - 0.6, 0.0, TAU, 20, Color(1, 1, 1, 0.32), 1.3, true)


## A drawn HudIcons glyph as a Control (role icons on the robot cards, etc.).
class Glyph extends Control:
	var kind: String = "cube"
	var col: Color = UITheme.GOLD
	var w: float = 1.8

	func _init(p_kind: String, p_px: float = 44.0, p_col: Color = UITheme.GOLD) -> void:
		kind = p_kind
		col = p_col
		custom_minimum_size = Vector2(p_px, p_px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, Color(col, 0.08))
		draw_arc(size * 0.5, r - 1.0, 0.0, TAU, 40, Color(col, 0.35), 1.2, true)
		HudIcons.draw(self, kind, size * 0.5, r * 0.62, col, w)
