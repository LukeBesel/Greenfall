extends GutTest
## Mastery and apprentice robots (design spec section 3; systems/mastery.gd, core/mastery_rules.gd,
## systems/pollution_crew.gd): only Lumi's own work fills a kind's mastery; it speeds her hands;
## robots may not work a kind under level 1 and work it faster level by level and alongside her;
## it is saved with the planet and a save from before it loads with sensible levels. Every number
## is the planet's: the first planet's are the spec's, the dummy planet has its own.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const LEVEL: int = 6
const SEED: int = 4471
const WATER_CELLS: int = 12
const CREW_RINGS: int = 3

var _saved: Dictionary = {}
var _nodes: Array[Node] = []
var _gained: Array[Array] = []
var def: PlanetDefinition
var grid: SphereGrid
var cells: SphereCells
var field: SphereField
var site_cells := PackedInt32Array()
var pol: Pollution
var mastery: Mastery


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = {"currencies": GameState.currencies, "flags": GameState.flags, "upgrades": GameState.upgrades}
	GameState.currencies = {}
	GameState.flags = {}
	GameState.upgrades = {}
	_gained.clear()
	EventBus.mastery_gained.connect(_on_gained)


func after_each() -> void:
	EventBus.mastery_gained.disconnect(_on_gained)
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	pol = null
	mastery = null
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.upgrades = _saved["upgrades"]


func _on_gained(kind: String, level: int) -> void:
	_gained.append([kind, level])


func _mastery(planet_id: StringName, saved: Dictionary = {}) -> Mastery:
	var m := Mastery.new()
	_nodes.append(m)
	m.setup(Planets.by_id(planet_id), saved)
	return m


## A globe of junk with the planet's sites, its pollution kinds and Lumi's mastery of them.
func _world(planet_id: StringName, lakes: String = "") -> void:
	def = Planets.by_id(planet_id)
	grid = SphereGrid.cached(LEVEL)
	grid.radius_m = SphereGrid.radius_for(LEVEL, 10.0)
	cells = SphereCells.new(grid.cell_count())
	cells.junk.fill(1.0)
	site_cells = DistrictFixture.face_centre_cells(grid, def.hub_count)
	if lakes != "":
		var list: PackedInt32Array = _district_cells(lakes)
		for i: int in WATER_CELLS:
			cells.state[list[list.size() - 1 - i]] = PlanetData.State.WATER
	field = SphereField.new(grid, SphereTerrain.new(grid, SEED), cells, SEED)
	field.worth = HexWorth.for_planet(def, grid, site_cells)
	pol = Pollution.new()
	_nodes.append(pol)
	pol.setup(def, grid, cells, field, site_cells, {})
	mastery = _mastery(planet_id)
	pol.set_mastery(mastery)


func _district_cells(id: String) -> PackedInt32Array:
	for spec: Dictionary in Districts.specs_for(def):
		if str(spec["id"]) == id:
			return Districts.region_cells(grid, site_cells[int(spec["site"])], int(spec["rings"]))
	return PackedInt32Array()


## The first hex of a district that holds exactly these kinds.
func _hex_with(district: String, kinds: Array[String]) -> int:
	var want: Array[String] = kinds.duplicate()
	want.sort()
	for c: int in _district_cells(district):
		var here: Array[String] = pol.kinds_left(c)
		here.sort()
		if here == want:
			return c
	return -1


## A crew working for the base of a district, every robot far from Lumi unless `lumi_at_hub`.
func _crew(district: String, lumi_at_hub: bool = false) -> SphereCrew:
	var hub: int = -1
	for spec: Dictionary in Districts.specs_for(def):
		if str(spec["id"]) == district:
			hub = site_cells[int(spec["site"])]
	var surface := SphereSurface.new(grid.radius_m)
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(grid, cells, field, surface, SphereSwarm.new(surface))
	crew.hub_cell = hub
	crew.depot_cell = hub
	crew.rings = CREW_RINGS
	crew.pollution = pol
	crew.max_near = 0  # records only: the rate is the rule under test, not the driving
	if lumi_at_hub:
		var lumi := Node3D.new()
		add_child_autofree(lumi)
		lumi.global_position = surface.ground(grid.centers[hub])
		crew.focus = lumi
	return crew


