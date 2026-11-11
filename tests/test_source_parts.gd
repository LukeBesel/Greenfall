extends GutTest
## Built job parts (systems/sources.gd, core/crew_chain.gd): a carried part marked "built" is
## ordered by Lumi, made on the Assembler's line, which builds no robot meanwhile, and fitted by
## her. With no Assembler the workbench makes it, slower, so the job can always be finished. The
## first planet's rocket, and a built part on the dummy planet from a fixture table.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const ROCKET_CITY: String = "old_capital"
const SPREAD_TABLE: String = "res://tests/fixtures/sources_spread.json"
const ROBOT: String = "scoopie"
const ROBOT_PARTS: float = 10.0

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


func _world(planet_id: StringName, def: PlanetDefinition = null, saved: Dictionary = {}) -> Sources:
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
	_sources.load_state(saved, {})
	_fx.districts.load_state({})
	return _sources


## The rocket's city open and clean, so its first part is on offer.
func _rocket_world(saved: Dictionary = {}) -> Sources:
	var s: Sources = _world(FIRST, null, saved)
	for id: String in _fx.districts.ids():
		_fx.set_district_stage(id, Districts.MAX_STAGE - 1)
	return s


## The first planet's Assembler line, standing, with a robot type it may build.
func _line() -> CrewChain:
	var c := CrewChain.new()
	c.configure(Planets.by_id(FIRST).table("robots").get("chain", {}))
	c.built = true
	for t: String in c.mix.keys():
		c.set_weight(t, 0)
	c.set_weight(ROBOT, 1)
	return c


func _tick_line(c: CrewChain, dt: float, parts: float = 1000.0) -> Dictionary:
	return c.tick_line(dt, parts, true, [ROBOT] as Array[String], func(_t: String) -> float: return ROBOT_PARTS)


func _give(currency: String, amount: float) -> void:
	GameState.add_currency(currency, BigNum.from_float(amount))


func _have(currency: String) -> float:
	return GameState.get_currency(currency).to_float()


# --- The data -----------------------------------------------------------------------------------

func test_every_rocket_part_is_built_on_the_line_in_about_45_seconds() -> void:
	var s: Sources = _world(FIRST)
	var steps: Array = s.steps(ROCKET_CITY)
	assert_eq(steps.size(), 6)
	for st: Dictionary in steps:
		assert_true(bool(st["built"]), "%s is built, not bought off a shelf" % st["id"])
		assert_between(float(st["line_s"]), 40.0, 50.0, "%s: about 45 s of line time" % st["id"])
		assert_gt(float(st["bench_s"]), float(st["line_s"]), "%s: the workbench is the slow way" % st["id"])
		assert_almost_eq(float(st["seconds"]), 6.0, 0.001, "%s: fitted at the pad in 6 s" % st["id"])
		assert_gt(float((st["cost"] as Dictionary).get("parts", 0.0)), 0.0, "%s consumes Parts" % st["id"])
	for id: String in s.ids():
		if id != ROCKET_CITY:
			for st: Dictionary in s.steps(id):
				assert_false(bool(st["built"]), "%s: the other cities' parts lie ready by their landmarks" % st["id"])


# --- Order, build, fetch, fit ---------------------------------------------------------------------

