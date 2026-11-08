class_name UpgradesScreen
extends CanvasLayer
## One place for every upgrade. [ui2] Seven tabs: Lumi, Bots, Hub, Research, Rockets, Requests and
## the Locker (Lumi's and the robots' looks; opens at hub level 3). Bigger text, one card style
## (ui/bench_kit.gd), costs shown with the currency icons, controller tab switching.
## Tabs can be gated by other systems: UpgradesScreen.set_tab_gate("contracts", func() -> bool)
## (a gated tab shows a lock and its hint until the gate opens).

signal closed

# l10n:begin
const TABS: Array[Dictionary] = [
	{"id": "patch", "name": "Upgrades"},  # [ui3] [ui6] everything with levels or tiers: Lumi, Base, Machines, Glim, Rocket
	{"id": "build", "name": "Build"},  # [ui3] [ui6] one-time buildings (HubBuilds): Yard, Machines, Story
	{"id": "bots", "name": "Bots"},
	{"id": "research", "name": "Research"},
	{"id": "contracts", "name": "Requests"},  # [money] contracts + world events (onboard gate)
]  # [ui6] the Locker is a yard build now (systems/camp/locker_cabinet.gd), not a tab
# l10n:end
## [ui2] Old tab ids (dev hooks, other branches) and where they went.
const TAB_ALIASES: Dictionary = {"cosmetics": "patch", "builder": "patch", "locker": "patch", "trade": "bots", "hub": "patch", "rockets": "patch"}  # [ui3] Hub and Rockets folded into Upgrades
const TAB_FONT: int = 19

## [ui2] id -> Callable() -> bool. A tab whose gate returns false is locked (see set_tab_gate).
static var _gates: Dictionary = {}
static var _gate_hints: Dictionary = {}


## Locks a tab until `open_fn` returns true; `hint` says how to open it (shown on the tab).
static func set_tab_gate(id: String, open_fn: Callable, hint: String = "") -> void:
	_gates[id] = open_fn
	_gate_hints[id] = hint


static func clear_tab_gate(id: String) -> void:
	_gates.erase(id)
	_gate_hints.erase(id)


static func tab_open(id: String) -> bool:
	var g: Variant = _gates.get(id)
	return not (g is Callable and (g as Callable).is_valid()) or bool((g as Callable).call())


## [ui2] data/workbench.json: when each tab appears (any condition). Opened tabs stay open.
static var _tab_cfg: Dictionary = {}


static func tab_conditions(id: String) -> Array:
	if _tab_cfg.is_empty():
		_tab_cfg = Economy.read_json("res://data/workbench.json").get("tabs", {})
	return _tab_cfg.get(id, [["always"]])


static func _cond_ok(c: Array, w: Node) -> bool:
	match str(c[0]):
		"always":
			return true
		"earned":
			return BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float() >= float(c[1])
		"stat":
			var v: Variant = GameState.stats.get(str(c[1]), 0.0)
			return (v is float or v is int) and float(v) >= float(c[2])
		"hub_level":
			var lv: int = int(GameState.world.get("hub_level", 1))
			if w and w.get("hub") != null:
				lv = maxi(lv, int(w.hub.level))
			return lv >= int(c[1]) or Achievements.best_hub_level() >= int(c[1])
		"flag":
			return bool(GameState.flags.get(str(c[1]), false))
		"builds":  # [ui3] something to build, or something built (camp2's HubBuilds)
			return BuildPanel.has_content(w if w else (Engine.get_main_loop() as SceneTree).current_scene)
	return false


## [ui2] Whether a tab is shown at all: a code gate (set_tab_gate) if one is set, else the data.
static func tab_visible(id: String, w: Node = null) -> bool:
	if DevHooks.has("bench-all"):
		return true
	if _gates.has(id):
		return tab_open(id)
	if id == "contracts" and not Contracts.unlocked():  # [onboard] the board opens later (base 3, 45 min)
		return false
	var seen: Array = GameState.flags.get("bench_tabs", [])
	if id in seen:
		return true
	for c: Variant in tab_conditions(id):
		if c is Array and _cond_ok(c, w):
			seen.append(id)
			GameState.flags["bench_tabs"] = seen
			return true
	return false

