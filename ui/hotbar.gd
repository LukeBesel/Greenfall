class_name Hotbar
extends Control
## Bottom-centre hotbar with the Lumi Level bar above it and the
## hopper gauge folded in underneath:
##   level   level number centred over a thin XP bar; a tiny Bloom Core ring at its left end
##           (set_core_charge); "+XP" ticks; a restrained flash + chime on level-up
##   surge   the Bloom Core ring's outer arc is the Surge gauge (systems/surge.gd): it fills with
##           Lumi's own work, shows the release key on a plate when full, and drains while the
##           Surge runs
##   slots   one rounded glass slot per tool (Scoop / Plant / Water): icon, key (1-3 or a D-pad
##           glyph on a pad), counter (seeds, water); the selected slot is raised with a thin glow;
##           locked tools are dim with a small lock
##   hopper  a slim fill bar under the slots with the Perfect band and the fill line
## Input: number keys (Patch's tool_* actions), mouse wheel (Ctrl+wheel still zooms) and the pad
## bumpers cycle tools once more than one is unlocked; holding a bumper zooms the camera.
## Everything is drawn in _draw with hairlines, so it stays crisp at any UI scale.

const SLOT: float = 52.0
const GAP: float = 10.0
const RAISE: float = 5.0
const LEVEL_W: float = 300.0
const HOPPER_W: float = 260.0
const HOLD_ZOOM_S: float = 0.3
const CYAN := Color(0.55, 0.9, 1.0)
const XP_COL := Color(0.5, 0.95, 0.75)
const CORE_COL := Color(0.45, 1.0, 0.6)
const SURGE_GOLD := Color(1.0, 0.85, 0.35)
const SURGE_R: float = 11.0
const SURGE_PLATE_H: float = 26.0
# l10n:begin
const TOOLS: Array[Dictionary] = [
	{"id": "scoop", "name": "SCOOP", "action": "tool_scoop", "icon": "scoop"},
	{"id": "plant", "name": "PLANT", "action": "tool_plant", "icon": "plant"},
	{"id": "water", "name": "WATER", "action": "tool_water", "icon": "water"},
]
# l10n:end

var patch: Patch
var world: Node
var lumi: LumiLevel

var _font: Font
var _sb_slot: StyleBoxFlat
var _sb_sel: StyleBoxFlat
var _sb_locked: StyleBoxFlat
var _sel_anim: Array[float] = [1.0, 0.0, 0.0]
var _shown_xp: float = 0.0
var _shown_level: int = 1
var _xp_tick: int = 0
var _xp_tick_t: float = 0.0
var _lvl_t: float = 0.0  # level-up celebration time left
var _lvl_text: String = ""
var _lvl_num: int = 0
var _core: float = -1.0
var _core_t: float = 0.0
var _surge: Surge
var _hopper: float = 0.0
var _hopper_shake: float = 0.0
var _tool_name_t: float = 0.0
var _bumper: int = 0  # -1 LB held, 1 RB held, 0 none
var _bumper_t: float = 0.0
var _t: float = 0.0
var _dev_done: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UITheme.font()
	_sb_slot = UITheme.box(Color(0.03, 0.04, 0.05, 0.5), Color(0.9, 0.9, 0.85, 0.22), 1, 11, 0)
	_sb_sel = UITheme.box(Color(0.05, 0.09, 0.11, 0.62), Color(CYAN, 0.9), 1, 11, 0)
	_sb_sel.shadow_color = Color(CYAN, 0.22)
	_sb_sel.shadow_size = 7
	_sb_locked = UITheme.box(Color(0.03, 0.04, 0.05, 0.28), Color(1, 1, 1, 0.08), 1, 11, 0)
	custom_minimum_size = Vector2(LEVEL_W + 120.0, 150.0)
	if lumi:
		lumi.leveled.connect(_on_leveled)
		lumi.xp_gained.connect(_on_xp)
	var st: Dictionary = LumiLevel.state()
	_shown_level = int(st.get("level", 1))
	_shown_xp = LumiLevel.progress()
	EventBus.tool_changed.connect(func(_t2: int) -> void: _tool_name_t = 1.6)


# --- API -----------------------------------------------------------------------------------

## Bloom Core charge 0..1 (story code). The tiny ring appears once this is called.
func set_core_charge(f: float) -> void:
	var v: float = clampf(f, 0.0, 1.0)
	if _core < 0.0 or absf(v - _core) >= 0.01:
		_core_t = 3.0
	_core = v


