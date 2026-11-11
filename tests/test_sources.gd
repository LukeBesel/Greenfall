extends GutTest
## Source jobs (systems/sources.gd, design spec section 4): each city's Lumi-only capstone job. It
## holds the city one stage short of its last, and doing it lifts the hold, pays the reward and
## fires the events the finds and the landmark listen for. The steps are data: the first planet's
## six jobs, a planet with no table (no jobs, no hold) and a one-step job on the dummy planet.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PARKED: StringName = &"ochre"
const CITIES: Array[String] = ["old_town", "scrapyard", "kettle_bay", "highreach", "lowmeadow", "old_capital"]
const ROCKET_CITY: String = "old_capital"
const ROCKET_PARTS: float = 2600.0
const ONE_STEP_TABLE: String = "res://tests/fixtures/sources_one_step.json"
## The street between a landmark's row of blocks and the open lot toward the yard, and that lot's
## own ground: nothing is built on either (planet/city_layout.gd).
const LOT_HALF: float = CityLayout.PITCH * 0.5 - CityLayout.ROAD_W * 0.5 - CityLayout.WALK_W
const FOOTPRINT_GAP_M: float = 0.8

var _saved: Dictionary = {}
var _fx: DistrictFixture
var _sources: Sources
var _planet: StringName


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_planet = Planets.current_id()
	_saved = {"currencies": GameState.currencies, "flags": GameState.flags, "stats": GameState.stats}
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}


func after_each() -> void:
	if is_instance_valid(_sources):
		_sources.free()
	_sources = null
	if _fx:
		_fx.free_systems()
	_fx = null
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.stats = _saved["stats"]
	Planets.set_current(_planet)


## The districts of a planet on the fixture globe with its source jobs set up as the world does:
## sources first, then the districts' load.
func _world(planet_id: StringName, def: PlanetDefinition = null, saved: Dictionary = {}, saved_districts: Dictionary = {}) -> Sources:
	Planets.set_current(planet_id)
	if _fx == null:
		_fx = DistrictFixture.new(planet_id, false)
	if def != null:
		_fx.def = def
	_fx.free_systems()
	_fx.build_systems()
	if is_instance_valid(_sources):
		_sources.free()
	_sources = Sources.new()
	_sources.setup(_fx.def, _fx.districts)
	_sources.load_state(saved, saved_districts)
	_fx.districts.load_state(saved_districts)
	return _sources


## Every city up to and including `city` is unlocked and stands as far as its hexes can take it.
func _restore_up_to(city: String) -> void:
	for id: String in _fx.districts.ids():
		_fx.set_district_stage(id, Districts.MAX_STAGE if id == city else Districts.MAX_STAGE - 1)
		if id == city:
			return


func _give(currency: String, amount: float) -> void:
	GameState.add_currency(currency, BigNum.from_float(amount))


func _have(currency: String) -> float:
	return GameState.get_currency(currency).to_float()


## Does the job's current step the way Lumi does: use the spot (twice for a carried part) and
## stay for the work.
func _do_step(s: Sources, city: String) -> void:
	var step: Dictionary = s.current_step(city)
	if step["type"] == Sources.TYPE_CARRY:
		assert_true(s.use(city), "%s: picks the part up, or orders it" % step["id"])
		if bool(step["built"]):
			assert_true(s.is_building(city), "%s: a built part is made first" % step["id"])
			s.advance_build(city, float(step["bench_s"]))
			assert_true(s.is_ready(city), "%s: built" % step["id"])
			assert_true(s.use(city), "%s: picks the built part up" % step["id"])
		assert_true(s.is_carrying(city))
	assert_true(s.use(city), "%s: uses the spot" % step["id"])
	if float(step["seconds"]) > 0.0:
		assert_true(s.is_engaged(city), "%s: the work is under way" % step["id"])
		s.advance(city, float(step["seconds"]))


func _do_job(s: Sources, city: String) -> void:
	var left: Array = s.steps(city).slice(s.step_index(city))
	var parts: float = 0.0
	for st: Dictionary in left:
		parts += float((st["cost"] as Dictionary).get("parts", 0.0))
	_give("parts", parts)
	for _i: int in left.size():
		_do_step(s, city)


# --- The data -----------------------------------------------------------------------------------

