class_name CityOldTown
extends Node3D
## Old Town, Verdance's first city (site 0; docs/design/PLANET1_DESIGN.md sections 4 and 15): what
## makes the start town its own place, on top of the shared town (VerdanceSite, TownOutskirts).
##   palette        warm brick and cream walls, terracotta / copper-green / slate roofs, strong
##                  awning colours: paint() sets each planned building's colours
##   roofs          wooden water tanks on stilts, painted roof signs and parasols on the roofs of
##                  the pad town and the outskirts, so from above the town is roofs, not white boxes
##   pumping station the source landmark at the head of the main street, on the lake: a brick pump
##                  house with a standpipe tower and a burst main fountaining over a flooded
##                  forecourt. set_source_state("broken" | "shut_down") switches it.
##   market         striped stalls along the main street
##   street trees   OldTownTrees: bare at the start, in leaf from stage 3, blossom at stage 5
##   burst main     OldTownBurst: the jet, its spray and the flooded forecourt, or the cap
##   ground         OldTownGround: paving, lawns, shrubs and flower borders from stage 3
##   lake edge      a scum film along the shore until stage 4, reeds after
##   set_stage(0-5) the town's own regrowth: shop lights and lit rooms, clean signs, lamp heads,
##                  trees, the lake edge (VerdanceSite wires it to EventBus.district_stage_changed)
## Everything is site-local metres (y up on the pad, x east, z south). Batched: one mesh for the
## station and one for the stalls (the town's building material), one MultiMesh per prop kind.

const STATE_BROKEN: String = "broken"
const STATE_SHUT_DOWN: String = "shut_down"
const MAX_STAGE: int = 5
## Where the station may stand (block keys, first dry one wins): the head of the main street.
const STATION_BLOCKS: Array[Vector2i] = [Vector2i(0, -3), Vector2i(1, -3), Vector2i(0, -2)]
const WATER_Y: float = -0.25  # the lake surface under the land (StreetFurniture.WATER_Y)

const T_RED: int = BuildingDetail.T_RED_BRICK
const T_PALE: int = BuildingDetail.T_BRICK
const T_PAINT: int = BuildingDetail.T_CONCRETE
## Walls: [texture, tint]. Red brick three times in ten, pale brick, then painted render.
const WALLS: Array = [
	[T_RED, Color(1.0, 0.95, 0.9)], [T_RED, Color(1.0, 0.86, 0.78)], [T_RED, Color(0.92, 0.9, 0.86)],
	[T_PALE, Color(1.0, 0.86, 0.62)], [T_PALE, Color(0.98, 0.78, 0.6)],
	[T_PAINT, Color(0.97, 0.9, 0.72)], [T_PAINT, Color(0.96, 0.86, 0.66)], [T_PAINT, Color(0.93, 0.62, 0.45)],
	[T_PAINT, Color(0.95, 0.76, 0.4)], [T_PAINT, Color(0.42, 0.68, 0.66)], [T_PAINT, Color(0.9, 0.64, 0.62)],
	[T_PAINT, Color(0.62, 0.76, 0.88)],
]
const ROOFS: Array[Color] = [Color(0.8, 0.34, 0.2), Color(0.74, 0.3, 0.2), Color(0.66, 0.24, 0.18), Color(0.3, 0.6, 0.5),
	Color(0.34, 0.44, 0.6), Color(0.36, 0.28, 0.38), Color(0.78, 0.62, 0.36), Color(0.16, 0.5, 0.52)]
const AWNING_COLS: Array[Color] = [Color(0.84, 0.14, 0.1), Color(0.04, 0.5, 0.5), Color(0.94, 0.68, 0.08), Color(0.12, 0.3, 0.64), Color(0.2, 0.52, 0.3)]
const TANK_COLS: Array[Color] = [Color(0.72, 0.5, 0.3), Color(0.66, 0.44, 0.26), Color(0.12, 0.5, 0.52), Color(0.7, 0.24, 0.16), Color(0.9, 0.84, 0.7)]
const SIGN_COLS: Array[Color] = [Color(0.86, 0.14, 0.1), Color(0.05, 0.52, 0.55), Color(0.96, 0.7, 0.06), Color(0.14, 0.32, 0.7), Color(0.9, 0.36, 0.08), Color(0.24, 0.58, 0.3)]
const BRICK := Color(1.0, 0.9, 0.84)
const STONE := Color(0.92, 0.88, 0.8)
const PIPE_TEAL := Color(0.08, 0.5, 0.52)
const LAMP_WARM := Color(1.0, 0.8, 0.5)

static var _mats: Array[ShaderMaterial] = [null, null]

var stage: int = 0
var source_state: String = STATE_BROKEN
var station_key := Vector2i(999, 999)
var station_rects: Array[Rect2] = []   # solid footprints (junk and furniture keep off)
var station_at := Vector3.ZERO         # the burst main
var stats: Dictionary = {}
var trees: OldTownTrees
var ground: OldTownGround
var tree_spots: Array[Vector2] = []

