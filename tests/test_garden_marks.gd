extends GutTest
## [v4grow] Owner playtest 3 #51: plants you can see. Globe plant sizes per stage, and the
## GardenMarks layer: soil mounds (wet / dry), sprouts, thirsty drops, perk-up on watering.

class FakeView:
	extends RefCounted
	func set_life(_id: int, _life: float) -> void:
		pass

class FakeWorld:
	extends Node
	var field: HexField
	var view := FakeView.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()

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
	var g := Garden.new()
	g.world = w
	w.add_child(g)
	g.setup()
	w.set("garden", g)
	var m: GardenMarks = GardenMarks.new()
	m.world = w
	m.garden = g
	w.add_child(m)
	return [w, g, m]


func _plant3(w: FakeWorld, g: Garden) -> PackedInt32Array:
	var hid: int = 10
	for pid: int in w.field.hex_pieces[hid]:
		w.field.remove_piece(pid)
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