func test_every_city_of_the_first_planet_has_a_source_job() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var specs: Array[Dictionary] = Sources.specs_for(def)
	var order: Array[String] = []
	for spec: Dictionary in specs:
		order.append(str(spec["district"]))
	assert_eq(order, CITIES, "one job a city, in play order")
	assert_eq(Sources.gates_stage_for(def), Districts.MAX_STAGE, "the job gates the last stage")
	var kinds_of: Dictionary = {}
	for d: Dictionary in Districts.specs_for(def):
		kinds_of[d["id"]] = d["pollution"]
	for spec: Dictionary in specs:
		var city: String = str(spec["district"])
		var steps: Array = spec["steps"]
		if city == ROCKET_CITY:
			assert_eq(steps.size(), 6, "the rocket has six parts")
		else:
			assert_between(steps.size(), 3, 5, "%s: a job of three to five steps" % city)
		assert_ne(str(spec["name"]), "", "%s: the source has a name" % city)
		assert_ne(str(spec["toast"]), "", "%s: the shutdown has a notice" % city)
		var ids: Dictionary = {}
		var uses_kind: bool = false
		for st: Dictionary in steps:
			ids[st["id"]] = true
			for key: String in ["text", "text_1", "desc", "prompt", "final_prompt"]:
				assert_ne(str(st[key]), "", "%s/%s has its %s" % [city, st["id"], key])
			if st["type"] != Sources.TYPE_USE:
				assert_gt(float(st["seconds"]), 0.0, "%s/%s takes hands-on time" % [city, st["id"]])
				assert_lte(float(st["seconds"]), 10.0, "%s/%s never holds Lumi still for long" % [city, st["id"]])
			if st["kind"] != "":
				uses_kind = true
				assert_has(kinds_of[city], st["kind"], "%s/%s works a kind the city holds" % [city, st["id"]])
		assert_eq(ids.size(), steps.size(), "%s: step ids are unique" % city)
		if city != ROCKET_CITY:
			assert_true(uses_kind, "%s: one step is hand work on the city's own pollution" % city)
			assert_eq(str((steps[0] as Dictionary)["type"]), Sources.TYPE_USE, "%s opens with a plain step: walk there and use it" % city)


func test_each_job_works_the_kind_its_city_introduces() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var newest: Dictionary = {}
	var seen: Array = []
	for d: Dictionary in Districts.specs_for(def):
		for k: Variant in d["pollution"]:
			if not seen.has(k):
				seen.append(k)
				newest[d["id"]] = k
	for spec: Dictionary in Sources.specs_for(def):
		var city: String = str(spec["district"])
		if city == ROCKET_CITY:
			continue
		var kinds: Array = (spec["steps"] as Array).map(func(st: Dictionary) -> String: return str(st["kind"]))
		assert_has(kinds, newest[city], "%s's job uses %s, the kind the city taught" % [city, newest[city]])


func test_no_job_pays_more_than_three_minutes_of_its_citys_income() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var table: Dictionary = def.table(Districts.TABLE)
	var income: Dictionary = {}
	for d: Dictionary in table["districts"]:
		income[d["id"]] = float(d["income_ref"])
	for spec: Dictionary in Sources.specs_for(def):
		var cubes: float = float((spec["reward"] as Dictionary).get("cubes", 0.0))
		assert_gt(cubes, 0.0, "%s pays cubes" % spec["district"])
		assert_lte(cubes, float(table["income_ref_s"]) * float(income[spec["district"]]), "%s stays under the 3-minute rule" % spec["district"])
		assert_eq(cubes, floorf(cubes), "%s pays whole cubes" % spec["district"])


func test_the_rocket_is_six_parts_for_2600_parts_in_rising_prices() -> void:
	var spec: Dictionary = Sources.specs_for(Planets.by_id(FIRST)).filter(func(s: Dictionary) -> bool: return s["district"] == ROCKET_CITY)[0]
	assert_almost_eq(float(Sources.total_cost(spec).get("parts", 0.0)), ROCKET_PARTS, 0.001)
	var last_price: float = 0.0
	var last_share: float = 0.0
	for st: Dictionary in spec["steps"]:
		assert_eq(str(st["type"]), Sources.TYPE_CARRY, "%s is built, carried and fitted by Lumi" % st["id"])
		var price: float = float((st["cost"] as Dictionary).get("parts", 0.0))
		assert_gt(price, last_price, "%s costs more than the part before" % st["id"])
		assert_gt(float(st["at_clean"]), last_share, "%s is offered later in the city's cleaning" % st["id"])
		last_price = price
		last_share = float(st["at_clean"])
	assert_lt(last_share, 1.0, "the last part never needs the whole city clean")


