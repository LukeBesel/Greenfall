class_name CodexScreen
extends CanvasLayer
## Codex (K / pause menu): three tabs.
##   Codex        entries for junk, plants, robots, memory shards and landmarks you have found
##   Achievements every achievement with progress
##   Stats        lifetime stats
## Slate glass panel, amber accent; tabs switch with Q/E or the shoulder buttons; tweens in/out.

signal closed

const TABS: Array[Dictionary] = [
	{"id": "codex", "name": "Codex"},
	{"id": "achievements", "name": "Achievements"},
	{"id": "stats", "name": "Stats"},
]
const CAT_COLORS: Dictionary = {
	"junk": Color(1.0, 0.7, 0.26), "plants": Color(0.56, 0.86, 0.54), "robots": Color(0.4, 0.72, 1.0),
	"shards": Color(0.5, 0.85, 1.0), "landmarks": Color(0.83, 0.61, 1.0),
}

var is_open: bool = false
var _root: Control
var _panel: PanelContainer
var _body: Control
var _tab: String = "codex"
var _tab_buttons: Dictionary = {}
var _summary: Label
var _tween: Tween
# Codex tab detail pane.
var _d_icon: ResearchIcons.IconView
var _d_cat: Label
var _d_name: Label
var _d_desc: Label


func _ready() -> void:
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 40)
	_root.add_child(mc)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.075, 0.94), Color(1, 1, 1, 0.1), 1, 14, 20))
	mc.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vb.add_child(header)
	header.add_child(ResearchIcons.IconView.new("book", 40, UITheme.GOLD))
	header.add_child(UITheme.label("CODEX", 32, UITheme.GOLD))
	_summary = UITheme.label("", 14, UITheme.MUTED)
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_summary)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	var close := Button.new()
	close.text = "Close  [K]"
	close.custom_minimum_size = Vector2(140, 44)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_screen)
	header.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for t: Dictionary in TABS:
		var b := Button.new()
		b.text = str(t["name"])
		b.custom_minimum_size = Vector2(150, 42)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_tab.bind(str(t["id"])))
		tabs.add_child(b)
		_tab_buttons[str(t["id"])] = b
	tabs.add_child(UITheme.label("   Q / E  switch tabs", 12, UITheme.MUTED))
	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_body)
	_root.visible = false


func open_screen(tab: String = "") -> void:
	if tab != "":
		_tab = tab
	is_open = true
	Codex.scan(null)
	_root.visible = true
	_build_tab()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("whoosh", 1.5, -14.0)
	if _tween:
		_tween.kill()
	_root.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.97, 0.97)
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.22)


func close_screen() -> void:
	if not is_open:
		return
	is_open = false
	EventBus.ui_modal_changed.emit(false)
	Audio.play("click", 0.8, -8.0)
	if _tween:
		_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_root, "modulate:a", 0.0, 0.14)
	_tween.tween_property(_panel, "scale", Vector2(0.97, 0.97), 0.14)
	_tween.chain().tween_callback(func() -> void:
		if not is_open:
			_root.visible = false)
	closed.emit()


func _set_tab(id: String) -> void:
	if id == _tab:
		return
	_tab = id
	Audio.play("click", 1.1, -8.0)
	_build_tab()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		var i: int = 0
		for k: int in TABS.size():
			if TABS[k]["id"] == _tab:
				i = k
		var step: int = 1 if event.is_action_pressed("ui_tab_next") else TABS.size() - 1
		_set_tab(str(TABS[(i + step) % TABS.size()]["id"]))
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("open_codex") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()


func _build_tab() -> void:
	for c: Node in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	for id: String in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var on: bool = id == _tab
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.2, 0.15, 0.07, 0.9) if on else UITheme.TEAL, UITheme.GOLD if on else UITheme.RUST, 1, 6, 8))
		b.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.CREAM)
	_summary.text = "%d / %d entries   ·   %d / %d achievements" % [Codex.count(), Codex.total(), Achievements.unlocked_count(), Achievements.defs().size()]
	var first: Control = null
	match _tab:
		"codex":
			first = _build_codex()
		"achievements":
			first = _build_achievements()
		"stats":
			first = _build_stats()
	if first:
		first.call_deferred("grab_focus")


