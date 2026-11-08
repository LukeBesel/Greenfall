class_name SphereStreamer
extends Node3D
## [sgrid] Streams a SphereGrid planet's ground around a set of stream centres.
##
## - Chunks (~256 hexes, SphereGrid.CHUNK_DROP) are built on WorkerThreadPool (SphereChunkJob)
##   and applied on the main thread, at most `apply_per_frame` per frame.
## - LOD 0 (24 tris/hex, warped borders) within lod0_m of the view centre, LOD 1 (12 tris/hex)
##   within lod1_m, LOD 2 (6 tris/hex) out to the horizon (from the view altitude, plus the
##   tallest hills behind it), capped at far_m; past that, and for any view higher than
##   shell_only_alt, the far shell (one coarse icosphere mesh reading the same state texture).
## - Collision (trimesh) only for chunks within collide_m of a physics centre (Lumi, robots).
## - The near ring: cells within near_m of the view centre and of every body (3D junk and other
##   per-hex props belong only there); near_changed(added, removed) fires when it moves.
##
## Centres: set_centre(key, world_pos, kind) with kind VIEW (camera: picks LOD and the near ring)
## or BODY (collision only). remove_centre(key) when a robot goes away.

signal near_changed(added: PackedInt32Array, removed: PackedInt32Array)
signal chunk_ready(chunk: int, lod: int)

enum { VIEW = 1, BODY = 2 }

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var material: ShaderMaterial
var shell_material: ShaderMaterial
var shell: SphereShell
## Optional PlanetData.city for the fine grid (set before setup) so cities read on the shell.
var shell_city := PackedInt32Array()
var lod0_m: float = 240.0
var lod1_m: float = 650.0
var far_m: float = 2000.0
var collide_m: float = 70.0
var near_m: float = 70.0
var hysteresis_m: float = 40.0
var max_jobs: int = 4
var apply_per_frame: int = 2
var update_every: float = 0.15
var outlines: bool = false:
	set(v):
		outlines = v
		for c: int in _chunks:
			_queue(c, (_chunks[c] as Dictionary)["lod"])
var lod_debug: bool = false
var shell_level: int = 5
var shell_drop: float = 3.0
## When the view is this high (m above ground), only the far shell is drawn.
var shell_only_alt: float = 1500.0

var stats: Dictionary = {}
var _centres: Dictionary = {}  # key -> {pos, kind}
var _chunks: Dictionary = {}   # chunk -> {lod, stamp, node, mesh_i, body, lines}
var _jobs: Dictionary = {}     # chunk -> {job, task}
var _pending: Dictionary = {}  # chunk -> lod (queued, not started)
var _stamp: int = 0
var _t: float = 0.0
var _warp: Array = []
var _shell: MeshInstance3D
var _line_mat: StandardMaterial3D
var _near := PackedInt32Array()
var _near_set: Dictionary = {}
var _near_keys: int = -1
var _view_cell: int = 0
var _want: Dictionary = {}


func setup(p_grid: SphereGrid, p_terrain: SphereTerrain, p_cells: SphereCells, p_mat: ShaderMaterial = null) -> void:
	grid = p_grid
	terrain = p_terrain
	cells = p_cells
	material = p_mat if p_mat else default_material(cells)
	for k: int in 3:
		var nz := FastNoiseLite.new()
		nz.seed = terrain.seed_value + 300 + k
		nz.frequency = 1.0 / 26.0
		_warp.append(nz)
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(0.55, 0.95, 1.0, 0.75)
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_shell()


static func default_material(p_cells: SphereCells) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://planet/sphere/sphere_ground.gdshader")
	m.set_shader_parameter("state_tex", p_cells.texture)
	m.set_shader_parameter("state_w", SphereCells.TEX_W)
	m.set_shader_parameter("tex_dirt", AssetLib.tex("dry_ground_rocks", "diff"))
	m.set_shader_parameter("tex_rubble", AssetLib.tex("rubble", "diff"))
	m.set_shader_parameter("tex_clean", AssetLib.tex("dirty_concrete", "diff"))
	m.set_shader_parameter("tex_grass", AssetLib.tex("sparse_grass", "diff"))
	return m


## ring_m: radius of this centre's near ring (-1 = near_m, 0 = none).
func set_centre(key: Variant, pos: Vector3, kind: int = BODY, ring_m: float = -1.0) -> void:
	var cc: Dictionary = _centres.get(key, {})
	if cc.is_empty():
		_centres[key] = cc
	cc["pos"] = pos
	cc["kind"] = kind
	if float(cc.get("ring_m", -1.0)) != ring_m:
		cc["ring_m"] = ring_m
		cc.erase("ring_key")


