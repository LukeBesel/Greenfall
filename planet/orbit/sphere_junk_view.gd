class_name SphereJunkView
extends FieldView
## [orbit] Phase A: draws SphereField's scoopable pieces in the near ring (one MultiMesh per
## model) and answers the FieldView calls Patch makes (piece_transform, piece_mesh, move_piece,
## hide_piece, set_focus_hex, refresh_hex). Phase B moves JunkLOD (near/far buffers) onto this.
## [orbB] A FieldView subclass, so it is the slice's `view` on the globe (scenes/slice_orbit.gd).
## The flat ground/mound/landmark machinery of FieldView is never built; the calls other systems
## make on it are answered here (no-ops where the globe's ground reads SphereCells instead).

var sfield: SphereField
var stats: Dictionary = {}
var quality: int = 1
var near_radius: float = 32.0   # full meshes inside this (metres to the cell centre), JunkLod's presets
var heavy_radius: float = 16.0  # heavy models (stalled importer LODs) switch closer
var budget: int = 600           # [orbB] pieces shown/hidden per frame when the ring moves
const PUMP_US: int = 2500       # [v5load] and at most this much time a frame
var _hidden_xf := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
var _mound_mesh_res: ArrayMesh
var _cell_mounds: Dictionary = {}  # [orbB] cell -> Array of [MeshInstance3D, StaticBody3D, Vector4]
var _cell_props: Dictionary = {}   # [orbB] cell -> Node3D (its landmark)
# [orbB] JunkLOD on the globe (planet/junk_lod.gd's scheme, for a growing piece set): per model a
# NEAR MultiMesh (the flat game's junk mesh) and a FAR one (JunkLod.far_mesh), instances packed
# at the front and drawn with visible_instance_count. A cell's band follows its distance to the
# camera with hysteresis; ring changes are applied under a per-frame piece budget.
var _groups: Dictionary = {}       # model -> group index
var _g_model: Array[String] = []
var _g_heavy := PackedByteArray()
var _g_mm: Array[MultiMesh] = []   # 2 per group: [near, far]
var _g_mmi: Array[MultiMeshInstance3D] = []
var _g_pids: Array[PackedInt32Array] = []
var _where := PackedByteArray()    # pid -> 0 hidden, 1 near, 2 far
var _slot := PackedInt32Array()    # pid -> index in its buffer
var _grp := PackedInt32Array()     # pid -> group
var _band: Dictionary = {}         # shown cell -> 2 heavy band, 1 near, 0 far
var _shown_cells: Dictionary = {}  # cell -> true once its pieces are in buffers
var _queue: Array = []             # pending [cell, show?]
var _near := PackedInt32Array()
var _t: float = 0.0
var _last_cam := Vector3(INF, INF, INF)
var _far_todo: Array[int] = []  # groups whose far mesh is still the near one (built one per frame)


func setup(p_field: HexField) -> void:
	field = p_field
	sfield = p_field as SphereField
	if sfield and not sfield.hex_swept.is_connected(_on_swept):  # [v2feel] 95% clean sweeps the rest
		sfield.hex_swept.connect(_on_swept)
	quality = clampi(Settings.quality, 0, 3)
	near_radius = JunkLod.NEAR_RADIUS[quality]
	heavy_radius = JunkLod.HEAVY_RADIUS[quality]
	if DevHooks.has("no-junk-lod"):
		near_radius = 1e9
		heavy_radius = 1e9


func _process(delta: float) -> void:
	var h: int = Hitch.t()
	_pump(budget, PUMP_US)
	Hitch.mark("junk pump", h)
	if not _far_todo.is_empty():
		h = Hitch.t()
		_build_far(_far_todo.pop_front())
		Hitch.mark("junk far mesh", h)
	_t -= delta
	if _t <= 0.0:
		_t = JunkLod.UPDATE_EVERY
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam:
			update_bands(cam.global_position)


func _group_for(model: String, vol: float) -> int:
	if _groups.has(model):
		return _groups[model]
	var g: int = _g_model.size()
	_groups[model] = g
	_g_model.append(model)
	var has: bool = model != "" and AssetLib.has_model(model)
	var near_mesh: Mesh = AssetLib.model_mesh_lite(model, [320, 500, 700, 700][quality]) if has else null
	if near_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 0.4, 0.4)
		near_mesh = bm
	var heavy: bool = JunkLod._tris(near_mesh) > JunkLod.HEAVY_TRIS if has else false
	_g_heavy.append(1 if heavy else 0)
	var far_mesh: Mesh = near_mesh  # until _process builds the light one (JunkLod.far_mesh is slow)
	if has:
		_far_todo.append(g)
	for k: int in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = near_mesh if k == 0 else far_mesh
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Junk_%s%s" % [model, "" if k == 0 else "_far"]
		mmi.multimesh = mm
		mmi.extra_cull_margin = 4.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if vol >= 1.2 and k == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		add_child(mmi)
		_g_mm.append(mm)
		_g_mmi.append(mmi)
		_g_pids.append(PackedInt32Array())
	return g


