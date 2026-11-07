class_name LateMenu
extends RefCounted
## [late] The pause menu's post-game entries: Garden Mode and the Ark Bridge. Hidden until they
## are open (Decor.unlocked / CradleMode.unlocked); `refresh` runs each time the menu opens and
## rebuilds the focus chain over the visible buttons so the pad never lands on a hidden one.


static func add_buttons(menu: Node, vb: Control, make: Callable) -> Array[Button]:
	var garden: Button = make.call(vb, TranslationServer.translate("Garden Mode  [%s]") % Settings.glyph("garden_mode"), func() -> void:
		menu.call("close_menu")
		var d: LateDirector = LateDirector.of(menu.get_parent())
		if d:
			d.open_garden())
	garden.name = "LateGarden"
	var ark: Button = make.call(vb, TranslationServer.translate("Ark Bridge"), func() -> void:
		menu.call("close_menu")
		var d: LateDirector = LateDirector.of(menu.get_parent())
		if d:
			d.open_bridge())
	ark.name = "LateArk"
	return [garden, ark]


static func refresh(menu: Node) -> void:
	var g: Button = menu.find_child("LateGarden", true, false) as Button
	var a: Button = menu.find_child("LateArk", true, false) as Button
	if g == null or a == null:
		return
	g.visible = Decor.unlocked()
	a.visible = CradleMode.unlocked() and not WeeklyChallenge.active  # [extras] no world travel from the challenge
	var vb: Node = g.get_parent()
	var list: Array[Button] = []
	for c: Node in vb.get_children():
		if c is Button and (c as Button).visible:
			list.append(c)
	for i: int in list.size():
		var b: Button = list[i]
		b.focus_neighbor_top = b.get_path_to(list[wrapi(i - 1, 0, list.size())])
		b.focus_neighbor_bottom = b.get_path_to(list[wrapi(i + 1, 0, list.size())])
