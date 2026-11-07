class_name UpgradesScreen
extends CanvasLayer
## One place for every upgrade: tabs Patch, Bots, Trade, Hub, Research, Rockets and Cosmetics,
## a responsive grid of UpgradeCards, live currency, controller tab switching.

signal closed

# l10n:begin
const TABS: Array[Dictionary] = [
	{"id": "patch", "name": "Lumi"},
	{"id": "bots", "name": "Bots"},
	{"id": "trade", "name": "Trade"},
	{"id": "hub", "name": "Hub"},
	{"id": "research", "name": "Research"},
	{"id": "rockets", "name": "Rockets"},
	{"id": "cosmetics", "name": "Cosmetics"},
	{"id": "contracts", "name": "Contracts"},
	{"id": "builder", "name": "Builder"},  # [drones] robot builder
]
# l10n:end

var is_open: bool = false
var _root: Control
var _grid: GridContainer
var _cards: Array[UpgradeCard] = []
var _currency: Label
var _tab_buttons: Array[Button] = []
var _tab: String = "patch"
var _refresh_t: float = 0.0
var _trade_t: float = 0.0
var _cosmetics: CosmeticsPanel  # [skins] design picker (focus its worn card first)
var _close_btn: Button
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
	dim.color = Color(0.02, 0.025, 0.03, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 36)
	_root.add_child(mc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.075, 0.08, 0.09, 0.96), Color(1, 1, 1, 0.1), 1, 10, 18))
	mc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	header.add_child(UITheme.label(tr("UPGRADES"), 34, UITheme.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	header.add_child(UIIcon.new("cube", 40, UITheme.GOLD))
	_currency = UITheme.label("0", 32, UITheme.GOLD)
	header.add_child(_currency)
	var close := Button.new()
	Settings.bind_text(close, func() -> String: return tr("Close  [%s]") % Settings.glyph("open_upgrades"))  # [deck]
	close.custom_minimum_size = Vector2(150, 48)
	close.pressed.connect(close_screen)
	_close_btn = close
	header.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for t: Dictionary in TABS:
		var b := Button.new()
		var live: bool = t["id"] in ["patch", "bots", "trade", "hub", "research", "rockets", "cosmetics", "contracts", "builder"]  # [drones]
		b.text = tr(str(t["name"])) if live else tr("%s (soon)") % tr(str(t["name"]))
		b.disabled = not live
		b.pressed.connect(_set_tab.bind(str(t["id"])))
		b.custom_minimum_size = Vector2(88, 44)  # [deck] 8 tabs fit 1280x800 at 110% interface scale
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true  # [vqa] long German / pseudo tab names shrink with an ellipsis, never widen the panel
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = b.text
		b.focus_mode = Control.FOCUS_NONE
		tabs.add_child(b)
		_tab_buttons.append(b)
	_style_tabs()
	tabs.add_child(PromptLabel.new("  {ui_tab_prev}{ui_tab_next}", 13))  # [deck] tab-switch glyphs
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true  # [deck] D-pad focus scrolls the grid
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
	if _tab == "contracts":  # [events] contracts board + token shop
		_grid.columns = 1
		var cnp := ContractsPanel.new()
		cnp.world = fleet.world if fleet else null
		_grid.add_child(cnp)
		return
	if _tab == "builder":  # [drones] robot builder
		_grid.columns = 1
		var bp := BuilderPanel.new()
		bp.fleet = fleet
		_grid.add_child(bp)
		return
	if _tab == "cosmetics":
		_grid.columns = 1
		var cp := CosmeticsPanel.new()
		cp.world = fleet.world if fleet else null
		_grid.add_child(cp)
		_cosmetics = cp  # [skins]
		return
	if _tab == "hub":
		_grid.columns = 1
		var hp := HubPanel.new()
		hp.hub = hub
		_grid.add_child(hp)
		_hub_panel = hp
		return
	if _tab == "rockets":
		_grid.columns = 1
		var rp := RocketsPanel.new()
		rp.world = fleet.world if fleet else null
		rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(rp)
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
	_relayout.call_deferred()  # [deck] again once the cards' minimum widths are known


func _set_tab(id: String) -> void:
	if id == _tab:
		return
	_tab = id
	_style_tabs()
	Audio.play("click", 1.1, -8.0)
	_populate()
	_trade_t = 0.0
	_refresh_all()
	_focus_default.call_deferred()


## Highlights the active tab button (same amber "on" style as the Codex tabs).
func _style_tabs() -> void:
	for i: int in mini(TABS.size(), _tab_buttons.size()):
		var on: bool = TABS[i]["id"] == _tab
		var b: Button = _tab_buttons[i]
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.2, 0.15, 0.07, 0.9) if on else UITheme.TEAL, UITheme.GOLD if on else UITheme.RUST, 1, 6, 8))
		b.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.CREAM)


