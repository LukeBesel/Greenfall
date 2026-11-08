class_name OrbitWorld
extends Node3D
## [orbit] Prototype (dev flag --orbit): Verdance as one walkable little planet.
## - The globe is the survey PlanetData itself (40,962 Goldberg cells: hexes + 12 pentagons).
## - Streaming: ground chunks (162 per planet, ~250 cells each, mesh + trimesh collision) load
##   within STREAM_M of Lumi, one per frame; junk is drawn only for the cells within JUNK_RINGS
##   of Lumi (multimesh per model, rebuilt from cached per-cell transforms when Lumi changes cell
##   or a cell there is cleaned); the rest of the planet is one low-detail shell reading the same
##   per-cell state texture, so far cleaning shows from orbit.
## - Hubs are sites on the globe (a spaced subset of PlanetData.hubs, each with a beacon); the
##   start hub has a small base and ruined blocks placed on the sphere.
## - Near robots walk the hex graph (OrbitBot); far crews are data-only (abstract simulation).
## Dev: --orbit-walk[=deg] (straight line, lap report), --orbit-view=follow|low|mid,
## --orbit-presim=MIN (far crews' progress), --orbit-pieces=N, --orbit-hubs=N, --orbit-hex=M, --orbit-level=6|7 (default 7),
## --orbit-trail (draw the saved lap), --orbit-nohud, --orbit-lap-quit.

var stream_m: float = 560.0
const JUNK_RINGS: int = 5
const LAP_PATH := "res://screenshots/orbit/lap_trail.json"
const JUNK_MODELS: Array[String] = ["old_tyre", "Television_01", "vintage_microwave", "plastic_crate_01", "trashbag",
	"metal_jerrycan", "cardboard_box_01", "plastic_jerrycan", "can_rusted", "bleach_bottle", "rusted_wheel_rim_01", "cement_bag"]
const JUNK_W: Array[float] = [0.6, 0.35, 0.35, 0.8, 1.0, 0.8, 1.0, 0.8, 2.0, 1.4, 0.5, 0.7]

var planet: PlanetData
var globe: OrbitGlobe
var walker: OrbitWalker
var cam: OrbitCam
var sun: DirectionalLight3D
var env: Environment
var ground_mat: ShaderMaterial
var hubs: Array[int] = []
var start_hub: int = 0
var bots: Array[OrbitBot] = []
var crews: Array[Dictionary] = []  # far crews: {hub, rate (cells/min), acc}
var pieces_per_cell: int = 120

var _chunks: Dictionary = {}  # chunk id -> Node3D
var _chunk_queue := PackedInt32Array()
var _stream_t: float = 0.0
var _junk_meshes: Array[Mesh] = []
var _junk_lift: Array[float] = []
var _junk_mms: Array[MultiMeshInstance3D] = []
var _junk_cache: Dictionary = {}  # cell -> Array[PackedFloat32Array] (one per model)
var _junk_ring := PackedInt32Array()
var _junk_ring_set: Dictionary = {}
var _junk_dirty: bool = true
var _junk_shown: Dictionary = {}  # cell -> junk fraction last drawn
var _walker_cell: int = 0
var _claimed: Dictionary = {}
var _warp := [FastNoiseLite.new(), FastNoiseLite.new(), FastNoiseLite.new()]
var _hud: Label
# Lap test.
var _lap_on: bool = false
var _lap_start := Vector3.ZERO
var _lap_min: float = INF
var _lap_done: bool = false
var _lap_t: float = 0.0
var _trail: Array = []
var _trail_d: float = 0.0
# Perf.
var stats: Dictionary = {}


