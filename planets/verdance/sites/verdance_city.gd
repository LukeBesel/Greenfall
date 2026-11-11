class_name VerdanceCity
extends Node3D
## One of Verdance's six cities (docs/design/PLANET1_DESIGN.md sections 1 and 15): what makes a hub
## town its own place, on top of the shared town (VerdanceSite, TownOutskirts). The look is data
## (CityLook, planets/verdance/data/cities.json); a city's own script extends this and builds only
## its source landmark.
##   palette        CityLook.paint() sets each planned building's colours
##   roofs          CityRoofs: tanks, signs, parasols, pitched roofs, skylights, hoardings, domes, flags
##   street         CityStreet: stalls, containers, car stacks, fences or banners on the main street
##   street trees   OldTownTrees: bare at the start, in leaf from stage 3, blossom at stage 5
##   ground         OldTownGround: paving, lawns, shrubs and flower borders from stage 3 (the yard too)
##   gardens        CityGardens: fences, hedges, drives and vegetable beds round a suburb's houses
##   shop names     OldTownShopSigns: painted name boards on the way from the yard to the landmark
##   lake edge      a scum film along the shore until stage 4, reeds after
##   landmark       the pollution source, on a block the city reserves (plan), built by the city's
##                  own script in its own frame (_build_landmark): local +Z looks at the yard.
##                  set_source_state("broken" | "shut_down") switches it.
##   set_stage(0-5) the city's own regrowth: shop lights and lit rooms, clean signs, lamp heads,
##                  trees, the lake edge (VerdanceSite wires it to EventBus.district_stage_changed)
## Everything is site-local metres (y up on the pad, x east, z south). Batched: one mesh for the
## landmark and one for the street (the city's building material), one MultiMesh per prop kind.

const STATE_BROKEN: String = "broken"
const STATE_SHUT_DOWN: String = "shut_down"
const MAX_STAGE: int = 5
const NO_BLOCK := Vector2i(999, 999)
const WATER_Y: float = -0.25  # the lake surface under the land (StreetFurniture.WATER_Y)
## Per stage 0..5: the share of windows lit and how clean the signs are.
const LIT: Array[float] = [0.0, 0.0, 0.4, 0.62, 0.85, 1.0]
const SIGN_CLEAN: Array[float] = [0.0, 0.55, 0.8, 1.0, 1.0, 1.0]
const LAMP_WARM := Color(1.0, 0.8, 0.5)
const BEACON_ALARM := Color(1.0, 0.55, 0.1)
const BEACON_SAFE := Color(0.3, 1.0, 0.5)
const SIGN_LIT := Color(1.0, 0.95, 0.8)
const SIGN_DARK := Color(0.9, 0.86, 0.74)
const YARD_MARGIN_M: float = 6.0   # the street dressing starts this far past the yard's own ground
const OLD_TOWN_ID: String = "old_town"

var city_id: String = ""
var display_name: String = ""   # the district's name, as the player reads it
var look: CityLook
var stage: int = 0
var source_state: String = STATE_BROKEN
var block_key: Vector2i = NO_BLOCK
var landmark_rects: Array[Rect2] = []  # solid footprints (junk, furniture and buildings keep off)
## The landmark's frame in the site: its block's centre, local +Z toward the yard, +X to the right
## of someone looking at it from the yard.
var frame := Transform3D.IDENTITY
var stats: Dictionary = {}
var trees: OldTownTrees
var ground: OldTownGround
var gardens: CityGardens
var tree_spots: Array[Vector2] = []
var approach_keys: Array[Vector2i] = []   # the open blocks between the yard and the landmark
var view_step := Vector2i.ZERO            # one block from the landmark toward the yard

var _site: VerdanceSite
var _body: StaticBody3D
var _lamp_glow: MultiMeshInstance3D
var _scum: MultiMeshInstance3D
var _reeds: MultiMeshInstance3D
var _sign: Label3D
var _beacon: StandardMaterial3D
var _t: float = 0.0
var _rects: Array[Rect2] = []
var _broken: Array[Node3D] = []    # shown while the source is running
var _shut: Array[Node3D] = []      # shown once it is shut down
var _moving: bool = false          # the city's script moves parts of its landmark (_animate)


