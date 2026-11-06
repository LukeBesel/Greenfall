class_name RocketsPanel
extends VBoxContainer
## Rockets tab: launch pad status and the nearest bases to fly to, with each district's progress.
## The pad needs a level 5 base. Launching closes the workbench and starts the launch sequence.

var world: Node


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	refresh()


func _ready_to_launch() -> bool:
	if world == null:
		return false
	if not Demo.rockets_allowed():  # [steam]
		return false
	return (world.hub != null and world.hub.level >= 5) or DevHooks.has("rocket")


func refresh() -> void:
	for c: Node in get_children():
		c.queue_free()
	if world == null or world.get("planet") == null:
		return
	var planet: PlanetData = world.planet
	var ready: bool = _ready_to_launch()
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM_LIGHT, UITheme.RUST, 1, 6, 14))
	add_child(status)
	var sv := VBoxContainer.new()
	status.add_child(sv)
	sv.add_child(UITheme.label("LAUNCH PAD", 13, UITheme.MUTED))
	if ready:
		sv.add_child(UITheme.label("Fuelled and ready. Pick a base to fly to.", 20, UITheme.GREEN))
	else:
		var lvl: int = world.hub.level if world.hub else 1
		sv.add_child(UITheme.label("Not built yet", 20, UITheme.CREAM))
		var l := UITheme.label("The launch pad comes with a level 5 base (yours is level %d). Upgrade the base in the Hub tab." % lvl, 14, UITheme.MUTED)
		if not Demo.rockets_allowed():  # [steam]
			l.text = "Rockets to the rest of Verdance are in the full game. The demo stays in the first district."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sv.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.value = 100.0 * minf(1.0, float(world.hub.level if world.hub else 1) / 5.0)
	sv.add_child(bar)
	add_child(UITheme.label("NEARBY BASES", 13, UITheme.MUTED))
	var here_i: int = int(world.hub_index)
	var here: Vector3 = planet.grid.centers[planet.hubs[here_i]]
	var order: Array = range(planet.hubs.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return here.angle_to(planet.grid.centers[planet.hubs[a]]) < here.angle_to(planet.grid.centers[planet.hubs[b]]))
	for i: int in order.slice(1, 8):
		var cell: int = planet.hubs[i]
		var nm: String = str(planet.cities[planet.city[cell]]["name"]) if planet.city[cell] >= 0 else PlanetData.BIOMES[planet.biome[cell]].capitalize().replace("_", " ") + " site"
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
		vb.add_child(UITheme.label("%d sectors away  ·  %s" % [int(km * 1000.0 / 17.3), "visited" if visited else "unexplored"], 12, UITheme.GREEN if visited else UITheme.MUTED))
		var b := Button.new()
		b.text = "Launch"
		b.custom_minimum_size = Vector2(110, 38)
		b.disabled = not ready
		b.pressed.connect(func() -> void:
			if world.upgrades:
				world.upgrades.close_screen()
			world._launch(i))
		hb.add_child(b)