func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	return sc


static func _glass(radius: int = 12, pad: int = 12) -> StyleBoxFlat:
	return UITheme.box(Color(0.04, 0.045, 0.055, 0.85), Color(1, 1, 1, 0.07), 1, radius, pad)


# --- Codex tab -----------------------------------------------------------------------

func _build_codex() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	_body.add_child(hb)
	var sc := _scroll()
	sc.size_flags_stretch_ratio = 1.6
	hb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	var first: Control = null
	for cat: Dictionary in Codex.categories():
		var cid: String = str(cat["id"])
		var col: Color = CAT_COLORS.get(cid, UITheme.GOLD)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		list.add_child(head)
		head.add_child(ResearchIcons.IconView.new(str(cat.get("icon", "book")), 26, col))
		head.add_child(UITheme.label(str(cat["name"]).to_upper(), 15, col))
		head.add_child(UITheme.label("%d / %d" % [Codex.count(cid), Codex.total(cid)], 13, UITheme.MUTED))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		list.add_child(flow)
		for e: Dictionary in Codex.entries():
			if e["cat"] != cid:
				continue
			var b := _entry_button(e, col)
			flow.add_child(b)
			if first == null:
				first = b
	# Detail pane.
	var det := PanelContainer.new()
	det.add_theme_stylebox_override("panel", _glass(14, 20))
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(det)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	det.add_child(dv)
	_d_icon = ResearchIcons.IconView.new("book", 72, UITheme.GOLD)
	dv.add_child(_d_icon)
	_d_cat = UITheme.label("", 12, UITheme.MUTED)
	dv.add_child(_d_cat)
	_d_name = UITheme.label("", 24, Color.WHITE)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	dv.add_child(_d_name)
	_d_desc = UITheme.label("", 16, UITheme.CREAM)
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_d_desc.custom_minimum_size = Vector2(280, 0)
	dv.add_child(_d_desc)
	if not Codex.entries().is_empty():
		_show_entry(Codex.entries()[0])
	return first


func _entry_button(e: Dictionary, col: Color) -> Button:
	var got: bool = Codex.is_unlocked(str(e["key"]))
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 40)
	b.text = str(e["name"]) if got else "? ? ?"
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_stylebox_override("normal", UITheme.box(Color(col.r * 0.15 + 0.05, col.g * 0.15 + 0.05, col.b * 0.15 + 0.05, 0.9) if got else Color(0.06, 0.065, 0.07, 0.8), Color(col, 0.45) if got else Color(1, 1, 1, 0.06), 1, 8, 8))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(0.12, 0.12, 0.12, 0.95), UITheme.GOLD, 1, 8, 8))
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 2, 8, 8))
	b.add_theme_color_override("font_color", UITheme.CREAM if got else UITheme.MUTED)
	UITheme.juice(b, 1.04)
	b.focus_entered.connect(_show_entry.bind(e))
	b.mouse_entered.connect(_show_entry.bind(e))
	b.pressed.connect(func() -> void:
		_show_entry(e)
		Audio.play("click", 1.3, -10.0))
	return b


func _show_entry(e: Dictionary) -> void:
	var got: bool = Codex.is_unlocked(str(e["key"]))
	var col: Color = CAT_COLORS.get(str(e["cat"]), UITheme.GOLD)
	var icon: String = "book"
	for cat: Dictionary in Codex.categories():
		if cat["id"] == e["cat"]:
			icon = str(cat.get("icon", "book"))
	_d_icon.kind = icon if got else "lock"
	_d_icon.color = col if got else UITheme.MUTED
	_d_icon.queue_redraw()
	var cat_name: String = str(e["cat"]).to_upper()
	for cat: Dictionary in Codex.categories():
		if cat["id"] == e["cat"]:
			cat_name = str(cat["name"]).to_upper()
	_d_cat.text = cat_name
	_d_cat.add_theme_color_override("font_color", col)
	_d_name.text = str(e["name"]) if got else "Not found yet"
	if got:
		var extra: String = ""
		if e["cat"] == "junk":
			extra = "\n\nCleared so far: %s" % _kg(Codex.junk_kg(str(e["id"])))
		_d_desc.text = str(e["desc"]) + extra
	else:
		_d_desc.text = "Hint: " + str(e["hint"])
	_d_desc.add_theme_color_override("font_color", UITheme.CREAM if got else UITheme.MUTED)