func _ready() -> void:
	var t0: int = Time.get_ticks_msec()
	var hex: float = DevHooks.get_f("orbit-hex", 10.0)
	planet = PlanetData.new(int(DevHooks.get_f("seed", 4471.0)), int(DevHooks.get_f("orbit-level", 7.0)), hex)
	planet.generate()
	stats["planet_ms"] = Time.get_ticks_msec() - t0
	var t1: int = Time.get_ticks_msec()
	globe = OrbitGlobe.new(planet, hex)
	stats["globe_ms"] = Time.get_ticks_msec() - t1
	pieces_per_cell = int(DevHooks.get_f("orbit-pieces", 120.0))
	for k: int in 3:
		var nz: FastNoiseLite = _warp[k]
		nz.seed = planet.seed_value + 300 + k
		nz.frequency = 1.0 / 26.0
	_pick_hubs(int(DevHooks.get_f("orbit-hubs", 10.0)))
	start_hub = hubs[0]
	for h: int in hubs:  # every hub site stands on a level pad (prefab footprint ~70 m)
		globe.add_site(globe.grid.centers[h], 140.0 if h == start_hub else 45.0, 40.0)
	for h: int in hubs:
		for c: int in globe.cells_around(h, 2):
			if planet.state[c] != PlanetData.State.WATER:
				globe.set_cell(c, 0.0, PlanetData.State.CLEAN)
	if DevHooks.has("orbit-presim"):
		_presim_crews(DevHooks.get_f("orbit-presim", 120.0) * 60.0)
	globe.flush()
	_build_env()
	_build_ground_mat()
	_build_shell()
	_build_junk_pool()
	# Lumi at the start hub, facing north along the base's main street.
	walker = OrbitWalker.new()
	walker.name = "Lumi"
	if DevHooks.has("orbit-walk"):
		walker.input = StraightWalkInput.new(Vector3(0, 0, -1))
	add_child(walker)
	var hub_dir: Vector3 = globe.grid.centers[start_hub]
	var spawn_dir: Vector3 = planet.local_to_dir(start_hub, 0.0, 6.0)
	walker.global_position = globe.ground(spawn_dir) + spawn_dir * 0.3
	var north: Vector3 = OrbitGlobe.frame(spawn_dir).z * -1.0
	var heading: float = deg_to_rad(DevHooks.get_f("orbit-walk", 0.0)) if DevHooks.get_s("orbit-walk", "1") != "1" else 0.0
	north = north.rotated(spawn_dir, -heading)
	walker.face(north)
	_walker_cell = globe.cell_at(walker.global_position, start_hub)
	cam = OrbitCam.new()
	cam.name = "OrbitCam"
	cam.target = walker
	cam.planet_r = globe.R
	add_child(cam)
	walker.cam = cam
	cam.reset_frame(north)
	_apply_view(DevHooks.get_s("orbit-view", "follow"))
	# Ground under Lumi before the first physics frame.
	var t2: int = Time.get_ticks_msec()
	for c: int in globe.chunks_near(walker.global_position, 300.0 if cam.view == "follow" else stream_m):  # all of it for fixed views (slow software renders)
		_load_chunk(c)
	stats["first_chunks_ms"] = Time.get_ticks_msec() - t2
	_queue_chunks()
	_build_base(start_hub)
	for i: int in hubs.size():
		_build_beacon(hubs[i], i == 0)
	_spawn_bots(start_hub, 4)
	for i: int in range(1, hubs.size()):
		crews.append({"hub": hubs[i], "rate": 0.25 + 0.05 * (i % 4), "acc": 0.0})
	if DevHooks.has("orbit-walk"):
		_lap_on = true
		_lap_start = walker.global_position
	if DevHooks.has("orbit-trail"):
		_draw_trail()
	_build_hud()
	stats["ready_ms"] = Time.get_ticks_msec() - t0
	print("[orbit] R=%.0fm cells=%d circumference=%.0fm hubs=%d (mean nearest hub %.0fm) chunks=%d ready=%dms planet=%dms globe=%dms first_chunks=%dms" % [
		globe.R, planet.cell_count(), TAU * globe.R, hubs.size(), _hub_spacing(), globe.chunk_grid.cell_count(),
		stats["ready_ms"], stats["planet_ms"], stats["globe_ms"], stats["first_chunks_ms"]])


