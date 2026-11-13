class_name ListDetail
extends VBoxContainer
## [ui6] The workbench pattern the owner picked (a reference upgrade screen): small category tabs,
## one plain list on the left (a single line per row: icon, name, tiny level pips, a price tag;
## locked rows are "? ?" with a grey LOCKED tag) and one detail panel on the right for the selected
## row (category eyebrow, bold name, one sentence, a big icon, a short table, a REQUIRES line and
## one big action button). D-pad / stick up-down walks the list, A on a row does its action.
##
## Feed it with `provider`: Callable() -> Array[Dictionary], one dict per row:
##   id, cat (category id), icon (kind), icon_set ("ui" UIIcon | "hud" HudIcons | "research"),
##   name, desc, lv, max (pips; max 0 = none), price ({cubes/parts/seeds}),
##   state: "ready" | "short" | "locked" | "done" | "busy",
##   table: [[label, value], ...], requires: "" or text, action: button text, act: Callable() -> bool,
##   custom: optional Callable(world) -> Control shown in the detail panel instead of the table.
## `categories`: [[id, name], ...] in tab order. `counter`: Callable() -> String for the corner.

signal acted(id: String)

const ROW_H: float = 48.0  # [v3clear] big readable rows (owner item 41)
const GOAL := Color(0.55, 0.9, 1.0)  # [v3clear] the row the objective card asks for
const TAG_OK := Color(1.0, 0.55, 0.18)
const SEL_BG := Color(1.0, 0.55, 0.18, 0.9)
const LOCK_GREY := Color(0.5, 0.52, 0.55)

var provider: Callable
var categories: Array = []
var counter: Callable
var world: Node
var title: String = ""
## [ui7] Float the list and the detail as separate glass modules (ui/holo_frame.gd): the category
## chips go on top of the list module, the counter on the detail module's eyebrow row.
var modules: bool = false

