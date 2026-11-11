extends GutTest
## What a running source does to the ground round it (systems/source_spread.gd, design spec
## section 4): hexes in its reach cannot pass a regrowth stage, clean hexes there are slowly fouled
## again, and both stop when the source is shut down. The waste that comes back is the globe's own
## (systems/pollution_soil.gd). The first planet's five polluting sources, its rocket (which
## fouls nothing), a planet with no table and the dummy planet with a table of its own.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PARKED: StringName = &"ochre"
const POLLUTERS: Array[String] = ["old_town", "scrapyard", "kettle_bay", "highreach", "lowmeadow"]
const ROCKET_CITY: String = "old_capital"
const SPREAD_TABLE: String = "res://tests/fixtures/sources_spread.json"
const SEED: int = 4471
## "A modest crew": the trickle of one source is at most this share of what one robot of the
## planet's first cleaner type clears, untrained and at its first tier, so one small robot keeps
## up with it with time to spare for the drive.
const MODEST_SHARE: float = 0.5
## Everything a source may have lying fouled at once is at most this many seconds of that robot.
const BACKLOG_S: float = 180.0

var _saved: Dictionary = {}
var _fx: DistrictFixture
var _sources: Sources
var _spread: SourceSpread
var _nodes: Array[Node] = []
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
	for n: Node in _nodes + [_sources, _spread]:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	_sources = null
	_spread = null
	if _fx:
		_fx.free_systems()
	_fx = null
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.stats = _saved["stats"]
	Planets.set_current(_planet)


## A planet's districts, source jobs and their spread on the fixture globe, as the world sets them
## up. Every city before `upto` (and it) is unlocked with its hexes at `stage`.
func _world(planet_id: StringName, def: PlanetDefinition = null) -> SourceSpread:
	Planets.set_current(planet_id)
	_fx = DistrictFixture.new(planet_id, false)
	if def != null:
		_fx.def = def
	_fx.build_systems()
	_sources = Sources.new()
	_sources.setup(_fx.def, _fx.districts)
	_sources.load_state({}, {})
	_fx.districts.load_state({})
	_spread = SourceSpread.new()
	_spread.setup(_fx.def, _sources, _fx.districts, _fx.cells)
	return _spread


func _with_table(path: String) -> PlanetDefinition:
	var def: PlanetDefinition = Planets.by_id(DUMMY).duplicate()
	def.tables = def.tables.duplicate()
	def.tables[Sources.TABLE] = path
	return def


## Opens every city up to `city` and sets that city's hexes to `stage`.
func _reach_city(city: String, stage: int) -> void:
	for id: String in _fx.districts.ids():
		_fx.set_district_stage(id, stage if id == city else Districts.MAX_STAGE - 1)
		if id == city:
			return


## The planet's kinds on the fixture's cells, with a real field, so soil goes through the game's
## own ledger.
func _pollution() -> Pollution:
	var field := SphereField.new(_fx.grid, SphereTerrain.new(_fx.grid, SEED), _fx.cells, SEED)
	field.worth = HexWorth.for_planet(_fx.def, _fx.grid, _fx.site_cells)
	var p := Pollution.new()
	_nodes.append(p)
	p.setup(_fx.def, _fx.grid, _fx.cells, field, _fx.site_cells, {})
	_spread.soil_fn = p.soil
	return p


func _first_cleaner() -> String:
	for id: String in Economy.robot_order:
		if str((Economy.robots[id] as Dictionary).get("role", "")) == "clean":
			return id
	return ""


# --- The data -----------------------------------------------------------------------------------

func test_every_polluting_source_reaches_into_its_city_and_the_rocket_does_not() -> void:
	var s: SourceSpread = _world(FIRST)
	assert_eq(s.ids(), POLLUTERS, "five sources foul the ground; the rocket is a build, not a leak")
	for id: String in POLLUTERS:
		var spec: Dictionary = s.spec_of(id)
		assert_eq(int(spec["hex_stage"]), 3, "%s: the lead's decision, hexes cannot pass stage 3" % id)
		assert_eq(s.reach_of(id).size(), int(spec["hexes"]), "%s: the whole reach is land" % id)
		assert_ne(str(spec["kind"]), "", "%s names the kind that comes back" % id)
		assert_true(str(spec["kind"]) in (_fx.districts.spec_of(id)["pollution"] as Array), "%s: a kind of its own city" % id)
		for c: int in s.reach_of(id):
			assert_eq(_fx.districts.district_of_cell(c), id)
	assert_eq(s.reach_of(ROCKET_CITY).size(), 0)
	assert_eq(s.hex_cap(_fx.districts.cells_of(ROCKET_CITY)[8]), Districts.MAX_STAGE)


