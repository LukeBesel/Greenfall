class_name SphereLitter
extends LitterView
## [orbD] Ground litter on the walkable globe: the flat LitterView's carpet (crumpled paper,
## wrappers, film, cardboard scraps and tiny real items, the same meshes and colours) on junk cells,
## built only for the cells in the streamer's near ring and freed when they leave it. Same API, so
## Patch's scoop (sweep) and the slice's refresh calls work unchanged: the scoop sweeps a swath,
## partial cleaning thins a cell (each piece has a threshold), a clean cell has none. Any change to
## a cell (Lumi, robots, far crews) re-thins it through SphereCells.cell_changed.
## Per cell: one Node3D in the cell's surface frame with a MultiMesh per mesh, pieces seated on
## the terrain. Budget: PER_M2_Q pieces a square metre by quality (x density_mult). [v1world]

const PER_M2: float = 2.6  # [v1world] was the density for every preset; now PER_M2_Q
## [v1world] Pieces a square metre by quality (Low .. Ultra). The flat carpet lays ~20.
const PER_M2_Q: Array[float] = [8.0, 11.0, 14.0, 14.0]
const ITEM_RANGE: Array[float] = [35.0, 50.0, 60.0, 60.0]  # [v5load] metres, Low .. Ultra
const CARPET_RANGE: Array[float] = [60.0, 90.0, 90.0, 90.0]
const HG_N: int = 9  # height grid samples a side over the cell (2.25 m apart)
const BIN_M: float = 2.0  # [v1world] sweep bins (cell-frame metres)
const CELL_R: float = 9.0  # placement radius round the cell centre (10 m hexes overlap a little)

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var sfield: SphereField
## cell -> {node, mms, pos, thr, mm, slot, alive (per piece, packed), bins (2 m -> piece ids), inv, n}
var _cell: Dictionary = {}
var _pending: Array[int] = []
var _ready_meshes: bool = false
var build_max_ms: float = 0.0  # [v1world] slowest main-thread apply of a job (--litter-report)
const JOB_CELLS: int = 4  # [v1world] cells laid per worker job
var _near_now: Dictionary = {}  # [v1world] cells in the near ring now
var _job_cells := PackedInt32Array()
var _job_ctx: Dictionary = {}
var _job_out: Dictionary = {}

# [art3] The carpet as drifts of real litter (art overhaul, junk part). Same pieces in the same
# places with the same thresholds (sweep, thinning and counts are untouched); what changed is how
# they are drawn:
# - the four tinted paper quads are ONE mesh under art/shaders/litter_carpet.gdshader, each piece a
#   kind from a painted atlas (art/models/junk/build_litter.py: paper, newspaper, cardboard, film,
#   leaves, grit ...) with a torn outline in the alpha, so a cell is 4 draws, not 13;
# - kinds follow a slow noise over the ground: drifts of paper and cardboard, and between them
#   small dark stuff (leaves, grit, bits) so the ground shows;
# - the nine tiny scans are three meshes (the junk kit's bottle and can, a rusty tin);
# - with distance pieces drop out one by one while the rest grow and lean to the mean colour, so
#   the far carpet is a calm drift, not sparkle, and its range ends without a line.
## Kinds, in atlas order (4 x 4): [width m, length m, weight in a drift, weight in a gap].
const KINDS: Array = [
	[0.21, 0.30, 3.0, 0.25], [0.22, 0.22, 2.0, 0.3], [0.34, 0.44, 1.6, 0.1], [0.40, 0.34, 2.2, 0.15],
	[0.62, 0.50, 1.5, 0.04], [0.20, 0.16, 1.6, 0.5], [0.42, 0.36, 1.5, 0.15], [0.38, 0.32, 0.8, 0.12],
	[0.16, 0.11, 0.9, 0.5], [0.30, 0.30, 0.8, 2.4], [0.11, 0.08, 0.6, 2.6], [0.12, 0.07, 0.8, 0.5],
	[0.26, 0.26, 1.0, 2.2], [0.36, 0.28, 0.5, 0.08], [0.09, 0.24, 0.8, 0.3], [0.50, 0.50, 0.5, 2.0],
]
const ITEM_SLOTS: Array[int] = [1, 2, 1, 2, 3, 1, 2, 3, 1]  # the nine tiny-item draws -> bottle, can, tin
const LOGIC_MESHES: int = 13  # the piece stream still draws among 4 sheets + 9 items
const SHEET_TILT: float = 0.35  # share of the old tilt a (larger, flatter) sheet keeps
var _art: bool = false
var _litter_mat: ShaderMaterial