func test_every_spot_stands_on_a_street_or_the_open_lot_clear_of_the_landmark() -> void:
	for spec: Dictionary in Sources.specs_for(Planets.by_id(FIRST)):
		var city: String = str(spec["district"])
		if city == "old_town":
			continue  # its landmark has a block of its own: test_old_towns_spots...
		var c: VerdanceCity = VerdanceCity.create(city)
		var solid: Array[Rect2] = c._footprint()
		for st: Dictionary in spec["steps"]:
			var spots: Array[Vector2] = [st["at"]]
			if st["type"] == Sources.TYPE_CARRY:
				spots.append(st["from"])
			for p: Vector2 in spots:
				var z_in_block: float = absf(p.y - CityLayout.PITCH * roundf(p.y / CityLayout.PITCH))
				var on_street: bool = z_in_block > LOT_HALF
				var on_lot: bool = absf(p.x) < LOT_HALF and p.y > CityLayout.PITCH * 0.5 and p.y < CityLayout.PITCH * 1.5
				assert_true(on_street or on_lot, "%s/%s at %s is on a street or the open lot" % [city, st["id"], str(p)])
				assert_lt(p.y, CityLayout.PITCH * 1.5, "%s/%s is short of the yard's block" % [city, st["id"]])
				for r: Rect2 in solid:
					assert_false(r.grow(FOOTPRINT_GAP_M).has_point(p), "%s/%s at %s is clear of the landmark piece %s" % [city, st["id"], str(p), str(r)])
		c.free()


func test_old_towns_spots_stand_on_the_pump_house_block_clear_of_its_walls() -> void:
	var spec: Dictionary = Sources.specs_for(Planets.by_id(FIRST))[0]
	assert_eq(str(spec["district"]), "old_town")
	# The landmark's frame is the burst main, (2.6, 9.4) from the middle of its emptied block.
	var burst := Vector2(2.6, 9.4)
	var hall := Rect2(Vector2(-10.5, -10.4), Vector2(16.5, 12.4))
	var tower := Rect2(Vector2(6.3, -9.2), Vector2(4.6, 4.6))
	for st: Dictionary in spec["steps"]:
		var spots: Array[Vector2] = [st["at"]]
		if st["type"] == Sources.TYPE_CARRY:
			spots.append(st["from"])
		for p: Vector2 in spots:
			var in_block: Vector2 = p + burst
			assert_true(absf(in_block.x) < CityLayout.PITCH * 0.5 and absf(in_block.y) < CityLayout.PITCH * 0.5, "%s is on the block" % st["id"])
			assert_false(hall.grow(FOOTPRINT_GAP_M).has_point(in_block), "%s is clear of the pump house" % st["id"])
			assert_false(tower.grow(FOOTPRINT_GAP_M).has_point(in_block), "%s is clear of the standpipe" % st["id"])


# --- The job, city by city ------------------------------------------------------------------------

func test_a_citys_job_completes_and_opens_its_last_stage(city: String = use_parameters(CITIES)) -> void:
	var s: Sources = _world(FIRST)
	var d: Districts = _fx.districts
	watch_signals(EventBus)
	_restore_up_to(city)
	assert_eq(d.stage_of(city), Districts.MAX_STAGE - 1, "every hex is thriving, the city is held one stage short")
	assert_eq(d.stage_cap_of(city), Districts.MAX_STAGE - 1)
	assert_true(s.is_open(city), "the job is on offer")
	assert_signal_not_emitted(EventBus, "source_shut_down")
	var hold_share: float = float(_fx.def.table(Sources.TABLE)["hold_share"])
	assert_almost_eq(d.share_of(city), 1.0 - hold_share, 0.0001, "the readout keeps the job's part of the bar empty")
	_give("parts", float(Sources.total_cost(s.spec_of(city)).get("parts", 0.0)))
	_do_step(s, city)
	assert_gt(d.share_of(city), 1.0 - hold_share, "and fills it step by step")
	assert_lt(d.share_of(city), 1.0)
	GameState.currencies = {}
	var cubes: float = _have("cubes")
	_do_job(s, city)
	var spec: Dictionary = s.spec_of(city)
	assert_true(s.is_shut(city))
	assert_false(s.is_open(city), "a job is done once")
	assert_signal_emit_count(EventBus, "source_step_done", s.steps(city).size())
	assert_signal_emitted_with_parameters(EventBus, "source_shut_down", [city])
	assert_signal_emit_count(EventBus, "source_shut_down", 1)
	assert_eq(d.stage_of(city), Districts.MAX_STAGE, "the last stage opens at once")
	assert_signal_emitted_with_parameters(EventBus, "district_stage_changed", [city, Districts.MAX_STAGE])
	assert_almost_eq(_have("cubes") - cubes, float((spec["reward"] as Dictionary).get("cubes", 0.0)), 0.001, "the reward is paid")
	assert_almost_eq(_have("parts"), float((spec["reward"] as Dictionary).get("parts", 0.0)), 0.001, "every Part given was spent on the job; its reward is left")
	assert_almost_eq(s.job_share(city), 1.0, 0.0001)
	for other: String in CITIES:
		if other != city:
			assert_false(s.is_shut(other), "%s's source still runs" % other)


