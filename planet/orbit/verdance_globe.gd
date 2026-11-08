class_name VerdanceGlobe
extends Node3D
## [orbit] Integrated prototype (--orbit): Verdance as one true-scale walkable planet, built from
## the team's modules. sphere-grid gives SphereGrid, SphereTerrain, SphereCells and
## SphereStreamer; sphere-move gives SphereSurface, SphereWalker, SphereCam and SphereBot.
## orbit adds the survey data, hub sites, the start base as a site prefab, junk, crews and the
## lap/views/perf tooling.
## - Survey data: PlanetData level 7 (163,842 hexes, biomes, water, cities, hub candidates). Its
##   cell ids are the SphereGrid ids, so SphereCells.from_planet carries the state 1:1.
## - Hubs: a spaced subset of PlanetData.hubs, each reserved as a level site pad
##   (SphereTerrain.reserve_site). The start hub's base is a prefab built in site-local metres
##   under the site transform, which is the interface planet env prefabs get.
## - Junk: real junk models in the streamer's 70 m near ring (near_changed), from cached
##   per-cell transforms. Near robots are SphereBots on the hex graph (this node is their graph).
##   Far crews are data only.
## Phase A (owner decisions, docs/DECISIONS.md): the real Lumi (player/patch.gd with SphereMotor)
## scoops real junk (SphereField + SphereJunkView), presses bales that fall with radial gravity,
## stacks and carries them to a real Depot on the start site, with the game HUD and economy.
## Real day and night sides: two suns fixed in space, the planet turns once per DAY_MIN.
## Dev: --orbit-walk[=boost] --orbit-lap-quit, --orbit-view=follow|ground|command|mid,
## --orbit-day=MIN (rotation period, default 24), --orbit-time=0..1 (local time at the start hub,
## 0.5 = noon), --orbit-scoop (autowalk with the scoop held), --orbit-cash (scripted bale test),
## --orbit-presim=MIN, --orbit-trail, --orbit-pieces=N, --orbit-hubs=N, --orbit-nohud.
## The first standalone prototype is still there as --orbit=v1 (planet/orbit/orbit_world.gd).

const LAP_PATH := "res://screenshots/orbit/lap_trail_v2.json"
const JUNK_MODELS: Array[String] = ["old_tyre", "Television_01", "vintage_microwave", "plastic_crate_01", "trashbag",
	"metal_jerrycan", "cardboard_box_01", "plastic_jerrycan", "can_rusted", "bleach_bottle", "rusted_wheel_rim_01", "cement_bag"]
const JUNK_W: Array[float] = [0.6, 0.35, 0.35, 0.8, 1.0, 0.8, 1.0, 0.8, 2.0, 1.4, 0.5, 0.7]
const WATER: int = 5

var planet: PlanetData
var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var streamer: SphereStreamer
var surface: SphereSurface
var swarm: SphereSwarm
var lumi: Patch
var cam: SphereCam
var field: SphereField
var junk_view: SphereJunkView
var depot: Depot
var hud: HUD
var district_name: String = "Verdance"
var day_min: float = 24.0
var day_t: float = 0.5  # planet rotation phase (0..1)
var sun2: DirectionalLight3D
var sky_sun: DirectionalLight3D
var lamp: OmniLight3D
var _cubes_root: Node3D
var _spin_axis := Vector3.UP
var _sun_dir0 := Vector3.ZERO  # first sun, rotation phase 0, planet frame
var sun: DirectionalLight3D
var env: Environment
var hubs: Array[int] = []
var sites: Array[Dictionary] = []
var bots: Array[SphereBot] = []
var crews: Array[Dictionary] = []
var stats: Dictionary = {}
var view_mode: String = "follow"
var view: SphereJunkView  # the FieldView role (Patch calls world.view)

var _orbit_cam: Camera3D
var _junk_dirty: bool = true
var _near_set: Dictionary = {}
var _claimed: Dictionary = {}
var _hud: Label
var _lap_on: bool = false
var _lap_start := Vector3.ZERO
var _lap_min: float = INF
var _lap_done: bool = false
var _lap_t: float = 0.0
var _trail: Array = []
var _trail_d: float = 0.0
var _perf: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _perf_n: int = 0


