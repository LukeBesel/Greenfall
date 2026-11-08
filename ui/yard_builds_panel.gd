class_name YardBuildsPanel
extends VBoxContainer
## [camp] Hub tab section: the yard. Upgrade the trash bin (automation/trash_bin.gd) and build the
## radio and the robot nursery (systems/camp/yard_builds.gd). A build is only listed once it can
## be earned (the nursery after the first sprout), so nothing is spoiled early.

var _rows: Dictionary = {}  # id -> [Label, Button]


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label(tr("YARD"), 18, UITheme.CREAM))
	_add_row("trash_bin", func() -> bool: return TrashBin.upgrade(_hub_level()))
	for id: String in YardBuilds.IDS:
		var bid: String = id
		_add_row(bid, func() -> bool: return YardBuilds.build(bid, _hub_level()))
	refresh()


func _add_row(id: String, act: Callable) -> void:
	var l: Label = UITheme.label("", 15, UITheme.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(func() -> void:
		if bool(act.call()):
			Audio.play("buy", 0.95, -2.0)
			EventBus.ui_modal_changed.emit(false)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	add_child(b)
	_rows[id] = [l, b]


func _hub_level() -> int:
	var hp: HubPanel = get_parent() as HubPanel
	if hp and hp.hub:
		return hp.hub.level
	return int(GameState.world.get("hub_level", 1))


func refresh() -> void:
	if _rows.is_empty():
		return
	var hl: int = _hub_level()
	# Trash bin.
	var bl: Label = _rows["trash_bin"][0]
	var bb: Button = _rows["trash_bin"][1]
	var cur: Dictionary = TrashBin.level_def(TrashBin.level())
	var nxt: Dictionary = TrashBin.next_def()
	var head: String = tr("Trash bin: %s (level %d)   ·   bales sell for %d%% here") % [tr(str(cur.get("name", ""))), TrashBin.level(), int(round(TrashBin.value_mult() * 100.0))]
	if nxt.is_empty():
		bl.text = head + "\n" + tr("Fully upgraded.")
		bb.visible = false
	else:
		var why: String = TrashBin.block_reason(hl)
		bl.text = "%s\n%s: %s\n%s" % [head, tr(str(nxt["name"])), tr(str(nxt.get("desc", ""))), why if why != "" and why != tr("Not enough materials.") else tr("Needs %s") % HubPanel.cost_text(nxt.get("cost", {}))]
		bb.text = tr("Upgrade to %s") % tr(str(nxt["name"]))
		bb.disabled = why != ""
		bb.visible = true
	# Radio, nursery.
	for id: String in YardBuilds.IDS:
		var l: Label = _rows[id][0]
		var b: Button = _rows[id][1]
		var on: bool = YardBuilds.listed(id)
		l.visible = on
		b.visible = on and not YardBuilds.built(id)
		if not on:
			continue
		var d: Dictionary = YardBuilds.def(id)
		var nm: String = tr(str(d.get("name", id)))
		var why2: String = YardBuilds.block_reason(id, hl)
		var status: String
		if YardBuilds.built(id):
			status = tr("Built. Walk up to it and press E.") if id == "radio" else tr("Built.")
		elif why2 != "" and why2 != tr("Not enough materials."):
			status = why2
		else:
			status = tr("Needs %s") % HubPanel.cost_text(d.get("cost", {}))
		l.text = "%s   ·   %s\n%s" % [nm, tr(str(d.get("desc", ""))), status]
		b.text = tr("Build %s") % nm
		b.disabled = why2 != ""
