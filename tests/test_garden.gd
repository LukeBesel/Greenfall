extends GutTest

class FakeView:
	extends RefCounted
	var lives: Dictionary = {}
	func set_life(id: int, life: float) -> void:
		lives[id] = life

class FakeWorld:
	extends Node
	var field: HexField
	var view := FakeView.new()
	var planet: PlanetData
	var slice_cells := PackedInt32Array()

var _cur: Dictionary
var _world_state: Dictionary


func before_each() -> void:
	AutoGrow.force = 0  # [v13goals] the planting rules, kept to turn back (data/plants.json player_planting); tests/test_auto_grow.gd covers the game now
	_cur = GameState.currencies.duplicate()
	_world_state = GameState.world.duplicate(true)
	GameState.world = {}


func after_each() -> void:
	AutoGrow.force = -1
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
	return [w, g]


func test_plant_water_grow() -> void:
	var made: Array = _make()
	var w: FakeWorld = made[0]
	var g: Garden = made[1]
	var hid: int = 10
	for pid: int in w.field.hex_pieces[hid]:
		w.field.remove_piece(pid)
	assert_true(w.field.is_clean(hid))
	var slot: int = (g.hex_slots[hid] as PackedInt32Array)[0]
	assert_true(g.plant(slot))  # [v13goals] no seed currency: a seed costs nothing in the kept planting rules
	assert_eq(w.planet.state[w.slice_cells[hid]], PlanetData.State.PLANTED)
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
