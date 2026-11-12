class_name HubPanel
extends HBoxContainer
## Workbench "Hub" tab. [ui2] Left: one big card for the next hub level (what it is, what it
## gives you, the cost in Parts and cubes, a big Upgrade button, the level spots). Right: the
## smaller things built at the hub (Air Scrubbers, bale stations, the Jammer).

## Height of the scrolling side column (fits the workbench at 1280x800 and 110% UI scale).
const SIDE_H: float = 460.0

var hub: Hub
## [ui3] Only the next-level card (the Upgrades tab's Base section).
var hero_only: bool = false
var _lv_pips: BenchKit.Pips
var _lv_lbl: Label
var _name: Label
var _desc: Label
var _gains: VBoxContainer
var _gain_sig: String = ""
var _cost: BenchKit.CostRow
var _btn: Button
var _hero: PanelContainer
var _now: Label
var _scrub: Label
var _scrub_cost: BenchKit.CostRow
var _scrub_btn: Button
var _stations: StationsPanel  # [stations]
var _jam_box: VBoxContainer
var _yard: YardBuildsPanel  # [camp]
var _jam: Label
var _jam_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# --- The next level: one clear card ---------------------------------------------------
	var hc: Array = BenchKit.card(Color(BenchKit.HOLO, 0.4), 400)
	_hero = hc[0]
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.size_flags_stretch_ratio = 1.1
	_hero.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(_hero)
	var hv: VBoxContainer = hc[1]
	hv.add_theme_constant_override("separation", 12)
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 12)
	hv.add_child(lr)
	_lv_lbl = BenchKit.caps("", BenchKit.HOLO)
	_lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lr.add_child(_lv_lbl)
	_lv_pips = BenchKit.Pips.new(5, true, BenchKit.HOLO)
	lr.add_child(_lv_pips)
	_name = UITheme.label("", 32, Color.WHITE)
	_name.add_theme_constant_override("outline_size", 0)
	hv.add_child(_name)
	_desc = BenchKit.body("", UITheme.MUTED)
	hv.add_child(_desc)
	hv.add_child(BenchKit.caps(tr("What you get")))
	_gains = VBoxContainer.new()
	_gains.add_theme_constant_override("separation", 6)
	hv.add_child(_gains)
	hv.add_child(BenchKit.spacer(4))
	_cost = BenchKit.CostRow.new(28, 26)
	_cost.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.add_child(_cost)
	_btn = BenchKit.big_button(tr("Upgrade"))
	_btn.custom_minimum_size.y = 64
	_btn.add_theme_font_size_override("font_size", 23)
	_btn.pressed.connect(_on_upgrade)
	hv.add_child(_btn)
	_now = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
	hv.add_child(_now)
	if hero_only:  # [ui3] the Upgrades tab shows just the level card; buildings live in the Build tab
		refresh()
		return
	# --- Built at the hub -----------------------------------------------------------------
	# The side column scrolls on its own, so the level card always stays in view.
	var side_sc := ScrollContainer.new()
	side_sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_sc.custom_minimum_size = Vector2(0, SIDE_H)
	side_sc.follow_focus = true
	add_child(side_sc)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 14)
	side_sc.add_child(side)
	var sc: Array = BenchKit.card()
	side.add_child(sc[0])
	var sv: VBoxContainer = sc[1]
	_scrub = BenchKit.body("", UITheme.CREAM)
	sv.add_child(_scrub)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 12)
	sv.add_child(sr)
	_scrub_btn = BenchKit.soft_button(tr("Build Air Scrubber"))
	_scrub_btn.pressed.connect(func() -> void:
		if hub.build_scrubber():
			Audio.play("buy", 1.0, -2.0)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	sr.add_child(_scrub_btn)
	_scrub_cost = BenchKit.CostRow.new(20, 18)
	sr.add_child(_scrub_cost)
	# [stations] Conveyor / auto-baler / recycler section (ui/stations_panel.gd).
	var stc: Array = BenchKit.card()
	side.add_child(stc[0])
	_stations = StationsPanel.new()
	(stc[1] as VBoxContainer).add_child(_stations)
	for g: Node in _stations.find_children("*", "GridContainer", true, false):
		(g as GridContainer).columns = 1  # one column beside the level card
	for b: Node in _stations.find_children("*", "Button", true, false):
		(b as Button).custom_minimum_size.x = 0.0  # fits beside the level card at 125% UI scale
		(b as Button).clip_text = true
		(b as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# [camp] trash bin, radio (ui/yard_builds_panel.gd)
	var yc: Array = BenchKit.card()
	side.add_child(yc[0])
	_yard = YardBuildsPanel.new()
	(yc[1] as VBoxContainer).add_child(_yard)
	# Signal Jammer (the Ledger arc, story/ledger.gd): shown once the dump drones start.
	var jc: Array = BenchKit.card()
	side.add_child(jc[0])
	_jam_box = jc[1]
	_jam = BenchKit.body("", UITheme.CREAM)
	_jam_box.add_child(_jam)
	_jam_btn = BenchKit.soft_button(tr("Build Signal Jammer"))
	_jam_btn.pressed.connect(func() -> void:
		var lg: Node = _ledger()
		if lg and lg.build_jammer():
			Audio.play("buy", 1.1, -2.0)
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	_jam_box.add_child(_jam_btn)
	refresh()


func first_button() -> Button:
	return _btn


func _on_upgrade() -> void:
	if hub.upgrade():
		Audio.play("buy", 0.9, -2.0)
		Audio.play("fanfare", 1.0, -8.0)
		EventBus.ui_modal_changed.emit(false)
	else:
		Audio.play("buzz", 1.2, -8.0)
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


## [ui2] What reaching hub level `lv` gives, one short line each (sell bonus, robot spots, and the
## things that open at that level).
static func level_gains(h: Hub, lv: int) -> Array[String]:
	var out: Array[String] = []
	var nd: Dictionary = h.level_def(lv)
	var pd: Dictionary = h.level_def(lv - 1)
	var s_new: int = int(round(float(nd.get("bonus", {}).get("sell_mult", 0.0)) * 100.0))
	var s_old: int = int(round(float(pd.get("bonus", {}).get("sell_mult", 0.0)) * 100.0))
	if s_new > s_old:
		out.append(TranslationServer.translate("Bales sell for +%d%% (now +%d%%)") % [s_new, s_old])
	var per: int = CrewRules.cap_gain_at_level(Economy.robot_cfg, lv - 1, Economy.tiers_open())
	if per > 0:
		out.append(TranslationServer.translate("+%d robot spots") % per)
	var sd: Dictionary = h.scrubber_def()
	if int(sd.get("requires_level", 2)) == lv:
		out.append(TranslationServer.translate("Air Scrubbers: clear the dusty sky"))
	var st: Stations = Stations.of(h) if h.is_inside_tree() else null
	if st:
		for id: String in ["conveyor", "auto_baler", "recycler"]:
			if int(st.def(id).get("requires_level", 0)) == lv:
				out.append(TranslationServer.translate("Unlocks the %s") % TranslationServer.translate(str(st.def(id).get("name", id))))
	if lv == 5:
		out.append(TranslationServer.translate("A launch pad: rockets to the next district"))
	return out


func refresh() -> void:
	if hub == null:
		return
	var max_lv: int = (hub.data.get("levels", []) as Array).size()
	_lv_pips.set_counts(hub.level, max_lv)
	var cur: Dictionary = hub.level_def(hub.level)
	var nxt: Dictionary = hub.level_def(hub.level + 1)
	if hub.sell_mult() > 0.0:
		_now.text = tr("Now: level %d, %s. Bales sell for +%d%%.") % [hub.level, tr(str(cur.get("name", ""))), int(round(hub.sell_mult() * 100.0))]
	else:
		_now.text = tr("Now: level %d, %s.") % [hub.level, tr(str(cur.get("name", "")))]
	if nxt.is_empty():
		_lv_lbl.text = tr("Hub level %d  ·  fully built") % hub.level
		_name.text = tr(str(cur.get("name", "")))
		_desc.text = tr(str(cur.get("desc", "")))
		_set_gains([tr("Every hub level is built.")])
		_cost.set_cost({}, " ")
		_btn.text = tr("Fully built")
		_btn.disabled = true
	else:
		_lv_lbl.text = tr("Next: hub level %d") % (hub.level + 1)
		_name.text = tr(str(nxt["name"]))
		_desc.text = tr(str(nxt.get("desc", "")))
		_set_gains(level_gains(hub, hub.level + 1))
		var c: Dictionary = nxt.get("cost", {})
		_cost.set_cost(c)
		var ok: bool = Hub.can_pay(c)
		_btn.text = tr("Upgrade to level %d") % (hub.level + 1) if ok else tr("Not enough yet")
		_btn.disabled = not ok
		if not Demo.can_raise_base(hub.level):  # [steam] demo cap: the button opens the end-of-demo screen
			_desc.text = Demo.base_cap_text()
			_btn.text = tr("Continue in the full game")
			_btn.disabled = false
		BenchKit.set_accent(_hero, Color(BenchKit.OK, 0.8) if not _btn.disabled else Color(BenchKit.HOLO, 0.3))
	if hero_only:
		return
	# Air Scrubbers.
	var sd: Dictionary = hub.scrubber_def()
	var locked: bool = hub.level < int(sd.get("requires_level", 2))
	var maxed: bool = hub.scrubbers >= int(sd.get("max", 6))
	var line2: String
	if locked:
		line2 = tr("Opens at hub level %d.") % int(sd.get("requires_level", 2))
	elif maxed:
		line2 = tr("All built.")
	else:
		line2 = tr(str(sd.get("desc", "")))
	_scrub.text = tr("%s   %d / %d\n%s") % [tr(str(sd.get("name", ""))), hub.scrubbers, int(sd.get("max", 6)), line2]
	_scrub_btn.text = tr("All built") if maxed else tr("Build Air Scrubber")
	_scrub_btn.disabled = locked or maxed or not Hub.can_pay(sd.get("cost", {}), hub.scrubber_cost_mult())
	var sdc: Dictionary = (sd.get("cost", {}) as Dictionary).duplicate()
	for k: String in sdc:
		sdc[k] = float(sdc[k]) * hub.scrubber_cost_mult()
	_scrub_cost.set_cost({} if locked or maxed else sdc, " ")
	if _stations:  # [stations]
		_stations.refresh()
		(_stations.get_parent().get_parent() as Control).visible = _stations.visible
	if _yard:  # [camp]
		_yard.refresh()
	var lg: Node = _ledger()
	var jam_on: bool = lg != null and lg.jammer_visible()
	(_jam_box.get_parent() as Control).visible = jam_on
	if jam_on:
		_jam.text = lg.jammer_text()
		_jam_btn.disabled = not lg.can_build_jammer()


func _set_gains(lines: Array[String]) -> void:
	var sig: String = "|".join(lines)
	if sig == _gain_sig:
		return
	_gain_sig = sig
	for c: Node in _gains.get_children():
		_gains.remove_child(c)
		c.queue_free()
	for l: String in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var dot: Label = UITheme.label("+", 20, UITheme.GREEN)
		dot.add_theme_constant_override("outline_size", 0)
		row.add_child(dot)
		row.add_child(BenchKit.body(l, UITheme.CREAM))
		_gains.add_child(row)
