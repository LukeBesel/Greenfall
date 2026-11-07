class_name GoalsPanel
extends VBoxContainer
## Compact goal tracker (top-right, under the district line). No card: right-aligned text over a
## hairline progress line. Shows the current goal; the toggle_goals key (G / L3) expands it to
## the next three with their rewards. The restart checklist (tutorial steps) uses the same style
## above the goal and fades away once the tutorial is done. A finished goal flashes green, sends
## an elegant toast to the notification stack, then the next one fades in.
## In Minimal HUD mode the tracker dims after a few seconds without progress.

const W: float = 280.0
const ROW_W: float = W  ## titles must fit (tests/test_qa_fixes_c.gd)
const CYAN := Color(0.55, 0.9, 1.0)
const DIM_AFTER_S: float = 6.0

var hud: Node
var expanded: bool = false
var _goals: Goals
var _head: Label
var _check: VBoxContainer
var _check_cap: Label
var _check_text: Label
var _rows: Array[Dictionary] = []
var _idle: float = 0.0
var _last_sig: String = ""
var _alpha: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	add_theme_constant_override("separation", 8)
	# Restart checklist block (tutorial).
	_check = VBoxContainer.new()
	_check.add_theme_constant_override("separation", 1)
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_check)
	_check_cap = _cap("")
	_check.add_child(_check_cap)
	_check_text = UITheme.label("", 14, UITheme.CREAM)
	_check_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_check_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_check_text.custom_minimum_size = Vector2(W, 0)
	_check.add_child(_check_text)
	_check.visible = false
	_head = _cap("")
	add_child(_head)
	for k: int in 3:
		_rows.append(_make_row())
	EventBus.tutorial_changed.connect(set_checklist)
	if DevHooks.get_s("hud-goals", "") == "expanded":
		expanded = true
	visible = false


