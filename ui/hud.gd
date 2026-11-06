class_name HUD
extends CanvasLayer
## Minimal industrial HUD. Thin type, hairline bars, one amber accent, no icons.
## Top-left: Cubes + rate. Top-right: restoration (district, planet). Bottom-center: hopper fill
## gauge with the Perfect band, context prompt, detector readout. Bottom-left: message log.

var patch: Patch
var world: Node

var _root: Control
var _cubes_label: Label
var _rate_label: Label
var _field_label: Label
var _field_bar: ProgressBar
var _planet_label: Label
var _meter: CompartmentMeter
var _meter_label: Label
var _prompt: Label
var _carry_label: Label
var _hex_label: Label
var _signal_label: Label
var _toasts: VBoxContainer
var _shown_cubes: float = 0.0
var _bump: float = 0.0
var _task_label: Label
var _task_caption: Label
var _tool_label: Label
var _goals_panel: GoalsPanel


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_build_top_left()
	_build_top_right()
	_build_bottom()
	_build_toasts()
	_goals_panel = GoalsPanel.new()
	_goals_panel.hud = self
	_root.add_child(_goals_panel)
	EventBus.compartment_changed.connect(_on_compartment)
	EventBus.toast.connect(show_toast)
	EventBus.cube_cashed.connect(func(_v: BigNum, _p: Vector3) -> void: _bump = 1.0)


func _margin(preset: Control.LayoutPreset, m: int = 22) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(preset)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT]:
		mc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif preset in [Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER_TOP, Control.PRESET_CENTER]:
		mc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM]:
		mc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	elif preset in [Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER]:
		mc.grow_vertical = Control.GROW_DIRECTION_BOTH
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, m)
	_root.add_child(mc)
	return mc


static func _caption(text: String) -> Label:
	return UITheme.label(text, 12, UITheme.MUTED)


func _build_top_left() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_TOP_LEFT)
	# Dark glass card so the text reads over bright litter and sky (matches the goals card).
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, UITheme.RUST, 1, 6, 12))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	card.add_child(vb)
	_rate_label = _caption("C U B E S")
	vb.add_child(_rate_label)
	_cubes_label = UITheme.label("0", 38, UITheme.CREAM)
	vb.add_child(_cubes_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	vb.add_child(gap)
	_task_caption = _caption("")
	vb.add_child(_task_caption)
	_task_label = UITheme.label("", 16, UITheme.CREAM)
	_task_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_task_label.custom_minimum_size = Vector2(360, 0)
	vb.add_child(_task_label)
	EventBus.tutorial_changed.connect(_on_task)


func _build_top_right() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_TOP_RIGHT)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(230, 0)
	vb.add_theme_constant_override("separation", 3)
	mc.add_child(vb)
	_field_label = UITheme.label("OLD TOWN  0.0%", 15, UITheme.CREAM)
	_field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_field_label)
	_field_bar = ProgressBar.new()
	_field_bar.custom_minimum_size = Vector2(0, 3)
	_field_bar.show_percentage = false
	_field_bar.max_value = 1.0
	vb.add_child(_field_bar)
	_planet_label = _caption("VERDANCE  0.0000%")
	_planet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_planet_label)


