class_name CommandOverlay
extends Control
## [orbC] What Command view draws over the globe, kept readable with hundreds of robots.
## [v6crew] Made simple enough for a young kid, mouse or controller:
## - every painted zone as filled hexes in its job's colour (the job being painted is brighter),
##   and the hex under the cursor outlined;
## - robots as job-coloured pips: bright with a ring while working, grey when resting, amber
##   with a "!" when one needs the player. Pips that would overlap merge into a counted cluster;
## - a card on the left: the crew of the hub in view and its effect ("3 robots, about 55 hexes an
##   hour"), the colour legend with what each job's robots are doing, and how to paint;
## - one line at the top for the guided first zone, and the robot under the cursor says what it
##   is doing (CrewTalk.look_text).
## Robots behind the planet's horizon are not drawn. Everything is drawn in one _draw pass.

const ROLE_COL: Dictionary = BotBadge.ROLE_COL
# l10n:begin
const ROLE_NAME: Dictionary = {"clean": "Cleaners", "haul": "Haulers", "plant": "Planters", "water": "Waterers", "skim": "Skimmers"}
const PAINT_WHAT: Dictionary = {"clean": "Paint the ground you want cleaned first.", "plant": "Paint where to plant.",
	"water": "Paint where to water.", "skim": "Paint the water to skim first."}
# l10n:end
const LEGEND_ORDER: Array[String] = ["clean", "haul", "plant", "water", "skim"]
const CLUSTER_PX: float = 26.0
const PIP_R: float = 6.0

var cmd: SphereCommand
var _font: Font
var _box: StyleBoxFlat
var stats: Dictionary = {}  # pips / clusters drawn last frame (tests, dev)
## [v6screens] The boxes drawn last frame, {name, rect, text_w}, so the layout audit
## (tools/ui_audit_run.gd) can check them like Controls: on screen, clear of the HUD and each other.
var panels: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # [v6screens] was set_anchors_preset: it kept a small size, so the top hints sat off the left edge
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.055, 0.06, 0.07, 0.86)
	_box.set_corner_radius_all(10)
	_box.border_color = Color(1, 1, 1, 0.14)
	_box.set_border_width_all(1)


## Screen position of a world point if the camera sees it (in front, above the horizon), else null.
static func screen_of(cam: Camera3D, surface: SphereSurface, p: Vector3) -> Variant:
	var c: Vector3 = cam.global_position
	if (p - c).dot(-cam.global_basis.z) <= 0.0:
		return null
	var cr: float = (c - surface.center).length()
	var dir_p: Vector3 = (p - surface.center).normalized()
	var dir_c: Vector3 = (c - surface.center).normalized()
	if dir_p.dot(dir_c) < surface.radius / maxf(cr, surface.radius + 0.01) - 0.002:
		return null  # past the horizon
	return cam.unproject_position(p)


## Pips -> clusters on a screen grid. Returns [{pos, n, role_counts, worst}] (tests use it).
static func cluster(points: Array, cell_px: float) -> Array:
	var cells: Dictionary = {}
	for pt: Dictionary in points:
		var sp: Vector2 = pt["pos"]
		var k := Vector2i(floori(sp.x / cell_px), floori(sp.y / cell_px))
		if not cells.has(k):
			cells[k] = {"pos": Vector2.ZERO, "n": 0, "roles": {}, "worst": 0}
		var cl: Dictionary = cells[k]
		cl["pos"] = (cl["pos"] as Vector2) + sp
		cl["n"] = int(cl["n"]) + 1
		(cl["roles"] as Dictionary)[pt["role"]] = int((cl["roles"] as Dictionary).get(pt["role"], 0)) + 1
		cl["worst"] = maxi(int(cl["worst"]), int(pt["state"]))
	var out: Array = []
	for k: Vector2i in cells:
		var cl: Dictionary = cells[k]
		cl["pos"] = (cl["pos"] as Vector2) / float(cl["n"])
		out.append(cl)
	return out


func _process(_d: float) -> void:
	var on: bool = cmd != null and cmd.is_active()
	visible = on
	if on:
		queue_redraw()


## The key or button that opens and closes this view, as text ("B").
static func back_key(pad: bool) -> String:
	for ev: InputEvent in InputMap.action_get_events("open_command") if InputMap.has_action("open_command") else []:
		if pad and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
			return PadGlyphs.event_name(ev)
		if not pad and ev is InputEventKey:
			var k: InputEventKey = ev
			return OS.get_keycode_string(k.physical_keycode if k.keycode == 0 else k.keycode)
	return "B"


