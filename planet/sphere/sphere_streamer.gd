class_name SphereStreamer
extends Node3D
## [sgrid] Streams a SphereGrid planet's ground around a set of stream centres.
##
## - Chunks (~256 hexes, SphereGrid.CHUNK_DROP) are built on WorkerThreadPool (SphereChunkJob)
##   and applied on the main thread, at most `apply_per_frame` per frame.
## - LOD 0 (24 tris/hex, warped borders) within lod0_m of the view centre; LOD 1 (12 tris/hex)
##   out to the horizon (from the view altitude, plus the tallest hills behind it), capped at
##   lod1_m; past that the far shell (one coarse icosphere mesh reading the same state texture).
## - Collision (trimesh) only for chunks within collide_m of a physics centre (Lumi, robots).
## - The near ring: cells within near_m of the view centre (3D junk and other per-hex props
##   belong only there); near_changed(added, removed) fires when the ring moves.
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
var lod0_m: float = 240.0
var lod1_m: float = 2600.0
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
var shell_only_alt: float = 3000.0

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
var _near_cell: int = -1
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


func set_centre(key: Variant, pos: Vector3, kind: int = BODY) -> void:
	_centres[key] = {"pos": pos, "kind": kind}


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
func settle(max_ms: int = 20000) -> void:
	var t0: int = Time.get_ticks_msec()
	_update_wants()
	while (not _pending.is_empty() or not _jobs.is_empty()) and Time.get_ticks_msec() - t0 < max_ms:
		_pump(1000)
		OS.delay_usec(500)


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
			var far: float = minf(horizon, lod1_m)
			stats["horizon_m"] = horizon
			for c: int in grid.chunks_within(vd, far + hysteresis_m):
				var d: float = maxf(0.0, (grid.centers[c].angle_to(vd) - grid.chunk_radius[c]) * R)
				var cur: int = loaded_lod(c)
				var l0: float = lod0_m + (hysteresis_m if cur == 0 else 0.0)
				var l1: float = far + (hysteresis_m if cur >= 0 else 0.0)
				if d < l0:
					want[c] = 0
				elif d < l1:
					want[c] = 1
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
		var d: float = (grid.centers[c].angle_to(p.normalized()) - grid.chunk_radius[c]) * terrain.R
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
	# Near ring around the view centre.
	for key: Variant in _centres:
		var cc: Dictionary = _centres[key]
		if int(cc["kind"]) == VIEW:
			_update_near(cc["pos"])
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
	order.sort_custom(func(a: int, b: int) -> bool: return grid.centers[a].dot(vd) > grid.centers[b].dot(vd))
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
		m.set_shader_parameter("lod_color", Vector3(1.0, 0.75, 0.75) if job.lod == 0 else Vector3(0.75, 0.85, 1.0))
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
	var nc: int = 0
	var tri: int = 0
	for c: int in _chunks:
		var ch: Dictionary = _chunks[c]
		if int(ch["lod"]) == 0:
			n0 += 1
		else:
			n1 += 1
		if ch["body"] != null:
			nc += 1
		tri += int(ch["tris"])
	stats["lod0"] = n0
	stats["lod1"] = n1
	stats["collide"] = nc
	stats["chunk_tris"] = tri
	stats["jobs"] = _jobs.size()
	stats["pending"] = _pending.size()
	stats["near"] = _near.size()


# --- Near ring ----------------------------------------------------------------------------

func _update_near(pos: Vector3) -> void:
	var cell: int = grid.cell_at_from(pos, _view_cell)
	_view_cell = cell
	if cell == _near_cell:
		return
	_near_cell = cell
	var nw: PackedInt32Array = PackedInt32Array()
	if terrain.altitude(pos) < near_m * 2.0:
		nw = grid.cells_within(pos, near_m, cell)
	var nset: Dictionary = {}
	var added := PackedInt32Array()
	for c: int in nw:
		nset[c] = true
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

## The whole planet at low detail: the level-`shell_level` icosphere (vertex i is cell i of the
## fine grid, so it reads the state texture directly), heights from the terrain, sunk a little
## so chunks always cover it.
func _build_shell() -> void:
	var lv: int = mini(shell_level, grid.level)
	var g: SphereGrid = SphereGrid.cached(lv)
	var n: int = g.cell_count()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	v.resize(n)
	nr.resize(n)
	uv.resize(n)
	for i: int in n:
		var d: Vector3 = g.centers[i]
		var h: float = terrain.height(d)
		if cells.state[i] == SphereChunkJob.WATER:
			h -= terrain.water_drop
		v[i] = d * (terrain.R + h - shell_drop)
		nr[i] = d
		uv[i] = Vector2(float(i), float(i))
	var idx := PackedInt32Array()
	idx.resize(g.tris.size())
	for t: int in range(0, g.tris.size(), 3):  # CCW from outside -> Godot's clockwise front faces
		idx[t] = g.tris[t]
		idx[t + 1] = g.tris[t + 2]
		idx[t + 2] = g.tris[t + 1]
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV2] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _shell == null:
		_shell = MeshInstance3D.new()
		_shell.name = "FarShell"
		_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shell)
	_shell.mesh = am
	if shell_material == null:
		shell_material = material.duplicate()
		shell_material.set_shader_parameter("far_shell", 1.0)
	_shell.material_override = shell_material
	stats["shell_tris"] = idx.size() / 3
