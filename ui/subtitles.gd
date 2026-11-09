class_name Subtitles
extends CanvasLayer
## [intro2] The one subtitle line for the whole game: WREN, story narration, the Ledger's intercepts
## and cinematic captions all go through here.
## Rules (owner playtest #1: "way too fast", "multiple lines at once", "words glitching"):
##   - ONE line on screen at a time, bottom centre, on a soft dark pill with a shadow.
##   - Readable text never scrambles while it is up: it fades in with a light glitch (a quick
##     chromatic flicker and a 1-2 frame scramble that resolves within ~150 ms), then stays clean.
##   - Story-redacted text glitches HEAVILY, but only the marked spans: wrap them in
##     [glitch]...[/glitch] (or write [REDACTED] / ████), and the rest of the line stays clean.
##     Ledger intercepts also get short jitter bursts of the whole pill (the words stay put).
##   - Each line stays fully visible for duration_for(text) = 55 ms per character + 1.2 s
##     (at least 2.5 s), then fades, then a short gap before the next one.
##   - Long lines are split at sentence (then clause) boundaries into chunks that fit one line;
##     every chunk follows the same timing rule.
## Lines queue; show_now() replaces whatever is up (cinematics that own their pacing).
## While the HUD is hidden (cinematics, letterbox) the line drops into the bottom letterbox bar and
## draws above the cinematic overlays; during play it sits just above the hotbar.

signal line_done(speaker: String)

const MS_PER_CHAR: float = 0.055
const BASE_S: float = 1.2
const MIN_S: float = 2.5
const FADE_S: float = 0.3
const GAP_S: float = 0.45
const MAX_CHARS: int = 80
const MAX_CHARS_CJK: int = 30
const MAX_QUEUE: int = 8
## [onboard2] Owner: "I can't read two lines at once." This bar is THE message line: speech
## (WREN, Ledger, intro) and every toast (rewards, sightings, goals, unlocks, hints, achievements,
## "now playing") share it, one line at a time, each held its reading time. Priorities: speech 3,
## story 2, goal/level/hint/achievement 1, info 0, low (sightings, now playing) -1. Higher goes
## first (never cutting off the line on screen); a queued line with the same wording but other
## numbers is replaced by the newer one ("+12 cubes" then "+15 cubes" shows once); low-value lines
## that waited too long are dropped; speech and story are never dropped.
const TOAST_MAX_QUEUE: int = 6
const STALE_S: Dictionary = {0: 20.0, -1: 12.0}  # [v4calm] was {0: 25, -1: 40}
const TOAST_KINDS: Dictionary = {
	"story": {"prio": 2, "col": Color(1.0, 0.86, 0.6)},
	"goal": {"prio": 1, "col": Color(0.7, 0.93, 1.0)},
	"level": {"prio": 1, "col": Color(0.72, 1.0, 0.85)},
	"hint": {"prio": 1, "col": Color(0.78, 1.0, 0.78)},
	"achievement": {"prio": 1, "col": Color(1.0, 0.82, 0.45)},
	"info": {"prio": 0, "col": Color(0.95, 0.94, 0.9)},
	"low": {"prio": -1, "col": Color(0.88, 0.88, 0.85)},
	"reward": {"prio": -1, "col": Color(0.88, 0.88, 0.85)},  # [v4calm] cut (CUT_KINDS)
	"tip": {"prio": 1, "col": Color(0.78, 1.0, 0.78)},  # [v4calm] same as hint
}

const SPEAKERS: Dictionary = {
	"": {"tag": "", "tag_col": Color(1, 1, 1), "col": Color(0.95, 0.94, 0.9)},
	"wren": {"tag": "WREN", "tag_col": Color(0.5, 0.86, 1.0), "col": Color(0.93, 0.96, 1.0)},
	"ledger": {"tag": "LEDGER", "tag_col": Color(1.0, 0.36, 0.26), "col": Color(1.0, 0.8, 0.55)},
	"ledger_ok": {"tag": "LEDGER", "tag_col": Color(0.45, 0.95, 0.6), "col": Color(0.82, 1.0, 0.86)},
}

## The live instance (the game world's). Story code without a reference uses Subtitles.say().
static var current: Subtitles
## Cinematics that want the low placement even with the HUD up (refcount).
static var _forced_low: int = 0

var world: Node
## Seconds each chunk was actually fully visible (dev check: --intro prints the tightest margin).
var shown_log: Array[Dictionary] = []

