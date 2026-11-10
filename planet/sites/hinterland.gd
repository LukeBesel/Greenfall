class_name Hinterland
extends Node3D
## [v3city] The land between Verdance's hub towns (owner item 42: "suburbs, outskirts or industrial
## edge, not empty plains"). Past every hub's outskirts (HUB_CLEAR_M from a hub) the ground gets
## scattered buildings and props, decided per fine hex from the planet seed:
##   zones (low-frequency noise): open junk fields, suburbs (detached houses, sheds, poles) and
##   industrial edges (warehouses, works sheds, tanks). Denser just outside the hubs' outskirts.
##   spacing: at most one building a hex (hexes are ~17 m apart), the big works only on a hex that
##   out-rolls its neighbours, so there are always 5+ m walkable gaps; never on water, a shore or a
##   hub site.
## Drawing is cheap: a handful of building archetypes (BuildingDetail proxies in object space,
## building_city local_space) and props as MultiMeshes over the whole ring round Lumi, with a far
## LOD (bare boxes) past NEAR_M; rebuilt when Lumi has moved REBUILD_M. Hexes are decided a few
## hundred per frame and cached. Colliders only for buildings within COLLIDE_M of Lumi. Every
## footprint goes into the junk keep-out (YardKeepOut.add_world) before Lumi gets near, so the
## junk lies round the buildings, not inside them.
## [v5look] So it reads as outskirts, not scattered boxes:
##   tracks: old roads wind between the zones (the edge of a low-frequency noise region, so they
##   are continuous chains of hexes). A track hex has no building; the hexes beside it get more
##   houses, which face the road, and power poles along it. Each hex draws a half-link to every
##   track neighbour (one MultiMesh of dusty asphalt strips), and junk keeps off the lane.
##   houses: pitched tile roofs with a chimney, a per-building tint and height (MultiMesh instance
##   colour and scale), and a yard: a garden shed, picket fences, sometimes a wreck in the drive.

const VIEW_M: float = 520.0
const NEAR_M: float = 170.0
const COLLIDE_M: float = 70.0
const REBUILD_M: float = 45.0
const HUB_CLEAR_M: float = 345.0
const CELLS_PER_FRAME: int = 600

## Archetypes: [name, width (along X), depth (Z), floors, style].
const ARCH: Array = [
	["house_a", 9.0, 8.0, 1, "apartments"],
	["house_b", 9.0, 7.5, 2, "apartments"],
	["block", 12.0, 10.0, 3, "apartments"],
	["shed", 9.0, 12.0, 1, "factory"],
	["warehouse", 18.0, 15.0, 2, "factory"],
	["works", 15.0, 12.0, 3, "factory"],
]
const PROPS: Array[String] = ["car", "pole", "tank", "fence", "shed", "picket", "track"]
const VARIANTS: int = 4  # looks per archetype (palette, shopfront, roof clutter, roof colour)
const K_SHED: int = -5
const K_PICKET: int = -6
const K_TRACK: int = -7
const TRACK_W: float = 4.4
## [v5look] Tile and sheet colours of the pitched roofs, and soft paint tints per building.
const ROOF_TILES: Array[Color] = [Color(0.66, 0.29, 0.2), Color(0.3, 0.34, 0.4), Color(0.45, 0.3, 0.22), Color(0.33, 0.42, 0.34)]
const TINTS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.95, 0.85), Color(0.9, 0.95, 1.0), Color(0.9, 0.97, 0.9), Color(1.0, 0.9, 0.87), Color(0.86, 0.85, 0.84), Color(1.0, 0.97, 0.78)]

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var keep_out: YardKeepOut
var hub_dirs: Array[Vector3] = []
var seed_value: int = 4471
var focus: Node3D
signal rebuilt  # [v5look] after each rebuild of the ring (dev hooks)

var stats: Dictionary = {"cells": 0, "buildings": 0, "props": 0, "rebuilds": 0, "last_ms": 0}

var _zone := FastNoiseLite.new()
var _angle := FastNoiseLite.new()
var _track := FastNoiseLite.new()
var _track_n: Dictionary = {}   # cell -> noise value
var _track_is: Dictionary = {}  # cell -> bool
var _decided: Dictionary = {}   # cell -> Array of [kind (archetype index, or -1 - prop index), Transform3D world, size: Vector2]
var _pending := PackedInt32Array()
var _pending_at: int = 0
var _last_pos := Vector3.INF
var _mm_near: Array[MultiMeshInstance3D] = []
var _mm_far: Array[MultiMeshInstance3D] = []
var _mm_props: Array[MultiMeshInstance3D] = []
var _body: StaticBody3D
var _body_pos := Vector3.INF
var _rng := RandomNumberGenerator.new()


func setup(p_grid: SphereGrid, p_terrain: SphereTerrain, p_cells: SphereCells, p_hubs: Array[Vector3], p_seed: int, p_keep_out: YardKeepOut) -> void:
	grid = p_grid
	terrain = p_terrain
	cells = p_cells
	hub_dirs = p_hubs
	seed_value = p_seed
	keep_out = p_keep_out
	_zone.seed = seed_value + 811
	_zone.frequency = 1.0 / 380.0
	_zone.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_angle.seed = seed_value + 812
	_angle.frequency = 1.0 / 600.0
	_track.seed = seed_value + 813
	_track.frequency = 1.0 / 300.0
	_track.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_archetypes()
	_body = StaticBody3D.new()
	_body.name = "Colliders"
	add_child(_body)