func _apply_view(v: String) -> void:
	cam.view = v
	match v:
		"low":
			stream_m = 950.0
			cam.distance = 190.0
			cam.pitch = -0.62
		"mid":
			env.fog_enabled = false
		"ground":
			cam.view = "follow"
			cam.distance = 7.5
			cam.pitch = -0.1
	if DevHooks.has("orbit-cam"):  # dist,pitch
		var a: PackedStringArray = DevHooks.get_s("orbit-cam", "6,-0.3").split(",")
		cam.distance = float(a[0])
		cam.pitch = float(a[1]) if a.size() > 1 else cam.pitch


# --- Hubs -----------------------------------------------------------------------------

func _pick_hubs(n: int) -> void:
	# Farthest-point subset of the survey's hub sites, starting at the Junkyard Hub.
	hubs = [planet.hubs[0]]
	while hubs.size() < mini(n, planet.hubs.size()):
		var best: int = -1
		var best_d: float = -1.0
		for h: int in planet.hubs:
			var d: float = INF
			for k: int in hubs:
				d = minf(d, globe.grid.centers[h].angle_to(globe.grid.centers[k]))
			if d > best_d:
				best_d = d
				best = h
		hubs.append(best)


func _hub_spacing() -> float:
	var s: float = 0.0
	for h: int in hubs:
		var d: float = INF
		for k: int in hubs:
			if k != h:
				d = minf(d, globe.grid.centers[h].angle_to(globe.grid.centers[k]))
		s += d * globe.R
	return s / maxf(1.0, hubs.size())


func _build_beacon(cell: int, home: bool) -> void:
	var d: Vector3 = globe.grid.centers[cell]
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35 if home else 1.4
	cyl.bottom_radius = 0.5 if home else 1.8
	cyl.height = 26.0 if home else 70.0
	cyl.radial_segments = 8
	cyl.rings = 1
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 0.95, 1.0) if not home else Color(1.0, 0.75, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.55
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var off: Vector3 = Vector3(9.0, 0, -9.0) if home else Vector3.ZERO
	var p: Vector3 = globe.local_point(cell, off.x, off.z)
	mi.global_transform = Transform3D(OrbitGlobe.frame(p.normalized()), p + p.normalized() * cyl.height * 0.5)


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
	sm.ground_color = Color(0.32, 0.4, 0.55)  # below the tiny planet's horizon: haze, not grey ground
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.62, 0.66)
	env.fog_density = 0.0016
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


## The sky and the sun follow the local surface frame: wherever Lumi stands, "up" is up and the
## time of day is the district's (a fixed world sun would put half the planet in night).
func _orient_sky() -> void:
	var f: Basis = cam.frame
	env.sky_rotation = f.get_euler()
	sun.global_transform = Transform3D(f * Basis.from_euler(Vector3(deg_to_rad(-38.0), deg_to_rad(35.0), 0.0)), Vector3.ZERO)


# --- Ground -----------------------------------------------------------------------------

func _build_ground_mat() -> void:
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = preload("res://planet/orbit/orbit_ground.gdshader")
	ground_mat.set_shader_parameter("state_tex", globe.state_tex)
	ground_mat.set_shader_parameter("state_w", OrbitGlobe.STATE_W)
	ground_mat.set_shader_parameter("tex_dirt", AssetLib.tex("dry_ground_rocks", "diff"))
	ground_mat.set_shader_parameter("tex_rubble", AssetLib.tex("rubble", "diff"))
	ground_mat.set_shader_parameter("tex_clean", AssetLib.tex("dirty_concrete", "diff"))
	ground_mat.set_shader_parameter("tex_grass", AssetLib.tex("sparse_grass", "diff"))


