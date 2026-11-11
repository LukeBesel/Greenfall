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

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1280, 800)]
const SCALES: Array[float] = [0.8, 1.0, 1.25, 1.5]
const LOCALES: Array[String] = ["en", "de", "fr", "es", "pt_BR", "zh_CN", "ja", "pseudo"]
const SCREENS: Array[String] = ["play", "hud", "prompts", "pause", "settings", "workbench", "locker", "survey", "loading"]
const TITLE_SCREENS: Array[String] = ["title", "title_settings"]
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
	if _want("loading"):
		var ld: CanvasLayer = get_tree().root.get_node_or_null("Loader") as CanvasLayer
		if ld:
			ld.visible = true
			for stage: int in 4:
				(ld.get("_status") as Label).text = ld.call("_status_text", stage)
				await _each_size("loading/%d" % stage, func(cfg: String) -> void: _audit(cfg, "loading", [ld], false))
			ld.visible = false


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


# --- Title screen ------------------------------------------------------------------------

func _run_title() -> void:
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