var _site: VerdanceSite
var _body: StaticBody3D
var _lamp_glow: MultiMeshInstance3D
var _scum: MultiMeshInstance3D
var _reeds: MultiMeshInstance3D
var burst_main: OldTownBurst  # the jet and the flood, or the cap and the damp ground
var _sign: Label3D
var _beacon: StandardMaterial3D
var _t: float = 0.0


# --- Palette ----------------------------------------------------------------------------------

## The town's building material: a copy of the shared city material with its own "lit" and
## "sign_clean" (index 0: the pad town, in the site's space; 1: the outskirts, in tile space).
static func material(local_space: bool) -> ShaderMaterial:
	var i: int = 1 if local_space else 0
	if _mats[i] == null:
		_mats[i] = BuildingDetail.material().duplicate()
		_mats[i].set_shader_parameter("local_space", local_space)
	return _mats[i]


## Paints one planned building (CityLayout / TownOutskirts dictionary) in the town's colours.
## Drawn from the building's own seed, so the layout's random stream is untouched.
static func paint(bd: Dictionary, _rng: RandomNumberGenerator = null, _dist: float = 0.0) -> void:
	var h: int = hash([int(bd.get("seed", 0)), 9173])
	var wall: Array = WALLS[h % WALLS.size()]
	if int(bd.get("floors", 3)) >= 8 and int(wall[0]) == T_RED:
		wall = WALLS[5 + (h >> 4) % 4]  # the few tall ones are cream, terracotta or mustard render
	var tint: Color = wall[1]
	bd["wall_tex"] = int(wall[0])
	bd["tint"] = tint.lightened(float((h >> 8) % 7) * 0.01 - 0.03)
	bd["roof_tint"] = ROOFS[(h >> 12) % ROOFS.size()]
	bd["awning"] = AWNING_COLS[(h >> 16) % AWNING_COLS.size()]
	bd["awning_striped"] = (h >> 20) % 3 != 0


# --- Planning (before the town is built) --------------------------------------------------------

## Reserves the station's block in the town's layout: its buildings go, the block stays a paved
## block. Returns false when no block is free (the station is then left out).
func plan(site: VerdanceSite) -> bool:
	_site = site
	for key: Vector2i in STATION_BLOCKS:
		if not site.layout.blocks.has(key):
			continue
		var b: Dictionary = site.layout.blocks[key]
		var r: Rect2 = b["rect"]
		if site._wet_share(r, 2.0) > 0.3:
			continue
		b["type"] = CityLayout.Block.BUILDINGS
		b["buildings"] = []
		b["landmark"] = true
		site.layout.blocks[key] = b
		station_key = key
		var c: Vector2 = r.get_center()
		station_rects = [Rect2(c + Vector2(-10.5, -10.4), Vector2(16.5, 12.4)), Rect2(c + Vector2(6.3, -9.2), Vector2(4.6, 4.6))]
		station_at = Vector3(c.x + 2.6, 0.0, c.y + 9.4)
		var ko: YardKeepOut = site.globe_ctx.get("keep_out") as YardKeepOut
		if ko:  # the flood shows from the start: loose junk keeps off the water
			for d: Vector3 in OldTownBurst.KEEP_OFF:
				ko.add_soft_disc(station_at.x + d.x, station_at.z + d.y, d.z)
		return true
	return false


func has_station() -> bool:
	return station_key != Vector2i(999, 999)


# --- Build --------------------------------------------------------------------------------------

func build(site: VerdanceSite) -> void:
	_site = site
	_body = PropColliders.body(self, "OldTownBody")
	if has_station():
		await BuildBudget.check("oldtown:station")
		_build_station()
	await BuildBudget.check("oldtown:market")
	_build_market()
	await BuildBudget.check("oldtown:roofs")
	_build_roofs()
	await BuildBudget.check("oldtown:trees")
	_build_trees()
	await BuildBudget.check("oldtown:ground")
	ground = OldTownGround.new()
	ground.name = "Ground"
	add_child(ground)
	ground.build(_site, station_key, station_rects + _rects)
	stats.merge(ground.stats)
	await BuildBudget.check("oldtown:lamps")
	_build_lamp_glow()
	await BuildBudget.check("oldtown:shore")
	_build_shore()
	set_source_state(source_state)
	set_stage(stage)
	if DevHooks.has("load-report") or DevHooks.has("town-map"):
		print("[oldtown] %s" % str(stats))


func _process(delta: float) -> void:
	_t += delta
	if _beacon:
		_beacon.emission_energy_multiplier = 3.5 if fmod(_t, 1.2) < 0.5 else 0.2


## The solid things this module added: junk keeps off them (VerdanceSite.prop_rects()).
func rects() -> Array[Rect2]:
	return _rects.duplicate()


var _rects: Array[Rect2] = []


# --- Stage and source ---------------------------------------------------------------------------

