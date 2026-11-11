class_name CityGardens
extends Node3D
## What makes a suburb of houses lived-in (cities.json "gardens"): round every low house a white
## rail fence along its front with a gate gap and a path to the door, a clipped hedge down one
## side, a drive in the gap to its neighbour where there is room for one, and behind it a
## vegetable bed in a timber frame or a painted shed. Flower clumps stand in the front strip and
## at the beds' ends once the district is sustained.
## The hedges and crops are straw-coloured while the ground is poisoned and green from stage 3.
## Batched: per CHUNK_M square one MultiMesh of boxes for the hard parts (fence, drive, path, bed
## frame, soil, shed), one for hedges and crops, one for flowers; all hidden past RANGE_M.

const CHUNK_M: float = 48.0
const RANGE_M: float = 110.0
const MAX_FLOORS: int = 2
const FENCE_OUT: float = 0.42        # the fence stands this far in front of the wall
const GATE_HALF: float = 0.6
const POST_EVERY: float = 1.15
const HEDGE_W: float = 0.46
const HEDGE_H: float = 0.72
const DRIVE_W: float = 2.5
const DRIVE_GAP: Vector2 = Vector2(2.7, 7.0)   # the gap to the next house a drive fits in
const BED_DEPTH: float = 2.2
const BED_BACK: float = 0.7          # between the back wall and the bed
const WHITE := Color(0.97, 0.96, 0.92)
const TIMBER := Color(0.72, 0.52, 0.32)
const SOIL := Color(0.5, 0.33, 0.22)
const PATH := Color(0.9, 0.84, 0.72)
const DRIVES: Array[Color] = [Color(0.86, 0.83, 0.76), Color(0.82, 0.56, 0.44), Color(0.78, 0.8, 0.82)]
const SHED_ROOF := Color(0.3, 0.52, 0.36)
## Hedge and crop colour per stage 0..5: dry straw while the soil is poisoned, green once it grows.
const LEAF: Array[Color] = [Color(0.8, 0.72, 0.36), Color(0.8, 0.72, 0.36), Color(0.74, 0.74, 0.36), Color(0.5, 0.7, 0.28),
	Color(0.36, 0.66, 0.24), Color(0.3, 0.64, 0.22)]

var stats: Dictionary = {}
var _leaf: StandardMaterial3D
var _flowers: Array[Node3D] = []
var _chunks: Dictionary = {}   # Vector2i -> {"hard": [xf], "hard_c": [col], "leaf": [...], "leaf_c": [...], "bloom": [...], "bloom_c": [...]}


## `roofs`: [frame (site space), Rect2 in the frame, roof height, plan] per building (VerdanceCity._roofs()).
## `body` takes a collider for every hedge of the pad town.
func build(roofs: Array, look: CityLook, body: StaticBody3D) -> void:
	var groups: Dictionary = {}   # frame -> [roof entries of houses]
	for e: Array in roofs:
		var bd: Dictionary = e[3]
		if int(bd.get("floors", 9)) > MAX_FLOORS or not bd.has("face") or str(bd.get("style", "")) == "factory":
			continue
		if not groups.has(e[0]):
			groups[e[0]] = []
		(groups[e[0]] as Array).append(e)
	var houses: int = 0
	var drives: int = 0
	var beds: int = 0
	for fr: Transform3D in groups:
		var taken: Array[Rect2] = []
		for e: Array in groups[fr]:
			taken.append((e[1] as Rect2).grow(0.3))
		for e: Array in groups[fr]:
			var bd: Dictionary = e[3]
			var h: int = hash([int(bd.get("seed", 0)), 7717])
			var rng := RandomNumberGenerator.new()
			rng.seed = h
			houses += 1
			_front(fr, e[1], bd, rng)
			if _side(fr, e[1], bd, groups[fr], h, body if fr == Transform3D.IDENTITY else null):
				drives += 1
			if _back(fr, e[1], bd, taken, look, rng):
				beds += 1
	_leaf = AssetLib.pbr_material("leafy_grass", 1.6, Color.WHITE, true)
	_leaf.vertex_color_use_as_albedo = true
	var hard: StandardMaterial3D = CityKit.vc_material(0.9)
	var box := BoxMesh.new()
	for key: Vector2i in _chunks:
		var ch: Dictionary = _chunks[key]
		var at := Vector3((float(key.x) + 0.5) * CHUNK_M, 0.0, (float(key.y) + 0.5) * CHUNK_M)
		_emit("Hard", box, ch["hard"], ch["hard_c"], hard, true, at)
		_emit("Leaf", box, ch["leaf"], ch["leaf_c"], _leaf, true, at)
		var bl: MultiMeshInstance3D = _emit("Flowers", OldTownFlowers.mesh(), ch["bloom"], ch["bloom_c"], OldTownFlowers.material(), false, at)
		if bl:
			_flowers.append(bl)
	stats = {"garden_houses": houses, "garden_drives": drives, "garden_beds": beds, "garden_chunks": _chunks.size()}
	_chunks.clear()