func test_the_launch_point_waits_for_every_source() -> void:
	var s: Sources = _world(FIRST)
	watch_signals(EventBus)
	for id: String in CITIES:
		_fx.set_district_stage(id, Districts.MAX_STAGE)
	assert_false(_fx.restoration.check_launch(), "every hex of every city thrives, and the sources still run")
	assert_lt(_fx.restoration.launch_value(), 1.0, "launch progress is not full while a source runs")
	for id: String in CITIES:
		assert_false(_fx.restoration.is_launched(), "not before %s is shut down" % id)
		_do_job(s, id)
	assert_eq(_fx.districts.count_at_stage(Districts.MAX_STAGE), CITIES.size())
	assert_true(_fx.restoration.is_launched(), "the rocket was the last thing missing")
	assert_signal_emit_count(EventBus, "launch_ready", 1)


func test_the_next_city_does_not_wait_for_the_source() -> void:
	_world(FIRST)
	_fx.set_district_stage("old_town", Districts.MAX_STAGE)
	assert_eq(_fx.districts.stage_of("old_town"), Districts.MAX_STAGE - 1)
	assert_true(_fx.districts.is_unlocked("scrapyard"), "the player can move on and come back for the job")


# --- Only Lumi's hands --------------------------------------------------------------------------

func test_a_job_is_offered_from_its_stage_and_in_an_unlocked_city_only() -> void:
	var s: Sources = _world(FIRST)
	var open_stage: int = int(s.spec_of("old_town")["open_stage"])
	assert_eq(open_stage, 4, "the lead's decision: the job waits until the city is sustained")
	_fx.set_district_stage("old_town", open_stage - 1)
	assert_false(s.is_open("old_town"), "too early")
	assert_false(s.use("old_town"), "nothing to use yet")
	assert_eq(s.active_spot("old_town"), "")
	assert_eq(s.card("old_town"), {})
	_fx.set_district_stage("scrapyard", Districts.MAX_STAGE)
	assert_false(_fx.districts.is_unlocked("scrapyard"))
	assert_false(s.is_open("scrapyard"), "a locked city's job waits")
	_fx.set_district_stage("old_town", open_stage)
	assert_true(s.is_open("old_town"))
	assert_eq(s.active_spot("old_town"), Sources.SPOT_AT)
	assert_false(s.is_open("no_such_city"))


func test_the_job_is_announced_once_when_it_opens() -> void:
	var s: Sources = _world(FIRST)
	watch_signals(EventBus)
	s._physics_process(1.0)
	assert_signal_not_emitted(EventBus, "source_job_opened")
	_fx.set_district_stage("old_town", Districts.MAX_STAGE)
	s._physics_process(1.0)
	s._physics_process(1.0)
	assert_signal_emit_count(EventBus, "source_job_opened", 1)
	assert_signal_emitted_with_parameters(EventBus, "source_job_opened", ["old_town"])


func test_work_runs_only_while_lumi_stays_in_reach() -> void:
	var s: Sources = _world(FIRST)
	_restore_up_to("old_town")
	_do_step(s, "old_town")  # the valve
	var step: Dictionary = s.current_step("old_town")
	assert_eq(str(step["type"]), Sources.TYPE_WORK)
	var here: Array[bool] = [true]
	s.in_reach_fn = func(_id: String) -> bool: return here[0]
	s._physics_process(1.0)
	assert_false(s.is_engaged("old_town"), "nothing happens until she uses the spot")
	assert_true(s.use("old_town"))
	assert_false(s.use("old_town"), "already at work")
	assert_eq(s.prompt("old_town"), "", "no prompt while she works")
	s._physics_process(float(step["seconds"]) * 0.5)
	assert_almost_eq(s.work_share("old_town"), 0.5, 0.01)
	here[0] = false
	s._physics_process(0.1)
	assert_false(s.is_engaged("old_town"), "walking off stops the work")
	assert_eq(s.step_index("old_town"), 1, "and the step is not done")
	here[0] = true
	assert_true(s.use("old_town"), "she takes it up again")
	s._physics_process(float(step["seconds"]) + 0.1)
	assert_eq(s.step_index("old_town"), 2, "the whole time in reach finishes it")


