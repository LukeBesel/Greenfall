class_name WorldPicker
extends Control
## [worlds2] Title screen "Worlds" list (ui/main_menu.gd): every Cradle Mode world with its type
## icon (ArkBridge.PlanetDisc), name, type and modifiers and how far it got. Picking one makes it
## the current world (CradleMode.select_world) and continues there. Gamepad and keyboard: up/down
## move, accept picks, cancel goes back. All text through tr().

signal picked(index: int)
signal closed

var rows: Array[Button] = []
var back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(620, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.95), UITheme.GOLD, 1, 6, 22))
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	vb.add_child(UITheme.label(tr("PLANETS"), 26, UITheme.GOLD))
	var sub := UITheme.label(tr("Every planet keeps its own save. Pick one to continue there."), 14, UITheme.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for i: int in CradleMode.worlds().size():
		var b: Button = _row(i)
		list.add_child(b)
		rows.append(b)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(foot)
	back = Button.new()
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(150, 42)
	back.pressed.connect(close_picker)
	UITheme.juice(back)
	foot.add_child(back)
	_chain()


## One world as a big focusable row.
func _row(i: int) -> Button:
	var w: Dictionary = CradleMode.worlds()[i]
	var here: bool = i == CradleMode.current_index()
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal: StyleBoxFlat = UITheme.box(Color(0.05, 0.055, 0.06, 0.8), UITheme.GOLD if here else Color(1, 1, 1, 0.08), 1, 4, 10)
	var hover: StyleBoxFlat = UITheme.box(Color(0.1, 0.09, 0.07, 0.9), UITheme.GOLD, 1, 4, 10)
	hover.border_width_left = 4
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	hb.add_child(ArkBridge.PlanetDisc.new(str(w.get("type", "verdance")), int(w.get("seed", 0)), 26.0))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var title: String = "%s   %s" % [tr("PLANET %d") % (i + 1), str(w.get("name", "?")).to_upper()]
	var tl := UITheme.label(title, 17, Color.WHITE)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tl)
	var wd := UITheme.label(WorldGen.describe(w), 12, Color(0.4, 0.75, 1.0))
	wd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(wd)
	var sl := UITheme.label(status_line(w, i), 12, UITheme.MUTED)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sl)
	if here:
		var cur := UITheme.label(tr("Current"), 12, UITheme.GOLD)
		cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cur.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(cur)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -4.0)
		picked.emit(i))
	b.focus_entered.connect(func() -> void: Audio.play("blip", 1.6, -18.0, 0.0))
	return b


## "1:20 h · 140 hexes · restored" / "Not visited yet" (pure given the record).
static func status_line(w: Dictionary, i: int) -> String:
	var st: Dictionary = w.get("stats", {})
	if st.is_empty():
		return TranslationServer.translate("Home world") if i == 0 else TranslationServer.translate("Not visited yet")
	var parts: Array[String] = [ArkBridge._hours(float(st.get("time_played", 0.0))),
		TranslationServer.translate("%d hexes") % int(st.get("hexes_cleaned", 0))]
	if bool(w.get("finale", false)):
		parts.append(TranslationServer.translate("restored"))
	return "  ·  ".join(parts)


## Dev (shots): n visited worlds in the in-memory profile, the first two restored.
static func dev_sample(n: int) -> void:
	while CradleMode.worlds().size() < n + 1:
		var i: int = CradleMode.worlds().size()
		var w: Dictionary = CradleMode._add_world()
		w["stats"] = {"time_played": 3600.0 * maxf(0.4, 6.5 - i * 1.4), "hexes_cleaned": maxi(20, 420 - i * 80), "ark_waves": maxi(0, 4 - i), "eggs": maxi(0, 30 - i * 6)}
		w["finale"] = i <= 2
	(CradleMode.worlds()[0] as Dictionary)["stats"] = {"time_played": 9.5 * 3600.0, "hexes_cleaned": 610, "ark_waves": 5}
	(CradleMode.worlds()[0] as Dictionary)["finale"] = true
	CradleMode.profile["current"] = mini(2, CradleMode.worlds().size() - 1)
	CradleMode.profile["unlocked"] = true
	CradleMode.profile["name"] = "Mira"
	# [worlds2] The other save profiles in the shot: one short game, one empty slot.
	ProfileSlots.dev_summaries[2] = {"empty": false, "name": "Weekend run", "time_s": 2.4 * 3600.0, "worlds": 1, "world": "Verdance",
		"district": "Old Town", "bloom_pct": 25, "saved_unix": 0.0}
	ProfileSlots.dev_summaries[3] = {"empty": true, "name": TranslationServer.translate("Profile %d") % 3}


func _chain() -> void:
	var all: Array[Button] = rows.duplicate()
	all.append(back)
	for k: int in all.size():
		var b: Button = all[k]
		b.focus_neighbor_top = b.get_path_to(all[wrapi(k - 1, 0, all.size())])
		b.focus_neighbor_bottom = b.get_path_to(all[wrapi(k + 1, 0, all.size())])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


func open_picker() -> void:
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	var cur: int = clampi(CradleMode.current_index(), 0, rows.size() - 1)
	if not rows.is_empty():
		rows[cur].call_deferred("grab_focus")


func close_picker() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_picker()
		get_viewport().set_input_as_handled()