func test_the_trickle_is_never_faster_than_a_modest_crew(city: String = use_parameters(POLLUTERS)) -> void:
	var s: SourceSpread = _world(FIRST)
	var spec: Dictionary = s.spec_of(city)
	var robot: float = Offline.unit_rate(_first_cleaner(), 0)
	assert_gt(robot, 0.0)
	var trickle: float = SourceSpread.units_per_s(spec, SphereOffline.UNITS_PER_CELL)
	assert_gt(trickle, 0.0, "it does foul the ground")
	assert_lte(trickle, robot * MODEST_SHARE, "one small robot clears it in under half its time")
	var backlog: float = float(spec["max_soiled"]) * float(spec["amount"]) * SphereOffline.UNITS_PER_CELL
	assert_lte(backlog / robot, BACKLOG_S, "and all that can lie fouled is a few minutes of its work")
	assert_gt(float(spec["amount"]), SphereCells.CLEAN_LEFT, "what comes back is enough to count as dirty")


func test_the_reach_never_locks_a_city_out_of_its_job(city: String = use_parameters(POLLUTERS)) -> void:
	var s: SourceSpread = _world(FIRST)
	var d: Districts = _fx.districts
	var open_stage: int = int(_sources.spec_of(city)["open_stage"])
	assert_lte(s.reach_of(city).size(), s.spare_hexes(city), "the reach is fewer hexes than the city may leave behind")
	_reach_city(city, s.hex_cap(s.reach_of(city)[0]))  # the reach as far as the source lets it grow
	assert_lt(d.stage_of(city), open_stage)
	for c: int in d.cells_of(city):  # and the rest of the city on to the job's stage
		if not c in s.reach_of(city) and Districts.cell_stage(_fx.cells, c) != Districts.NOT_LAND:
			_fx.set_cell_stage(c, open_stage)
	assert_lt(s.hex_cap(s.reach_of(city)[0]), open_stage, "the reach is held below the job's stage")
	assert_eq(d.stage_of(city), open_stage, "and the city still reaches it")
	assert_true(_sources.is_open(city), "so the job comes on offer")
	var next: int = d.ids().find(city) + 1
	assert_true(d.is_unlocked(d.ids()[next]), "and the next city opens")


# --- The hold -----------------------------------------------------------------------------------

func test_hexes_in_the_reach_cannot_pass_the_held_stage_until_the_source_is_shut(city: String = use_parameters(POLLUTERS)) -> void:
	var s: SourceSpread = _world(FIRST)
	var near: int = s.reach_of(city)[0]
	var far: int = _fx.districts.cells_of(city)[_fx.districts.cells_of(city).size() - 1]
	var levels := HexLevels.new()
	_nodes.append(levels)
	levels.cap_fn = s.hex_cap
	levels.levels = {near: 2, far: 2}
	assert_true(s.holds(near))
	assert_false(s.holds(far), "ground far from the source grows freely")
	assert_eq(levels.capped(near, 5), 3, "a hex that would thrive waits at stage 3")
	assert_eq(levels.capped(near, 3), 3)
	assert_eq(levels.capped(near, 2), 2)
	assert_eq(levels.capped(far, 5), 5)
	levels.levels[near] = 4
	assert_eq(levels.capped(near, 5), 4, "a level a hex already has is never taken back")
	levels.levels[near] = 3
	assert_true(_sources.force_shut(city))
	assert_false(s.holds(near))
	assert_eq(levels.capped(near, 5), 5, "shut down: the hex rises as far as it has grown")
	for other: String in POLLUTERS:
		if other != city:
			assert_true(s.holds(s.reach_of(other)[0]), "%s's source still holds its own ground" % other)