## The whole planet at low detail (level-5 icosphere, ~20k triangles) just under the chunk ground.
func _build_shell() -> void:
	var g5: GeoSphere = GeoSphere.cached(5)
	var n: int = g5.cell_count()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv2 := PackedVector2Array()
	v.resize(n)
	nr.resize(n)
	uv2.resize(n)
	for i: int in n:
		var d: Vector3 = g5.centers[i]
		v[i] = d * (globe.R - 1.6)
		nr[i] = d
		uv2[i] = Vector2(float(i), 0.0)  # level-5 vertex i is level-6 cell i (subdivision appends)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = _flip(g5.tris)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "FarShell"
	mi.mesh = am
	var m: ShaderMaterial = ground_mat.duplicate()
	m.set_shader_parameter("far_shell", 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Godot's front faces are clockwise; the icosphere is counter-clockwise from outside.
static func _flip(idx: PackedInt32Array) -> PackedInt32Array:
	var o := idx.duplicate()
	for t: int in range(0, o.size(), 3):
		var a: int = o[t + 1]
		o[t + 1] = o[t + 2]
		o[t + 2] = a
	return o


func _owner(d: Vector3, hint: int) -> int:
	var a: float = globe.cell_angle() * 0.55
	var p: Vector3 = d * globe.R
	var w := Vector3((_warp[0] as FastNoiseLite).get_noise_3dv(p), (_warp[1] as FastNoiseLite).get_noise_3dv(p), (_warp[2] as FastNoiseLite).get_noise_3dv(p))
	return globe.grid.nearest_from((d + w * a).normalized(), hint)


func _load_chunk(c: int) -> void:
	if _chunks.has(c):
		return
	var t0: int = Time.get_ticks_msec()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var g: GeoSphere = globe.grid
	for cell: int in globe.chunk_cells[c]:
		var ctr: Vector3 = g.centers[cell]
		var cs: PackedVector3Array = g.corners(cell)
		var k: int = cs.size()
		var base: int = v.size()
		var dirs: Array[Vector3] = [ctr]
		for i: int in k:
			dirs.append(cs[i])
		for i: int in k:
			dirs.append((ctr + cs[i]).normalized())  # spoke mids: 1 + k + i
		for i: int in k:
			dirs.append((cs[i] + cs[(i + 1) % k]).normalized())  # edge mids: 1 + 2k + i
		for d: Vector3 in dirs:
			var own: int = _owner(d, cell)
			var h: float = globe.height(d)
			if planet.state[own] == PlanetData.State.WATER:
				h -= 0.45
			v.append(d * (globe.R + h))
			nr.append(globe.ground_normal(d))
			uv2.append(Vector2(float(own), 0.0))
		# Clockwise from outside (Godot front faces), whatever the grid's corner order is.
		var n0: Vector3 = (v[base + 1 + k] - v[base]).cross(v[base + 1 + k + 1] - v[base])
		var flip: bool = n0.dot(ctr) < 0.0
		for i: int in k:
			var j: int = (i + 1) % k
			var s0: int = base + 1 + k + i
			var s1: int = base + 1 + k + j
			var c0: int = base + 1 + i
			var c1: int = base + 1 + j
			var e: int = base + 1 + 2 * k + i
			if flip:
				idx.append_array(PackedInt32Array([base, s0, s1, s0, c0, e, s0, e, s1, s1, e, c1]))
			else:
				idx.append_array(PackedInt32Array([base, s1, s0, s0, e, c0, s0, s1, e, s1, c1, e]))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var node := Node3D.new()
	node.name = "Chunk%d" % c
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = ground_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var body := StaticBody3D.new()
	var cs3 := CollisionShape3D.new()
	var shp := ConcavePolygonShape3D.new()
	shp.backface_collision = true
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for i: int in idx.size():
		faces[i] = v[idx[i]]
	shp.set_faces(faces)
	cs3.shape = shp
	body.add_child(cs3)
	node.add_child(body)
	add_child(node)
	_chunks[c] = node
	stats["chunk_ms_sum"] = float(stats.get("chunk_ms_sum", 0.0)) + (Time.get_ticks_msec() - t0)
	stats["chunks_built"] = int(stats.get("chunks_built", 0)) + 1


func _queue_chunks() -> void:
	var want: PackedInt32Array = globe.chunks_near(walker.global_position, stream_m)
	for c: int in want:
		if not _chunks.has(c) and not _chunk_queue.has(c):
			_chunk_queue.append(c)
	# Unload chunks well out of range (hysteresis).
	var keep: PackedInt32Array = globe.chunks_near(walker.global_position, stream_m + 250.0)
	for c: int in _chunks.keys():
		if not keep.has(c):
			(_chunks[c] as Node).queue_free()
			_chunks.erase(c)


# --- Junk -------------------------------------------------------------------------------

func _build_junk_pool() -> void:
	for id: String in JUNK_MODELS:
		var mesh: Mesh = AssetLib.model_mesh_lite(id, 900) if AssetLib.has_model(id) else null
		if mesh == null:
			mesh = BoxMesh.new()
		_junk_meshes.append(mesh)
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
	var ctr: Vector3 = globe.grid.centers[cell]
	var f: Basis = OrbitGlobe.frame(ctr)
	for i: int in pieces_per_cell:
		var r: float = sqrt(rng.randf()) * globe.hex_size * 0.92
		var a: float = rng.randf() * TAU
		var d: Vector3 = (ctr + (f.x * cos(a) + f.z * sin(a)) * (r / globe.R)).normalized()
		var pick: float = rng.randf() * wsum
		var m: int = 0
		while m < JUNK_W.size() - 1 and pick > JUNK_W[m]:
			pick -= JUNK_W[m]
			m += 1
		var up: Vector3 = d
		var lf: Basis = OrbitGlobe.frame(up)
		var b := Basis(lf.y, rng.randf() * TAU) * lf
		if rng.randf() < 0.45:
			b = Basis(b.x, rng.randf_range(1.2, 1.7)) * b
		var s: float = rng.randf_range(0.85, 1.25)
		b = b.scaled(Vector3.ONE * s)
		var o: Vector3 = globe.ground(d) + up * (_junk_lift[m] * s * 0.6 - 0.04)
		var buf: PackedFloat32Array = bufs[m]
		buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z]))
		bufs[m] = buf
	_junk_cache[cell] = bufs
	return bufs


