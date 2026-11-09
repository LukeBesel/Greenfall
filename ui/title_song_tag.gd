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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # [qafix] QA #21: set_anchors_preset kept a 0x0 rect, so the tag sat off-screen
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
	# [qafix] QA #21: a clipped Label in a box has no minimum width, so it collapsed to 1 px. It
	# sizes to its text now (the text is shortened in _short); the box keeps it at the right edge.
	_label.clip_text = false
	hb.add_child(_label)
	modulate.a = 0.0


func _process(delta: float) -> void:
	var id: String = Tunes.now_playing()
	if id != _id:
		_id = id
		if id != "":
			_label.text = short("%s, %s" % [tr(Tunes.title(id)), tr(Tunes.artist_name(id))])
			_t = 0.0
	_t += delta
	var want: float = 0.0
	if _id != "":
		want = 1.0 if _t < BRIGHT_S else SUBTLE
	modulate.a = move_toward(modulate.a, want, delta / (0.8 if want > modulate.a else 1.6))


## [qafix] Long song + artist names end in an ellipsis instead of running off the screen.
static func short(text: String, max_chars: int = 56) -> String:
	return text if text.length() <= max_chars else text.left(max_chars - 1).strip_edges() + "…"


class NoteIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(16, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Color(1.0, 0.86, 0.55)
		draw_circle(Vector2(5.5, 17.0), 4.0, c)
		draw_line(Vector2(9.2, 17.0), Vector2(9.2, 3.0), c, 1.8, true)
		draw_line(Vector2(9.2, 3.0), Vector2(14.5, 6.5), c, 2.2, true)
