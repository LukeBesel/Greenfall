class_name StreetFurniture
extends Node3D
## [v3city] The street life of a globe hub town (owner item 42: "streets, signs, lights, parked
## junk"), on top of CityView's sidewalks, kerbs, lamps and hydrants:
##   - road paint: zebra crossings and stop lines at the intersections, dashed centre lines
##   - bus stops (shelter, bench, ad panel, stop pole), benches, litter bins, bollards, post boxes
##   - corner poles: street-name blades, stop signs, dead traffic lights over the junctions
##   - parked wrecks: cars, hatchbacks and vans along the kerbs (a few skewed, stripped or on their
##     roof), rows of them on the parking lots, a couple on the forecourt lots
## Everything is built with the shared kit (KitMesh.Builder, one merged mesh per 72 m cell and
## material) in site-local metres; colliders are boxes on the PROP layer. The wrecks and shelters
## hand their footprints to the junk keep-out (prop_rects), so no junk lies inside them.
## Nothing goes on lake cells (water_fn), inside `keep_r` of the yard, or out past `town_r`.

const CELL: float = 72.0
const KERB: float = CityLayout.PITCH * 0.5 - CityLayout.ROAD_W * 0.5  # 13.5: kerb line from a block centre
const ROAD_C: float = CityLayout.PITCH * 0.5                          # 18: road centre line
const CAR_COLS: Array[String] = ["#8f3b2e", "#3d5f86", "#d8cfb8", "#6f9a83", "#c49a3a", "#6d6f72", "#b8b6ae",
	"#4a3f5c", "#2f6f73", "#a8572f", "#e1dccd", "#556b2f"]
const SHELTER_COL: Array[String] = ["#2f6f73", "#3d5f86", "#7a3b30", "#55606b"]

var layout: CityLayout
var water_fn: Callable
var town_r: float = 136.0
var keep_r: float = 24.0   # no furniture this close to the yard centre (its machines and the pad)
var goal_r: float = 40.0   # no wrecks this close (the first hexes)
var state: String = "broken"
var obstacles: Array[Vector2] = []  # lamps, hydrants, boxes CityView put on the sidewalks
var prop_rects: Array[Rect2] = []   # junk keep-out (site-local)
var counts: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _b: Dictionary = {}       # cell -> KitMesh.Builder (street furniture)
var _cars: Dictionary = {}    # cell -> KitMesh.Builder (wrecks: always broken)
var _paint := SurfaceTool.new()
var _paint_n: int = 0
var _body: StaticBody3D
var _meshes: Array[MeshInstance3D] = []


func build(p_layout: CityLayout, seed_v: int) -> void:
	layout = p_layout
	_rng.seed = seed_v + 9091
	_body = PropColliders.body(self, "FurnitureBody")
	_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	await BuildBudget.check("town:paint")
	_road_paint()
	await BuildBudget.check("town:sidewalks")
	_sidewalks()
	await BuildBudget.check("town:corners")
	_corners()
	await BuildBudget.check("town:wrecks")
	_kerb_wrecks()
	_lot_wrecks()
	await BuildBudget.check("town:flush")
	_flush()


func set_state(st: String) -> void:
	state = st
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi) and not mi.has_meta("wreck"):
			KitMat.apply(mi, state, false)


# --- Helpers ----------------------------------------------------------------------------------

func _wet(p: Vector2) -> bool:
	return water_fn.is_valid() and bool(water_fn.call(p.x, p.y))


func _ok(p: Vector2, r_min: float = -1.0) -> bool:
	var d: float = p.length()
	return d > (keep_r if r_min < 0.0 else r_min) and d < town_r - 2.0 and not _wet(p)


func _clear_of(p: Vector2, r: float) -> bool:
	for o: Vector2 in obstacles:
		if o.distance_squared_to(p) < r * r:
			return false
	return true


func _builder(p: Vector2, wreck: bool = false) -> KitMesh.Builder:
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var d: Dictionary = _cars if wreck else _b
	if not d.has(c):
		d[c] = KitMesh.Builder.new(1 + c.x * 31 + c.y * 7, {}, "broken" if wreck else state)
	return d[c]


func _count(k: String) -> void:
	counts[k] = int(counts.get(k, 0)) + 1


## Site-local transform: on the ground at p, facing `yaw` (local -Z forward after the yaw).
static func _at(p: Vector2, yaw: float, y: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y))


func _collide(xf: Transform3D, size: Vector3) -> void:
	PropColliders.add_box(_body, xf * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), size)