## Hooks onto a globe (OrbitPlanet: grid, terrain, cells, field, streamer).
func setup_globe(g: Node) -> void:
	grid = g.get("grid")
	terrain = g.get("terrain")
	cells = g.get("cells")
	sfield = g.get("field")
	field = sfield
	_rng.seed = 4471
	await _build_meshes()
	_ready_meshes = true
	var st: SphereStreamer = g.get("streamer")
	if st:
		st.near_changed.connect(_on_near)
		var near: Array[int] = []
		for c: int in cells.n:
			if cells.has_flag(c, SphereCells.F_NEAR):
				near.append(c)
		_on_near(PackedInt32Array(near), PackedInt32Array())
	cells.cell_changed.connect(func(c: int) -> void:
		if _cell.has(c):
			refresh_hex(c))


func _on_near(added: PackedInt32Array, removed: PackedInt32Array) -> void:
	for c: int in removed:
		_drop(c)
		_pending.erase(c)
		_near_now.erase(c)
	for c: int in added:
		_near_now[c] = true
		if not _cell.has(c) and not _pending.has(c):
			_pending.append(c)


## [v1world] Cells are laid on a WorkerThreadPool thread (placement, heights, colours, MultiMesh
## buffers), a few at a time; the main thread only makes the MultiMeshes from the buffers.
func _process(_delta: float) -> void:
	if not _ready_meshes:
		return
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var t0: int = Time.get_ticks_usec()
		for c: int in _job_out:
			if _near_now.has(c) and not _cell.has(c):
				_apply_cell(c, _job_out[c])
				refresh_hex(c)  # it may have been cleaned while its litter was laid
		build_max_ms = maxf(build_max_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		Hitch.mark("litter apply", t0 if Hitch.on else 0)
		_job_out = {}
	if _pending.is_empty():
		return
	_job_cells = PackedInt32Array()
	while not _pending.is_empty() and _job_cells.size() < JOB_CELLS:
		var c: int = _pending.pop_front()
		if _near_now.has(c) and not _cell.has(c) and cells.state[c] != 5 and cells.is_dirty(c) and sfield.hex_hub[c] == 0:
			_job_cells.append(c)
	if _job_cells.is_empty():
		return
	var q: int = clampi(Settings.quality, 0, 3)
	_job_ctx = {"q": q, "n_mesh": _meshes.size(), "rem": {}, "piles": {}}
	for c: int in _job_cells:  # field state read here, so the thread never reads what the game writes
		_job_ctx["rem"][c] = sfield.removed_fraction(c)
		_job_ctx["piles"][c] = (sfield.hex_piles[c] as Array).duplicate() if c < sfield.hex_piles.size() else []
	var kob: Object = sfield.keep_out.get_object() if sfield.keep_out.is_valid() else null
	if kob is YardKeepOut:  # [v1world] a copy for the worker (footprints may still be appended on the main thread)
		var yk: YardKeepOut = kob
		_job_ctx["ko"] = {"rects": yk.rects.duplicate(), "discs": yk.discs.duplicate(), "inv": yk.xf_inv, "r": yk.radius,
			"bins": yk._bins.duplicate(true), "bin_m": YardKeepOut.BIN_M}  # [v3city] the town's footprints, binned
	_task = WorkerThreadPool.add_task(_job, false, "litter cells")


## [art3] The new carpet's meshes: one sheet (a shallow tent, 4 triangles) and three small items.
func _build_meshes() -> void:
	if not JunkLooks.enabled() or DevHooks.has("no-litter-art"):
		await super()
		return
	_art = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	var top := Vector3(0.06, 0.05, -0.04)
	for k: int in 4:
		for p: Vector3 in [pts[k], top, pts[(k + 1) % 4]]:
			st.set_color(Color.WHITE)
			st.set_uv(Vector2(p.x + 0.5, p.z + 0.5))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	st.generate_tangents()
	_meshes.append(st.commit())
	await JunkLooks.fetch()
	_meshes.append(JunkLooks.kit_item("bottle_pet", 1))
	_meshes.append(JunkLooks.kit_item("can_crushed", 1))
	await AssetLib.fetch_model("can_rusted")
	_meshes.append(JunkLooks.dressed(AssetLib.model_mesh_lite("can_rusted", [24, 90, 140, 140][clampi(Settings.quality, 0, 3)]), "can_rusted"))
	for t: String in ["litter_atlas", "litter_normal"]:
		var keep: Resource = await BuildBudget.fetch("res://art/models/junk/%s.png" % t)
		keep = null
	_litter_material()


func _litter_material() -> ShaderMaterial:
	if _litter_mat == null:
		_litter_mat = ShaderMaterial.new()
		_litter_mat.shader = load("res://art/shaders/litter_carpet.gdshader")
		_litter_mat.set_shader_parameter("atlas", load("res://art/models/junk/litter_atlas.png"))
		_litter_mat.set_shader_parameter("normal_atlas", load("res://art/models/junk/litter_normal.png"))
		var r: float = CARPET_RANGE[clampi(Settings.quality, 0, 3)]
		_litter_mat.set_shader_parameter("fade_from", r * 0.4)
		_litter_mat.set_shader_parameter("fade_to", r)
	return _litter_mat


## [art3] Integer-hash value noise over world metres (thread-safe; the drifts cross cell borders).
static func _vn(p: Vector3) -> float:
	var i := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var f: Vector3 = p - Vector3(i)
	f = f * f * (Vector3.ONE * 3.0 - 2.0 * f)
	var v: Array[float] = []
	for k: int in 8:
		v.append(float(hash(Vector3i(i.x + (k & 1), i.y + ((k >> 1) & 1), i.z + ((k >> 2) & 1))) & 0xffff) / 65535.0)
	return lerpf(lerpf(lerpf(v[0], v[1], f.x), lerpf(v[2], v[3], f.x), f.y), lerpf(lerpf(v[4], v[5], f.x), lerpf(v[6], v[7], f.x), f.y), f.z)


## [art3] How much of a drift each height-grid point of a cell is in (0 gap .. 1 drift).
func _zone_grid(dir: Vector3, f: Basis) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(HG_N * HG_N)
	var step: float = CELL_R * 2.0 / float(HG_N - 1)
	for j: int in HG_N:
		for i: int in HG_N:
			var w: Vector3 = (dir + (f.x * (-CELL_R + i * step) + f.z * (-CELL_R + j * step)) / terrain.R).normalized() * terrain.R
			out[j * HG_N + i] = _vn(w * 0.17) * 0.75 + _vn(w * 0.45 + Vector3(31.0, 7.0, 13.0)) * 0.25
	return out


## Lays every cell of the current job (worker thread: no scene-tree access).
func _job() -> void:
	var out: Dictionary = {}
	for c: int in _job_cells:
		out[c] = _compute_cell(c)
	_job_out = out


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _drop(c: int) -> void:
	if _cell.has(c):
		(_cell[c]["node"] as Node).queue_free()
		_cell.erase(c)


## One cell's carpet: its frame and, per mesh, a MultiMesh buffer and the pieces' world points
## and thresholds. Worker-thread safe (reads the grid, terrain and _job_ctx only).
func _compute_cell(c: int) -> Dictionary:
	var rem: float = float(_job_ctx["rem"][c])
	var dir: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(dir)
	var origin: Vector3 = terrain.ground(dir)
	var xf := Transform3D(f, origin)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c, 4471])
	# [v1world] The flat carpet's density (LitterView: ~20 a square metre, landfill x2.2), in the
	# quality budget. Heights come from a small grid of terrain samples (bilinear), not one terrain
	# lookup a piece, and cell ownership from the neighbours' centres, so a dense cell stays cheap.
	var q: int = int(_job_ctx["q"])
	var n_mesh: int = LOGIC_MESHES if _art else int(_job_ctx["n_mesh"])
	var n_slot: int = int(_job_ctx["n_mesh"])
	var zg: PackedFloat32Array = _zone_grid(dir, f) if _art else PackedFloat32Array()
	var lr := RandomNumberGenerator.new()  # [art3] looks draw from their own stream: the piece stream is as it was
	lr.seed = hash([c, 9911])
	var w_drift: float = 0.0
	var w_gap: float = 0.0
	for kd: Array in KINDS:
		w_drift += float(kd[2])
		w_gap += float(kd[3])
	var n: int = int(PI * CELL_R * CELL_R * PER_M2_Q[q] * density_mult)
	var hg: PackedFloat32Array = _height_grid(dir, f, origin)
	var nb := PackedVector3Array()
	for o: int in grid.neighbors(c):
		nb.append(grid.centers[o])
	var piles: Array = _job_ctx["piles"][c]
	var ko: Dictionary = _job_ctx.get("ko", {})
	var pile_k: float = 0.3 + 0.7 * (1.0 - rem)
	var raw := PackedFloat32Array()  # 16 floats a piece (3x4 transform, colour), all meshes
	var raw_m := PackedInt32Array()
	var raw_p := PackedVector3Array()
	var raw_t := PackedFloat32Array()
	var items_share: float = 0.88 if q == 0 else 0.82
	var lim: float = rem * 0.9
	for i: int in n:
		var r: float = CELL_R * sqrt(rng.randf())
		var a: float = rng.randf() * TAU
		var lx: float = cos(a) * r
		var lz: float = sin(a) * r
		var d: Vector3 = (dir + (f.x * lx + f.z * lz) / terrain.R).normalized()
		var dc: float = d.dot(dir)
		var mine: bool = true
		for qc: Vector3 in nb:
			if d.dot(qc) > dc:
				mine = false  # only on this cell (its neighbours lay their own)
				break
		if mine and not ko.is_empty() and _ko_blocks(ko, d):  # [v1world] the yard keep-out, from a main-thread snapshot
			mine = false  # [v1yard] none on the start yard's pad
		if not mine:
			continue
		var m: int = rng.randi() % 4 if rng.randf() < items_share else 4 + rng.randi() % maxi(1, n_mesh - 4)
		var thr: float = rng.randf()
		if thr < lim:
			continue
		var gh: float = _grid_h(hg, lx, lz)
		var y: float = gh + 0.01 + float(i) / float(n) * 0.05
		for pile: Vector4 in piles:  # the carpet runs over the heaps too (as the flat one does)
			var dd: float = Vector2(lx - pile.x, lz - pile.y).length() / pile.z
			if dd < 1.0:
				y = maxf(y, gh + pile.w * sqrt(1.0 - dd * dd) * pile_k * 0.9)
		var bas := Basis(Vector3.UP, rng.randf() * TAU)
		if m >= 4:
			bas = bas * Basis(Vector3.RIGHT, PI * 0.5)  # small items lie on their side
			y += 0.04
		var tilt: float = rng.randf_range(-0.25, 0.25)
		var scl: float = rng.randf_range(0.7, 1.3) if m < 4 else rng.randf_range(0.8, 1.0)
		var col: Color = _color(rng) if m < 4 else Color.WHITE
		if _art and m < 4:
			# [art3] a kind for this spot: paper and cardboard in the drifts, small dark stuff between
			var drift: float = smoothstep(0.44, 0.60, _grid_h(zg, lx, lz))
			var pick: float = lr.randf() * lerpf(w_gap, w_drift, drift)
			var kind: int = KINDS.size() - 1
			for ki: int in KINDS.size():
				pick -= lerpf(float(KINDS[ki][3]), float(KINDS[ki][2]), drift)
				if pick <= 0.0:
					kind = ki
					break
			var kd2: Array = KINDS[kind]
			var grow: float = scl * lerpf(0.8, 1.05, drift)
			bas = bas.rotated(Vector3.RIGHT, tilt * SHEET_TILT) * Basis.from_scale(Vector3(float(kd2[0]) * grow, (float(kd2[0]) + float(kd2[1])) * 0.5 * grow, float(kd2[1]) * grow))
			var v: float = lr.randf_range(0.62, 1.0) * lerpf(0.8, 1.0, drift)
			var warm: float = lr.randf_range(-0.05, 0.05)
			col = Color(v * (1.0 + warm), v, v * (1.0 - warm), (float(kind) + 0.5) / 16.0)
		else:
			bas = bas.rotated(Vector3.RIGHT, tilt)
			bas = bas.scaled(Vector3.ONE * scl)
			col.a = 1.0
		if _art:
			m = 0 if m < 4 else ITEM_SLOTS[m - 4]
		raw.append_array([bas.x.x, bas.y.x, bas.z.x, lx, bas.x.y, bas.y.y, bas.z.y, y, bas.x.z, bas.y.z, bas.z.z, lz, col.r, col.g, col.b, col.a])
		raw_m.append(m)
		raw_p.append(xf * Vector3(lx, y, lz))
		raw_t.append(thr)
	# Split per mesh (each buffer filled once: no copies of shared packed arrays).
	var n_cols: int = 1 if _art else 4  # slots that carry a colour
	n_mesh = n_slot
	var counts := PackedInt32Array()
	counts.resize(n_mesh)
	for m: int in raw_m:
		counts[m] += 1
	var bufs: Array = []
	var pts: Array = []
	var thr_m: Array = []
	for m: int in n_mesh:
		var stride: int = 16 if m < n_cols else 12
		var buf := PackedFloat32Array()
		buf.resize(counts[m] * stride)
		var pp := PackedVector3Array()
		pp.resize(counts[m])
		var tt := PackedFloat32Array()
		tt.resize(counts[m])
		var k: int = 0
		for i: int in raw_m.size():
			if raw_m[i] != m:
				continue
			for j: int in stride:
				buf[k * stride + j] = raw[i * 16 + j]
			pp[k] = raw_p[i]
			tt[k] = raw_t[i]
			k += 1
		bufs.append(buf)
		pts.append(pp)
		thr_m.append(tt)
	# Sweep bins over the pieces in the order _apply_cell lists them (mesh by mesh).
	var bins: Dictionary = {}
	var idx: int = 0
	for m: int in n_mesh:
		var stride: int = 16 if m < n_cols else 12
		var buf: PackedFloat32Array = bufs[m]
		for k: int in counts[m]:
			var key := Vector2i(floori(buf[k * stride + 3] / BIN_M), floori(buf[k * stride + 11] / BIN_M))
			if not bins.has(key):
				bins[key] = PackedInt32Array()
			var lst: PackedInt32Array = bins[key]
			lst.append(idx)
			bins[key] = lst
			idx += 1
	return {"xf": xf, "bufs": bufs, "pts": pts, "thr": thr_m, "bins": bins}


