class_name MeadowSphere
extends Node3D
## [orbB] The meadow on the globe: restored cells visibly turn green, as plants/meadow.gd does on
## the flat field (that one grows in the flat ground shader from the field's life texture, which
## the globe doesn't have). Per cell, by hex level: Planted -> sprouts in rows; Growing -> young
## grass; Sustained -> a closed sward with flowers; Thriving -> a dense meadow with flowers,
## shrubs, ferns and saplings (Meadow.THRIVE_MODELS). Meadow's own tuft / flower / sprout meshes,
## coloured per instance (the Anvil sites' grass shader). Pure presentation: rebuilt from the hex
## levels, never saved.
## Lives in the HubFrame (frame-local, +Y up): a hub's region only, nearest Lumi first, a few cells
## a frame; one MultiMesh per cell and kind, faded out past VIEW_M.

const VIEW_M: float = 120.0
const PER_FRAME: int = 2  # about 0.9 ms a cell (headless)
## Instances per cell by hex level (0..5), per quality preset scale.
const GRASS: Array[int] = [0, 0, 0, 70, 140, 200]
const FLOWERS: Array[int] = [0, 0, 0, 0, 30, 60]
const SPROUTS: Array[int] = [0, 0, 36, 20, 0, 0]
const QUALITY: Array[float] = [0.55, 0.75, 1.0, 1.2]

var world: Node
var frame_cells := PackedInt32Array()
var _built: Dictionary = {}  # cell -> level it was built at
var _queue: Array[int] = []
var _t: float = 0.0
var _mat: ShaderMaterial
var _meshes: Array = []


func setup(p_world: Node) -> void:
	world = p_world
	name = "MeadowSphere"
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://planet/planets/anvil/anvil_grass.gdshader")
	_meshes = [Meadow._tuft_mesh(), Meadow._flower_mesh(), Meadow._sprout_mesh()]
	EventBus.hex_level_changed.connect(func(hid: int, _l: int) -> void:
		if _built.has(hid):
			_built.erase(hid)
			_free_cell(hid)
		_t = 0.0)


func _hl() -> HexLevels:
	return world.get("hex_levels") as HexLevels


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 1.0
		_plan()
	var n: int = 0
	while not _queue.is_empty() and n < PER_FRAME:
		_build_cell(_queue.pop_front())
		n += 1


## Cells at Planted or above in this region, nearest Lumi first; built ones that changed level
## are rebuilt (the level signal frees them).
func _plan() -> void:
	var hl: HexLevels = _hl()
	var patch: Node3D = world.get("patch") as Node3D
	if hl == null or patch == null:
		return
	var lp: Vector3 = to_local(patch.global_position)
	var want: Array = []
	var region: Dictionary = {}
	for c: int in frame_cells:
		region[c] = true
	for hid: Variant in hl.levels:
		var h: int = int(hid)
		if not region.has(h) or int(hl.levels[hid]) < 2 or _built.has(h):
			continue
		var d: float = to_local(world.field.hex_center(h)).distance_to(lp)
		if d < VIEW_M + 40.0:
			want.append([d, h])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	_queue.clear()
	for e: Array in want:
		_queue.append(int(e[1]))