func test_mastery_of_the_citys_kind_shortens_its_hand_work() -> void:
	var s: Sources = _world(FIRST)
	var m := Mastery.new()
	add_child_autofree(m)
	m.setup(_fx.def, {})
	s._mastery = m
	var step: Dictionary = (s.steps("scrapyard") as Array).filter(func(st: Dictionary) -> bool: return st["kind"] == "wrecks")[0]
	assert_almost_eq(s.work_speed(step), 1.0, 0.0001, "no mastery: the plain speed")
	m.grant("wrecks", 5)
	assert_gt(s.work_speed(step), 1.0, "mastery of wrecks speeds the cutting")
	assert_almost_eq(s.work_speed(s.steps("scrapyard")[0]), 1.0, 0.0001, "a step with no kind is not sped up")


func test_a_part_is_paid_for_once_and_cannot_be_taken_without_the_parts() -> void:
	var s: Sources = _world(FIRST)
	_restore_up_to(ROCKET_CITY)
	var step: Dictionary = s.current_step(ROCKET_CITY)
	var price: float = float(step["cost"]["parts"])
	assert_eq(s.active_spot(ROCKET_CITY), Sources.SPOT_FROM, "the part is picked up first")
	assert_false(s.can_afford(ROCKET_CITY))
	assert_false(s.use(ROCKET_CITY), "no Parts, no part")
	assert_false(bool(s.card(ROCKET_CITY)["affordable"]))
	_give("parts", price + 10.0)
	assert_true(s.use(ROCKET_CITY))
	assert_almost_eq(_have("parts"), 10.0, 0.001, "the price is paid with the order")
	s.advance_build(ROCKET_CITY, float(step["bench_s"]))
	assert_true(s.use(ROCKET_CITY), "the built part is picked up")
	assert_almost_eq(_have("parts"), 10.0, 0.001, "and is not paid for again")
	assert_eq(s.active_spot(ROCKET_CITY), Sources.SPOT_AT, "then she carries it to its place")
	assert_eq((s.card(ROCKET_CITY)["cost"] as Dictionary).size(), 0, "nothing more to pay for this part")
	assert_eq(str(s.card(ROCKET_CITY)["text"]), str(step["text_1"]))
	assert_true(s.use(ROCKET_CITY))
	s.advance(ROCKET_CITY, float(step["seconds"]))
	assert_almost_eq(_have("parts"), 10.0, 0.001, "fitting costs nothing more")
	assert_eq(s.step_index(ROCKET_CITY), 1)
	assert_false(s.is_carrying(ROCKET_CITY))


func test_rocket_parts_are_offered_as_the_city_is_cleaned() -> void:
	var s: Sources = _world(FIRST)
	_restore_up_to("lowmeadow")
	assert_true(_fx.districts.is_unlocked(ROCKET_CITY))
	assert_false(s.is_open(ROCKET_CITY), "nothing is clean yet")
	var land: int = _fx.districts.land_of(ROCKET_CITY)
	var first: Dictionary = s.steps(ROCKET_CITY)[0]
	var second: Dictionary = s.steps(ROCKET_CITY)[1]
	_fx.set_district_stage(ROCKET_CITY, 1, ceili(float(first["at_clean"]) * land) + 1)
	assert_true(s.is_open(ROCKET_CITY), "the first part is offered long before the city is restored")
	_give("parts", ROCKET_PARTS)
	_do_step(s, ROCKET_CITY)
	assert_false(s.is_open(ROCKET_CITY), "the second part waits for more of the city")
	_fx.set_district_stage(ROCKET_CITY, 1, ceili(float(second["at_clean"]) * land) + 1)
	assert_true(s.is_open(ROCKET_CITY))


# --- Saving -------------------------------------------------------------------------------------

