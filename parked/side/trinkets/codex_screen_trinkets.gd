# Snippets cut from ui/codex_screen.gd in task M3-13 with the Collection's trinkets: the trinket
# list under Lumi's collection on the Collection tab (it ended with a "TRINKETS AND CURIOS" label),
# its detail pane (_show_trinket) and the hint per source (_trinket_hint).

	var pick: Dictionary = {}
	for src: String in Collection.sources():
		var items: Array = Collection.defs().filter(func(t: Dictionary) -> bool: return str(t.get("source", "")) == src)
		var n_found: int = items.filter(func(t: Dictionary) -> bool: return Collection.has(str(t["id"]))).size()
		list.add_child(UITheme.label("%s   %d / %d" % [Collection.source_name(src).to_upper(), n_found, items.size()], 12, UITheme.MUTED))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		list.add_child(flow)
		for t: Dictionary in items:
			var got: bool = Collection.has(str(t["id"]))
			var b := Button.new()
			b.custom_minimum_size = Vector2(168, 40)
			b.text = ("◆  " + tr(str(t["name"]))) if got else "?   ? ? ?"
			b.clip_text = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 14)
			var col: Color = COLLECT_COLOR
			b.add_theme_stylebox_override("normal", UITheme.box(Color(col.r * 0.15 + 0.05, col.g * 0.15 + 0.05, col.b * 0.15 + 0.05, 0.9) if got else Color(0.05, 0.055, 0.06, 0.85), Color(col, 0.45) if got else Color(1, 1, 1, 0.06), 1, 8, 8))
			b.add_theme_stylebox_override("hover", UITheme.box(Color(0.12, 0.12, 0.12, 0.95), UITheme.GOLD, 1, 8, 8))
			b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 2, 8, 8))
			b.add_theme_color_override("font_color", UITheme.CREAM if got else Color(UITheme.MUTED, 0.8))
			UITheme.juice(b, 1.04)
			b.focus_entered.connect(_show_trinket.bind(t))
			b.mouse_entered.connect(_show_trinket.bind(t))
			b.pressed.connect(func() -> void:
				_show_trinket(t)
				Audio.play("click", 1.3, -10.0))
			flow.add_child(b)
			if first == null:
				first = b
			if pick.is_empty() and got:
				pick = t
	if not Exhibits.exhibits().is_empty():  # [eggs2]
		_show_exhibit(Exhibits.exhibits()[0])
	else:
		if pick.is_empty() and not Collection.defs().is_empty():
			pick = Collection.defs()[0]
		if not pick.is_empty():
			_show_trinket(pick)
	return first
	list.add_child(UITheme.label(tr("TRINKETS AND CURIOS"), 13, UITheme.MUTED))
func _show_trinket(t: Dictionary) -> void:
	var got: bool = Collection.has(str(t["id"]))
	var src: String = str(t.get("source", ""))
	_c_icon.text = "◆" if got else "?"
	_c_icon.add_theme_color_override("font_color", COLLECT_COLOR if got else Color(UITheme.MUTED, 0.6))
	_c_where.text = Collection.source_name(src).to_upper()
	_c_name.text = tr(str(t["name"])) if got else tr("Not found yet")
	_c_text.text = tr(str(t.get("desc", ""))) if got else _trinket_hint(t)
	_c_text.add_theme_color_override("font_color", UITheme.CREAM if got else UITheme.MUTED)
	_c_reward.text = tr("In your collection") if got else ""


static func _trinket_hint(t: Dictionary) -> String:
	match str(t.get("source", "")):
		"wildlife_visit": return TranslationServer.translate("Hint: a shy visitor comes to Sustained and Thriving hexes. Bring a camera.")
		"animal_photos": return TranslationServer.translate("Hint: animals come back as the ground heals. Photograph them in photo mode (P).")  # [wild]
		"contracts": return TranslationServer.translate("Hint: finish %d requests (Requests tab at the workbench).") % int(t.get("milestone", 1))
		"capsule": return TranslationServer.translate("Hint: Curio Capsules, on the Requests reward track at the workbench.")
		"streak": return TranslationServer.translate("Hint: keep scooping without stopping until the streak meter is full.")
	return TranslationServer.translate("Hint: turns up during %s.") % Collection.source_name(str(t.get("source", ""))).to_lower()
