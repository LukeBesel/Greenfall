class_name FutureLayer
extends Node3D
## The Future Layer: as a district is restored it builds up into a clean, glowing city.
## Per hex (HexLevels 0..5): Clean -> light seams in the ground; Planted/Growing -> glowing
## planters and floating seed-lanterns; Sustained -> holo way-signs and light orbs; Thriving ->
## brighter seams, light strips on nearby buildings, holo billboards, hover platforms with light
## bridges, and drones. Per district (score from cleaned share, hex levels and the hub level):
## rooflines and beacons on the skyline, white glass spires rising in the distance, holo ads in
## the sky, hover traffic on the roads and an aurora at night.
## Everything is derived from seed + levels (plan() is pure and deterministic; no save data).
## Cheap: a handful of MultiMeshes (unshaded emissive; the environment glow does the halo),
## a few Label3D texts, no lights. New pieces draw in / flicker on via a per-instance birth time.

const CYAN := Color(0.62, 0.88, 1.0)  # soft sky-blue light
const TEAL := Color(0.7, 1.0, 0.85)  # mint
const MAGENTA := Color(1.0, 0.88, 0.7)  # warm white (was neon magenta)
const ICE := Color(0.62, 0.86, 1.0)
const AMBER := Color(1.0, 0.72, 0.32)
const LIME := Color(0.62, 1.0, 0.42)
const VIOLET := Color(0.85, 0.92, 1.0)  # pale (was violet)

## Kinds understood by art/shaders/light_seam.gdshader.
const K_PULSE := 0.0
const K_CALM := 1.0
const K_BOB := 2.0
const K_BLINK := 3.0
const K_DRIFT := 4.0
const K_STEADY := 5.0

# l10n:begin
const MESSAGES: Array[String] = [
	"GROW TOGETHER", "THANK YOU, PATCH", "EVERY SEED COUNTS", "TOMORROW IS GROWING",
	"HELLO, NEIGHBOR!", "CLEAN AIR TODAY  98%", "FRESH SPROUTS DAILY", "SOLAR GRID  100%",
	"OPEN SKY  OPEN HEARTS", "WATER IS LIFE", "NEXT GLIDER  2 MIN", "BUILT BY HANDS & BOTS",
]
# l10n:end
# l10n:begin
const SKY_MESSAGES: Array[String] = [
	"WELCOME TO THE NEW GREENFALL", "THE CITY IS BREATHING AGAIN", "PLANT SOMETHING TODAY",
	"SKYWAY OPEN  ALL ABOARD", "TOGETHER WE BLOOM", "LIGHT  WATER  LIFE",
]
# l10n:end

## Static instance channels: name -> [mesh id, material id, casts shadow].
const CHANNELS: Dictionary = {
	"line": ["box", "light", false], "orb": ["sphere", "light", false], "sign": ["quad", "holo", false],
	"post": ["post", "white", true], "planter": ["ring", "white", true], "platform": ["slab", "white", true],
	"spire": ["spire", "glass", false], "pane": ["box", "pane", false],
	"beam": ["box", "white", true],
}

var world: Node
var field: HexField
var layout: CityLayout
var _slots: Dictionary = {}  # hid -> PackedVector3Array of plant slot positions
var _mmi: Dictionary = {}  # channel -> MultiMeshInstance3D
var _mats: Dictionary = {}
var _meshes: Dictionary = {}
var _known: Dictionary = {}  # element key -> birth time on _clock
var _labels: Dictionary = {}  # key -> Label3D
var _movers: Array = []
var _mover_mm: Dictionary = {}
var _aurora: MeshInstance3D
var _aurora_mat: ShaderMaterial
var _clock: float = 0.0
var _built: bool = false
var _dirty: bool = false
var _since_build: float = 0.0
var _poll: float = 0.0
var _sig: Vector2i = Vector2i(-1, -1)  # (hub level, cleaned count) at last build
var last_plan: Dictionary = {}


func setup(p_world: Node) -> void:
	world = p_world
	field = world.field
	layout = world.layout
	var g: Garden = world.get("garden") as Garden
	if g:
		for hid: int in g.hex_slots:
			var ps := PackedVector3Array()
			for s: int in g.hex_slots[hid]:
				ps.append(g.slot_pos[s])
			_slots[hid] = ps
	_make_resources()
	EventBus.hex_level_changed.connect(_on_level_changed)
	rebuild()
	if DevHooks.has("future"):  # preview: start with the air already as clear as the district earns
		var sd: Node = world.get("sky_director")
		if sd:
			sd.set("haze", minf(float(sd.get("haze")), 1.0 - smoothstep(0.2, 1.0, float(last_plan.get("score", 0.0))) * 0.7))


# --- Inputs ------------------------------------------------------------------------------

func _levels() -> Dictionary:
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	return hl.levels if hl else {}


func _hub_level() -> int:
	var h: Hub = world.get("hub") as Hub
	return h.level if h else 1


func _cleaned_frac() -> float:
	return float(field.cleaned_count) / float(maxi(field.junk_hex_count, 1))


## 0 (dusty) .. 1 (fully built-up future district).
static func district_score(levels: Dictionary, hub_level: int, cleaned_frac: float) -> float:
	var sum: float = 0.0
	for id: int in levels:
		sum += float(levels[id])
	var mean: float = sum / float(maxi(levels.size(), 1))
	return clampf(0.2 * cleaned_frac + 0.3 * float(clampi(hub_level, 1, 5) - 1) / 4.0 + 0.5 * mean / 5.0, 0.0, 1.0)


# --- Plan (pure data) ---------------------------------------------------------------------

static func _h(a: int, b: int = 0, c: int = 0) -> float:
	return float(hash(Vector3i(a, b, c)) & 0xFFFFFF) / 16777216.0


static func _key(tag: int, a: int, b: int = 0, c: int = 0) -> int:
	return hash([tag, a, b, c])


static func _new_plan() -> Dictionary:
	var p: Dictionary = {"labels": [], "movers": [], "aurora": 0.0, "score": 0.0}
	for ch: String in CHANNELS:
		p[ch] = {"xf": [], "col": [], "cus": [], "key": []}  # plain Arrays: packed ones copy out of a Dictionary
	return p


static func _add(p: Dictionary, ch: String, xf: Transform3D, col: Color, kind: float, en: float, key: int, seed_: float = -1.0) -> void:
	var c: Dictionary = p[ch]
	# Thin, delicate light lines and small orbs (owner: thin glowing lines are fine, nothing thick).
	if ch == "line":
		xf.basis.y *= 0.35
		xf.basis.z *= 0.35
	elif ch == "orb":
		xf.basis = xf.basis.scaled(Vector3.ONE * 0.65)
	(c["xf"] as Array).append(xf)
	(c["col"] as Array).append(col)
	# Toned down: futuristic accents are soft light, not neon (owner: "not that Tron-like").
	var soft: float = 0.35 if ch in ["line", "seam"] else 0.55
	(c["cus"] as Array).append(Color(_h(key) * 10.0 if seed_ < 0.0 else seed_, kind, en * soft, 0.0))
	(c["key"] as Array).append(key)


## A holo panel: the shader lays out icon and frame from the panel's aspect (colour alpha).
static func _sign(p: Dictionary, pos: Vector3, yaw: float, w: float, hgt: float, tint: Color, icon: float, en: float, key: int) -> Transform3D:
	var xf: Transform3D = _panel_xf(pos, yaw, w, hgt)
	_add(p, "sign", xf, Color(tint.r, tint.g, tint.b, w / hgt), icon, en, key)
	return xf


## A thin box from a to b (unit box x axis runs a -> b, so lines draw in from a).
static func seg_xf(a: Vector3, b: Vector3, thick: float, wide: float) -> Transform3D:
	var x: Vector3 = b - a
	var len_v: float = maxf(x.length(), 0.001)
	var xd: Vector3 = x / len_v
	var ref: Vector3 = Vector3.UP if absf(xd.y) < 0.9 else Vector3.RIGHT
	var zd: Vector3 = xd.cross(ref).normalized()
	var yd: Vector3 = zd.cross(xd).normalized()
	return Transform3D(Basis(xd * len_v, yd * thick, zd * wide), (a + b) * 0.5)


