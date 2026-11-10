class_name BuildPanel
extends VBoxContainer
## [ui3] Workbench "Build" tab: one-time buildings only (owner: "one-time buildings go on a
## separate tab"). The list is camp2's single source, HubBuilds.available(world, "one_time")
## (data/builds.json): only unlocked, not-yet-built things, in order; a building drops off once it
## stands and joins the small "Built" line. Building goes through HubBuilds.build (pay, place,
## reveal; the first Signal Jammer is one of them). Also the controls of machines that already stand (bale stations' route / move).

var world: Node
var _list: VBoxContainer
var _rows: Dictionary = {}  # id -> BenchRow
var _empty: Label
var _built: Label
var _stations: StationsPanel
var _ops: VBoxContainer
var _t: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	add_child(_list)
	_empty = BenchKit.body(tr("Nothing new to build right now. New buildings unlock as you play."), UITheme.MUTED)
	add_child(_empty)
	_built = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
	add_child(_built)
	# Machines that stand: their few controls (route, move).
	_ops = VBoxContainer.new()
	_ops.add_theme_constant_override("separation", 10)
	add_child(_ops)
	_stations = StationsPanel.new()
	_ops.add_child(_stations)
	for g: Node in _stations.find_children("*", "GridContainer", true, false):
		(g as Control).visible = false  # machine upgrades are in the Upgrades tab
	refresh()


func _ledger() -> Node:
	return get_tree().get_first_node_in_group("ledger") if is_inside_tree() else null


func _world() -> Node:
	if world:
		return world
	return get_tree().current_scene if is_inside_tree() else null


func first_button() -> Button:
	for r: Node in _list.get_children():
		if r is BenchRow and not (r as BenchRow).button().disabled:
			return (r as BenchRow).button()
	for r: Node in _list.get_children():
		if r is BenchRow:
			return (r as BenchRow).button()
	return null


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


## The Build tab has something to show (for the tab's visibility).
static func has_content(w: Node) -> bool:
	return not HubBuilds.available(w, "one_time").is_empty() or not HubBuilds.built_names(w).is_empty()


func refresh() -> void:
	var w: Node = _world()
	var items: Array = HubBuilds.available(w, "one_time")
	var want: Array[String] = []
	for e: Dictionary in items:
		want.append(str(e["id"]))
	for id: String in _rows.keys():
		if not (id in want):
			var r: BenchRow = _rows[id]
			_list.remove_child(r)
			r.queue_free()
			_rows.erase(id)
	for i: int in items.size():
		var e: Dictionary = items[i]
		var id: String = str(e["id"])
		var row: BenchRow = _rows.get(id)
		if row == null:
			row = BenchRow.new()
			_list.add_child(row)
			_rows[id] = row
			row.pressed.connect(func() -> void:
				if HubBuilds.build(_world(), id):
					Audio.play("buy", 0.95, -2.0)
					EventBus.ui_modal_changed.emit(false)
				else:
					Audio.play("buzz", 1.2, -8.0)
				refresh())
		_list.move_child(row, i)
		var reason: String = str(e.get("reason", ""))
		row.show_entry(tr(str(e.get("name", id))), str(e.get("tier", "")), tr(str(e.get("desc", ""))), e.get("cost", {}),
			tr("Build"), reason, HubBuilds.not_enough(reason))
	_empty.visible = items.is_empty()
	var names: Array[String] = []
	for n: String in HubBuilds.built_names(w):
		names.append(tr(n))
	_built.text = (tr("Built:  %s") % "  ·  ".join(names)) if not names.is_empty() else ""
	_built.visible = not names.is_empty()
	_stations.refresh()
