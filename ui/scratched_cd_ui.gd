class_name ScratchedCdUI
extends CanvasLayer
## [tunes] Scratched CDs (planet/cd_finds.gd): the pickup choice ("Play now" / "Keep for later"),
## and while one plays its single play, a short "Last play" card and a soft vignette so it feels
## worth stopping to listen. When it ends it cracks (a small sound) and is gone; the toast says
## where the intact CD is.

var world: Node
var _root: Control
var _ask: PanelContainer
var _ask_text: Label
var _ask_hint: Label
var _keep: Button
var _play: Button
var _leave: Button
var _ask_id: String = ""
var _card: PanelContainer
var _card_title: Label
var _card_by: Label
var _card_t: float = 0.0
var _vignette: TextureRect
var _vig: float = 0.0


func _ready() -> void:
	name = "ScratchedCdUI"
	layer = 33
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_build_vignette()
	_build_card()
	_build_ask()
	var d: Node = Tunes.director()
	if d:
		d.connect("scratch_started", _on_started)
		d.connect("scratch_finished", _on_finished)


func _exit_tree() -> void:
	var d: Node = Tunes.director()
	if d:
		if d.is_connected("scratch_started", _on_started):
			d.disconnect("scratch_started", _on_started)
		if d.is_connected("scratch_finished", _on_finished):
			d.disconnect("scratch_finished", _on_finished)


func _build_vignette() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.01, 0.015, 0.03, 1.0))
	g.set_offset(0, 0.55)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.055, 0.86), Color(ExtrasCdList.CD_COLOR, 0.35), 1, 12, 14))
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.offset_left = -200
	_card.offset_right = 200
	_card.offset_top = 70
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_card.add_child(vb)
	var head: Label = UITheme.label(tr("NOW PLAYING  ·  LAST PLAY"), 11, ExtrasCdList.CD_COLOR)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(head)
	_card_title = UITheme.label("", 22, Color.WHITE)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_card_title)
	_card_by = UITheme.label("", 13, UITheme.MUTED)
	_card_by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_by.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_card_by)
	_card.visible = false


func _build_ask() -> void:
	_ask = PanelContainer.new()
	_ask.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.065, 0.95), Color(1, 1, 1, 0.1), 1, 12, 20))
	_ask.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_ask.custom_minimum_size = Vector2(520, 0)
	_ask.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ask.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_ask)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_ask.add_child(vb)
	vb.add_child(UITheme.label(tr("SCRATCHED CD"), 13, ExtrasCdList.CD_COLOR))
	_ask_text = UITheme.label("", 18, Color.WHITE)
	_ask_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	_ask_text.custom_minimum_size = Vector2(480, 0)
	vb.add_child(_ask_text)
	_ask_hint = UITheme.label("", 13, UITheme.MUTED)
	_ask_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_ask_hint.custom_minimum_size = Vector2(480, 0)
	vb.add_child(_ask_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	_play = _button(row, tr("Play now"), func() -> void: _answer("play"))
	UITheme.orange_button(_play)
	_keep = _button(row, tr("Keep for later"), func() -> void: _answer("keep"))
	_leave = _button(row, tr("Leave it"), func() -> void: _answer("leave"))
	_ask.visible = false


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 42)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		cb.call())
	parent.add_child(b)
	return b


static func ask_text(id: String) -> String:
	return TranslationServer.translate("%s by %s: it will only play once, then break. Play now?") % [
		TranslationServer.translate(Tunes.title(id)), TranslationServer.translate(Tunes.artist_name(id))]


static func hint_text(id: String) -> String:
	return TranslationServer.translate("Find the intact CD on %s to keep it.") % Tunes.planet_name(Tunes.home(id))


## The pickup choice. The game waits while it is open.
func ask(id: String) -> void:
	_ask_id = id
	_ask_text.text = ask_text(id)
	var full: bool = Tunes.case_full()
	_ask_hint.text = hint_text(id) + ("  " + tr("Your CD case is full (%d).") % Tunes.case_size() if full else "")
	_keep.disabled = full
	_leave.visible = full
	_ask.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	_play.call_deferred("grab_focus")


func _answer(what: String) -> void:
	var id: String = _ask_id
	_ask_id = ""
	_ask.visible = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()
	match what:
		"play":
			if not Tunes.hold(id) and not Tunes.is_found(id):
				Tunes.held().append(id)  # played at once: it never sits in the case
			if not Tunes.play_scratched(id):
				EventBus.toast.emit(tr("Kept in your CD case. Play it at the CD player."), "info")
		"keep":
			if Tunes.hold(id):
				EventBus.toast.emit(tr("Kept in your CD case (%d / %d). Play it at the CD player.") % [Tunes.held().size(), Tunes.case_size()], "info")
		_:
			EventBus.toast.emit(tr("You leave the scratched CD where it lay."), "info")


func _unhandled_input(event: InputEvent) -> void:
	if _ask.visible and event.is_action_pressed("ui_cancel"):
		_answer("leave" if Tunes.case_full() else "keep")
		get_viewport().set_input_as_handled()


## [onboard2] Coordinator: the "NOW PLAYING · LAST PLAY" card folds into the one message line
## (ui/subtitles.gd): the title, then the hint, one at a time. The vignette stays (no text).
func _on_started(id: String) -> void:
	EventBus.toast.emit(tr("Last play: %s, by %s.") % [tr(Tunes.title(id)), tr(Tunes.artist_name(id))], "info")
	EventBus.toast.emit(hint_text(id), "hint")


func _on_finished(id: String) -> void:
	Audio.play("crunch", 1.9, -10.0)
	Audio.play("clink", 0.8, -8.0)
	EventBus.toast.emit(tr("The scratched CD cracks and falls apart. %s") % hint_text(id), "info")


func _process(delta: float) -> void:
	var playing: bool = Tunes.director() != null and str(Tunes.director().get("scratch")) != ""
	_vig = move_toward(_vig, 0.42 if playing else 0.0, delta / 2.0)
	_vignette.modulate.a = _vig
	if _card.visible:
		_card_t -= delta
		_card.modulate.a = clampf(minf(9.0 - _card_t, _card_t) / 0.6, 0.0, 1.0)
		if _card_t <= 0.0:
			_card.visible = false
