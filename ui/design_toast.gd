class_name DesignToast
extends CanvasLayer
## "New design unlocked" card: slides in at the top of the screen with a spinning preview of Lumi
## in the new design, its name, tagline and buff, holds a few seconds, then slides away. Unlocks
## queue in Designs.pending_toasts and play one after another.

static var _inst: DesignToast

var _panel: PanelContainer
var _preview: DesignPreview
var _title: Label
var _name: Label
var _tag: Label
var _buff: Label
var _stripe: ColorRect
var _busy: bool = false


static func show_next() -> void:
	if Designs.pending_toasts.is_empty():
		return
	if _inst and is_instance_valid(_inst):
		_inst._play_next()
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_inst = DesignToast.new()
	tree.root.add_child.call_deferred(_inst)


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.CARD_BG, Color(1, 1, 1, 0.1), 1, 10, 0))
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	_panel.add_child(hb)
	_stripe = ColorRect.new()
	_stripe.custom_minimum_size = Vector2(6, 0)
	hb.add_child(_stripe)
	_preview = DesignPreview.new(Vector2i(150, 150))
	_preview.spin_speed = 1.1
	hb.add_child(_preview)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_right", 22)
	mc.add_theme_constant_override("margin_top", 14)
	mc.add_theme_constant_override("margin_bottom", 14)
	hb.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	mc.add_child(vb)
	_title = UITheme.label(tr("NEW DESIGN UNLOCKED"), 13, UITheme.MUTED)
	vb.add_child(_title)
	_name = UITheme.label("", 32, Color.WHITE)
	vb.add_child(_name)
	_tag = UITheme.label("", 15, UITheme.CREAM)
	vb.add_child(_tag)
	_buff = UITheme.label("", 15, UITheme.GREEN)
	vb.add_child(_buff)
	vb.add_child(UITheme.label(tr("Wear it at the workbench: Cosmetics"), 13, UITheme.MUTED))
	_panel.modulate.a = 0.0
	_play_next()


func _play_next() -> void:
	if _busy or Designs.pending_toasts.is_empty() or not is_inside_tree():
		return
	_busy = true
	var id: String = Designs.pending_toasts.pop_front()
	var d: Dictionary = Designs.def(id)
	var glow: Color = PatchModel.glow_of(id)
	_preview.show_design(id)
	_stripe.color = glow
	_title.add_theme_color_override("font_color", glow.lightened(0.25))
	_name.text = tr(str(d.get("name", id))).to_upper()
	_tag.text = tr(str(d.get("tagline", "")))
	_buff.text = Designs.buff_text(id)
	_buff.visible = _buff.text != "" and not Designs.looks_only()
	Audio.play("chime", 1.15, -2.0)
	await get_tree().process_frame
	var w: float = _panel.get_combined_minimum_size().x
	_panel.position = Vector2((get_viewport().get_visible_rect().size.x - w) * 0.5, -40.0)
	if DevHooks.has("design-unlock"):  # screenshots: software rendering runs at a few frames, so no slide-in
		_panel.position.y = 86.0
		_panel.modulate.a = 1.0
	var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "position:y", 86.0, 0.45)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.3)
	tw.tween_interval(9999.0 if DevHooks.has("design-unlock") else 5.5)  # held for screenshots
	tw.tween_property(_panel, "position:y", 40.0, 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_panel, "modulate:a", 0.0, 0.35)
	await tw.finished
	_busy = false
	if Designs.pending_toasts.is_empty():
		_inst = null
		queue_free()
	else:
		_play_next()
