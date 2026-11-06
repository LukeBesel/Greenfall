class_name HUD
extends CanvasLayer
## In-game HUD. Sleek and sparse: thin type, hairlines, soft glass, no heavy boxes.
##   top-left      main currency (Cubes) with a count-up and rate; other currencies as brief chips
##                 (ui/currency_cluster.gd)
##   top-right     district line (fades when unchanged) and the compact goal tracker with the
##                 restart checklist (ui/goals_panel.gd; G / L3 expands)
##   bottom-centre hotbar with the Lumi Level bar above and the hopper gauge below (ui/hotbar.gd);
##                 above it the interact prompt and a contextual readout (hex %, part signal,
##                 carried bales) that only shows while relevant
##   bottom-left   one notification stack for toasts, achievements and story lines (ui/notify_stack.gd)
##   bottom-right  key hints (Full mode, or during the restart checklist)
## Settings.hud_mode: FULL (no auto-fade), MINIMAL (default: extras fade after a few seconds without
## change), HIDDEN (only prompts and notifications).
## Public API kept for callers: show_toast(text, kind), visible, patch, world. New: notify(),
## set_core_charge(f) (Bloom Core ring by the level bar), hotbar, goals.

const FADE_AFTER_S: float = 6.0
const CONTEXT_HOLD_S: float = 3.0

var patch: Patch
var world: Node

var hotbar: Hotbar
var goals: GoalsPanel
var lumi: LumiLevel

var _root: Control
var _currency: CurrencyCluster
var _district: VBoxContainer
var _field_label: Label
var _field_bar: Control
var _field_frac: float = 0.0
var _planet_label: Label
var _prompt: Label
var _context: Label
var _notify: NotifyStack
var _hints: Label
var _goals_panel: GoalsPanel  # legacy name (same node as `goals`)
var _district_sig: String = ""
var _district_idle: float = 0.0
var _context_sig: String = ""
var _context_idle: float = 99.0
var _signal_text: String = ""
var _signal_color: Color = Color.WHITE
var _signal_strength: float = 0.0
var _top_left: MarginContainer
var _top_right: MarginContainer
var _bottom: Control


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	lumi = (world.get("lumi_level") as LumiLevel) if world else null
	_build_top_left()
	_build_top_right()
	_build_bottom()
	_build_notify()
	_build_hints()
	EventBus.compartment_changed.connect(_on_compartment)
	EventBus.toast.connect(show_toast)
	if lumi:
		lumi.leveled.connect(func(lv: int, rw: String) -> void:
			notify("Lumi reached level %d%s" % [lv, ("  ·  " + rw) if rw != "" else ""], "level"))
	Settings.changed.connect(_apply_mode)
	_apply_mode()


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


func _build_top_left() -> void:
	_top_left = _margin(Control.PRESET_TOP_LEFT)
	_currency = CurrencyCluster.new()
	_top_left.add_child(_currency)


func _build_top_right() -> void:
	_top_right = _margin(Control.PRESET_TOP_RIGHT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_right.add_child(vb)
	_district = VBoxContainer.new()
	_district.add_theme_constant_override("separation", 3)
	_district.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_district)
	_field_label = UITheme.label("OLD TOWN   0%", 13, UITheme.CREAM)
	_field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_district.add_child(_field_label)
	_field_bar = Control.new()
	_field_bar.custom_minimum_size = Vector2(GoalsPanel.W, 3)
	_field_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_bar.draw.connect(func() -> void:
		var w: float = 120.0
		var x0: float = _field_bar.size.x - w
		_field_bar.draw_rect(Rect2(x0, 0, w, 2), Color(1, 1, 1, 0.14))
		_field_bar.draw_rect(Rect2(x0, 0, w * _field_frac, 2), UITheme.GREEN))
	_district.add_child(_field_bar)
	_planet_label = UITheme.label("", 12, UITheme.MUTED)
	_planet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_district.add_child(_planet_label)
	goals = GoalsPanel.new()
	goals.hud = self
	vb.add_child(goals)
	_goals_panel = goals


func _build_bottom() -> void:
	_bottom = Control.new()
	_bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bottom)
	hotbar = Hotbar.new()
	hotbar.patch = patch
	hotbar.world = world
	hotbar.lumi = lumi
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var sz := Vector2(Hotbar.LEVEL_W + 260.0, 150.0)
	hotbar.offset_left = -sz.x * 0.5
	hotbar.offset_right = sz.x * 0.5
	hotbar.offset_top = -sz.y - 8.0
	hotbar.offset_bottom = -8.0
	_bottom.add_child(hotbar)
	# Prompt and contextual readout, just above the level bar.
	var mc: MarginContainer = _margin(Control.PRESET_CENTER_BOTTOM, 0)
	mc.add_theme_constant_override("margin_bottom", 130)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(vb)
	_prompt = UITheme.label("", 16, UITheme.CREAM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_prompt)
	_context = UITheme.label("", 13, UITheme.MUTED)
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context.custom_minimum_size = Vector2(420, 0)
	_context.modulate.a = 0.0
	vb.add_child(_context)


func _build_notify() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_BOTTOM_LEFT)
	_notify = NotifyStack.new()
	mc.add_child(_notify)


