class_name FutureLayerSphere
extends Node3D
## [orbE] The Future Layer on a round planet: per cell from SphereCells.level (4 bits; the flat
## HexLevels scale 0..5, higher values clamp to Thriving), drawn on the streamer's full-detail
## chunks near the camera. Each loaded LOD-0 chunk gets one small MultiMesh per channel built from
## the same per-hex plan as the flat layer (FutureLayer.plan_hex_at in the cell's tangent frame),
## so the look matches: thin light seams, centre orbs, seed-lanterns, holo way-signs on white
## posts, hover platforms and floating halo rings on Thriving cells. A cell whose level changes
## rebuilds only its chunk (new pieces draw in). No save data: everything derives from the cells.
## District-wide pieces (skyline, aurora, traffic) wait for the hub sites (phase D).

const CHANNELS: Array[String] = ["line", "orb", "sign", "post", "planter", "platform"]

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var streamer: SphereStreamer
var eye_fn: Callable  # () -> Vector3 camera position
var sky: Node  # SkyDirector: clear_bonus / night_tint hooks, like the flat layer
var range_m: float = 320.0  # chunks farther than this from the camera drop their pieces (OrbitQuality)
var hex_r: float = 5.8  # centre-to-corner (m), measured from the grid
var stats: Dictionary = {"chunks": 0, "pieces": 0, "build_us_max": 0}
var _mats: Dictionary = {}
var _meshes: Dictionary = {}
var _chunks: Dictionary = {}  # chunk -> Node3D
var _queue: Dictionary = {}  # chunk -> true (needs a (re)build)
var _known: Dictionary = {}  # piece key -> birth time on _clock
var _clock: float = 0.0
var _poll: float = 0.0
var _score: float = 0.0
var _seen := PackedByteArray()  # level last drawn per cell


func setup(p_grid: SphereGrid, p_terrain: SphereTerrain, p_cells: SphereCells, p_streamer: SphereStreamer) -> void:
	grid = p_grid
	terrain = p_terrain
	cells = p_cells
	streamer = p_streamer
	hex_r = float(grid.hex_metrics().get("corner_m", 5.8))
	_seen.resize(cells.n)
	for i: int in cells.n:
		_seen[i] = show_level(cells.level[i])
	_make_resources()
	streamer.chunk_ready.connect(_on_chunk_ready)
	cells.cell_changed.connect(_on_cell_changed)


func _make_resources() -> void:
	var light := ShaderMaterial.new()
	light.shader = preload("res://art/shaders/light_seam.gdshader")
	var holo := ShaderMaterial.new()
	holo.shader = preload("res://art/shaders/holo_sign.gdshader")
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.94, 0.96, 0.98)
	white.roughness = 0.22
	white.metallic = 0.05
	white.rim_enabled = true
	white.rim = 0.25
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats = {"light": light, "holo": holo, "white": white}
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_meshes = {"line": BoxMesh.new(), "orb": ProcMesh.sphere(0.5, 12, 6), "sign": quad,
		"post": ProcMesh.cyl(0.5, 0.5, 1.0, 8), "planter": FutureLayer.hex_ring_mesh(0.5, 0.38, 0.2),
		"platform": FutureLayer.hex_prism_mesh(1.0, 1.0, 0.18)}


func _mat_for(ch: String) -> Material:
	return _mats[str(FutureLayer.CHANNELS[ch][1])]


## The level the layer shows for a cell (SphereCells.level is 0..15; the look tops out at 5).
static func show_level(raw: int) -> int:
	return clampi(raw, 0, 5)


