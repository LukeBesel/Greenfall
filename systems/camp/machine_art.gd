class_name MachineArt
extends RefCounted
## [v6yard] The yard machines' models and their picture signs, on the art kit (YardArt.Kit over
## KitMesh.Builder; docs/ART_KIT.md). The owner's bar: a 5-year-old can tell what each machine does
## from its shape. So every machine has one big readable gesture (the press head over a cube-sized
## chamber, the belt running off a chunky motor, the wide hopper mouth) and a round picture sign:
## no words, one pictogram in low relief.
##
## Everything tunable is in data/machine_art.json (docs/ADJUSTING.md, "Yard machines"): which sign a
## machine carries, its size and colours, and each machine's paint.
##
##   put_sign(kit, id, pos, rot, two_sided)  the round sign of machine `id` (data: signs.<id>)
##   sign_post(id, height)               the same sign on its own post (a Kit; origin on the ground)
##   pod_service()                       the repair cart and cones by the crashed pod (story/crash_site.gd)
##   baler_body() / baler_platen() / baler_gate()    automation/auto_baler.gd
##   belt_pad() / belt_turntable() / belt_segment()  automation/conveyor.gd (the Belt Drive)

const DATA: String = "res://data/machine_art.json"
const SIGN_BASE: float = 0.72  # the size the pictograms are drawn at (metres across)

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(DATA)
	return _cfg


static func reload() -> void:
	_cfg = {}


## A colour from the data (a "#rrggbb" string), or `fallback`.
static func col(section: String, key: String, fallback: Color) -> Color:
	var s: Variant = cfg().get(section, {})
	var v: Variant = (s as Dictionary).get(key, null) if s is Dictionary else null
	if v is String and (v as String).is_valid_html_color():
		var c := Color.html(v as String)
		return Color(c.r, c.g, c.b, fallback.a)
	return fallback


static func num(section: String, key: String, fallback: float) -> float:
	var s: Variant = cfg().get(section, {})
	var v: Variant = (s as Dictionary).get(key, null) if s is Dictionary else null
	return float(v) if v is float or v is int else fallback


## The sign entry of machine `id`, over the shared defaults: {icon, size, rim, face, ink, accent, show}.
static func sign_def(id: String) -> Dictionary:
	var all: Variant = cfg().get("signs", {})
	var out: Dictionary = {"icon": id, "size": SIGN_BASE, "rim": "#f5801f", "face": "#ede3cc", "ink": "#2b3340", "accent": "#f5801f", "show": true}
	if all is Dictionary:
		var dflt: Variant = (all as Dictionary).get("defaults", {})
		if dflt is Dictionary:
			out.merge(dflt as Dictionary, true)
		var own: Variant = (all as Dictionary).get(id, {})
		if own is Dictionary:
			out.merge(own as Dictionary, true)
	return out


static func _hex(v: Variant, fallback: Color) -> Color:
	return Color.html(v as String) if v is String and (v as String).is_valid_html_color() else fallback


# --- Picture signs -----------------------------------------------------------------------------------

## The round picture sign of machine `id`, facing +Z after `rot` (degrees), centred on `pos`.
## two_sided: the picture on the back as well (signs on posts).
static func put_sign(k: YardArt.Kit, id: String, pos: Vector3, rot: Vector3 = Vector3.ZERO, two_sided: bool = false) -> void:
	var d: Dictionary = sign_def(id)
	if not bool(d.get("show", true)):
		return
	var size: float = float(d.get("size", SIGN_BASE))
	var u: float = size / SIGN_BASE
	var rim: Color = _hex(d.get("rim"), YardArt.ORANGE)
	var face: Color = _hex(d.get("face"), YardArt.CREAM)
	var ink: Color = _hex(d.get("ink"), YardArt.DARK)
	var accent: Color = _hex(d.get("accent"), rim)
	var r: float = size * 0.5
	k.push(ProcMesh.xf(pos, rot))
	k.cyl(r, 0.07, Vector3.ZERO, rim, Vector3(90, 0, 0), 0.02, 24)
	for i: int in 8:  # rim bolts
		var a: float = TAU * (i + 0.5) / 8.0
		k.bolt(Vector3(cos(a) * (r - 0.028 * u), sin(a) * (r - 0.028 * u), 0.035), Vector3.BACK, YardArt.STEEL, 0.012 * u)
	for side: int in (2 if two_sided else 1):
		k.push(Transform3D(Basis(Vector3.UP, PI * side), Vector3.ZERO))
		k.cyl(r - 0.055 * u, 0.02, Vector3(0, 0, 0.036), face, Vector3(90, 0, 0), 0.006, 24)
		_icon(k, str(d.get("icon", id)), u, ink, accent, face)
		k.pop()
	k.pop()


