class_name SphereWater
extends Node3D
## [orbD] Lake surfaces on the walkable globe: a hex of water over every water cell in the
## streamer's near ring (the ground there sits SphereTerrain.water_drop low, its bed), built from
## the grid's shared corners so neighbouring water cells meet without seams, a little below the
## land. murky -> clear as the cell is cleaned (sphere_water.gdshader, the flat lakes' look).
## Freed when a cell leaves the ring; the far shell shows lakes from afar.

const BELOW_LAND: float = 0.12

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var _mat: ShaderMaterial
var _cell: Dictionary = {}  # cell -> MeshInstance3D


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


func _on_near(added: PackedInt32Array, removed: PackedInt32Array) -> void:
	for c: int in removed:
		if _cell.has(c):
			(_cell[c] as Node).queue_free()
			_cell.erase(c)
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


## Clarity from the cell's junk: a cleaned lake goes clear.
func _tint(c: int) -> void:
	var mi: MeshInstance3D = _cell[c]
	var clear: float = 1.0 - cells.junk[c]
	mi.set_instance_shader_parameter("clarity", clear)


func count() -> int:
	return _cell.size()