static func _orb_xf(pos: Vector3, d: float, flat: float = 1.0) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(d, d * flat, d)), pos)


static func _panel_xf(pos: Vector3, yaw: float, w: float, hgt: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, hgt, 1.0)), pos)


static func corner(c: Vector3, r: float, i: int) -> Vector3:
	var a: float = deg_to_rad(60.0 * i - 30.0)
	return c + Vector3(cos(a) * r, 0.0, sin(a) * r)


static func _ground(lay: CityLayout, p: Vector3, lift: float) -> Vector3:
	return Vector3(p.x, (lay.height_at(p.x, p.z) if lay else 0.0) + lift, p.z)


static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## Everything the layer shows for these inputs. Deterministic; counts never shrink as levels rise.
static func plan(fld: HexField, lay: CityLayout, levels: Dictionary, hub_level: int, cleaned_frac: float, slots: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _new_plan()
	var s: float = district_score(levels, hub_level, cleaned_frac)
	p["score"] = s
	var ids: Array = levels.keys()
	ids.sort()
	var thriving: Array[int] = []
	for hid: int in ids:
		var lv: int = int(levels[hid])
		if lv >= 1:
			_plan_hex(p, fld, lay, hid, lv, slots.get(hid, PackedVector3Array()))
		if lv >= 5:
			thriving.append(hid)
	_plan_thriving(p, fld, lay, thriving)
	_plan_buildings(p, fld, lay, levels, s)
	_plan_roads(p, fld, lay, levels)
	_plan_hub(p, hub_level)
	_plan_skyline(p, fld, lay, s)
	return p


static func _plan_hex(p: Dictionary, fld: HexField, lay: CityLayout, hid: int, lv: int, slots: PackedVector3Array) -> void:
	var c: Vector3 = fld.hex_center(hid)
	var r: float = fld.hex_size
	var seam_en: float = [0.0, 1.15, 1.35, 1.5, 1.7, 2.0][lv]
	# No seams along the hex edges: the ground itself now shows clean ground with an organic
	# border (HexField.border_warp), and ruler-straight light lines fought that.
	if lv < 2:
		return
	# Planted: circuit traces from the centre, corner nodes, glowing planters and seed-lanterns.
	var rot: int = 1 if _h(hid, 2) < 0.5 else 0
	var inr: float = r * 0.866
	var spokes: Array = [0, 2, 4]
	for sp: int in spokes:
		var ang: float = deg_to_rad(60.0 * (sp + rot))
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var pa: Vector3 = _ground(lay, c + d * 0.45, 0.025)
		var pb: Vector3 = _ground(lay, c + d * inr * 0.62, 0.025)
		pb.y = pa.y
		_add(p, "line", seg_xf(pa, pb, 0.02, 0.04), TEAL, K_PULSE, seam_en * 0.6, _key(2, hid, sp))
	for e: int in 6:
		if lv >= 4 and e % 2 == 0:
			_add(p, "orb", _orb_xf(_ground(lay, corner(c, r - 0.14, e), 0.03), 0.16, 0.5), ICE, K_STEADY, 2.6, _key(3, hid, e))
	_add(p, "orb", _orb_xf(_ground(lay, c, 0.03), 0.22, 0.4), CYAN, K_STEADY, 2.4, _key(3, hid, 9))
	if lv >= 3:
		for e: int in 6:
			var a2: Vector3 = _ground(lay, corner(c, r * 0.3, e), 0.025)
			var b2: Vector3 = corner(c, r * 0.3, e + 1)
			b2.y = a2.y
			_add(p, "line", seg_xf(a2, b2, 0.02, 0.04), TEAL, K_CALM, seam_en * 0.6, _key(4, hid, e))
	var n_plant: int = 1 if lv == 2 else 2
	var order: Array = range(slots.size())
	order.sort_custom(func(i: int, j: int) -> bool: return _h(hid, i, 7) < _h(hid, j, 7))
	for k: int in mini(n_plant, order.size()):
		var sp_pos: Vector3 = slots[int(order[k])]
		_add(p, "planter", Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), sp_pos), Color.WHITE, 0.0, 1.0, _key(5, hid, k))
		var rim: Color = LIME if _h(hid, k, 5) < 0.5 else TEAL
		for e: int in 6:
			var a3: Vector3 = corner(sp_pos, 0.52, e) + Vector3(0, 0.2, 0)
			var b3: Vector3 = corner(sp_pos, 0.52, e + 1) + Vector3(0, 0.2, 0)
			_add(p, "line", seg_xf(a3, b3, 0.03, 0.04), rim, K_CALM, 1.7, _key(6, hid, k, e))
	var n_lant: int = [0, 0, 2, 4, 4, 5][lv]
	for k: int in n_lant:
		var ang2: float = _h(hid, k, 11) * TAU
		var rr: float = (0.25 + 0.5 * _h(hid, k, 12)) * r
		var pos: Vector3 = _ground(lay, c + Vector3(cos(ang2) * rr, 0, sin(ang2) * rr), 1.3 + 1.3 * _h(hid, k, 13))
		_add(p, "orb", _orb_xf(pos, 0.15, 1.25), AMBER if _h(hid, k, 14) < 0.6 else LIME, K_DRIFT, 3.2, _key(7, hid, k))
	if lv < 4:
		return
	# Sustained: a holo way-sign on a slim white post and floating light orbs.
	if _h(hid, 20) < 0.6:
		var ang3: float = _h(hid, 21) * TAU
		var sp2: Vector3 = _ground(lay, c + Vector3(cos(ang3), 0, sin(ang3)) * r * 0.5, 0.0)
		if not lay or lay.surface_at(sp2.x, sp2.z) != CityLayout.Surface.BUILDING:
			_add(p, "post", Transform3D(Basis.from_scale(Vector3(0.07, 1.75, 0.07)), sp2 + Vector3(0, 0.875, 0)), Color.WHITE, 0.0, 1.0, _key(8, hid))
			var yaw: float = _h(hid, 22) * TAU
			var icon: float = 1.0 + floorf(_h(hid, 23) * 6.0)
			var tint: Color = [CYAN, TEAL, MAGENTA, ICE][int(_h(hid, 24) * 4.0)]
			var key_s: int = _key(9, hid)
			_sign(p, sp2 + Vector3(0, 2.3, 0), yaw, 1.3, 0.9, tint, icon, 2.2, key_s)
			_add(p, "orb", _orb_xf(sp2 + Vector3(0, 1.77, 0), 0.1), tint, K_STEADY, 3.0, _key(10, hid))
	for k: int in 2:
		var ang4: float = _h(hid, k, 30) * TAU
		var pos2: Vector3 = _ground(lay, c + Vector3(cos(ang4), 0, sin(ang4)) * r * 0.55, 2.6 + 1.2 * _h(hid, k, 31))
		_add(p, "orb", _orb_xf(pos2, 0.3), ICE if k == 0 else CYAN, K_BOB, 3.4, _key(11, hid, k))