# --- Archetype meshes -----------------------------------------------------------------------

func _build_archetypes() -> void:
	var det := BuildingDetail.new()
	var mat: ShaderMaterial = TownOutskirts.material()
	for vi: int in ARCH.size() * VARIANTS:
		var i: int = int(vi / float(VARIANTS))
		var a: Array = ARCH[i]
		var w: float = a[1]
		var d: float = a[2]
		var r := Rect2(-w * 0.5, -d * 0.5, w, d)
		var gabled: bool = i <= 1 or i == 3  # [v5look] houses and the works shed get pitched roofs (no flat-roof clutter under them)
		var bd: Dictionary = {"rect": r, "face": Vector2(0, 1), "bays": int(w / 3.0), "floors": int(a[3]), "style": a[4], "seed": 9001 + vi * 7919, "ruined": vi % 2 == 1 or gabled}
		var body := BuildingDetail.Geo.new()
		var dg := BuildingDetail.Geo.new()
		det.proxy_building(bd, body, dg)
		body.mat(BuildingDetail.K_PLAIN, Color(0.56, 0.54, 0.5), BuildingDetail.T_CONCRETE)
		body.abox(Vector3(r.position.x - 0.3, -2.6, r.position.y - 0.3), Vector3(w + 0.6, 2.62, d + 0.6))
		if gabled:
			_gable(body, w, d, float(a[3]) * BuildingDetail.FLOOR_H, vi, i == 3)
		# Near: the body and its roof clutter in one mesh. Far: the body alone.
		var near_g := BuildingDetail.Geo.new()
		near_g.v = body.v + dg.v
		near_g.n = body.n + dg.n
		near_g.c = body.c + dg.c
		near_g.u = body.u + dg.u
		near_g.u2 = body.u2 + dg.u2
		_mm_near.append(_mmi("Near_" + str(a[0]), near_g.mesh(), mat, true, true))
		_mm_far.append(_mmi("Far_" + str(a[0]), body.mesh(), mat, false, true))
	for p: String in PROPS:
		_mm_props.append(_mmi("Prop_" + p, _track_mesh() if p == "track" else _prop_mesh(p), null, not p in ["fence", "picket", "track"]))


## [v5look] A pitched roof over a proxy body (ridge along X): two tiled slopes with an overhang,
## closed gable ends, a soffit (seen from Lumi's height), a fascia and sometimes a chimney. It sits
## on the proxy's parapet, which then reads as the top of the wall.
func _gable(g: BuildingDetail.Geo, w: float, d: float, y1: float, vi: int, sheet: bool) -> void:
	var ov: float = 0.3 if sheet else 0.55
	var ye: float = y1 + 1.25
	var run: float = d * 0.5 + ov
	var yr: float = ye + run * (0.28 if sheet else 0.62)
	var x0: float = -w * 0.5 - ov
	var x1: float = w * 0.5 + ov
	var rise: float = yr - ye
	if sheet:
		g.mat(BuildingDetail.K_METAL, [Color(0.58, 0.6, 0.62), Color(0.5, 0.42, 0.36), Color(0.44, 0.52, 0.56), Color(0.62, 0.58, 0.5)][vi % 4], 0, BuildingDetail.F_RUST)
	else:
		g.mat(BuildingDetail.K_ROOF, ROOF_TILES[vi % ROOF_TILES.size()], 0, 0)
	g.quad(Vector3(x0, ye, run), Vector3(x1, ye, run), Vector3(x1, yr, 0), Vector3(x0, yr, 0), Vector3(0, run, rise).normalized())
	g.quad(Vector3(x1, ye, -run), Vector3(x0, ye, -run), Vector3(x0, yr, 0), Vector3(x1, yr, 0), Vector3(0, run, -rise).normalized())
	g.mat(BuildingDetail.K_PLAIN, [Color(0.6, 0.56, 0.5), Color(0.56, 0.5, 0.44), Color(0.62, 0.6, 0.56), Color(0.52, 0.5, 0.46)][(vi / 2) % 4], BuildingDetail.T_CONCRETE)
	g.tri(Vector3(x0, ye, -run), Vector3(x0, ye, run), Vector3(x0, yr, 0), Vector3(-1, 0, 0))
	g.tri(Vector3(x1, ye, -run), Vector3(x1, ye, run), Vector3(x1, yr, 0), Vector3(1, 0, 0))
	g.mat(BuildingDetail.K_PLAIN, Color(0.5, 0.47, 0.43), BuildingDetail.T_CONCRETE)
	g.quad(Vector3(x0, ye, -run), Vector3(x1, ye, -run), Vector3(x1, ye, run), Vector3(x0, ye, run), Vector3(0, -1, 0))
	g.mat(BuildingDetail.K_COPING, BuildingDetail.COPING.darkened(0.12))
	for sz: float in [-1.0, 1.0]:
		g.abox(Vector3(x0, ye - 0.14, sz * run - 0.06), Vector3(x1 - x0, 0.16, 0.12))
	g.abox(Vector3(x0, yr - 0.05, -0.12), Vector3(x1 - x0, 0.14, 0.24))  # ridge cap
	if not sheet and vi % 4 != 2:
		var cx: float = w * (0.24 if vi % 2 == 0 else -0.27)
		var cz: float = d * 0.16
		g.mat(BuildingDetail.K_PLAIN, Color(0.92, 0.72, 0.62), BuildingDetail.T_RED_BRICK)
		g.abox(Vector3(cx - 0.4, ye + rise * 0.35, cz - 0.4), Vector3(0.8, rise * 0.65 + 0.9, 0.8))
		g.mat(BuildingDetail.K_COPING, BuildingDetail.COPING.darkened(0.3))
		g.abox(Vector3(cx - 0.48, yr + 0.85, cz - 0.48), Vector3(0.96, 0.12, 0.96))


