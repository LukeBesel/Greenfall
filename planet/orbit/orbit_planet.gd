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
const HUB_SITE_M: float = 82.0  # [orbD] a ruin_block site prefab is 108 m square (corners at 76 m)
const VERDANCE_HUB_SITE_M: float = 120.0  # [v3city] Verdance's hub towns (VerdanceSite.HUB_TOWN_R + a margin)
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
var site_manager: SiteManager  # [orbD] every hub's site prefab (planet/sites/)
var planet_id: String = "verdance"  # [orbD] which planet's site prefabs
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
	stats["grid_load_ms"] = Time.get_ticks_msec() - t0  # [orbE]
	var lv: int = SphereGrid.level_of_freq(f)
	# The survey runs on the same cells: level grids keep their GeoSphere, others share this grid.
	planet = PlanetData.new(seed_value, lv, GlobeSpec.HEX_M) if lv >= 0 else PlanetData.new(seed_value, 0, GlobeSpec.HEX_M, GeoSphere.from_grid(grid))
	terrain = SphereTerrain.new(grid, seed_value)
	# [orbE] The survey and the terrain's elevation are pure data: behind the loading screen they run
	# on a worker thread while the bar keeps moving (Anvil: 2-4 s that froze the first frame).
	var survey := func() -> void:
		planet.generate()
		if not planet_state.is_empty():
			planet.apply_dict(planet_state)
		# The survey's elevation lifts the macro terrain: lakes sit low, hills read from Command view.
		var sorted_e: PackedFloat32Array = planet.elevation.duplicate()
		sorted_e.sort()
		terrain.set_cell_elevation(planet.elevation, 14.0, sorted_e[int(sorted_e.size() * 0.25)])
	if BuildBudget.active():
		await BuildBudget.join(BuildBudget.add_task(survey, "globe survey"))
	else:
		survey.call()
	stats["planet_ms"] = Time.get_ticks_msec() - t0
	await BuildBudget.check("globe survey")
	var t1: int = Time.get_ticks_msec()
	# [orbE] The cells without from_planet's texture pass: refresh_all below writes it once.
	cells = SphereCells.new(planet.cell_count())
	cells.junk = planet.junk.duplicate()
	cells.state = planet.state.duplicate()
	cells.biome = planet.biome.duplicate()
	stats["grid_ms"] = Time.get_ticks_msec() - t1
	var tq: int = Time.get_ticks_msec()  # [orbE] load-time breakdown (docs/PERFORMANCE.md)
	_place_hubs(n_hubs if n_hubs > 0 else int(spec.get("hub_count", 10)), cells_state.is_empty(), site_cells)
	if not cells_state.is_empty() and not cells.apply_dict(cells_state):
		push_warning("[orbit] saved cells didn't match this planet; starting its state fresh.")
		_clear_sites()
	if before_field.is_valid():
		before_field.call(self)
	stats["hubs_ms"] = Time.get_ticks_msec() - tq
	await BuildBudget.check("globe hubs")  # [orbE]
	tq = Time.get_ticks_msec()
	cells.refresh_all()
	stats["refresh_ms"] = Time.get_ticks_msec() - tq
	await BuildBudget.check("globe cells")  # [orbE]
	tq = Time.get_ticks_msec()
	field = SphereField.new(grid, terrain, cells, seed_value)
	var ko: YardKeepOut = yard_keep_out()  # [v1yard] junk right up to the pad's edge, small pieces near the start
	if ko:
		field.keep_out = ko.blocks
		var c0: int = start_cell()
		for c: int in grid.cells_within(grid.centers[c0], YardKeepOut.SMALL_ONLY_M, c0):
			field.small_only[c] = true
	stats["field_ms"] = Time.get_ticks_msec() - tq
	await BuildBudget.check("globe field")  # [orbE]
	surface = SphereSurface.new(grid.radius_m)
	surface.height_fn = terrain.height
	surface.cell_fn = func(p: Vector3, _hint: int) -> int: return grid.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return grid.centers[c]
	swarm = SphereSwarm.new(surface)
	streamer = SphereStreamer.new()
	streamer.name = "Streamer"
	streamer.shell_city = planet.city
	add_child(streamer)
	OrbitQuality.apply_streamer(streamer, Settings.quality, grid.radius_m)  # [orbE] per-preset budgets
	tq = Time.get_ticks_msec()
	streamer.setup(grid, terrain, cells)
	stats["streamer_setup_ms"] = Time.get_ticks_msec() - tq
	await BuildBudget.check("globe shell")  # [orbE]
	tq = Time.get_ticks_msec()
	streamer.near_changed.connect(_on_near_changed)
	junk_view = SphereJunkView.new()
	junk_view.name = "Junk"
	junk_view.setup(field)
	add_child(junk_view)
	_build_gravity()
	stats["junkview_ms"] = Time.get_ticks_msec() - tq
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
		var r: float = START_SITE_M if i == 0 else (VERDANCE_HUB_SITE_M if str(spec.get("id", "verdance")) == "verdance" else HUB_SITE_M)
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
	var ko: YardKeepOut = yard_keep_out() if i == 0 else null  # [v1yard] only the pad's own cells go clean
	for c: int in s["cells"]:
		cells.set_flag(c, SphereCells.F_SITE)
		if ko:
			if ko.cell_inside(grid, c):
				cells.state[c] = 1
				cells.junk[c] = 0.0
				cells.flags[c] |= SphereCells.F_HUB
			continue
		if grid.distance_m(c, hub_cell) < (60.0 if i > 0 else 22.0):
			cells.state[c] = 1
			cells.junk[c] = 0.0
			cells.flags[c] |= SphereCells.F_HUB


