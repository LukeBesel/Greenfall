class_name VerdanceSite
extends Node3D
## [orbD] Verdance's hub sites on the walkable globe. A small local CityLayout (a 3 x 3 block
## grid around the hub yard) gives the street grid: CityView lays its sidewalks, kerbs, lot
## fences and street furniture, and every building is a shared art-kit building (KitBuilding:
## modules, towers, hangars, tank farms, machine housings, art/kit/**, docs/ART_KIT.md) on its
## own kit ground patch, broken while the base is ruined, repaired at level 2-3, restored at 4-5.
## Landfill lots get kit debris, crate stacks and tipped barrels. StreetDressing adds the yard
## (slab, paint, puddles, weeds, drifts, the landmark, the ruin layer); no facade dressing.
## Everything is in site-local metres (+Y up, y = 0 on the pad, x east, z south), so it stands on
## a SphereTerrain site pad under PlanetEnvs.build_site, or alone in a preview.
## Sites:
##   start_yard  hub 0: the landing yard (pod + broken workbench + trash bin go on its anchors;
##               every other machine is a Hub build), intact-but-dusty blocks around it
##   ruin_block  hubs 1..: ruined blocks (most buildings broken off, rubble, dead lamps), the hub
##               yard in the middle; seeded per hub, so no two look alike
## The ruin goes when the base is rebuilt: set_level(l) shows StreetDressing's level layers.
## World-space shader maths (building_city, deco, yard_slab, mural ...) run in site-local space
## through the `site_inv` shader global, which SiteManager points at the nearest site.

const SITES: Array[String] = ["start_yard", "ruin_block"]
## [v1world] Hub blocks use the flat city's buildings (CityView) and facade dressing, not kit buildings.
const CITY_BUILDINGS: bool = true
const START_EXTENT: float = 108.0  # [v3city] 7 x 7 blocks cut to the start pad's 140 m flat circle (was 3 x 3)
## [v3city] The start town (owner item 42: "a full, lived-in city"). Blocks whose far corner lies
## past TOWN_R stay off the pad (the ground blends back to the sphere beyond 140 m). Building
## footprints keep GOAL_R m off the yard centre: the first hexes Lumi cleans (the small-only cells,
## YardKeepOut.SMALL_ONLY_M) stay whole. Floors per ring: forecourt row, mid-rise, skyline towers.
const TOWN_R: float = 136.0
const GOAL_R: float = 40.0
const HUB_TOWN_R: float = 116.0  # [v3city] other hubs' pads are 120 m (OrbitPlanet.VERDANCE_HUB_SITE_M)
const RING_FLOORS: Array = [[0, 0], [3, 5], [3, 8], [7, 16]]
const TOWER_SHARE: float = 0.22  # ring-3 buildings that shoot up to 18-26 floors
## [v3city] Town characters, so no two hubs look copy-pasted. Per ring 1..3: floors [min, max];
## tower: share of outer-ring buildings that shoot up (tower_f floors); lots: share of open
## blocks; factory: share of works/warehouse fronts; ruin: broken-off share (ring 1, rings 2+);
## houses: small detached buildings with yards instead of perimeter rows.
const KINDS: Dictionary = {
	"start": {"rings": [[3, 5], [3, 8], [7, 16]], "tower": 0.22, "tower_f": [18, 26], "lots": 0.14, "factory": 0.35, "ruin": [0.3, 0.2]},
	"downtown": {"rings": [[5, 9], [8, 16], [10, 18]], "tower": 0.4, "tower_f": [18, 30], "lots": 0.06, "factory": 0.08, "ruin": [0.4, 0.35]},
	"oldtown": {"rings": [[3, 5], [3, 6], [3, 7]], "tower": 0.0, "tower_f": [0, 0], "lots": 0.12, "factory": 0.12, "ruin": [0.45, 0.4]},
	"industrial": {"rings": [[2, 4], [2, 5], [2, 6]], "tower": 0.0, "tower_f": [0, 0], "lots": 0.32, "factory": 0.85, "ruin": [0.5, 0.45]},
	"suburb": {"rings": [[1, 2], [1, 3], [1, 3]], "tower": 0.0, "tower_f": [0, 0], "lots": 0.12, "factory": 0.05, "ruin": [0.35, 0.3], "houses": true},
	"harbour": {"rings": [[3, 6], [3, 7], [4, 8]], "tower": 0.05, "tower_f": [10, 14], "lots": 0.16, "factory": 0.45, "ruin": [0.45, 0.4]},
}
## Per hub (harbours take over where the lake reaches in): every character turns up on Verdance.
const KIND_BY_HUB: Array[String] = ["oldtown", "downtown", "oldtown", "suburb", "industrial", "oldtown", "suburb", "industrial", "downtown", "suburb"]
const HUB_EXTENT: float = 36.0     # 3 x 3 blocks, 108 m
## Which share of buildings are broken off on a ruined hub.
const RUIN_SHARE: float = 0.7
const START_RUIN_SHARE: float = 0.4

var site_id: String = "ruin_block"
var hub_index: int = 0
var seed_value: int = 4471
var level: int = 1
var restoration: float = 0.0
var layout: CityLayout
var city: CityView
var dressing: StreetDressing
var kit_root: Node3D
var kits: Array[KitBuilding] = []
var _foot: Array[Rect2] = []
var _kit_state: String = ""
var district_name: String = ""
var _rubble: Node3D
var furniture: StreetFurniture  # [v3city] the start town's street life
var town_r: float = TOWN_R  # [v3city] the town's reach on its pad (the pad's flat radius, less a margin)
var kind: String = "start"   # [v3city] the town's character (KINDS)
var outskirts: TownOutskirts  # [v3city] the city past the pad (the skyline)
var globe_ctx: Dictionary = {}  # [v3city] {terrain, grid, cells, xf, clear} from SiteManager
## [v3city] func(x, z) -> bool: a site-local point on a lake cell (the start yard is by a lake).
var water: Callable