static func _plan_thriving(p: Dictionary, fld: HexField, lay: CityLayout, thriving: Array[int]) -> void:
	var plats: Array[Vector3] = []
	var n_board: int = 0
	var n_drone: int = 0
	for hid: int in thriving:
		var c: Vector3 = fld.hex_center(hid)
		var base_y: float = lay.height_at(c.x, c.z) if lay else 0.0
		# Hover platform: a white hex slab with a lit rim and an underglow.
		if _h(hid, 40) < 0.24:
			var hy: float = base_y + 3.8 + 1.6 * _h(hid, 41)
			var pc := Vector3(c.x, hy, c.z)
			plats.append(pc)
			_add(p, "platform", Transform3D(Basis.from_scale(Vector3(1.25, 1.0, 1.25)), pc), Color.WHITE, 0.0, 1.0, _key(12, hid))
			for e: int in 6:
				_add(p, "line", seg_xf(corner(pc, 1.3, e) + Vector3(0, 0.02, 0), corner(pc, 1.3, e + 1) + Vector3(0, 0.02, 0), 0.05, 0.05), CYAN, K_PULSE, 3.0, _key(13, hid, e))
			_add(p, "orb", _orb_xf(pc - Vector3(0, 0.16, 0), 1.6, 0.06), CYAN, K_STEADY, 2.0, _key(14, hid))
			_add(p, "orb", _orb_xf(pc + Vector3(0, 0.95, 0), 0.32), MAGENTA, K_BOB, 3.4, _key(15, hid))
		# Floating halo rings: light-only hexes that hover and bob over the meadow.
		if _h(hid, 51) < 0.4:
			var hr_y: float = base_y + 2.6 + 1.2 * _h(hid, 52)
			var hc := Vector3(c.x, hr_y, c.z) + Vector3(_h(hid, 53) - 0.5, 0, _h(hid, 54) - 0.5) * fld.hex_size * 0.8
			var hseed: float = _h(hid, 55) * 10.0
			var hcol: Color = MAGENTA if _h(hid, 56) < 0.4 else CYAN
			for e: int in 6:
				_add(p, "line", seg_xf(corner(hc, 0.75, e), corner(hc, 0.75, e + 1), 0.05, 0.05), hcol, 6.0, 2.2, _key(21, hid, e), hseed)
		# Holo billboard with a friendly message on a tall white post.
		if _h(hid, 42) < 0.2 and n_board < 14:
			var ang: float = _h(hid, 43) * TAU
			var bp: Vector3 = c + Vector3(cos(ang), 0, sin(ang)) * fld.hex_size * 0.35
			bp.y = base_y
			if not lay or lay.surface_at(bp.x, bp.z) != CityLayout.Surface.BUILDING:
				var yaw: float = _yaw_to(bp, Vector3.ZERO) if bp.length() > 1.0 else 0.0
				_add(p, "post", Transform3D(Basis.from_scale(Vector3(0.12, 3.3, 0.12)), bp + Vector3(0, 1.65, 0)), Color.WHITE, 0.0, 1.0, _key(16, hid))
				var key_b: int = _key(17, hid)
				var tint: Color = [CYAN, MAGENTA, TEAL][n_board % 3]
				var pxf: Transform3D = _sign(p, bp + Vector3(0, 4.15, 0), yaw, 2.9, 1.5, tint, 0.0, 1.9, key_b)
				(p["labels"] as Array).append({"key": key_b, "xf": pxf, "w": 2.9, "h": 1.5, "text": MESSAGES[int(_h(hid, 44) * MESSAGES.size())], "col": tint})
				_add(p, "line", seg_xf(bp + Vector3(-1.45, 3.37, 0).rotated(Vector3.UP, yaw), bp + Vector3(1.45, 3.37, 0).rotated(Vector3.UP, yaw), 0.05, 0.05), tint, K_PULSE, 3.0, _key(18, hid))
				n_board += 1
		# Drones circling the thriving blocks.
		if _h(hid, 45) < 0.3 and n_drone < 18:
			(p["movers"] as Array).append({"type": 0, "c": Vector3(c.x, base_y + 4.5 + 2.5 * _h(hid, 46), c.z), "r": 3.0 + 4.0 * _h(hid, 47),
				"speed": (0.25 + 0.2 * _h(hid, 48)) * (1.0 if _h(hid, 49) < 0.5 else -1.0), "phase": _h(hid, 50) * TAU, "key": _key(19, hid),
				"col": CYAN if n_drone % 3 != 2 else MAGENTA})
			n_drone += 1
	# Light bridges between nearby platforms.
	for i: int in plats.size():
		for j: int in range(i + 1, plats.size()):
			var d: float = Vector2(plats[i].x - plats[j].x, plats[i].z - plats[j].z).length()
			if d > 12.5:
				continue
			var dir: Vector3 = (plats[j] - plats[i]).normalized()
			var side: Vector3 = dir.cross(Vector3.UP).normalized() * 0.32
			var a: Vector3 = plats[i] + dir * 1.15
			var b: Vector3 = plats[j] - dir * 1.15
			_add(p, "line", seg_xf(a + side, b + side, 0.04, 0.07), CYAN, K_PULSE, 2.8, _key(20, i, j, 0))
			_add(p, "line", seg_xf(a - side, b - side, 0.04, 0.07), CYAN, K_PULSE, 2.8, _key(20, i, j, 1))
			_add(p, "line", seg_xf(a - Vector3(0, 0.05, 0), b - Vector3(0, 0.05, 0), 0.015, 0.6), ICE, K_CALM, 0.7, _key(20, i, j, 2))