## [v5look] One half-link of a track: a unit strip along +Z (scaled to its length per instance),
## dusty cracked asphalt with a worn centre dash and pale verges.
func _track_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = TRACK_W * 0.5
	var parts: Array = [  # x0, x1, y_top, z0, z1, colour
		[-hw, hw, 0.0, 0.0, 1.0, Color(0.3, 0.29, 0.28)],
		[-0.08, 0.08, 0.012, 0.25, 0.75, Color(0.8, 0.74, 0.56)],
		[-hw, -hw + 0.3, 0.01, 0.0, 1.0, Color(0.46, 0.42, 0.36)],
		[hw - 0.3, hw, 0.01, 0.0, 1.0, Color(0.46, 0.42, 0.36)],
	]
	for pt: Array in parts:
		var a := Vector3(pt[0], pt[2], pt[3])
		var b := Vector3(pt[1], pt[2], pt[3])
		var c := Vector3(pt[1], pt[2], pt[4])
		var e := Vector3(pt[0], pt[2], pt[4])
		st.set_color(pt[5])
		st.set_normal(Vector3.UP)
		for v: Vector3 in [a, b, c, a, c, e]:
			st.add_vertex(v)
		if is_equal_approx(float(pt[2]), 0.0):  # skirts on the long sides (the strip can bridge a dip)
			for sx: float in [pt[0], pt[1]]:
				st.set_normal(Vector3(signf(sx), 0, 0))
				var t0 := Vector3(sx, 0, 0)
				var t1 := Vector3(sx, 0, 1)
				var b0 := Vector3(sx, -0.6, 0)
				var b1 := Vector3(sx, -0.6, 1)
				for v2: Vector3 in ([t0, b1, b0, t0, t1, b1] if sx > 0.0 else [t0, b0, b1, t0, b1, t1]):
					st.add_vertex(v2)
	var m: ArrayMesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = AssetLib.tex("asphalt_02", "diff")
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.22, 0.22, 0.22)
	mat.albedo_color = Color(1.7, 1.7, 1.7)  # the asphalt texture is dark: the vertex colour sets the tone
	mat.roughness = 1.0
	mat.metallic_specular = 0.2
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	return m


