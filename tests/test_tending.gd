extends GutTest
## Tending (design spec section 5; plants/tending.gd, plants/garden.gd, the regrowth table's
## `tending` block): a planting action sets a patch, a watering soaks the whole hex for 3 minutes
## with an immediate burst, thirsty plants grow at a quarter rate, and with tending a hex goes from
## clean to growing in about 2 minutes, so no stage asks for idle waiting.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
## "About 2 minutes" with the walking between actions the test leaves out.
const CLEAN_TO_GROWING_S: float = 150.0
const STEP_S: float = 0.5

var _saved: Dictionary = {}


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	GameState.world = {}
	GameState.orbit = {}


func after_each() -> void:
	Planets.set_current(FIRST)
	GameState.from_dict(_saved)


func _make() -> GlobeWorld:
	var w := GlobeWorld.new(5)
	add_child_autofree(w)
	w.add_garden().set_process(false)
	w.add_hex_levels().set_process(false)
	return w


## A spot and facing so that the slot `s` is right in front of Lumi.
func _facing(w: GlobeWorld, s: int) -> Array:
	var fwd: Vector3 = SphereGrid.frame(w.garden.slot_pos[s].normalized()).x
	return [w.garden.slot_pos[s] - fwd * 1.0, fwd]


## Lumi standing so the pour lands on the middle of hex `hid`.
func _pour_at(w: GlobeWorld, hid: int) -> Array:
	var c: Vector3 = w.field.hex_center(hid)
	var fwd: Vector3 = SphereGrid.frame(c.normalized()).x
	return [c - fwd * 1.3, fwd]


func _first_free(g: Garden, hid: int) -> int:
	for s: int in g.hex_slots[hid]:
		if g.slot_species[s] < 0 and g.plantable(s):
			return s
	return -1


func _tick(w: GlobeWorld, dt: float) -> void:
	w.garden.clock += dt
	w.garden.grow_step(dt)
	w.hex_levels.step(dt)


func test_every_planet_states_its_tending_numbers() -> void:
	for pid: StringName in PLANETS:
		var t: Dictionary = Planets.by_id(pid).table("regrowth").get("tending", {})
		assert_false(t.is_empty(), "%s has a tending block" % pid)
		assert_almost_eq(float(t.get("dry_rate", -1.0)), 0.25, 0.001, "%s: unwatered plants grow at 25%%" % pid)
		assert_gt(int(t.get("patch_size", 0)), 1, "%s: a planting action sets several plants" % pid)
		assert_gt(float(t.get("burst_stage", 0.0)), 0.0, "%s: watering gives an immediate burst" % pid)
	var first: Dictionary = Planets.by_id(FIRST).table("regrowth").get("tending", {})
	assert_almost_eq(float(first["wet_s"]), 180.0, 0.001, "a watered hex grows at full rate for 3 minutes")


func test_planting_sets_a_patch_for_one_seed_cost() -> void:
	var w: GlobeWorld = _make()
	var g: Garden = w.garden
	var hid: int = w.land_cell()
	w.clean(hid)
	g.ensure_hex(hid)
	GameState.currencies["seeds"] = BigNum.from_float(5)
	var at: Array = _facing(w, _first_free(g, hid))
	var n: int = Tending.plant_patch(g, at[0], at[1])
	assert_between(n, 3, int(g.tending["patch_size"]), "several plants went in at once")
	assert_almost_eq(GameState.get_currency("seeds").to_float(), 5.0 - float(g.tending["patch_seeds"]), 0.001)
	var slots: int = (g.hex_slots[hid] as PackedInt32Array).size()
	var actions: int = 1
	while _first_free(g, hid) >= 0 and actions < 100:
		at = _facing(w, _first_free(g, hid))
		GameState.currencies["seeds"] = BigNum.from_float(5)
		assert_gt(Tending.plant_patch(g, at[0], at[1]), 0)
		actions += 1
	assert_lt(float(actions), slots * 0.5, "a hex of %d slots takes a few actions (%d), not dozens" % [slots, actions])


