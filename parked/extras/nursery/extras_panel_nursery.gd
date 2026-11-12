# Snippet cut from ui/extras_panel.gd in task M3-13: the Keepsakes panel's Nursery tab. Put it back
# with TABS "nursery", TAB_NAMES "Nursery", tab_open "nursery": YardBuilds.built("nursery") or
# Nursery.count() > 0, _rebuild "nursery": _build_nursery(), and the var _confirm: String it uses.

# --- Nursery -----------------------------------------------------------------------------

func _build_nursery() -> void:
	var left: VBoxContainer = _col(440, tr("CARETAKERS  ·  %d") % Nursery.count())
	left.add_child(_wrap(tr("Garden bonus: plants grow %d%% faster (up to %d%%).") % [int(round(Nursery.garden_bonus() * 100.0)), int(round(Nursery.BONUS_CAP * 100.0))], 14, UITheme.GREEN))
	var recs: Array = Nursery.list()
	if recs.is_empty():
		left.add_child(_wrap(tr("No one has retired yet. Old or Mk I-II robots can retire here; they'll look after the nursery garden at the base."), 14, UITheme.MUTED))
	for i: int in range(recs.size() - 1, -1, -1):
		var r: Dictionary = recs[i]
		var tdef: Dictionary = RobotBuilder.trait_def(str(r.get("trait", "")))
		var tier: int = int(r.get("tier", 0))
		var row: HBoxContainer = UITheme.stat_row(RobotBuilder.CREW_COLORS.get(str(Economy.robots.get(str(r.get("type", "")), {}).get("role", "clean")), UITheme.GOLD),
			"%s  ·  %s %s" % [str(r.get("name", "")), tr(str(Economy.robots.get(str(r.get("type", "")), {}).get("name", ""))), Economy.tier_name(tier)],
			tr(str(tdef.get("name", ""))))
		left.add_child(row)
	var right: VBoxContainer = _col(0, tr("RETIRE A ROBOT"))
	var fl: Fleet = world.get("fleet") as Fleet if world else null
	right.add_child(_wrap(tr("Retiring gives a few parts back, and the robot keeps its name and personality in the nursery."), 13, UITheme.MUTED))
	if fl == null or fl.robots().is_empty():
		right.add_child(_wrap(tr("No robots in this district."), 14, UITheme.MUTED))
		return
	for rb: Robot in fl.robots():
		var why: String = Nursery.retire_block_reason(rb)
		var key: String = rb.robot_name
		var label: String = "%s  ·  %s %s" % [rb.robot_name, tr(str(Economy.robots.get(rb.type_id, {}).get("name", ""))), Economy.tier_name(rb.tier)]
		if why == "":
			label += "\n" + (tr("Press again to retire (+%d parts)") % Nursery.refund_for(rb.tier) if _confirm == key else tr("Retire  (+%d parts)") % Nursery.refund_for(rb.tier))
		else:
			label += "\n" + why
		var robot: Robot = rb
		var b: Button = _btn(right, label, func() -> void:
			if Nursery.retire_block_reason(robot) != "":
				return
			if _confirm != key:
				_confirm = key
				_rebuild()
				return
			_confirm = ""
			Nursery.retire(fl, robot)
			_rebuild(), 52)
		b.add_theme_color_override("font_color", UITheme.GOLD if _confirm == key else (UITheme.CREAM if why == "" else UITheme.MUTED))
		if _confirm == key:
			_first = b