# --- Achievements tab ----------------------------------------------------------------

func _build_achievements() -> Control:
	var sc := _scroll()
	_body.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	var first: Control = null
	# Unlocked first (newest at the top), then the rest by progress.
	var list: Array = Achievements.defs().duplicate()
	var um: Dictionary = Achievements.unlocked_map()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ua: bool = um.has(a["id"])
		var ub: bool = um.has(b["id"])
		if ua != ub:
			return ua
		if ua:
			return float(um[a["id"]]) > float(um[b["id"]])
		return Achievements.progress(str(a["id"])) > Achievements.progress(str(b["id"])))
	for a: Dictionary in list:
		var card := _achievement_card(a)
		grid.add_child(card)
		if first == null:
			first = card
	return first


func _achievement_card(a: Dictionary) -> Button:
	var id: String = str(a["id"])
	var got: bool = Achievements.is_unlocked(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", UITheme.box(Color(0.13, 0.1, 0.05, 0.9) if got else Color(0.05, 0.055, 0.065, 0.85), Color(UITheme.GOLD, 0.5) if got else Color(1, 1, 1, 0.06), 1, 12, 10))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(0.12, 0.11, 0.1, 0.95), UITheme.GOLD, 1, 12, 10))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(0.12, 0.11, 0.1, 0.95), UITheme.GOLD, 1, 12, 10))
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 2, 12, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -12
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var ic := ResearchIcons.IconView.new(str(a.get("icon", "star")), 50, UITheme.GOLD if got else Color(0.5, 0.52, 0.53))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var n := UITheme.label(str(a["name"]), 16, Color.WHITE if got else UITheme.CREAM)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(n)
	var d := UITheme.label(str(a.get("desc", "")), 12, UITheme.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(d)
	if got:
		var when: String = Time.get_date_string_from_unix_time(int(float(Achievements.unlocked_map()[id])))
		var l := UITheme.label("Unlocked  ·  %s" % when, 11, UITheme.GOLD)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l)
	else:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(row)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = Achievements.progress(id)
		bar.custom_minimum_size = Vector2(0, 6)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var c: Dictionary = a.get("cond", {})
		var pl := UITheme.label("  %s / %s" % [_short(Achievements.value_of(c)), _short(float(c.get("target", 1)))], 11, UITheme.MUTED)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pl)
	UITheme.juice(b, 1.02)
	return b


# --- Stats tab -----------------------------------------------------------------------