## Whether a block exists (kept on the pad and not given to the lake).
func _has(k: Vector2i) -> bool:
	return layout.blocks.has(k)


# --- Road paint -------------------------------------------------------------------------------

func _quad(c: Vector2, along: Vector2, half_l: float, half_w: float, col: Color) -> void:
	if _wet(c) or c.length() > town_r - 3.0:
		return
	var across := Vector2(-along.y, along.x)
	var y: float = 0.045
	var p: Array[Vector3] = []
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q: Vector2 = c + along * half_l * s.x + across * half_w * s.y
		p.append(Vector3(q.x, y, q.y))
	for i: int in [0, 2, 1, 0, 3, 2]:
		_paint.set_color(col)
		_paint.set_normal(Vector3.UP)
		_paint.set_uv(Vector2(p[i].x, p[i].z) * 0.5)
		_paint.add_vertex(p[i])
	_paint_n += 1


## The street grid's junctions inside the town: zebra crossings on every arm whose road runs
## between two kept blocks, a stop line before each, and dashed centre lines on the streets.
func _road_paint() -> void:
	var n: int = int(ceil(layout.extent / CityLayout.PITCH)) + 1
	var white := Color(0.92, 0.91, 0.86)
	var yellow := Color(0.95, 0.75, 0.2)
	for i: int in range(-n, n):
		for j: int in range(-n, n):
			var ic := Vector2((i + 0.5) * CityLayout.PITCH, (j + 0.5) * CityLayout.PITCH)
			if ic.length() > town_r or _wet(ic):
				continue
			# Arms: +x, -x, +z, -z. An arm is a street if a block stands on either side of it.
			var arms: Array = [[Vector2(1, 0), Vector2i(i + 1, j), Vector2i(i + 1, j + 1)], [Vector2(-1, 0), Vector2i(i, j), Vector2i(i, j + 1)],
				[Vector2(0, 1), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)], [Vector2(0, -1), Vector2i(i, j), Vector2i(i + 1, j)]]
			var live: int = 0
			for a: Array in arms:
				if _has(a[1]) or _has(a[2]):
					live += 1
			for a: Array in arms:
				if not (_has(a[1]) or _has(a[2])):
					continue
				var d: Vector2 = a[0]
				var across := Vector2(-d.y, d.x)
				var wear: float = _rng.randf_range(0.35, 0.8)
				if live >= 3:
					# Zebra: stripes along the traffic, side by side across the road.
					var zc: Vector2 = ic + d * 6.6
					for k: int in 8:
						var off: float = -3.85 + k * 1.1
						var col := Color(white.r, white.g, white.b, wear * _rng.randf_range(0.6, 1.0))
						if _rng.randf() < 0.12:
							continue  # worn away
						_quad(zc + across * off, d, 1.3, 0.28, col)
					# Stop line on the approach half.
					_quad(ic + d * 8.6 + across * 2.2, across, 2.1, 0.16, Color(white.r, white.g, white.b, wear))
					_count("crossings")
				# Centre dashes down this arm to the middle of the block side.
				for k2: int in 3:
					var t: float = 10.5 + k2 * 4.0
					if _rng.randf() < 0.15:
						continue
					_quad(ic + d * t, d, 1.1, 0.07, Color(yellow.r, yellow.g, yellow.b, wear * 0.9))


# --- Sidewalk furniture -----------------------------------------------------------------------

func _sidewalks() -> void:
	var sides: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for key: Vector2i in layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var b: Dictionary = layout.blocks[key]
		var c := Vector2(key) * CityLayout.PITCH
		var shelter_done: bool = false
		for o: Vector2 in sides:
			# A side faces a street; skip the ones facing the yard's own road (its machines stand there).
			var along := Vector2(-o.y, o.x)
			var slots: Array[float] = [-7.5, -2.5, 2.5, 7.5]
			var used: Array[float] = []
			# One bus stop on a long building side now and then.
			if not shelter_done and int(b["type"]) == CityLayout.Block.BUILDINGS and _rng.randf() < 0.3:
				var t: float = [-5.0, 5.0][_rng.randi() % 2]
				var p: Vector2 = c + o * 12.1 + along * t
				if _ok(p) and _clear_of(p, 2.4) and _ok(p + along * 1.8) and _ok(p - along * 1.8):
					_bus_stop(p, o)
					used.append(t)
					shelter_done = true
			for t2: float in slots:
				var skip: bool = false
				for u: float in used:
					if absf(u - t2) < 4.2:
						skip = true
				if skip:
					continue
				var q: Vector2 = c + o * 12.8 + along * t2
				if not _ok(q) or not _clear_of(q, 1.6):
					continue
				var r: float = _rng.randf()
				if r < 0.2:
					_bench(c + o * 12.6 + along * t2, o)
				elif r < 0.42:
					_bin(q, o)
				elif r < 0.5:
					_post_box(q, o)
				elif r < 0.6 and int(b["type"]) != CityLayout.Block.BUILDINGS:
					for k: int in 3:
						_bollard(c + o * 13.0 + along * (t2 - 1.2 + k * 1.2))


