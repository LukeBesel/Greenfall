class_name ResearchNodeCard
extends Button
## One node in the research graph: a rounded glass card with an icon disc, name and a status line.
## States: locked / available / queued / active (progress ring) / researched. Hover and focus
## grow it a touch; starting research pops it; finishing it bursts and flashes.

const W: float = 184.0  # [ui2] taller, readable cards (was 200 x 76, 15 / 12 px text); 5 columns fit 1280x720 @125%
const H: float = 86.0

var node_id: String
var accent: Color = UITheme.GOLD
var state: String = "locked"
var _flash: float = 0.0
var _glow_t: float = 0.0
var _particles: CPUParticles2D
var _affordable: bool = false


func _init(id: String, p_accent: Color) -> void:
	node_id = id
	accent = p_accent
	flat = true
	text = ""
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for s: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())


func _ready() -> void:
	pivot_offset = size * 0.5
	UITheme.juice(self, 1.05)
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 28
	_particles.lifetime = 0.9
	_particles.explosiveness = 1.0
	_particles.spread = 180.0
	_particles.initial_velocity_min = 90.0
	_particles.initial_velocity_max = 260.0
	_particles.gravity = Vector2(0, 380)
	_particles.scale_amount_min = 2.5
	_particles.scale_amount_max = 5.0
	_particles.position = Vector2(30, H * 0.5)
	add_child(_particles)
	refresh()


func refresh() -> void:
	var s: String = Research.status(node_id)
	_affordable = GameState.can_afford(Research.CURRENCY, Research.cost(node_id))
	if s != state:
		state = s
	tooltip_text = ""
	queue_redraw()


func _process(delta: float) -> void:
	_glow_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
	if state == "active" or _flash > 0.0:
		queue_redraw()


## Started (or queued): a quick pop and a spray of accent sparks.
func pop() -> void:
	_flash = 0.7
	_burst(accent, 18)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale = Vector2(0.9, 0.9)
	tw.tween_property(self, "scale", Vector2(1.06, 1.06), 0.22)
	tw.tween_property(self, "scale", Vector2.ONE, 0.18)


## Research finished: big flash and a green-gold burst.
func celebrate() -> void:
	_flash = 1.0
	_burst(Color(0.75, 1.0, 0.7), 34)
	var tw := create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	scale = Vector2(1.18, 1.18)
	tw.tween_property(self, "scale", Vector2.ONE, 0.7)


## Can't do that: a little head-shake.
func shake() -> void:
	var x0: float = position.x
	var tw := create_tween()
	for k: int in 4:
		tw.tween_property(self, "position:x", x0 + (6.0 if k % 2 == 0 else -6.0), 0.04)
	tw.tween_property(self, "position:x", x0, 0.04)


func _burst(col: Color, n: int) -> void:
	# Hidden canvas items don't step particles, so a burst while closed would freeze mid-air.
	if Settings.reduced_motion or not is_visible_in_tree():
		return
	_particles.color = col
	_particles.amount = n
	_particles.restart()
	_particles.emitting = true