func _clear_sites() -> void:
	cells = SphereCells.from_planet(planet)
	for s: Dictionary in sites:
		_clear_site(s, int(s["cell"]), int(s["index"]))


## [v1yard] The start yard's per-piece keep-out (the pad, the pod; SiteManager adds the building
## footprints), or null off Verdance (other planets' start prefabs keep the 22 m clear core).
func yard_keep_out() -> YardKeepOut:
	if _keep_out == null and not sites.is_empty() and str(spec.get("id", "verdance")) == "verdance":
		_keep_out = YardKeepOut.for_site(sites[0], terrain)
	return _keep_out


var _keep_out: YardKeepOut


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
	# [orbD] The real hub sites: SiteManager builds the start yard prefab now (in this frame, so
	# its anchors are ready for the depot) and the other hubs as Lumi comes near.
	site_manager = SiteManager.new()
	site_manager.name = "Sites"
	add_child(site_manager)
	planet_id = str(spec.get("id", planet_id))  # [orbD] --orbit-planet: that planet's site prefabs
	site_manager.setup(self, planet_id, sites, seed_value)
	# [orbE] Behind the loading screen the yard builds across frames like the flat district (it
	# was one 5-7 s frame); without a budget it builds at once, as before.
	var p: SitePrefab = site_manager.build_hub(0, not BuildBudget.active())
	if not p.is_built:
		await p.rebuilt
	start_site = p.get_parent()
	start_site.name = "StartSite"
	SiteManager.point_shaders_at(p)
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
	# [v1world] The globe lays the flat world's density (SphereField.DRAW_PIECES), so a ring move
	# while walking materializes only the cells close to a tracked body now; the outer ring's cells
	# follow over the next frames under a time budget (they are 35-70 m out, past the scoop's reach).
	var t0: int = Time.get_ticks_usec()
	var soon: Array[Vector3] = []
	if _live:
		for k: String in trackers:
			var b: Node3D = trackers[k]
			if is_instance_valid(b) and b.is_inside_tree():
				soon.append(b.global_position)
	for c: int in added:
		if field.materialized[c] == 1:
			continue
		var now: bool = not _live
		for p: Vector3 in soon:
			if grid.great_circle_m(p, grid.centers[c]) < FILL_NOW_M:
				now = true
				break
		if now:
			field.materialize(c)
		elif not _fill_set.has(c):
			_fill_set[c] = true
			_fill_q.append(c)
	_junk_dirty = true
	if _live and not added.is_empty():
		stats["near_fill_max_ms"] = maxf(float(stats.get("near_fill_max_ms", 0.0)), (Time.get_ticks_usec() - t0) / 1000.0)


const FILL_NOW_M: float = 36.0  # [v1world]
const FILL_BUDGET_US: int = 3000  # [v1world] deferred materializing per frame
var _live: bool = false  # [v1world] the world is running (the build materializes at once)
var _fill_q: Array[int] = []
var _fill_set: Dictionary = {}


## [v1world] Materializes queued near cells under a per-frame time budget (all of them: flush).
func _drain_fill(flush: bool) -> void:
	var t0: int = Time.get_ticks_usec()
	var did: bool = false
	while not _fill_q.is_empty():
		var c: int = _fill_q.pop_front()
		_fill_set.erase(c)
		if field.materialized[c] == 0 and streamer.is_near(c):
			field.materialize(c)
			did = true
		if not flush and Time.get_ticks_usec() - t0 > FILL_BUDGET_US:
			break
	if did:
		_junk_dirty = true
		stats["near_fill_max_ms"] = maxf(float(stats.get("near_fill_max_ms", 0.0)), (Time.get_ticks_usec() - t0) / 1000.0)


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
	_live = true  # [v1world]
	update_centres()
	if not _fill_q.is_empty():  # [v1world]
		_drain_fill(false)
	if _junk_dirty:
		_junk_dirty = false
		junk_view.rebuild(streamer.near_cells())
		stats["junk"] = int(junk_view.stats.get("pieces", 0))
		stats["junk_ms"] = int(float(junk_view.stats.get("rebuild_us", 0)) / 1000.0)


## Draw the near ring's junk right now (after loading: no pop-in over the first frames).
func refresh_junk_now() -> void:
	update_centres()
	_drain_fill(true)  # [v1world]
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