func _ready() -> void:
	var t0: int = Time.get_ticks_msec()
	var seed_v: int = int(DevHooks.get_f("seed", 4471.0))
	planet = PlanetData.new(seed_v, 7, 10.0)
	planet.generate()
	stats["planet_ms"] = Time.get_ticks_msec() - t0
	var t1: int = Time.get_ticks_msec()
	grid = SphereGrid.for_hex_size(7, 10.0)
	terrain = SphereTerrain.new(grid, seed_v)
	# The survey's elevation lifts the macro terrain: lakes sit low, hills read from Command view.
	var sorted_e: PackedFloat32Array = planet.elevation.duplicate()
	sorted_e.sort()
	terrain.set_cell_elevation(planet.elevation, 14.0, sorted_e[int(sorted_e.size() * 0.25)])
	cells = SphereCells.from_planet(planet)
	stats["grid_ms"] = Time.get_ticks_msec() - t1
	view_mode = DevHooks.get_s("orbit-view", "follow")
	_place_hubs(int(DevHooks.get_f("orbit-hubs", 10.0)))
	crews.clear()
	for i: int in range(1, sites.size()):
		crews.append({"hub": int(sites[i]["cell"]), "rate": 0.25 + 0.05 * (i % 4), "acc": 0.0})
	if DevHooks.has("orbit-presim"):
		var all_crews: Array[Dictionary] = []
		for i: int in sites.size():
			all_crews.append({"hub": int(sites[i]["cell"]), "rate": 0.5 + 0.1 * (i % 4), "acc": 0.0})
		_tick(all_crews, DevHooks.get_f("orbit-presim", 120.0) * 60.0)
	cells.refresh_all()
	field = SphereField.new(grid, terrain, cells, seed_v)
	_build_env()
	surface = SphereSurface.new(grid.radius_m)
	surface.height_fn = terrain.height
	surface.cell_fn = func(p: Vector3, _hint: int) -> int: return grid.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return grid.centers[c]
	swarm = SphereSwarm.new(surface)
	streamer = SphereStreamer.new()
	streamer.name = "Streamer"
	add_child(streamer)
	streamer.setup(grid, terrain, cells)
	streamer.near_changed.connect(_on_near_changed)
	junk_view = SphereJunkView.new()
	junk_view.name = "Junk"
	junk_view.setup(field)
	view = junk_view
	add_child(junk_view)
	_build_gravity()
	_cubes_root = Node3D.new()
	_cubes_root.name = "Cubes"
	add_child(_cubes_root)
	_build_base(sites[0])
	for i: int in sites.size():
		_build_beacon(sites[i], i == 0)
	# Lumi (the real Patch) on the start site, facing north up the main street.
	var hub_cell: int = int(sites[0]["cell"])
	var spawn_dir: Vector3 = terrain.local_to_dir(hub_cell, 0.0, 6.0)
	var north: Vector3 = -SphereGrid.frame(spawn_dir).z
	cam = SphereCam.new()
	cam.name = "SphereCam"
	cam.surface = surface
	lumi = Patch.new()
	lumi.name = "Patch"
	lumi.world = self
	match DevHooks.get_s("orbit-walk", ""):
		"":
			lumi.input = SphereInput.new()
		"boost":
			lumi.input = SphereAutoInput.new(Vector3(0, 0, -1), true)
		_:
			lumi.input = SphereAutoInput.new(Vector3(0, 0, -1), false)
	if DevHooks.has("orbit-scoop") and lumi.input is SphereAutoInput:
		(lumi.input as SphereAutoInput).scoop = true
	lumi.enable_sphere(surface, cam)
	add_child(lumi)
	lumi.place_on_sphere(terrain.ground(spawn_dir), north)
	lumi.detector.field = field
	cam.target = lumi
	add_child(cam)
	cam.reset_frame(north)
	_apply_view()
	cam.snap()
	_build_depot(sites[0])
	_build_lights()
	_spawn_bots(hub_cell, 4)
	_update_centres()
	var t2: int = Time.get_ticks_msec()
	streamer.settle()
	stats["settle_ms"] = Time.get_ticks_msec() - t2
	if DevHooks.has("orbit-walk") and not DevHooks.has("orbit-scoop"):
		_lap_on = true
		_lap_start = lumi.global_position
	if DevHooks.has("orbit-trail"):
		_draw_trail()
	Settings.apply_quality_to_tree(self)
	if not (DevHooks.has("orbit-nohud") or DevHooks.has("no-hud")):
		hud = HUD.new()  # the game's HUD: cubes, bale meter, hex readout, prompts
		hud.patch = lumi
		hud.world = self
		add_child(hud)
	if DevHooks.has("orbit-devhud"):
		var cl := CanvasLayer.new()
		add_child(cl)
		_hud = Label.new()
		_hud.position = Vector2(14, 10)
		_hud.add_theme_font_size_override("font_size", 15)
		_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		cl.add_child(_hud)
	stats["ready_ms"] = Time.get_ticks_msec() - t0
	if DevHooks.has("orbit-cash"):
		_cash_test.call_deferred()
	print("[orbit] integrated: R=%.0fm hexes=%d around=%.1fkm hubs=%d (nearest hub mean %.0fm, min %.0fm) ready=%dms planet=%dms grid=%dms settle=%dms" % [
		grid.radius_m, grid.cell_count(), TAU * grid.radius_m / 1000.0, sites.size(), _hub_spacing(false), _hub_spacing(true),
		stats["ready_ms"], stats["planet_ms"], stats["grid_ms"], stats["settle_ms"]])


