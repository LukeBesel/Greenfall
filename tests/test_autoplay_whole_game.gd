extends GutTest
## The play bot's whole-planet layer (tools/autoplay_travel.gd, tools/autoplay_cadence.gd,
## tools/autoplay_stall.gd): which city it flies to, the per-city cadence table and the stall watch
## that ends a dead run with a non-zero exit code. Planner tests take the planet id and run on the
## first planet and on the dummy planet (one district, no table).

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"

var _fx: DistrictFixture
var _sources: Sources
var _planet: StringName
var _saved: Dictionary = {}


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


## The planet's districts and source jobs on the fixture globe, after `stages` ({city: stage}) were
## set on its hexes (a load, as the world does it).
func _world(planet_id: StringName, stages: Dictionary = {}) -> Districts:
	Planets.set_current(planet_id)
	_fx = DistrictFixture.new(planet_id, false)
	_fx.build_systems()
	for id: String in stages:
		_fx.set_district_stage(id, int(stages[id]))
	_fx.free_systems()
	_fx.build_systems()
	_sources = Sources.new()
	_sources.setup(_fx.def, _fx.districts)
	_sources.load_state({}, {})
	_fx.districts.load_state({})
	return _fx.districts


# --- Where to fly ----------------------------------------------------------------------------

func test_planner_keeps_lumi_in_the_first_city_at_a_fresh_start() -> void:
	for pid: StringName in [FIRST, DUMMY]:
		var d: Districts = _world(pid)
		assert_eq(AutoplayTravel.target_city(d, _sources), d.ids()[0], "%s: the start city" % pid)
		assert_eq(d.site_of(d.ids()[0]), 0, "%s: it stands on the start site" % pid)
		after_each()
		before_each()


func test_planner_does_an_open_source_job_before_moving_on() -> void:
	var d: Districts = _world(FIRST, {"old_town": 4})
	assert_true(d.is_unlocked("scrapyard"), "stage 4 in the first city opens the second")
	GameState.add_currency("cubes", BigNum.from_float(1.0e6))
	GameState.add_currency("parts", BigNum.from_float(1.0e6))
	assert_true(AutoplayTravel.job_waiting(_sources, "old_town"), "the first city's job is on offer and paid for")
	assert_eq(AutoplayTravel.target_city(d, _sources), "old_town", "the job first: only Lumi can do it")


func test_planner_moves_to_the_newest_city_once_the_job_is_done() -> void:
	var d: Districts = _world(FIRST, {"old_town": 4})
	_sources.force_shut("old_town")
	assert_eq(AutoplayTravel.target_city(d, _sources), "scrapyard")


func test_planner_moves_on_when_the_job_cannot_be_paid_yet() -> void:
	var d: Districts = _world(FIRST, {"old_town": 4})
	if AutoplayTravel.job_waiting(_sources, "old_town"):
		pass_test("the first job costs nothing on this table")
		return
	assert_eq(AutoplayTravel.target_city(d, _sources), "scrapyard", "an unpaid job does not hold Lumi back")


func test_planner_returns_to_a_city_below_the_last_stage_when_every_city_is_open() -> void:
	var stages: Dictionary = {"old_town": 4, "scrapyard": 4, "kettle_bay": 4, "highreach": 4, "lowmeadow": 4, "old_capital": 5}
	var d: Districts = _world(FIRST, stages)
	for id: String in d.ids():
		_sources.force_shut(id)
	assert_true(d.is_unlocked("old_capital"))
	assert_eq(AutoplayTravel.target_city(d, _sources), "old_town", "the earliest city still short of the last stage")


func test_planner_stays_in_the_last_city_until_its_job_is_done() -> void:
	var stages: Dictionary = {"old_town": 4, "scrapyard": 4, "kettle_bay": 4, "highreach": 4, "lowmeadow": 4, "old_capital": 4}
	var d: Districts = _world(FIRST, stages)
	for id: String in ["old_town", "scrapyard", "kettle_bay", "highreach", "lowmeadow"]:
		_sources.force_shut(id)
	assert_eq(AutoplayTravel.target_city(d, _sources), "old_capital")


func test_open_stage_is_read_from_the_next_citys_unlock_rule() -> void:
	var d: Districts = _world(FIRST)
	assert_eq(AutoplayTravel.open_stage(d, "old_town"), 4)
	assert_eq(AutoplayTravel.open_stage(d, "old_capital"), Districts.MAX_STAGE, "the last city opens nothing")


func test_home_trip_comes_for_a_tool_at_once_and_for_shopping_only_now_and_then() -> void:
	var t := AutoplayTravel.new()
	assert_true(t.home_wanted(true, false, false, 10.0), "a city's tool waits at the bench")
	assert_true(t.home_wanted(false, true, false, 10.0), "the Assembler is on offer")
	assert_false(t.home_wanted(false, false, true, AutoplayTravel.SHOP_EVERY_S - 1.0), "shopping waits its turn")
	assert_true(t.home_wanted(false, false, true, AutoplayTravel.SHOP_EVERY_S), "then it is worth the flight")
	t.shopped(2000.0)
	assert_false(t.home_trip)
	assert_false(t.home_wanted(false, false, true, 2000.0 + AutoplayTravel.SHOP_EVERY_S - 1.0), "counted from the last trip home")


# --- The cadence table -------------------------------------------------------------------------