func _rebuild_junk() -> void:
	var t0: int = Time.get_ticks_msec()
	_junk_ring = globe.cells_around(_walker_cell, JUNK_RINGS)
	_junk_ring_set.clear()
	for c: int in _junk_ring:
		_junk_ring_set[c] = true
	var out: Array = []
	for _m: int in JUNK_MODELS.size():
		out.append(PackedFloat32Array())
	var total: int = 0
	for c: int in _junk_ring:
		var j: float = planet.junk[c] if planet.state[c] == PlanetData.State.JUNK else 0.0
		_junk_shown[c] = j
		if j <= 0.02:
			continue
		var bufs: Array = _cell_junk(c)
		for m: int in bufs.size():
			var b: PackedFloat32Array = bufs[m]
			@warning_ignore("integer_division")
			var n: int = int(round(b.size() / 12 * j))
			if n > 0:
				var o: PackedFloat32Array = out[m]
				o.append_array(b.slice(0, n * 12))
				out[m] = o
				total += n
	for m: int in _junk_mms.size():
		var mm: MultiMesh = _junk_mms[m].multimesh
		var o: PackedFloat32Array = out[m]
		mm.instance_count = 0
		@warning_ignore("integer_division")
		mm.instance_count = o.size() / 12
		if o.size() > 0:
			mm.buffer = o
	stats["junk_instances"] = total
	stats["junk_rebuild_ms"] = Time.get_ticks_msec() - t0


# --- Robots -----------------------------------------------------------------------------

func _spawn_bots(hub: int, n: int) -> void:
	var around: PackedInt32Array = globe.cells_around(hub, 1)
	for i: int in n:
		var b := OrbitBot.new()
		b.name = "Bot%d" % i
		add_child(b)
		b.setup(self, around[(i + 1) % around.size()], hub, ["scoopie", "haulbug", "scoopie", "scoopie"][i % 4])
		bots.append(b)


