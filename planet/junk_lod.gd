class_name JunkLod
extends RefCounted
## [vqa2] Distance LOD for field junk (FieldView). Every junk group (chunk x model) has two
## MultiMeshes: NEAR keeps the mesh the game always drew (identical close-up look), FAR uses a
## much lighter mesh (`far_mesh`: vertices welded across UV/normal seams, then simplified, so
## models whose importer LODs stall - the 18k-triangle plastic crate - still drop to ~100 tris).
## A piece lives in NEAR while its hex centre is within `near_radius` of the camera (with
## hysteresis), else in FAR. Instances are packed at the front of each buffer and drawn with
## `visible_instance_count`, so hidden or far pieces cost nothing in the near pass (zero-scale
## instances would still be vertex-shaded and counted as primitives).

const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0, -50, 0))
const NEAR_RADIUS: Array[float] = [26.0, 32.0, 40.0, 52.0]  # by quality preset, metres to hex centre
const FAR_TRIS: Array[int] = [80, 120, 180, 240]
const HYSTERESIS: float = 6.0
const UPDATE_EVERY: float = 0.2

var field: HexField
var near_radius: float = 38.0
var near_mm: Array[MultiMesh] = []
var far_mm: Array[MultiMesh] = []
var near_mmi: Array[MultiMeshInstance3D] = []
var far_mmi: Array[MultiMeshInstance3D] = []
var _near_pids: Array[PackedInt32Array] = []  # group -> packed pids in NEAR order
var _far_pids: Array[PackedInt32Array] = []
var _group := PackedInt32Array()  # pid -> group
var _where := PackedByteArray()  # pid -> 0 hidden, 1 near, 2 far
var _slot := PackedInt32Array()  # pid -> index in its buffer
var _xf: Array[Transform3D] = []  # pid -> current transform (CPU copy: reading MultiMesh back can stall)
var _hex_near := PackedByteArray()  # hex -> 1 near
var _t: float = 0.0
var _forced: bool = false
var _last_cam := Vector3(INF, INF, INF)


func _init(p_field: HexField, quality: int) -> void:
	field = p_field
	near_radius = NEAR_RADIUS[clampi(quality, 0, 3)]
	if DevHooks.has("no-junk-lod"):  # A/B measurements: everything stays NEAR (the old look and cost)
		near_radius = 1e9
	var n: int = field.piece_count()
	_group.resize(n)
	_where.resize(n)
	_slot.resize(n)
	_xf.resize(n)
	_hex_near.resize(field.hex_count())
	_hex_near.fill(1)  # until the first camera update everything counts as near (no pop on load)


## Registers one group; returns its index. Both MMIs are added to `parent`.
func add_group(parent: Node3D, name: String, model: String, near_mesh: Mesh, pids: PackedInt32Array, shadows: bool, quality: int) -> int:
	var g: int = near_mm.size()
	var mm_n := _new_mm(near_mesh, pids.size())
	var mm_f := _new_mm(far_mesh(model, FAR_TRIS[clampi(quality, 0, 3)]), pids.size())
	near_mm.append(mm_n)
	far_mm.append(mm_f)
	_near_pids.append(PackedInt32Array())
	_far_pids.append(PackedInt32Array())
	for pid: int in pids:
		_group[pid] = g
		_where[pid] = 0
	var mi_n := _new_mmi(name, mm_n, shadows)
	var mi_f := _new_mmi(name + "_far", mm_f, shadows)
	parent.add_child(mi_n)
	parent.add_child(mi_f)
	near_mmi.append(mi_n)
	far_mmi.append(mi_f)
	return g


func _new_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	for i: int in n:
		mm.set_instance_transform(i, HIDDEN)
	return mm


