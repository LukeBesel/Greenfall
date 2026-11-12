# Snippet cut from ui/hotbar.gd in task M3-13 with Lumi Level: the level bar over the slots (XP
# fill, level number, "+XP" ticks, the level-up banner) with the Bloom Core ring at its left end.
# The hotbar kept the ring and the Surge gauge (_draw_core). It also had var lumi: LumiLevel,
# LEVEL_W, XP_COL, the _shown_xp/_shown_level/_xp_tick/_lvl_* state, _on_xp, _on_leveled and
# celebrating() (the HUD hid its context line during a level-up).

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