## Light strips on building rooflines / corners / floor bands, beacons on tall roofs.
static func _plan_buildings(p: Dictionary, fld: HexField, lay: CityLayout, levels: Dictionary, s: float) -> void:
	if lay == null:
		return
	for bd: Dictionary in lay.all_buildings():
		var r: Rect2 = bd["rect"]
		var sd: int = int(bd["seed"]) & 0x7FFFFFFF
		var floors: int = int(bd["floors"])
		var top: float = floors * 3.0
		# Thriving neighbours: sample around the footprint.
		var near5: bool = false
		var rc: Vector2 = r.get_center()
		if rc.length() < fld.hex_size * fld.radius * 2.0 + 12.0:
			var g: Rect2 = r.grow(3.5)
			for q: Vector2 in [g.position, g.end, Vector2(g.position.x, g.end.y), Vector2(g.end.x, g.position.y), g.get_center(),
					Vector2(rc.x, g.position.y), Vector2(rc.x, g.end.y), Vector2(g.position.x, rc.y), Vector2(g.end.x, rc.y)]:
				if int(levels.get(fld.hex_at(Vector3(q.x, 0, q.y)), 0)) >= 5:
					near5 = true
					break
		var roof: bool = near5 or _h(sd, 1) < s * 1.15 - 0.08
		if not roof or (bool(bd["ruined"]) and not near5):
			continue
		var pal: float = _h(sd, 2)
		var col: Color = CYAN if pal < 0.55 else (MAGENTA if pal < 0.78 else (ICE if pal < 0.9 else VIOLET))
		var o: float = 0.14
		var cs: Array[Vector3] = [Vector3(r.position.x - o, 0, r.position.y - o), Vector3(r.end.x + o, 0, r.position.y - o),
			Vector3(r.end.x + o, 0, r.end.y + o), Vector3(r.position.x - o, 0, r.end.y + o)]
		var ry: float = top + (0.45 if bool(bd["ruined"]) else 0.9)
		if bool(bd["ruined"]):
			ry = maxf(3.0, top - 6.0)
		for e: int in 4:
			_add(p, "line", seg_xf(cs[e] + Vector3(0, ry, 0), cs[(e + 1) % 4] + Vector3(0, ry, 0), 0.08, 0.08), col, K_CALM, 1.7, _key(30, sd, e))
		if near5 or _h(sd, 3) < s - 0.3:
			for e: int in 4:
				_add(p, "line", seg_xf(cs[e] + Vector3(0, 0.4, 0), cs[e] + Vector3(0, ry, 0), 0.1, 0.1), col, K_PULSE, 1.9, _key(31, sd, e))
			# Floor bands on the street face, every other floor.
			var f: Vector2 = bd["face"]
			var a: Vector3
			var b: Vector3
			if absf(f.y) > 0.5:
				var z: float = (r.position.y - o) if f.y < 0 else (r.end.y + o)
				a = Vector3(r.position.x - o, 0, z)
				b = Vector3(r.end.x + o, 0, z)
			else:
				var x: float = (r.position.x - o) if f.x < 0 else (r.end.x + o)
				a = Vector3(x, 0, r.position.y - o)
				b = Vector3(x, 0, r.end.y + o)
			var fl: int = 2
			while fl < floors and fl * 3.0 < ry - 1.0:
				_add(p, "line", seg_xf(a + Vector3(0, fl * 3.0, 0), b + Vector3(0, fl * 3.0, 0), 0.04, 0.04), TEAL if pal < 0.5 else col, K_PULSE, 1.3, _key(32, sd, fl))
				fl += 2
		# Glass sky-terraces along every side that looks onto a street: white edge beam and rail,
		# glass deck and balustrade, a light strip underneath.
		if near5 and not bool(bd["ruined"]) and floors >= 3:
			for side: int in 4:
				var fc2: Vector2 = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)][side]
				var smid: Vector2 = rc + Vector2(fc2.x * r.size.x, fc2.y * r.size.y) * 0.5
				var probe: Vector2 = smid + fc2 * 4.0
				if lay.surface_at(probe.x, probe.y) not in [CityLayout.Surface.ROAD, CityLayout.Surface.SIDEWALK]:
					continue
				var dep: float = 1.5
				var ty: float = 6.1
				var along2 := Vector2(absf(fc2.y), absf(fc2.x)) * ((r.size.x if absf(fc2.y) > 0.5 else r.size.y) * 0.5 - 0.4)
				var c2: Vector2 = smid + fc2 * dep * 0.5
				var a0 := Vector3(c2.x - along2.x, ty, c2.y - along2.y)
				var a1 := Vector3(c2.x + along2.x, ty, c2.y + along2.y)
				var out3 := Vector3(fc2.x, 0, fc2.y) * dep * 0.5
				_add(p, "pane", seg_xf(a0, a1, 0.08, dep), Color.WHITE, 0.0, 1.0, _key(38, sd, side, 0))
				_add(p, "pane", seg_xf(a0 + out3 + Vector3(0, 0.55, 0), a1 + out3 + Vector3(0, 0.55, 0), 1.0, 0.05), Color.WHITE, 0.0, 1.0, _key(38, sd, side, 1))
				_add(p, "beam", seg_xf(a0 + out3 + Vector3(0, 1.05, 0), a1 + out3 + Vector3(0, 1.05, 0), 0.09, 0.09), Color.WHITE, 0.0, 1.0, _key(38, sd, side, 2))
				_add(p, "beam", seg_xf(a0 + out3, a1 + out3, 0.14, 0.12), Color.WHITE, 0.0, 1.0, _key(38, sd, side, 3))
				_add(p, "line", seg_xf(a0 + out3 - Vector3(0, 0.1, 0), a1 + out3 - Vector3(0, 0.1, 0), 0.05, 0.06), col, K_PULSE, 2.2, _key(38, sd, side, 4))
		# Tall holo banner hanging on the street face of buildings next to thriving ground.
		if (near5 or _h(sd, 5) < s - 0.55) and _h(sd, 6) < 0.7 and floors >= 3:
			var fc: Vector2 = bd["face"]
			var span: float = (r.size.x if absf(fc.y) > 0.5 else r.size.y)
			var bh: float = minf(ry - 4.0, 10.0)
			var off: float = (_h(sd, 7) - 0.5) * maxf(span - 3.0, 0.0)
			var along := Vector2(1, 0) if absf(fc.y) > 0.5 else Vector2(0, 1)
			var face_pt: Vector2 = rc + Vector2(fc.x * r.size.x, fc.y * r.size.y) * 0.5 + fc * 0.35 + along * off
			var byaw: float = atan2(fc.x, fc.y)
			var btint: Color = [CYAN, MAGENTA, TEAL, VIOLET][int(_h(sd, 8) * 4.0)]
			_sign(p, Vector3(face_pt.x, 3.0 + bh * 0.5, face_pt.y), byaw, 2.0, bh, btint, 1.0 + floorf(_h(sd, 9) * 6.0), 1.7, _key(35, sd))
		if floors >= 5 and (near5 or _h(sd, 4) < s):
			var mp: Vector3 = Vector3(rc.x, ry, rc.y)
			_add(p, "post", Transform3D(Basis.from_scale(Vector3(0.12, 3.0, 0.12)), mp + Vector3(0, 1.5, 0)), Color.WHITE, 0.0, 1.0, _key(33, sd))
			_add(p, "orb", _orb_xf(mp + Vector3(0, 3.15, 0), 0.55), MAGENTA if pal < 0.5 else CYAN, K_BLINK, 5.0, _key(34, sd))


## Tron lanes: once the ground beside a road is sustained, its curbs and centre line light up.
static func _plan_roads(p: Dictionary, fld: HexField, lay: CityLayout, levels: Dictionary) -> void:
	# Glowing road lanes removed: they made the city read as Tron rather than a bright, natural future.
	if true or lay == null or lay.wild:
		return
	var reach: float = fld.hex_size * (fld.radius + 1) * 1.75
	var half: float = CityLayout.PITCH * 0.5
	var edge: float = CityLayout.ROAD_W * 0.5 - 0.3
	var step: float = 3.0
	for axis: int in 2:
		var k: int = -int(reach / CityLayout.PITCH) - 1
		while k <= int(reach / CityLayout.PITCH):
			var road: float = k * CityLayout.PITCH + half
			k += 1
			if absf(road) > reach:
				continue
			var t: float = -reach
			var i: int = 0
			while t < reach:
				var a: float = t
				var b: float = t + step
				t = b
				i += 1
				var mid: float = (a + b) * 0.5
				var mp: Vector3 = Vector3(road, 0, mid) if axis == 0 else Vector3(mid, 0, road)
				if lay.surface_at(mp.x, mp.z) != CityLayout.Surface.ROAD:
					continue
				var lv: int = int(levels.get(fld.hex_at(mp), 0))
				if lv < 4:
					continue
				for side: int in 2:
					var off: float = edge * (1.0 if side == 0 else -1.0)
					var pa: Vector3 = Vector3(road + off, 0.02, a) if axis == 0 else Vector3(a, 0.02, road + off)
					var pb: Vector3 = Vector3(road + off, 0.02, b) if axis == 0 else Vector3(b, 0.02, road + off)
					_add(p, "line", seg_xf(pa, pb, 0.03, 0.14), CYAN if lv >= 5 else TEAL, K_PULSE, 1.9, _key(36, axis, int(road), i * 2 + side))
				# Light pylons on the sidewalks (slim white poles, glowing tips) and, now and then,
				# a holo gate spanning the road with a friendly message.
				if lv >= 5 and i % 4 == 0:
					@warning_ignore("integer_division")  # [health]
					var sgn: float = 1.0 if (i / 4) % 2 == 0 else -1.0
					var lo: float = CityLayout.ROAD_W * 0.5 + 1.0
					var pp: Vector3 = Vector3(road + lo * sgn, CityLayout.CURB_H, mid) if axis == 0 else Vector3(mid, CityLayout.CURB_H, road + lo * sgn)
					_add(p, "post", Transform3D(Basis.from_scale(Vector3(0.09, 5.0, 0.09)), pp + Vector3(0, 2.5, 0)), Color.WHITE, 0.0, 1.0, _key(39, axis, int(road), i))
					_add(p, "line", seg_xf(pp + Vector3(0, 0.3, 0), pp + Vector3(0, 4.9, 0), 0.03, 0.11), CYAN if sgn > 0.0 else MAGENTA, K_PULSE, 1.8, _key(39, axis, int(road), i + 1))
					_add(p, "orb", _orb_xf(pp + Vector3(0, 5.15, 0), 0.26), ICE, K_STEADY, 1.8, _key(39, axis, int(road), i + 2))
				if lv >= 5 and i % 8 == 4 and _h(axis, int(road), i) < 0.55:
					var gy: float = 8.6
					var gw: float = CityLayout.ROAD_W + 1.6
					var g0: Vector3 = Vector3(road - gw * 0.5, 0.0, mid) if axis == 0 else Vector3(mid, 0.0, road - gw * 0.5)
					var g1: Vector3 = Vector3(road + gw * 0.5, 0.0, mid) if axis == 0 else Vector3(mid, 0.0, road + gw * 0.5)
					for gp: Vector3 in [g0, g1]:
						_add(p, "post", Transform3D(Basis.from_scale(Vector3(0.22, gy + 1.6, 0.22)), gp + Vector3(0, (gy + 1.6) * 0.5, 0)), Color.WHITE, 0.0, 1.0, _key(26, int(gp.x * 10.0), int(gp.z * 10.0)))
						_add(p, "line", seg_xf(gp + Vector3(0, 0.4, 0), gp + Vector3(0, gy + 1.5, 0), 0.05, 0.3), CYAN, K_PULSE, 2.0, _key(27, int(gp.x * 10.0), int(gp.z * 10.0)))
					var gyaw: float = 0.0 if axis == 0 else PI * 0.5
					var gkey: int = _key(28, axis, int(road), i)
					@warning_ignore("integer_division")  # [health]
					var gtint: Color = [CYAN, MAGENTA, TEAL][(i / 8) % 3]
					var gxf: Transform3D = _sign(p, (g0 + g1) * 0.5 + Vector3(0, gy + 0.8, 0), gyaw, gw - 0.5, 1.5, gtint, 0.0, 2.6, gkey)
					(p["labels"] as Array).append({"key": gkey, "xf": gxf, "w": gw - 0.5, "h": 1.5, "text": MESSAGES[int(_h(axis, int(road), i + 7) * MESSAGES.size())], "col": gtint})
					_add(p, "beam", seg_xf(g0 + Vector3(0, gy, 0), g1 + Vector3(0, gy, 0), 0.14, 0.14), Color.WHITE, 0.0, 1.0, _key(29, axis, int(road), i))
					_add(p, "line", seg_xf(g0 + Vector3(0, gy - 0.1, 0), g1 + Vector3(0, gy - 0.1, 0), 0.05, 0.08), gtint, K_PULSE, 2.4, _key(29, axis, int(road), i + 1))
					_add(p, "beam", seg_xf(g0 + Vector3(0, gy + 1.6, 0), g1 + Vector3(0, gy + 1.6, 0), 0.1, 0.1), Color.WHITE, 0.0, 1.0, _key(29, axis, int(road), i + 2))
				if i % 2 == 0:
					var ca: Vector3 = Vector3(road, 0.02, a + 0.6) if axis == 0 else Vector3(a + 0.6, 0.02, road)
					var cb: Vector3 = Vector3(road, 0.02, b - 0.6) if axis == 0 else Vector3(b - 0.6, 0.02, road)
					_add(p, "line", seg_xf(ca, cb, 0.03, 0.18), MAGENTA if lv >= 5 else ICE, K_CALM, 1.7, _key(37, axis, int(road), i))


