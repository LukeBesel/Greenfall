class_name HoloFrame
extends RefCounted
## [ui7] The workbench / Locker frame (owner: "more futuristic and roboty ... doesn't open the
## entire screen ... you can see the environment around the border and in between sections ... a
## bit see-through"). Floating glass modules: chamfered corners, a thin glowing cyan edge, corner
## brackets, a few tick marks and faint scanlines; status LEDs and a mono "LM-1 // NAME" header;
## a quick hologram unfold (scale from a line + one scan sweep) instead of a slide. Kept quiet:
## nothing flickers once it is open.

const EDGE := Color(0.45, 0.88, 1.0)
const GLASS_A: float = 0.74
const GAP: int = 12
const CUT: int = 12


## Dark tinted glass with chamfered corners and a thin glowing cyan edge.
static func glass(alpha: float = GLASS_A, edge_a: float = 0.55, pad: int = 12, cut: int = CUT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.03, 0.045, alpha)
	sb.border_color = Color(EDGE, edge_a)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(cut)
	sb.corner_detail = 1  # straight cuts, not rounds
	sb.set_content_margin_all(pad)
	sb.shadow_color = Color(EDGE, 0.07)
	sb.shadow_size = 5
	sb.anti_aliasing = true
	return sb


## A floating module: a glass PanelContainer with its FrameDecor (brackets, ticks, scanlines) behind
## the content. Add the content as the panel's next child.
static func module(pad: int = 12, alpha: float = GLASS_A) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", glass(alpha, 0.55, pad))
	var d := FrameDecor.new()
	d.inset = float(pad)
	pc.add_child(d)
	return pc


## The mono "techy" font for labels and numbers (Anonymous Pro, with the CJK fallbacks).
static func mono() -> Font:
	return LedgerUplink.mono_font()


static func mono_label(text: String, px: int, col: Color) -> Label:
	var l: Label = UITheme.label(text, px, col)
	l.add_theme_font_override("font", mono())
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


## "LM-1 // WORKBENCH": a dim unit code, then the name; LEDs in front.
static func header_title(name_: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(Leds.new())
	hb.add_child(mono_label("LM-1 //", 17, Color(EDGE, 0.55)))
	hb.add_child(mono_label(name_.to_upper(), 20, EDGE.lightened(0.35)))
	return hb


## The HUD layers under the frame (CanvasLayer 1..`below`-1) are hidden while it is open, so no
## HUD text shows through the glass. Returns what was hidden, for show_hud().
static func hide_hud(tree: SceneTree, below: int) -> Array[CanvasLayer]:
	var out: Array[CanvasLayer] = []
	if tree == null or tree.root == null:
		return out
	for n: Node in tree.root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.visible and cl.layer > 0 and cl.layer < below:
			cl.visible = false
			out.append(cl)
	return out


static func show_hud(layers: Array[CanvasLayer]) -> void:
	for cl: CanvasLayer in layers:
		if is_instance_valid(cl):
			cl.visible = true
	layers.clear()


## The full-screen layer behind the modules: no dim, only a light vignette (it also keeps
## clicks off the world).
static func vignette() -> ColorRect:
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 d = (UV - vec2(0.5, 0.54)) * vec2(1.0, 1.2);
	COLOR = vec4(0.0, 0.015, 0.025, smoothstep(0.3, 0.85, length(d)) * 0.55 + 0.06);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	cr.material = m
	return cr


## Margins for the floating frame: ~80% of the width and height, centred slightly low (a little
## roomier on small logical screens so nothing has to scroll).
static func fit_margins(mc: MarginContainer, vp: Vector2) -> void:
	var small: bool = vp.y < 650.0
	var side: int = int(vp.x * (0.075 if small else 0.11))
	var top: int = int(vp.y * (0.045 if small else 0.11))
	var bottom: int = int(vp.y * (0.025 if small else 0.06))
	mc.add_theme_constant_override("margin_left", side)
	mc.add_theme_constant_override("margin_right", side)
	mc.add_theme_constant_override("margin_top", top)
	mc.add_theme_constant_override("margin_bottom", bottom)


## The hologram unfold: the frame opens from a bright line, then one scan sweep runs down
## every module.
static func unfold(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.0, 0.03)
	c.modulate = Color(0.75, 1.3, 1.5, 0.0)
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "scale:y", 1.0, 0.17).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate", Color.WHITE, 0.24)
	for n: Node in c.find_children("*", "", true, false):
		if n is FrameDecor:
			(n as FrameDecor).sweep()