var _cat: String = ""
var _sel: String = ""
var _items: Array = []
var _sig: String = ""
var _cat_row: HBoxContainer
var _cat_btns: Dictionary = {}
var _counter: Label
var _list: VBoxContainer
var _rows: Dictionary = {}  # id -> Button
var _empty: Label
var _detail: VBoxContainer
var _detail_hide: Control  # [v6screens] what an empty selection hides (was _detail's third parent)
var _d_eyebrow: Label
var _d_name: Label
var _d_desc: Label
var _d_icon_box: CenterContainer
var _d_icon_key: String = ""
var _d_table: GridContainer
var _d_custom: Control
var _d_custom_id: String = ""
var _d_req: Label
var _d_btn: Button
var _d_cost: BenchKit.CostRow
var _t: float = 0.0
var _goal: String = ""  # [v3clear] id of the row the current goal needs


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	_cat_row = HBoxContainer.new()
	_cat_row.add_theme_constant_override("separation", 6)
	_cat_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_cat_row)
	_counter = HoloFrame.mono_label("", 13, Color(HoloFrame.EDGE, 0.7)) if modules else UITheme.label("", 14, UITheme.MUTED)
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # [v6screens] was clipped ("RECHERCHÉ…" at UI 1.5): it wraps
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not modules:
		add_child(top)
		top.add_child(_counter)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", HoloFrame.GAP if modules else 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	# Left: the list.
	var lp: Array = _panel()
	(lp[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(lp[0] as Control).size_flags_stretch_ratio = 1.0
	body.add_child(lp[0])
	if modules:
		(lp[1] as VBoxContainer).add_child(top)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 160 if modules else 300)
	sc.follow_focus = true
	(lp[1] as VBoxContainer).add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	sc.add_child(_list)
	_empty = BenchKit.body(tr("Nothing here yet. Keep playing."), UITheme.MUTED, BenchKit.SMALL_SIZE)
	(lp[1] as VBoxContainer).add_child(_empty)
	# Right: the detail panel.
	var dp: Array = _panel()
	(dp[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(dp[0] as Control).size_flags_stretch_ratio = 0.9
	body.add_child(dp[0])
	# [v6screens] The detail scrolls when the screen is short (interface scale 1.5 at 720p), so the
	# frame never runs off the bottom (tools/ui_audit.gd).
	_detail_hide = (dp[1] as Node).get_parent().get_parent().get_parent()
	var dsc := ScrollContainer.new()
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.follow_focus = true
	(dp[1] as VBoxContainer).add_child(dsc)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.add_child(_detail)
	_d_eyebrow = BenchKit.caps("", TAG_OK)
	if modules:
		_d_eyebrow.add_theme_font_override("font", HoloFrame.mono())
		var er := HBoxContainer.new()
		er.add_theme_constant_override("separation", 10)
		_detail.add_child(er)
		er.add_child(_d_eyebrow)
		_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		er.add_child(_counter)
	else:
		_detail.add_child(_d_eyebrow)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 12)
	_detail.add_child(nr)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nr.add_child(nv)
	_d_name = UITheme.label("", 26, Color.WHITE)
	_d_name.add_theme_constant_override("outline_size", 0)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_name.custom_minimum_size.x = 120
	nv.add_child(_d_name)
	_d_desc = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE + 1)
	nv.add_child(_d_desc)
	_d_icon_box = CenterContainer.new()
	_d_icon_box.custom_minimum_size = Vector2(56, 56) if modules else Vector2(72, 72)
	nr.add_child(_d_icon_box)
	_d_table = GridContainer.new()
	_d_table.columns = 2
	_d_table.add_theme_constant_override("h_separation", 18)
	_d_table.add_theme_constant_override("v_separation", 4)
	_detail.add_child(_d_table)
	_d_req = UITheme.label("", BenchKit.SMALL_SIZE, UITheme.MUTED)
	_d_req.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_req.custom_minimum_size.x = 120
	_detail.add_child(_d_req)
	_detail.add_child(BenchKit.spacer(0, true))
	_d_cost = BenchKit.CostRow.new(20, 18)
	_d_cost.alignment = BoxContainer.ALIGNMENT_CENTER
	_detail.add_child(_d_cost)
	_d_btn = BenchKit.big_button("")
	if modules:  # [ui7] a little more compact inside the floating frame
		_d_btn.custom_minimum_size.y = 44
		_detail.add_theme_constant_override("separation", 5)
		_d_table.add_theme_constant_override("v_separation", 2)
	_d_btn.pressed.connect(func() -> void: _do(_sel))
	_detail.add_child(_d_btn)
	refresh(true)


## A dark panel with an orange hazard edge on top: [PanelContainer, VBoxContainer body].
func _panel() -> Array:
	if modules:  # [ui7] a floating glass module, no hazard edge
		var m: PanelContainer = HoloFrame.module(12)
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 8)
		m.add_child(mv)
		return [m, mv]
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", BenchKit.holo(Color(BenchKit.HOLO, 0.25), Color(0.02, 0.035, 0.045, 0.85), 0.3, 8, 0))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	pc.add_child(outer)
	outer.add_child(_HazardEdge.new())  # drawn, not UITheme.hazard_strip's static texture (a static Resource crashed the quit)
	var mc := MarginContainer.new()
	mc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 12)
	outer.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	mc.add_child(vb)
	return [pc, vb]


func first_button() -> Button:
	var b: Button = _rows.get(_sel)
	if b:
		return b
	return _list.get_child(0) as Button if _list.get_child_count() > 0 else _d_btn


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return  # the workbench is closed: nothing to refresh
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


func _cat_items() -> Array:
	return _items.filter(func(it: Dictionary) -> bool: return str(it.get("cat", "")) == _cat)


