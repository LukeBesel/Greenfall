class_name LumiBuilder
extends Control
## The Locker's page for Lumi (design spec section 13): the look she wears is put together here
## from the pieces found in the world, and nowhere else. Left: the slots (and "Sets" on top).
## Right: the chosen slot's pieces, found ones first; a found piece is worn with one press. An
## unfound piece that this planet hides is a dark silhouette named "???" with one hint line, and
## cannot be worn; pieces hidden on other worlds are only counted. "Saved looks" at the foot of
## the slot list keeps three looks. "Wear look" is what changes Lumi. Wearing every piece of one
## set shows the set's name and its small bonus at the top; a mixed look shows that it has none.
##
## The look being edited shows on the turntable beside the Locker (systems/camp/locker_stage.gd,
## handed in as `stage`); without one (tests) the page still edits.
## Hosted by ui/locker_panel.gd through CosmeticTargets: var b := LumiBuilder.new();
## b.world = world; b.stage = stage; parent.add_child(b).

signal closed
signal worn

const SETS: String = "sets"
const SAVED: String = "saved"
const SLOT_W: float = 176.0
const MIN_SIZE := Vector2(500, 430)
const WORN_STAT: String = "looks_worn"

var world: Node
var stage: LockerStage
var edit: Dictionary = {}

var _orig: Dictionary = {}
var _slot: String = ""
var _order: Array[String] = []
var _slot_btns: Dictionary[String, Button] = {}
var _list: VBoxContainer
var _title: Label
var _set_line: Label
var _status: Label
var _focus_row: Control
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = MIN_SIZE
	_rng.randomize()
	edit = LumiStyle.current()
	_orig = edit.duplicate(true)
	_build()
	var found: Array = Looks.found()
	var newest: String = Looks.slot_of(str(found[-1])) if not found.is_empty() else ""
	select_slot(newest if newest in _order else _order[1], false)


# --- Layout -----------------------------------------------------------------------------------

func _build() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	top.add_child(FieldPlate.stencil(tr("Lumi"), FieldPlate.CYAN, 20))
	_set_line = FieldPlate.stencil("", FieldPlate.INK_DIM)
	_set_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_set_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_set_line)
	vb.add_child(FieldPlate.rule())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	vb.add_child(body)
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(SLOT_W, 0)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.follow_focus = true
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 4)
	side_scroll.add_child(side)
	_add_slot(side, SETS, tr("Sets"))
	for s: Dictionary in Looks.slot_defs():
		_add_slot(side, str(s["id"]), tr(str(s["name"])))
	_add_slot(side, SAVED, tr("Saved looks"))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_title = FieldPlate.stencil("", FieldPlate.INK)
	right.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	vb.add_child(FieldPlate.rule())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	vb.add_child(foot)
	foot.add_child(_key(tr("Randomize"), _shuffle))
	_status = FieldPlate.stencil("", FieldPlate.AMBER)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(_status)
	var wear_btn := _key(tr("Wear look"), wear)
	wear_btn.custom_minimum_size.x = 150
	foot.add_child(wear_btn)


func _key(text: String, on_press: Callable, accent: Color = FieldPlate.CYAN) -> Button:
	var b := Button.new()
	b.text = text
	FieldPlate.key(b, accent)
	b.pressed.connect(on_press)
	return b


