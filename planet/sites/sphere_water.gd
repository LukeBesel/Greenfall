class_name SphereWater
extends Node3D
## [orbD] Lake surfaces on the walkable globe: a hex of water over every water cell in the
## streamer's near ring (the ground there sits SphereTerrain.water_drop low, its bed), built from
## the grid's shared corners so neighbouring water cells meet without seams, a little below the
## land. murky -> clear as the cell is cleaned (sphere_water.gdshader, the flat lakes' look).
## Freed when a cell leaves the ring; the far shell shows lakes from afar.
## As on the flat (water/water_view.gd): fish jump in clear lake cells (a few per cell, each
## jumping now and then with a splash), and cleaning a lake cell Lumi can see plays the lake-clear
## moment (chime, whoosh, a little shake, Wren's line) and stocks it.

const BELOW_LAND: float = 0.25  # [v1world] was 0.12: the chunk bank (sphere_chunk_job._wetness) crosses this inside the cell
const FISH_PER_CELL: int = 3
const FISH_SPREAD: float = 5.0  # jump starts within this far of the cell centre (10 m cells)

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var _mat: ShaderMaterial
var _cell: Dictionary = {}  # cell -> MeshInstance3D
var world: Node  # the slice (its wren speaks the lake line)
var _fish: Array[Dictionary] = []  # {node, cell, lake, speed, phase, a, b, splashed}; a/b in the lake's frame
var _fish_mesh: Mesh
var _fish_mat: StandardMaterial3D


func setup_globe(g: Node) -> void:
	grid = g.get("grid")
	terrain = g.get("terrain")
	cells = g.get("cells")
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://planet/sites/sphere_water.gdshader")
	_mat.set_shader_parameter("wave_nrm", AssetLib.tex("rubble", "nor_gl"))
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
			_tint(c))
	EventBus.hex_cleaned.connect(_on_clean)


func _on_near(added: PackedInt32Array, removed: PackedInt32Array) -> void:
	for c: int in removed:
		if _cell.has(c):
			(_cell[c] as Node).queue_free()
			_cell.erase(c)
			_fish = _fish.filter(func(f: Dictionary) -> bool: return int(f["cell"]) != c)
	for c: int in added:
		if cells.state[c] == 5 and not _cell.has(c):
			_build(c)


func _build(c: int) -> void:
	var dir: Vector3 = grid.centers[c]
	var f: Basis = SphereGrid.frame(dir)
	var origin: Vector3 = dir * (terrain.R + terrain.height(dir) - BELOW_LAND)
	var xf := Transform3D(f, origin)
	var inv: Transform3D = xf.affine_inverse()
	var corners: PackedVector3Array = grid.corners(c)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctr: Vector3 = inv * origin
	var pts: Array[Vector3] = []
	for k: int in corners.size():
		var d: Vector3 = corners[k].normalized()
		pts.append(inv * (d * (terrain.R + terrain.height(d) - BELOW_LAND)))
	for k: int in pts.size():
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[(k + 1) % pts.size()]
		for v: Vector3 in [ctr, b, a] if (b - ctr).cross(a - ctr).dot(Vector3.UP) > 0.0 else [ctr, a, b]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Lake%d" % c
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	add_child(mi)
	_cell[c] = mi
	_tint(c)
	if _clear(c):
		_stock_fish(c)


## Clarity from the cell's junk: a cleaned lake goes clear.
func _tint(c: int) -> void:
	var mi: MeshInstance3D = _cell[c]
	var clear: float = 1.0 - cells.junk[c]
	mi.set_instance_shader_parameter("clarity", clear)


func _clear(c: int) -> bool:
	return SphereCells.clean_left(cells.junk[c])  # [v2feel]


func count() -> int:
	return _cell.size()


## Fish jumping (for checks).
func fish_count() -> int:
	return _fish.size()


## The lake-clear moment (flat WaterView._on_clean), for a lake cell Lumi is near.
func _on_clean(hid: int, _pos: Vector3, _bonus: BigNum) -> void:
	if hid < 0 or hid >= cells.n or cells.state[hid] != 5 or not _cell.has(hid):
		return
	Audio.play("chime", 0.6, -2.0)
	Audio.play("whoosh", 0.4, -6.0)
	EventBus.shake_requested.emit(0.1)
	var wren: Variant = world.get("wren") if world else null
	if wren is Wren:
		(wren as Wren).line_started.emit(tr("The water... I can see the bottom. Lumi, there's something moving down there."), 1)
	if not _fish.any(func(f: Dictionary) -> bool: return int(f["cell"]) == hid):
		_stock_fish(hid)


func _stock_fish(c: int) -> void:
	if _fish_mesh == null:
		_fish_mesh = ProcMesh.capsule(0.05, 0.28)
		_fish_mat = StandardMaterial3D.new()
		_fish_mat.albedo_color = Color(0.75, 0.78, 0.8)
		_fish_mat.metallic = 0.6
		_fish_mat.roughness = 0.3
	var lake: MeshInstance3D = _cell[c]
	for i: int in FISH_PER_CELL:
		var n := MeshInstance3D.new()
		n.mesh = _fish_mesh
		n.material_override = _fish_mat
		n.visible = false
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lake.add_child(n)
		var fish: Dictionary = {"node": n, "cell": c, "speed": randf_range(0.6, 1.1), "phase": randf() * 6.0}
		_new_jump(fish)
		_fish.append(fish)


func _new_jump(fish: Dictionary) -> void:
	var a := Vector3(randf_range(-FISH_SPREAD, FISH_SPREAD), 0.0, randf_range(-FISH_SPREAD, FISH_SPREAD))
	var d := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(1.0, 2.0)
	fish["a"] = a
	fish["b"] = a + d
	fish["splashed"] = false


func _process(_delta: float) -> void:
	if _fish.is_empty():
		return
	var t: float = Time.get_ticks_msec() * 0.001
	for fish: Dictionary in _fish:
		var n: MeshInstance3D = fish["node"]
		if not is_instance_valid(n):
			continue
		var ph: float = fmod(t * float(fish["speed"]) + float(fish["phase"]), 6.0)
		if ph < 1.0:
			var a: Vector3 = fish["a"]
			var b: Vector3 = fish["b"]
			n.visible = true
			n.position = a.lerp(b, ph) + Vector3(0, sin(ph * PI) * 0.9, 0)
			n.rotation = Vector3(0, atan2(b.x - a.x, b.z - a.z), cos(ph * PI) * 1.2)
			if ph >= 0.97 and not bool(fish.get("splashed", false)):
				fish["splashed"] = true
				var lake: Node3D = n.get_parent()
				Vfx.burst("soil", lake.global_transform * (b + Vector3(0, 0.1, 0)), Color(0.7, 0.85, 1.0, 0.8), 0.4)
		else:
			n.visible = false
			if ph > 5.9:
				_new_jump(fish)