## (No visibility ranges: a MultiMesh spans the whole ring, so near/far is split per instance on
## each rebuild instead.)
func _mmi(nm: String, mesh: Mesh, mat: Material, shadow: bool, colors: bool = false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors  # [v5look] buildings: a tint per instance (the city shader's COLOR.rgb)
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	if mat:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	add_child(mi)
	return mi


func _prop_mesh(p: String) -> Mesh:
	var b := KitMesh.Builder.new(77, {}, "broken")
	match p:
		"car":
			b.box("paint:#7a3b30", Vector3(1.78, 0.62, 4.2), KitMesh.xf(Vector3(0, 0.6, 0)), 0.09)
			b.box("paint:#7a3b30", Vector3(1.6, 0.5, 2.0), KitMesh.xf(Vector3(0, 1.15, -0.15)), 0.08)
			b.box("glass", Vector3(1.62, 0.36, 1.8), KitMesh.xf(Vector3(0, 1.17, -0.15)), 0.02)
			for sx: float in [-0.78, 0.78]:
				for sz: float in [-1.35, 1.35]:
					b.cyl("paint:#141416", 0.32, 0.22, KitMesh.xf(Vector3(sx - 0.11 * signf(sx), 0.32, sz), Vector3(0, 0, 90)), 0.05, 12)
		"pole":
			b.cyl("paint:#4a3a2a", 0.13, 8.5, KitMesh.xf(Vector3.ZERO), 0.02, 8)
			b.box("paint:#4a3a2a", Vector3(1.9, 0.14, 0.14), KitMesh.xf(Vector3(0, 7.9, 0)), 0.02)
			for sx2: float in [-0.8, 0.0, 0.8]:
				b.cyl("paint:#e6e1d4", 0.05, 0.16, KitMesh.xf(Vector3(sx2, 7.97, 0)), 0.01, 8)
		"tank":
			b.cyl("paint:#9a9488", 2.6, 4.5, KitMesh.xf(Vector3.ZERO), 0.1, 18)
			b.cyl("paint:#7a756c", 2.7, 0.3, KitMesh.xf(Vector3(0, 4.5, 0)), 0.08, 18)
			b.box("paint:#2c2e31", Vector3(0.1, 4.6, 0.6), KitMesh.xf(Vector3(2.62, 2.3, 0)), 0.01)
		"fence":
			for sx3: float in [-3.0, 0.0, 3.0]:
				b.cyl("paint:#6d6f72", 0.04, 1.9, KitMesh.xf(Vector3(sx3, 0, 0)), 0.005, 6)
			b.box("paint:#6d6f72", Vector3(6.0, 0.04, 0.04), KitMesh.xf(Vector3(0, 1.85, 0)), 0.005)
			b.box("paint:#8a8c8e", Vector3(6.0, 1.7, 0.02), KitMesh.xf(Vector3(0, 0.95, 0)), 0.002)
		"shed":  # [v5look] a garden shed: plank walls, a door, a low pitched sheet roof
			b.box("paint:#7a6248", Vector3(2.6, 2.0, 2.1), KitMesh.xf(Vector3(0, 1.0, 0)), 0.03)
			b.box("paint:#4a3a2c", Vector3(0.85, 1.7, 0.06), KitMesh.xf(Vector3(-0.45, 0.87, 1.06)), 0.01)
			b.box("glass", Vector3(0.6, 0.5, 0.05), KitMesh.xf(Vector3(0.7, 1.35, 1.06)), 0.01)
			for sgn: float in [-1.0, 1.0]:
				b.box("paint:#4f565c", Vector3(3.0, 0.07, 1.42), KitMesh.xf(Vector3(0, 2.26, sgn * 0.62), Vector3(sgn * 24.0, 0, 0)), 0.01)
			b.box("paint:#7a6248", Vector3(2.5, 0.5, 1.2), KitMesh.xf(Vector3(0, 2.1, 0)), 0.02)
			b.box("paint:#7a6248", Vector3(2.6, 0.7, 2.1), KitMesh.xf(Vector3(0, -0.3, 0)), 0.02)
		"picket":  # [v5look] a low garden fence, 6 m: posts, two rails, boards (some missing)
			for px: float in [-2.9, -1.0, 1.0, 2.9]:
				b.box("paint:#b9ad94", Vector3(0.12, 1.8, 0.12), KitMesh.xf(Vector3(px, 0.25, 0)), 0.01)
			for ry: float in [0.4, 0.85]:
				b.box("paint:#b9ad94", Vector3(5.9, 0.07, 0.05), KitMesh.xf(Vector3(0, ry, 0)), 0.005)
			for k: int in 20:
				if k in [6, 13, 14]:
					continue
				b.box("paint:#cfc4aa", Vector3(0.16, 0.95 + 0.05 * float(k % 3), 0.03), KitMesh.xf(Vector3(-2.85 + 0.3 * k, 0.6, 0.04), Vector3(0, 0, 4.0 if k == 9 else 0.0)), 0.004)
	var mi := KitMesh.instance(b, "broken", false)
	var m: ArrayMesh = mi.mesh
	for s: int in m.get_surface_count():  # bake the kit materials into the mesh (MultiMesh has no per-surface overrides)
		m.surface_set_material(s, mi.get_surface_override_material(s))
	mi.free()
	return m


# --- Deciding hexes -------------------------------------------------------------------------

func _hash01(c: int, salt: int) -> float:
	return float(hash([seed_value, c, salt]) & 0xFFFFFF) / float(0xFFFFFF)


func _hub_m(dir: Vector3) -> float:
	var best: float = INF
	for h: Vector3 in hub_dirs:
		best = minf(best, h.angle_to(dir) * terrain.R)
	return best


## Whether hex c out-rolls every hex within `rings` rings of it.
func _local_max(c: int, rings: int, salt: int) -> bool:
	var v: float = _hash01(c, salt)
	var front: PackedInt32Array = PackedInt32Array([c])
	var seen: Dictionary = {c: true}
	for r: int in rings:
		var nxt := PackedInt32Array()
		for q: int in front:
			for o: int in grid.neighbors(q):
				if seen.has(o):
					continue
				seen[o] = true
				if _hash01(o, salt) >= v:
					return false
				nxt.append(o)
		front = nxt
	return true


## [v5play] No wedge spots: a hex's building or prop is dropped when it would stand closer than
## MIN_GAP_M to a neighbouring hex's bigger one (footprint area; a tie goes to the lower hex id).
## The big works (18 x 15 m on hexes ~17 m apart) used to leave gaps down to 0.5 m beside a house,
## or overlap it: Lumi (1.1 m wide) and the robots wedged there.
const MIN_GAP_M: float = 2.2
var _cand: Dictionary = {}  # cell -> its own choice, before the neighbours are looked at


func _candidate(c: int) -> Array:
	var v: Variant = _cand.get(c)
	if v == null:
		v = _decide_alone(c)
		_cand[c] = v
	return v


## [v5look] Tracks: the hexes on the inner edge of the track noise's positive region. Such an
## edge is a continuous chain of hexes, so the tracks wind on without gaps (and end at the water,
## at a hub's own streets, or close into a loop).
func _tn(c: int) -> float:
	var v: Variant = _track_n.get(c)
	if v == null:
		v = _track.get_noise_3dv(grid.centers[c] * terrain.R)
		_track_n[c] = v
	return v


## For the junk field (SphereField.pile_block): no mounds on a road hex.
func is_track_cell(c: int) -> bool:
	return grid != null and _is_track(c)


func _is_track(c: int) -> bool:
	var v: Variant = _track_is.get(c)
	if v != null:
		return v
	var res: bool = false
	if _tn(c) >= 0.0 and cells.state[c] != 5 and not cells.has_flag(c, SphereCells.F_SITE) and _hub_m(grid.centers[c]) >= HUB_CLEAR_M:
		for o: int in grid.neighbors(c):
			if _tn(o) < 0.0:
				res = true
				break
	_track_is[c] = res
	return res


## The half-links of track hex c: toward each track neighbour, two strips from its centre to the
## middle of the shared edge. They lie on the ground mesh itself (planet/sphere/sphere_chunk_job.gd,
## full LOD: centre, centre-corner midpoints, corners and edge midpoints): centre -> the middle of
## the two centre-corner points -> the edge midpoint, tilted like the triangles under them, so the
## road neither floats nor sinks. Links 60 or 120 degrees apart sit on slightly different levels
## (no z-fighting where they overlap at the centre); both halves of a link share a level.
func _track_links(c: int, out: Array) -> void:
	var dir: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(dir)
	var k: int = grid.nbr_count[c]
	var b6: int = c * SphereGrid.MAX_N
	var ha: float = terrain.height(dir)
	for j: int in k:
		var o: int = grid.nbr[b6 + j]
		if not _is_track(o):
			continue
		var ci: Vector3 = grid.tri_center[grid.cell_tri[b6 + (j + k - 1) % k]]
		var cj: Vector3 = grid.tri_center[grid.cell_tri[b6 + j]]
		var ed: Vector3 = (ci + cj).normalized()
		var he: float = terrain.height(ed)
		if absf(he - ha) > 2.5 or absf(terrain.height(grid.centers[o]) - ha) > 5.0:
			continue  # too steep for a road
		var t: Vector3 = grid.centers[o] - dir
		var lvl: int = posmod(int(floor(atan2(t.dot(f.z), t.dot(f.x)) / (PI / 3.0) + 0.5)), 3)
		var lift: Vector3 = dir * (0.06 + 0.012 * lvl)
		var s0d: Vector3 = (dir + ci).normalized()
		var s1d: Vector3 = (dir + cj).normalized()
		var s0: Vector3 = s0d * (terrain.R + terrain.height(s0d))
		var s1: Vector3 = s1d * (terrain.R + terrain.height(s1d))
		var a: Vector3 = dir * (terrain.R + ha) + lift
		var q: Vector3 = (s0 + s1) * 0.5 + lift
		var e: Vector3 = ed * (terrain.R + he) + lift
		a -= (q - a).normalized() * 1.3  # past the centre: fills the outer corner of a bend
		var pts: Array[Vector3] = [a, q, e]
		for n: int in 2:
			var along: Vector3 = pts[n + 1] - pts[n]
			var len_m: float = along.length()
			along /= len_m
			var x: Vector3 = s1 - s0
			x = (x - along * x.dot(along)).normalized()
			var y: Vector3 = along.cross(x)
			if y.dot(dir) < 0.0:
				x = -x
				y = -y
			out.append([K_TRACK, Transform3D(Basis(x, y, along * len_m), pts[n]), Vector2(TRACK_W, len_m), 0])


## A prop beside a building: (lx, lz) metres in the building's frame, on the ground there.
func _beside(b: Basis, d2: Vector3, lx: float, lz: float, yaw: float, sink: float = 0.0) -> Transform3D:
	var dn: Vector3 = (d2 + (b.x * lx + b.z * lz) / terrain.R).normalized()
	return Transform3D(b * Basis(Vector3.UP, yaw), dn * (terrain.R + terrain.height(dn) - sink))


func _decide(c: int) -> Array:
	var mine: Array = _candidate(c)
	var solid: Array = mine.filter(func(e: Array) -> bool: return int(e[0]) != K_TRACK)
	if solid.is_empty():
		return mine
	var area: float = (solid[0][2] as Vector2).x * (solid[0][2] as Vector2).y
	for o: int in grid.neighbors(c):
		var theirs: Array = _candidate(o).filter(func(e: Array) -> bool: return int(e[0]) != K_TRACK)
		if theirs.is_empty():
			continue
		var t_area: float = (theirs[0][2] as Vector2).x * (theirs[0][2] as Vector2).y
		if t_area < area or (t_area == area and o > c):
			continue  # the neighbour is the one that yields
		for e: Array in solid:
			for t: Array in theirs:
				if rect_gap(e[1], e[2], t[1], t[2]) < MIN_GAP_M:
					return mine.filter(func(x: Array) -> bool: return int(x[0]) == K_TRACK)  # the road stays
	return mine


## Gap in metres between two footprints (Transform3D on the ground, size x by z), 0 when they
## overlap: edge points of each against the other's box.
static func rect_gap(a_xf: Transform3D, a_size: Vector2, b_xf: Transform3D, b_size: Vector2) -> float:
	var best: float = INF
	for pair: Array in [[a_xf, a_size, b_xf, b_size], [b_xf, b_size, a_xf, a_size]]:
		var pxf: Transform3D = pair[0]
		var hs: Vector2 = (pair[1] as Vector2) * 0.5
		var oxf: Transform3D = pair[2]
		var ohs: Vector2 = (pair[3] as Vector2) * 0.5
		var ox: Vector3 = oxf.basis.x.normalized()
		var oz: Vector3 = oxf.basis.z.normalized()
		for k: int in 44:
			var t: float = float(k % 11) / 10.0 * 2.0 - 1.0
			var lp: Vector2 = [Vector2(t * hs.x, -hs.y), Vector2(t * hs.x, hs.y), Vector2(-hs.x, t * hs.y), Vector2(hs.x, t * hs.y)][int(k / 11.0)]
			var w: Vector3 = pxf.origin + pxf.basis.x.normalized() * lp.x + pxf.basis.z.normalized() * lp.y - oxf.origin
			var ex := Vector2(maxf(absf(w.dot(ox)) - ohs.x, 0.0), maxf(absf(w.dot(oz)) - ohs.y, 0.0))
			best = minf(best, ex.length())
	return best


func _decide_alone(c: int) -> Array:
	var out: Array = []
	if cells.state[c] == 5 or cells.has_flag(c, SphereCells.F_SITE):
		return out
	var dir: Vector3 = grid.centers[c]
	var hm: float = _hub_m(dir)
	if hm < HUB_CLEAR_M:
		return out
	if _is_track(c):  # [v5look] the road itself: no building, no prop
		_track_links(c, out)
		return out
	var road: int = -1  # a track hex next door: build along it, facing it
	for o: int in grid.neighbors(c):
		if cells.state[o] == 5:
			return out  # no building on a shore
		if road < 0 and _is_track(o):
			road = o
	var p: Vector3 = dir * terrain.R
	var z: float = _zone.get_noise_3dv(p) + clampf(1.0 - (hm - HUB_CLEAR_M) / 400.0, 0.0, 1.0) * 0.35
	var ind: bool = _zone.get_noise_3dv(p * 1.7 + Vector3(300, 0, 0)) > 0.25
	var zone: int = 0 if z < -0.05 else (2 if ind else 1)
	var roll: float = _hash01(c, 3)
	var kind: int = -99
	if road >= 0:  # [v5look] roadside: more houses, a few even out in the junk fields
		roll -= 0.25
		if zone == 0 and roll < 0.1:
			zone = 1
	if zone == 1 and roll < 0.6:  # hexes are ~17 m apart: a house (<= 12 m) per hex leaves 5+ m gaps
		var r2: float = _hash01(c, 4)
		kind = 0 if r2 < 0.45 else (1 if r2 < 0.8 else (2 if r2 < 0.9 else 3))
		if kind >= 2 and not _local_max(c, 1, 7):
			kind = 0  # the bigger ones only where no neighbour stands close
	elif zone == 2 and roll < 0.8 and _local_max(c, 1, 8):
		var r3: float = _hash01(c, 5)
		kind = 4 if r3 < 0.45 else (5 if r3 < 0.75 else 3)
	if kind == -99:
		# Props on the open ground: wrecks, poles along the suburbs, tanks by the works, fences.
		var pr: float = _hash01(c, 6)
		if road >= 0 and pr < 0.3:
			kind = -2  # [v5look] a line of poles along the road
		elif zone == 0 and pr < 0.035:
			kind = -1  # car
		elif zone == 1 and pr < 0.07:
			kind = -2 if pr < 0.05 else -1
		elif zone == 2 and pr < 0.1:
			kind = -3 if pr < 0.03 else (-4 if pr < 0.07 else -1)
		else:
			return out
	var f: Basis = SphereGrid.frame(dir)
	var yaw: float = _angle.get_noise_3dv(p) * PI + (PI * 0.5 if _hash01(c, 9) < 0.5 else 0.0)
	yaw += (_hash01(c, 13) - 0.5) * 0.3  # [v5look] nobody built these to a grid
	var off := Vector2(_hash01(c, 10) - 0.5, _hash01(c, 11) - 0.5) * 1.0
	var d2: Vector3 = (dir + (f.x * off.x + f.z * off.y) / terrain.R).normalized()
	var b := Basis(SphereGrid.frame(d2).y, yaw) * SphereGrid.frame(d2)
	if road >= 0:  # [v5look] the front (+Z) looks at the road; a roadside pole stands at its verge
		var up: Vector3 = d2
		var to_road: Vector3 = grid.centers[road] - d2
		to_road = (to_road - up * to_road.dot(up)).normalized()
		if kind == -2:
			d2 = (d2 + to_road * ((grid.centers[road] - dir).length() * 0.5 - (TRACK_W * 0.5 + 0.9) / terrain.R)).normalized()
			up = d2
		var bz: Vector3 = to_road.rotated(up, (_hash01(c, 13) - 0.5) * 0.16)
		bz = (bz - up * bz.dot(up)).normalized()
		b = Basis(up.cross(bz).normalized(), up, bz)
	var size := Vector2(2.0, 4.4)
	if kind >= 0:
		size = Vector2(float(ARCH[kind][1]), float(ARCH[kind][2]))
	elif kind == -3:
		size = Vector2(5.4, 5.4)
	elif kind == -2:
		size = Vector2(0.4, 0.4)
	elif kind == -4:
		size = Vector2(6.0, 0.3)
	# Stand on the lowest of the corners (plinths reach 2.6 m down); skip steep ground.
	var lo: float = INF
	var hi: float = -INF
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2.ZERO]:
		var q: Vector3 = d2 * terrain.R + b.x * s.x * size.x * 0.5 + b.z * s.y * size.y * 0.5
		var hgt: float = terrain.height(q.normalized())
		lo = minf(lo, hgt)
		hi = maxf(hi, hgt)
	if hi - lo > 2.4 and kind >= 0:
		return out
	var base: float = hi if kind >= 0 else (lo + hi) * 0.5
	var xf := Transform3D(b, d2 * (terrain.R + base - (0.05 if kind >= 0 else 0.0)))
	# [v5look] A tint and a height per building (instance colour and scale; colliders stay unscaled).
	var sy: float = 1.0
	var tint: Color = Color.WHITE
	if kind >= 0:
		sy = 0.92 + 0.26 * _hash01(c, 14)
		tint = TINTS[posmod(hash([seed_value, c, 15]), TINTS.size())]
	out.append([kind, xf, size, posmod(hash([seed_value, c, 12]), VARIANTS), Vector3(1, sy, 1), tint])
	if kind >= 0 and kind <= 1 and hi - lo < 1.3:
		_yard(c, b, d2, size, out)
	return out


