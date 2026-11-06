class_name GoalsPanel
extends PanelContainer
## Compact goals tracker for the HUD (top-right, under the district readout). One slate glass
## card with three rows: goal text, hairline progress bar, count and reward. On completion the
## row flashes amber, the reward counts up, then it slides out and the next goal slides in.

const W: float = 300.0
const PAD: int = 10
const ROW_W: float = W - PAD * 2
const ROW_H: float = 46.0

var hud: Node
var _count_label: Label
var _rows: Array[Dictionary] = []
var _style_idle: StyleBoxFlat
var _style_done: StyleBoxFlat
var _goals: Goals
var _list: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -W - 22.0
	offset_right = -22.0
	offset_top = 96.0
	custom_minimum_size = Vector2(W, 0)
	add_theme_stylebox_override("panel", UITheme.box(Color(0.055, 0.06, 0.065, 0.74), UITheme.RUST, 1, 3, PAD))
	_style_idle = UITheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 2, 0)
	_style_done = UITheme.box(Color(1.0, 0.7, 0.26, 0.16), UITheme.GOLD, 1, 2, 0)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(head)
	var cap := UITheme.label("G O A L S", 12, UITheme.MUTED)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	_count_label = UITheme.label("", 12, UITheme.MUTED)
	head.add_child(_count_label)
	for k: int in 3:
		_rows.append(_make_row())
	visible = false


func _make_row() -> Dictionary:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(ROW_W, ROW_H)
	wrap.clip_contents = true
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(wrap)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style_idle)
	card.size = Vector2(ROW_W, ROW_H)
	card.custom_minimum_size = Vector2(ROW_W, ROW_H)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	card.add_child(hb)
	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(2, 0)
	accent.color = UITheme.GOLD
	hb.add_child(accent)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 10)
	mc.add_theme_constant_override("margin_top", 5)
	mc.add_theme_constant_override("margin_bottom", 5)
	hb.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	mc.add_child(vb)
	var title := UITheme.label("", 15, UITheme.CREAM)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	vb.add_child(title)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	vb.add_child(line)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 3)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.16), Color(0, 0, 0, 0), 0, 1, 0))
	line.add_child(bar)
	var count := UITheme.label("", 12, UITheme.MUTED)
	line.add_child(count)
	var reward := UITheme.label("", 12, UITheme.GOLD)
	reward.custom_minimum_size = Vector2(96, 0)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(reward)
	return {"wrap": wrap, "card": card, "accent": accent, "title": title, "bar": bar, "count": count,
		"reward": reward, "goal": -1, "busy": false}


func _process(_delta: float) -> void:
	if _goals == null:
		var w: Node = hud.get("world") if hud else null
		_goals = (w.get("goals") as Goals) if w else null
		if _goals == null:
			return
		_goals.completed.connect(_on_completed)
		visible = true
	var total: int = _goals.chain.size()
	var done: int = _goals.done_count()
	_count_label.text = "%d / %d" % [done, total] if done < total else "ALL DONE"
	for r: Dictionary in _rows:
		if r["busy"]:
			continue
		var gi: int = r["goal"]
		if gi < 0 or _goals.is_done(gi):
			var nxt: int = _next_free()
			if nxt != gi:
				_assign(r, nxt, gi >= 0 or nxt >= 0)
			continue
		_refresh(r)


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
	var card: PanelContainer = r["card"]
	var wrap: Control = r["wrap"]
	wrap.visible = gi >= 0
	if gi < 0:
		return
	card.add_theme_stylebox_override("panel", _style_idle)
	(r["accent"] as ColorRect).color = UITheme.GOLD
	(r["title"] as Label).text = str(_goals.chain[gi].get("text", ""))
	(r["title"] as Label).add_theme_color_override("font_color", UITheme.CREAM)
	(r["reward"] as Label).text = _reward_text(_goals.reward_of(gi), 1.0)
	_refresh(r)
	if animate:
		r["busy"] = true
		card.position.x = ROW_W + 12.0
		card.modulate.a = 0.0
		var tw := card.create_tween().set_parallel(true)
		tw.tween_property(card, "position:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "modulate:a", 1.0, 0.3)
		tw.chain().tween_callback(func() -> void: r["busy"] = false)
	else:
		card.position.x = 0.0
		card.modulate = Color.WHITE


func _refresh(r: Dictionary) -> void:
	var gi: int = r["goal"]
	var bar: ProgressBar = r["bar"]
	bar.value = lerpf(bar.value, _goals.progress(gi), 0.25)
	var tgt: float = _goals.target_of(gi)
	var v: float = minf(_goals.value_of(gi), tgt)
	(r["count"] as Label).text = ("%s/%s" % [_n(floorf(v)), _n(tgt)]) if tgt > 1.0 else ""


func _on_completed(gi: int) -> void:
	for r: Dictionary in _rows:
		if int(r["goal"]) == gi:
			_celebrate(r, gi)
			return


func _celebrate(r: Dictionary, gi: int) -> void:
	r["busy"] = true
	var card: PanelContainer = r["card"]
	var reward: Dictionary = _goals.reward_of(gi)
	card.add_theme_stylebox_override("panel", _style_done)
	(r["accent"] as ColorRect).color = UITheme.GREEN
	(r["title"] as Label).add_theme_color_override("font_color", UITheme.GOLD)
	(r["bar"] as ProgressBar).value = 1.0
	(r["count"] as Label).text = "DONE"
	var rl: Label = r["reward"]
	card.pivot_offset = Vector2(ROW_W, ROW_H) * 0.5
	var tw := card.create_tween()
	tw.tween_property(card, "modulate", Color(1.7, 1.45, 1.0), 0.08)
	tw.parallel().tween_property(card, "scale", Vector2(1.03, 1.03), 0.08)
	tw.tween_property(card, "modulate", Color.WHITE, 0.45)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(t: float) -> void: rl.text = _reward_text(reward, t), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(card, "position:x", -ROW_W - 12.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		r["busy"] = false
		_assign(r, _next_free(), true))


static func _reward_text(reward: Dictionary, t: float) -> String:
	var parts: Array[String] = []
	for k: String in ["cubes", "seeds"]:
		if float(reward.get(k, 0.0)) > 0.0:
			parts.append("+%s %s" % [_n(round(float(reward[k]) * t)), k])
	return "  ".join(parts)


static func _n(v: float) -> String:
	return Settings.fmt(BigNum.from_float(v))