func _wet(x: float, z: float) -> bool:
	return water.is_valid() and bool(water.call(x, z))


## [v3city] Share of sample points (every `step` m) of a rect that lie on water.
func _wet_share(r: Rect2, step: float = 3.0) -> float:
	if not water.is_valid():
		return 0.0
	var n: int = 0
	var w: int = 0
	var z: float = r.position.y + step * 0.5
	while z < r.end.y:
		var x: float = r.position.x + step * 0.5
		while x < r.end.x:
			n += 1
			w += 1 if _wet(x, z) else 0
			x += step
		z += step
	for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		n += 1
		w += 1 if _wet(p.x, p.y) else 0
	return float(w) / maxf(1.0, float(n))


## Builds a site under `parent`; returns the VerdanceSite node.
static func build(parent: Node3D, p_site: String, stage: int, p_restoration: float, opts: Dictionary = {}) -> VerdanceSite:
	var s := VerdanceSite.new()
	s.name = "VerdanceSite_" + p_site
	s.site_id = p_site if p_site in SITES else "ruin_block"
	s.hub_index = int(opts.get("hub_index", 0 if p_site == "start_yard" else 1))
	s.seed_value = int(opts.get("seed", 4471)) + s.hub_index * 7919
	s.level = clampi(stage, 1, 5)
	s.restoration = clampf(p_restoration, 0.0, 1.0)
	s.district_name = str(opts.get("name", ""))
	if opts.get("water") is Callable:
		s.water = opts["water"]  # [v3city]
	if opts.get("globe") is Dictionary:
		s.globe_ctx = opts["globe"]  # [v3city]
	if opts.has("flat"):
		s.town_r = float(opts["flat"]) - 4.0  # [v3city]
	elif s.site_id != "start_yard":
		s.town_r = HUB_TOWN_R
	parent.add_child(s)
	await s._make()
	return s


## Site-local rectangles that are solid (building footprints): the globe clears junk under them.
func footprints() -> Array[Rect2]:
	return _foot.duplicate()


## [v3city] Small solid things the junk keeps off (parked wrecks, bus shelters), site-local.
func prop_rects() -> Array[Rect2]:
	return _extra_foot.duplicate()


## Anchors inside the hub yard (the centre block, ~11 m half-size): the depot and the bench on
## the south corners either side of the pod door, the rocket pad on the north side. Lumi spawns
## at (0, 6) facing north, so the way out of the yard stays open.
func anchors() -> Dictionary:
	var a: Dictionary = {
		"depot": [Vector3(8.0, 0, 7.5), -PI * 0.5],
		"bench": [Vector3(-8.0, 0, 7.5), PI * 0.5],
		"door": [Vector3(0, 0, 9.5), 0.0],
		"rocket_pad": [Vector3(0, 0, -6.5), 0.0],
	}
	if site_id == "start_yard":
		a.merge(START_YARD_ANCHORS, true)  # [v1yard] the start yard's depot moves by the bench
	return a


## [orbD] The start yard's machines and Hub builds (orbB ports Camp onto these; owner rules: the
## yard starts with only the pod, the broken bench and the bin; interactables at least 3 m apart;
## the lane north out of the yard, |x| < 2.5 m, stays open). East: depot, bin, stations, radio,
## signal tower, telescope. West: bench (shack over it), generator, composter, locker, camera
## bot, nursery. The pod sits behind Lumi's spawn at (0, 6). Lamps on the yard's corners.
const START_YARD_ANCHORS: Dictionary = {
	"pod": [Vector3(0, 0, 9.8), 0.0],
	# [v1yard] The trash bin (the depot and its bin's reach) on the west side, 5.5 m from the bench,
	# in a marked, lit bay on the pad's edge: trash, bin and bench a few steps apart.
	"depot": [Vector3(-8.0, 0, 2.0), PI * 0.5],
	"bin": [Vector3(-8.0, 0, -1.3), PI * 0.5],
	"stations": [Vector3(16.5, 0, 1.5), 0.0],  # out on the street east of the yard (flat: "keep the base yard free")
	"radio": [Vector3(5.0, 0, -1.5), -PI * 0.5],
	"signal_tower": [Vector3(8.0, 0, -7.5), -PI * 0.5],
	"telescope": [Vector3(4.8, 0, -9.0), 0.0],
	"shack": [Vector3(-7.35, 0, 7.5), PI * 0.5],  # over the bench: the flat lean-to has it 0.65 m in from its centre
	"fabricator": [Vector3(-6.0, 0, -9.6), 0.0],
	"generator": [Vector3(-5.0, 0, 9.5), PI],
	"composter": [Vector3(8.5, 0, 3.8), -PI * 0.5],  # [v1yard] east, where the depot was
	"locker": [Vector3(8.5, 0, 0.2), -PI * 0.5],
	"camera_bot": [Vector3(-5.0, 0, -2.0), PI * 0.5],
	"nursery": [Vector3(-7.5, 0, -5.5), PI * 0.5],
	"lamps_0": [Vector3(-3.6, 0, -10.0), 0.0],
	"lamps_1": [Vector3(3.6, 0, -10.0), 0.0],
	"lamps_2": [Vector3(-10.2, 0, 10.2), 0.0],
	"lamps_3": [Vector3(10.2, 0, 10.2), 0.0],
}


## Half-size of the built area (m).
func extent() -> float:
	return layout.extent + CityLayout.PITCH * 0.5 if layout else HUB_EXTENT


