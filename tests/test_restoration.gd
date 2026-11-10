extends GutTest
## Restoration (systems/restoration.gd): the planet's two goals from data. Launch progress from
## the districts, launch_ready exactly once, the whole-planet share and its steps, saving, and
## the ending that launch_ready starts (story/planet_ending.gd, ui/end_screen.gd). Tests that can
## run on any planet take the planet id: the first planet, the dummy planet and a parked one.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PARKED: StringName = &"ochre"
const PLANETS: Array[StringName] = [FIRST, DUMMY, PARKED]
const VALUES: Array[float] = [0.0, 0.25, 0.45, 0.65, 0.85, 1.0]

var _fx: DistrictFixture
var _save_enabled: bool = true


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_save_enabled = SaveManager.enabled
	SaveManager.enabled = false


func after_each() -> void:
	if _fx:
		_fx.free_systems()
	_fx = null
	SaveManager.enabled = _save_enabled
	get_tree().paused = false


func _fixture(planet_id: StringName) -> DistrictFixture:
	_fx = DistrictFixture.new(planet_id)
	return _fx


# --- Launch progress ----------------------------------------------------------------------------

func test_the_first_planet_reads_the_accepted_values_from_its_table() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	assert_eq(Restoration.stage_values_for(def), VALUES)
	var fx: DistrictFixture = _fixture(FIRST)
	assert_eq(fx.restoration.launch_stage(), 5)
	assert_eq(fx.restoration.launch_sequence(), "bloom")
	var shares: Array[float] = []
	for step: Dictionary in fx.restoration.planet_steps():
		shares.append(float(step["share"]))
		assert_ne(str(step["name"]), "", "every step is named")
	assert_eq(shares, [0.01, 0.05, 0.25, 0.5, 1.0] as Array[float])


func test_a_district_is_worth_its_stage_value_plus_its_share_of_the_next_step() -> void:
	assert_almost_eq(Restoration.district_value(0, 0.0, VALUES), 0.0, 0.0001)
	assert_almost_eq(Restoration.district_value(0, 0.5, VALUES), 0.125, 0.0001)
	assert_almost_eq(Restoration.district_value(1, 0.0, VALUES), 0.25, 0.0001)
	assert_almost_eq(Restoration.district_value(3, 0.62, VALUES), 0.65 + 0.2 * 0.62, 0.0001)
	assert_almost_eq(Restoration.district_value(4, 1.0, VALUES), 1.0, 0.0001, "a full share meets the next value")
	assert_almost_eq(Restoration.district_value(5, 0.3, VALUES), 1.0, 0.0001, "the last stage is 1")
	assert_almost_eq(Restoration.district_value(9, 2.0, VALUES), 1.0, 0.0001, "clamped")
	assert_almost_eq(Restoration.district_value(-1, -1.0, VALUES), 0.0, 0.0001)


func test_launch_progress_is_the_mean_over_the_districts() -> void:
	var stages := PackedInt32Array([5, 4, 0, 0, 0, 0])
	var shares := PackedFloat32Array([1.0, 0.5, 0.0, 0.0, 0.0, 0.0])
	assert_almost_eq(Restoration.mean_value(stages, shares, VALUES), (1.0 + 0.925) / 6.0, 0.0001)
	assert_almost_eq(Restoration.mean_value(PackedInt32Array(), PackedFloat32Array(), VALUES), 0.0, 0.0001, "no districts: nothing")


