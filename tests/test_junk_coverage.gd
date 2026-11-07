extends GutTest
## [world2] Owner: "the only clear areas should be what you or bots pick up". At generation every
## open ground point of the district (streets, sidewalks, lots, the hub hex outside the yard, the
## streets of building-blocked hexes) has junk close by; only the yard slab is clear.

const NEAR: float = 1.0      # "covered": a piece within this many metres
const GAP: float = 3.0       # nowhere is the nearest piece farther than this

var layout: CityLayout
var field: HexField


func before_all() -> void:
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	layout = CityLayout.new(4471, 150.0, false)
	field = HexField.new(int(cfg.get("radius", 4)), float(cfg.get("hex_size", 10.0)), 4471, layout)
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var ppx: Array = cfg.get("pieces_per_hex", [260, 420])
	field.generate(types, Vector2i(int(ppx[0]), int(ppx[1])))


func _open_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var r: float = field.radius * field.hex_size * 1.5
	var x: float = -r
	while x <= r:
		var z: float = -r
		while z <= r:
			var p := Vector3(x + 0.37, 0.0, z + 0.61)
			z += 1.5
			var own: int = field.owner_hex(p)
			if own < 0 or field.is_water(own):
				continue
			var s: int = layout.surface_at(p.x, p.z)
			if s == CityLayout.Surface.YARD or s == CityLayout.Surface.BUILDING:
				continue
			var near_wall: bool = false
			for o: Vector2 in [Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
				if layout.surface_at(p.x + o.x, p.z + o.y) in [CityLayout.Surface.BUILDING, CityLayout.Surface.YARD]:
					near_wall = true
			if not near_wall:
				out.append(p)
		x += 1.5
	return out


func test_the_whole_district_reads_covered() -> void:
	var pts: Array[Vector3] = _open_points()
	assert_gt(pts.size(), 2000)
	var covered: int = 0
	var worst: float = 0.0
	var by_surf: Dictionary = {}
	for p: Vector3 in pts:
		var s: int = layout.surface_at(p.x, p.z)
		var arr: Array = by_surf.get(s, [0, 0])
		arr[0] += 1
		if not field.pieces_within(p, NEAR).is_empty():
			covered += 1
			arr[1] += 1
		elif field.pieces_within(p, GAP).is_empty():
			worst += 1.0
			if worst < 12:
				gut.p("bare at %s block %d hex %d d%d" % [str(p), layout.block_type_at(p.x, p.z), field.owner_hex(p), Hex.distance(field.hex_axial[field.owner_hex(p)], Vector2i.ZERO)])
		by_surf[s] = arr
	var share: float = float(covered) / pts.size()
	gut.p("coverage %.1f%% of %d open points; per surface %s; bare (> %.0f m from junk) %d" % [share * 100.0, pts.size(), str(by_surf), GAP, int(worst)])
	assert_gt(share, 0.75, "most open ground has junk within a metre")
	for s: int in [CityLayout.Surface.ROAD, CityLayout.Surface.SIDEWALK]:
		var a: Array = by_surf.get(s, [1, 1])
		assert_gt(float(a[1]) / a[0], 0.75, "streets and sidewalks read covered (surface %d)" % s)
	assert_lt(worst / pts.size(), 0.01, "no bare patches")


func test_ring_around_the_base_is_covered() -> void:
	# The spawn view: the streets right around the yard.
	var n: int = 0
	var c: int = 0
	for p: Vector3 in _open_points():
		if Vector2(p.x, p.z).length() > 26.0:
			continue
		n += 1
		if not field.pieces_within(p, NEAR).is_empty():
			c += 1
	assert_gt(n, 200)
	assert_gt(float(c) / n, 0.8, "the streets at the start are not empty")


func test_yard_stays_clear() -> void:
	for pid: int in field.piece_count():
		var p: Vector3 = field.piece_pos[pid]
		assert_ne(layout.surface_at(p.x, p.z), CityLayout.Surface.YARD, "junk on the yard slab at %s" % str(p))
		if layout.surface_at(p.x, p.z) == CityLayout.Surface.YARD:
			return
