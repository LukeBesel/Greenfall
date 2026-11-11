class_name HubLandmarks
extends RefCounted
## [v6yard] The hubs' landmarks as art-kit models (docs/ART_KIT.md): chunky, bevelled, one draw
## call per material, automatic LODs, three states. One big readable gesture each, so a small child
## can say what it is: a tank on legs (water), a fan on a tower (wind), a portal with a hook
## (lifting), a mast with dishes (signal), a wheel with gondolas (fair), a tall chimney with tanks
## (fuel). Every landmark has the same little console in front: that is where Lumi wakes it.
##
## Sizes, colours and spin speeds are data: data/landmarks.json, per kind and per planet
## (docs/ADJUSTING.md, "Yard machines and landmarks").
##
##   HubLandmarks.has(kind)                       a kit model exists for this StreetDressing kind
##   HubLandmarks.create(kind, level, seed, planet) -> HubLandmarkNode (origin on the ground, front +Z)
##   HubLandmarks.data_for(kind, state, seed, planet) -> Data (cached mesh, lights, top, solids, spin)
##   HubLandmarks.warm(kind, state, seed, planet)   the geometry a frame ahead of data_for (half the work each)
##   HubLandmarks.foot(kind, planet)              clear radius the model needs (metres)
## States follow the hub's level (data "states"): 1 broken and dark, 2 repaired and lit, 3+ restored.

const DATA: String = "res://data/landmarks.json"
const KINDS: Array[String] = ["water_tower", "windpump", "crane", "radio_mast", "ferris_wheel", "smokestack"]

static var _cfg: Dictionary = {}


## What a built landmark is: geometry and everything the scene needs to stand it up.
class Data:
	extends Resource
	var mesh: ArrayMesh
	var tris: int = 0
	var lights: Array[Dictionary] = []
	var top := Vector3.ZERO          # where the hub's beacon stands
	var solids: Array = []           # [centre, size] boxes (PROP colliders)
	var kiosk := Vector3.ZERO        # the wake console
	var spin_mesh: ArrayMesh         # the turning part (or null)
	var spin_at := Vector3.ZERO
	var spin_axis := Vector3.BACK
	var spin_speed: float = 0.0      # radians a second when awake
	var gondola_meshes: Array[ArrayMesh] = []
	var gondola_r: float = 0.0
	var gondola_n: int = 0
	var gondola_skip: Array[int] = []


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(DATA)
	return _cfg


static func reload() -> void:
	_cfg = {}


static func kinds() -> Array[String]:
	return KINDS


static func has(kind: String) -> bool:
	return KINDS.has(kind) and bool(kind_cfg(kind, "").get("kit", true))


## The settings of a kind: data "kinds".<kind>, then "planets".<planet>.<kind> on top.
static func kind_cfg(kind: String, planet: String) -> Dictionary:
	var out: Dictionary = {}
	var ks: Variant = cfg().get("kinds", {})
	if ks is Dictionary and (ks as Dictionary).get(kind) is Dictionary:
		out.merge((ks as Dictionary)[kind] as Dictionary, true)
	var ps: Variant = cfg().get("planets", {})
	if planet != "" and ps is Dictionary and (ps as Dictionary).get(planet) is Dictionary:
		var p: Dictionary = (ps as Dictionary)[planet]
		if p.get(kind) is Dictionary:
			out.merge(p[kind] as Dictionary, true)
	return out


static func foot(kind: String, planet: String = "") -> float:
	return float(kind_cfg(kind, planet).get("foot", 4.5))


## broken / repaired / restored for a hub level (data "states").
static func state_for_level(level: int) -> String:
	var st: Variant = cfg().get("states", {})
	var best: String = "broken"
	if st is Dictionary:
		for l: int in range(1, level + 1):
			if (st as Dictionary).has(str(l)):
				best = str((st as Dictionary)[str(l)])
	elif level >= 3:
		best = "restored"
	elif level == 2:
		best = "repaired"
	return best


static func create(kind: String, level: int, seed_: int = 1, planet: String = "") -> HubLandmarkNode:
	var n := HubLandmarkNode.new()
	n.name = "Landmark"
	n.kind = kind
	n.planet = planet
	n.seed_i = seed_
	n.set_level(level)
	return n


## For tools: a landmark node in a given state (tools/machine_stats.gd, the lineup).
static func build(kind: String, state: String, seed_: int = 1, planet: String = "") -> HubLandmarkNode:
	var n := HubLandmarkNode.new()
	n.kind = kind
	n.planet = planet
	n.seed_i = seed_
	n.set_state(state)
	return n


## Built landmarks by key, and geometry waiting for its mesh (see warm()).
static var _built: Dictionary = {}
static var _pending: Dictionary = {}


static func _key(kind: String, state: String, seed_: int, c: Dictionary) -> String:
	return "%s:%s:%d:%d" % [kind, state, seed_, c.hash()]


## Step one of a build, for callers that spread the work over two frames (StreetDressing while a
## town builds): the geometry now, the mesh and its LODs at the next data_for(). Nothing to do if
## the landmark is already built.
static func warm(kind: String, state: String, seed_: int = 1, planet: String = "") -> void:
	var c: Dictionary = kind_cfg(kind, planet)
	var key: String = _key(kind, state, seed_, c)
	if not _built.has(key) and not _pending.has(key):
		_pending[key] = _geometry(kind, state, seed_, c)


static func data_for(kind: String, state: String, seed_: int = 1, planet: String = "") -> Data:
	var c: Dictionary = kind_cfg(kind, planet)
	var key: String = _key(kind, state, seed_, c)
	if not _built.has(key):
		var g: Array = _pending[key] if _pending.has(key) else _geometry(kind, state, seed_, c)
		_pending.erase(key)
		var b: KitMesh.Builder = g[0]
		var d: Data = g[1]
		d.tris = b.tri_count()
		d.mesh = b.commit(null, bool(cfg().get("lods", true)))
		d.lights = b.lights
		_built[key] = d
	return _built[key]


static func clear_cache() -> void:
	_built.clear()
	_pending.clear()


## [Builder, Data]: every part added, nothing committed yet.
static func _geometry(kind: String, state: String, seed_: int, c: Dictionary) -> Array:
	var pal: Dictionary = {"main": str(c.get("main", "cream")), "accent": str(c.get("accent", "teal"))}
	var b := KitMesh.Builder.new(seed_ * 131 + KINDS.find(kind), pal, state)
	var d := Data.new()
	match kind:
		"water_tower":
			_water_tower(b, d, state, c)
		"windpump":
			_windpump(b, d, state, c, pal, seed_)
		"crane":
			_crane(b, d, state, c)
		"radio_mast":
			_radio_mast(b, d, state, c, pal, seed_)
		"ferris_wheel":
			_ferris(b, d, state, c, pal, seed_)
		"smokestack":
			_smokestack(b, d, state, c)
	_kiosk(b, _x(d.kiosk, Vector3(0, float(c.get("kiosk_yaw", 0.0)), 0)), state)
	return [b, d]


# --- Helpers -----------------------------------------------------------------------------------------

static func _x(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return KitMesh.xf(pos, rot)


static func _yaw(a: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, a), Vector3.ZERO)


## A closed tube ring: centre c, in the plane of u and v, radius r.
static func _ring(b: KitMesh.Builder, key: String, c: Vector3, u: Vector3, v: Vector3, r: float, tube_r: float, n: int = 28, sides: int = 6) -> void:
	var pts := PackedVector3Array()
	for i: int in n + 1:
		var a: float = TAU * i / n
		pts.append(c + (u * cos(a) + v * sin(a)) * r)
	b.tube(key, pts, tube_r, sides)


## A tapered band round a lathe body: y0..y1, radius r0 -> r1 (a touch proud of the body).
static func _band(b: KitMesh.Builder, key: String, y0: float, y1: float, r0: float, r1: float, sides: int = 20, t: Transform3D = Transform3D.IDENTITY) -> void:
	var p := PackedVector3Array([Vector3(0, y0, 0), Vector3(r0, y0, 1), Vector3(r1, y1, 1), Vector3(0, y1, 0)])
	b.add(key, KitMesh.lathe(p, sides), t)


