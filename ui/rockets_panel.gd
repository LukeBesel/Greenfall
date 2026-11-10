class_name RocketsPanel
extends VBoxContainer
## The workbench's rocket section: launch pad status and the rocket's tier (automation/rocket_tiers.gd)
## with its stats and upgrade button. The rocket comes with a level 5 base. Travel itself is only at
## the rocket: its destination list (ui/rocket_picker.gd) opens with E on the pad.

var world: Node


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	refresh()


func _ready_to_launch() -> bool:
	if world == null:
		return false
	if not Demo.rockets_allowed():  # [steam]
		return false
	return world.rocket_status() == "" if world.has_method("rocket_status") else ((world.hub != null and world.hub.level >= 5) or DevHooks.has("rocket"))


func refresh() -> void:
	for c: Node in get_children():
		c.queue_free()
	if world == null or world.get("planet") == null:
		return
	var ready_: bool = _ready_to_launch()
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM_LIGHT, UITheme.RUST, 1, 6, 14))
	add_child(status)
	var sv := VBoxContainer.new()
	status.add_child(sv)
	sv.add_child(UITheme.label(tr("LAUNCH PAD"), 13, UITheme.MUTED))
	var why: String = world.rocket_status() if world.has_method("rocket_status") else ""
	if ready_:
		sv.add_child(UITheme.label(tr("Cells charged and ready. Walk to the rocket to pick a base."), 20, UITheme.GREEN))
	elif why.begins_with(tr("Energy cells recharging: %s. Rocket upgrades refill them faster.").get_slice("%", 0)):  # [l10n]
		var lr := UITheme.label(why, 18, UITheme.GOLD)
		lr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sv.add_child(lr)
	else:
		var lvl: int = world.hub.level if world.hub else 1
		sv.add_child(UITheme.label(tr("Not built yet"), 20, UITheme.CREAM))
		var l := UITheme.label(tr("The launch pad comes with a level 5 base (yours is level %d). Upgrade the base in the Upgrades tab.") % lvl, 14, UITheme.MUTED)
		if not Demo.rockets_allowed():  # [steam]
			l.text = Planets.current().name_in(tr("Rockets to the rest of {planet} are in the full game. The demo stays in the first district."))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sv.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.value = 100.0 * minf(1.0, float(world.hub.level if world.hub else 1) / 5.0)
	sv.add_child(bar)
	_tier_box()


## Current rocket tier with its travel stats, and the next tier's upgrade.
func _tier_box() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM_LIGHT, UITheme.RUST, 1, 6, 14))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var d: Dictionary = RocketTiers.def()
	v.add_child(UITheme.label(tr("ROCKET"), 13, UITheme.MUTED))
	v.add_child(UITheme.label(tr(str(d.get("name", ""))), 20, UITheme.CREAM))
	v.add_child(_stats_label(d, {}))
	var nd: Dictionary = RocketTiers.next_def()
	if nd.is_empty():
		v.add_child(UITheme.label(tr("Top tier: warp hops, no recharge."), 14, UITheme.GREEN))
		return
	v.add_child(HSeparator.new())
	v.add_child(UITheme.label("NEXT: " + tr(str(nd["name"])).to_upper(), 13, UITheme.GOLD))
	var desc := UITheme.label(tr(str(nd.get("desc", ""))), 14, UITheme.CREAM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	v.add_child(_stats_label(nd, d))
	var cost := UITheme.label(HubPanel.cost_text(nd.get("cost", {})), 13, UITheme.MUTED)
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cost)
	var b := Button.new()
	var why: String = RocketTiers.blocker()
	b.text = tr("Upgrade to %s") % tr(str(nd["name"])) if why == "" else why
	b.disabled = why != ""
	b.custom_minimum_size = Vector2(300, 42)
	b.pressed.connect(func() -> void:
		if RocketTiers.upgrade():
			Audio.play("buy", 0.8, -2.0)
			Audio.music_sting("upgrade")
			if world and world.has_method("refresh_rocket"):
				world.refresh_rocket()
		else:
			Audio.play("buzz", 1.2, -8.0)
		refresh())
	v.add_child(b)


static func _stats_label(d: Dictionary, prev: Dictionary) -> Label:
	var rs: float = float(d.get("recharge_s", 0.0))
	var txt: String = TranslationServer.translate("Countdown %ds  ·  Flight %.1fs  ·  Recharge %s  ·  Cargo pods x%.1f every %ds") % [
		int(d.get("countdown_s", 5)), float(d.get("flight_s", 5.0)), "none" if rs <= 0.0 else RocketTiers.fmt_time(rs),
		float(d.get("cargo_mult", 1.0)), int(d.get("cargo_period_s", 60))]
	if bool(d.get("warp", false)):
		txt += TranslationServer.translate("  ·  WARP")
	return UITheme.label(txt, 13, UITheme.GREEN if not prev.is_empty() else UITheme.CREAM)
