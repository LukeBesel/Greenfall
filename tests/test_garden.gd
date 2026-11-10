extends GutTest


var _cur: Dictionary
var _world_state: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world.duplicate(true)
	GameState.world = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.world = _world_state


func _make() -> Array:
	var w := GlobeWorld.new(5)
	add_child_autofree(w)
	return [w, w.add_garden()]


func test_plant_water_grow() -> void:
	var made: Array = _make()
	var w: GlobeWorld = made[0]
	var g: Garden = made[1]
	var hid: int = w.land_cell()
	w.clean(hid)
	assert_true(w.field.is_clean(hid))
	GameState.currencies["seeds"] = BigNum.from_float(5)
	var slot: int = (g.hex_slots[hid] as PackedInt32Array)[0]
	assert_true(g.plant(slot))
	assert_eq(int(GameState.get_currency("seeds").to_float()), 4)
	assert_eq(w.planet.state[hid], PlanetData.State.PLANTED)
	assert_eq(w.fixture.cells.state[hid], PlanetData.State.PLANTED, "the globe's cells follow")
	# Without water it doesn't grow.
	g._tick = 100.0
	g._process(0.0)
	assert_eq(g.slot_stage[slot], 0)
	# The species is picked at random and the slowest stage takes up to ~6 min at early-game
	# growth speed, so keep it watered long enough for any species to reach its first stage.
	for i: int in 120:
		g.water(slot, 60.0)
		g._tick = 10.0
		g._process(0.0)
		if g.slot_stage[slot] > 0:
			break
	assert_gt(g.slot_stage[slot], 0)
	assert_gt(float(w.view.lives.get(hid, 0.0)), 0.0)


func test_no_seeds_no_planting() -> void:
	var made: Array = _make()
	var w: GlobeWorld = made[0]
	var g: Garden = made[1]
	var hid: int = w.land_cell()
	w.clean(hid)
	GameState.currencies["seeds"] = BigNum.zero()
	var slot: int = (g.hex_slots[hid] as PackedInt32Array)[0]
	assert_false(g.plant(slot))


func test_plant_parts_split_variants() -> void:
	var parts: Array[Mesh] = PlantParts.variants("celandine_01")
	assert_eq(parts.size(), 5, "five LOD0 clumps, LOD copies skipped")
	var whole: AABB = AssetLib.model_aabb("celandine_01")
	for m: Mesh in parts:
		assert_lt(m.get_aabb().size.x, whole.size.x * 0.5, "a single clump, not the file's whole row")


func test_meadow_meshes_build() -> void:
	for m: ArrayMesh in [Meadow._tuft_mesh(), Meadow._flower_mesh()]:
		assert_eq(m.get_surface_count(), 1)
		assert_almost_eq(m.get_aabb().end.y, 1.0, 0.25, "unit height (the shader scales it)")