func test_lumi_orders_a_part_waits_for_it_fetches_it_and_fits_it() -> void:
	var s: Sources = _rocket_world()
	var step: Dictionary = s.current_step(ROCKET_CITY)
	var price: float = float(step["cost"]["parts"])
	watch_signals(EventBus)
	assert_eq(s.prompt(ROCKET_CITY), str(step["prompt"]))
	assert_false(s.use(ROCKET_CITY), "no Parts, no order")
	assert_false(s.is_building(ROCKET_CITY))
	_give("parts", price + 5.0)
	assert_true(s.use(ROCKET_CITY))
	assert_almost_eq(_have("parts"), 5.0, 0.001, "the order consumes the Parts")
	assert_true(s.is_building(ROCKET_CITY))
	assert_signal_emitted_with_parameters(EventBus, "source_part_ordered", [ROCKET_CITY, 0])
	assert_false(s.is_carrying(ROCKET_CITY), "nothing to carry yet")
	assert_false(s.use(ROCKET_CITY), "it cannot be picked up before it is built")
	assert_eq(s.prompt(ROCKET_CITY), "", "no prompt while it is built")
	assert_true(s.is_open(ROCKET_CITY), "the job keeps the card")
	assert_eq(str(s.card(ROCKET_CITY)["text"]), "Wait for the part")
	assert_eq((s.card(ROCKET_CITY)["cost"] as Dictionary).size(), 0, "nothing more to pay")
	assert_true(bool(s.card(ROCKET_CITY)["affordable"]))
	var share: float = s.job_share(ROCKET_CITY)
	s._physics_process(float(step["bench_s"]) * 0.5)
	assert_almost_eq(s.build_share(ROCKET_CITY), 0.5, 0.001)
	assert_gt(s.job_share(ROCKET_CITY), share, "the card's bar fills while it is built")
	assert_signal_not_emitted(EventBus, "source_part_built")
	s._physics_process(float(step["bench_s"]) * 0.5)
	assert_true(s.is_ready(ROCKET_CITY))
	assert_false(s.is_building(ROCKET_CITY))
	assert_signal_emitted_with_parameters(EventBus, "source_part_built", [ROCKET_CITY, 0])
	assert_eq(s.active_spot(ROCKET_CITY), Sources.SPOT_FROM, "it waits where it was ordered")
	assert_eq(s.prompt(ROCKET_CITY), "Pick up the finished part")
	assert_eq(str(s.card(ROCKET_CITY)["text"]), "Fetch the finished part")
	assert_true(s.use(ROCKET_CITY))
	assert_true(s.is_carrying(ROCKET_CITY))
	assert_almost_eq(_have("parts"), 5.0, 0.001, "picking it up costs nothing")
	assert_eq(s.active_spot(ROCKET_CITY), Sources.SPOT_AT)
	assert_true(s.use(ROCKET_CITY))
	s.advance(ROCKET_CITY, float(step["seconds"]))
	assert_eq(s.step_index(ROCKET_CITY), 1, "fitted at the pad")
	assert_signal_emit_count(EventBus, "source_part_ordered", 1)


func test_a_part_on_the_line_holds_robot_building_until_it_is_done() -> void:
	var s: Sources = _rocket_world()
	var line: CrewChain = _line()
	s.set_line(line)
	var step: Dictionary = s.current_step(ROCKET_CITY)
	var out: Dictionary = _tick_line(line, 10.0)
	assert_eq(line.current, ROBOT, "the line is building a robot")
	assert_almost_eq(float(out["spend"]), ROBOT_PARTS, 0.001)
	_give("parts", float(step["cost"]["parts"]))
	assert_true(s.use(ROCKET_CITY))
	s._physics_process(1.0)
	assert_true(s.on_line(ROCKET_CITY), "the part is on the Assembler's line")
	assert_eq(line.part, str(step["id"]))
	assert_eq(str(s.card(ROCKET_CITY)["desc"]), "It is on the Assembler's line. Robot building waits until it is done.")
	var spent: float = 0.0
	var built: int = 0
	for _i: int in int(line.assembly_s()) * 2:  # far longer than a robot takes
		out = _tick_line(line, 1.0)
		spent += float(out["spend"])
		built += 1 if str(out["built"]) != "" else 0
	assert_eq(built, 0, "no robot leaves the line while the part is on it")
	assert_almost_eq(spent, 0.0, 0.001, "and none is started")
	assert_eq(line.status, CrewChain.PART)
	assert_almost_eq(line.progress_s, 10.0, 0.001, "the robot that was on the line keeps the work done on it")
	s._physics_process(float(step["line_s"]) - 1.0)
	assert_true(s.is_ready(ROCKET_CITY), "about 45 s of line time, and the part is done")
	assert_eq(line.part, "", "the line is free again")
	out = _tick_line(line, line.assembly_s())
	assert_eq(str(out["built"]), ROBOT, "robot building goes on where it stopped")
	s.set_line(null)