func _add_slot(side: VBoxContainer, slot: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.pressed.connect(select_slot.bind(slot))
	side.add_child(b)
	_slot_btns[slot] = b
	_order.append(slot)


# --- Slots and pieces -------------------------------------------------------------------------

## Show a slot's pieces ("sets" = the sets page, "saved" = the saved looks). Unknown ids are ignored.
func select_slot(slot: String, take_focus: bool = true) -> void:
	if not (slot in _order):
		return
	_slot = slot
	_refresh(take_focus)


func shown_slot() -> String:
	return _slot


## The pieces of the shown slot that this planet hides and the player has not found.
func unfound_here() -> Array[String]:
	var out: Array[String] = []
	var here: Array[String] = _hidden_here()
	for id: String in Looks.of_slot(_slot):
		if not Looks.has(id) and id in here:
			out.append(id)
	return out


func _hidden_here() -> Array[String]:
	return Finds.pieces_for(Planets.current())


## The hint line under an unfound piece: where this planet hides it.
func hint_of(piece: String) -> String:
	return Finds.hint_for(Planets.current(), piece)


func _refresh(take_focus: bool = false) -> void:
	for id: String in _slot_btns:
		FieldPlate.key(_slot_btns[id], FieldPlate.CYAN, id == _slot)
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_focus_row = null
	if _slot == SETS:
		_title.text = tr("Sets").to_upper()
		_build_sets()
	elif _slot == SAVED:
		_title.text = tr("Saved looks").to_upper()
		_build_saved()
	else:
		_title.text = tr(str(Looks.slot_def(_slot).get("name", _slot))).to_upper()
		_build_pieces()
	_update_lines()
	if stage:
		stage.show_style(edit)
	if take_focus:
		_focus_shown_row.call_deferred()


## Focus goes to the worn row of the list (after the layout pass; the list may have changed again).
func _focus_shown_row() -> void:
	if _focus_row and is_instance_valid(_focus_row) and _focus_row.is_inside_tree():
		_focus_row.grab_focus()


func _build_pieces() -> void:
	var worn_piece: String = LumiStyle.piece_in(edit, _slot)
	if LumiStyle.can_clear(_slot):
		var empty: bool = worn_piece == "" and str(edit[_slot]) == str((LumiStyle.options(_slot)[0] as Dictionary)["id"])
		var none := _key(tr("None"), _clear_slot)
		none.alignment = HORIZONTAL_ALIGNMENT_LEFT
		FieldPlate.key(none, FieldPlate.CYAN, empty)
		_list.add_child(none)
		if empty:
			_focus_row = none
	var unfound: Array[String] = unfound_here()
	var elsewhere: int = 0
	for id: String in Looks.of_slot(_slot):
		if Looks.has(id):
			var row := PieceRow.new(id, true, id == worn_piece, LumiStyle.piece_tint(id, FieldPlate.INK))
			row.pressed.connect(_wear_piece.bind(id))
			_list.add_child(row)
			if id == worn_piece or _focus_row == null:
				_focus_row = row
		elif not (id in unfound):
			elsewhere += 1
	for id: String in unfound:
		var row := PieceRow.new(id, false, false, FieldPlate.INK_DIM, hint_of(id))
		row.pressed.connect(_refuse)
		_list.add_child(row)
	if elsewhere > 0:
		_list.add_child(FieldPlate.sentence(tr("%d more lie on other worlds.") % elsewhere, FieldPlate.INK_DIM))


## The sets the player knows of: any with a piece found, and the one this planet hides.
func _build_sets() -> void:
	_list.add_child(FieldPlate.sentence(tr("Wear every piece of one set for its small bonus. A mixed look gives none."), FieldPlate.INK_DIM))
	var here: String = Finds.set_for(Planets.current())
	var worn_set: String = LumiStyle.worn_set(edit)
	for id: String in Designs.ids():
		var p: Array[int] = Looks.set_progress(id)
		if p[1] == 0 or (p[0] == 0 and id != here):
			continue
		var known: bool = p[0] > 0
		var title: String = tr(Designs.name_of(id)) if known else tr(Looks.UNFOUND_NAME)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		if p[0] == p[1]:
			b.text = "%s  ·  %s" % [title, Designs.buff_text(id)]
			FieldPlate.key(b, FieldPlate.GREEN, id == worn_set)
			b.pressed.connect(_wear_set.bind(id))
			if id == worn_set or _focus_row == null:
				_focus_row = b
		else:
			b.text = tr("%s  ·  %d of %d pieces") % [title, p[0], p[1]]
			FieldPlate.key(b, FieldPlate.INK_DIM)
			b.pressed.connect(_refuse)
		_list.add_child(b)
	var looks := CheckButton.new()
	looks.text = tr("Looks only (no set bonus)")
	looks.button_pressed = Designs.looks_only()
	looks.focus_mode = Control.FOCUS_ALL
	looks.custom_minimum_size.y = FieldPlate.TOUCH_PX
	looks.toggled.connect(_set_looks_only)
	_list.add_child(looks)


## The saved looks: each slot loads its look onto the turntable, or keeps the one that is there.
func _build_saved() -> void:
	_list.add_child(FieldPlate.sentence(tr("Keep a look to put it on again later."), FieldPlate.INK_DIM))
	for i: int in LumiStyle.looks().size():
		var lk: Dictionary = LumiStyle.look(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_list.add_child(row)
		var load_btn := _key(tr("Look %d") % (i + 1) if not lk.is_empty() else tr("%d  ·  Empty") % (i + 1), _load_look.bind(i),
			FieldPlate.CYAN if not lk.is_empty() else FieldPlate.INK_DIM)
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.disabled = lk.is_empty()
		load_btn.tooltip_text = tr("Put this saved look on the turntable")
		row.add_child(load_btn)
		var save_btn := _key(tr("Save here"), _save_look.bind(i), FieldPlate.INK_DIM)
		save_btn.tooltip_text = tr("Keep the look on the turntable in this slot")
		row.add_child(save_btn)
		if _focus_row == null:
			_focus_row = save_btn


func _update_lines() -> void:
	var worn_set: String = LumiStyle.worn_set(edit)
	if worn_set != "":
		var off: String = "  " + tr("(off: looks only)") if Designs.looks_only() else ""
		_set_line.text = (tr("%s set  ·  %s") % [tr(Designs.name_of(worn_set)), Designs.buff_text(worn_set)] + off).to_upper()
		_set_line.add_theme_color_override("font_color", FieldPlate.INK_DIM if Designs.looks_only() else FieldPlate.GREEN)
	else:
		_set_line.text = tr("Mixed look  ·  no set bonus").to_upper()
		_set_line.add_theme_color_override("font_color", FieldPlate.INK_DIM)
	_status.text = "" if LumiStyle.same(edit, _orig) else tr("Not worn yet").to_upper()


# --- Editing ----------------------------------------------------------------------------------

func _wear_piece(piece: String) -> void:
	if not Looks.has(piece):
		_refuse()
		return
	LumiStyle.wear_piece(edit, piece)
	Audio.play("click", 1.2, -6.0)
	_refresh(true)


func _clear_slot() -> void:
	LumiStyle.clear_slot(edit, _slot)
	Audio.play("click", 1.0, -6.0)
	_refresh(true)


func _wear_set(design: String) -> void:
	if not Looks.set_collected(design):
		_refuse()
		return
	edit = LumiStyle.with_set(edit, design)
	Audio.play("click", 1.2, -6.0)
	_refresh(true)


func _refuse() -> void:
	Audio.play("error", 1.0, -8.0)


func _set_looks_only(on: bool) -> void:
	Designs.set_looks_only(on)
	Audio.play("click", 1.0, -6.0)
	_update_lines()


func _shuffle() -> void:
	edit = LumiStyle.randomized(_rng, edit)
	Audio.play("click", 1.3, -6.0)
	_refresh()


func _load_look(i: int) -> void:
	var lk: Dictionary = LumiStyle.look(i)
	if lk.is_empty():
		return
	lk.erase("name")
	edit = lk
	Audio.play("click", 1.2, -6.0)
	_refresh()


func _save_look(i: int) -> void:
	if not LumiStyle.allowed(edit):
		_refuse()
		return
	LumiStyle.save_look(i, edit, tr("Look %d") % (i + 1))
	Audio.play("buy", 1.3, -6.0)
	_refresh()


## Lumi wears the look on the turntable. False when a piece of it is not found.
func wear() -> bool:
	if not LumiStyle.allowed(edit):
		_refuse()
		_status.text = tr("A piece of this look is not found yet").to_upper()
		return false
	var changed: bool = not LumiStyle.same(edit, LumiStyle.current())
	LumiStyle.set_current(edit)
	_orig = LumiStyle.current()
	edit = _orig.duplicate(true)
	if changed:
		GameState.inc_stat(WORN_STAT)
		LumiStyle.refresh_player(world)
		Audio.play("buy", 1.2, -4.0)
	_update_lines()
	worn.emit()
	return true


## Drop the edit and show the worn look again.
func revert() -> void:
	edit = LumiStyle.current()
	_orig = edit.duplicate(true)
	_refresh()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	for step: Array in [["ui_tab_next", 1], ["ui_tab_prev", -1]]:
		if InputMap.has_action(str(step[0])) and event.is_action_pressed(str(step[0])):
			var n: int = _order.size()
			var next: String = _order[(maxi(0, _order.find(_slot)) + int(step[1]) + n) % n]
			select_slot(next, false)
			_slot_btns[next].grab_focus()
			get_viewport().set_input_as_handled()
			return
