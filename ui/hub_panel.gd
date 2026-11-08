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
var _scope: TelescopePanel  # [scope]
var _jam_sep: HSeparator
var _jam: Label
var _jam_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UITheme.label(tr("HUB"), 20, UITheme.CREAM))
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
	# [scope] The Telescope (ui/telescope_panel.gd).
	add_child(HSeparator.new())
	_scope = TelescopePanel.new()
	add_child(_scope)
	# Signal Jammer (the Ledger arc, story/ledger.gd): shown once the dump drones start.
	_jam_sep = HSeparator.new()
	add_child(_jam_sep)
	_jam = UITheme.label("", 15, UITheme.CREAM)
	_jam.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_jam)
	_jam_btn = Button.new()
	_jam_btn.custom_minimum_size = Vector2(320, 44)
	_jam_btn.text = tr("Build Signal Jammer")
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
	# [money] Only cubes / parts / seeds; legacy keys are folded at their rates.
	var parts: Array[String] = []
	var f: Dictionary = Currencies.fold(cost)
	for k: String in Currencies.IDS:
		if float(f.get(k, 0.0)) <= 0.0:
			continue
		var need := BigNum.from_float(float(f[k]) * mult)
		var have: BigNum = GameState.get_currency(k)
		parts.append(L10nFmt.amount(k, need.to_float()) + ("" if have.gte(need) else TranslationServer.translate(" (have %s)") % Settings.fmt(have)))
	return ",  ".join(parts)


func refresh() -> void:
	if hub == null:
		return
	_mats.text = tr("Parts %s") % Settings.fmt(GameState.get_currency("parts"))  # [money]
	var cur: Dictionary = hub.level_def(hub.level)
	_info.text = tr("Level %d   ·   %s\n%s   Bales sell for +%d%%.") % [hub.level, tr(str(cur.get("name", ""))), tr(str(cur.get("desc", ""))), int(hub.sell_mult() * 100.0)]
	var nxt: Dictionary = hub.level_def(hub.level + 1)
	if nxt.is_empty():
		_next.text = tr("Fully built.")
		_btn.visible = false
	else:
		_next.text = tr("Next: %s. %s\nNeeds %s") % [tr(str(nxt["name"])), tr(str(nxt.get("desc", ""))), cost_text(nxt.get("cost", {}))]
		_btn.text = tr("Build %s") % tr(str(nxt["name"]))
		_btn.disabled = not Hub.can_pay(nxt.get("cost", {}))
		_btn.visible = true
		if not Demo.can_raise_base(hub.level):  # [steam] demo cap: the button opens the end-of-demo screen
			_next.text = Demo.base_cap_text()
			_btn.text = tr("Continue in the full game")
			_btn.disabled = false
	var sd: Dictionary = hub.scrubber_def()
	var locked: bool = hub.level < int(sd.get("requires_level", 2))
	var maxed: bool = hub.scrubbers >= int(sd.get("max", 6))
	var suffix: String
	if locked:
		suffix = tr("\nRequires hub level %d.") % int(sd.get("requires_level", 2))
	elif maxed:
		suffix = tr("\nAll built (max).")
	else:
		suffix = "\n" + tr("Needs %s") % cost_text(sd.get("cost", {}), hub.scrubber_cost_mult())
	_scrub.text = tr("%s   ·   %d / %d built\n%s%s") % [tr(str(sd.get("name", ""))), hub.scrubbers, int(sd.get("max", 6)), tr(str(sd.get("desc", ""))), suffix]
	_scrub_btn.text = tr("Air Scrubbers maxed") if maxed else tr("Build Air Scrubber")
	_scrub_btn.disabled = locked or maxed or not Hub.can_pay(sd.get("cost", {}), hub.scrubber_cost_mult())
	if _stations:  # [stations]
		_stations.refresh()
	if _scope:  # [scope]
		_scope.refresh()
	var lg: Node = _ledger()
	var jam_on: bool = lg != null and lg.jammer_visible()
	_jam_sep.visible = jam_on
	_jam.visible = jam_on
	_jam_btn.visible = jam_on
	if jam_on:
		_jam.text = lg.jammer_text()
		_jam_btn.disabled = not lg.can_build_jammer()