func refresh(force: bool = false) -> void:
	_items = provider.call() if provider.is_valid() else []
	_goal = goal_row_id(world)
	# Categories: only the ones with rows (keep the current one).
	var cats_here: Array[String] = []
	for c: Array in categories:
		if _items.any(func(it: Dictionary) -> bool: return str(it.get("cat", "")) == str(c[0])):
			cats_here.append(str(c[0]))
	if _cat == "" or not (_cat in cats_here):
		_cat = cats_here[0] if not cats_here.is_empty() else ""
	var csig: String = ",".join(cats_here) + "|" + _cat
	if force or csig != str(get_meta("csig", "")):
		set_meta("csig", csig)
		_rebuild_cats(cats_here)
	_counter.text = str(counter.call()) if counter.is_valid() else ""
	var rows: Array = _cat_items()
	var ids: Array[String] = []
	for it: Dictionary in rows:
		ids.append(str(it["id"]))
	if _sel == "" or not (_sel in ids):
		_sel = ids[0] if not ids.is_empty() else ""
	var sig: String = _cat + "|" + ",".join(ids)
	if force or sig != _sig:
		_sig = sig
		_rebuild_rows(rows)
	for it: Dictionary in rows:
		_style_row(_rows.get(str(it["id"])), it)
	_empty.visible = rows.is_empty()
	_show_detail(_find(_sel))


func _find(id: String) -> Dictionary:
	for it: Dictionary in _items:
		if str(it["id"]) == id:
			return it
	return {}


func _rebuild_cats(cats_here: Array[String]) -> void:
	for c: Node in _cat_row.get_children():
		_cat_row.remove_child(c)
		c.queue_free()
	_cat_btns.clear()
	if cats_here.size() <= 1 and title == "":
		return
	for c: Array in categories:
		var cid: String = str(c[0])
		if not (cid in cats_here):
			continue
		var b := Button.new()
		b.text = tr(str(c[1])).to_upper()
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE  # LB / RB style: the list keeps the focus
		var on: bool = cid == _cat
		b.add_theme_stylebox_override("normal", BenchKit.holo(Color(TAG_OK, 0.9) if on else Color(BenchKit.HOLO, 0.15), Color(TAG_OK, 0.18) if on else Color(0, 0, 0, 0.2), 0.6 if on else 0.0, 6, 6))
		b.add_theme_stylebox_override("hover", BenchKit.holo(Color(TAG_OK, 0.6), Color(TAG_OK, 0.12), 0.4, 6, 6))
		b.add_theme_color_override("font_color", Color.WHITE if on else UITheme.MUTED)
		b.pressed.connect(func() -> void: set_category(cid))
		_cat_row.add_child(b)
		_cat_btns[cid] = b


## Switch category (also the shoulder buttons through the screen's next_category()).
func set_category(cid: String) -> void:
	if cid == _cat:
		return
	_cat = cid
	_sel = ""
	Audio.play("click", 1.15, -9.0)
	refresh(true)
	var f: Button = first_button()
	if f:
		f.grab_focus.call_deferred()


## [v1guide] Shows row `id` (its category, selected). False when it isn't listed.
func select_id(id: String) -> bool:
	var it: Dictionary = {} if _items.is_empty() else _find(id)
	if it.is_empty():  # [v9b] the rows may be old (read while a load was still building the yard): read them again
		_items = provider.call() if provider.is_valid() else []
		it = _find(id)
	if it.is_empty():
		return false
	_cat = str(it.get("cat", ""))
	_sel = id
	if is_inside_tree():
		refresh(true)
	return true


func next_category(step: int) -> bool:
	var ids: Array = _cat_btns.keys()
	if ids.size() <= 1:
		return false
	var i: int = maxi(0, ids.find(_cat))
	set_category(str(ids[wrapi(i + step, 0, ids.size())]))
	return true


