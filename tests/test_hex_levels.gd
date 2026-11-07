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
	var garden: Garden
	var hex_levels: HexLevels

var _cur: Dictionary
var _world_state: Dictionary
var _stats: Dictionary
var _events: Array = []


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_stats = GameState.stats.duplicate(true)
	_world_state = GameState.world.duplicate(true)
	GameState.world = {}
	_events.clear()
	EventBus.hex_level_changed.connect(_on_level)


func after_each() -> void:
	EventBus.hex_level_changed.disconnect(_on_level)
	GameState.currencies = _cur
	GameState.stats = _stats
	GameState.world = _world_state


func _on_level(hid: int, level: int) -> void:
	_events.append([hid, level])


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
	w.garden.set_process(false)
	w.hex_levels = HexLevels.new()
	w.hex_levels.world = w
	w.hex_levels.celebrate = false
	w.add_child(w.hex_levels)
	w.hex_levels.setup()
	w.hex_levels.set_process(false)
	return w


func _clean(w: FakeWorld, hid: int) -> void:
	for pid: int in w.field.hex_pieces[hid].duplicate():
		w.field.remove_piece(pid)


## Plants every slot of a hex and sets each to `stage` with `water` seconds left.
func _plant_all(w: FakeWorld, hid: int, stage: int, water_s: float) -> void:
	var g: Garden = w.garden
	GameState.currencies["seeds"] = BigNum.from_float(1000)
	for s: int in g.hex_slots[hid]:
		if g.slot_species[s] < 0:
			g.plant(s)
		g.slot_stage[s] = stage
		g.slot_water[s] = water_s
	g._recount(hid)


func test_hub_hex_untracked_and_junk_is_zero() -> void:
	var w: FakeWorld = _make()
	assert_eq(w.hex_levels.level_of(0), -1, "hub hex has no level")
	assert_eq(w.hex_levels.level_of(10), 0)


func test_clean_then_planted_then_growing() -> void:
	var w: FakeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var hid: int = 10
	_clean(w, hid)
	var c0: float = GameState.get_currency("cubes").to_float()
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 1)
	assert_gt(GameState.get_currency("cubes").to_float(), c0, "level-up pays cubes")
	assert_eq(_events.back(), [hid, 1])
	_plant_all(w, hid, 0, 50.0)
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 2)
	_plant_all(w, hid, 2, 50.0)
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 3)
	assert_gt(hl.bonus("grow_pct"), 0.0, "growing gives a permanent growth bonus")
	assert_eq(int(GameState.stats.get("hex_lvl_3", 0)), 1)


func test_sustained_needs_continuous_water() -> void:
	var w: FakeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var hid: int = 10
	_clean(w, hid)
	_plant_all(w, hid, 2, 1000.0)
	var win: int = int(hl.cfg["sustain_window_s"])
	for i: int in 100:
		hl.step(1.0)
	assert_eq(hl.level_of(hid), 3, "window not full yet")
	# Let it go dry for a long stretch: the ratio drops below 90%.
	_plant_all(w, hid, 2, 0.0)
	for i: int in 40:
		hl.step(1.0)
	assert_false(hl.sustained_now(hid))
	assert_eq(hl.level_of(hid), 3)
	# Wet again, but the dry minute is still inside the window.
	_plant_all(w, hid, 2, 1000.0)
	for i: int in 60:
		hl.step(1.0)
	assert_lt(hl.watered_ratio(hid), 0.9)
	assert_eq(hl.level_of(hid), 3)
	# A watering robot keeps it wet for a full window.
	for i: int in win:
		hl.step(1.0)
	assert_true(hl.sustained_now(hid))
	assert_eq(hl.level_of(hid), 4)


func test_thriving_when_bloomed_and_sustained() -> void:
	var w: FakeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var hid: int = 10
	_clean(w, hid)
	_plant_all(w, hid, 4, 1000.0)
	for i: int in int(hl.cfg["sustain_window_s"]) + 1:
		hl.step(1.0)
	assert_eq(hl.level_of(hid), 5)
	assert_eq(_events.back(), [hid, 5])
	assert_gt(hl.bonus("seed_pct"), 0.0)
	# Levels never drop, even if it dries out.
	_plant_all(w, hid, 4, 0.0)
	for i: int in 30:
		hl.step(1.0)
	assert_eq(hl.level_of(hid), 5)
	assert_eq(hl.count_at_least(4), 1)


func test_persist_roundtrip() -> void:
	var w: FakeWorld = _make()
	var hid: int = 10
	_clean(w, hid)
	_plant_all(w, hid, 2, 1000.0)
	for i: int in 30:
		w.hex_levels.step(1.0)
	assert_eq(w.hex_levels.level_of(hid), 3)
	w.hex_levels.persist_save()
	assert_true(GameState.world.has("hex_levels"))
	var hl2 := HexLevels.new()
	hl2.world = w
	hl2.celebrate = false
	w.add_child(hl2)
	hl2.setup()
	hl2.set_process(false)
	assert_eq(hl2.level_of(hid), 3)
	assert_almost_eq(hl2.sustain_progress(hid), w.hex_levels.sustain_progress(hid), 0.001, "sustain window restored")


func test_garden_stipend_pays_sustained_and_thriving_hexes() -> void:
	var hl := HexLevels.new()
	hl.cfg = Economy.read_json("res://data/hex_levels.json")
	hl.levels = {1: 5, 2: 4, 3: 2}
	hl._recalc_bonus()
	var per_min: float = hl.bonus("cubes_per_min")
	assert_gt(per_min, 0.0, "Sustained/Thriving hexes pay a stipend")
	var c0: float = GameState.get_currency("cubes").to_float()
	hl._pay_stipend(60.0)
	assert_almost_eq(GameState.get_currency("cubes").to_float() - c0, floorf(per_min), 1.0)
	hl.free()