## The sign of machine `id` on its own post (origin on the ground, sign centre at `height`).
static func sign_post(id: String, height: float = 2.6) -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var d: Dictionary = sign_def(id)
	var r: float = float(d.get("size", SIGN_BASE)) * 0.5
	k.cyl(0.2, 0.1, Vector3(0, 0.05, 0), YardArt.DARK, Vector3.ZERO, 0.025, 8)
	k.cyl(0.14, 0.18, Vector3(0, 0.19, 0), YardArt.TEAL_D, Vector3.ZERO, 0.03, 8, "paint", 0.1)
	k.hazard(Vector3(0.13, 0.3, 0.13), Vector3(0, 0.45, 0))
	k.cyl(0.055, height - r - 0.2, Vector3(0, (height - r + 0.2) * 0.5, 0), YardArt.TEAL, Vector3.ZERO, 0.012, 10)
	k.cyl(0.075, 0.06, Vector3(0, height - r - 0.03, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.015, 10)
	put_sign(k, id, Vector3(0, height, 0), Vector3.ZERO, true)
	return k


## The sign of machine `id` on a short stalk (origin: the stalk's foot): for a bench top or a roof edge.
static func sign_stalk(id: String, stalk: float = 0.3) -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var r: float = float(sign_def(id).get("size", SIGN_BASE)) * 0.5
	for x: float in [-0.12, 0.12]:
		k.box(Vector3(0.05, stalk + 0.06, 0.05), Vector3(x, stalk * 0.5, 0), YardArt.TEAL, Vector3.ZERO, 0.012)
	k.box(Vector3(0.4, 0.05, 0.12), Vector3(0, 0.025, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	put_sign(k, id, Vector3(0, stalk + r, 0), Vector3.ZERO, true)
	return k


## A flat pictogram bar (w x h, centre x,y in the sign's plane; `layer` 1 lies over layer 0).
static func _bar(k: YardArt.Kit, u: float, w: float, h: float, x: float, y: float, c: Color, rz: float = 0.0, layer: int = 0) -> void:
	k.box(Vector3(w * u, h * u, 0.022), Vector3(x * u, y * u, 0.056 + layer * 0.012), c, Vector3(0, 0, rz), minf(0.006, minf(w, h) * u * 0.3))


static func _dot(k: YardArt.Kit, u: float, r: float, x: float, y: float, c: Color, layer: int = 0, segs: int = 16) -> void:
	k.cyl(r * u, 0.022, Vector3(x * u, y * u, 0.056 + layer * 0.012), c, Vector3(90, 0, 0), 0.005, segs)


static func _icon(k: YardArt.Kit, icon: String, u: float, ink: Color, accent: Color, face: Color) -> void:
	match icon:
		"wrench":  # the workbench: a spanner and a nut
			k.push(ProcMesh.xf(Vector3.ZERO, Vector3(0, 0, -38)))
			_bar(k, u, 0.075, 0.34, 0.0, -0.03, ink)
			_dot(k, u, 0.1, 0.0, 0.16, ink)
			_bar(k, u, 0.07, 0.13, 0.0, 0.225, face, 0.0, 1)
			_dot(k, u, 0.06, 0.0, -0.2, ink)
			_dot(k, u, 0.024, 0.0, -0.2, face, 1)
			k.pop()
			_dot(k, u, 0.065, -0.15, 0.13, accent, 0, 6)
			_dot(k, u, 0.026, -0.15, 0.13, face, 1, 12)
		"bin":  # the trash bin: an arrow down into a bin
			_bar(k, u, 0.27, 0.2, 0.0, -0.15, ink)
			_bar(k, u, 0.34, 0.05, 0.0, -0.02, ink)
			for x: float in [-0.065, 0.065]:
				_bar(k, u, 0.026, 0.13, x, -0.15, face, 0.0, 1)
			_bar(k, u, 0.07, 0.13, 0.0, 0.2, accent)
			_bar(k, u, 0.07, 0.16, -0.047, 0.1, accent, 45.0)
			_bar(k, u, 0.07, 0.16, 0.047, 0.1, accent, -45.0)
		"bale":  # the baler: a press head squeezing a strapped cube
			_bar(k, u, 0.25, 0.23, 0.0, -0.045, accent)
			for x: float in [-0.06, 0.06]:
				_bar(k, u, 0.03, 0.23, x, -0.045, ink, 0.0, 1)
			_bar(k, u, 0.36, 0.045, 0.0, -0.19, ink)
			_bar(k, u, 0.36, 0.05, 0.0, 0.105, ink)
			_bar(k, u, 0.075, 0.13, 0.0, 0.19, ink)
		"belt":  # the belt drive: a cube riding a belt on two wheels
			_bar(k, u, 0.34, 0.04, 0.0, -0.055, ink)
			_bar(k, u, 0.34, 0.04, 0.0, -0.185, ink)
			for x: float in [-0.16, 0.16]:
				_dot(k, u, 0.085, x, -0.12, ink)
				_dot(k, u, 0.03, x, -0.12, face, 1)
			_bar(k, u, 0.13, 0.13, -0.07, 0.035, accent)
			_bar(k, u, 0.17, 0.04, 0.09, 0.2, ink)
			_bar(k, u, 0.04, 0.1, 0.155, 0.225, ink, 45.0)
			_bar(k, u, 0.04, 0.1, 0.155, 0.175, ink, -45.0)
		"leaf":  # the composter: a sprout out of a heap of soil
			_bar(k, u, 0.34, 0.06, 0.0, -0.2, ink)
			_bar(k, u, 0.2, 0.05, 0.0, -0.155, ink)
			_bar(k, u, 0.04, 0.24, 0.0, -0.04, accent)
			for s: float in [-1.0, 1.0]:
				var up: float = 0.04 if s > 0.0 else 0.0
				_dot(k, u, 0.075, s * 0.07, 0.06 + up, accent)
				_dot(k, u, 0.058, s * 0.135, 0.115 + up, accent)
		"signal":  # the signal tower: a mast and its waves
			_bar(k, u, 0.045, 0.24, 0.0, -0.11, ink)
			_bar(k, u, 0.18, 0.045, 0.0, -0.215, ink)
			_dot(k, u, 0.045, 0.0, 0.04, accent)
			for rr: float in [0.115, 0.19]:
				for s: float in [-1.0, 1.0]:
					for j: int in 5:
						var a: float = deg_to_rad(-44.0 + j * 22.0)
						_bar(k, u, 0.034, rr * 0.42, s * cos(a) * rr, 0.04 + sin(a) * rr, accent, rad_to_deg(a) * s)
		"bot":  # the bot fabricator: a robot's head
			k.box(Vector3(0.32 * u, 0.24 * u, 0.022), Vector3(0, -0.04 * u, 0.056), ink, Vector3.ZERO, 0.03 * u)
			for s: float in [-1.0, 1.0]:
				_bar(k, u, 0.045, 0.11, s * 0.185, -0.04, ink)
				_dot(k, u, 0.042, s * 0.075, -0.015, accent, 1)
			_bar(k, u, 0.13, 0.028, 0.0, -0.105, face, 0.0, 1)
			_bar(k, u, 0.03, 0.09, 0.0, 0.125, ink)
			_dot(k, u, 0.034, 0.0, 0.19, accent)
		_:  # an arrow up: something happens here
			_bar(k, u, 0.07, 0.24, 0.0, -0.06, ink)
			_bar(k, u, 0.07, 0.17, -0.05, 0.1, ink, -45.0)
			_bar(k, u, 0.07, 0.17, 0.05, 0.1, ink, 45.0)


# --- Auto-baler (automation/auto_baler.gd) ------------------------------------------------------------

const BALER_HW: float = 0.58   # half the chamber's width (AutoBaler.CHAMBER.x * 0.5)
const BALER_HD: float = 0.5
const BALER_FLOOR: float = 0.34


## The press that does not move: skid, chamber between two fat columns, the crosshead with twin
## hydraulic cylinders, the wide feed hopper at the back (-Z), the roller ramp out the front (+Z),
## the power pack, the gate's guide frame with the picture sign on top. Local: AutoBaler's frame.
static func baler_body() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var body: Color = col("baler", "body", YardArt.BLUE)
	var body_d: Color = body.darkened(0.22)
	var press: Color = col("baler", "press", YardArt.YELLOW)
	var trim: Color = col("baler", "trim", YardArt.CREAM)
	var hw: float = BALER_HW
	# Skid with runners, lifting lugs and a hazard nose either side of the ramp.
	k.box(Vector3(2.5, 0.12, 2.7), Vector3(0, 0.1, -0.4), YardArt.GUNMETAL, Vector3.ZERO, 0.03)
	for x: float in [-1.05, 1.05]:
		k.box(Vector3(0.22, 0.08, 2.9), Vector3(x, 0.04, -0.4), YardArt.DARK, Vector3.ZERO, 0.03)
		k.hazard(Vector3(0.5, 0.125, 0.04), Vector3(x * 0.92, 0.1, 0.955))
		for z: float in [-1.6, 0.8]:
			k.box(Vector3(0.08, 0.16, 0.16), Vector3(x * 1.13, 0.2, z), press, Vector3.ZERO, 0.02)
			k.cyl(0.035, 0.1, Vector3(x * 1.13, 0.22, z), YardArt.DARK, Vector3(0, 0, 90), 0.008, 10)
	# Chamber floor and back wall.
	k.box(Vector3(hw * 2.0 + 0.1, BALER_FLOOR - 0.16, BALER_HD * 2.0 + 0.1), Vector3(0, 0.16 + (BALER_FLOOR - 0.16) * 0.5, 0), YardArt.DARK, Vector3.ZERO, 0.02)
	k.box(Vector3(hw * 2.0, 1.4, 0.08), Vector3(0, BALER_FLOOR + 0.7, -BALER_HD - 0.04), body_d, Vector3.ZERO, 0.02)
	for x: float in [-0.3, 0.0, 0.3]:
		k.box(Vector3(0.06, 1.3, 0.05), Vector3(x, BALER_FLOOR + 0.7, -BALER_HD - 0.09), body, Vector3.ZERO, 0.015)
	# Two fat columns: panelled outside, wear plates inside, hazard feet.
	for s: float in [-1.0, 1.0]:
		var cx: float = s * (hw + 0.14)
		k.box(Vector3(0.28, 2.4, 1.24), Vector3(cx, 1.36, 0), body, Vector3.ZERO, 0.05)
		k.panel(0.9, 1.5, Vector3(cx + s * 0.142, 1.45, 0), body_d, Vector3(0, s * 90.0, 0), body.lightened(0.06), 0.035)
		k.box(Vector3(0.3, 0.14, 1.28), Vector3(cx, 0.23, 0), body_d, Vector3.ZERO, 0.03)
		k.hazard(Vector3(0.285, 0.34, 0.03), Vector3(cx, 0.52, 0.61))
		k.box(Vector3(0.02, 1.6, 0.9), Vector3(s * (hw - 0.004), BALER_FLOOR + 0.85, 0), YardArt.STEEL, Vector3.ZERO, 0.006)
		for y: float in [0.9, 1.5, 2.1]:
			k.bolt(Vector3(cx - s * 0.06, y, 0.622), Vector3.BACK)
			k.bolt(Vector3(cx + s * 0.08, y, 0.622), Vector3.BACK)
	# Crosshead (its front stays behind the gate's slot) with a cap and a bolted flange.
	k.box(Vector3(1.96, 0.4, 1.06), Vector3(0, 2.6, -0.03), trim, Vector3.ZERO, 0.06)
	k.box(Vector3(1.7, 0.08, 0.9), Vector3(0, 2.83, -0.03), body_d, Vector3.ZERO, 0.025)
	k.box(Vector3(2.0, 0.1, 1.1), Vector3(0, 2.42, -0.03), body, Vector3.ZERO, 0.03)
	for x: float in [-0.85, -0.6, 0.6, 0.85]:
		k.bolt(Vector3(x, 2.62, 0.502), Vector3.BACK, YardArt.STEEL, 0.026)
	# Twin hydraulic cylinders: fat barrels, end caps, tie rods, a manifold across the top.
	for s: float in [-1.0, 1.0]:
		var x: float = s * 0.33
		k.cyl(0.19, 0.1, Vector3(x, 2.92, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.025, 16)
		k.cyl(0.15, 0.95, Vector3(x, 3.44, 0), press, Vector3.ZERO, 0.02, 16)
		k.cyl(0.19, 0.1, Vector3(x, 3.96, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.025, 16)
		for q: int in 4:
			var a: float = TAU * (q + 0.5) / 4.0
			k.pipe(Vector3(x + cos(a) * 0.165, 2.95, sin(a) * 0.165), Vector3(x + cos(a) * 0.165, 3.94, sin(a) * 0.165), 0.014, YardArt.STEEL, false)
		k.cyl(0.05, 0.08, Vector3(x, 4.04, 0), YardArt.BRASS, Vector3.ZERO, 0.012, 10)
	k.box(Vector3(0.9, 0.09, 0.2), Vector3(0, 4.03, -0.14), YardArt.GUNMETAL, Vector3.ZERO, 0.025)
	# Hoses from the manifold down the right side to the power pack.
	for s: float in [-1.0, 1.0]:
		k.cable([Vector3(0.42, 4.03, -0.14 + s * 0.05), Vector3(0.95, 3.75, -0.15 + s * 0.08), Vector3(1.08, 2.7, -0.15 + s * 0.1), Vector3(1.12, 1.2, -0.15 + s * 0.1), Vector3(1.2, 0.8, -0.15 + s * 0.12)], 0.03, YardArt.RUBBER if s < 0.0 else YardArt.ORANGE)
	# The feed hopper: a wide scoop sloping into the chamber's back, on two braced posts.
	var slope: float = 25.0
	k.push(ProcMesh.xf(Vector3(0, 2.0, -1.03), Vector3(slope, 0, 0)))
	k.box(Vector3(1.26, 0.06, 1.1), Vector3.ZERO, press, Vector3.ZERO, 0.02)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.06, 0.62, 1.1), Vector3(s * 0.66, 0.3, 0), press, Vector3(0, 0, s * -9.0), 0.02)
		k.hazard(Vector3(0.075, 0.09, 1.12), Vector3(s * 0.71, 0.62, 0), Vector3(0, 0, s * -9.0))
	k.push(ProcMesh.xf(Vector3(0, 0.33, -0.56), Vector3(-14, 0, 0)))  # the flared back wall
	k.box(Vector3(1.4, 0.7, 0.06), Vector3.ZERO, press, Vector3.ZERO, 0.02)
	k.hazard(Vector3(1.5, 0.09, 0.075), Vector3(0, 0.37, 0))
	k.decal("arrow", Vector2(0.4, 0.4), Vector3(0, -0.02, -0.032), Vector3(0, 180, 0))
	k.pop()
	for x: float in [-0.4, 0.0, 0.4]:  # wear strips down the slide
		k.box(Vector3(0.07, 0.02, 1.0), Vector3(x, 0.04, 0), YardArt.STEEL, Vector3.ZERO, 0.006)
	k.pop()
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.1, 2.0, 0.1), Vector3(s * 0.56, 1.14, -1.42), body_d, Vector3.ZERO, 0.02)
		k.box(Vector3(0.07, 1.25, 0.07), Vector3(s * 0.56, 1.25, -1.05), body_d, Vector3(40, 0, 0), 0.015)
		k.box(Vector3(0.2, 0.05, 0.2), Vector3(s * 0.56, 0.17, -1.42), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	k.box(Vector3(1.22, 0.07, 0.07), Vector3(0, 1.3, -1.42), body_d, Vector3.ZERO, 0.015)
	# The gate's guide frame above the crosshead, and the picture sign on top of it.
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.08, 1.3, 0.1), Vector3(s * 0.64, 3.44, 0.55), body, Vector3.ZERO, 0.02)
	k.box(Vector3(1.42, 0.1, 0.12), Vector3(0, 4.08, 0.55), body, Vector3.ZERO, 0.025)
	k.box(Vector3(0.09, 0.2, 0.07), Vector3(0, 4.2, 0.55), YardArt.GUNMETAL, Vector3.ZERO, 0.015)
	put_sign(k, "baler", Vector3(0, 4.17 + float(sign_def("baler").get("size", SIGN_BASE)) * 0.5, 0.55), Vector3.ZERO, true)
	# Roller ramp out the front, tilted down to the ground.
	var ramp_len: float = 1.8
	k.push(Transform3D(Basis(Vector3.RIGHT, atan2(BALER_FLOOR - 0.14, ramp_len)), Vector3(0, (BALER_FLOOR + 0.14) * 0.5, BALER_HD + ramp_len * 0.5)))
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.07, 0.17, ramp_len), Vector3(s * 0.53, -0.02, 0), press, Vector3.ZERO, 0.02)
		k.box(Vector3(0.09, 0.05, ramp_len + 0.04), Vector3(s * 0.55, 0.08, 0), body, Vector3.ZERO, 0.015)
		k.box(Vector3(0.07, 0.2, 0.07), Vector3(s * 0.53, -0.1, ramp_len * 0.4), YardArt.GUNMETAL, Vector3.ZERO, 0.015)
	for i: int in 9:
		k.cyl(0.045, 0.98, Vector3(0, 0.0, -ramp_len * 0.5 + 0.1 + i * (ramp_len - 0.2) / 8.0), YardArt.STEEL, Vector3(0, 0, 90), 0.01, 10)
	k.pop()
	k.box(Vector3(1.0, 0.03, 0.5), Vector3(0, 0.015, BALER_HD + ramp_len + 0.38), YardArt.DARK, Vector3.ZERO, 0.01)
	k.decal("chevrons", Vector2(0.8, 0.26), Vector3(0, 0.032, BALER_HD + ramp_len + 0.38), Vector3(-90, 0, 0))
	# Hydraulic power pack on the right: tank, finned motor, a round pressure gauge, a filler cap.
	var px: float = hw + 0.64
	k.box(Vector3(0.7, 0.1, 1.0), Vector3(px + 0.02, 0.11, -0.15), YardArt.GUNMETAL, Vector3.ZERO, 0.03)  # the pack's shelf on the skid
	k.box(Vector3(0.52, 0.6, 0.84), Vector3(px, 0.46, -0.15), trim, Vector3.ZERO, 0.05)
	k.panel(0.4, 0.34, Vector3(px, 0.5, 0.275), trim.darkened(0.06), Vector3.ZERO, Color(-1, 0, 0), 0.025)
	k.cyl(0.15, 0.48, Vector3(px, 0.92, -0.15), body, Vector3(90, 0, 0), 0.03, 16)
	for i: int in 4:
		k.cyl(0.17, 0.03, Vector3(px, 0.92, -0.3 + i * 0.1), YardArt.GUNMETAL, Vector3(90, 0, 0), 0.008, 16)
	k.cyl(0.07, 0.06, Vector3(px, 0.92, 0.12), YardArt.GUNMETAL, Vector3(90, 0, 0), 0.012, 12)
	k.cyl(0.105, 0.04, Vector3(px + 0.08, 0.52, 0.29), YardArt.GUNMETAL, Vector3(90, 0, 0), 0.01, 16)
	k.cyl(0.085, 0.03, Vector3(px + 0.08, 0.52, 0.305), YardArt.CREAM, Vector3(90, 0, 0), 0.006, 16)
	k.box(Vector3(0.014, 0.07, 0.01), Vector3(px + 0.095, 0.54, 0.322), YardArt.RED, Vector3(0, 0, -35), 0.003)
	k.glow_box(Vector3(0.035, 0.035, 0.02), Vector3(px - 0.12, 0.6, 0.285), YardArt.MINT)
	k.glow_box(Vector3(0.035, 0.035, 0.02), Vector3(px - 0.12, 0.52, 0.285), YardArt.AMBER)
	k.cyl(0.06, 0.07, Vector3(px - 0.12, 0.79, -0.45), press, Vector3.ZERO, 0.015, 10)
	k.pipe(Vector3(px - 0.2, 0.3, -0.5), Vector3(hw + 0.3, 0.3, -0.5), 0.035, YardArt.ORANGE, true)
	# A control box with two fat buttons on the left column, a warning plate under it.
	var bx: float = -(hw + 0.14)
	k.box(Vector3(0.24, 0.34, 0.09), Vector3(bx, 1.45, 0.66), trim, Vector3.ZERO, 0.03)
	k.glow_cyl(0.045, 0.03, Vector3(bx, 1.52, 0.715), YardArt.MINT, Vector3(90, 0, 0), 12)
	k.cyl(0.045, 0.03, Vector3(bx, 1.39, 0.715), YardArt.RED, Vector3(90, 0, 0), 0.008, 12)
	k.decal("warn", Vector2(0.2, 0.2), Vector3(bx, 1.1, 0.622))
	# The slot of the fill gauge on the right column, the beacon's socket, a number on the cap.
	k.box(Vector3(0.1, 1.64, 0.02), Vector3(hw + 0.14, 1.3, 0.622), YardArt.RUBBER, Vector3.ZERO, 0.006)
	k.cyl(0.11, 0.06, Vector3(-hw - 0.15, 2.83, 0.2), YardArt.DARK, Vector3.ZERO, 0.015, 12)
	k.decal("label_scrap", Vector2(0.6, 0.15), Vector3(0.0, 0.92, -BALER_HD - 0.12), Vector3(0, 180, 0))
	return k