func _bus_stop(p: Vector2, o: Vector2) -> void:
	var yaw: float = atan2(-o.x, -o.y) + PI  # open side toward the road (+o)
	var xf: Transform3D = _at(p, yaw)
	var b: KitMesh.Builder = _builder(p)
	var col: String = "paint:" + SHELTER_COL[_rng.randi() % SHELTER_COL.size()]
	var w: float = 3.4
	var d: float = 1.4
	var h: float = 2.45
	# Posts (four), roof with a lip, glass back and one glass end, the bench and the ad panel.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(col, Vector3(0.08, h, 0.08), xf * KitMesh.xf(Vector3(sx * (w * 0.5 - 0.05), h * 0.5, sz * (d * 0.5 - 0.05))), 0.01)
	var tilt: float = _rng.randf_range(-3.0, 3.0) if _rng.randf() < 0.4 else 0.0
	b.box(col, Vector3(w + 0.2, 0.1, d + 0.25), xf * KitMesh.xf(Vector3(0, h + 0.05, 0.08), Vector3(tilt, 0, 0)), 0.03)
	b.box("steel", Vector3(w + 0.22, 0.14, 0.06), xf * KitMesh.xf(Vector3(0, h, d * 0.5 + 0.2)), 0.01)
	if _rng.randf() < 0.75:
		b.box("glass", Vector3(w - 0.15, 1.75, 0.03), xf * KitMesh.xf(Vector3(0, 1.15, -d * 0.5 + 0.04)), 0.005)
	else:  # smashed: just the frame rail
		b.box(col, Vector3(w - 0.15, 0.06, 0.05), xf * KitMesh.xf(Vector3(0, 0.3, -d * 0.5 + 0.04)), 0.01)
	b.box("glass", Vector3(0.03, 1.75, d - 0.15), xf * KitMesh.xf(Vector3(-w * 0.5 + 0.04, 1.15, 0)), 0.005)
	# Ad panel at the other end: a box with a dead lightbox face.
	b.box("paint:#2a2c30", Vector3(0.18, 1.85, d - 0.2), xf * KitMesh.xf(Vector3(w * 0.5 - 0.1, 1.05, 0)), 0.02)
	b.box("trim:white", Vector3(0.02, 1.55, d - 0.45), xf * KitMesh.xf(Vector3(w * 0.5 - 0.2, 1.1, 0)), 0.005)
	# Bench inside.
	b.box("paint:#7a5a3a", Vector3(2.0, 0.06, 0.38), xf * KitMesh.xf(Vector3(-0.2, 0.46, -0.3)), 0.01)
	for sx2: float in [-0.9, 0.5]:
		b.box("dark_steel", Vector3(0.06, 0.44, 0.3), xf * KitMesh.xf(Vector3(sx2, 0.22, -0.3)), 0.01)
	# Stop pole by the kerb with its round sign and a timetable box.
	var pole := xf * KitMesh.xf(Vector3(w * 0.5 + 0.7, 0, 0.5))
	b.cyl("dark_steel", 0.04, 2.7, pole, 0.005, 8)
	b.cyl("paint:#1f5fa8", 0.3, 0.04, pole * KitMesh.xf(Vector3(0, 2.55, 0), Vector3(90, 0, 0)), 0.01, 16)
	b.cyl("paint:#f2efe6", 0.22, 0.05, pole * KitMesh.xf(Vector3(0, 2.55, 0.0), Vector3(90, 0, 0)), 0.01, 16)
	b.box("paint:#f2efe6", Vector3(0.3, 0.42, 0.06), pole * KitMesh.xf(Vector3(0, 1.5, 0.05)), 0.01)
	_collide(xf * Transform3D(Basis(), Vector3(0, 0, -d * 0.5 + 0.1)), Vector3(w, h, 0.25))
	_collide(xf * Transform3D(Basis(), Vector3(w * 0.5 - 0.1, 0, 0)), Vector3(0.25, h, d))
	_collide(pole, Vector3(0.15, 2.7, 0.15))
	var gx: Vector2 = Vector2(cos(-yaw), sin(-yaw))
	prop_rects.append(_rect_of(p, Vector2(w + 0.4, d + 0.4), yaw))
	obstacles.append(p)
	obstacles.append(p + gx * (w * 0.5 + 0.7))
	_count("bus_stops")