## The town's own regrowth for a district stage 0..5 (0 polluted, 1 clean, 2 planted, 3 growing,
## 4 sustained, 5 thriving): signs wash clean from stage 1, shop windows and lamp heads light at 2,
## rooms light and the street trees leaf out at 3, the lake edge clears at 4, and at 5 every light
## is on, the trees are full and flowers stand round them.
func set_stage(s: int) -> void:
	stage = clampi(s, 0, MAX_STAGE)
	var lit: float = [0.0, 0.0, 0.4, 0.62, 0.85, 1.0][stage]
	var clean: float = [0.0, 0.55, 0.8, 1.0, 1.0, 1.0][stage]
	for m: ShaderMaterial in _mats:
		if m:
			m.set_shader_parameter("lit", lit)
			m.set_shader_parameter("sign_clean", clean)
	if _lamp_glow:
		_lamp_glow.visible = stage >= 2
	if trees:
		trees.set_stage(stage)
	if ground:
		ground.set_stage(stage)
	if _scum:
		_scum.visible = stage < 4
	if _reeds:
		_reeds.visible = stage >= 4
	_apply_sign()


## The burst main: "broken" (fountain, flood, flashing beacon) or "shut_down" (capped, drained,
## the beacon steady green). The source's gameplay calls this when its last step is done.
func set_source_state(state: String) -> void:
	source_state = STATE_SHUT_DOWN if state == STATE_SHUT_DOWN else STATE_BROKEN
	var broken: bool = source_state == STATE_BROKEN
	if burst_main:
		burst_main.set_broken(broken)
	if _beacon:
		_beacon.albedo_color = Color(1.0, 0.55, 0.1) if broken else Color(0.3, 1.0, 0.5)
		_beacon.emission = _beacon.albedo_color
	set_process(broken and _beacon != null)
	if not broken and _beacon:
		_beacon.emission_energy_multiplier = 2.0
	_apply_sign()


## The pump house's sign is lit once the main is shut down or the town's lights are back.
func _apply_sign() -> void:
	if _sign:
		var on: bool = source_state == STATE_SHUT_DOWN or stage >= 2
		_sign.modulate = Color(1.0, 0.95, 0.8) if on else Color(0.9, 0.86, 0.74)
		_sign.shaded = not on


# --- Small mesh helpers -------------------------------------------------------------------------