static func _cap(t: String) -> Label:
	var l := UITheme.label(t, 12, UITheme.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _make_row() -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	var title := UITheme.label("", 14, UITheme.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.custom_minimum_size = Vector2(W, 0)
	wrap.add_child(title)
	var line := Control.new()
	line.custom_minimum_size = Vector2(W, 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)
	var r: Dictionary = {"wrap": wrap, "title": title, "line": line, "goal": -1, "shown": 0.0, "flash": 0.0, "busy": false}
	line.draw.connect(func() -> void: _draw_line(r))
	wrap.visible = false
	return r


## Restart checklist text (EventBus.tutorial_changed); "" hides it with a fade.
func set_checklist(text: String) -> void:
	_idle = 0.0
	if text == "":
		if _check.visible:
			var tw := _check.create_tween()
			tw.tween_property(_check, "modulate:a", 0.0, 0.6)
			tw.tween_callback(func() -> void: _check.visible = false)
		return
	var step: int = int(GameState.flags.get("tutorial_step", 0))
	var n: int = Tutorial.STEPS.size()
	_check_cap.text = ("R E S T A R T   C H E C K L I S T    %d / %d" % [mini(step + 1, n), n]) if step < n else "N E X T   S T E P"
	var was: String = _check_text.text
	_check_text.text = text
	if not _check.visible or _check.modulate.a < 0.99 or _strip_count(was) != _strip_count(text):
		_check.visible = true
		_check.modulate.a = 0.0
		_check.create_tween().tween_property(_check, "modulate:a", 1.0, 0.4)


## Step text without its "  3/8" counter (so counting up doesn't re-fade the block).
static func _strip_count(t: String) -> String:
	var i: int = t.rfind("   ")
	return t.substr(0, i) if i > 0 and t.substr(i).strip_edges().contains("/") else t


func toggle() -> void:
	expanded = not expanded
	_idle = 0.0
	Audio.play("click", 1.1 if expanded else 0.95, -12.0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("toggle_goals"):
		return
	var w: Node = hud.get("world") if hud else null
	if w and w.has_method("any_modal_open") and bool(w.call("any_modal_open")):
		return
	toggle()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _goals == null:
		var w: Node = hud.get("world") if hud else null
		_goals = (w.get("goals") as Goals) if w else null
		if _goals == null:
			return
		_goals.completed.connect(_on_completed)
		visible = true
	var total: int = _goals.chain.size()
	var done: int = _goals.done_count()
	var show_n: int = 3 if expanded else 1
	_head.visible = expanded
	_head.text = ("G O A L S    %d / %d" % [done, total]) if done < total else "A L L   G O A L S   D O N E"
	var sig: String = ""
	for k: int in _rows.size():
		var r: Dictionary = _rows[k]
		(r["wrap"] as Control).visible = k < show_n and int(r["goal"]) >= 0
		if r["busy"]:
			continue
		var gi: int = r["goal"]
		if gi < 0 or _goals.is_done(gi):
			var nxt: int = _next_free()
			if nxt != gi:
				_assign(r, nxt, gi >= 0)
			continue
		r["shown"] = lerpf(float(r["shown"]), _goals.progress(gi), clampf(delta * 6.0, 0.0, 1.0))
		sig += "%d:%.3f," % [gi, _goals.progress(gi)]
		(r["line"] as Control).queue_redraw()
	# Minimal: dim after a few seconds without progress.
	if sig != _last_sig:
		_last_sig = sig
		_idle = 0.0
	_idle += delta
	var want: float = 1.0
	if Settings.hud_mode == Settings.HudMode.MINIMAL and not expanded and _idle > DIM_AFTER_S:
		want = 0.5
	_alpha = move_toward(_alpha, want, delta * (3.0 if want > _alpha else 0.5))
	modulate.a = _alpha


## First current goal no row is showing.
func _next_free() -> int:
	var shown: Dictionary = {}
	for r: Dictionary in _rows:
		shown[int(r["goal"])] = true
	for i: int in _goals.current():
		if not shown.has(i):
			return i
	return -1


func _assign(r: Dictionary, gi: int, animate: bool) -> void:
	r["goal"] = gi
	r["flash"] = 0.0
	var wrap: Control = r["wrap"]
	if gi < 0:
		wrap.visible = false
		return
	r["shown"] = _goals.progress(gi)
	var title: Label = r["title"]
	title.text = tr(str(_goals.chain[gi].get("text", "")))
	title.add_theme_color_override("font_color", UITheme.CREAM)
	if animate:
		r["busy"] = true
		wrap.modulate.a = 0.0
		var tw := wrap.create_tween()
		tw.tween_property(wrap, "modulate:a", 1.0, 0.45)
		tw.tween_callback(func() -> void: r["busy"] = false)
	else:
		wrap.modulate.a = 1.0


func _draw_line(r: Dictionary) -> void:
	var line: Control = r["line"]
	var gi: int = r["goal"]
	if _goals == null or gi < 0:
		return
	var w: float = line.size.x
	var y: float = 3.0
	var f: float = clampf(float(r["shown"]), 0.0, 1.0)
	var fl: float = float(r["flash"])
	var col: Color = CYAN.lerp(UITheme.GREEN, fl)
	var font: Font = UITheme.font()
	var tgt: float = _goals.target_of(gi)
	var v: float = minf(_goals.value_of(gi), tgt)
	var txt: String = ("%s / %s" % [_n(floorf(v)), _n(tgt)]) if tgt > 1.0 else ""
	if fl > 0.0:
		txt = tr("DONE")
	var lw: float = 150.0 if expanded else 120.0
	var x0: float = w - lw
	line.draw_rect(Rect2(x0, y, lw, 2.0), Color(1, 1, 1, 0.14))
	line.draw_rect(Rect2(x0, y, lw * (1.0 if fl > 0.0 else f), 2.0), col)
	var tx: float = x0 - 8.0
	if txt != "":
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		tx -= tw
		line.draw_string_outline(font, Vector2(tx, y + 8.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.4))
		line.draw_string(font, Vector2(tx, y + 8.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.GREEN if fl > 0.0 else UITheme.MUTED)
		tx -= 12.0
	if expanded:
		var rw: String = reward_text(_goals.reward_of(gi), 1.0)
		if rw != "":
			var w2: float = font.get_string_size(rw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			line.draw_string_outline(font, Vector2(tx - w2, y + 8.0), rw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.4))
			line.draw_string(font, Vector2(tx - w2, y + 8.0), rw, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UITheme.GOLD, 0.9))


func _on_completed(gi: int) -> void:
	_idle = 0.0
	var reward: String = reward_text(_goals.reward_of(gi), 1.0)
	if hud and hud.has_method("notify"):
		hud.call("notify", tr("Goal complete  ·  %s%s") % [tr(str(_goals.chain[gi].get("text", ""))), ("    " + reward) if reward != "" else ""], "goal")
	Audio.play("ding", 1.35, -12.0)
	for r: Dictionary in _rows:
		if int(r["goal"]) == gi:
			_celebrate(r)
			return


func _celebrate(r: Dictionary) -> void:
	r["busy"] = true
	var wrap: Control = r["wrap"]
	(r["title"] as Label).add_theme_color_override("font_color", UITheme.GREEN)
	var tw := wrap.create_tween()
	tw.tween_method(func(t: float) -> void:
		r["flash"] = t
		(r["line"] as Control).queue_redraw(), 0.0, 1.0, 0.25)
	tw.tween_interval(1.1)
	tw.tween_property(wrap, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		r["busy"] = false
		_assign(r, _next_free(), true))


static func reward_text(reward: Dictionary, t: float) -> String:
	var parts: Array[String] = []
	for k: String in ["cubes", "seeds"]:
		if float(reward.get(k, 0.0)) > 0.0:
			parts.append((TranslationServer.translate("+%s cubes") if k == "cubes" else TranslationServer.translate("+%s seeds")) % _n(round(float(reward[k]) * t)))
	return "  ".join(parts)


static func _n(v: float) -> String:
	return Settings.fmt(BigNum.from_float(v))


## Number of goal rows on screen (tests).
func visible_rows() -> int:
	var n: int = 0
	for r: Dictionary in _rows:
		if (r["wrap"] as Control).visible:
			n += 1
	return n
