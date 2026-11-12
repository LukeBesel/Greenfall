class_name YardBuildsPanel
extends VBoxContainer
## [camp2] Hub tab section: BUILD. One list of every yard structure that can be built here now
## (systems/camp/hub_builds.gd, kind one_time): lean-to, generator, lamps, the first signal tower,
## compost press, CD player, bale stations, the first jammer. Only what
## is unlocked is listed; they drop off once built (a collapsed "Built:" line names them). Tiered
## things (trash bin levels, tower tiers, scrubbers, more jammers) are the Upgrades tab's (ui3).

var _list: VBoxContainer
var _built: Label
var _empty: Label
var _sig: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(BenchKit.caps(tr("Build")))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	add_child(_list)
	_empty = BenchKit.body(tr("Nothing new to build yet. More opens as the base grows."), UITheme.MUTED, BenchKit.SMALL_SIZE)
	add_child(_empty)
	_built = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
	add_child(_built)
	refresh()


func _hub_panel() -> HubPanel:
	var n: Node = get_parent()
	while n and not (n is HubPanel):
		n = n.get_parent()
	return n as HubPanel


func _world() -> Node:
	var hp: HubPanel = _hub_panel()
	if hp and hp.hub:
		return hp.hub.get_parent()
	return get_tree().current_scene if is_inside_tree() else null


func first_button() -> Button:
	for c: Node in _list.find_children("Btn", "Button", true, false):
		return c as Button
	return null


func refresh() -> void:
	if _list == null:
		return
	var w: Node = _world()
	var items: Array[Dictionary] = HubBuilds.available(w, "one_time")
	_sig = _sync(_list, items, _sig)
	_empty.visible = items.is_empty()
	var done: Array[String] = []
	for n: String in HubBuilds.built_names(w):
		done.append(tr(n))
	_built.visible = not done.is_empty()
	_built.text = tr("Built:  %s") % ",  ".join(done)


## Rebuilds a list's rows only when its entries change; costs and states refresh in place.
func _sync(box: VBoxContainer, items: Array[Dictionary], old_sig: String) -> String:
	var keys: Array[String] = []
	for e: Dictionary in items:
		keys.append("%s:%s" % [e["id"], e["name"]])
	var sig: String = ",".join(keys)
	if sig != old_sig:
		for c: Node in box.get_children():
			box.remove_child(c)
			c.queue_free()
		for e: Dictionary in items:
			box.add_child(_row(str(e["id"])))
	for i: int in mini(items.size(), box.get_child_count()):
		_fill(box.get_child(i), items[i])
	return sig


func _row(id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = id
	v.add_theme_constant_override("separation", 4)
	var l: Label = BenchKit.body("", UITheme.CREAM)
	l.name = "Text"
	v.add_child(l)
	var h := HBoxContainer.new()
	h.name = "Row"
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var b: Button = BenchKit.soft_button("")
	b.name = "Btn"
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.pressed.connect(func() -> void:
		if HubBuilds.build(_world(), id):
			Audio.play("buy", 0.95, -2.0)
			EventBus.ui_modal_changed.emit(false)
		else:
			Audio.play("buzz", 1.2, -8.0)
		var hp: HubPanel = _hub_panel()
		if hp:
			hp.refresh()
		else:
			refresh())
	h.add_child(b)
	var cr := BenchKit.CostRow.new(20, 18)
	cr.name = "Cost"
	h.add_child(cr)
	return v


func _fill(row: Node, e: Dictionary) -> void:
	var l: Label = row.get_node("Text")
	var b: Button = row.get_node("Row/Btn")
	var cr: BenchKit.CostRow = row.get_node("Row/Cost")
	var why: String = str(e["reason"])
	var head: String = tr(str(e["name"]))
	if str(e["tier"]) != "":
		head += "   ·   " + str(e["tier"])
	var line2: String = tr(str(e["desc"]))
	if why != "" and not HubBuilds.not_enough(why):
		line2 += "\n" + why
	l.text = "%s\n%s" % [head, line2]
	var upgrade: bool = str(e["kind"]) == "tiered"
	b.text = tr("Upgrade to %s") % tr(str(e["name"])) if upgrade else tr("Build %s") % tr(str(e["name"]))
	b.disabled = why != ""
	cr.set_cost(e["cost"], tr("Free"))
