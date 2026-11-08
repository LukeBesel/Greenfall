class_name OrbitPlanet
extends Node3D
## [orbB] Phase B: one planet as a walkable globe, the world the slice builds on under --orbit
## (scenes/slice_orbit.gd). The globe core of phase A's VerdanceGlobe as a reusable node:
## survey data (PlanetData level 7, 163,842 cells), SphereGrid + SphereTerrain, per-cell state
## (SphereCells), the streamer, the walk surface, scoopable junk (SphereField + SphereJunkView),
## hub sites and radial gravity. No player, camera or HUD: the slice owns those.
## Cell ids are the survey ids everywhere (hologram, maps, saves).
##
## Split for the phase B-E helpers:
## - OrbitDay  (planet/orbit/orbit_day.gd): sky, suns, real day/night sides (orbE).
## - OrbitCrews (planet/orbit/orbit_crews.gd): the SphereBot graph and far crews (orbC).
## - Sites: _place_hubs / build_start_site here until PlanetEnvs.build_site lands (orbD).

const WATER: int = 5
const START_SITE_M: float = 140.0  # start pad radius (the yard and its blocks)
const HUB_SITE_M: float = 45.0
const SITE_BLEND_M: float = 40.0

var seed_value: int = 4471
var spec: Dictionary = GlobeSpec.DEFAULT  # GlobeSpec.of(planet id): frequency, hub_count, radius
var planet: PlanetData
var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var streamer: SphereStreamer
var surface: SphereSurface
var swarm: SphereSwarm
var field: SphereField
var junk_view: SphereJunkView
var hubs: Array[int] = []
var sites: Array[Dictionary] = []
var start_site: Node3D
var stats: Dictionary = {}
## Bodies the streamer keeps 3D around (key -> Node3D); "view" is the camera.
var trackers: Dictionary = {}
var view_camera: Callable  # -> Vector3: where the camera is (for the "view" centre)
var _junk_dirty: bool = true


## Builds the globe of `p_spec` (GlobeSpec.of: frequency, hub_count). planet_state /
## cells_state are saved dicts (empty for a new game). n_hubs < 0: the spec's hub count.
## site_cells: a save's pads, in order (empty: pick them from the survey). before_field: called
## once the cells and sites exist, before the field reads them (old-save migration).
func build(p_seed: int, p_spec: Dictionary = GlobeSpec.DEFAULT, n_hubs: int = -1, planet_state: Dictionary = {}, cells_state: Dictionary = {}, site_cells := PackedInt32Array(), before_field := Callable()) -> void:
	seed_value = p_seed
	spec = p_spec
	var f: int = int(spec.get("frequency", GlobeSpec.VERDANCE_FREQ))
	var t0: int = Time.get_ticks_msec()
	grid = SphereGrid.for_freq(f, GlobeSpec.HEX_M)
	var lv: int = SphereGrid.level_of_freq(f)
	# The survey runs on the same cells: level grids keep their GeoSphere, others share this grid.
	planet = PlanetData.new(seed_value, lv, GlobeSpec.HEX_M) if lv >= 0 else PlanetData.new(seed_value, 0, GlobeSpec.HEX_M, GeoSphere.from_grid(grid))
	planet.generate()
	if not planet_state.is_empty():
		planet.apply_dict(planet_state)
	stats["planet_ms"] = Time.get_ticks_msec() - t0
	var t1: int = Time.get_ticks_msec()
	terrain = SphereTerrain.new(grid, seed_value)
	# The survey's elevation lifts the macro terrain: lakes sit low, hills read from Command view.
	var sorted_e: PackedFloat32Array = planet.elevation.duplicate()
	sorted_e.sort()
	terrain.set_cell_elevation(planet.elevation, 14.0, sorted_e[int(sorted_e.size() * 0.25)])
	cells = SphereCells.from_planet(planet)
	stats["grid_ms"] = Time.get_ticks_msec() - t1
	_place_hubs(n_hubs if n_hubs > 0 else int(spec.get("hub_count", 10)), cells_state.is_empty(), site_cells)
	if not cells_state.is_empty() and not cells.apply_dict(cells_state):
		push_warning("[orbit] saved cells didn't match this planet; starting its state fresh.")
		_clear_sites()
	if before_field.is_valid():
		before_field.call(self)
	cells.refresh_all()
	field = SphereField.new(grid, terrain, cells, seed_value)
	surface = SphereSurface.new(grid.radius_m)
	surface.height_fn = terrain.height
	surface.cell_fn = func(p: Vector3, _hint: int) -> int: return grid.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return grid.centers[c]
	swarm = SphereSwarm.new(surface)
	streamer = SphereStreamer.new()
	streamer.name = "Streamer"
	streamer.shell_city = planet.city
	add_child(streamer)
	streamer.setup(grid, terrain, cells)
	streamer.near_changed.connect(_on_near_changed)
	junk_view = SphereJunkView.new()
	junk_view.name = "Junk"
	junk_view.setup(field)
	add_child(junk_view)
	_build_gravity()
	stats["build_ms"] = Time.get_ticks_msec() - t0


