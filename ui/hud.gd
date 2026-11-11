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
##   bottom-right  key hints in a readable pill (ui/key_hints.gd): the first minutes, Full mode, or
##                 while Tab is held away from the workbench [onboard]
## Settings.hud_mode: FULL (no auto-fade), MINIMAL (default: extras fade after a few seconds without
## change), HIDDEN (only prompts and notifications).
## Public API kept for callers: show_toast(text, kind), visible, patch, world. New: notify(),
## set_core_charge(f) (Bloom Core ring by the level bar), hotbar, goals.

const FADE_AFTER_S: float = 6.0
const CONTEXT_HOLD_S: float = 3.0
const CONTEXT_COLOR := Color(0.8, 0.82, 0.8)  # [onboard] brighter than UITheme.MUTED

var _planet_t: float = 0.0  # [orbE] planet % refresh timer
var _planet_frac: float = 0.0
var patch: Patch
var world: Node

var hotbar: Hotbar
var goals: GoalsPanel
var lumi: LumiLevel

var _root: Control
var _currency: CurrencyCluster
var _district: VBoxContainer
var _district_card: PanelContainer  # [v7look] the glass card around the base / planet lines
var _field_label: Label
var _field_bar: Control
var _field_frac: float = 0.0
var _planet_label: Label
var _relay_label: Label  # [onboard] the Signal Tower's relay signal: how well WREN can reach Lumi
var _prompt: Label
var _context: Label
var _notify: NotifyStack
var _hints: KeyHints  # [onboard] was a 12 px muted label
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
var _hints_give: float = 1.0  # [v7look] 0 while WREN's bar overlaps the key-hint pill
var _hints_mc: MarginContainer  # [v7look] lifted over the hotbar's readouts on narrow screens
var _hold_corner_s: float = 0.0
var _hold_all: bool = false  # [v7look] hold_corner(s, true): the bottom band steps aside too  # [v7look] seconds the top-right cards stay faded out (hold_corner)
var _bottom: Control
var _scrims: Control


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudReadable.theme()  # [onboard] heavier halo + font so HUD text reads over busy scenes
	add_child(_root)
	_build_scrims()
	lumi = (world.get("lumi_level") as LumiLevel) if world else null
	_build_top_left()
	var coins := CoinFlight.new()  # [first] sale cubes fly into the counter
	coins.cluster = _currency
	_root.add_child(coins)
	_build_top_right()
	_build_bottom()
	_build_notify()
	_build_hints()
	EventBus.compartment_changed.connect(_on_compartment)
	EventBus.toast.connect(show_toast)
	if lumi:
		lumi.leveled.connect(func(lv: int, rw: String) -> void:
			notify(tr("Lumi reached level %d%s") % [lv, ("  ·  " + rw) if rw != "" else ""], "level"))
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


## Soft dark radial scrims behind the corners and the hotbar (no boxes) so thin text and lines
## read over bright litter and sky.
func _build_scrims() -> void:
	_scrims = Control.new()
	_scrims.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrims.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_scrims)
	var spec: Array = [
		# [anchor, size, gradient centre (UV), gradient edge (UV)]
		[Control.PRESET_TOP_LEFT, Vector2(460, 220), Vector2(0, 0), Vector2(1, 0)],
		[Control.PRESET_TOP_RIGHT, Vector2(560, 380), Vector2(1, 0), Vector2(0, 0)],  # [onboard] taller: objective card
		[Control.PRESET_CENTER_BOTTOM, Vector2(760, 380), Vector2(0.5, 1), Vector2(1, 1)],
	]
	for e: Array in spec:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.42))
		g.set_color(1, Color(0, 0, 0, 0.0))
		g.add_point(0.5, Color(0, 0, 0, 0.2))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = e[2]
		gt.fill_to = e[3]
		gt.width = 128
		gt.height = 64
		var tr_ := TextureRect.new()
		tr_.texture = gt
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.stretch_mode = TextureRect.STRETCH_SCALE
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr_.set_anchors_preset(e[0])
		var sz: Vector2 = e[1]
		match e[0]:
			Control.PRESET_TOP_LEFT:
				tr_.offset_right = sz.x
				tr_.offset_bottom = sz.y
			Control.PRESET_TOP_RIGHT:
				tr_.offset_left = -sz.x
				tr_.offset_bottom = sz.y
			_:
				tr_.offset_left = -sz.x * 0.5
				tr_.offset_right = sz.x * 0.5
				tr_.offset_top = -sz.y
		_scrims.add_child(tr_)