## The city that stands on hub `hub_index` of the planet being played (the district whose site it
## is), or null on open ground. The start site is the first city even on a planet without districts.
static func for_site(hub_index: int, start: bool) -> VerdanceCity:
	var id: String = OLD_TOWN_ID if start else ""
	var shown: String = ""
	for d: Dictionary in Districts.specs_for(Planets.current()):
		if int(d["site"]) == hub_index and CityLook.has(str(d["id"])):
			id = str(d["id"])
			shown = str(d.get("name", ""))
	var c: VerdanceCity = create(id)
	if c:
		c.display_name = shown
	return c


## A city by id, or null when the data has none. The script is the one the data names.
static func create(id: String) -> VerdanceCity:
	var l: CityLook = CityLook.of(id)
	if l == null:
		return null
	var script: Script = load(str(l.data.get("script", ""))) as Script
	var c: VerdanceCity = script.new() as VerdanceCity if script else null
	if c == null:
		return null
	c.city_id = id
	c.look = l
	c.name = "City_" + id
	return c


# --- Planning (before the town is built) --------------------------------------------------------

## Reserves the landmark's ground in the town's layout: buildings under it go, and (with
## "approach") the blocks between it and the yard become open lots. Returns false when no block
## is free (the landmark is then left out).
func plan(site: VerdanceSite) -> bool:
	_site = site
	block_key = _pick_block(site)
	if block_key == NO_BLOCK:
		return false
	var c: Vector2 = Vector2(block_key) * CityLayout.PITCH
	var to_yard: Vector2 = -Vector2(block_key)
	to_yard = Vector2(signf(to_yard.x), 0.0) if absf(to_yard.x) > absf(to_yard.y) else Vector2(0.0, signf(to_yard.y))
	frame = Transform3D(Basis(Vector3.UP, atan2(to_yard.x, to_yard.y)), Vector3(c.x, 0.0, c.y))
	landmark_rects = []
	for r: Rect2 in _footprint():
		landmark_rects.append(site_rect(r))
	for key: Vector2i in site.layout.blocks:
		var b: Dictionary = site.layout.blocks[key]
		var keep: Array = []
		var hit: bool = key == block_key
		for bd: Dictionary in b["buildings"]:
			if _on_landmark((bd["rect"] as Rect2).grow(1.5)):
				hit = true
			else:
				keep.append(bd)
		if hit and key != Vector2i.ZERO:
			b["type"] = CityLayout.Block.BUILDINGS
			b["buildings"] = keep
			b["landmark"] = true
			site.layout.blocks[key] = b
	if bool(look.landmark().get("approach", false)):
		_open_approach(site, Vector2i(to_yard))
	_keep_junk_off(site)
	return true


func has_landmark() -> bool:
	return block_key != NO_BLOCK


## The first block of the data's list that exists and is dry.
func _pick_block(site: VerdanceSite) -> Vector2i:
	for raw: Variant in look.landmark().get("blocks", []):
		var key := Vector2i(int(raw[0]), int(raw[1]))
		if site.layout.blocks.has(key) and site._wet_share(site.layout.blocks[key]["rect"], 2.0) <= 0.3:
			return key
	return NO_BLOCK


## The blocks between the landmark and the yard lose their buildings: from the yard the landmark
## closes the view across an open, junk-filled lot.
func _open_approach(site: VerdanceSite, step: Vector2i) -> void:
	var key: Vector2i = block_key + step
	view_step = step
	while key != Vector2i.ZERO and maxi(absi(key.x), absi(key.y)) < 4:
		if site.layout.blocks.has(key):
			var b: Dictionary = site.layout.blocks[key]
			b["type"] = CityLayout.Block.PARKING
			b["buildings"] = []
			site.layout.blocks[key] = b
			approach_keys.append(key)
		key += step
	stats["approach"] = true


## Solid footprints of the landmark in its own frame (x right, y toward the yard). A city overrides this.
func _footprint() -> Array[Rect2]:
	return []


## Ground of the landmark that stays free of junk so it can be seen (a slick, a stain, an avenue):
## rects in the landmark's frame (x right, y toward the yard). A city overrides this.
func _clear_ground() -> Array[Rect2]:
	return []