## The card's lines for the hub in view: [{text, col, size, dot?}] (tests read it too).
static func card_lines(p_cmd: SphereCommand) -> Array:
	var crew: SphereCrew = p_cmd.crew
	var hub: int = p_cmd.view_hub()
	var sum: Dictionary = CrewTalk.hub_summary(crew, hub)
	var out: Array = [{"text": TranslationServer.translate("ROBOT COMMAND"), "col": UITheme.MUTED, "size": 14}]
	var n: int = int(sum["robots"])
	if n == 0:
		out.append({"text": TranslationServer.translate("No robots here yet."), "col": UITheme.CREAM, "size": 20})
		out.append({"text": TranslationServer.translate("Build one at the workbench."), "col": UITheme.MUTED, "size": 16})
		out.append_array(other_bases(crew, hub))
		return out
	out.append({"text": TranslationServer.translate_plural("%d robot", "%d robots", n) % n, "col": UITheme.CREAM, "size": 22})
	if float(sum["hexes_per_hour"]) >= 1.0:
		out.append({"text": TranslationServer.translate("About %d hexes an hour") % roundi(float(sum["hexes_per_hour"])), "col": UITheme.GREEN, "size": 18})
	# Legend: one row per job the hub has robots for, with what they are doing.
	var by: Dictionary = {}
	for u: Dictionary in crew.hub_robots(hub):
		var r: String = str(u["role"])
		if not by.has(r):
			by[r] = [0, 0]
		var st: int = CrewTalk.state(crew, u)
		by[r][0 if st != CrewTalk.IDLE and st != CrewTalk.HELP else 1] += 1
	for r: String in LEGEND_ORDER:
		if not by.has(r):
			continue
		var w: int = int(by[r][0])
		var idle: int = int(by[r][1])
		var what: String = TranslationServer.translate("%d working") % w
		if idle > 0 and w > 0:
			what = TranslationServer.translate("%d working, %d waiting") % [w, idle]
		elif idle > 0:
			what = TranslationServer.translate("%d waiting") % idle
		out.append({"text": "%s: %s" % [TranslationServer.translate(str(ROLE_NAME[r])), what], "col": UITheme.CREAM, "size": 16,
			"dot": ROLE_COL[r], "sel": r == p_cmd.role and p_cmd.roles().size() > 1})
	if bool(sum["needs_hauler"]):
		out.append({"text": TranslationServer.translate("Bales are piling up. Build a Haul Bug."), "col": BotBadge.AMBER, "size": 16})
	out.append_array(other_bases(crew, hub))
	return out


## [v6crew] The other bases with robots, one short row each, so one glance shows the whole crew:
## a header and up to MAX_OTHER rows "Maple Yard: 3 robots, 2 working" (most robots first).
const MAX_OTHER: int = 5


static func other_bases(crew: SphereCrew, here: int) -> Array:
	var rows: Array = []
	for i: int in crew.hubs.size():
		var h: int = crew.hubs[i]
		if h == here:
			continue
		var sum: Dictionary = CrewTalk.hub_summary(crew, h)
		if int(sum["robots"]) > 0:
			rows.append({"i": i, "n": int(sum["robots"]), "w": int(sum["working"])})
	if rows.is_empty():
		return []
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"]))
	var out: Array = [{"text": TranslationServer.translate("OTHER BASES"), "col": UITheme.MUTED, "size": 14}]
	for r: Dictionary in rows.slice(0, MAX_OTHER):
		var nm: String = HubPlan.hub_name(crew.planet_id, int(r["i"]))
		if nm == "":
			nm = TranslationServer.translate("Base %d") % (int(r["i"]) + 1)
		var n: int = int(r["n"])
		out.append({"text": "%s: %s, %s" % [nm, TranslationServer.translate_plural("%d robot", "%d robots", n) % n,
			TranslationServer.translate("%d working") % int(r["w"])], "col": UITheme.CREAM, "size": 15})
	return out


## How to paint, for the device in use: [what, how].
static func hint_lines(p_cmd: SphereCommand) -> Array:
	var pad: bool = p_cmd.using_pad
	var what: String = TranslationServer.translate(str(PAINT_WHAT.get(p_cmd.role, PAINT_WHAT["clean"])))
	if p_cmd.painted_now > 0:
		what = TranslationServer.translate("Good! Your robots will work here first.")
	var how: String = TranslationServer.translate("Hold A: paint   Hold X: erase   %s: back") % back_key(true) if pad \
		else TranslationServer.translate("Left mouse: paint   Right mouse: erase   %s: back") % back_key(false)
	if p_cmd.roles().size() > 1:
		how += "   " + (TranslationServer.translate("Y: next job") if pad else TranslationServer.translate("Tab: next job"))
	return [what, how]


func _text(pos: Vector2, text: String, fs: int, col: Color, centred: bool = false) -> float:
	var tw: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at: Vector2 = pos - Vector2(tw.x * 0.5, 0) if centred else pos
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.03, 0.03, 0.04, 0.85))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return tw.x


