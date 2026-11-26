extends GutTest
## [orbB] JunkLOD on the globe (SphereJunkView): near/far buffers by camera distance, the
## per-frame budget, and hides/moves on the right buffer.

var _grid: SphereGrid
var _terrain: SphereTerrain
var _field: SphereField
var _view: SphereJunkView
var _cam: Camera3D
var _cells: PackedInt32Array
var _centre: Vector3


func before_all() -> void:
	_grid = SphereGrid.for_hex_size(7, 10.0)
	_terrain = SphereTerrain.new(_grid, 4471)
	var sc := SphereCells.new(_grid.cell_count())
	_field = SphereField.new(_grid, _terrain, sc, 4471)
	var c0: int = _grid.cell_at(Vector3(0.3, 0.8, 0.2).normalized())
	_cells = _grid.cells_around(c0, 4)
	for c: int in _cells:
		_field.materialize(c)
	_centre = _field.hex_center(c0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_position = _centre + _centre.normalized() * 5.0
	_cam.current = true
	_view = SphereJunkView.new()
	add_child(_view)
	_view.setup(_field)


func after_all() -> void:
	_view.queue_free()
	_cam.queue_free()


func _alive_count() -> int:
	var n: int = 0
	for c: int in _cells:
		for pid: int in _field.pieces_in(c):
			n += _field.piece_alive[pid]
	return n


func test_budget_then_bands() -> void:
	_view.budget = 200
	_view.rebuild(_cells)
	_view._pump(_view.budget)
	assert_lt(_view.counts().x + _view.counts().y, _alive_count(), "one frame shows at most the budget (plus one cell)")
	_view.flush()
	var c: Vector2i = _view.counts()
	assert_eq(c.x + c.y, _alive_count(), "every alive piece of the ring is drawn once")
	assert_gt(c.x, 0, "full meshes near the camera")
	assert_gt(c.y, 0, "light meshes past the near radius")
	for cell: int in _cells:
		var d: float = _field.hex_center(cell).distance_to(_cam.global_position)
		for pid: int in _field.pieces_in(cell):
			if _field.piece_alive[pid] == 1 and d > _view.near_radius + JunkLod.HYSTERESIS:
				assert_eq(_view._where[pid], 2, "far cell -> far buffer")


func test_camera_move_flips_and_hide() -> void:
	_view.flush()
	var before: Vector2i = _view.counts()
	var far_cell: int = _cells[_cells.size() - 1]
	_cam.global_position = _field.hex_center(far_cell) + _field.hex_center(far_cell).normalized() * 5.0
	_view.update_bands(_cam.global_position)
	assert_gt(int(_view.stats.get("flips", 0)), 0, "cells change band when the camera moves")
	var pid: int = _field.pieces_in(far_cell)[0]
	assert_eq(_view._where[pid], 1, "now near")
	_field.remove_piece(pid)
	_view.hide_piece(pid)
	assert_eq(_view._where[pid], 0)
	assert_eq(_view.counts().x + _view.counts().y, before.x + before.y - 1)


func test_ring_leaves() -> void:
	_view.flush()
	var keep: PackedInt32Array = _cells.slice(0, 7)
	_view.rebuild(keep)
	_view.flush()
	var n: int = 0
	for c: int in keep:
		for pid: int in _field.pieces_in(c):
			n += _field.piece_alive[pid]
	assert_eq(_view.counts().x + _view.counts().y, n, "cells that left the ring are hidden")