func remove_centre(key: Variant) -> void:
	_centres.erase(key)


func near_cells() -> PackedInt32Array:
	return _near


func is_near(cell: int) -> bool:
	return _near_set.has(cell)


func loaded_lod(chunk: int) -> int:
	return int((_chunks[chunk] as Dictionary)["lod"]) if _chunks.has(chunk) else -1


func has_collision(chunk: int) -> bool:
	return _chunks.has(chunk) and (_chunks[chunk] as Dictionary)["body"] != null


## Rebuild chunks (e.g. after a site was reserved, or water changed).
func rebuild(chunks: PackedInt32Array) -> void:
	for c: int in chunks:
		if _chunks.has(c):
			_queue(c, int((_chunks[c] as Dictionary)["lod"]))
	_rebuild_shell_later = true


var _rebuild_shell_later: bool = false


## Blocks until every wanted chunk is built (loading screens, tests, screenshots).
## [orbE] near_only: only the full-detail (LOD 0) and collision chunks block; mid-distance
## chunks are queued and stream in during the first seconds of play (the far shell covers them).
## Loading screens use it: Anvil's settle went from ~7-14 s to the near ring only.
func settle(max_ms: int = 20000, near_only: bool = false) -> void:
	var t0: int = Time.get_ticks_msec()
	_update_wants()
	stats["settle_wants_ms"] = Time.get_ticks_msec() - t0  # [orbE]
	var later: Dictionary = {}
	if near_only:
		for c: int in _pending.keys():
			if int(_pending[c]) > 0:
				later[c] = _pending[c]
				_pending.erase(c)
	while (not _pending.is_empty() or not _jobs.is_empty()) and Time.get_ticks_msec() - t0 < max_ms:
		_pump(1000)
		OS.delay_usec(500)
	stats["settle_loop_ms"] = Time.get_ticks_msec() - t0 - int(stats["settle_wants_ms"])  # [orbE]
	for c: int in later:
		if not _chunks.has(c) and not _jobs.has(c):
			_pending[c] = later[c]
	_count_stats()


func _process(delta: float) -> void:
	if grid == null:
		return
	_t += delta
	if _t >= update_every:
		_t = 0.0
		_update_wants()
	_pump(apply_per_frame)
	if _rebuild_shell_later and _jobs.is_empty():
		_rebuild_shell_later = false
		_build_shell()
	if shell:
		shell.update(delta)
	cells.flush()


func _exit_tree() -> void:
	for c: int in _jobs:
		WorkerThreadPool.wait_for_task_completion(int((_jobs[c] as Dictionary)["task"]))
	_jobs.clear()


# --- LOD selection ------------------------------------------------------------------------

## Desired LOD per chunk: 0, 1, or absent (shell only). Collision chunks are forced to LOD 0.
func desired() -> Dictionary:
	var want: Dictionary = {}
	var view_pos := Vector3.ZERO
	var have_view: bool = false
	for key: Variant in _centres:
		var c: Dictionary = _centres[key]
		if int(c["kind"]) == VIEW:
			view_pos = c["pos"]
			have_view = true
	var R: float = terrain.R
	if have_view:
		var vd: Vector3 = view_pos.normalized()
		var alt: float = maxf(2.0, terrain.altitude(view_pos))
		stats["view_alt"] = alt
		if alt < shell_only_alt:
			var hmax: float = terrain.macro_amp + terrain.detail_amp
			# Horizon from the eye, plus how far hills of height hmax stay visible behind it.
			var horizon: float = sqrt(2.0 * R * (alt + hmax) + alt * alt) + sqrt(2.0 * R * hmax * 2.0)
			var far: float = minf(horizon, far_m)
			stats["horizon_m"] = horizon
			for c: int in grid.chunks_within(vd, far + hysteresis_m):
				var d: float = maxf(0.0, (grid.chunk_center[c].angle_to(vd) - grid.chunk_radius[c]) * R)  # [orbB] chunk_center
				var cur: int = loaded_lod(c)
				var l0: float = lod0_m + (hysteresis_m if cur == 0 else 0.0)
				var l1: float = lod1_m + (hysteresis_m if cur == 1 else 0.0)
				var l2: float = far + (hysteresis_m if cur >= 0 else 0.0)
				if d < l0:
					want[c] = 0
				elif d < l1:
					want[c] = 1
				elif d < l2:
					want[c] = 2
	for key: Variant in _centres:
		var cc: Dictionary = _centres[key]
		var pd: Vector3 = (cc["pos"] as Vector3).normalized()
		if terrain.altitude(cc["pos"]) > collide_m * 2.0:
			continue
		var lim: float = collide_m + (hysteresis_m * 0.5)
		for c: int in grid.chunks_within(pd, lim):
			want[c] = 0
	return want