func test_a_job_part_way_through_comes_back_from_a_save() -> void:
	var s: Sources = _world(FIRST)
	_restore_up_to(ROCKET_CITY)
	for id: String in CITIES.slice(0, 2):
		_do_job(s, id)
	_give("parts", 1000.0)
	_do_step(s, ROCKET_CITY)
	assert_true(s.use(ROCKET_CITY), "the second part is ordered")
	s.advance_build(ROCKET_CITY, float(s.current_step(ROCKET_CITY)["bench_s"]))
	assert_true(s.use(ROCKET_CITY), "and is in her hands")
	var parts_left: float = _have("parts")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.save_state()))
	var saved_districts: Dictionary = JSON.parse_string(JSON.stringify(_fx.districts.save_state()))
	watch_signals(EventBus)
	var s2: Sources = _world(FIRST, null, saved, saved_districts)
	assert_signal_not_emitted(EventBus, "source_shut_down", "a load is silent")
	assert_signal_not_emitted(EventBus, "source_step_done")
	assert_true(s2.is_shut("old_town") and s2.is_shut("scrapyard"))
	assert_eq(_fx.districts.stage_cap_of("old_town"), Districts.MAX_STAGE, "a shut source holds nothing after a load")
	assert_false(s2.is_shut("kettle_bay"))
	for id: String in ["old_town", "kettle_bay"]:
		_fx.set_district_stage(id, Districts.MAX_STAGE)
	assert_eq(_fx.districts.stage_of("old_town"), Districts.MAX_STAGE)
	assert_eq(_fx.districts.stage_of("kettle_bay"), Districts.MAX_STAGE - 1, "a loaded city whose source runs is still held")
	assert_eq(s2.step_index(ROCKET_CITY), 1)
	assert_true(s2.is_carrying(ROCKET_CITY), "she still carries the part she paid for")
	assert_true(s2.use(ROCKET_CITY))
	s2.advance(ROCKET_CITY, 60.0)
	assert_eq(s2.step_index(ROCKET_CITY), 2)
	assert_almost_eq(_have("parts"), parts_left, 0.001, "and does not pay again")


func test_a_save_from_before_source_jobs_keeps_a_thriving_city_and_gives_the_rest_their_job() -> void:
	_fx = DistrictFixture.new(FIRST)
	_fx.set_district_stage("old_town", Districts.MAX_STAGE)
	_fx.set_district_stage("scrapyard", Districts.MAX_STAGE)
	var old_save: Dictionary = {"stages": {"old_town": 5, "scrapyard": 4}, "unlocked": ["old_town", "scrapyard", "kettle_bay"], "visited": ["old_town"]}
	watch_signals(EventBus)
	var s: Sources = _world(FIRST, null, {}, old_save)
	assert_true(s.is_shut("old_town"), "a city that was thriving stays thriving")
	assert_eq(_fx.districts.stage_of("old_town"), Districts.MAX_STAGE)
	assert_false(s.is_shut("scrapyard"))
	assert_eq(_fx.districts.stage_of("scrapyard"), Districts.MAX_STAGE - 1, "a city short of it gets its job, whatever its hexes say")
	assert_true(s.is_open("scrapyard"))
	assert_signal_not_emitted(EventBus, "source_shut_down")
	assert_eq(_have("cubes"), 0.0, "nothing is paid for the past")


func test_a_new_game_starts_with_every_source_running() -> void:
	var s: Sources = _world(FIRST)
	for id: String in CITIES:
		assert_false(s.is_shut(id))
		assert_eq(s.step_index(id), 0)
		assert_eq(_fx.districts.stage_cap_of(id), Districts.MAX_STAGE - 1)
	assert_eq(s.shut_count(), 0)


func test_force_shut_lifts_the_hold_without_paying() -> void:
	var s: Sources = _world(FIRST)
	_restore_up_to("old_town")
	watch_signals(EventBus)
	assert_true(s.force_shut("old_town"))
	assert_false(s.force_shut("old_town"), "once")
	assert_false(s.force_shut("no_such_city"))
	assert_eq(_fx.districts.stage_of("old_town"), Districts.MAX_STAGE)
	assert_signal_emitted_with_parameters(EventBus, "source_shut_down", ["old_town"])
	assert_eq(_have("cubes"), 0.0)


# --- Any planet ---------------------------------------------------------------------------------

func test_a_planet_without_the_table_has_no_jobs_and_no_hold(planet_id: StringName = use_parameters([DUMMY, PARKED])) -> void:
	var s: Sources = _world(planet_id)
	assert_eq(s.ids(), [] as Array[String])
	var id: String = _fx.districts.ids()[0]
	assert_false(s.has(id))
	assert_false(s.is_open(id))
	assert_false(s.is_shut(id), "nothing to shut down")
	_fx.set_district_stage(id, Districts.MAX_STAGE)
	assert_eq(_fx.districts.stage_of(id), Districts.MAX_STAGE, "its city reaches the last stage by its hexes alone")
	assert_true(_fx.restoration.is_launched())
	assert_eq(s.save_state(), {})


