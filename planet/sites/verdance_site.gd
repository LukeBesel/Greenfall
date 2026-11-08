class_name VerdanceSite
extends Node3D
## [orbD] Verdance's hub sites on the walkable globe, built from the flat game's real city kit:
## a small local CityLayout (a 3 x 3 block grid around the hub yard, 5 x 5 for the start yard)
## dressed by CityView (modular facade kits, BuildingDetail roofs, sidewalks, kerbs, street
## furniture) and StreetDressing (shopfronts, murals, billboard, yard slab and paint, puddles,
## weeds, drifts, the landmark, the ruin layer). Nothing grey-boxed.
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
const START_EXTENT: float = 72.0   # 5 x 5 blocks, 180 m: on the start pad (140 m flat radius)
const HUB_EXTENT: float = 36.0     # 3 x 3 blocks, 108 m
## Which share of buildings are broken off on a ruined hub.
const RUIN_SHARE: float = 0.7

var site_id: String = "ruin_block"
var hub_index: int = 0
var seed_value: int = 4471
var level: int = 1
var restoration: float = 0.0
var layout: CityLayout
var city: CityView
var dressing: StreetDressing
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
	var out: Array[Rect2] = []
	if layout == null:
		return out
	for bd: Dictionary in layout.all_buildings():
		out.append(bd["rect"])
	return out


## Half-size of the built area (m).
func extent() -> float:
	return layout.extent + CityLayout.PITCH * 0.5 if layout else HUB_EXTENT


func set_level(l: int) -> void:
	level = clampi(l, 1, 5)
	if dressing:
		dressing.set_level(level, is_inside_tree())
	if _rubble:
		_rubble.visible = level <= 1


func set_restoration(r: float) -> void:
	restoration = clampf(r, 0.0, 1.0)


# --- Build ----------------------------------------------------------------------------------

func _make() -> void:
	var start: bool = site_id == "start_yard"
	layout = CityLayout.new(seed_value, START_EXTENT if start else HUB_EXTENT)
	if not start:
		_ruin_layout()
	city = CityView.new()
	city.name = "City"
	add_child(city)
	await city.build(layout, _sidewalk_material())
	_roads()
	dressing = StreetDressing.new()
	dressing.name = "Dressing"
	add_child(dressing)
	await dressing.build(layout, null, hub_index, district_name, "", level)
	if not start:
		_build_rubble()
	set_level(level)


## Per-hub block mix and broken buildings: the inner ring is reshuffled (buildings, landfill,
## parking, vacant lots) and most buildings are broken off a few floors down.
func _ruin_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 61
	var kinds: Array[int] = [CityLayout.Block.BUILDINGS, CityLayout.Block.BUILDINGS, CityLayout.Block.BUILDINGS,
		CityLayout.Block.LANDFILL, CityLayout.Block.PARKING, CityLayout.Block.VACANT]
	for key: Vector2i in layout.blocks:
		if key == Vector2i.ZERO:
			continue
		var b: Dictionary = layout.blocks[key]
		var t: int = kinds[rng.randi() % kinds.size()]
		b["type"] = t
		b["buildings"] = layout._make_buildings(b["rect"], rng, key) if t == CityLayout.Block.BUILDINGS else []
		for bd: Dictionary in b["buildings"]:
			bd["ruined"] = rng.randf() < RUIN_SHARE
			bd["floors"] = mini(int(bd["floors"]), 5)
		layout.blocks[key] = b


func _sidewalk_material() -> Material:
	var m: StandardMaterial3D = AssetLib.pbr_material("concrete_pavement", 0.35, Color(0.78, 0.76, 0.72), true)
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


## Rubble at the foot of broken buildings: real junk/debris models in MultiMeshes, mounds of
## broken concrete (lumpy meshes), tipped slabs. Shown while the base is ruined (level 1).
func _build_rubble() -> void:
	_rubble = Node3D.new()
	_rubble.name = "Rubble"
	add_child(_rubble)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 97
	var conc: StandardMaterial3D = AssetLib.pbr_material("concrete_wall_008", 0.5, Color(0.62, 0.6, 0.56), true)
	var brick: StandardMaterial3D = AssetLib.pbr_material("red_brick", 0.6, Color(0.7, 0.6, 0.56), true)
	var b := FrontierView.Batch.new()
	for bd: Dictionary in layout.all_buildings():
		if not bool(bd.get("ruined", false)):
			continue
		var r: Rect2 = bd["rect"]
		var face: Vector2 = bd["face"]
		var n: int = 3 + int(r.size.length() / 6.0)
		for k: int in n:
			# Spill out in front of the facade, onto the sidewalk and the street.
			var along: float = rng.randf()
			var p2: Vector2
			if absf(face.y) > 0.5:
				p2 = Vector2(lerpf(r.position.x, r.end.x, along), (r.position.y if face.y < 0 else r.end.y) + face.y * rng.randf_range(0.5, 4.5))
			else:
				p2 = Vector2((r.position.x if face.x < 0 else r.end.x) + face.x * rng.randf_range(0.5, 4.5), lerpf(r.position.y, r.end.y, along))
			var sz := Vector3(rng.randf_range(0.5, 1.6), rng.randf_range(0.2, 0.7), rng.randf_range(0.4, 1.3))
			var bas := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))).scaled(sz)
			b.add(_chunk_mesh(), Transform3D(bas, Vector3(p2.x, sz.y * 0.25, p2.y)), brick if rng.randf() < 0.35 else conc)
		# A long tipped slab off the broken top, leaning on the facade.
		if rng.randf() < 0.55:
			var mid: Vector2 = r.get_center() + face * (minf(r.size.x, r.size.y) * 0.5 + 1.2)
			var yaw: float = atan2(face.x, face.y)
			var bas2 := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -rng.randf_range(0.35, 0.7))
			b.add(_chunk_mesh(), Transform3D(bas2.scaled(Vector3(rng.randf_range(2.4, 4.0), 0.25, rng.randf_range(2.5, 4.5))), Vector3(mid.x, 0.9, mid.y)), conc)
	b.flush(_rubble)
	for c: Node in _rubble.get_children():
		c.set_meta("no_collide", true)


static var _chunk: ArrayMesh


## A chunky broken-concrete lump (unit size, bevelled, irregular): never a raw box.
static func _chunk_mesh() -> ArrayMesh:
	if _chunk:
		return _chunk
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 7
	sm.rings = 4
	var arr: Array = sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nz := FastNoiseLite.new()
	nz.seed = 7
	nz.frequency = 2.2
	for i: int in v.size():
		var p: Vector3 = v[i]
		var k: float = 1.0 + nz.get_noise_3dv(p * 2.0) * 0.35
		p *= k
		# Flatten into a slab-ish chunk with a facetted top.
		p.y = clampf(p.y, -0.42, 0.38)
		v[i] = p
	arr[Mesh.ARRAY_VERTEX] = v
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(tmp, 0)
	st.set_smooth_group(-1)
	st.generate_normals()
	_chunk = st.commit()
	return _chunk
