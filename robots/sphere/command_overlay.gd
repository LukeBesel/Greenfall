class_name CommandOverlay
extends Control
## [orbC] What Command view draws over the globe, kept readable with hundreds of robots:
## - robots as small role-coloured pips (bright working, dim idle, red ring stuck). Pips that
##   would overlap merge into one cluster disc with a count, in the colour of its biggest role;
## - the painted zone of the selected role as small dots on its hexes;
## - one label at the top: the role being painted and the keys.
## Robots behind the planet's horizon are not drawn. Everything is drawn in one _draw pass.

const ROLE_COL: Dictionary = {
	"clean": Color(1.0, 0.72, 0.3), "haul": Color(0.45, 0.72, 1.0), "plant": Color(0.55, 0.9, 0.5),
	"water": Color(0.4, 0.9, 0.95), "skim": Color(0.35, 0.85, 0.75),
}
const CLUSTER_PX: float = 26.0
const PIP_R: float = 5.0

var cmd: SphereCommand
var _font: Font
var _label: Label
var stats: Dictionary = {}  # pips / clusters drawn last frame (tests, dev)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_label = UITheme.label("", 18, UITheme.CREAM)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-260, 18)
	_label.custom_minimum_size = Vector2(520, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _process(_d: float) -> void:
	var on: bool = cmd != null and cmd.is_active()
	visible = on
	if on:
		_label.text = "%s  ·  %s" % [(tr("%s zone") % tr(cmd.role.capitalize())).to_upper(), tr("Tab: role · Left: paint · Right: erase · Middle: send a robot · E: back to Lumi")]
		queue_redraw()


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


func _draw() -> void:
	if cmd == null or cmd.cam == null or cmd.cam.camera == null or cmd.crew == null:
		return
	var cam: Camera3D = cmd.cam.camera
	var crew: SphereCrew = cmd.crew
	var surf: SphereSurface = cmd.surface
	# Painted zone of the selected role.
	var zone: Dictionary = crew.zones.get(cmd.role, {})
	var zc: Color = ROLE_COL.get(cmd.role, Color.WHITE)
	for c: int in zone:
		var sp: Variant = screen_of(cam, surf, surf.ground(cmd.grid.centers[c]))
		if sp != null:
			draw_circle(sp, 3.0, Color(zc, 0.55))
	# Robots: 0 working, 1 idle, 2 stuck.
	var pts: Array = []
	for u: Dictionary in crew.robots():
		var p: Vector3 = (u["bot"] as SphereBot).global_position if u["bot"] != null else surf.ground(crew.unit_dir(u))
		var sp: Variant = screen_of(cam, surf, p + surf.up_at(p) * 0.8)
		if sp == null:
			continue
		var state: int = 2 if crew.is_stuck(u) else (1 if str(u["mode"]) == "idle" else 0)
		pts.append({"pos": sp, "role": str(u["role"]), "state": state})
	var groups: Array = cluster(pts, CLUSTER_PX)
	var nclusters: int = 0
	for cl: Dictionary in groups:
		var best: String = "clean"
		var bn: int = -1
		for r: String in cl["roles"]:
			if int(cl["roles"][r]) > bn:
				bn = int(cl["roles"][r])
				best = r
		var col: Color = ROLE_COL.get(best, Color.WHITE)
		var pos: Vector2 = cl["pos"]
		if int(cl["n"]) == 1:
			var dim: float = 0.55 if int(cl["worst"]) == 1 else 1.0
			draw_circle(pos, PIP_R + 1.5, Color(0, 0, 0, 0.55))
			draw_circle(pos, PIP_R, Color(col.r * dim, col.g * dim, col.b * dim, 0.95))
		else:
			nclusters += 1
			var r: float = clampf(8.0 + sqrt(float(cl["n"])) * 2.2, 9.0, 22.0)
			draw_circle(pos, r + 1.5, Color(0, 0, 0, 0.55))
			draw_circle(pos, r, Color(col, 0.88))
			var txt: String = str(int(cl["n"]))
			var fs: int = 13 if r < 14.0 else 15
			var tw: Vector2 = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(_font, pos + Vector2(-tw.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.06, 0.07))
		if int(cl["worst"]) == 2:
			draw_arc(pos, PIP_R + 4.0 if int(cl["n"]) == 1 else 24.0, 0.0, TAU, 24, Color(1.0, 0.35, 0.3), 2.0)
	stats = {"robots": pts.size(), "marks": groups.size(), "clusters": nclusters}