## [v5look] A house's yard: a shed behind it, a picket fence down one side and along the back,
## sometimes a wreck in the drive on the other side. All within ~7 m of the house's middle, so
## the gaps to the next hex's building stay open.
func _yard(c: int, b: Basis, d2: Vector3, size: Vector2, out: Array) -> void:
	var side: float = -1.0 if _hash01(c, 20) < 0.5 else 1.0
	var hw: float = size.x * 0.5
	var hd: float = size.y * 0.5
	var shed: bool = _hash01(c, 21) < 0.55
	if shed:
		out.append([K_SHED, _beside(b, d2, side * (hw - 1.6), -(hd + 1.7), PI * 0.5 * side, 0.1), Vector2(2.6, 2.1), 0])
	if _hash01(c, 22) < 0.65:
		out.append([K_PICKET, _beside(b, d2, side * (hw + 1.5), -0.6, PI * 0.5, 0.12), Vector2(0.3, 6.0), 0])
	if _hash01(c, 23) < 0.5:
		out.append([K_PICKET, _beside(b, d2, -side * (hw - 2.6) if shed else 0.0, -(hd + 3.0), 0.0, 0.12), Vector2(6.0, 0.3), 0])
	if _hash01(c, 24) < 0.3:
		out.append([-1, _beside(b, d2, -side * (hw + 1.7), 0.8, (_hash01(c, 25) - 0.5) * 0.5), Vector2(2.0, 4.4), 0])