## A round deck with a ring railing (posts, top and mid rails) at height y.
static func _deck(b: KitMesh.Builder, y: float, r: float, state: String, posts: int = 14) -> void:
	b.cyl("dark_steel", r, 0.18, _x(Vector3(0, y - 0.18, 0)), 0.04, 20)
	b.cyl("paint:accent", r + 0.05, 0.08, _x(Vector3(0, y - 0.24, 0)), 0.02, 20)
	var rr: float = r - 0.12
	for i: int in posts:
		if state == "broken" and i % 5 == 2:
			continue
		var a: float = TAU * i / posts
		b.rod("paint:rail", Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(cos(a) * rr, y + 1.05, sin(a) * rr), 0.04, 6)
	_ring(b, "paint:rail", Vector3(0, y + 1.05, 0), Vector3.RIGHT, Vector3.BACK, rr, 0.045, 24)
	_ring(b, "paint:rail", Vector3(0, y + 0.55, 0), Vector3.RIGHT, Vector3.BACK, rr, 0.028, 24, 5)


## The wake console every landmark has: a slab, a cream cabinet with a sloped teal desk, a screen,
## one fat button, a lamp on a stalk. Front +Z of t.
static func _kiosk(b: KitMesh.Builder, t: Transform3D, state: String) -> void:
	b.box("concrete", Vector3(1.9, 0.16, 1.5), t * _x(Vector3(0, 0.08, 0)), 0.04)
	b.box("hazard", Vector3(1.92, 0.05, 0.14), t * _x(Vector3(0, 0.15, 0.7)), 0.015)
	b.box("paint:main", Vector3(1.0, 0.95, 0.6), t * _x(Vector3(0, 0.63, -0.1)), 0.07, 2)
	b.box("paint:accent", Vector3(1.08, 0.3, 0.72), t * _x(Vector3(0, 1.18, -0.04), Vector3(22, 0, 0)), 0.06)
	b.box("dark_steel", Vector3(0.62, 0.02, 0.36), t * _x(Vector3(-0.12, 1.345, 0.02), Vector3(22, 0, 0)), 0.006)
	b.box("trim:cool", Vector3(0.54, 0.02, 0.28), t * _x(Vector3(-0.12, 1.352, 0.02), Vector3(22, 0, 0)), 0.006)
	b.add("paint:red" if state == "broken" else "trim:green", KitMesh.bevel_cylinder(0.11, 0.07, 0.02, 12), t * _x(Vector3(0.36, 1.31, 0.1), Vector3(22, 0, 0)))
	KitProps.vent(b, t * _x(Vector3(0, 0.3, 0.2)), Vector2(0.6, 0.4), "paint:main")
	b.decal("power", Vector2(0.24, 0.24), t * _x(Vector3(0.34, 0.75, 0.205)))
	b.rod("paint:accent", t * Vector3(-0.62, 0.16, -0.3), t * Vector3(-0.62, 2.3, -0.3), 0.06, 8)
	b.box("dark_steel", Vector3(0.3, 0.14, 0.4), t * _x(Vector3(-0.62, 2.33, -0.16)), 0.04)
	b.box("trim:warm", Vector3(0.22, 0.03, 0.3), t * _x(Vector3(-0.62, 2.255, -0.16)), 0.01)
	if state != "broken":
		b.lights.append({"pos": t * Vector3(-0.3, 2.0, 0.3), "color": KitMat.GLOW["warm"], "range": 6.0, "energy": 1.4})


static func _f(c: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = c.get(key, null)
	return float(v) if v is float or v is int else fallback


# --- Water tower (Landing Yard) --------------------------------------------------------------------

static func _water_tower(b: KitMesh.Builder, d: Data, state: String, c: Dictionary) -> void:
	var h: float = _f(c, "height", 11.0)       # deck height
	var r: float = _f(c, "radius", 3.2)        # tank radius
	var th: float = _f(c, "tank_height", 4.6)
	var s0: float = r * 0.84
	var s1: float = r * 0.62
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var at: Callable = func(i: int, y: float) -> Vector3:
		var cn: Vector2 = corners[i % 4]
		var w: float = lerpf(s0, s1, clampf(y / h, 0.0, 1.0))
		return Vector3(cn.x * w, y, cn.y * w)
	for i: int in 4:
		var ft: Vector3 = at.call(i, 0.0)
		b.box("concrete", Vector3(1.3, 0.5, 1.3), _x(ft + Vector3(0, 0.25, 0)), 0.08)
		b.box("dark_steel", Vector3(0.75, 0.1, 0.75), _x(ft + Vector3(0, 0.55, 0)), 0.03)
		b.rod("paint:accent", at.call(i, 0.5), at.call(i, h - 0.1), 0.2, 10)
		d.solids.append([ft + Vector3(0, 1.3, 0), Vector3(1.1, 2.6, 1.1)])
	var bays: int = 3
	for lv: int in bays:
		var y0: float = 1.0 + lv * (h - 1.6) / bays
		var y1: float = 1.0 + (lv + 1) * (h - 1.6) / bays
		for i: int in 4:
			b.rod("paint:accent", at.call(i, y1), at.call(i + 1, y1), 0.1, 8)
			if state == "broken" and (i + lv) % 5 == 0:
				continue
			b.rod("dark_steel", at.call(i, y0), at.call(i + 1, y1), 0.055, 6)
			b.rod("dark_steel", at.call(i + 1, y0), at.call(i, y1), 0.055, 6)
			var mid: Vector3 = ((at.call(i, y0) as Vector3) + (at.call(i + 1, y1) as Vector3) + (at.call(i + 1, y0) as Vector3) + (at.call(i, y1) as Vector3)) * 0.25
			b.add("dark_steel", KitMesh.bevel_cylinder(0.2, 0.09, 0.02, 8), KitMesh.look_y(mid * 0.985, Vector3(mid.x, 0, mid.z)))
	_deck(b, h, r + 0.85, state, 16)
	# The tank: a fat drum with bands and seams, a level gauge, a conical roof with a finial.
	var body := PackedVector3Array([Vector3(0, h + 0.02, 0), Vector3(r - 0.35, h + 0.02, 1), Vector3(r, h + 0.4, 1), Vector3(r, h + th, 1), Vector3(0, h + th, 0)])
	b.add("paint:main", KitMesh.lathe(body, 24), Transform3D.IDENTITY)
	for k: int in 3:
		b.cyl("paint:accent", r + 0.07, 0.24, _x(Vector3(0, h + 0.55 + k * (th - 1.0) / 2.0, 0)), 0.05, 24)
	for k: int in 12:
		b.box("paint:main", Vector3(0.1, th - 1.0, 0.08), _yaw(TAU * (k + 0.5) / 12.0) * _x(Vector3(0, h + th * 0.5 + 0.1, r)), 0.02)
	var roof := PackedVector3Array([Vector3(0, h + th - 0.06, 0), Vector3(r + 0.32, h + th - 0.06, 1), Vector3(r + 0.32, h + th + 0.12, 1), Vector3(r * 0.5, h + th + 1.25, 0), Vector3(0.32, h + th + 2.0, 1), Vector3(0.32, h + th + 2.3, 1), Vector3(0, h + th + 2.3, 0)])
	b.add("paint:accent", KitMesh.lathe(roof, 24), Transform3D.IDENTITY)
	b.cyl("dark_steel", 0.1, 0.9, _x(Vector3(0, h + th + 2.3, 0)), 0.02, 8)
	b.add("trim:red", KitMesh.bevel_cylinder(0.2, 0.3, 0.06, 10), _x(Vector3(0, h + th + 3.2, 0)))
	var gt: Transform3D = _yaw(deg_to_rad(38.0))
	var fill: float = {"broken": 0.25, "repaired": 0.6}.get(state, 1.0)
	b.box("dark_steel", Vector3(0.36, th - 1.2, 0.1), gt * _x(Vector3(0, h + th * 0.5 + 0.1, r + 0.03)), 0.03)
	b.box("trim:cool", Vector3(0.16, (th - 1.5) * fill, 0.05), gt * _x(Vector3(0, h + 0.85 + (th - 1.5) * fill * 0.5, r + 0.09)), 0.015)
	b.box("paint:accent", Vector3(2.9, 1.0, 0.5), _x(Vector3(0, h + th * 0.52, r - 0.19)), 0.05)
	b.decal("label_water", Vector2(2.4, 0.6), _x(Vector3(0, h + th * 0.52, r + 0.06)))
	# The fat down pipe to a valve wheel and a trough: this is where the water comes out.
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(0, h + 0.1, 0), Vector3(0, 1.2, 0), Vector3(0, 1.2, 2.5), Vector3(0, 0.62, 2.5)]), 0.3, "paint:pipe")
	b.rod("dark_steel", Vector3(0, 1.45, 1.2), Vector3(0, 2.0, 1.2), 0.06, 8)
	b.add("paint:red", KitMesh.bevel_cylinder(0.36, 0.08, 0.025, 14), _x(Vector3(0, 2.0, 1.2)))
	b.cyl("dark_steel", 0.08, 0.06, _x(Vector3(0, 2.08, 1.2)), 0.015, 8)
	b.box("concrete", Vector3(2.3, 0.55, 1.5), _x(Vector3(0, 0.275, 2.7)), 0.09)
	b.box("dirt" if state == "broken" else "paint:sky", Vector3(1.95, 0.04, 1.15), _x(Vector3(0, 0.555, 2.7)), 0.012)
	d.solids.append([Vector3(0, 0.65, 1.7), Vector3(1.0, 1.3, 3.6)])
	d.solids.append([Vector3(0, 0.3, 2.7), Vector3(2.3, 0.6, 1.5)])
	KitProps.ladder(b, _yaw(PI) * _x(Vector3(0, 0, s1 + 0.15)), h - 0.2)
	for sx: float in [-1.0, 1.0]:
		b.box("dark_steel", Vector3(0.5, 0.22, 0.4), _x(Vector3(sx * 1.3, h - 0.42, s1 + 0.5), Vector3(25, 0, 0)), 0.05)
		b.box("trim:warm", Vector3(0.4, 0.04, 0.3), _x(Vector3(sx * 1.3, h - 0.54, s1 + 0.55), Vector3(25, 0, 0)), 0.012)
	if state != "broken":
		b.lights.append({"pos": Vector3(0, h - 1.4, s1 + 1.6), "color": KitMat.GLOW["warm"], "range": 13.0, "energy": 2.0})
	if state == "broken":
		for k: int in 4:
			b.box("rusty", Vector3(0.9, 0.7, 0.06), _yaw(1.1 + k * 1.7) * _x(Vector3(0, h + 1.2 + (k % 3) * 0.9, r + 0.03), Vector3(0, 0, 8.0 * (k - 1.5))), 0.02)
		KitProps.debris(b, _x(Vector3(0, 0, -0.5)), s0 + 1.5, 10)
	elif state == "restored":
		for sx: float in [-1.0, 1.0]:
			KitProps.planter(b, _x(Vector3(sx * (s0 + 0.2), 0, s0 + 1.7)), 2.0, state)
	d.kiosk = Vector3(s0 + 1.9, 0, s0 + 1.2)
	d.top = Vector3(0, h + th + 3.6, 0)


