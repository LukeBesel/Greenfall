class_name ToBeContinued
extends CanvasLayer
## [v7play] The end of this release's road on a planet (owner decision, docs/RELEASE_CHECK.md): once
## the drive is built and the next planet is still closed, after WREN's "to be continued" lines, a
## short full-screen card: the rocket on its pad under the two suns, the home meters ("Home: fuel
## 2/10, power 2/10"), "To be continued" and a line that Lumi can stay and keep restoring the planet.
## Any press closes it. Once per save (flags.tbc_seen_<planet id>). All text is data:
## data/homeward.json closed.card {title, line, hint}; the meter line is data/story_arc.json's.
## Shown by HomewardDirector (systems/homeward_director.gd, maybe_show_tbc); dev: --open=tbc.

signal closed
signal opened  # [v9c]

var is_open: bool = false
var _root: Control
var _title: Label
var _meter: Label
var _line: Label
var _hint: PromptLabel
var _t: float = 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "TbcRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var art := _Art.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 30)
	_root.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	_title = UITheme.label("", 40, UITheme.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_title)
	_meter = UITheme.label("", 20, Color(0.8, 0.95, 1.0))
	_meter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_meter)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(spacer)
	_line = UITheme.label("", 19, Color(0.98, 0.95, 0.88))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_line)
	_hint = PromptLabel.new("", 15, Color(1, 1, 1, 0.75))
	_hint.align_center = true
	vb.add_child(_hint)
	_root.visible = false


## The card's text for planet k, from data (pure; tests use it).
static func texts() -> Dictionary:
	var c: Dictionary = Homeward.closed_cfg().get("card", {})
	return {
		"title": TranslationServer.translate(str(c.get("title", "To be continued"))),
		"meter": StoryArc.format_meter(StoryArc.meter()),
		"line": TranslationServer.translate(str(c.get("line", ""))),
		"hint": str(c.get("hint", "{interact}  continue")),
	}


static func seen_flag() -> String:
	return "tbc_seen_%s" % str(Homeward.planet_def(Homeward.current_planet()).get("id", ""))


func open_card() -> void:
	if is_open:
		return
	var t: Dictionary = texts()
	_title.text = str(t["title"]).to_upper()
	_meter.text = str(t["meter"])
	_line.text = str(t["line"])
	_hint.set_template(TranslationServer.translate(str(t["hint"])))
	is_open = true
	_t = 0.0
	GameState.flags[seen_flag()] = true
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.8)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.music_sting("first_sprout")
	opened.emit()
	print("[home] to be continued card")


func close_card() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func _process(delta: float) -> void:
	if is_open:
		_t += delta
		if DevHooks.has("autoplay") and _t > 3.0:  # the bot reads it and goes on, as a player would
			close_card()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	var back: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")  # B / Esc: at once
	var press: bool = _t >= 1.2 and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed))  # a moment to read before a held key closes it
	if back or press:
		close_card()
		get_viewport().set_input_as_handled()


## The picture: dusk sky, the two suns, the start yard's pad with the rocket standing on it.
## House style: chunky shapes, soft glow, hazard stripes (docs/ART_KIT.md).
class _Art extends Control:
	func _draw() -> void:
		var s: Vector2 = size
		var top := Color(0.08, 0.16, 0.3)
		var low := Color(0.98, 0.62, 0.4)
		var sky := PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y * 0.72), Vector2(0, s.y * 0.72)])
		var mid := top.lerp(low, 0.35)
		draw_polygon(PackedVector2Array([sky[0], sky[1], Vector2(s.x, s.y * 0.4), Vector2(0, s.y * 0.4)]), PackedColorArray([top, top, mid, mid]))
		draw_polygon(PackedVector2Array([Vector2(0, s.y * 0.4), Vector2(s.x, s.y * 0.4), sky[2], sky[3]]), PackedColorArray([mid, mid, low, low]))
		# The two suns (the big gold one low, the small pale one higher), each with a soft halo.
		for sun: Array in [[Vector2(0.24, 0.5), 0.09, Color(1.0, 0.82, 0.42)], [Vector2(0.72, 0.3), 0.045, Color(1.0, 0.95, 0.85)]]:
			var c: Vector2 = Vector2(s.x * float(sun[0].x), s.y * float(sun[0].y))
			var r: float = s.y * float(sun[1])
			for k: int in 24:  # a soft halo: many faint rings, no visible steps
				draw_circle(c, r * (1.0 + (23 - k) * 0.11), Color(sun[2], 0.022))
			draw_circle(c, r, sun[2])
		# Green hills (Verdance is greening) and the ground.
		var g := Color(0.18, 0.36, 0.22)
		var hills := PackedVector2Array([Vector2(0, s.y * 0.7)])
		for i: int in 13:
			var x: float = s.x * i / 12.0
			hills.append(Vector2(x, s.y * (0.66 + 0.035 * sin(i * 1.7))))
		hills.append(Vector2(s.x, s.y))
		hills.append(Vector2(0, s.y))
		draw_colored_polygon(hills, g)
		draw_rect(Rect2(0, s.y * 0.8, s.x, s.y * 0.2), Color(0.13, 0.26, 0.16))
		# The pad: a dark slab with hazard stripes on its rim.
		var cx: float = s.x * 0.5
		var pw: float = s.y * 0.5
		var py: float = s.y * 0.78
		draw_rect(Rect2(cx - pw * 0.5, py, pw, s.y * 0.04), Color(0.22, 0.23, 0.25))
		var n: int = 12
		for i: int in n:
			if i % 2 == 0:
				draw_rect(Rect2(cx - pw * 0.5 + pw * i / n, py, pw / n, s.y * 0.012), Color(0.98, 0.78, 0.2))
		# The rocket: a chunky cream body, red nose and fins, a round window glowing warm.
		var rw: float = s.y * 0.09
		var rh: float = s.y * 0.3
		var base_y: float = py
		var body := Rect2(cx - rw * 0.5, base_y - rh, rw, rh)
		for k: int in 12:  # a soft warm glow round the rocket
			draw_circle(Vector2(cx, base_y - rh * 0.5), rw * (0.6 + (11 - k) * 0.12), Color(1.0, 0.85, 0.6, 0.012))
		var red := Color(0.86, 0.26, 0.2)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - rw * 0.5, base_y - rh * 0.25), Vector2(cx - rw * 1.0, base_y), Vector2(cx - rw * 0.5, base_y)]), red)
		draw_colored_polygon(PackedVector2Array([Vector2(cx + rw * 0.5, base_y - rh * 0.25), Vector2(cx + rw * 1.0, base_y), Vector2(cx + rw * 0.5, base_y)]), red)
		draw_rect(body, Color(0.95, 0.92, 0.84))
		draw_rect(Rect2(body.position.x, base_y - rh * 0.38, rw, rh * 0.06), red)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - rw * 0.5, base_y - rh), Vector2(cx, base_y - rh - rw * 1.1), Vector2(cx + rw * 0.5, base_y - rh)]), red)
		var win := Vector2(cx, base_y - rh * 0.68)
		draw_circle(win, rw * 0.26, Color(0.3, 0.32, 0.36))
		draw_circle(win, rw * 0.19, Color(1.0, 0.8, 0.45))
		# A dark band behind the text at the top and the bottom, so it reads on every size.
		draw_rect(Rect2(0, 0, s.x, s.y * 0.2), Color(0, 0, 0, 0.25))
		draw_rect(Rect2(0, s.y * 0.84, s.x, s.y * 0.16), Color(0, 0, 0, 0.35))
