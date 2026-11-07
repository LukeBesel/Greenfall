class_name CreditsRoll
extends CanvasLayer
## [beat] End credits after the Cradle finale (story/bloom_finale.gd): fades to a dark, quiet
## screen and scrolls the credits built from docs/CREDITS.md (assets grouped by author), then
## fades back into the game, which keeps going (the Seed Ark loop). Skippable any time with
## Esc / Space / Enter / click / pad A or B; the game is paused underneath while it rolls.
## Plays once per save after the finale (flags.credits_seen); the title screen keeps its own
## Credits page. Dev: --credits[=S] plays it S seconds after the district loads; --credits-hold[=PX]
## freezes it PX pixels in (screenshots).

signal finished

const SPEED: float = 60.0  ## px per second
const FADE_S: float = 1.2

var _bg: ColorRect
var _col: VBoxContainer
var _hint: Label
var _t: float = 0.0
var _done: bool = false
var _was_paused: bool = false
var _scroll_end: float = 0.0
var _w: float = 760.0


## Plays the roll over the current scene. Returns the node (await its `finished`).
static func play(parent: Node) -> CreditsRoll:
	var c := CreditsRoll.new()
	parent.add_child(c)
	return c


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_bg = ColorRect.new()
	_bg.color = Color(0.015, 0.02, 0.025, 0.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_col = VBoxContainer.new()
	_col.alignment = BoxContainer.ALIGNMENT_BEGIN
	_col.add_theme_constant_override("separation", 6)
	_col.modulate.a = 0.0
	add_child(_col)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_w = minf(vp.x - 32.0, 760.0)
	for e: Array in entries():
		_col.add_child(_line(str(e[0]), str(e[1])))
	_hint = UITheme.label(tr("Esc  Skip"), 13, UITheme.MUTED)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -140
	_hint.offset_top = -40
	_hint.offset_right = -24
	_hint.offset_bottom = -16
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.modulate.a = 0.0
	add_child(_hint)
	var tw := create_tween()
	tw.tween_property(_bg, "color:a", 0.97, FADE_S)
	tw.parallel().tween_property(_hint, "modulate:a", 0.8, FADE_S)
	tw.tween_property(_col, "modulate:a", 1.0, 0.6)
	_layout.call_deferred()


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = _w
	_col.custom_minimum_size = Vector2(w, 0)
	_col.size = Vector2(w, 0)
	_col.reset_size()
	_col.position = Vector2((vp.x - w) * 0.5, vp.y + 20.0)
	_scroll_end = -_col.get_combined_minimum_size().y - 20.0
	print("[credits] %d rows, %.0f px" % [_col.get_child_count(), -_scroll_end])
	if DevHooks.has("credits-hold"):  # screenshots: hold the roll at this many px scrolled
		_col.position.y = vp.y * 0.18 - DevHooks.get_f("credits-hold", 0.0)


func _line(kind: String, text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(_w, 0)  # autowrap needs a width up front
	match kind:
		"title":
			l.add_theme_font_size_override("font_size", 54)
			l.add_theme_color_override("font_color", UITheme.GOLD)
		"sub":
			l.add_theme_font_size_override("font_size", 18)
			l.add_theme_color_override("font_color", UITheme.CREAM)
		"head":
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", UITheme.GOLD)
		"name":
			l.add_theme_font_size_override("font_size", 19)
			l.add_theme_color_override("font_color", UITheme.CREAM)
		"small":
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", UITheme.MUTED)
		"gap":
			l.custom_minimum_size = Vector2(_w, 46)
	return l


## The roll as [kind, text] rows (pure: tests read it). Assets are grouped by author.
static func entries(md_path: String = "res://docs/CREDITS.md") -> Array:
	var out: Array = [["title", "GREENFALL"], ["sub", TranslationServer.translate("The Cradle is home.")], ["gap", ""]]
	var by_author: Dictionary = {}
	var authors: Array[String] = []
	var kinds: Dictionary = {}
	var intro: Array[String] = []
	var tail: Array = []
	var in_tail: bool = false
	var f := FileAccess.open(md_path, FileAccess.READ)
	while f != null and not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.begins_with("| ") and not line.begins_with("| Asset") and not line.begins_with("|---"):
			var cells: PackedStringArray = line.split("|", false)
			if cells.size() < 3:
				continue
			var asset: String = cells[0].strip_edges()
			var paren: int = asset.find(" (`")
			if paren > 0:
				asset = asset.substr(0, paren)
			kinds[cells[1].strip_edges()] = true
			for a: String in cells[2].strip_edges().split(","):
				var who: String = a.strip_edges()
				if who == "":
					continue
				if not by_author.has(who):
					by_author[who] = []
					authors.append(who)
				(by_author[who] as Array).append(asset)
		elif line.begins_with("## "):
			in_tail = true
			tail.append(["gap", ""])
			tail.append(["head", line.substr(3).to_upper()])
		elif in_tail and line != "":
			tail.append(["small", line])
		elif not in_tail and line != "" and not line.begins_with("#") and not line.begins_with("|") and not line.begins_with("Regenerated"):
			intro.append(line.replace(" (https://polyhaven.com)", "").strip_edges())
	out.append(["head", TranslationServer.translate("MADE WITH LOVE AND JUNK")])
	out.append(["name", TranslationServer.translate("Code, procedural meshes, synthesized music and sound, and writing are original to Greenfall.")])
	out.append(["small", TranslationServer.translate("Built with the Godot Engine.")])
	out.append(["gap", ""])
	if not authors.is_empty():
		out.append(["head", TranslationServer.translate("MODELS AND TEXTURES FROM POLY HAVEN")])
		for s: String in intro:
			out.append(["small", s])
		out.append(["gap", ""])
		for who: String in authors:
			out.append(["name", who])
			out.append(["small", ", ".join(PackedStringArray(by_author[who]))])
	out.append_array(tail)
	out.append(["gap", ""])
	out.append(["gap", ""])
	out.append(["sub", TranslationServer.translate("Thank you for playing.")])
	out.append(["small", TranslationServer.translate("Lumi is still out there, planting. The Seed Ark is open.")])
	out.append(["gap", ""])
	return out


func _process(delta: float) -> void:
	if _done:
		return
	var dt: float = delta / maxf(Engine.time_scale, 0.001)  # real seconds, even in fast autoplay runs
	_t += dt
	if _t > FADE_S and not DevHooks.has("credits-hold"):
		_col.position.y -= SPEED * dt * (6.0 if DevHooks.has("autoplay") else 1.0)
	if _scroll_end < 0.0 and _col.position.y <= _scroll_end:
		skip()


func _input(event: InputEvent) -> void:
	if _done or _t < 0.6:
		return
	var press: bool = (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed)
	if press:
		get_viewport().set_input_as_handled()
		skip()


## Fades out and gives the game back.
func skip() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(_col, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(_hint, "modulate:a", 0.0, 0.5)
	tw.tween_property(_bg, "color:a", 0.0, FADE_S)
	tw.tween_callback(func() -> void:
		get_tree().paused = _was_paused
		print("[credits] done")
		finished.emit()
		queue_free())


func _exit_tree() -> void:
	if not _done and get_tree():
		get_tree().paused = _was_paused