static func _new_mmi(name: String, mm: MultiMesh, shadows: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.visibility_range_end = 110.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	return mmi


func is_shown(pid: int) -> bool:
	return _where[pid] != 0


## Shows a piece at xf (or moves it there).
func show_piece(pid: int, xf: Transform3D) -> void:
	var want: int = 1 if _hex_near[field.piece_hex[pid]] == 1 else 2
	_xf[pid] = xf
	if _where[pid] == want:
		(near_mm if want == 1 else far_mm)[_group[pid]].set_instance_transform(_slot[pid], xf)
		return
	_remove(pid)
	_append(pid, want, xf)


func hide_piece(pid: int) -> void:
	_remove(pid)


func set_overlay(m: Material) -> void:
	for mmi: MultiMeshInstance3D in near_mmi + far_mmi:
		mmi.material_overlay = m


func _append(pid: int, where: int, xf: Transform3D) -> void:
	var g: int = _group[pid]
	var mm: MultiMesh = near_mm[g] if where == 1 else far_mm[g]
	var list: PackedInt32Array = _near_pids[g] if where == 1 else _far_pids[g]
	var i: int = list.size()
	list.append(pid)
	mm.set_instance_transform(i, xf)
	mm.visible_instance_count = i + 1
	(near_mmi[g] if where == 1 else far_mmi[g]).visible = true
	if where == 1:
		_near_pids[g] = list
	else:
		_far_pids[g] = list
	_where[pid] = where
	_slot[pid] = i


func _remove(pid: int) -> void:
	var where: int = _where[pid]
	if where == 0:
		return
	var g: int = _group[pid]
	var mm: MultiMesh = near_mm[g] if where == 1 else far_mm[g]
	var list: PackedInt32Array = _near_pids[g] if where == 1 else _far_pids[g]
	var i: int = _slot[pid]
	var last: int = list.size() - 1
	if i != last:  # move the last instance into the hole
		var moved: int = list[last]
		list[i] = moved
		_slot[moved] = i
		mm.set_instance_transform(i, _xf[moved])
	mm.set_instance_transform(last, HIDDEN)
	list.resize(last)
	mm.visible_instance_count = last
	if last == 0:
		(near_mmi[g] if where == 1 else far_mmi[g]).visible = false
	if where == 1:
		_near_pids[g] = list
	else:
		_far_pids[g] = list
	_where[pid] = 0


func _current_xf(pid: int) -> Transform3D:
	return _xf[pid]


## Re-sorts hexes into near / far around the camera. Cheap: one distance per hex every 0.2 s,
## and only hexes that cross the radius move their pieces.
func update(delta: float, cam: Vector3) -> void:
	_t -= delta
	if _t > 0.0 and not _forced:
		return
	_t = UPDATE_EVERY
	if cam.distance_squared_to(_last_cam) < 0.25 and not _forced:
		return
	_last_cam = cam
	_forced = false
	var r_in: float = near_radius
	var r_out: float = near_radius + HYSTERESIS
	var flips: int = 0
	var maxd: float = 0.0
	for h: int in field.hex_count():
		if field.hex_pieces[h].is_empty():
			continue
		var d: float = field.hex_center(h).distance_to(cam)
		maxd = maxf(maxd, d)
		var was: int = _hex_near[h]
		var now: int = was
		if was == 1 and d > r_out:
			now = 0
		elif was == 0 and d < r_in:
			now = 1
		if now == was:
			continue
		_hex_near[h] = now
		flips += 1
		for pid: int in field.hex_pieces[h]:
			if _where[pid] != 0:
				_remove(pid)
				_append(pid, 1 if now == 1 else 2, _xf[pid])
	if DevHooks.has("lod-debug"):
		print("[lod] cam=%s flips=%d maxd=%.0f counts=%s id=%d" % [cam, flips, maxd, counts(), get_instance_id()])


## Overhead views (Command) or anything that wants every hex re-sorted on the next update.
func force_update() -> void:
	_forced = true


## Per-pid counts for tests / stats: [near, far].
func counts() -> Vector2i:
	var c := Vector2i.ZERO
	for w: int in _where:
		if w == 1:
			c.x += 1
		elif w == 2:
			c.y += 1
	return c


# --- Far meshes -------------------------------------------------------------------

static var _far: Dictionary = {}


## A very light stand-in for a model seen from 30+ m: per surface, vertices are welded by
## position (UV / normal seams no longer block the simplifier), then simplified with the
## importer's LOD generator, then vertex-clustered if that still stalls. Materials are kept.
static func far_mesh(id: String, max_tris: int) -> Mesh:
	var key: String = "%s@%d" % [id, max_tris]
	if _far.has(key):
		return _far[key]
	var full: Mesh = AssetLib.model_mesh(id)
	var lite: Mesh = AssetLib.model_mesh_lite(id, max_tris)
	if _tris(lite) <= max_tris * 1.25:
		_far[key] = lite
		return lite
	var out := ArrayMesh.new()
	var ns: int = full.get_surface_count()
	var total_full: int = _tris(full)
	for s: int in ns:
		var arrays: Array = full.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		@warning_ignore("integer_division")
		var share: float = float(idx.size() / 3) / maxf(float(total_full), 1.0)
		var budget: int = maxi(12, int(max_tris * share))
		var welded: Array = _weld(arrays)
		var best: PackedInt32Array = welded[Mesh.ARRAY_INDEX]
		if best.size() > budget * 3:
			var im := ImporterMesh.new()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, welded)
			im.generate_lods(180.0, 180.0, [])
			for li: int in im.get_surface_lod_count(0):
				var lidx: PackedInt32Array = im.get_surface_lod_indices(0, li)
				if lidx.size() < best.size():
					best = lidx
				if best.size() <= budget * 3:
					break
		if best.size() > budget * 3 * 2:
			best = _cluster(welded[Mesh.ARRAY_VERTEX], best, budget)
		if best.size() < 3:
			continue
		welded[Mesh.ARRAY_INDEX] = best
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, welded)
		out.surface_set_material(out.get_surface_count() - 1, full.surface_get_material(s))
	if out.get_surface_count() == 0 or _tris(out) >= _tris(lite):
		_far[key] = lite
		return lite
	_far[key] = out
	return out