func _build_top_left() -> void:
	_top_left = _margin(Control.PRESET_TOP_LEFT)
	_currency = CurrencyCluster.new()
	_top_left.add_child(_currency)


func _build_top_right() -> void:
	_top_right = _margin(Control.PRESET_TOP_RIGHT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)  # [v7look] card to card, like the goal stack
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_right.add_child(vb)
	# [v7look] The base / planet lines as one glass card in the goal cards' style (they were two faint
	# floating lines that crowded the card under them): the base's name and %, a real bar, the bases.
	_district_card = PanelContainer.new()
	var dsb := UITheme.box(Color(0.03, 0.04, 0.05, 0.55), Color(0.9, 0.9, 0.85, 0.14), 1, 11, 0)
	dsb.content_margin_left = 14
	dsb.content_margin_right = 14
	dsb.content_margin_top = 8
	dsb.content_margin_bottom = 9
	_district_card.add_theme_stylebox_override("panel", dsb)
	_district_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_district_card.custom_minimum_size = Vector2(ChecklistCard.W, 0)
	_district_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	_district = VBoxContainer.new()
	_district.add_theme_constant_override("separation", 5)
	_district.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_district_card.add_child(_district)
	_field_label = UITheme.label(tr("OLD TOWN   0%"), 15, UITheme.CREAM)
	_district.add_child(_field_label)
	_field_bar = Control.new()
	_field_bar.custom_minimum_size = Vector2(0, 6)
	_field_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field_bar.draw.connect(func() -> void:
		var w: float = _field_bar.size.x
		_field_bar.draw_rect(Rect2(0, 0, w, 6), Color(1, 1, 1, 0.16))
		if _field_frac > 0.0:
			_field_bar.draw_rect(Rect2(0, 0, maxf(w * _field_frac, 6.0), 6), UITheme.GREEN))
	_district.add_child(_field_bar)
	_planet_label = UITheme.label("", 13, Color(UITheme.CREAM, 0.82))
	_district.add_child(_planet_label)
	_relay_label = UITheme.label("", 13, Color(0.6, 0.85, 1.0))
	_district.add_child(_relay_label)
	goals = GoalsPanel.new()
	goals.hud = self
	vb.add_child(goals)
	_goals_panel = goals
	# [v7look] under the goal stack: what to do comes first, and when the card fades (minimal HUD)
	# it leaves no hole above the goal card
	vb.add_child(_district_card)


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
	mc.add_theme_constant_override("margin_bottom", 168)  # [v3clear] above the level bar (the hex line sat on it)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(vb)
	_prompt = UITheme.label("", 16, UITheme.CREAM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_prompt)
	_context = UITheme.label("", 14, CONTEXT_COLOR)  # [onboard] 13 px muted was hard to read
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context.custom_minimum_size = Vector2(360, 0)
	_context.clip_text = true  # [vqa] one short phrase; never wider than the hotbar area
	_context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_context.modulate.a = 0.0
	vb.add_child(_context)


func _build_notify() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_BOTTOM_LEFT)
	# [vqa] Sits above the hotbar / level-bar band (bottom 150 px), never beside it.
	mc.add_theme_constant_override("margin_bottom", 250)  # [onboard] above WREN's subtitle band too: no overlap
	_notify = NotifyStack.new()
	mc.add_child(_notify)


func _build_hints() -> void:
	var mc: MarginContainer = _margin(Control.PRESET_BOTTOM_RIGHT)
	_hints_mc = mc
	_hints = KeyHints.new()  # [onboard] readable pill; shows itself when it should (KeyHints.want_shown)
	_hints.world = world
	mc.add_child(_hints)


## [v7look] Fades the top-right cards (base line, goal stack) out for `s` seconds and then back, so a
## big centred moment (a base's arrival title) has the top of the screen to itself. 0 releases now.
## With `all`, the hotbar band and the key hints step aside too (an arrival title: nothing else on screen).
func hold_corner(s: float, all: bool = false) -> void:
	_hold_corner_s = s  # the cards fade in 0.25 s, about as fast as the title fades in
	_hold_all = all and s > 0.0