func _hex(cam: Camera3D, surf: SphereSurface, c: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for d: Vector3 in cmd.grid.corners(c):
		var sp: Variant = screen_of(cam, surf, surf.ground(d))
		if sp == null:
			return PackedVector2Array()
		out.append(sp)
	return out


func _draw() -> void:
	if cmd == null or cmd.cam == null or cmd.cam.camera == null or cmd.crew == null:
		return
	if _font == null:
		_font = get_theme_default_font()
	var cam: Camera3D = cmd.cam.camera
	var crew: SphereCrew = cmd.crew
	panels.clear()  # [v6screens]
	var surf: SphereSurface = cmd.surface
	# Painted zones, every job: filled hexes (the job being painted on top and brighter).
	var drawn: int = 0
	var order: Array = crew.zones.keys()
	order.erase(cmd.role)
	order.append(cmd.role)
	for r: Variant in order:
		var zone: Dictionary = crew.zones.get(r, {})
		var zc: Color = ROLE_COL.get(str(r), Color.WHITE)
		var sel: bool = str(r) == cmd.role
		for c: int in zone:
			if drawn > 900:
				break
			var poly: PackedVector2Array = _hex(cam, surf, c)
			if poly.size() < 3 or not Rect2(Vector2(-80, -80), size + Vector2(160, 160)).has_point(poly[0]):
				continue
			drawn += 1
			draw_colored_polygon(poly, Color(zc, 0.34 if sel else 0.16))
			poly.append(poly[0])
			draw_polyline(poly, Color(zc, 0.9 if sel else 0.45), 2.0 if sel else 1.2, true)
	var zcol: Color = ROLE_COL.get(cmd.role, Color.WHITE)
	if cmd.hover_cell >= 0:  # the hex under the cursor
		var hp: PackedVector2Array = _hex(cam, surf, cmd.hover_cell)
		if hp.size() >= 3:
			# [v6crew] an unpainted hex under the cursor shows what a click does: it fills in the job's colour
			if not (crew.zones.get(cmd.role, {}) as Dictionary).has(cmd.hover_cell):
				var pulse_h: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
				draw_colored_polygon(hp, Color(zcol, 0.14 + 0.12 * pulse_h))
			hp.append(hp[0])
			draw_polyline(hp, Color(1, 1, 1, 0.95), 3.0, true)
			draw_polyline(hp, Color(zcol, 0.95), 1.5, true)
	if cmd.using_pad:  # [v3qa] the pad's cursor: a reticle at the screen centre
		var mid: Vector2 = size * 0.5
		draw_arc(mid, 14.0, 0.0, TAU, 32, Color(zcol, 0.9), 2.5)
		draw_line(mid - Vector2(22, 0), mid - Vector2(8, 0), Color(zcol, 0.9), 2.0)
		draw_line(mid + Vector2(8, 0), mid + Vector2(22, 0), Color(zcol, 0.9), 2.0)
	# Bales waiting for a Haul Bug: small squares.
	var nb: int = 0
	for b: Dictionary in crew.bales:
		if nb > 250:
			break
		var bd: Vector3 = b.get("dir", cmd.grid.centers[int(b["cell"])])
		var bs: Variant = screen_of(cam, surf, surf.ground(bd))
		if bs != null:
			nb += 1
			draw_rect(Rect2((bs as Vector2) - Vector2(3, 3), Vector2(6, 6)), Color(0.86, 0.8, 0.66, 0.9))
			draw_rect(Rect2((bs as Vector2) - Vector2(3, 3), Vector2(6, 6)), Color(0.1, 0.09, 0.08, 0.9), false, 1.0)
	# Robots: 0 working, 1 resting, 2 needs help / stuck.
	var pts: Array = []
	for u: Dictionary in crew.robots():
		var p: Vector3 = (u["bot"] as SphereBot).global_position if u["bot"] != null else surf.ground(crew.unit_dir(u))
		var sp: Variant = screen_of(cam, surf, p + surf.up_at(p) * 0.8)
		if sp == null:
			continue
		var st: int = CrewTalk.state(crew, u)
		var state: int = 2 if crew.is_stuck(u) or st == CrewTalk.HELP else (1 if st == CrewTalk.IDLE else 0)
		pts.append({"pos": sp, "role": str(u["role"]), "state": state})
	var groups: Array = cluster(pts, CLUSTER_PX)
	var nclusters: int = 0
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	for cl: Dictionary in groups:
		var best: String = "clean"
		var bn: int = -1
		for r: String in cl["roles"]:
			if int(cl["roles"][r]) > bn:
				bn = int(cl["roles"][r])
				best = r
		var col: Color = ROLE_COL.get(best, Color.WHITE)
		var pos: Vector2 = cl["pos"]
		var worst: int = int(cl["worst"])
		if int(cl["n"]) == 1:
			draw_circle(pos, PIP_R + 2.0, Color(0, 0, 0, 0.6))
			draw_circle(pos, PIP_R, BotBadge.GREY if worst == 1 else col)
			if worst == 0:
				draw_arc(pos, PIP_R + 3.0 + pulse * 2.5, 0.0, TAU, 20, Color(col, 0.75 - pulse * 0.4), 1.6, true)
			elif worst == 1:
				draw_circle(pos, PIP_R * 0.45, col)
		else:
			nclusters += 1
			var r: float = clampf(8.0 + sqrt(float(cl["n"])) * 2.2, 9.0, 22.0)
			draw_circle(pos, r + 1.5, Color(0, 0, 0, 0.55))
			draw_circle(pos, r, Color(col, 0.88))
			var txt: String = str(int(cl["n"]))
			var fs: int = 13 if r < 14.0 else 15
			var tw: Vector2 = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(_font, pos + Vector2(-tw.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.06, 0.07))
		if worst == 2:
			var rr: float = PIP_R + 4.0 if int(cl["n"]) == 1 else 24.0
			draw_arc(pos, rr, 0.0, TAU, 24, BotBadge.AMBER, 2.2, true)
			_text(pos + Vector2(0, -rr - 3.0), "!", 18, BotBadge.AMBER, true)
	stats = {"robots": pts.size(), "marks": groups.size(), "clusters": nclusters, "zone_hexes": drawn}
	# The robot under the cursor says what it is doing.
	if not cmd.hover_unit.is_empty():
		var hu: Dictionary = cmd.hover_unit
		var hp3: Vector3 = surf.ground(crew.unit_dir(hu))
		var hs: Variant = screen_of(cam, surf, hp3 + surf.up_at(hp3) * 0.8)
		if hs != null:
			var line: String = CrewTalk.look_text(crew, hu)
			var w: float = _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var at: Vector2 = (hs as Vector2) + Vector2(14, -14)
			at.x = clampf(at.x, 8.0, maxf(8.0, size.x - w - 20.0))
			draw_style_box(_box, Rect2(at + Vector2(-8, -19), Vector2(w + 16, 28)))
			panels.append({"name": "look", "rect": Rect2(at + Vector2(-8, -19), Vector2(w + 16, 28)), "text_w": w})  # [v6screens]
			draw_string(_font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.CREAM)
	# The card (left, under the cube counter) and the paint hints (top centre, clear of the HUD).
	var lines: Array = card_lines(cmd)
	var cw: float = 0.0
	var ch: float = 14.0
	for l: Dictionary in lines:
		cw = maxf(cw, _font.get_string_size(str(l["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l["size"])).x + (22.0 if l.has("dot") else 0.0))
		ch += float(l["size"]) + 9.0
	var origin := Vector2(22, 96)
	draw_style_box(_box, Rect2(origin, Vector2(cw + 32.0, ch)))
	panels.append({"name": "card", "rect": Rect2(origin, Vector2(cw + 32.0, ch)), "text_w": cw})  # [v6screens]
	var y: float = origin.y + 10.0
	for l: Dictionary in lines:
		var fs2: int = int(l["size"])
		y += fs2 + 2.0
		var x: float = origin.x + 16.0
		if l.has("dot"):
			if bool(l.get("sel", false)):
				draw_circle(Vector2(x + 6.0, y - fs2 * 0.33), 9.0, Color(1, 1, 1, 0.9))
			draw_circle(Vector2(x + 6.0, y - fs2 * 0.33), 6.5, l["dot"])
			x += 22.0
		draw_string(_font, Vector2(x, y), str(l["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, l["col"])
		y += 7.0
	var hints: Array = hint_lines(cmd)
	var mid_x: float = size.x * 0.5
	var w0: float = _font.get_string_size(str(hints[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var w1: float = _font.get_string_size(str(hints[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var bw: float = maxf(w0, w1) + 36.0
	draw_style_box(_box, Rect2(Vector2(mid_x - bw * 0.5, 16), Vector2(bw, 62)))
	panels.append({"name": "hints", "rect": Rect2(Vector2(mid_x - bw * 0.5, 16), Vector2(bw, 62)), "text_w": maxf(w0, w1)})  # [v6screens]
	draw_circle(Vector2(mid_x - w0 * 0.5 - 4.0, 36), 7.0, zcol)
	draw_string(_font, Vector2(mid_x - w0 * 0.5 + 10.0, 43), str(hints[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UITheme.CREAM)
	draw_string(_font, Vector2(mid_x - w1 * 0.5, 67), str(hints[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.MUTED)