func test_value_follows_the_live_districts(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	var n: float = float(fx.districts.count())
	var values: Array[float] = Restoration.stage_values_for(fx.def)
	assert_almost_eq(Restoration.value(), 0.0, 0.0001, "an untouched planet")
	var first: String = fx.districts.ids()[0]
	fx.set_district_stage(first, 3)
	assert_almost_eq(fx.restoration.launch_value(), values[3] / n, 0.0001)
	assert_almost_eq(Restoration.value(), fx.restoration.launch_value(), 0.0001, "the static read is the live world's")
	assert_almost_eq(Restoration.measure("launch"), fx.restoration.launch_value(), 0.0001)
	assert_eq(Restoration.measure("city_stage", first), 3.0)
	assert_eq(Restoration.measure("city_stage"), 3.0, "an empty key is the city the readout shows")
	assert_eq(Restoration.measure("cities_restored"), 0.0)
	assert_eq(Restoration.measure("stat"), -1.0, "not a planet measure")
	fx.free_systems()
	assert_almost_eq(Restoration.value(), 0.0, 0.0001, "no world: 0, never a stale value")


func test_a_planet_without_a_restoration_table_uses_even_steps(planet_id: StringName = use_parameters([DUMMY, PARKED])) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	assert_false(fx.def.has_table(Restoration.TABLE))
	assert_eq(Restoration.stage_values_for(fx.def), [0.0, 0.2, 0.4, 0.6, 0.8, 1.0] as Array[float])
	assert_eq(fx.restoration.launch_stage(), Districts.MAX_STAGE)
	assert_eq(fx.restoration.launch_sequence(), "", "no cinematic: straight to the end screen")
	assert_eq(fx.restoration.planet_steps().size(), 0)


# --- The launch point ---------------------------------------------------------------------------

func test_launch_ready_fires_once_and_only_when_every_city_is_thriving() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var ids: Array[String] = fx.districts.ids()
	watch_signals(EventBus)
	for i: int in ids.size():
		assert_signal_not_emitted(EventBus, "launch_ready", "%d of 6 thriving is not enough" % i)
		assert_eq(fx.restoration.districts_restored(), i)
		assert_false(fx.restoration.is_launched())
		fx.set_district_stage(ids[i], 4)
		assert_signal_not_emitted(EventBus, "launch_ready", "sustained is not thriving")
		fx.set_district_stage(ids[i], 5)
	assert_signal_emit_count(EventBus, "launch_ready", 1)
	assert_signal_emitted_with_parameters(EventBus, "launch_ready", [String(FIRST)])
	assert_true(fx.restoration.is_launched())
	assert_eq(fx.restoration.districts_restored(), 6)
	assert_almost_eq(fx.restoration.launch_value(), 1.0, 0.0001)
	assert_false(fx.restoration.check_launch(), "asked again: no")
	fx.set_district_stage(ids[0], 0, 5)
	fx.set_district_stage(ids[0], 5)
	fx.restoration._process(10.0)
	assert_signal_emit_count(EventBus, "launch_ready", 1, "never twice")


func test_launch_ready_on_a_planet_with_one_implicit_district(planet_id: StringName = use_parameters([DUMMY, PARKED])) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	watch_signals(EventBus)
	fx.set_district_stage(fx.districts.ids()[0], 5)
	assert_signal_emit_count(EventBus, "launch_ready", 1)
	assert_signal_emitted_with_parameters(EventBus, "launch_ready", [String(planet_id)])


func test_the_launch_rule_is_never_met_without_districts() -> void:
	assert_false(Restoration.rule_met({"when": "all_districts_stage", "stage": 5}, PackedInt32Array()))
	assert_false(Restoration.rule_met({"when": "all_districts_stage", "stage": 5}, PackedInt32Array([5, 5, 4])))
	assert_true(Restoration.rule_met({"when": "all_districts_stage", "stage": 5}, PackedInt32Array([5, 5, 5])))
	assert_true(Restoration.rule_met({"when": "all_districts_stage", "stage": 4}, PackedInt32Array([5, 4])))
	assert_false(Restoration.rule_met({"when": "something_else"}, PackedInt32Array([5])), "an unknown rule never fires")


func test_a_loaded_save_does_not_launch_again(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	for id: String in fx.districts.ids():
		fx.set_district_stage(id, 5)
	assert_true(fx.restoration.is_launched())
	fx.restoration.mark_ending_seen()
	fx.restoration.check_planet()
	var saved_d: Dictionary = JSON.parse_string(JSON.stringify(fx.districts.save_state()))
	var saved_r: Dictionary = JSON.parse_string(JSON.stringify(fx.restoration.save_state()))
	var steps_before: Array[Dictionary] = fx.restoration.planet_steps()
	fx.free_systems()
	fx.build_systems()
	fx.districts.load_state(saved_d)
	fx.restoration.load_state(saved_r)
	watch_signals(EventBus)
	fx.restoration._process(10.0)
	assert_true(fx.restoration.is_launched())
	assert_true(fx.restoration.is_ending_seen())
	assert_eq(fx.restoration.planet_steps(), steps_before)
	assert_signal_not_emitted(EventBus, "launch_ready")
	assert_signal_not_emitted(EventBus, "planet_step_reached")


func test_a_save_from_before_the_launch_rule_launches_on_its_next_check() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	for id: String in fx.districts.ids():
		fx.set_district_stage(id, 5)
	fx.free_systems()
	fx.build_systems()  # the hexes are all thriving, the save carries no restoration state
	fx.districts.load_state({})
	fx.restoration.load_state({})
	watch_signals(EventBus)
	assert_false(fx.restoration.is_launched())
	fx.restoration._process(10.0)
	assert_signal_emit_count(EventBus, "launch_ready", 1)


func test_launch_progress_changes_are_announced() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	watch_signals(EventBus)
	fx.restoration._process(10.0)
	assert_signal_emit_count(EventBus, "planet_restoration_changed", 1, "the first read")
	fx.restoration._process(10.0)
	assert_signal_emit_count(EventBus, "planet_restoration_changed", 1, "nothing changed")
	fx.set_district_stage("old_town", 1, 20)
	fx.restoration._process(10.0)
	assert_signal_emit_count(EventBus, "planet_restoration_changed", 2)


# --- The whole planet ---------------------------------------------------------------------------

func test_whole_planet_share_is_restored_land_over_all_land() -> void:
	var cells := SphereCells.new(1000)
	cells.junk.fill(1.0)
	assert_almost_eq(Restoration.share_of_cells(cells), 0.0, 0.0001)
	for c: int in 200:
		cells.set_state(c, PlanetData.State.WATER)
	for c: int in range(200, 400):
		cells.set_junk(c, 0.0)
	assert_almost_eq(Restoration.share_of_cells(cells), 200.0 / 800.0, 0.0001, "water is not land")
	cells.set_state(400, PlanetData.State.RESTORED)
	assert_almost_eq(Restoration.share_of_cells(cells), 201.0 / 800.0, 0.0001, "ground the regrowth front reached counts")
	assert_almost_eq(Restoration.share_of_cells(null), 0.0, 0.0001)
	var sea := SphereCells.new(10)
	sea.state.fill(PlanetData.State.WATER)
	assert_almost_eq(Restoration.share_of_cells(sea), 0.0, 0.0001, "no land: nothing to restore")


func test_planet_steps_are_reached_in_order_and_the_planet_is_restored_at_one() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var n: int = fx.cells.n
	watch_signals(EventBus)
	fx.restoration.check_planet()
	assert_signal_not_emitted(EventBus, "planet_step_reached")
	for c: int in ceili(n * 0.06):
		fx.set_cell_stage(c, 1)
	fx.restoration.check_planet()
	assert_signal_emit_count(EventBus, "planet_step_reached", 2, "1% and 5%")
	assert_eq(get_signal_parameters(EventBus, "planet_step_reached", 0), [String(FIRST), "first_green"])
	assert_eq(get_signal_parameters(EventBus, "planet_step_reached", 1), [String(FIRST), "green_belt"])
	fx.restoration.check_planet()
	assert_signal_emit_count(EventBus, "planet_step_reached", 2, "each step once")
	assert_signal_not_emitted(EventBus, "planet_restored")
	assert_signal_not_emitted(EventBus, "launch_ready", "the long goal is not the launch rule")
	for c: int in n:
		fx.cells.set_junk(c, 0.0)
	fx.restoration.check_planet()
	assert_signal_emit_count(EventBus, "planet_step_reached", 5)
	assert_signal_emit_count(EventBus, "planet_restored", 1)
	assert_signal_emitted_with_parameters(EventBus, "planet_restored", [String(FIRST)])
	assert_true(fx.restoration.is_planet_restored())
	fx.restoration.check_planet()
	assert_signal_emit_count(EventBus, "planet_restored", 1, "once")


func test_nothing_outside_the_planet_enters_the_measure() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	GameState.flags["cradle_returned"] = true
	GameState.flags["core_charge"] = 1.0
	assert_almost_eq(Restoration.value(), 0.0, 0.0001, "the old Bloom Core and ark flags do not move it")
	assert_false(fx.restoration.check_launch())
	GameState.flags.erase("cradle_returned")
	GameState.flags.erase("core_charge")


# --- The ending ---------------------------------------------------------------------------------

func test_the_end_screen_shows_the_stats_and_reports_the_choice() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var screen: EndScreen = EndScreen.open(host, {"planet": "Test World", "time_played": 3 * 3600.0 + 45 * 60.0,
		"hexes_cleaned": 512, "cities_restored": 6, "cities_total": 6, "robots_built": 149})
	watch_signals(screen)
	assert_true(get_tree().paused, "the game waits behind it")
	var rows: Array[Array] = screen.stat_rows()
	assert_eq(rows.size(), 4)
	assert_eq(str(rows[0][1]), "3 h 45 min")
	assert_eq(str(rows[1][1]), "512")
	assert_eq(str(rows[2][1]), "6 of 6")
	assert_eq(str(rows[3][1]), "149")
	assert_eq(EndScreen.fmt_time(12 * 60.0 + 30.0), "12 min")
	var texts: Array[String] = []
	for b: Node in screen.find_children("*", "Button", true, false):
		texts.append((b as Button).text)
	assert_eq(texts, ["Keep playing", "Quit to title"] as Array[String])
	screen.keep_playing()
	assert_signal_emit_count(screen, "kept_playing", 1)
	assert_false(get_tree().paused, "and the game goes on")
	screen.keep_playing()
	assert_signal_emit_count(screen, "kept_playing", 1, "a second press does nothing")


func test_launch_ready_shows_the_end_screen_once_per_save() -> void:
	var fx: DistrictFixture = _fixture(DUMMY)  # no cinematic: straight to the end screen
	var world := Node3D.new()
	add_child_autofree(world)
	var ending := PlanetEnding.new()
	ending.setup(world, fx.restoration)
	ending.skip_credits = true
	world.add_child(ending)
	watch_signals(EventBus)
	ending._process(PlanetEnding.CHECK_S)
	assert_signal_not_emitted(EventBus, "ending_shown", "nothing before the launch point")
	fx.set_district_stage(fx.districts.ids()[0], 5)
	assert_signal_emit_count(EventBus, "launch_ready", 1)
	ending._process(PlanetEnding.CHECK_S)
	await wait_process_frames(2)
	assert_signal_emit_count(EventBus, "ending_shown", 1)
	var screen: EndScreen = world.find_child("EndScreen", true, false) as EndScreen
	assert_not_null(screen, "the end screen is open")
	assert_true(fx.restoration.is_ending_seen())
	assert_eq(int(screen.stats["cities_restored"]), 1)
	assert_eq(int(screen.stats["cities_total"]), 1)
	screen.keep_playing()
	await wait_process_frames(2)
	assert_false(ending.is_running())
	for i: int in 5:
		ending._process(PlanetEnding.CHECK_S)
	EventBus.launch_ready.emit(String(DUMMY))  # even a stray second signal
	ending._process(PlanetEnding.CHECK_S)
	await wait_process_frames(2)
	assert_signal_emit_count(EventBus, "ending_shown", 1, "never again for this save")
	# A reload of that save: seen, so no ending.
	var again := PlanetEnding.new()
	again.setup(world, fx.restoration)
	world.add_child(again)
	again._process(PlanetEnding.CHECK_S)
	await wait_process_frames(2)
	assert_signal_emit_count(EventBus, "ending_shown", 1)


func test_a_save_that_quit_before_the_end_screen_sees_the_ending_on_load() -> void:
	var fx: DistrictFixture = _fixture(DUMMY)
	fx.set_district_stage(fx.districts.ids()[0], 5)
	assert_true(fx.restoration.is_launched())
	assert_false(fx.restoration.is_ending_seen())
	var world := Node3D.new()
	add_child_autofree(world)
	var ending := PlanetEnding.new()
	ending.setup(world, fx.restoration)
	ending.skip_credits = true
	world.add_child(ending)
	watch_signals(EventBus)
	ending._process(PlanetEnding.CHECK_S)
	await wait_process_frames(2)
	assert_signal_emit_count(EventBus, "ending_shown", 1)
	(world.find_child("EndScreen", true, false) as EndScreen).keep_playing()
