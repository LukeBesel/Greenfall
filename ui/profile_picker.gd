class_name ProfilePicker
extends Control
## [worlds2] Title screen save profiles (ui/main_menu.gd > Profiles): three slots, each with its
## name, play time, worlds, current world and district, and Bloom %. Per slot: Continue (then the
## world list, ui/world_picker.gd, when the profile has more than one world), New (confirm when it
## would erase), Rename and Delete (confirm). Pad friendly: a focus grid over the slot buttons;
## cancel backs out of a dialog, then the picker. All text through tr().

signal go          ## a profile/world is chosen: the title screen loads the game
signal closed(changed: bool)

var _list: VBoxContainer
var _grid: Array = []          # rows of Buttons (one row per slot), then [back]
var _back: Button
var _dialog: Control           # confirm / rename overlay (one at a time)
var _worlds: WorldPicker
var _changed: bool = false
var _focus_after: Vector2i = Vector2i(-1, 0)


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
	pc.custom_minimum_size = Vector2(700, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.95), UITheme.GOLD, 1, 6, 22))
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	vb.add_child(UITheme.label(tr("SAVE PROFILES"), 26, UITheme.GOLD))
	var sub := UITheme.label(tr("Each profile has its own planets and progress. Settings are shared."), 14, UITheme.MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	vb.add_child(_list)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(foot)
	_back = Button.new()
	_back.text = tr("Back")
	_back.custom_minimum_size = Vector2(150, 42)
	_back.pressed.connect(close_picker)
	UITheme.juice(_back)
	foot.add_child(_back)
	_rebuild()


func open_picker() -> void:
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)
	_focus(Vector2i(SaveManager.profile_slot - 1, 0))


func close_picker() -> void:
	visible = false
	closed.emit(_changed)


# --- Cards ---------------------------------------------------------------------------------

func _rebuild() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	_grid = []
	for n: int in range(1, SaveManager.PROFILES + 1):
		_list.add_child(_card(n))
	_grid.append([_back])
	_chain()


func _card(n: int) -> Control:
	var s: Dictionary = ProfileSlots.summary(n)
	var active: bool = n == SaveManager.profile_slot
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.06, 0.85), UITheme.GOLD if active else Color(1, 1, 1, 0.08), 1, 4, 12))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	var badge := UITheme.label("%d" % n, 30, UITheme.GOLD if active else UITheme.MUTED)
	badge.custom_minimum_size = Vector2(34, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(badge)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var title := UITheme.label(str(s["name"]).to_upper() + ("   " + tr("ACTIVE") if active else ""), 18, Color.WHITE)
	vb.add_child(title)
	var line := summary_text(s)
	var l1 := UITheme.label(line[0], 13, Color(0.4, 0.75, 1.0) if not s["empty"] else UITheme.MUTED)
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l1)
	if line[1] != "":
		vb.add_child(UITheme.label(line[1], 12, UITheme.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var btns: Array = []
	if not s["empty"]:
		btns.append(_btn(row, tr("Continue"), _continue.bind(n), true))
	btns.append(_btn(row, tr("New"), _new.bind(n, bool(s["empty"]))))
	btns.append(_btn(row, tr("Rename"), _rename.bind(n)))
	if not s["empty"]:
		btns.append(_btn(row, tr("Delete"), _delete.bind(n)))
	_grid.append(btns)
	return pc


## Two summary lines for a slot (pure): play time, worlds, current world; district and Bloom %.
static func summary_text(s: Dictionary) -> Array[String]:
	if bool(s.get("empty", true)):
		return [TranslationServer.translate("Empty slot"), ""]
	var w: int = int(s["worlds"])
	# TRANSLATORS: Save profile summary: play time, number of planets, the current planet's name.
	var a: String = TranslationServer.translate("%s  ·  %s  ·  on %s") % [ProfileSlots.hours(float(s["time_s"])),
		TranslationServer.translate_plural("%d planet", "%d planets", w) % w, str(s["world"])]
	var parts: Array[String] = []
	if str(s.get("district", "")) != "":
		parts.append(str(s["district"]))
	# TRANSLATORS: Save profile summary: how far the Bloom (restoration milestones) has come.
	parts.append(TranslationServer.translate("Bloom %d%%") % int(s["bloom_pct"]))
	# Only the game's three currencies: Cubes, Seeds, Parts.
	parts.append(TranslationServer.translate("%s cubes") % Settings.fmt(BigNum.from_float(float(s.get("cubes", 0.0)))))
	parts.append(TranslationServer.translate("%s seeds") % Settings.fmt(BigNum.from_float(float(s.get("seeds", 0.0)))))
	parts.append(TranslationServer.translate_plural("%d part", "%d parts", int(s.get("parts", 0.0))) % int(s.get("parts", 0.0)))
	return [a, "  ·  ".join(parts)]


func _btn(row: HBoxContainer, text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(118, 38)
	if primary:
		UITheme.orange_button(b)
		b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color.WHITE, 2, 5, 8))
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -4.0)
		cb.call())
	b.focus_entered.connect(func() -> void: Audio.play("blip", 1.6, -18.0, 0.0))
	UITheme.juice(b, 1.03)
	row.add_child(b)
	return b


## Focus grid: left/right along a slot's buttons, up/down between slots (same column, clamped).
func _chain() -> void:
	for r: int in _grid.size():
		var row: Array = _grid[r]
		for c: int in row.size():
			var b: Button = row[c]
			var up: Array = _grid[wrapi(r - 1, 0, _grid.size())]
			var dn: Array = _grid[wrapi(r + 1, 0, _grid.size())]
			b.focus_neighbor_left = b.get_path_to(row[maxi(c - 1, 0)])
			b.focus_neighbor_right = b.get_path_to(row[mini(c + 1, row.size() - 1)])
			b.focus_neighbor_top = b.get_path_to(up[mini(c, up.size() - 1)])
			b.focus_neighbor_bottom = b.get_path_to(dn[mini(c, dn.size() - 1)])