## Two planter spots per cell (no garden on the globe yet), deterministic, in tangent metres.
static func cell_slots(cell: int, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k: int in 2:
		var a: float = FutureLayer._h(cell, k, 61) * TAU
		var d: float = r * (0.42 + 0.12 * FutureLayer._h(cell, k, 62))
		out.append(Vector3(cos(a) * d, 0.0, sin(a) * d))
	return out


## Plan one cell in its tangent frame (x east, y up, z south; origin on the cell centre).
static func plan_cell(cell: int, lv: int, r: float) -> Dictionary:
	var p: Dictionary = FutureLayer._new_plan()
	if lv <= 0:
		return p
	FutureLayer.plan_hex_at(p, null, cell, lv, cell_slots(cell, r), Vector3.ZERO, r)
	if lv >= 5:
		_plan_thriving_cell(p, cell, r)
	return p


## Thriving: a hover platform with a lit rim, or a floating halo ring (the flat layer's pieces).
static func _plan_thriving_cell(p: Dictionary, cell: int, r: float) -> void:
	if FutureLayer._h(cell, 40) < 0.24:
		var pc := Vector3(0, 3.8 + 1.6 * FutureLayer._h(cell, 41), 0)
		FutureLayer._add(p, "platform", Transform3D(Basis.from_scale(Vector3(1.25, 1.0, 1.25)), pc), Color.WHITE, 0.0, 1.0, FutureLayer._key(12, cell))
		for e: int in 6:
			FutureLayer._add(p, "line", FutureLayer.seg_xf(FutureLayer.corner(pc, 1.3, e) + Vector3(0, 0.02, 0), FutureLayer.corner(pc, 1.3, e + 1) + Vector3(0, 0.02, 0), 0.05, 0.05),
				FutureLayer.CYAN, FutureLayer.K_PULSE, 3.0, FutureLayer._key(13, cell, e))
		FutureLayer._add(p, "orb", FutureLayer._orb_xf(pc - Vector3(0, 0.16, 0), 1.6, 0.06), FutureLayer.CYAN, FutureLayer.K_STEADY, 2.0, FutureLayer._key(14, cell))
	elif FutureLayer._h(cell, 51) < 0.5:
		var hc := Vector3((FutureLayer._h(cell, 53) - 0.5) * r * 0.8, 2.6 + 1.2 * FutureLayer._h(cell, 52), (FutureLayer._h(cell, 54) - 0.5) * r * 0.8)
		var hseed: float = FutureLayer._h(cell, 55) * 10.0
		var hcol: Color = FutureLayer.MAGENTA if FutureLayer._h(cell, 56) < 0.4 else FutureLayer.CYAN
		for e: int in 6:
			FutureLayer._add(p, "line", FutureLayer.seg_xf(FutureLayer.corner(hc, 0.75, e), FutureLayer.corner(hc, 0.75, e + 1), 0.05, 0.05), hcol, 6.0, 2.2, FutureLayer._key(21, cell, e), hseed)


## A cell's ground as a plane in its tangent frame: [frame, centre point, slope x, slope z].
## Four height samples per cell (centre and three around it) instead of one per piece: a chunk
## of Thriving cells went from 138 ms to a few ms. Within a 6 m hex the curvature drop is ~1 cm.
func cell_plane(cell: int) -> Array:
	var up: Vector3 = grid.centers[cell]
	var f: Basis = SphereGrid.frame(up)
	var hc: float = terrain.height(up)
	var d: float = hex_r * 0.6
	var a: float = 0.0
	var b: float = 0.0
	for k: int in 3:
		var th: float = TAU * k / 3.0
		var hk: float = terrain.height(terrain.local_to_dir(cell, cos(th) * d, sin(th) * d)) - hc
		a += hk * cos(th)
		b += hk * sin(th)
	return [f, up * (grid.radius_m + hc), a * 2.0 / (3.0 * d), b * 2.0 / (3.0 * d)]


## Tangent-frame transform of a cell -> world, on the cell's ground plane, lifted along its up.
static func to_world(plane: Array, t: Transform3D) -> Transform3D:
	var f: Basis = plane[0]
	var o: Vector3 = t.origin
	var lift: float = o.y + float(plane[2]) * o.x + float(plane[3]) * o.z
	return Transform3D(f * t.basis, (plane[1] as Vector3) + f.x * o.x + f.z * o.z + f.y * lift)


func _on_chunk_ready(c: int, lod: int) -> void:
	if lod == 0:
		_queue[c] = true
	elif _chunks.has(c):
		_drop(c)


func _on_cell_changed(i: int) -> void:
	# cell_changed also fires for junk, state and the streamer's near flags: only levels count.
	var lv: int = show_level(cells.level[i])
	if _seen[i] == lv:
		return
	_seen[i] = lv
	var c: int = grid.cell_chunk[i]
	if _chunks.has(c) or _job.get("c", -1) == c:
		_queue[c] = true


func _drop(c: int) -> void:
	(_chunks[c] as Node).queue_free()
	_chunks.erase(c)
	_queue.erase(c)


func _process(delta: float) -> void:
	_clock += delta
	(_mats["light"] as ShaderMaterial).set_shader_parameter("t_now", _clock)
	(_mats["holo"] as ShaderMaterial).set_shader_parameter("t_now", _clock)
	_poll += delta
	if _poll >= 1.0:
		_poll = 0.0
		_sweep()
	if _job.is_empty():
		for c: int in _queue.keys():
			_queue.erase(c)
			if streamer.loaded_lod(c) == 0:
				_job = _start_job(c)
				break
	if not _job.is_empty():
		var t0: int = Time.get_ticks_usec()
		if streamer.loaded_lod(int(_job["c"])) != 0:
			_job = {}
		elif _step_job(_job, BUDGET_US):
			_job = {}
		stats["build_us_max"] = maxi(int(stats["build_us_max"]), Time.get_ticks_usec() - t0)
	if sky:  # a built-up neighbourhood clears its own air and tints the night (as on the flat sky)
		sky.set("clear_bonus", smoothstep(0.2, 1.0, _score) * 0.7)
		sky.set("night_tint", Color(0.55, 0.62, 0.9, smoothstep(0.3, 1.0, _score) * 0.15))


## Drop chunks the streamer no longer holds at full detail or that are out of range.
func _sweep() -> void:
	var eye: Vector3 = eye_fn.call() if eye_fn.is_valid() else Vector3.ZERO
	for c: int in _chunks.keys():
		var far: bool = eye != Vector3.ZERO and grid.great_circle_m(eye, grid.centers[grid.chunk_cells[grid.chunk_start[c]]]) > range_m + grid.chunk_radius[c] * grid.radius_m
		if streamer.loaded_lod(c) != 0 or far:
			_drop(c)
	var sum: float = 0.0
	var cnt: int = 0
	for c: int in _chunks:
		for i: int in grid.cells_in_chunk(c):
			if cells.level[i] > 0:
				sum += float(show_level(cells.level[i]))
				cnt += 1
	_score = clampf(sum / maxf(float(cnt), 1.0) / 5.0 * clampf(float(cnt) / 60.0, 0.0, 1.0), 0.0, 1.0)
	stats["chunks"] = _chunks.size()


## (Re)build one chunk's pieces from its cells' levels (all at once: tests and dev tools).
func build_chunk(c: int) -> void:
	var job: Dictionary = _start_job(c)
	while not _step_job(job, 1000000):
		pass


## Builds run a few cells per frame within BUDGET_US, then the chunk's MultiMeshes swap in.
const BUDGET_US: int = 2500
var _job: Dictionary = {}


func _start_job(c: int) -> Dictionary:
	var bufs: Dictionary = {}
	var counts: Dictionary = {}
	for ch: String in CHANNELS:
		bufs[ch] = PackedFloat32Array()
		counts[ch] = 0
	return {"c": c, "cells": grid.cells_in_chunk(c), "idx": 0, "bufs": bufs, "counts": counts, "us": 0,
		"origin": grid.centers[grid.chunk_cells[grid.chunk_start[c]]] * grid.radius_m,
		"fresh": _clock if _chunks.has(c) else -100.0}  # first sight: no draw-in; a level-up: draw in


## Advance a build by up to budget_us; true when the chunk has been swapped in.
func _step_job(job: Dictionary, budget_us: int) -> bool:
	var t0: int = Time.get_ticks_usec()
	var list: PackedInt32Array = job["cells"]
	var bufs: Dictionary = job["bufs"]
	var counts: Dictionary = job["counts"]
	var origin: Vector3 = job["origin"]
	var fresh: float = job["fresh"]
	var idx: int = job["idx"]
	while idx < list.size() and Time.get_ticks_usec() - t0 < budget_us:
		var i: int = list[idx]
		idx += 1
		var lv: int = show_level(cells.level[i])
		if lv <= 0:
			continue
		var ta: int = Time.get_ticks_usec()
		var p: Dictionary = plan_cell(i, lv, hex_r)
		var tb: int = Time.get_ticks_usec()
		var plane: Array = cell_plane(i)
		var tc: int = Time.get_ticks_usec()
		stats["plan_us"] = int(stats.get("plan_us", 0)) + tb - ta
		stats["plane_us"] = int(stats.get("plane_us", 0)) + tc - tb
		for ch: String in CHANNELS:
			var d: Dictionary = p[ch]
			var xfs: Array = d["xf"]
			if xfs.is_empty():
				continue
			var buf: PackedFloat32Array = bufs[ch]
			bufs[ch] = PackedFloat32Array()  # drop the dictionary's reference: resize in place, no copy
			var o: int = buf.size()
			buf.resize(o + xfs.size() * 20)
			for k: int in xfs.size():
				var key: int = d["key"][k]
				if not _known.has(key):
					_known[key] = fresh
				var t: Transform3D = to_world(plane, xfs[k])
				t.origin -= origin
				_write(buf, o + k * 20, t, d["col"][k], d["cus"][k], float(_known[key]))
			bufs[ch] = buf
			counts[ch] = int(counts[ch]) + xfs.size()
	job["idx"] = idx
	job["us"] = int(job["us"]) + Time.get_ticks_usec() - t0
	if idx < list.size():
		return false
	_finish_job(job)
	return true


func _finish_job(job: Dictionary) -> void:
	var t0: int = Time.get_ticks_usec()
	var c: int = job["c"]
	var bufs: Dictionary = job["bufs"]
	var counts: Dictionary = job["counts"]
	var node: Node3D = _chunks.get(c)
	if node == null:
		node = Node3D.new()
		node.name = "FutureChunk%d" % c
		add_child(node)
		_chunks[c] = node
	node.position = job["origin"]
	var total: int = 0
	for ch: String in CHANNELS:
		var n: int = counts[ch]
		total += n
		var mmi: MultiMeshInstance3D = node.get_node_or_null(ch) as MultiMeshInstance3D
		if n == 0:
			if mmi:
				mmi.queue_free()
			continue
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.name = ch
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _meshes[ch]
			mmi.multimesh = mm
			mmi.material_override = _mat_for(ch)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(FutureLayer.CHANNELS[ch][2]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mmi)
		mmi.multimesh.instance_count = n
		mmi.multimesh.buffer = bufs[ch]
	node.set_meta("pieces", total)
	var pieces: int = 0
	for k: int in _chunks:
		pieces += int((_chunks[k] as Node).get_meta("pieces", 0))
	stats["pieces"] = pieces
	stats["chunks"] = _chunks.size()
	stats["build_us_total_max"] = maxi(int(stats.get("build_us_total_max", 0)), int(job["us"]))
	stats["swap_us_max"] = maxi(int(stats.get("swap_us_max", 0)), Time.get_ticks_usec() - t0)


static func _write(buf: PackedFloat32Array, o: int, t: Transform3D, col: Color, cu: Color, born: float) -> void:
	buf[o] = t.basis.x.x
	buf[o + 1] = t.basis.y.x
	buf[o + 2] = t.basis.z.x
	buf[o + 3] = t.origin.x
	buf[o + 4] = t.basis.x.y
	buf[o + 5] = t.basis.y.y
	buf[o + 6] = t.basis.z.y
	buf[o + 7] = t.origin.y
	buf[o + 8] = t.basis.x.z
	buf[o + 9] = t.basis.y.z
	buf[o + 10] = t.basis.z.z
	buf[o + 11] = t.origin.z
	buf[o + 12] = col.r
	buf[o + 13] = col.g
	buf[o + 14] = col.b
	buf[o + 15] = col.a
	buf[o + 16] = cu.r
	buf[o + 17] = cu.g
	buf[o + 18] = cu.b
	buf[o + 19] = born


## Dev (--orbit-future[=N]): restoration levels in rings around a cell, highest in the middle,
## so the layer can be seen (and timed) before the hex-level flow lands on the globe.
static func dev_seed(p_cells: SphereCells, p_grid: SphereGrid, centre: int, rings: int) -> int:
	var n: int = 0
	var ring_of: Dictionary = {centre: 0}
	var frontier: Array[int] = [centre]
	for k: int in range(1, rings + 1):
		var nxt: Array[int] = []
		for c: int in frontier:
			for j: int in p_grid.neighbors(c):
				if j >= 0 and not ring_of.has(j):
					ring_of[j] = k
					nxt.append(j)
		frontier = nxt
	for c: int in ring_of:
		@warning_ignore("integer_division")
		var lv: int = clampi(5 - int(ring_of[c]) * 5 / maxi(rings, 1) + (1 if FutureLayer._h(c, 77) < 0.3 else 0), 0, 5)
		if lv > 0 and p_cells.state[c] != 5:
			p_cells.set_level(c, lv)
			n += 1
	return n
