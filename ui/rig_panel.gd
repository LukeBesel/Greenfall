class_name RigPanel
extends VBoxContainer
## The workbench's "Rig" tab (systems/rigs.gd; design spec section 7): one column per slot on
## Lumi's body, every module of the slot in it. A row says what the module changes, both ways
## ("+60% chest size", "-8% speed"), and carries the one thing that can be done with it: build it
## from its plan, fit it, or take it off. A city's tool is marked with the waste it clears. A
## module whose plan has not arrived says which city brings it. Fitting is free, so the panel is
## for trying loadouts: the row that is fitted is lit, and the slot's heading names it.

const ROW_GAP: int = 10
const COL_GAP: int = 14
const NAME_SIZE: int = 20
const TEXT_SIZE: int = 18
const COL_MIN_W: float = 300.0

var world: Node
var _rigs: Rigs
var _cols: HBoxContainer
var _buttons: Dictionary[String, Button] = {}
var _first: Button


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	head.add_child(BenchKit.title(tr("Rig")))
	var note: Label = BenchKit.body(tr("One module in each slot. Swapping is free. A city's tool must be fitted to clear that city's waste."), UITheme.CREAM, TEXT_SIZE)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(note)
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", COL_GAP)
	_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_cols)
	_rigs = Rigs.of(world)
	if _rigs != null:
		_rigs.changed.connect(_rebuild)
	EventBus.currency_changed.connect(_on_currency_changed)
	_rebuild()


func _exit_tree() -> void:
	if _rigs != null and is_instance_valid(_rigs) and _rigs.changed.is_connected(_rebuild):
		_rigs.changed.disconnect(_rebuild)
	if EventBus.currency_changed.is_connected(_on_currency_changed):
		EventBus.currency_changed.disconnect(_on_currency_changed)


## The control a controller lands on when the tab opens.
func first_button() -> Control:
	return _first


func _on_currency_changed(_currency: String, _amount: BigNum) -> void:
	for id: String in _buttons:
		if _rigs.state(id) == Rigs.PLAN:
			_buttons[id].disabled = not _rigs.can_build(id)


func _rebuild() -> void:
	var focused: String = ""
	for id: String in _buttons:
		if is_instance_valid(_buttons[id]) and _buttons[id].has_focus():
			focused = id
	for c: Node in _cols.get_children():
		_cols.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_first = null
	if _rigs == null or not _rigs.enabled():
		_cols.add_child(BenchKit.body(tr("No rig on this world."), UITheme.CREAM, TEXT_SIZE))
		return
	for slot: String in _rigs.slots():
		_cols.add_child(_column(slot))
	if focused != "" and _buttons.has(focused):
		_buttons[focused].grab_focus.call_deferred()


func _column(slot: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ROW_GAP)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(COL_MIN_W, 0)
	var fitted: String = _rigs.fitted(slot)
	var head: Array = BenchKit.card(Color(BenchKit.HOLO, 0.5))
	var hb: VBoxContainer = head[1]
	hb.add_theme_constant_override("separation", 2)
	hb.add_child(BenchKit.caps(tr(_rigs.slot_name(slot))))
	hb.add_child(UITheme.label(tr(_rigs.name_of(fitted)) if fitted != "" else tr("Empty"), NAME_SIZE, Color.WHITE if fitted != "" else UITheme.MUTED))
	col.add_child(head[0])
	for id: String in _rigs.modules_of(slot):
		col.add_child(_row(id))
	return col


func _row(id: String) -> Control:
	var state: String = _rigs.state(id)
	var accent: Color = Color(BenchKit.HOLO, 0.9) if state == Rigs.FITTED else Color(1, 1, 1, 0.14)
	var card: Array = BenchKit.card(accent)
	var body: VBoxContainer = card[1]
	body.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	var name_l: Label = UITheme.label(tr(_rigs.name_of(id)), NAME_SIZE, UITheme.MUTED if state == Rigs.LOCKED else Color.WHITE)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	top.add_child(name_l)
	if state == Rigs.FITTED:
		top.add_child(BenchKit.caps(tr("Fitted")))
	elif _rigs.is_tool(id):
		top.add_child(BenchKit.caps(tr("Tool"), UITheme.GOLD))
	if state == Rigs.LOCKED:
		body.add_child(BenchKit.body(_rigs.lock_hint(id), UITheme.MUTED, TEXT_SIZE))
		return card[0]
	body.add_child(BenchKit.body(tr(str(_rigs.module(id).get("desc", ""))), UITheme.CREAM, TEXT_SIZE))
	for line: String in _rigs.effect_lines(id):
		# A loss is amber and starts with a minus: colour is never the only sign.
		body.add_child(UITheme.label(line, TEXT_SIZE, UITheme.GOLD if line.begins_with("-") else UITheme.GREEN))
	body.add_child(_action(id, state))
	return card[0]


func _action(id: String, state: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var b: Button
	match state:
		Rigs.FITTED:
			b = BenchKit.soft_button(tr("Take off"))
			b.pressed.connect(_on_take_off.bind(_rigs.slot_of(id)))
		Rigs.OWNED:
			b = BenchKit.big_button(tr("Fit"))
			b.pressed.connect(_on_fit.bind(id))
		_:
			b = BenchKit.big_button(tr("Build"))
			b.disabled = not _rigs.can_build(id)
			b.pressed.connect(_on_build.bind(id))
	row.add_child(b)
	if state == Rigs.PLAN:
		var cost := BenchKit.CostRow.new()
		cost.set_cost(_rigs.cost_of(id))
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost)
	_buttons[id] = b
	if _first == null:
		_first = b
	return row


func _on_fit(id: String) -> void:
	if _rigs.fit(id):
		Audio.play("click", 0.8, -4.0)


func _on_take_off(slot: String) -> void:
	_rigs.unfit(slot)
	Audio.play("click", 1.2, -8.0)


func _on_build(id: String) -> void:
	if _rigs.build(id):
		Audio.play("click", 0.7, -2.0)
		_rigs.fit(id)
	else:
		Audio.play("buzz", 1.0, -10.0)