func _rebuild_rows(rows: Array) -> void:
	var had_focus: bool = false
	var fo: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo and _list.is_ancestor_of(fo):
		had_focus = true
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	for it: Dictionary in rows:
		var id: String = str(it["id"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, ROW_H)
		b.focus_mode = Control.FOCUS_ALL
		b.focus_entered.connect(func() -> void: _select(id))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			# Left / right on the list flips the category (the shoulders still change tabs).
			if ev.is_action_pressed("ui_left") or ev.is_action_pressed("ui_right"):
				if next_category(1 if ev.is_action_pressed("ui_right") else -1):
					b.accept_event())
		# [v1guide] Owner (2026-11-08 #25): a click on a row only shows its details; only the price
		# tag (or the detail panel's buy button) buys. A on a pad / Enter still acts on the row.
		b.button_down.connect(func() -> void:
			b.set_meta("mouse", Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)))
		b.pressed.connect(func() -> void:
			if bool(b.get_meta("mouse", false)):
				b.set_meta("mouse", false)
				_select(id)
			elif _sel != id:
				_select(id)
			else:
				_do(id))
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 10
		hb.offset_right = -8
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var icon_box := CenterContainer.new()
		icon_box.custom_minimum_size = Vector2(24, 24)
		icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon_box)
		var nm: Label = UITheme.label("", 19, UITheme.CREAM)  # [v3clear] 17 -> 19
		nm.add_theme_constant_override("outline_size", 0)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.resized.connect(_fit_name.bind(nm))  # [v6screens] long names step the font down before they cut
		hb.add_child(nm)
		var pips := BenchKit.Pips.new(3, false, TAG_OK)
		pips.pip = 7.0
		hb.add_child(pips)
		var tag := PanelContainer.new()
		tag.custom_minimum_size = Vector2(78, 0)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_STOP  # [v1guide] the price square is the buy button
		tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tag.tooltip_text = tr("Buy")
		tag.gui_input.connect(func(ev: InputEvent) -> void:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				tag.accept_event()
				_select(id)
				_do(id))
		hb.add_child(tag)
		var tl := HBoxContainer.new()
		tl.alignment = BoxContainer.ALIGNMENT_CENTER
		tl.add_theme_constant_override("separation", 3)
		tag.add_child(tl)
		b.set_meta("parts", [icon_box, nm, pips, tag, tl])
		b.set_meta("icon_key", "")
		_list.add_child(b)
		_rows[id] = b
	# Explicit up / down links (A on a row acts; the detail button is a mouse target).
	var bl: Array = _list.get_children()
	for i: int in bl.size():
		var b: Button = bl[i]
		if i > 0:
			b.focus_neighbor_top = b.get_path_to(bl[i - 1])
		if i < bl.size() - 1:
			b.focus_neighbor_bottom = b.get_path_to(bl[i + 1])
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	_d_btn.focus_mode = Control.FOCUS_NONE  # A on a row acts; the big button is for the mouse
	if had_focus:
		var f: Button = first_button()
		if f:
			f.grab_focus.call_deferred()


static func _icon(kind: String, set_: String, px: float, col: Color) -> Control:
	match set_:
		"ui":
			return UIIcon.new(kind, px, col)
		"research":
			var g := _ResearchGlyph.new()
			g.kind = kind
			g.col = col
			g.custom_minimum_size = Vector2(px, px)
			return g
	var hg := BenchKit.Glyph.new(kind, px, col)
	return hg


## A thin orange / dark diagonal hazard edge along the top of a panel.
class _HazardEdge extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.09, 0.9))
		var x: float = -size.y
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + size.y, 0), Vector2(x + size.y + 6, 0), Vector2(x + 6, size.y)]), Color(1.0, 0.62, 0.18, 0.75))
			x += 12.0


class _ResearchGlyph extends Control:
	var kind: String = ""
	var col: Color = Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		ResearchIcons.draw(self, kind, size * 0.5, minf(size.x, size.y) * 0.42, col, 1.6)


