extends GutTest
## [v13goals] Clean ground greens by itself (plants/auto_grow.gd): plants come up without seeds on
## a clean hex's soil, never get thirsty, stop at max_fill, and a hex with clean neighbours greens
## faster. The hex levels follow the plants with no planting or watering (Grassy, Blooming, Lush,
## Thriving), quietly and without cubes past Clean.

class FakeView:
	extends RefCounted
	func set_life(_id: int, _life: float) -> void:
		pass

## A flat field that knows its neighbours (the globe's SphereField does; the flat one does not).
class NbField:
	extends HexField
	var nb: Dictionary = {}
	func _init() -> void:
		super(2, 10.0, 5)
	func neighbors(i: int) -> PackedInt32Array:
		return nb.get(i, PackedInt32Array())

class FakeWorld:
	extends Node
	var field: HexField
	var view := FakeView.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()
	var garden: Garden
	var hex_levels: HexLevels

var _before: Dictionary


func before_each() -> void:
	_before = GameState.to_dict()
	GameState.world = {}
	AutoGrow.force = 1


func after_each() -> void:
	GameState.from_dict(_before)
	AutoGrow.force = -1


func _make() -> FakeWorld:
	var w := FakeWorld.new()
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	w.field = NbField.new()
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
	w.garden.set_process(false)
	w.hex_levels = HexLevels.new()
	w.hex_levels.world = w
	w.hex_levels.celebrate = false
	w.add_child(w.hex_levels)
	w.hex_levels.setup()
	w.hex_levels.set_process(false)
	return w


func _land(w: FakeWorld) -> Array[int]:
	var out: Array[int] = []
	for h: int in w.field.hex_count():
		if w.field.hex_hub[h] == 0 and not w.field.is_water(h) and w.garden.hex_slots.has(h) and w.garden.soil_count(h) >= 4:
			out.append(h)
	return out


func _clean(w: FakeWorld, hid: int) -> void:
	for pid: int in w.field.hex_pieces[hid].duplicate():
		w.field.remove_piece(pid)


func _always() -> float:
	return 0.0


func _never() -> float:
	return 1.0


func test_plants_come_up_by_themselves_on_clean_ground_only() -> void:
	var w := _make()
	var land: Array[int] = _land(w)
	assert_gt(land.size(), 1, "some land with soil")
	var clean: int = land[0]
	var dirty: int = land[1]
	_clean(w, clean)
	assert_true(w.field.is_clean(clean))
	assert_false(w.field.is_clean(dirty))
	var seeds_spent: float = GameState.get_currency("cubes").to_float()
	var n: int = AutoGrow.sow_step(w.garden, [clean, dirty], 2.0, _always)
	assert_eq(n, 1, "one plant came up, on the clean hex")
	assert_eq(GameState.get_currency("cubes").to_float(), seeds_spent, "nothing paid for it")
	var grown: int = 0
	for sl: int in w.garden.hex_slots[clean]:
		if w.garden.slot_species[sl] >= 0:
			grown += 1
			assert_gte(w.garden.slot_water[sl], Garden.AUTO_WATER, "it never gets thirsty")
	assert_eq(grown, 1)
	for sl: int in w.garden.hex_slots.get(dirty, PackedInt32Array()):
		assert_eq(w.garden.slot_species[sl], -1, "nothing grows on the dirty hex")
	assert_eq(AutoGrow.sow_step(w.garden, [clean], 2.0, _never), 0, "the chance said no: nothing this tick")


func test_it_fills_up_to_max_fill_and_stops() -> void:
	var w := _make()
	var h: int = _land(w)[0]
	_clean(w, h)
	for k: int in 200:
		AutoGrow.sow_step(w.garden, [h], 2.0, _always)
	var soil: int = w.garden.soil_count(h)
	var grown: int = 0
	for sl: int in w.garden.hex_slots[h]:
		if w.garden.slot_species[sl] >= 0:
			grown += 1
	assert_eq(grown, ceili(float(AutoGrow.cfg().get("max_fill", 0.9)) * soil), "up to max_fill of the soil, no more")


func test_clean_neighbours_make_it_green_faster() -> void:
	var w := _make()
	var land: Array[int] = _land(w)
	var h: int = land[0]
	var f: NbField = w.field as NbField
	var around := PackedInt32Array(land.slice(1, 4))
	f.nb[h] = around
	_clean(w, h)
	var alone: float = AutoGrow.rate(f, h)
	assert_almost_eq(alone, 1.0 * float(AutoGrow.cfg().get("growth", 1.0)), 0.001, "a lone clean hex")
	for n: int in around:
		_clean(w, n)
	var together: float = AutoGrow.rate(f, h)
	assert_almost_eq(together, (1.0 + float(AutoGrow.cfg().get("neighbour_boost", 2.0))) * float(AutoGrow.cfg().get("growth", 1.0)), 0.001, "all its neighbours clean")
	assert_gt(together, alone)


func test_hex_levels_follow_the_plants_without_watering() -> void:
	var w := _make()
	var h: int = _land(w)[0]
	_clean(w, h)
	w.hex_levels.step(1.0)
	assert_eq(w.hex_levels.level_of(h), 1, "Clean")
	assert_eq(w.hex_levels.level_name(2), "Grassy")
	var cubes0: float = GameState.get_currency("cubes").to_float()
	for k: int in 200:
		AutoGrow.sow_step(w.garden, [h], 2.0, _always)
	w.hex_levels.step(1.0)
	assert_gte(w.hex_levels.level_of(h), 2, "Grassy once a quarter of its soil grows")
	# Grow every plant to bloom (no water given), then the sustain window passes.
	for sl: int in w.garden.hex_slots[h]:
		if w.garden.slot_species[sl] >= 0:
			w.garden.slot_stage[sl] = 4
	w.garden._recount(h)
	var window: int = int(w.hex_levels.cfg.get("sustain_window_s", 180)) + 2
	for k: int in window:
		w.hex_levels.step(1.0)
	assert_eq(w.hex_levels.level_of(h), 5, "Thriving, with nobody watering it")
	assert_almost_eq(GameState.get_currency("cubes").to_float(), cubes0, 0.01, "levels past Clean pay no cubes: they come by themselves")


func test_old_planting_rules_still_there_to_turn_back() -> void:
	AutoGrow.force = 0
	var g := Garden.new()
	GameState.flags["seeds_unlocked"] = true
	assert_true(g.unlocked(), "player_planting true: the seed tool comes back")
	g.free()
	var hl: Dictionary = Economy.read_json("res://data/hex_levels.json")
	assert_eq(str((hl["levels"] as Array)[2]["name"]), "Planted", "the planting levels are kept")