func _cities() -> Array[Dictionary]:
	return [{"id": "a", "name": "A", "pollution": ["litter"]}, {"id": "b", "name": "B", "pollution": ["litter", "wrecks"]},
		{"id": "c", "name": "C", "pollution": ["litter", "wrecks", "slick"]}]


func test_cadence_names_each_citys_new_kind_and_dates_its_first_mastery() -> void:
	var c := AutoplayCadence.new()
	c.setup(_cities())
	assert_eq(str(c.rows[1]["kind"]), "wrecks")
	assert_eq(str(c.rows[2]["kind"]), "slick")
	c.mastery_gained("wrecks", 1, 500.0)
	c.mastery_gained("wrecks", 2, 600.0)
	c.mastery_gained("litter", 1, 50.0)
	assert_eq(float(c.rows[1]["mastery1_s"]), 500.0, "the first level only")
	assert_eq(float(c.rows[0]["mastery1_s"]), 50.0)


func test_cadence_splits_the_run_into_city_spans_by_arrival() -> void:
	var c := AutoplayCadence.new()
	c.setup(_cities())
	c.arrive("a", 0.0, 0)
	for t: float in [30.0, 60.0, 200.0]:
		c.spent(t)
	c.sample(100.0, 900.0, 5.0)
	c.arrive("b", 300.0, 8)
	c.spent(320.0)
	c.sample(310.0, 400.0, 40.0)
	c.goal_done(350.0)
	var rows: Array[Dictionary] = c.table(1000.0, 12)
	assert_eq(int(rows[0]["purchases"]), 3)
	assert_eq(float(rows[0]["longest_wait_s"]), 140.0, "200 to 300 is shorter than 60 to 200")
	assert_eq(float(rows[0]["cubes_max"]), 900.0)
	assert_eq(int(rows[0]["crew_leave"]), 8, "the crew on reaching the next city")
	assert_eq(int(rows[1]["purchases"]), 1)
	assert_eq(float(rows[1]["longest_wait_s"]), 680.0, "the last span runs to the end of the run")
	assert_eq(float(rows[1]["goal_gap_s"]), 650.0)
	assert_eq(int(rows[1]["crew_leave"]), 12)
	assert_eq(float(rows[2]["arrive_s"]), -1.0, "a city not reached has no span")
	assert_false(rows[2].has("purchases"))


func test_cadence_counts_an_arrival_once() -> void:
	var c := AutoplayCadence.new()
	c.setup(_cities())
	c.arrive("a", 0.0, 0)
	c.arrive("b", 300.0, 8)
	c.arrive("a", 900.0, 30)
	assert_eq(float(c.rows[0]["arrive_s"]), 0.0)
	assert_eq(int(c.rows[0]["crew_leave"]), 8)


func test_cadence_report_has_a_row_per_city_and_the_launch_time() -> void:
	var c := AutoplayCadence.new()
	c.setup(_cities())
	c.arrive("a", 0.0, 0)
	c.stage_reached("a", 5, 400.0)
	c.launched(900.0)
	var report: Dictionary = {}
	c.write(report, 1000.0, 3)
	assert_eq((report["cadence"] as Array).size(), 3)
	assert_eq(float(report["cadence"][0]["stage4_s"]), 400.0, "stage 5 passes stage 4 too")
	assert_eq(float(report["launch_s"]), 900.0)


# --- Stalls ------------------------------------------------------------------------------------

func test_stall_watch_fires_after_four_minutes_with_no_progress() -> void:
	var s := AutoplayStall.new()
	assert_eq(AutoplayStall.LIMIT_S, 240.0)
	s.progress(100.0)
	assert_false(s.tick(300.0, "cleaning"))
	assert_false(s.tick(340.0, "cleaning"), "exactly four minutes is not over the limit")
	assert_true(s.tick(341.0, "cleaning hex 7"))
	assert_eq(str(s.stalled["doing"]), "cleaning hex 7", "says what the bot was trying to do")
	assert_false(s.tick(400.0, "cleaning"), "fires once")


func test_stall_watch_resets_on_progress() -> void:
	var s := AutoplayStall.new()
	s.progress(0.0)
	s.tick(200.0, "")
	s.progress(230.0)
	assert_false(s.tick(460.0, ""))
	var report: Dictionary = {}
	s.write(report, 460.0)
	assert_null(report["stall"])
	assert_eq(float(report["longest_idle_s"]), 230.0)


func test_stall_watch_does_not_count_flights_and_cinematics() -> void:
	var s := AutoplayStall.new()
	s.progress(0.0)
	s.tick(100.0, "")
	s.pause(100.0)
	s.pause(400.0)
	assert_false(s.tick(400.0, "flying"), "300 s in the air is not idle play")
	assert_true(s.tick(541.0, "cleaning"))


func test_cadence_table_carries_over_to_the_next_stage_of_a_staged_run() -> void:
	var c := AutoplayCadence.new()
	c.setup(_cities())
	c.arrive("a", 0.0, 0)
	c.spent(40.0)
	c.sample(20.0, 500.0, 3.0)
	c.arrive("b", 300.0, 8)
	var next := AutoplayCadence.new()
	next.setup(_cities())
	next.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	next.arrive("a", 900.0, 30)
	assert_eq(float(next.rows[0]["arrive_s"]), 0.0, "the first stage's arrival stands")
	var rows: Array[Dictionary] = next.table(1000.0, 30)
	assert_eq(int(rows[0]["purchases"]), 1)
	assert_eq(float(rows[0]["cubes_max"]), 500.0)
	assert_eq(float(rows[1]["arrive_s"]), 300.0)