func test_a_part_holds_the_line_even_when_the_player_paused_robot_building() -> void:
	var s: Sources = _rocket_world()
	var line: CrewChain = _line()
	line.paused = true
	s.set_line(line)
	var step: Dictionary = s.current_step(ROCKET_CITY)
	_give("parts", float(step["cost"]["parts"]))
	assert_true(s.use(ROCKET_CITY))
	s._physics_process(float(step["line_s"]))
	assert_true(s.is_ready(ROCKET_CITY), "pausing the robots does not stop Lumi's part")
	_tick_line(line, 1.0)
	assert_eq(line.status, CrewChain.PAUSED)
	s.set_line(null)


func test_without_the_assembler_the_workbench_builds_the_part_slower() -> void:
	var s: Sources = _rocket_world()
	var line: CrewChain = _line()
	line.built = false  # on offer, never built
	s.set_line(line)
	var step: Dictionary = s.current_step(ROCKET_CITY)
	_give("parts", float(step["cost"]["parts"]))
	assert_true(s.use(ROCKET_CITY), "a player with no Assembler can still order the part")
	s._physics_process(float(step["line_s"]))
	assert_false(s.on_line(ROCKET_CITY))
	assert_eq(line.part, "", "nothing holds a line that does not stand")
	assert_true(s.is_building(ROCKET_CITY), "the line's time is not enough at the workbench")
	assert_eq(str(s.card(ROCKET_CITY)["desc"]), "The workbench is building it. The Assembler would be three times as fast.")
	assert_almost_eq(s.build_left_s(ROCKET_CITY), float(step["bench_s"]) - float(step["line_s"]), 0.01)
	s._physics_process(float(step["bench_s"]) - float(step["line_s"]))
	assert_true(s.is_ready(ROCKET_CITY), "but it is built")
	s.set_line(null)


func test_the_whole_rocket_can_be_built_with_no_assembler() -> void:
	var s: Sources = _rocket_world()
	_fx.set_district_stage(ROCKET_CITY, Districts.MAX_STAGE)
	_give("parts", float(Sources.total_cost(s.spec_of(ROCKET_CITY))["parts"]))
	var seconds: float = 0.0
	for st: Dictionary in s.steps(ROCKET_CITY):
		assert_true(s.use(ROCKET_CITY), "%s: ordered" % st["id"])
		s._physics_process(float(st["bench_s"]))
		seconds += float(st["bench_s"])
		assert_true(s.use(ROCKET_CITY), "%s: fetched" % st["id"])
		assert_true(s.use(ROCKET_CITY), "%s: at the pad" % st["id"])
		s.advance(ROCKET_CITY, float(st["seconds"]))
	assert_true(s.is_shut(ROCKET_CITY))
	assert_almost_eq(_have("parts"), 0.0, 0.001)
	assert_eq(_fx.districts.stage_of(ROCKET_CITY), Districts.MAX_STAGE)
	assert_lte(seconds, 15.0 * 60.0, "the slow way is still under a quarter of an hour of waiting in all")


func test_an_assembler_built_while_the_bench_works_takes_the_part_over() -> void:
	var s: Sources = _rocket_world()
	var line: CrewChain = _line()
	line.built = false
	s.set_line(line)
	var step: Dictionary = s.current_step(ROCKET_CITY)
	_give("parts", float(step["cost"]["parts"]))
	assert_true(s.use(ROCKET_CITY))
	s._physics_process(float(step["bench_s"]) * 0.5)
	line.built = true
	assert_almost_eq(s.build_left_s(ROCKET_CITY), float(step["line_s"]) * 0.5, 0.01, "half built: half the line's time is left")
	s._physics_process(1.0)
	assert_eq(line.part, str(step["id"]))
	s._physics_process(float(step["line_s"]) * 0.5)
	assert_true(s.is_ready(ROCKET_CITY))
	s.set_line(null)