## Registers the city's clear ground with the globe's keep-out, in this site's own frame (the
## keep-out's plain lists are the start yard's: a hub town's go in as world footprints).
func _keep_junk_off(site: VerdanceSite) -> void:
	var ko: YardKeepOut = site.globe_ctx.get("keep_out") as YardKeepOut
	var clear: Array[Rect2] = _clear_ground()
	if ko == null or clear.is_empty() or not site.globe_ctx.has("xf"):
		return
	var items: Array = []
	for r: Rect2 in clear:
		items.append([site.globe_ctx["xf"], site_rect(r)])
	ko.add_world("city_ground%d" % site.hub_index, items)
	stats["clear_ground"] = items.size()


func _on_landmark(r: Rect2) -> bool:
	for l: Rect2 in landmark_rects:
		if l.intersects(r):
			return true
	return false


## A rect of the landmark's frame (x right, y toward the yard) in the site's space.
func site_rect(r: Rect2) -> Rect2:
	var a: Vector3 = frame * Vector3(r.position.x, 0.0, r.position.y)
	var b: Vector3 = frame * Vector3(r.end.x, 0.0, r.end.y)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


# --- Build --------------------------------------------------------------------------------------

func build(site: VerdanceSite) -> void:
	_site = site
	_body = PropColliders.body(self, "CityBody")
	if has_landmark():
		await BuildBudget.check("city:landmark")
		_build_landmark()
	await BuildBudget.check("city:street")
	var yard_r: float = (site.furniture.goal_r if site.furniture else VerdanceSite.GOAL_R) + YARD_MARGIN_M
	stats["street"] = CityStreet.build(self, site, look, yard_r)
	await BuildBudget.check("city:roofs")
	CityRoofs.build(self, _roofs(), look)
	if bool(look.data.get("gardens", false)):
		await BuildBudget.check("city:gardens")
		gardens = CityGardens.new()
		gardens.name = "Gardens"
		add_child(gardens)
		gardens.build(_roofs(), look, _body)
		stats.merge(gardens.stats)
	await BuildBudget.check("city:trees")
	_build_trees()
	await BuildBudget.check("city:ground")
	ground = OldTownGround.new()
	ground.name = "Ground"
	add_child(ground)
	ground.build(_site, block_key, landmark_rects + _rects, tree_spots, _site.site_id != "start_yard",
		approach_keys if bool(look.landmark().get("avenue", false)) else ([] as Array[Vector2i]), look.data.get("paving", {}))
	stats.merge(ground.stats)
	await BuildBudget.check("city:signs")
	var signs := OldTownShopSigns.new()
	signs.name = "ShopSigns"
	add_child(signs)
	signs.build(_site, Vector2(frame.origin.x, frame.origin.z) if has_landmark() else Vector2(0, -80), StreetDressing.NEAR_R,
		_site.seed_value + 3391, look.shop_names, look.boards)
	stats["shop_signs"] = signs.count
	await BuildBudget.check("city:lamps")
	_build_lamp_glow()
	await BuildBudget.check("city:shore")
	_build_shore()
	set_source_state(source_state)
	set_stage(stage)
	if DevHooks.has("load-report") or DevHooks.has("town-map"):
		print("[city] %s on block %s %s" % [city_id, str(block_key), str(stats)])


## The city's source landmark, in the city's building material. A city overrides this.
func _build_landmark() -> void:
	pass


func _process(delta: float) -> void:
	_t += delta
	if _beacon and source_state == STATE_BROKEN:
		_beacon.emission_energy_multiplier = 3.5 if fmod(_t, 1.2) < 0.5 else 0.2
	if _moving:
		_animate(_t, source_state == STATE_BROKEN)


## The solid things this module added: junk keeps off them (VerdanceSite.prop_rects()).
func rects() -> Array[Rect2]:
	return _rects.duplicate()


func add_rect(r: Rect2) -> void:
	_rects.append(r)


func add_solid(xf: Transform3D, size: Vector3) -> void:
	PropColliders.add_box(_body, xf, size)


## A solid box of the landmark, given in the landmark's frame; `foot` also keeps junk off it.
func add_landmark_solid(at: Vector3, size: Vector3) -> void:
	PropColliders.add_box(_body, frame * Transform3D(Basis.IDENTITY, at), size)