func _apply_view() -> void:
	match view_mode:
		"ground":
			cam.distance = 7.5
			cam.pitch = -0.1
		"command":
			cam.view = "command"
			cam.command_height = DevHooks.get_f("orbit-height", 400.0)
		"mid":
			env.fog_enabled = false
			_orbit_cam = Camera3D.new()
			_orbit_cam.fov = 60.0
			_orbit_cam.far = grid.radius_m * 12.0
			_orbit_cam.near = 1.0
			add_child(_orbit_cam)
	if DevHooks.has("orbit-cam"):
		var a: PackedStringArray = DevHooks.get_s("orbit-cam", "6,-0.3").split(",")
		cam.distance = float(a[0])
		if a.size() > 1:
			cam.pitch = float(a[1])


# --- Hubs -------------------------------------------------------------------------------

func _place_hubs(n: int) -> void:
	# Farthest-point subset of the survey's hub candidates, starting at the Junkyard Hub.
	var picks: Array[int] = [planet.hubs[0]]
	while picks.size() < mini(n, planet.hubs.size()):
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
		var s: Dictionary = terrain.reserve_site(picks[i], 140.0 if i == 0 else 45.0, 40.0, blocked)
		if s.is_empty():
			s = terrain.reserve_site(picks[i], 140.0 if i == 0 else 45.0, 40.0)  # coast: allow it
		if s.is_empty():
			continue
		sites.append(s)
		hubs.append(picks[i])
		for c: int in s["cells"]:
			cells.set_flag(c, SphereCells.F_SITE)
			if grid.distance_m(c, picks[i]) < (60.0 if i > 0 else 22.0):
				cells.state[c] = 1
				cells.junk[c] = 0.0


func _hub_spacing(min_only: bool) -> float:
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