# --- Hubs and sites -----------------------------------------------------------------------

## Farthest-point subset of the survey's hub candidates, starting at the Junkyard Hub, each
## reserved as a level pad. fresh: clear the yard (the only clean ground at the start).
func _place_hubs(n: int, fresh: bool, saved := PackedInt32Array()) -> void:
	var picks: Array[int] = [planet.hubs[0]]
	if not saved.is_empty() and saved[0] >= 0 and saved[saved.size() - 1] < grid.cell_count():
		picks.assign(Array(saved))  # [orbB] the save's pads, whatever the hub picking does now
	while picks.size() < mini(n, planet.hubs.size()) and saved.is_empty():
		var best: int = -1
		var best_d: float = -1.0
		for h: int in planet.hubs:
			var d: float = INF
			for k: int in picks:
				d = minf(d, grid.centers[h].angle_to(grid.centers[k]))
			if d > best_d:
				best_d = d
				best = h
		picks.append(best)
	var blocked := func(c: int) -> bool: return cells.state[c] == WATER
	for i: int in picks.size():
		var r: float = START_SITE_M if i == 0 else HUB_SITE_M
		var s: Dictionary = terrain.reserve_site(picks[i], r, SITE_BLEND_M, blocked)
		if s.is_empty():
			s = terrain.reserve_site(picks[i], r, SITE_BLEND_M)  # coast: allow it
		if s.is_empty():
			continue
		s["index"] = i
		sites.append(s)
		hubs.append(picks[i])
		if fresh:
			_clear_site(s, picks[i], i)


func _clear_site(s: Dictionary, hub_cell: int, i: int) -> void:
	for c: int in s["cells"]:
		cells.set_flag(c, SphereCells.F_SITE)
		if grid.distance_m(c, hub_cell) < (60.0 if i > 0 else 22.0):
			cells.state[c] = 1
			cells.junk[c] = 0.0
			cells.flags[c] |= SphereCells.F_HUB


func _clear_sites() -> void:
	cells = SphereCells.from_planet(planet)
	for s: Dictionary in sites:
		_clear_site(s, int(s["cell"]), int(s["index"]))


func start_cell() -> int:
	return int(sites[0]["cell"]) if not sites.is_empty() else planet.hubs[0]


## The site index whose pad holds this world point, or -1.
func site_at(p: Vector3) -> int:
	var c: int = grid.cell_at(p)
	for s: Dictionary in sites:
		if (s["cells"] as PackedInt32Array).has(c):
			return int(s["index"])
	return -1


## Stand-in start base in site-local metres on the flat pad (y = 0 is the pad, +y up): the
## contract PlanetEnvs.build_site gets (orbD replaces this with the real yard prefab).
func build_start_site() -> Node3D:
	start_site = Node3D.new()
	start_site.name = "StartSite"
	add_child(start_site)
	start_site.global_transform = sites[0]["transform"]
	var slab_m: StandardMaterial3D = AssetLib.pbr_material("concrete_pavement", 0.2, Color(0.9, 0.9, 0.88), true)
	_box(start_site, Vector3.ZERO, Vector3(16, 0.04, 16), slab_m, false)  # flush with the pad (no collision)
	return start_site


## Site-local point -> world point on the pad of site i.
func site_point(i: int, local: Vector3) -> Vector3:
	return (sites[i]["transform"] as Transform3D) * local


