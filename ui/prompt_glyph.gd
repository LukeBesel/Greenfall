class_name PromptGlyph
extends Control
## [deck] One input prompt badge for an action on the device in use: a keycap for keyboard and
## mouse, or controller art in the active pad family (Xbox letters, PlayStation shapes, Steam
## Deck monochrome; bumpers, triggers, D-pad arms and sticks drawn as vectors). Redraws when
## the last input device or a binding changes.
## Pseudo-actions: "@move" (WASD / left stick), "@look" (mouse / right stick), "@dpad";
## "#N" is raw controller button N (for screens that read buttons directly).

var action: String = ""
var px: int = 16  # badge height follows the surrounding text size
var tint: Color = UITheme.CREAM
## Force a device (for previews): -1 follows Settings.last_input_pad, 0 keyboard, 1 pad.
var force_pad: int = -1
var _spec: Dictionary = {}


func _init(p_action: String = "", p_px: int = 16) -> void:
	action = p_action
	px = p_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	Settings.input_device_changed.connect(func(_p: bool) -> void: refresh())
	Settings.changed.connect(refresh)
	refresh()


func pad() -> bool:
	return Settings.last_input_pad if force_pad < 0 else force_pad == 1


## Spec for the current device: {shape, text, color, dir}.
static func spec_for(p_action: String, use_pad: bool) -> Dictionary:
	match p_action:
		"@move":
			return {"shape": "stick", "text": "L", "dir": Vector2.ZERO, "color": UITheme.CREAM} if use_pad \
				else {"shape": "key", "text": "WASD", "color": UITheme.CREAM, "dir": Vector2.ZERO}
		"@look":
			return {"shape": "stick", "text": "R", "dir": Vector2.ZERO, "color": UITheme.CREAM} if use_pad \
				else {"shape": "key", "text": "Mouse", "color": UITheme.CREAM, "dir": Vector2.ZERO}
		"@dpad":
			return {"shape": "dpad", "text": "", "dir": Vector2.ZERO, "color": UITheme.CREAM} if use_pad \
				else {"shape": "key", "text": "Arrows", "color": UITheme.CREAM, "dir": Vector2.ZERO}
	if p_action.begins_with("#"):  # raw pad button by index (screens that read buttons directly)
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(p_action.substr(1)) as JoyButton
		return PadGlyphs.badge(jb)
	var ev: InputEvent = Settings.binding(p_action, use_pad)
	if ev == null:
		ev = Settings.binding(p_action, not use_pad)
	if ev == null:
		return {"shape": "key", "text": "?", "color": UITheme.CREAM, "dir": Vector2.ZERO}
	return PadGlyphs.badge(ev)


func refresh() -> void:
	_spec = spec_for(action, pad())
	update_minimum_size()
	queue_redraw()


func _font_px() -> int:
	return maxi(Settings.MIN_FONT_PX, roundi(px * 0.75))