func _build_beacon(s: Dictionary, home: bool) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35 if home else 2.0
	cyl.bottom_radius = 0.5 if home else 2.6
	cyl.height = 26.0 if home else 120.0
	cyl.radial_segments = 8
	cyl.rings = 1
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.75, 0.4, 0.55) if home else Color(0.45, 0.95, 1.0, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root := Node3D.new()
	add_child(root)
	root.global_transform = s["transform"]
	root.add_child(mi)
	mi.position = Vector3(9.0, cyl.height * 0.5, -9.0) if home else Vector3(0, cyl.height * 0.5, 0)


## The start base as a site prefab: everything in site-local metres on the flat pad (y = 0 is
## the pad, +y up, x east, z south): the same contract the planet env prefabs get.
func _build_base(s: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "StartSite"
	add_child(root)
	root.global_transform = s["transform"]
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed_value + 17
	var wall: StandardMaterial3D = AssetLib.pbr_material("concrete_wall_008", 0.22, Color(0.85, 0.8, 0.74), true)
	var brick: StandardMaterial3D = AssetLib.pbr_material("red_brick", 0.3, Color(0.8, 0.72, 0.68), true)
	var slab_m: StandardMaterial3D = AssetLib.pbr_material("concrete_pavement", 0.2, Color(0.9, 0.9, 0.88), true)
	_box(root, Vector3(0, 0, 0), Vector3(16, 0.04, 16), slab_m, false)  # flush with the pad (no collision)
	_box(root, Vector3(-4.5, 0, -4.0), Vector3(3.4, 2.4, 2.2), wall, true)
	if AssetLib.has_model("street_lamp_01"):
		for p: Vector2 in [Vector2(4.2, -3.0), Vector2(-7, 7), Vector2(7, 7)]:
			var mi := MeshInstance3D.new()
			mi.mesh = AssetLib.model_mesh("street_lamp_01")
			mi.position = Vector3(p.x, 0, p.y)
			root.add_child(mi)
	const PITCH: float = 36.0
	for bx: int in range(-3, 3):
		for bz: int in range(-3, 3):
			if rng.randf() < 0.25:
				continue
			for k: int in rng.randi_range(1, 3):
				var w: float = rng.randf_range(7.0, 12.0)
				var dpt: float = rng.randf_range(7.0, 11.0)
				var h: float = rng.randf_range(5.0, 19.0) * (0.6 if rng.randf() < 0.4 else 1.0)
				var c := Vector3((bx + 0.5) * PITCH + rng.randf_range(-4.0, 4.0), 0, (bz + 0.5) * PITCH + rng.randf_range(-4.0, 4.0))
				_box(root, c, Vector3(w, h, dpt), wall if rng.randf() < 0.6 else brick, true)


func _box(root: Node3D, at: Vector3, size: Vector3, mat: Material, collide: bool) -> void:
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


# --- Environment ------------------------------------------------------------------------

func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_coefficient = 2.4
	sm.rayleigh_color = Color(0.3, 0.45, 0.85)
	sm.mie_coefficient = 0.006
	sm.mie_eccentricity = 0.82
	sm.mie_color = Color(0.95, 0.85, 0.75)
	sm.turbidity = 6.0
	sm.sun_disk_scale = 1.2
	sm.ground_color = Color(0.36, 0.42, 0.52)
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.62, 0.66)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)


# --- Game world API (what Patch, the HUD and the Depot call) -----------------------------

func _on_near_changed(added: PackedInt32Array, _removed: PackedInt32Array) -> void:
	for c: int in added:
		field.materialize(c)
	_junk_dirty = true


func _rebuild_junk() -> void:
	var near: PackedInt32Array = streamer.near_cells()
	_near_set.clear()
	for c: int in near:
		_near_set[c] = true
	junk_view.rebuild(near)
	stats["junk"] = int(junk_view.stats.get("pieces", 0))
	stats["junk_ms"] = int(junk_view.stats.get("rebuild_us", 0)) / 1000


func collect_piece(pid: int) -> void:
	var hid: int = field.piece_hex[pid]
	var became_clean: bool = field.remove_piece(pid)
	_write_cell(hid)
	junk_view.hide_piece(pid)
	if became_clean:
		_on_hex_clean(hid)


## SphereField's ledger -> SphereCells (ground texture, far view) and the survey PlanetData.
func _write_cell(hid: int) -> void:
	var left: float = 1.0 - field.removed_fraction(hid)
	cells.set_junk(hid, left if field.hex_clean[hid] == 0 else 0.0)
	planet.set_junk(hid, left)
	if field.hex_clean[hid] == 1:
		planet.mark_clean(hid)


func _on_hex_clean(hid: int) -> void:
	cells.set_state(hid, 1)
	var bonus: BigNum = Economy.hex_bonus(field.hex_total[hid])
	GameState.add_currency("cubes", bonus)
	GameState.inc_stat("hexes_cleaned")
	var center: Vector3 = field.hex_center(hid)
	var u: Vector3 = center.normalized()
	Audio.play("chime", 1.0, -3.0)
	Vfx.burst("big_sparkle", center + u * 0.3, Color(1.0, 0.92, 0.55))
	Vfx.float_text(center + u * 1.4, tr("HEX CLEAN!  +%s") % Settings.fmt(bonus), Color(1.0, 0.92, 0.45), 1.5, 2.0)
	EventBus.hex_cleaned.emit(hid, center, bonus)
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	lumi.model.set_happy(1.0)


