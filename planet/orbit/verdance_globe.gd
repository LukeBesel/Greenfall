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
## Dev: --orbit-walk[=boost] --orbit-lap-quit, --orbit-view=follow|ground|command|mid,
## --orbit-presim=MIN, --orbit-trail, --orbit-pieces=N, --orbit-hubs=N, --orbit-nohud,
## --orbit-mid-dist=R (mid camera distance in planet radii), --orbit-nolabels.
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
var walker: SphereWalker
var cam: SphereCam
var sun: DirectionalLight3D
var env: Environment
var hubs: Array[int] = []
var sites: Array[Dictionary] = []
var bots: Array[SphereBot] = []
var crews: Array[Dictionary] = []
var pieces_per_cell: int = 120
var stats: Dictionary = {}
var view: String = "follow"

var _orbit_cam: Camera3D
var _mid_dist: float = 2.2
var _junk_mms: Array[MultiMeshInstance3D] = []
var _junk_lift: Array[float] = []
var _junk_cache: Dictionary = {}
var _junk_dirty: bool = true
var _near_set: Dictionary = {}
var _junk_shown: Dictionary = {}
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
	pieces_per_cell = int(DevHooks.get_f("orbit-pieces", 120.0))
	view = DevHooks.get_s("orbit-view", "follow")
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
	_build_env()
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
	streamer.near_changed.connect(func(_a: PackedInt32Array, _r: PackedInt32Array) -> void: _junk_dirty = true)
	_build_junk_pool()
	_build_base(sites[0])
	for i: int in sites.size():
		_build_beacon(sites[i], i == 0)
	# Lumi on the start site, facing north up the main street.
	walker = SphereWalker.new(surface)
	walker.name = "Lumi"
	match DevHooks.get_s("orbit-walk", ""):
		"":
			walker.input = SphereInput.new()
		"boost":
			walker.input = SphereAutoInput.new(Vector3(0, 0, -1), true)
		_:
			walker.input = SphereAutoInput.new(Vector3(0, 0, -1), false)
	add_child(walker)
	var hub_cell: int = int(sites[0]["cell"])
	var spawn_dir: Vector3 = terrain.local_to_dir(hub_cell, 0.0, 6.0)
	var north: Vector3 = -SphereGrid.frame(spawn_dir).z
	walker.place(terrain.ground(spawn_dir) + spawn_dir * 0.3, north)
	cam = SphereCam.new()
	cam.name = "SphereCam"
	cam.surface = surface
	cam.target = walker
	add_child(cam)
	walker.cam = cam
	cam.reset_frame(north)
	_apply_view()
	cam.snap()
	_spawn_bots(hub_cell, 4)
	_update_centres()
	var t2: int = Time.get_ticks_msec()
	streamer.settle()
	stats["settle_ms"] = Time.get_ticks_msec() - t2
	if DevHooks.has("orbit-walk"):
		_lap_on = true
		_lap_start = walker.global_position
	if DevHooks.has("orbit-trail"):
		_draw_trail()
	Settings.apply_quality_to_tree(self)
	# The quality pass sets the flat-world fog density (0.0025..0.005); on the orbit that is several
	# times too thick, and from Command height the whole map turned to grey haze.
	env.fog_density = 0.0003 if view == "command" else 0.0011
	if not (DevHooks.has("orbit-nohud") or DevHooks.has("no-hud")):
		var cl := CanvasLayer.new()
		add_child(cl)
		_hud = Label.new()
		_hud.position = Vector2(14, 10)
		_hud.add_theme_font_size_override("font_size", 15)
		_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		cl.add_child(_hud)
	stats["ready_ms"] = Time.get_ticks_msec() - t0
	print("[orbit] integrated: R=%.0fm hexes=%d around=%.1fkm hubs=%d (nearest hub mean %.0fm, min %.0fm) ready=%dms planet=%dms grid=%dms settle=%dms" % [
		grid.radius_m, grid.cell_count(), TAU * grid.radius_m / 1000.0, sites.size(), _hub_spacing(false), _hub_spacing(true),
		stats["ready_ms"], stats["planet_ms"], stats["grid_ms"], stats["settle_ms"]])


func _apply_view() -> void:
	match view:
		"ground":
			cam.distance = 7.5
			cam.pitch = -0.1
		"command":
			cam.view = "command"
			cam.command_height = DevHooks.get_f("orbit-height", 400.0)
		"mid":
			env.fog_enabled = false
			env.tonemap_exposure = 1.0
			_mid_dist = DevHooks.get_f("orbit-mid-dist", 2.2)
			_orbit_cam = Camera3D.new()
			_orbit_cam.fov = 60.0
			_orbit_cam.far = grid.radius_m * 12.0
			_orbit_cam.near = 1.0
			add_child(_orbit_cam)
			_build_atmosphere()
			if not DevHooks.has("orbit-nolabels"):
				_build_city_labels()
	if DevHooks.has("orbit-cam"):
		var a: PackedStringArray = DevHooks.get_s("orbit-cam", "6,-0.3").split(",")
		cam.distance = float(a[0])
		if a.size() > 1:
			cam.pitch = float(a[1])


