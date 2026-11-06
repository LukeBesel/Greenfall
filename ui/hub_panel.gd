class_name HubPanel
extends VBoxContainer
## Workbench "Hub" tab: upgrade the base with cubes + salvaged materials, build air scrubbers.

var hub: Hub
var _info: Label
var _next: Label
var _btn: Button
var _scrub: Label
var _scrub_btn: Button
var _mats: Label
var _stations: StationsPanel  # [stations]
var _jam_sep: HSeparator
var _jam: Label
var _jam_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label("HUB", 20, UITheme.CREAM))
	_mats = UITheme.label("", 15, UITheme.GOLD)
	add_child(_mats)
	_info = UITheme.label("", 16, UITheme.CREAM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_info)
	_next = UITheme.label("", 14, UITheme.MUTED)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_next)
	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(320, 46)
	_btn.pressed.connect(func() -> void:
		if hub.upgrade():
			Audio.play("buy", 0.9, -2.0)
			EventBus.ui_modal_changed.emit(false)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	add_child(_btn)
	add_child(HSeparator.new())
	_scrub = UITheme.label("", 15, UITheme.CREAM)
	_scrub.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_scrub)
	_scrub_btn = Button.new()
	_scrub_btn.custom_minimum_size = Vector2(320, 44)
	_scrub_btn.pressed.connect(func() -> void:
		if hub.build_scrubber():
			Audio.play("buy", 1.0, -2.0)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	add_child(_scrub_btn)
	# [stations] Conveyor / auto-baler / recycler section (ui/stations_panel.gd).
	add_child(HSeparator.new())
	_stations = StationsPanel.new()
	add_child(_stations)
	# Signal Jammer (the Ledger arc, story/ledger.gd): shown once the dump drones start.
	_jam_sep = HSeparator.new()
	add_child(_jam_sep)
	_jam = UITheme.label("", 15, UITheme.CREAM)
	_jam.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_jam)
	_jam_btn = Button.new()
	_jam_btn.custom_minimum_size = Vector2(320, 44)
	_jam_btn.text = "Build Signal Jammer"
	_jam_btn.pressed.connect(func() -> void:
		var lg: Node = _ledger()
		if lg and lg.build_jammer():
			Audio.play("buy", 1.1, -2.0)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	add_child(_jam_btn)
	refresh()


func _ledger() -> Node:
	return get_tree().get_first_node_in_group("ledger") if is_inside_tree() else null


static func cost_text(cost: Dictionary, mult: float = 1.0) -> String:
	var parts: Array[String] = []
	var names: Dictionary = {"cubes": "cubes", "sheet_metal": "sheet metal", "plastic_stock": "plastic stock", "glass_cullet": "glass", "bolts": "bolts"}
	for k: String in cost:
		var need := BigNum.from_float(float(cost[k]) * mult)
		var have: BigNum = GameState.get_currency(k)
		parts.append("%s %s%s" % [Settings.fmt(need), names.get(k, k), "" if have.gte(need) else " (have %s)" % Settings.fmt(have)])
	return ",  ".join(parts)


func refresh() -> void:
	if hub == null:
		return
	_mats.text = "Sheet metal %s    Plastic stock %s    Glass %s" % [Settings.fmt(GameState.get_currency("sheet_metal")), Settings.fmt(GameState.get_currency("plastic_stock")), Settings.fmt(GameState.get_currency("glass_cullet"))]
	var cur: Dictionary = hub.level_def(hub.level)
	_info.text = "Level %d   ·   %s\n%s   Bales sell for +%d%%." % [hub.level, cur.get("name", ""), cur.get("desc", ""), int(hub.sell_mult() * 100.0)]
	var nxt: Dictionary = hub.level_def(hub.level + 1)
	if nxt.is_empty():
		_next.text = "Fully built."
		_btn.visible = false
	else:
		_next.text = "Next: %s. %s\nNeeds %s" % [nxt["name"], nxt.get("desc", ""), cost_text(nxt.get("cost", {}))]
		_btn.text = "Build %s" % nxt["name"]
		_btn.disabled = not Hub.can_pay(nxt.get("cost", {}))
		_btn.visible = true
	var sd: Dictionary = hub.scrubber_def()
	var locked: bool = hub.level < int(sd.get("requires_level", 2))
	var maxed: bool = hub.scrubbers >= int(sd.get("max", 6))
	var suffix: String
	if locked:
		suffix = "\nRequires hub level %d." % int(sd.get("requires_level", 2))
	elif maxed:
		suffix = "\nAll built (max)."
	else:
		suffix = "\nNeeds " + cost_text(sd.get("cost", {}), hub.scrubber_cost_mult())
	_scrub.text = "%s   ·   %d / %d built\n%s%s" % [sd.get("name", ""), hub.scrubbers, int(sd.get("max", 6)), sd.get("desc", ""), suffix]
	_scrub_btn.text = "Air Scrubbers maxed" if maxed else "Build Air Scrubber"
	_scrub_btn.disabled = locked or maxed or not Hub.can_pay(sd.get("cost", {}), hub.scrubber_cost_mult())
	if _stations:  # [stations]
		_stations.refresh()
	var lg: Node = _ledger()
	var jam_on: bool = lg != null and lg.jammer_visible()
	_jam_sep.visible = jam_on
	_jam.visible = jam_on
	_jam_btn.visible = jam_on
	if jam_on:
		_jam.text = lg.jammer_text()
		_jam_btn.disabled = not lg.can_build_jammer()
