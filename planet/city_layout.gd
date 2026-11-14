class_name CityLayout
extends RefCounted
## Pure-data city district: a grid of blocks separated by roads with sidewalks.
## Answers "what surface is here, how high is it, is it inside a building" for the sim, the
## ground shader (via a baked layout image) and the city view.

enum Surface { LOT, ROAD, SIDEWALK, BUILDING, YARD }
enum Block { HUB, BUILDINGS, LANDFILL, PARKING, VACANT }

const PITCH: float = 36.0       # block center spacing
const ROAD_W: float = 9.0       # carriageway width
const WALK_W: float = 2.6       # sidewalk width
const CURB_H: float = 0.12      # sidewalk height above road
const BUILDING_DEPTH: float = 11.0
const ROW_GAP: float = 0.1  # [v8bld] between back-to-back building rows (see _make_buildings)
const YARD_HALF: float = 8.5   # half-size of the hub yard

var seed_value: int
var extent: float               # half-size of the area the layout covers (meters)
var blocks: Dictionary = {}     # Vector2i -> {type, rect: Rect2 (inside sidewalks), buildings: Array[Dictionary]}


var wild: bool = false


func _init(p_seed: int = 4471, p_extent: float = 140.0, p_wild: bool = false) -> void:
	seed_value = p_seed
	extent = p_extent
	wild = p_wild
	_generate()


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 313
	var n: int = int(ceil(extent / PITCH))
	# Inner ring layout (the playable district), outer blocks are mostly buildings.
	var inner: Dictionary = {
		Vector2i(0, 0): Block.HUB,
		Vector2i(1, 0): Block.BUILDINGS, Vector2i(-1, 0): Block.LANDFILL,
		Vector2i(0, 1): Block.BUILDINGS, Vector2i(0, -1): Block.PARKING,
		Vector2i(1, 1): Block.LANDFILL, Vector2i(-1, -1): Block.BUILDINGS,
		Vector2i(1, -1): Block.VACANT, Vector2i(-1, 1): Block.BUILDINGS,
	}
	for bx: int in range(-n, n + 1):
		for bz: int in range(-n, n + 1):
			var key := Vector2i(bx, bz)
			var t: int = inner.get(key, Block.BUILDINGS if rng.randf() < 0.8 else Block.LANDFILL)
			if wild:
				t = Block.HUB if key == Vector2i.ZERO else (Block.LANDFILL if rng.randf() < 0.35 else Block.VACANT)
			var half: float = PITCH * 0.5 - ROAD_W * 0.5 - WALK_W
			var c := Vector2(bx * PITCH, bz * PITCH)
			var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
			var b: Dictionary = {"type": t, "rect": rect, "buildings": []}
			if t == Block.BUILDINGS:
				b["buildings"] = drop_overlaps(_make_buildings(rect, rng, key))
			blocks[key] = b


## Perimeter buildings: each side split into 2-3 buildings of different heights and styles.
## [v8bld] The buildings that don't stand inside an earlier one of the list. _make_buildings'
## east and west sides of a standard block (21.8 m: the north and south rows take the corners) are
## -0.2 m long, yet still got a 6-9 m building each: inside the corner buildings, two facades on
## one plane z-fought (owner: "building was glitching a bit then stopped"), and a taller one stuck
## out of the roof. Callers drop them after they have drawn their numbers for every building, so
## every other building keeps its height, style and seed.
static func drop_overlaps(list: Array) -> Array:
	var kept: Array = []
	for bd: Dictionary in list:
		var r: Rect2 = bd["rect"]
		var inside: bool = false
		for k: Dictionary in kept:
			var o: Rect2 = r.intersection(k["rect"])
			if o.size.x > 0.05 and o.size.y > 0.05:
				inside = true
				break
		if not inside:
			kept.append(bd)
	return kept