func _bench(p: Vector2, o: Vector2) -> void:
	var yaw: float = atan2(-o.x, -o.y) + PI  # seat faces the road
	var xf: Transform3D = _at(p, yaw)
	var b: KitMesh.Builder = _builder(p)
	var wood: String = ["paint:#7a5a3a", "paint:#5b6b3a", "paint:#3f5a6b"][_rng.randi() % 3]
	var broken: bool = _rng.randf() < 0.25
	for k: int in 3:
		if broken and k == 1:
			continue
		b.box(wood, Vector3(1.8, 0.04, 0.12), xf * KitMesh.xf(Vector3(0, 0.45, -0.17 + k * 0.15)), 0.01)
	for k2: int in 2:
		b.box(wood, Vector3(1.8, 0.11, 0.035), xf * KitMesh.xf(Vector3(0, 0.62 + k2 * 0.16, -0.3), Vector3(-12, 0, 0)), 0.01)
	for sx: float in [-0.75, 0.75]:
		b.box("dark_steel", Vector3(0.05, 0.45, 0.45), xf * KitMesh.xf(Vector3(sx, 0.225, -0.08)), 0.01)
		b.box("dark_steel", Vector3(0.05, 0.42, 0.05), xf * KitMesh.xf(Vector3(sx, 0.62, -0.3), Vector3(-12, 0, 0)), 0.01)
	_collide(xf, Vector3(1.8, 0.85, 0.5))
	obstacles.append(p)
	_count("benches")


func _bin(p: Vector2, o: Vector2) -> void:
	var b: KitMesh.Builder = _builder(p)
	var col: String = ["paint:#2f4f3a", "paint:#2f6f73", "paint:#3a3d42"][_rng.randi() % 3]
	var yaw: float = _rng.randf() * TAU
	if _rng.randf() < 0.18:  # knocked over, lid off, its bag spilled
		var xf: Transform3D = _at(p, yaw) * KitMesh.xf(Vector3(0, 0.28, 0), Vector3(0, 0, 90))
		b.cyl(col, 0.27, 0.85, xf * KitMesh.xf(Vector3(0, -0.42, 0)), 0.02, 12)
		b.cyl("rubber", 0.24, 0.3, _at(p + o * 0.0 + Vector2(cos(yaw), sin(yaw)) * 0.75, yaw) * KitMesh.xf(Vector3(0, 0.0, 0)), 0.08, 8)
		_collide(_at(p, yaw), Vector3(0.6, 0.55, 0.9))
	else:
		var xf2: Transform3D = _at(p, yaw)
		b.cyl(col, 0.27, 0.82, xf2, 0.02, 12)
		b.cyl("dark_steel", 0.3, 0.07, xf2 * KitMesh.xf(Vector3(0, 0.82, 0)), 0.02, 12)
		b.box("dark_steel", Vector3(0.22, 0.04, 0.06), xf2 * KitMesh.xf(Vector3(0, 0.9, 0)), 0.01)
		if _rng.randf() < 0.5:  # overflowing
			b.cyl("rubber", 0.2, 0.25, xf2 * KitMesh.xf(Vector3(0.05, 0.86, 0.02), Vector3(8, 0, 6)), 0.08, 8)
		_collide(xf2, Vector3(0.55, 0.9, 0.55))
	obstacles.append(p)
	_count("bins")


func _post_box(p: Vector2, o: Vector2) -> void:
	var yaw: float = atan2(-o.x, -o.y) + PI
	var xf: Transform3D = _at(p, yaw)
	var b: KitMesh.Builder = _builder(p)
	var col: String = ["paint:#1f4f8a", "paint:#a8322a", "paint:#c49a3a"][_rng.randi() % 3]
	b.box(col, Vector3(0.48, 0.95, 0.42), xf * KitMesh.xf(Vector3(0, 0.55, 0)), 0.03)
	b.box(col, Vector3(0.5, 0.08, 0.44), xf * KitMesh.xf(Vector3(0, 1.06, 0)), 0.02)
	b.box("dark_steel", Vector3(0.3, 0.04, 0.02), xf * KitMesh.xf(Vector3(0, 0.85, 0.22)), 0.005)
	for sx: float in [-0.18, 0.18]:
		b.box("dark_steel", Vector3(0.05, 0.1, 0.32), xf * KitMesh.xf(Vector3(sx, 0.05, 0)), 0.01)
	_collide(xf, Vector3(0.5, 1.1, 0.45))
	obstacles.append(p)
	_count("post_boxes")


