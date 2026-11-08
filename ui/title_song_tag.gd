class_name TitleSongTag
extends Control
## [tunes] The title screen's now-playing tag, bottom right (the menu sits on the left): a small
## note, "Sunbaked, Two Suns Tango Orchestra". It fades in bright for a few seconds when a song
## starts, then stays subtle.

const BRIGHT_S: float = 5.0
const SUBTLE: float = 0.42

var _label: Label
var _note: Control
var _t: float = 99.0
var _id: String = ""


func _ready() -> void:
	name = "TitleSongTag"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.anchor_left = 1.0
	hb.anchor_right = 1.0
	hb.anchor_top = 1.0
	hb.anchor_bottom = 1.0
	hb.offset_left = -560
	hb.offset_right = -36
	hb.offset_top = -64
	hb.offset_bottom = -36
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hb)
	_note = NoteIcon.new()
	hb.add_child(_note)
	_label = UITheme.label("", 15, Color(1.0, 0.96, 0.88))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(_label)
	modulate.a = 0.0


func _process(delta: float) -> void:
	var id: String = Tunes.now_playing()
	if id != _id:
		_id = id
		if id != "":
			_label.text = "%s, %s" % [tr(Tunes.title(id)), tr(Tunes.artist_name(id))]
			_t = 0.0
	_t += delta
	var want: float = 0.0
	if _id != "":
		want = 1.0 if _t < BRIGHT_S else SUBTLE
	modulate.a = move_toward(modulate.a, want, delta / (0.8 if want > modulate.a else 1.6))


class NoteIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(16, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(1.0, 0.86, 0.55)
		draw_circle(Vector2(5.5, 17.0), 4.0, c)
		draw_line(Vector2(9.2, 17.0), Vector2(9.2, 3.0), c, 1.8, true)
		draw_line(Vector2(9.2, 3.0), Vector2(14.5, 6.5), c, 2.2, true)