# --- Windpump (Garden Row) -------------------------------------------------------------------------

static func _windpump(b: KitMesh.Builder, d: Data, state: String, c: Dictionary, pal: Dictionary, seed_: int) -> void:
	var h: float = _f(c, "height", 10.5)
	var wr: float = _f(c, "wheel_radius", 3.0)
	var s0: float = 1.9
	var s1: float = 0.42
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var at: Callable = func(i: int, y: float) -> Vector3:
		var cn: Vector2 = corners[i % 4]
		var w: float = lerpf(s0, s1, clampf(y / h, 0.0, 1.0))
		return Vector3(cn.x * w, y, cn.y * w)
	for i: int in 4:
		var ft: Vector3 = at.call(i, 0.0)
		b.box("concrete", Vector3(0.9, 0.4, 0.9), _x(ft + Vector3(0, 0.2, 0)), 0.07)
		b.rod("paint:accent", at.call(i, 0.35), at.call(i, h), 0.14, 8)
		d.solids.append([ft + Vector3(0, 1.1, 0), Vector3(0.7, 2.2, 0.7)])
	var bays: int = 4
	for lv: int in bays:
		var y0: float = 0.8 + lv * (h - 2.4) / bays
		var y1: float = 0.8 + (lv + 1) * (h - 2.4) / bays
		for i: int in 4:
			b.rod("paint:accent", at.call(i, y1), at.call(i + 1, y1), 0.075, 6)
			if state == "broken" and (i * 2 + lv) % 5 == 0:
				continue
			b.rod("steel", at.call(i, y0), at.call(i + 1, y1), 0.045, 5)
			b.rod("steel", at.call(i + 1, y0), at.call(i, y1), 0.045, 5)
	# Service deck near the top, the gearbox head on a turntable, the tail vane.
	var dy: float = h - 1.5
	b.box("dark_steel", Vector3(2.3, 0.1, 2.3), _x(Vector3(0, dy, 0)), 0.03)
	for i: int in 4:
		var p0 := Vector3(corners[i].x * 1.1, dy, corners[i].y * 1.1)
		var p1 := Vector3(corners[(i + 1) % 4].x * 1.1, dy, corners[(i + 1) % 4].y * 1.1)
		KitProps.railing(b, Transform3D.IDENTITY, p0, p1, 0.95, "paint:rail", state)
	b.cyl("dark_steel", 0.5, 0.3, _x(Vector3(0, h - 0.15, 0)), 0.05, 14)
	b.box("paint:main", Vector3(1.0, 0.95, 1.7), _x(Vector3(0, h + 0.6, 0.1)), 0.18, 2)
	b.box("paint:accent", Vector3(1.04, 0.2, 1.74), _x(Vector3(0, h + 0.68, 0.1)), 0.06)
	KitProps.vent(b, _x(Vector3(0.52, h + 0.25, 0.1), Vector3(0, 90, 0)), Vector2(0.7, 0.36), "paint:main")
	b.rod("dark_steel", Vector3(0, h + 0.55, 0.9), Vector3(0, h + 0.55, 1.3), 0.17, 12)
	b.rod("paint:accent", Vector3(0, h + 0.6, -0.7), Vector3(0, h + 0.85, -4.0), 0.09, 8)
	b.rod("steel", Vector3(0, h + 1.1, -0.6), Vector3(0, h + 1.4, -3.6), 0.03, 5)
	var vane: Transform3D = _x(Vector3(0, h + 0.95, -4.6), Vector3(4, 0, 0) if state != "broken" else Vector3(4, 0, 24))
	b.box("paint:accent", Vector3(0.09, 1.7, 2.0), vane, 0.035)
	b.box("paint:main", Vector3(0.11, 0.3, 2.04), vane * _x(Vector3(0, 0.55, 0)), 0.03)
	for sx: float in [-1.0, 1.0]:
		b.decal("logo", Vector2(0.9, 0.9), vane * _x(Vector3(sx * 0.05, -0.15, 0), Vector3(0, sx * 90.0, 0)))
	# The pump rod down the middle to a pump, its spout into a round stock tank.
	b.rod("steel", Vector3(0, h - 0.2, 0), Vector3(0, 1.5, 0), 0.05, 6)
	b.cyl("paint:pipe", 0.34, 1.5, _x(Vector3.ZERO), 0.06, 14)
	b.cyl("dark_steel", 0.4, 0.14, _x(Vector3(0, 1.5, 0)), 0.03, 14)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(0.3, 1.0, 0), Vector3(2.4, 1.0, 0), Vector3(2.4, 1.0, 1.2), Vector3(3.0, 1.45, 1.2)]), 0.13, "paint:pipe")
	var tk := Vector3(4.5, 0, 1.2)
	b.cyl("paint:main", 1.7, 1.15, _x(tk), 0.07, 22)
	for y: float in [0.22, 0.85]:
		b.cyl("paint:accent", 1.75, 0.14, _x(tk + Vector3(0, y, 0)), 0.03, 22)
	b.cyl("dark_steel", 1.6, 0.03, _x(tk + Vector3(0, 1.13, 0)), 0.01, 22)
	b.cyl("dirt" if state == "broken" else "paint:sky", 1.52, 0.03, _x(tk + Vector3(0, 1.145, 0)), 0.01, 22)
	d.solids.append([tk + Vector3(0, 0.6, 0), Vector3(3.0, 1.2, 3.0)])
	d.solids.append([Vector3(0, 0.8, 0), Vector3(0.8, 1.6, 0.8)])
	# The seed store: a low sealed vault with a round-topped hatch (the story's reason to come here).
	var vt: Transform3D = _x(Vector3(-3.7, 0, 1.2))
	b.box("concrete", Vector3(3.0, 0.3, 2.8), vt * _x(Vector3(0, 0.15, 0)), 0.06)
	b.box("paint:main", Vector3(2.5, 1.7, 2.2), vt * _x(Vector3(0, 1.1, -0.1)), 0.42, 3)
	b.box("paint:accent", Vector3(2.56, 0.22, 2.26), vt * _x(Vector3(0, 0.55, -0.1)), 0.07)
	KitProps.hatch(b, vt * _x(Vector3(0, 0.3, 1.0)), Vector2(0.9, 1.2), state)
	for sx: float in [-0.5, 0.5]:
		b.box("dark_steel", Vector3(0.07, 0.3, 0.07), vt * _x(Vector3(sx, 2.05, 0.3)), 0.015)
	b.box("paint:accent", Vector3(1.5, 0.46, 0.1), vt * _x(Vector3(0, 2.4, 0.3)), 0.03)
	b.decal("label_seeds", Vector2(1.28, 0.32), vt * _x(Vector3(0, 2.4, 0.35)))
	b.box("trim:green", Vector3(1.5, 0.05, 0.12), vt * _x(Vector3(0, 2.66, 0.3)), 0.015)
	d.solids.append([vt.origin + Vector3(0, 1.0, -0.1), Vector3(2.6, 2.0, 2.3)])
	if state == "broken":
		KitProps.debris(b, _x(Vector3(0, 0, 0.5)), 4.5, 10)
	else:
		for sx: float in [-1.0, 1.0]:
			KitProps.planter(b, _x(Vector3(sx * 1.4 - 3.7, 0, 3.2)), 1.6, state)
		b.lights.append({"pos": Vector3(0, h - 2.5, 1.5), "color": KitMat.GLOW["warm"], "range": 11.0, "energy": 1.6})
	d.kiosk = Vector3(0.2, 0, 3.6)
	d.top = Vector3(0, h + 0.55 + wr + 0.5, 1.3)
	# The fan wheel: its own mesh on the spin node (faces +Z, turns about Z).
	d.spin_at = Vector3(0, h + 0.55, 1.42)
	d.spin_axis = Vector3.BACK
	d.spin_speed = _f(c, "spin", 0.9)
	var blades: int = int(_f(c, "blades", 16.0))
	d.spin_mesh = KitMesh.cached("landmark:fan:%s:%.2f:%d:%d:%d" % [state, wr, blades, pal.hash(), seed_], func() -> Resource:
		var w := KitMesh.Builder.new(seed_ + 5, pal, state)
		var cone := PackedVector3Array([Vector3(0, -0.12, 0), Vector3(0.5, -0.12, 1), Vector3(0.52, 0.2, 0), Vector3(0.3, 0.6, 0), Vector3(0, 0.72, 0)])
		w.add("paint:accent", KitMesh.lathe(cone, 14), _x(Vector3.ZERO, Vector3(90, 0, 0)))
		for i: int in blades:
			if state == "broken" and (i == 3 or i == 4 or i == 11):
				continue
			var bt: Transform3D = _x(Vector3.ZERO, Vector3(0, 0, 360.0 * i / blades))
			var pitch := Vector3(0, 20, 0) if not (state == "broken" and i == 8) else Vector3(35, 20, 0)
			w.box("paint:main", Vector3(0.3, wr * 0.42, 0.05), bt * _x(Vector3(0, wr * 0.37, 0), pitch), 0.02)
			w.box("paint:main", Vector3(0.5, wr * 0.44, 0.05), bt * _x(Vector3(0, wr * 0.74, 0), pitch), 0.02)
			w.box("paint:accent", Vector3(0.52, wr * 0.09, 0.06), bt * _x(Vector3(0, wr * 0.955, 0), pitch), 0.02)
		_ring(w, "steel", Vector3.ZERO, Vector3.RIGHT, Vector3.UP, wr * 0.5, 0.045, 24)
		_ring(w, "steel", Vector3.ZERO, Vector3.RIGHT, Vector3.UP, wr * 0.9, 0.045, 28)
		return w.commit()) as ArrayMesh


