class_name UpgradesPanel
extends VBoxContainer
## [ui3] Workbench "Upgrades" tab: everything with levels or tiers, grouped simply.
##   Lumi      - Lumi's upgrade cards (upgrades.json, tab "patch").
##   Base      - the next hub level card and the next tier of each tiered build (camp2's
##               HubBuilds.available(world, "tiered"): trash bin, signal tower, air scrubbers,
##               signal jammers, ...).
##   Machines  - machine upgrades (tab "hub", e.g. Belt Drive) once their machine stands.
##   Glim      - [buddy] Glim's upgrade tracks (ui/glim_bench.gd), once he's found.
##   Rocket    - the rocket stages, once the pad is open.
## A section with nothing in it is not shown.

signal card_bought

var world: Node
var hub: Hub
var cards: Array[UpgradeCard] = []
var _base: VBoxContainer
var _tier_list: VBoxContainer
var _tier_rows: Dictionary = {}  # id -> BenchRow
var _hub_panel: HubPanel
var _grids: Array[GridContainer] = []
var _rockets: RocketsPanel
var _rocket_head: Label
var _t: float = 0.0
var _glim: GlimBench  # [buddy]


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_card_section(tr("Lumi"), "patch")
	_glim = GlimBench.new()  # [buddy] Glim's tracks, once he's found
	_glim.world = world
	add_child(_glim)
	_base = VBoxContainer.new()
	_base.add_theme_constant_override("separation", 10)
	add_child(_base)
	_base.add_child(BenchKit.caps(tr("Base")))
	if hub:
		_hub_panel = HubPanel.new()
		_hub_panel.hero_only = true
		_hub_panel.hub = hub
		_base.add_child(_hub_panel)
	_tier_list = VBoxContainer.new()
	_tier_list.add_theme_constant_override("separation", 10)
	_base.add_child(_tier_list)
	_add_card_section(tr("Machines"), "hub")
	_rocket_head = BenchKit.caps(tr("Rocket"))
	add_child(_rocket_head)
	_rockets = RocketsPanel.new()
	_rockets.world = world
	_rockets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rockets)
	resized.connect(_relayout)
	refresh()
	_relayout.call_deferred()


func _add_card_section(title: String, tab: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(BenchKit.caps(title))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	box.add_child(g)
	_grids.append(g)
	for id: String in Economy.upgrade_order:
		var d: Dictionary = Economy.upgrade_defs[id]
		if str(d.get("tab", "patch")) != tab:
			continue
		var rs: String = str(d.get("requires_station", ""))
		if rs != "" and not Stations.built_in_state(rs):
			continue  # [camp] machine upgrades only once the machine stands
		var card := UpgradeCard.new(id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.bought.connect(func(_i: String, _n: int) -> void: card_bought.emit())
		g.add_child(card)
		cards.append(card)
	box.visible = g.get_child_count() > 0


func _relayout() -> void:
	var cols: int = clampi(int((size.x + 12.0) / 372.0), 1, 3)
	for g: GridContainer in _grids:
		g.columns = cols


func first_button() -> Button:
	if not cards.is_empty():
		return cards[0].first_button()
	return _hub_panel.first_button() if _hub_panel else null


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


func _world() -> Node:
	if world:
		return world
	return hub.get_parent() if hub else (get_tree().current_scene if is_inside_tree() else null)


func refresh() -> void:
	if _hub_panel:
		_hub_panel.refresh()
	if _glim and _glim.is_inside_tree():  # [buddy]
		_glim.refresh()
	var w: Node = _world()
	var items: Array = HubBuilds.available(w, "tiered")
	var want: Array[String] = []
	for e: Dictionary in items:
		want.append(str(e["id"]))
	for id: String in _tier_rows.keys():
		if not (id in want):
			var old: BenchRow = _tier_rows[id]
			_tier_list.remove_child(old)
			old.queue_free()
			_tier_rows.erase(id)
	for i: int in items.size():
		var e: Dictionary = items[i]
		var id: String = str(e["id"])
		var row: BenchRow = _tier_rows.get(id)
		if row == null:
			row = BenchRow.new()
			_tier_list.add_child(row)
			_tier_rows[id] = row
			row.pressed.connect(func() -> void:
				if HubBuilds.build(_world(), id):
					Audio.play("buy", 0.95, -2.0)
				else:
					Audio.play("buzz", 1.2, -8.0)
				refresh())
		_tier_list.move_child(row, i)
		var reason: String = str(e.get("reason", ""))
		row.show_entry(tr(str(e.get("name", id))), str(e.get("tier", "")), tr(str(e.get("desc", ""))), e.get("cost", {}),
			tr("Upgrade"), reason, HubBuilds.not_enough(reason))
	var rockets_on: bool = UpgradesScreen.tab_visible("rockets", w)
	_rocket_head.visible = rockets_on
	_rockets.visible = rockets_on
