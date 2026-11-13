class_name RocketsPanel
extends VBoxContainer
## Rockets tab: launch pad status and the nearest bases to fly to, with each district's progress.
## The pad needs a level 5 base. Launching closes the workbench and starts the launch sequence.
## Also the rocket's tier (Mk I-IV, automation/rocket_tiers.gd): stats and the upgrade button.

var world: Node


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	refresh()


func _ready_to_launch() -> bool:
	if world == null:
		return false
	if not Demo.rockets_allowed():  # [steam]
		return false
	return world.rocket_status() == "" if world.has_method("rocket_status") else ((world.hub != null and Hub.rocket_open(world.hub.level)) or DevHooks.has("rocket"))


func refresh() -> void:
	for c: Node in get_children():
		c.queue_free()
	if world == null or world.get("planet") == null:
		return
	var planet: PlanetData = world.planet
	var ready_: bool = _ready_to_launch()
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM_LIGHT, UITheme.RUST, 1, 6, 14))
	add_child(status)
	var sv := VBoxContainer.new()
	status.add_child(sv)
	sv.add_child(UITheme.label(tr("LAUNCH PAD"), 13, UITheme.MUTED))
	var why: String = world.rocket_status() if world.has_method("rocket_status") else ""
	if ready_:
		sv.add_child(UITheme.label(tr("Cells charged and ready. Pick a base to fly to."), 20, UITheme.GREEN))
	elif why.begins_with(tr("Energy cells recharging: %s. Rocket upgrades refill them faster.").get_slice("%", 0)):  # [l10n]
		var lr := UITheme.label(why, 18, UITheme.GOLD)
		lr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sv.add_child(lr)
	else:
		var lvl: int = world.hub.level if world.hub else 1
		sv.add_child(UITheme.label(tr("Not built yet"), 20, UITheme.CREAM))
		var l := UITheme.label(Hub.rocket_lock_text(lvl), 14, UITheme.MUTED)
		if not Demo.rockets_allowed():  # [steam]
			l.text = tr("Rockets to the rest of Verdance are in the full game. The demo stays in the first district.")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sv.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.value = 100.0 * minf(1.0, float(world.hub.level if world.hub else 1) / float(maxi(Hub.rocket_level(), 1))) if not ready_ else 100.0
	sv.add_child(bar)
	_tier_box()
	if world.get("orbit") != null:
		# [v5play] On the round planet the rocket itself is the way to fly (press E at the pad, pick
		# a hub). The list below launched the flat game's rocket: script errors, no flight.
		var how := UITheme.label(Objectives.glyphs(tr("Walk to the rocket on the launch pad and press {interact} to choose where to fly.")) if ready_ else Hub.rocket_lock_text(world.hub.level if world.hub else 1), 15, UITheme.CREAM)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(how)
		return
	add_child(UITheme.label(tr("NEARBY BASES"), 13, UITheme.MUTED))
	var here_i: int = int(world.hub_index)
	var here: Vector3 = planet.grid.centers[planet.hubs[here_i]]
	var order: Array = range(planet.base_hub_count if planet.base_hub_count > 0 else planet.hubs.size())  # [biomes] frontiers listed below
	order.sort_custom(func(a: int, b: int) -> bool:
		return here.angle_to(planet.grid.centers[planet.hubs[a]]) < here.angle_to(planet.grid.centers[planet.hubs[b]]))
	for i: int in order.filter(func(x: int) -> bool: return x != here_i).slice(0, 7):  # [biomes]
		var cell: int = planet.hubs[i]
		var nm: String = tr(str(planet.cities[planet.city[cell]]["name"])) if planet.city[cell] >= 0 else PlanetData.BIOMES[planet.biome[cell]].capitalize().replace("_", " ") + " site"
		var km: float = here.angle_to(planet.grid.centers[cell]) * planet.radius_m / 1000.0
		var visited: bool = GameState.districts.has(i) and not (GameState.districts[i] as Dictionary).is_empty()
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.box(UITheme.TEAL, UITheme.RUST, 1, 5, 10))
		add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 0)
		hb.add_child(vb)
		vb.add_child(UITheme.label(nm, 17, UITheme.CREAM))
		vb.add_child(UITheme.label(tr("%d sectors away  ·  %s") % [int(km * 1000.0 / 17.3), "visited" if visited else "unexplored"], 12, UITheme.GREEN if visited else UITheme.MUTED))
		var b := Button.new()
		b.text = tr("Launch")
		b.custom_minimum_size = Vector2(110, 38)
		b.disabled = not ready_
		b.pressed.connect(func() -> void:
			if world.upgrades:
				world.upgrades.close_screen()
			world._launch(i))
		hb.add_child(b)
	FrontierRockets.add_section(self, world, ready_)  # [biomes] late-game frontier destinations


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
			Refuse.say(RocketTiers.blocker())  # [v9d] say why
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