func salvage_materials(_type_id: String, _vol: float) -> void:
	pass  # hub materials come with the hub (phase D)


func add_cube(cube: JunkCube) -> void:
	_cubes_root.add_child(cube)


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


## The cash-in depot on the start site's pad (site-local metres, like any site prefab).
func _build_depot(s: Dictionary) -> void:
	var root: Node3D = get_node_or_null("StartSite")
	depot = Depot.new()
	depot.name = "Depot"
	depot.world = self
	depot.patch = lumi
	root.add_child(depot)
	depot.position = Vector3(5.5, 0.0, 3.5)
	depot.rotation.y = -PI * 0.5


## Dev: press a bale, carry it to the depot and cash it (headless proof of the loop).
func _cash_test() -> void:
	var before: String = Settings.fmt(GameState.get_currency("cubes"))
	for k: int in 12:
		var pid: int = field.nearest_alive(lumi.global_position)
		if pid >= 0:
			lumi._take_piece(pid)
	await get_tree().create_timer(1.0).timeout
	print("[orbit] cash: pieces=%d near=%d fill=%.2f" % [field.piece_count(), streamer.near_cells().size(), lumi.compartment.fill])
	lumi.start_cube()
	await get_tree().create_timer(2.4).timeout
	var c: JunkCube = lumi.nearest_loose_cube()
	var alt: float = surface.altitude(c.global_position) if c else -99.0
	print("[orbit] cash: bale made=%s alt_above_ground=%.2f carried=%d" % [str(c != null), alt, lumi.carried.size()])
	if c:
		lumi.pick_up(c)
	await get_tree().create_timer(0.6).timeout
	lumi.place_on_sphere(depot.global_position + depot.global_basis.y * 0.5, lumi.forward())
	await get_tree().create_timer(3.0).timeout
	var after: String = Settings.fmt(GameState.get_currency("cubes"))
	print("[orbit] cash: cubes %s -> %s depot_cashed=%d hexes_cleaned=%d %s" % [before, after, depot.cashed, int(GameState.stats.get("hexes_cleaned", 0)),
		"PASS" if depot.cashed >= 1 else "FAIL"])
	if DevHooks.has("orbit-lap-quit") or DevHooks.has("orbit-cash-quit"):
		get_tree().quit(0 if depot.cashed >= 1 else 1)


# --- Robots: this node is the SphereBot graph -------------------------------------------

func _spawn_bots(hub: int, n: int) -> void:
	var around: PackedInt32Array = grid.cells_around(hub, 1)
	for i: int in n:
		var b := SphereBot.new()
		b.name = "Bot%d" % i
		add_child(b)
		b.setup(surface, grid.centers[around[(i + 1) % around.size()]])
		b.add_visual(["scoopie", "haulbug", "scoopie", "scoopie"][i % 4])
		b.graph = self
		b.hub_cell = hub
		b.cell = around[(i + 1) % around.size()]
		b.swarm = swarm
		swarm.add(b)
		bots.append(b)


func claim_dirty(from: int, hub: int, rings: int) -> int:
	var lim: float = (rings + 0.5) * 17.3
	var seen: Dictionary = {from: true}
	var front := PackedInt32Array([from])
	while not front.is_empty():
		var nxt := PackedInt32Array()
		for c: int in front:
			if cells.is_dirty(c) and not _claimed.has(c):
				_claimed[c] = true
				return c
			for j: int in grid.neighbors(c):
				if not seen.has(j) and grid.distance_m(j, hub) < lim:
					seen[j] = true
					nxt.append(j)
		front = nxt
	return -1


func path(from: int, to: int) -> PackedInt32Array:
	if to < 0:
		return PackedInt32Array()
	var prev: Dictionary = {from: -1}
	var front := PackedInt32Array([from])
	var lim: float = grid.distance_m(from, to) + 100.0
	while not front.is_empty() and not prev.has(to):
		var nxt := PackedInt32Array()
		for c: int in front:
			for j: int in grid.neighbors(c):
				if not prev.has(j) and grid.distance_m(j, to) < lim:
					prev[j] = c
					nxt.append(j)
		front = nxt
	var out := PackedInt32Array()
	var cur: int = to
	while cur != -1 and prev.has(cur):
		out.insert(0, cur)
		cur = prev[cur]
	return out


