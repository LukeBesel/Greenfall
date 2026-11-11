extends GutTest


var _cur: Dictionary
var _world_state: Dictionary
var _orbit: Dictionary
var _stats: Dictionary
var _events: Array = []


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_stats = GameState.stats.duplicate(true)
	_world_state = GameState.world.duplicate(true)
	GameState.world = {}
	_orbit = GameState.orbit
	GameState.orbit = {}
	_events.clear()
	EventBus.hex_level_changed.connect(_on_level)


func after_each() -> void:
	EventBus.hex_level_changed.disconnect(_on_level)
	GameState.currencies = _cur
	GameState.stats = _stats
	GameState.world = _world_state
	GameState.orbit = _orbit


func _on_level(hid: int, level: int) -> void:
	_events.append([hid, level])


func _make() -> GlobeWorld:
	var w := GlobeWorld.new(5)
	add_child_autofree(w)
	w.add_garden().set_process(false)
	w.add_hex_levels().set_process(false)
	return w


func _clean(w: GlobeWorld, hid: int) -> void:
	w.clean(hid)


## Plants every slot of a hex and sets each to `stage` with `water` seconds left.
func _plant_all(w: GlobeWorld, hid: int, stage: int, water_s: float) -> void:
	var g: Garden = w.garden
	GameState.currencies["seeds"] = BigNum.from_float(1000)
	for s: int in g.hex_slots[hid]:
		if g.slot_species[s] < 0:
			g.plant(s)
		g.slot_stage[s] = stage
		g.slot_water[s] = water_s
	g._recount(hid)


func test_hub_hex_untracked_and_junk_is_zero() -> void:
	var w: GlobeWorld = _make()
	w.field.hex_hub[GlobeFixture.HUB_CELL] = 1
	assert_eq(w.hex_levels.level_of(GlobeFixture.HUB_CELL), -1, "hub hex has no level")
	assert_eq(w.hex_levels.level_of(w.land_cell()), 0, "untracked land reads level 0")


func test_clean_then_planted_then_growing() -> void:
	var w: GlobeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var hid: int = w.land_cell()
	_clean(w, hid)
	var c0: float = GameState.get_currency("cubes").to_float()
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 1)
	assert_eq(GameState.get_currency("cubes").to_float(), c0, "a hex's stage pays no cubes")
	assert_eq(_events.back(), [hid, 1])
	_plant_all(w, hid, 0, 50.0)
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 2)
	_plant_all(w, hid, 2, 50.0)
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 3)
	assert_gt(hl.bonus("grow_pct"), 0.0, "growing gives a permanent growth bonus")
	assert_eq(int(GameState.stats.get("hex_lvl_3", 0)), 1)


## B40: slots on paving (streets, kerbs, the pad) never take a seed, so the quarter a hex needs to
## count as Planted is a quarter of the slots that can: a street-side hex with only a few open
## slots was held at Clean for good, and a city with many of them could never pass stage 1.
func test_planted_counts_a_quarter_of_the_slots_that_can_take_a_seed() -> void:
	var w: GlobeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var g: Garden = w.garden
	var hid: int = w.land_cell()
	_clean(w, hid)
	var slots: PackedInt32Array = g.hex_slots[hid]
	assert_gte(slots.size(), 8, "a hex with room for a street")
	var open_n: int = maxi(1, int(slots.size() * 0.2))
	for i: int in slots.size():
		g._paving[slots[i]] = [i >= open_n, 0.0]
	GameState.currencies["seeds"] = BigNum.from_float(1000)
	for i: int in open_n:
		assert_true(g.plantable(slots[i]))
		g.plant(slots[i])
	g._recount(hid)
	hl.step(1.0)
	assert_eq(hl.level_of(hid), 2, "every open slot planted: Planted, though under a quarter of all its slots")


## B40: a hex's life (Growing at 0.35, Thriving at 0.8) is measured over the slots that can hold a
## plant, so a hex half under a street can still be fully restored.
func test_life_is_measured_over_the_slots_that_can_hold_a_plant() -> void:
	var w: GlobeWorld = _make()
	var g: Garden = w.garden
	var hid: int = w.land_cell()
	_clean(w, hid)
	var slots: PackedInt32Array = g.hex_slots[hid]
	var half: int = slots.size() / 2
	for i: int in slots.size():
		g._paving[slots[i]] = [i >= half, 0.0]
	GameState.currencies["seeds"] = BigNum.from_float(1000)
	for i: int in half:
		g.plant(slots[i])
		g.slot_stage[slots[i]] = 4
	g._recount(hid)
	assert_almost_eq(float(g.hex_life[hid]), 1.0, 0.001, "every plant in bloom on every open slot: full life")


func test_sustained_needs_continuous_water() -> void:
	var w: GlobeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var hid: int = w.land_cell()
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
	var w: GlobeWorld = _make()
	var hl: HexLevels = w.hex_levels
	var hid: int = w.land_cell()
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
	var w: GlobeWorld = _make()
	var hid: int = w.land_cell()
	_clean(w, hid)
	_plant_all(w, hid, 2, 1000.0)
	for i: int in 30:
		w.hex_levels.step(1.0)
	assert_eq(w.hex_levels.level_of(hid), 3)
	GameState.orbit["hex_levels"] = w.hex_levels.persist()  # where the slice saves it
	var hl2 := HexLevels.new()
	hl2.world = w
	hl2.celebrate = false
	w.add_child(hl2)
	hl2.setup()
	hl2.set_process(false)
	assert_eq(hl2.level_of(hid), 3)
	assert_almost_eq(hl2.sustain_progress(hid), w.hex_levels.sustain_progress(hid), 0.001, "sustain window restored")


func test_sustained_and_thriving_hexes_pay_no_cube_stipend() -> void:
	var hl := HexLevels.new()
	hl.cfg = Economy.planet_table("regrowth")
	hl.levels = {1: 5, 2: 4, 3: 2}
	hl._recalc_bonus()
	assert_eq(hl.bonus("cubes_per_min"), 0.0, "no garden stipend")
	assert_eq(hl.bonus("wildlife_cubes_per_min"), 0.0, "no wildlife trickle")
	assert_false(hl.has_method("_pay_stipend"), "nothing pays cubes over time")
	hl.free()