func test_no_seeds_no_patch() -> void:
	var w: GlobeWorld = _make()
	var hid: int = w.land_cell()
	w.clean(hid)
	w.garden.ensure_hex(hid)
	GameState.currencies["seeds"] = BigNum.zero()
	var at: Array = _facing(w, _first_free(w.garden, hid))
	assert_eq(Tending.plant_patch(w.garden, at[0], at[1]), 0)


func test_watering_soaks_the_hex_with_a_burst_once_per_rewater() -> void:
	var w: GlobeWorld = _make()
	var g: Garden = w.garden
	var hid: int = w.land_cell()
	w.clean(hid)
	GameState.currencies["seeds"] = BigNum.from_float(1000)
	for s: int in g.hex_slots[hid]:
		g.plant(s)
	var at: Array = _pour_at(w, hid)
	var soaked: Array[int] = Tending.hand_water(g, at[0], at[1])
	assert_eq(soaked.size(), (g.hex_slots[hid] as PackedInt32Array).size(), "one pour waters every plant on the hex")
	var burst: float = float(g.tending["burst_stage"])
	for s: int in soaked:
		assert_almost_eq(g.slot_water[s], g.wet_cap(s), 0.001, "full growth for wet_s (or the species' own, if longer)")
		assert_gte(g.slot_water[s], float(g.tending["wet_s"]))
		assert_almost_eq(g.slot_progress[s], burst, 0.001, "an immediate growth burst")
	Tending.hand_water(g, at[0], at[1])
	assert_almost_eq(g.slot_progress[soaked[0]], burst, 0.001, "no second burst inside rewater_s")
	g.clock += float(g.tending["rewater_s"])
	Tending.hand_water(g, at[0], at[1])
	assert_almost_eq(g.slot_progress[soaked[0]], 2.0 * burst, 0.001, "the next burst after rewater_s")


func test_thirsty_plants_grow_at_the_dry_rate() -> void:
	var w: GlobeWorld = _make()
	var g: Garden = w.garden
	var hid: int = w.land_cell()
	w.clean(hid)
	GameState.currencies["seeds"] = BigNum.from_float(10)
	var ids: PackedInt32Array = g.hex_slots[hid]
	g.plant(ids[0])
	g.plant(ids[1])
	g.slot_species[ids[1]] = g.slot_species[ids[0]]
	g.water(ids[0], 100.0)
	g.grow_step(10.0)
	assert_gt(g.slot_progress[ids[1]], 0.0, "a thirsty plant still grows")
	assert_almost_eq(g.slot_progress[ids[1]] / g.slot_progress[ids[0]], float(g.tending["dry_rate"]), 0.001)


func test_clean_to_growing_in_about_two_minutes_with_tending() -> void:
	var tended: float = _time_to_growing(true)
	var left: float = _time_to_growing(false)
	gut.p("clean to growing: %.0f s tended, %.0f s planted and left dry" % [tended, left])
	assert_lt(tended, CLEAN_TO_GROWING_S, "about 2 minutes with tending")
	assert_gt(left, tended * 2.0, "tending is what makes it fast")


## Plays a tending player on one hex: a planting action a second until the hex is full, then (if
## `water`) a pour whenever the hex's burst is ready. Seconds from clean to Growing (level 3).
func _time_to_growing(water: bool) -> float:
	var w: GlobeWorld = _make()
	var g: Garden = w.garden
	var hid: int = w.land_cell()
	w.clean(hid)
	g.ensure_hex(hid)
	GameState.currencies["seeds"] = BigNum.from_float(1000)
	var t: float = 0.0
	var plant_t: float = 0.0
	while t < 1200.0:
		if _first_free(g, hid) >= 0:
			if t >= plant_t:
				var at: Array = _facing(w, _first_free(g, hid))
				Tending.plant_patch(g, at[0], at[1])
				plant_t = t + 1.0
		elif water and Tending.burst_ready(g, hid):
			var at2: Array = _pour_at(w, hid)
			Tending.hand_water(g, at2[0], at2[1])
		_tick(w, STEP_S)
		t += STEP_S
		if w.hex_levels.level_of(hid) >= 3:
			return t
	return t
