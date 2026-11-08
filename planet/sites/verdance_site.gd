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
const START_EXTENT: float = 36.0   # 3 x 3 blocks, 108 m, on the start pad (140 m flat radius)
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
	parent.add_child(s)
	await s._make()
	return s


## Site-local rectangles that are solid (building footprints): the globe clears junk under them.
func footprints() -> Array[Rect2]:
	return _foot.duplicate()


## Anchors inside the hub yard (the centre block, ~11 m half-size): the depot and the bench on
## the south corners either side of the pod door, the rocket pad on the north side. Lumi spawns
## at (0, 6) facing north, so the way out of the yard stays open.
func anchors() -> Dictionary:
	return {
		"depot": [Vector3(8.0, 0, 7.5), -PI * 0.5],
		"bench": [Vector3(-8.0, 0, 7.5), PI * 0.5],
		"door": [Vector3(0, 0, 9.5), 0.0],
		"rocket_pad": [Vector3(0, 0, -6.5), 0.0],
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
	if ks != _kit_state:
		_kit_state = ks
		for k: KitBuilding in kits:
			k.set_state(ks)
			k.set_powered(level >= 2)


## The kit state for a base level: broken (1), repaired (2-3), restored (4-5).
static func kit_state(l: int) -> String:
	return "broken" if l <= 1 else ("repaired" if l <= 3 else "restored")


func set_restoration(r: float) -> void:
	restoration = clampf(r, 0.0, 1.0)


# --- Build ----------------------------------------------------------------------------------

func _make() -> void:
	var start: bool = site_id == "start_yard"
	layout = CityLayout.new(seed_value, START_EXTENT if start else HUB_EXTENT)
	_ruin_layout(not start)
	city = CityView.new()
	city.name = "City"
	city.skyline = false
	city.buildings = false  # the kit's buildings instead (below)
	add_child(city)
	await city.build(layout, _sidewalk_material())
	_roads()
	_kit_blocks()
	dressing = StreetDressing.new()
	dressing.name = "Dressing"
	dressing.skip_facades = true
	add_child(dressing)
	await dressing.build(layout, null, hub_index, district_name, "", level)
	set_level(level)


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
	for axis: int in 2:
		for k: int in range(-n, n + 1):
			var c: float = (k + 0.5) * CityLayout.PITCH
			if absf(c) > e:
				continue
			var t: float = -e
			while t < e - 0.01:
				var t1: float = minf(t + step, e)
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


func _road_quad(st: SurfaceTool, axis: int, c: float, t0: float, t1: float, hw: float, e: float) -> void:
	var y: float = 0.03
	var pts: Array[Vector3] = []
	for tt: float in [t0, t1]:
		for s: float in [-hw, hw]:
			pts.append(Vector3(c + s, y, tt) if axis == 0 else Vector3(tt, y, c + s))
	var fade := func(tt: float, s: float) -> float:
		var edge: float = e - absf(tt)
		var wob: float = sin(tt * 0.7 + s * 1.3 + c) * 2.5
		return clampf((edge - 4.0 + wob) / 10.0, 0.0, 1.0)
	var cols: Array[Color] = []
	for tt: float in [t0, t1]:
		for s: float in [-hw, hw]:
			var a: float = fade.call(tt, s)
			var g: float = 0.9 + 0.1 * sin(tt * 1.7 + c)
			cols.append(Color(g, g, g, a))
	var idx: Array[int] = [0, 1, 2, 1, 3, 2]
	for i: int in idx:
		st.set_color(cols[i])
		var p: Vector3 = pts[i]
		st.set_uv(Vector2(p.x, p.z) * 0.25)
		st.add_vertex(p)


## Block layouts in block-local metres (the inner rect is ~21.8 m square): [kind, x, z, yaw°].
const PATTERNS: Array = [
	[["module_large", 0.0, 0.0, 0.0]],
	[["module_medium", 0.0, -5.4, 0.0], ["module_medium", 0.0, 5.4, 180.0]],
	[["module_small", -5.0, -4.6, 0.0], ["module_small", 5.0, -4.6, 0.0], ["machine_housing", -5.0, 5.0, 180.0], ["module_small", 5.0, 5.0, 180.0]],
	[["hangar", 0.0, 0.0, 90.0]],
	[["tank_farm", 0.0, -4.0, 0.0], ["machine_housing", 0.0, 6.2, 180.0]],
	[["tower", -5.5, -5.5, 0.0], ["module_medium", 3.5, 4.0, 180.0]],
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
	var junk := KitMesh.Builder.new(seed_value, {"main": "cream", "accent": "teal"}, _kit_state)
	var any_junk: bool = false
	for key: Vector2i in layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var b: Dictionary = layout.blocks[key]
		var c: Vector2 = (b["rect"] as Rect2).get_center()
		match int(b["type"]):
			CityLayout.Block.BUILDINGS:
				var pat: Array = PATTERNS[rng.randi() % PATTERNS.size()]
				var turn: float = float(rng.randi() % 4) * 90.0 if pat.size() == 1 else (0.0 if rng.randf() < 0.5 else 180.0)
				for e: Array in pat:
					var kind: String = e[0]
					var lp := Vector2(float(e[1]), float(e[2])).rotated(deg_to_rad(-turn))
					var yaw: float = deg_to_rad(float(e[3]) + turn)
					var pal: Dictionary = {"main": "cream", "accent": ACCENTS[rng.randi() % ACCENTS.size()]}
					var kb: KitBuilding = KitBuilding.create(kind, _kit_state, 1 + rng.randi() % 3, pal, level >= 2)
					kb.position = Vector3(c.x + lp.x, 0.0, c.y + lp.y)
					kb.rotation.y = yaw
					kit_root.add_child(kb)
					kits.append(kb)
					var fp: Vector2 = KitBuilding.FOOTPRINT.get(kind, Vector2(10, 10)) * 0.8
					if absf(sin(yaw)) > 0.5:
						fp = Vector2(fp.y, fp.x)
					_foot.append(Rect2(Vector2(kb.position.x, kb.position.z) - fp * 0.5, fp))
			CityLayout.Block.LANDFILL:
				any_junk = true
				var t := Transform3D(Basis(), Vector3(c.x, 0, c.y))
				KitProps.debris(junk, t, 9.0, 26)
				KitProps.crate_stack(junk, t * KitMesh.xf(Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)), Vector3(0, rng.randf() * 90.0, 0)), 3 + rng.randi() % 3, _kit_state)
				for k: int in 3:
					KitProps.barrel(junk, t * KitMesh.xf(Vector3(rng.randf_range(-8, 8), 0.0, rng.randf_range(-8, 8)), Vector3(0, rng.randf() * 180.0, 0)), "paint:barrel", rng.randf() < 0.5)
				var gp: Node3D = KitMesh.ground_patch(Vector2(18, 18), _kit_state, 1 + rng.randi() % 3)
				gp.position = Vector3(c.x, 0, c.y)
				kit_root.add_child(gp)
	if any_junk:
		var mi: MeshInstance3D = KitMesh.instance(junk)
		mi.name = "LotJunk"
		kit_root.add_child(mi)
	# The kit has no bodies of its own: one trimesh body for the buildings' solid meshes.
	SitePrefab.collision_for(kit_root, self)