func _focus(at: Vector2i) -> void:
	var r: int = clampi(at.x, 0, _grid.size() - 1)
	var row: Array = _grid[r]
	(row[clampi(at.y, 0, row.size() - 1)] as Button).call_deferred("grab_focus")


# --- Actions -------------------------------------------------------------------------------

func _use(n: int) -> void:
	if n == SaveManager.profile_slot:
		return  # already loaded (CradleBoot)
	_changed = true
	SaveManager.set_profile(n)
	CradleMode.reload_for_profile()


func _continue(n: int) -> void:
	_use(n)
	if CradleMode.worlds().size() > 1:
		# Profile, then world (ui/world_picker.gd).
		if _worlds:
			_worlds.queue_free()
		_worlds = WorldPicker.new()
		add_child(_worlds)
		_worlds.picked.connect(func(i: int) -> void:
			if CradleMode.select_world(i):
				go.emit())
		_worlds.closed.connect(func() -> void: _focus(Vector2i(n - 1, 0)))
		_worlds.open_picker()
		return
	CradleMode.select_world(CradleMode.current_index())
	go.emit()


func _new(n: int, empty: bool) -> void:
	var start := func() -> void:
		_use(n)
		start_new_game()
		go.emit()
	if empty:
		start.call()
		return
	_confirm(tr("START OVER IN %s?") % ProfileSlots.summary(n)["name"],
		tr("Every world, Heirloom and Starseed in this profile will be erased. The other profiles stay as they are."),
		tr("Erase and start"), start, Vector2i(n - 1, 1))


## A fresh campaign in the current profile (it keeps its name).
static func start_new_game() -> void:
	CradleMode.reset_all()
	SaveManager.delete_save()
	GameState.new_game()


func _delete(n: int) -> void:
	var del: Callable = func() -> void:
		SaveManager.delete_profile(n)
		if n == SaveManager.profile_slot:
			CradleMode.reload_for_profile()
		_changed = true
		_rebuild()
		_focus(Vector2i(n - 1, 0))
	_confirm(tr("DELETE %s?") % ProfileSlots.summary(n)["name"],
		tr("This profile's worlds and progress will be erased. This can't be undone."),
		tr("Delete"), del, Vector2i(n - 1, 0))


func _rename(n: int) -> void:
	_close_dialog()
	var box: VBoxContainer = _dialog_box(tr("RENAME PROFILE"))
	var le := LineEdit.new()
	le.text = ProfileSlots.summary(n)["name"]
	le.max_length = ProfileSlots.NAME_MAX
	le.custom_minimum_size = Vector2(380, 44)
	le.select_all_on_focus = true
	box.add_child(le)
	var ok: Callable = func() -> void:
		if ProfileSlots.rename(n, le.text):
			_changed = true
		_close_dialog()
		_rebuild()
		_focus(Vector2i(n - 1, 0))
	le.text_submitted.connect(func(_t: String) -> void: ok.call())
	var row: Array[Button] = _dialog_buttons(box, tr("Cancel"), tr("Save"), ok, Vector2i(n - 1, 0))
	le.focus_neighbor_bottom = le.get_path_to(row[1])
	row[0].focus_neighbor_top = row[0].get_path_to(le)
	row[1].focus_neighbor_top = row[1].get_path_to(le)
	le.call_deferred("grab_focus")


func _confirm(title: String, msg: String, yes_text: String, yes: Callable, back_to: Vector2i) -> void:
	_close_dialog()
	var box: VBoxContainer = _dialog_box(title)
	var m := UITheme.label(msg, 15)
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.custom_minimum_size = Vector2(440, 0)
	box.add_child(m)
	var run: Callable = func() -> void:
		_close_dialog()
		yes.call()
	var row: Array[Button] = _dialog_buttons(box, tr("Cancel"), yes_text, run, back_to)
	row[0].call_deferred("grab_focus")


func _dialog_box(title: String) -> VBoxContainer:
	_dialog = Control.new()
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dialog)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialog.add_child(center)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.97), UITheme.GOLD, 1, 6, 22))
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	vb.add_child(UITheme.label(title, 22, UITheme.GOLD))
	return vb


func _dialog_buttons(box: VBoxContainer, no_text: String, yes_text: String, yes: Callable, back_to: Vector2i) -> Array[Button]:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 12)
	box.add_child(hb)
	var no := Button.new()
	no.text = no_text
	no.custom_minimum_size = Vector2(150, 44)
	no.pressed.connect(func() -> void:
		_close_dialog()
		_focus(back_to))
	UITheme.juice(no)
	hb.add_child(no)
	var y := Button.new()
	y.text = yes_text
	y.custom_minimum_size = Vector2(170, 44)
	UITheme.orange_button(y)
	y.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color.WHITE, 2, 5, 8))
	y.pressed.connect(yes)
	UITheme.juice(y)
	hb.add_child(y)
	no.focus_neighbor_right = no.get_path_to(y)
	y.focus_neighbor_left = y.get_path_to(no)
	_focus_after = back_to
	return [no, y]


func _close_dialog() -> void:
	if _dialog and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if _worlds and is_instance_valid(_worlds) and _worlds.visible:
		return  # the world list handles its own cancel
	get_viewport().set_input_as_handled()
	if _dialog:
		_close_dialog()
		_focus(_focus_after)
	else:
		close_picker()