func test_the_hex_readout_says_why() -> void:
	var s: SourceSpread = _world(FIRST)
	var near: int = s.reach_of("old_town")[0]
	var far: int = _fx.districts.cells_of("old_town")[_fx.districts.cells_of("old_town").size() - 1]
	_fx.set_district_stage("old_town", 2)
	assert_eq(s.hex_note(near), "", "still growing toward the held stage: nothing to explain")
	_fx.set_district_stage("old_town", 3)
	assert_eq(s.hex_note(near), "SOURCE STILL RUNNING", "held at its stage")
	assert_eq(s.hex_note(far), "", "a hex outside the reach is not the source's doing")
	_fx.set_cell_stage(near, 0)
	assert_eq(s.hex_note(near), "SOURCE STILL RUNNING", "lying dirty in the reach while the source fouls it")
	_sources.force_shut("old_town")
	assert_eq(s.hex_note(near), "")
	_fx.set_cell_stage(near, 3)
	assert_eq(s.hex_note(near), "", "shut down: nothing holds the hex")


# --- The trickle --------------------------------------------------------------------------------

func test_clean_ground_in_the_reach_is_fouled_again_slowly(city: String = use_parameters(POLLUTERS)) -> void:
	var s: SourceSpread = _world(FIRST)
	var spec: Dictionary = s.spec_of(city)
	var every: float = float(spec["every_s"])
	watch_signals(EventBus)
	_reach_city(city, int(spec["from_stage"]))
	assert_true(s.trickling(city))
	assert_eq(s.step(city, every - 1.0), -1, "not before its time")
	assert_eq(s.dirty_in_reach(city), 0)
	var c: int = s.step(city, 1.0)
	assert_true(c in s.reach_of(city), "one hex of the reach")
	assert_true(_fx.cells.is_dirty(c))
	assert_almost_eq(_fx.cells.junk[c], float(spec["amount"]), 0.0001, "part of its waste is back")
	assert_signal_emitted_with_parameters(EventBus, "source_soiled", [city, c])
	assert_eq(s.dirty_in_reach(city), 1)
	assert_eq(_fx.districts.stage_of(city), int(spec["from_stage"]), "a stage the city has is never taken back")
	assert_eq(s.step(city, every * 0.5), -1, "one hex each period, no more")


func test_the_trickle_waits_while_enough_lies_fouled_and_goes_on_when_it_is_cleared() -> void:
	var s: SourceSpread = _world(FIRST)
	var spec: Dictionary = s.spec_of("old_town")
	var every: float = float(spec["every_s"])
	_reach_city("old_town", int(spec["from_stage"]))
	var fouled: Array[int] = []
	for _i: int in int(spec["max_soiled"]) + 4:
		var c: int = s.step("old_town", every)
		if c >= 0:
			fouled.append(c)
	assert_eq(fouled.size(), int(spec["max_soiled"]), "it stops at its limit however long nobody comes")
	assert_eq(s.dirty_in_reach("old_town"), int(spec["max_soiled"]))
	_fx.set_cell_stage(fouled[0], 3)
	assert_ne(s.step("old_town", every), -1, "one cleared, one more comes")
	assert_eq(s.dirty_in_reach("old_town"), int(spec["max_soiled"]))


func test_nothing_is_fouled_before_the_city_has_reached_the_trickles_stage_or_is_open() -> void:
	var s: SourceSpread = _world(FIRST)
	var spec: Dictionary = s.spec_of("old_town")
	assert_gt(int(spec["from_stage"]), 0, "the first cleaning of a city is never undone")
	_fx.set_district_stage("old_town", 1, s.reach_of("old_town").size())  # the reach is clean, the city is not
	assert_false(s.trickling("old_town"))
	assert_eq(s.step("old_town", 10000.0), -1)
	assert_eq(s.dirty_in_reach("old_town"), 0)
	_fx.set_district_stage("scrapyard", Districts.MAX_STAGE)
	assert_false(_fx.districts.is_unlocked("scrapyard"))
	assert_eq(s.step("scrapyard", 10000.0), -1, "a locked city's source fouls nothing")


func test_the_trickle_stops_at_shutdown() -> void:
	var s: SourceSpread = _world(FIRST)
	var every: float = float(s.spec_of("old_town")["every_s"])
	_reach_city("old_town", Districts.MAX_STAGE)
	assert_ne(s.step("old_town", every), -1)
	assert_true(_sources.force_shut("old_town"))
	assert_false(s.trickling("old_town"))
	for _i: int in 5:
		assert_eq(s.step("old_town", every), -1, "shut down: nothing comes back")
	assert_eq(s.dirty_in_reach("old_town"), 1, "what lay there stays until it is cleaned")