func set_hopper(fill: float, cap: float) -> void:
	var r: float = fill / maxf(cap, 0.01)
	if r >= 1.0 and _hopper >= 1.0:
		_hopper_shake = 0.25
	_hopper = r


func unlocked(i: int) -> bool:
	if i == 0:
		return true
	return world != null and world.get("garden") != null and world.garden.unlocked()


func unlocked_count() -> int:
	var n: int = 0
	for i: int in TOOLS.size():
		if unlocked(i):
			n += 1
	return n


## True during the level-up moment (the HUD hides the context line over it).
func celebrating() -> bool:
	return _lvl_t > 0.0


## Selects the next/previous unlocked tool (wraps).
func cycle(dir: int) -> void:
	if patch == null or unlocked_count() < 2:
		return
	var i: int = patch.tool
	for _k: int in TOOLS.size():
		i = wrapi(i + dir, 0, TOOLS.size())
		if unlocked(i):
			patch.set_tool(i)
			return


# --- Input -----------------------------------------------------------------------------------

func _can_take_input() -> bool:
	if patch == null or not (patch.input is PlayerInput) or not (patch.input as PlayerInput).enabled:
		return false
	if world and world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
		return false
	var hud: Variant = world.get("hud") if world else null
	if hud is CanvasLayer and not (hud as CanvasLayer).visible:
		return false
	return unlocked_count() >= 2


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if not mb.pressed or mb.ctrl_pressed or mb.shift_pressed or mb.alt_pressed:
			return
		if mb.button_index != MOUSE_BUTTON_WHEEL_UP and mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
			return
		if not _can_take_input():
			return
		cycle(1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		if jb.button_index != JOY_BUTTON_LEFT_SHOULDER and jb.button_index != JOY_BUTTON_RIGHT_SHOULDER:
			return
		var dir: int = -1 if jb.button_index == JOY_BUTTON_LEFT_SHOULDER else 1
		if jb.pressed:
			if not _can_take_input():
				return
			if _bumper == -dir:  # both bumpers together release a Surge (systems/surge.gd): no tool change
				_bumper = 0
				return
			_bumper = dir
			_bumper_t = 0.0
			get_viewport().set_input_as_handled()
		elif _bumper == dir:
			# A tap cycles; a hold was a zoom.
			if _bumper_t < HOLD_ZOOM_S:
				cycle(dir)
			_bumper = 0
			get_viewport().set_input_as_handled()


# --- Events ----------------------------------------------------------------------------------

func _on_xp(amount: int, _source: String) -> void:
	_xp_tick += amount
	_xp_tick_t = 1.4


func _on_leveled(lv: int, reward_text: String) -> void:
	_lvl_num = lv
	_lvl_text = reward_text
	_lvl_t = 3.6
	_shown_level = lv
	_shown_xp = 0.0
	Audio.play("chime", 1.32, -7.0, 0.0)
	Audio.play("sparkle", 1.25, -14.0)


# --- Frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if not _dev_done and _t > 1.0:
		_dev_done = true
		_apply_dev()
	if patch:
		for i: int in TOOLS.size():
			_sel_anim[i] = move_toward(_sel_anim[i], 1.0 if patch.tool == i else 0.0, delta * 7.0)
	if _lvl_t > 0.0 and not DevHooks.has("lumi-levelup"):
		_lvl_t = maxf(0.0, _lvl_t - delta)
	elif _lvl_t > 0.0:
		_lvl_t = maxf(2.9, _lvl_t - delta)  # dev: hold the moment for the screenshot
	var st: Dictionary = LumiLevel.state()
	if _lvl_t <= 2.6:
		_shown_level = int(st.get("level", 1))
		_shown_xp = lerpf(_shown_xp, LumiLevel.progress(), clampf(delta * 6.0, 0.0, 1.0))
	_xp_tick_t = maxf(0.0, _xp_tick_t - delta)
	if _xp_tick_t <= 0.0:
		_xp_tick = 0
	_core_t = maxf(0.0, _core_t - delta)
	_tool_name_t = maxf(0.0, _tool_name_t - delta)
	_hopper_shake = maxf(0.0, _hopper_shake - delta)
	if _bumper != 0:
		_bumper_t += delta
	# Duck-typed Bloom Core (story/core_charge.gd exposes `shown`), so no hard dependency.
	var cc: Variant = world.get("core_charge") if world else null
	if cc is Object and (cc as Object).get("shown") != null:
		set_core_charge(float((cc as Object).get("shown")))
	if _surge == null and world:
		_surge = Surge.of(world)
	queue_redraw()


## Dev hooks for screenshots: --tool=plant|water, --hud-pad (pad glyphs), --hud-mode=full|minimal|hidden.
func _apply_dev() -> void:
	if DevHooks.has("tool") and patch:
		var want: int = ["scoop", "plant", "water"].find(DevHooks.get_s("tool", "scoop"))
		if want >= 0 and unlocked(want):
			patch.set_tool(want)
	if DevHooks.has("hud-pad"):
		Settings.last_input_pad = true
	if DevHooks.has("hud-mode"):
		Settings.hud_mode = maxi(0, ["full", "minimal", "hidden"].find(DevHooks.get_s("hud-mode", "minimal")))
		Settings.changed.emit()


# --- Drawing ---------------------------------------------------------------------------------

func _row_w() -> float:
	return TOOLS.size() * SLOT + (TOOLS.size() - 1) * GAP


func _text(pos: Vector2, s: String, sz: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, outline: bool = true) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x: float = pos.x - (w * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (w if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0))
	if outline:
		draw_string_outline(_font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.45 * col.a))
	draw_string(_font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw() -> void:
	var cx: float = size.x * 0.5
	var bottom: float = size.y
	var hop_y: float = bottom - 10.0
	var slot_y: float = hop_y - 10.0 - SLOT
	var lvl_y: float = slot_y - RAISE - 24.0
	_draw_level(cx, lvl_y)
	_draw_slots(cx, slot_y)
	_draw_hopper(cx, hop_y)


func _draw_level(cx: float, y: float) -> void:
	var x0: float = cx - LEVEL_W * 0.5
	var flash: float = clampf((_lvl_t - 2.6) / 1.0, 0.0, 1.0)  # first second of a level-up
	var glow: float = clampf(_lvl_t / 0.8, 0.0, 1.0) if _lvl_t > 0.0 else 0.0
	# Track, fill and a soft head.
	draw_rect(Rect2(x0 - 1.0, y - 1.0, LEVEL_W + 2.0, 5.0), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(x0, y, LEVEL_W, 3.0), Color(1, 1, 1, 0.16))
	var f: float = 1.0 if flash > 0.0 else _shown_xp
	var col: Color = XP_COL.lerp(Color.WHITE, flash * 0.7)
	if f > 0.0:
		draw_rect(Rect2(x0, y, LEVEL_W * f, 3.0), col)
		draw_rect(Rect2(x0, y - 1.0, LEVEL_W * f, 5.0), Color(col, 0.18 + 0.3 * glow))
		draw_circle(Vector2(x0 + LEVEL_W * f, y + 1.5), 2.2, Color(col, 0.9))
	# Quarter ticks.
	for k: int in range(1, 4):
		draw_line(Vector2(x0 + LEVEL_W * k * 0.25, y - 1.0), Vector2(x0 + LEVEL_W * k * 0.25, y + 4.0), Color(0, 0, 0, 0.35), 1.0)
	# Level number (pops on level-up).
	var pop: float = 1.0 + 0.35 * flash
	var num_sz: int = int(round(18.0 * pop))
	_text(Vector2(cx, y - 6.0), str(_shown_level), num_sz, XP_COL.lerp(Color.WHITE, 0.25 + 0.5 * flash))
	if Settings.hud_mode == Settings.HudMode.FULL:
		_text(Vector2(cx - 18.0, y - 7.0), "LV", 12, Color(UITheme.MUTED, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
	# XP tick at the right end.
	if _xp_tick > 0 and _lvl_t <= 0.0:
		var a: float = clampf(_xp_tick_t / 0.5, 0.0, 1.0)
		_text(Vector2(x0 + LEVEL_W + 8.0, y + 5.0), tr("+%d XP") % _xp_tick, 12, Color(XP_COL, 0.85 * a), HORIZONTAL_ALIGNMENT_LEFT)
	# Bloom Core ring at the left end.
	if _core >= 0.0:
		var c := Vector2(x0 - 14.0, y + 1.5)
		draw_arc(c, 6.0, 0.0, TAU, 24, Color(1, 1, 1, 0.16), 1.5, true)
		if _core > 0.001:
			draw_arc(c, 6.0, -PI * 0.5, -PI * 0.5 + TAU * _core, 24, CORE_COL, 1.6, true)
		draw_circle(c, 1.6, Color(CORE_COL, 0.4 + 0.5 * _core))
		var gauged: bool = _surge != null and _surge.enabled()
		var show_pct: float = 1.0 if Settings.hud_mode == Settings.HudMode.FULL else clampf(_core_t / 0.6, 0.0, 1.0)
		if gauged and (_surge.can_release() or _surge.active()):
			show_pct = 0.0  # the Surge plate takes the line
		if show_pct > 0.01:
			_text(Vector2(c.x - (SURGE_R + 6.0 if gauged else 10.0), y + 5.5), tr("CORE %d%%") % int(floor(_core * 100.0 + 0.001)), 12, Color(CORE_COL, 0.85 * show_pct),
				HORIZONTAL_ALIGNMENT_RIGHT)
		if gauged:
			_draw_surge(c)
	# Level-up banner: "LEVEL 7" and the reward line, rising slightly and fading.
	if _lvl_t > 0.0:
		var a2: float = clampf(_lvl_t / 0.6, 0.0, 1.0) * clampf((3.6 - _lvl_t) / 0.25, 0.0, 1.0)
		var rise: float = (1.0 - clampf((3.6 - _lvl_t) / 0.4, 0.0, 1.0)) * 6.0
		_text(Vector2(cx, y - 30.0 + rise), "L E V E L   %d" % _lvl_num, 18, Color(Color.WHITE.lerp(XP_COL, 0.35), a2))
		if _lvl_text != "":
			_text(Vector2(cx, y - 52.0 + rise), _lvl_text, 13, Color(UITheme.GOLD, 0.95 * a2))
		# Thin light sweeping out along the bar.
		var sweep: float = clampf((3.6 - _lvl_t) / 0.7, 0.0, 1.0)
		var hw: float = LEVEL_W * 0.5 * sweep
		draw_line(Vector2(cx - hw, y + 1.5), Vector2(cx + hw, y + 1.5), Color(1, 1, 1, 0.8 * (1.0 - sweep)), 2.0)


## The Surge gauge round the Bloom Core ring at `c`: an arc that fills with Lumi's own work (cyan),
## a full ring with the release key on a plate when ready (green), and a draining arc while the
## Surge runs (gold). Shape and words carry it as well as colour.
func _draw_surge(c: Vector2) -> void:
	var full: bool = _surge.can_release()
	var running: bool = _surge.active()
	var f: float = _surge.gauge()
	var col: Color = SURGE_GOLD if running else (CORE_COL if full else CYAN)
	draw_arc(c, SURGE_R, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 4.5, true)
	draw_arc(c, SURGE_R, 0.0, TAU, 32, Color(1, 1, 1, 0.16), 2.5, true)
	if f > 0.001:
		draw_arc(c, SURGE_R, -PI * 0.5, -PI * 0.5 + TAU * f, 32, col, 3.0, true)
	if not (full or running):
		return
	var glow: float = 0.5 if Settings.reduced_motion else 0.35 + 0.3 * (0.5 + 0.5 * sin(_t * 5.0))
	draw_arc(c, SURGE_R + 3.0, 0.0, TAU, 32, Color(col, glow), 1.5, true)
	var label: String = tr("SURGE")
	var key: String = SurgeFx.release_glyph() if full else "%d" % ceili(_surge.time_left())
	var key_w: float = _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var label_w: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var w: float = key_w + label_w + 34.0
	var x1: float = c.x - SURGE_R - 8.0
	var r := Rect2(x1 - w, c.y - SURGE_PLATE_H * 0.5, w, SURGE_PLATE_H)
	var cut: float = 7.0  # the instrument plate's clipped corner
	var plate := PackedVector2Array([r.position + Vector2(cut, 0.0), Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
		r.position + Vector2(0.0, cut)])
	draw_colored_polygon(plate, Color(0.07, 0.09, 0.11, 0.9))
	plate.append(plate[0])
	draw_polyline(plate, Color(col, 0.9), 1.5, true)
	var base_y: float = c.y + 5.5
	_text(Vector2(r.position.x + 12.0, base_y), key, 16, Color(col, 1.0), HORIZONTAL_ALIGNMENT_LEFT, false)
	_text(Vector2(r.end.x - 10.0, base_y), label, 16, UITheme.CREAM, HORIZONTAL_ALIGNMENT_RIGHT, false)


func _draw_slots(cx: float, y: float) -> void:
	var rw: float = _row_w()
	var x0: float = cx - rw * 0.5
	var pad: bool = Settings.last_input_pad
	var multi: bool = unlocked_count() >= 2
	for i: int in TOOLS.size():
		var tdef: Dictionary = TOOLS[i]
		var on: bool = unlocked(i)
		var s: float = _sel_anim[i]
		var r := Rect2(x0 + i * (SLOT + GAP), y - RAISE * s, SLOT, SLOT)
		if not on:
			draw_style_box(_sb_locked, r)
		else:
			draw_style_box(_sb_slot, r)
			if s > 0.01:
				_sb_sel.border_color = Color(CYAN, 0.9 * s)
				_sb_sel.shadow_color = Color(CYAN, (0.18 + 0.06 * sin(_t * 2.4)) * s)
				_sb_sel.bg_color = Color(0.05, 0.09, 0.11, 0.62 * s)
				draw_style_box(_sb_sel, r)
		var c: Vector2 = r.get_center() + Vector2(0, -1)
		var icol: Color = UITheme.CREAM.lerp(Color.WHITE, s) if on else Color(UITheme.MUTED, 0.45)
		if i == 0 and on:
			# Hopper fill rises inside the Scoop slot as a faint tint.
			var fh: float = (SLOT - 4.0) * clampf(_hopper / 1.15, 0.0, 1.0)
			if fh > 0.5:
				var hc: Color = _hopper_color()
				draw_rect(Rect2(r.position.x + 2.0, r.end.y - 2.0 - fh, SLOT - 4.0, fh), Color(hc, 0.1))
				draw_line(Vector2(r.position.x + 6.0, r.end.y - 2.0 - fh), Vector2(r.end.x - 6.0, r.end.y - 2.0 - fh), Color(hc, 0.55), 1.0)
		HudIcons.draw(self, str(tdef["icon"]), c, 15.0, icol, 1.6)
		if not on:
			HudIcons.draw(self, "lock", r.position + Vector2(SLOT - 11.0, 12.0), 8.0, Color(UITheme.MUTED, 0.6), 1.2)
			continue
		# Key: number on keyboard, a D-pad glyph on a pad.
		var kc: Color = Color(UITheme.CREAM, 0.55 + 0.4 * s)
		if pad:
			_draw_pad_glyph(r.position + Vector2(10.0, 10.0), str(tdef["action"]), kc)
		else:
			_text(r.position + Vector2(7.0, 15.0), Settings.glyph(str(tdef["action"])), 12, kc, HORIZONTAL_ALIGNMENT_LEFT, false)
		# Counter.
		var cnt: String = ""
		var ccol: Color = UITheme.CREAM
		if i == 1:
			cnt = Settings.fmt(GameState.get_currency("seeds"))
			ccol = UITheme.CREAM if GameState.get_currency("seeds").to_float() >= 1.0 else Color(1.0, 0.55, 0.4)
		elif i == 2 and patch:
			cnt = str(int(patch.water))
			var wf: float = patch.water / maxf(patch.water_cap(), 1.0)
			ccol = UITheme.CREAM if wf > 0.15 else Color(1.0, 0.55, 0.4)
			# Thin water gauge along the slot's bottom edge.
			draw_line(Vector2(r.position.x + 8.0, r.end.y - 4.0), Vector2(r.end.x - 8.0, r.end.y - 4.0), Color(1, 1, 1, 0.12), 2.0)
			draw_line(Vector2(r.position.x + 8.0, r.end.y - 4.0), Vector2(r.position.x + 8.0 + (SLOT - 16.0) * wf, r.end.y - 4.0), Color(0.55, 0.8, 1.0, 0.9), 2.0)
		if cnt != "":
			_text(Vector2(r.end.x - 6.0, r.end.y - (9.0 if i == 2 else 6.0)), cnt, 12, ccol, HORIZONTAL_ALIGNMENT_RIGHT)
	# Selected tool name, briefly after a switch (always in Full).
	if patch and (_tool_name_t > 0.0 or Settings.hud_mode == Settings.HudMode.FULL) and multi:
		var a: float = 1.0 if Settings.hud_mode == Settings.HudMode.FULL else clampf(_tool_name_t / 0.5, 0.0, 1.0)
		var sr := Rect2(x0 + patch.tool * (SLOT + GAP), y - RAISE, SLOT, SLOT)
		if _lvl_t <= 0.0:
			_text(Vector2(sr.get_center().x, y - RAISE - 7.0), tr(str(TOOLS[patch.tool]["name"])), 12, Color(CYAN, 0.9 * a))
	# Bumper glyphs on a pad.
	if pad and multi:
		_pill(Vector2(x0 - 22.0, y + SLOT * 0.5), "LB")
		_pill(Vector2(x0 + rw + 22.0, y + SLOT * 0.5), "RB")


func _pill(c: Vector2, s: String) -> void:
	var r := Rect2(c - Vector2(15, 9), Vector2(30, 18))
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.35), 1, 9, 0), r)
	_text(c + Vector2(0, 4.5), s, 12, Color(UITheme.CREAM, 0.85), HORIZONTAL_ALIGNMENT_CENTER, false)