func _style_row(b: Button, it: Dictionary) -> void:
	if b == null:
		return
	var parts: Array = b.get_meta("parts")
	var icon_box: CenterContainer = parts[0]
	var nm: Label = parts[1]
	var pips: BenchKit.Pips = parts[2]
	var tag: PanelContainer = parts[3]
	var tl: HBoxContainer = parts[4]
	var st: String = str(it.get("state", "ready"))
	var locked: bool = st == "locked"
	var on: bool = str(it["id"]) == _sel
	var ikey: String = "%s|%s|%s|%s" % [it.get("icon", ""), it.get("icon_set", "hud"), str(locked), str(on)]
	if str(b.get_meta("icon_key")) != ikey:
		b.set_meta("icon_key", ikey)
		for c: Node in icon_box.get_children():
			icon_box.remove_child(c)
			c.queue_free()
		if not locked:
			var ic: Control = _icon(str(it.get("icon", "cube")), str(it.get("icon_set", "hud")), 22.0, Color(0.08, 0.06, 0.04) if on else BenchKit.HOLO)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_box.add_child(ic)
	# [v3clear] Locked rows keep their name (the detail says what unlocks them); the goal's row is cyan;
	# rows you can't pay yet are dimmer than the ones you can.
	var goal: bool = str(it["id"]) == _goal and not locked and st != "done"
	nm.text = ("▸ " if goal else "") + str(it.get("name", ""))
	_fit_name(nm)  # [v6screens]
	nm.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04) if on else (LOCK_GREY if locked else (GOAL if goal else (UITheme.CREAM if st == "ready" else UITheme.CREAM.darkened(0.25)))))
	var mx: int = int(it.get("max", 0))
	pips.visible = mx > 0 and not locked and mx <= 10
	if pips.visible:
		pips.col = Color(0.08, 0.06, 0.04) if on else TAG_OK
		pips.set_counts(int(it.get("lv", 0)), mx)
		pips.queue_redraw()
	# Price tag: orange when you can pay, dim red when short, grey LOCKED / DONE.
	var tsig: String = "%s|%s|%s" % [st, JSON.stringify(it.get("price", {})), str(on)]
	if str(tag.get_meta("sig", "")) != tsig:
		tag.set_meta("sig", tsig)
		for c: Node in tl.get_children():
			tl.remove_child(c)
			c.queue_free()
		var bg: Color = TAG_OK
		var fg: Color = Color(0.1, 0.06, 0.02) if not on else TAG_OK.lightened(0.3)  # on the orange row the tag turns dark: light text
		match st:
			"locked":
				bg = Color(0.3, 0.31, 0.33, 0.9)
				fg = Color(0.75, 0.76, 0.78)
				tl.add_child(_tag_label(tr("LOCKED"), fg))
			"done":
				bg = Color(BenchKit.OK, 0.25)
				fg = BenchKit.OK
				tl.add_child(_tag_label(tr("DONE"), fg))
			"busy":
				bg = Color(BenchKit.HOLO, 0.25)
				fg = BenchKit.HOLO
				tl.add_child(_tag_label(str(it.get("tag", tr("ACTIVE"))), fg))
			_:
				if st == "short":
					bg = Color(0.55, 0.16, 0.1, 0.85)
					fg = Color(1.0, 0.82, 0.76)
				var price: Dictionary = Currencies.fold(it.get("price", {}))
				if str(it.get("tag", "")) != "" and price.is_empty():  # [ui7] WORN / OWNED style tags
					bg = Color(BenchKit.HOLO, 0.22)
					fg = BenchKit.HOLO
					tl.add_child(_tag_label(str(it["tag"]), fg))
					price = {"_": 1.0}
				var shown: int = 0
				for cid: String in Currencies.IDS:
					var v: float = float(price.get(cid, 0.0))
					if v <= 0.0 or shown >= 2:
						continue
					shown += 1
					var ic := CurrencyIcon.new(cid, 14.0, fg)
					tl.add_child(ic)
					tl.add_child(_tag_label(Settings.fmt(BigNum.from_float(ceilf(v))), fg))
				if shown == 0 and not price.has("_"):
					tl.add_child(_tag_label(tr("FREE"), fg))
		if on and st != "locked":
			bg = Color(0.08, 0.06, 0.04, 0.85)
		tag.add_theme_stylebox_override("panel", UITheme.box(bg, Color(0, 0, 0, 0), 0, 4, 4))
	# Row background: solid orange when selected.
	var sel_sb: StyleBoxFlat = UITheme.box(SEL_BG, Color(0, 0, 0, 0), 0, 5, 6)
	var idle: StyleBoxFlat = UITheme.box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 5, 6)
	if goal:  # [v3clear] the row the current goal needs: a cyan frame
		idle = UITheme.box(Color(GOAL, 0.12), Color(GOAL, 0.9), 2, 5, 6)
	elif st == "ready":  # [v3clear] affordable rows stand out
		idle = UITheme.box(Color(TAG_OK, 0.1), Color(TAG_OK, 0.35), 1, 5, 6)
	b.add_theme_stylebox_override("normal", sel_sb if on else idle)
	b.add_theme_stylebox_override("hover", sel_sb if on else UITheme.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 5, 6))
	b.add_theme_stylebox_override("pressed", sel_sb)
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color.WHITE, 1, 5, 6))


