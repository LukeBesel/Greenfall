class_name GlimPanel
extends CanvasLayer
## [buddy] Glim's panel (hold glim_scan): his four upgrade tracks on the left (cubes / parts /
## seeds), his looks on the right (GlimLooksEditor, also hosted by the Locker when
## CosmeticTargets exists). Pauses the game while open; Esc / B / glim_scan closes.

var world: Node
var director: GlimDirector
var is_open: bool = false
var _root: Control
var _tracks: VBoxContainer
var _looks: GlimLooksEditor
var _money: Label
var _first: Control


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(860, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.06, 0.07, 0.9), Color(0.45, 0.9, 1.0, 0.22), 1, 12, 20))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title: Label = UITheme.label(tr("GLIM"), 26, Color(0.62, 0.95, 1.0))
	head.add_child(title)
	var sub: Label = UITheme.label("  " + tr("lantern bot"), 14, UITheme.MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	_money = UITheme.label("", 16, UITheme.CREAM)
	head.add_child(_money)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	vb.add_child(body)
	_tracks = VBoxContainer.new()
	_tracks.add_theme_constant_override("separation", 8)
	_tracks.custom_minimum_size = Vector2(470, 0)
	# [v6screens] The upgrade list scrolls on a short screen (UI scale 1.25 / 1.5) instead of
	# running off the bottom (tools/ui_audit.gd).
	_track_scroll = ScrollContainer.new()
	_track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_track_scroll.follow_focus = true
	_track_scroll.add_child(_tracks)
	body.add_child(_track_scroll)
	_panel_box = pc
	_root.resized.connect(_fit)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.07)
	sep.custom_minimum_size = Vector2(1, 0)
	body.add_child(sep)
	_looks = GlimLooksEditor.new()
	_looks.director = director
	_looks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_looks.visible = false  # [ui7] all cosmetics live at the Locker (yard build); it hosts GlimLooksEditor
	body.add_child(_looks)
	var to_locker: Label = UITheme.label(tr("Change Glim's looks at the Locker in the yard."), 15, UITheme.MUTED)
	to_locker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_locker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(to_locker)
	var hint: Label = UITheme.label("", 13, UITheme.MUTED)
	Settings.bind_text(hint, func() -> String: return tr("%s  close") % Settings.glyph("pause"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(hint)
	_root.visible = false


var _track_scroll: ScrollContainer
var _panel_box: PanelContainer


func _fit() -> void:  # [v6screens]
	var vs: Vector2 = _root.size
	if vs.y <= 0.0:
		return
	_panel_box.custom_minimum_size.x = minf(860.0, vs.x - 24.0)
	var want: float = _tracks.get_combined_minimum_size().y
	_track_scroll.custom_minimum_size = Vector2(_tracks.custom_minimum_size.x, minf(want, maxf(160.0, vs.y - 190.0)))


func open_panel() -> void:
	if is_open:
		return
	is_open = true
	_looks.director = director
	_rebuild()
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("click", 1.2, -6.0)


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


func _rebuild() -> void:
	for c: Node in _tracks.get_children():
		_tracks.remove_child(c)
		c.queue_free()
	_first = null
	var bits: Array[String] = []
	for cur: String in Currencies.IDS:
		bits.append(Currencies.amount_text(cur, GameState.get_currency(cur).to_float()))
	_money.text = "   ".join(bits)
	_tracks.add_child(UITheme.label(tr("UPGRADES"), 15, UITheme.MUTED))
	for t: Variant in Glim.tracks():
		_tracks.add_child(_track_row(t as Dictionary))
	_looks.rebuild()
	if _first == null:  # [v6screens] nothing affordable yet: a pad still starts on the first row (it says what it needs)
		for c: Node in _tracks.find_children("*", "Button", true, false):
			_first = c as Button
			break
	if _first:
		_first.call_deferred("grab_focus")
	_fit.call_deferred()


func _track_row(t: Dictionary) -> Control:
	var id: String = str(t["id"])
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.06), 1, 8, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hb.add_child(info)
	var top := HBoxContainer.new()
	info.add_child(top)
	top.add_child(UITheme.label(tr(str(t.get("name", id))), 18, Color.WHITE))
	var pips := Label.new()
	var tier: int = Glim.tier(id)
	var mx: int = Glim.max_tier(id)
	pips.text = "   " + "●".repeat(tier) + "○".repeat(maxi(0, mx - tier))
	pips.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	pips.add_theme_font_size_override("font_size", 14)
	top.add_child(pips)
	var desc: Label = UITheme.label(tr(str(t.get("desc", ""))), 13, UITheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(280, 0)
	info.add_child(desc)
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 44)
	var why: String = Glim.block_reason(id)
	if why == "Maxed":
		b.text = tr("Maxed")
		b.disabled = true
	elif why != "":
		var req: Dictionary = t.get("requires", {})
		var need: String = ""
		for k: String in req:
			if Glim.tier(k) < int(req[k]):
				need = tr("Needs %s %d") % [tr(str(Glim.track(k).get("name", k))), int(req[k])]
				break
		b.text = need if need != "" else TranslationServer.translate(why)
		b.disabled = true
	else:
		var cost: Dictionary = Glim.next_cost(id)
		b.text = Currencies.cost_text(cost)
		var ok: bool = GameState.can_afford_all(cost)
		b.disabled = not ok
		b.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.55)
		b.pressed.connect(func() -> void:
			if Glim.buy(id):
				Audio.play("upgrade", 1.1, -4.0)
				if director:
					director.refresh()
				_rebuild())
		if ok and _first == null:
			_first = b
	hb.add_child(b)
	return pc


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("glim_scan"):
		close_panel()
		get_viewport().set_input_as_handled()