# --- Gantry crane (Gantry Works) -------------------------------------------------------------------

static func _crane(b: KitMesh.Builder, d: Data, state: String, c: Dictionary) -> void:
	var span: float = _f(c, "span", 15.0)
	var ch: float = _f(c, "height", 12.0)  # underside of the girder
	var hx: float = span * 0.5
	var run: float = 8.6
	for s: float in [-1.0, 1.0]:
		var x: float = s * hx
		b.box("concrete", Vector3(1.5, 0.3, run + 0.8), _x(Vector3(x, 0.15, 0)), 0.06)
		b.box("steel", Vector3(0.2, 0.16, run + 0.4), _x(Vector3(x, 0.38, 0)), 0.04)
		for z: float in [-run * 0.5 - 0.1, run * 0.5 + 0.1]:
			b.box("hazard", Vector3(0.9, 0.7, 0.3), _x(Vector3(x, 0.65, z)), 0.06)
		# The bogie: a fat truck on four wheels.
		b.box("dark_steel", Vector3(1.0, 0.75, 5.8), _x(Vector3(x, 1.08, 0)), 0.12)
		b.box("hazard", Vector3(1.04, 0.24, 5.84), _x(Vector3(x, 0.84, 0)), 0.05)
		for z: float in [-2.1, -0.75, 0.75, 2.1]:
			b.add("steel", KitMesh.bevel_cylinder(0.42, 0.5, 0.06, 14), _x(Vector3(x - 0.25, 0.86, z), Vector3(0, 0, -90)))
		# A-frame legs up to the girder, tied half way up, a ladder on the left one.
		for sz: float in [-1.0, 1.0]:
			b.rod("paint:main", Vector3(x, 1.4, sz * 2.4), Vector3(x * 0.97, ch + 0.2, sz * 0.5), 0.36, 10)
			b.box("dark_steel", Vector3(0.95, 0.16, 0.95), _x(Vector3(x, 1.5, sz * 2.4)), 0.04)
		b.rod("paint:main", Vector3(x * 0.985, ch * 0.5 + 0.7, -1.45), Vector3(x * 0.985, ch * 0.5 + 0.7, 1.45), 0.17, 8)
		b.box("paint:accent", Vector3(1.1, 0.5, 2.2), _x(Vector3(x * 0.97, ch - 0.1, 0)), 0.1)
		d.solids.append([Vector3(x, 1.3, 0), Vector3(1.5, 2.6, run + 1.0)])
	KitProps.ladder(b, _x(Vector3(-hx * 0.985, 1.5, 2.72), Vector3(-9.5, 0, 0)), ch - 1.6)
	# The girder: a deep box beam with flanges, ribs, hazard ends and a walkway on top.
	var gy: float = ch + 0.95
	b.box("paint:main", Vector3(span + 2.6, 1.6, 1.5), _x(Vector3(0, gy, 0)), 0.12)
	for fy: float in [ch + 0.12, ch + 1.78]:
		b.box("paint:accent", Vector3(span + 2.8, 0.18, 1.74), _x(Vector3(0, fy, 0)), 0.05)
	var ribs: int = int(span / 1.5)
	for i: int in ribs + 1:
		var rx: float = -hx + i * span / ribs
		for sz: float in [-1.0, 1.0]:
			b.box("paint:main", Vector3(0.14, 1.44, 0.08), _x(Vector3(rx, gy, sz * 0.77)), 0.025)
	for s: float in [-1.0, 1.0]:
		b.box("hazard", Vector3(0.16, 1.5, 1.56), _x(Vector3(s * (hx + 1.3), gy, 0)), 0.04)
		b.add("trim:red", KitMesh.bevel_cylinder(0.14, 0.2, 0.04, 10), _x(Vector3(s * (hx + 1.0), ch + 1.87, 0)))
	KitProps.railing(b, Transform3D.IDENTITY, Vector3(-hx, ch + 1.87, -0.78), Vector3(hx, ch + 1.87, -0.78), 1.0, "paint:rail", state)
	b.decal("logo", Vector2(1.2, 1.2), _x(Vector3(-hx * 0.45, gy, 0.76)))
	b.decal("chevrons", Vector2(2.4, 0.8), _x(Vector3(hx * 0.5, gy, 0.76)))
	# The cab hangs under the girder by the left leg: a glass-fronted box.
	var cab := Vector3(-hx + 2.6, ch - 1.15, 0.5)
	b.box("paint:accent", Vector3(2.0, 2.0, 2.2), _x(cab), 0.2, 2)
	b.box("dark_steel", Vector3(1.7, 1.0, 0.1), _x(cab + Vector3(0, 0.15, 1.08)), 0.04)
	b.box("glass", Vector3(1.5, 0.82, 0.1), _x(cab + Vector3(0, 0.15, 1.11)), 0.03)
	b.box("paint:main", Vector3(2.1, 0.16, 2.3), _x(cab + Vector3(0, 1.0, 0)), 0.05)
	b.box("trim:warm", Vector3(1.2, 0.05, 0.08), _x(cab + Vector3(0, -0.6, 1.1)), 0.015)
	# The trolley, hoist drum, cables, hook block and hook; the hull plates it lifts.
	var tx: float = hx * 0.28
	b.box("paint:accent", Vector3(2.4, 0.6, 2.3), _x(Vector3(tx, ch - 0.28, 0)), 0.1)
	b.add("dark_steel", KitMesh.bevel_cylinder(0.42, 1.6, 0.05, 14), _x(Vector3(tx, ch - 0.72, -0.8), Vector3(90, 0, 0)))
	for sx: float in [-1.0, 1.0]:
		b.add("steel", KitMesh.bevel_cylinder(0.3, 0.3, 0.05, 12), _x(Vector3(tx + sx * 0.9, ch - 0.05, 1.0), Vector3(90, 0, 0)))
	var lifted: bool = state != "broken"
	var hook_y: float = ch * 0.55 if lifted else ch * 0.62
	for sx: float in [-0.3, 0.3]:
		b.rod("steel", Vector3(tx + sx, ch - 0.7, 0), Vector3(tx + sx, hook_y + 0.6, 0), 0.04, 6)
	b.box("hazard", Vector3(1.1, 0.75, 0.55), _x(Vector3(tx, hook_y + 0.3, 0)), 0.1)
	b.add("dark_steel", KitMesh.bevel_cylinder(0.3, 0.6, 0.04, 12), _x(Vector3(tx, hook_y + 0.3, -0.3), Vector3(90, 0, 0)))
	b.tube("dark_steel", PackedVector3Array([Vector3(tx, hook_y, 0), Vector3(tx, hook_y - 0.55, 0), Vector3(tx + 0.3, hook_y - 0.85, 0), Vector3(tx + 0.55, hook_y - 0.6, 0), Vector3(tx + 0.5, hook_y - 0.35, 0)]), 0.1, 8, 0.2)
	var load_y: float = hook_y - 3.2 if lifted else 0.3
	var lt: Transform3D = _x(Vector3(tx, load_y, 0.0)) if lifted else _x(Vector3(tx + 0.6, load_y, 0.4), Vector3(0, 18, 6))
	for k: int in 3:
		b.box("paint:#e9e4d6" if k != 1 else "paint:accent", Vector3(4.4 - k * 0.25, 0.16, 2.6 - k * 0.1), lt * _x(Vector3(k * 0.08, k * 0.2, 0), Vector3(0, k * 2.0, 0)), 0.05)
		for rx: float in [-1.4, 0.0, 1.4]:
			b.box("dark_steel", Vector3(0.12, 0.05, 2.4 - k * 0.1), lt * _x(Vector3(rx + k * 0.08, k * 0.2 + 0.1, 0), Vector3(0, k * 2.0, 0)), 0.012)
	if lifted:
		for cx: float in [-1.9, 1.9]:
			for cz: float in [-1.1, 1.1]:
				b.rod("steel", Vector3(tx + 0.35, hook_y - 0.8, 0), lt * Vector3(cx, 0.55, cz), 0.03, 5)
	else:
		d.solids.append([Vector3(tx + 0.6, 0.45, 0.4), Vector3(4.4, 0.9, 2.8)])
		KitProps.debris(b, _x(Vector3(-2.0, 0, 0.5)), 5.0, 12)
	for sx: float in [-1.0, 1.0]:
		b.box("dark_steel", Vector3(0.6, 0.24, 0.5), _x(Vector3(sx * hx * 0.55, ch - 0.1, 0.95), Vector3(30, 0, 0)), 0.06)
		b.box("trim:warm", Vector3(0.5, 0.04, 0.4), _x(Vector3(sx * hx * 0.55, ch - 0.24, 1.02), Vector3(30, 0, 0)), 0.012)
		if state != "broken":
			b.lights.append({"pos": Vector3(sx * hx * 0.55, ch - 1.5, 1.6), "color": KitMat.GLOW["warm"], "range": 15.0, "energy": 2.0})
	if state == "restored":
		KitProps.crate_stack(b, _x(Vector3(-hx + 2.4, 0, 2.6)), 4, state)
	d.kiosk = Vector3(hx - 2.2, 0, run * 0.5 + 0.2)
	d.top = Vector3(0, ch + 2.2, 0)