var is_open: bool = false
var _root: Control
var _grid: GridContainer
var _cards: Array[UpgradeCard] = []
var _currency: Label
var _parts_lbl: Label  # [money] the other two currencies, small, next to cubes
var _seeds_lbl: Label
var _tab_buttons: Array[Button] = []
var _tab: String = "patch"
var _refresh_t: float = 0.0
var _trade_t: float = 0.0
var _close_btn: Button
var _robot_cards: Array[RobotCard] = []
var fleet: Fleet
var _panel: Control  # [ui2] the single-panel tab's panel (focus target)
var _hub_panel: HubPanel
var hub: Hub
var _alloc: AllocationBoard
var build_at: Callable = func() -> Vector3: return Vector3.ZERO


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DevHooks.has("tab"):
		_tab = DevHooks.get_s("tab", "patch")
	_tab = str(TAB_ALIASES.get(_tab, _tab))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 36)
	_root.add_child(mc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BenchKit.holo(Color(BenchKit.HOLO, 0.5), Color(0.02, 0.035, 0.045, 0.9), 1.0, 12, 18))  # [ui2] glass + thin glowing frame
	mc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	header.add_theme_constant_override("separation", 8)
	var wt: Label = UITheme.label(tr("WORKBENCH"), 26, BenchKit.HOLO)
	wt.add_theme_constant_override("outline_size", 0)
	wt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wt)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	# [money] [ui2] The three currencies, same icons and size: cubes, parts, seeds.
	for cur: String in ["cubes", "parts", "seeds"]:
		header.add_child(CurrencyIcon.new(cur, 30.0))
		var l: Label = UITheme.label("0", 26, Color.WHITE)
		l.add_theme_constant_override("outline_size", 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(l)
		match cur:
			"cubes": _currency = l
			"parts": _parts_lbl = l
			_: _seeds_lbl = l
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(14, 0)
		header.add_child(gap)
	var close := Button.new()
	Settings.bind_text(close, func() -> String: return tr("Close  [%s]") % Settings.glyph("open_upgrades"))  # [deck]
	close.custom_minimum_size = Vector2(150, 44)
	BenchKit.style_action(close, BenchKit.HOLO)
	close.pressed.connect(close_screen)
	_close_btn = close
	header.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	for t: Dictionary in TABS:
		var b := Button.new()
		b.text = tr(str(t["name"]))
		b.add_theme_font_size_override("font_size", TAB_FONT)  # [ui2] bigger, readable tabs
		b.pressed.connect(_set_tab.bind(str(t["id"])))
		b.custom_minimum_size = Vector2(96, 50)  # [deck] [ui2] 7 tabs fit 1280x800 at 110% interface scale
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true  # [vqa] long German / pseudo tab names shrink with an ellipsis, never widen the panel
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = b.text
		b.focus_mode = Control.FOCUS_NONE
		tabs.add_child(b)
		# [vqa2] Share the row by how long each name is (short "Hub" gives room to a long
		# "Research"), so long translations fit before any of them needs the ellipsis.
		var fnt: Font = b.get_theme_font("font")
		var fsz: int = b.get_theme_font_size("font_size")
		if fnt:
			b.size_flags_stretch_ratio = maxf(1.0, (fnt.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x + 24.0) / 88.0)
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
		_grid.remove_child(c)  # [ui2] out of the tree now: no focus neighbours into a dying tab
		c.queue_free()
	_cards.clear()
	_robot_cards.clear()
	_panel = null
	_alloc = null
	var w: Node = fleet.world if fleet else null
	if not tab_open(_tab):  # [ui2] a gated tab: say how it opens
		_grid.columns = 1
		var c: Array = BenchKit.card(Color(1, 1, 1, 0.12))
		_grid.add_child(c[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		(c[1] as VBoxContainer).add_child(row)
		row.add_child(BenchKit.Glyph.new("lock", 52, UITheme.MUTED))
		row.add_child(BenchKit.body(str(_gate_hints.get(_tab, "")) if str(_gate_hints.get(_tab, "")) != "" else tr("Not open yet. Keep playing."), UITheme.CREAM, 20))
		return
	if _tab == "contracts":  # [events] contracts board + token shop
		_grid.columns = 1
		var cnp := ContractsPanel.new()
		cnp.world = w
		_grid.add_child(cnp)
		_panel = cnp
		return
	if _tab in ["patch", "build", "research", "bots"]:  # [ui6] [ui7] one list + one detail panel (ui/list_detail.gd)
		_grid.columns = 1
		var ld := ListDetail.new()
		ld.world = w
		match _tab:
			"patch":
				ld.provider = func() -> Array: return BenchLists.upgrades(w)
				ld.categories = BenchLists.UPGRADE_CATS
				ld.counter = BenchLists.upgrades_counter
			"build":
				ld.provider = func() -> Array: return BenchLists.builds(w)
				ld.categories = BenchLists.BUILD_CATS
				ld.counter = func() -> String: return BenchLists.builds_counter(w)
			"bots":  # [ui7] Build / Tiers / Fleet / Fabricator (ui/bench_bots.gd)
				var fl: Fleet = fleet
				var ba: Callable = build_at
				ld.provider = func() -> Array: return BenchBots.rows(fl, ba)
				ld.categories = BenchBots.CATS
				ld.counter = func() -> String: return BenchBots.counter(fl)
			"research":
				ld.provider = BenchLists.research
				ld.categories = BenchLists.research_cats()
				ld.counter = BenchLists.research_counter
		ld.custom_minimum_size = Vector2(0, maxf(_root.size.y - 300.0, 300.0))  # fits without scrolling the page
		_grid.add_child(ld)
		_panel = ld
		return
	_relayout()
	if _tab == "bots" and fleet:
		for rid: String in Economy.robot_order:
			var rc := RobotCard.new(rid, fleet, build_at)
			rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rc.goto_tab.connect(_set_tab)
			_grid.add_child(rc)
			_robot_cards.append(rc)
		if fleet.count("multibot") > 0:  # [ui2] the Multibot job board only once there are multibots
			var ab := AllocationBoard.new()
			ab.fleet = fleet
			ab.world = fleet.world
			ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_grid.add_child(ab)
			_alloc = ab
	for id: String in Economy.upgrade_order:
		if str(Economy.upgrade_defs[id].get("tab", "patch")) != _tab or _tab == "bots":  # [ui2] bot upgrades live on their RobotCard
			continue
		var rs: String = str(Economy.upgrade_defs[id].get("requires_station", ""))
		if rs != "" and not Stations.built_in_state(rs):
			continue  # [camp] machine upgrades only show once the machine stands in the yard
		var card := UpgradeCard.new(id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.bought.connect(func(_i: String, _n: int) -> void: _refresh_all())
		_grid.add_child(card)
		_cards.append(card)
	_relayout.call_deferred()  # [deck] again once the cards' minimum widths are known


func _set_tab(id: String) -> void:
	id = str(TAB_ALIASES.get(id, id))
	if id == _tab:
		return
	_tab = id
	_close_btn.focus_neighbor_bottom = NodePath()  # [ui2] the old tab's buttons are going away
	_focus_sig = ""
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
		var tid: String = str(TABS[i]["id"])
		b.visible = on or tab_visible(tid, fleet.world if fleet else null)  # [ui2] tabs appear once they are open
		b.tooltip_text = tr(str(TABS[i]["name"]))
		# [ui2] Holo tabs: the active one is a lit glass pill, the rest are quiet text.
		b.add_theme_stylebox_override("normal", BenchKit.holo(Color(BenchKit.HOLO, 0.8), Color(0.1, 0.25, 0.32, 0.55), 1.0, 8, 8) if on else BenchKit.holo(Color(BenchKit.HOLO, 0.12), Color(0, 0, 0, 0.2), 0.0, 8, 8))
		b.add_theme_stylebox_override("hover", BenchKit.holo(Color(BenchKit.HOLO, 0.5), Color(0.08, 0.18, 0.22, 0.5), 0.6, 8, 8))
		b.add_theme_color_override("font_color", BenchKit.HOLO.lightened(0.5) if on else UITheme.MUTED)
		b.add_theme_color_override("font_hover_color", Color.WHITE)


## Gives controller/keyboard players a focused control on every tab. The old tab's children are
## only queue_freed, so freed or queued nodes are skipped.
func _focus_default() -> void:
	if not is_open:
		return
	_wire_focus()
	var target: Control = null
	if not _cards.is_empty() and is_instance_valid(_cards[0]):
		target = _cards[0].first_button()
	elif not _robot_cards.is_empty() and is_instance_valid(_robot_cards[0]):
		target = _robot_cards[0].first_button()
	elif is_instance_valid(_panel) and not _panel.is_queued_for_deletion() and _panel.has_method("first_button"):  # [ui2]
		target = _panel.call("first_button") as Control
	if target == null or not _focusable(target, true):
		target = _first_focusable(_grid, false)
	if target == null or (target is BaseButton and (target as BaseButton).disabled):
		target = _close_btn  # [ui6] a disabled button can't take focus: Close, not nothing
	if target:
		target.grab_focus()


## [deck] Card grids get explicit D-pad neighbours (Godot's search misses other cards).
var _focus_sig: String = ""


func _wire_focus() -> void:
	if not _tab.is_empty():  # [ui3] [ui6] [ui7] every tab is a list that links its own rows
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
	if _tab != "bots":  # [ui2] [ui3] single-panel tabs (Upgrades lays out its own sections)
		_grid.columns = 1
		return
	var w: float = _root.size.x - 110.0
	# [deck] Never more columns than the widest card allows (no clipping at 1280x800 / 110%).
	var min_w: float = 420.0 if _tab == "bots" else 350.0
	for c: Node in _grid.get_children():
		if c is Control and not c.is_queued_for_deletion():
			min_w = maxf(min_w, (c as Control).get_combined_minimum_size().x + 14.0)
	_grid.columns = clampi(int(w / min_w), 1, 3 if _tab == "bots" else 4)


func open_screen() -> void:
	is_open = true
	if _tab == "contracts" and not Contracts.unlocked():  # [onboard]
		_tab = "patch"
		_populate()
	_style_tabs()  # [onboard] the Requests tab appears once the board is open
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
			if str(t["id"]) == _tab or tab_visible(str(t["id"]), fleet.world if fleet else null):  # [ui2] skip hidden tabs
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
	_parts_lbl.text = Settings.fmt(GameState.get_currency("parts"))
	_seeds_lbl.text = Settings.fmt(GameState.get_currency("seeds"))
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		_refresh_all()
		_wire_focus()
	_trade_t -= delta
	if _trade_t <= 0.0:
		_trade_t = 1.0
		_style_tabs()  # [ui2] gates can open while the screen is up

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