func _tag_label(t: String, col: Color) -> Label:
	var l: Label = UITheme.label(t, 14, col)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("shadow_outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	if modules:
		l.add_theme_font_override("font", HoloFrame.mono())
	return l


func _select(id: String) -> void:
	if id == _sel:
		return
	_sel = id
	Audio.play("click", 1.4, -14.0)
	for it: Dictionary in _cat_items():
		_style_row(_rows.get(str(it["id"])), it)
	_show_detail(_find(id))


## [v9b] A double click on a price tag acted twice: on a research row the second click hit the
## row's new action, "Cancel (refund)", so the project started and stopped at once. A second act
## on the same row this soon is the same click.
const REACT_MS: int = 450
var _did_id: String = ""
var _did_ms: int = -100000


func _do(id: String) -> void:
	var it: Dictionary = _find(id)
	if it.is_empty():
		return
	if id == _did_id and Time.get_ticks_msec() - _did_ms < REACT_MS:
		return
	_did_id = id
	_did_ms = Time.get_ticks_msec()
	var act: Variant = it.get("act")
	if str(it.get("state", "")) != "ready" or not (act is Callable) or not (act as Callable).is_valid():
		Audio.play("buzz", 1.2, -10.0)
		return
	if bool((act as Callable).call()):
		Audio.play("buy", 1.0, -3.0)
		Audio.play("confirm", 1.05, -7.0)
		acted.emit(id)
	else:
		Audio.play("buzz", 1.2, -8.0)
	refresh()
	_flash_row(id)  # [v3clear] the bought row lights up (the HUD is hidden behind the bench)


## [v3clear] A short bright pulse on a row and the detail's name: "that worked".
func _flash_row(id: String) -> void:
	var b: Control = _rows.get(id) as Control
	for c: Control in [b, _d_name]:
		if c == null or not c.is_inside_tree():
			continue
		c.modulate = Color(1.8, 1.7, 1.2)
		c.create_tween().set_ignore_time_scale(true).tween_property(c, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## [v6screens] A row name that does not fit its width steps down from 19 px to 14 px before the
## ellipsis cuts it (long names in German, French and Portuguese on a narrow screen).
const NAME_PX: int = 19
const NAME_MIN_PX: int = 14


static func _fit_name(nm: Label) -> void:
	if nm.size.x <= 1.0:
		return
	var font: Font = nm.get_theme_font("font")
	var px: int = NAME_PX
	while px > NAME_MIN_PX and font.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > nm.size.x:
		px -= 1
	if nm.get_theme_font_size("font_size") != px:
		nm.add_theme_font_size_override("font_size", px)


func _show_detail(it: Dictionary) -> void:
	_detail_hide.visible = not it.is_empty()
	if it.is_empty():
		return
	var st: String = str(it.get("state", "ready"))
	var locked: bool = st == "locked"
	var cat_name: String = ""
	for c: Array in categories:
		if str(c[0]) == str(it.get("cat", "")):
			cat_name = tr(str(c[1]))
	_d_eyebrow.text = cat_name.to_upper()
	_d_name.text = str(it.get("name", ""))  # [v3clear] locked items keep their name
	_d_desc.text = "" if locked else str(it.get("desc", ""))
	_d_desc.visible = _d_desc.text != ""
	var ikey: String = "%s|%s|%s" % [it.get("icon", ""), it.get("icon_set", "hud"), str(locked)]
	if ikey != _d_icon_key:
		_d_icon_key = ikey
		for c: Node in _d_icon_box.get_children():
			_d_icon_box.remove_child(c)
			c.queue_free()
		_d_icon_box.add_child(_icon("lock" if locked else str(it.get("icon", "cube")), "hud" if locked else str(it.get("icon_set", "hud")), 64.0, LOCK_GREY if locked else BenchKit.HOLO))
	# A custom detail body (e.g. the launch pad) replaces the table.
	var cf: Variant = it.get("custom")
	var cid: String = str(it["id"]) if cf is Callable else ""
	if cid != _d_custom_id:
		_d_custom_id = cid
		if _d_custom and is_instance_valid(_d_custom):
			_detail.remove_child(_d_custom)
			_d_custom.queue_free()
		_d_custom = null
		if cf is Callable:
			_d_custom = (cf as Callable).call(world) as Control
			if _d_custom:
				_detail.add_child(_d_custom)
				_detail.move_child(_d_custom, _d_table.get_index() + 1)
	var tsig: String = JSON.stringify(it.get("table", []))
	if str(_d_table.get_meta("sig", "")) != tsig:
		_d_table.set_meta("sig", tsig)
		for c: Node in _d_table.get_children():
			_d_table.remove_child(c)
			c.queue_free()
		for row: Variant in it.get("table", []):
			if not (row is Array) or (row as Array).size() < 2:
				continue
			var k: Label = UITheme.label(str(row[0]).to_upper(), 13, UITheme.MUTED)
			k.add_theme_constant_override("outline_size", 0)
			if modules:
				k.add_theme_font_override("font", HoloFrame.mono())
			_d_table.add_child(k)
			var v: Label = UITheme.label(str(row[1]), 17, Color.WHITE)
			v.add_theme_constant_override("outline_size", 0)
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.custom_minimum_size.x = 120
			_d_table.add_child(v)
	_d_table.visible = _d_table.get_child_count() > 0 and not locked
	var req: String = str(it.get("requires", ""))
	if locked:
		_d_req.text = (tr("LOCKED.  To unlock: %s") % req) if req != "" else tr("Locked. Keep playing to unlock it.")  # [v3clear]
		_d_req.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))
	elif req != "":
		_d_req.text = tr("REQUIRES   %s") % req
		_d_req.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45) if st == "short" else UITheme.MUTED)
	else:
		_d_req.text = tr("You can buy this now!") if st == "ready" else (short_text(it.get("price", {})) if st == "short" else "")  # [v3clear]
		_d_req.add_theme_color_override("font_color", BenchKit.OK if st == "ready" else Color(1.0, 0.6, 0.45))
	_d_req.visible = _d_req.text != ""
	var action: String = str(it.get("action", ""))
	_d_btn.visible = action != "" and not locked
	_d_btn.text = action
	_d_btn.disabled = st != "ready"
	_d_cost.visible = _d_btn.visible and st in ["ready", "short"]
	if _d_cost.visible:
		_d_cost.set_cost(it.get("price", {}), " ")


## [v3clear] "Need 40 more cubes. Pick up trash to earn them." for a price you can't pay yet.
static func short_text(price: Dictionary) -> String:
	var miss: PackedStringArray = []
	var how: String = ""
	for cid: String in Currencies.IDS:
		var need: float = float(Currencies.fold(price).get(cid, 0.0))
		var have: float = GameState.get_currency(cid).to_float()
		if need > have + 0.001:
			miss.append(TranslationServer.translate("%s more %s") % [Settings.fmt(BigNum.from_float(ceilf(need - have))), Currencies.display_name(cid).to_lower()])
			if how == "":
				how = TranslationServer.translate("Pick up trash to earn them.") if cid == "cubes" else TranslationServer.translate("Dig up parts and salvage junk to get them.")
	if miss.is_empty():
		return ""
	return TranslationServer.translate("Need %s. %s") % [", ".join(miss), how]  # [v5text] no English "and"


## [v3clear] The id of the workbench row the objective card's current step asks for ("" for none).
static func goal_row_id(w: Node) -> String:
	var ob: Variant = w.get("objectives") if w else null
	if not ob is Objectives:
		return ""
	var r: Array = (ob as Objectives).bench_row()
	return str(r[1]) if r.size() >= 2 else ""
