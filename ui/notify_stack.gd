class_name NotifyStack
extends VBoxContainer
## One tidy notification stack (bottom-left) for toasts, achievements, Codex entries and story
## lines: at most MAX rows, short lifetimes, soft fades. A repeat of a visible message refreshes
## that row ("x2") instead of stacking. Each row is a thin coloured accent line plus text; no box.

const MAX: int = 3
## [vqa] The stack never shows more than about this many text lines: older rows fade out early.
const MAX_LINES: int = 3
const WIDTH: float = 300.0
## [onboard2] A row on its way out fades over this long, then is gone: no half-faded "ghost"
## rows lingering behind newer ones.
const FADE_OUT_S: float = 0.25
const LIFE: Dictionary = {"info": 3.0, "hint": 4.2, "story": 4.8, "goal": 3.4, "level": 3.4}  # [vqa] shorter

var _rows: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(WIDTH, 0)


static func accent(kind: String, text: String) -> Color:
	if text.begins_with("Achievement") or text.begins_with(TranslationServer.translate("Achievement: %s. %s").get_slice("%", 0)):  # [l10n]
		return UITheme.GOLD
	match kind:
		"story": return UITheme.GOLD
		"hint": return UITheme.GREEN
		"goal": return Color(0.55, 0.9, 1.0)
		"level": return Color(0.5, 0.95, 0.75)
	return Color(UITheme.CREAM, 0.5)


func push(text: String, kind: String = "info") -> void:
	if text.strip_edges() == "":
		return
	text = tr(text)  # [l10n] plain data toasts (formatted ones arrive translated)
	for r: Dictionary in _rows:
		if str(r["text"]) == text and is_instance_valid(r["node"]):
			r["count"] = int(r["count"]) + 1
			(r["label"] as Label).text = "%s   x%d" % [text, int(r["count"])]
			r["left"] = float(LIFE.get(kind, 4.0))
			(r["node"] as Control).modulate.a = 1.0
			return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(2, 0)
	bar.color = accent(kind, text)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var l := UITheme.label(text, 14, UITheme.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(WIDTH - 12.0, 0)
	l.max_lines_visible = 2  # [vqa]
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(l)
	# [onboard] A soft backing fading to the right: bottom-left has no corner scrim, and thin text
	# over bright litter was hard to read.
	var back := PanelContainer.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", HudReadable.fade_backing(0.5))
	back.add_child(row)
	back.modulate.a = 0.0
	add_child(back)
	_rows.append({"node": back, "label": l, "text": text, "count": 1, "left": float(LIFE.get(kind, 4.0)), "age": 0.0})
	while _rows.size() > MAX:
		var old: Dictionary = _rows.pop_front()
		var n: Control = old["node"]
		if is_instance_valid(n):
			n.queue_free()
	# [onboard2] Make room now: rows other than the newest that would break the line budget leave
	# at once (a quick fade), instead of fading slowly at half opacity behind the new one.
	_retire_over_budget(1 if text.length() <= 36 else 2)  # ~36 characters fit one line at 14 px


func _process(delta: float) -> void:
	# [vqa] Line budget: while the rows wrap to more than MAX_LINES lines, the oldest fades out now.
	_retire_over_budget(-1)
	for i: int in range(_rows.size() - 1, -1, -1):
		var r: Dictionary = _rows[i]
		var n: Control = r["node"]
		if not is_instance_valid(n):
			_rows.remove_at(i)
			continue
		r["age"] = float(r["age"]) + delta
		r["left"] = float(r["left"]) - delta
		var a: float = minf(clampf(float(r["age"]) / 0.3, 0.0, 1.0), clampf(float(r["left"]) / FADE_OUT_S, 0.0, 1.0))
		n.modulate.a = a
		if float(r["left"]) <= 0.0:
			n.queue_free()
			_rows.remove_at(i)


## Oldest rows leave (FADE_OUT_S) while the stack is over MAX_LINES text lines. new_lines: the
## newest row's line count if its label hasn't been laid out yet (-1 = ask the label).
func _retire_over_budget(new_lines: int) -> void:
	var lines: int = 0
	for i: int in _rows.size():
		var l: Label = _rows[i]["label"]
		if not is_instance_valid(l) or float(_rows[i]["left"]) <= FADE_OUT_S:
			continue  # already leaving
		var n: int = new_lines if (i == _rows.size() - 1 and new_lines > 0) else maxi(1, l.get_line_count())
		lines += mini(n, 2)
	var k: int = 0
	while lines > MAX_LINES and k < _rows.size() - 1:
		var r: Dictionary = _rows[k]
		if float(r["left"]) > FADE_OUT_S and is_instance_valid(r["label"]):
			lines -= mini(maxi(1, (r["label"] as Label).get_line_count()), 2)
			r["left"] = FADE_OUT_S
		k += 1


## Rows currently readable (not on their way out).
func live_count() -> int:
	var n: int = 0
	for r: Dictionary in _rows:
		if float(r["left"]) > FADE_OUT_S:
			n += 1
	return n


func count() -> int:
	return _rows.size()