func test_a_job_on_another_planet_is_data_only() -> void:
	var def: PlanetDefinition = Planets.by_id(DUMMY).duplicate()
	def.tables = def.tables.duplicate()
	def.tables[Sources.TABLE] = ONE_STEP_TABLE
	var s: Sources = _world(DUMMY, def)
	var id: String = _fx.districts.ids()[0]
	assert_eq(s.ids(), [id] as Array[String])
	watch_signals(EventBus)
	_fx.set_district_stage(id, Districts.MAX_STAGE)
	assert_eq(_fx.districts.stage_of(id), 3, "this planet's job gates stage 4")
	assert_false(_fx.restoration.is_launched())
	_do_job(s, id)
	assert_eq(_fx.districts.stage_of(id), Districts.MAX_STAGE)
	assert_signal_emitted_with_parameters(EventBus, "source_shut_down", [id])
	assert_almost_eq(_have("seeds"), 7.0, 0.001, "its reward is in its own currency")
	assert_true(_fx.restoration.is_launched())


# --- The districts' hold (systems/districts.gd) ---------------------------------------------------

func test_a_held_district_keeps_the_stage_it_has_and_rises_when_the_hold_lifts() -> void:
	_fx = DistrictFixture.new(FIRST)
	var d: Districts = _fx.districts
	watch_signals(EventBus)
	_fx.set_district_stage("old_town", 3)
	d.set_stage_cap("old_town", 2)
	assert_eq(d.stage_of("old_town"), 3, "a stage reached is never taken back")
	_fx.set_district_stage("old_town", 5)
	assert_eq(d.stage_of("old_town"), 3, "but it does not rise past the hold")
	assert_almost_eq(d.clean_share_of("old_town"), 1.0, 0.0001)
	d.set_stage_cap("old_town", Districts.MAX_STAGE)
	assert_eq(d.stage_of("old_town"), 5)
	assert_signal_emitted_with_parameters(EventBus, "district_stage_changed", ["old_town", 5])
	d.set_stage_cap("no_such_city", 1)
	assert_eq(d.stage_cap_of("no_such_city"), Districts.MAX_STAGE)


# --- In the world (systems/source_sites.gd) -------------------------------------------------------

func test_the_step_on_offer_stands_in_the_landmarks_frame_and_lumi_uses_it_there() -> void:
	var def: PlanetDefinition = Planets.by_id(DUMMY).duplicate()
	def.tables = def.tables.duplicate()
	def.tables[Sources.TABLE] = ONE_STEP_TABLE
	var s: Sources = _world(DUMMY, def)
	var city: String = _fx.districts.ids()[0]
	var site_at := Vector3(0.0, 500.0, 0.0)
	var prefab := SitePrefab.new()
	add_child_autofree(prefab)
	prefab.position = site_at
	prefab.content = Node3D.new()
	prefab.add_child(prefab.content)
	var town := TownSite.new()
	prefab.content.add_child(town)
	var sm := SiteManager.new()
	autofree(sm)
	sm.sites = [{"transform": Transform3D(Basis.IDENTITY, site_at)}] as Array[Dictionary]
	sm.prefabs = [prefab]
	var ia := Interactables.new()
	add_child_autofree(ia)
	var lumi := Node3D.new()
	add_child_autofree(lumi)
	lumi.position = site_at + Vector3(40.0, 0.0, 0.0)
	var sites := SourceSites.new()
	add_child_autofree(sites)
	sites.setup(s, _fx.districts, sm, ia, func() -> Node3D: return lumi)
	var step: Dictionary = s.current_step(city)
	var spot: Vector3 = site_at + Vector3((step["at"] as Vector2).x, 0.0, (step["at"] as Vector2).y)
	assert_eq(town.source_state, SourceSites.STATE_BROKEN, "the source runs")
	assert_almost_eq((sites.target_pos(city) as Vector3).distance_to(spot), 0.0, 0.001, "the beam's target is the step's spot")
	assert_false(sites.in_reach(city), "Lumi is 40 m away")
	assert_eq(ia.prompt(lumi.global_position), "", "no prompt out of reach")
	lumi.position = spot + Vector3(1.0, 0.0, 0.0)
	assert_true(sites.in_reach(city))
	assert_string_contains(ia.prompt(lumi.global_position), tr(str(step["prompt"])))
	watch_signals(EventBus)
	assert_true(ia.try_use(lumi.global_position), "the interact key does the step")
	assert_signal_emitted_with_parameters(EventBus, "source_shut_down", [city])
	assert_eq(town.source_state, SourceSites.STATE_SHUT_DOWN, "the landmark shows it")
	assert_null(sites.target_pos(city), "nothing left to point at")
	assert_null(sites.marker(city, Sources.SPOT_AT))
	assert_eq(ia.prompt(lumi.global_position), "")