# --- The waste that comes back (systems/pollution_soil.gd) ---------------------------------------

func test_fouled_ground_keeps_its_level_and_shows_its_growth_again_when_cleaned() -> void:
	var s: SourceSpread = _world(FIRST)
	var spec: Dictionary = s.spec_of("old_town")
	_reach_city("old_town", 3)
	var p: Pollution = _pollution()
	for c: int in s.reach_of("old_town"):
		_fx.cells.set_state(c, PlanetData.State.GROWING)
	var c: int = s.step("old_town", float(spec["every_s"]))
	assert_ne(c, -1)
	assert_true(_fx.cells.is_dirty(c))
	assert_true(p.is_soiled(c))
	assert_eq(p.kinds_left(c), ["litter"] as Array[String], "Old Town's own kind lies there again")
	assert_almost_eq(_fx.cells.junk[c], float(spec["amount"]), 0.0001)
	assert_eq(int(_fx.cells.level[c]), 3, "the hex keeps the level it grew to")
	assert_eq(Districts.cell_stage(_fx.cells, c), 0, "but counts as dirty until it is cleaned")
	assert_almost_eq(p.soil(c, "litter", 0.5), 0.0, 0.0001, "a dirty hex is not fouled twice")
	SphereOffline.write_cell(_fx.cells, p._field, c, 0.0)  # a robot clears it
	p._soil.settle()
	assert_false(p.is_soiled(c))
	assert_eq(_fx.cells.state[c], PlanetData.State.GROWING, "clean again: it shows what grew on it")
	assert_eq(Districts.cell_stage(_fx.cells, c), 3)


func test_a_kind_worked_with_a_tool_comes_back_as_itself() -> void:
	_world(FIRST)
	_reach_city("highreach", 3)
	var p: Pollution = _pollution()
	var smog_hex: int = -1
	var plain_hex: int = -1
	for c: int in _fx.districts.cells_of("highreach"):
		if p._index["smog"] in p.kinds_at(c):
			smog_hex = c if smog_hex < 0 else smog_hex
		else:
			plain_hex = c if plain_hex < 0 else plain_hex
	assert_ne(smog_hex, -1, "some hex of the city holds smog")
	var back: float = p.soil(smog_hex, "smog", 0.25)
	assert_gt(back, SphereCells.CLEAN_LEFT)
	assert_true("smog" in p.kinds_left(smog_hex), "smog lies on it again")
	assert_almost_eq(_fx.cells.floor_of(smog_hex), back, 0.0001, "and a scoop cannot take it: it needs the can")
	assert_false(_fx.cells.workable(smog_hex), "a cleaner robot leaves it to the right tool")
	if plain_hex >= 0:
		assert_gt(p.soil(plain_hex, "smog", 0.25), 0.0)
		assert_almost_eq(_fx.cells.floor_of(plain_hex), 0.0, 0.0001, "a hex that never held smog gets loose waste")
		assert_true(_fx.cells.workable(plain_hex))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(p.save_state()))
	var p2 := Pollution.new()
	_nodes.append(p2)
	p2.setup(_fx.def, _fx.grid, _fx.cells, p._field, _fx.site_cells, saved)
	assert_true(p2.is_soiled(smog_hex), "the fouled hexes survive a save")
	assert_true("smog" in p2.kinds_left(smog_hex))