# --- Streaming ------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if focus == null or not is_instance_valid(focus) or not focus.is_inside_tree():
		return
	var pos: Vector3 = focus.global_position
	if _pending_at < _pending.size():
		var t0: int = Time.get_ticks_usec()
		var end: int = mini(_pending.size(), _pending_at + CELLS_PER_FRAME)
		for i: int in range(_pending_at, end):
			var c: int = _pending[i]
			if not _decided.has(c):
				var lst: Array = _decide(c)
				_decided[c] = lst
				stats["cells"] += 1
				_register(c, lst)
			if Time.get_ticks_usec() - t0 > 4000:
				end = i + 1
				break
		_pending_at = end
		stats["decide_ms"] = float(stats.get("decide_ms", 0.0)) + float(Time.get_ticks_usec() - t0) / 1000.0
		stats["frames"] = int(stats.get("frames", 0)) + 1
		if _pending_at >= _pending.size():
			_rebuild(pos)
		return
	if _last_pos == Vector3.INF or pos.distance_to(_last_pos) > REBUILD_M:
		_last_pos = pos
		_pending = grid.cells_within(pos.normalized(), VIEW_M)
		_pending_at = 0
	elif _body_pos == Vector3.INF or pos.distance_to(_body_pos) > 12.0:
		_colliders(pos)