## Gives controller/keyboard players a focused control on every tab. The old tab's children are
## only queue_freed, so freed or queued nodes are skipped.
func _focus_default() -> void:
	if not is_open:
		return
	_wire_focus()
	if _tab == "research":
		if is_instance_valid(_research) and not _research.is_queued_for_deletion():
			_research.focus_first()
		return
	var target: Control = null
	if not _cards.is_empty() and is_instance_valid(_cards[0]):
		target = _cards[0].first_button()
	elif not _robot_cards.is_empty() and is_instance_valid(_robot_cards[0]):
		target = _robot_cards[0].first_button()
	elif _tab == "trade" and is_instance_valid(_trade):
		target = _trade.first_button()
	elif _tab == "cosmetics" and is_instance_valid(_cosmetics) and not _cosmetics.is_queued_for_deletion():  # [skins]
		target = _cosmetics.first_button()
	if target == null or not _focusable(target, true):
		target = _first_focusable(_grid, false)
	if target == null:
		target = _first_focusable(_grid, true)
	if target == null:
		target = _close_btn
	if target:
		target.grab_focus()


## [deck] Card grids get explicit D-pad neighbours (Godot's search misses other cards).
var _focus_sig: String = ""


func _wire_focus() -> void:
	if not _tab in ["patch", "bots", "hub"]:
		return
	var sig: String = FocusGrid.signature(_grid) + "|%d" % _grid.columns
	if sig != _focus_sig:
		_focus_sig = sig
		FocusGrid.wire(_grid, _close_btn)
		var first: Control = FocusGrid._focusables(_grid)[0] if not FocusGrid._focusables(_grid).is_empty() else null
		if first:
			_close_btn.focus_neighbor_bottom = _close_btn.get_path_to(first)


func _focusable(c: Control, allow_disabled: bool) -> bool:
	if not is_instance_valid(c) or c.is_queued_for_deletion() or not c.is_visible_in_tree():
		return false
	if c.focus_mode == Control.FOCUS_NONE:
		return false
	return allow_disabled or not (c is BaseButton and (c as BaseButton).disabled)


func _first_focusable(root: Node, allow_disabled: bool) -> Control:
	for child: Node in root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Control and _focusable(child as Control, allow_disabled):
			return child as Control
		var f: Control = _first_focusable(child, allow_disabled)
		if f:
			return f
	return null


func _relayout() -> void:
	# Single-panel tabs fill the width; only card grids reflow.
	if _tab in ["research", "cosmetics", "hub", "trade", "rockets", "contracts", "builder"]:  # [drones] builder
		_grid.columns = 1
		return
	var w: float = _root.size.x - 110.0
	# [deck] Never more columns than the widest card allows (no clipping at 1280x800 / 110%).
	var min_w: float = 350.0
	for c: Node in _grid.get_children():
		if c is Control and not c.is_queued_for_deletion():
			min_w = maxf(min_w, (c as Control).get_combined_minimum_size().x + 14.0)
	_grid.columns = clampi(int(w / min_w), 1, 4)


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
	_trade_t = 0.0
	_focus_default.call_deferred()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	# Handled here (before GUI focus navigation) because Tab is also ui_focus_next.
	if event.is_action_pressed("open_upgrades"):
		close_screen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		var order: Array[String] = []
		for t: Dictionary in TABS:
			order.append(str(t["id"]))
		var i: int = maxi(0, order.find(_tab))
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
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
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
		_wire_focus()
	_trade_t -= delta
	if _trade_t <= 0.0:
		_trade_t = 0.5
		if _tab == "trade" and is_instance_valid(_trade):
			_trade.refresh()


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
	if _tab == "bots" and is_instance_valid(_alloc):
		_alloc.refresh()
	if _tab == "hub" and is_instance_valid(_hub_panel):
		_hub_panel.refresh()
