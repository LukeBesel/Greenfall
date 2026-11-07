class_name StationsPanel
extends VBoxContainer
## Hub tab section for bale automation: build the Conveyor Feeder, Auto-baler and Recycler,
## set the conveyor's auto-route, and buy the station upgrades (upgrades.json tab "hub").

var _rows: Dictionary = {}  # id -> {"label": Label, "btn": Button}
var _route_btn: Button
var _stats: Label
var _relocate: Button
var _cards: Array[UpgradeCard] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label(tr("BALE AUTOMATION  &  RECYCLING"), 18, UITheme.CREAM))
	for id: String in ["conveyor", "auto_baler", "recycler"]:
		var l := UITheme.label("", 15, UITheme.CREAM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		add_child(l)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var b := Button.new()
		b.custom_minimum_size = Vector2(320, 44)
		b.pressed.connect(_on_build.bind(id))
		row.add_child(b)
		if id == "auto_baler":
			_relocate = Button.new()
			_relocate.custom_minimum_size = Vector2(240, 44)
			_relocate.text = tr("Move to frontier")
			_relocate.pressed.connect(func() -> void:
				var s: Stations = _stations()
				if s and s.relocate_baler():
					Audio.play("buy", 1.1, -4.0)
				else:
					Audio.play("buzz", 1.2, -8.0)
				refresh())
			row.add_child(_relocate)
		if id == "recycler":
			_route_btn = Button.new()
			_route_btn.custom_minimum_size = Vector2(320, 44)
			_route_btn.pressed.connect(func() -> void:
				var s: Stations = _stations()
				if s:
					s.cycle_route()
					Audio.play("click", 1.1, -6.0)
				refresh())
			add_child(_route_btn)
		_rows[id] = {"label": l, "btn": b}
	_stats = UITheme.label("", 14, UITheme.MUTED)
	add_child(_stats)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	for uid: String in Economy.upgrade_order:
		if str(Economy.upgrade_defs[uid].get("tab", "")) != "hub":
			continue
		var card := UpgradeCard.new(uid)
		grid.add_child(card)
		_cards.append(card)
	refresh()


func _stations() -> Stations:
	return Stations.of(self)


func _on_build(id: String) -> void:
	var s: Stations = _stations()
	if s and s.build(id):
		EventBus.ui_modal_changed.emit(false)
	else:
		Audio.play("buzz", 1.2, -8.0)
	refresh()


func refresh() -> void:
	var s: Stations = _stations()
	if s == null:
		visible = false
		return
	visible = true
	for id: String in _rows:
		var d: Dictionary = s.def(id)
		var lab: Label = _rows[id]["label"]
		var btn: Button = _rows[id]["btn"]
		var reason: String = s.block_reason(id)
		var status: String = ""
		if s.built(id):
			status = tr("Built.")
		elif reason.begins_with(tr("Requires research: %s.").get_slice("%", 0)) or reason.begins_with(tr("Requires hub level %d.").get_slice("%", 0)):  # [l10n]
			status = reason
		else:
			status = tr("Needs %s") % HubPanel.cost_text(d.get("cost", {}))
		lab.text = "%s   ·   %s\n%s" % [tr(str(d.get("name", id))), tr(str(d.get("desc", ""))), status]
		btn.text = (tr("%s built") % tr(str(d.get("name", id)))) if s.built(id) else tr("Build %s") % tr(str(d.get("name", id)))
		btn.disabled = reason != ""
	_relocate.visible = s.baler != null
	_relocate.disabled = s.baler == null or not s.baler.idle() or not Hub.can_pay(s.def("auto_baler").get("relocate_cost", {}))
	_route_btn.visible = s.recycler != null and s.conveyor != null
	_route_btn.text = tr("Auto-route: %s") % Stations.route_text(s.route_n)
	_stats.text = tr("Bales recycled %d   ·   Junk destroyed %s kg   ·   Parts %s") % [int(GameState.stats.get("bales_recycled", 0.0)),  # [money]
		Settings.fmt(BigNum.from_float(float(GameState.stats.get("junk_destroyed_kg", 0.0)))), Settings.fmt(GameState.get_currency("parts"))]
	for c: UpgradeCard in _cards:
		c.refresh()