static func _box(root: Node3D, at: Vector3, size: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size + Vector3(0, 0.6, 0)  # 0.6 m below the pad, so the blend never shows a gap
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at + Vector3(0, size.y * 0.5 - 0.3, 0)
	root.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		sb.add_child(cs)
		sb.position = mi.position
		root.add_child(sb)


# --- Cells <-> field ----------------------------------------------------------------------

func _on_near_changed(added: PackedInt32Array, _removed: PackedInt32Array) -> void:
	for c: int in added:
		field.materialize(c)
	_junk_dirty = true


## Redraw the near ring's junk on the next frame (after pieces were added or moved).
func mark_junk_dirty() -> void:
	_junk_dirty = true


## SphereField's ledger -> SphereCells (ground texture, far view) and the survey PlanetData.
func write_cell(hid: int) -> void:
	var left: float = 1.0 - field.removed_fraction(hid)
	cells.set_junk(hid, left if field.hex_clean[hid] == 0 else 0.0)
	planet.set_junk(hid, left)
	if field.hex_clean[hid] == 1:
		planet.mark_clean(hid)


func cell_at(p: Vector3) -> int:
	return grid.cell_at(p)


## A world point as direction + height above the planet's ground there (saves never store x/z).
func to_dirh(p: Vector3) -> Array:
	var d: Vector3 = p.normalized()
	var h: float = p.length() - (grid.radius_m + terrain.height(d))
	return [snappedf(d.x, 0.000001), snappedf(d.y, 0.000001), snappedf(d.z, 0.000001), snappedf(h, 0.001)]


func from_dirh(a: Array) -> Vector3:
	var d := Vector3(float(a[0]), float(a[1]), float(a[2])).normalized()
	return d * (grid.radius_m + terrain.height(d) + float(a[3]))


# --- Gravity ------------------------------------------------------------------------------

## Cubes fall toward the planet's centre: one point-gravity area around the whole globe.
func _build_gravity() -> void:
	JunkCube.planet_radius = grid.radius_m
	var area := Area3D.new()
	area.name = "PlanetGravity"
	area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	area.gravity_point = true
	area.gravity_point_center = Vector3.ZERO
	area.gravity_point_unit_distance = 0.0
	area.gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	area.monitoring = true  # gravity overrides only reach bodies the area detects
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 0xFFFF
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = grid.radius_m + 3000.0
	cs.shape = sh
	area.add_child(cs)
	add_child(area)


func _exit_tree() -> void:
	JunkCube.planet_radius = 0.0


# --- Loop ---------------------------------------------------------------------------------

func track(key: String, body: Node3D) -> void:
	trackers[key] = body


func untrack(key: String) -> void:
	trackers.erase(key)
	if streamer:
		streamer.remove_centre(key)


func update_centres() -> void:
	if view_camera.is_valid():
		streamer.set_centre("view", view_camera.call(), SphereStreamer.VIEW)
	for k: String in trackers.keys():
		var b: Node3D = trackers[k]
		if is_instance_valid(b) and b.is_inside_tree():
			streamer.set_centre(k, b.global_position, SphereStreamer.BODY)


func _process(_delta: float) -> void:
	if streamer == null:
		return
	update_centres()
	if _junk_dirty:
		_junk_dirty = false
		junk_view.rebuild(streamer.near_cells())
		stats["junk"] = int(junk_view.stats.get("pieces", 0))
		stats["junk_ms"] = int(float(junk_view.stats.get("rebuild_us", 0)) / 1000.0)


## Draw the near ring's junk right now (after loading: no pop-in over the first frames).
func refresh_junk_now() -> void:
	update_centres()
	_junk_dirty = false
	junk_view.rebuild(streamer.near_cells())
	junk_view.flush()
	stats["junk"] = int(junk_view.stats.get("pieces", 0))


## Mean and minimum distance from each hub to its nearest other hub (m).
func hub_spacing(min_only: bool) -> float:
	var s: float = 0.0
	var mn: float = INF
	for a: Dictionary in sites:
		var d: float = INF
		for b: Dictionary in sites:
			if a != b:
				d = minf(d, grid.distance_m(int(a["cell"]), int(b["cell"])))
		s += d
		mn = minf(mn, d)
	return mn if min_only else s / maxf(1.0, sites.size())
