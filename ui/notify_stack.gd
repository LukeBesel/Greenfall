class_name NotifyStack
extends VBoxContainer
## One tidy notification stack (bottom-left) for toasts, achievements, Codex entries and story
## lines: at most MAX rows, short lifetimes, soft fades. A repeat of a visible message refreshes
## that row ("x2") instead of stacking. Each row is a thin coloured accent line plus text; no box.

const MAX: int = 3
const WIDTH: float = 300.0
const LIFE: Dictionary = {"info": 4.0, "hint": 5.5, "story": 6.0, "goal": 4.5, "level": 4.5}

var _rows: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)
	custom_minimum_size = Vector2(WIDTH, 0)


static func accent(kind: String, text: String) -> Color:
	if text.begins_with("Achievement"):
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
	l.max_lines_visible = 3
	row.add_child(l)
	row.modulate.a = 0.0
	add_child(row)
	_rows.append({"node": row, "label": l, "text": text, "count": 1, "left": float(LIFE.get(kind, 4.0)), "age": 0.0})
	while _rows.size() > MAX:
		var old: Dictionary = _rows.pop_front()
		var n: Control = old["node"]
		if is_instance_valid(n):
			n.queue_free()


func _process(delta: float) -> void:
	for i: int in range(_rows.size() - 1, -1, -1):
		var r: Dictionary = _rows[i]
		var n: Control = r["node"]
		if not is_instance_valid(n):
			_rows.remove_at(i)
			continue
		r["age"] = float(r["age"]) + delta
		r["left"] = float(r["left"]) - delta
		var a: float = minf(clampf(float(r["age"]) / 0.3, 0.0, 1.0), clampf(float(r["left"]) / 0.8, 0.0, 1.0))
		n.modulate.a = a
		if float(r["left"]) <= 0.0:
			n.queue_free()
			_rows.remove_at(i)


func count() -> int:
	return _rows.size()
