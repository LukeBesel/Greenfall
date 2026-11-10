class_name EndScreen
extends Control
## The end screen of a planet: shown once, after the launch cinematic (story/planet_ending.gd).
## A plain panel with the planet's name, what the player did, and two choices: keep playing or go
## back to the title. Pauses the game while open. It only reports the choice (`kept_playing`,
## `quit_to_title`); the caller saves and changes scene.
##
## Use: var s := EndScreen.open(world, {"planet": "Name", "time_played": 3600.0, "hexes_cleaned": 512,
##     "cities_restored": 6, "cities_total": 6, "robots_built": 149})

signal kept_playing
signal quit_to_title

const LAYER: int = 60
const PANEL_W: float = 640.0
const FADE_S: float = 0.18

var stats: Dictionary = {}
var is_open: bool = false
var _keep: Button


## Opens the screen over `parent`'s world, on its own canvas layer.
static func open(parent: Node, p_stats: Dictionary) -> EndScreen:
	var layer := CanvasLayer.new()
	layer.name = "EndScreenLayer"
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var screen := EndScreen.new()
	screen.name = "EndScreen"
	screen.stats = p_stats
	layer.add_child(screen)
	parent.add_child(layer)
	return screen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	is_open = true
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
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UITheme.label(tr("READY TO LAUNCH"), 16, UITheme.MUTED))
	col.add_child(UITheme.label(tr("%s is alive again") % tr(str(stats.get("planet", ""))), 36, UITheme.CREAM))
	var rule := ColorRect.new()
	rule.color = UITheme.GREEN
	rule.custom_minimum_size = Vector2(80, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var body := UITheme.label(tr("Every city is thriving and the rocket is ready. The rest of the planet is still out there if you want it."), 18, UITheme.MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	col.add_child(_stat_row())
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	_keep = _button(tr("Keep playing"), 220.0)
	_keep.pressed.connect(keep_playing)
	buttons.add_child(_keep)
	var quit: Button = _button(tr("Quit to title"), 190.0)
	quit.pressed.connect(_on_quit)
	buttons.add_child(quit)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_S)
	_keep.grab_focus.call_deferred()
	Audio.play("fanfare", 1.0, -8.0)


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		keep_playing()


## The rows shown: [label, value] pairs (tests read them).
func stat_rows() -> Array[Array]:
	return [
		[tr("Time played"), fmt_time(float(stats.get("time_played", 0.0)))],
		[tr("Hexes cleaned"), str(int(stats.get("hexes_cleaned", 0)))],
		[tr("Cities restored"), tr("%d of %d") % [int(stats.get("cities_restored", 0)), int(stats.get("cities_total", 0))]],
		[tr("Robots built"), str(int(stats.get("robots_built", 0)))],
	]


## Seconds as "3 h 45 min", or "12 min" under an hour.
static func fmt_time(seconds: float) -> String:
	var minutes: int = int(maxf(seconds, 0.0) / 60.0)
	@warning_ignore("integer_division")
	var hours: int = minutes / 60
	if hours > 0:
		return TranslationServer.translate("%d h %d min") % [hours, minutes % 60]
	return TranslationServer.translate("%d min") % minutes


func _stat_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	for pair: Array in stat_rows():
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(UITheme.label(str(pair[1]), 24, UITheme.GOLD))
		cell.add_child(UITheme.label(str(pair[0]), 16, UITheme.MUTED))
		row.add_child(cell)
	return row


func _button(text: String, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 50)
	b.add_theme_font_size_override("font_size", 19)
	return b


## "Keep playing": closes the screen and reports the choice.
func keep_playing() -> void:
	if not is_open:
		return
	_close()
	kept_playing.emit()


func _on_quit() -> void:
	if not is_open:
		return
	_close()
	quit_to_title.emit()


func _close() -> void:
	is_open = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	var layer: Node = get_parent()
	(layer if layer is CanvasLayer else self).queue_free()
