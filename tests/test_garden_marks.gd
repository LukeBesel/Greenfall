extends GutTest
## [v4grow] Owner playtest 3 #51: plants you can see. Globe plant sizes per stage, and the
## GardenMarks layer: soil mounds (wet / dry), sprouts, thirsty drops, perk-up on watering.


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
	var g: Garden = w.add_garden()
	var m: GardenMarks = GardenMarks.new()
	m.world = w
	m.garden = g
	w.add_child(m)
	return [w, g, m]


func _plant3(w: GlobeWorld, g: Garden) -> PackedInt32Array:
	var hid: int = w.land_cell()
	w.clean(hid)
	GameState.currencies["seeds"] = BigNum.from_float(5)
	var ids: PackedInt32Array = g.hex_slots[hid]
	var out := PackedInt32Array()
	for k: int in 3:
		assert_true(g.plant(ids[k]))
		out.append(ids[k])
	return out


func test_globe_plants_have_real_height() -> void:
	var made: Array = _make()
	var g: Garden = made[1]
	var slots: PackedInt32Array = _plant3(made[0], g)
	var s: int = slots[0]
	assert_eq(g.globe_scale(s), 0.0, "a seed: only the sprout shows")
	for st: int in [2, 3, 4]:
		g.slot_stage[s] = st
		var vs: Array = PlantParts.variants(str(g.species[g.slot_species[s]]["model"]), Garden.VARIANT_TRIS)
		var sz: Vector3 = (vs[g._variant_of(s)] as Mesh).get_aabb().size
		var h: float = sz.y * g.globe_scale(s)
		var wd: float = maxf(sz.x, sz.z) * g.globe_scale(s)
		assert_true(h >= 0.25 or wd >= float(g.cfg.get("globe_max_width", 1.6)) - 0.01, "stage %d stands %.2f m (w %.2f)" % [st, h, wd])
		assert_lte(wd, float(g.cfg.get("globe_max_width", 1.6)) + 0.01, "no wider than the cap")
	g.slot_stage[s] = 4
	assert_gte(g.globe_height(4), 0.9, "a bloom is about a metre tall")


func test_marks_show_soil_sprouts_and_thirst() -> void:
	var made: Array = _make()
	var g: Garden = made[1]
	var m: GardenMarks = made[2]
	var slots: PackedInt32Array = _plant3(made[0], g)
	m._refresh()
	assert_eq(int(m.shown["planted"]), 3, "a soil mound under every plant")
	assert_eq(int(m.shown["sprouts"]), 3, "seeds show as sprouts")
	assert_eq(int(m.shown["thirsty"]), 3, "no water yet: three drops")
	assert_eq(m.wetness(slots[0]), 0.0)
	var got: Array = []
	g.watered.connect(func(s: int, dry: bool) -> void: got.append([s, dry]))
	g.water(slots[0], 30.0)
	assert_eq(got, [[slots[0], true]], "watering a dry plant says so")
	assert_gt(m.wetness(slots[0]), 0.5, "the soil reads wet")
	g._perk_step(Garden.PERK_S * 0.5)
	assert_gt(g.perk_of(slots[0]), 0.5, "it bounces up")
	g._perk_step(Garden.PERK_S)
	assert_eq(g.perk_of(slots[0]), 0.0, "and settles")
	m._refresh()
	assert_eq(int(m.shown["thirsty"]), 2, "the watered one loses its drop")
	g.water(slots[0], 30.0)
	assert_eq(got.size(), 2)
	assert_false(bool(got[1][1]), "watering it again: not dry")


func test_paving_is_found_on_streets_kerbs_and_the_pad() -> void:
	var lay := CityLayout.new(4471, 108.0)
	var key: Vector2i = Vector2i(1, 1)
	assert_true(lay.blocks.has(key), "a town block")
	var c := Vector2(key) * CityLayout.PITCH
	var road_x: float = c.x + CityLayout.PITCH * 0.5  # the street between two blocks
	assert_true(GardenGround.paved(lay, road_x, c.y), "a street")
	var walk_x: float = c.x + CityLayout.PITCH * 0.5 - CityLayout.ROAD_W * 0.5 - CityLayout.WALK_W * 0.5
	assert_true(GardenGround.paved(lay, walk_x, c.y), "a sidewalk and its kerb")
	assert_true(GardenGround.paved(lay, 0.0, 0.0), "the hub's yard pad")
	var lot: bool = lay.surface_at(c.x, c.y) == CityLayout.Surface.LOT
	assert_eq(GardenGround.paved(lay, c.x, c.y), not lot, "a lot's middle is open ground")


## B41: paving takes planters: a box on a street or the pad, a tree pit on a sidewalk or a kerb;
## a slot inside a building takes nothing.
func test_a_street_takes_planter_boxes_and_a_sidewalk_tree_pits() -> void:
	var lay := CityLayout.new(4471, 108.0)
	var key: Vector2i = Vector2i(1, 1)
	var c := Vector2(key) * CityLayout.PITCH
	var road_x: float = c.x + CityLayout.PITCH * 0.5
	var walk_x: float = c.x + CityLayout.PITCH * 0.5 - CityLayout.ROAD_W * 0.5 - CityLayout.WALK_W * 0.5
	assert_eq(GardenGround.planter_kind(GardenGround.paved_surface(lay, road_x, c.y)), GardenPlanters.Kind.BOX, "a street: a planter box")
	assert_eq(GardenGround.planter_kind(GardenGround.paved_surface(lay, 0.0, 0.0)), GardenPlanters.Kind.BOX, "the pad: a planter box")
	assert_eq(GardenGround.planter_kind(GardenGround.paved_surface(lay, walk_x, c.y)), GardenPlanters.Kind.PIT, "a sidewalk: a tree pit")
	assert_gt(GardenPlanters.soil_top(GardenPlanters.Kind.BOX), GardenPlanters.soil_top(GardenPlanters.Kind.PIT), "a box stands taller than a pit")
	assert_eq(GardenPlanters.soil_top(GardenPlanters.Kind.NONE), 0.0)
	var made: Array = _make()
	var g: Garden = made[1]
	var slots: PackedInt32Array = _plant3(made[0], g)
	var hid: int = g.slot_hex[slots[0]]
	var free: Array[int] = []
	for sl: int in g.hex_slots[hid]:
		if g.slot_species[sl] < 0:
			free.append(sl)
	g.ground.set_known(free[0], true, false, GardenPlanters.Kind.PIT)
	g.ground.set_known(free[1], true, true)
	assert_true(g.plantable(free[0]), "a paved slot takes a plant")
	assert_false(g.plantable(free[1]), "a slot inside a building does not")
	GameState.currencies["seeds"] = BigNum.from_float(5)
	g.plant(free[0])
	assert_true(g.planters.has_slot(free[0]), "its plant stands in a tree pit")
	assert_false(g.planters.has_slot(slots[0]), "a plant on open ground has none")
	g.slot_stage[free[0]] = 2  # grown past the sprout (a seed's clump has no size)
	var up: Vector3 = g.slot_pos[free[0]].normalized()
	assert_almost_eq(g._slot_xf(free[0]).origin.dot(up) - g.slot_pos[free[0]].dot(up), GardenPlanters.soil_top(GardenPlanters.Kind.PIT), 0.001,
		"the plant stands on the pit's soil")
	assert_not_null(GardenPlanters.box_mesh())
	assert_not_null(GardenPlanters.pit_mesh())
