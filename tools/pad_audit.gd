class_name PadAudit
extends Node
## [deck] Controller-only audit (DevHooks `--pad-audit`, headless is fine). In the game scene it
## opens every screen and tab (workbench tabs incl. contracts, Command view, globe, codex tabs,
## pause menu and every Settings tab); on the title screen (`--menu --pad-audit`) the main
## menu and its Settings. For each it checks, as a pad-only player would meet it:
##   - something has focus (or the screen is driven without focus, e.g. the Command map);
##   - every visible focusable control is reachable from it with the D-pad (focus neighbours);
##   - no text entry (LineEdit / TextEdit) is needed;
##   - the pad's B button closes it.
## Prints "[pad] <screen>: OK | <problems>" per screen and "[pad] RESULT pass|fail".
## `--audit-shots=DIR` (rendered runs) also saves a screenshot of every screen into DIR, which
## makes it a one-process UI tour for checking layouts at a given resolution (e.g. 1280x800).
## [vqa] Headless: add --audit-size=1280x800 (and --ui-scale=1.0/1.1) for real screen bounds; text
## sticking out of its panel is reported as "overflow".

var _fails: int = 0
var _checked: int = 0
var _shots: Array[String] = []


## Screenshot of the current screen (when --audit-shots is set; after a couple of real frames).
func _shot() -> void:
	if not DevHooks.has("audit-shots") or _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(int(DevHooks.get_f("audit-frames", 3.0)))
	var name_: String = _shots[-1].to_lower().replace("/", "_").replace(" ", "_")
	DevHooks.save_viewport("%s/%02d_%s.png" % [DevHooks.get_s("audit-shots", "screenshots/ui_tour"), _checked, name_])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int = 3) -> void:
	for i: int in n:
		await get_tree().process_frame


func _press_pad(button: JoyButton) -> void:
	for down: bool in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		e.device = 0
		get_tree().root.push_input(e)
		await _frames(2)