func _bollard(p: Vector2) -> void:
	if not _ok(p):
		return
	var b: KitMesh.Builder = _builder(p)
	var lean: Vector3 = Vector3(_rng.randf_range(-12, 12), 0, _rng.randf_range(-12, 12)) if _rng.randf() < 0.3 else Vector3.ZERO
	var xf: Transform3D = _at(p, 0.0) * KitMesh.xf(Vector3.ZERO, lean)
	b.cyl("paint:#2a2c30", 0.09, 0.85, xf, 0.02, 10)
	b.cyl("paint:yellow", 0.095, 0.1, xf * KitMesh.xf(Vector3(0, 0.62, 0)), 0.01, 10)
	_collide(_at(p, 0.0), Vector3(0.2, 0.85, 0.2))
	_count("bollards")


# --- Corners ------------------------------------------------------------------------------------

## Each junction gets one pole on one of its corners: a street-name post, a stop sign, or (on
## busy four-way junctions) a dead traffic light reaching over the road.
func _corners() -> void:
	var n: int = int(ceil(layout.extent / CityLayout.PITCH)) + 1
	for i: int in range(-n, n):
		for j: int in range(-n, n):
			var ic := Vector2((i + 0.5) * CityLayout.PITCH, (j + 0.5) * CityLayout.PITCH)
			var around: Array[Vector2i] = [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]
			var have: Array[Vector2i] = []
			for k: Vector2i in around:
				if _has(k) and k != Vector2i.ZERO:
					have.append(k)
			if have.is_empty():
				continue
			var blk: Vector2i = have[_rng.randi() % have.size()]
			var bc := Vector2(blk) * CityLayout.PITCH
			var to_ic: Vector2 = (ic - bc).sign()
			var p: Vector2 = bc + to_ic * 12.85
			if not _ok(p) or not _clear_of(p, 1.4):
				continue
			var r: float = _rng.randf()
			if have.size() == 4 and r < 0.45:
				_traffic_light(p, ic)
			elif r < 0.7:
				_name_post(p)
			else:
				_stop_sign(p, ic, to_ic)
			obstacles.append(p)


func _name_post(p: Vector2) -> void:
	var b: KitMesh.Builder = _builder(p)
	var lean: Vector3 = Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)) if _rng.randf() < 0.25 else Vector3.ZERO
	var xf: Transform3D = _at(p, 0.0) * KitMesh.xf(Vector3.ZERO, lean)
	b.cyl("dark_steel", 0.045, 3.0, xf, 0.005, 8)
	var green: String = "paint:#2f6b45"
	b.box(green, Vector3(1.0, 0.2, 0.03), xf * KitMesh.xf(Vector3(0.3, 2.85, 0)), 0.01)
	b.box(green, Vector3(0.03, 0.2, 1.0), xf * KitMesh.xf(Vector3(0, 2.62, 0.3), Vector3(0, 0, _rng.randf_range(-8, 8))), 0.01)
	b.box("paint:#f2efe6", Vector3(0.7, 0.05, 0.035), xf * KitMesh.xf(Vector3(0.3, 2.85, 0)), 0.003)
	b.box("paint:#f2efe6", Vector3(0.035, 0.05, 0.7), xf * KitMesh.xf(Vector3(0, 2.62, 0.3)), 0.003)
	_collide(_at(p, 0.0), Vector3(0.15, 3.0, 0.15))
	_count("name_posts")