## [v7look] Top of the key-hint pill while it is lifted over the hotbar (narrow screens) and showing,
## else INF: the subtitle bar keeps above it (Subtitles._prompt_top).
func hints_top() -> float:
	if _hints_mc == null or _hints_mc.get_theme_constant("margin_bottom") <= 22 or _hints == null:
		return INF
	if not _hints.is_visible_in_tree() or _hints.modulate.a < 0.05 or _hints.size.y < 1.0:
		return INF
	return _hints.get_global_rect().position.y


## [v7look] The top-right cards' rect while they show (alpha over 0.1), else an empty rect (tools/ui_audit_run.gd).
func corner_rect() -> Rect2:
	if not _top_right.is_visible_in_tree() or _top_right.modulate.a <= 0.1:
		return Rect2()
	var r := Rect2()
	for c: Control in [_district_card, goals]:
		if c and c.is_visible_in_tree() and c.modulate.a > 0.1:
			r = c.get_global_rect() if r.size == Vector2.ZERO else r.merge(c.get_global_rect())
	return r


## [onboard] Tab away from the workbench: the full key list for a few seconds (scenes/slice.gd).
func peek_hints() -> void:
	_hints.peek(3.0)


func _apply_mode() -> void:
	var hidden: bool = Settings.hud_mode == Settings.HudMode.HIDDEN
	_top_left.visible = not hidden
	_scrims.visible = not hidden
	_top_right.visible = not hidden
	hotbar.visible = not hidden
	_context.visible = not hidden


func _on_compartment(fill: float, cap: float) -> void:
	hotbar.set_hopper(fill, cap)


# --- Public API ----------------------------------------------------------------------------

## [onboard2] One message line: toasts go to the subtitle bar's queue (ui/subtitles.gd), one at a
## time with reading time. The old bottom-left stack is only a fallback where there is no bar.
func show_toast(text: String, kind: String = "info") -> void:
	if Subtitles.cut(text, kind):  # [v4calm] item 49: reward chatter never shows
		return
	if not Subtitles.post(text, kind):
		_notify.push(text, kind)


func notify(text: String, kind: String = "info") -> void:
	show_toast(text, kind)


## Bloom Core charge 0..1, drawn as a tiny ring at the left end of the level bar.
func set_core_charge(f: float) -> void:
	hotbar.set_core_charge(f)