func _run() -> void:
	# [vqa] Headless has no real window (its visible rect is a bogus square): --audit-size=WxH sets
	# the root viewport so the clipping / overflow checks see a real screen (1280x720, 1280x800...).
	if DevHooks.has("audit-size"):
		var wh: PackedStringArray = DevHooks.get_s("audit-size", "1280x720").split("x")
		get_tree().root.size = Vector2i(int(wh[0]), int(wh[1]))
	await _frames(20)
	# [ui3] The loader / title hands over to the game a few frames later: wait for it (60 s cap).
	if not DevHooks.has("menu"):
		var t0: int = Time.get_ticks_msec()
		while not (get_tree().current_scene and get_tree().current_scene.has_method("open_upgrades") and get_tree().current_scene.get("upgrades") != null) and Time.get_ticks_msec() - t0 < 120000:
			await _frames(5)
		await _frames(20)
	print("[pad] screen %s (interface scale %.2f)" % [get_tree().root.get_visible_rect().size, Settings.ui_scale])
	Settings.last_input_pad = true
	Settings.input_device_changed.emit(true)  # prompts switch to pad glyphs
	var scene: Node = get_tree().current_scene
	if scene and scene.has_method("open_upgrades"):
		await _audit_game(scene)
	else:
		await _audit_menu(scene)
	print("[pad] RESULT %s (%d screens, %d with problems)" % ["pass" if _fails == 0 else "fail", _checked, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _audit_game(w: Node) -> void:
	var up: UpgradesScreen = w.get("upgrades")
	up.open_screen()
	for t: Dictionary in UpgradesScreen.TABS:
		up.call("_set_tab", str(t["id"]))
		await _frames(4)
		up.call("_focus_default")
		await _frames(2)
		_check("Workbench/%s" % t["name"], up.get("_root"))
		await _shot()
	await _close_with_b("Workbench", func() -> bool: return up.is_open)
	await _audit_locker(w)
	var cv: CommandView = w.get("command")
	w.call("_open_command")
	await _frames(6)
	_check("Command view", cv.get("_root"))
	await _shot()
	await _close_with_b("Command view", func() -> bool: return cv.is_open)
	var gv: GlobeView = w.get("globe")
	gv.open_view()
	await _frames(6)
	_check("Globe map", gv.get("_root"))
	await _shot()
	await _close_with_b("Globe map", func() -> bool: return gv.is_open)
	var cx: CodexScreen = w.get("codex")
	for t: Dictionary in CodexScreen.TABS:
		cx.open_screen(str(t["id"]))
		await _frames(6)
		_check("Codex/%s" % t["name"], cx.get("_root"))
		await _shot()
		cx.close_screen()
		await _frames(2)
	cx.open_screen("codex")
	await _frames(4)
	await _close_with_b("Codex", func() -> bool: return cx.is_open)
	var pm: PauseMenu = w.get("pause_menu")
	pm.open_menu()
	await _frames(4)
	_check("Pause menu", pm.get("_root"))
	await _shot()
	var sp: SettingsPanel = pm.get("_settings")
	pm.call("_open_settings")
	await _frames(4)
	await _audit_settings(sp, "Pause/Settings")
	await _close_with_b("Pause/Settings", func() -> bool: return sp.is_open)
	await _close_with_b("Pause menu", func() -> bool: return pm.is_open)
	# A presses the focused button: Resume closes the menu.
	pm.open_menu()
	await _frames(4)
	(pm.get("_first") as Button).grab_focus()
	await _press_pad(JOY_BUTTON_A)
	await _frames(3)
	_checked += 1
	if pm.is_open:
		_fail("Pause menu", "A does not press the focused button")
	else:
		print("[pad] Pause menu: A presses Resume OK")


func _audit_menu(m: Node) -> void:
	await _frames(10)
	var ui: Control = m.get("_ui")
	_check("Title menu", ui)
	await _shot()
	var sp: SettingsPanel = m.get("_settings")
	if sp:
		if m.has_method("_open_settings"):
			m.call("_open_settings")
		else:
			sp.open_panel()
		await _frames(4)
		await _audit_settings(sp, "Title/Settings")
		await _close_with_b("Title/Settings", func() -> bool: return sp.is_open)


func _audit_settings(sp: SettingsPanel, label: String) -> void:
	for i: int in SettingsPanel.TABS.size():
		sp.select_tab(i)
		await _frames(3)
		(sp.get("_tab_buttons") as Array)[i].grab_focus()
		await _frames(2)
		_check("%s/%s" % [label, SettingsPanel.TABS[i]], sp)
		await _shot()


## [ui7] The Locker overlay, every section (Lumi, Glim, Bots, Rocket). The audit opens all four:
## it builds the Locker, finds Glim and lifts the rocket tier for this run only.
func _audit_locker(w: Node) -> void:
	YardBuilds.mark_built("locker")
	Glim.st()["found"] = true
	if int(GameState.flags.get("rocket_tier", 1)) < 2:
		GameState.flags["rocket_tier"] = 2
	var cl: CanvasLayer = LockerPanel.open_overlay(w)
	await _frames(6)
	var lp: LockerPanel = null
	for n: Node in cl.find_children("*", "", true, false):
		if n is LockerPanel:
			lp = n as LockerPanel
			break
	var root: Control = cl.get_child(0) as Control
	var secs: Array[String] = []
	for b: Button in lp.get("_who_btns"):
		secs.append(str(b.get_meta("who")))
	for want: String in ["target:lumi", "target:glim", "bots", "rocket"]:
		if not (want in secs):
			_fail("Locker", "no %s section" % want)
	for sec: String in secs:
		lp.set_editing(sec)
		await _frames(5)
		var f: Button = lp.first_button()
		if f:
			f.grab_focus()
		await _frames(2)
		_check("Locker/%s" % sec.trim_prefix("target:"), root)
		await _shot()
	await _close_with_b("Locker", func() -> bool: return is_instance_valid(cl) and not cl.has_meta("closing"))
	await _frames(10)


func _close_with_b(label: String, still_open: Callable) -> void:
	await _press_pad(JOY_BUTTON_B)
	await _frames(3)
	if still_open.call():
		_fail(label, "B does not close it")


func _fail(label: String, why: String) -> void:
	_fails += 1
	print("[pad] %s: FAIL %s" % [label, why])


## Focus reachability from the focused control over D-pad neighbours only (no Tab key on a pad).
func _check(label: String, root: Control, focus_optional: bool = false) -> void:
	_checked += 1
	_shots.append(label)
	var problems: Array[String] = []
	if root == null or not root.is_visible_in_tree():
		_fail(label, "screen not visible")
		return
	var all: Array[Control] = []
	for n: Node in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		# Disabled buttons can't take focus in Godot 4 (nothing to do there anyway): not required.
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		if c.is_visible_in_tree() and c.focus_mode == Control.FOCUS_ALL and not c.is_queued_for_deletion():
			if c is LineEdit or c is TextEdit:
				problems.append("text entry %s" % c.name)
			all.append(c)
	var start: Control = get_viewport().gui_get_focus_owner()
	if start == null or not root.is_ancestor_of(start):
		if not all.is_empty() and not focus_optional:
			problems.append("nothing focused on open")
		start = all[0] if not all.is_empty() else null
	var seen: Dictionary = {}
	if start:
		var queue: Array[Control] = [start]
		seen[start] = true
		while not queue.is_empty():
			var c: Control = queue.pop_front()
			var nexts: Array[Control] = []
			for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				nexts.append(c.find_valid_focus_neighbor(side))
			for nx: Control in nexts:
				if nx and not seen.has(nx) and root.is_ancestor_of(nx):
					seen[nx] = true
					queue.append(nx)
	var missing: Array[String] = []
	for c: Control in all:
		if not seen.has(c):
			missing.append(_name(c))
	if not missing.is_empty() and DevHooks.has("audit-why"):  # [ui7] where the unreachable ones sit
		for c: Control in all:
			if not seen.has(c):
				print("[pad]   unreachable: %s (%s) text=%s" % [root.get_path_to(c), c.get_parent().get_class(), str(c.get("text")).left(24)])
	if not missing.is_empty():
		problems.append("%d unreachable: %s" % [missing.size(), ", ".join(missing.slice(0, 6))])
	# Panels must fit the screen (e.g. 1280x800 at 110% interface scale): anything visible poking
	# out of the visible rect, except content inside scroll areas, counts as clipped.
	var vr: Rect2 = root.get_viewport_rect().grow(1.0)
	var clipped: Array[String] = []
	for n: Node in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if not c.is_visible_in_tree() or c is ScrollContainer or c.size == Vector2.ZERO:
			continue
		var p: Node = c.get_parent()
		var in_scroll: bool = false
		while p and p != root:
			if p is ScrollContainer:
				in_scroll = true
				break
			p = p.get_parent()
		if in_scroll or c.mouse_filter == Control.MOUSE_FILTER_IGNORE and not (c is Label or c is Button):
			continue
		if not vr.encloses(c.get_global_rect()) and (c is Button or c is Label or c is PanelContainer):
			clipped.append(_name(c) + ("@%s" % c.get_global_rect() if c is PanelContainer else ""))
	if not clipped.is_empty():
		problems.append("%d clipped: %s" % [clipped.size(), ", ".join(clipped.slice(0, 5))])
		if DevHooks.has("audit-why"):  # [vqa] which child sets the width: the widest minimum-size chain
			for n: Node in root.find_children("*", "PanelContainer", true, false):
				var pc: Control = n as Control
				if pc.is_visible_in_tree() and not vr.encloses(pc.get_global_rect()):
					var cur: Control = pc
					var chain: Array[String] = []
					while cur and chain.size() < 14:
						chain.append("%s %d" % [_name(cur), int(cur.get_combined_minimum_size().x)])
						var best: Control = null
						for ch: Node in cur.get_children():
							if ch is Control and (ch as Control).visible and (best == null or (ch as Control).get_combined_minimum_size().x > best.get_combined_minimum_size().x):
								best = ch as Control
						cur = best
					print("[pad]   why: ", " > ".join(chain))
					break
	# [vqa] Text overflow (long German / pseudo strings): a label or button sticking out of the
	# panel that holds it, or a clipped button whose text no longer fits.
	var over: Array[String] = []
	var trunc: Array[String] = []  # ellipsized on purpose: reported, not a failure
	for n: Node in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if not (c is Label or c is Button or c is RichTextLabel) or not c.is_visible_in_tree() or c.size == Vector2.ZERO:
			continue
		var panel: Control = null
		var q: Node = c.get_parent()
		var scrolled: bool = false
		while q and q != root:
			if q is ScrollContainer:
				scrolled = true
			if q is PanelContainer or q is Panel:
				panel = q as Control
				break
			q = q.get_parent()
		if panel and not scrolled and panel.is_visible_in_tree() and not panel.get_global_rect().grow(2.0).encloses(c.get_global_rect()):
			over.append(_name(c))
		elif c is Button and (c as Button).clip_text and (c as Button).text != "":
			var b: Button = c
			var font: Font = b.get_theme_font("font")
			var fs: int = b.get_theme_font_size("font_size")
			var widest: float = 0.0
			for line: String in b.text.split("\n"):
				widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font else 0.0)
			var pad: float = b.get_theme_stylebox("normal").get_minimum_size().x if b.get_theme_stylebox("normal") else 0.0
			if widest + pad > b.size.x + 2.0:
				trunc.append(_name(c))
	if not over.is_empty():
		problems.append("%d overflow: %s" % [over.size(), ", ".join(over.slice(0, 6))])
	if not trunc.is_empty():
		print("[pad] %s: note %d truncated with an ellipsis: %s" % [label, trunc.size(), ", ".join(trunc.slice(0, 6))])
	if problems.is_empty():
		print("[pad] %s: OK (%d focus stops)" % [label, all.size()])
	else:
		_fail(label, "; ".join(problems))


func _name(c: Control) -> String:
	var t: String = str(c.get("text")) if c.get("text") != null else ""
	return "%s'%s'" % [c.get_class(), t.left(18)] if t != "" else str(c.name)