## A tiny D-pad with the bound direction lit, or the button name for other bindings.
func _draw_pad_glyph(c: Vector2, action: String, col: Color) -> void:
	var ev: InputEvent = Settings.binding(action, true)
	var dir := Vector2.ZERO
	if ev is InputEventJoypadButton:
		match (ev as InputEventJoypadButton).button_index:
			JOY_BUTTON_DPAD_UP: dir = Vector2.UP
			JOY_BUTTON_DPAD_DOWN: dir = Vector2.DOWN
			JOY_BUTTON_DPAD_LEFT: dir = Vector2.LEFT
			JOY_BUTTON_DPAD_RIGHT: dir = Vector2.RIGHT
	if dir == Vector2.ZERO:
		_text(c + Vector2(-3, 5), Settings.event_label(ev) if ev else "?", 12, col, HORIZONTAL_ALIGNMENT_LEFT, false)
		return
	var a: float = 3.0
	var dim := Color(col, col.a * 0.35)
	draw_rect(Rect2(c - Vector2(a * 0.5, a * 1.5), Vector2(a, a * 3.0)), dim)
	draw_rect(Rect2(c - Vector2(a * 1.5, a * 0.5), Vector2(a * 3.0, a)), dim)
	draw_rect(Rect2(c + dir * a - Vector2(a * 0.5, a * 0.5), Vector2(a, a)), col)


