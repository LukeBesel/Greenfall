class_name TelescopePanel
extends VBoxContainer
## [scope] Hub tab section: build the Telescope (automation/telescope.gd).

var _label: Label
var _btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label(tr("OBSERVATORY"), 18, UITheme.CREAM))
	_label = UITheme.label("", 15, UITheme.CREAM)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_label)
	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(320, 44)
	_btn.pressed.connect(func() -> void:
		var t: Telescope = Telescope.of(self)
		if t and t.build():
			EventBus.ui_modal_changed.emit(false)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	add_child(_btn)
	refresh()


func refresh() -> void:
	var t: Telescope = Telescope.of(self)
	if t == null:
		visible = false
		return
	visible = true
	var d: Dictionary = t.data
	var name_: String = tr(str(d.get("name", "Telescope")))
	var reason: String = t.block_reason()
	var status: String
	if t.built():
		status = tr("Built. Walk up to it and press E.")
	elif reason != "" and reason != tr("Not enough materials."):
		status = reason
	else:
		status = tr("Needs %s") % HubPanel.cost_text(Telescope.cost())
	_label.text = "%s   ·   %s\n%s" % [name_, tr(str(d.get("desc", ""))), status]
	_btn.text = (tr("%s built") % name_) if t.built() else (tr("Build %s") % name_)
	_btn.disabled = reason != ""
