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

var _fails: int = 0
var _checked: int = 0
var _shots: Array[String] = []


## Screenshot of the current screen (when --audit-shots is set; after a couple of real frames).
func _shot() -> void:
	if not DevHooks.has("audit-shots") or _shots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(int(DevHooks.get_f("audit-frames", 3.0)))
	var name: String = _shots[-1].to_lower().replace("/", "_").replace(" ", "_")
	DevHooks.save_viewport("%s/%02d_%s.png" % [DevHooks.get_s("audit-shots", "screenshots/ui_tour"), _checked, name])


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
	await _frames(20)
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
	if not missing.is_empty():
		problems.append("%d unreachable: %s" % [missing.size(), ", ".join(missing.slice(0, 6))])
	if problems.is_empty():
		print("[pad] %s: OK (%d focus stops)" % [label, all.size()])
	else:
		_fail(label, "; ".join(problems))


func _name(c: Control) -> String:
	var t: String = str(c.get("text")) if c.get("text") != null else ""
	return "%s'%s'" % [c.get_class(), t.left(18)] if t != "" else str(c.name)