## A thin glowing rim around the planet for the orbit views.
func _build_atmosphere() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec3 tint = vec3(0.35, 0.65, 1.0);
void fragment() {
	float f = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint * (pow(f, 6.0) * 0.35 + pow(f, 14.0) * 0.6);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var sp := SphereMesh.new()
	sp.radius = grid.radius_m * 1.018
	sp.height = sp.radius * 2.0
	sp.radial_segments = 96
	sp.rings = 48
	var mi := MeshInstance3D.new()
	mi.name = "Atmosphere"
	mi.mesh = sp
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## City names (and hub sites) floating over the globe in the orbit view; the planet hides the
## ones on its far side.
func _build_city_labels() -> void:
	for cd: Dictionary in planet.cities:
		var d: Vector3 = grid.centers[int(cd["cell"])]
		var lb := Label3D.new()
		lb.text = str(cd["name"])
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.fixed_size = true
		lb.pixel_size = 0.0011
		lb.font_size = 26 if cd["capital"] else 20
		lb.outline_size = 8
		lb.modulate = Color(1.0, 0.86, 0.55) if cd["capital"] else Color(1.0, 0.95, 0.85)
		lb.outline_modulate = Color(0.05, 0.04, 0.03, 0.85)
		lb.position = d * (grid.radius_m + 40.0)
		lb.offset = Vector2(0, 26)  # just above the city, not over it
		add_child(lb)
	for i: int in sites.size():
		var d2: Vector3 = grid.centers[int(sites[i]["cell"])]
		var hb := Label3D.new()
		hb.text = "HOME" if i == 0 else "hub"
		hb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hb.fixed_size = true
		hb.pixel_size = 0.0011
		hb.font_size = 18
		hb.outline_size = 6
		hb.modulate = Color(0.45, 0.95, 1.0)
		hb.outline_modulate = Color(0.0, 0.08, 0.1, 0.85)
		hb.position = d2 * (grid.radius_m + 25.0)
		add_child(hb)


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
	_box(root, Vector3(0, 0, 0), Vector3(16, 0.25, 16), slab_m, false)
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
	add_child(sun)


# --- Junk (near ring) -------------------------------------------------------------------

func _build_junk_pool() -> void:
	for id: String in JUNK_MODELS:
		var mesh: Mesh = AssetLib.model_mesh_lite(id, 900) if AssetLib.has_model(id) else null
		if mesh == null:
			mesh = BoxMesh.new()
		_junk_lift.append(-mesh.get_aabb().position.y)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.extra_cull_margin = 4.0
		add_child(mmi)
		_junk_mms.append(mmi)


func _cell_junk(cell: int) -> Array:
	if _junk_cache.has(cell):
		return _junk_cache[cell]
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed_value * 31 + cell
	var bufs: Array = []
	for _m: int in JUNK_MODELS.size():
		bufs.append(PackedFloat32Array())
	var wsum: float = 0.0
	for w: float in JUNK_W:
		wsum += w
	var ctr: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(ctr)
	for i: int in pieces_per_cell:
		var r: float = sqrt(rng.randf()) * 9.2
		var a: float = rng.randf() * TAU
		var d: Vector3 = (ctr + (f.x * cos(a) + f.z * sin(a)) * (r / grid.radius_m)).normalized()
		var pick: float = rng.randf() * wsum
		var m: int = 0
		while m < JUNK_W.size() - 1 and pick > JUNK_W[m]:
			pick -= JUNK_W[m]
			m += 1
		var lf: Basis = SphereGrid.frame(d)
		var b := Basis(lf.y, rng.randf() * TAU) * lf
		if rng.randf() < 0.45:
			b = Basis(b.x, rng.randf_range(1.2, 1.7)) * b
		var s: float = rng.randf_range(0.85, 1.25)
		b = b.scaled(Vector3.ONE * s)
		var o: Vector3 = terrain.ground(d) + d * (_junk_lift[m] * s * 0.6 - 0.04)
		var buf: PackedFloat32Array = bufs[m]
		buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z]))
		bufs[m] = buf
	_junk_cache[cell] = bufs
	return bufs


