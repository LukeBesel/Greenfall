class_name UIAuditRun
extends Node
## [v6screens] Dev: `--orbit --no-intro --ui-audit`. Lays the round game's 2D screens out at the
## sizes and interface scales players use and reports what is off-screen, cut, overlapping or
## covering Lumi, by numbers (headless; no render). See docs/QA_VERDANCE.md.
##   --ui-audit-sizes=1280x720,1920x1080   (default: SIZES)
##   --ui-audit-scales=0.8,1,1.5           (default: SCALES)
## Prints `[ui-audit]` lines, then `[ui-audit] done: N issues` and quits (exit 1 on issues).
##
## Play pass: a long WREN line on the subtitle bar at the default camera, with the goal stack as
## it is and expanded. The bar must not touch Lumi's body (LumiScreen) or the goal stack, and where
## it covers the hotbar the hotbar must be dimmed.

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1280, 800)]
const SCALES: Array[float] = [0.8, 1.0, 1.25, 1.5]
## A long line, about the longest chunk the bar shows (Subtitles.MAX_CHARS).
const LONG_LINE: String = "Bring every cube you scoop to the bench by the pod, and we can fix the old beacon"

var so: Node  # SliceOrbit
var issues: int = 0


static func attach(p_so: Node) -> UIAuditRun:
	var r := UIAuditRun.new()
	r.name = "UIAuditRun"
	r.so = p_so
	p_so.add_child(r)
	return r


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func sizes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s: String = DevHooks.get_s("ui-audit-sizes", "")
	if s == "":
		return SIZES
	for p: String in s.split(","):
		var xy: PackedStringArray = p.split("x")
		if xy.size() == 2:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	return out


func scales() -> Array[float]:
	var out: Array[float] = []
	var s: String = DevHooks.get_s("ui-audit-scales", "")
	if s == "":
		return SCALES
	for p: String in s.split(","):
		out.append(float(p))
	return out


func _run() -> void:
	await _frames(int(DevHooks.get_f("ui-audit-wait", 120.0)))
	var root: Window = get_tree().root
	var size0: Vector2i = root.size
	var scale0: float = Settings.ui_scale
	for sz: Vector2i in sizes():
		for sc: float in scales():
			root.size = sz
			Settings.ui_scale = sc
			Settings.apply_ui_scale()
			await _frames(3)
			await _play_pass("%dx%d@%.2f" % [sz.x, sz.y, sc])
	root.size = size0
	Settings.ui_scale = scale0
	Settings.apply_ui_scale()
	print("[ui-audit] done: %d issues" % issues)
	if not DevHooks.has("ui-audit-stay"):
		get_tree().quit(1 if issues > 0 else 0)


func _report(cfg: String, kind: String, what: String, note: String) -> void:
	issues += 1
	print("[ui-audit] %s play %s %s  %s" % [kind.to_upper(), cfg, what, note])


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
