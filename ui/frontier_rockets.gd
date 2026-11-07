class_name FrontierRockets
extends RefCounted
## [biomes] The "FRONTIERS" section of the workbench Rockets tab: the four late-game districts
## (planet/frontiers.gd) with their unlock checklist and a Launch button once they are open.


static func add_section(panel: Control, world: Node, pad_ready: bool) -> void:
	var planet: PlanetData = world.planet
	if planet.frontier_hubs.is_empty():
		return
	panel.add_child(UITheme.label(TranslationServer.translate("FRONTIERS"), 13, UITheme.MUTED))
	for fid: String in Frontiers.ids():
		if not planet.frontier_hubs.has(fid):
			continue
		var hub_i: int = int(planet.frontier_hubs[fid])
		var d: Dictionary = Frontiers.def(fid)
		var st: Dictionary = Frontiers.unlock_status(fid, planet.frontier_hubs)
		var open: bool = Frontiers.can_launch(planet, hub_i)
		var here: bool = hub_i == int(world.hub_index)
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.box(UITheme.TEAL if open else UITheme.PLUM_LIGHT, UITheme.RUST, 1, 5, 10))
		panel.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row.add_child(hb)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 1)
		hb.add_child(vb)
		vb.add_child(UITheme.label(TranslationServer.translate(str(d.get("name", fid))), 17, UITheme.CREAM if open else UITheme.MUTED))
		var tag := UITheme.label(TranslationServer.translate(str(d.get("tagline", ""))), 12, UITheme.MUTED)
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(tag)
		if not open:
			for line: String in st["lines"]:
				vb.add_child(UITheme.label(line, 12, UITheme.GREEN if line.begins_with("✓") else UITheme.MUTED))
		else:
			var lvl: int = Frontiers.base_level(hub_i)
			vb.add_child(UITheme.label(TranslationServer.translate("You are here") if here else (TranslationServer.translate("Base level %d") % lvl if lvl > 0 else TranslationServer.translate("Unexplored  ·  bales sell x%d here") % int(float(d.get("value_mult", 1.0)))), 12, UITheme.GREEN))
		var b := Button.new()
		b.text = TranslationServer.translate("Launch")
		b.custom_minimum_size = Vector2(110, 38)
		b.disabled = not (open and pad_ready) or here
		b.pressed.connect(func() -> void:
			if world.upgrades:
				world.upgrades.close_screen()
			world._launch(hub_i))
		hb.add_child(b)