func _stop_sign(p: Vector2, _ic: Vector2, to_ic: Vector2) -> void:
	var b: KitMesh.Builder = _builder(p)
	# Faces the traffic coming toward the junction along one of the two roads at this corner.
	var face: Vector2 = Vector2(to_ic.x, 0) if _rng.randf() < 0.5 else Vector2(0, to_ic.y)
	var yaw: float = atan2(face.x, face.y) + PI
	var xf: Transform3D = _at(p, yaw)
	b.cyl("dark_steel", 0.04, 2.5, xf, 0.005, 8)
	b.cyl("paint:#b8322a", 0.36, 0.03, xf * KitMesh.xf(Vector3(0, 2.3, 0.05), Vector3(90, 22.5, 0)), 0.006, 8)
	b.cyl("paint:#f2efe6", 0.3, 0.035, xf * KitMesh.xf(Vector3(0, 2.3, 0.052), Vector3(90, 22.5, 0)), 0.004, 8)
	b.cyl("paint:#b8322a", 0.26, 0.04, xf * KitMesh.xf(Vector3(0, 2.3, 0.056), Vector3(90, 22.5, 0)), 0.004, 8)
	_collide(_at(p, 0.0), Vector3(0.15, 2.5, 0.15))
	_count("stop_signs")


func _traffic_light(p: Vector2, ic: Vector2) -> void:
	var b: KitMesh.Builder = _builder(p)
	var to: Vector2 = (ic - p).normalized()
	var yaw: float = atan2(-to.x, -to.y)  # local -Z toward the junction
	var bent: bool = _rng.randf() < 0.2
	var xf: Transform3D = _at(p, yaw) * KitMesh.xf(Vector3.ZERO, Vector3(-9.0 if bent else 0.0, 0, 0))
	b.cyl("dark_steel", 0.09, 4.6, xf, 0.01, 10)
	b.cyl("dark_steel", 0.13, 0.5, xf, 0.01, 10)
	# Arm out over the road with the signal head hanging from it; a second head on the pole.
	var arm_l: float = 4.2
	b.rod("dark_steel", xf * Vector3(0, 4.4, 0), xf * Vector3(0, 4.55, -arm_l), 0.055, 8)
	for at: Vector3 in [Vector3(0, 3.65, -arm_l + 0.3), Vector3(0.0, 2.6, 0.2)]:
		var hx: Transform3D = xf * KitMesh.xf(at)
		b.box("paint:#2a2c30", Vector3(0.36, 0.95, 0.3), hx, 0.03)
		var lens: Array[String] = ["trim:red", "trim:#ffb020", "trim:green"]
		for k: int in 3:
			b.cyl(lens[k], 0.1, 0.05, hx * KitMesh.xf(Vector3(0, 0.3 - k * 0.3, -0.15), Vector3(90, 0, 0)), 0.01, 12)
			b.box("paint:#2a2c30", Vector3(0.26, 0.04, 0.16), hx * KitMesh.xf(Vector3(0, 0.42 - k * 0.3, -0.22)), 0.01)
	_collide(_at(p, 0.0), Vector3(0.26, 4.6, 0.26))
	_count("traffic_lights")


# --- Wrecks -----------------------------------------------------------------------------------

## Parked wrecks along both kerbs of each street segment between junctions.
func _kerb_wrecks() -> void:
	var n: int = int(ceil(layout.extent / CityLayout.PITCH)) + 1
	for axis: int in 2:
		for k: int in range(-n, n):
			var line: float = (k + 0.5) * CityLayout.PITCH  # the road's centre line
			for m: int in range(-n, n + 1):
				var seg_c: float = m * CityLayout.PITCH  # between junctions m-0.5 and m+0.5
				# The two blocks this segment runs between.
				var ka: Vector2i = Vector2i(m, k) if axis == 0 else Vector2i(k, m)
				var kb: Vector2i = Vector2i(m, k + 1) if axis == 0 else Vector2i(k + 1, m)
				for side: int in 2:
					var blk: Vector2i = ka if side == 0 else kb
					if not _has(blk):
						continue
					var sgn: float = -1.0 if side == 0 else 1.0
					for slot: int in 3:
						if _rng.randf() > 0.4:
							continue
						var t: float = seg_c - 6.0 + slot * 6.0 + _rng.randf_range(-0.6, 0.6)
						var off: float = line + sgn * 3.25
						var p: Vector2 = Vector2(t, off) if axis == 0 else Vector2(off, t)
						if not _ok(p, goal_r):
							continue
						var yaw: float = (0.0 if axis == 0 else PI * 0.5) + (PI if _rng.randf() < 0.5 else 0.0)
						if _rng.randf() < 0.12:
							yaw += _rng.randf_range(-0.5, 0.5)  # left skewed across the lane
						_car(p, yaw + PI * 0.5)