## The base gets its own accents as the hub levels up.
static func _plan_hub(p: Dictionary, hub_level: int) -> void:
	if hub_level < 2:
		return
	var y0: float = 0.03
	var hh: float = CityLayout.YARD_HALF - 0.35
	var cs: Array[Vector3] = [Vector3(-hh, y0, -hh), Vector3(hh, y0, -hh), Vector3(hh, y0, hh), Vector3(-hh, y0, hh)]
	for e: int in 4:
		_add(p, "line", seg_xf(cs[e], cs[(e + 1) % 4], 0.012, 0.025), CYAN, K_CALM, 1.1, _key(40, e))  # thin and quiet
	if hub_level >= 3:
		var masts: Array = [0, 2] if hub_level < 5 else [0, 1, 2, 3]
		for m: int in masts:
			var mp: Vector3 = cs[m] * Vector3(0.96, 0.0, 0.96)
			_add(p, "post", Transform3D(Basis.from_scale(Vector3(0.22, 7.5, 0.22)), mp + Vector3(0, 3.75, 0)), Color.WHITE, 0.0, 1.0, _key(41, m))
			for side: int in 2:
				var off := Vector3(0.13 if side == 0 else -0.13, 0, 0.0)
				_add(p, "line", seg_xf(mp + off + Vector3(0, 0.3, 0), mp + off + Vector3(0, 7.4, 0), 0.04, 0.04), CYAN if side == 0 else MAGENTA, K_PULSE, 3.0, _key(42, m, side))
			_add(p, "orb", _orb_xf(mp + Vector3(0, 7.75, 0), 0.5), MAGENTA, K_BLINK, 5.0, _key(43, m))
			var yaw: float = _yaw_to(mp, Vector3.ZERO)
			_sign(p, mp + Vector3(0, 5.2, 0) + Vector3(sin(yaw), 0, cos(yaw)) * 0.5, yaw, 1.4, 1.4, TEAL, 6.0, 2.2, _key(44, m))
	if hub_level >= 4:
		for ring: int in 2:
			var rad: float = 3.6 - ring * 0.8
			var ry: float = 24.0 + ring * 0.6
			for k: int in 12:
				var a := Vector3(cos(TAU * k / 12.0) * rad, ry, sin(TAU * k / 12.0) * rad)
				var b := Vector3(cos(TAU * (k + 1) / 12.0) * rad, ry, sin(TAU * (k + 1) / 12.0) * rad)
				_add(p, "line", seg_xf(a, b, 0.09, 0.09), CYAN if ring == 0 else MAGENTA, K_PULSE, 3.2, _key(45, ring, k))
	if hub_level >= 5:
		_add(p, "line", seg_xf(Vector3(0, 24.6, 0), Vector3(0, 170.0, 0), 0.14, 0.14), CYAN, K_PULSE, 1.8, _key(46, 0))
		_add(p, "orb", _orb_xf(Vector3(0, 24.3, 0), 1.1), ICE, K_BLINK, 4.0, _key(48, 0))