# --- Signal mast (Signal Heights) ------------------------------------------------------------------

static func _radio_mast(b: KitMesh.Builder, d: Data, state: String, c: Dictionary, pal: Dictionary, seed_: int) -> void:
	var h: float = _f(c, "height", 26.0)
	var r0: float = 1.15
	var r1: float = 0.42
	var rad: Callable = func(y: float) -> float: return lerpf(r0, r1, clampf((y - 1.6) / (h - 1.6), 0.0, 1.0))
	b.cyl("concrete", 3.0, 0.6, _x(Vector3.ZERO, Vector3(0, 22.5, 0)), 0.1, 8)
	b.cyl("hazard", 1.6, 0.14, _x(Vector3(0, 0.6, 0)), 0.03, 16)
	var body := PackedVector3Array([Vector3(0, 0.6, 0), Vector3(1.4, 0.6, 1), Vector3(1.4, 1.1, 1), Vector3(r0, 1.6, 0), Vector3(r1, h, 0), Vector3(r1 + 0.1, h + 0.1, 1), Vector3(r1 + 0.1, h + 0.35, 1), Vector3(0, h + 0.35, 0)])
	b.add("paint:main", KitMesh.lathe(body, 16), Transform3D.IDENTITY)
	var nb: int = 4
	for k: int in nb:
		var y0: float = 3.0 + k * (h - 4.0) / nb
		var y1: float = y0 + (h - 4.0) / nb * 0.5
		_band(b, "paint:accent", y0, y1, (rad.call(y0) as float) + 0.03, (rad.call(y1) as float) + 0.03, 16)
	for a: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:  # bolted gussets round the foot
		b.box("dark_steel", Vector3(0.14, 1.3, 1.0), _yaw(a) * _x(Vector3(0, 1.25, 1.55), Vector3(-18, 0, 0)), 0.03)
	KitProps.hatch(b, _yaw(deg_to_rad(-60.0)) * _x(Vector3(0, 0.6, 1.38)), Vector2(0.8, 1.7), state)
	d.solids.append([Vector3(0, 2.0, 0), Vector3(3.4, 4.0, 3.4)])
	# Two ring decks, three dishes on arms, the halo ring that glows when the mast is awake.
	for dk: float in [h * 0.36, h * 0.66]:
		_deck(b, dk, (rad.call(dk) as float) + 1.25, state, 12)
		for a: float in [0.6, 2.7, 4.8]:
			b.rod("dark_steel", _yaw(a) * Vector3(0, dk - 1.2, (rad.call(dk - 1.2) as float) - 0.05), _yaw(a) * Vector3(0, dk - 0.22, (rad.call(dk) as float) + 1.0), 0.06, 6)
	var dishes: Array = [[h * 0.44, 0.0, 2.0], [h * 0.56, 2.3, 1.3], [h * 0.76, -2.0, 1.5]]
	for ds: Array in dishes:
		var y: float = ds[0]
		var t: Transform3D = _yaw(float(ds[1]))
		var rr: float = rad.call(y)
		b.box("dark_steel", Vector3(0.3, 0.3, 1.2), t * _x(Vector3(0, y, rr + 0.5)), 0.06)
		b.cyl("paint:accent", 0.34, 0.5, t * _x(Vector3(0, y - 0.25, rr + 1.0)), 0.06, 12)
		KitProps.dish(b, t * _x(Vector3(0, y + 0.1, rr + 1.05)), float(ds[2]), state, false)
	var hy: float = h - 2.2
	for a: float in [0.3, 2.4, 4.5]:
		b.rod("steel", _yaw(a) * Vector3(0, hy - 0.5, (rad.call(hy) as float)), _yaw(a) * Vector3(0, hy, 1.7), 0.045, 6)
	_ring(b, "dark_steel", Vector3(0, hy, 0), Vector3.RIGHT, Vector3.BACK, 1.7, 0.09, 28, 8)
	_ring(b, "trim:cool", Vector3(0, hy + 0.1, 0), Vector3.RIGHT, Vector3.BACK, 1.7, 0.05, 28, 6)
	for k: int in 3:
		b.box("paint:main", Vector3(0.34, 1.7, 0.16), _yaw(TAU * k / 3.0 + 0.5) * _x(Vector3(0, h - 4.2, (rad.call(h - 4.2) as float) + 0.22)), 0.05)
	for k: int in 3:  # whips on the halo ring (the top itself belongs to the turning radar)
		var wa: float = TAU * k / 3.0 + 1.3
		var wd := Vector3(cos(wa), 0, sin(wa))
		var lean: Vector3 = wd * (1.5 if state == "broken" and k == 1 else 0.2)
		b.rod("steel", wd * 1.7 + Vector3(0, hy, 0), wd * 1.7 + lean + Vector3(0, hy + 2.4 + k * 0.5, 0), 0.04, 5)
	# The equipment hut at the foot, with a cable tray up to the mast, and three guy anchors.
	var ht: Transform3D = _x(Vector3(4.9, 0, -0.6))
	b.box("concrete", Vector3(3.2, 0.3, 2.8), ht * _x(Vector3(0, 0.15, 0)), 0.06)
	b.box("paint:main", Vector3(2.7, 2.3, 2.3), ht * _x(Vector3(0, 1.45, 0)), 0.16, 2)
	b.box("paint:accent", Vector3(2.9, 0.22, 2.5), ht * _x(Vector3(0, 2.66, 0)), 0.07)
	KitProps.hatch(b, ht * _x(Vector3(0.5, 0.3, 1.15)), Vector2(0.85, 1.75), state)
	KitProps.vent(b, ht * _x(Vector3(-0.75, 1.3, 1.15)), Vector2(0.7, 0.5))
	b.decal("label_power", Vector2(0.9, 0.225), ht * _x(Vector3(-0.75, 2.1, 1.16)))
	for k: int in 3:
		b.box("trim:green" if k != 1 else "trim:warm", Vector3(0.08, 0.08, 0.03), ht * _x(Vector3(-1.0 + k * 0.16, 1.0, 1.165)), 0.01)
	KitProps.cable(b, Transform3D.IDENTITY, Vector3(3.6, 2.7, -0.6), Vector3(0.9, 5.0, -0.2), 0.7, 0.05)
	d.solids.append([ht.origin + Vector3(0, 1.4, 0), Vector3(2.9, 2.8, 2.5)])
	for k: int in 3:
		var ga: float = TAU * k / 3.0 + 2.6
		var an := Vector3(cos(ga) * 6.0, 0, sin(ga) * 6.0)
		b.box("concrete", Vector3(1.1, 0.7, 1.1), _x(an + Vector3(0, 0.35, 0), Vector3(0, rad_to_deg(-ga), 0)), 0.08)
		b.box("hazard", Vector3(1.12, 0.14, 1.12), _x(an + Vector3(0, 0.66, 0), Vector3(0, rad_to_deg(-ga), 0)), 0.03)
		if not (state == "broken" and k == 2):
			KitProps.cable(b, Transform3D.IDENTITY, an + Vector3(0, 0.75, 0), Vector3(cos(ga) * 0.6, h * 0.62, sin(ga) * 0.6), 0.25, 0.04)
		d.solids.append([an + Vector3(0, 0.4, 0), Vector3(1.1, 0.8, 1.1)])
	if state == "broken":
		KitProps.debris(b, _x(Vector3(0, 0, 3.0)), 3.5, 10)
	else:
		b.lights.append({"pos": Vector3(0, hy + 0.2, 1.7), "color": KitMat.GLOW["cool"], "range": 12.0, "energy": 1.4})
		if state == "restored":
			KitProps.planter(b, _x(Vector3(-3.3, 0, 2.6), Vector3(0, 30, 0)), 2.0, state)
	d.kiosk = Vector3(0.6, 0, 4.4)
	d.top = Vector3(0, h + 2.1, 0)
	# A little radar bar on the very top that turns when the mast is awake.
	d.spin_at = Vector3(0, h + 0.35, 0)
	d.spin_axis = Vector3.UP
	d.spin_speed = _f(c, "spin", 0.7)
	d.spin_mesh = KitMesh.cached("landmark:radar:%s:%d" % [state, pal.hash()], func() -> Resource:
		var w := KitMesh.Builder.new(seed_ + 9, pal, state)
		w.cyl("dark_steel", 0.2, 0.5, Transform3D.IDENTITY, 0.04, 10)
		w.box("paint:accent", Vector3(2.4, 0.6, 0.14), _x(Vector3(0, 0.75, 0.05), Vector3(-8, 0, 0)), 0.05)
		for sx: float in [-1.0, 1.0]:
			w.box("paint:accent", Vector3(0.5, 0.6, 0.14), _x(Vector3(sx * 1.4, 0.75, 0.17), Vector3(-8, sx * -28.0, 0)), 0.05)
		w.rod("steel", Vector3(0, 0.6, 0.1), Vector3(0, 0.75, 0.9), 0.03, 5)
		w.box("dark_steel", Vector3(0.16, 0.16, 0.16), _x(Vector3(0, 0.75, 0.9)), 0.03)
		w.cyl("dark_steel", 0.1, 0.3, _x(Vector3(0, 1.05, 0.0)), 0.02, 8)
		w.add("trim:red", KitMesh.bevel_cylinder(0.16, 0.26, 0.05, 10), _x(Vector3(0, 1.35, 0)))
		return w.commit()) as ArrayMesh