# --- Frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var minimal: bool = Settings.hud_mode == Settings.HudMode.MINIMAL
	var cc: Variant = world.get("core_charge") if world else null  # [story2] Bloom Core ring by the level bar
	if cc is CoreCharge:
		set_core_charge((cc as CoreCharge).shown)
	if world and world.field:
		var f: HexField = world.field
		var pct: float = float(f.cleaned_count) / maxf(f.junk_hex_count, 1)
		_field_frac = pct
		_field_label.text = "%s   %d%%" % [str(world.district_name).to_upper(), int(floor(pct * 100.0))]
		# [orbE] The planet % walks every hub-region cell on a globe (Anvil: ~3.5 ms a frame): a few
		# times a second is plenty for a percentage.
		_planet_t -= get_process_delta_time()
		if _planet_t <= 0.0:
			_planet_t = 0.25
			var pl: PlanetData = world.planet if world.get("planet") != null else null
			_planet_frac = pl.restored_fraction() if pl else 0.0
			var orb: Variant = world.get("orbit")  # [orbD] globe: planet % over the hub regions
			if orb is SliceOrbit and (orb as SliceOrbit).sites:
				_planet_frac = (orb as SliceOrbit).sites.planet_fraction()
			elif world.has_method("planet_fraction"):
				_planet_frac = world.planet_fraction()
		var frac: float = _planet_frac
		_planet_label.text = "%s   %s%%" % [str(Economy.planet.get("name", "Verdance")).to_upper(), _fmt_small_pct(frac * 100.0)]
		if world.get("orbit") is SliceOrbit:  # [orbB] the globe has no district: one planet line (hub regions), its bar
			_field_label.text = _planet_label.text
			_field_frac = frac
			_planet_label.visible = false
			var hp: HubPurpose = (world.get("orbit") as SliceOrbit).sites.purpose if (world.get("orbit") as SliceOrbit).sites else null
			var hl: Dictionary = hp.hud_lines() if hp and hp.is_processing() else {}
			if not hl.is_empty():  # [v6hubs] this base's clean %, and the bases restored (the way onward) instead of a planet % that drops at each new base
				_field_label.text = str(hl["field"])
				_field_frac = float(hl["frac"])
				_planet_label.text = str(hl["planet"])
				_planet_label.visible = true
		_field_bar.queue_redraw()
		_relay_label.text = tr("WREN SIGNAL   %d%%") % SignalTower.signal_pct()
		_relay_label.visible = SignalTower.tier() > 0  # [v3clear] hide what isn't relevant yet: no 0% before the tower
		var sig: String = _field_label.text + _planet_label.text + _relay_label.text
		if sig != _district_sig:
			_district_sig = sig
			_district_idle = 0.0
	_district_idle += delta
	var dwant: float = 1.0 if not minimal or _district_idle < FADE_AFTER_S else 0.0
	_district_card.modulate.a = move_toward(_district_card.modulate.a, dwant, delta * (3.0 if dwant > 0.0 else 0.6))
	# [v7look] a big moment (a base's arrival title) has the screen: the top-right cards step aside
	_hold_corner_s = maxf(_hold_corner_s - delta, 0.0)
	# [v7look] On a narrow screen (960 wide, or UI 1.5) the key-hint pill ran over the hotbar's right
	# readouts (STREAK, the hex count): it wraps to two rows beside them; only if even that is too
	# wide does it sit just above the hotbar band.
	if _hints_mc and _hints and hotbar:
		var vw: float = _root.size.x
		var hb_right: float = vw * 0.5 + Hotbar.LEVEL_W * 0.5 + 100.0  # the STREAK / hex readouts end about here
		var room: float = vw - 22.0 - hb_right - 8.0  # beside the hotbar's right readouts
		_hints.cap_w = maxf(room, 90.0)  # one row: smaller, then key caps only, to fit (KeyHints.compact)
		var lifted: bool = vw - 22.0 - _hints.size.x < hb_right  # still too wide (a very narrow screen): over the band
		var mb: int = 22 + (150 if lifted else 0)  # just over the hotbar band
		if _hints_mc.get_theme_constant("margin_bottom") != mb:
			_hints_mc.add_theme_constant_override("margin_bottom", mb)
	var orb: Variant = world.get("orbit") if world else null  # and the Command view, with its own card and hints
	var in_cmd: bool = orb is SliceOrbit and (orb as SliceOrbit).cam != null and (orb as SliceOrbit).cam.view == "command"
	_top_right.modulate.a = move_toward(_top_right.modulate.a, 0.0 if _hold_corner_s > 0.0 or in_cmd else 1.0, delta * 4.0)
	var bottom_out: bool = _hold_all and _hold_corner_s > 0.0
	_bottom.modulate.a = move_toward(_bottom.modulate.a, 0.0 if bottom_out else 1.0, delta * 4.0)
	if _hints_mc:  # [v7look] and the key-hint pill gives way while a WREN line is up
		var sub_on: bool = false
		var sb: Subtitles = Subtitles.current
		if sb and _hints and _hints.visible and sb.pill().visible and sb.pill().modulate.a > 0.2 and not sb.hushed():
			sub_on = true  # [v7look] owner rule: no key hints while WREN talks (they come back after)
		_hints_give = move_toward(_hints_give, 0.0 if sub_on else 1.0, delta * 4.0)
		_hints_mc.modulate.a = minf(_bottom.modulate.a, _hints_give)
	if patch:
		if patch.detector and not patch.detector.readout_changed.is_connected(_on_signal):
			patch.detector.readout_changed.connect(_on_signal)
		hotbar.set_hopper(patch.compartment.fill, patch.capacity())
		_prompt.text = _prompt_text(patch.prompt)
		_update_context(delta, minimal)