static func _ko_blocks(ko: Dictionary, dir: Vector3) -> bool:
	var p: Vector3 = (ko["inv"] as Transform3D) * (dir.normalized() * float(ko["r"]))
	var q := Vector2(p.x, p.z)
	for r: Rect2 in ko["rects"]:
		if r.has_point(q):
			return true
	var bins: Dictionary = ko.get("bins", {})
	if not bins.is_empty():  # [v3city]
		var bm: float = float(ko["bin_m"])
		var bin: Variant = bins.get(Vector2i(floori(q.x / bm), floori(q.y / bm)))
		if bin != null:
			for r2: Rect2 in bin:
				if r2.has_point(q):
					return true
	for dd: Vector3 in ko["discs"]:
		if q.distance_squared_to(Vector2(dd.x, dd.y)) < dd.z * dd.z:
			return true
	return false


const _PAL: Array[Color] = [
	Color(0.84, 0.82, 0.74), Color(0.78, 0.74, 0.62), Color(0.6, 0.46, 0.31), Color(0.5, 0.39, 0.27),
	Color(0.7, 0.71, 0.7), Color(0.12, 0.12, 0.13), Color(0.32, 0.45, 0.62), Color(0.72, 0.24, 0.18),
	Color(0.86, 0.7, 0.22), Color(0.28, 0.5, 0.32), Color(0.92, 0.92, 0.9), Color(0.3, 0.6, 0.72),
]
const _PAL_CUM: Array[float] = [4.0, 7.0, 11.0, 14.0, 16.5, 19.0, 19.8, 20.6, 21.4, 21.9, 23.4, 23.9]