func _grow_pid_arrays() -> void:
	var n: int = sfield.piece_pos.size()
	if _where.size() < n:
		var old: int = _where.size()
		_where.resize(n)
		_slot.resize(n)
		_grp.resize(n)
		for pid: int in range(old, n):
			_grp[pid] = -1


## 1 = near buffer, 2 = far, for a piece of group g in a cell of this band.
func _want(g: int, band: int) -> int:
	return 1 if band == 2 or (band == 1 and _g_heavy[g] == 0) else 2


func _append(pid: int, where: int) -> void:
	var g: int = _grp[pid]
	var b: int = g * 2 + where - 1
	var mm: MultiMesh = _g_mm[b]
	var list: PackedInt32Array = _g_pids[b]
	var i: int = list.size()
	if i >= mm.instance_count:  # grow (resizing clears the buffer: write the packed ones back)
		mm.instance_count = maxi(64, mm.instance_count * 2)
		for k: int in i:
			mm.set_instance_transform(k, sfield.piece_xf[list[k]])
	list.append(pid)
	mm.set_instance_transform(i, sfield.piece_xf[pid])
	mm.visible_instance_count = i + 1
	_g_mmi[b].visible = true
	_g_pids[b] = list
	_where[pid] = where
	_slot[pid] = i


func _remove(pid: int) -> void:
	if pid >= _where.size() or _where[pid] == 0:
		return
	var b: int = _grp[pid] * 2 + _where[pid] - 1
	var mm: MultiMesh = _g_mm[b]
	var list: PackedInt32Array = _g_pids[b]
	var i: int = _slot[pid]
	var last: int = list.size() - 1
	if i != last:
		var moved: int = list[last]
		list[i] = moved
		_slot[moved] = i
		mm.set_instance_transform(i, sfield.piece_xf[moved])
	mm.set_instance_transform(last, _hidden_xf)
	list.resize(last)
	mm.visible_instance_count = last
	if last == 0:
		_g_mmi[b].visible = false
	_g_pids[b] = list
	_where[pid] = 0


## The near ring changed: cells that entered are shown, cells that left are hidden, a budget of
## pieces per frame at a time (flush() does it all at once, e.g. after loading).
func rebuild(near: PackedInt32Array) -> void:
	var t0: int = Time.get_ticks_usec()
	_queue_ring(near)
	stats["rebuild_us"] = Time.get_ticks_usec() - t0


## [v5load] Queues the ring's changes; _pump does the work under a budget. Two fixes:
## - A cell whose pieces are not laid yet (the planet's deferred fill) is left out until they are.
##   It used to be marked shown while still empty, and its junk was then never drawn (about a fifth
##   of the ring's pieces after a short walk: scoopable, solid for robots, invisible).
## - A cell's heaps and wreck (_ensure_extras) are made when its turn comes in _pump, not all at
##   once here (30-50 ms frames when the ring moved).
func _queue_ring(near: PackedInt32Array) -> void:
	var want: Dictionary = {}
	var last: Dictionary = {}  # cell -> its latest queued op (show?)
	for op: Array in _queue:
		last[op[0]] = op[1]
	for c: int in near:
		want[c] = true
		if sfield and sfield.materialized[c] == 0:
			continue
		if not bool(last.get(c, _shown_cells.has(c))):
			_queue.append([c, true])
	for c: int in _shown_cells:
		if not want.has(c) and bool(last.get(c, true)):
			_queue.append([c, false])
	for c: int in last:  # queued to show, never shown, and out of the ring again
		if bool(last[c]) and not want.has(c) and not _shown_cells.has(c):
			_queue.append([c, false])
	_near = near


func flush() -> void:
	_pump(1 << 30)