## Rows of wrecks on the parking lots, a few dumped on the other open lots.
func _lot_wrecks() -> void:
	for key: Vector2i in layout.blocks:
		var b: Dictionary = layout.blocks[key]
		var r: Rect2 = b["rect"]
		match int(b["type"]):
			CityLayout.Block.PARKING:
				# Two rows nose to nose along x, an aisle down the middle the other way.
				for row: float in [-5.5, 5.5]:
					for k: int in 8:
						var x: float = r.position.x + 1.6 + k * 2.6
						if absf(x - r.get_center().x) < 2.0:
							continue  # the aisle
						if _rng.randf() > 0.6:
							continue
						var p := Vector2(x, r.get_center().y + row)
						if _ok(p, goal_r):
							_car(p, (0.0 if row < 0.0 else PI) + _rng.randf_range(-0.12, 0.12))
			CityLayout.Block.LANDFILL, CityLayout.Block.VACANT:
				for _k2: int in _rng.randi_range(1, 2):
					var p2 := Vector2(_rng.randf_range(r.position.x + 3, r.end.x - 3), _rng.randf_range(r.position.y + 3, r.end.y - 3))
					if _ok(p2, goal_r):
						_car(p2, _rng.randf() * TAU)
			CityLayout.Block.BUILDINGS:
				# Forecourts: the open lot in front of a building row.
				if maxi(absi(key.x), absi(key.y)) == 1 and _rng.randf() < 0.7:
					var p3: Vector2 = r.get_center() - Vector2(key).normalized() * 3.0
					if _ok(p3, goal_r) and not _in_building(b, p3, 3.0):
						_car(p3, _rng.randf() * TAU)


func _in_building(b: Dictionary, p: Vector2, grow: float) -> bool:
	for bd: Dictionary in b["buildings"]:
		if (bd["rect"] as Rect2).grow(grow).has_point(p):
			return true
	return false


## A wrecked car at p, its length along local Z after `yaw`. Kinds: sedan, hatchback, van.
## Some lost their wheels (sitting on the ground, nose down), a few lie on their roof.
func _car(p: Vector2, yaw: float) -> void:
	for o: Vector2 in obstacles:
		if o.distance_squared_to(p) < 9.0:
			return
	var b: KitMesh.Builder = _builder(p, true)
	var kind: int = _rng.randi() % 3
	var paint: String = "paint:" + CAR_COLS[_rng.randi() % CAR_COLS.size()]
	var L: float = [4.3, 3.8, 4.8][kind]
	var W: float = 1.78 if kind != 2 else 1.95
	var wheels: bool = _rng.randf() > 0.3
	var flipped: bool = _rng.randf() < 0.06
	var lift: float = 0.0 if wheels else -0.2
	var tilt := Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-4, 4)) if not wheels else Vector3.ZERO
	var clr: float = 0.3
	var body_h: float = 0.62 if kind != 2 else 0.9
	var top: float = clr + body_h + [0.5, 0.55, 1.0][kind]
	var root: Transform3D = _at(p, yaw) * KitMesh.xf(Vector3(0, lift, 0), tilt)
	if flipped:
		root = _at(p, yaw) * KitMesh.xf(Vector3(0, top - 0.02, 0), Vector3(0, 0, 180))
	b.box(paint, Vector3(W, body_h, L), root * KitMesh.xf(Vector3(0, clr + body_h * 0.5, 0)), 0.09)
	var cab_y: float = clr + body_h
	match kind:
		0:  # sedan: cabin in the middle, sloped glass front and back
			b.box(paint, Vector3(W - 0.16, 0.5, L * 0.46), root * KitMesh.xf(Vector3(0, cab_y + 0.25, -0.1)), 0.08)
			b.box("glass", Vector3(W - 0.24, 0.5, 0.05), root * KitMesh.xf(Vector3(0, cab_y + 0.22, L * 0.23 + 0.12), Vector3(-55, 0, 0)), 0.01)
			b.box("glass", Vector3(W - 0.24, 0.45, 0.05), root * KitMesh.xf(Vector3(0, cab_y + 0.2, -L * 0.23 - 0.3), Vector3(50, 0, 0)), 0.01)
			for sx: float in [-1.0, 1.0]:
				b.box("glass", Vector3(0.03, 0.34, L * 0.4), root * KitMesh.xf(Vector3(sx * (W - 0.15) * 0.5, cab_y + 0.27, -0.1)), 0.005)
		1:  # hatchback: cabin to the back
			b.box(paint, Vector3(W - 0.14, 0.55, L * 0.55), root * KitMesh.xf(Vector3(0, cab_y + 0.27, -L * 0.2)), 0.08)
			b.box("glass", Vector3(W - 0.24, 0.5, 0.05), root * KitMesh.xf(Vector3(0, cab_y + 0.24, L * 0.08 + 0.12), Vector3(-55, 0, 0)), 0.01)
			for sx2: float in [-1.0, 1.0]:
				b.box("glass", Vector3(0.03, 0.36, L * 0.42), root * KitMesh.xf(Vector3(sx2 * (W - 0.13) * 0.5, cab_y + 0.3, -L * 0.2)), 0.005)
		_:  # van: a tall box, short bonnet
			b.box(paint, Vector3(W - 0.06, 1.0, L * 0.78), root * KitMesh.xf(Vector3(0, cab_y + 0.5, -L * 0.11)), 0.08)
			b.box("glass", Vector3(W - 0.2, 0.55, 0.05), root * KitMesh.xf(Vector3(0, cab_y + 0.6, L * 0.28 + 0.03), Vector3(-20, 0, 0)), 0.01)
			for sx3: float in [-1.0, 1.0]:
				b.box("glass", Vector3(0.03, 0.42, 0.7), root * KitMesh.xf(Vector3(sx3 * (W - 0.05) * 0.5, cab_y + 0.62, L * 0.18)), 0.005)
	# Bumpers, lights, wheels.
	for sz: float in [-1.0, 1.0]:
		b.box("dark_steel", Vector3(W + 0.04, 0.16, 0.14), root * KitMesh.xf(Vector3(0, clr + 0.14, sz * (L * 0.5 + 0.02))), 0.04)
		for sx4: float in [-1.0, 1.0]:
			var lamp: String = "paint:#e8e2cf" if sz > 0.0 else "paint:#9a2a22"
			b.box(lamp, Vector3(0.32, 0.12, 0.04), root * KitMesh.xf(Vector3(sx4 * (W * 0.5 - 0.25), clr + body_h - 0.16, sz * (L * 0.5 + 0.005))), 0.01)
	if wheels:
		for sx5: float in [-1.0, 1.0]:
			for sz2: float in [-1.0, 1.0]:
				var flat: float = 0.06 if _rng.randf() < 0.4 else 0.0
				var wx: Transform3D = root * KitMesh.xf(Vector3(sx5 * (W * 0.5 - 0.02) - sx5 * 0.11, 0.33 - flat * 0.5, sz2 * L * 0.32), Vector3(0, 0, 90))
				b.cyl("rubber", 0.33, 0.22, wx * KitMesh.xf(Vector3(0, -0.11, 0)), 0.06, 14)
				b.cyl("steel", 0.18, 0.24, wx * KitMesh.xf(Vector3(0, -0.12, 0)), 0.02, 10)
	var h: float = clr + body_h + (1.0 if kind == 2 else 0.55)
	_collide(_at(p, yaw), Vector3(W + 0.1, h, L + 0.1))
	prop_rects.append(_rect_of(p, Vector2(W, L), yaw))
	obstacles.append(p)
	_count("wrecks")