## LitterView._litter_color with a given rng (thread-safe): faded, grimy, dusty trash colours.
static func _color(rng: RandomNumberGenerator) -> Color:
	var x: float = rng.randf() * _PAL_CUM[_PAL_CUM.size() - 1]
	var c: Color = _PAL[0]
	for i: int in _PAL_CUM.size():
		if x <= _PAL_CUM[i]:
			c = _PAL[i]
			break
	var l: float = c.get_luminance()
	c = c.lerp(Color(l, l, l), rng.randf_range(0.1, 0.4))
	c = c.darkened(rng.randf_range(0.05, 0.4))
	return c.lerp(Color(0.48, 0.43, 0.37), rng.randf_range(0.0, 0.35))


## Main thread: the cell's node and MultiMeshes from a computed carpet.
func _apply_cell(c: int, data: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Litter%d" % c
	node.transform = data["xf"]
	add_child(node)
	var mms: Array[MultiMesh] = []
	var wpos := PackedVector3Array()
	var thrs := PackedFloat32Array()
	var mmi_of := PackedInt32Array()
	var slots := PackedInt32Array()
	var bins: Dictionary = data["bins"]
	for m: int in _meshes.size():
		var pp: PackedVector3Array = data["pts"][m]
		if pp.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = m < (1 if _art else 4)
		mm.mesh = _meshes[m]
		mm.instance_count = pp.size()
		mm.buffer = data["bufs"][m]
		wpos.append_array(pp)
		thrs.append_array(data["thr"][m])
		var base: int = mmi_of.size()
		mmi_of.resize(base + pp.size())
		slots.resize(base + pp.size())
		for k: int in pp.size():
			mmi_of[base + k] = mms.size()
			slots[base + k] = k
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# [v5load] Draw cost: the litter is a third of the scene's draws. Tiny items (5-15 cm) are
		# about a pixel at 50 m, so they stop there on Medium (60 m before) and at 35 m on Low; the
		# paper carpet keeps its 90 m (60 m on Low). `--no-litter-range`: the old 60 / 90 m.
		var ql: int = clampi(Settings.quality, 0, 3)
		mmi.visibility_range_end = ITEM_RANGE[ql] if not mm.use_colors else CARPET_RANGE[ql]
		if DevHooks.has("no-litter-range"):
			mmi.visibility_range_end = 90.0 if mm.use_colors else 60.0
		mmi.visibility_range_end_margin = 4.0
		if mm.use_colors:
			mmi.material_override = _litter_material() if _art else _carpet()
		node.add_child(mmi)
		mms.append(mm)
	var alive := PackedByteArray()
	alive.resize(wpos.size())
	alive.fill(1)
	_cell[c] = {"node": node, "mms": mms, "pos": wpos, "thr": thrs, "mm": mmi_of, "slot": slots,
		"alive": alive, "bins": bins, "inv": node.transform.affine_inverse(), "n": wpos.size()}


## [v1world] Terrain heights over the cell (cell-frame metres above the origin's tangent plane),
## HG_N x HG_N samples spanning +-CELL_R.
func _height_grid(dir: Vector3, f: Basis, origin: Vector3) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(HG_N * HG_N)
	var step: float = CELL_R * 2.0 / float(HG_N - 1)
	for j: int in HG_N:
		for i: int in HG_N:
			var lx: float = -CELL_R + i * step
			var lz: float = -CELL_R + j * step
			var d: Vector3 = (dir + (f.x * lx + f.z * lz) / terrain.R).normalized()
			out[j * HG_N + i] = (terrain.ground(d) - origin).dot(f.y)
	return out


func _grid_h(hg: PackedFloat32Array, lx: float, lz: float) -> float:
	var step: float = CELL_R * 2.0 / float(HG_N - 1)
	var u: float = clampf((lx + CELL_R) / step, 0.0, HG_N - 1.001)
	var v: float = clampf((lz + CELL_R) / step, 0.0, HG_N - 1.001)
	var i: int = int(u)
	var j: int = int(v)
	var fu: float = u - i
	var fv: float = v - j
	var a: float = lerpf(hg[j * HG_N + i], hg[j * HG_N + i + 1], fu)
	var b: float = lerpf(hg[(j + 1) * HG_N + i], hg[(j + 1) * HG_N + i + 1], fu)
	return lerpf(a, b, fv)


func _carpet() -> StandardMaterial3D:
	if _carpet_mat:
		return _carpet_mat
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.albedo_texture = AssetLib.tex("dirty_concrete", "diff")
	mat.albedo_color = Color(1.35, 1.35, 1.35)  # [v1world] was 1.7: under the globe's open sun the sheets read as white confetti
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.normal_enabled = true  # [v1world] the flat carpet's crinkle
	mat.normal_texture = AssetLib.tex("rubble", "nor_gl")
	mat.normal_scale = 0.4
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 3.0
	_carpet_mat = mat
	return mat


## Patch's scoop / a robot's: hides the pieces within radius of a world point. Returns the count.
func sweep(pos: Vector3, radius: float) -> int:
	if grid == null:
		return 0
	var n: int = 0
	var r2: float = radius * radius
	var c0: int = grid.cell_at(pos)
	for c: int in grid.cells_around(c0, 1):
		if not _cell.has(c):
			continue
		var cd: Dictionary = _cell[c]
		var lp: Vector3 = (cd["inv"] as Transform3D) * pos
		if absf(lp.y) > radius + 3.0 or Vector2(lp.x, lp.z).length() > CELL_R + radius + 1.0:
			continue
		var bins: Dictionary = cd["bins"]
		var wpos: PackedVector3Array = cd["pos"]
		var alive: PackedByteArray = cd["alive"]
		var b0 := Vector2i(floori((lp.x - radius) / BIN_M), floori((lp.z - radius) / BIN_M))
		var b1 := Vector2i(floori((lp.x + radius) / BIN_M), floori((lp.z + radius) / BIN_M))
		for bz: int in range(b0.y, b1.y + 1):
			for bx: int in range(b0.x, b1.x + 1):
				var key := Vector2i(bx, bz)
				if not bins.has(key):
					continue
				for i: int in bins[key]:
					if alive[i] == 1 and wpos[i].distance_squared_to(pos) <= r2:
						_hide(cd, i)
						alive[i] = 0
						n += 1
	return n


func _hide(cd: Dictionary, i: int) -> void:
	var alive: PackedByteArray = cd["alive"]
	alive[i] = 0
	cd["alive"] = alive
	cd["n"] = int(cd["n"]) - 1
	var mm: MultiMesh = (cd["mms"] as Array)[(cd["mm"] as PackedInt32Array)[i]]
	mm.set_instance_transform((cd["slot"] as PackedInt32Array)[i], _hidden())


## Thins a cell's litter as it gets cleaner; a clean cell (or a hub cell) has none.
func refresh_hex(hid: int) -> void:
	if not _cell.has(hid):
		return
	if not cells.is_dirty(hid) or sfield.hex_clean[hid] == 1:
		_drop(hid)
		return
	var lim: float = sfield.removed_fraction(hid) * 0.9
	var cd: Dictionary = _cell[hid]
	var thr: PackedFloat32Array = cd["thr"]
	var alive: PackedByteArray = cd["alive"]
	for i: int in thr.size():
		if alive[i] == 1 and thr[i] < lim:
			_hide(cd, i)
			alive = cd["alive"]


func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)


## Pieces currently laid (for checks).
func piece_count() -> int:
	var n: int = 0
	for c: int in _cell:
		n += int(_cell[c]["n"])
	return n