func work_cell(c: int, left: float) -> void:
	if field.materialized[c] == 1:
		for pid: int in field.reduce_to(c, left):
			junk_view.hide_piece(pid)
		_write_cell(c)
		if left <= 0.0 and field.hex_clean[c] == 0:
			field.hex_clean[c] = 1
			field.cleaned_count += 1
	else:
		cells.set_junk(c, left)
		field.settle(c)
	if left <= 0.0 and cells.state[c] == 0:
		cells.set_state(c, 1)


func junk_left(c: int) -> float:
	return (1.0 - field.removed_fraction(c)) if field and field.materialized[c] == 1 else cells.junk[c]


func release(c: int) -> void:
	_claimed.erase(c)


## Far crews: no nodes or physics. Each one clears whole cells nearest its hub at `rate` cells per
## minute (the same shape as Offline.compute, per hub).
func _tick(list: Array[Dictionary], dt: float) -> void:
	for cr: Dictionary in list:
		cr["acc"] = float(cr["acc"]) + float(cr["rate"]) * dt / 60.0
		while float(cr["acc"]) >= 1.0:
			cr["acc"] = float(cr["acc"]) - 1.0
			var c: int = claim_dirty(int(cr["hub"]), int(cr["hub"]), 16)
			if c < 0:
				break
			cells.set_junk(c, 0.0)
			cells.set_state(c, 1)
			if field:
				if field.materialized[c] == 1:
					work_cell(c, 0.0)
				else:
					field.settle(c)
			release(c)


# --- Lap test + trail -------------------------------------------------------------------

func _lap_tick(delta: float) -> void:
	if not _lap_on or _lap_done:
		return
	_lap_t += delta
	_trail_d += lumi.velocity.length() * delta
	if _trail_d > 20.0:
		_trail_d = 0.0
		var p: Vector3 = lumi.global_position
		_trail.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	if int(_lap_t / 60.0) != int((_lap_t - delta) / 60.0):
		print("[orbit] t=%.0fs walked=%.0fm cell=%d %s" % [_lap_t, lumi.sphere_motor.distance, grid.cell_at(lumi.global_position), _perf_line()])
	var circ: float = TAU * grid.radius_m
	if lumi.sphere_motor.distance > circ * 0.8:
		var dd: float = lumi.global_position.distance_to(_lap_start)
		if dd < _lap_min:
			_lap_min = dd
		elif dd > _lap_min + 15.0:
			_lap_done = true
			_trail.append([_lap_start.x, _lap_start.y, _lap_start.z])
			var ok: bool = _lap_min < 12.0
			print("[orbit] LAP walked=%.0fm around=%.0fm game_time=%.0fs (%.1f min) closest_to_start=%.2fm %s" % [
				lumi.sphere_motor.distance, circ, _lap_t, _lap_t / 60.0, _lap_min, "PASS" if ok else "FAIL"])
			var abs_path: String = ProjectSettings.globalize_path(LAP_PATH)
			DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
			var fa := FileAccess.open(abs_path, FileAccess.WRITE)
			if fa:
				fa.store_string(JSON.stringify({"trail": _trail, "R": grid.radius_m, "time_s": _lap_t, "closest": _lap_min}))
			if DevHooks.has("orbit-lap-quit"):
				get_tree().quit(0 if ok else 1)