func add_batch(nm: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material, shadows: bool, range_m: float) -> MultiMeshInstance3D:
	stats[nm] = xfs.size()
	return CityKit.mmi_on(self, nm, mesh, xfs, cols, mat, shadows, range_m)


## Whether a w x d footprint at p is dry and clear of buildings, wrecks, shelters and the landmark.
func is_free(p: Vector2, size: Vector2) -> bool:
	var r := Rect2(p - size * 0.5, size)
	for q: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), p]:
		if _site._wet(q.x, q.y):
			return false
	for o: Rect2 in _site.footprints() + _site.prop_rects() + landmark_rects + _rects:
		if o.grow(0.4).intersects(r):
			return false
	return true


# --- Stage and source ---------------------------------------------------------------------------

## The city's own regrowth for a district stage 0..5 (0 polluted, 1 clean, 2 planted, 3 growing,
## 4 sustained, 5 thriving): signs wash clean from stage 1, shop windows and lamp heads light at 2,
## rooms light and the street trees leaf out at 3, the lake edge clears at 4, and at 5 every light
## is on, the trees are full and flowers stand round them.
func set_stage(s: int) -> void:
	stage = clampi(s, 0, MAX_STAGE)
	if look:
		look.set_lights(LIT[stage], SIGN_CLEAN[stage])
	if _lamp_glow:
		_lamp_glow.visible = stage >= 2
	if trees:
		trees.set_stage(stage)
	if ground:
		ground.set_stage(stage)
	if gardens:
		gardens.set_stage(stage)
	if _scum:
		_scum.visible = stage < 4
	if _reeds:
		_reeds.visible = stage >= 4
	_apply_sign()
	_on_stage()


## The source: "broken" (running: smoke, leaks, a flashing beacon) or "shut_down" (stopped, the
## beacon steady green, its lamps on). The source's gameplay calls this when its last step is done.
func set_source_state(state: String) -> void:
	source_state = STATE_SHUT_DOWN if state == STATE_SHUT_DOWN else STATE_BROKEN
	var broken: bool = source_state == STATE_BROKEN
	for n: Node3D in _broken:
		n.visible = broken
	for n2: Node3D in _shut:
		n2.visible = not broken
	if _beacon:
		_beacon.albedo_color = BEACON_ALARM if broken else BEACON_SAFE
		_beacon.emission = _beacon.albedo_color
	set_process(_moving or (broken and _beacon != null))
	if not broken and _beacon:
		_beacon.emission_energy_multiplier = 2.0
	_apply_sign()
	_on_source(broken)


## Hooks for a city's own extras.
func _on_stage() -> void:
	pass


func _on_source(_broken_now: bool) -> void:
	pass


## Moves the landmark's working parts (a crane's swing, a scraper bridge's turn) at time `_now` s.
## Called every frame once the city has placed a moving part (place_part).
func _animate(_now: float, _broken_now: bool) -> void:
	pass


## The landmark's sign is lit once the source is shut down or the city's lights are back.
func _apply_sign() -> void:
	if _sign:
		var on: bool = source_state == STATE_SHUT_DOWN or stage >= 2
		_sign.modulate = SIGN_LIT if on else SIGN_DARK
		_sign.shaded = not on


# --- Landmark helpers (positions in the landmark's frame) -----------------------------------------

## Adds a node at a landmark-frame transform; `when` = "broken" or "shut_down" ties it to that
## state of the source, "" shows it always.
func place(n: Node3D, when: String = "") -> Node3D:
	n.transform = frame * n.transform
	add_child(n)
	if when == STATE_BROKEN:
		_broken.append(n)
	elif when == STATE_SHUT_DOWN:
		_shut.append(n)
	return n


## One mesh of the landmark from a Geo built in the landmark's frame.
func place_mesh(nm: String, g: BuildingDetail.Geo, when: String = "") -> MeshInstance3D:
	CityKit.xform(g, 0, frame)
	var mi: MeshInstance3D = CityKit.mesh_node(nm, g, look.material(false))
	add_child(mi)
	if when == STATE_BROKEN:
		_broken.append(mi)
	elif when == STATE_SHUT_DOWN:
		_shut.append(mi)
	stats[nm + "_tris"] = g.tri_count()
	return mi