## [v5load] rebuild() + flush() behind the loading screen, yielding between cells, plus the far
## meshes the first live frames would otherwise build one a frame (JunkLod.far_mesh is slow).
func rebuild_async(near: PackedInt32Array) -> void:
	_queue_ring(near)
	# The ring's models: their near (lite) and far meshes are mesh simplification, 50-200 ms each
	# and not divisible. One worker task makes them all while the loader keeps drawing (nothing
	# else builds meanwhile: the caller awaits this); the groups and _build_far below then find
	# them cached.
	if BuildBudget.active():
		# Every junk model, not only the first ring's: a model first met while walking made its
		# lite mesh in that frame and its far mesh in the next (30-150 ms each). Landmarks too.
		var todo: Array[String] = []
		var marks: Array[String] = []
		for tid: Variant in Economy.junk_types:
			for md: Variant in (Economy.junk_types[tid] as Dictionary).get("models", []):
				var m: String = str((md as Dictionary).get("id", "")) if md is Dictionary else str(md)
				if m != "" and not todo.has(m) and not _groups.has(m) and AssetLib.has_model(m):
					todo.append(m)
		if not todo.has("trashbag") and AssetLib.has_model("trashbag"):
			todo.append("trashbag")
		for fl: Array in SphereField.FLOATERS:  # the lakes' floating junk
			if not todo.has(str(fl[1])) and not _groups.has(str(fl[1])) and AssetLib.has_model(str(fl[1])):
				todo.append(str(fl[1]))
		var sets: Array = [Economy.landmarks]
		for bk: Variant in Economy.biome_sets:
			sets.append((Economy.biome_sets[bk] as Dictionary).get("landmarks", []))
		for lst: Variant in sets:
			for d: Variant in (lst as Array):
				var lid: String = str((d as Dictionary).get("id", "")) if d is Dictionary else ""
				if lid != "" and not marks.has(lid) and AssetLib.has_model(lid):
					marks.append(lid)
		# Main thread first: the models' surfaces and their materials' average colours (texture
		# reads), so the worker below never asks the rendering server for anything.
		var was_tracing: bool = AssetLib.tracing
		AssetLib.tracing = false  # warmed here, not blocking loads
		for m: String in todo + marks:
			await OrbitPreload.snapshot(m)
		for m: String in todo:
			var fm0: Mesh = AssetLib.model_mesh(m)  # a cache hit for every model on the preload list
			for s: int in fm0.get_surface_count():
				JunkFarSingle.average_color(fm0.surface_get_material(s))
			await BuildBudget.check("junk colours")
		var q: int = quality
		var lm_tris: int = LANDMARK_TRIS[clampi(Settings.quality, 0, 3)]
		var warm := func() -> void:
			for m: String in todo:
				var nm: Mesh = AssetLib.model_mesh_lite(m, [320, 500, 700, 700][q])
				var fm: Mesh = JunkLod.far_mesh(m, JunkLod.FAR_TRIS[q] * (4 if JunkLod._tris(nm) > JunkLod.HEAVY_TRIS else 1))
				if not DevHooks.has("no-far-single"):
					JunkFarSingle.single(fm)
			for m: String in marks:
				AssetLib.model_mesh_lite(m, lm_tris)
		await BuildBudget.join(BuildBudget.add_task(warm, "junk meshes"))
		AssetLib.tracing = was_tracing
	while not _queue.is_empty():
		_pump(40)
		await BuildBudget.check("junk pieces")
	while not _far_todo.is_empty():
		_build_far(_far_todo.pop_front())
		await BuildBudget.check("junk far mesh")


func _build_far(g: int) -> void:
	var fm: Mesh = JunkLod.far_mesh(_g_model[g], JunkLod.FAR_TRIS[quality] * (4 if _g_heavy[g] == 1 else 1))
	_g_mm[g * 2 + 1].mesh = fm if DevHooks.has("no-far-single") else JunkFarSingle.single(fm)  # [orbE] one draw per far model


## budget_us > 0 [v5load]: also stop once this call has used that much time (play: 2.5 ms a frame).
func _pump(max_pieces: int, budget_us: int = 0) -> void:
	if _queue.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	_grow_pid_arrays()
	var done: int = 0
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	while not _queue.is_empty() and done < max_pieces:
		if budget_us > 0 and Time.get_ticks_usec() - t0 > budget_us:
			break
		var op: Array = _queue.pop_front()
		var c: int = op[0]
		if op[1]:
			if _shown_cells.has(c):
				continue
			_shown_cells[c] = true
			_ensure_extras(c)  # [orbB] heaps and wrecks of the near ring (made once, kept)
			var band: int = _band_for(c, cam.global_position, 0) if cam else 2
			_band[c] = band
			for pid: int in sfield.pieces_in(c):
				if sfield.piece_alive[pid] == 0:
					continue
				if _grp[pid] < 0:
					_grp[pid] = _group_for(sfield.piece_model[pid], sfield.piece_vol[pid])
				_append(pid, _want(_grp[pid], band))
				done += 1
		else:
			if not _shown_cells.has(c):
				continue
			_shown_cells.erase(c)
			_band.erase(c)
			for pid: int in sfield.pieces_in(c):
				_remove(pid)
				done += 1
	_count()
	stats["pump_us"] = Time.get_ticks_usec() - t0