func _build_bottom() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_CENTER_BOTTOM, 26)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 5)
	mc.add_child(vb)
	_signal_label = UITheme.label("", 15, Color(1, 0.35, 0.3))
	_signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_signal_label)
	_prompt = UITheme.label("", 16, UITheme.CREAM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_prompt)
	# Tool / seeds / compost / water readout gets its own centred line so the hopper row stays
	# narrow and clear of the bottom-left toast log at 1280x720.
	_tool_label = _caption("")
	_tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tool_label.visible = false
	vb.add_child(_tool_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(_caption("HOPPER"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_carry_label = _caption("")
	row.add_child(_carry_label)
	_meter_label = _caption("0.0 / 10")
	row.add_child(_meter_label)
	_meter = CompartmentMeter.new()
	vb.add_child(_meter)
	_hex_label = _caption("")
	_hex_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hex_label)


func _build_toasts() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_BOTTOM_LEFT)
	_toasts = VBoxContainer.new()
	_toasts.custom_minimum_size = Vector2(340, 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(_toasts)


func _on_compartment(fill: float, cap: float) -> void:
	_meter.set_values(fill, cap)


func _process(delta: float) -> void:
	var cubes: BigNum = GameState.get_currency("cubes")
	var target: float = cubes.to_float()
	if target < 1.0e9:
		_shown_cubes = lerpf(_shown_cubes, target, clampf(delta * 10.0, 0.0, 1.0))
		if absf(_shown_cubes - target) < 0.5:
			_shown_cubes = target
		_cubes_label.text = Settings.fmt(BigNum.from_float(round(_shown_cubes)))
	else:
		_cubes_label.text = Settings.fmt(cubes)
	var rate: float = GameState.income_rate()
	_rate_label.text = "C U B E S" + (("    +%s / s" % Settings.fmt(BigNum.from_float(rate))) if rate > 0.0 else "")
	_bump = maxf(0.0, _bump - delta * 3.0)
	_cubes_label.add_theme_color_override("font_color", UITheme.CREAM.lerp(UITheme.GOLD, _bump))
	if world and world.field:
		var f: HexField = world.field
		var pct: float = float(f.cleaned_count) / maxf(f.junk_hex_count, 1)
		_field_label.text = "%s   %.1f%%" % [str(world.district_name).to_upper(), pct * 100.0]
		_field_bar.value = pct
		var pl: PlanetData = world.planet if world.get("planet") != null else null
		var frac: float = pl.restored_fraction() if pl else 0.0
		_planet_label.text = "%s   %s%%      %s  map" % [str(Economy.planet.get("name", "Verdance")).to_upper(), _fmt_small_pct(frac * 100.0), Settings.glyph("open_globe")]
	if patch:
		if patch.detector and not patch.detector.readout_changed.is_connected(_on_signal):
			patch.detector.readout_changed.connect(_on_signal)
		_meter_label.text = "%.1f / %.0f" % [patch.compartment.fill, patch.capacity()]
		if GameState.flags.get("seeds_unlocked", false):
			var names: Array[String] = ["SCOOP", "PLANT", "WATER"]
			_tool_label.visible = true
			_tool_label.text = "%s   %s    SEEDS %s    COMPOST %s    WATER %d/%d" % [_tool_keys(), names[patch.tool], Settings.fmt(GameState.get_currency("seeds")), Settings.fmt(GameState.get_currency("compost")), int(patch.water), int(patch.water_cap())]
		_meter.set_values(patch.compartment.fill, patch.capacity())
		_meter.band = Economy.cube_rules.get("perfect_band", [0.9, 1.0])
		var cap: int = patch.carry_cap()
		_carry_label.text = ("CARRYING %d/%d    " % [patch.carried.size(), cap]) if not patch.carried.is_empty() else ""
		_prompt.text = _prompt_text(patch.prompt)
		var h: int = patch.focus_hex()
		if h >= 0 and world.field.hex_hub[h] == 0:
			_hex_label.text = ("HEX  %d%% CLEAR" % int(floor(world.field.removed_fraction(h) * 100.0))) if not world.field.is_clean(h) else (world.hex_levels.describe(h) if world.get("hex_levels") else "HEX  CLEAR")
		else:
			_hex_label.text = ""


func _on_task(text: String) -> void:
	_task_caption.text = "R E S T A R T   C H E C K L I S T" if text != "" else ""
	_task_label.text = text
	_task_label.modulate.a = 0.0
	create_tween().tween_property(_task_label, "modulate:a", 1.0, 0.4)


func _on_signal(text: String, color: Color, strength: float) -> void:
	_signal_label.text = text
	_signal_label.add_theme_color_override("font_color", color)
	_signal_label.modulate.a = 0.5 + strength * 0.5


func _fmt_small_pct(p: float) -> String:
	if p <= 0.0:
		return "0.0000"
	if p < 0.01:
		return "%.4f" % p
	if p < 1.0:
		return "%.3f" % p
	return "%.2f" % p


## Prompt line; the button glyph follows the last input device ("E  interact" / "A  interact").
func _prompt_text(kind: String) -> String:
	var g: String = Settings.glyph("interact")
	match kind:
		"pick_up": return g + "   pick up bale"
		"dig": return g + "   dig up part"
		"shard": return g + "   read memory shard"
		"seed": return g + "   pick up the seed tin"
		"place": return g + "   set bale down"
		"upgrades": return g + "   workbench"
	if kind.begins_with("E "):
		return g + kind.substr(1)
	return ""


## Tool-switch keys for the tool readout ("1 2 3" on keyboard, "D-pad" on a controller).
func _tool_keys() -> String:
	if Settings.last_input_pad:
		return "D-PAD"
	return "%s %s %s" % [Settings.glyph("tool_scoop"), Settings.glyph("tool_plant"), Settings.glyph("tool_water")]


func show_toast(text: String, kind: String = "info") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(2, 0)
	bar.color = UITheme.GOLD if kind == "story" else (UITheme.GREEN if kind == "hint" else UITheme.MUTED)
	row.add_child(bar)
	var l := UITheme.label(text, 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(320, 0)
	row.add_child(l)
	row.modulate.a = 0.0
	_toasts.add_child(row)
	while _toasts.get_child_count() > 4:
		var old: Node = _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.3)
	tw.tween_interval(6.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.8)
	tw.tween_callback(row.queue_free)