## Axis-aligned bounds of a w x l box turned by yaw (local X = w, Z = l).
static func _rect_of(p: Vector2, size: Vector2, yaw: float) -> Rect2:
	var c: float = absf(cos(yaw))
	var s: float = absf(sin(yaw))
	var e := Vector2(size.x * c + size.y * s, size.x * s + size.y * c) * 0.5
	return Rect2(p - e, e * 2.0)


# --- Flush ------------------------------------------------------------------------------------

func _flush() -> void:
	for pass_i: int in 2:
		var d: Dictionary = _b if pass_i == 0 else _cars
		for c: Vector2i in d:
			var b: KitMesh.Builder = d[c]
			var mi := MeshInstance3D.new()
			mi.name = ("Furniture_%d_%d" if pass_i == 0 else "Wrecks_%d_%d") % [c.x, c.y]
			mi.mesh = b.commit()
			KitMat.apply(mi, "broken" if pass_i == 1 else state, false)
			mi.visibility_range_end = 230.0 if pass_i == 0 else 330.0
			mi.visibility_range_end_margin = 20.0
			mi.set_meta("no_collide", true)
			if pass_i == 1:
				mi.set_meta("wreck", true)
			add_child(mi)
			_meshes.append(mi)
	if _paint_n > 0:
		var pm := MeshInstance3D.new()
		pm.name = "RoadPaint"
		pm.mesh = _paint.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.85
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(0.86, 0.85, 0.8)
		pm.material_override = m
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pm.visibility_range_end = 260.0
		pm.set_meta("no_collide", true)
		add_child(pm)
	_b.clear()
	_cars.clear()