func _build_hints() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_BOTTOM_RIGHT)
	_hints = UITheme.label("", 12, Color(UITheme.MUTED, 0.9))
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mc.add_child(_hints)


func _apply_mode() -> void:
	var hidden: bool = Settings.hud_mode == Settings.HudMode.HIDDEN
	_top_left.visible = not hidden
	_top_right.visible = not hidden
	hotbar.visible = not hidden
	_context.visible = not hidden


func _on_compartment(fill: float, cap: float) -> void:
	hotbar.set_hopper(fill, cap)


# --- Public API ----------------------------------------------------------------------------

func show_toast(text: String, kind: String = "info") -> void:
	_notify.push(text, kind)


func notify(text: String, kind: String = "info") -> void:
	_notify.push(text, kind)


## Bloom Core charge 0..1, drawn as a tiny ring at the left end of the level bar.
func set_core_charge(f: float) -> void:
	hotbar.set_core_charge(f)


# --- Frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var minimal: bool = Settings.hud_mode == Settings.HudMode.MINIMAL
	if world and world.field:
		var f: HexField = world.field
		var pct: float = float(f.cleaned_count) / maxf(f.junk_hex_count, 1)
		_field_frac = pct
		_field_label.text = "%s   %d%%" % [str(world.district_name).to_upper(), int(floor(pct * 100.0))]
		var pl: PlanetData = world.planet if world.get("planet") != null else null
		var frac: float = pl.restored_fraction() if pl else 0.0
		_planet_label.text = "%s   %s%%" % [str(Economy.planet.get("name", "Verdance")).to_upper(), _fmt_small_pct(frac * 100.0)]
		_field_bar.queue_redraw()
		var sig: String = _field_label.text + _planet_label.text
		if sig != _district_sig:
			_district_sig = sig
			_district_idle = 0.0
	_district_idle += delta
	var dwant: float = 1.0 if not minimal or _district_idle < FADE_AFTER_S else 0.0
	_district.modulate.a = move_toward(_district.modulate.a, dwant, delta * (3.0 if dwant > 0.0 else 0.6))
	if patch:
		if patch.detector and not patch.detector.readout_changed.is_connected(_on_signal):
			patch.detector.readout_changed.connect(_on_signal)
		hotbar.set_hopper(patch.compartment.fill, patch.capacity())
		_prompt.text = _prompt_text(patch.prompt)
		_update_context(delta, minimal)
	_update_hints()


## Hex %, part signal and carried bales in one quiet line that only shows while relevant:
## for a few seconds after it changes (scooping, a level-up), or while a part signal is strong.
func _update_context(delta: float, minimal: bool) -> void:
	var bits: Array[String] = []
	if not patch.carried.is_empty():
		bits.append("CARRYING %d/%d" % [patch.carried.size(), patch.carry_cap()])
	var h: int = patch.focus_hex()
	var hex_text: String = ""
	if h >= 0 and world and world.field.hex_hub[h] == 0:
		hex_text = ("HEX  %d%% CLEAR" % int(floor(world.field.removed_fraction(h) * 100.0))) if not world.field.is_clean(h) else (world.hex_levels.describe(h) if world.get("hex_levels") else "HEX  CLEAR")
		var op: Variant = world.get("outposts")  # [outposts] note the outpost on this hex
		if op is Outposts and (op as Outposts).hex_note(h) != "":
			hex_text += "   ·   " + (op as Outposts).hex_note(h)
	if hex_text != "":
		bits.append(hex_text)
	var strong: bool = _signal_text != "" and (_signal_strength >= 0.5 or not minimal)
	if strong:
		bits.append(_signal_text)
	var text: String = "    ·    ".join(bits)
	# Only a change of the hex/carry part counts as "new"; the signal shows while it is strong.
	var sig: String = hex_text + str(patch.carried.size())
	if sig != _context_sig:
		_context_sig = sig
		_context_idle = 0.0
	_context_idle += delta
	_context.text = text
	_context.add_theme_color_override("font_color", _signal_color if strong and hex_text == "" else UITheme.MUTED)
	var want: float = 1.0 if (not minimal or _context_idle < CONTEXT_HOLD_S or strong or not patch.carried.is_empty()) and text != "" else 0.0
	if hotbar.celebrating():
		want = 0.0
	_context.modulate.a = move_toward(_context.modulate.a, want, delta * (4.0 if want > 0.0 else 1.2))


func _on_signal(text: String, color: Color, strength: float) -> void:
	_signal_text = text
	_signal_color = color
	_signal_strength = strength


func _update_hints() -> void:
	var tutorial_on: bool = int(GameState.flags.get("tutorial_step", 0)) < Tutorial.STEPS.size()
	var show: bool = Settings.hud_mode == Settings.HudMode.FULL or (Settings.hud_mode == Settings.HudMode.MINIMAL and tutorial_on)
	_hints.visible = show
	if show:
		_hints.text = "%s  map      %s  command      %s  lens      %s  goals" % [Settings.glyph("open_globe"), Settings.glyph("open_command"), Settings.glyph("lens_view"), Settings.glyph("toggle_goals")]


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