func _rebuild_junk() -> void:
	var t0: int = Time.get_ticks_msec()
	var near: PackedInt32Array = streamer.near_cells()
	_near_set.clear()
	for c: int in near:
		_near_set[c] = true
	if _junk_cache.size() > 2500:
		var keep: Dictionary = {}
		for c: int in near:
			if _junk_cache.has(c):
				keep[c] = _junk_cache[c]
		_junk_cache = keep
	var out: Array = []
	for _m: int in JUNK_MODELS.size():
		out.append(PackedFloat32Array())
	var total: int = 0
	for c: int in near:
		var j: float = cells.junk[c] if cells.is_dirty(c) else 0.0
		_junk_shown[c] = j
		if j <= 0.02:
			continue
		var bufs: Array = _cell_junk(c)
		for m: int in bufs.size():
			var b: PackedFloat32Array = bufs[m]
			@warning_ignore("integer_division")
			var k: int = int(round(b.size() / 12 * j))
			if k > 0:
				var o: PackedFloat32Array = out[m]
				o.append_array(b.slice(0, k * 12))
				out[m] = o
				total += k
	for m: int in _junk_mms.size():
		var mm: MultiMesh = _junk_mms[m].multimesh
		var o: PackedFloat32Array = out[m]
		mm.instance_count = 0
		@warning_ignore("integer_division")
		mm.instance_count = o.size() / 12
		if o.size() > 0:
			mm.buffer = o
	stats["junk"] = total
	stats["junk_ms"] = Time.get_ticks_msec() - t0


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
	cells.set_junk(c, left)
	if left <= 0.0 and cells.state[c] == 0:
		cells.set_state(c, 1)
	if _near_set.has(c) and absf(float(_junk_shown.get(c, 1.0)) - maxf(left, 0.0)) > 0.08:
		_junk_dirty = true


func junk_left(c: int) -> float:
	return cells.junk[c]


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
			release(c)


# --- Lap test + trail -------------------------------------------------------------------

func _lap_tick(delta: float) -> void:
	if not _lap_on or _lap_done:
		return
	_lap_t += delta
	_trail_d += walker.velocity.length() * delta
	if _trail_d > 20.0:
		_trail_d = 0.0
		var p: Vector3 = walker.global_position
		_trail.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	if int(_lap_t / 60.0) != int((_lap_t - delta) / 60.0):
		print("[orbit] t=%.0fs walked=%.0fm cell=%d %s" % [_lap_t, walker.distance, grid.cell_at(walker.global_position), _perf_line()])
	var circ: float = TAU * grid.radius_m
	if walker.distance > circ * 0.8:
		var dd: float = walker.global_position.distance_to(_lap_start)
		if dd < _lap_min:
			_lap_min = dd
		elif dd > _lap_min + 15.0:
			_lap_done = true
			_trail.append([_lap_start.x, _lap_start.y, _lap_start.z])
			var ok: bool = _lap_min < 12.0
			print("[orbit] LAP walked=%.0fm around=%.0fm game_time=%.0fs (%.1f min) closest_to_start=%.2fm %s" % [
				walker.distance, circ, _lap_t, _lap_t / 60.0, _lap_min, "PASS" if ok else "FAIL"])
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
	var u: Vector3 = walker.global_position.normalized()
	mk.global_transform = Transform3D(SphereGrid.frame(u), walker.global_position + u * 90.0)


# --- Loop -------------------------------------------------------------------------------

func _update_centres() -> void:
	var cp: Vector3 = _orbit_cam.global_position if _orbit_cam else cam.camera.global_position
	streamer.set_centre("view", cp, SphereStreamer.VIEW)
	streamer.set_centre("lumi", walker.global_position, SphereStreamer.BODY)


func _physics_process(delta: float) -> void:
	_lap_tick(delta)


func _process(delta: float) -> void:
	_perf_tick(delta)
	var f: Basis = cam.frame
	env.sky_rotation = f.get_euler()
	sun.global_basis = f * Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(35.0), 0.0))
	if _orbit_cam:  # the whole little planet with Lumi's side toward the camera
		var u: Vector3 = walker.up()
		var d: Vector3 = (u * 0.82 + f.z * 0.57).normalized()
		_orbit_cam.look_at_from_position(d * grid.radius_m * _mid_dist, u * grid.radius_m * 0.12, f.y)
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
			grid.radius_m, grid.cell_count(), walker.distance, TAU * grid.radius_m, int(stats.get("junk", 0)), cleaned,
			Engine.get_frames_per_second()]


func _perf_tick(delta: float) -> void:
	_perf[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_perf[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf[2] = maxf(_perf[2], Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_perf[3] += delta
	_perf_n += 1
	if _perf[3] >= 5.0 * Engine.time_scale and not DevHooks.has("orbit-walk"):
		print("[orbit-perf] " + _perf_line())


func _perf_line() -> String:
	var st: Dictionary = streamer.stats
	var s: String = "process_ms avg=%.2f max=%.2f physics_ms avg=%.2f junk=%d junk_ms=%d draw_calls=%d prims=%d streamer=%s" % [
		_perf[0] / maxi(_perf_n, 1), _perf[2], _perf[1] / maxi(_perf_n, 1), int(stats.get("junk", 0)), int(stats.get("junk_ms", 0)),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), JSON.stringify(st)]
	_perf = [0.0, 0.0, 0.0, 0.0]
	_perf_n = 0
	return s