## A vertex-coloured mesh from a Geo (the kind byte in alpha is dropped): for MultiMesh props,
## whose instance colour tints the light parts and leaves the dark ones dark.
static func _vc_mesh(g: BuildingDetail.Geo) -> ArrayMesh:
	var cols := PackedColorArray()
	cols.resize(g.c.size())
	for i: int in g.c.size():
		cols[i] = Color(g.c[i].r, g.c[i].g, g.c[i].b, 1.0)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = g.v
	arr[Mesh.ARRAY_NORMAL] = g.n
	arr[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _vc_material(rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	return m


func _mmi(nm: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material, shadows: bool, range_m: float) -> MultiMeshInstance3D:
	stats[nm] = xfs.size()
	return mmi_on(self, nm, mesh, xfs, cols, mat, shadows, range_m)


## One MultiMesh under `parent`: per-instance colours when `cols` has them, hidden past `range_m`.
static func mmi_on(parent: Node3D, nm: String, mesh: Mesh, xfs: Array[Transform3D], cols: Array[Color], mat: Material, shadows: bool,
		range_m: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = range_m
	mi.visibility_range_end_margin = 30.0
	mi.set_meta("no_collide", true)
	parent.add_child(mi)
	return mi


static func _v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# --- The pumping station -------------------------------------------------------------------------

## Pump house No. 1: a red-brick hall with a gable roof and tall works windows, a brick standpipe
## tower with a riveted tank and a tiled cap, two teal mains out of the front wall, and the burst
## one fountaining over the forecourt.
func _build_station() -> void:
	var g := BuildingDetail.Geo.new()
	var hall: Rect2 = station_rects[0]
	var tower: Rect2 = station_rects[1]
	var hc: Vector2 = hall.get_center()
	var eaves: float = 12.0
	var ridge: float = 16.2
	var south := Vector3(0, 0, 1)
	g.uv = BuildingDetail._bay_uv(hall, 77)
	# Stone plinth, brick walls with works windows on the long sides, brick piers, a stone cornice.
	g.mat(BuildingDetail.K_COPING, STONE.darkened(0.12))
	g.abox(_v3(hall.position - Vector2(0.25, 0.25), 0.0), Vector3(hall.size.x + 0.5, 1.1, hall.size.y + 0.5))
	g.mat(BuildingDetail.K_FACADE, BRICK, T_RED, BuildingDetail.F_RIBBON)
	g.abox(_v3(hall.position, 0.0), Vector3(hall.size.x, eaves, hall.size.y), -2)
	g.mat(BuildingDetail.K_PLAIN, BRICK.darkened(0.12), T_RED)
	var piers: int = 6
	for i: int in piers + 1:
		var x: float = hall.position.x + hall.size.x * float(i) / float(piers)
		for z: float in [hall.position.y - 0.3, hall.end.y - 0.3]:
			g.abox(Vector3(x - 0.45, 0.0, z), Vector3(0.9, eaves, 0.6))
	g.mat(BuildingDetail.K_COPING, STONE)
	g.abox(_v3(hall.position - Vector2(0.45, 0.45), eaves - 0.5), Vector3(hall.size.x + 0.9, 0.55, hall.size.y + 0.9))
	g.abox(_v3(hall.position - Vector2(0.2, 0.2), 4.3), Vector3(hall.size.x + 0.4, 0.3, hall.size.y + 0.4))
	# The gable roof: two slopes of tile-red roofing, brick gable ends, a raised lantern on the ridge.
	g.mat(BuildingDetail.K_ROOF, Color(0.82, 0.34, 0.2), 0, BuildingDetail.F_ROOF_SEAMS_X)
	var x0: float = hall.position.x - 0.5
	var x1: float = hall.end.x + 0.5
	var z0: float = hall.position.y - 0.6
	var z1: float = hall.end.y + 0.6
	var zm: float = hc.y
	for sgn: float in [-1.0, 1.0]:
		var ze: float = z0 if sgn < 0.0 else z1
		var nrm := Vector3(0, absf(ze - zm), sgn * (ridge - eaves)).normalized()
		g.quad(Vector3(x0, eaves, ze), Vector3(x1, eaves, ze), Vector3(x1, ridge, zm), Vector3(x0, ridge, zm), nrm)
	g.mat(BuildingDetail.K_PLAIN, BRICK, T_RED)
	for xe: float in [hall.position.x, hall.end.x]:
		var out := Vector3(-1.0 if xe < hc.x else 1.0, 0, 0)
		g.tri(Vector3(xe, eaves, hall.position.y), Vector3(xe, eaves, hall.end.y), Vector3(xe, ridge - 0.15, zm), out)
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL.darkened(0.1), 0, BuildingDetail.F_RUST)
	g.abox(Vector3(hc.x - 4.0, ridge - 0.5, zm - 0.9), Vector3(8.0, 1.3, 1.8))
	g.mat(BuildingDetail.K_ROOF, Color(0.82, 0.34, 0.2))
	g.abox(Vector3(hc.x - 4.3, ridge + 0.8, zm - 1.2), Vector3(8.6, 0.12, 2.4))
	# The big sliding door on the street front, and the painted sign board over it.
	var fz: float = hall.end.y
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL, 0, BuildingDetail.F_RUST)
	g.abox(Vector3(hc.x - 5.6, 1.1, fz + 0.02), Vector3(4.2, 4.6, 0.16))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.abox(Vector3(hc.x - 6.0, 5.7, fz + 0.02), Vector3(8.6, 0.14, 0.22))
	g.mat(BuildingDetail.K_FLAT, Color(0.06, 0.36, 0.4))
	g.abox(Vector3(hc.x - 6.2, 8.6, fz + 0.3), Vector3(12.4, 1.9, 0.14))
	g.mat(BuildingDetail.K_FLAT, Color(0.93, 0.68, 0.1))
	g.abox(Vector3(hc.x - 6.3, 8.5, fz + 0.28), Vector3(12.6, 0.12, 0.2))
	g.abox(Vector3(hc.x - 6.3, 10.48, fz + 0.28), Vector3(12.6, 0.12, 0.2))
	_sign = Label3D.new()
	_sign.name = "StationSign"
	_sign.text = "OLD TOWN WATERWORKS"
	_sign.font_size = 160
	_sign.pixel_size = 0.0062
	_sign.outline_size = 0
	_sign.double_sided = false
	_sign.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_sign.position = Vector3(hc.x, 9.55, fz + 0.46)
	_sign.visibility_range_end = 260.0
	add_child(_sign)
	# The standpipe tower: a brick shaft with stone bands, the tank, a tiled cone and a finial.
	var tc: Vector2 = tower.get_center()
	var shaft: float = 25.0
	g.uv = BuildingDetail._bay_uv(tower, 78)
	g.mat(BuildingDetail.K_PLAIN, BRICK.darkened(0.05), T_RED)
	g.abox(_v3(tower.position, 0.0), Vector3(tower.size.x, shaft, tower.size.y), -2)
	g.mat(BuildingDetail.K_COPING, STONE)
	for y: float in [1.0, 8.0, 16.0, shaft - 0.4]:
		g.abox(_v3(tower.position - Vector2(0.22, 0.22), y - 0.3), Vector3(tower.size.x + 0.44, 0.6 if y > 2.0 else 1.0, tower.size.y + 0.44))
	g.mat(BuildingDetail.K_DARK, Color(0.04, 0.045, 0.05))
	for y2: float in [10.5, 19.0]:
		g.abox(Vector3(tc.x - 0.5, y2, tower.end.y - 0.02), Vector3(1.0, 2.6, 0.06))
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 0.2)), 4.0, 3.2, 0.4, 18)
	g.mat(BuildingDetail.K_METAL, Color(0.9, 0.84, 0.68), 0, BuildingDetail.F_HOOPS | BuildingDetail.F_RUST)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 3.2)), 3.7, 3.7, 5.6, 20)
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 2.2)), 3.76, 3.76, 1.0, 20, false)
	g.mat(BuildingDetail.K_FLAT, Color(0.82, 0.34, 0.2))
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 7.4)), 0.25, 4.1, 2.8, 20)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, _v3(tc, shaft + 9.6)), 0.05, 0.08, 1.8, 6)
	# A ladder up the tower's east face.
	for e: float in [-0.25, 0.25]:
		g.rod(Vector3(tower.end.x + 0.12, 0.3, tc.y + e), Vector3(tower.end.x + 0.12, shaft, tc.y + e), 0.03)
	for k: int in 50:
		g.rod(Vector3(tower.end.x + 0.12, 0.6 + k * 0.48, tc.y - 0.25), Vector3(tower.end.x + 0.12, 0.6 + k * 0.48, tc.y + 0.25), 0.02)
	# The two mains: out of the front wall, over concrete saddles, down into the street. The east
	# one burst at its last joint.
	var burst: Vector3 = station_at
	var pr: float = 0.55
	for pi: int in 2:
		var px: float = burst.x if pi == 1 else burst.x - 4.4
		var zend: float = burst.z - (0.9 if pi == 1 else -0.6)
		g.mat(BuildingDetail.K_METAL, PIPE_TEAL, 0, BuildingDetail.F_RUST)
		g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(px, 1.5, (fz + zend) * 0.5)), pr, pr, zend - fz, 14, false)
		g.mat(BuildingDetail.K_METAL, Color(0.78, 0.8, 0.8))
		for zf: float in [fz + 0.2, lerpf(fz, zend, 0.5), zend - 0.1]:
			g.cyl(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(px, 1.5, zf)), pr + 0.14, pr + 0.14, 0.16, 14)
		g.mat(BuildingDetail.K_COPING, STONE.darkened(0.2))
		for zs: float in [lerpf(fz, zend, 0.25), lerpf(fz, zend, 0.78)]:
			g.abox(Vector3(px - 0.8, 0.0, zs - 0.3), Vector3(1.6, 1.0, 0.6))
		# A red valve wheel on a stem.
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(px, 2.5, fz + 1.6)), 0.06, 0.06, 1.0, 6)
		g.mat(BuildingDetail.K_FLAT, Color(0.84, 0.14, 0.1))
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(px, 3.0, fz + 1.6)), 0.5, 0.5, 0.08, 12)
		if pi == 0:
			# The sound main drops into the ground through an elbow.
			g.mat(BuildingDetail.K_METAL, PIPE_TEAL, 0, BuildingDetail.F_RUST)
			g.cyl(Transform3D(Basis.IDENTITY, Vector3(px, 0.75, zend + pr * 0.2)), pr, pr, 1.5, 14)
		PropColliders.add_box(_body, Transform3D(Basis.IDENTITY, Vector3(px, 1.05, (fz + zend) * 0.5)), Vector3(1.4, 2.1, zend - fz))
		_rects.append(Rect2(px - 0.9, fz, 1.8, zend - fz + 0.4))
	# The torn end of the burst main: a split flange and a peeled-back plate.
	g.mat(BuildingDetail.K_METAL, PIPE_TEAL.darkened(0.2), 0, BuildingDetail.F_RUST)
	g.box(Transform3D(Basis.from_euler(Vector3(0.9, 0.3, 0.2)), burst + Vector3(0.5, 1.7, -0.5)), Vector3(0.9, 0.06, 1.1))
	g.box(Transform3D(Basis.from_euler(Vector3(-0.5, -0.4, 0.7)), burst + Vector3(-0.6, 1.3, -0.3)), Vector3(0.8, 0.06, 0.9))
	# Striped barriers round the hole and a warning beacon on a post.
	for bi: int in 5:
		var a: float = -0.5 + bi * 1.05
		var bp: Vector3 = burst + Vector3(sin(a) * 4.6, 0.0, cos(a) * 3.6 + 0.6)
		var bx := Transform3D(Basis(Vector3.UP, a + (0.25 if bi % 2 == 0 else -0.2)), bp)
		g.mat(BuildingDetail.K_FLAT, Color(0.96, 0.62, 0.06), 0, BuildingDetail.F_STRIPES)
		g.box(bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)), Vector3(2.0, 0.26, 0.06))
		g.box(bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0)), Vector3(2.0, 0.16, 0.06))
		g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
		for sx: float in [-0.9, 0.9]:
			g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx, 0.5, 0)), Vector3(0.07, 1.0, 0.07))
			g.box(bx * Transform3D(Basis.IDENTITY, Vector3(sx, 0.03, 0)), Vector3(0.1, 0.06, 0.7))
		PropColliders.add_box(_body, bx * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(2.0, 1.0, 0.25))
	var post: Vector3 = burst + Vector3(-2.2, 0.0, 1.6)
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	g.cyl(Transform3D(Basis.IDENTITY, post + Vector3(0, 1.6, 0)), 0.05, 0.07, 3.2, 8)
	var mi := MeshInstance3D.new()
	mi.name = "Station"
	mi.mesh = g.mesh()
	mi.material_override = material(false)
	mi.set_meta("no_collide", true)
	add_child(mi)
	stats["station_tris"] = g.tri_count()
	PropColliders.add_box(_body, Transform3D(Basis.IDENTITY, _v3(hc, eaves * 0.5)), Vector3(hall.size.x + 0.6, eaves, hall.size.y + 0.6))
	PropColliders.add_box(_body, Transform3D(Basis.IDENTITY, _v3(tc, shaft * 0.5)), Vector3(tower.size.x + 0.4, shaft, tower.size.y + 0.4))
	# The beacon lamp (its material flashes while the main is broken).
	_beacon = StandardMaterial3D.new()
	_beacon.albedo_color = Color(1.0, 0.55, 0.1)
	_beacon.emission_enabled = true
	_beacon.emission = _beacon.albedo_color
	var lamp := MeshInstance3D.new()
	lamp.name = "Beacon"
	lamp.mesh = ProcMesh.sphere(0.16, 10, 6)
	lamp.material_override = _beacon
	lamp.position = post + Vector3(0, 3.3, 0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lamp)
	burst_main = OldTownBurst.new()
	burst_main.name = "Burst"
	burst_main.position = burst
	add_child(burst_main)
	burst_main.build(material(false))