var _root: Control
var _mc: MarginContainer
var _pill: PanelContainer
var _tag: Label
var _label: Label
var _queue: Array[Dictionary] = []
var _cur: Dictionary = {}
var _phase: int = 0  # 0 idle, 1 fade in, 2 hold, 3 fade out, 4 gap
var _pt: float = 0.0
var _hold: float = 0.0
var _beeps_left: int = 0  # [main] robot beep-talk under spoken lines (no human voice-over)
var _beep_t: float = 0.0
var _beep_pitch: float = 1.0
var _low: float = -1.0
var _chars: String = ""
var _mask: Array = []
var _heavy: bool = false
var _app_t: float = 0.0
var _noise_t: float = 0.0
var _burst_t: float = 0.0
var _burst_wait: float = 2.0
var _col: Color = Color.WHITE
var _dirty: bool = false
var _clock: float = 0.0  # [onboard2] for stale toasts
var _speech_hidden: bool = false


# --- Timing rule (pure, tested) ---------------------------------------------------------

## [v4calm] Owner item 49 ("far too many messages"): toast kinds that never reach the screen.
## reward = stat and reward chatter (parts found, hex level-ups, new looks, event payouts),
## achievement / level / low = unlocks the menus already show. Story beats, goals, how-to hints and
## warnings (info) still show, one at a time.
const CUT_KINDS: Array[String] = ["reward", "achievement", "level", "low"]
## [v4calm] Breathing room between two messages on the bar when a toast is involved.
const TOAST_GAP_S: float = 2.0
## [v4calm] Messages cut so far (dev: the clarity log's summary).
static var cut_count: int = 0


## [v4calm] True when a toast is cut (never shown). Same kind mapping as queue_toast.
static func cut(text: String, kind: String) -> bool:
	return toast_kind(text, kind) in CUT_KINDS


## [v4calm] Seconds of empty bar after a line before the next one: a short beat between spoken
## lines, a longer one whenever a toast is the one leaving or the one coming.
static func gap_after(speaker: String, next_is_toast: bool) -> float:
	return TOAST_GAP_S if speaker.begins_with("toast:") or next_is_toast else GAP_S


func _next_is_toast() -> bool:
	return not _queue.is_empty() and int(_queue[0].get("prio", 3)) < 3


## [v4calm] Owner item 50: the soft chirp under a WREN line (dB).
const CHIRP_DB: float = -22.0


## [v4calm] Beeps under a spoken chunk: one soft chirp on the first chunk of a WREN line, else none.
static func beeps_for(speaker: String, first_chunk: bool) -> int:
	return 1 if speaker == "wren" and first_chunk else 0


## Seconds a line (or chunk) stays fully visible.
static func duration_for(text: String) -> float:
	return maxf(MIN_S, plain(text).length() * MS_PER_CHAR + BASE_S)


const GLITCH_OPEN := "[glitch]"
const GLITCH_CLOSE := "[/glitch]"
const NOISE: String = "#%&$@/\\|=+*<>01▒░▓"


## The text without glitch markup (what the reader reads; what timing counts).
static func plain(text: String) -> String:
	return text.replace(GLITCH_OPEN, "").replace(GLITCH_CLOSE, "")


## Splits marked-up text into its plain characters and a per-character "heavy glitch" mask.
## [REDACTED] and █ runs are always heavy.
static func glitch_mask(text: String) -> Array:
	var chars: String = ""
	var mask: Array[bool] = []
	var on: bool = false
	var i: int = 0
	while i < text.length():
		if text.substr(i, GLITCH_OPEN.length()) == GLITCH_OPEN:
			on = true
			i += GLITCH_OPEN.length()
			continue
		if text.substr(i, GLITCH_CLOSE.length()) == GLITCH_CLOSE:
			on = false
			i += GLITCH_CLOSE.length()
			continue
		chars += text[i]
		mask.append(on or text[i] == "█")
		i += 1
	var at: int = chars.find("[REDACTED]")
	while at >= 0:
		for k: int in 10:
			mask[at + k] = true
		at = chars.find("[REDACTED]", at + 1)
	return [chars, mask]


