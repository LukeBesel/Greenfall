class_name FabricatorPanel
extends VBoxContainer
## [orbC] The Bot Fabricator's one panel (top of the workbench Bots tab once it is built): one
## status line, one row per robot type with its share of the mix (- n +) and the cost of one robot,
## and a Pause / Resume button. Nothing else (owner: simple UI, nothing busy).

var fab: BotFabricator
var _status: Label
var _rows: VBoxContainer
var _pause: Button
var _counts: Dictionary = {}  # type -> Label
var _t: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(BenchKit.caps(tr("Bot Fabricator")))
	_status = BenchKit.body("", UITheme.CREAM)
	add_child(_status)
	add_child(BenchKit.body(tr("Mix: how many of each it builds in turn. New robots go to the hub that needs them most."), UITheme.MUTED, BenchKit.SMALL_SIZE))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)
	_pause = BenchKit.soft_button("")
	_pause.pressed.connect(func() -> void:
		if fab:
			fab.set_paused(not fab.paused())
			Audio.play("click", 1.0, -8.0)
		refresh())
	add_child(_pause)
	_build_rows()
	refresh()


func _build_rows() -> void:
	for c: Node in _rows.get_children():
		c.queue_free()
	_counts.clear()
	for t: String in BotFabricator.types():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rows.add_child(row)
		var nm: Label = BenchKit.body(tr(str(Economy.robots.get(t, {}).get("name", t))), UITheme.CREAM)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var c: Dictionary = BotFabricator.robot_cost(t)
		var cost := BenchKit.CostRow.new(18, 16)
		cost.set_cost(c)
		row.add_child(cost)
		row.add_child(_step_button("-", t, -1))
		var n: Label = BenchKit.body("0", Color.WHITE)
		n.custom_minimum_size.x = 28
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(n)
		_counts[t] = n
		row.add_child(_step_button("+", t, 1))


func _step_button(text: String, t: String, d: int) -> Button:
	var b := BenchKit.soft_button(text)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size.x = 44
	b.pressed.connect(func() -> void:
		if fab:
			fab.set_weight(t, fab.weight(t) + d)
			Audio.play("click", 1.1 if d > 0 else 0.9, -8.0)
		refresh())
	return b


func refresh() -> void:
	if fab == null or _status == null:
		return
	_status.text = fab.status_line()
	for t: String in _counts:
		(_counts[t] as Label).text = str(fab.weight(t))
	_pause.text = tr("Resume") if fab.paused() else tr("Pause")


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()
