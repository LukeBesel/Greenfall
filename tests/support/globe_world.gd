class_name GlobeWorld
extends Node3D
## Test support: the members of the slice (scenes/slice.gd) that the planting systems read, on a
## GlobeFixture planet: the field, a ground view that records hex life, the planet survey, the
## Garden and the HexLevels. Tests add what else they need as children.

class LifeView:
	extends RefCounted
	var lives: Dictionary = {}

	func set_life(id: int, life: float) -> void:
		lives[id] = life


var fixture: GlobeFixture
var field: SphereField
var view := LifeView.new()
var planet: PlanetData
var garden: Garden
var hex_levels: HexLevels


func _init(seed_v: int = 4471) -> void:
	fixture = GlobeFixture.new(seed_v)
	field = fixture.field
	planet = PlanetData.new(seed_v, 0, 10.0, GeoSphere.from_grid(fixture.grid))
	planet.generate()


## The Garden, wired the way the slice wires it. Call once the world is in the tree.
func add_garden() -> Garden:
	garden = Garden.new()
	garden.world = self
	garden.cells = fixture.cells
	add_child(garden)
	garden.setup()
	return garden


## The HexLevels (quiet: no vfx, audio or toasts). Call once the world is in the tree.
func add_hex_levels() -> HexLevels:
	hex_levels = HexLevels.new()
	hex_levels.world = self
	hex_levels.celebrate = false
	add_child(hex_levels)
	hex_levels.setup()
	return hex_levels


## The k-th land cell of the hub's region that Lumi can clean and plant (no hub ground, no water).
func land_cell(k: int = 0) -> int:
	for c: int in fixture.region():
		if field.hex_hub[c] == 0 and not field.is_water(c):
			if k == 0:
				return c
			k -= 1
	return -1


## Scoops a cell clean and makes its plant slots, the way Lumi does by working there.
func clean(cell: int) -> void:
	fixture.clean(cell)
	if garden != null:
		garden.ensure_hex(cell)
	if hex_levels != null:
		hex_levels.track(cell)