func set_level(l: int) -> void:
	level = clampi(l, 1, 5)
	if dressing:
		dressing.set_level(level, is_inside_tree())
	if _rubble:
		_rubble.visible = level <= 1
	var ks: String = kit_state(level)
	if furniture:
		furniture.set_state(ks)  # [v3city]
	if ks != _kit_state:
		_kit_state = ks
		for k: KitBuilding in kits:
			k.set_state(ks)
			k.set_powered(level >= 2)
		_build_lots()
		if kit_root:
			KitBatch.merge(kit_root)  # [orbE] the rebuilt bodies merge again


## The kit state for a base level: broken (1), repaired (2-3), restored (4-5).
static func kit_state(l: int) -> String:
	return "broken" if l <= 1 else ("repaired" if l <= 3 else "restored")


func set_restoration(r: float) -> void:
	restoration = clampf(r, 0.0, 1.0)


# --- Build ----------------------------------------------------------------------------------

func _make() -> void:
	var start: bool = site_id == "start_yard"
	layout = CityLayout.new(seed_value, START_EXTENT)  # [v3city] every Verdance hub is a town now
	kind = "start" if start else _pick_kind()
	_town_layout()
	BuildBudget.lap("site:town layout")
	city = CityView.new()
	city.name = "City"
	city.skyline = false
	city.buildings = CITY_BUILDINGS  # [v1world] the flat district's brick and factory buildings (owner, Nov 8); was the kit's
	city.flush_walks = true
	city.water_fn = water  # [v3city]
	# [v3city] kit facades on the inner ring, proxies (with colliders) beyond; props everywhere
	city.detail_ring = 1
	city.proxy_collide = true
	city.prop_ring = 3
	city.prop_radius = town_r
	add_child(city)
	await city.build(layout, _sidewalk_material())
	BuildBudget.lap("site:city")
	await BuildBudget.check("site:roads")  # [orbE] behind the loading screen: a few kit buildings per frame
	_roads()
	BuildBudget.lap("site:roads")
	await BuildBudget.check("site:kit")
	await _kit_blocks()
	if true:  # [v3city] bus stops, benches, bins, signs, traffic lights, road paint, parked wrecks
		furniture = StreetFurniture.new()
		furniture.name = "Furniture"
		furniture.water_fn = water
		furniture.town_r = town_r
		furniture.goal_r = GOAL_R if start else 18.0
		furniture.state = kit_state(level)
		furniture.buildings = _foot.duplicate()
		furniture.big_ship = start
		var pb: Variant = city.get("_prop_body")
		if pb is Node:
			for cs: Node in (pb as Node).get_children():
				if cs is CollisionShape3D:
					furniture.obstacles.append(Vector2((cs as Node3D).position.x, (cs as Node3D).position.z))
		add_child(furniture)
		await furniture.build(layout, seed_value)
		BuildBudget.lap("site:furniture")
		_extra_foot.append_array(furniture.prop_rects)
		if DevHooks.has("load-report") or DevHooks.has("town-map"):
			print("[town] street furniture: %s, %d road paint quads" % [str(furniture.counts), furniture._paint_n])
	if not globe_ctx.is_empty():  # [v3city] the city round the pad
		outskirts = TownOutskirts.new()
		outskirts.name = "Outskirts"
		outskirts.terrain = globe_ctx["terrain"]
		outskirts.grid = globe_ctx["grid"]
		outskirts.cells = globe_ctx["cells"]
		outskirts.site_xf = globe_ctx["xf"]
		outskirts.town_r = town_r
		outskirts.r_in = town_r - 8.0
		outskirts.seed_value = seed_value
		outskirts.kind = kind
		add_child(outskirts)
		await outskirts.build()
		BuildBudget.lap("site:outskirts")
		print("[town] hub %d outskirts (%s): %s" % [hub_index, kind, str(outskirts.stats)])
		var ko: Variant = globe_ctx.get("keep_out")
		if ko is YardKeepOut:
			(ko as YardKeepOut).add_world("outskirts%d" % hub_index, outskirts.foot)
			if not start:  # the pad town's buildings and wrecks too (hub 0's are in the yard's own frame)
				var items: Array = []
				var sxf: Transform3D = globe_ctx["xf"]
				for fr: Rect2 in _foot + _extra_foot:
					items.append([sxf, fr])
				(ko as YardKeepOut).add_world("town%d" % hub_index, items)
	dressing = StreetDressing.new()
	dressing.name = "Dressing"
	dressing.skip_facades = not CITY_BUILDINGS  # [v1world] shopfronts, awnings, neon, murals, billboard, string lights
	dressing.kit_yard = true
	add_child(dressing)
	await dressing.build(layout, null, hub_index, district_name, "", level)
	set_level(level)
	BuildBudget.lap("site:set_level")
	if DevHooks.has("town-map") and (start or DevHooks.has("town-map-hubs")):
		_town_map(DevHooks.get_s("town-map", "user://town_map.png") if start else DevHooks.get_s("town-map", "user://town_map.png").replace(".png", "_hub%d.png" % hub_index))