func _make_buildings(r: Rect2, rng: RandomNumberGenerator, key: Vector2i) -> Array:
	var out: Array = []
	var d: float = BUILDING_DEPTH
	var dist: float = Vector2(key).length()
	var max_floors: int = 4 + int(dist * 1.2)
	# Four sides: north (-z), south (+z), west (-x), east (+x). Corners belong to north/south.
	# [v8bld] Back to back, two rows keep ROW_GAP m apart: a 21.8 m block is shorter than two 11 m
	# rows, and the overlapping rows' end walls shared a plane (a z-fighting strip up each corner).
	var dz: float = minf(d, r.size.y * 0.5 - ROW_GAP * 0.5)
	var dx: float = minf(d, r.size.x * 0.5 - ROW_GAP * 0.5)
	var sides: Array = [
		{"face": Vector2(0, -1), "rect": Rect2(r.position, Vector2(r.size.x, dz))},
		{"face": Vector2(0, 1), "rect": Rect2(Vector2(r.position.x, r.end.y - dz), Vector2(r.size.x, dz))},
		{"face": Vector2(-1, 0), "rect": Rect2(Vector2(r.position.x, r.position.y + d), Vector2(dx, r.size.y - 2.0 * d))},
		{"face": Vector2(1, 0), "rect": Rect2(Vector2(r.end.x - dx, r.position.y + d), Vector2(dx, r.size.y - 2.0 * d))},
	]
	for si: int in sides.size():
		var s: Dictionary = sides[si]
		var sr: Rect2 = s["rect"]
		var seg: int = 0
		var along_x: bool = absf((s["face"] as Vector2).y) > 0.5
		var length: float = sr.size.x if along_x else sr.size.y
		var bays: int = int(floor(length / 3.0))
		var cuts: int = rng.randi_range(1, 2)
		var splits: Array[int] = []
		for k: int in cuts:
			splits.append(rng.randi_range(2, maxi(bays - 2, 3)))
		splits.sort()
		var start: int = 0
		splits.append(bays)
		for e: int in splits:
			if e - start < 2:
				continue
			var a: float = start * 3.0
			var len_m: float = (e - start) * 3.0
			var br: Rect2 = Rect2(sr.position + Vector2(a, 0), Vector2(len_m, sr.size.y)) if along_x \
				else Rect2(sr.position + Vector2(0, a), Vector2(sr.size.x, len_m))
			var bdict: Dictionary = {
				"rect": br, "face": s["face"], "bays": e - start,
				"floors": rng.randi_range(2, max_floors),
				"style": "factory" if rng.randf() < 0.35 else "apartments",
				"seed": rng.randi(), "ruined": rng.randf() < 0.15,
			}
			# [v8bld] Trim level (BuildingDetail.TRIM_STEP): neighbours in a row alternate and every side
			# has its own pair, so the cornices and belt courses of two buildings never share a plane.
			bdict["trim"] = seg % 2 + 2 * si
			seg += 1
			out.append(bdict)
			start = e
	return out


func block_key_at(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x / PITCH), roundi(z / PITCH))


func surface_at(x: float, z: float) -> int:
	if wild:
		return Surface.YARD if (absf(x) < YARD_HALF and absf(z) < YARD_HALF) else Surface.LOT
	var key: Vector2i = block_key_at(x, z)
	var c := Vector2(key) * PITCH
	var lx: float = absf(x - c.x)
	var lz: float = absf(z - c.y)
	var road_edge: float = PITCH * 0.5 - ROAD_W * 0.5
	if lx > road_edge or lz > road_edge:
		return Surface.ROAD
	if lx > road_edge - WALK_W or lz > road_edge - WALK_W:
		return Surface.SIDEWALK
	var b: Dictionary = blocks.get(key, {})
	if b.is_empty():
		return Surface.LOT
	if int(b["type"]) == Block.HUB:
		# A small swept yard around the hub; the rest of the block is still junk lot.
		return Surface.YARD if (lx < YARD_HALF and lz < YARD_HALF) else Surface.LOT
	for bd: Dictionary in b["buildings"]:
		if (bd["rect"] as Rect2).has_point(Vector2(x, z)):
			return Surface.BUILDING
	return Surface.LOT


func block_type_at(x: float, z: float) -> int:
	return int(blocks.get(block_key_at(x, z), {}).get("type", Block.VACANT))


func height_at(x: float, z: float) -> float:
	var s: int = surface_at(x, z)
	return CURB_H if s == Surface.SIDEWALK else 0.0


