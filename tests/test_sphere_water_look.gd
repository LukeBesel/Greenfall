extends GutTest
## [v4world] Owner playtest 3 #53: the globe's lake surface reads as water. Its faces point up
## (they were wound the other way and culled from above, so only the lake bed showed), its
## vertices carry shore / depth for the shader, the sky uniforms follow the sky material, and the
## state texture carries a lake's murk to the far ground water.

var _grid: SphereGrid
var _terrain: SphereTerrain
var _cells: SphereCells
var _lake: Array[int] = []


func before_all() -> void:
	_grid = SphereGrid.for_hex_size(7, 10.0)
	_terrain = SphereTerrain.new(_grid, 4471)
	_cells = SphereCells.new(_grid.cell_count())
	# A lake: a cell and two rings round it.
	var c0: int = _grid.cell_at(Vector3(0.3, 0.8, 0.2).normalized())
	for c: int in _grid.cells_around(c0, 2):
		_cells.state[c] = 5
		_cells.junk[c] = 1.0
		_lake.append(c)


func _water() -> SphereWater:
	var sw := SphereWater.new()
	sw.grid = _grid
	sw.terrain = _terrain
	sw.cells = _cells
	sw.set("_mat", ShaderMaterial.new())
	add_child_autofree(sw)
	return sw


func test_faces_point_up() -> void:
	var sw: SphereWater = _water()
	sw._build(_lake[0])
	var mi: MeshInstance3D = sw.get_child(0) as MeshInstance3D
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	assert_gt(v.size(), 0)
	var up_ok: int = 0
	for i: int in range(0, v.size(), 3):
		# Godot's front faces are clockwise: seen from above, the winding's normal points down.
		if (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).dot(Vector3.UP) < 0.0:
			up_ok += 1
	assert_eq(up_ok, v.size() / 3, "every face is a front face seen from above")


func test_shore_and_depth_in_vertex_colours() -> void:
	var sw: SphereWater = _water()
	var mid: Color = sw._shore_col(_grid.centers[_lake[0]])
	var edge_cell: int = _lake[_lake.size() - 1]  # outer ring: touches land
	var land: int = -1
	for o: int in _grid.neighbors(edge_cell):
		if _cells.state[o] != 5:
			land = o
	var near_line: Vector3 = _grid.centers[edge_cell].lerp(_grid.centers[land], 0.4).normalized()  # ~1.7 m off the waterline
	var edge: Color = sw._shore_col(near_line)
	assert_gt(edge.r, mid.r + 0.3, "foam side: nearer the shore by the lake's edge")
	assert_gt(mid.g, edge.g, "deeper in the middle")
	var line: Vector3 = (_grid.centers[edge_cell] + _grid.centers[land]).normalized()
	assert_gt(sw._shore_col(line).r, 0.9, "the waterline itself is shore")


func test_sky_params_follow_the_sky() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://planet/orbit/orbit_sky.gdshader")
	sm.set_shader_parameter("day", 0.0)
	var night: Dictionary = SphereWater.sky_params(sm, null)
	sm.set_shader_parameter("day", 1.0)
	var day: Dictionary = SphereWater.sky_params(sm, null)
	assert_lt((night["sky_zen"] as Vector3).length(), (day["sky_zen"] as Vector3).length(), "a darker sky in the water at night")
	assert_eq(float(day["sky_day"]), 1.0)


func test_state_texture_carries_lake_murk() -> void:
	var c: int = _lake[0]
	_cells.junk[c] = 0.8
	_cells.refresh_all()
	assert_almost_eq(_cells.image.get_pixel(c % SphereCells.TEX_W, c / SphereCells.TEX_W).r, 0.8, 0.01, "a lake cell's junk is in the red channel")