## Nearest dirty, unclaimed land cell within `rings` of the hub, searched outward from `from`.
func claim_dirty(from: int, hub: int, rings: int) -> int:
	var lim: float = (rings + 0.5) * globe.cell_angle() * 1.75
	var hd: Vector3 = globe.grid.centers[hub]
	var seen: Dictionary = {from: true}
	var front := PackedInt32Array([from])
	while not front.is_empty():
		var nxt := PackedInt32Array()
		for c: int in front:
			if globe.is_dirty(c) and not _claimed.has(c):
				_claimed[c] = true
				return c
			for j: int in globe.grid.neighbors(c):
				if not seen.has(j) and globe.grid.centers[j].angle_to(hd) < lim:
					seen[j] = true
					nxt.append(j)
		front = nxt
	return -1


func release(c: int) -> void:
	_claimed.erase(c)


## BFS shortest path on the hex graph (cell ids after `from`, ending at `to`). Land and water
## are both passable here (Lumi wades); the real game would add costs.
func path(from: int, to: int) -> PackedInt32Array:
	var prev: Dictionary = {from: -1}
	var front := PackedInt32Array([from])
	var td: Vector3 = globe.grid.centers[to]
	var max_ang: float = globe.grid.centers[from].angle_to(td) + globe.cell_angle() * 6.0
	while not front.is_empty() and not prev.has(to):
		var nxt := PackedInt32Array()
		for c: int in front:
			for j: int in globe.grid.neighbors(c):
				if not prev.has(j) and globe.grid.centers[j].angle_to(td) < max_ang:
					prev[j] = c
					nxt.append(j)
		front = nxt
	var out := PackedInt32Array()
	var cur: int = to
	while cur != from and prev.has(cur):
		out.insert(0, cur)
		cur = prev[cur]
	return out


func work_cell(c: int, left: float) -> void:
	globe.set_cell(c, left)
	if _junk_ring_set.has(c) and absf(float(_junk_shown.get(c, 1.0)) - maxf(left, 0.0)) > 0.08:
		_junk_dirty = true


## Far crews: no nodes, no physics. Each clears whole cells around its hub at `rate` cells per
## minute, nearest first (the same shape as Offline.compute, per hub).
func _tick_crews(dt: float) -> void:
	for cr: Dictionary in crews:
		cr["acc"] = float(cr["acc"]) + float(cr["rate"]) * dt / 60.0
		while float(cr["acc"]) >= 1.0:
			cr["acc"] = float(cr["acc"]) - 1.0
			var c: int = claim_dirty(int(cr["hub"]), int(cr["hub"]), 14)
			if c < 0:
				break
			globe.set_cell(c, 0.0)
			release(c)


func _presim_crews(seconds: float) -> void:
	for i: int in range(0, hubs.size()):
		crews.append({"hub": hubs[i], "rate": 0.5 + 0.1 * (i % 4), "acc": 0.0})
	_tick_crews(seconds)
	crews.clear()


# --- Start base ---------------------------------------------------------------------------