## Distance from a road point to the nearest curb (0 at the curb). Large when not on a road.
func curb_distance(x: float, z: float) -> float:
	if wild:
		return INF
	var key: Vector2i = block_key_at(x, z)
	var c := Vector2(key) * PITCH
	var road_edge: float = PITCH * 0.5 - ROAD_W * 0.5
	var lx: float = absf(x - c.x)
	var lz: float = absf(z - c.y)
	var dx: float = lx - road_edge if lx > road_edge else INF
	var dz: float = lz - road_edge if lz > road_edge else INF
	return minf(dx, dz)


## Lane marking mask at a road point: dashed center lines (0..1).
func lane_mark(x: float, z: float) -> float:
	if wild:
		return 0.0
	var key: Vector2i = block_key_at(x, z)
	var c := Vector2(key) * PITCH
	var lx: float = x - c.x
	var lz: float = z - c.y
	var road_edge: float = PITCH * 0.5 - ROAD_W * 0.5
	var m: float = 0.0
	if absf(absf(lx) - PITCH * 0.5) < 0.08 and absf(lz) < road_edge - 1.0:
		m = 1.0 if fmod(absf(z) + 100.0, 4.0) < 2.2 else 0.0
	if absf(absf(lz) - PITCH * 0.5) < 0.08 and absf(lx) < road_edge - 1.0:
		m = 1.0 if fmod(absf(x) + 100.0, 4.0) < 2.2 else 0.0
	return m


## Bakes the layout to an image for the ground shader: R = surface id / 4, G = lane mark,
## B = sidewalk-edge factor (curb), A = height. `res` meters per pixel over [-size/2, size/2].
func bake_image(size_m: float, res: float = 0.25) -> Image:
	var px: int = int(size_m / res)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	_bake_rows(img, 0, px, size_m, res)
	return img


## Rows [r0, r1) of the bake into img's rows 0.. (read-only on the layout: safe on worker threads).
func _bake_rows(img: Image, r0: int, r1: int, size_m: float, res: float) -> void:
	var px: int = img.get_width()
	for j: int in range(r0, r1):
		var z: float = -size_m * 0.5 + (j + 0.5) * res
		for i: int in px:
			var x: float = -size_m * 0.5 + (i + 0.5) * res
			var s: int = surface_at(x, z)
			var lane: float = lane_mark(x, z) if s == Surface.ROAD else 0.0
			var curb: float = 0.0
			if s == Surface.ROAD:
				curb = clampf(1.0 - curb_distance(x, z) / 1.6, 0.0, 1.0)
			img.set_pixel(i, j - r0, Color(float(s) / 4.0, lane, curb, height_at(x, z) / 0.5))


## [leftovers] bake_image on WorkerThreadPool threads, one row band per task, so the 1200 x 1200
## bake (about 3 s of GDScript) runs beside the district build. Same pixels as bake_image.
## Collect with `await bake_collect(job)` (BuildBudget yields frames while it waits).
func bake_start(size_m: float, res: float = 0.25, bands: int = 1) -> Dictionary:
	var px: int = int(size_m / res)
	var rows: int = ceili(float(px) / bands)
	var list: Array = []
	for b: int in bands:
		var r0: int = mini(px, b * rows)
		var r1: int = mini(px, r0 + rows)
		list.append([r0, r1, Image.create(px, maxi(1, r1 - r0), false, Image.FORMAT_RGBA8)])
	var job: Dictionary = {"px": px, "size": size_m, "res": res, "bands": list}
	job["group"] = BuildBudget.add_group_task(_bake_band.bind(job), bands, "layout bake")
	return job


func _bake_band(i: int, job: Dictionary) -> void:
	var band: Array = job["bands"][i]
	if int(band[1]) > int(band[0]):
		_bake_rows(band[2], band[0], band[1], job["size"], job["res"])


func bake_collect(job: Dictionary) -> Image:
	await BuildBudget.join_group(int(job["group"]))
	var px: int = job["px"]
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for band: Array in job["bands"]:
		var h: int = int(band[1]) - int(band[0])
		if h > 0:
			img.blit_rect(band[2], Rect2i(0, 0, px, h), Vector2i(0, band[0]))
	return img


## All building records in blocks within `radius` meters of the origin (plus the rest beyond).
func all_buildings() -> Array:
	var out: Array = []
	for key: Vector2i in blocks:
		for bd: Dictionary in blocks[key]["buildings"]:
			out.append(bd)
	return out
