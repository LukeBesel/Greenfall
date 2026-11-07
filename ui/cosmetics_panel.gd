class_name CosmeticsPanel
extends VBoxContainer
## Workbench "Cosmetics" tab: Lumi's design picker. A spinning preview of the focused design, its
## name, tagline, small bonus and how to unlock it, and a row of design cards (D-pad / mouse:
## focus or hover previews, press wears). "Looks only" switches every design bonus off.
## Logic and state: systems/designs.gd; looks: PatchModel.VARIANTS.

var world: Node
var _preview: DesignPreview
var _cards: Dictionary = {}  # id -> Button
var _row: HBoxContainer
var _name: Label
var _tag: Label
var _desc: Label
var _buff: Label
var _state: Label
var _bar: ProgressBar
var _prog: Label
var _looks: CheckButton
var _shown: String = ""
var _builder_btn: Button  # [style]


## Kept for older callers (scenes/slice.gd hooks it to a few gameplay signals).
static func check_unlocks() -> void:
	Designs.check_unlocks()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	add_child(head)
	var t := UITheme.label(tr("DESIGNS"), 20, UITheme.CREAM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_looks = CheckButton.new()
	_looks.text = tr("Looks only (no bonuses)")
	_looks.button_pressed = Designs.looks_only()
	_looks.toggled.connect(func(on: bool) -> void:
		Designs.set_looks_only(on)
		Audio.play("click", 1.0, -6.0)
		_show(_shown, true))
	head.add_child(_looks)
	# [style] Character Builder: every slot of the look, on its own screen.
	var bb := Button.new()
	bb.text = tr("Character Builder")
	bb.custom_minimum_size = Vector2(190, 36)
	bb.focus_mode = Control.FOCUS_ALL
	UITheme.orange_button(bb)
	bb.pressed.connect(func() -> void:
		var lb: LumiBuilder = LumiBuilder.open(world, self)
		lb.closed.connect(func() -> void:
			refresh()
			if is_instance_valid(bb):
				bb.grab_focus.call_deferred()))
	head.add_child(bb)
	_builder_btn = bb

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	add_child(top)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.035, 0.045, 0.85), Color(1, 1, 1, 0.07), 1, 10, 0))
	top.add_child(frame)
	_preview = DesignPreview.new(Vector2i(300, 300))
	_preview.process_mode = Node.PROCESS_MODE_ALWAYS
	frame.add_child(_preview)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size = Vector2(360, 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	top.add_child(info)
	_name = UITheme.label("", 34, Color.WHITE)
	info.add_child(_name)
	_tag = UITheme.label("", 17, UITheme.MUTED)
	info.add_child(_tag)
	_desc = UITheme.label("", 15, UITheme.CREAM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(340, 0)
	info.add_child(_desc)
	_buff = UITheme.label("", 16, UITheme.GREEN)
	info.add_child(_buff)
	_state = UITheme.label("", 16, UITheme.GOLD)
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_state)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(300, 10)
	_bar.max_value = 1.0
	info.add_child(_bar)
	_prog = UITheme.label("", 14, UITheme.MUTED)
	info.add_child(_prog)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)
	for id: String in Designs.ids():
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 70)
		b.focus_mode = Control.FOCUS_ALL
		b.clip_text = true
		b.mouse_entered.connect(func() -> void: _show(id))
		b.focus_entered.connect(func() -> void: _show(id))
		b.pressed.connect(func() -> void: _wear(id))
		_row.add_child(b)
		_cards[id] = b
	refresh()
	_show(Designs.current(), true)


var _sig: String = ""
var _tick: float = 0.0


## Keep cards and progress live (unlocks while the bench is open, dev hooks after build).
func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	var sig: String = "%s|%s|%s" % [Designs.current(), str(Designs.unlocked()), str(Designs.looks_only())]
	for id: String in _cards:
		sig += "|%.2f" % Designs.progress(id)
	if sig != _sig:
		_sig = sig
		_looks.set_pressed_no_signal(Designs.looks_only())
		refresh()


## The worn design's card (the workbench focuses it when the tab opens).
func first_button() -> Control:
	return _cards.get(Designs.current())


func refresh() -> void:
	var current: String = Designs.current()
	for id: String in _cards:
		var b: Button = _cards[id]
		var glow: Color = PatchModel.glow_of(id)
		var unlocked: bool = Designs.is_unlocked(id)
		var line2: String = tr("Wearing") if id == current else (tr("Unlocked") if unlocked else tr("Locked  %d%%") % int(Designs.progress(id) * 100.0))
		b.text = "%s\n%s" % [tr(str(Designs.def(id).get("name", id))), line2]
		var bg := Color(0.08, 0.085, 0.1, 0.95) if unlocked else Color(0.05, 0.05, 0.06, 0.9)
		for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			var lit: bool = st in ["focus", "hover"] or id == current
			var sb := UITheme.box(bg.lightened(0.08) if st in ["hover", "focus"] else bg, Color(1, 1, 1, 0.08), 2 if lit else 1, 8, 8)
			sb.border_width_top = 5
			sb.border_color = glow if lit else (glow.darkened(0.55) if unlocked else Color(0.25, 0.25, 0.27))
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", glow.lightened(0.35) if unlocked else UITheme.MUTED)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	_show(_shown, true)


func _show(id: String, force: bool = false) -> void:
	if id == "" or (id == _shown and not force):
		return
	_shown = id
	var d: Dictionary = Designs.def(id)
	var glow: Color = PatchModel.glow_of(id)
	_preview.show_design(id)
	_name.text = tr(str(d.get("name", id))).to_upper()
	_name.add_theme_color_override("font_color", glow.lightened(0.45))
	_tag.text = tr(str(d.get("tagline", "")))
	_desc.text = tr(str(d.get("desc", "")))
	var bt: String = Designs.buff_text(id)
	_buff.text = (tr("Bonus: %s") % bt) + ("  " + tr("(off: looks only)") if Designs.looks_only() else "")
	_buff.add_theme_color_override("font_color", UITheme.MUTED if Designs.looks_only() else UITheme.GREEN)
	var unlocked: bool = Designs.is_unlocked(id)
	if id == Designs.current():
		_state.text = tr("Wearing") if LumiStyle.is_preset(LumiStyle.current()) else tr("Wearing a custom look with this bonus")  # [style]
	elif unlocked:
		_state.text = tr("Unlocked. Press to wear.")
	else:
		_state.text = tr("Locked: %s") % Designs.unlock_text(id)
	_state.add_theme_color_override("font_color", glow.lightened(0.3) if unlocked else UITheme.GOLD)
	_bar.visible = not unlocked
	_prog.visible = not unlocked
	_bar.value = Designs.progress(id)
	_prog.text = Designs.progress_text(id)


func _wear(id: String) -> void:
	if not Designs.is_unlocked(id):
		Audio.play("error", 1.0, -6.0)
		_show(id, true)
		return
	if not LumiStyle.wear_preset(id):  # [style] wearing a design = its preset look
		return
	if world and world.get("patch"):
		var p: Node3D = world.patch
		(p.get("model") as PatchModel).set_variant(id)
		Vfx.burst("sparkle", p.global_position + Vector3(0, 0.8, 0), PatchModel.glow_of(id))
	Audio.play("buy", 1.2, -4.0)
	refresh()
