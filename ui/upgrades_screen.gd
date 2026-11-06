class_name UpgradesScreen
extends CanvasLayer
## One place for every upgrade: tabs (Patch now; Bots, Hub, Research, Rockets, Cosmetics later),
## a responsive grid of UpgradeCards, live currency, controller tab switching.

signal closed

const TABS: Array[Dictionary] = [
	{"id": "patch", "name": "Patch"},
	{"id": "bots", "name": "Bots"},
	{"id": "trade", "name": "Trade"},
	{"id": "hub", "name": "Hub"},
	{"id": "research", "name": "Research"},
	{"id": "rockets", "name": "Rockets"},
	{"id": "cosmetics", "name": "Cosmetics"},
]

var is_open: bool = false
var _root: Control
var _grid: GridContainer
var _cards: Array[UpgradeCard] = []
var _currency: Label
var _tab_buttons: Array[Button] = []
var _tab: String = "patch"
var _refresh_t: float = 0.0
var _robot_cards: Array[RobotCard] = []
var fleet: Fleet
var _trade: TradePanel
var _hub_panel: HubPanel
var hub: Hub
var _alloc: AllocationBoard
var _research: ResearchPanel
var build_at: Callable = func() -> Vector3: return Vector3.ZERO


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DevHooks.has("tab"):
		_tab = DevHooks.get_s("tab", "patch")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.04, 0.12, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 36)
	_root.add_child(mc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.17, 0.12, 0.24, 0.97), UITheme.RUST, 5, 22, 18))
	mc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	header.add_child(UITheme.label("UPGRADES", 34, UITheme.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	header.add_child(UIIcon.new("cube", 40, UITheme.GOLD))
	_currency = UITheme.label("0", 32, UITheme.GOLD)
	header.add_child(_currency)
	var close := Button.new()
	close.text = "Close  [Tab]"
	close.custom_minimum_size = Vector2(150, 48)
	close.pressed.connect(close_screen)
	header.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for t: Dictionary in TABS:
		var b := Button.new()
		var live: bool = t["id"] in ["patch", "bots", "trade", "hub", "research", "cosmetics"]
		b.text = t["name"] if live else "%s (soon)" % t["name"]
		b.disabled = not live
		b.pressed.connect(_set_tab.bind(str(t["id"])))
		b.custom_minimum_size = Vector2(120, 44)
		b.focus_mode = Control.FOCUS_NONE
		tabs.add_child(b)
		_tab_buttons.append(b)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	_populate()
	_root.resized.connect(_relayout)
	_relayout()
	_root.visible = false


func _populate() -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_cards.clear()
	_robot_cards.clear()
	if _tab == "research":
		_grid.columns = 1
		_research = ResearchPanel.new()
		_grid.add_child(_research)
		return
	if _tab == "cosmetics":
		_grid.columns = 1
		var cp := CosmeticsPanel.new()
		cp.world = fleet.world if fleet else null
		_grid.add_child(cp)
		return
	if _tab == "hub":
		_grid.columns = 1
		var hp := HubPanel.new()
		hp.hub = hub
		_grid.add_child(hp)
		_hub_panel = hp
		return
	if _tab == "trade":
		_grid.columns = 1
		var tp := TradePanel.new()
		tp.fleet = fleet
		tp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(tp)
		_trade = tp
		return
	_relayout()
	if _tab == "bots" and fleet:
		var ab := AllocationBoard.new()
		ab.fleet = fleet
		ab.world = fleet.world
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(ab)
		_alloc = ab
		for rid: String in Economy.robot_order:
			var rc := RobotCard.new(rid, fleet, build_at)
			rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_grid.add_child(rc)
			_robot_cards.append(rc)
	for id: String in Economy.upgrade_order:
		if str(Economy.upgrade_defs[id].get("tab", "patch")) != _tab:
			continue
		var card := UpgradeCard.new(id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.bought.connect(func(_i: String, _n: int) -> void: _refresh_all())
		_grid.add_child(card)
		_cards.append(card)


func _set_tab(id: String) -> void:
	if id == _tab:
		return
	_tab = id
	Audio.play("click", 1.1, -8.0)
	_populate()
	_refresh_all()


func _relayout() -> void:
	if _tab == "research":
		_grid.columns = 1
		return
	if _tab == "cosmetics":
		_grid.columns = 1
		var cp := CosmeticsPanel.new()
		cp.world = fleet.world if fleet else null
		_grid.add_child(cp)
		return
	if _tab == "hub":
		_grid.columns = 1
		var hp := HubPanel.new()
		hp.hub = hub
		_grid.add_child(hp)
		_hub_panel = hp
		return
	if _tab == "trade":
		_grid.columns = 1
		return
	var w: float = _root.size.x - 110.0
	_grid.columns = clampi(int(w / 350.0), 1, 4)


func open_screen() -> void:
	is_open = true
	_root.visible = true
	_refresh_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("click", 1.0, -6.0)
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.15)
	if not _cards.is_empty():
		_cards[0].first_button().call_deferred("grab_focus")
	elif _tab == "research" and is_instance_valid(_research):
		_research.focus_first.call_deferred()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		var order: Array[String] = ["patch", "bots", "hub", "trade", "research", "cosmetics"]
		var i: int = order.find(_tab)
		_set_tab(order[(i + (1 if event.is_action_pressed("ui_tab_next") else order.size() - 1)) % order.size()])
		get_viewport().set_input_as_handled()


func close_screen() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	EventBus.ui_modal_changed.emit(false)
	Audio.play("click", 0.8, -6.0)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("open_upgrades") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_screen()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open:
		return
	_currency.text = Settings.fmt(GameState.get_currency("cubes"))
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		_refresh_all()


func _refresh_all() -> void:
	var best: UpgradeCard = null
	var best_score: float = 0.0
	for c: UpgradeCard in _cards:
		c.is_best_value = false
		var s: float = c.value_score()
		if s > best_score:
			best_score = s
			best = c
	if best:
		best.is_best_value = true
	for c: UpgradeCard in _cards:
		c.refresh()
	for rc: RobotCard in _robot_cards:
		rc.refresh()
	if _tab == "trade" and is_instance_valid(_trade) and Engine.get_process_frames() % 60 == 0:
		_trade.refresh()
	if _tab == "bots" and is_instance_valid(_alloc):
		_alloc.refresh()
	if _tab == "hub" and is_instance_valid(_hub_panel):
		_hub_panel.refresh()