## Balances glitch tags across chunks (a span cut by a chunk break carries on in the next).
static func _balance(parts: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var open: bool = false
	for p: String in parts:
		var q: String = (GLITCH_OPEN + p) if open else p
		var o: int = q.rfind(GLITCH_OPEN)
		var c: int = q.rfind(GLITCH_CLOSE)
		open = o >= 0 and o > c
		out.append(q + GLITCH_CLOSE if open else q)
	return out


## Total screen time of a queued line: every chunk's hold plus its fades and the gaps.
static func total_time(text: String) -> float:
	var t: float = 0.0
	for c: String in chunks(text):
		t += duration_for(c) + FADE_S * 2.0 + GAP_S
	return t


static func _is_cjk(text: String) -> bool:
	for i: int in mini(text.length(), 12):
		if text.unicode_at(i) >= 0x2E80:
			return true
	return false


## The longest chunk chunks() produces for this text's script.
static func max_chars_for(text: String) -> int:
	return MAX_CHARS_CJK if _is_cjk(text) else MAX_CHARS


## Splits a line into chunks that each fit on one subtitle line: whole sentences where possible,
## then clauses (commas, dashes), then words.
static func chunks(text: String) -> PackedStringArray:
	text = text.strip_edges().replace("\n", " ")
	var out := PackedStringArray()
	if text == "":
		return out
	var cjk: bool = _is_cjk(text)
	var limit: int = max_chars_for(text)
	if plain(text).length() <= limit:
		out.append(text)
		return out
	var sentences: PackedStringArray = _split_after(text, ["。", "！", "？", ". ", "! ", "? ", "… "])
	var cur: String = ""
	for s: String in sentences:
		var cand: String = s if cur == "" else cur + ("" if cjk else " ") + s
		if plain(cand).length() <= limit:
			cur = cand
			continue
		if cur != "":
			out.append(cur)
		cur = ""
		if plain(s).length() <= limit:
			cur = s
		else:
			out.append_array(_split_long(s, limit))
	if cur != "":
		out.append(cur)
	return _balance(out)


## Splits after any of the separators (kept on the left piece, surrounding spaces dropped).
static func _split_after(text: String, seps: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var start: int = 0
	var i: int = 0
	while i < text.length():
		var hit: String = ""
		for s: String in seps:
			if text.substr(i, s.length()) == s:
				hit = s
				break
		if hit != "":
			var piece: String = text.substr(start, i + hit.length() - start).strip_edges()
			if piece != "":
				out.append(piece)
			i += hit.length()
			start = i
		else:
			i += 1
	var rest: String = text.substr(start).strip_edges()
	if rest != "":
		out.append(rest)
	return out


## A sentence too long for one line: break at the clause mark nearest the middle, else a space.
static func _split_long(s: String, limit: int) -> PackedStringArray:
	var out := PackedStringArray()
	if plain(s).length() <= limit:
		out.append(s)
		return out
	@warning_ignore("integer_division")
	var mid: int = s.length() / 2
	var best: int = -1
	for mark: String in [", ", "; ", " — ", "— ", ": ", "、", "，"]:
		var from: int = 0
		while true:
			var at: int = s.find(mark, from)
			if at < 0:
				break
			var cut: int = at + mark.length()
			if best < 0 or absi(cut - mid) < absi(best - mid):
				best = cut
			from = at + 1
	if best <= 0 or best >= s.length() or absf(best - mid) > s.length() * 0.3:
		best = s.rfind(" ", mini(mid + 4, s.length() - 1))
		if best <= 0:
			best = mid  # no spaces (CJK): cut in the middle
	var a: String = s.substr(0, best).strip_edges()
	var b: String = s.substr(best).strip_edges()
	if a == "" or b == "":
		a = s.substr(0, mid)
		b = s.substr(mid)
	out.append_array(_split_long(a, limit))
	out.append_array(_split_long(b, limit))
	return out


# --- Static helpers for story code -------------------------------------------------------

## Queue a line on the live subtitle bar (no-op if there is none). speaker: "", wren, ledger, ledger_ok.
static func say(text: String, speaker: String = "") -> void:
	if current and is_instance_valid(current):
		current.queue_line(text, speaker)


## [onboard2] Post a toast on the message line (kinds: TOAST_KINDS). Returns false if there is no bar.
static func post(text: String, kind: String = "info") -> bool:
	if current and is_instance_valid(current):
		current.queue_toast(text, kind)
		return true
	return false


## Keep the low (letterbox) placement even while the HUD is visible.
static func force_low(on: bool) -> void:
	_forced_low = maxi(0, _forced_low + (1 if on else -1))


# --- Node ------------------------------------------------------------------------------

func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	layer = 6
	if world == null:
		world = get_parent()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_mc = MarginContainer.new()
	_mc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_mc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_mc)
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mc.add_child(_pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(row)
	_tag = UITheme.label("", 12, Color(0.5, 0.86, 1.0))
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tag)
	_label = UITheme.label("", 19, Color(0.95, 0.94, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.add_theme_constant_override("shadow_outline_size", 4)
	row.add_child(_label)
	_pill.modulate.a = 0.0
	_pill.visible = false
	_apply_settings()
	Settings.changed.connect(_apply_settings)


## Subtitle settings: on/off, size, a more opaque backing.
func _apply_settings() -> void:
	visible = true  # [onboard2] toasts share this bar; the subtitle setting hides speech lines only
	var sz: Array[int] = UITheme.subtitle_sizes()
	_tag.add_theme_font_size_override("font_size", sz[0])
	_label.add_theme_font_size_override("font_size", sz[1])
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.035, 0.9 if Settings.subtitle_background else 0.68)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 7
	sb.content_margin_bottom = 8
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 2)
	_pill.add_theme_stylebox_override("panel", sb)


## Queue a line. Long lines become several one-line chunks shown back to back.
func queue_line(text: String, speaker: String = "") -> void:
	text = tr(text) if text != "" else text  # [l10n] raw data lines (formatted ones arrive translated)
	if text.strip_edges() == "":
		return
	var cs: PackedStringArray = chunks(text)
	var items: Array[Dictionary] = []
	for i: int in cs.size():
		items.append({"text": cs[i], "speaker": speaker, "first": i == 0, "last": i == cs.size() - 1, "prio": 3, "t": _clock})
	_enqueue(items)
	var speech: int = 0
	for q: Dictionary in _queue:
		speech += 1 if int(q["prio"]) >= 3 else 0
	while speech > MAX_QUEUE:  # an old backlog of speech: the oldest speech goes
		for k: int in _queue.size():
			if int(_queue[k]["prio"]) >= 3:
				_queue.remove_at(k)
				break
		speech -= 1
	if _phase == 0:
		_next()


## [onboard2] A toast on the message line (see TOAST_KINDS).
func queue_toast(text: String, kind: String = "info") -> void:
	text = tr(text) if text != "" else text
	if text.strip_edges() == "":
		return
	kind = toast_kind(text, kind)
	if kind in CUT_KINDS:  # [v4calm] item 49
		cut_count += 1
		return
	var prio: int = int((TOAST_KINDS[kind] as Dictionary)["prio"])
	if current_text() == text or (_phase == 4 and str(_cur.get("text", "")) == text):
		return  # the same line is up right now
	var key: String = merge_key(text)
	for q: Dictionary in _queue:
		if q.has("key") and str(q["key"]) == key:
			q["text"] = text  # the newer numbers win; one line instead of several
			q["t"] = _clock
			return
	var cs: PackedStringArray = chunks(text)
	var items: Array[Dictionary] = []
	for i: int in cs.size():
		items.append({"text": cs[i], "speaker": "toast:" + kind, "last": i == cs.size() - 1, "prio": prio, "t": _clock, "key": key if i == 0 else key + "#%d" % i})
	_enqueue(items)
	# Too many toasts waiting: the lowest-value, oldest go (story is kept).
	var n: int = 0
	for q: Dictionary in _queue:
		n += 1 if int(q["prio"]) < 3 else 0
	while n > TOAST_MAX_QUEUE:
		var worst: int = -1
		for k: int in _queue.size():
			var pk: int = int(_queue[k]["prio"])
			if pk < 2 and (worst < 0 or pk < int(_queue[worst]["prio"])):
				worst = k
		if worst < 0:
			break
		_queue.remove_at(worst)
		n -= 1
	if _phase == 0:
		_next()


## Kind from the text when the caller only said "info" (achievements, sightings).
static func toast_kind(text: String, kind: String) -> String:
	if kind in ["info", "story", "hint"]:  # [v4calm] achievements arrive as "story"
		if text.begins_with("Achievement") or text.begins_with(TranslationServer.translate("Achievement: %s. %s").get_slice("%", 0)):
			return "achievement"
		if text.begins_with(TranslationServer.translate("New sighting: %s. It's in the Codex now.").get_slice("%", 0)) or text.begins_with("New sighting"):
			return "low"
	return kind if TOAST_KINDS.has(kind) else "info"


## The wording without its numbers: "+12 cubes" and "+15 cubes" merge.
static func merge_key(text: String) -> String:
	var re := RegEx.create_from_string("[0-9][0-9.,]*[KMBTkmbt%]?")
	return re.sub(text, "#", true)


## Inserts after everything of the same or higher priority (stable), never before the line on screen.
func _enqueue(items: Array[Dictionary]) -> void:
	if items.is_empty():
		return
	var prio: int = int(items[0]["prio"])
	var at: int = _queue.size()
	for k: int in _queue.size():
		if int(_queue[k]["prio"]) < prio:
			at = k
			break
	for i: int in items.size():
		_queue.insert(at + i, items[i])


## WREN's signal (stage was the old glitch level; every line is shown clean now).
func show_line(text: String, _stage: int = 2) -> void:
	queue_line(text, "wren")


## Drop the queued speech and show this line now (replaces whatever is up). "" just clears.
## [onboard2] Queued toasts are kept: nothing important is lost.
func show_now(text: String, speaker: String = "") -> void:
	_queue = _queue.filter(func(q: Dictionary) -> bool: return int(q["prio"]) < 3)
	if _phase == 2 and not _cur.is_empty():
		_log_shown()
	_cur = {}
	_phase = 0
	_beeps_left = 0
	_pill.modulate.a = 0.0
	_pill.visible = false
	if text != "":
		queue_line(text, speaker)


func clear() -> void:
	show_now("")


## Anything showing or queued (for one speaker, or "*" for any).
func is_busy(speaker: String = "*") -> bool:
	if speaker == "*":  # [onboard2] speech only: toasts on the bar never hold up a cutscene
		if not _cur.is_empty() and int(_cur.get("prio", 3)) >= 3 and _phase in [1, 2, 3]:
			return true
		return _queue.any(func(q: Dictionary) -> bool: return int(q["prio"]) >= 3)
	if not _cur.is_empty() and str(_cur.get("speaker", "")) == speaker and _phase in [1, 2, 3]:
		return true
	for q: Dictionary in _queue:
		if str(q["speaker"]) == speaker:
			return true
	return false


## The text on screen ("" when nothing is).
func current_text() -> String:
	return str(_cur.get("text", "")) if _phase in [1, 2, 3] else ""


func _next() -> void:
	if _queue.is_empty():
		_phase = 0
		_cur = {}
		_pill.visible = false
		return
	_cur = _queue.pop_front()
	var spk: String = str(_cur["speaker"])
	if int(_cur.get("prio", 3)) < 2 and STALE_S.has(int(_cur["prio"])) and _clock - float(_cur.get("t", _clock)) > float(STALE_S[int(_cur["prio"])]):
		_next()  # waited too long; it no longer matters
		return
	var sp: Dictionary = SPEAKERS.get(spk, SPEAKERS[""])
	if spk.begins_with("toast:"):
		sp = {"tag": "", "tag_col": Color.WHITE, "col": (TOAST_KINDS.get(spk.substr(6), TOAST_KINDS["info"]) as Dictionary)["col"]}
	_tag.text = tr(str(sp["tag"])) if str(sp["tag"]) != "" else ""
	_tag.visible = _tag.text != ""
	_tag.add_theme_color_override("font_color", sp["tag_col"])
	_col = sp["col"]
	_label.add_theme_color_override("font_color", _col)
	var gm: Array = glitch_mask(str(_cur["text"]))
	_chars = gm[0]
	_mask = gm[1]
	_heavy = _mask.has(true)
	_label.text = _chars
	_app_t = 0.0
	_noise_t = 0.0
	_burst_t = 0.0
	_burst_wait = randf_range(1.2, 2.6)
	_hold = duration_for(_chars)
	_phase = 1
	_pt = 0.0
	# Speech with subtitles switched off still runs its timing (cutscenes wait on it), unseen.
	_speech_hidden = not spk.begins_with("toast:") and not Settings.subtitles_enabled
	_pill.visible = not _speech_hidden
	_pill.modulate.a = 0.0
	if not _speech_hidden and not spk.begins_with("toast:"):
		Audio.duck(_hold + FADE_S * 2.0)  # [sound] music dips under the line
		if str(_cur["speaker"]).begins_with("ledger") and Audio.has_sound("ledger_tick"):
			Audio.play("ledger_tick", 1.0, -18.0, 0.05)
		else:  # [v4calm] owner item 50: no beep-talk. One soft chirp at the start of a WREN line, none for narration
			_beeps_left = beeps_for(str(_cur["speaker"]), bool(_cur.get("first", true)))
			_beep_t = 0.0
			_beep_pitch = 1.2


## Purposeful glitches. Readable words: a light flicker and scramble on appearance only (~150 ms).
## Marked spans ([glitch], [REDACTED], █): heavy, continuous scramble. Ledger intercepts: short
## jitter bursts of the whole line; its words never change.
func _glitch(delta: float) -> void:
	_app_t += delta
	var appear: float = 1.0 - clampf(_app_t / 0.15, 0.0, 1.0)
	var ledger: bool = str(_cur.get("speaker", "")) == "ledger"
	var burst: bool = false
	if ledger:
		_burst_wait -= delta
		if _burst_wait <= 0.0:
			_burst_t = randf_range(0.08, 0.16)
			_burst_wait = randf_range(1.6, 3.2)
		_burst_t = maxf(0.0, _burst_t - delta)
		burst = _burst_t > 0.0
	_noise_t -= delta
	var tick: bool = _noise_t <= 0.0
	if tick:
		_noise_t = 0.045
	if appear > 0.0 or (_heavy and tick) or _dirty:
		var out: PackedStringArray = _chars.split("")
		for i: int in out.size():
			if out[i] == " ":
				continue
			var heavy: bool = i < _mask.size() and bool(_mask[i])
			if heavy and randf() < 0.75:
				out[i] = NOISE[randi() % NOISE.length()]
			elif appear > 0.0 and randf() < 0.4 * appear:
				out[i] = NOISE[randi() % NOISE.length()]
		_label.text = "".join(out)
		_dirty = appear > 0.0
	# Chromatic flicker: on appearance (and in Ledger bursts) the line shifts a pixel or two and
	# its colour splits toward cyan / magenta for a frame at a time.
	var amt: float = maxf(appear, 1.0 if burst else 0.0)
	if amt > 0.0:
		offset = Vector2(randf_range(-2.5, 2.5), randf_range(-1.0, 1.0)) * amt
		var tint: Color = Color(0.55, 1.0, 1.0) if randf() < 0.5 else Color(1.0, 0.5, 0.85)
		_label.add_theme_color_override("font_color", _col.lerp(tint, 0.5 * amt))
		_dirty = true
	elif offset != Vector2.ZERO or _dirty:
		offset = Vector2.ZERO
		_label.add_theme_color_override("font_color", _col)
		if not _heavy:
			_label.text = _chars
		_dirty = false


func _log_shown() -> void:
	var t: String = str(_cur.get("text", ""))
	shown_log.append({"text": t, "shown": _pt, "need": duration_for(t)})
	if shown_log.size() > 200:
		shown_log.pop_front()


func _is_low() -> bool:
	if _forced_low > 0:
		return true
	var hud: Variant = world.get("hud") if world else null
	return hud is CanvasLayer and not (hud as CanvasLayer).visible


func _process(delta: float) -> void:
	# Placement: inside the bottom letterbox bar during cinematics, above the hotbar in play.
	var low: float = 1.0 if _is_low() else 0.0
	_low = low if _low < 0.0 else move_toward(_low, low, delta * 4.0)
	layer = 45 if low > 0.5 else 6
	_mc.add_theme_constant_override("margin_bottom", int(lerpf(182.0, 16.0, _low)))
	_clock += delta
	if _phase == 0:
		offset = Vector2.ZERO
		return
	_pt += delta
	if _beeps_left > 0:  # [main] beep-talk
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beeps_left -= 1
			_beep_t = randf_range(0.07, 0.13)
			Audio.play("blip", _beep_pitch * randf_range(0.95, 1.05), CHIRP_DB, 0.0)
	if _phase in [1, 2, 3]:
		_glitch(delta)
	match _phase:
		1:
			_pill.modulate.a = clampf(_pt / FADE_S, 0.0, 1.0)
			if _pt >= FADE_S:
				_phase = 2
				_pt = 0.0
		2:
			_pill.modulate.a = 1.0
			if _pt >= _hold:
				_log_shown()
				_phase = 3
				_pt = 0.0
		3:
			_pill.modulate.a = 1.0 - clampf(_pt / FADE_S, 0.0, 1.0)
			if _pt >= FADE_S:
				_pill.modulate.a = 0.0
				if bool(_cur.get("last", true)):
					line_done.emit(str(_cur["speaker"]))
				_phase = 4
				_pt = 0.0
		4:
			if _pt >= gap_after(str(_cur.get("speaker", "")), _next_is_toast()):  # [v4calm] spacing
				_next()
