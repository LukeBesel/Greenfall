extends Control
## End-of-demo screen: what the player achieved, a wishlist call to action (Steam overlay store
## page, or the browser without Steam), and the choice to keep playing the first district.
## Pauses the game while open. Shown by Demo.show_end_screen().

## Why it opened: "auto" (earned the next base level), "base" or "rocket" (tried a full-game feature).
var reason: String = "auto"
var _wish: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.flags["demo_end_seen"] = true
	get_tree().paused = true
	EventBus.ui_modal_changed.emit(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.CARD_BG, Color(1, 1, 1, 0.12), 1, 4, 34))
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	col.add_child(UITheme.label(tr("END OF THE DEMO"), 13, UITheme.MUTED))
	var title := UITheme.label("GREENFALL", 64, Color(1.0, 0.95, 0.86))
	title.add_theme_font_override("font", StoreArt.logo_font())
	col.add_child(title)
	var bar := ColorRect.new()
	bar.color = UITheme.GOLD
	bar.custom_minimum_size = Vector2(80, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	var lead: String = {
		"rocket": tr("The launch pad is waiting, but the rest of Verdance is in the full game."),
		"base": tr("Your base has grown as far as the demo goes."),
	}.get(reason, "You've earned the next base level. That's where the demo ends.")
	var head := UITheme.label(lead, 20, UITheme.CREAM)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(head)
	var body := UITheme.label(tr("In the full game Lumi builds the base up to level 5, plants whole districts until they thrive, grows them into a bright future city, and flies rockets to dozens of bases across the planet. Your demo progress carries over."), 15, UITheme.MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 26)
	col.add_child(stats)
	for row: Array in [
		[tr("Hexes cleaned"), str(int(GameState.stats.get("hexes_cleaned", 0)))],
		[tr("Bales made"), str(int(GameState.stats.get("cubes_made", 0)))],
		[tr("Robots built"), str(int(GameState.stats.get("robots_built", 0)))],
		[tr("Time played"), _fmt_time(float(GameState.stats.get("time_played", 0.0)))],
	]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(UITheme.label(str(row[1]), 24, UITheme.GOLD))
		v.add_child(UITheme.label(str(row[0]), 12, UITheme.MUTED))
		stats.add_child(v)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	_wish = Button.new()
	_wish.text = tr("Wishlist on Steam")
	_wish.custom_minimum_size = Vector2(250, 50)
	_wish.add_theme_font_size_override("font_size", 19)
	UITheme.orange_button(_wish)
	_wish.pressed.connect(func() -> void:
		SteamService.open_store_page()
		Audio.play("chime", 1.0, -6.0))
	buttons.add_child(_wish)
	var keep := Button.new()
	keep.text = tr("Keep playing")
	keep.custom_minimum_size = Vector2(170, 50)
	keep.pressed.connect(close)
	buttons.add_child(keep)
	var quit := Button.new()
	quit.text = tr("Title screen")
	quit.custom_minimum_size = Vector2(150, 50)
	quit.pressed.connect(func() -> void:
		SaveManager.save_game()
		close()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	buttons.add_child(quit)
	var note := UITheme.label(tr("Keep playing: the first district stays open, at base level %d.") % Demo.MAX_BASE_LEVEL, 12, UITheme.MUTED)
	col.add_child(note)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	_wish.call_deferred("grab_focus")
	Audio.play("fanfare", 1.0, -8.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	var layer: Node = get_parent()
	(layer if layer is CanvasLayer else self).queue_free()


static func _fmt_time(s: float) -> String:
	var m: int = int(s / 60.0)
	@warning_ignore("integer_division")
	return TranslationServer.translate("%dh %02dm") % [m / 60, m % 60] if m >= 60 else TranslationServer.translate("%d min") % m