func _wants_collision(c: int) -> bool:
	for key: Variant in _centres:
		var cc: Dictionary = _centres[key]
		var p: Vector3 = cc["pos"]
		if terrain.altitude(p) > collide_m * 2.0:
			continue
		var d: float = (grid.chunk_center[c].angle_to(p.normalized()) - grid.chunk_radius[c]) * terrain.R  # [orbB] chunk_center
		if d < collide_m + hysteresis_m * 0.5:
			return true
	return false


func _update_wants() -> void:
	var want: Dictionary = desired()
	_want = want
	# Unload chunks no longer wanted.
	for c: int in _chunks.keys():
		if not want.has(c):
			_unload(c)
	for c: int in _pending.keys():
		if not want.has(c):
			_pending.erase(c)
	for c: int in want:
		var l: int = want[c]
		var coll: bool = _wants_collision(c)
		if _chunks.has(c):
			var ch: Dictionary = _chunks[c]
			if int(ch["lod"]) != l or (coll and ch["body"] == null):
				_queue(c, l)
			elif not coll and ch["body"] != null:
				(ch["body"] as Node).queue_free()
				ch["body"] = null
		elif not _jobs.has(c):
			_queue(c, l)
	_update_near_rings()
	_count_stats()


func _queue(c: int, l: int) -> void:
	_pending[c] = l


func _pump(max_apply: int) -> void:
	# Apply finished jobs.
	var applied: int = 0
	for c: int in _jobs.keys():
		if applied >= max_apply:
			break
		var j: Dictionary = _jobs[c]
		var task: int = j["task"]
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_jobs.erase(c)
			var job: SphereChunkJob = j["job"]
			if not _pending.has(c) and _want.has(c):
				_apply(job)
				applied += 1
	# Start new jobs, nearest first.
	if _pending.is_empty() or _jobs.size() >= max_jobs:
		return
	var vd: Vector3 = grid.centers[_view_cell]
	var order: Array = _pending.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return grid.chunk_center[a].dot(vd) > grid.chunk_center[b].dot(vd))  # [orbB]
	for c: int in order:
		if _jobs.size() >= max_jobs:
			break
		if _jobs.has(c):
			continue  # still building an older version; restarts when it lands
		var l: int = _pending[c]
		_pending.erase(c)
		_start(c, l)


func _start(c: int, l: int) -> void:
	_stamp += 1
	var job := SphereChunkJob.new()
	job.chunk = c
	job.lod = l
	job.stamp = _stamp
	job.grid = grid
	job.terrain = terrain
	job.state = cells.state  # copy-on-write snapshot
	job.warp = _warp
	job.want_collision = l == 0 and _wants_collision(c)
	job.want_outlines = outlines and l == 0
	var task: int = WorkerThreadPool.add_task(job.run, false, "sphere chunk")
	_jobs[c] = {"job": job, "task": task, "stamp": _stamp}


func _apply(job: SphereChunkJob) -> void:
	var t0: int = Time.get_ticks_usec()
	var c: int = job.chunk
	var ch: Dictionary = _chunks.get(c, {})
	if ch.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Chunk%d" % c
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		ch = {"lod": -1, "node": mi, "body": null, "lines": null, "tris": 0}
		_chunks[c] = ch
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = job.verts
	arr[Mesh.ARRAY_NORMAL] = job.normals
	arr[Mesh.ARRAY_TEX_UV2] = job.uv2
	arr[Mesh.ARRAY_INDEX] = job.indices
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi2: MeshInstance3D = ch["node"]
	mi2.mesh = am
	mi2.material_override = material
	if lod_debug:
		var m: ShaderMaterial = material.duplicate()
		m.set_shader_parameter("lod_tint", 1.0)
		m.set_shader_parameter("lod_color", [Vector3(1.0, 0.7, 0.7), Vector3(0.7, 1.0, 0.75), Vector3(0.7, 0.8, 1.0)][job.lod])
		mi2.material_override = m
	ch["lod"] = job.lod
	ch["tris"] = job.indices.size() / 3
	# Collision
	if ch["body"] != null:
		(ch["body"] as Node).queue_free()
		ch["body"] = null
	if not job.faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "Collision"
		var cs := CollisionShape3D.new()
		var shp := ConcavePolygonShape3D.new()
		shp.backface_collision = true
		shp.set_faces(job.faces)
		cs.shape = shp
		body.add_child(cs)
		mi2.add_child(body)
		ch["body"] = body
	# Outlines
	if ch["lines"] != null:
		(ch["lines"] as Node).queue_free()
		ch["lines"] = null
	if not job.lines.is_empty():
		var la: Array = []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = job.lines
		var lm := ArrayMesh.new()
		lm.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
		var li := MeshInstance3D.new()
		li.name = "Outlines"
		li.mesh = lm
		li.material_override = _line_mat
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi2.add_child(li)
		ch["lines"] = li
	var us: int = Time.get_ticks_usec() - t0
	stats["built"] = int(stats.get("built", 0)) + 1
	stats["build_us_sum"] = int(stats.get("build_us_sum", 0)) + job.build_us
	stats["build_us_max"] = maxi(int(stats.get("build_us_max", 0)), job.build_us)
	stats["apply_us_sum"] = int(stats.get("apply_us_sum", 0)) + us
	stats["apply_us_max"] = maxi(int(stats.get("apply_us_max", 0)), us)
	chunk_ready.emit(c, job.lod)