# --- Saving -------------------------------------------------------------------------------------

func test_a_part_being_built_and_a_finished_part_come_back_from_a_save() -> void:
	var s: Sources = _rocket_world()
	var step: Dictionary = s.current_step(ROCKET_CITY)
	_give("parts", float(step["cost"]["parts"]))
	assert_true(s.use(ROCKET_CITY))
	s._physics_process(float(step["bench_s"]) * 0.25)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.save_state()))
	watch_signals(EventBus)
	var s2: Sources = _rocket_world(saved)
	assert_true(s2.is_building(ROCKET_CITY), "the order is not lost")
	assert_almost_eq(s2.build_share(ROCKET_CITY), 0.25, 0.001, "nor the work done on it")
	assert_almost_eq(_have("parts"), 0.0, 0.001)
	s2._physics_process(float(step["bench_s"]))
	assert_true(s2.is_ready(ROCKET_CITY))
	saved = JSON.parse_string(JSON.stringify(s2.save_state()))
	var s3: Sources = _rocket_world(saved)
	assert_true(s3.is_ready(ROCKET_CITY), "a finished part still waits after a load")
	assert_true(s3.use(ROCKET_CITY))
	assert_true(s3.is_carrying(ROCKET_CITY))
	assert_almost_eq(_have("parts"), 0.0, 0.001, "and is not paid for again")


# --- Any planet ---------------------------------------------------------------------------------

func test_a_built_part_on_another_planet_is_data_only() -> void:
	var def: PlanetDefinition = Planets.by_id(DUMMY).duplicate()
	def.tables = def.tables.duplicate()
	def.tables[Sources.TABLE] = SPREAD_TABLE
	var s: Sources = _world(DUMMY, def)
	var id: String = _fx.districts.ids()[0]
	var line := CrewChain.new()
	line.built = true
	s.set_line(line)
	_give("seeds", 4.0)
	assert_true(s.use(id), "ordered with this planet's own currency")
	assert_almost_eq(_have("seeds"), 0.0, 0.001)
	assert_eq(str(s.card(id)["text"]), "Wait for the pump")
	s._physics_process(19.0)
	assert_true(s.is_building(id))
	assert_eq(line.part, "pump")
	s._physics_process(1.0)
	assert_true(s.is_ready(id), "this planet's line takes 20 s")
	assert_eq(s.prompt(id), "Pick up the pump")
	line.built = false
	s.set_line(null)
	var s2: Sources = _world(DUMMY, def)
	_give("seeds", 4.0)
	assert_true(s2.use(id))
	s2._physics_process(29.0)
	assert_true(s2.is_building(id))
	s2._physics_process(1.0)
	assert_true(s2.is_ready(id), "and its bench 30 s")


# --- The crew at the launch point (tools/crew_sim) ------------------------------------------------

func test_the_rocket_holds_the_line_and_the_launch_crew_stays_between_100_and_200() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var r: Dictionary = CrewSim.run(def, CrewSim.load_calibration(), CrewSim.POLICY_DEFAULT)
	assert_eq(int(r["job_parts_built"]), 6, "the default player builds the whole rocket")
	assert_almost_eq(float(r["parts_on_jobs"]), 2600.0, 0.001)
	assert_between(float(r["line_held_s"]), 6.0 * 40.0, 6.0 * 50.0, "six parts of about 45 s each on the line")
	assert_between(int(r["crew_end"]), 100, 200, "the owner's launch crew")
	assert_gte(float(r["parts_left"]), 0.0)
