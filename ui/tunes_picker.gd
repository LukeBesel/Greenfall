class_name TunesPicker
extends CanvasLayer
## [tunes] Quick-select for your CDs, anywhere (N), once Glim has the Music upgrade
## (Tunes.glim_music()): Shuffle, Off, or one song on repeat. A small card at the bottom right;
## the game pauses while it is open, like the other small panels.

const KEY: Key = KEY_N

var world: Node
var is_open: bool = false
var _root: Control
var _list: VBoxContainer


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
	vb.add_child(UITheme.label(tr("GLIM'S CDS"), 13, ExtrasCdList.CD_COLOR))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	vb.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)
	var hint: Label = UITheme.label(tr("N / Esc  close"), 11, UITheme.MUTED)
	vb.add_child(hint)
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY:
		if is_open:
			close()
		elif Tunes.glim_music() and not (world and world.has_method("any_modal_open") and world.any_modal_open()):
			open()
		else:
			return
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open or not Tunes.glim_music():
		return
	is_open = true
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
	var first: Button = _add(tr("Shuffle"), mode == Tunes.SHUFFLE, Tunes.SHUFFLE)
	_add(tr("Off (the day's music)"), mode == "", "")
	var focus: Button = first
	for id: String in Tunes.found():
		var b: Button = _add("%s  ·  %s" % [tr(Tunes.title(id)), tr(Tunes.artist_name(id))], mode == id, id)
		if mode == id:
			focus = b
	focus.call_deferred("grab_focus")


func _add(text: String, on: bool, id: String) -> Button:
	var b := Button.new()
	b.text = ("▶  " if on else "") + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.CREAM)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		Radio.play(id)
		if id != "" and id != Tunes.SHUFFLE:
			EventBus.toast.emit(tr("Now playing: %s by %s") % [tr(Tunes.title(id)), tr(Tunes.artist_name(id))], "info")
		close())
	_list.add_child(b)
	return b