func _build_cell(hid: int) -> void:
	var hl: HexLevels = _hl()
	if hl == null or _built.has(hid):
		return
	var lvl: int = clampi(hl.level_of(hid), 0, 5)
	_built[hid] = lvl
	var f: SphereField = world.field
	var q: float = QUALITY[clampi(Settings.quality, 0, 3)]
	var ctr: Vector3 = f.hex_center(hid)
	var fr: Basis = SphereGrid.frame(ctr.normalized())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([f.seed_value, hid, 515])
	var counts: Array[int] = [int(GRASS[lvl] * q), int(FLOWERS[lvl] * q), int(SPROUTS[lvl] * q)]
	var row_a: float = rng.randf() * PI
	for kind: int in 3:
		if counts[kind] <= 0:
			continue
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		var tries: int = 0
		while xfs.size() < counts[kind] and tries < counts[kind] * 4:
			tries += 1
			var lx: float
			var lz: float
			if kind == 2:  # sprouts in planting rows across the cell
				var row: int = rng.randi_range(-3, 3)
				var along: float = rng.randf_range(-1.0, 1.0) * f.hex_size * 0.8
				lx = cos(row_a) * along - sin(row_a) * row * 0.8
				lz = sin(row_a) * along + cos(row_a) * row * 0.8
			else:
				var r: float = sqrt(rng.randf()) * f.hex_size * 0.92
				var a: float = rng.randf() * TAU
				lx = cos(a) * r
				lz = sin(a) * r
			var gp: Vector3 = f.terrain.ground((ctr + fr.x * lx + fr.z * lz).normalized())
			if f.hex_at(gp) != hid:
				continue
			var lp: Vector3 = to_local(gp)
			var lush: float = clampf(0.35 + 0.15 * lvl + rng.randf_range(-0.2, 0.2), 0.0, 1.0)
			var hgt: float = (lerpf(0.25, 0.85, lush) if kind != 2 else 0.35) * rng.randf_range(0.75, 1.2) * (0.7 if kind == 1 else 1.0)
			var wid: float = rng.randf_range(0.8, 1.3) * (0.6 if kind == 1 else 1.0)
			var up: Vector3 = (global_basis.inverse() * gp.normalized()).normalized()
			var b: Basis = Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, rng.randf() * TAU)
			xfs.append(Transform3D(b * Basis.from_scale(Vector3(wid, hgt, wid)), lp - up * 0.02))
			var g := Color(0.3, 0.52, 0.18).lerp(Color(0.5, 0.52, 0.22), rng.randf() * (1.0 - lush))
			cols.append(Color(g.r, g.g, g.b, rng.randf()))
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[kind]
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_custom_data(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Meadow_%d_%d" % [hid, kind]
		mmi.multimesh = mm
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = VIEW_M
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	if lvl >= 5:
		_thrive(hid, fr, ctr, rng)


## Thriving: a few shrubs, ferns and saplings per cell (Meadow.THRIVE_MODELS), on the ground.
func _thrive(hid: int, fr: Basis, ctr: Vector3, rng: RandomNumberGenerator) -> void:
	var f: SphereField = world.field
	for spec: Array in Meadow.THRIVE_MODELS:
		var mesh: Mesh = AssetLib.model_mesh_lite(str(spec[0]), 1500)
		if mesh == null:
			continue
		var xfs: Array[Transform3D] = []
		for k: int in int(spec[1]):
			var r: float = sqrt(rng.randf()) * f.hex_size * 0.8
			var a: float = rng.randf() * TAU
			var gp: Vector3 = f.terrain.ground((ctr + fr.x * cos(a) * r + fr.z * sin(a) * r).normalized())
			if f.hex_at(gp) != hid:
				continue
			var up: Vector3 = (global_basis.inverse() * gp.normalized()).normalized()
			var sc: float = rng.randf_range(float(spec[2]), float(spec[3]))
			xfs.append(Transform3D(Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, a * 3.0).scaled(Vector3.ONE * sc), to_local(gp)))
		if xfs.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Meadow_%d_t%s" % [hid, str(spec[0])]
		mmi.multimesh = mm
		mmi.visibility_range_end = VIEW_M
		add_child(mmi)


func _free_cell(hid: int) -> void:
	var pre: String = "Meadow_%d_" % hid
	for c: Node in get_children():
		if String(c.name).begins_with(pre):
			remove_child(c)
			c.queue_free()


## Cells built and instances per kind (headless checks).
func census() -> Dictionary:
	var n: Dictionary = {"cells": _built.size(), "grass": 0, "flowers": 0, "sprouts": 0, "thrive": 0}
	for c: Node in get_children():
		if c is MultiMeshInstance3D:
			var nm: String = String(c.name)
			var k: String = nm.get_slice("_", 2)
			var cnt: int = (c as MultiMeshInstance3D).multimesh.instance_count
			match k:
				"0": n["grass"] = int(n["grass"]) + cnt
				"1": n["flowers"] = int(n["flowers"]) + cnt
				"2": n["sprouts"] = int(n["sprouts"]) + cnt
				_: n["thrive"] = int(n["thrive"]) + cnt
	return n