func _draw_trail() -> void:
	var abs_path: String = ProjectSettings.globalize_path(LAP_PATH)
	if not FileAccess.file_exists(abs_path):
		push_warning("orbit: no lap trail at %s (run --orbit --orbit-walk first)" % abs_path)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
	if not (d is Dictionary):
		return
	var pts: Array = (d as Dictionary).get("trail", [])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 1.0, 0.95)
	var seg := CylinderMesh.new()
	seg.top_radius = 7.0
	seg.bottom_radius = 7.0
	seg.height = 1.0
	seg.radial_segments = 6
	seg.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = seg
	mm.instance_count = maxi(0, pts.size() - 1)
	for i: int in pts.size() - 1:
		var a := Vector3(float(pts[i][0]), float(pts[i][1]), float(pts[i][2]))
		var b := Vector3(float(pts[i + 1][0]), float(pts[i + 1][1]), float(pts[i + 1][2]))
		a += a.normalized() * 6.0
		b += b.normalized() * 6.0
		var y: Vector3 = b - a
		var x: Vector3 = y.cross(a).normalized()
		var z: Vector3 = x.cross(y.normalized())
		mm.set_instance_transform(i, Transform3D(Basis(x, y, z), (a + b) * 0.5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	var mk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 16.0
	cyl.bottom_radius = 1.0
	cyl.height = 180.0
	mk.mesh = cyl
	var m2 := StandardMaterial3D.new()
	m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m2.albedo_color = Color(1.0, 0.8, 0.35)
	mk.material_override = m2
	add_child(mk)
	var u: Vector3 = lumi.global_position.normalized()
	mk.global_transform = Transform3D(SphereGrid.frame(u), lumi.global_position + u * 90.0)


# --- Loop -------------------------------------------------------------------------------

func _update_centres() -> void:
	var cp: Vector3 = _orbit_cam.global_position if _orbit_cam else cam.camera.global_position
	streamer.set_centre("view", cp, SphereStreamer.VIEW)
	streamer.set_centre("lumi", lumi.global_position, SphereStreamer.BODY)


func _physics_process(delta: float) -> void:
	_lap_tick(delta)
	_scoop_log(delta)


func _process(delta: float) -> void:
	_perf_tick(delta)
	var f: Basis = cam.frame
	env.sky_rotation = f.get_euler()
	_update_day(delta, f)
	if Input.is_action_just_pressed("open_command") and lumi.input is PlayerInput and (lumi.input as PlayerInput).enabled:
		cam.view = "follow" if cam.view == "command" else "command"
	if _orbit_cam:  # the whole little planet with Lumi's side toward the camera
		var u: Vector3 = lumi.up()
		var d: Vector3 = (u * 0.82 + f.z * 0.57).normalized()
		_orbit_cam.look_at_from_position(d * grid.radius_m * 2.7, u * grid.radius_m * 0.12, f.y)
		_orbit_cam.current = true
	_update_centres()
	if _junk_dirty:
		_junk_dirty = false
		_rebuild_junk()
	_tick(crews, delta)
	if _hud:
		var cleaned: int = 0
		for b: SphereBot in bots:
			cleaned += b.cleaned
		_hud.text = "Verdance  R %.0f m  %d hexes  walked %.0f / %.0f m  junk %d  bots cleaned %d  fps %d" % [
			grid.radius_m, grid.cell_count(), lumi.sphere_motor.distance, TAU * grid.radius_m, int(stats.get("junk", 0)), cleaned,
			Engine.get_frames_per_second()]


# --- Day and night (owner: real day and night sides) -------------------------------------
## Two suns fixed in space light one side of the planet; the planet turns once every day_min
## minutes, so walking far changes your local time and every spot gets its own day. The sky
## dome follows the local frame (sky_rotation), so a sky-only light carries the sun's direction
## into sky space for the disk; the scene is lit by the real (world-space) lights.

const DECLINATION: float = 0.25

var _phi0: float = 0.0
var _elapsed: float = 0.0


func _build_lights() -> void:
	day_min = DevHooks.get_f("orbit-day", 24.0)
	var h: Vector3 = grid.centers[int(sites[0]["cell"])]
	var lon: float = atan2(h.x, h.z)
	_phi0 = lon + (DevHooks.get_f("orbit-time", 0.42) - 0.5) * TAU
	sun2 = DirectionalLight3D.new()
	sun2.name = "SecondSun"
	sun2.light_color = Color(1.0, 0.72, 0.5)
	sun2.shadow_enabled = false
	sun2.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun2)
	sky_sun = DirectionalLight3D.new()
	sky_sun.name = "SkySun"
	sky_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	sky_sun.light_color = sun.light_color
	add_child(sky_sun)
	lamp = OmniLight3D.new()  # Lumi's own light: nights stay readable (Glim takes this over)
	lamp.name = "LumiLamp"
	lamp.omni_range = 11.0
	lamp.light_color = Color(0.75, 0.88, 1.0)
	lamp.shadow_enabled = false
	lumi.add_child(lamp)
	lamp.position = Vector3(0, 2.4, 0.4)


## World direction toward a sun at rotation phase phi (the planet's spin axis is world +Y).
static func sun_dir(phi: float, decl: float) -> Vector3:
	return Vector3(sin(phi) * cos(decl), sin(decl), cos(phi) * cos(decl)).normalized()


## Local time 0..1 (0.5 = noon) at a point, for the HUD clock and tests.
func local_time(p: Vector3) -> float:
	var phi: float = _phi0 + TAU * _elapsed / (day_min * 60.0)
	var lon: float = atan2(p.x, p.z)
	return fposmod(0.5 + (phi - lon) / TAU, 1.0)


func _update_day(delta: float, f: Basis) -> void:
	_elapsed += delta
	var phi: float = _phi0 + TAU * _elapsed / (day_min * 60.0)
	var s1: Vector3 = sun_dir(phi, DECLINATION)
	var s2: Vector3 = sun_dir(phi + 0.42, DECLINATION - 0.12)
	var u: Vector3 = lumi.up()
	var e1: float = s1.dot(u)
	var e2: float = s2.dot(u)
	var d1: float = smoothstep(-0.06, 0.14, e1)
	var d2: float = smoothstep(-0.06, 0.14, e2)
	var day: float = maxf(d1, d2 * 0.8)
	sun.global_basis = _toward(s1)
	sun.light_energy = 1.2 * d1
	sun.shadow_enabled = d1 > 0.05
	sun2.global_basis = _toward(s2)
	sun2.light_energy = 0.45 * d2
	var sky_dir: Vector3 = (f * s1) if DevHooks.has("orbit-skyflip") else (f.transposed() * s1)
	sky_sun.global_basis = _toward(sky_dir)
	sky_sun.light_energy = 1.0
	env.ambient_light_energy = lerpf(0.75, 1.1, day)
	env.ambient_light_sky_contribution = lerpf(0.25, 1.0, day)
	env.ambient_light_color = Color(0.36, 0.44, 0.62)
	env.tonemap_exposure = lerpf(1.55, 1.25, day)
	lamp.light_energy = lerpf(2.2, 0.0, day)
	lamp.visible = day < 0.98
	stats["local_time"] = local_time(lumi.global_position)
	stats["daylight"] = day


static func _toward(d: Vector3) -> Basis:
	var ref: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	return Basis.looking_at(-d, ref)


func _perf_tick(delta: float) -> void:
	_perf[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_perf[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf[2] = maxf(_perf[2], Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_perf[3] += delta
	_perf_n += 1
	if _perf[3] >= 5.0 * Engine.time_scale and (not DevHooks.has("orbit-walk") or DevHooks.has("orbit-scoop")):
		print("[orbit-perf] " + _perf_line())


var _scoop_log_t: float = 0.0


func _scoop_log(delta: float) -> void:
	if not DevHooks.has("orbit-scoop"):
		return
	_scoop_log_t += delta
	if int(_scoop_log_t / 10.0) != int((_scoop_log_t - delta) / 10.0):
		print("[orbit] scoop t=%.0fs walked=%.0fm fill=%.2f/%.2f scooped=%.1f hexes_cleaned=%d cubes=%s junk_drawn=%d time=%.2f day=%.2f" % [
			_scoop_log_t, lumi.sphere_motor.distance, lumi.compartment.fill, lumi.capacity(), float(GameState.stats.get("junk_removed", 0.0)) if GameState.stats.get("junk_removed", 0.0) is float else -1.0,
			int(GameState.stats.get("hexes_cleaned", 0)), Settings.fmt(GameState.get_currency("cubes")), int(stats.get("junk", 0)),
			float(stats.get("local_time", 0.0)), float(stats.get("daylight", 0.0))])


func _perf_line() -> String:
	var st: Dictionary = streamer.stats
	var s: String = "process_ms avg=%.2f max=%.2f physics_ms avg=%.2f junk=%d junk_ms=%d draw_calls=%d prims=%d streamer=%s" % [
		_perf[0] / maxi(_perf_n, 1), _perf[2], _perf[1] / maxi(_perf_n, 1), int(stats.get("junk", 0)), int(stats.get("junk_ms", 0)),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), JSON.stringify(st)]
	_perf = [0.0, 0.0, 0.0, 0.0]
	_perf_n = 0
	return s