func _band_for(c: int, cam: Vector3, was: int) -> int:
	var d: float = sfield.hex_center(c).distance_to(cam)
	var now: int = 2 if d < heavy_radius else (1 if d < near_radius else 0)
	if now < was:  # moving outwards: hold the inner band a little longer (JunkLod.band_for)
		var edge: float = heavy_radius if was == 2 else near_radius
		if d <= edge + JunkLod.HYSTERESIS:
			now = was if was - now == 1 else (1 if d <= near_radius + JunkLod.HYSTERESIS else 0)
	return now


## Re-sort shown cells into near / far around the camera (only cells that cross move pieces).
func update_bands(cam: Vector3) -> void:
	if cam.distance_squared_to(_last_cam) < 0.25:
		return
	_last_cam = cam
	var flips: int = 0
	for c: int in _band:
		var was: int = _band[c]
		var now: int = _band_for(c, cam, was)
		if now == was:
			continue
		_band[c] = now
		flips += 1
		for pid: int in sfield.pieces_in(c):
			if _where[pid] != 0:
				var w: int = _want(_grp[pid], now)
				if w != _where[pid]:
					_remove(pid)
					_append(pid, w)
	stats["flips"] = flips
	_count()


func _count() -> void:
	var nn: int = 0
	var ff: int = 0
	for b: int in _g_pids.size():
		if b % 2 == 0:
			nn += _g_pids[b].size()
		else:
			ff += _g_pids[b].size()
	stats["pieces"] = nn + ff
	stats["near"] = nn
	stats["far"] = ff
	stats["pending"] = _queue.size()


func counts() -> Vector2i:
	_count()
	return Vector2i(int(stats["near"]), int(stats["far"]))


func piece_transform(pid: int) -> Transform3D:
	return sfield.piece_xf[pid]


func piece_mesh(pid: int) -> Mesh:
	var m: String = sfield.piece_model[pid]
	return AssetLib.model_mesh(m) if m != "" and AssetLib.has_model(m) else BoxMesh.new()


## [v2feel] The leftovers of a cell that just counted as clean: gone with a small poof each
## (a few poofs at most, and only for pieces on screen).
func _on_swept(_cell: int, pids: PackedInt32Array) -> void:
	var poofs: int = 0
	for pid: int in pids:
		var shown: bool = pid < _where.size() and _where[pid] != 0
		_remove(pid)
		if shown and poofs < 8:
			poofs += 1
			var p: Vector3 = sfield.piece_pos[pid]
			Vfx.burst("dust", p + p.normalized() * 0.2, Color(0.75, 0.72, 0.62, 0.6), 0.5)


func hide_piece(pid: int) -> void:
	_remove(pid)


func move_piece(pid: int, pos: Vector3) -> void:
	sfield.piece_pos[pid] = pos
	var xf: Transform3D = sfield.piece_xf[pid]
	xf.origin = pos
	sfield.piece_xf[pid] = xf
	_set_xf(pid)


func _set_xf(pid: int) -> void:
	if pid < _where.size() and _where[pid] != 0:
		_g_mm[_grp[pid] * 2 + _where[pid] - 1].set_instance_transform(_slot[pid], sfield.piece_xf[pid])


var focus_cell: int = -1


## [orbB] The cell Lumi is working (a cell id). Like the flat game, no ground ring is drawn: the
## objective outline (story/objective_hex.gd) marks hexes; this keeps the id for whoever asks.
func set_focus_hex(id: int) -> void:
	focus_cell = id


## The ground reads SphereCells' state texture; here the cell's heaps shrink and the pieces on
## them settle (flat FieldView._update_mounds / _resettle).
func refresh_hex(id: int, _flipped_now: bool = false) -> void:
	if sfield == null:
		return
	for pid: int in sfield.resettle(id):
		_set_xf(pid)
	_update_mounds(id)


## [v8fix] A cell lost heaps or its wreck (SphereField.clear_piles_near): its pieces were
## re-seated on the ground, its mounds and wreck go.
func piles_changed(id: int) -> void:
	if sfield == null:
		return
	for pid: int in sfield.pieces_in(id):
		_set_xf(pid)
	_update_mounds(id)
	if _cell_props.has(id) and not sfield._cell_landmark.has(id):  # its wreck went too
		var n: Node = _cell_props[id]
		if is_instance_valid(n):
			n.queue_free()
		_cell_props.erase(id)