## The moving press head (origin: its underside): a fat hazard-edged slab, ribs, the two chrome rods.
static func baler_platen() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var press: Color = col("baler", "press", YardArt.YELLOW)
	k.box(Vector3(BALER_HW * 2.0 - 0.06, 0.18, BALER_HD * 2.0 - 0.06), Vector3(0, 0.09, 0), press, Vector3.ZERO, 0.035)
	k.hazard(Vector3(BALER_HW * 2.0 - 0.1, 0.11, 0.03), Vector3(0, 0.09, BALER_HD - 0.02))
	k.box(Vector3(BALER_HW * 2.0 - 0.12, 0.03, BALER_HD * 2.0 - 0.12), Vector3(0, 0.005, 0), YardArt.STEEL, Vector3.ZERO, 0.01)
	for x: float in [-0.33, 0.0, 0.33]:
		k.box(Vector3(0.06, 0.1, BALER_HD * 2.0 - 0.2), Vector3(x, 0.22, 0), press.darkened(0.15), Vector3.ZERO, 0.015)
	for s: float in [-1.0, 1.0]:
		k.cyl(0.1, 0.12, Vector3(s * 0.33, 0.24, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.02, 12)
		k.cyl(0.058, 1.62, Vector3(s * 0.33, 1.0, 0), YardArt.STEEL, Vector3.ZERO, 0.01, 12)
	return k


## The safety gate (origin: the gate node; it drops while pressing): steel bars in a hazard frame.
static func baler_gate() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var w: float = BALER_HW * 2.0
	for i: int in 7:
		var x: float = -BALER_HW + 0.09 + i * (w - 0.18) / 6.0
		k.pipe(Vector3(x, BALER_FLOOR + 0.08, 0), Vector3(x, BALER_FLOOR + 1.52, 0), 0.018, YardArt.STEEL, false)
	k.hazard(Vector3(w - 0.02, 0.09, 0.055), Vector3(0, BALER_FLOOR + 0.08, 0))
	k.hazard(Vector3(w - 0.02, 0.09, 0.055), Vector3(0, BALER_FLOOR + 1.52, 0))
	k.box(Vector3(w - 0.02, 0.05, 0.045), Vector3(0, BALER_FLOOR + 0.8, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	k.box(Vector3(0.2, 0.05, 0.07), Vector3(0, BALER_FLOOR + 0.8, 0.02), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	return k


# --- Belt Drive (automation/conveyor.gd) --------------------------------------------------------------

## The feed pad round the turntable (origin: the hopper position on the ground): a dark plate with a
## hazard border, two low guides, the gantry with the picture sign, and the drive: a fat motor, a
## belt guard with two pulleys, a gearbox. half = Conveyor.PAD_HALF.
static func belt_pad(half: float) -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var frame: Color = col("belt", "frame", YardArt.YELLOW)
	var motor: Color = col("belt", "motor", YardArt.ORANGE)
	k.box(Vector3(half * 2.0, 0.1, half * 2.0), Vector3(0, 0.05, 0), YardArt.DARK, Vector3.ZERO, 0.02)
	for side: int in 4:
		var yaw: float = side * 90.0
		k.push(ProcMesh.xf(Vector3.ZERO, Vector3(0, yaw, 0)))
		k.hazard(Vector3(half * 2.0, 0.014, 0.13), Vector3(0, 0.105, half - 0.065))
		k.pop()
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		k.box(Vector3(0.16, 0.03, 0.16), Vector3(c.x * (half - 0.08), 0.11, c.y * (half - 0.08)), YardArt.GUNMETAL, Vector3.ZERO, 0.01)
		k.bolt(Vector3(c.x * (half - 0.08), 0.125, c.y * (half - 0.08)), Vector3.UP)
	# Low side guides on the north and east edges (bales can't roll off the far sides).
	k.box(Vector3(half * 2.0, 0.24, 0.07), Vector3(0, 0.22, half - 0.04), frame, Vector3.ZERO, 0.025)
	k.box(Vector3(0.07, 0.24, half * 2.0), Vector3(half - 0.04, 0.22, 0), frame, Vector3.ZERO, 0.025)
	# Gantry over the north edge: two posts on feet, a beam, the sign hanging from it.
	for x: float in [-half - 0.05, half + 0.05]:
		k.box(Vector3(0.32, 0.05, 0.32), Vector3(x, 0.025, half + 0.1), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
		k.box(Vector3(0.12, 2.3, 0.12), Vector3(x, 1.15, half + 0.1), frame, Vector3.ZERO, 0.025)
		k.hazard(Vector3(0.13, 0.4, 0.13), Vector3(x, 0.4, half + 0.1))
		k.box(Vector3(0.07, 0.5, 0.07), Vector3(x - signf(x) * 0.17, 2.1, half + 0.1), frame.darkened(0.15), Vector3(0, 0, signf(x) * -45.0), 0.015)
	k.box(Vector3(half * 2.0 + 0.34, 0.14, 0.14), Vector3(0, 2.3, half + 0.1), frame, Vector3.ZERO, 0.03)
	for x: float in [-0.14, 0.14]:
		k.box(Vector3(0.05, 0.16, 0.05), Vector3(x, 2.43, half + 0.1), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	put_sign(k, "belt", Vector3(0, 2.45 + float(sign_def("belt").get("size", SIGN_BASE)) * 0.5, half + 0.1), Vector3.ZERO, true)
	k.cyl(0.07, 0.05, Vector3(half + 0.05, 2.39, half + 0.1), YardArt.DARK, Vector3.ZERO, 0.012, 10)  # the beacon's socket
	# The drive beside the pad: skid, a fat finned motor, the belt guard and gearbox.
	k.push(Transform3D(Basis(), Vector3(half + 0.34, 0, -0.45)))
	k.box(Vector3(0.9, 0.06, 0.62), Vector3(0.08, 0.03, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.015)
	k.cyl(0.2, 0.52, Vector3(0.2, 0.3, 0.02), motor, Vector3(0, 0, 90), 0.04, 18)
	for i: int in 5:
		k.cyl(0.225, 0.028, Vector3(0.04 + i * 0.085, 0.3, 0.02), motor.darkened(0.25), Vector3(0, 0, 90), 0.008, 18)
	k.cyl(0.12, 0.07, Vector3(0.49, 0.3, 0.02), YardArt.GUNMETAL, Vector3(0, 0, 90), 0.02, 14)
	k.box(Vector3(0.2, 0.1, 0.16), Vector3(0.2, 0.54, 0.02), YardArt.CREAM, Vector3.ZERO, 0.025)  # terminal box
	k.glow_box(Vector3(0.03, 0.03, 0.02), Vector3(0.2, 0.55, 0.105), YardArt.MINT)
	k.box(Vector3(0.26, 0.4, 0.36), Vector3(-0.26, 0.25, 0.0), YardArt.TEAL_D, Vector3.ZERO, 0.04)  # gearbox
	k.bolts4(Vector3(-0.26, 0.25, 0.182), Vector3(0.09, 0, 0), Vector3(0, 0.15, 0), Vector3.BACK)
	# Belt guard: two pulleys under a hazard-edged cover on the gearbox's outer face.
	k.box(Vector3(0.6, 0.34, 0.07), Vector3(-0.02, 0.3, 0.3), frame, Vector3.ZERO, 0.03)
	for x: float in [-0.2, 0.17]:
		k.cyl(0.11 if x < 0.0 else 0.075, 0.03, Vector3(x, 0.3, 0.345), YardArt.DARK, Vector3(90, 0, 0), 0.008, 14)
		k.cyl(0.03, 0.03, Vector3(x, 0.3, 0.365), YardArt.STEEL, Vector3(90, 0, 0), 0.006, 8)
	k.hazard(Vector3(0.62, 0.05, 0.08), Vector3(-0.02, 0.48, 0.3))
	k.pop()
	k.cable([Vector3(half + 0.54, 0.5, -0.43), Vector3(half + 0.3, 0.75, 0.2), Vector3(half + 0.05, 0.6, half + 0.04)], 0.022)
	return k


## The roller turntable (origin: the turntable node): a steel disc in a painted ring with a bed of
## live rollers that turns to face the route.
static func belt_turntable() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var frame: Color = col("belt", "frame", YardArt.YELLOW)
	k.cyl(0.76, 0.05, Vector3(0, 0.025, 0), frame, Vector3.ZERO, 0.015, 28)
	k.cyl(0.7, 0.07, Vector3(0, 0.04, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.012, 28)
	for i: int in 7:
		var zz: float = -0.48 + i * 0.16
		var hlf: float = sqrt(maxf(0.68 * 0.68 - zz * zz, 0.01))
		k.cyl(0.045, hlf * 1.8, Vector3(0, 0.1, zz), YardArt.STEEL, Vector3(0, 0, 90), 0.01, 10)
	for s: float in [-1.0, 1.0]:  # which way it points: two little arrows on the rim
		k.box(Vector3(0.1, 0.02, 0.05), Vector3(s * 0.62, 0.085, 0.0), frame, Vector3(0, 45, 0), 0.006)
	return k


## One belt run's hard parts (origin: the segment's centre, +X along the belt, belt surface at
## y = 0): side skirts with a top lip and bolts, the bed, head / tail drums, return idlers.
static func belt_segment(length: float, belt_w: float, first: bool, last: bool) -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var frame: Color = col("belt", "frame", YardArt.YELLOW)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(length + 0.02, 0.22, 0.06), Vector3(0, 0.0, s * (belt_w * 0.5 + 0.035)), frame, Vector3.ZERO, 0.02)
		k.box(Vector3(length + 0.02, 0.035, 0.1), Vector3(0, 0.11, s * (belt_w * 0.5 + 0.05)), frame.darkened(0.12), Vector3.ZERO, 0.012)
		for i: int in int(length / 0.45):
			k.bolt(Vector3(-length * 0.5 + 0.22 + i * 0.45, -0.02, s * (belt_w * 0.5 + 0.066)), Vector3(0, 0, s), YardArt.STEEL, 0.016)
	k.box(Vector3(length, 0.05, belt_w + 0.06), Vector3(0, -0.2, 0), YardArt.GUNMETAL, Vector3.ZERO, 0.015)
	k.box(Vector3(length, 0.02, belt_w - 0.02), Vector3(0, -0.15, 0), YardArt.RUBBER, Vector3.ZERO, 0.006)
	var ends: Array[float] = []
	if first:
		ends.append(-length * 0.5)
	if last:
		ends.append(length * 0.5)
	for ex: float in ends:
		k.cyl(0.075, belt_w + 0.04, Vector3(ex, -0.075, 0), YardArt.STEEL, Vector3(90, 0, 0), 0.012, 12)
		for s: float in [-1.0, 1.0]:  # bearing blocks
			k.box(Vector3(0.16, 0.16, 0.05), Vector3(ex, -0.075, s * (belt_w * 0.5 + 0.075)), YardArt.TEAL_D, Vector3.ZERO, 0.02)
	var n_idle: int = maxi(1, int(length / 0.7))
	for i: int in n_idle:
		k.cyl(0.03, belt_w - 0.04, Vector3(-length * 0.5 + (i + 0.5) * length / n_idle, -0.17, 0), YardArt.STEEL, Vector3(90, 0, 0), 0.006, 8)
	return k


# --- The pod's repair stand (story/crash_site.gd) ---------------------------------------------------

const POD_SERVICE_SOLID := Vector3(1.0, 1.0, 0.65)  # the cart's collider (centre at y 0.5)


## What stands by the crashed pod once Lumi starts mending it: a service cart (drawers, a toolbox,
## a spanner, a work lamp on a stalk), a cable snaking off toward the pod (-X) and three cones.
## Origin on the ground at the cart; the cart's front (drawers) faces -X, toward the pod.
static func pod_service() -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var body: Color = col("pod", "cart", YardArt.CREAM)
	var trim: Color = col("pod", "cart_trim", YardArt.TEAL)
	var cone: Color = col("pod", "cone", YardArt.ORANGE)
	k.box(Vector3(0.58, 0.62, 0.92), Vector3(0, 0.5, 0), body, Vector3.ZERO, 0.05)
	k.box(Vector3(0.66, 0.07, 1.0), Vector3(0, 0.845, 0), trim, Vector3.ZERO, 0.025)
	k.box(Vector3(0.62, 0.06, 0.96), Vector3(0, 0.2, 0), trim.darkened(0.2), Vector3.ZERO, 0.02)
	k.hazard(Vector3(0.05, 0.1, 0.94), Vector3(-0.3, 0.22, 0))
	for i: int in 3:
		k.box(Vector3(0.03, 0.15, 0.8), Vector3(-0.295, 0.33 + i * 0.18, 0), YardArt.ORANGE.lightened(0.12), Vector3.ZERO, 0.012)
		k.box(Vector3(0.03, 0.025, 0.3), Vector3(-0.32, 0.35 + i * 0.18, 0), YardArt.STEEL, Vector3.ZERO, 0.008)
	for x: float in [-0.22, 0.22]:
		for z: float in [-0.36, 0.36]:
			k.cyl(0.09, 0.06, Vector3(x, 0.09, z), YardArt.RUBBER, Vector3(90, 0, 0), 0.02, 12)
			k.box(Vector3(0.05, 0.1, 0.09), Vector3(x, 0.15, z), YardArt.GUNMETAL, Vector3.ZERO, 0.012)
	k.pipe(Vector3(0.3, 0.75, -0.4), Vector3(0.3, 0.75, 0.4), 0.02, YardArt.STEEL, false)  # push bar
	for z: float in [-0.4, 0.4]:
		k.pipe(Vector3(0.24, 0.6, z), Vector3(0.3, 0.75, z), 0.018, YardArt.STEEL, false)
	# On top: a red toolbox, a spanner, a coil of cable, a work lamp on a stalk.
	k.box(Vector3(0.24, 0.17, 0.4), Vector3(0.08, 0.965, 0.22), YardArt.RED, Vector3(0, 8, 0), 0.03)
	k.box(Vector3(0.05, 0.03, 0.2), Vector3(0.08, 1.065, 0.22), YardArt.GUNMETAL, Vector3(0, 8, 0), 0.01)
	k.box(Vector3(0.05, 0.02, 0.3), Vector3(-0.1, 0.89, -0.2), YardArt.STEEL, Vector3(0, 30, 0), 0.006)
	k.cyl(0.05, 0.02, Vector3(-0.17, 0.89, -0.32), YardArt.STEEL, Vector3.ZERO, 0.005, 8)
	k.cyl(0.11, 0.07, Vector3(0.12, 0.915, -0.26), YardArt.ORANGE, Vector3.ZERO, 0.02, 14)
	k.cyl(0.06, 0.075, Vector3(0.12, 0.915, -0.26), YardArt.DARK, Vector3.ZERO, 0.012, 10)
	k.pipe(Vector3(0.22, 0.88, 0.42), Vector3(0.22, 1.75, 0.42), 0.022, trim, false)
	k.cyl(0.1, 0.13, Vector3(0.14, 1.76, 0.42), YardArt.ORANGE, Vector3(0, 0, 65), -1.0, 14, "paint", 0.05)
	k.glow_cyl(0.075, 0.02, Vector3(0.075, 1.73, 0.42), YardArt.WARM, Vector3(0, 0, 65))
	k.light(Vector3(-0.5, 1.5, 0.42), YardArt.WARM, 0.8, 4.0)
	k.cable([Vector3(-0.1, 0.9, -0.3), Vector3(-0.4, 0.5, -0.5), Vector3(-0.7, 0.04, -0.7), Vector3(-1.3, 0.04, -0.5), Vector3(-1.9, 0.04, -0.75)], 0.022, YardArt.ORANGE)
	# Three cones round the work area.
	for c: Vector3 in [Vector3(-0.9, 0, 0.9), Vector3(-0.2, 0, -1.25), Vector3(0.75, 0, 0.95)]:
		k.box(Vector3(0.3, 0.035, 0.3), c + Vector3(0, 0.018, 0), YardArt.DARK, Vector3.ZERO, 0.012)
		k.cyl(0.11, 0.42, c + Vector3(0, 0.245, 0), cone, Vector3.ZERO, 0.01, 12, "paint", 0.03)
		k.cyl(0.082, 0.09, c + Vector3(0, 0.27, 0), YardArt.CREAM, Vector3.ZERO, 0.006, 12, "paint", 0.066)
	return k