func _draw() -> void:
	var d: Dictionary = Research.def(node_id)
	var rect := Rect2(Vector2.ZERO, size)
	var bg := Color(0.07, 0.075, 0.085, 0.92)
	var border := Color(1, 1, 1, 0.08)
	var name_col: Color = UITheme.MUTED
	var icon_col := Color(0.45, 0.47, 0.48)
	var bw: int = 1
	match state:
		"available":
			bg = Color(0.1, 0.105, 0.115, 0.95)
			border = Color(accent, 0.55 if _affordable else 0.25)
			name_col = UITheme.CREAM
			icon_col = accent
		"queued":
			bg = Color(0.11, 0.1, 0.08, 0.95)
			border = Color(UITheme.GOLD, 0.7)
			name_col = UITheme.CREAM
			icon_col = accent
		"active":
			var pulse: float = 0.6 + 0.4 * sin(_glow_t * 4.0)
			bg = Color(0.14, 0.12, 0.08, 0.97)
			border = Color(UITheme.GOLD, 0.6 + 0.4 * pulse)
			name_col = Color.WHITE
			icon_col = UITheme.GOLD
			bw = 2
		"researched":
			bg = Color(accent.r * 0.18 + 0.06, accent.g * 0.18 + 0.06, accent.b * 0.18 + 0.06, 0.95)
			border = Color(accent, 0.8)
			name_col = Color.WHITE
			icon_col = accent.lightened(0.15)
	if has_focus() or is_hovered():
		border = UITheme.GOLD
		bw = 2
	# Soft shadow, then the card.
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 12, 0), Rect2(Vector2(0, 3), size))
	draw_style_box(UITheme.box(bg, border, bw, 12, 0), rect)
	if state == "active":
		draw_style_box(UITheme.box(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.18), 6, 16, 0), rect.grow(4))
	# Icon disc + progress ring.
	var ic := Vector2(32, size.y * 0.5)
	draw_circle(ic, 22.0, Color(icon_col, 0.13))
	ResearchIcons.draw(self, str(d.get("icon", "data")), ic, 15.0, icon_col, 2.0)
	if state == "active":
		var p: float = Research.progress(node_id)
		draw_arc(ic, 24.5, 0.0, TAU, 40, Color(1, 1, 1, 0.08), 3.0, true)
		draw_arc(ic, 24.5, -PI * 0.5, -PI * 0.5 + TAU * p, 40, UITheme.GOLD, 3.0, true)
	elif state == "researched":
		draw_circle(Vector2(size.x - 14, 14), 9.0, accent)
		ResearchIcons.draw(self, "check", Vector2(size.x - 14, 14), 9.0, Color(0.06, 0.07, 0.08), 1.6)
	elif state == "locked":
		ResearchIcons.draw(self, "lock", Vector2(size.x - 15, 15), 9.0, Color(1, 1, 1, 0.25), 1.6)
	elif state == "queued":
		var qp: int = Research.queue_position(node_id) + 1
		draw_style_box(UITheme.box(UITheme.GOLD, Color(0, 0, 0, 0), 0, 8, 0), Rect2(Vector2(size.x - 34, 7), Vector2(26, 17)))
		draw_string(UITheme.font(), Vector2(size.x - 34, 20), "#%d" % qp, HORIZONTAL_ALIGNMENT_CENTER, 26, 12, Color(0.1, 0.07, 0.03))
	# Text.
	var f: Font = UITheme.font()
	var tx: float = 62.0
	var lines: PackedStringArray = _wrap(f, tr(str(d.get("name", node_id))), size.x - tx - 22.0, 16)
	var y0: float = 36.0 if lines.size() == 1 else 28.0
	for i: int in lines.size():
		draw_string(f, Vector2(tx, y0 + i * 19.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - tx - 8.0, 16, name_col)
	var sub_y: float = 62.0 if lines.size() == 1 else 72.0
	var sub: String = ""
	var sub_col: Color = UITheme.MUTED
	match state:
		"researched":
			sub = tr("Researched")
			sub_col = Color(accent, 0.9)
		"active":
			sub = tr("%s left") % Research.time_text(Research.remaining())
			sub_col = UITheme.GOLD
		"queued":
			sub = tr("Queued  ·  %s") % Research.time_text(Research.duration(node_id))
			sub_col = UITheme.CREAM
		_:
			sub = tr("%s  ·  %s") % [L10nFmt.amount("cubes", Research.cost(node_id).to_float()), Research.time_text(Research.duration(node_id))]
			sub_col = UITheme.GOLD if state == "available" and _affordable else UITheme.MUTED
	draw_string(f, Vector2(tx, sub_y), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - tx - 8.0, 14, sub_col)
	if _flash > 0.0:
		draw_style_box(UITheme.box(Color(1, 0.95, 0.8, _flash * 0.45), Color(0, 0, 0, 0), 0, 12, 0), rect)


## Splits a name over at most two lines that fit `width`.
static func _wrap(f: Font, txt: String, width: float, fs: int) -> PackedStringArray:
	if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return PackedStringArray([txt])
	var words: PackedStringArray = txt.split(" ")
	var first: String = words[0]
	var i: int = 1
	while i < words.size() and f.get_string_size(first + " " + words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		first += " " + words[i]
		i += 1
	if i >= words.size():
		return PackedStringArray([first])
	return PackedStringArray([first, " ".join(words.slice(i))])