func test_a_laid_out_hex_gets_its_own_pieces_back() -> void:
	_world(FIRST)
	var p: Pollution = _pollution()
	var field: SphereField = p._field
	var list: PackedInt32Array = _fx.districts.cells_of("old_town")
	var c: int = list[30]
	assert_gt(field.materialize(c).size(), 0, "the hex is laid out with its pieces")
	SphereOffline.write_cell(_fx.cells, field, c, 0.0)  # a robot clears it
	assert_false(_fx.cells.is_dirty(c))
	var cleaned: int = field.cleaned_count
	var made: int = field.pieces_in(c).size()
	var back: float = p.soil(c, "litter", 0.25)
	assert_between(back, 0.2, 0.4, "about a quarter of its waste is back")
	var alive: int = 0
	for pid: int in field.pieces_in(c):
		alive += int(field.piece_alive[pid])
	assert_gt(alive, 0, "as pieces Lumi and the robots can scoop")
	assert_eq(field.pieces_in(c).size(), made, "pieces that were taken from it: none is made up")
	assert_eq(field.hex_clean[c], 0)
	assert_eq(field.cleaned_count, cleaned - 1, "the hex no longer counts as cleaned")
	assert_true(_fx.cells.is_dirty(c))
	assert_almost_eq(_fx.cells.junk[c], back, 0.0001, "the ledger and the globe agree")
	SphereOffline.write_cell(_fx.cells, field, c, 0.0)
	assert_false(_fx.cells.is_dirty(c), "and it is cleaned like any other hex")
	assert_eq(field.cleaned_count, cleaned)
	var bare: int = list[31]
	_fx.set_cell_stage(bare, 1)
	field.settle(bare)  # the ledger learns the hex is clean, as on a load
	field.materialize(bare)
	assert_eq(field.pieces_in(bare).size(), 0, "a hex laid out while clean (after a load) has no pieces")
	cleaned = field.cleaned_count
	assert_between(p.soil(bare, "litter", 0.25), 0.2, 0.4, "its pieces are laid out now")
	assert_gt(field.pieces_in(bare).size(), 0)
	assert_true(_fx.cells.is_dirty(bare))
	assert_eq(field.hex_clean[bare], 0)
	SphereOffline.write_cell(_fx.cells, field, bare, 0.0)
	assert_false(_fx.cells.is_dirty(bare))
	assert_eq(field.cleaned_count, cleaned)


func test_water_hub_ground_and_dirty_hexes_are_never_fouled() -> void:
	_world(FIRST)
	var p: Pollution = _pollution()
	var list: PackedInt32Array = _fx.districts.cells_of("old_town")
	assert_almost_eq(p.soil(list[20], "litter", 0.3), 0.0, 0.0001, "untouched junk")
	_fx.cells.set_flag(list[21], SphereCells.F_HUB)
	_fx.cells.set_junk(list[21], 0.0)
	assert_almost_eq(p.soil(list[21], "litter", 0.3), 0.0, 0.0001, "hub ground")
	assert_almost_eq(p.soil(-1, "litter", 0.3), 0.0, 0.0001)
	_fx.set_cell_stage(list[22], 2)
	assert_almost_eq(p.soil(list[22], "no_such_kind", 0.3), 0.3, 0.0001, "an unknown kind comes back as loose waste")


# --- Any planet ---------------------------------------------------------------------------------

func test_a_planet_without_the_table_holds_and_fouls_nothing(planet_id: StringName = use_parameters([DUMMY, PARKED])) -> void:
	var s: SourceSpread = _world(planet_id)
	var id: String = _fx.districts.ids()[0]
	assert_eq(s.ids(), [] as Array[String])
	_fx.set_district_stage(id, Districts.MAX_STAGE)
	assert_false(s.holds(_fx.districts.cells_of(id)[8]))
	assert_eq(s.hex_cap(_fx.districts.cells_of(id)[8]), Districts.MAX_STAGE)
	assert_eq(s.step(id, 10000.0), -1)
	assert_eq(s.hex_note(_fx.districts.cells_of(id)[8]), "")


func test_a_spread_on_another_planet_is_data_only() -> void:
	var s: SourceSpread = _world(DUMMY, _with_table(SPREAD_TABLE))
	var id: String = _fx.districts.ids()[0]
	var spec: Dictionary = s.spec_of(id)
	assert_eq(s.reach_of(id).size(), 5)
	assert_eq(s.hex_cap(s.reach_of(id)[0]), 2, "this planet's source holds its ground at stage 2")
	_fx.set_district_stage(id, 2)
	assert_eq(s.step(id, 9.0), -1)
	var c: int = s.step(id, 1.0)
	assert_ne(c, -1, "its trickle runs from the start and every ten seconds")
	assert_almost_eq(_fx.cells.junk[c], 0.5, 0.0001)
	assert_ne(s.step(id, float(spec["every_s"])), -1)
	assert_eq(s.step(id, float(spec["every_s"])), -1, "and stops at two fouled hexes")
