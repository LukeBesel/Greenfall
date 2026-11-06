class_name LedgerUplink
extends CanvasLayer
## Intercepted Ledger transmissions: a cold monospace terminal box, red/amber, with glitchy
## scrambling and jitter. Deliberately unlike WREN's soft centered subtitles.

const GLITCH: String = "#%&$@/\\|=+*<>01"
const RED := Color(1.0, 0.28, 0.2)
const AMBER := Color(1.0, 0.68, 0.22)
const GREEN := Color(0.45, 1.0, 0.6)

signal line_finished

var _box: PanelContainer
var _header: Label
var _body: Label
var _footer: Label
var _scan: ColorRect
var _queue: Array[Dictionary] = []
var _full: String = ""
var _shown: float = 0.0
var _hold: float = 0.0
var _glitch_t: float = 0.0
var _tick_t: float = 0.0
var _friendly: bool = false
var _base_x: float = 0.0
var _style: StyleBoxFlat

static var _mono: Font


static func mono_font() -> Font:
	if _mono == null:
		var f: Variant = load("res://ui/fonts/AnonymousPro-Bold.ttf") if ResourceLoader.exists("res://ui/fonts/AnonymousPro-Bold.ttf") else null
		if f is Font:
			_mono = f
		else:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(["Anonymous Pro", "DejaVu Sans Mono", "Liberation Mono", "Consolas", "Menlo", "monospace"])
			_mono = sf
	return _mono


func _ready() -> void:
	layer = 7
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var mc := MarginContainer.new()
	# Top right, under the district readout: away from WREN's centered subtitles.
	mc.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mc.add_theme_constant_override("margin_top", 84)
	mc.add_theme_constant_override("margin_right", 22)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mc)
	_box = PanelContainer.new()
	_box.custom_minimum_size = Vector2(440, 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.07, 0.015, 0.012, 0.86)
	_style.border_color = Color(RED, 0.75)
	_style.border_width_left = 3
	_style.border_width_top = 1
	_style.border_width_bottom = 1
	_style.border_width_right = 1
	_style.set_content_margin_all(12)
	_style.content_margin_left = 16
	_box.add_theme_stylebox_override("panel", _style)
	mc.add_child(_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(vb)
	_header = _mk_label(11, RED)
	vb.add_child(_header)
	_body = _mk_label(16, AMBER)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.custom_minimum_size = Vector2(408, 0)
	vb.add_child(_body)
	_footer = _mk_label(11, Color(RED, 0.6))
	vb.add_child(_footer)
	_scan = ColorRect.new()
	_scan.color = Color(1.0, 0.4, 0.2, 0.08)
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan.custom_minimum_size = Vector2(0, 3)
	_box.add_child(_scan)
	_box.modulate.a = 0.0
	_base_x = 0.0


func _mk_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", mono_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(col, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func is_busy() -> bool:
	return _full != "" or not _queue.is_empty()


## Queue an intercepted line. friendly = the post-resolution, helpful Ledger (green).
func show_line(text: String, friendly: bool = false, header: String = "") -> void:
	_queue.append({"text": text, "friendly": friendly, "header": header})


## Show a line immediately (cinematics), dropping anything queued. hold = seconds after typing.
func show_now(text: String, friendly: bool = false, hold: float = -1.0) -> void:
	_queue.clear()
	_start({"text": text, "friendly": friendly, "header": ""})
	if hold >= 0.0:
		_hold = hold


func _start(l: Dictionary) -> void:
	_full = str(l["text"])
	_friendly = bool(l["friendly"])
	_shown = 0.0
	_hold = 3.2 + _full.length() * 0.045
	_glitch_t = 0.35
	var col: Color = GREEN if _friendly else AMBER
	_body.add_theme_color_override("font_color", col)
	_body.add_theme_color_override("font_shadow_color", Color(col, 0.35))
	_header.add_theme_color_override("font_color", Color(0.4, 0.9, 0.55) if _friendly else RED)
	_style.border_color = Color(0.4, 0.9, 0.55, 0.75) if _friendly else Color(RED, 0.75)
	_style.bg_color = Color(0.015, 0.06, 0.03, 0.86) if _friendly else Color(0.07, 0.015, 0.012, 0.86)
	var h: String = str(l["header"])
	_header.text = h if h != "" else ("<< LEDGER // CONTRACT 0001 // AMENDED >>" if _friendly else "<< INTERCEPT // LEDGER-NODE 07 // UNSECURED CHANNEL >>")
	_footer.text = "line item %04d   checksum %s" % [randi() % 9999, "OK" if _friendly else "MISMATCH"]
	_box.modulate.a = 1.0
	if Audio.has_sound("glitch"):
		Audio.play("glitch", 1.0, -14.0 if _friendly else -9.0)


func _process(delta: float) -> void:
	if _full == "":
		if not _queue.is_empty():
			_start(_queue.pop_front())
		return
	var before: int = int(_shown)
	_shown = minf(_shown + delta * 42.0, _full.length())
	var n: int = int(_shown)
	_tick_t -= delta
	if n > before and _tick_t <= 0.0 and _full.substr(before, 1) != " ":
		_tick_t = 0.05
		if Audio.has_sound("ledger_tick"):
			Audio.play("ledger_tick", 1.0, -20.0, 0.1)
	_glitch_t = maxf(0.0, _glitch_t - delta)
	# Occasional glitch bursts while the line is up (never once the Ledger is friendly).
	if not _friendly and randf() < delta * 0.5:
		_glitch_t = 0.12
	var text: String = _full.substr(0, n)
	var chars: PackedStringArray = text.split("")
	var cursor: String = "_" if fmod(Time.get_ticks_msec() * 0.002, 1.0) < 0.5 else " "
	if _glitch_t > 0.0:
		for i: int in chars.size():
			if chars[i] != " " and randf() < 0.25:
				chars[i] = GLITCH[randi() % GLITCH.length()]
		_box.position.x = _base_x + randf_range(-4.0, 4.0)
		_box.modulate = Color(1.0, 0.85, 0.85, randf_range(0.7, 1.0))
	else:
		_box.position.x = _base_x
		_box.modulate = Color(1, 1, 1, 1.0 if _hold > 0.0 else _box.modulate.a)
	_body.text = "> " + "".join(chars) + (cursor if n < _full.length() or fmod(Time.get_ticks_msec() * 0.002, 1.0) < 0.5 else " ")
	_scan.position.y = fmod(Time.get_ticks_msec() * 0.08, maxf(_box.size.y, 1.0))
	_scan.size.x = _box.size.x
	if n >= _full.length():
		_hold -= delta
		if _hold <= 0.0:
			_box.modulate.a = maxf(0.0, _box.modulate.a - delta * 2.0)
			if _box.modulate.a <= 0.0:
				_full = ""
				line_finished.emit()
