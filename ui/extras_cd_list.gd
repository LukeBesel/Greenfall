class_name ExtrasCdList
extends RefCounted
## [tunes] The Keepsakes "CD Player" tab (ui/extras_panel.gd): your CDs with the artist, locked
## ones with a lock and where they are found, a Shuffle row on top, and what is playing now.

const CD_COLOR := Color(0.62, 0.86, 1.0)


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


static func _col(body: Control, width: float, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(UITheme.CARD_BG, Color(1, 1, 1, 0.06), 1, 8, 12))
	pc.custom_minimum_size = Vector2(width, 0)
	if width <= 0.0:
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	pc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	if title != "":
		vb.add_child(UITheme.label(title, 12, Color(0.4, 0.75, 1.0)))
	return vb


static func _wrap(text: String, size: int, col: Color) -> Label:
	var l: Label = UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _row(parent: Control, text: String, icon: String, icon_col: Color, cb: Callable, h: float = 52.0) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		cb.call())
	parent.add_child(b)
	if icon != "":
		var iv := ResearchIcons.IconView.new(icon, 26, icon_col, false)
		iv.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		iv.position.x -= 10
		b.add_child(iv)
	return b


## `on_btn` gets every row (the panel focuses the first); `rebuild` redraws the tab.
static func build(_panel: Node, body: Control, on_btn: Callable, rebuild: Callable) -> void:
	var avail: Array[String] = Tunes.available()
	var mode: String = Radio.playing()
	var now: String = Tunes.now_playing()
	var left: VBoxContainer = _col(body, 440, _t("CDS  ·  %d / %d") % [Tunes.found_count(), avail.size()])
	var shuf: Button = _row(left, "%s%s\n%s" % ["▶  " if mode == Tunes.SHUFFLE else "", _t("Shuffle"), _t("All your CDs, at random")],
		"recycle", CD_COLOR, func() -> void:
			if Radio.play(Tunes.SHUFFLE):
				EventBus.toast.emit(_t("CD player: shuffle"), "info")
			rebuild.call())
	shuf.add_theme_color_override("font_color", UITheme.GOLD if mode == Tunes.SHUFFLE else UITheme.CREAM)
	on_btn.call(shuf)
	var focus: Button = shuf if mode == Tunes.SHUFFLE else null
	for id: String in avail:
		var ok: bool = Tunes.is_found(id)
		var cur: bool = id == mode
		var txt: String
		if ok:
			txt = "%s%s\n%s" % ["▶  " if cur else "", _t(Tunes.title(id)), _t("by %s, from %s") % [_t(Tunes.artist_name(id)), Tunes.planet_name(Tunes.home(id))]]
		else:
			txt = "? ? ?\n%s" % (_t("Found on %s") % Tunes.planet_name(Tunes.found_on(id)))
		var b: Button = _row(left, txt, "" if ok else "lock", Color(UITheme.MUTED, 0.7), func() -> void:
			if not ok:
				EventBus.toast.emit(_t("Not found yet: CDs turn up in the rubble on %s.") % Tunes.planet_name(Tunes.found_on(id)), "hint")
				return
			if Radio.play(id):
				EventBus.toast.emit(_t("Now playing: %s by %s") % [_t(Tunes.title(id)), _t(Tunes.artist_name(id))], "info")
			rebuild.call())
		b.add_theme_color_override("font_color", UITheme.GOLD if cur else (UITheme.CREAM if ok else UITheme.MUTED))
		on_btn.call(b)
		if cur:
			focus = b
	if not Tunes.held().is_empty():
		left.add_child(UITheme.label(_t("CD CASE  ·  SCRATCHED, ONE PLAY EACH  ·  %d / %d") % [Tunes.held().size(), Tunes.case_size()], 12, Color(0.4, 0.75, 1.0)))
		for id: String in Tunes.held():
			var sb: Button = _row(left, "%s\n%s" % [_t("Play once: %s") % _t(Tunes.title(id)), _t("by %s") % _t(Tunes.artist_name(id))], "", Color.WHITE, func() -> void:
				if Tunes.play_scratched(id):
					EventBus.toast.emit(_t("Last play: %s by %s") % [_t(Tunes.title(id)), _t(Tunes.artist_name(id))], "info")
				rebuild.call())
			sb.add_theme_color_override("font_color", Color(0.75, 0.8, 0.86))
			on_btn.call(sb)
	if focus:
		focus.call_deferred("grab_focus")
	var right: VBoxContainer = _col(body, 0, _t("NOW PLAYING"))
	if mode != "" and (mode == Tunes.SHUFFLE or Tunes.is_found(mode)):
		var id: String = now if now != "" else (mode if mode != Tunes.SHUFFLE else "")
		if mode == Tunes.SHUFFLE:
			right.add_child(UITheme.label(_t("Shuffle"), 14, CD_COLOR))
		if id != "":
			right.add_child(UITheme.label(_t(Tunes.title(id)), 26, Color.WHITE))
			var a: Dictionary = Tunes.artist(str(Tunes.song(id).get("artist", "")))
			right.add_child(UITheme.label(_t("by %s, from %s") % [_t(str(a.get("name", ""))), Tunes.planet_name(Tunes.home(id))], 16, UITheme.GOLD))
			if str(Tunes.song(id).get("desc", "")) != "":
				right.add_child(_wrap(_t(str(Tunes.song(id).get("desc", ""))), 15, UITheme.MUTED))
			right.add_child(_wrap("%s  ·  %s" % [_t(str(a.get("genre", ""))), _t(str(a.get("bio", "")))], 13, UITheme.MUTED))
		var off: Button = _row(right, _t("Turn off (back to the day's music)"), "", Color.WHITE, func() -> void:
			Radio.play("")
			EventBus.toast.emit(_t("The CD player goes quiet. The day's music comes back."), "info")
			rebuild.call(), 44)
		UITheme.orange_button(off)
		on_btn.call(off)
	else:
		right.add_child(UITheme.label(_t("The day's music"), 26, Color.WHITE))
		right.add_child(_wrap(_t("Your CDs come on now and then while you work, with quiet in between. Pick one here, or Shuffle, to play them back to back."), 15, UITheme.MUTED))
	if Tunes.glim_music():
		right.add_child(_wrap(_t("Glim has copied your CDs: press N anywhere to pick a song."), 13, UITheme.GREEN))
	else:
		right.add_child(_wrap(_t("The music comes from the CD player, so it's softer far away from it."), 13, UITheme.MUTED))
	right.add_child(_wrap(_t("New CDs turn up in the rubble as you clean. Each planet hides its own."), 13, UITheme.GREEN))