## A part of the landmark that moves: `g` is built round the origin (x right, z toward the yard)
## and the node stands at `pivot` in the landmark's frame. The city's _animate() turns or shifts it
## with move_part().
func place_part(nm: String, g: BuildingDetail.Geo, pivot: Vector3, when: String = "") -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	holder.transform = Transform3D(Basis.IDENTITY, pivot)
	holder.set_meta("rest", frame * holder.transform)
	if not g.empty():
		holder.add_child(CityKit.mesh_node("Mesh", g, look.material(false)))
		stats[nm + "_tris"] = g.tri_count()
	place(holder, when)
	_moving = true
	return holder


## Sets a moving part to its rest place turned `yaw` about the site's up and shifted by `shift`
## (in the part's own axes).
func move_part(part: Node3D, yaw: float, shift: Vector3 = Vector3.ZERO) -> void:
	var rest: Transform3D = part.get_meta("rest", part.transform)
	part.transform = rest * Transform3D(Basis(Vector3.UP, yaw), shift)


## The landmark's painted name (lit with the city), at a landmark-frame transform.
func place_sign(xf: Transform3D, letter_m: float) -> void:
	_sign = CityKit.label(str(look.landmark().get("sign", "")), xf, letter_m, SIGN_DARK)
	_sign.name = "LandmarkSign"
	place(_sign)


## The warning beacon: flashes amber while the source runs, steady green after.
func place_beacon(at: Vector3, r: float = 0.16) -> void:
	_beacon = StandardMaterial3D.new()
	_beacon.albedo_color = BEACON_ALARM
	_beacon.emission_enabled = true
	_beacon.emission = _beacon.albedo_color
	var lamp := MeshInstance3D.new()
	lamp.name = "Beacon"
	lamp.mesh = ProcMesh.sphere(r, 10, 6)
	lamp.material_override = _beacon
	lamp.position = at
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	place(lamp)


## Lamp heads that come on when the source is shut down.
func place_lamps(nm: String, pts: Array[Vector3], r: float, col: Color = LAMP_WARM) -> void:
	var holder := Node3D.new()
	holder.name = nm
	place(holder, STATE_SHUT_DOWN)
	CityKit.glow(holder, "Heads", pts, r, Color(col.r * 1.6, col.g * 1.5, col.b * 1.3))


# --- Rooftops, trees, lamps, the lake edge --------------------------------------------------------

## Every roof of the pad town and the outskirts: [frame (site space), Rect2 in the frame, roof
## height, plan].
func _roofs() -> Array:
	var roofs: Array = []
	for key: Vector2i in _site.layout.blocks:
		for bd: Dictionary in _site.layout.blocks[key]["buildings"]:
			roofs.append([Transform3D.IDENTITY, bd["rect"], float(int(bd["floors"])) * BuildingDetail.FLOOR_H + 0.15, bd])
	if _site.outskirts:
		roofs.append_array(_site.outskirts.roofs)
	return roofs


## Street trees in the kerb strip of every block (OldTownTrees): bare at the start, in leaf from
## stage 3, in blossom with flowers at their feet at stage 5.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _site.seed_value + 3301
	var skip: float = float(look.data.get("tree_skip", 0.22))
	var yard_r: float = 27.0 if _site.site_id == "start_yard" else 15.0
	var spots: Array[Vector2] = []
	var blocked: Array[Vector2] = []
	if _site.furniture:
		blocked.append_array(_site.furniture.obstacles)
	for key: Vector2i in _site.layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var c := Vector2(key) * CityLayout.PITCH
		for o: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			if _across_view(key, o):
				continue
			var along := Vector2(-o.y, o.x)
			for t: float in [-9.6, -3.2, 3.2, 9.6]:
				if rng.randf() < skip:
					continue
				var p: Vector2 = c + o * 12.75 + along * (t + rng.randf_range(-0.5, 0.5))
				if p.length() < yard_r or p.length() > _site.town_r - 4.0 or not is_free(p, Vector2(0.8, 0.8)):
					continue
				var ok: bool = true
				for q: Vector2 in blocked:
					if q.distance_squared_to(p) < 3.2:
						ok = false
						break
				if ok:
					spots.append(p)
					blocked.append(p)
	if spots.is_empty():
		return
	trees = OldTownTrees.new()
	trees.name = "Trees"
	add_child(trees)
	trees.build(spots, _site.seed_value + 3307, _body, stats)
	tree_spots = spots