func set_stage(stage: int) -> void:
	var s: int = clampi(stage, 0, LEAF.size() - 1)
	if _leaf:
		_leaf.albedo_color = LEAF[s]
	for n: Node3D in _flowers:
		n.visible = s >= 4


## The front: a path from the door, a rail fence with a gate gap either side of it, and a soil
## strip under the windows with flower clumps.
func _front(fr: Transform3D, r: Rect2, bd: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Vector2 = bd["face"]
	var l := Vector2(-f.y, f.x)
	var w: float = absf(r.size.x * l.x) + absf(r.size.y * l.y)
	var d: float = absf(r.size.x * f.x) + absf(r.size.y * f.y)
	var front: Vector2 = r.get_center() + f * d * 0.5
	var yaw: float = atan2(f.x, f.y)
	var setback: float = float(bd.get("setback", 1.0))
	_box("hard", fr, front + f * setback * 0.5, 0.03, yaw, Vector3(1.0, 0.05, setback), PATH)
	var colour_i: int = rng.randi()
	for side: float in [-1.0, 1.0]:
		var run: float = w * 0.5 - GATE_HALF
		if run < 1.0:
			continue
		var mid: Vector2 = front + l * side * (GATE_HALF + run * 0.5)
		if not bool(bd.get("ruined", false)) or rng.randf() < 0.5:
			for y: float in [0.36, 0.74]:
				_box("hard", fr, mid + f * FENCE_OUT, y, yaw, Vector3(run, 0.07, 0.04), WHITE)
			var posts: int = maxi(2, int(round(run / POST_EVERY)) + 1)
			for i: int in posts:
				var t: float = -run * 0.5 + run * float(i) / float(posts - 1)
				_box("hard", fr, mid + l * t + f * FENCE_OUT, 0.48, yaw, Vector3(0.09, 0.96, 0.09), WHITE)
		_box("hard", fr, mid + f * FENCE_OUT * 0.45, 0.05, yaw, Vector3(run - 0.2, 0.1, FENCE_OUT * 0.7), SOIL)
		for k: int in maxi(1, int(run / 1.1)):
			var p: Vector2 = mid + l * rng.randf_range(-run * 0.45, run * 0.45) + f * FENCE_OUT * 0.45
			_bloom(fr, p, 0.1, rng, colour_i + int(side))


## The side: a clipped hedge along the wall, and a drive from the kerb in the gap to the next house
## of the row when the gap is wide enough. Returns whether a drive was laid.
func _side(fr: Transform3D, r: Rect2, bd: Dictionary, row: Array, h: int, body: StaticBody3D) -> bool:
	var f: Vector2 = bd["face"]
	var l := Vector2(-f.y, f.x)
	var w: float = absf(r.size.x * l.x) + absf(r.size.y * l.y)
	var d: float = absf(r.size.x * f.x) + absf(r.size.y * f.y)
	var c: Vector2 = r.get_center()
	var yaw: float = atan2(f.x, f.y)
	var shade: float = 0.86 + float((h >> 5) % 24) / 100.0
	var at: Vector2 = c + l * (w * 0.5 + HEDGE_W * 0.5 + 0.06)
	_box("leaf", fr, at, HEDGE_H * 0.5, yaw, Vector3(HEDGE_W, HEDGE_H, d), Color(shade, shade, shade))
	if body:
		PropColliders.add_box(body, fr * Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, HEDGE_H * 0.5, at.y)), Vector3(HEDGE_W, HEDGE_H, d))
	# The gap to the nearest house of the same row on that side.
	var gap: float = INF
	for e: Array in row:
		var o: Dictionary = e[3]
		if (o["face"] as Vector2) != f:
			continue
		var oc: Vector2 = (e[1] as Rect2).get_center()
		var ow: float = absf((e[1] as Rect2).size.x * l.x) + absf((e[1] as Rect2).size.y * l.y)
		var along: float = (oc - c).dot(l)
		if along > 0.1 and absf((oc - c).dot(f)) < 4.0:
			gap = minf(gap, along - ow * 0.5 - w * 0.5)
	if gap < DRIVE_GAP.x or gap > DRIVE_GAP.y:
		return false
	var setback: float = float(bd.get("setback", 1.0))
	var front: Vector2 = c + f * d * 0.5
	var mid: Vector2 = c + l * (w * 0.5 + gap * 0.5 + HEDGE_W * 0.5)
	var col: Color = DRIVES[(h >> 9) % DRIVES.size()]
	var inside: float = d * 0.85 + setback
	_box("hard", fr, mid + f * (d * 0.5 + setback - inside * 0.5), 0.035, yaw, Vector3(DRIVE_W, 0.06, inside), col)
	var walk: Vector2 = front + l * (mid - front).dot(l) + f * (setback + CityLayout.WALK_W * 0.5)
	_box("hard", fr, walk, CityLayout.CURB_H + 0.02, yaw, Vector3(DRIVE_W + 0.6, 0.04, CityLayout.WALK_W), col.darkened(0.06))
	return true