## A small base and ruined blocks around the start hub, every piece set on the sphere with its
## own up (what StreetDressing / CityView would do through a hub chart).
func _build_base(hub: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = planet.seed_value + 17
	var wall: StandardMaterial3D = AssetLib.pbr_material("concrete_wall_008", 0.22, Color(0.85, 0.8, 0.74), true)
	var brick: StandardMaterial3D = AssetLib.pbr_material("red_brick", 0.3, Color(0.8, 0.72, 0.68), true)
	var slab_m: StandardMaterial3D = AssetLib.pbr_material("concrete_pavement", 0.2, Color(0.9, 0.9, 0.88), true)
	_box(hub, Vector3(0, 0, 0), Vector3(16, 0.25, 16), slab_m, false)  # yard slab
	_box(hub, Vector3(-4.5, 0, -4.0), Vector3(3.4, 2.4, 2.2), wall, true)  # lean-to
	if AssetLib.has_model("street_lamp_01"):
		for p: Vector2 in [Vector2(4.2, -3.0), Vector2(-7, 7), Vector2(7, 7)]:
			_model(hub, "street_lamp_01", Vector3(p.x, 0, p.y), 0.0)
	const PITCH: float = 36.0
	# Blocks centred between the streets; streets run along both axes through the yard.
	for bx: int in range(-3, 3):
		for bz: int in range(-3, 3):
			if rng.randf() < 0.25:
				continue
			var cx: float = (bx + 0.5) * PITCH
			var cz: float = (bz + 0.5) * PITCH
			for k: int in rng.randi_range(1, 3):
				var w: float = rng.randf_range(7.0, 12.0)
				var dpt: float = rng.randf_range(7.0, 11.0)
				var h: float = rng.randf_range(5.0, 19.0) * (0.6 if rng.randf() < 0.4 else 1.0)
				var ox: float = rng.randf_range(-4.0, 4.0)
				var oz: float = rng.randf_range(-4.0, 4.0)
				_box(hub, Vector3(cx + ox, 0, cz + oz), Vector3(w, h, dpt), wall if rng.randf() < 0.6 else brick, true)


func _box(hub: int, local: Vector3, size: Vector3, mat: Material, collide: bool) -> void:
	var d: Vector3 = planet.local_to_dir(hub, local.x, local.z)
	var f: Basis = _hub_basis(hub, d)
	var p: Vector3 = globe.ground(d) - d * 0.4
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size + Vector3(0, 0.4, 0)
	mi.mesh = bm
	mi.material_override = mat
	var xf := Transform3D(f, p + d * (size.y + 0.4) * 0.5)
	add_child(mi)
	mi.global_transform = xf
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		sb.add_child(cs)
		add_child(sb)
		sb.global_transform = xf


func _model(hub: int, id: String, local: Vector3, yaw: float) -> void:
	var d: Vector3 = planet.local_to_dir(hub, local.x, local.z)
	var mi := MeshInstance3D.new()
	mi.mesh = AssetLib.model_mesh(id)
	add_child(mi)
	mi.global_transform = Transform3D(Basis(d, yaw) * _hub_basis(hub, d), globe.ground(d))


## The hub chart's east/south carried to point d (so blocks stay square to the streets).
func _hub_basis(hub: int, d: Vector3) -> Basis:
	var hf: Basis = OrbitGlobe.frame(globe.grid.centers[hub])
	var q := Quaternion(hf.y, d)
	return (Basis(q) * hf).orthonormalized()


# --- Lap test + trail -------------------------------------------------------------------

func _lap_tick(delta: float) -> void:
	if not _lap_on or _lap_done:
		return
	_lap_t += delta
	if int(_lap_t / 20.0) != int((_lap_t - delta) / 20.0):
		print("[orbit] t=%.0fs walked=%.0fm floor=%s v=%.2f cell=%d chunks=%d queue=%d fps=%d" % [_lap_t, walker.distance, str(walker.is_on_floor()),
			walker.velocity.length(), _walker_cell, _chunks.size(), _chunk_queue.size(), Engine.get_frames_per_second()])
	_trail_d += walker.velocity.length() * delta
	if _trail_d > 12.0:
		_trail_d = 0.0
		var p: Vector3 = walker.global_position
		_trail.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	var circ: float = TAU * globe.R
	if walker.distance > circ * 0.8:
		var dd: float = walker.global_position.distance_to(_lap_start)
		if dd < _lap_min:
			_lap_min = dd
		elif dd > _lap_min + 15.0:
			_lap_done = true
			var p0: Vector3 = _lap_start
			_trail.append([p0.x, p0.y, p0.z])
			print("[orbit] LAP walked=%.0fm circumference=%.0fm game_time=%.0fs (%.1f min) closest_to_start=%.1fm %s" % [
				walker.distance, circ, _lap_t, _lap_t / 60.0, _lap_min, "PASS" if _lap_min < 12.0 else "FAIL"])
			var abs_path: String = ProjectSettings.globalize_path(LAP_PATH)
			DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
			var fa := FileAccess.open(abs_path, FileAccess.WRITE)
			if fa:
				fa.store_string(JSON.stringify({"trail": _trail, "R": globe.R, "time_s": _lap_t, "closest": _lap_min}))
			if DevHooks.has("orbit-lap-quit"):
				get_tree().quit(0 if _lap_min < 12.0 else 1)


func _draw_trail() -> void:
	var abs_path: String = ProjectSettings.globalize_path(LAP_PATH)
	if not FileAccess.file_exists(abs_path):
		push_warning("orbit: no lap trail at %s (run --orbit-walk first)" % abs_path)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
	if not (d is Dictionary):
		return
	var pts: Array = (d as Dictionary).get("trail", [])
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 1.0, 0.95)
	var seg := CylinderMesh.new()
	seg.top_radius = 4.0
	seg.bottom_radius = 4.0
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
		a += a.normalized() * 3.0
		b += b.normalized() * 3.0
		var y: Vector3 = (b - a)
		var x: Vector3 = y.cross(a).normalized()
		var z: Vector3 = x.cross(y.normalized())
		mm.set_instance_transform(i, Transform3D(Basis(x, y, z), (a + b) * 0.5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	# "You are here": a tall marker over Lumi for the orbit view.
	var mk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 0.5
	cyl.height = 90.0
	mk.mesh = cyl
	var mm2 := StandardMaterial3D.new()
	mm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm2.albedo_color = Color(1.0, 0.8, 0.35)
	mk.material_override = mm2
	add_child(mk)
	var u: Vector3 = walker.global_position.normalized()
	mk.global_transform = Transform3D(OrbitGlobe.frame(u), walker.global_position + u * 45.0)


# --- Loop -------------------------------------------------------------------------------

func _build_hud() -> void:
	if DevHooks.has("orbit-nohud") or DevHooks.has("no-hud"):
		return
	var cl := CanvasLayer.new()
	add_child(cl)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	cl.add_child(_hud)


func _physics_process(delta: float) -> void:
	_lap_tick(delta)


var _perf_acc: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _perf_n: int = 0


func _perf_tick(delta: float) -> void:
	_perf_acc[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_perf_acc[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf_acc[2] = maxf(_perf_acc[2], Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_perf_acc[3] += delta
	_perf_n += 1
	if _perf_acc[3] >= 5.0 * Engine.time_scale:
		print("[orbit-perf] process_ms avg=%.2f max=%.2f physics_ms avg=%.2f chunks=%d built=%d chunk_build_avg_ms=%.0f junk=%d junk_rebuild_ms=%d draw_calls=%d prims=%d" % [
			_perf_acc[0] / _perf_n, _perf_acc[2], _perf_acc[1] / _perf_n, _chunks.size(), int(stats.get("chunks_built", 0)),
			float(stats.get("chunk_ms_sum", 0.0)) / maxf(1.0, float(stats.get("chunks_built", 1))), int(stats.get("junk_instances", 0)),
			int(stats.get("junk_rebuild_ms", 0)),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		_perf_acc = [0.0, 0.0, 0.0, 0.0]
		_perf_n = 0


func _process(delta: float) -> void:
	_perf_tick(delta)
	_orient_sky()
	var c: int = globe.cell_at(walker.global_position, _walker_cell)
	if c != _walker_cell:
		_walker_cell = c
		_junk_dirty = true
	_stream_t -= delta
	if _stream_t <= 0.0:
		_stream_t = 0.5
		_queue_chunks()
	if not _chunk_queue.is_empty():
		var ch: int = _chunk_queue[0]
		_chunk_queue.remove_at(0)
		_load_chunk(ch)
	if _junk_dirty:
		_junk_dirty = false
		_rebuild_junk()
	_tick_crews(delta)
	globe.flush()
	if _hud:
		var cleaned: int = 0
		for b: OrbitBot in bots:
			cleaned += b.cleaned
		_hud.text = "orbit prototype  R %.0f m  hexes %d  walked %.0f / %.0f m  cell %d  chunks %d  junk %d  bots cleaned %d  fps %d" % [
			globe.R, planet.cell_count(), walker.distance, TAU * globe.R, _walker_cell, _chunks.size(),
			int(stats.get("junk_instances", 0)), cleaned, Engine.get_frames_per_second()]