# --- The market -----------------------------------------------------------------------------------

## Market stalls along the main street's kerb: a steel frame, a striped canopy in the town's
## awning colours, a counter and crates of goods. One mesh in the town's building material.
func _build_market() -> void:
	var g := BuildingDetail.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = _site.seed_value + 2203
	var n: int = 0
	var road_x: float = CityLayout.PITCH * 0.5
	for side: float in [-1.0, 1.0]:
		var z: float = -98.0
		while z < 100.0:
			var p := Vector2(road_x + side * 2.9, z + rng.randf_range(-0.6, 0.6))
			z += rng.randf_range(4.6, 7.5)
			if absf(p.y) < 46.0 or p.length() > _site.town_r - 8.0 or not _free(p, Vector2(3.4, 2.4)):
				continue
			if absf(fposmod(p.y + CityLayout.PITCH * 0.5, CityLayout.PITCH) - CityLayout.PITCH * 0.5) < 7.5:
				continue  # the junctions stay open
			if rng.randf() < 0.3:
				continue
			_stall(g, p, PI * 0.5 * side + rng.randf_range(-0.08, 0.08), rng)
			n += 1
	stats["stalls"] = n
	if g.empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Market"
	mi.mesh = g.mesh()
	mi.material_override = material(false)
	mi.visibility_range_end = 240.0
	mi.set_meta("no_collide", true)
	add_child(mi)


