class_name HUD
extends CanvasLayer
## In-game HUD: Cubes with rate, restoration percent (field + planet), compartment meter,
## context prompt, carry count, hex readout, toast feed, upgrades badge, control hints.

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
var _toasts: VBoxContainer
var _upgrade_btn: Button
var _hints: Label
var _shown_cubes: float = 0.0
var _cube_icon: UIIcon
var _bump: float = 0.0


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
	_build_bottom_right()
	EventBus.currency_changed.connect(_on_currency)
	EventBus.compartment_changed.connect(_on_compartment)
	EventBus.toast.connect(show_toast)
	EventBus.cube_cashed.connect(func(_v: BigNum, _p: Vector3) -> void: _bump = 1.0)


func _margin(preset: Control.LayoutPreset, m: int = 16) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(preset)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Grow away from the anchored edge so content stays on screen.
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


func _build_top_left() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_TOP_LEFT)
	var panel := PanelContainer.new()
	mc.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	panel.add_child(hb)
	_cube_icon = UIIcon.new("cube", 52, UITheme.GOLD)
	hb.add_child(_cube_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	hb.add_child(vb)
	_cubes_label = UITheme.label("0", 40, UITheme.GOLD)
	vb.add_child(_cubes_label)
	_rate_label = UITheme.label("cubes", 16, UITheme.MUTED)
	vb.add_child(_rate_label)


func _build_top_right() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_TOP_RIGHT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 0)
	mc.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	_field_label = UITheme.label("Junkyard  0%", 20)
	vb.add_child(_field_label)
	_field_bar = ProgressBar.new()
	_field_bar.custom_minimum_size = Vector2(0, 14)
	_field_bar.show_percentage = false
	_field_bar.max_value = 1.0
	vb.add_child(_field_bar)
	_planet_label = UITheme.label("Verdance  0.0000%", 16, UITheme.MUTED)
	vb.add_child(_planet_label)


func _build_bottom() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_CENTER_BOTTOM, 18)
	mc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 6)
	mc.add_child(vb)
	_prompt = UITheme.label("", 22, UITheme.CREAM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_prompt)
	_hex_label = UITheme.label("", 16, UITheme.MUTED)
	_hex_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hex_label)
	var panel := PanelContainer.new()
	vb.add_child(panel)
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	var row := HBoxContainer.new()
	inner.add_child(row)
	var t := UITheme.label("COMPARTMENT", 15, UITheme.MUTED)
	row.add_child(t)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_meter_label = UITheme.label("0 / 10", 15, UITheme.CREAM)
	row.add_child(_meter_label)
	_meter = CompartmentMeter.new()
	inner.add_child(_meter)


func _build_toasts() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_CENTER_LEFT)
	_toasts = VBoxContainer.new()
	_toasts.custom_minimum_size = Vector2(320, 0)
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(_toasts)


func _build_bottom_right() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_BOTTOM_RIGHT)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	mc.add_child(vb)
	_carry_label = UITheme.label("", 20, UITheme.CREAM)
	_carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_carry_label)
	_upgrade_btn = Button.new()
	_upgrade_btn.text = "Upgrades  [Tab]"
	_upgrade_btn.focus_mode = Control.FOCUS_NONE
	_upgrade_btn.custom_minimum_size = Vector2(200, 52)
	_upgrade_btn.pressed.connect(func() -> void: if world: world.open_upgrades())
	vb.add_child(_upgrade_btn)
	var hm: MarginContainer = _margin(Control.PRESET_BOTTOM_LEFT)
	_hints = UITheme.label("WASD move · Hold LMB/Space scoop · RMB/C cube · E pick up / place · Q drop · Tab upgrades · Wheel zoom · V lens", 14, Color(1, 1, 1, 0.6))
	_hints.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hints.custom_minimum_size = Vector2(300, 0)
	hm.add_child(_hints)


func _on_currency(id: String, _amount: BigNum) -> void:
	if id == "cubes":
		_bump = maxf(_bump, 0.6)


func _on_compartment(fill: float, cap: float) -> void:
	_meter.set_values(fill, cap)


