class_name WeeklyRun
extends CanvasLayer
## [extras] The Seed of the Week while it runs (systems/extras/weekly.gd): the intro card on
## arrival (week, seed, twist, goal, best), the starting kit robots, a one-line tracker at the top
## of the screen (hexes and the clock, minimal-HUD style), and the result card when the goal is
## reached (time, score, bests, paint chip). Pad: A presses, B closes a card.

var world: Node
var _tracker: Label
var _card_root: Control
var _first: Button
var _t: float = 0.0
var card_open: bool = false
var card_kind: String = ""


func _ready() -> void:
	layer = 33
	process_mode = Node.PROCESS_MODE_ALWAYS
	var top := CenterContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 14
	top.offset_bottom = 50
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.06, 0.55), Color(1, 1, 1, 0.08), 1, 12, 8))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pc)
	_tracker = UITheme.label("", 14, UITheme.CREAM)
	_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(_tracker)
	_card_root = Control.new()
	_card_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.theme = UITheme.get_theme()
	_card_root.visible = false
	add_child(_card_root)
	if GameState.flags.get("weekly_intro", false):
		(func() -> void: show_intro()).call_deferred()
	_refresh()


func elapsed() -> float:
	if GameState.flags.get("weekly_intro", false):
		return 0.0
	if GameState.flags.has("weekly_time"):
		return float(GameState.flags["weekly_time"])
	return maxf(0.0, float(GameState.stats.get("time_played", 0.0)) - float(GameState.flags.get("weekly_t0", 0.0)))


func hexes() -> int:
	var f: HexField = world.get("field") as HexField if world else null
	return f.junk_hexes_cleaned() if f else 0


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	_refresh()
	if not GameState.flags.has("weekly_time") and not GameState.flags.get("weekly_intro", false) and hexes() >= WeeklyChallenge.goal_hexes():
		finish()


func _refresh() -> void:
	var done: bool = GameState.flags.has("weekly_time")
	_tracker.text = tr("SEED OF THE WEEK  ·  %d / %d hexes  ·  %s%s") % [mini(hexes(), WeeklyChallenge.goal_hexes()), WeeklyChallenge.goal_hexes(),
		WeeklyChallenge.clock_text(elapsed()), tr("  ·  done") if done else ""]


func _spawn_kit() -> void:
	var fl: Fleet = world.get("fleet") as Fleet
	var bots: Array = GameState.flags.get("weekly_kit_robots", [])
	GameState.flags.erase("weekly_kit_robots")
	if fl == null:
		return
	for i: int in bots.size():
		var rb: Robot = fl.spawn(str(bots[i]), 0, Vector3(-2.4 + i * 1.6, 0.2, 0.8), 0.0, "Week-%d" % (i + 1))
		if rb:
			rb.rotation.y = PI


func show_intro() -> void:
	var tw: Dictionary = WeeklyChallenge.twist()
	var w: Vector2i = WeeklyChallenge.iso_week(WeeklyChallenge.now())
	var best: Dictionary = WeeklyChallenge.week_rec()
	var lines: Array = [
		[tr("Twist"), tr(str(tw.get("name", ""))), UITheme.GOLD],
		["", tr(str(tw.get("desc", ""))), UITheme.MUTED],
		[tr("Goal"), tr("Clean %d hexes") % WeeklyChallenge.goal_hexes(), UITheme.CREAM],
		[tr("Seed"), str(WeeklyChallenge.current_seed()), UITheme.CREAM],
		[tr("Best"), (tr("%s  ·  %d points") % [WeeklyChallenge.clock_text(float(best["best_time"])), int(best["best_score"])]) if float(best.get("best_time", 0.0)) > 0.0 else tr("No finish yet"), UITheme.CREAM],
		[tr("Reward"), tr("A paint chip for your garden (first finish each week)"), UITheme.GREEN],
	]
	_show_card(tr("SEED OF THE WEEK"), tr("Week %d, %d") % [w.y, w.x], lines, [[tr("Start the clock"), _start_run], [tr("Return home"), _go_home]], "intro")