func _build_stats() -> Control:
	var sc := _scroll()
	_body.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(grid)
	var st: Dictionary = GameState.stats
	var junk_rows: Array = []
	for t: String in Economy.junk_ids:
		junk_rows.append([Color.html(str(Economy.junk_types[t].get("cube_color", "#888888"))).lightened(0.25), str(Economy.junk_types[t].get("name", t)), _kg(Codex.junk_kg(t))])
	junk_rows.append([UITheme.GOLD, "Total", _kg(Codex.junk_kg("*"))])
	var first: Control = _stat_card(grid, "Junk removed", "by type", junk_rows)
	_stat_card(grid, "Cleaning", "", [
		[UITheme.GOLD, "Hexes cleaned", _int(st.get("hexes_cleaned", 0))],
		[UITheme.GREEN, "Hexes restored", _int(st.get("hexes_restored", 0))],
		[UITheme.CREAM, "Bales pressed", _int(st.get("cubes_made", 0))],
		[Color(0.6, 0.86, 1.0), "Pure bales", _int(st.get("pure_cubes", 0))],
		[UITheme.GOLD, "Perfect bales", _int(st.get("perfect_cubes", 0))],
		[UITheme.MUTED, "Lumpy bales", _int(st.get("lumpy_cubes", 0))],
		[UITheme.GOLD, "Bales cashed in", _int(st.get("cubes_cashed", 0))],
		[UITheme.GOLD, "Cubes earned", Settings.fmt(BigNum.from_serialized(st.get("cubes_earned_total", [0.0, 0])))],
	])
	_stat_card(grid, "Growing", "", [
		[UITheme.GREEN, "Seeds planted", _int(st.get("plants_planted", 0))],
		[Color(1.0, 0.85, 0.4), "Plants bloomed", _int(st.get("plants_bloomed", 0))],
		[Color(0.6, 0.8, 1.0), "Air filtered", _int(st.get("air_filtered", 0))],
	])
	_stat_card(grid, "Robots", "", [
		[Color(0.4, 0.72, 1.0), "Robots built", _int(st.get("robots_built", 0))],
		[UITheme.CREAM, "Bales by robots", _int(st.get("robot_bales", 0))],
		[UITheme.GOLD, "Parts dug up", _int(st.get("parts_found", 0))],
	])
	_stat_card(grid, "Exploring", "", [
		[UITheme.CREAM, "Distance rolled", _dist(float(st.get("distance_m", 0.0)))],
		[Color(0.5, 0.85, 1.0), "Memory shards read", _int(st.get("shards_found", 0))],
		[Color(0.83, 0.61, 1.0), "Codex entries", "%d / %d" % [Codex.count(), Codex.total()]],
		[UITheme.MUTED, "Time played", _time(float(st.get("time_played", 0.0)))],
	])
	_stat_card(grid, "Progress", "", [
		[UITheme.GOLD, "Upgrades bought", _int(st.get("upgrades_bought", 0))],
		[Color(0.45, 0.8, 1.0), "Data earned", _int(st.get("data_earned", 0))],
		[Color(0.45, 0.8, 1.0), "Research done", "%d / %d" % [Research.done_list().size(), Research.ids().size()]],
		[UITheme.GOLD, "Achievements", "%d / %d" % [Achievements.unlocked_count(), Achievements.defs().size()]],
		[UITheme.CREAM, "Best hub level", str(Achievements.best_hub_level())],
	])
	return first


## A stats card; focusable so a controller can scroll through them.
func _stat_card(parent: Control, title: String, subtitle: String, rows: Array) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _glass(12, 14))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.focus_mode = Control.FOCUS_ALL
	parent.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var th := HBoxContainer.new()
	vb.add_child(th)
	th.add_child(UITheme.label(title.to_upper(), 15, UITheme.GOLD))
	if subtitle != "":
		th.add_child(UITheme.label("  " + subtitle, 12, UITheme.MUTED))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.07)
	line.custom_minimum_size = Vector2(0, 1)
	vb.add_child(line)
	for r: Array in rows:
		vb.add_child(UITheme.stat_row(r[0], str(r[1]), str(r[2])))
	pc.focus_entered.connect(func() -> void: pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.055, 0.85), UITheme.GOLD, 1, 12, 14)))
	pc.focus_exited.connect(func() -> void: pc.add_theme_stylebox_override("panel", _glass(12, 14)))
	return pc


# --- Formatting ----------------------------------------------------------------------

static func _int(v: Variant) -> String:
	return _group(int(round(float(v))))


static func _group(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _kg(kg: float) -> String:
	if kg >= 10000.0:
		return "%.1f t" % (kg / 1000.0)
	if kg >= 100.0:
		return "%s kg" % _group(int(round(kg)))
	return "%.1f kg" % kg


static func _dist(m: float) -> String:
	return "%.2f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % int(m)


static func _time(s: float) -> String:
	var n: int = int(s)
	if n >= 3600:
		return "%dh %02dm" % [n / 3600, (n % 3600) / 60]
	if n >= 60:
		return "%dm %02ds" % [n / 60, n % 60]
	return "%ds" % n


static func _short(v: float) -> String:
	if v >= 1.0e6:
		return "%.1fM" % (v / 1.0e6)
	if v >= 10000.0:
		return "%.1fK" % (v / 1000.0)
	if is_equal_approx(v, round(v)) or v >= 100.0:
		return _group(int(round(v)))
	return "%.1f" % v