func _process(delta: float) -> void:
	var cubes: BigNum = GameState.get_currency("cubes")
	# Tick the number up smoothly for small values; exact for big ones.
	var target: float = cubes.to_float()
	if target < 1.0e9:
		_shown_cubes = lerpf(_shown_cubes, target, clampf(delta * 10.0, 0.0, 1.0))
		if absf(_shown_cubes - target) < 0.5:
			_shown_cubes = target
		_cubes_label.text = Settings.fmt(BigNum.from_float(round(_shown_cubes)))
	else:
		_cubes_label.text = Settings.fmt(cubes)
	var rate: float = GameState.income_rate()
	_rate_label.text = ("cubes  ·  +%s/s" % Settings.fmt(BigNum.from_float(rate))) if rate > 0.0 else "cubes"
	_bump = maxf(0.0, _bump - delta * 4.0)
	_cubes_label.pivot_offset = _cubes_label.size * Vector2(0.0, 0.5)
	_cubes_label.scale = Vector2.ONE * (1.0 + _bump * 0.12)
	if world and world.field:
		var f: HexField = world.field
		var pct: float = float(f.cleaned_count) / maxf(f.junk_hex_count, 1)
		_field_label.text = "Junkyard  %.1f%%" % (pct * 100.0)
		_field_bar.value = pct
		var total: float = float(Economy.planet.get("total_hexes", 40962))
		_planet_label.text = "%s  %s%%" % [Economy.planet.get("name", "Verdance"), _fmt_small_pct(float(f.cleaned_count) / total * 100.0)]
	if patch:
		_meter_label.text = "%.1f / %.0f" % [patch.compartment.fill, patch.capacity()]
		_meter.set_values(patch.compartment.fill, patch.capacity())
		_meter.band = Economy.cube_rules.get("perfect_band", [0.9, 1.0])
		var cap: int = patch.carry_cap()
		_carry_label.text = "Carrying %d / %d" % [patch.carried.size(), cap] if not patch.carried.is_empty() or cap > 1 else ""
		_prompt.text = _prompt_text(patch.prompt)
		var h: int = patch.focus_hex()
		if h >= 0 and world.field.hex_hub[h] == 0:
			_hex_label.text = "This hex: %d%% clean" % int(floor(world.field.removed_fraction(h) * 100.0)) if not world.field.is_clean(h) else "This hex: CLEAN"
		else:
			_hex_label.text = ""
	var affordable: bool = false
	for id: String in Economy.upgrade_order:
		if Economy.is_unlocked(id) and not Economy.is_maxed(id) and GameState.can_afford("cubes", Economy.upgrade_cost(id)):
			affordable = true
			break
	_upgrade_btn.text = "Upgrades  [Tab]" + ("  ●" if affordable else "")
	_upgrade_btn.modulate = Color(1.15, 1.1, 0.8) if affordable else Color.WHITE


func _fmt_small_pct(p: float) -> String:
	if p <= 0.0:
		return "0.0000"
	if p < 0.01:
		return "%.4f" % p
	if p < 1.0:
		return "%.3f" % p
	return "%.2f" % p


func _prompt_text(kind: String) -> String:
	match kind:
		"pick_up": return "[E]  Pick up cube"
		"place": return "[E]  Place cube    ·    roll onto the Depot pad to cash in"
		"upgrades": return "[E]  Upgrade Board"
		"flower": return "A tiny wildflower. Patch is careful not to scoop it."
	return ""


func show_toast(text: String, kind: String = "info") -> void:
	var panel := PanelContainer.new()
	var accent: Color = UITheme.GOLD if kind == "story" else (UITheme.GREEN if kind == "hint" else UITheme.TEAL)
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, accent, 3, 12, 10))
	var l := UITheme.label(text, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(300, 0)
	panel.add_child(l)
	panel.modulate.a = 0.0
	_toasts.add_child(panel)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).queue_free()
		_toasts.remove_child(_toasts.get_child(0))
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_interval(5.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(panel.queue_free)
	Audio.play("click", 1.4, -12.0)