## Far city: white glass hex spires rising, holo ads in the sky, hover traffic, aurora.
static func _plan_skyline(p: Dictionary, fld: HexField, lay: CityLayout, s: float) -> void:
	var seed_v: int = fld.seed_value
	var n_spire: int = int(round(smoothstep(0.12, 1.0, s) * 30.0))
	for i: int in n_spire:
		var ang: float = TAU * fmod(i * 0.381966 + _h(seed_v, i, 60) * 0.05, 1.0)
		var dist: float = 185.0 + 140.0 * _h(seed_v, i, 61)
		var base := Vector3(cos(ang) * dist, -1.0, sin(ang) * dist)
		var w: float = 7.0 + 6.0 * _h(seed_v, i, 62)
		var hgt: float = 80.0 + 130.0 * _h(seed_v, i, 63)
		_add(p, "spire", Transform3D(Basis.from_scale(Vector3(w, hgt, w)), base + Vector3(0, hgt * 0.5, 0)), Color.WHITE, 0.0, 1.0, _key(50, i))
		var col: Color = CYAN if i % 3 != 1 else MAGENTA
		for e: int in 6:
			if e % 2 == 1 and i % 2 == 0:
				continue
			var a: Vector3 = corner(base, w * 0.5 * 1.02, e)
			var b: Vector3 = corner(base + Vector3(0, hgt, 0), w * 0.5 * 0.55 * 1.04, e)
			_add(p, "line", seg_xf(a, b, 0.5, 0.5), col, K_PULSE, 2.6, _key(51, i, e))
		var band: float = 22.0
		var k: int = 1
		while band * k < hgt - 6.0:
			var y: float = band * k
			var rr: float = w * 0.5 * lerpf(1.0, 0.55, y / hgt) * 1.04
			for e: int in 6:
				_add(p, "line", seg_xf(corner(base + Vector3(0, y, 0), rr, e), corner(base + Vector3(0, y, 0), rr, e + 1), 0.4, 0.4), ICE, K_CALM, 1.6, _key(52, i, k, e))
			k += 1
		var top: Vector3 = base + Vector3(0, hgt, 0)
		_add(p, "line", seg_xf(top, top + Vector3(0, 18.0, 0), 0.3, 0.3), ICE, K_CALM, 2.0, _key(53, i))
		_add(p, "orb", _orb_xf(top + Vector3(0, 18.5, 0), 2.2), col, K_BLINK, 6.0, _key(54, i))
		if _h(seed_v, i, 64) < 0.45:
			var hr: float = w * 0.7
			for e: int in 6:
				_add(p, "line", seg_xf(corner(top + Vector3(0, 7, 0), hr, e), corner(top + Vector3(0, 7, 0), hr, e + 1), 0.35, 0.35), col, K_PULSE, 3.0, _key(55, i, e))
	# Holo ads hanging in the sky, facing the base.
	var n_ads: int = int(floor(smoothstep(0.4, 1.0, s) * 6.0 + 0.001))
	for i: int in n_ads:
		var ang2: float = TAU * (i / 6.0) + 0.4 + 0.2 * _h(seed_v, i, 70)
		var d2: float = 66.0 + 26.0 * _h(seed_v, i, 71)
		var pos := Vector3(cos(ang2) * d2, 24.0 + 10.0 * _h(seed_v, i, 72), sin(ang2) * d2)
		var yaw: float = _yaw_to(pos, Vector3.ZERO)
		var tint: Color = [CYAN, MAGENTA, TEAL, VIOLET][i % 4]
		var key: int = _key(56, i)
		var xf: Transform3D = _sign(p, pos, yaw, 26.0, 9.0, tint, 0.0, 1.5, key)
		(p["labels"] as Array).append({"key": key, "xf": xf, "w": 26.0, "h": 9.0, "text": SKY_MESSAGES[i % SKY_MESSAGES.size()], "col": tint})
		var right: Vector3 = Vector3(cos(yaw), 0, -sin(yaw))
		_add(p, "line", seg_xf(pos - right * 13.0 - Vector3(0, 4.9, 0), pos + right * 13.0 - Vector3(0, 4.9, 0), 0.25, 0.25), tint, K_PULSE, 3.0, _key(57, i))
		_add(p, "line", seg_xf(pos - right * 13.0 + Vector3(0, 4.9, 0), pos + right * 13.0 + Vector3(0, 4.9, 0), 0.25, 0.25), tint, K_PULSE, 3.0, _key(58, i))
	# Hover traffic gliding along the roads.
	if lay and not lay.wild:
		var n_car: int = int(round(smoothstep(0.35, 1.0, s) * 20.0))
		for i: int in n_car:
			var road: float = (1.0 if i % 2 == 0 else -1.0) * CityLayout.PITCH * 0.5
			@warning_ignore("integer_division")  # [health]
			var lane: float = (1.6 if (i / 2) % 2 == 0 else -1.6)
			@warning_ignore("integer_division")  # [health]
			(p["movers"] as Array).append({"type": 1, "axis": (i / 4) % 2, "road": road + lane, "dir": 1.0 if lane > 0.0 else -1.0,
				"h": 5.8 + 2.2 * _h(seed_v, i, 80), "speed": 7.0 + 4.0 * _h(seed_v, i, 81), "phase": _h(seed_v, i, 82) * 140.0,
				"key": _key(59, i), "col": [CYAN, MAGENTA, ICE][i % 3]})
	p["aurora"] = smoothstep(0.3, 1.0, s)


static func count(p: Dictionary) -> int:
	var n: int = 0
	for ch: String in CHANNELS:
		n += (p[ch]["xf"] as Array).size()
	return n + (p["movers"] as Array).size() + (p["labels"] as Array).size()


# --- Build ----------------------------------------------------------------------------------

func _make_resources() -> void:
	var light := ShaderMaterial.new()
	light.shader = preload("res://art/shaders/light_seam.gdshader")
	var holo := ShaderMaterial.new()
	holo.shader = preload("res://art/shaders/holo_sign.gdshader")
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.94, 0.96, 0.98)
	white.roughness = 0.22
	white.metallic = 0.05
	white.rim_enabled = true
	white.rim = 0.25
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 0.98)
	glass.metallic = 0.7
	glass.roughness = 0.1
	glass.emission_enabled = true
	glass.emission = Color(0.16, 0.42, 0.6)
	glass.emission_energy_multiplier = 0.35
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pane := StandardMaterial3D.new()
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.albedo_color = Color(0.72, 0.92, 1.0, 0.38)
	pane.metallic = 0.6
	pane.roughness = 0.05
	pane.emission_enabled = true
	pane.emission = Color(0.1, 0.5, 0.7)
	pane.emission_energy_multiplier = 0.25
	pane.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats = {"light": light, "holo": holo, "white": white, "glass": glass, "pane": pane}
	var box := BoxMesh.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_meshes = {"box": box, "sphere": ProcMesh.sphere(0.5, 12, 6), "quad": quad,
		"post": ProcMesh.cyl(0.5, 0.5, 1.0, 8), "ring": hex_ring_mesh(0.5, 0.38, 0.2),
		"slab": hex_prism_mesh(1.0, 1.0, 0.18), "spire": hex_prism_mesh(0.5, 0.5 * 0.55, 1.0)}
	for ch: String in CHANNELS:
		var spec: Array = CHANNELS[ch]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _meshes[spec[0]]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Future_" + ch
		mmi.multimesh = mm
		mmi.material_override = _mats[spec[1]]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if spec[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_mmi[ch] = mmi
	# Movers: body (white), underglow (light), trail (light).
	for part: Array in [["body", "sphere", "white"], ["glow", "sphere", "light"], ["trail", "box", "light"]]:
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.use_custom_data = true
		mm2.mesh = _meshes[part[1]]
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.name = "FutureMover_" + str(part[0])
		mmi2.multimesh = mm2
		mmi2.material_override = _mats[part[2]]
		mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi2)
		_mover_mm[part[0]] = mm2
	# Aurora: a wide open band of curtains far out in the night sky.
	_aurora_mat = ShaderMaterial.new()
	_aurora_mat.shader = preload("res://art/shaders/future_fx.gdshader")
	_aurora_mat.set_shader_parameter("mode", 1)
	_aurora_mat.set_shader_parameter("tint", Color(0.2, 1.0, 0.75))
	_aurora_mat.set_shader_parameter("tint2", Color(0.5, 0.85, 1.0))
	_aurora = MeshInstance3D.new()
	_aurora.name = "Aurora"
	_aurora.mesh = band_mesh(430.0, 70.0, 230.0, deg_to_rad(-200.0), deg_to_rad(40.0), 64)
	_aurora.material_override = _aurora_mat
	_aurora.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aurora.extra_cull_margin = 500.0
	_aurora.visible = false
	add_child(_aurora)


func rebuild() -> void:
	var t0: int = Time.get_ticks_usec()
	_dirty = false
	_since_build = 0.0
	_sig = Vector2i(_hub_level(), field.cleaned_count)
	var p: Dictionary = plan(field, layout, _levels(), _sig.x, _cleaned_frac(), _slots)
	last_plan = p
	var fresh: float = _clock if _built else -100.0
	for ch: String in CHANNELS:
		var c: Dictionary = p[ch]
		var xfs: Array = c["xf"]
		var n: int = xfs.size()
		var buf := PackedFloat32Array()
		buf.resize(n * 20)
		var cols: Array = c["col"]
		var cus: Array = c["cus"]
		var keys: Array = c["key"]
		for i: int in n:
			var t: Transform3D = xfs[i]
			var k: int = keys[i]
			if not _known.has(k):
				_known[k] = fresh
			var o: int = i * 20
			buf[o] = t.basis.x.x
			buf[o + 1] = t.basis.y.x
			buf[o + 2] = t.basis.z.x
			buf[o + 3] = t.origin.x
			buf[o + 4] = t.basis.x.y
			buf[o + 5] = t.basis.y.y
			buf[o + 6] = t.basis.z.y
			buf[o + 7] = t.origin.y
			buf[o + 8] = t.basis.x.z
			buf[o + 9] = t.basis.y.z
			buf[o + 10] = t.basis.z.z
			buf[o + 11] = t.origin.z
			var col: Color = cols[i]
			buf[o + 12] = col.r
			buf[o + 13] = col.g
			buf[o + 14] = col.b
			buf[o + 15] = col.a
			var cu: Color = cus[i]
			buf[o + 16] = cu.r
			buf[o + 17] = cu.g
			buf[o + 18] = cu.b
			buf[o + 19] = float(_known[k])
		var mm: MultiMesh = (_mmi[ch] as MultiMeshInstance3D).multimesh
		(_mmi[ch] as MultiMeshInstance3D).set_meta("inst_xf", xfs)  # [world2] collider audit / FutureColliders
		mm.instance_count = n
		if n > 0:
			mm.buffer = buf
		(_mmi[ch] as MultiMeshInstance3D).visible = n > 0
	_build_labels(p["labels"])
	_movers = p["movers"]
	for m: Dictionary in _movers:
		if not _known.has(int(m["key"])):
			_known[int(m["key"])] = fresh
	for part: String in _mover_mm:
		var mm3: MultiMesh = _mover_mm[part]
		mm3.instance_count = _movers.size() * (2 if part == "glow" else 1)
	_update_movers()
	_aurora.visible = float(p["aurora"]) > 0.01
	if not _built:
		print("[future] score=%.2f pieces=%d built in %.1f ms" % [float(p["score"]), count(p), (Time.get_ticks_usec() - t0) / 1000.0])
	_built = true