## Whether side `o` of block `key` lies across the line of sight from the yard to the landmark: a
## kerb of an approach block that the view crosses, or the landmark block's side toward the yard.
## No street trees stand there, so the landmark still closes the view once they are in leaf.
func _across_view(key: Vector2i, o: Vector2) -> bool:
	if view_step == Vector2i.ZERO or absf(o.dot(Vector2(view_step))) < 0.5:
		return false
	return approach_keys.has(key) or (key == block_key and o.dot(Vector2(view_step)) > 0.5)


## A warm glow on every street lamp head of the town (CityView.lamp_bulbs), shown from stage 2.
func _build_lamp_glow() -> void:
	if _site.city == null or _site.city.lamp_bulbs.is_empty():
		return
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for e: Array in _site.city.lamp_bulbs:
		var xf: Transform3D = e[0]
		xfs.append(Transform3D(xf.basis.orthonormalized().scaled(Vector3.ONE * 0.15), xf.origin))
		cols.append(LAMP_WARM)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.6, 1.4, 1.1)
	_lamp_glow = add_batch("LampGlow", ProcMesh.sphere(1.0, 10, 6), xfs, cols, m, false, 240.0)


## Along the town's shore: a pale scum film on the water until the district is sustained, then
## reeds at the water's edge.
func _build_shore() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _site.seed_value + 4409
	var step: float = 4.0
	var half: float = _site.town_r
	var film: Array[Transform3D] = []
	var reed: Array[Transform3D] = []
	var x: float = -half
	while x <= half:
		var z: float = -half
		while z <= half:
			var p := Vector2(x, z)
			if p.length() < half and p.length() > 16.0 and _site._wet(p.x, p.y):
				var land := Vector2.ZERO
				for d: Vector2 in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
					if not _site._wet(p.x + d.x, p.y + d.y):
						land += d
				if land != Vector2.ZERO:
					var n: Vector2 = land.normalized()
					for k: int in 2:
						var q: Vector2 = p - n * rng.randf_range(0.0, 3.5) + Vector2(-n.y, n.x) * rng.randf_range(-2.0, 2.0)
						if _site._wet(q.x, q.y):
							film.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(1.6, 3.2), 1.0, rng.randf_range(1.0, 2.2))), CityKit.v3(q, WATER_Y + 0.03)))
					if rng.randf() < 0.55:
						var rq: Vector2 = p + n * rng.randf_range(0.2, 1.6)
						if not _site._wet(rq.x, rq.y):
							rq = p
						if rq.length() > 16.0:
							reed.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.8, 2.8)), CityKit.v3(rq, WATER_Y - 0.05)))
			z += step
		x += step
	if not film.is_empty():
		var disc := SurfaceTool.new()
		disc.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in 10:
			var a0: float = TAU * float(i) / 10.0
			var a1: float = TAU * float(i + 1) / 10.0
			for v: Array in [[Vector3.ZERO, 0.75], [Vector3(cos(a1), 0, sin(a1)) * (0.8 + 0.2 * sin(a1 * 3.0)), 0.0], [Vector3(cos(a0), 0, sin(a0)) * (0.8 + 0.2 * sin(a0 * 3.0)), 0.0]]:
				disc.set_normal(Vector3.UP)
				disc.set_color(Color(0.86, 0.9, 0.78, v[1]))
				disc.add_vertex(v[0])
		var fm := StandardMaterial3D.new()
		fm.vertex_color_use_as_albedo = true
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.roughness = 0.6
		_scum = add_batch("ShoreScum", disc.commit(), film, [], fm, false, 260.0)
	var grass: Array[Mesh] = PlantParts.variants("grass_medium_02", 300)
	if not reed.is_empty() and not grass.is_empty():
		_reeds = add_batch("ShoreReeds", grass[0], reed, [], null, false, 200.0)