## Hex %, part signal and carried bales in one quiet line that only shows while relevant:
## for a few seconds after it changes (scooping, a level-up), or while a part signal is strong.
func _update_context(delta: float, minimal: bool) -> void:
	# [vqa] One short phrase, by priority: carrying > strong part signal > this hex. The hex part is
	# just its state ("HEX 40% CLEAR", "GROWING  THIRSTY"); level hints and outpost notes live in
	# the goals card and the outpost itself. It shows for a few seconds after it changes, while
	# carrying, or while the signal is strong, in every HUD mode.
	var text: String = ""
	var h: int = patch.focus_hex()
	var hex_text: String = ""
	if h >= 0 and world and world.field.hex_hub[h] == 0:
		if not world.field.is_clean(h):
			hex_text = tr("HEX  %d%% CLEAR") % int(floor(world.field.removed_fraction(h) * 100.0))
		else:
			hex_text = _short_level(h)
	elif h >= 0 and world:  # [onboard] on the hub ground: say where you are
		hex_text = tr("%s  BASE") % str(world.district_name).to_upper()
	var strong: bool = _signal_text != "" and (_signal_strength >= 0.5 or not minimal)
	if not patch.carried.is_empty():
		text = tr("CARRYING %d/%d") % [patch.carried.size(), patch.carry_cap()]
	elif strong:
		text = _signal_text
	else:
		text = hex_text
	var sig: String = hex_text + str(patch.carried.size())
	if sig != _context_sig:
		_context_sig = sig
		_context_idle = 0.0
	_context_idle += delta
	_context.text = text
	_context.add_theme_color_override("font_color", _signal_color if strong and patch.carried.is_empty() else CONTEXT_COLOR)
	# [onboard] Always on (playtest 2: "always show the % of the hex I'm standing in"); it only
	# brightens for a few seconds after a change.
	var want: float = (1.0 if (_context_idle < CONTEXT_HOLD_S or strong or not patch.carried.is_empty()) else 0.8) if text != "" else 0.0
	if hotbar.celebrating():
		want = 0.0
	if Subtitles.current and is_instance_valid(Subtitles.current) and Subtitles.current.current_text() != "":
		want = 0.0  # [orbB] owner rule (onboard2): one message line on screen at a time
	_context.modulate.a = move_toward(_context.modulate.a, want, delta * (4.0 if want > 0.0 else 1.2))
	# [v6screens] With little room under Lumi (big interface scale) the subtitle line sits over the
	# hotbar and the prompt: they dim under it instead of showing through the text.
	var cov: Rect2 = Subtitles.current.cover_rect() if Subtitles.current and is_instance_valid(Subtitles.current) else Rect2()
	for c: Control in [hotbar, _prompt]:
		var dim: bool = cov.size.y > 0.0 and cov.intersects(c.get_global_rect())
		c.self_modulate.a = move_toward(c.self_modulate.a, 0.2 if dim else 1.0, delta * 5.0)


## [vqa] "GROWING", "PLANTED  THIRSTY", "GROWING  SUSTAIN 60%": the hex level in a few words.
func _short_level(h: int) -> String:
	var hl: Variant = world.get("hex_levels")
	if hl == null:
		return tr("HEX  CLEAR")
	var l: int = int(hl.level_of(h))
	if l < 0:
		return ""
	var s: String = tr("HEX  %s") % str(hl.level_name(l)).to_upper()
	if l == 3 or (l == 4 and not hl.sustained_now(h)):
		if hl._ring_n.has(h) and hl.watered_ratio(h) >= float(hl.cfg.get("sustain_ratio", 0.9)):
			s += tr("  SUSTAIN %d%%") % int(hl.sustain_progress(h) * 100.0)
		elif hl._ring_n.has(h):
			s += tr("  THIRSTY")
	return s


func _on_signal(text: String, color: Color, strength: float) -> void:
	_signal_text = text
	_signal_color = color
	_signal_strength = strength


## [v5text] Shared with the survey map (ui/globe_view.gd), so both print the planet % the same way.
static func fmt_small_pct(p: float) -> String:
	return _fmt_small_pct(p)


static func _fmt_small_pct(p: float) -> String:
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
		# TRANSLATORS: %s is the interact key or pad button glyph (E / A).
		"pick_up": return tr("%s   pick up bale") % g
		"dig": return tr("%s   dig up part") % g
		"shard": return tr("%s   read memory shard") % g
		"seed": return tr("%s   pick up the seed tin") % g
		"place": return tr("%s   set bale down") % g
		"upgrades": return tr("%s   workbench") % g
	if kind.begins_with("E "):
		return g + kind.substr(1)
	if kind.begins_with("~ "):  # [v6crew] a line to read, no key (a robot saying what it is doing)
		return kind.substr(2)
	return ""