func _hopper_color() -> Color:
	var pal: Dictionary = UITheme.meter_colors()
	var band: Array = Economy.cube_rules.get("perfect_band", [0.9, 1.0])
	if _hopper > float(band[1]) + 0.0001:
		return pal["over"]
	if _hopper >= float(band[0]):
		return pal["good"]
	return UITheme.CREAM


func _draw_hopper(cx: float, y: float) -> void:
	var off := Vector2(sin(Time.get_ticks_msec() * 0.08) * 3.0 * _hopper_shake / 0.25, 0)
	var x0: float = cx - HOPPER_W * 0.5
	var scale_max: float = 1.15
	var band: Array = Economy.cube_rules.get("perfect_band", [0.9, 1.0])
	var pal: Dictionary = UITheme.meter_colors()
	var o := Vector2(x0, y) + off
	draw_rect(Rect2(o - Vector2(1, 1), Vector2(HOPPER_W + 2.0, 4.0)), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(o, Vector2(HOPPER_W, 2.0)), Color(1, 1, 1, 0.16))
	var b0: float = float(band[0]) / scale_max * HOPPER_W
	var b1: float = float(band[1]) / scale_max * HOPPER_W
	draw_rect(Rect2(o + Vector2(b0, -2.0), Vector2(b1 - b0, 6.0)), pal["band"])
	var w: float = clampf(_hopper / scale_max, 0.0, 1.0) * HOPPER_W
	if w > 0.0:
		draw_rect(Rect2(o, Vector2(w, 2.0)), _hopper_color())
	draw_line(o + Vector2(b1, -4.0), o + Vector2(b1, 6.0), Color(1, 1, 1, 0.6), 1.0)
	if patch and (patch.compartment.fill > 0.0 or Settings.hud_mode == Settings.HudMode.FULL):
		_text(o + Vector2(HOPPER_W + 8.0, 5.0), "%.1f / %.0f" % [patch.compartment.fill, patch.capacity()], 12, Color(UITheme.MUTED, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
