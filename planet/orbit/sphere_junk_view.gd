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
var _mm_by_model: Dictionary = {}  # model id -> MultiMeshInstance3D
var _slot: Dictionary = {}  # pid -> [model id, instance index]
var _near := PackedInt32Array()
var _hidden_xf := Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3.ZERO)


func setup(p_field: HexField) -> void:
	field = p_field
	sfield = p_field as SphereField


func _process(_delta: float) -> void:
	pass  # [orbB] no flat ground, LOD or life texture to tick


func _mm_for(model: String) -> MultiMeshInstance3D:
	if _mm_by_model.has(model):
		return _mm_by_model[model]
	var mesh: Mesh = AssetLib.model_mesh_lite(model, 1500) if model != "" and AssetLib.has_model(model) else null
	if mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 0.4, 0.4)
		mesh = bm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 4.0
	mmi.name = "Junk_" + model
	add_child(mmi)
	_mm_by_model[model] = mmi
	return mmi


## Redraws the alive pieces of these cells (call when the near ring changes).
func rebuild(near: PackedInt32Array) -> void:
	var t0: int = Time.get_ticks_usec()
	_near = near
	var groups: Dictionary = {}  # model -> PackedInt32Array of pids
	for c: int in near:
		for pid: int in sfield.pieces_in(c):
			if sfield.piece_alive[pid] == 0:
				continue
			var m: String = sfield.piece_model[pid]
			var arr: PackedInt32Array = groups.get(m, PackedInt32Array())
			arr.append(pid)
			groups[m] = arr
	_slot.clear()
	var total: int = 0
	for m: String in _mm_by_model.keys():
		if not groups.has(m):
			(_mm_by_model[m] as MultiMeshInstance3D).multimesh.instance_count = 0
	for m: String in groups:
		var pids: PackedInt32Array = groups[m]
		var mm: MultiMesh = _mm_for(m).multimesh
		mm.instance_count = 0
		mm.instance_count = pids.size()
		var buf := PackedFloat32Array()
		buf.resize(pids.size() * 12)
		for i: int in pids.size():
			var xf: Transform3D = sfield.piece_xf[pids[i]]
			var b: Basis = xf.basis
			var o: int = i * 12
			buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = xf.origin.x
			buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = xf.origin.y
			buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = xf.origin.z
			_slot[pids[i]] = [m, i]
		mm.buffer = buf
		total += pids.size()
	stats["pieces"] = total
	stats["rebuild_us"] = Time.get_ticks_usec() - t0


func piece_transform(pid: int) -> Transform3D:
	return sfield.piece_xf[pid]


func piece_mesh(pid: int) -> Mesh:
	var m: String = sfield.piece_model[pid]
	return AssetLib.model_mesh(m) if m != "" and AssetLib.has_model(m) else BoxMesh.new()


func hide_piece(pid: int) -> void:
	var s: Variant = _slot.get(pid)
	if s == null:
		return
	(_mm_by_model[s[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(int(s[1]), _hidden_xf)


func move_piece(pid: int, pos: Vector3) -> void:
	sfield.piece_pos[pid] = pos
	var xf: Transform3D = sfield.piece_xf[pid]
	xf.origin = pos
	sfield.piece_xf[pid] = xf
	var s: Variant = _slot.get(pid)
	if s != null:
		(_mm_by_model[s[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(int(s[1]), xf)


func set_focus_hex(_id: int) -> void:
	pass  # phase B: the ground shader's focus ring reads a cell id


func refresh_hex(_id: int, _flipped_now: bool = false) -> void:
	pass  # the ground reads SphereCells' state texture


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
