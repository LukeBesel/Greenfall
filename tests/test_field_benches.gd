extends GutTest
## Field benches (systems/camp/field_benches.gd) and the rocket's faster cells
## (automation/rocket_tiers.gd, automation/rocket_charge.gd), task M3-22. The bench rules take the
## planet id and run on the first planet and on the dummy planet (one city on the start site:
## nothing is ever offered there).

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"

var _fx: DistrictFixture
var _planet: StringName
var _saved: Dictionary = {}
var _set_up_events: Array[String] = []


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
	RocketTiers.now_override = 1000.0
	_set_up_events.clear()
	EventBus.field_bench_set_up.connect(_on_set_up)


func after_each() -> void:
	EventBus.field_bench_set_up.disconnect(_on_set_up)
	if _fx:
		_fx.free_systems()
	_fx = null
	RocketTiers.now_override = -1.0
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.stats = _saved["stats"]
	Planets.set_current(_planet)


func _on_set_up(id: String) -> void:
	_set_up_events.append(id)


## The planet's districts on the fixture globe, with `visited` cities reached (and so unlocked).
func _rules(planet_id: StringName, visited: Array[String] = []) -> FieldBenches:
	Planets.set_current(planet_id)
	_fx = DistrictFixture.new(planet_id)
	_fx.districts.load_state({"visited": visited, "unlocked": visited})
	var fb := FieldBenches.new()
	fb.setup(_fx.districts)
	return fb


## A city of the planet that does not stand on the start site ("" on a planet with none).
func _away_city(d: Districts) -> String:
	for id: String in d.ids():
		if d.site_of(id) != FieldBenches.START_SITE:
			return id
	return ""


# --- Where a bench is offered ----------------------------------------------------------------

func test_the_start_city_never_gets_a_field_bench() -> void:
	for pid: StringName in [FIRST, DUMMY]:
		var fb: FieldBenches = _rules(pid)
		var start: String = _fx.districts.ids()[0]
		assert_true(_fx.districts.is_visited(start), "%s: the start city is reached" % pid)
		assert_false(fb.offered(start), "%s: its own workbench stands in the start yard" % pid)
		assert_false(fb.set_up(start), "%s: nothing to set up there" % pid)
		assert_true(fb.shown().is_empty(), "%s: no kit or bench at a fresh start" % pid)
		after_each()
		before_each()


func test_a_kit_waits_in_a_city_once_lumi_reaches_it() -> void:
	var fb: FieldBenches = _rules(FIRST)
	var city: String = _away_city(_fx.districts)
	assert_ne(city, "", "the first planet has cities off the start site")
	assert_false(fb.offered(city), "not before Lumi gets there")
	after_each()
	before_each()
	fb = _rules(FIRST, [city] as Array[String])
	assert_true(fb.offered(city), "a kit waits on arrival")
	assert_eq(fb.shown().size(), 1)
	assert_eq(int(fb.shown()[0]["site"]), _fx.districts.site_of(city), "on the city's own site")
	assert_false(bool(fb.shown()[0]["ready"]), "packed until set up")


func test_setting_up_pays_the_data_cost_and_says_so_once() -> void:
	var city: String = "scrapyard"
	var fb: FieldBenches = _rules(FIRST, [city] as Array[String])
	var cost: Dictionary = FieldBenches.cost()
	for k: String in cost:
		GameState.add_currency(k, BigNum.from_float(float(cost[k])))
	assert_eq(fb.block_reason(city), "", "affordable once reached")
	assert_true(fb.set_up(city))
	assert_true(fb.is_set_up(city))
	assert_false(fb.offered(city), "no kit once the bench stands")
	assert_true(bool(fb.shown()[0]["ready"]))
	for k2: String in cost:
		assert_almost_eq(GameState.get_currency(k2).to_float(), 0.0, 0.001, "%s paid" % k2)
	assert_false(fb.set_up(city), "a bench is set up once")
	assert_eq(_set_up_events, [city] as Array[String], "one event, with the city")


func test_a_bench_with_a_price_waits_for_it() -> void:
	var fb: FieldBenches = _rules(FIRST, ["scrapyard"] as Array[String])
	if FieldBenches.cost().is_empty():
		assert_eq(fb.block_reason("scrapyard"), "", "a free bench is never held back")
		return
	assert_ne(fb.block_reason("scrapyard"), "", "not affordable with nothing in hand")
	assert_false(fb.set_up("scrapyard"))


# --- Saves ------------------------------------------------------------------------------------

