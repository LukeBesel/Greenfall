class_name LedgerUplink
extends CanvasLayer
## Intercepted Ledger transmissions. [intro2] Shown through the game's one subtitle line
## (ui/subtitles.gd) with a red LEDGER tag (green once the Ledger turns friendly), so they follow
## the same rules as every other line: one at a time, at the bottom, clean, long enough to read.
## The API is unchanged (show_line / show_now / is_busy / line_finished).

const RED := Color(1.0, 0.28, 0.2)
const AMBER := Color(1.0, 0.68, 0.22)
const GREEN := Color(0.45, 1.0, 0.6)

signal line_finished

static var _mono: Font

var _subs: Subtitles


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


## The world's subtitle line (or a private one when there is none, e.g. in tests).
func _bind() -> Subtitles:
	if _subs and is_instance_valid(_subs):
		return _subs
	if Subtitles.current and is_instance_valid(Subtitles.current):
		_subs = Subtitles.current
	else:
		_subs = Subtitles.new()
		add_child(_subs)
	if not _subs.line_done.is_connected(_on_done):
		_subs.line_done.connect(_on_done)
	return _subs


func _on_done(speaker: String) -> void:
	if speaker.begins_with("ledger"):
		line_finished.emit()


func is_busy() -> bool:
	var s: Subtitles = _bind()
	return s.is_busy("ledger") or s.is_busy("ledger_ok")


## Queue an intercepted line. friendly = the post-resolution, helpful Ledger (green).
## header is kept for callers; the subtitle line shows only the speaker tag.
func show_line(text: String, friendly: bool = false, _header: String = "") -> void:
	if visible and Audio.has_sound("glitch"):
		Audio.play("glitch", 1.0, -18.0 if friendly else -14.0)
	_bind().queue_line(text, "ledger_ok" if friendly else "ledger")


## Show a line immediately (cinematics), dropping anything queued. hold is ignored: the subtitle
## rule decides how long a line stays up.
func show_now(text: String, friendly: bool = false, _hold: float = -1.0) -> void:
	_bind().show_now(text, "ledger_ok" if friendly else "ledger")
