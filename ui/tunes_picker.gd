class_name TunesPicker
extends CanvasLayer
## [tunes] The radio: your found CDs, anywhere (N, or Pause > Radio), from the first CD on
## (Tunes.radio_open()). [v10snd] Owner: "player can play sun baked whenever they want". One simple
## list: a found song (plays on repeat), Random songs (they come by themselves, with quiet in
## between) or Stop. Shown as Glim's radio once Glim is built. A small card at the bottom right;
## the game pauses while it is open, like the other small panels.

const ACTION: String = "open_radio"

var world: Node
var is_open: bool = false
var _root: Control
var _list: VBoxContainer
var _title: Label
var _hint: Label


func _ready() -> void:
	name = "TunesPicker"
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.065, 0.92), Color(1, 1, 1, 0.1), 1, 12, 14))
	pc.anchor_left = 1.0
	pc.anchor_right = 1.0
	pc.anchor_top = 1.0
	pc.anchor_bottom = 1.0
	pc.offset_left = -340
	pc.offset_right = -24
	pc.offset_top = -430
	pc.offset_bottom = -96
	_root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	_title = UITheme.label(tr("RADIO"), 13, ExtrasCdList.CD_COLOR)
	vb.add_child(_title)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	vb.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)
	_hint = UITheme.label("", 11, UITheme.MUTED)
	vb.add_child(_hint)
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		if is_open:
			close()
		elif Tunes.radio_open() and not (world and world.has_method("any_modal_open") and world.any_modal_open()):
			open()
		else:
			return
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or not Tunes.radio_open():
		return
	is_open = true
	_title.text = tr("GLIM'S RADIO") if Tunes.glim_built() else tr("RADIO")
	_hint.text = tr("%s / Esc  close") % Settings.glyph(ACTION)
	_fill()
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


func _fill() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var mode: String = Radio.playing()
	var first: Button = _add(tr("Random songs"), mode == "" or mode == Tunes.SHUFFLE, "")
	_add(tr("Stop the music"), mode == Tunes.OFF, Tunes.OFF)
	var focus: Button = first
	for id: String in Tunes.found():
		var b: Button = _add(tr(Tunes.title(id)), mode == id, id)  # [v10snd] the title alone: "title · artist" was cut off
		if mode == id:
			focus = b
	for id: String in Tunes.held():
		var sb: Button = _add(tr("Play once: %s (scratched)") % tr(Tunes.title(id)), false, "")
		sb.remove_meta("pick")
		for c: Dictionary in sb.pressed.get_connections():
			sb.pressed.disconnect(c["callable"])
		sb.pressed.connect(func() -> void:
			Audio.play("click", 1.0, -6.0)
			Tunes.play_scratched(id)
			close())
	focus.call_deferred("grab_focus")


## The row of a pick ("" Random songs, Tunes.OFF Stop, or a song id); null when it is not listed.
func row(id: String) -> Button:
	for c: Node in _list.get_children():
		if c is Button and c.has_meta("pick") and str(c.get_meta("pick")) == id:
			return c
	return null


func _add(text: String, on: bool, id: String) -> Button:
	var b := Button.new()
	b.set_meta("pick", id)
	b.text = ("▶  " if on else "") + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.CREAM)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		Radio.play(id)
		if id != "" and id != Tunes.SHUFFLE and id != Tunes.OFF:
			EventBus.toast.emit(tr("Now playing: %s by %s") % [tr(Tunes.title(id)), tr(Tunes.artist_name(id))], "low")
		close())
	_list.add_child(b)
	return b