## Behind the house: a vegetable bed in a timber frame with three crop rows, or (one house in
## four) a painted shed, where the court behind is free. Returns whether anything was placed.
func _back(fr: Transform3D, r: Rect2, bd: Dictionary, taken: Array[Rect2], look: CityLook, rng: RandomNumberGenerator) -> bool:
	var f: Vector2 = bd["face"]
	var l := Vector2(-f.y, f.x)
	var w: float = absf(r.size.x * l.x) + absf(r.size.y * l.y)
	var d: float = absf(r.size.x * f.x) + absf(r.size.y * f.y)
	var yaw: float = atan2(f.x, f.y)
	var long: float = minf(w - 1.4, 4.4)
	var mid: Vector2 = r.get_center() - f * (d * 0.5 + BED_BACK + BED_DEPTH * 0.5)
	var ext: Vector2 = Vector2(long, BED_DEPTH) if absf(f.y) > 0.5 else Vector2(BED_DEPTH, long)
	var spot := Rect2(mid - ext * 0.5, ext)
	var own: Rect2 = r.grow(0.3)
	for t: Rect2 in taken:
		if t != own and t.intersects(spot):
			return false
	taken.append(spot.grow(0.4))
	if rng.randi() % 4 == 0 and not look.walls.is_empty():
		var wall: Color = (look.walls[rng.randi() % look.walls.size()] as Array)[1]
		_box("hard", fr, mid, 1.05, yaw, Vector3(2.4, 2.1, 1.8), wall)
		_box("hard", fr, mid, 2.2, yaw, Vector3(2.8, 0.14, 2.2), SHED_ROOF)
		_box("hard", fr, mid - f * 0.91, 0.95, yaw, Vector3(0.8, 1.8, 0.04), WHITE)
		return true
	for sgn: float in [-1.0, 1.0]:
		_box("hard", fr, mid + f * sgn * BED_DEPTH * 0.5, 0.14, yaw, Vector3(long, 0.28, 0.1), TIMBER)
		_box("hard", fr, mid + l * sgn * long * 0.5, 0.14, yaw, Vector3(0.1, 0.28, BED_DEPTH), TIMBER)
	_box("hard", fr, mid, 0.1, yaw, Vector3(long - 0.1, 0.2, BED_DEPTH - 0.1), SOIL)
	for row: int in 3:
		var shade: float = rng.randf_range(0.8, 1.15)
		_box("leaf", fr, mid + f * (float(row) - 1.0) * 0.66, 0.36, yaw, Vector3(long - 0.5, 0.34, 0.34), Color(shade, shade, shade * 0.9))
	var ci: int = rng.randi()
	for sgn2: float in [-1.0, 1.0]:
		_bloom(fr, mid + l * sgn2 * (long * 0.5 - 0.3), 0.2, rng, ci)
	return true


func _chunk(site_at: Vector3) -> Dictionary:
	var key := Vector2i(int(floor(site_at.x / CHUNK_M)), int(floor(site_at.z / CHUNK_M)))
	if not _chunks.has(key):
		_chunks[key] = {"hard": [] as Array[Transform3D], "hard_c": [] as Array[Color], "leaf": [] as Array[Transform3D],
			"leaf_c": [] as Array[Color], "bloom": [] as Array[Transform3D], "bloom_c": [] as Array[Color]}
	return _chunks[key]


## One box of `size` (x across, y up, z along the yaw) with its middle at `p`, `y` up, in frame `fr`.
func _box(kind: String, fr: Transform3D, p: Vector2, y: float, yaw: float, size: Vector3, col: Color) -> void:
	var xf: Transform3D = fr * Transform3D(Basis(Vector3.UP, yaw).scaled_local(size), Vector3(p.x, y, p.y))
	var ch: Dictionary = _chunk(xf.origin)
	(ch[kind] as Array[Transform3D]).append(xf)
	(ch[kind + "_c"] as Array[Color]).append(col)


func _bloom(fr: Transform3D, p: Vector2, y: float, rng: RandomNumberGenerator, colour_i: int) -> void:
	var xf: Transform3D = fr * Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), Vector3(p.x, y, p.y))
	var ch: Dictionary = _chunk(xf.origin)
	(ch["bloom"] as Array[Transform3D]).append(xf)
	(ch["bloom_c"] as Array[Color]).append(OldTownFlowers.colour(colour_i, rng))


func _emit(nm: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material, shadows: bool, at: Vector3) -> MultiMeshInstance3D:
	if xfs.is_empty():
		return null
	var local: Array[Transform3D] = []
	for xf: Transform3D in xfs:
		local.append(Transform3D(xf.basis, xf.origin - at))
	var mi: MultiMeshInstance3D = CityKit.mmi_on(self, nm, mesh, local, cols, mat, shadows, RANGE_M)
	mi.position = at
	mi.visibility_range_end_margin = 10.0
	return mi
