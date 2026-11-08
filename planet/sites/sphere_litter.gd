class_name SphereLitter
extends LitterView
## [orbD] Ground litter on the walkable globe: the flat LitterView's carpet (crumpled paper,
## wrappers, film, cardboard scraps and tiny real items, the same meshes and colours) on junk cells,
## built only for the cells in the streamer's near ring and freed when they leave it. Same API, so
## Patch's scoop (sweep) and the slice's refresh calls work unchanged: the scoop sweeps a swath,
## partial cleaning thins a cell (each piece has a threshold), a clean cell has none. Any change to
## a cell (Lumi, robots, far crews) re-thins it through SphereCells.cell_changed.
## Per cell: one Node3D in the cell's surface frame with a MultiMesh per mesh, pieces seated on
## the terrain. Budget: PER_M2 pieces a square metre (x density_mult), ~650 on a full 10 m cell.

const PER_M2: float = 2.6
const CELL_R: float = 9.0  # placement radius round the cell centre (10 m hexes overlap a little)

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var sfield: SphereField
## cell -> {node, mms: Array[MultiMesh], items: Array[[mm, slot, world_pos, threshold]]}
var _cell: Dictionary = {}
var _pending: Array[int] = []
var _ready_meshes: bool = false


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
	for c: int in added:
		if not _cell.has(c) and not _pending.has(c):
			_pending.append(c)


func _process(_delta: float) -> void:
	if not _ready_meshes:
		return
	# A few cells a frame (each is a few hundred terrain samples).
	for k: int in 3:
		if _pending.is_empty():
			return
		var c: int = _pending.pop_front()
		_build_cell(c)


func _drop(c: int) -> void:
	if _cell.has(c):
		(_cell[c]["node"] as Node).queue_free()
		_cell.erase(c)


func _build_cell(c: int) -> void:
	if cells.state[c] == 5 or not cells.is_dirty(c) or sfield.hex_hub[c] != 0:
		return
	var rem: float = sfield.removed_fraction(c)
	var dir: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(dir)
	var origin: Vector3 = terrain.ground(dir)
	var node := Node3D.new()
	node.name = "Litter%d" % c
	node.transform = Transform3D(f, origin)
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c, 4471])
	var n: int = int(PI * CELL_R * CELL_R * PER_M2 * density_mult)
	var groups: Array = []  # per mesh: [Array[Transform3D], Array[Color], Array[[i, wpos, thr]]]
	for m: int in _meshes.size():
		groups.append([[], [], []])
	for i: int in n:
		var r: float = CELL_R * sqrt(rng.randf())
		var a: float = rng.randf() * TAU
		var lx: float = cos(a) * r
		var lz: float = sin(a) * r
		var d: Vector3 = (dir + (f.x * lx + f.z * lz) / terrain.R).normalized()
		if grid.cell_at(d) != c:
			continue  # only on this cell (its neighbours lay their own)
		if sfield.keep_out.is_valid() and bool(sfield.keep_out.call(d)):
			continue  # [v1yard] none on the start yard's pad (its cells round it are junk cells now)
		var wp: Vector3 = terrain.ground(d)
		var lp: Vector3 = node.transform.affine_inverse() * wp
		var m: int = rng.randi() % 4 if rng.randf() < 0.88 else 4 + rng.randi() % maxi(1, _meshes.size() - 4)
		var thr: float = rng.randf()
		if thr < rem * 0.9:
			continue
		var bas := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		var s: float = rng.randf_range(0.7, 1.3)
		(groups[m][0] as Array).append(Transform3D(bas.scaled(Vector3.ONE * s), lp + Vector3(0, 0.01, 0)))
		(groups[m][1] as Array).append(_litter_color())
		(groups[m][2] as Array).append([wp, thr])
	var mms: Array[MultiMesh] = []
	var items: Array = []
	for m: int in _meshes.size():
		var xfs: Array = groups[m][0]
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = m < 4
		mm.mesh = _meshes[m]
		mm.instance_count = xfs.size()
		for k: int in xfs.size():
			mm.set_instance_transform(k, xfs[k])
			if mm.use_colors:
				mm.set_instance_color(k, (groups[m][1] as Array)[k])
			var it: Array = (groups[m][2] as Array)[k]
			items.append([mm, k, it[0], it[1]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 90.0 if mm.use_colors else 60.0
		if mm.use_colors:
			mmi.material_override = _carpet()
		node.add_child(mmi)
		mms.append(mm)
	_cell[c] = {"node": node, "mms": mms, "items": items}


func _carpet() -> StandardMaterial3D:
	if _carpet_mat:
		return _carpet_mat
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.albedo_texture = AssetLib.tex("dirty_concrete", "diff")
	mat.albedo_color = Color(1.7, 1.7, 1.7)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		var items: Array = _cell[c]["items"]
		for i: int in range(items.size() - 1, -1, -1):
			var it: Array = items[i]
			if (it[2] as Vector3).distance_squared_to(pos) <= r2:
				(it[0] as MultiMesh).set_instance_transform(int(it[1]), _hidden())
				items.remove_at(i)
				n += 1
	return n


## Thins a cell's litter as it gets cleaner; a clean cell (or a hub cell) has none.
func refresh_hex(hid: int) -> void:
	if not _cell.has(hid):
		return
	if not cells.is_dirty(hid) or sfield.hex_clean[hid] == 1:
		_drop(hid)
		return
	var rem: float = sfield.removed_fraction(hid)
	var items: Array = _cell[hid]["items"]
	for i: int in range(items.size() - 1, -1, -1):
		var it: Array = items[i]
		if float(it[3]) < rem * 0.9:
			(it[0] as MultiMesh).set_instance_transform(int(it[1]), _hidden())
			items.remove_at(i)


func _hidden() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)


## Pieces currently laid (for checks).
func piece_count() -> int:
	var n: int = 0
	for c: int in _cell:
		n += (_cell[c]["items"] as Array).size()
	return n