# --- The rules are the planet's numbers ---------------------------------------------------------

func test_levels_follow_the_planets_curve(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var m: Mastery = _mastery(planet_id)
	var cfg: Dictionary = m.config()
	assert_true(m.enabled(), "%s has mastery" % planet_id)
	assert_gt(m.kinds().size(), 1)
	for id: String in m.kinds():
		var l1: float = float(cfg["kinds"][id]["level1"])
		assert_gt(l1, 0.0, "%s names its first level" % id)
		assert_eq(MasteryRules.level_for(cfg, id, l1 * 0.99), 0)
		assert_eq(MasteryRules.level_for(cfg, id, l1), 1)
		for level: int in range(2, m.max_level() + 1):
			var need: float = MasteryRules.units_for(cfg, id, level)
			assert_almost_eq(need, l1 * pow(float(cfg["growth"]), level - 1.0), need * 0.0001, "level %d of %s" % [level, id])
			assert_eq(MasteryRules.level_for(cfg, id, need), level)
			assert_eq(MasteryRules.level_for(cfg, id, need * 0.999), level - 1)
		assert_eq(MasteryRules.level_for(cfg, id, 1.0e12), m.max_level(), "the top level is the cap")


func test_the_first_planet_has_the_specs_numbers() -> void:
	var m: Mastery = _mastery(FIRST)
	var cfg: Dictionary = m.config()
	assert_eq(m.max_level(), 10)
	assert_eq(m.kinds(), ["litter", "wrecks", "slick", "smog", "blight"] as Array[String])
	assert_almost_eq(MasteryRules.hand_bonus(cfg, 0), 1.0, 0.0001)
	assert_almost_eq(MasteryRules.hand_bonus(cfg, 5), 1.4, 0.0001, "1 + 0.08 x level")
	assert_almost_eq(MasteryRules.hand_bonus(cfg, 10), 1.8, 0.0001)
	assert_eq(MasteryRules.robot_factor(cfg, "litter", 0), 0.0, "no robot works a kind under level 1")
	assert_almost_eq(MasteryRules.robot_factor(cfg, "litter", 1), 0.52, 0.0001, "0.4 + 0.12 x level")
	assert_almost_eq(MasteryRules.robot_factor(cfg, "litter", 5), 1.0, 0.0001)
	assert_almost_eq(MasteryRules.robot_factor(cfg, "litter", 10), 1.6, 0.0001)
	assert_almost_eq(MasteryRules.near_factor(cfg, 79.0), 1.25, 0.0001, "+25% within 80 m of Lumi")
	assert_almost_eq(MasteryRules.near_factor(cfg, 81.0), 1.0, 0.0001)


func test_the_first_level_is_about_two_minutes_and_the_fifth_about_twenty() -> void:
	var m: Mastery = _mastery(FIRST)
	var cfg: Dictionary = m.config()
	for id: String in m.kinds():
		var ratio: float = MasteryRules.units_for(cfg, id, 5) / MasteryRules.units_for(cfg, id, 1)
		assert_between(ratio, 8.0, 12.0, "%s: level 5 takes about ten times the work of level 1" % id)
	# Litter against the first city's hexes: a hex of 108 to 144 units takes Lumi 60 to 100 s.
	var work: float = float(Planets.by_id(FIRST).table("districts")["districts"][0]["hex_work"])
	assert_between(MasteryRules.units_for(cfg, "litter", 1) / work, 1.0, 2.5, "level 1 within the first two or three hexes")
	assert_between(MasteryRules.units_for(cfg, "litter", 5) / work, 10.0, 25.0, "level 5 within the first 10 to 25 hexes")


func test_the_dummy_planet_has_its_own_numbers_and_no_code() -> void:
	var m: Mastery = _mastery(DUMMY)
	assert_eq(m.max_level(), 4)
	assert_eq(m.kinds(), ["dross", "spores"] as Array[String])
	m.add_work("dross", 50.0)
	assert_eq(m.level("dross"), 1)
	assert_almost_eq(m.hand_bonus("dross"), 1.1, 0.0001)
	assert_almost_eq(m.robot_factor("dross"), 0.75, 0.0001)
	m.add_work("spores", 15.0)
	assert_eq(m.level("spores"), 1, "a unit of spores is worth two")
	assert_almost_eq(m.near_factor(30.0), 1.5, 0.0001)
	assert_almost_eq(m.near_factor(50.0), 1.0, 0.0001)


func test_a_planet_without_mastery_leaves_robots_free() -> void:
	var bare: PlanetDefinition = Planets.by_id(&"ochre").duplicate()
	bare.tables = Planets.by_id(&"ochre").tables.duplicate()
	bare.tables.erase(Pollution.TABLE)
	var m := Mastery.new()
	_nodes.append(m)
	m.setup(bare)
	assert_false(m.enabled())
	assert_true(m.robots_can_work("anything"))
	assert_eq(m.robot_factor("anything"), 1.0)
	assert_eq(m.hand_bonus("anything"), 1.0)
	assert_eq(m.near_factor(1.0), 1.0)
	m.add_work("anything", 1.0e6)
	assert_eq(_gained.size(), 0)


# --- Only Lumi's own work fills it ---------------------------------------------------------------

func test_only_lumis_own_work_fills_mastery(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var m: Mastery = _mastery(planet_id)
	var id: String = m.kinds()[0]
	var need: float = MasteryRules.units_for(m.config(), id, 1)
	EventBus.pollution_cleared.emit(id, need * 5.0, false)
	assert_eq(m.units(id), 0.0, "robot work teaches nothing")
	assert_eq(m.level(id), 0)
	EventBus.pollution_cleared.emit(id, need * 0.5, true)
	assert_eq(m.level(id), 0)
	assert_almost_eq(m.progress(id), 0.5, 0.001, "half way to the first level")
	EventBus.pollution_cleared.emit(id, need * 0.5, true)
	assert_eq(m.level(id), 1)
	assert_eq(_gained, [[id, 1]])
	assert_eq(m.level(m.kinds()[1]), 0, "each kind has its own level")


func test_each_level_is_announced_once() -> void:
	var m: Mastery = _mastery(FIRST)
	m.add_work("litter", MasteryRules.units_for(m.config(), "litter", 3))
	assert_eq(_gained, [["litter", 1], ["litter", 2], ["litter", 3]], "a big take that crosses levels names each")
	m.add_work("litter", 1.0)
	assert_eq(_gained.size(), 3)
	m.add_work("litter", 1.0e9)
	assert_eq(m.level("litter"), 10)
	assert_eq(_gained.size(), 10, "and nothing past the top level")
	assert_eq(m.progress("litter"), 1.0)


func test_lumis_hands_get_faster_on_the_kind_she_masters() -> void:
	_world(FIRST)
	GameState.flags["seeds_unlocked"] = true
	var c: int = _hex_with("highreach", ["litter", "smog"])
	var plain: float = float(pol.hand_work("water", c, 1.0, 1000.0)["vol"])
	mastery.grant("smog", 5)
	var skilled: float = float(pol.hand_work("water", c, 1.0, 1000.0)["vol"])
	assert_almost_eq(skilled / plain, 1.4, 0.001, "misting at smog level 5")
	field.materialize(c)
	var pid: int = field.pieces_in(c)[0]
	assert_eq(pol.piece_hand_bonus(pid), 1.0, "litter is still at level 0")
	mastery.grant("litter", 2)
	assert_almost_eq(pol.piece_hand_bonus(pid), 1.16, 0.0001, "the scoop pulses 16% sooner on litter at level 2")


# --- Robots are apprentices ----------------------------------------------------------------------

func test_robots_cannot_scoop_a_kind_lumi_has_not_learnt() -> void:
	_world(FIRST)
	var litter_hex: int = _hex_with("scrapyard", ["litter"])
	var wreck_hex: int = _hex_with("scrapyard", ["litter", "wrecks"])
	var in_city: Dictionary = {}
	for list: PackedInt32Array in pol.zone_lists():
		for c: int in list:
			in_city[c] = true
	var open_ground: int = 0
	while in_city.has(open_ground):
		open_ground += 1
	for c: int in [litter_hex, wreck_hex, open_ground]:
		assert_true(cells.is_shut(c), "nothing is learnt: hex %d is Lumi's" % c)
		assert_false(cells.workable(c))
	var region := PackedInt32Array([litter_hex, wreck_hex])
	assert_eq(SphereOffline.units_left(cells, region), 0.0, "time away cleans nothing either")
	assert_eq(float(SphereOffline.take_units(cells, field, region, 1000.0)["units"]), 0.0)
	mastery.grant("litter", 1)
	assert_true(cells.workable(litter_hex), "litter learnt: a litter hex is the crew's")
	assert_true(cells.workable(open_ground))
	assert_false(cells.workable(wreck_hex), "a hex with wrecks on it stays Lumi's")
	assert_true(cells.is_dirty(wreck_hex))
	SphereOffline.take_units(cells, field, region, 1.0e6)
	assert_false(cells.is_dirty(litter_hex))
	assert_eq(cells.junk[wreck_hex], 1.0, "untouched")
	mastery.grant("wrecks", 1)
	assert_true(cells.workable(wreck_hex), "wrecks learnt")
	assert_false(cells.shut.is_empty(), "slick is still Lumi's")
	mastery.grant("slick", 1)
	assert_true(cells.shut.is_empty(), "no hex is shut once every scooped kind is learnt")


func test_a_hex_opens_when_lumi_clears_the_unlearnt_kind_from_it() -> void:
	_world(FIRST)
	mastery.grant("litter", 1)
	GameState.upgrades["lift_strength"] = 2
	var c: int = _hex_with("scrapyard", ["litter", "wrecks"])
	assert_true(cells.is_shut(c))
	field.materialize(c)
	for pid: int in field.pieces_in(c):
		if pol.kind(pol.ids()[field.piece_kind[pid]])["id"] == "wrecks":
			pol.piece_taken(pid, field.piece_vol[pid])
			field.remove_piece(pid)
	cells.set_junk(c, 1.0 - field.removed_fraction(c))
	pol._process(Pollution.POLL_S + 0.1)
	assert_eq(pol.kinds_left(c), ["litter"] as Array[String])
	assert_false(cells.is_shut(c), "the litter she left is the crew's")
	assert_true(cells.workable(c))
	assert_eq(mastery.level("wrecks"), 0, "one hex of wrecks is not a level")
	assert_gt(mastery.units("wrecks"), 0.0)


func test_skimmers_wait_for_slick_and_tool_robots_for_their_kind() -> void:
	_world(FIRST, "kettle_bay")
	mastery.grant("litter", 1)
	var lake: int = _hex_with("kettle_bay", ["slick"])
	var crew: SphereCrew = _crew("kettle_bay")
	assert_true(crew.water_dirty(lake))
	assert_false(crew.wants("skim", lake), "slick is not learnt")
	mastery.grant("slick", 1)
	assert_true(crew.wants("skim", lake))
	var smog_hex: int = _hex_with("highreach", ["litter", "smog"])
	assert_false(pol.robot_wants("water", smog_hex), "smog is not learnt")
	assert_false(pol.robot_work("water", smog_hex, false))
	assert_eq(pol.held_left(smog_hex, "smog"), 1.0, "a robot action takes nothing")
	assert_true(cells.workable(smog_hex), "the litter on it is still a cleaner's")
	mastery.grant("smog", 1)
	assert_true(pol.robot_wants("water", smog_hex))
	pol.robot_work("water", smog_hex, false)
	assert_lt(pol.held_left(smog_hex, "smog"), 1.0)


func test_a_waiting_robot_says_which_kind_lumi_must_learn() -> void:
	_world(FIRST)
	var crew: SphereCrew = _crew("scrapyard")
	var u: Dictionary = crew.spawn("scoopie", 0, crew.hub_cell)
	crew.run_far(5.0, 1.0)
	assert_eq(str(u["mode"]), "idle")
	assert_eq(crew.waiting_on_kind("clean", crew.hub_cell), "litter")
	assert_eq(crew.status_text(u), "idle: Lumi must learn litter first")
	assert_eq(float(u["log"]["junk"]), 0.0)
	mastery.grant("litter", 1)
	crew.run_far(600.0, 1.0)
	assert_gt(float(u["log"]["junk"]), 0.0, "litter learnt: it works")
	mastery.grant("litter", 5)
	crew.run_far(6.0 * 3600.0, 2.0)
	assert_eq(crew.waiting_on_kind("clean", crew.hub_cell), "wrecks", "the litter hexes are done: the rest hold wrecks")
	assert_eq(crew.status_text(u), "idle: Lumi must learn wrecks first")
	for c: int in grid.cells_around(crew.hub_cell, CREW_RINGS):
		assert_true(not cells.is_dirty(c) or "wrecks" in pol.kinds_left(c), "only hexes with wrecks are left")
	assert_eq(mastery.block_text("clean"), "", "wrecks are not met in the first city: the bench does not mention them")
	EventBus.district_entered.emit("scrapyard")
	assert_eq(mastery.block_text("clean"), "Lumi must learn wrecks first")
	assert_eq(mastery.role_line("clean"), "Litter 5  ·  Wrecks 0")
	mastery.grant("wrecks", 1)
	assert_eq(mastery.block_text("clean"), "")


func test_a_robots_rate_follows_the_level(planet_id: StringName = use_parameters(PLANETS)) -> void:
	_world(planet_id)
	var base: String = pol.base_id()
	var district: String = str(Districts.specs_for(def)[0]["id"])
	var cfg: Dictionary = mastery.config()
	var got: Array[float] = []
	for level: int in [1, mastery.max_level()]:
		mastery.grant(base, level)
		var crew: SphereCrew = _crew(district)
		var u: Dictionary = crew.spawn("scoopie", 0, crew.hub_cell)
		var hex: int = _hex_with(district, [base])
		assert_almost_eq(crew.mastery_rate(u, hex), MasteryRules.robot_factor(cfg, base, level), 0.0001)
		crew.run_far(1200.0, 1.0)
		var expect: float = Offline.unit_rate("scoopie", 0) * 1200.0 * MasteryRules.robot_factor(cfg, base, level)
		assert_between(float(u["log"]["junk"]), expect * 0.8, expect * 1.001, "%s level %d" % [base, level])
		got.append(float(u["log"]["junk"]))
	assert_gt(got[1], got[0] * 1.5, "a crew is weak at level 1 and strong at the top")


func test_a_robot_working_alongside_lumi_is_faster() -> void:
	_world(FIRST)
	mastery.grant("litter", 5)
	var crew: SphereCrew = _crew("old_town", true)
	var u: Dictionary = crew.spawn("scoopie", 0, crew.hub_cell)
	var hex: int = grid.neighbors(crew.hub_cell)[0]
	assert_almost_eq(crew.mastery_rate(u, hex), 1.25, 0.0001, "within 80 m of Lumi")
	(crew.focus as Node3D).global_position = crew.surface.ground(grid.centers[_district_cells("old_town")[-1]])
	assert_gt(crew.surface.up_at(crew.focus.global_position).angle_to(crew.unit_dir(u)) * crew.surface.radius, 80.0)
	assert_almost_eq(crew.mastery_rate(u, hex), 1.0, 0.0001, "far crews still work, at their own rate")
	crew.focus = null
	assert_almost_eq(crew.mastery_rate(u, hex), 1.0, 0.0001)


func test_a_hex_of_two_kinds_is_worked_at_their_shared_rate() -> void:
	_world(FIRST)
	mastery.grant("litter", 5)
	mastery.grant("wrecks", 1)
	var c: int = _hex_with("scrapyard", ["litter", "wrecks"])
	var share: float = pol.share_of(c, "wrecks")
	assert_almost_eq(pol.crew_speed(c), (1.0 - share) * 1.0 + share * 0.52, 0.0001)
	var smog_hex: int = _hex_with("highreach", ["litter", "smog"])
	assert_almost_eq(pol.crew_speed(smog_hex), 1.0, 0.0001, "smog is not scooped: the cleaner's rate there is litter's")
	mastery.grant("smog", 3)
	assert_almost_eq(pol.crew_speed_held("water", smog_hex), 0.76, 0.0001, "the watering robot's is smog's")


func test_time_away_is_worked_at_the_mastery_rate() -> void:
	_world(FIRST)
	mastery.grant("litter", 1)
	var hub: int = site_cells[0]
	var fleet: Array = [{"type": "scoopie", "tier": 0}]
	var full: Dictionary = SphereOffline.simulate(grid, cells, null, [{"cell": hub, "robots": fleet, "rings": 3}], 3600.0)
	cells.junk.fill(1.0)
	cells.state.fill(0)
	var slow: Dictionary = SphereOffline.simulate(grid, cells, null, [{"cell": hub, "robots": fleet, "rings": 3, "rate": pol.crew_speed_base()}], 3600.0)
	assert_gt(float(full["units"]), 0.0)
	assert_almost_eq(float(slow["units"]) / float(full["units"]), 0.52, 0.001)


# --- Saving --------------------------------------------------------------------------------------

func test_mastery_round_trips(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var m: Mastery = _mastery(planet_id)
	var ids: Array[String] = m.kinds()
	m.add_work(ids[0], MasteryRules.units_for(m.config(), ids[0], 2) + 7.0)
	m.add_work(ids[1], 3.0)
	var text: String = JSON.stringify(m.save_state())
	_gained.clear()
	var again: Mastery = _mastery(planet_id, JSON.parse_string(text))
	assert_eq(again.level(ids[0]), 2)
	assert_almost_eq(again.units(ids[0]), m.units(ids[0]), 0.001)
	assert_almost_eq(again.units(ids[1]), m.units(ids[1]), 0.001)
	assert_almost_eq(again.progress(ids[0]), m.progress(ids[0]), 0.001)
	assert_eq(_gained.size(), 0, "loading announces nothing")
	assert_eq(_mastery(planet_id, {"units": {"not_a_kind": 5.0}}).units(ids[0]), 0.0, "an unknown kind in a save is ignored")


func test_a_save_from_before_mastery_is_credited_with_its_clean_hexes() -> void:
	_world(FIRST)
	var town: PackedInt32Array = _district_cells("old_town")
	for i: int in 40:
		cells.set_junk(town[i], 0.0)
		cells.set_state(town[i], PlanetData.State.CLEAN)
	var cleaned: Dictionary = pol.cleaned_units()
	assert_between(float(cleaned["litter"]), 39.0 * 108.0, 40.0 * 144.0, "40 clean hexes of the first city")
	assert_false(cleaned.has("wrecks"))
	var old: Mastery = _mastery(FIRST)
	old.seed_legacy(cleaned, ["clean", "haul"])
	var credit: float = float(cleaned["litter"]) * float(old.config()["legacy_credit"])
	assert_almost_eq(old.units("litter"), credit, 0.01, "half of it counts as her own work")
	assert_eq(old.level("litter"), MasteryRules.level_for(old.config(), "litter", credit))
	assert_between(old.level("litter"), 4, 6)
	assert_eq(old.level("wrecks"), 1, "its cleaners keep working what cleaners work")
	assert_eq(old.level("slick"), 0, "it has no skimmer")
	assert_eq(_gained.size(), 0, "loading an old save announces nothing")
	var fresh: Mastery = _mastery(FIRST)
	fresh.seed_legacy({}, [])
	for id: String in fresh.kinds():
		assert_eq(fresh.level(id), 0, "a new game starts with nothing learnt")
	assert_eq(SphereCrew.saved_roles({"robots": [{"type": "scoopie"}, {"type": "scoopie"}, {"type": "haulbug"}]}), ["clean", "haul"])