func test_a_city_whose_site_is_not_built_points_the_beam_at_the_site() -> void:
	var s: Sources = _world(FIRST)
	_restore_up_to("old_town")
	var sm := SiteManager.new()
	autofree(sm)
	var at := Vector3(0.0, 800.0, 0.0)
	var all: Array[Dictionary] = []
	for i: int in _fx.def.hub_count:
		all.append({"transform": Transform3D(Basis.IDENTITY, at + Vector3(float(i) * 1000.0, 0.0, 0.0))})
		sm.prefabs.append(null)
	sm.sites = all
	var sites := SourceSites.new()
	add_child_autofree(sites)
	sites.setup(s, _fx.districts, sm, null, Callable())
	assert_null(sites.town_of("old_town"))
	assert_eq(sites.target_pos("old_town"), at + Vector3(float(_fx.districts.site_of("old_town")) * 1000.0, 0.0, 0.0))
	assert_false(sites.in_reach("old_town"))
	assert_null(sites.target_pos("scrapyard"), "a job that is not on offer has no target")


# --- The card (story/objectives.gd) ---------------------------------------------------------------

class FakeWorld extends Node:
	var goals: Goals
	var orbit: SliceOrbit


## An objective card past its story steps, on a world that has only the districts and the jobs.
func _card(s: Sources) -> Objectives:
	var w := FakeWorld.new()
	add_child_autofree(w)
	w.goals = Goals.new()
	w.add_child(w.goals)
	w.orbit = SliceOrbit.new()
	w.add_child(w.orbit)
	w.orbit.sources = s
	w.orbit.districts = _fx.districts
	var o := Objectives.new()
	autofree(o)
	o.world = w
	o.chain = [{"id": "a", "text": "A", "desc": "a", "type": "stat", "key": "src_test_a", "target": 1}]
	o.revealed = true
	return o


func test_an_open_job_takes_the_card_after_the_story_and_gives_it_back_when_done() -> void:
	var s: Sources = _world(FIRST)
	var o: Objectives = _card(s)
	_restore_up_to("old_town")
	assert_eq(str(o.current().get("id", "")), "a", "the story's steps come first")
	assert_eq(o.source_district(), "")
	o.step = 1
	var first: Dictionary = s.steps("old_town")[0]
	var card: Dictionary = o.current()
	assert_eq(str(card.get("_source", "")), "old_town", "then the city's job has the card, ahead of the goal chain")
	assert_eq(Objectives.texts(card)[0], tr(str(first["text"])))
	assert_eq(Objectives.texts(card)[1], tr(str(first["desc"])))
	assert_eq(str(o.progress()[1]), "1 / %d" % s.steps("old_town").size())
	assert_eq(str(o.step_target(card)["to"]), "place", "the beam goes to the step's spot")
	var key: int = o.position()
	_do_step(s, "old_town")
	assert_ne(o.position(), key, "a finished step moves the card on")
	assert_eq(Objectives.texts(o.current())[0], tr(str(s.steps("old_town")[1]["text"])))
	assert_gt(float(o.progress()[0]), 0.0)
	_do_step(s, "old_town")
	_do_step(s, "old_town")
	assert_true(s.is_shut("old_town"))
	assert_false(o.current().has("_source"), "the goal chain is back once the source is shut")
	assert_true(o.current().has("_goal"))


func test_a_part_lumi_cannot_pay_for_says_so_on_the_card() -> void:
	var s: Sources = _world(FIRST)
	var o: Objectives = _card(s)
	o.step = 1
	_restore_up_to(ROCKET_CITY)
	_fx.districts.set_player_cell(_fx.districts.cells_of(ROCKET_CITY)[0])
	assert_eq(o.source_district(), ROCKET_CITY, "the card follows the city Lumi is in")
	var step: Dictionary = s.current_step(ROCKET_CITY)
	assert_string_contains(Objectives.texts(o.current())[1], Currencies.cost_text(step["cost"]))
	_give("parts", ROCKET_PARTS)
	assert_eq(Objectives.texts(o.current())[1], tr(str(step["desc"])))