# --- [orbB] Heaps and landmarks --------------------------------------------------------------

func _ensure_extras(c: int) -> void:
	if not _cell_mounds.has(c):
		var list: Array = []
		for pile: Vector4 in sfield.hex_piles[c]:
			if _mound_mesh_res == null:
				_mound_mesh_res = FieldView._mound_mesh()
				_mound_mesh_res.surface_set_material(0, AssetLib.pbr_material("rubble", 0.9, Color(0.42, 0.38, 0.36), true))
			var root := Node3D.new()
			root.name = "Mound%d" % c
			add_child(root)
			root.global_transform = sfield.pile_transform(c, pile)
			var mi := MeshInstance3D.new()
			mi.mesh = _mound_mesh_res
			mi.position = Vector3(0, -0.02, 0)
			root.add_child(mi)
			var body: StaticBody3D = MoundColliders.make(root, Vector4(0, 0, pile.z, pile.w))
			list.append([mi, body, pile])
		_cell_mounds[c] = list
		_update_mounds(c)
	if not _cell_props.has(c) and sfield._cell_landmark.has(c):
		_cell_props[c] = _build_landmark(sfield.landmarks[sfield._cell_landmark[c]])


func _update_mounds(id: int) -> void:
	var list: Array = _cell_mounds.get(id, [])
	if list.is_empty():
		return
	var left: float = 0.0 if sfield.hex_clean[id] == 1 else (0.3 + 0.7 * (1.0 - sfield.removed_fraction(id)))
	var piles: Array = sfield.hex_piles[id]
	for e: Array in list:
		var mi: MeshInstance3D = e[0]
		var pile: Vector4 = e[2]
		if not piles.has(pile):  # [v8fix] cleared off an outpost's ground (SphereField.clear_piles_near)
			mi.visible = false
			MoundColliders.update(e[1], Vector3.ZERO, false)
			continue
		mi.visible = left > 0.0
		mi.scale = Vector3(pile.z * 1.1, maxf(pile.w * left * 0.9, 0.001), pile.z * 1.1)
		MoundColliders.update(e[1], mi.scale, mi.visible, 1.0 - sfield.removed_fraction(id))


## [orbE] Landmark triangle budget per quality preset (Low, Medium, High, Ultra).
const LANDMARK_TRIS: Array[int] = [3000, 6000, 12000, 24000]


func _build_landmark(lm: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Landmark_%s" % str(lm["model"])
	add_child(root)
	root.global_transform = Transform3D(lm["basis"], lm["pos"])
	var model: String = str(lm["model"])
	if not AssetLib.has_model(model):
		return root
	var mi := MeshInstance3D.new()
	# [orbE] perf: a landmark's mesh within a triangle budget per preset, using the model's own
	# import LODs (AssetLib.lite): Anvil's concrete road barriers were 61k triangles each (8 in view).
	mi.mesh = AssetLib.model_mesh_lite(model, LANDMARK_TRIS[clampi(Settings.quality, 0, 3)])
	root.add_child(mi)
	# Solid like the flat props (PhysLayers.PROP): one box from the model's bounds, in its own frame.
	var bb: AABB = AssetLib.model_aabb(model)
	if bb.size.y >= 0.35:
		var b := StaticBody3D.new()
		b.name = "PropBody"
		b.collision_layer = PhysLayers.PROP
		b.collision_mask = 0
		b.add_to_group("prop_body")
		root.add_child(b)
		var cs := CollisionShape3D.new()
		cs.shape = PropColliders.box_shape(bb.size * 0.92)
		cs.position = bb.get_center()
		b.add_child(cs)
	return root


func mound_count() -> int:
	var n: int = 0
	for c: int in _cell_mounds:
		n += (_cell_mounds[c] as Array).size()
	return n


func landmark_count() -> int:
	return _cell_props.size()


# --- [orbB] FieldView calls the globe answers without a flat ground ----------------------

func set_junk_overlay(_m: Material) -> void:
	pass


func set_life(_id: int, _life: float) -> void:
	pass


func set_level(id: int, lvl: int) -> void:
	if sfield and sfield.cells:
		sfield.cells.set_level(id, clampi(lvl, 0, 15))


func set_rows(_id: int, _angle01: float) -> void:
	pass


func set_grid_visible(_v: float) -> void:
	pass


func state_texture() -> ImageTexture:
	return sfield.cells.texture if sfield and sfield.cells else null


func life_texture() -> ImageTexture:
	return null
