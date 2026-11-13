class_name UIAuditRun
extends Node
## [v6screens] Dev: the layout audit of the round game's 2D screens, by numbers (headless, no
## render). Lays every screen out at the sizes and interface scales players use, in every language,
## and reports what is off-screen, cut, overlapping, covering Lumi, or lost to the gamepad.
##   In the game:   godot --headless --path . -- --fresh --orbit --no-intro --ui-audit
##   Title screen:  godot --headless --path . -- --menu --ui-audit
## Options:
##   --ui-audit-sizes=1280x720,1920x1080   (default SIZES)
##   --ui-audit-scales=0.8,1,1.5           (default SCALES)
##   --ui-audit-locales=en,de,pseudo       (default LOCALES: the six languages, English, pseudo)
##   --ui-audit-screens=pause,settings     (default: all; names in SCREENS / TITLE_SCREENS)
##   --ui-audit-verbose                    every issue in every configuration, not one per place
##   --ui-audit-stay                       no quit; the long line stays up (for a `--shot` render)
## Prints `[ui-audit]` lines and `[ui-audit] done: N issues` and quits (exit 1 on issues). An issue
## seen in several configurations is printed once with how many and the first few.
## The checks themselves are tools/ui_audit.gd (UIAudit). See docs/QA_VERDANCE.md.
##
## Play pass: a long WREN line on the subtitle bar at the default camera, with the goal stack as
## it is and expanded. The bar must not touch Lumi's body (LumiScreen) or the goal stack, and where
## it covers the hotbar the hotbar must be dimmed.

## [v8ui] 1500x1000: a 3:2 laptop window (the owner's MacBook, item 76).
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1280, 800), Vector2i(1500, 1000)]
const SCALES: Array[float] = [0.8, 1.0, 1.25, 1.5]
const LOCALES: Array[String] = ["en", "de", "fr", "es", "pt_BR", "zh_CN", "ja", "pseudo"]
const SCREENS: Array[String] = ["play", "hud", "card", "prompts", "arrival", "pause", "settings", "workbench", "locker", "survey", "loading", "codex", "rockets", "system", "document", "photo", "glim", "garden", "command", "tbc", "pad"]
const TITLE_SCREENS: Array[String] = ["title", "title_settings", "pad"]
## A long line, about the longest chunk the bar shows (Subtitles.MAX_CHARS).
const LONG_LINE: String = "Bring every cube you scoop to the bench by the pod, and we can fix the old beacon"

var so: Node  # SliceOrbit (null on the title screen)
var title: bool = false
var issues: int = 0
var _seen: Dictionary = {}  # key -> {line, configs: Array[String]}
var _order: Array[String] = []


static func attach(p_so: Node) -> UIAuditRun:
	var r := UIAuditRun.new()
	r.name = "UIAuditRun"
	r.so = p_so
	p_so.add_child(r)
	return r