## [v3city] The start town's blocks: the yard in the middle, the main street north and south of it
## open (landfill, then parking), a forecourt ring whose building rows stand back past GOAL_R and
## face the yard across their lots, mid-rise blocks round that, and skyline towers on the outer
## ring. Blocks off the pad are dropped; some lots stay open in every ring (junk to clean).
func _town_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 67
	var lake: int = 0
	for key: Vector2i in layout.blocks.keys():
		var b: Dictionary = layout.blocks[key]
		var r: Rect2 = b["rect"]
		var far: float = Vector2(maxf(absf(r.position.x), absf(r.end.x)), maxf(absf(r.position.y), absf(r.end.y))).length()
		if far > town_r:
			layout.blocks.erase(key)
			continue
		if key == Vector2i.ZERO:
			continue
		# The lake: blocks whose kerb ring runs into the water go (no sidewalks over the lake).
		var walk_r: Rect2 = r.grow(CityLayout.WALK_W)
		if _wet_share(walk_r, 2.5) > 0.45:
			layout.blocks.erase(key)
			lake += 1
			continue
		var ring: int = maxi(absi(key.x), absi(key.y))
		var pr: Dictionary = KINDS[kind]
		var start: bool = kind == "start"
		var t: int = CityLayout.Block.BUILDINGS
		if start and key.x == 0 and ring <= 2:
			t = CityLayout.Block.LANDFILL if ring == 1 else CityLayout.Block.PARKING  # the main street's open lots
		elif (ring >= 2 or not start) and rng.randf() < float(pr["lots"]):
			var lr: float = rng.randf()
			t = CityLayout.Block.PARKING if (kind == "industrial" and lr < 0.4) else (CityLayout.Block.LANDFILL if lr < 0.7 else CityLayout.Block.VACANT)
		b["type"] = t
		b["buildings"] = []
		if t == CityLayout.Block.BUILDINGS:
			if start and ring == 1:
				b["buildings"] = _forecourt_row(r, key, rng)
			elif pr.get("houses", false):
				b["buildings"] = _houses(r, rng)
			else:
				b["buildings"] = layout._make_buildings(r, rng, key)
			b["buildings"] = (b["buildings"] as Array).filter(func(bd: Dictionary) -> bool: return _wet_share((bd["rect"] as Rect2).grow(2.0), 2.0) == 0.0)
			var fl: Array = (pr["rings"] as Array)[clampi(ring, 1, 3) - 1]
			for bd: Dictionary in b["buildings"]:
				var f: int = rng.randi_range(int(fl[0]), int(fl[1]))
				if ring >= (3 if start else 2) and rng.randf() < float(pr["tower"]):
					f = rng.randi_range(int(pr["tower_f"][0]), int(pr["tower_f"][1]))
				if not start or ring > 1:
					bd["style"] = "factory" if rng.randf() < float(pr["factory"]) else "apartments"
				bd["ruined"] = rng.randf() < float(pr["ruin"][0 if ring <= 1 else 1])
				bd["floors"] = maxi(1 if pr.get("houses", false) else 2, f - (rng.randi_range(1, 3) if bd["ruined"] and f > 3 else 0))
				if bd["style"] == "factory" and f > 8:
					bd["style"] = "apartments"  # towers are offices and flats, not sheds
			if b["buildings"].is_empty():
				b["type"] = CityLayout.Block.LANDFILL
		layout.blocks[key] = b
	var nb: int = 0
	var tall: int = 0
	var kinds: Dictionary = {}
	for key: Vector2i in layout.blocks:
		var bl: Dictionary = layout.blocks[key]
		kinds[int(bl["type"])] = int(kinds.get(int(bl["type"]), 0)) + 1
		for bd: Dictionary in bl["buildings"]:
			nb += 1
			tall = maxi(tall, int(bd["floors"]))
	print("[town] hub %d %s town: %d blocks (types %s), %d buildings up to %d floors, %d blocks left to the lake" % [hub_index, kind, layout.blocks.size(), str(kinds), nb, tall, lake])


## [v3city] Dev: --town-map=PATH writes a top-down plan of the town (0.5 m a pixel): lake blue,
## streets grey, sidewalks light, lots brown, buildings shaded by height, the goal disc outlined.
func _town_map(path: String) -> void:
	var half: float = 170.0
	var res: float = 0.5
	var px: int = int(half * 2.0 / res)
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	for j: int in px:
		var z: float = -half + (j + 0.5) * res
		for i: int in px:
			var x: float = -half + (i + 0.5) * res
			var col := Color(0.42, 0.36, 0.28)  # junk ground
			var srf: int = layout.surface_at(x, z)
			if Vector2(x, z).length() > town_r + 10.0:
				col = Color(0.36, 0.32, 0.25)
			elif srf == CityLayout.Surface.ROAD:
				col = Color(0.3, 0.3, 0.32)
			elif srf == CityLayout.Surface.SIDEWALK and layout.blocks.has(layout.block_key_at(x, z)):
				col = Color(0.62, 0.6, 0.56)
			if _wet(x, z):
				col = col.lerp(Color(0.15, 0.35, 0.6), 0.75)
			if absf(Vector2(x, z).length() - GOAL_R) < 0.4:
				col = Color(1, 0.3, 0.6)
			img.set_pixel(i, j, col)
	var to_px := func(p: Vector2) -> Vector2i: return Vector2i(int((p.x + half) / res), int((p.y + half) / res))
	for key: Vector2i in layout.blocks:
		for bd: Dictionary in layout.blocks[key]["buildings"]:
			var r: Rect2 = bd["rect"]
			var f: float = clampf(float(bd["floors"]) / 26.0, 0.0, 1.0)
			var c := Color(0.95, 0.85, 0.6).lerp(Color(0.85, 0.2, 0.15), f)
			var a: Vector2i = to_px.call(r.position)
			var b: Vector2i = to_px.call(r.end)
			img.fill_rect(Rect2i(a, b - a), c)
			img.fill_rect(Rect2i(a, Vector2i(b.x - a.x, 1)), Color.BLACK)
			img.fill_rect(Rect2i(a, Vector2i(1, b.y - a.y)), Color.BLACK)
	for r2: Rect2 in _extra_foot:
		var a2: Vector2i = to_px.call(r2.position)
		var b2: Vector2i = to_px.call(r2.end)
		img.fill_rect(Rect2i(a2, (b2 - a2).max(Vector2i.ONE)), Color(0.1, 0.9, 0.3))
	img.save_png(path)
	print("[town] map -> %s" % path)


