class_name CodexArtists
extends RefCounted
## [tunes] The Codex "Artists" page: the bands behind your CDs (data/songs.json artists). An
## artist shows up once you own one of their songs, with their genre, bio and the songs you have.

const COLOR := Color(0.62, 0.86, 1.0)


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


static func build(body: Control) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	body.add_child(hb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	sc.size_flags_stretch_ratio = 1.2
	hb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	sc.add_child(list)
	var known: Array[String] = Tunes.known_artists()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	list.add_child(head)
	head.add_child(ResearchIcons.IconView.new("star", 26, COLOR))
	head.add_child(UITheme.label(_t("ARTISTS"), 15, COLOR))
	head.add_child(UITheme.label(_t("%d / %d known") % [known.size(), Tunes.artists().size()], 13, UITheme.MUTED))
	var det := PanelContainer.new()
	det.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.055, 0.85), Color(1, 1, 1, 0.07), 1, 14, 20))
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(det)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dsc := ScrollContainer.new()  # [v6screens] scrolls on a short screen (tools/ui_audit.gd)
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	det.add_child(dsc)
	dsc.add_child(dv)
	var genre: Label = UITheme.label("", 12, COLOR)
	dv.add_child(genre)
	var nm: Label = UITheme.label("", 24, Color.WHITE)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	dv.add_child(nm)
	var bio: Label = UITheme.label("", 16, UITheme.CREAM)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD
	bio.custom_minimum_size = Vector2(300, 0)
	dv.add_child(bio)
	var tracks: Label = UITheme.label("", 13, UITheme.MUTED)
	tracks.autowrap_mode = TextServer.AUTOWRAP_WORD
	tracks.custom_minimum_size = Vector2(300, 0)
	dv.add_child(tracks)
	var show := func(aid: String) -> void:
		var a: Dictionary = Tunes.artist(aid)
		var got: bool = aid in known
		genre.text = ("%s  ·  %s" % [_t(str(a.get("genre", ""))), _t("From %s") % Tunes.planet_name(Tunes.artist_home(aid))]).to_upper() if got else ""
		nm.text = _t(str(a.get("name", ""))) if got else _t("Not met yet")
		bio.text = _t(str(a.get("bio", ""))) if got else (_t("Find one of their CDs in the rubble on %s.") % Tunes.planet_name(Tunes.artist_home(aid)))
		var have: PackedStringArray = []
		var total: int = 0
		for id: String in Tunes.songs_by(aid):
			total += 1
			if Tunes.is_found(id):
				have.append(_t(Tunes.title(id)))
		tracks.text = (_t("Your CDs (%d / %d): %s") % [have.size(), total, ", ".join(have)]) if got else ""
	var first: Control = null
	for a: Dictionary in Tunes.artists():
		var aid: String = str(a["id"])
		var got: bool = aid in known
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.text = ("◆  " + _t(str(a["name"]))) if got else "?   ? ? ?"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", UITheme.CREAM if got else Color(UITheme.MUTED, 0.8))
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.08, 0.11, 0.14, 0.9) if got else Color(0.05, 0.055, 0.06, 0.85), Color(COLOR, 0.45) if got else Color(1, 1, 1, 0.06), 1, 8, 8))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(0.12, 0.12, 0.12, 0.95), UITheme.GOLD, 1, 8, 8))
		b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 2, 8, 8))
		b.focus_entered.connect(show.bind(aid))
		b.mouse_entered.connect(show.bind(aid))
		list.add_child(b)
		if first == null:
			first = b
	show.call(known[0] if not known.is_empty() else (str(Tunes.artists()[0]["id"]) if not Tunes.artists().is_empty() else ""))
	return first