func test_benches_survive_a_save_and_load() -> void:
	var fb: FieldBenches = _rules(FIRST, ["scrapyard", "kettle_bay"] as Array[String])
	assert_true(fb.set_up("scrapyard"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(fb.save_state()))
	var back := FieldBenches.new()
	back.setup(_fx.districts)
	back.load_state(saved, true)
	assert_true(back.is_set_up("scrapyard"))
	assert_false(back.is_set_up("kettle_bay"), "a kit not set up stays a kit")
	assert_true(back.offered("kettle_bay"))


func test_a_save_from_before_field_benches_has_one_in_every_city_reached() -> void:
	for pid: StringName in [FIRST, DUMMY]:
		var visited: Array[String] = []
		Planets.set_current(pid)
		var probe := DistrictFixture.new(pid)
		for id: String in probe.districts.ids():
			visited.append(id)
		probe.free_systems()
		var fb: FieldBenches = _rules(pid, visited.slice(0, mini(3, visited.size())))
		fb.load_state({}, false)
		for id2: String in visited.slice(0, mini(3, visited.size())):
			assert_eq(fb.is_set_up(id2), fb.has_site(id2), "%s %s: reached, so its bench stands (never the start city)" % [pid, id2])
		for id3: String in visited.slice(3):
			assert_false(fb.is_set_up(id3), "%s %s: not reached" % [pid, id3])
		after_each()
		before_each()


func test_each_city_bench_has_its_own_colours() -> void:
	Planets.set_current(FIRST)
	var a: Dictionary[String, Color] = FieldBenches.look_of("scrapyard")
	var b: Dictionary[String, Color] = FieldBenches.look_of("kettle_bay")
	assert_ne(a["canopy"], b["canopy"], "two cities, two tarps")
	assert_eq(FieldBenches.look_of("no_such_city")["frame"], FieldBenches.look_of("another_unknown")["frame"], "the default look")
	for k: String in ["frame", "panel", "canopy", "trim"]:
		assert_gt(a[k].get_luminance() + a[k].s, 0.35, "%s is bright, not drab" % k)


# --- The rocket's cells ---------------------------------------------------------------------------

func test_mk1_cells_recharge_in_thirty_seconds() -> void:
	assert_almost_eq(float(RocketTiers.def(1)["recharge_s"]), 30.0, 0.001, "data/rockets.json")
	RocketTiers.mark_launched()
	assert_almost_eq(RocketTiers.recharge_left(), 30.0, 0.001)
	RocketTiers.now_override += 30.0
	assert_eq(RocketTiers.recharge_left(), 0.0, "full after 30 s of nothing")


func test_charge_by_brings_the_cells_closer_and_never_past_full() -> void:
	RocketTiers.mark_launched()
	assert_almost_eq(RocketTiers.charge_by(10.0), 10.0, 0.001)
	assert_almost_eq(RocketTiers.recharge_left(), 20.0, 0.001)
	assert_almost_eq(RocketTiers.charge_by(100.0), 20.0, 0.001, "only what was left")
	assert_eq(RocketTiers.recharge_left(), 0.0)
	assert_eq(RocketTiers.charge_by(5.0), 0.0, "full cells take nothing")


func test_work_in_the_rocket_city_charges_the_cells_faster() -> void:
	var rc := RocketCharge.new()
	add_child_autofree(rc)
	rc.set_physics_process(false)
	rc.in_city_fn = func() -> bool: return true
	RocketTiers.mark_launched()
	var cfg: Dictionary = RocketTiers.work_cfg()
	EventBus.pollution_cleared.emit("litter", 5.0, true)
	assert_gt(rc.working_s, 0.0, "her own cleaning counts as work")
	rc.step(1.0)
	RocketTiers.now_override += 1.0
	assert_almost_eq(RocketTiers.recharge_left(), 30.0 - 1.0 - float(cfg["extra_rate"]), 0.01, "a working second is worth more")
	var before: float = RocketTiers.recharge_left()
	EventBus.cube_made.emit({})
	assert_almost_eq(RocketTiers.recharge_left(), before - float(cfg["per_bale_s"]), 0.01, "a pressed bale adds a lump")


func test_idle_robots_or_another_city_do_not_charge_the_cells() -> void:
	var rc := RocketCharge.new()
	add_child_autofree(rc)
	rc.set_physics_process(false)
	var here: Array[bool] = [true]
	rc.in_city_fn = func() -> bool: return here[0]
	RocketTiers.mark_launched()
	EventBus.pollution_cleared.emit("litter", 50.0, false)
	assert_eq(rc.working_s, 0.0, "robots' work does not count")
	rc.step(1.0)
	assert_almost_eq(RocketTiers.recharge_left(), 30.0, 0.01, "no bonus with nothing done")
	here[0] = false
	EventBus.hand_tended.emit(Surge.TEND_PLANT)
	assert_gt(rc.working_s, 0.0, "planting is work")
	rc.step(1.0)
	assert_almost_eq(RocketTiers.recharge_left(), 30.0, 0.01, "but not in another city")
	here[0] = true
	rc.step(1.0)
	assert_lt(RocketTiers.recharge_left(), 30.0, "back in the rocket's city, the window still counts")