## On the title screen: the runner lives on the root so it survives reloading the menu per language.
static func attach_title(tree: SceneTree) -> void:
	if tree.root.has_node("UIAuditRun"):
		return
	var r := UIAuditRun.new()
	r.name = "UIAuditRun"
	r.title = true
	tree.root.add_child.call_deferred(r)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _wait_s(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _list(flag: String, all: Array) -> Array:
	var s: String = DevHooks.get_s(flag, "")
	if s == "":
		return all
	return Array(s.split(","))


func sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Variant in _list("ui-audit-sizes", []):
		var xy: PackedStringArray = str(p).split("x")
		if xy.size() == 2:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	return SIZES if out.is_empty() else out


func scales() -> Array[float]:
	var out: Array[float] = []
	for p: Variant in _list("ui-audit-scales", []):
		out.append(float(str(p)))
	return SCALES if out.is_empty() else out


func _want(screen: String) -> bool:
	return screen in _list("ui-audit-screens", SCREENS + TITLE_SCREENS)


func _set_locale(loc: String) -> void:
	Settings.locale_override = loc
	Settings.apply_language()


## Calls `check(cfg)` at every size and interface scale (awaited).
func _each_size(name_: String, check: Callable) -> void:
	var root: Window = get_tree().root
	for sz: Vector2i in sizes():
		for sc: float in scales():
			root.size = sz
			Settings.ui_scale = sc
			Settings.apply_ui_scale()
			await _frames(3)
			await check.call("%s %s %dx%d@%.2f" % [name_, TranslationServer.get_locale(), sz.x, sz.y, sc])


func _run() -> void:
	await _frames(int(DevHooks.get_f("ui-audit-wait", 120.0)))
	var root: Window = get_tree().root
	var size0: Vector2i = root.size
	var scale0: float = Settings.ui_scale
	var loc0: String = Settings.locale_override
	if title:
		await _run_title()
	else:
		if _want("play"):
			_set_locale("en")
			await _each_size("play", _play_pass)
		for loc: Variant in _list("ui-audit-locales", LOCALES):
			_set_locale(str(loc))
			await _frames(2)
			await _screens_pass()
		if _want("pad"):
			_set_locale("en")
			await _pad_pass()
	root.size = size0
	Settings.ui_scale = scale0
	Settings.apply_ui_scale()
	_set_locale(loc0)
	_flush()
	print("[ui-audit] done: %d issues (%d places)" % [issues, _order.size()])
	if not DevHooks.has("ui-audit-stay"):
		get_tree().quit(1 if issues > 0 else 0)
		return
	while is_inside_tree():  # --ui-audit-stay: keep the long line up (for a --shot render)
		if Subtitles.current and Subtitles.current.current_text() == "":
			Subtitles.current.show_now(tr(LONG_LINE), "wren")
		await _frames(10)


# --- Reporting ---------------------------------------------------------------------------

func _report(cfg: String, kind: String, what: String, note: String) -> void:
	_add(cfg, "%s %s" % [kind.to_upper(), what], "[ui-audit] %s %s %s  %s" % [kind.to_upper(), cfg, what, note])


func _add(cfg: String, key: String, line: String) -> void:
	issues += 1
	if DevHooks.has("ui-audit-verbose"):
		print(line)
	if not _seen.has(key):
		_seen[key] = {"line": line, "configs": []}
		_order.append(key)
	(_seen[key]["configs"] as Array).append(cfg)


func _flush() -> void:
	for k: String in _order:
		var e: Dictionary = _seen[k]
		var cs: Array = e["configs"]
		var locs: Dictionary = {}
		for c: Variant in cs:
			var parts: PackedStringArray = str(c).split(" ")
			if parts.size() >= 2:
				locs[parts[1]] = true
		print("%s   [x%d; %s; e.g. %s]" % [e["line"], cs.size(), ",".join(PackedStringArray(locs.keys())), ", ".join(PackedStringArray(cs.slice(0, 3)))])


var _counted: Dictionary = {}


func _audit(cfg: String, screen: String, roots: Array, gamepad: bool = true, other_ways: Array = []) -> void:
	var view: Rect2 = get_viewport().get_visible_rect()
	var sname: String = cfg.split(" ")[0]
	if not _counted.has(sname):  # what was looked at, once per screen (a screen with 0 is not open)
		_counted[sname] = true
		print("[ui-audit] screen %s: %d texts/buttons, %d focusable" % [sname, UIAudit.content_of(roots).size(), UIAudit.focusables(roots).size()])
	for d: Dictionary in UIAudit.layout(roots, view, _ok_overlap):
		_add(cfg, "%s %s %s %s" % [d["kind"], screen, d["node"], _note_kind(str(d["note"]))], UIAudit.line(screen, cfg, d))
	if gamepad:
		for d: Dictionary in UIAudit.focus(roots, get_viewport(), other_ways):
			_add(cfg, "%s %s %s" % [d["kind"], screen, d["node"]], UIAudit.line(screen, cfg, d))


## The part of a note that names the problem, without its numbers (for grouping).
static func _note_kind(note: String) -> String:
	var re := RegEx.create_from_string("[0-9]+")
	return re.sub(note, "#", true).left(40)


## Pairs that overlap on purpose: a label laid over its own button or bar, decorative glyphs.
static func _ok_overlap(a: Control, b: Control) -> bool:
	for c: Control in [a, b]:
		if c.has_meta("ui_audit_overlap_ok"):
			return true
	return false


# --- Play pass ---------------------------------------------------------------------------

func _play_pass(cfg: String) -> void:
	var w: Node = so.get("w")
	var hud: Node = w.get("hud") if w else null
	var cam: SphereCam = so.get("cam")
	var patch: Node3D = w.get("patch") as Node3D if w else null
	var subs: Subtitles = Subtitles.current
	if hud == null or cam == null or patch == null or subs == null:
		_report(cfg, "missing", "world", "hud=%s cam=%s patch=%s subs=%s" % [hud != null, cam != null, patch != null, subs != null])
		return
	var goals: GoalsPanel = hud.get("goals") as GoalsPanel
	for expand: bool in [false, true]:
		if goals:
			goals.expanded = expand
		var c2: String = cfg + (" goals+" if expand else "")
		subs.show_now(tr(LONG_LINE), "wren")
		await _frames(40)
		_check_play(c2, hud, cam, patch, subs, goals)
		subs.clear()
		await _frames(2)
	if goals:
		goals.expanded = false


func _check_play(cfg: String, hud: Node, cam: SphereCam, patch: Node3D, subs: Subtitles, goals: GoalsPanel) -> void:
	var view: Rect2 = get_viewport().get_visible_rect()
	var lr: Rect2 = LumiScreen.rect(patch, cam.camera)
	var pill: Rect2 = UIAudit.rect_of(subs.pill())
	var hb: Control = hud.get("hotbar") as Control
	var gr: Rect2 = UIAudit.rect_of(goals) if goals and goals.is_visible_in_tree() else Rect2()
	if hud.has_method("corner_rect"):  # [v7look] the goal stack and the base card under it
		gr = hud.call("corner_rect")
	if DevHooks.has("ui-audit-verbose"):
		print("[ui-audit] play %s view %dx%d lumi %s pill %s goals %s" % [cfg, roundi(view.size.x), roundi(view.size.y), _r(lr), _r(pill), _r(gr)])
	if lr.size.y < 1.0:
		_report(cfg, "missing", "Lumi", "not on screen")
	if not subs.pill().visible or subs.pill().modulate.a < 0.5:
		_report(cfg, "hidden", "subtitle", "the line is not showing")
	if not view.encloses(pill):
		_report(cfg, "offscreen", "subtitle", _r(pill))
	if pill.intersects(lr):
		_report(cfg, "covers", "subtitle over Lumi", "pill %s lumi %s" % [_r(pill), _r(lr)])
	if gr.size.y > 0.0 and pill.intersects(gr):
		_report(cfg, "covers", "subtitle over the goal card", "goals %s" % _r(gr))
	var kh: Control = hud.get("_hints") as Control  # [v7look] the key-hint pill: off the hotbar, never mid-screen
	if kh and kh.is_visible_in_tree() and kh.modulate.a > 0.05 and hb and hb.is_visible_in_tree():
		var kr: Rect2 = UIAudit.rect_of(kh)
		var slots: Rect2 = hb.get_global_rect().grow_side(SIDE_TOP, -14.0)
		if kr.intersects(slots.grow_side(SIDE_LEFT, -90.0).grow_side(SIDE_RIGHT, -90.0)) and minf(kr.intersection(slots).size.x, kr.intersection(slots).size.y) >= UIAudit.OVERLAP_MIN:
			_report(cfg, "overlap", "key hints with the hotbar", "hints %s hotbar %s" % [_r(kr), _r(slots)])
		var hm: Control = hud.get("_hints_mc") as Control
		var giving: bool = float(hud.get("_hints_give")) < 0.95  # fading out (it takes 0.25 s)
		if subs.pill().visible and (hm == null or hm.modulate.a > 0.1) and not giving:
			_report(cfg, "covers", "key hints still up during a WREN line", "hints %s pill %s" % [_r(kr), _r(pill)])
		if kr.size.y > 60.0:
			_report(cfg, "offplace", "key hints wrap to more than one row", "hints %s" % _r(kr))
		if kr.position.y < view.size.y * 0.55:
			_report(cfg, "offplace", "key hints mid-screen", "hints %s view %dx%d" % [_r(kr), roundi(view.size.x), roundi(view.size.y)])
	if hb and hb.is_visible_in_tree():
		var ink: Rect2 = hb.get_global_rect().grow_side(SIDE_TOP, -14.0)
		if pill.intersects(ink) and hb.self_modulate.a > 0.5:
			_report(cfg, "covers", "subtitle over the hotbar (not dimmed)", "hotbar %s" % _r(ink))


static func _r(r: Rect2) -> String:
	return "%d,%d %dx%d" % [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]


# --- Screens in the game -----------------------------------------------------------------

func _screens_pass() -> void:
	var w: Node = so.get("w")
	var hud: Node = w.get("hud")
	if _want("hud") and hud:
		await _each_size("hud", func(cfg: String) -> void: _audit(cfg, "hud", [hud], false))
	if _want("card") and hud:  # [v9d] the objective card on steps with a count, a price in two currencies, a long reason
		var ob: Objectives = w.get("objectives") as Objectives
		var tut: Variant = w.get("tutorial")
		if ob:
			var keep: int = ob.step
			if tut is Tutorial:
				(tut as Tutorial).step = Tutorial.STEPS.size()
				EventBus.tutorial_changed.emit("")
			ob.revealed = true
			for sid: String in ["dump3", "bench2", "base2", "hub_wake_4", "robot"]:
				var k: int = ob.chain.map(func(d: Dictionary) -> String: return str(d.get("id", ""))).find(sid)
				if k < 0:
					continue
				ob.step = k
				ob.changed.emit(k)
				await _frames(4)
				await _each_size("card/" + sid, func(cfg: String) -> void: _audit(cfg, "card", [hud], false))
			ob.step = keep
			ob.changed.emit(keep)
	if _want("prompts") and hud:
		await _each_size("prompts", func(cfg: String) -> void: _check_prompts(cfg, hud))
	if _want("pause"):
		var pm := PauseMenu.new()  # fresh: its buttons are worded when it is built
		w.add_child(pm)
		await _frames(2)
		pm.open_menu()
		await _wait_s(0.4)
		await _each_size("pause", func(cfg: String) -> void: _audit(cfg, "pause", [pm]))
		if _want("settings"):
			pm.call("_open_settings")
			await _wait_s(0.4)
			var sp: SettingsPanel = pm.get("_settings")
			for i: int in SettingsPanel.TABS.size():
				sp.select_tab(i)
				var tabs: Array = sp.get("_tab_buttons")
				if i > 0:
					(tabs[i] as Control).grab_focus()  # as "More settings" and the bumpers do
				await _wait_s(0.1)
				await _each_size("settings/" + SettingsPanel.TABS[i], func(cfg: String) -> void: _audit(cfg, "settings", [sp], true, tabs))
		pm.close_menu()
		await _frames(2)
		pm.queue_free()
		get_tree().paused = false
		await _frames(2)
	if _want("workbench"):
		var up := UpgradesScreen.new()
		up.fleet = w.get("fleet")
		up.hub = w.get("hub")
		w.add_child(up)
		await _frames(2)
		up.open_screen()
		await _wait_s(0.6)
		for t: Dictionary in UpgradesScreen.TABS:
			var id: String = str(t["id"])
			if not UpgradesScreen.tab_visible(id, w):
				continue
			up.call("_set_tab", id)
			await _wait_s(0.2)
			await _each_size("workbench/" + id, func(cfg: String) -> void: _audit(cfg, "workbench", [up], true, _tab_buttons_of(up)))
		up.close_screen()
		await _wait_s(0.3)
		up.queue_free()
		get_tree().paused = false
		await _frames(2)
	if _want("locker"):
		var cl: CanvasLayer = LockerPanel.open_overlay(w)
		await _wait_s(0.6)
		await _each_size("locker", func(cfg: String) -> void: _audit(cfg, "locker", [cl]))
		for b: Node in cl.find_children("*", "Button", true, false):
			if (b as Button).text == TranslationServer.translate("Close"):
				(b as Button).pressed.emit()
				break
		await _wait_s(0.4)
		if is_instance_valid(cl):
			cl.queue_free()
		get_tree().paused = false
	if _want("survey"):
		var layers: Node = so.get("layers")
		var gv: GlobeView = layers.get("survey") as GlobeView if layers else null
		if gv:
			gv.open_view()
			await _wait_s(0.8)
			await _each_size("survey", func(cfg: String) -> void: _audit(cfg, "survey", [gv]))
			gv.close_view()
			await _wait_s(0.5)
			so.call("set_input", true)
			get_tree().paused = false
	for e: Dictionary in _extra_screens():
		if not _want(str(e["name"])):
			continue
		await (e["open"] as Callable).call()
		await _wait_s(0.6)
		var tabs: Array = (e["tabs"] as Callable).call() if e.has("tabs") else [""]
		for t: Variant in tabs:
			if e.has("set_tab"):
				await (e["set_tab"] as Callable).call(t)
				await _wait_s(0.2)
			var nm: String = str(e["name"]) + ("/" + str(t) if str(t) != "" else "")
			var root: Node = (e["root"] as Callable).call()
			await _each_size(nm, func(cfg: String) -> void: _audit(cfg, str(e["name"]), [root], true, (e["other"] as Callable).call() if e.has("other") else []))
		await (e["close"] as Callable).call()
		await _wait_s(0.4)
		get_tree().paused = false
	if _want("command"):
		await _command_pass()
	if _want("arrival"):
		await _arrival_pass()
	if _want("loading"):
		var ld: CanvasLayer = get_tree().root.get_node_or_null("Loader") as CanvasLayer
		if ld:
			ld.visible = true
			for stage: int in 4:
				(ld.get("_status") as Label).text = ld.call("_status_text", stage)
				await _each_size("loading/%d" % stage, func(cfg: String) -> void: _audit(cfg, "loading", [ld], false))
			ld.visible = false


## Screens opened from the pause menu, the rocket and the map, and a found document:
## {name, open, close, is_open, root, [tabs, set_tab, other]} (callables; open/close may await).
func _extra_screens() -> Array[Dictionary]:
	var w: Node = so.get("w")
	var out: Array[Dictionary] = []
	var cx: CodexScreen = w.get("codex") as CodexScreen
	if cx:
		out.append({"name": "codex", "root": func() -> Node: return cx,
			"open": func() -> void: cx.open_screen("codex"), "close": func() -> void: cx.close_screen(),
			"is_open": func() -> bool: return cx.is_open,
			"tabs": func() -> Array: return CodexScreen.TABS.map(func(t: Dictionary) -> String: return str(t["id"])),
			"set_tab": func(t: Variant) -> void: cx.open_screen(str(t)),
			"other": func() -> Array: return _buttons_named(cx, "Tab")})
	var sites: Node = so.get("sites")
	var pk: RocketPicker = sites.get("picker") as RocketPicker if sites else null
	if pk:
		out.append({"name": "rockets", "root": func() -> Node: return pk,
			"open": func() -> void: pk.open(), "close": func() -> void: pk.close(), "is_open": func() -> bool: return pk.is_open})
	var layers: Node = so.get("layers")
	var sm: SystemMap = layers.get("system_map") as SystemMap if layers else null
	if sm:
		out.append({"name": "system", "root": func() -> Node: return sm,
			"open": func() -> void: sm.open_map(true), "close": func() -> void: sm.close_map(), "is_open": func() -> bool: return sm.is_open})
	var ph: PhotoMode = w.get("photo") as PhotoMode
	if ph:
		out.append({"name": "photo", "root": func() -> Node: return ph,
			"open": func() -> void: ph.open(), "close": func() -> void: ph.close(), "is_open": func() -> bool: return ph.is_open})
	var gp: GlimPanel = w.get_node_or_null("GlimPanel") as GlimPanel
	if gp:
		out.append({"name": "glim", "root": func() -> Node: return gp,
			"open": func() -> void: gp.open_panel(), "close": func() -> void: gp.close_panel(), "is_open": func() -> bool: return gp.is_open})
	var gpl: GardenPlacer = w.get_node_or_null("GardenPlacer") as GardenPlacer
	if gpl and Decor.unlocked():  # needs base level 5, the Cradle, or --garden
		out.append({"name": "garden", "root": func() -> Node: return gpl,
			"open": func() -> void: gpl.open(), "close": func() -> void: gpl.close(), "is_open": func() -> bool: return gpl.is_open})
	var hd: HomewardDirector = HomewardDirector.of(w)  # [v7play] the "to be continued" card
	if hd and hd.tbc:
		var tc: ToBeContinued = hd.tbc
		out.append({"name": "tbc", "root": func() -> Node: return tc,
			"open": func() -> void: tc.open_card(), "close": func() -> void: tc.close_card(), "is_open": func() -> bool: return tc.is_open})
	var dv: Node = w.get("doc_view") as Node
	if dv:
		var doc: Dictionary = {}
		var f := FileAccess.open("res://data/ledger.json", FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				doc = (d as Dictionary).get("contract_doc", {})
		if not doc.is_empty():
			out.append({"name": "document", "root": func() -> Node: return dv,
				"open": func() -> void: dv.call("show_doc", doc), "close": func() -> void: dv.call("close_doc"),
				"is_open": func() -> bool: return bool(dv.get("is_open"))})
	return out


## Buttons a screen reaches by bumpers rather than the d-pad (its tab strip): every Button whose
## parent holds several toggle buttons.
static func _buttons_named(root: Node, _hint: String) -> Array:
	var out: Array = []
	for b: Node in root.find_children("*", "Button", true, false):
		if (b as Button).toggle_mode or (b as Button).button_group != null:
			out.append(b)
	return out


## The Command view's boxes are drawn, not Controls (robots/sphere/command_overlay.gd keeps
## their rects in `panels`): each must be on screen, and clear of the HUD's texts and each other.
func _command_pass() -> void:
	var cam: SphereCam = so.get("cam")
	var w: Node = so.get("w")
	var hud: Node = w.get("hud")
	# [v8bot] Owner: a Salvage Surge banner sat right on the Command view's hint. Raise an event so
	# its banner is up (it must step aside), and paint a zone so the card's "Robots here" row shows
	# (with --robots=scoopie:3 the crew has robots to count).
	var ev: WorldEvents = w.get("events") as WorldEvents
	if ev != null and ev.active.is_empty():
		if not ev.start("salvage_surge", true):
			ev.start_random()
	var crew_: SphereCrew = SphereCrew.active
	if crew_ != null and crew_.hub_cell >= 0:
		var around: PackedInt32Array = crew_.grid.cells_around(crew_.hub_cell, 2)
		for k: int in mini(2, around.size() - 8):
			crew_.set_zone_cell("clean", around[8 + k], true)
	cam.view = "command"
	so.get("crews").call("on_view", so)
	await _wait_s(2.5)
	var ov: CommandOverlay = null
	for n: Node in get_tree().root.find_children("*", "Control", true, false):
		if n is CommandOverlay:
			ov = n
	if ov == null:
		_report("command", "missing", "Command view overlay", "")
	else:
		await _each_size("command", func(cfg: String) -> void: await _check_command(cfg, ov, hud))
	cam.view = "follow"
	so.get("crews").call("on_view", so)
	await _wait_s(1.5)


func _check_command(cfg: String, ov: CommandOverlay, hud: Node) -> void:
	ov.queue_redraw()
	await _frames(2)
	var view: Rect2 = get_viewport().get_visible_rect()
	var ps: Array[Dictionary] = ov.panels.duplicate()
	if not _counted.has("command"):
		_counted["command"] = true
		print("[ui-audit] screen command: %d drawn boxes (%s)" % [ps.size(), ", ".join(PackedStringArray(ps.map(func(p: Dictionary) -> String: return str(p["name"]))))])
	var huds: Array[Control] = UIAudit.content_of([hud]) if hud else []
	var ev: WorldEvents = so.get("w").get("events") as WorldEvents  # [v8bot] the event banner too
	if ev != null and ev.hud != null:
		huds.append_array(UIAudit.content_of([ev.hud]))
		if not _counted.has("command_event"):
			_counted["command_event"] = true
			print("[ui-audit] command: event %s up" % str(ev.active.get("id", "none")))
	for i: int in ps.size():
		var r: Rect2 = ps[i]["rect"]
		var nm: String = str(ps[i]["name"])
		if not view.grow(1.5).encloses(r):
			_report(cfg, "offscreen", "command " + nm, "%s view %dx%d" % [_r(r), roundi(view.size.x), roundi(view.size.y)])
		for j: int in range(i + 1, ps.size()):
			var x: Rect2 = r.intersection(ps[j]["rect"])
			if minf(x.size.x, x.size.y) >= UIAudit.OVERLAP_MIN:
				_report(cfg, "overlap", "command %s with %s" % [nm, ps[j]["name"]], _r(x))
		for c: Control in huds:
			var x2: Rect2 = r.intersection(UIAudit.clip_rect(c, UIAudit.rect_of(c)))
			if minf(x2.size.x, x2.size.y) >= UIAudit.OVERLAP_MIN:
				_report(cfg, "overlap", "command %s with HUD %s" % [nm, UIAudit.short_path(c)], "\"%s\" %s" % [UIAudit.text_of(c).left(32), _r(x2)])


## [v7look] A base's arrival title (hub_purpose.gd show_title), the hub with the longest words in this
## language, with a long WREN line up: it must fit the screen, wrap without cutting, and stay clear of
## the top-right cards (they step aside), the cube counter and the subtitle bar.
func _arrival_pass() -> void:
	var w: Node = so.get("w")
	var hud: HUD = w.get("hud") as HUD
	var sites: Node = so.get("sites")
	var hp: HubPurpose = sites.get("purpose") as HubPurpose if sites else null
	var subs: Subtitles = Subtitles.current
	if hp == null or hud == null or subs == null:
		_report("arrival", "missing", "arrival title", "purpose=%s hud=%s subs=%s" % [hp != null, hud != null, subs != null])
		return
	var best: int = -1
	var most: int = -1
	for i: int in range(1, HubPlan.main_total(hp.planet) + 1):
		var n: int = HubPlan.hub_name(hp.planet, i).length() * 3 + tr(HubPlan.reason(hp.planet, i)).length()
		if HubPlan.hub_name(hp.planet, i) != "" and n > most:
			most = n
			best = i
	if best < 0:
		_report("arrival", "missing", "arrival title", "no hub with a name")
		return
	print("[ui-audit] screen arrival: the title of hub %d (%s)" % [best, HubPlan.hub_name(hp.planet, best)])
	await _each_size("arrival", func(cfg: String) -> void:
		subs.show_now(tr(LONG_LINE), "wren")
		hp.show_title(best)
		await _wait_s(0.45)
		_check_arrival(cfg, hp, hud, subs))
	var t: Control = hp.title_node()
	if t:
		t.queue_free()
	hud.hold_corner(0.0)
	subs.hush(0.0)
	subs.clear()
	await _frames(2)


func _check_arrival(cfg: String, hp: HubPurpose, hud: HUD, subs: Subtitles) -> void:
	var t: Control = hp.title_node()
	if t == null:
		_report(cfg, "missing", "arrival title", "not shown")
		return
	var view: Rect2 = get_viewport().get_visible_rect()
	var tr_: Rect2 = UIAudit.rect_of(t)
	if not view.grow(1.5).encloses(tr_):
		_report(cfg, "offscreen", "arrival title", "%s view %dx%d" % [_r(tr_), roundi(view.size.x), roundi(view.size.y)])
	for l: Node in t.get_children():
		if l is Label:
			var why: String = UIAudit.label_clipped(l as Label)
			if why != "":
				_report(cfg, "clipped", "arrival title", "\"%s\" %s" % [(l as Label).text.left(32), why])
	var others: Dictionary = {"the top-right cards": hud.corner_rect(), "the subtitle bar": UIAudit.rect_of(subs.pill()) if subs.pill().visible and not subs.hushed() else Rect2()}
	if not subs.hushed():
		_report(cfg, "covers", "arrival title with WREN's bar still up", "the bar should fade out while the title shows")
	var bottom: Control = hud.get("_bottom") as Control
	if bottom and bottom.is_visible_in_tree() and bottom.modulate.a > 0.05:
		_report(cfg, "covers", "arrival title with the hotbar still up", "alpha %.2f" % bottom.modulate.a)
	var tl: Control = hud.get("_top_left") as Control
	if tl and tl.is_visible_in_tree():
		for c: Control in UIAudit.content_of([tl]):
			others["the cube counter"] = UIAudit.rect_of(c) if not others.has("the cube counter") else (others["the cube counter"] as Rect2).merge(UIAudit.rect_of(c))
	if DevHooks.has("ui-audit-verbose"):
		print("[ui-audit] arrival %s title %s %s" % [cfg, _r(tr_), ", ".join(PackedStringArray(others.keys().map(func(k: String) -> String: return "%s %s" % [k, _r(others[k])])))])
	for k: String in others:
		var x: Rect2 = tr_.intersection(others[k])
		if minf(x.size.x, x.size.y) >= UIAudit.OVERLAP_MIN:
			_report(cfg, "overlap", "arrival title with " + k, "title %s other %s" % [_r(tr_), _r(others[k])])


func _tab_buttons_of(up: Node) -> Array:
	var out: Array = []
	var d: Variant = up.get("_tab_btns")
	if d is Dictionary:
		out.append_array((d as Dictionary).values())
	return out


## The prompts that sit over the hotbar (wake a far hub's landmark, the planet's BASES line) must
## fit the screen in every language.
func _check_prompts(cfg: String, hud: Node) -> void:
	var view: Rect2 = get_viewport().get_visible_rect()
	var prompt: Label = hud.get("_prompt") as Label
	var texts: Array[String] = []
	var sites: Node = so.get("sites")
	var hp: Object = sites.get("purpose") if sites else null
	if hp:
		var site0: int = int(hp.get("site"))
		for i: int in range(1, HubPlan.main_total(str(hp.get("planet"))) + 1):
			hp.set("site", i)
			var p: String = str(hp.call("landmark_prompt"))
			if p != "":
				texts.append(p)
			texts.append(tr("E   Wake the %s  (%s)") % [HubPlan.landmark_name(str(hp.get("planet")), i), Outposts.cost_text(HubPlan.wake_cost(str(hp.get("planet"))))])
		hp.set("site", site0)
	if prompt:
		var font: Font = prompt.get_theme_font("font")
		var fs: int = prompt.get_theme_font_size("font_size")
		for t: String in texts:
			var wpx: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if wpx > view.size.x - 32.0:
				_report(cfg, "offscreen", "prompt", "\"%s\" wants %d px, screen %d" % [t.left(48), roundi(wpx), roundi(view.size.x)])
	var pl: Label = hud.get("_planet_label") as Label
	if pl and pl.is_visible_in_tree():
		var why: String = UIAudit.label_clipped(pl)
		var r: Rect2 = UIAudit.rect_of(pl)
		if why != "" or not view.grow(1.5).encloses(r):
			_report(cfg, "clipped", "planet line", "\"%s\" %s" % [pl.text, why if why != "" else _r(r)])


# --- Gamepad pass -------------------------------------------------------------------------
# [v6screens] Each screen driven by controller buttons only (real InputEventJoypadButton events,
# through the game's own input map): the focus is on a shown control of the screen when it opens
# and after every d-pad press, and B closes it (Settings: back to the menu it came from).

func _press(btn: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.device = 0
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var r := InputEventJoypadButton.new()
	r.button_index = btn
	r.device = 0
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(2)


func _pad_focus_ok(cfg: String, roots: Array, when: String) -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	var ok: bool = f != null and f.is_visible_in_tree()
	if ok:
		ok = false
		for r: Variant in roots:
			if r != null and is_instance_valid(r) and (r as Node).is_ancestor_of(f):
				ok = true
	if not ok:
		_report(cfg, "pad", "focus lost " + when, "focus on %s" % (UIAudit.short_path(f) if f else "nothing"))
	return ok


## Walks the screen with the d-pad (down, then up) and reports where the focus gets lost.
func _pad_walk(cfg: String, roots: Array, downs: int = 14) -> int:
	if UIAudit.focusables(roots).is_empty():
		return 0  # nothing to focus (a page to read): B must still close it
	if not _pad_focus_ok(cfg, roots, "when it opens"):
		return 0
	var seen: Dictionary = {}
	for i: int in downs:
		await _press(JOY_BUTTON_DPAD_DOWN)
		if not _pad_focus_ok(cfg, roots, "after d-pad down x%d" % (i + 1)):
			return seen.size()
		seen[get_viewport().gui_get_focus_owner()] = true
	for i: int in 3:
		await _press(JOY_BUTTON_DPAD_UP)
		if not _pad_focus_ok(cfg, roots, "after d-pad up x%d" % (i + 1)):
			break
	return seen.size()


func _pad_pass() -> void:
	var w: Node = so.get("w")
	var cfg: String = "pad en 1280x720@1.00"
	get_tree().root.size = Vector2i(1280, 720)
	Settings.ui_scale = 1.0
	Settings.apply_ui_scale()
	# Pause, then Settings from it.
	var pm: PauseMenu = w.get("pause_menu") as PauseMenu
	if pm:
		await _press(JOY_BUTTON_START)
		await _wait_s(0.4)
		if not pm.is_open:
			_report(cfg, "pad", "Start does not open the pause menu", "")
			pm.open_menu()
			await _wait_s(0.4)
		var n: int = await _pad_walk(cfg + " pause", [pm])
		print("[ui-audit] pad pause: %d controls reached" % n)
		var sp: SettingsPanel = pm.get("_settings")
		pm.call("_open_settings")
		await _wait_s(0.4)
		n = await _pad_walk(cfg + " settings", [sp], 10)
		print("[ui-audit] pad settings: %d controls reached" % n)
		await _press(JOY_BUTTON_B)
		await _wait_s(0.3)
		if sp.is_open:
			_report(cfg + " settings", "pad", "B does not close Settings", "")
		elif pm.is_open:
			_pad_focus_ok(cfg + " settings", [pm], "back on the pause menu")
		await _press(JOY_BUTTON_B)
		await _wait_s(0.4)
		if pm.is_open:
			_report(cfg + " pause", "pad", "B does not close the pause menu", "")
			pm.close_menu()
		get_tree().paused = false
		await _frames(4)
	var up: UpgradesScreen = w.get("upgrades") as UpgradesScreen
	if up:
		up.open_screen()
		await _wait_s(0.6)
		var n2: int = await _pad_walk(cfg + " workbench", [up])
		print("[ui-audit] pad workbench: %d controls reached" % n2)
		await _press(JOY_BUTTON_RIGHT_SHOULDER)
		await _wait_s(0.3)
		_pad_focus_ok(cfg + " workbench", [up], "after RB (next tab)")
		await _press(JOY_BUTTON_B)
		await _wait_s(0.5)
		if up.is_open:
			_report(cfg + " workbench", "pad", "B does not close the workbench", "")
			up.close_screen()
		get_tree().paused = false
		await _frames(4)
	var cl: CanvasLayer = LockerPanel.open_overlay(w)
	await _wait_s(0.6)
	var n3: int = await _pad_walk(cfg + " locker", [cl], 6)
	print("[ui-audit] pad locker: %d controls reached" % n3)
	await _press(JOY_BUTTON_B)
	await _wait_s(0.6)
	if is_instance_valid(cl) and not cl.has_meta("closing") and cl.is_inside_tree():
		_report(cfg + " locker", "pad", "B does not close the locker", "")
		cl.queue_free()
	get_tree().paused = false
	await _frames(4)
	var layers: Node = so.get("layers")
	var gv: GlobeView = layers.get("survey") as GlobeView if layers else null
	if gv:
		await _press(JOY_BUTTON_BACK)
		await _wait_s(0.8)
		if not gv.is_open:
			_report(cfg + " survey", "pad", "View does not open the survey map", "")
			gv.open_view()
			await _wait_s(0.8)
		await _press(JOY_BUTTON_B)
		await _wait_s(0.6)
		if gv.is_open:
			_report(cfg + " survey", "pad", "B does not close the survey map", "")
			gv.close_view()
			await _wait_s(0.5)
		else:
			print("[ui-audit] pad survey: View opens it, B closes it")
		so.call("set_input", true)
		get_tree().paused = false
	for e: Dictionary in _extra_screens():
		await (e["open"] as Callable).call()
		await _wait_s(0.6)
		var nm: String = cfg + " " + str(e["name"])
		var n4: int = await _pad_walk(nm, [(e["root"] as Callable).call()], 8)
		print("[ui-audit] pad %s: %d controls reached" % [e["name"], n4])
		await _press(JOY_BUTTON_B)
		await _wait_s(0.6)
		if bool((e["is_open"] as Callable).call()):
			_report(nm, "pad", "B does not close the " + str(e["name"]), "")
			await (e["close"] as Callable).call()
			await _wait_s(0.4)
		get_tree().paused = false
		await _frames(4)


func _pad_title(mm: Node) -> void:
	var cfg: String = "pad en 1280x720@1.00 title"
	get_tree().root.size = Vector2i(1280, 720)
	Settings.ui_scale = 1.0
	Settings.apply_ui_scale()
	await _frames(4)
	var ui: Control = mm.get("_ui") as Control
	var n: int = await _pad_walk(cfg, [ui], 6)
	print("[ui-audit] pad title: %d controls reached" % n)
	mm.call("_open_settings")
	await _wait_s(0.4)
	var sp: SettingsPanel = mm.get("_settings")
	await _pad_walk(cfg + " settings", [sp], 8)
	await _press(JOY_BUTTON_B)
	await _wait_s(0.4)
	if sp.is_open:
		_report(cfg + " settings", "pad", "B does not close Settings", "")
		sp.close_panel()
	else:
		_pad_focus_ok(cfg, [ui], "back on the title menu")


# --- Title screen ------------------------------------------------------------------------

func _run_title() -> void:
	# [v8ui] Owner item 76: the audit used whatever save was on disk (or none, so no Continue button
	# at all), and a short line fit. Audit the title with the longest Continue line instead
	# ("Verdance · 12h 51m · 999.99K cubes · 28 Nov 19:30"); --ui-audit-real-save keeps the real one.
	if not DevHooks.has("ui-audit-real-save"):
		DevHooks.args["menu-long-save"] = "1"
	for loc: Variant in _list("ui-audit-locales", LOCALES):
		_set_locale(str(loc))
		get_tree().reload_current_scene()
		await _wait_s(1.5)
		var mm: Node = get_tree().current_scene
		if mm == null:
			_report("title " + str(loc), "missing", "title", "no scene")
			continue
		var ui: Control = mm.get("_ui") as Control
		if _want("title"):
			await _each_size("title", func(cfg: String) -> void: _audit(cfg, "title", [ui]))
		if _want("title_settings"):
			mm.call("_open_settings")
			await _wait_s(0.4)
			var sp: SettingsPanel = mm.get("_settings")
			for i: int in SettingsPanel.TABS.size():
				sp.select_tab(i)
				var tabs: Array = sp.get("_tab_buttons")
				if i > 0:
					(tabs[i] as Control).grab_focus()  # as "More settings" and the bumpers do
				await _wait_s(0.1)
				await _each_size("title_settings/" + SettingsPanel.TABS[i], func(cfg: String) -> void: _audit(cfg, "settings", [sp], true, tabs))
			sp.close_panel()
	if _want("pad"):
		_set_locale("en")
		get_tree().reload_current_scene()
		await _wait_s(1.5)
		await _pad_title(get_tree().current_scene)