var _extra_foot: Array[Rect2] = []  # [v3city] furniture footprints (cars, shelters): junk keeps off them


## [v3city] The hub's character: a harbour where the lake reaches into the town, else one of
## HUB_KINDS, turned per hub so neighbouring hubs differ.
func _pick_kind() -> String:
	var wet: int = 0
	var n: int = 0
	for k: int in 48:
		var a: float = TAU * k / 48.0
		for rr: float in [40.0, 70.0, 100.0]:
			n += 1
			wet += 1 if _wet(cos(a) * rr, sin(a) * rr) else 0
	if float(wet) / n > 0.12:
		return "harbour"
	return KIND_BY_HUB[hub_index % KIND_BY_HUB.size()]


## [v3city] A suburb block: detached houses (one or two floors) round the block's edge, facing
## the streets, with yards between them.
static func _houses(r: Rect2, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var sides: Array = [[Vector2(0, -1), r.position, Vector2(1, 0)], [Vector2(0, 1), Vector2(r.position.x, r.end.y - 8.0), Vector2(1, 0)],
		[Vector2(-1, 0), Vector2(r.position.x, r.position.y + 9.0), Vector2(0, 1)], [Vector2(1, 0), Vector2(r.end.x - 8.0, r.position.y + 9.0), Vector2(0, 1)]]
	for sd: Array in sides:
		var face: Vector2 = sd[0]
		var o: Vector2 = sd[1]
		var along: Vector2 = sd[2]
		var length: float = (r.size.x if along.x > 0.5 else r.size.y - 18.0)
		var t: float = rng.randf_range(0.0, 2.0)
		while t + 9.0 <= length:
			if rng.randf() < 0.82:
				var depth: float = rng.randf_range(6.5, 8.0)
				var p: Vector2 = o + along * t
				var setback: float = rng.randf_range(0.5, 2.0)
				var br: Rect2
				if along.x > 0.5:
					var z0: float = p.y + (setback if face.y < 0 else 8.0 - depth - setback)
					br = Rect2(Vector2(p.x, z0), Vector2(9.0, depth))
				else:
					var x0: float = p.x + (setback if face.x < 0 else 8.0 - depth - setback)
					br = Rect2(Vector2(x0, p.y), Vector2(depth, 9.0))
				out.append({"rect": br, "face": face, "bays": 3, "floors": 1, "style": "apartments", "seed": rng.randi(), "ruined": false})
			t += rng.randf_range(10.5, 13.0)
	return out


## [v3city] A forecourt block next to the yard: building rows along its outer edges only, set back
## past GOAL_R and facing the yard; the lot in front stays open ground (junk, parked wrecks).
func _forecourt_row(r: Rect2, key: Vector2i, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var depth: float = CityLayout.BUILDING_DEPTH
	var rows: Array = []  # [Rect2, face]
	if key.x != 0:
		var sx: float = signf(key.x)
		var x_out: float = r.end.x if sx > 0 else r.position.x
		rows.append([Rect2(Vector2(x_out - depth if sx > 0 else x_out, r.position.y), Vector2(depth, r.size.y)), Vector2(-sx, 0)])
	if key.y != 0:
		var sz: float = signf(key.y)
		var z_out: float = r.end.y if sz > 0 else r.position.y
		var x0: float = r.position.x
		var x1: float = r.end.x
		if key.x != 0:  # the corner belongs to the x row
			if key.x > 0:
				x1 -= depth
			else:
				x0 += depth
		rows.append([Rect2(Vector2(x0, z_out - depth if sz > 0 else z_out), Vector2(x1 - x0, depth)), Vector2(0, -sz)])
	for row: Array in rows:
		var rr: Rect2 = _goal_clip(row[0], row[1])
		if rr.size.x < 6.0 or rr.size.y < 6.0:
			continue
		var face: Vector2 = row[1]
		var along_x: bool = absf(face.y) > 0.5
		var length: float = rr.size.x if along_x else rr.size.y
		var bays_all: int = int(floor(length / 3.0))
		var start: int = 0
		while bays_all - start >= 2:
			var nb: int = mini(bays_all - start, rng.randi_range(3, 5))
			if bays_all - start - nb < 2:
				nb = bays_all - start
			var a: float = start * 3.0
			var br: Rect2 = Rect2(rr.position + Vector2(a, 0), Vector2(nb * 3.0, rr.size.y)) if along_x \
				else Rect2(rr.position + Vector2(0, a), Vector2(rr.size.x, nb * 3.0))
			out.append({"rect": br, "face": face, "bays": nb, "floors": 3,
				"style": "factory" if rng.randf() < 0.3 else "apartments", "seed": rng.randi(), "ruined": false})
			start += nb
	return out


## [v3city] A building row cut back (from the yard side) until no point of it lies within GOAL_R.
func _goal_clip(rr: Rect2, face: Vector2) -> Rect2:
	for k: int in 40:
		var near := Vector2(clampf(0.0, rr.position.x, rr.end.x), clampf(0.0, rr.position.y, rr.end.y))
		if near.length() >= GOAL_R:
			return rr
		# Trim 1 m off the side facing the yard (the side the row faces), or off its yard-side end.
		if face.x != 0.0:
			if face.x < 0.0:
				rr = Rect2(rr.position + Vector2(1, 0), rr.size - Vector2(1, 0))
			else:
				rr.size.x -= 1.0
		else:
			if face.y < 0.0:
				rr = Rect2(rr.position + Vector2(0, 1), rr.size - Vector2(0, 1))
			else:
				rr.size.y -= 1.0
		if rr.size.x < 6.0 or rr.size.y < 6.0:
			break
	return rr


## Per-hub block mix and broken buildings: the inner ring is reshuffled (buildings, landfill,
## parking, vacant lots) and most buildings are broken off a few floors down.
func _ruin_layout(reshuffle: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 61
	var share: float = RUIN_SHARE if reshuffle else START_RUIN_SHARE
	var kinds: Array[int] = [CityLayout.Block.BUILDINGS, CityLayout.Block.BUILDINGS, CityLayout.Block.BUILDINGS,
		CityLayout.Block.LANDFILL, CityLayout.Block.PARKING, CityLayout.Block.VACANT]
	for key: Vector2i in layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var b: Dictionary = layout.blocks[key]
		if not reshuffle and key.x == 0:
			# The start yard's main street: open landfill lots north and south of the yard, so the
			# way out (and a lap round the planet) is never walled off.
			b["type"] = CityLayout.Block.LANDFILL
			b["buildings"] = []
			layout.blocks[key] = b
			continue
		if reshuffle:
			var t: int = kinds[rng.randi() % kinds.size()]
			b["type"] = t
			b["buildings"] = layout._make_buildings(b["rect"], rng, key) if t == CityLayout.Block.BUILDINGS else []
		for bd: Dictionary in b["buildings"]:
			bd["ruined"] = rng.randf() < share
			# Ruins are broken off low; even standing ones stay mid-rise on a hub site.
			bd["floors"] = rng.randi_range(2, 4) if bd["ruined"] else mini(int(bd["floors"]), 6)
		layout.blocks[key] = b


func _sidewalk_material() -> Material:
	var m: StandardMaterial3D = AssetLib.pbr_material("concrete_pavement", 1.1, Color(0.58, 0.56, 0.52), true)
	return m


## Asphalt streets between the blocks: one merged mesh of road strips with worn, broken ends
## that fade into the ground at the site's edge (vertex alpha), plus patched cracks.
func _roads() -> void:
	var e: float = layout.extent + CityLayout.PITCH * 0.5
	var n: int = int(ceil(layout.extent / CityLayout.PITCH))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w: float = CityLayout.ROAD_W * 0.5 + 0.2
	var step: float = 3.0
	var town: bool = true  # [v3city] both outer streets, fading out round the town's edge
	_road_r = town_r + 4.0
	for axis: int in 2:
		for k: int in range(-n - 1 if town else -n, n + 1):
			var c: float = (k + 0.5) * CityLayout.PITCH
			if absf(c) > e:
				continue
			var t: float = -e
			while t < e - 0.01:
				var t1: float = minf(t + step, e)
				if not town or Vector2(c, t).length() < _road_r + 6.0 or Vector2(c, t1).length() < _road_r + 6.0:
					_road_quad(st, axis, c, t, t1, half_w, e)
				t = t1
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = st.commit()
	var m: StandardMaterial3D = AssetLib.pbr_material("asphalt_02", 0.22, Color(0.72, 0.7, 0.68), true)
	m.vertex_color_use_as_albedo = false
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.vertex_color_is_srgb = false
	m.albedo_color = Color(0.72, 0.7, 0.68, 1.0)
	# Alpha comes from vertex colour (ends fade out).
	m.vertex_color_use_as_albedo = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	add_child(mi)


var _road_r: float = INF


func _road_quad(st: SurfaceTool, axis: int, c: float, t0: float, t1: float, hw: float, e: float) -> void:
	var y: float = 0.03
	var pts: Array[Vector3] = []
	for tt: float in [t0, t1]:
		for s: float in [-hw, hw]:
			pts.append(Vector3(c + s, y, tt) if axis == 0 else Vector3(tt, y, c + s))
	var rr: float = _road_r
	var fade := func(tt: float, s: float) -> float:
		var edge: float = e - absf(tt)
		if rr < INF:  # [v3city] radial: the town's streets run out into the wasteland
			edge = rr - Vector2(c + s, tt).length()
		var wob: float = sin(tt * 0.7 + s * 1.3 + c) * 2.5
		return clampf((edge - 4.0 + wob) / 10.0, 0.0, 1.0)
	var cols: Array[Color] = []
	var shown: float = 0.0
	for tt: float in [t0, t1]:
		for s: float in [-hw, hw]:
			var a: float = fade.call(tt, s)
			var pv: Vector3 = pts[cols.size()]
			if a > 0.0 and _wet(pv.x, pv.z):
				a = 0.0  # [v3city] the street runs out at the lake shore
			shown += a
			var g: float = 0.9 + 0.1 * sin(tt * 1.7 + c)
			cols.append(Color(g, g, g, a))
	if shown < 0.01:
		return
	var idx: Array[int] = [0, 1, 2, 1, 3, 2]
	for i: int in idx:
		st.set_color(cols[i])
		var p: Vector3 = pts[i]
		st.set_uv(Vector2(p.x, p.z) * 0.25)
		st.add_vertex(p)


## Block layouts in block-local metres (the inner rect is ~21.8 m square): [kind, x, z, yaw°].
const PATTERNS: Array = [
	[["module_large", -1.5, -2.0, 0.0], ["module_small", 6.5, 6.5, 180.0], ["machine_housing", -6.0, 7.0, 180.0]],
	[["module_medium", -4.0, -5.4, 0.0], ["module_medium", 4.0, 5.4, 180.0], ["tower", 6.5, -6.0, 0.0], ["machine_housing", -6.0, 6.0, 90.0]],
	[["module_small", -5.0, -4.6, 0.0], ["module_small", 5.0, -4.6, 0.0], ["machine_housing", -5.0, 5.0, 180.0], ["module_small", 5.0, 5.0, 180.0]],
	[["hangar", -2.0, 0.0, 90.0], ["tower", 7.0, -6.5, 0.0], ["module_small", 7.0, 5.5, 180.0]],
	[["tank_farm", -1.0, -4.0, 0.0], ["machine_housing", -5.0, 6.2, 180.0], ["module_small", 5.0, 6.2, 180.0]],
	[["tower", -5.5, -5.5, 0.0], ["module_medium", 3.5, -3.0, 0.0], ["module_small", -4.0, 5.5, 180.0], ["machine_housing", 5.0, 6.5, 180.0]],
]
## Verdance's kit palette (docs/ART_KIT.md): cream with a teal accent; a few buildings take a
## second accent so a block isn't one colour.
const ACCENTS: Array[String] = ["teal", "teal", "navy", "orange"]


## Every building block gets kit buildings on kit ground patches; landfill lots get kit debris,
## crate stacks and tipped barrels. Kit meshes are cached per kind / state / seed, so seeds are
## folded to a few variants per kind.
func _kit_blocks() -> void:
	kit_root = Node3D.new()
	kit_root.name = "Kit"
	add_child(kit_root)
	_kit_state = kit_state(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 401
	# The hub yard: a kit ground patch (plates, kerbs, cracks, grit, tufts), never a flat slab.
	_lots.append({"c": Vector2.ZERO, "kind": "yard", "seed": 1 + hub_index % 3})
	var hero_key := Vector2i(0, -1)
	for key: Vector2i in layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var b: Dictionary = layout.blocks[key]
		var c: Vector2 = (b["rect"] as Rect2).get_center()
		if key == hero_key and site_id != "start_yard" and not CITY_BUILDINGS:
			_hero(c)
			continue
		match int(b["type"]):
			CityLayout.Block.BUILDINGS when CITY_BUILDINGS:  # [v1world] CityView builds them; junk clears off their footprints
				for bd: Dictionary in b["buildings"]:
					_foot.append(bd["rect"])
			CityLayout.Block.BUILDINGS:
				var pat: Array = PATTERNS[rng.randi() % PATTERNS.size()]
				var turn: float = float(rng.randi() % 4) * 90.0 if pat.size() == 1 else (0.0 if rng.randf() < 0.5 else 180.0)
				for e: Array in pat:
					var lp := Vector2(float(e[1]), float(e[2])).rotated(deg_to_rad(-turn))
					var pal: Dictionary = {"main": "cream", "accent": ACCENTS[rng.randi() % ACCENTS.size()]}
					_kit(str(e[0]), Vector2(c.x + lp.x, c.y + lp.y), deg_to_rad(float(e[3]) + turn), pal, 1 + rng.randi() % 3)
					await BuildBudget.check("site:kit")  # [orbE]
			CityLayout.Block.LANDFILL, CityLayout.Block.VACANT, CityLayout.Block.PARKING:
				if maxi(absi(key.x), absi(key.y)) > 1:
					continue  # [v3city] the town's outer lots: junk ground, fences and wrecks (StreetFurniture)
				_lots.append({"c": c, "kind": "landfill" if int(b["type"]) == CityLayout.Block.LANDFILL else "lot", "seed": 1 + rng.randi() % 3})
	await BuildBudget.check("site:lots")  # [orbE]
	await _build_lots(true)
	BuildBudget.lap("site:lots")
	await BuildBudget.check("site:collision")  # [orbE]
	# The kit has no bodies of its own: one trimesh body for the buildings' solid meshes.
	SitePrefab.collision_for(kit_root, self)
	BuildBudget.lap("site:collision_for")
	KitBatch.merge(kit_root)  # [orbE] perf: one surface per material for all the yard's buildings
	BuildBudget.lap("site:kitbatch")


var _lots: Array[Dictionary] = []
var _lot_root: Node3D


## One kit building at a site-local point, with its footprint for the junk clearing.
func _kit(kind: String, at: Vector2, yaw: float, pal: Dictionary, seed_v: int) -> KitBuilding:
	var kb: KitBuilding = KitBuilding.create(kind, _kit_state, seed_v, pal, level >= 2)
	kb.position = Vector3(at.x, 0.0, at.y)
	kb.rotation.y = yaw
	kit_root.add_child(kb)
	kits.append(kb)
	var fp: Vector2 = KitBuilding.FOOTPRINT.get(kind, Vector2(10, 10)) * 0.8
	if absf(sin(yaw)) > 0.5:
		fp = Vector2(fp.y, fp.x)
	_foot.append(Rect2(at - fp * 0.5, fp))
	return kb


## The hub's hero building, facing the yard across the street (Moon Sweepers' big hub hall):
## a large module flanked by a tower and a tank farm, the hub sign on its front.
func _hero(c: Vector2) -> void:
	var pal: Dictionary = {"main": "cream", "accent": "teal"}
	_kit("hangar", c + Vector2(0, 1.0), PI * 0.5, pal, 1 + hub_index % 3)
	_kit("tower", c + Vector2(-8.0, -6.5), PI, pal, 1 + (hub_index + 1) % 3)
	_kit("tank_farm", c + Vector2(7.5, -6.0), PI, {"main": "cream", "accent": "orange"}, 1 + (hub_index + 2) % 3)
	_kit("dome", c + Vector2(-8.5, 6.5), 0.0, pal, 1 + hub_index % 3)


## [v1yard] The start yard's pad: one flat, clean slab of pale concrete panels (thin joints, a
## darker kerb lip and a teal edge line), no missing plates, grit or tufts. Lumi lands on it, so it
## should read as solid, swept ground against the trash round it.
static func clean_pad(size: float) -> Node3D:
	var k := YardArt.Kit.new()
	var h: float = size * 0.5
	# [v3city] Real slabs, not painted hairlines (QA: the 5 cm seam strips read as glitch lines
	# across the pad): a dark bedding layer, and on it 6 x 6 bevelled panels with 12 cm joints,
	# each a touch lighter or darker, so the joints read as paving at any distance.
	k.box(Vector3(size, 0.05, size), Vector3(0, 0.025, 0), Color(0.3, 0.3, 0.29), Vector3.ZERO, 0.02)
	var n: int = 6
	var step: float = size / n
	var tone := RandomNumberGenerator.new()
	tone.seed = 4471
	for i: int in n:
		for j: int in n:
			var t: float = tone.randf_range(-0.035, 0.035)
			var col := Color(0.47 + t, 0.47 + t, 0.45 + t * 0.9)
			var cx: float = -h + (i + 0.5) * step
			var cz: float = -h + (j + 0.5) * step
			k.box(Vector3(step - 0.12, 0.03, step - 0.12), Vector3(cx, 0.06, cz), col, Vector3.ZERO, 0.015)
	for side: int in 4:
		var along_x: bool = side < 2
		var sgn: float = -1.0 if side % 2 == 0 else 1.0
		var lip := Vector3(size, 0.1, 0.3) if along_x else Vector3(0.3, 0.1, size)
		var at := Vector3(0, 0.05, sgn * (h - 0.15)) if along_x else Vector3(sgn * (h - 0.15), 0.05, 0)
		k.box(lip, at, Color(0.42, 0.43, 0.42), Vector3.ZERO, 0.03)
		var line := Vector3(size - 0.9, 0.008, 0.12) if along_x else Vector3(0.12, 0.008, size - 0.9)
		var lat := Vector3(0, 0.078, sgn * (h - 0.55)) if along_x else Vector3(sgn * (h - 0.55), 0.078, 0)
		k.box(line, lat, Color(0.3, 0.75, 0.78))
	var mi: MeshInstance3D = k.mi(0.08, "CleanPad")
	mi.set_meta("no_collide", true)
	var root := Node3D.new()
	root.name = "YardPad"
	root.add_child(mi)
	return root


## Yard and lot dressing for the current state: kit ground patches everywhere; landfill heaps of
## kit debris, crate stacks and tipped barrels while broken, tidied when repaired, planters with
## bushes and flowers when restored. Rebuilt on a state change (meshes are kit-cached).
## sliced [v5load]: behind the loader, hand frames back between lots (set_level's rebuild in play
## stays one call).
func _build_lots(sliced: bool = false) -> void:
	if _lot_root:
		_lot_root.free()
	_lot_root = Node3D.new()
	_lot_root.name = "Lots"
	add_child(_lot_root)
	var st: String = _kit_state
	var b := KitMesh.Builder.new(seed_value + 7, {"main": "cream", "accent": "teal"}, st)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 409
	for lot: Dictionary in _lots:
		var c: Vector2 = lot["c"]
		var yard: bool = lot["kind"] == "yard"
		var gp: Node3D = clean_pad(21.0) if yard and site_id == "start_yard" else KitMesh.ground_patch(Vector2(21, 21) if yard else Vector2(18, 18), st, int(lot["seed"]))  # [v1yard]
		gp.position = Vector3(c.x, 0.0, c.y)
		_lot_root.add_child(gp)
		if sliced:
			await BuildBudget.check("site:lot")
		var t := Transform3D(Basis(), Vector3(c.x, 0, c.y))
		if yard:
			# Lived-in clutter on the yard's edges, clear of the anchors and the way out north.
			# Clear of every start-yard anchor (the lamps are the "Yard Lamps" Hub build).
			for p: Vector3 in [Vector3(-10.2, 0, -8.2), Vector3(10.2, 0, -3.6)]:
				KitProps.crate_stack(b, t * KitMesh.xf(p, Vector3(0, rng.randf() * 90.0, 0)), 3, st)
			KitProps.barrel(b, t * KitMesh.xf(Vector3(-10.4, 0, 5.7)), "paint:barrel", st == "broken")
			if st == "restored":
				for x: float in [-4.5, 4.5]:
					KitProps.planter(b, t * KitMesh.xf(Vector3(x, 0, 10.2)), 2.4, st)
			continue
		match st:
			"broken":
				if lot["kind"] == "landfill":
					KitProps.debris(b, t, 9.0, 26)
					KitProps.crate_stack(b, t * KitMesh.xf(Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)), Vector3(0, rng.randf() * 90.0, 0)), 3 + rng.randi() % 3, st)
					for k: int in 3:
						KitProps.barrel(b, t * KitMesh.xf(Vector3(rng.randf_range(-8, 8), 0.0, rng.randf_range(-8, 8)), Vector3(0, rng.randf() * 180.0, 0)), "paint:barrel", rng.randf() < 0.5)
				else:
					KitProps.debris(b, t, 7.0, 10)
			"repaired":
				KitProps.crate_stack(b, t * KitMesh.xf(Vector3(-5, 0, -5)), 4, st)
				KitProps.barrel(b, t * KitMesh.xf(Vector3(5, 0, -5)))
				KitProps.lamp_post(b, t * KitMesh.xf(Vector3(6, 0, 6)), 4.5, st)
			_:
				for k: int in 4:
					KitProps.planter(b, t * KitMesh.xf(Vector3(-6.0 + k * 4.0, 0, rng.randf_range(-3, 3)), Vector3(0, 90.0 * (k % 2), 0)), 2.6, st)
				KitProps.lamp_post(b, t * KitMesh.xf(Vector3(6, 0, 6)), 4.5, st)
	if sliced:
		await BuildBudget.check("site:lot props")
	var mi: MeshInstance3D = KitMesh.instance(b)
	mi.name = "LotProps"
	_lot_root.add_child(mi)