func _unload(c: int) -> void:
	var ch: Dictionary = _chunks[c]
	(ch["node"] as Node).queue_free()
	_chunks.erase(c)


func _count_stats() -> void:
	var n0: int = 0
	var n1: int = 0
	var n2: int = 0
	var nc: int = 0
	var tri: int = 0
	for c: int in _chunks:
		var ch: Dictionary = _chunks[c]
		match int(ch["lod"]):
			0: n0 += 1
			1: n1 += 1
			_: n2 += 1
		if ch["body"] != null:
			nc += 1
		tri += int(ch["tris"])
	stats["lod0"] = n0
	stats["lod1"] = n1
	stats["lod2"] = n2
	stats["collide"] = nc
	stats["chunk_tris"] = tri
	stats["jobs"] = _jobs.size()
	stats["pending"] = _pending.size()
	stats["near"] = _near.size()


# --- Near ring ----------------------------------------------------------------------------

## Near ring = union of each centre's ring (cells within its ring_m, default near_m), so a robot
## working far from Lumi keeps its own junk ring. A centre higher than 2 x its ring_m has none.
func _update_near_rings() -> void:
	var changed: bool = false
	for key: Variant in _centres:
		var cc: Dictionary = _centres[key]
		var pos: Vector3 = cc["pos"]
		var rm: float = float(cc.get("ring_m", -1.0))
		if rm < 0.0:
			rm = near_m
		var hint: int = int(cc.get("cell", -1))
		var cell: int = grid.cell_at_from(pos, hint)
		cc["cell"] = cell
		if int(cc["kind"]) == VIEW:
			_view_cell = cell
		var low: bool = rm > 0.0 and terrain.altitude(pos) < rm * 2.0
		var k: int = cell if low else -2
		if cc.has("ring") and int(cc.get("ring_key", -3)) == k:
			continue
		cc["ring_key"] = k
		cc["ring"] = grid.cells_within(pos, rm, cell) if low else PackedInt32Array()
		changed = true
	if not changed and _near_keys == _centres.size():
		return
	_near_keys = _centres.size()
	var nset: Dictionary = {}
	var nw := PackedInt32Array()
	for key: Variant in _centres:
		for c: int in ((_centres[key] as Dictionary)["ring"] as PackedInt32Array):
			if not nset.has(c):
				nset[c] = true
				nw.append(c)
	var added := PackedInt32Array()
	for c: int in nw:
		if not _near_set.has(c):
			added.append(c)
	var removed := PackedInt32Array()
	for c: int in _near:
		if not nset.has(c):
			removed.append(c)
	_near = nw
	_near_set = nset
	if not added.is_empty() or not removed.is_empty():
		near_changed.emit(added, removed)


# --- Far shell ----------------------------------------------------------------------------

## The whole planet at low detail, as a map of big hexes (SphereShell): one flat-coloured hex
## per level-`shell_level` cell, coloured by the fine hexes it covers and refreshed as they
## change, heights from the terrain, sunk a little so chunks always cover it.
func _build_shell() -> void:
	if shell == null:
		shell = SphereShell.new(grid, cells, terrain, shell_level, shell_city)
		shell.drop = shell_drop
	var am: ArrayMesh = shell.build_mesh()
	if _shell == null:
		_shell = MeshInstance3D.new()
		_shell.name = "FarShell"
		_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shell)
	_shell.mesh = am
	if shell_material == null:
		shell_material = shell.make_material(material)
	_shell.material_override = shell_material
	stats["shell_tris"] = int(shell.stats["tris"])
	stats["shell_ms"] = int(shell.stats.get("map_ms", 0)) + int(shell.stats["mesh_ms"])