## Whether a w x d footprint at p is dry and clear of buildings, wrecks, shelters and the station.
func _free(p: Vector2, size: Vector2) -> bool:
	var r := Rect2(p - size * 0.5, size)
	for q: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), p]:
		if _site._wet(q.x, q.y):
			return false
	for o: Rect2 in _site.footprints() + _site.prop_rects() + station_rects + _rects:
		if o.grow(0.4).intersects(r):
			return false
	return true


func _stall(g: BuildingDetail.Geo, p: Vector2, yaw: float, rng: RandomNumberGenerator) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.0, p.y))
	var col: Color = AWNING_COLS[rng.randi() % AWNING_COLS.size()]
	g.uv = Vector2.ZERO
	g.mat(BuildingDetail.K_METAL, BuildingDetail.METAL_DARK)
	for sx: float in [-1.4, 1.4]:
		for sz: float in [-0.9, 0.9]:
			g.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, 1.2 if sz > 0.0 else 1.35, sz)), Vector3(0.06, 2.4 if sz > 0.0 else 2.7, 0.06))
	# The canopy: a sloped striped sheet with a scalloped front valance.
	g.mat(BuildingDetail.K_FLAT, col, 0, BuildingDetail.F_STRIPES)
	g.box(xf * Transform3D(Basis(Vector3.RIGHT, 0.16), Vector3(0, 2.6, 0.05)), Vector3(3.2, 0.05, 2.3))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 2.28, 1.18)), Vector3(3.2, 0.28, 0.03))
	# Counter and goods.
	g.mat(BuildingDetail.K_FLAT, BuildingDetail.WOOD.lightened(0.15))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.45, 0.5)), Vector3(2.8, 0.9, 0.8))
	g.box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.55, -0.55)), Vector3(2.6, 1.1, 0.5))
	for k: int in 4:
		g.mat(BuildingDetail.K_FLAT, SIGN_COLS[rng.randi() % SIGN_COLS.size()])
		g.box(xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), Vector3(-1.05 + k * 0.7, 1.02, 0.5)), Vector3(0.56, 0.24, 0.5))
	PropColliders.add_box(_body, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), Vector3(3.0, 2.0, 2.0))
	var ext: Vector2 = Vector2(2.3, 3.2) if absf(sin(yaw)) > 0.5 else Vector2(3.2, 2.3)
	_rects.append(Rect2(p - ext * 0.5, ext))