## The fold back to a line; `done` runs when it has closed.
static func fold(c: Control, done: Callable) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "scale:y", 0.03, 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "modulate:a", 0.0, 0.1)
	tw.chain().tween_callback(done)


## Drawn behind a module's content: faint scanlines, corner brackets just outside the cuts, a
## few tick marks on the top and bottom edges, and the opening scan sweep.
class FrameDecor extends Control:
	var inset: float = 12.0
	var sweep_t: float = -1.0:
		set(v):
			sweep_t = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		show_behind_parent = false

	func _ready() -> void:
		resized.connect(queue_redraw)

	func sweep() -> void:
		sweep_t = 0.0
		var tw := create_tween()
		tw.tween_property(self, "sweep_t", 1.0, 0.42).set_delay(0.08)
		tw.tween_callback(func() -> void: sweep_t = -1.0)

	func _draw() -> void:
		var r := Rect2(Vector2(-inset, -inset), size + Vector2(inset, inset) * 2.0)
		# Scanlines (one call).
		var lines := PackedVector2Array()
		var y: float = r.position.y + 3.0
		while y < r.end.y - 2.0:
			lines.append(Vector2(r.position.x + 2.0, y))
			lines.append(Vector2(r.end.x - 2.0, y))
			y += 4.0
		if not lines.is_empty():
			draw_multiline(lines, Color(HoloFrame.EDGE, 0.022))
		# Corner brackets, 4 px outside the chamfers.
		var o: float = 4.0
		var l: float = 16.0
		var c := Color(HoloFrame.EDGE, 0.85)
		var tl := r.position - Vector2(o, o)
		var br := r.end + Vector2(o, o)
		var tr_ := Vector2(br.x, tl.y)
		var bl := Vector2(tl.x, br.y)
		draw_polyline(PackedVector2Array([tl + Vector2(0, l), tl, tl + Vector2(l, 0)]), c, 1.5)
		draw_polyline(PackedVector2Array([tr_ + Vector2(-l, 0), tr_, tr_ + Vector2(0, l)]), c, 1.5)
		draw_polyline(PackedVector2Array([bl + Vector2(0, -l), bl, bl + Vector2(l, 0)]), c, 1.5)
		draw_polyline(PackedVector2Array([br + Vector2(-l, 0), br, br + Vector2(0, -l)]), c, 1.5)
		# Tick marks: a short run on the top edge (right) and the bottom edge (left).
		var tc := Color(HoloFrame.EDGE, 0.45)
		for i: int in 6:
			var x1: float = r.end.x - 34.0 - i * 6.0
			draw_line(Vector2(x1, r.position.y + 3.0), Vector2(x1, r.position.y + (8.0 if i % 3 == 0 else 6.0)), tc, 1.0)
			var x2: float = r.position.x + 28.0 + i * 6.0
			draw_line(Vector2(x2, r.end.y - 3.0), Vector2(x2, r.end.y - (8.0 if i % 3 == 0 else 6.0)), tc, 1.0)
		# The opening scan sweep: a bright line with a soft trail above it.
		if sweep_t >= 0.0:
			var sy: float = lerpf(r.position.y, r.end.y, sweep_t)
			var a: float = 1.0 - sweep_t * 0.6
			draw_rect(Rect2(r.position.x + 1.0, sy - 18.0, r.size.x - 2.0, 18.0), Color(HoloFrame.EDGE, 0.06 * a))
			draw_line(Vector2(r.position.x + 1.0, sy), Vector2(r.end.x - 1.0, sy), Color(HoloFrame.EDGE, 0.55 * a), 1.5)


## Three small status LEDs (green, cyan, amber); the green one breathes slowly.
class Leds extends Control:
	var _t: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(34, 12)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var cols: Array[Color] = [Color(0.4, 1.0, 0.6), HoloFrame.EDGE, Color(1.0, 0.7, 0.3)]
		for i: int in 3:
			var c: Color = cols[i]
			var a: float = (0.65 + 0.35 * sin(_t * 2.2)) if i == 0 else 0.8
			var p := Vector2(5.0 + i * 12.0, size.y * 0.5)
			draw_circle(p, 4.5, Color(c, 0.18 * a))
			draw_circle(p, 2.6, Color(c, a))