func _start_run() -> void:
	GameState.flags.erase("weekly_intro")
	GameState.flags["weekly_t0"] = float(GameState.stats.get("time_played", 0.0))
	_spawn_kit()
	_close_card()
	EventBus.toast.emit(tr("The clock is running. Clean %d hexes.") % WeeklyChallenge.goal_hexes(), "info")


func finish() -> void:
	var t: float = elapsed()
	GameState.flags["weekly_time"] = t
	var cubes: float = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	var sc: int = WeeklyChallenge.score(hexes(), int(GameState.stats.get("plants_bloomed", 0)), cubes, t, true)
	GameState.flags["weekly_score"] = sc
	var r: Dictionary = WeeklyChallenge.record_finish(t, sc)
	GameState.stats["weekly_finished"] = float(WeeklyChallenge.week_rec().get("done", false))
	Audio.play("fanfare", 1.0, -6.0)
	var lines: Array = [
		[tr("Time"), WeeklyChallenge.clock_text(t) + (tr("  (new best)") if r["new_time"] else ""), UITheme.CREAM],
		[tr("Score"), str(sc) + (tr("  (new best)") if r["new_score"] else ""), UITheme.CREAM],
		[tr("Best"), tr("%s  ·  %d points") % [WeeklyChallenge.clock_text(float(r["best_time"])), int(r["best_score"])], UITheme.MUTED],
	]
	if str(r["chip"]) != "":
		lines.append([tr("Reward"), tr("New paint chip! (%d in all) Weekly decorations in Garden Mode use them.") % WeeklyChallenge.chip_count(), Color.html(str(r["chip"]))])
	_show_card(tr("CHALLENGE COMPLETE"), WeeklyChallenge.week_id(), lines, [[tr("Return home"), _go_home], [tr("Keep exploring"), _close_card]], "done")


func _go_home() -> void:
	_close_card()
	WeeklyChallenge.leave(get_tree())


func _show_card(title: String, sub: String, lines: Array, buttons: Array, kind: String) -> void:
	for c: Node in _card_root.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(500, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.92), Color(1, 1, 1, 0.1), 1, 10, 22))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	vb.add_child(UITheme.label(sub.to_upper(), 12, Color(0.4, 0.75, 1.0)))
	vb.add_child(UITheme.label(title, 28, Color.WHITE))
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(1, 1, 1, 0.08)
	vb.add_child(sep)
	for l: Array in lines:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var k: Label = UITheme.label(str(l[0]), 14, UITheme.MUTED)
		k.custom_minimum_size = Vector2(70, 0)
		hb.add_child(k)
		var v: Label = UITheme.label(str(l[1]), 15, l[2])
		v.autowrap_mode = TextServer.AUTOWRAP_WORD
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size = Vector2(380, 0)
		hb.add_child(v)
		vb.add_child(hb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var btns: Array[Button] = []
	for b: Array in buttons:
		var bt := Button.new()
		bt.text = str(b[0])
		bt.custom_minimum_size = Vector2(0, 44)
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb: Callable = b[1]
		bt.pressed.connect(func() -> void:
			Audio.play("click", 1.0, -6.0)
			cb.call())
		UITheme.juice(bt, 1.02)
		row.add_child(bt)
		btns.append(bt)
	if btns.size() > 1:
		UITheme.orange_button(btns[0])
	_first = btns[0] if not btns.is_empty() else null
	card_open = true
	card_kind = kind
	_card_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	if _first:
		_first.call_deferred("grab_focus")


func _close_card() -> void:
	if not card_open:
		return
	card_open = false
	_card_root.visible = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


func _unhandled_input(event: InputEvent) -> void:
	if card_open and card_kind == "done" and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		_close_card()
		get_viewport().set_input_as_handled()
