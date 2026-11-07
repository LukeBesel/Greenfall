class_name Subtitles
extends CanvasLayer
## WREN's subtitle line: typed out with soft voice blips. Early (fragmented) lines flicker with
## glitch characters that resolve as they type.

const GLITCH: String = "▒░#/\\_-~=*"

var _label: Label
var _who: Label
var _box: Control
var _bg: PanelContainer
var _full: String = ""
var _shown: float = 0.0
var _stage: int = 2
var _hold: float = 0.0
var _blip_t: float = 0.0


func _ready() -> void:
	layer = 6
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	mc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mc.add_theme_constant_override("margin_bottom", 182)  # [hud] clear of the hotbar, level bar and prompt
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mc)
	# Optional backdrop (Settings.subtitle_background); transparent otherwise.
	_bg = PanelContainer.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(_bg)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(620, 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(vb)
	_who = UITheme.label("W R E N", 12, Color(0.55, 0.85, 1.0))
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_who)
	_label = UITheme.label("", 19, Color(0.92, 0.96, 1.0))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_label)
	_box = _bg
	_box.modulate.a = 0.0
	_apply_settings()
	Settings.changed.connect(_apply_settings)


## Subtitle settings: on/off, size, backdrop.
func _apply_settings() -> void:
	visible = Settings.subtitles_enabled
	var sz: Array[int] = UITheme.subtitle_sizes()
	_who.add_theme_font_size_override("font_size", sz[0])
	_label.add_theme_font_size_override("font_size", sz[1])
	(_label.get_parent() as Control).custom_minimum_size.x = 620.0 * clampf(float(sz[1]) / 19.0, 1.0, 1.3)
	@warning_ignore("incompatible_ternary")
	_bg.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.025, 0.035, 0.82), Color(1, 1, 1, 0.08), 1, 6, 12) if Settings.subtitle_background else StyleBoxEmpty.new())


func show_line(text: String, stage: int) -> void:
	text = tr(text) if text != "" else text  # [l10n] raw data lines (formatted ones arrive translated)
	_full = text
	_shown = 0.0
	_stage = stage
	_hold = 3.0 + text.length() * 0.04
	_box.modulate.a = 1.0


func _process(delta: float) -> void:
	if _full == "":
		return
	var before: int = int(_shown)
	_shown = minf(_shown + delta * (38.0 if _stage > 0 else 26.0), _full.length())
	var n: int = int(_shown)
	if n > before and _full.substr(before, 1) != " ":
		_blip_t -= 1.0
		if _blip_t <= 0.0 and visible:
			_blip_t = 1.0
			Audio.play("blip", 1.0 + (hash(_full.substr(before, 1)) % 7) * 0.04, -16.0, 0.03)
	var text: String = _full.substr(0, n)
	if _stage == 0:
		# Fragmented signal: some typed characters flicker as noise.
		var chars: PackedStringArray = text.split("")
		for i: int in chars.size():
			if chars[i] != " " and randf() < 0.12 * (1.0 - float(i) / maxf(n, 1.0)) + 0.03:
				chars[i] = GLITCH[randi() % GLITCH.length()]
		text = "".join(chars)
	_label.text = text
	if n >= _full.length():
		_hold -= delta
		if _hold <= 0.0:
			_box.modulate.a = maxf(0.0, _box.modulate.a - delta * 1.5)
			if _box.modulate.a <= 0.0:
				_full = ""