func _get_minimum_size() -> Vector2:
	var h: float = float(maxi(px, Settings.MIN_FONT_PX)) + 8.0
	match str(_spec.get("shape", "key")):
		"key":
			var w: float = UITheme.font().get_string_size(str(_spec.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px()).x
			return Vector2(maxf(h, w + 12.0), h)
		"bumper", "trigger":
			var w2: float = UITheme.font().get_string_size(str(_spec.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, _font_px()).x
			return Vector2(maxf(h * 1.5, w2 + 14.0), h)
		"menu", "view":
			return Vector2(h * 1.3, h)
	return Vector2(h, h)


func _draw() -> void:
	var sz: Vector2 = size
	var h: float = minf(sz.y, float(maxi(px, Settings.MIN_FONT_PX)) + 8.0)
	var c := Vector2(sz.x * 0.5, sz.y * 0.5)
	var ink: Color = tint
	var bg := Color(0.08, 0.085, 0.095, 0.92)
	var edge := Color(ink, 0.55)
	var f: Font = UITheme.font()
	var fs: int = _font_px()
	var shape: String = str(_spec.get("shape", "key"))
	var text: String = str(_spec.get("text", ""))
	var col: Color = _spec.get("color", ink)
	match shape:
		"key":
			var r := Rect2(Vector2(1, (sz.y - h) * 0.5 + 1), Vector2(sz.x - 2, h - 2))
			draw_style_box(UITheme.box(bg, edge, 1, 4, 0), r)
			# Keycap lip: a slightly darker bottom edge.
			draw_line(Vector2(r.position.x + 3, r.end.y - 1.5), Vector2(r.end.x - 3, r.end.y - 1.5), Color(ink, 0.25), 1.0)
			_text(f, text, c + Vector2(0, -1), fs, ink)
		"face", "ps_cross", "ps_circle", "ps_square", "ps_triangle":
			var rad: float = h * 0.5 - 1.0
			draw_circle(c, rad, bg)
			draw_arc(c, rad, 0.0, TAU, 32, Color(col, 0.7), 1.2, true)
			var k: float = rad * 0.45
			match shape:
				"face":
					_text(f, text, c, fs, col)
				"ps_cross":
					draw_line(c + Vector2(-k, -k), c + Vector2(k, k), col, 2.0, true)
					draw_line(c + Vector2(-k, k), c + Vector2(k, -k), col, 2.0, true)
				"ps_circle":
					draw_arc(c, k * 1.05, 0.0, TAU, 24, col, 2.0, true)
				"ps_square":
					draw_rect(Rect2(c - Vector2(k, k) * 0.9, Vector2(k, k) * 1.8), col, false, 2.0)
				"ps_triangle":
					var pts := PackedVector2Array([c + Vector2(0, -k * 1.1), c + Vector2(k * 1.05, k * 0.75), c + Vector2(-k * 1.05, k * 0.75), c + Vector2(0, -k * 1.1)])
					draw_polyline(pts, col, 2.0, true)
		"bumper":
			var r2 := Rect2(Vector2(1, (sz.y - h) * 0.5 + 2), Vector2(sz.x - 2, h - 4))
			draw_style_box(UITheme.box(bg, edge, 1, int(h * 0.4), 0), r2)
			_text(f, text, c, fs, ink)
		"trigger":
			var r3 := Rect2(Vector2(1, (sz.y - h) * 0.5 + 1), Vector2(sz.x - 2, h - 2))
			var sb: StyleBoxFlat = UITheme.box(bg, edge, 1, 3, 0)
			sb.corner_radius_top_left = int(h * 0.45)
			sb.corner_radius_top_right = int(h * 0.45)
			draw_style_box(sb, r3)
			_text(f, text, c + Vector2(0, 1), fs, ink)
		"dpad":
			var a: float = h * 0.5 - 1.0
			var w: float = a * 0.62
			var lit: Vector2 = _spec.get("dir", Vector2.ZERO)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				var on: bool = lit == Vector2.ZERO or lit == d
				var arm := Rect2(c + d * (a - w * 0.5) - Vector2(w, w) * 0.5, Vector2(w, w))
				draw_rect(arm.grow(0.5), bg)
				draw_rect(arm, Color(ink, 0.95) if on else Color(ink, 0.25))
			draw_rect(Rect2(c - Vector2(w, w) * 0.5, Vector2(w, w)), Color(ink, 0.25 if lit != Vector2.ZERO else 0.95))
		"stick":
			var rr: float = h * 0.5 - 1.0
			draw_circle(c, rr, bg)
			draw_arc(c, rr, 0.0, TAU, 32, edge, 1.2, true)
			var dir: Vector2 = _spec.get("dir", Vector2.ZERO)
			draw_circle(c + dir * rr * 0.28, rr * 0.55, Color(ink, 0.16))
			draw_arc(c + dir * rr * 0.28, rr * 0.55, 0.0, TAU, 24, Color(ink, 0.6), 1.0, true)
			_text(f, text, c + dir * rr * 0.28, fs, ink)
			if bool(_spec.get("press", false)):
				draw_arc(c, rr + 0.5, -PI * 0.75, -PI * 0.25, 8, ink, 1.6, true)
			elif dir != Vector2.ZERO:
				var tip: Vector2 = c + dir * (rr - 1.0)
				var side := Vector2(-dir.y, dir.x) * 2.5
				draw_colored_polygon(PackedVector2Array([tip, tip - dir * 3.5 + side, tip - dir * 3.5 - side]), ink)
		"menu", "view":
			var r4 := Rect2(Vector2(1, (sz.y - h) * 0.5 + 2), Vector2(sz.x - 2, h - 4))
			draw_style_box(UITheme.box(bg, edge, 1, int(h * 0.4), 0), r4)
			var u: float = h * 0.16
			if shape == "menu":
				for i: int in 3:
					var y: float = c.y + (i - 1) * u * 1.1
					draw_line(Vector2(c.x - u * 1.4, y), Vector2(c.x + u * 1.4, y), ink, 1.5)
			else:
				draw_rect(Rect2(c + Vector2(-u * 1.5, -u * 1.2), Vector2(u * 1.9, u * 1.6)), ink, false, 1.3)
				draw_rect(Rect2(c + Vector2(-u * 0.4, -u * 0.4), Vector2(u * 1.9, u * 1.6)), ink, false, 1.3)


func _text(f: Font, t: String, centre: Vector2, fs: int, col: Color) -> void:
	var ts: Vector2 = f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc: float = f.get_ascent(fs)
	var desc: float = f.get_descent(fs)
	draw_string(f, Vector2(centre.x - ts.x * 0.5, centre.y + (asc - desc) * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