func _build_labels(list: Array) -> void:
	var want: Dictionary = {}
	for d: Dictionary in list:
		var k: int = int(d["key"])
		want[k] = true
		if _labels.has(k):
			continue
		var l := Label3D.new()
		var txt: String = tr(str(d["text"]))
		l.text = txt
		l.font_size = 96
		l.outline_size = 18
		var col: Color = d["col"]
		l.modulate = Color(1.5, 1.9, 1.9)
		l.outline_modulate = Color(col.r, col.g, col.b, 0.8)
		l.shaded = false
		l.double_sided = false  # [vqa2] one face per side: seen from behind it read mirrored
		l.render_priority = 2
		l.outline_render_priority = 1
		var w: float = float(d["w"]) * 0.86
		var hgt: float = float(d["h"]) * 0.5
		l.pixel_size = minf(w / (maxf(txt.length(), 4.0) * 0.62 * 96.0), hgt / 96.0)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		var xf: Transform3D = d["xf"]
		l.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + xf.basis.z.normalized() * 0.04)
		add_child(l)
		_labels[k] = l
		var back: Label3D = l.duplicate() as Label3D  # [vqa2] the back face, reading the right way round
		back.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.08))
		l.add_child(back)
		if _built and float(_known.get(k, -100.0)) >= _clock - 0.01:
			l.modulate.a = 0.0
			back.modulate.a = 0.0
			var tw := l.create_tween()
			tw.tween_interval(0.35)
			tw.tween_property(l, "modulate:a", 1.0, 0.6)
			tw.parallel().tween_property(back, "modulate:a", 1.0, 0.6)
	for k: int in _labels.keys():
		if not want.has(k):
			(_labels[k] as Label3D).queue_free()
			_labels.erase(k)


# --- Runtime -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_since_build += delta
	(_mats["light"] as ShaderMaterial).set_shader_parameter("t_now", _clock)
	(_mats["holo"] as ShaderMaterial).set_shader_parameter("t_now", _clock)
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		if Vector2i(_hub_level(), field.cleaned_count) != _sig:
			_dirty = true
	if _dirty and _since_build > 2.5:
		rebuild()
	if not _movers.is_empty():
		_update_movers()
	if _aurora.visible:
		var night: float = night_factor()
		_aurora_mat.set_shader_parameter("strength", night * float(last_plan.get("aurora", 0.0)))
	# A built-up district clears its own air and tints its night sky (small hooks on SkyDirector).
	var sd: Node = world.get("sky_director")
	if sd:
		var sc: float = float(last_plan.get("score", 0.0))
		sd.set("clear_bonus", smoothstep(0.2, 1.0, sc) * 0.7)
		sd.set("night_tint", Color(0.55, 0.62, 0.9, smoothstep(0.3, 1.0, sc) * 0.15))


func night_factor() -> float:
	var sd: Node = world.get("sky_director") if world else null
	if sd == null:
		return 0.0
	var tod: float = float(sd.get("time_of_day"))
	var day_t: float = (tod - 0.25) / 0.5
	var elev: float = sin(clampf(day_t, 0.0, 1.0) * PI) * 70.0
	return 1.0 - smoothstep(-2.0, 10.0, elev if day_t > 0.0 and day_t < 1.0 else -10.0)


func _mover_xf(m: Dictionary, t: float) -> Array:
	# Returns [position, heading, fade].
	if int(m["type"]) == 0:
		var a: float = float(m["phase"]) + t * float(m["speed"])
		var r: float = float(m["r"])
		var c: Vector3 = m["c"]
		var pos: Vector3 = c + Vector3(cos(a) * r, sin(a * 2.0) * 0.4, sin(a) * r)
		var fwd := Vector3(-sin(a), 0, cos(a)) * signf(float(m["speed"]))
		return [pos, fwd, 1.0]
	var span: float = 140.0
	var u: float = fmod(float(m["phase"]) + t * float(m["speed"]), span)
	var along: float = (u - span * 0.5) * float(m["dir"])
	var fade: float = smoothstep(0.0, 8.0, u) * smoothstep(span, span - 8.0, u)
	var road: float = float(m["road"])
	var h: float = float(m["h"]) + sin(t * 1.3 + float(m["phase"])) * 0.12
	if int(m["axis"]) == 0:
		return [Vector3(road, h, along), Vector3(0, 0, float(m["dir"])), fade]
	return [Vector3(along, h, road), Vector3(float(m["dir"]), 0, 0), fade]


func _update_movers() -> void:
	var body: MultiMesh = _mover_mm["body"]
	var glow: MultiMesh = _mover_mm["glow"]
	var trail: MultiMesh = _mover_mm["trail"]
	for i: int in _movers.size():
		var m: Dictionary = _movers[i]
		var r: Array = _mover_xf(m, _clock)
		var pos: Vector3 = r[0]
		var fwd: Vector3 = r[1]
		var age: float = clampf((_clock - float(_known.get(int(m["key"]), -100.0))) / 1.2, 0.0, 1.0)
		var f: float = float(r[2]) * age
		var car: bool = int(m["type"]) == 1
		var yaw: float = atan2(fwd.x, fwd.z)
		var bs: Vector3 = (Vector3(1.1, 0.45, 2.6) if car else Vector3(0.7, 0.28, 0.7)) * maxf(f, 0.001)
		var basis_ := Basis(Vector3.UP, yaw) * Basis.from_scale(bs)
		var col: Color = m["col"]
		var cus := Color(float(i) * 0.37, K_STEADY, 1.0, -100.0)
		body.set_instance_transform(i, Transform3D(basis_, pos))
		body.set_instance_color(i, Color.WHITE)
		body.set_instance_custom_data(i, cus)
		var gs: Vector3 = (Vector3(1.3, 0.12, 2.8) if car else Vector3(0.75, 0.1, 0.75)) * maxf(f, 0.001)
		glow.set_instance_transform(i * 2, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(gs), pos - Vector3(0, bs.y * 0.42, 0)))
		glow.set_instance_color(i * 2, col)
		glow.set_instance_custom_data(i * 2, Color(cus.r, K_STEADY, 3.0, -100.0))
		var lamp: Vector3 = pos + fwd * (bs.z * 0.48) + Vector3(0, bs.y * 0.1, 0)
		glow.set_instance_transform(i * 2 + 1, Transform3D(Basis.from_scale(Vector3.ONE * (0.22 if car else 0.14) * maxf(f, 0.001)), lamp))
		glow.set_instance_color(i * 2 + 1, ICE)
		glow.set_instance_custom_data(i * 2 + 1, Color(cus.r, K_STEADY, 4.0, -100.0))
		var tail_len: float = (3.5 if car else 1.6) * f
		var back: Vector3 = pos - fwd * (bs.z * 0.5)
		trail.set_instance_transform(i, seg_xf(back - fwd * maxf(tail_len, 0.01), back, 0.05 * maxf(f, 0.001), 0.14 * maxf(f, 0.001)))
		trail.set_instance_color(i, col)
		trail.set_instance_custom_data(i, Color(cus.r, K_CALM, 2.2 * f, -100.0))