## Unique positions only (first vertex's normal / UV / tangent wins); bones dropped.
static func _weld(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i: int in verts.size():
			idx[i] = i
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	var keep := PackedInt32Array()
	var seen: Dictionary = {}
	for i: int in verts.size():
		var v: Vector3 = verts[i]
		var k := Vector3i(roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0))
		if seen.has(k):
			remap[i] = seen[k]
		else:
			seen[k] = keep.size()
			remap[i] = keep.size()
			keep.append(i)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for a: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		var src: Variant = arrays[a]
		if src == null:
			continue
		match a:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				var p := PackedVector3Array()
				p.resize(keep.size())
				for j: int in keep.size():
					p[j] = (src as PackedVector3Array)[keep[j]]
				out[a] = p
			Mesh.ARRAY_TANGENT:
				var t := PackedFloat32Array()
				t.resize(keep.size() * 4)
				for j: int in keep.size():
					for c: int in 4:
						t[j * 4 + c] = (src as PackedFloat32Array)[keep[j] * 4 + c]
				out[a] = t
			Mesh.ARRAY_COLOR:
				var col := PackedColorArray()
				col.resize(keep.size())
				for j: int in keep.size():
					col[j] = (src as PackedColorArray)[keep[j]]
				out[a] = col
			_:
				var uv := PackedVector2Array()
				uv.resize(keep.size())
				for j: int in keep.size():
					uv[j] = (src as PackedVector2Array)[keep[j]]
				out[a] = uv
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	var n: int = 0
	for t: int in range(0, idx.size() - 2, 3):
		var a0: int = remap[idx[t]]
		var a1: int = remap[idx[t + 1]]
		var a2: int = remap[idx[t + 2]]
		if a0 == a1 or a1 == a2 or a0 == a2:
			continue
		ni[n] = a0
		ni[n + 1] = a1
		ni[n + 2] = a2
		n += 3
	ni.resize(n)
	out[Mesh.ARRAY_INDEX] = ni
	return out


## Vertex clustering on a grid that grows coarser until the budget fits; each cell is
## represented by its first vertex (keeps that vertex's attributes).
static func _cluster(verts: PackedVector3Array, idx: PackedInt32Array, budget: int) -> PackedInt32Array:
	var box := AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		box = box.expand(v)
	var res: int = 16
	var best: PackedInt32Array = idx
	while res >= 3:
		var cell: Vector3 = box.size / float(res) + Vector3.ONE * 1e-5
		var rep: Dictionary = {}
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		for i: int in verts.size():
			var k := Vector3i(((verts[i] - box.position) / cell).floor())
			if not rep.has(k):
				rep[k] = i
			remap[i] = rep[k]
		var tri_seen: Dictionary = {}
		var out := PackedInt32Array()
		for t: int in range(0, idx.size() - 2, 3):
			var a0: int = remap[idx[t]]
			var a1: int = remap[idx[t + 1]]
			var a2: int = remap[idx[t + 2]]
			if a0 == a1 or a1 == a2 or a0 == a2:
				continue
			var tk := Vector3i(a0, a1, a2)
			if tri_seen.has(tk):
				continue
			tri_seen[tk] = true
			out.append(a0)
			out.append(a1)
			out.append(a2)
		best = out
		if out.size() <= budget * 3 * 2:
			break
		res -= 2
	return best


static func _tris(m: Mesh) -> int:
	var t: int = 0
	for s: int in m.get_surface_count():
		var a: Array = m.surface_get_arrays(s)
		if a[Mesh.ARRAY_INDEX] != null:
			@warning_ignore("integer_division")
			t += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		else:
			@warning_ignore("integer_division")
			t += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