# [v5play] For the walk check (planet/sites/hinter_walk.gd).
func decided_cells() -> Array:
	return _decided.keys()


func decided(c: int) -> Array:
	return _decided.get(c, [])


## Every hex in view of the focus is decided and drawn.
func is_settled() -> bool:
	return _last_pos != Vector3.INF and _pending_at >= _pending.size() and focus != null and focus.global_position.distance_to(_last_pos) <= REBUILD_M


func refresh_colliders(pos: Vector3) -> void:
	_colliders(pos)


func _register(c: int, lst: Array) -> void:
	if keep_out == null or lst.is_empty():
		return
	var items: Array = []
	var lanes: Array = []
	for e: Array in lst:
		var sz: Vector2 = e[2]
		if int(e[0]) == -2:
			continue
		var xf: Transform3D = e[1]
		if int(e[0]) == K_TRACK:  # [v5look] the lane stays clear of junk (a path to follow); the verges do not
			lanes.append([Transform3D(xf.basis.orthonormalized(), xf.origin), Rect2(-0.7, 0.0, 1.4, sz.y)])
			continue
		if int(e[0]) == K_PICKET and sz.x < sz.y:  # the side fence: its mesh runs along X, yawed 90 degrees
			sz = Vector2(sz.y, sz.x)
		items.append([Transform3D(xf.basis, xf.origin), Rect2(-sz * 0.5, sz)])
	if not items.is_empty():
		keep_out.add_world("hinter%d" % c, items)
	if not lanes.is_empty():
		keep_out.add_world("lane%d" % c, lanes, true)