# --- Big wheel (Fairground) ------------------------------------------------------------------------

static func _ferris(b: KitMesh.Builder, d: Data, state: String, c: Dictionary, pal: Dictionary, seed_: int) -> void:
	var r: float = _f(c, "radius", 8.5)
	var n: int = int(_f(c, "gondolas", 12.0))
	var hy: float = r + 3.1
	var hz: float = 1.9
	# The boarding platform with steps, hazard nose and a striped ticket booth.
	b.box("concrete", Vector3(13.0, 0.5, 5.4), _x(Vector3(0, 0.25, 0)), 0.1)
	b.box("hazard", Vector3(13.04, 0.1, 0.3), _x(Vector3(0, 0.46, 2.56)), 0.03)
	KitProps.stairs(b, _yaw(PI) * _x(Vector3(0, 0, -3.5)), 0.5, 0.8, 1.8, "paint:rail", state)
	d.solids.append([Vector3(0, 0.25, 0), Vector3(13.0, 0.5, 5.4)])
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			var ft := Vector3(sx * 4.8, 0.5, sz * (hz + 0.5))
			b.box("dark_steel", Vector3(1.1, 0.2, 1.1), _x(ft + Vector3(0, 0.1, 0)), 0.05)
			b.rod("paint:accent", ft + Vector3(0, 0.15, 0), Vector3(sx * 0.25, hy, sz * hz), 0.3, 10)
			d.solids.append([ft + Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 1.0)])
		b.rod("paint:accent", Vector3(-3.25, 4.0, sz * (hz + 0.33)), Vector3(3.25, 4.0, sz * (hz + 0.33)), 0.15, 8)
		b.add("paint:main", KitMesh.bevel_cylinder(1.0, 0.5, 0.1, 18), _x(Vector3(0, hy, sz * (hz + 0.1)), Vector3(sz * 90.0, 0, 0)))
		b.decal("logo", Vector2(1.1, 1.1), _x(Vector3(0, hy, sz * (hz + 0.61)), Vector3(0, 0.0 if sz > 0.0 else 180.0, 0)))
	b.rod("dark_steel", Vector3(0, hy, -hz), Vector3(0, hy, hz), 0.45, 14)
	# The drive: a motor house on the platform with a belt up to the axle.
	b.box("paint:main", Vector3(1.9, 1.5, 1.3), _x(Vector3(2.6, 1.25, -2.0)), 0.14, 2)
	b.box("paint:accent", Vector3(2.0, 0.2, 1.4), _x(Vector3(2.6, 2.05, -2.0)), 0.06)
	KitProps.vent(b, _yaw(PI) * _x(Vector3(-2.6, 0.8, 2.65)), Vector2(0.9, 0.6))
	b.decal("label_power", Vector2(0.9, 0.225), _x(Vector3(2.6, 1.7, -2.655), Vector3(0, 180, 0)))
	d.solids.append([Vector3(2.6, 1.3, -2.0), Vector3(2.0, 1.7, 1.4)])
	var booth: Transform3D = _x(Vector3(-7.6, 0.0, 1.2))
	b.box("concrete", Vector3(2.3, 0.16, 2.2), booth * _x(Vector3(0, 0.08, 0.1)), 0.04)
	b.box("paint:main", Vector3(1.6, 2.0, 1.4), booth * _x(Vector3(0, 1.0, 0)), 0.12, 2)
	b.box("dark_steel", Vector3(1.1, 0.7, 0.08), booth * _x(Vector3(0, 1.35, 0.7)), 0.03)
	b.box("glass", Vector3(0.95, 0.56, 0.08), booth * _x(Vector3(0, 1.35, 0.73)), 0.02)
	b.box("paint:accent", Vector3(1.3, 0.1, 0.34), booth * _x(Vector3(0, 0.95, 0.82)), 0.03)
	for k: int in 6:  # the striped awning
		b.box("paint:accent" if k % 2 == 0 else "paint:main", Vector3(0.3, 0.07, 1.0), booth * _x(Vector3(-0.75 + k * 0.3, 2.12, 0.55), Vector3(18, 0, 0)), 0.02)
	b.box("paint:accent", Vector3(1.9, 0.2, 1.6), booth * _x(Vector3(0, 2.1, -0.05)), 0.07)
	d.solids.append([booth.origin + Vector3(0, 1.0, 0), Vector3(1.7, 2.0, 1.5)])
	if state == "broken":
		b.box("paint:" + str(c.get("gondola_a", "yellow")), Vector3(1.5, 0.85, 1.3), _x(Vector3(2.6, 0.95, 1.4), Vector3(18, 30, 62)), 0.18, 2)
		KitProps.debris(b, _x(Vector3(1.5, 0.5, 1.2)), 3.5, 10)
	else:
		for sx: float in [-1.0, 1.0]:
			KitProps.lamp_post(b, _x(Vector3(sx * 6.1, 0.5, 2.3), Vector3(0, 180, 0)), 4.2, state)
	d.kiosk = Vector3(-2.2, 0, 3.7)
	d.top = Vector3(0, hy + r + 0.6, 0)
	# The wheel: two rims, spokes, cross axles for the gondolas and a ring of fair lights.
	d.spin_at = Vector3(0, hy, 0)
	d.spin_axis = Vector3.BACK
	d.spin_speed = _f(c, "spin", 0.12)
	d.spin_mesh = KitMesh.cached("landmark:wheel:%s:%.2f:%d:%d" % [state, r, n, pal.hash()], func() -> Resource:
		var w := KitMesh.Builder.new(seed_ + 3, pal, state)
		for sz: float in [-1.0, 1.0]:
			var cz := Vector3(0, 0, sz * 1.05)
			_ring(w, "paint:main", cz, Vector3.RIGHT, Vector3.UP, r, 0.17, 40, 8)
			_ring(w, "paint:main", cz, Vector3.RIGHT, Vector3.UP, r * 0.55, 0.1, 32, 6)
			for i: int in n:
				var a: float = TAU * i / n
				var dir := Vector3(cos(a), sin(a), 0)
				w.rod("paint:accent", cz + dir * 0.7, cz + dir * r, 0.085, 6)
				var a2: float = TAU * (i + 0.5) / n
				w.rod("steel", cz + dir * (r * 0.55), cz + Vector3(cos(a2), sin(a2), 0) * r, 0.04, 5)
			for i: int in n * 3:
				var la: float = TAU * (i + 0.5) / (n * 3)
				if state == "broken" and i % 4 == 1:
					continue
				w.add("trim:warm", KitMesh.bevel_cylinder(0.1, 0.1, 0.03, 8), _x(cz + Vector3(cos(la), sin(la), 0) * r + Vector3(0, 0, sz * 0.15), Vector3(sz * 90.0, 0, 0)), 0.5, 0.0)
		for i: int in n:
			var a3: float = TAU * i / n
			var dir3 := Vector3(cos(a3), sin(a3), 0)
			w.rod("steel", dir3 * r + Vector3(0, 0, -1.05), dir3 * r + Vector3(0, 0, 1.05), 0.07, 6)
		w.rod("paint:main", Vector3(0, 0, -1.3), Vector3(0, 0, 1.3), 0.85, 16)
		return w.commit()) as ArrayMesh
	# Gondolas (origin at the pivot on the rim's axle): two colours, drawn as two MultiMeshes.
	d.gondola_r = r
	d.gondola_n = n
	if state == "broken":
		d.gondola_skip = [2, 7, 8]
	for key: String in ["gondola_a", "gondola_b"]:
		var gc: String = str(c.get(key, "yellow" if key == "gondola_a" else "teal"))
		d.gondola_meshes.append(KitMesh.cached("landmark:gondola:%s:%s:%d" % [state, gc, pal.hash()], func() -> Resource:
			var g := KitMesh.Builder.new(seed_ + 11, pal, state)
			g.box("paint:" + gc, Vector3(1.5, 0.8, 1.3), _x(Vector3(0, -1.75, 0)), 0.2, 2)
			g.box("paint:main", Vector3(1.54, 0.14, 1.34), _x(Vector3(0, -1.42, 0)), 0.05)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					g.rod("steel", Vector3(sx * 0.62, -1.4, sz * 0.52), Vector3(sx * 0.62, -0.62, sz * 0.52), 0.04, 5)
			var roofp := PackedVector3Array([Vector3(0, -0.66, 0), Vector3(0.98, -0.66, 1), Vector3(0.98, -0.56, 1), Vector3(0.25, -0.28, 0), Vector3(0, -0.28, 0)])
			g.add("paint:" + gc, KitMesh.lathe(roofp, 12), Transform3D.IDENTITY)
			g.rod("steel", Vector3(0, -0.3, 0), Vector3(0, 0.0, 0), 0.06, 6)
			g.box("dark_steel", Vector3(0.2, 0.2, 0.5), _x(Vector3.ZERO), 0.05)
			return g.commit()) as ArrayMesh)