## [buddy] Glim's looks (shell colour, glow colour, top). Locked looks show only "???" and how to
## unlock them; cost unlocks are bought here. A standalone Control: the Glim panel embeds it and
## the Locker can host it through CosmeticTargets.
class GlimLooksEditor extends VBoxContainer:
	const SLOT_NAMES: Dictionary = {"shells": "Shell", "glows": "Glow", "tops": "Top"}
	var director: GlimDirector

	func _ready() -> void:
		add_theme_constant_override("separation", 10)
		if get_child_count() == 0:
			rebuild()

	func rebuild() -> void:
		for c: Node in get_children():
			remove_child(c)
			c.queue_free()
		add_child(UITheme.label(TranslationServer.translate("LOOKS"), 15, UITheme.MUTED))
		for slot: String in Glim.SLOTS:
			add_child(UITheme.label(TranslationServer.translate(str(SLOT_NAMES[slot])), 14, UITheme.CREAM))
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			row.add_theme_constant_override("v_separation", 6)
			add_child(row)
			for l: Variant in Glim.looks(slot):
				row.add_child(_swatch(slot, l as Dictionary))

	func _swatch(slot: String, l: Dictionary) -> Button:
		var id: String = str(l["id"])
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		var open: bool = Glim.look_unlocked(slot, id)
		var worn: bool = Glim.worn(slot) == id
		var u: Dictionary = l.get("unlock", {})
		var hint: Array = Glim.unlock_hint(slot, id)
		var hint_text: String = ""
		if str(hint[0]) != "":
			hint_text = TranslationServer.translate(str(hint[0])) % [hint[1]]
		if open:
			b.text = TranslationServer.translate(str(l.get("name", id)))
			b.tooltip_text = b.text
		elif u.has("cost"):
			b.text = TranslationServer.translate("???  %s") % Currencies.cost_text(u["cost"])
			b.tooltip_text = hint_text
			b.disabled = not GameState.can_afford_all(u["cost"])
		else:
			b.text = "???"
			b.tooltip_text = hint_text
			b.disabled = true
		var col: Color = Color.html(str(l.get("color", "#2a3036"))) if open and l.has("color") else Color(0.16, 0.18, 0.2)
		var border: Color = Color(0.5, 0.95, 1.0) if worn else Color(1, 1, 1, 0.12)
		b.add_theme_stylebox_override("normal", UITheme.box(col.darkened(0.25) if open else col, border, 2 if worn else 1, 6, 10))
		b.add_theme_stylebox_override("hover", UITheme.box(col.darkened(0.1) if open else col.lightened(0.1), Color(0.6, 0.95, 1.0), 1, 6, 10))
		b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color(0.6, 0.95, 1.0), 2, 6, 10))
		b.add_theme_color_override("font_color", Color.WHITE if open else UITheme.MUTED)
		b.pressed.connect(func() -> void:
			if not Glim.look_unlocked(slot, id) and not Glim.buy_look(slot, id):
				return
			Glim.wear(slot, id)
			Audio.play("click", 1.3, -6.0)
			if director:
				director.refresh()
			rebuild())
		return b
