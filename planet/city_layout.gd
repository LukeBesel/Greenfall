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
const YARD_HALF: float = 8.5   # half-size of the hub yard

var seed_value: int
var extent: float               # half-size of the area the layout covers (meters)
var blocks: Dictionary = {}     # Vector2i -> {type, rect: Rect2 (inside sidewalks), buildings: Array[Dictionary]}


func _init(p_seed: int = 4471, p_extent: float = 140.0) -> void:
	seed_value = p_seed
	extent = p_extent
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
			var half: float = PITCH * 0.5 - ROAD_W * 0.5 - WALK_W
			var c := Vector2(bx * PITCH, bz * PITCH)
			var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
			var b: Dictionary = {"type": t, "rect": rect, "buildings": []}
			if t == Block.BUILDINGS:
				b["buildings"] = _make_buildings(rect, rng, key)
			blocks[key] = b


## Perimeter buildings: each side split into 2-3 buildings of different heights and styles.
func _make_buildings(r: Rect2, rng: RandomNumberGenerator, key: Vector2i) -> Array:
	var out: Array = []
	var d: float = BUILDING_DEPTH
	var dist: float = Vector2(key).length()
	var max_floors: int = 4 + int(dist * 1.2)
	# Four sides: north (-z), south (+z), west (-x), east (+x). Corners belong to north/south.
	var sides: Array = [
		{"face": Vector2(0, -1), "rect": Rect2(r.position, Vector2(r.size.x, d))},
		{"face": Vector2(0, 1), "rect": Rect2(Vector2(r.position.x, r.end.y - d), Vector2(r.size.x, d))},
		{"face": Vector2(-1, 0), "rect": Rect2(Vector2(r.position.x, r.position.y + d), Vector2(d, r.size.y - 2.0 * d))},
		{"face": Vector2(1, 0), "rect": Rect2(Vector2(r.end.x - d, r.position.y + d), Vector2(d, r.size.y - 2.0 * d))},
	]
	for s: Dictionary in sides:
		var sr: Rect2 = s["rect"]
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
			out.append({
				"rect": br, "face": s["face"], "bays": e - start,
				"floors": rng.randi_range(2, max_floors),
				"style": "factory" if rng.randf() < 0.35 else "apartments",
				"seed": rng.randi(), "ruined": rng.randf() < 0.15,
			})
			start = e
	return out


func block_key_at(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x / PITCH), roundi(z / PITCH))


func surface_at(x: float, z: float) -> int:
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
	for j: int in px:
		var z: float = -size_m * 0.5 + (j + 0.5) * res
		for i: int in px:
			var x: float = -size_m * 0.5 + (i + 0.5) * res
			var s: int = surface_at(x, z)
			var lane: float = lane_mark(x, z) if s == Surface.ROAD else 0.0
			var curb: float = 0.0
			if s == Surface.ROAD:
				curb = clampf(1.0 - curb_distance(x, z) / 1.6, 0.0, 1.0)
			img.set_pixel(i, j, Color(float(s) / 4.0, lane, curb, height_at(x, z) / 0.5))
	return img


## All building records in blocks within `radius` meters of the origin (plus the rest beyond).
func all_buildings() -> Array:
	var out: Array = []
	for key: Vector2i in blocks:
		for bd: Dictionary in blocks[key]["buildings"]:
			out.append(bd)
	return out
