class_name GlobeFixture
extends RefCounted
## Test support: a small round planet (10 m cells, all junk) with a SphereField, and a hub frame on
## it (a Node3D standing on a cell with +Y up, the way planet/orbit/hub_frame.gd hosts the per-hub
## systems). Tests of shared systems that place things on the ground build their world from this.

const LEVEL: int = 5
const HUB_CELL: int = 100
const REGION_RINGS: int = 6

var grid: SphereGrid
var terrain: SphereTerrain
var cells: SphereCells
var field: SphereField


func _init(seed_v: int = 4471) -> void:
	grid = SphereGrid.new()
	grid.generate(LEVEL)
	grid.radius_m = SphereGrid.radius_for(LEVEL, 10.0)
	terrain = SphereTerrain.new(grid, seed_v)
	cells = SphereCells.new(grid.cell_count())
	cells.junk.fill(1.0)
	field = SphereField.new(grid, terrain, cells, seed_v)


## The hub's region: the cells within REGION_RINGS of the hub cell.
func region() -> PackedInt32Array:
	return grid.cells_around(HUB_CELL, REGION_RINGS)


## Where the hub frame stands: on the hub cell's ground, +Y up.
func frame_transform() -> Transform3D:
	var p: Vector3 = field.hex_center(HUB_CELL)
	return Transform3D(SphereGrid.frame(p.normalized()), p)


## Scoops every piece of a cell, the way Lumi cleans it.
func clean(cell: int) -> void:
	field.materialize(cell)
	for pid: int in field.pieces_in(cell):
		field.remove_piece(pid)