func _rebuild(pos: Vector3) -> void:
	var t0: int = Time.get_ticks_msec()
	var near_l: Array = []
	var far_l: Array = []
	var prop_l: Array = []
	var n_t: int = 0
	for i: int in ARCH.size() * VARIANTS:
		near_l.append([])
		far_l.append([])
	for i2: int in PROPS.size():
		prop_l.append([])
	var vis2: float = (VIEW_M + 20.0) * (VIEW_M + 20.0)
	var n_b: int = 0
	var n_p: int = 0
	for c: int in _pending:
		var lst: Variant = _decided.get(c)
		if lst == null:
			continue
		for e: Array in lst:
			var xf: Transform3D = e[1]
			var d2: float = xf.origin.distance_squared_to(pos)
			if d2 > vis2:
				continue
			var k: int = e[0]
			if k >= 0:
				var kv: int = k * VARIANTS + int(e[3]) if e.size() > 3 else k * VARIANTS
				if e.size() > 5:  # [v5look] height and tint
					xf = Transform3D(xf.basis.scaled_local(e[4]), xf.origin)
				((near_l[kv] if d2 < NEAR_M * NEAR_M else far_l[kv]) as Array).append([xf, e[5] if e.size() > 5 else Color.WHITE])
				n_b += 1
			elif k == K_TRACK:
				(prop_l[-k - 1] as Array).append(xf)
				n_t += 1
			elif d2 < 320.0 * 320.0:
				(prop_l[-k - 1] as Array).append(xf)
				n_p += 1
	for i3: int in ARCH.size() * VARIANTS:
		_fill(_mm_near[i3], near_l[i3])
		_fill(_mm_far[i3], far_l[i3])
	for i4: int in PROPS.size():
		_fill(_mm_props[i4], prop_l[i4])
	stats["buildings"] = n_b
	stats["props"] = n_p
	stats["tracks"] = n_t
	stats["rebuilds"] += 1
	stats["last_ms"] = Time.get_ticks_msec() - t0
	_colliders(pos)
	rebuilt.emit()


func _fill(mi: MultiMeshInstance3D, xfs: Array) -> void:
	var mm: MultiMesh = mi.multimesh
	mm.instance_count = xfs.size()
	for i: int in xfs.size():
		if mm.use_colors:
			mm.set_instance_transform(i, xfs[i][0])
			mm.set_instance_color(i, xfs[i][1])
		else:
			mm.set_instance_transform(i, xfs[i])


## Box colliders for the buildings, tanks and cars near Lumi (one body, shapes reused).
func _colliders(pos: Vector3) -> void:
	_body_pos = pos
	for ch: Node in _body.get_children():
		ch.free()
	var lim2: float = COLLIDE_M * COLLIDE_M
	for c: int in grid.cells_within(pos.normalized(), COLLIDE_M + 20.0):
		var lst: Variant = _decided.get(c)
		if lst == null:
			continue
		for e: Array in lst:
			var xf: Transform3D = e[1]
			if xf.origin.distance_squared_to(pos) > lim2:
				continue
			var k: int = e[0]
			if k == K_TRACK:
				continue
			var sz: Vector2 = e[2]
			if k == K_PICKET and sz.x < sz.y:
				sz = Vector2(sz.y, sz.x)
			var h: float = 4.6 if k == -3 else (1.6 if k == -1 else (8.5 if k == -2 else (1.9 if k == -4 else (2.5 if k == K_SHED else (1.05 if k == K_PICKET else float(ARCH[k][3]) * 3.0 * (float((e[4] as Vector3).y) if e.size() > 4 else 1.0) + (4.0 if k <= 1 or k == 3 else 1.0))))))
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(sz.x, h + 2.6, sz.y)
			cs.shape = box
			cs.transform = xf * Transform3D(Basis(), Vector3(0, h * 0.5 - 1.3, 0))
			_body.add_child(cs)


## [v5look] Dev (--hinter-report): where the nearest house and track hex are, as --orbit-spawn
## metres from `from_cell`, to stand a render next to them.
func debug_nearest(from_cell: int) -> String:
	var up: Vector3 = grid.centers[from_cell]
	var f: Basis = SphereGrid.frame(up)
	var best: Dictionary = {}
	for c: int in _decided:
		for e: Array in _decided[c]:
			var k: int = e[0]
			var nm: String = "house" if k in [0, 1] else ("track" if k == K_TRACK else ("works" if k >= 3 else ""))
			if nm == "":
				continue
			var p: Vector3 = (e[1] as Transform3D).origin
			var d: float = p.distance_to(up * terrain.R)
			if not best.has(nm) or d < float(best[nm][0]):
				best[nm] = [d, "%d,%d" % [int(p.dot(f.x)), int(p.dot(f.z))]]
	var mmc: Array = []
	for mi: MultiMeshInstance3D in _mm_props:
		mmc.append("%s=%d vis=%s aabb=%s" % [mi.name, mi.multimesh.instance_count, mi.is_visible_in_tree(), str(mi.multimesh.get_aabb().size)])
	return str(best) + " " + str(mmc) + " focus=" + str(focus.global_position.length() - terrain.R)


## [v5look] Dev (--hinter-goto=track|house|works[,back_m]): a spot to stand and a way to look, at
## the nearest such thing to `from`: on a track looking along it, or in front of a building.
func dev_spot(what: String, from: Vector3, back_m: float, side_m: float = 0.0) -> Array:
	var best: Array = []
	var bd: float = INF
	for c: int in _decided:
		for e: Array in _decided[c]:
			var k: int = e[0]
			if (what == "track" and k != K_TRACK) or (what == "house" and not k in [0, 1]) or (what == "works" and k < 3):
				continue
			var xf: Transform3D = e[1]
			var d: float = xf.origin.distance_to(from)
			if d < bd and (k != K_TRACK or d > 45.0):
				bd = d
				var z: Vector3 = xf.basis.z.normalized()
				var at: Vector3 = xf.origin + z * back_m + xf.basis.x.normalized() * side_m
				best = [at, z if k == K_TRACK else (xf.origin - at).normalized()]
	return best