# --- Rooftops -------------------------------------------------------------------------------------

## Water tanks on stilts, painted roof signs and parasols on the roofs of the pad town and the
## outskirts: three MultiMeshes, coloured per instance.
func _build_roofs() -> void:
	var roofs: Array = []  # [frame (site space), Rect2 in the frame, roof height, plan]
	for key: Vector2i in _site.layout.blocks:
		for bd: Dictionary in _site.layout.blocks[key]["buildings"]:
			roofs.append([Transform3D.IDENTITY, bd["rect"], float(int(bd["floors"])) * BuildingDetail.FLOOR_H + 0.15, bd])
	if _site.outskirts:
		roofs.append_array(_site.outskirts.roofs)
	var tanks: Array[Transform3D] = []
	var tank_c: Array[Color] = []
	var signs: Array[Transform3D] = []
	var sign_c: Array[Color] = []
	var shades: Array[Transform3D] = []
	var shade_c: Array[Color] = []
	for e: Array in roofs:
		var bd: Dictionary = e[3]
		if bool(bd.get("ruined", false)):
			continue
		var fr: Transform3D = e[0]
		var r: Rect2 = e[1]
		var y: float = e[2]
		var floors: int = int(bd["floors"])
		var face: Vector2 = bd["face"]
		var h: int = hash([int(bd["seed"]), 4421])
		var c: Vector2 = r.get_center()
		var back: Vector2 = -face
		var lat := Vector2(-face.y, face.x)
		var depth: float = absf(r.size.x * face.x) + absf(r.size.y * face.y)
		var width: float = absf(r.size.x * lat.x) + absf(r.size.y * lat.y)
		if depth < 6.5 or width < 6.5:
			continue
		# The tank stands on the back half (a setback tier keeps its back wall on the plan's).
		if floors >= 3 and h % 100 < 46:
			var tp: Vector2 = c + back * (depth * 0.5 - 2.3) + lat * (float((h >> 7) % 100) / 100.0 - 0.5) * (width - 4.8)
			var sc: float = 0.85 + float((h >> 14) % 40) / 100.0
			tanks.append(fr * Transform3D(Basis(Vector3.UP, float(h % 7)).scaled(Vector3.ONE * sc), _v3(tp, y)))
			tank_c.append(TANK_COLS[(h >> 3) % TANK_COLS.size()])
		# A painted sign on the street parapet of the walk-ups (no setbacks under six floors).
		if floors >= 3 and floors <= 5 and width >= 7.5 and (h >> 9) % 100 < 22:
			var sp: Vector2 = c + face * (depth * 0.5 - 0.7)
			signs.append(fr * Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), _v3(sp, y)))
			sign_c.append(SIGN_COLS[(h >> 5) % SIGN_COLS.size()])
		# Parasols on a roof terrace.
		if floors <= 7 and (h >> 11) % 100 < 30:
			for k: int in 1 + (h >> 4) % 3:
				var pp: Vector2 = c + lat * (float(k) - 1.0) * 2.6 + face * (depth * 0.1) + back * float((h >> (k + 2)) % 3)
				if not r.grow(-1.6).has_point(pp):
					continue
				shades.append(fr * Transform3D(Basis(Vector3.UP, float(k)), _v3(pp, y)))
				shade_c.append(AWNING_COLS[((h >> 6) + k) % AWNING_COLS.size()])
	var mat: StandardMaterial3D = _vc_material()
	if not tanks.is_empty():
		_mmi("RoofTanks", _tank_mesh(), tanks, tank_c, mat, true, 520.0)
	if not signs.is_empty():
		_mmi("RoofSigns", _sign_mesh(), signs, sign_c, mat, true, 520.0)
	if not shades.is_empty():
		_mmi("RoofShades", _shade_mesh(), shades, shade_c, mat, false, 320.0)


## A wooden roof tank: four steel legs with braces, a platform, the staved barrel with three
## hoops and a shallow cone. The barrel takes the instance colour.
static func _tank_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	var dark := Color(0.2, 0.2, 0.21)
	g.col = dark
	for sx: float in [-0.95, 0.95]:
		for sz: float in [-0.95, 0.95]:
			g.rod(Vector3(sx, 0.0, sz), Vector3(sx * 0.85, 2.2, sz * 0.85), 0.07)
	for a: Array in [[Vector3(-0.95, 0.2, -0.95), Vector3(0.85, 2.0, -0.85)], [Vector3(0.95, 0.2, 0.95), Vector3(-0.85, 2.0, 0.85)],
			[Vector3(-0.95, 0.2, 0.95), Vector3(-0.85, 2.0, -0.85)], [Vector3(0.95, 0.2, -0.95), Vector3(0.85, 2.0, 0.85)]]:
		g.rod(a[0], a[1], 0.035)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 2.25, 0)), 1.45, 1.45, 0.12, 12)
	g.col = Color(1, 1, 1)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 3.55, 0)), 1.25, 1.32, 2.5, 14)
	g.col = Color(0.3, 0.3, 0.32)
	for y: float in [2.7, 3.5, 4.4]:
		g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), 1.31, 1.34, 0.08, 14, false)
	g.col = Color(0.62, 0.6, 0.58)
	g.cyl(Transform3D(Basis.IDENTITY, Vector3(0, 5.2, 0)), 0.08, 1.4, 0.8, 14)
	return _vc_mesh(g)


