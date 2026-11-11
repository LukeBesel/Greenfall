class_name RigPanel
extends VBoxContainer
## The workbench's "Rig" tab (systems/rigs.gd; design spec section 7): one column per slot on
## Lumi's body, every module of the slot in it. A row is short: the module's name, what it
## changes both ways ("+40% chest size  -8% speed") and the one thing that can be done with it:
## build it from its plan, fit it, or take it off. A city's tool is marked. A module whose plan
## has not arrived says which city brings it. The plate above the columns describes the row in
## focus (or under the pointer), so the rows stay short enough to compare a whole slot at once.
## Fitting is free, so the panel is for trying loadouts: the fitted row is lit.

const ROW_GAP: int = 8
const COL_GAP: int = 12
const NAME_SIZE: int = 20
const TEXT_SIZE: int = 18
const COL_MIN_W: float = 230.0
const DETAIL_MIN_H: float = 106.0
const ACTION_H: float = 46.0
const COST_ICON: float = 20.0
const HOST_PAD: float = 4.0

var world: Node
var _rigs: Rigs
var _detail_name: Label
var _detail_text: Label
var _cols: HBoxContainer
var _host: ScrollContainer
var _scroll: ScrollContainer
var _buttons: Dictionary[String, Button] = {}
var _costs: Dictionary[String, BenchKit.CostRow] = {}
var _first: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plate: Array = BenchKit.card(Color(BenchKit.HOLO, 0.4))
	(plate[0] as Control).custom_minimum_size.y = DETAIL_MIN_H
	var pb: VBoxContainer = plate[1]
	pb.add_theme_constant_override("separation", 2)
	_detail_name = BenchKit.caps("")
	pb.add_child(_detail_name)
	_detail_text = BenchKit.body("", UITheme.CREAM, TEXT_SIZE)
	pb.add_child(_detail_text)
	add_child(plate[0])
	# The columns scroll on their own, so the plate above them never scrolls away.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_scroll = scroll
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", COL_GAP)
	_cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cols)
	_host = _scroll_host()
	if _host != null:
		_host.resized.connect(_fit_height)
		_fit_height()
	_rigs = Rigs.of(world)
	if _rigs != null:
		_rigs.changed.connect(_rebuild)
	EventBus.currency_changed.connect(_on_currency_changed)
	_rebuild()
	_describe("")


func _exit_tree() -> void:
	if _rigs != null and is_instance_valid(_rigs) and _rigs.changed.is_connected(_rebuild):
		_rigs.changed.disconnect(_rebuild)
	if EventBus.currency_changed.is_connected(_on_currency_changed):
		EventBus.currency_changed.disconnect(_on_currency_changed)
	if _host != null and is_instance_valid(_host) and _host.resized.is_connected(_fit_height):
		_host.resized.disconnect(_fit_height)


## The workbench page this panel sits in scrolls; the panel takes exactly its height instead.
func _scroll_host() -> ScrollContainer:
	var at: Node = get_parent()
	while at != null and not (at is ScrollContainer):
		at = at.get_parent()
	return at as ScrollContainer


func _fit_height() -> void:
	custom_minimum_size.y = maxf(_host.size.y - HOST_PAD, 0.0)


## The control a controller lands on when the tab opens.
func first_button() -> Control:
	return _first


func _on_currency_changed(_currency: String, _amount: BigNum) -> void:
	for id: String in _costs:
		_buttons[id].disabled = not _rigs.can_build(id)
		_costs[id].set_cost(_rigs.cost_of(id))


## Fills the plate above the columns: a module's name and what it is ("" = how rigs work).
func _describe(id: String) -> void:
	if id == "" or _rigs == null:
		_detail_name.text = tr("Rig")
		_detail_text.text = tr("One module in each slot. Swapping is free. A city's tool must be fitted to clear that city's waste.")
		return
	_detail_name.text = "%s  ·  %s" % [tr(_rigs.slot_name(_rigs.slot_of(id))), tr(_rigs.name_of(id))]
	_detail_text.text = tr(str(_rigs.module(id).get("desc", "")))


func _rebuild() -> void:
	var focused: String = ""
	for id: String in _buttons:
		if is_instance_valid(_buttons[id]) and _buttons[id].has_focus():
			focused = id
	for c: Node in _cols.get_children():
		_cols.remove_child(c)
		c.queue_free()
	_buttons.clear()
	_costs.clear()
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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(BenchKit.caps(tr(_rigs.slot_name(slot))))
	var now: Label = UITheme.label(tr(_rigs.name_of(fitted)) if fitted != "" else tr("Empty"), TEXT_SIZE, Color.WHITE if fitted != "" else UITheme.MUTED)
	now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	now.clip_text = true
	head.add_child(now)
	col.add_child(head)
	for id: String in _rigs.modules_of(slot):
		col.add_child(_row(id))
	return col


func _row(id: String) -> Control:
	var state: String = _rigs.state(id)
	var accent: Color = Color(BenchKit.HOLO, 0.9) if state == Rigs.FITTED else Color(1, 1, 1, 0.14)
	var card: Array = BenchKit.card(accent)
	var body: VBoxContainer = card[1]
	body.add_theme_constant_override("separation", 4)
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
	var effects := HFlowContainer.new()
	effects.add_theme_constant_override("h_separation", 14)
	effects.add_theme_constant_override("v_separation", 0)
	body.add_child(effects)
	for line: String in _rigs.effect_lines(id):
		# A loss is amber and starts with a minus: colour is never the only sign.
		effects.add_child(UITheme.label(line, TEXT_SIZE, UITheme.GOLD if line.begins_with("-") else UITheme.GREEN))
	body.add_child(_action(id, state))
	(card[0] as Control).mouse_entered.connect(_describe.bind(id))
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
	b.custom_minimum_size = Vector2(96, ACTION_H)
	b.focus_entered.connect(_on_row_focused.bind(id, b))
	b.mouse_entered.connect(_describe.bind(id))
	row.add_child(b)
	if state == Rigs.PLAN:
		var cost := BenchKit.CostRow.new(COST_ICON, TEXT_SIZE)
		cost.show_missing = false  # the amount turns red when short; "need N" would not fit a column
		cost.set_cost(_rigs.cost_of(id))
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost)
		_costs[id] = cost
	_buttons[id] = b
	if _first == null:
		_first = b
	return row


## A row took focus: describe it and bring it into view. The scroll waits a frame, because focus
## can arrive before the panel has its size and a scroll made then would stay wrong.
func _on_row_focused(id: String, b: Button) -> void:
	_describe(id)
	await get_tree().process_frame
	if is_instance_valid(b) and b.is_inside_tree() and b.has_focus():
		_scroll.ensure_control_visible(b)


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
