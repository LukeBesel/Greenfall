extends GutTest
## [green] Restored-ground previews (GardenDev), meadow helpers and single plant variants.

class FakeView:
	extends RefCounted
	var lives: Dictionary = {}
	func set_life(id: int, life: float) -> void:
		lives[id] = life
	func hide_piece(_pid: int) -> void:
		pass
	func refresh_hex(_id: int, _f: bool) -> void:
		pass

class FakeLitter:
	extends RefCounted
	func refresh_hex(_id: int) -> void:
		pass

class FakeWorld:
	extends Node
	var field: HexField
	var view := FakeView.new()
	var litter := FakeLitter.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()
	var garden: Garden
	var hex_levels: HexLevels

var _cur: Dictionary
var _world_state: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world.duplicate(true)
	_flags = GameState.flags.duplicate(true)
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world_state
	GameState.flags = _flags


func _make() -> FakeWorld:
	var w := FakeWorld.new()
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	w.field = HexField.new(2, 10.0, 5)
	w.field.generate(types, Vector2i(5, 8))
	w.planet = PlanetData.new(5, 3, 10.0)
	w.planet.generate()
	w.slice_cells.resize(w.field.hex_count())
	for i: int in w.field.hex_count():
		w.slice_cells[i] = i
	add_child_autofree(w)
	w.garden = Garden.new()
	w.garden.world = w
	w.add_child(w.garden)
	w.garden.setup()
	w.hex_levels = HexLevels.new()
	w.hex_levels.world = w
	w.hex_levels.celebrate = false
	w.add_child(w.hex_levels)
	w.hex_levels.setup()
	return w


func _land_with_slots(w: FakeWorld) -> int:
	for h: int in GardenDev.land_by_distance(w):
		if (w.garden.hex_slots.get(h, PackedInt32Array()) as PackedInt32Array).size() >= 4:
			return h
	return -1


func test_grow_hex_levels_give_rising_life() -> void:
	var lives: Array[float] = []
	for lv: int in [2, 3, 4, 5]:
		var w: FakeWorld = _make()
		var h: int = _land_with_slots(w)
		assert_gt(h, -1)
		GardenDev.grow_hex(w, h, lv)
		assert_true(w.field.is_clean(h), "cleaned")
		assert_eq(w.hex_levels.level_of(h), lv)
		lives.append(float(w.garden.hex_life.get(h, 0.0)))
		assert_almost_eq(float(w.view.lives.get(h, -1.0)), lives[-1], 0.001, "life reaches the ground view")
	for i: int in range(1, lives.size()):
		assert_gt(lives[i], lives[i - 1], "each level is greener than the one before")
	assert_lt(lives[0], 0.35, "Planted reads as planted (tilled soil + sprouts)")
	assert_gte(lives[3], 0.8, "Thriving is fully alive")


func test_grow_hex_leaves_work_for_watering_robots() -> void:
	var w: FakeWorld = _make()
	var h: int = _land_with_slots(w)
	GardenDev.grow_hex(w, h, 4)
	var partial: int = 0
	for s: int in w.garden.hex_slots[h]:
		if w.garden.slot_species[s] >= 0:
			var full: float = float(w.garden.species[w.garden.slot_species[s]].get("water_s", 120))
			assert_gt(w.garden.slot_water[s], 0.0)
			if w.garden.slot_water[s] < full:
				partial += 1
	assert_gt(partial, 0, "plants are part-watered so Drips have something to do")


func test_hash_is_stable_and_in_range() -> void:
	for i: int in 200:
		var v: float = Meadow._hh(i, 3)
		assert_between(v, 0.0, 1.0)
		assert_eq(v, Meadow._hh(i, 3))


func test_plant_parts_split_variants() -> void:
	var parts: Array[Mesh] = PlantParts.variants("celandine_01")
	assert_eq(parts.size(), 5, "five LOD0 clumps, LOD copies skipped")
	var whole: AABB = AssetLib.model_aabb("celandine_01")
	for m: Mesh in parts:
		assert_lt(m.get_aabb().size.x, whole.size.x * 0.5, "a single clump, not the file's whole row")


func test_meadow_meshes_build() -> void:
	for m: ArrayMesh in [Meadow._tuft_mesh(), Meadow._flower_mesh(), Meadow._sprout_mesh()]:
		assert_eq(m.get_surface_count(), 1)
		assert_almost_eq(m.get_aabb().end.y, 1.0, 0.25, "unit height (the shader scales it)")