## A roof sign: a steel frame and a painted board facing +Z, the instance colour as its field
## with a dark lettering band and two darker rules across it.
static func _sign_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.18, 0.18, 0.19)
	for sx: float in [-2.8, 0.0, 2.8]:
		g.rod(Vector3(sx, 0.0, -0.15), Vector3(sx, 4.6, -0.15), 0.06)
		g.rod(Vector3(sx, 0.0, -1.6), Vector3(sx, 3.4, -0.15), 0.04)
	g.rod(Vector3(-3.1, 1.5, -0.15), Vector3(3.1, 1.5, -0.15), 0.05)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.1, -0.06)), Vector3(6.5, 3.1, 0.06))
	g.col = Color(1, 1, 1)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.1, 0.0)), Vector3(6.3, 2.9, 0.06))
	g.col = Color(0.3, 0.3, 0.3)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 3.5, 0.02)), Vector3(5.5, 0.7, 0.06))
	g.col = Color(0.55, 0.55, 0.55)
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0.02)), Vector3(5.5, 0.22, 0.06))
	g.box(Transform3D(Basis.IDENTITY, Vector3(0, 4.3, 0.02)), Vector3(6.3, 0.14, 0.06))
	return _vc_mesh(g)


## A terrace parasol: a pole and an eight-panel canopy, alternate panels a darker shade.
static func _shade_mesh() -> ArrayMesh:
	var g := BuildingDetail.Geo.new()
	g.col = Color(0.3, 0.3, 0.3)
	g.rod(Vector3(0, 0, 0), Vector3(0, 2.3, 0), 0.03)
	var top := Vector3(0, 2.55, 0)
	for i: int in 8:
		var a0: float = TAU * float(i) / 8.0
		var a1: float = TAU * float(i + 1) / 8.0
		var p0 := Vector3(cos(a0) * 1.45, 2.1, sin(a0) * 1.45)
		var p1 := Vector3(cos(a1) * 1.45, 2.1, sin(a1) * 1.45)
		g.col = Color(1, 1, 1) if i % 2 == 0 else Color(0.55, 0.55, 0.55)
		var nrm: Vector3 = (p1 - top).cross(p0 - top).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		g.tri(top, p0, p1, nrm)
		g.tri(top, p0, p1, -nrm)
	return _vc_mesh(g)


# --- Street trees ---------------------------------------------------------------------------------

## Street trees in the kerb strip of every block (OldTownTrees): bare at the start, in leaf from
## stage 3, in blossom with flowers at their feet at stage 5.
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _site.seed_value + 3301
	var spots: Array[Vector2] = []
	var blocked: Array[Vector2] = []
	if _site.furniture:
		blocked.append_array(_site.furniture.obstacles)
	for key: Vector2i in _site.layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var c := Vector2(key) * CityLayout.PITCH
		for o: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			var along := Vector2(-o.y, o.x)
			for t: float in [-9.6, -3.2, 3.2, 9.6]:
				if rng.randf() < 0.22:
					continue
				var p: Vector2 = c + o * 12.75 + along * (t + rng.randf_range(-0.5, 0.5))
				if p.length() < 27.0 or p.length() > _site.town_r - 4.0 or not _free(p, Vector2(0.8, 0.8)):
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


# --- Lamps ----------------------------------------------------------------------------------------

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
	_lamp_glow = _mmi("LampGlow", ProcMesh.sphere(1.0, 10, 6), xfs, cols, m, false, 240.0)


# --- The lake edge --------------------------------------------------------------------------------

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
							film.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(1.6, 3.2), 1.0, rng.randf_range(1.0, 2.2))), _v3(q, WATER_Y + 0.03)))
					if rng.randf() < 0.55:
						var rq: Vector2 = p + n * rng.randf_range(0.2, 1.6)
						if not _site._wet(rq.x, rq.y):
							rq = p
						if rq.length() > 16.0:
							reed.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.8, 2.8)), _v3(rq, WATER_Y - 0.05)))
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
		_scum = _mmi("ShoreScum", disc.commit(), film, [], fm, false, 260.0)
	var grass: Array[Mesh] = PlantParts.variants("grass_medium_02", 300)
	if not reed.is_empty() and not grass.is_empty():
		_reeds = _mmi("ShoreReeds", grass[0], reed, [], null, false, 200.0)
