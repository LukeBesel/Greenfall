# Parked with the Seed of the Week (M1-08). This was the 'weekly' tab of ExtrasPanel (ui/extras_panel.gd):
# paste it back into that class, add "weekly" to TABS / TAB_NAMES and the match in _rebuild().

# --- Seed of the Week --------------------------------------------------------------------

func _build_weekly() -> void:
	var w: Vector2i = WeeklyChallenge.iso_week(WeeklyChallenge.now())
	var tw: Dictionary = WeeklyChallenge.twist()
	var wr: Dictionary = WeeklyChallenge.week_rec()
	var left: VBoxContainer = _col(520, tr("WEEK %d, %d") % [w.y, w.x])
	left.add_child(UITheme.label(tr("Seed of the Week"), 26, Color.WHITE))
	left.add_child(_wrap(tr("The same seed and twist for everyone this week. Clean %d hexes as fast as you can. It has its own save, so your world is untouched.") % WeeklyChallenge.goal_hexes(), 14, UITheme.MUTED))
	left.add_child(UITheme.stat_row(UITheme.GOLD, tr("Twist: %s") % tr(str(tw.get("name", ""))), ""))
	left.add_child(_wrap(tr(str(tw.get("desc", ""))), 13, UITheme.MUTED))
	left.add_child(UITheme.stat_row(UITheme.CREAM, tr("Seed"), str(WeeklyChallenge.current_seed())))
	left.add_child(UITheme.stat_row(UITheme.CREAM, tr("Best time"), WeeklyChallenge.clock_text(float(wr["best_time"])) if float(wr.get("best_time", 0.0)) > 0.0 else "--"))
	left.add_child(UITheme.stat_row(UITheme.CREAM, tr("Best score"), str(int(wr.get("best_score", 0))) if int(wr.get("best_score", 0)) > 0 else "--"))
	if WeeklyChallenge.active:
		var home: Button = _btn(left, tr("Return home"), func() -> void:
			close_panel()
			WeeklyChallenge.leave(get_tree()))
		UITheme.orange_button(home)
		_btn(left, tr("Restart this week's run"), func() -> void:
			close_panel()
			WeeklyChallenge.restart(get_tree()))
	else:
		var go: Button = _btn(left, tr("Resume this week's run") if WeeklyChallenge.has_run() else tr("Start the challenge"), func() -> void:
			close_panel()
			WeeklyChallenge.start(get_tree()))
		UITheme.orange_button(go)
	var right: VBoxContainer = _col(0, tr("PAINT CHIPS  ·  %d") % WeeklyChallenge.chip_count())
	right.add_child(_wrap(tr("Finish a week's challenge for its paint chip. Chips unlock the weekly decorations in Garden Mode and paint them."), 13, UITheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for c: Variant in WeeklyChallenge.chips():
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(44, 56)
		chip.tooltip_text = str((c as Dictionary).get("week", ""))
		chip.add_theme_stylebox_override("panel", UITheme.box(Color.html(str((c as Dictionary).get("color", "#e8a33d"))), Color(1, 1, 1, 0.5), 1, 4, 0))
		grid.add_child(chip)
	if WeeklyChallenge.chips().is_empty():
		right.add_child(_wrap(tr("No chips yet."), 14, UITheme.MUTED))

