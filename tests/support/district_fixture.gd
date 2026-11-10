class_name DistrictFixture
extends RefCounted
## Test support: a round planet of junk with hub sites spread over it, and the Districts and
## Restoration of any registered planet built on it. The grid is a small one whatever the planet's
## own size: the rules only need hexes and site positions. Sites stand on the centres of the
## grid's twenty faces, as far from its twelve five-sided cells as a hex can be, so a region of up
## to 26 rings is made of six-sided cells only.

const LEVEL: int = 6
const FIXTURE_PLANETS: String = "res://tests/fixtures/planets"

var def: PlanetDefinition
var grid: SphereGrid
var cells: SphereCells
var site_cells := PackedInt32Array()
var districts: Districts
var restoration: Restoration


## Builds the fixture for a registered planet. Add `districts` and `restoration` to the tree (or
## free them) in the test.
func _init(planet_id: StringName, with_systems: bool = true, level: int = LEVEL) -> void:
	def = Planets.by_id(planet_id)
	grid = SphereGrid.cached(level)
	cells = SphereCells.new(grid.cell_count())
	cells.junk.fill(1.0)
	site_cells = face_centre_cells(grid, def.hub_count)
	if with_systems:
		build_systems()


## Fresh Districts and Restoration on the fixture's cells as they are now (a "load").
func build_systems() -> void:
	districts = Districts.new()
	districts.setup(def, grid, cells, site_cells)
	restoration = Restoration.new()
	restoration.setup(def, districts, cells)


func free_systems() -> void:
	for node: Node in [districts, restoration]:
		if is_instance_valid(node):
			node.free()
	districts = null
	restoration = null


## Cleans a hex and sets its regrowth stage (0 = dirty again), the way play changes the globe.
func set_cell_stage(c: int, stage: int) -> void:
	if stage <= 0:
		cells.set_state(c, PlanetData.State.JUNK)
		cells.set_junk(c, 1.0)
		return
	cells.set_junk(c, 0.0)
	cells.set_state(c, PlanetData.State.CLEAN)
	cells.set_level(c, stage)


## Sets the first `count` land hexes of a district (nearest its site first) to `stage`.
## count < 0 = every land hex. Returns how many were set.
func set_district_stage(id: String, stage: int, count: int = -1) -> int:
	var done: int = 0
	for c: int in districts.cells_of(id):
		if count >= 0 and done >= count:
			break
		if Districts.cell_stage(cells, c) == Districts.NOT_LAND:
			continue
		set_cell_stage(c, stage)
		done += 1
	return done


## `count` hexes on face centres of the grid, far from every five-sided cell and from each other.
static func face_centre_cells(g: SphereGrid, count: int) -> PackedInt32Array:
	var corners: Array[Vector3] = []
	for c: int in g.cell_count():
		if g.is_pentagon(c):
			corners.append(g.centers[c].normalized())
	var out := PackedInt32Array()
	for a: int in corners.size():
		for b: int in range(a + 1, corners.size()):
			for c: int in range(b + 1, corners.size()):
				# Three corners of one face are each about 63 degrees apart.
				if corners[a].angle_to(corners[b]) < 1.2 and corners[b].angle_to(corners[c]) < 1.2 and corners[a].angle_to(corners[c]) < 1.2:
					out.append(g.cell_at((corners[a] + corners[b] + corners[c]).normalized()))
	return out.slice(0, count)