# --- Tall stack (Stack Works) ----------------------------------------------------------------------

static func _smokestack(b: KitMesh.Builder, d: Data, state: String, c: Dictionary) -> void:
	var h: float = _f(c, "height", 26.0)
	var r0: float = 2.0
	var r1: float = 1.3
	var rad: Callable = func(y: float) -> float: return lerpf(r0, r1, clampf((y - 2.8) / (h - 2.8), 0.0, 1.0))
	b.cyl("concrete", 3.0, 0.8, _x(Vector3.ZERO, Vector3(0, 22.5, 0)), 0.12, 8)
	var body := PackedVector3Array([Vector3(0, 0.8, 0), Vector3(2.35, 0.8, 1), Vector3(2.35, 2.2, 1), Vector3(r0, 2.8, 0), Vector3(r1, h, 0), Vector3(r1 + 0.22, h + 0.15, 1), Vector3(r1 + 0.22, h + 0.75, 1), Vector3(r1 - 0.15, h + 0.75, 1), Vector3(r1 - 0.15, h + 0.1, 0), Vector3(0, h + 0.1, 0)])
	b.add("paint:main", KitMesh.lathe(body, 20), Transform3D.IDENTITY)
	b.cyl("dark_steel", r1 - 0.16, 0.05, _x(Vector3(0, h + 0.12, 0)), 0.01, 20)
	_band(b, "hazard", h - 2.6, h - 0.9, (rad.call(h - 2.6) as float) + 0.03, (rad.call(h - 0.9) as float) + 0.03)
	for y: float in [h * 0.3, h * 0.72]:
		_band(b, "paint:accent", y, y + 1.5, (rad.call(y) as float) + 0.03, (rad.call(y + 1.5) as float) + 0.03)
	for k: int in 10:  # buttress ribs round the foot
		b.box("paint:main", Vector3(0.22, 1.7, 0.3), _yaw(TAU * k / 10.0) * _x(Vector3(0, 1.65, 2.32)), 0.06)
	var dk: float = h * 0.52
	_deck(b, dk, (rad.call(dk) as float) + 1.2, state, 14)
	var taper: float = rad_to_deg(atan2(r0 - (rad.call(dk) as float), dk - 2.8))
	KitProps.ladder(b, _yaw(deg_to_rad(140.0)) * _x(Vector3(0, 2.2, r0 + 0.32), Vector3(-taper, 0, 0)), dk - 2.3)
	for k: int in 4:
		var la: float = TAU * k / 4.0 + 0.4
		b.add("trim:red", KitMesh.bevel_cylinder(0.14, 0.22, 0.04, 8), _x(Vector3(cos(la) * (r1 + 0.1), h + 0.75, sin(la) * (r1 + 0.1))))
	d.solids.append([Vector3(0, 2.2, 0), Vector3(4.7, 4.4, 4.7)])
	# The boiler house on the right with a fat flue duct into the stack.
	var hs: Transform3D = _x(Vector3(5.6, 0, -0.2))
	b.box("concrete", Vector3(5.6, 0.3, 4.6), hs * _x(Vector3(0, 0.15, 0)), 0.06)
	b.box("dark_steel", Vector3(5.0, 3.4, 4.0), hs * _x(Vector3(0, 2.0, 0)), 0.1)
	KitMesh.panel_wall(b, 5.0, 3.4, hs * _x(Vector3(-2.5, 0.3, 2.0)), {"key": "paint:accent", "panel": Vector2(1.25, 1.13), "missing": 0.2 if state == "broken" else 0.0, "patch": 0.25 if state == "repaired" else 0.0, "hazard": true, "trim": "trim:warm"})
	b.box("paint:main", Vector3(5.3, 0.26, 4.3), hs * _x(Vector3(0, 3.83, 0)), 0.08)
	KitProps.hatch(b, hs * _x(Vector3(-1.2, 0.3, 2.12)), Vector2(1.1, 2.0), state)
	KitProps.vent(b, hs * _x(Vector3(1.3, 3.96, 0.4), Vector3(-90, 0, 0)), Vector2(1.0, 0.8))
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(4.6, 3.9, -0.2), Vector3(4.6, 6.2, -0.2), Vector3(1.5, 6.2, -0.2)]), 0.62, "paint:accent")
	d.solids.append([hs.origin + Vector3(0, 2.0, 0), Vector3(5.2, 4.0, 4.3)])
	# The fuel tanks on the left, piped into the stack's foot: they are still full.
	KitProps.tank(b, _x(Vector3(-4.6, 0, 1.2)), 1.5, 4.2, "paint:accent", state)
	KitProps.tank(b, _x(Vector3(-4.9, 0, -2.6)), 1.2, 3.4, "paint:accent", state)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(-3.1, 1.3, 1.2), Vector3(-2.3, 1.3, 1.2)]), 0.16, "paint:pipe")
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(-3.9, 1.0, -2.2), Vector3(-2.8, 1.0, -2.2), Vector3(-2.8, 1.0, -0.6), Vector3(-2.2, 1.0, -0.6)]), 0.13, "paint:pipe")
	for tk: Array in [[Vector3(-4.6, 0.3, 2.75), 1.0], [Vector3(-4.9, 0.3, -1.35), 0.75]]:
		var fill: float = {"broken": 0.9, "repaired": 0.9}.get(state, 1.0)
		b.box("dark_steel", Vector3(0.3, float(tk[1]) * 2.2, 0.08), _x((tk[0] as Vector3) + Vector3(0, float(tk[1]) * 1.6, 0)), 0.03)
		b.box("trim:warm", Vector3(0.14, float(tk[1]) * 2.0 * fill, 0.05), _x((tk[0] as Vector3) + Vector3(0, float(tk[1]) * 1.6, 0.05)), 0.015)
	d.solids.append([Vector3(-4.6, 2.2, 1.2), Vector3(3.0, 4.4, 3.0)])
	d.solids.append([Vector3(-4.9, 1.8, -2.6), Vector3(2.4, 3.6, 2.4)])
	if state == "broken":
		KitProps.debris(b, _x(Vector3(0, 0, 3.6)), 4.0, 12)
		KitProps.barrel(b, _x(Vector3(-2.2, 0, 3.4)), "paint:barrel", true)
	else:
		for k: int in 3:
			KitProps.barrel(b, _x(Vector3(-2.4 + k * 0.7, 0, 3.3 + (k % 2) * 0.3)))
		b.lights.append({"pos": Vector3(0, h + 1.5, 0), "color": KitMat.GLOW["red"], "range": 10.0, "energy": 1.2})
	d.kiosk = Vector3(1.0, 0, 4.6)
	d.top = Vector3(0, h + 1.3, 0)