func _on_level_changed(hid: int, level: int) -> void:
	if level >= 1:
		sweep(hid, level)
	_dirty = true
	rebuild.call_deferred()


## Level-up moment: a curtain of light rises around the hex while the new pieces draw in.
func sweep(hid: int, level: int) -> void:
	var c: Vector3 = field.hex_center(hid)
	var mi := MeshInstance3D.new()
	mi.mesh = hex_curtain_mesh(field.hex_size * 0.985, 3.0 + level * 0.4)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/future_fx.gdshader")
	mat.set_shader_parameter("mode", 0)
	var col: Color = [TEAL, TEAL, LIME, CYAN, ICE, MAGENTA][clampi(level, 0, 5)]
	mat.set_shader_parameter("tint", col)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.x, layout.height_at(c.x, c.z) if layout else 0.0, c.z)
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, 1.7)
	tw.tween_callback(mi.queue_free)


# --- Meshes ----------------------------------------------------------------------------------

## Pointy-top hex prism (r_bot at y=-h/2, r_top at y=+h/2), flat-shaded, with caps.
static func hex_prism_mesh(r_bot: float, r_top: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := Vector3(0, -h * 0.5, 0)
	var hi := Vector3(0, h * 0.5, 0)
	for i: int in 6:
		var a0: Vector3 = corner(lo, r_bot, i)
		var a1: Vector3 = corner(lo, r_bot, i + 1)
		var b0: Vector3 = corner(hi, r_top, i)
		var b1: Vector3 = corner(hi, r_top, i + 1)
		var n: Vector3 = (b0 - a0).cross(a1 - a0).normalized()
		for v: Vector3 in [a0, b0, a1, a1, b0, b1]:
			st.set_normal(-n if n.dot(a0 + a1) < 0.0 else n)
			st.add_vertex(v)
		st.set_normal(Vector3.UP)
		for v: Vector3 in [hi, b1, b0]:
			st.add_vertex(v)
		st.set_normal(Vector3.DOWN)
		for v: Vector3 in [lo, a0, a1]:
			st.add_vertex(v)
	st.index()
	return st.commit()


## Low hex planter rim (open middle), sitting on y = 0.
static func hex_ring_mesh(r_out: float, r_in: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, h, 0)
	for i: int in 6:
		var o0: Vector3 = corner(Vector3.ZERO, r_out, i)
		var o1: Vector3 = corner(Vector3.ZERO, r_out, i + 1)
		var i0: Vector3 = corner(Vector3.ZERO, r_in, i)
		var i1: Vector3 = corner(Vector3.ZERO, r_in, i + 1)
		var n_out: Vector3 = ((o0 + o1) * 0.5).normalized()
		st.set_normal(n_out)
		for v: Vector3 in [o0, o1, o0 + top, o0 + top, o1, o1 + top]:
			st.add_vertex(v)
		st.set_normal(-n_out)
		for v: Vector3 in [i0, i0 + top, i1, i1, i0 + top, i1 + top]:
			st.add_vertex(v)
		st.set_normal(Vector3.UP)
		for v: Vector3 in [o0 + top, o1 + top, i0 + top, i0 + top, o1 + top, i1 + top]:
			st.add_vertex(v)
	return st.commit()


## Open hex wall (UV.y = 0 at the top, 1 at the bottom) for the level-up sweep.
static func hex_curtain_mesh(r: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 6:
		var a: Vector3 = corner(Vector3.ZERO, r, i)
		var b: Vector3 = corner(Vector3.ZERO, r, i + 1)
		var u0: float = i / 6.0
		var u1: float = (i + 1) / 6.0
		for v: Array in [[a, Vector2(u0, 1)], [a + Vector3(0, h, 0), Vector2(u0, 0)], [b, Vector2(u1, 1)],
				[b, Vector2(u1, 1)], [a + Vector3(0, h, 0), Vector2(u0, 0)], [b + Vector3(0, h, 0), Vector2(u1, 0)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


## Section of an open cylinder (for the aurora); UV.x around, UV.y = 0 top, 1 bottom.
static func band_mesh(radius: float, y0: float, y1: float, a0: float, a1: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in segs:
		var t0: float = float(i) / segs
		var t1: float = float(i + 1) / segs
		var p0 := Vector3(cos(lerpf(a0, a1, t0)) * radius, 0, sin(lerpf(a0, a1, t0)) * radius)
		var p1 := Vector3(cos(lerpf(a0, a1, t1)) * radius, 0, sin(lerpf(a0, a1, t1)) * radius)
		# Curtains lean in toward the top so they arc over the skyline.
		var q0: Vector3 = p0 * 0.82 + Vector3(0, y1, 0)
		var q1: Vector3 = p1 * 0.82 + Vector3(0, y1, 0)
		for v: Array in [[p0 + Vector3(0, y0, 0), Vector2(t0, 1)], [q0, Vector2(t0, 0)], [p1 + Vector3(0, y0, 0), Vector2(t1, 1)],
				[p1 + Vector3(0, y0, 0), Vector2(t1, 1)], [q0, Vector2(t0, 0)], [q1, Vector2(t1, 0)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


# --- Dev preview --------------------------------------------------------------------------------

## --future=N: quietly clean every land hex, plant them to match, set every hex to level N
## (and the hub to N, set by slice.gd before the hub is built) so the layer can be previewed.
static func apply_preview(w: Node, n: int) -> void:
	n = clampi(n, 0, HexLevels.MAX_LEVEL)
	var fld: HexField = w.field
	var hl: HexLevels = w.hex_levels
	var g: Garden = w.garden
	var planet: PlanetData = w.planet
	if n >= 1:
		for pid: int in fld.piece_count():
			if fld.piece_alive[pid] == 1 and fld.hex_hub[fld.piece_hex[pid]] == 0 and not fld.is_water(fld.piece_hex[pid]):
				fld.remove_piece(pid)
				w.view.hide_piece(pid)
		for hid: int in hl.levels:
			if not fld.is_clean(hid):
				fld.hex_clean[hid] = 1
				fld.cleaned_count += 1
			w.view.refresh_hex(hid, false)
			w.litter.refresh_hex(hid)
			planet.set_junk(w.slice_cells[hid], 0.0)
			planet.mark_clean(w.slice_cells[hid])
	if n >= 2 and g:
		GameState.flags["seeds_unlocked"] = true
		var stage: int = [0, 0, 1, 2, 3, 4][n]
		for hid: int in hl.levels:
			var sl: PackedInt32Array = g.hex_slots.get(hid, PackedInt32Array())
			var sum: float = 0.0
			for i: int in sl.size():
				var s: int = sl[i]
				if n < 4 and i % 2 == 1:
					continue
				g.slot_species[s] = g._pick_species(s)  # [biomes] district-appropriate species (frontier natives)
				g.slot_stage[s] = stage
				g.slot_water[s] = float(g.species[g.slot_species[s]].get("water_s", 120))
				g._update_inst(s)
				sum += stage + 1.0
			if sl.size() > 0:
				var life: float = sum / (sl.size() * 5.0)
				g.hex_life[hid] = life
				w.view.set_life(hid, life)
				planet.state[w.slice_cells[hid]] = PlanetData.State.RESTORED if life >= 0.8 else (PlanetData.State.GROWING if life >= 0.35 else PlanetData.State.PLANTED)
	for hid: int in hl.levels:
		hl.levels[hid] = maxi(int(hl.levels[hid]), n)
	hl._recalc_bonus()
	if n >= 2 and g:
		# Re-push the plant transforms once the scene is up so their MultiMesh bounds are fresh.
		w.get_tree().create_timer(1.0).timeout.connect(func() -> void:
			for s: int in g.slot_species.size():
				if g.slot_species[s] >= 0:
					g._update_inst(s))
