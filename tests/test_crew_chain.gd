extends GutTest
## Task M3-20: crew pacing and the robot chain. The crew cap and every robot price come from the
## planet's robots table (core/crew_rules.gd); Scroungers dig buried parts out of cleaned ground
## and bring them home (robots/sphere/sphere_scrounge.gd); the Assembler builds robots from Parts
## in the player's mix (core/crew_chain.gd, systems/crew/robot_chain.gd); the crew simulator
## (tools/crew_sim) plays the whole planet on the same rules. Tests that can run on any planet take
## the planet id: the first planet (it has the chain) and the dummy planet (it has none).

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
## The accepted crew after each city (docs/design/PLANET1_DESIGN.md section 17) and how far the
## simulator may stand from it.
const ACCEPTED_CREW: Array[int] = [8, 50, 72, 94, 119, 147]
const CREW_TOLERANCE: float = 0.15
const LAUNCH_CREW_MIN: int = 100
const LAUNCH_CREW_MAX: int = 200
## The dearest Parts price on the first planet: the rocket's last part.
const LARGEST_PARTS_PRICE: float = 600.0
## The cadence rules for the crew, in player seconds (design spec section 14).
const FASTEST_DOUBLING_S: float = 180.0
const LONGEST_WAIT_S: float = 360.0
const HUB: int = 100
const HEX_SPACING_M: float = 17.35

var _fx: DistrictFixture
var _g5: SphereGrid
var _t5: SphereTerrain


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)
	_g5 = SphereGrid.new()
	_g5.generate(5)
	_g5.radius_m = SphereGrid.radius_for(5, 10.0)
	_t5 = SphereTerrain.new(_g5, 7)


func after_all() -> void:
	Planets.set_current(FIRST)
	Planets.unregister(DUMMY)


func before_each() -> void:
	Planets.set_current(FIRST)
	GameState.new_game()


func after_each() -> void:
	if _fx:
		_fx.free_systems()
	_fx = null


# --- Helpers --------------------------------------------------------------------------------------

func _cfg() -> Dictionary:
	return {"crew_cap": {"by_base_level": [4, 8, 56], "by_cities_open": [8, 56, 90]},
		"price": {"parts_growth": 1.0, "cubes_growth": 1.0, "tier_per_robot": 0.9, "tier_max_parts": 100, "tier_cities_open": 2},
		"tiers": [{"name": "A", "mult": 1.0, "build_mult": 1.0}, {"name": "B", "mult": 1.6, "build_mult": 1.5}]}


func _chain(extra: Dictionary = {}) -> CrewChain:
	var c := CrewChain.new()
	var cfg: Dictionary = {"finder": "f", "ground": {"rich": 2.0, "bare": 0.0}, "open_ground": 1.0, "arrival_parts": {"rich": 130.0},
		"assembler": {"cost": {"parts": 45}, "assembly_s": 10.0, "max_weight": 9, "reserve_parts": 0, "default_mix": {"a": 3, "b": 2, "c": 1}}}
	cfg.merge(extra, true)
	c.configure(cfg)
	return c


## A clean round planet with a crew of far records on it (no Lumi: every robot is a record).
func _crew_world() -> SphereCrew:
	var cells := SphereCells.new(_g5.cell_count())
	cells.junk.fill(0.0)
	cells.state.fill(1)
	cells.refresh_all()
	var surface := SphereSurface.new(_g5.radius_m)
	surface.height_fn = _t5.height
	surface.cell_fn = func(p: Vector3, _h: int) -> int: return _g5.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return _g5.centers[c]
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(_g5, cells, null, surface, SphereSwarm.new(surface))
	crew.hub_cell = HUB
	crew.depot_cell = HUB
	return crew


## The chain in a world of districts: {fx, crew, fleet, rc}.
func _chain_world(planet_id: StringName) -> Dictionary:
	Planets.set_current(planet_id)
	GameState.new_game()
	_fx = DistrictFixture.new(planet_id)
	add_child_autofree(_fx.districts)
	add_child_autofree(_fx.restoration)
	_fx.grid.radius_m = SphereGrid.radius_for(DistrictFixture.LEVEL, HEX_SPACING_M)  # the fixture's globe has no size of its own
	var surface := SphereSurface.new(_fx.grid.radius_m)
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(_fx.grid, _fx.cells, null, surface, null, null, String(planet_id))
	crew.hub_cell = _fx.site_cells[0]
	crew.depot_cell = _fx.site_cells[0]
	var fleet := SphereFleet.new()
	fleet.crew = crew
	add_child_autofree(fleet)
	var rc := RobotChain.new()
	add_child_autofree(rc)
	rc.set_physics_process(false)
	rc.setup(null, crew, fleet, _fx.districts, _fx.cells, _fx.site_cells)
	rc.load_state({})
	return {"fx": _fx, "crew": crew, "fleet": fleet, "rc": rc}


func _set_parts(n: float) -> void:
	GameState.currencies["parts"] = BigNum.from_float(n)


func _parts() -> float:
	return GameState.get_currency("parts").to_float()


func _run_line(rc: RobotChain, seconds: float) -> void:
	var steps: int = ceili(seconds / RobotChain.LINE_STEP_S)
	for i: int in steps:
		rc._physics_process(RobotChain.LINE_STEP_S)


# --- Crew cap and prices: the planet's table, not code ------------------------------------------------

func test_crew_cap_is_the_smaller_of_base_level_and_cities_open() -> void:
	var cfg: Dictionary = _cfg()
	assert_eq(CrewRules.cap(cfg, 1, 1), 4, "a level 1 base holds 4")
	assert_eq(CrewRules.cap(cfg, 2, 1), 8)
	assert_eq(CrewRules.cap(cfg, 3, 1), 8, "the first city holds 8 whatever the base level")
	assert_eq(CrewRules.cap(cfg, 3, 2), 56)
	assert_eq(CrewRules.cap(cfg, 2, 3), 8, "a small base holds the crew back in a later city")
	assert_eq(CrewRules.cap(cfg, 9, 9), 56, "past the end of both lists: their last entries")
	assert_eq(CrewRules.cap_gain_at_level(cfg, 1, 1), 4)
	assert_eq(CrewRules.cap_gain_at_level(cfg, 2, 1), 0, "the next city, not the base, is what is missing")


func test_a_table_without_the_new_cap_keeps_the_old_rule() -> void:
	assert_eq(CrewRules.cap({"crew_cap": {"base": 1, "per_level": 2}}, 3, 1), 7)
	assert_eq(CrewRules.cap({}, 2, 4), CrewRules.LEGACY_BASE + 2 * CrewRules.LEGACY_PER_LEVEL)


func test_the_first_planet_holds_the_accepted_crew_per_city() -> void:
	var cfg: Dictionary = Economy.robot_cfg
	var by_cities: Array = (cfg["crew_cap"] as Dictionary)["by_cities_open"]
	assert_eq(by_cities.size(), 6, "one cap per city")
	for i: int in ACCEPTED_CREW.size():
		assert_gte(int(by_cities[i]), ACCEPTED_CREW[i], "city %d's cap has room for the accepted crew" % (i + 1))
	assert_eq(CrewRules.cap(cfg, 1, 1), 4, "a handful at the start")
	assert_eq(CrewRules.cap(cfg, 2, 1), 8, "eight in the first city")
	assert_eq(CrewRules.cap(cfg, 99, 99), LAUNCH_CREW_MAX, "never more than 200 before the launch point")
	assert_gt(CrewRules.cap(cfg, 99, 99), 12, "the owner: definitely more than 12")


func test_a_robot_price_does_not_compound() -> void:
	var cfg: Dictionary = _cfg()
	var type_def: Dictionary = {"parts": 10, "cost": 0, "tier_parts": [30]}
	assert_eq(CrewRules.build_parts(cfg, type_def, 0, 0), 10.0)
	assert_eq(CrewRules.build_parts(cfg, type_def, 150, 0), 10.0, "the 151st costs what the first did")
	assert_eq(CrewRules.build_parts(cfg, type_def, 0, 1), 15.0, "a robot of a repaired type costs the tier's build multiplier more")
	cfg["price"]["parts_growth"] = 1.2
	assert_eq(CrewRules.build_parts(cfg, type_def, 2, 0), ceilf(10.0 * 1.2 * 1.2), "growth comes from the table")


func test_the_fleet_reads_prices_from_the_table(planet_id: StringName = use_parameters(PLANETS)) -> void:
	Planets.set_current(planet_id)
	GameState.new_game()
	var f := Fleet.new()
	add_child_autofree(f)
	for id: String in Economy.robot_order:
		var def: Dictionary = Economy.robots[id]
		assert_eq(f.build_parts(id).to_float(), CrewRules.build_parts(Economy.robot_cfg, def, 0, 0), "%s: the table's price" % id)
		assert_eq(f.build_cost(id).to_float(), CrewRules.build_cubes(Economy.robot_cfg, def, 0), "%s: robots cost Parts" % id)
	assert_eq(f.crew_cap(), CrewRules.cap(Economy.robot_cfg, 1, 1))


func test_a_tier_step_costs_its_price_plus_a_share_per_robot_up_to_the_cap() -> void:
	var cfg: Dictionary = _cfg()
	var type_def: Dictionary = {"parts": 10, "tier_parts": [30]}
	assert_eq(CrewRules.tier_parts(cfg, type_def, 0, 0), 30.0)
	assert_eq(CrewRules.tier_parts(cfg, type_def, 0, 5), 75.0, "30 + 0.9 x 10 x 5")
	assert_eq(CrewRules.tier_parts(cfg, type_def, 0, 50), 100.0, "never more than the table's largest tier price")
	assert_eq(CrewRules.tier_parts(cfg, type_def, 1, 5), -1.0, "no tier after the last")
	assert_false(CrewRules.tiers_open(cfg, 1), "tier steps wait for the second city")
	assert_true(CrewRules.tiers_open(cfg, 2))


func test_no_crew_price_passes_the_largest_parts_price() -> void:
	for owned: int in [0, 1, 30, 200]:
		assert_lte(CrewRules.dearest_parts(Economy.robot_cfg, owned), LARGEST_PARTS_PRICE, "with %d robots of every type" % owned)
	assert_eq(CrewRules.tier_count(Economy.robot_cfg), 2, "two tiers on the first planet: rusty and repaired")


func test_crew_upgrades_cost_parts_not_cubes() -> void:
	var seen: int = 0
	for id: String in Economy.upgrade_order:
		if str(Economy.upgrade_defs[id].get("robot", "")) == "":
			assert_eq(Economy.upgrade_currency(id), "cubes", "%s: Lumi's own upgrades cost cubes" % id)
			continue
		seen += 1
		assert_eq(Economy.upgrade_currency(id), "parts", "%s: one job per currency" % id)
	assert_gt(seen, 5)
	var id: String = "bot_scoopie_speed"
	var cost: float = Economy.upgrade_cost(id).to_float()
	GameState.currencies["cubes"] = BigNum.from_float(100000.0)
	_set_parts(0.0)
	assert_eq(Economy.buy_upgrade(id, 1), 0, "cubes do not buy a crew upgrade")
	_set_parts(cost)
	assert_eq(Economy.buy_upgrade(id, 1), 1)
	assert_almost_eq(_parts(), 0.0, 0.001)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 100000.0, 0.001, "and no cubes were taken")


func test_a_full_crew_blocks_building_and_says_what_to_do() -> void:
	var f := Fleet.new()
	add_child_autofree(f)
	Research.unlock_story("haul_rig")
	_set_parts(1000.0)
	GameState.world["hub_level"] = 1
	var cap: int = f.crew_cap()
	for i: int in cap:
		assert_not_null(f.build("haulbug", Vector3.ZERO), "robot %d of %d fits" % [i + 1, cap])
	assert_false(f.has_room())
	assert_null(f.build("haulbug", Vector3.ZERO), "the crew is full, whatever the robot's job")
	assert_string_contains(f.build_block_reason("haulbug"), "raise the base level")
	GameState.world["hub_level"] = 2
	assert_true(f.has_room(), "a base level makes room")
	GameState.world["hub_level"] = 5
	GameState.flags[Economy.FLAG_TIERS_OPEN] = 1
	assert_eq(f.crew_cap(), 8, "the first city holds 8 however large the base")
	GameState.flags[Economy.FLAG_TIERS_OPEN] = 6
	assert_eq(f.crew_cap(), LAUNCH_CREW_MAX)


func test_tier_steps_open_with_the_second_city() -> void:
	var f := Fleet.new()
	add_child_autofree(f)
	_set_parts(1000.0)
	var req: Dictionary = f.tier_requirements("scoopie")
	assert_false(bool(req["ok"]), "not in the first city")
	assert_true(bool(req.get("locked", false)))
	assert_false(f.upgrade_tier("scoopie"))
	GameState.flags[Economy.FLAG_TIERS_OPEN] = 2
	req = f.tier_requirements("scoopie")
	assert_true(bool(req["ok"]))
	assert_eq((req["parts"] as BigNum).to_float(), CrewRules.tier_parts(Economy.robot_cfg, Economy.robots["scoopie"], 0, 0))
	assert_eq((req["cost"] as BigNum).to_float(), 0.0, "no cubes")
	assert_true(f.upgrade_tier("scoopie"))
	assert_eq(f.tier_of("scoopie"), 1)
	assert_true(bool(f.tier_requirements("scoopie").get("maxed", false)), "repaired is the last tier here")


# --- The ground: growth is tied to newly cleaned ground --------------------------------------------------

func test_a_hex_leaves_its_buried_parts_once() -> void:
	var c: CrewChain = _chain()
	assert_eq(c.seed_cell(7, "rich"), 2.0)
	assert_eq(c.seed_cell(7, "rich"), 0.0, "cleaning it again gives nothing")
	assert_eq(c.seed_cell(8, "bare"), 0.0, "a city with no buried parts")
	assert_eq(c.seed_cell(9, ""), 1.0, "open ground")
	assert_eq(c.seed_cell(10, "unknown_city"), 1.0, "a city the table does not name counts as open ground")
	assert_false(c.has_stock(8))
	assert_almost_eq(c.stock_total(), 4.0, 0.0001)


func test_parts_dug_never_exceed_parts_seeded() -> void:
	var c: CrewChain = _chain()
	c.seed_cell(1, "rich")
	c.seed_cell(2, "rich")
	var got: float = 0.0
	for i: int in 50:
		got += c.take(1, 0.3) + c.take(2, 5.0) + c.take(3, 5.0)
	assert_almost_eq(got, 4.0, 0.0001, "everything the ground held, and no more")
	assert_almost_eq(c.stock_total(), 0.0, 0.0001)
	assert_false(c.has_stock(1))
	assert_eq(c.seed_cell(1, "rich"), 0.0, "an emptied hex is not seeded again")


func test_delivered_parts_are_paid_whole_and_nothing_is_lost() -> void:
	var c: CrewChain = _chain()
	var paid: float = 0.0
	for i: int in 10:
		var whole: float = c.deliver(1.8)
		assert_eq(whole, floorf(whole), "whole Parts only")
		paid += whole
	assert_eq(paid, 18.0)
	assert_almost_eq(c.delivered_parts, 18.0, 0.0001)


func test_arrival_salvage_is_paid_once() -> void:
	var c: CrewChain = _chain()
	assert_eq(c.claim_arrival("bare"), 0.0)
	assert_eq(c.claim_arrival("rich"), 130.0)
	assert_eq(c.claim_arrival("rich"), 0.0)


func test_the_first_city_has_no_buried_parts_and_later_cities_do() -> void:
	var c := CrewChain.new()
	c.configure(Economy.robot_cfg.get("chain", {}))
	var ids: Array[String] = []
	for spec: Dictionary in Districts.specs_for(Planets.by_id(FIRST)):
		ids.append(str(spec["id"]))
	assert_eq(c.parts_per_hex(ids[0]), 0.0, "in the first city Parts come only from Lumi's own hands")
	for i: int in range(1, ids.size()):
		assert_gt(c.parts_per_hex(ids[i]), 0.0, "%s leaves buried parts" % ids[i])
	assert_eq(str((c.assembler_cfg()["unlock"] as Dictionary)["district"]), ids[2], "the Assembler comes with the third city")


# --- The Assembler's line ------------------------------------------------------------------------------

func test_the_line_builds_one_robot_at_a_time_and_pays_up_front() -> void:
	var c: CrewChain = _chain()
	var allowed: Array[String] = ["a", "b", "c"]
	var price: Callable = func(_t: String) -> float: return 20.0
	var out: Dictionary = c.tick_line(1.0, 100.0, true, allowed, price)
	assert_eq(c.status, CrewChain.OFF, "nothing happens before it is built")
	c.built = true
	out = c.tick_line(1.0, 100.0, true, allowed, price)
	assert_eq(float(out["spend"]), 20.0, "paid when the robot goes on the line")
	assert_eq(str(out["built"]), "")
	assert_eq(c.status, CrewChain.BUILDING)
	var spent: float = 0.0
	var built: Array[String] = []
	for i: int in 8:
		out = c.tick_line(1.0, 80.0, true, allowed, price)
		spent += float(out["spend"])
		if str(out["built"]) != "":
			built.append(str(out["built"]))
	assert_eq(built.size(), 0, "9 of its 10 seconds: not done yet")
	assert_eq(spent, 0.0, "and nothing more was charged meanwhile")
	out = c.tick_line(1.0, 80.0, true, allowed, price)
	assert_eq(str(out["built"]), "a", "done after assembly_s")
	assert_eq(c.current, "")


func test_the_line_waits_for_parts_room_and_the_player() -> void:
	var c: CrewChain = _chain({"assembler": {"assembly_s": 4.0, "max_weight": 9, "reserve_parts": 10, "default_mix": {"a": 1}}})
	c.built = true
	var allowed: Array[String] = ["a"]
	var price: Callable = func(_t: String) -> float: return 20.0
	assert_eq(float(c.tick_line(1.0, 29.0, true, allowed, price)["spend"]), 0.0)
	assert_eq(c.status, CrewChain.NEED_PARTS, "the reserve stays in the wallet")
	c.tick_line(1.0, 30.0, false, allowed, price)
	assert_eq(c.status, CrewChain.CREW_FULL, "no room: nothing goes on the line")
	c.paused = true
	c.tick_line(1.0, 500.0, true, allowed, price)
	assert_eq(c.status, CrewChain.PAUSED)
	c.paused = false
	assert_eq(float(c.tick_line(1.0, 30.0, true, allowed, price)["spend"]), 20.0)
	for i: int in 6:
		assert_eq(str(c.tick_line(1.0, 10.0, false, allowed, price)["built"]), "", "finished, but the crew is full: it waits in the door")
	assert_eq(c.status, CrewChain.CREW_FULL)
	assert_eq(str(c.tick_line(1.0, 10.0, true, allowed, price)["built"]), "a", "handed over as soon as there is room")
	c.set_weight("a", 0)
	c.tick_line(1.0, 500.0, true, allowed, price)
	assert_eq(c.status, CrewChain.NO_MIX)


func test_the_line_follows_the_build_mix() -> void:
	var c: CrewChain = _chain({"assembler": {"assembly_s": 1.0, "max_weight": 9, "reserve_parts": 0, "default_mix": {"a": 3, "b": 2, "c": 1, "d": 4}}})
	c.built = true
	var allowed: Array[String] = ["a", "b", "c"]  # "d" has not been built by hand yet
	var price: Callable = func(_t: String) -> float: return 1.0
	var made: Dictionary[String, int] = {}
	for i: int in 240:
		var t: String = str(c.tick_line(1.0, 1000.0, true, allowed, price)["built"])
		if t != "":
			made[t] = made.get(t, 0) + 1
	var total: int = made.get("a", 0) + made.get("b", 0) + made.get("c", 0)
	assert_gt(total, 100)
	assert_false(made.has("d"), "a type Lumi has not built by hand never goes on the line")
	assert_almost_eq(float(made["a"]) / float(total), 3.0 / 6.0, 0.02)
	assert_almost_eq(float(made["b"]) / float(total), 2.0 / 6.0, 0.02)
	assert_almost_eq(float(made["c"]) / float(total), 1.0 / 6.0, 0.02)
	assert_almost_eq(c.share("a", allowed), 0.5, 0.0001)
	c.set_weight("a", 0)
	c.set_weight("b", 0)
	assert_eq(c.upcoming(4, allowed), ["c", "c", "c", "c"] as Array[String], "a new mix counts from now, not from what was built before")
	c.set_weight("c", 99)
	assert_eq(c.weight("c"), 9, "a share number stops at the table's largest")


func test_chain_state_survives_a_save() -> void:
	var c: CrewChain = _chain()
	c.seed_cell(11, "rich")
	c.seed_cell(12, "rich")
	c.take(11, 0.5)
	c.take(12, 2.0)
	c.deliver(2.5)
	c.claim_arrival("rich")
	c.built = true
	c.offered = true
	c.set_weight("a", 5)
	c.tick_line(3.0, 100.0, true, ["a", "b"] as Array[String], func(_t: String) -> float: return 20.0)
	var saved: Variant = JSON.parse_string(JSON.stringify(c.to_dict()))
	var d: CrewChain = _chain()
	d.from_dict(saved)
	assert_almost_eq(d.stock_at(11), 1.5, 0.001)
	assert_false(d.has_stock(12))
	assert_eq(d.seed_cell(12, "rich"), 0.0, "an emptied hex stays empty after a load")
	assert_almost_eq(d.stock_total(), c.stock_total(), 0.001)
	assert_eq(d.claim_arrival("rich"), 0.0)
	assert_true(d.built)
	assert_eq(d.weight("a"), 5)
	assert_eq(d.current, c.current)
	assert_almost_eq(d.progress_s, 3.0, 0.001)
	assert_eq(d.deliver(0.5), 1.0, "the half Part carried over is still owed")
	var empty: CrewChain = _chain()
	empty.from_dict({})
	assert_false(empty.built, "a save from before the chain: nothing built, the default mix")
	assert_eq(empty.weight("a"), 3)


# --- Scroungers on the globe -----------------------------------------------------------------------------

func test_a_scrounger_digs_the_ground_empty_and_brings_every_part_home() -> void:
	var crew: SphereCrew = _crew_world()
	crew.chain = _chain()
	var seeded: float = 0.0
	for c: int in _g5.cells_around(HUB, 3):
		if c != HUB:
			seeded += crew.chain.seed_cell(c, "rich")
	var loads: Array[float] = []
	crew.parts_delivered.connect(func(p: float, _hub: int) -> void: loads.append(p))
	var u: Dictionary = crew.spawn("scrounger", 0, HUB)
	assert_eq(str(u["role"]), SphereScrounge.ROLE)
	crew.run_far(1500.0, 0.5)
	var total: float = 0.0
	for p: float in loads:
		total += p
		assert_lte(p, SphereScrounge.sack(u) + 0.001, "a trip carries one sack at most")
	assert_almost_eq(total, seeded, 0.01, "every buried part reached the base, none twice")
	assert_almost_eq(crew.chain.stock_total(), 0.0, 0.01)
	assert_gt(loads.size(), int(seeded / SphereScrounge.sack(u)) - 1, "it took trips: Parts per Scrounger are capped by the round trip")
	crew.run_far(60.0, 0.5)
	assert_eq(str(u["idle"]), SphereScrounge.IDLE_EMPTY, "with the ground empty it waits for newly cleaned hexes")
	assert_gt(crew.idle_for(u), 30.0)


func test_a_scrounger_searches_only_the_painted_area() -> void:
	var crew: SphereCrew = _crew_world()
	crew.chain = _chain()
	var ring: PackedInt32Array = _g5.cells_around(HUB, 2)
	var zone: Array[int] = [ring[3], ring[4], ring[5]]
	for c: int in ring:
		if c != HUB:
			crew.chain.seed_cell(c, "rich")
	for c: int in zone:
		crew.set_zone_cell(SphereScrounge.ROLE, c, true)
	var before: float = crew.chain.stock_total()
	crew.spawn("scrounger", 0, HUB)
	crew.run_far(600.0, 0.5)
	for c: int in zone:
		assert_false(crew.chain.has_stock(c), "the search zone is dug out")
	assert_almost_eq(crew.chain.stock_total(), before - 2.0 * zone.size(), 0.01, "and nothing outside it was touched")


func test_a_cleaner_zone_does_not_hold_the_scroungers() -> void:
	var crew: SphereCrew = _crew_world()
	crew.chain = _chain()
	var ring: PackedInt32Array = _g5.cells_around(HUB, 1)
	crew.chain.seed_cell(ring[2], "rich")
	crew.set_zone_cell("clean", ring[5], true)
	crew.spawn("scrounger", 0, HUB)
	crew.run_far(200.0, 0.5)
	assert_false(crew.chain.has_stock(ring[2]), "zones are per job: the cleaners' area is not the Scroungers'")


func test_a_scroungers_sack_survives_a_save() -> void:
	var crew: SphereCrew = _crew_world()
	crew.chain = _chain()
	var u: Dictionary = crew.spawn("scrounger", 0, HUB)
	u["parts"] = 5.0
	var saved: Variant = JSON.parse_string(JSON.stringify(crew.to_dict()))
	crew.from_dict(saved)
	assert_eq(crew.robots().size(), 1)
	assert_almost_eq(SphereScrounge.carried(crew.robots()[0]), 5.0, 0.001)
	var old: Dictionary = saved
	((old["robots"] as Array)[0] as Dictionary).erase("parts")
	crew.from_dict(old)
	assert_eq(SphereScrounge.carried(crew.robots()[0]), 0.0, "a robot saved before sacks existed loads with an empty one")


func test_a_robot_can_be_shipped_to_another_hub() -> void:
	var crew: SphereCrew = _crew_world()
	var other: int = _g5.cells_around(HUB, 12)[400]
	var u: Dictionary = crew.spawn("scoopie", 0, HUB)
	crew.reassign(u, other)
	assert_eq(int(u["hub"]), other)
	assert_lt(_g5.distance_m(crew.unit_cell(u), other), 30.0, "set down beside its new hub")
	crew.new_robot_hub_fn = func() -> int: return other
	assert_eq(crew.hub_for_new_robot(), other)
	crew.new_robot_hub_fn = func() -> int: return -1
	assert_eq(crew.hub_for_new_robot(), HUB, "no city in play: the crew's own hub")


# --- The chain in a world ----------------------------------------------------------------------------------

func test_a_hex_is_seeded_when_it_is_first_cleaned() -> void:
	var w: Dictionary = _chain_world(FIRST)
	var fx: DistrictFixture = w["fx"]
	var rc: RobotChain = w["rc"]
	var first: int = fx.districts.cells_of("old_town")[5]
	var second: int = fx.districts.cells_of("scrapyard")[5]
	fx.set_cell_stage(first, 1)
	rc.settle_ground()
	assert_false(rc.chain.has_stock(first), "the first city's ground holds nothing")
	fx.set_cell_stage(second, 1)
	assert_false(rc.chain.has_stock(second), "judged on the chain's tick, not in the middle of a change")
	rc.settle_ground()
	assert_eq(rc.chain.stock_at(second), rc.chain.parts_per_hex("scrapyard"))
	rc.chain.take(second, 99.0)
	fx.set_cell_stage(second, 0)
	fx.set_cell_stage(second, 1)
	fx.set_cell_stage(second, 3)
	rc.settle_ground()
	assert_false(rc.chain.has_stock(second), "dirtied and cleaned again, or grown further: nothing new")
	# Ground under a new building: cleaned, then marked as hub ground. It gives nothing.
	var under: int = fx.districts.cells_of("scrapyard")[9]
	fx.cells.set_junk(under, 0.0)
	fx.cells.set_state(under, PlanetData.State.CLEAN)
	fx.cells.set_flag(under, SphereCells.F_HUB)
	rc.settle_ground()
	assert_false(rc.chain.has_stock(under), "hub ground is not land")
	assert_almost_eq(rc.chain.seeded_parts, rc.chain.parts_per_hex("scrapyard"), 0.0001)


func test_a_planet_without_the_chain_has_none(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var w: Dictionary = _chain_world(planet_id)
	var fx: DistrictFixture = w["fx"]
	var rc: RobotChain = w["rc"]
	var has: bool = not (Economy.robot_cfg.get("chain", {}) as Dictionary).is_empty()
	assert_eq(rc.has_chain(), has)
	assert_false(rc.listed(), "nothing to build on a new game")
	assert_false(rc.build())
	fx.set_district_stage(fx.districts.ids()[0], 1, 20)
	_run_line(rc, 30.0)
	assert_eq((w["crew"] as SphereCrew).robots().size(), 0, "no robot appears by itself")
	if not has:
		assert_eq(rc.chain.seeded_parts, 0.0, "and no ground is seeded")
		assert_eq(rc.block_reason(), "Not yet.")


func test_parts_brought_home_go_into_the_wallet() -> void:
	var w: Dictionary = _chain_world(FIRST)
	var crew: SphereCrew = w["crew"]
	watch_signals(EventBus)
	_set_parts(3.0)
	crew.parts_delivered.emit(7.6, crew.hub_cell)
	assert_eq(_parts(), 10.0, "whole Parts")
	assert_signal_emitted_with_parameters(EventBus, "parts_scrounged", [7.0])
	crew.parts_delivered.emit(0.4, crew.hub_cell)
	assert_eq(_parts(), 11.0, "the fraction came with the next sack")
	assert_eq(float(GameState.stats.get("parts_scrounged", 0.0)), 8.0)


func test_the_assembler_comes_with_its_city_and_builds_the_crew_without_clicks() -> void:
	var w: Dictionary = _chain_world(FIRST)
	var crew: SphereCrew = w["crew"]
	var fleet: SphereFleet = w["fleet"]
	var rc: RobotChain = w["rc"]
	var unlock: String = str((rc.chain.assembler_cfg()["unlock"] as Dictionary)["district"])
	watch_signals(EventBus)
	_set_parts(0.0)
	assert_false(HubBuilds.listed(rc.get_parent(), RobotChain.BUILD_ID), "not on the Build list before its city")
	EventBus.district_entered.emit("scrapyard")
	assert_false(rc.listed(), "the second city is not it")
	EventBus.district_entered.emit(unlock)
	assert_true(rc.listed())
	assert_signal_emitted(EventBus, "assembler_offered")
	var salvage: float = float((rc.chain.cfg["arrival_parts"] as Dictionary)[unlock])
	assert_eq(_parts(), salvage, "the old factory shell's salvage")
	EventBus.district_entered.emit(unlock)
	assert_eq(_parts(), salvage, "paid once")
	assert_true(rc.build(), "the salvage pays for it at once")
	assert_eq(_parts(), salvage - float(rc.cost()["parts"]))
	assert_true(rc.is_built())
	assert_false(rc.listed(), "one Assembler on this planet")
	assert_signal_emitted(EventBus, "assembler_built")
	# Nothing by hand yet: the line has nothing it may build.
	_run_line(rc, 200.0)
	assert_eq(crew.robots().size(), 0)
	assert_eq(rc.chain.status, CrewChain.NO_MIX)
	# Lumi builds the first of two types by hand; from here the line runs on its own.
	Research.unlock_story("haul_rig")
	Research.unlock_story("scoopie_rig")
	crew.spawn("haulbug", 0, crew.hub_cell)
	crew.spawn("scoopie", 0, crew.hub_cell)
	GameState.world["hub_level"] = 3
	GameState.flags[Economy.FLAG_TIERS_OPEN] = 3
	_set_parts(60.0)
	var per_robot: float = rc.chain.assembly_s()
	_run_line(rc, per_robot * 0.9)
	assert_eq(crew.robots().size(), 2, "a robot takes the line's assembly time")
	_run_line(rc, per_robot * 0.2)
	assert_eq(crew.robots().size(), 3, "then it rolls out, with no click")
	assert_signal_emitted(EventBus, "robot_assembled")
	assert_eq(float(GameState.stats.get("robots_assembled", 0.0)), 1.0)
	_run_line(rc, per_robot * 30.0)
	assert_eq(rc.chain.status, CrewChain.NEED_PARTS, "it stops when the Parts run out: no Parts, no growth")
	assert_lt(_parts(), fleet.build_parts("scoopie").to_float())
	var with_60: int = crew.robots().size()
	assert_between(with_60, 7, 12, "60 Parts are about 7 robots")
	_set_parts(100000.0)
	var before: int = crew.robots().size()
	_run_line(rc, per_robot * 10.0 + 1.0)
	assert_between(crew.robots().size() - before, 10, 11, "one robot per assembly time, however many Parts there are")
	_run_line(rc, per_robot * 200.0)
	assert_eq(crew.robots().size(), fleet.crew_cap(), "and never past the crew cap")
	assert_eq(rc.chain.status, CrewChain.CREW_FULL)


func test_new_robots_work_for_the_city_lumi_is_in_and_idle_ones_follow() -> void:
	var w: Dictionary = _chain_world(FIRST)
	var fx: DistrictFixture = w["fx"]
	var crew: SphereCrew = w["crew"]
	var rc: RobotChain = w["rc"]
	assert_eq(rc.work_hub(), fx.site_cells[fx.districts.site_of("old_town")])
	crew.rings = 3
	for c: int in fx.districts.cells_of("old_town"):
		fx.set_cell_stage(c, 1)  # nothing left to clean in the first base's region
	var u: Dictionary = crew.spawn("scoopie", 0, crew.hub_cell)
	crew.run_far(20.0, 1.0)
	assert_eq(str(u["mode"]), "idle", "out of work at home")
	assert_eq(rc.redeploy(), 0, "in the city in play nobody is moved")
	fx.set_district_stage("old_town", 4)
	var second_cell: int = fx.site_cells[fx.districts.site_of("scrapyard")]
	fx.districts.set_player_cell(second_cell)
	assert_eq(rc.work_hub(), second_cell, "the base of the city Lumi stands in")
	assert_eq(crew.hub_for_new_robot(), second_cell)
	assert_eq(rc.redeploy(), 0, "not idle for long enough yet")
	crew.run_far(float(rc.chain.cfg["redeploy_idle_s"]) + 5.0, 1.0)
	assert_eq(rc.redeploy(), 1, "a robot with nothing to do follows Lumi")
	assert_eq(int(u["hub"]), second_cell)
	crew.run_far(120.0, 1.0)
	assert_ne(str(u["mode"]), "idle", "and finds work there")


func test_ground_cleaned_before_the_chain_gives_nothing() -> void:
	var w: Dictionary = _chain_world(FIRST)
	var fx: DistrictFixture = w["fx"]
	var rc: RobotChain = w["rc"]
	rc.chain = CrewChain.new()
	rc.chain.configure(Economy.robot_cfg.get("chain", {}))
	var cells: PackedInt32Array = fx.districts.cells_of("scrapyard")
	rc._cells.cell_changed.disconnect(rc._on_cell_changed)
	for i: int in 10:
		fx.set_cell_stage(cells[i], 2)
	rc._cells.cell_changed.connect(rc._on_cell_changed)
	rc._changed.clear()
	rc.load_state({}, true)
	assert_eq(rc.chain.seeded_parts, 0.0)
	fx.set_cell_stage(cells[0], 0)
	fx.set_cell_stage(cells[0], 1)
	rc.settle_ground()
	assert_false(rc.chain.has_stock(cells[0]), "an old save's clean ground is spent")
	fx.set_cell_stage(cells[20], 1)
	rc.settle_ground()
	assert_true(rc.chain.has_stock(cells[20]), "ground cleaned from now on is not")


func test_the_chain_saves_and_loads_with_the_world() -> void:
	var w: Dictionary = _chain_world(FIRST)
	var fx: DistrictFixture = w["fx"]
	var rc: RobotChain = w["rc"]
	var cell: int = fx.districts.cells_of("scrapyard")[3]
	fx.set_cell_stage(cell, 1)
	rc.settle_ground()
	assert_true(rc.chain.has_stock(cell))
	rc.chain.offered = true
	_set_parts(1000.0)
	assert_true(rc.build())
	rc.set_weight("scoopie", 7)
	rc.set_paused(true)
	var saved: Variant = JSON.parse_string(JSON.stringify(rc.save_state()))
	var again := RobotChain.new()
	add_child_autofree(again)
	again.set_physics_process(false)
	again.setup(null, w["crew"], w["fleet"], fx.districts, fx.cells, fx.site_cells)
	again.load_state(saved, true)
	assert_true(again.is_built())
	assert_true(again.chain.paused)
	assert_eq(again.chain.weight("scoopie"), 7)
	assert_eq(again.chain.stock_at(cell), rc.chain.stock_at(cell))


# --- The whole planet: the crew simulator -----------------------------------------------------------------

func test_the_simulated_crew_follows_the_accepted_curve() -> void:
	var r: Dictionary = CrewSim.run(Planets.by_id(FIRST), CrewSim.load_calibration())
	var by_city: Array = r["crew_by_city"]
	assert_eq(by_city.size(), ACCEPTED_CREW.size())
	for i: int in ACCEPTED_CREW.size():
		var want: float = float(ACCEPTED_CREW[i])
		assert_between(float(by_city[i]), want * (1.0 - CREW_TOLERANCE), want * (1.0 + CREW_TOLERANCE), "crew after city %d (accepted %d)" % [i + 1, ACCEPTED_CREW[i]])
	assert_between(int(r["crew_end"]), LAUNCH_CREW_MIN, LAUNCH_CREW_MAX, "100 to 200 robots at the launch point")
	assert_gte(float(r["fastest_doubling_s"]), FASTEST_DOUBLING_S, "the crew never doubles in a couple of minutes")
	assert_lte(float(r["longest_stall_s"]), LONGEST_WAIT_S, "and never stops growing for long from the second city on")
	assert_gt(int(r["assembled"]), int(r["hand_built"]), "the Assembler builds most of the crew")
	assert_lte(float(r["parts_scrounged"]), float(r["ground_seeded"]) + 0.001, "Scroungers bring in no more than the cleaned ground held")
	assert_gt(float(r["first_assembler_min"]), 80.0, "the Assembler stands in the third city")


func test_the_chain_cannot_run_away() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var cal: Dictionary = CrewSim.load_calibration()
	var normal: Dictionary = CrewSim.run(def, cal)
	var greedy: Dictionary = CrewSim.run(def, cal, CrewSim.POLICY_ALL_FINDERS)
	assert_lte(int(greedy["crew_end"]), int(normal["crew_end"]), "building nothing but Scroungers does not make a bigger crew")
	assert_lte(int(greedy["crew_end"]), LAUNCH_CREW_MAX)
	assert_lte(float(greedy["parts_scrounged"]), float(greedy["ground_seeded"]) + 0.001, "the ground runs out")
	assert_gte(float(greedy["fastest_doubling_s"]), FASTEST_DOUBLING_S)
	# With ten times the buried parts the crew is no larger: the line and the cap pace it, not Parts.
	var rich: Dictionary = cal.duplicate(true)
	var per_hex: Array = rich["hand_parts_per_hex"]
	for i: int in per_hex.size():
		per_hex[i] = float(per_hex[i]) * 10.0
	var flooded: Dictionary = CrewSim.run(def, rich)
	assert_lte(int(flooded["crew_end"]), LAUNCH_CREW_MAX)
	assert_lte(int((flooded["crew_by_city"] as Array)[2]), int((Economy.robot_cfg["crew_cap"]["by_cities_open"] as Array)[2]))
	assert_gte(float(flooded["fastest_doubling_s"]), FASTEST_DOUBLING_S, "even flooded with Parts the crew does not double in under three minutes")


func test_without_scroungers_the_crew_still_grows_but_slower() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var cal: Dictionary = CrewSim.load_calibration()
	var normal: Dictionary = CrewSim.run(def, cal)
	var none: Dictionary = CrewSim.run(def, cal, CrewSim.POLICY_NO_FINDERS)
	assert_eq(float(none["parts_scrounged"]), 0.0)
	assert_lt(int(none["crew_end"]), int(normal["crew_end"]), "Scroungers are what feeds the line")
	assert_gte(int(none["crew_end"]), LAUNCH_CREW_MIN, "but a player who never builds one is not locked out")


func test_ring_of_counts_hexes_outward() -> void:
	assert_eq(CrewSim.ring_of(0), 0)
	assert_eq(CrewSim.ring_of(1), 1)
	assert_eq(CrewSim.ring_of(6), 1)
	assert_eq(CrewSim.ring_of(7), 2)
	assert_eq(CrewSim.ring_of(126), 6)
	assert_eq(CrewSim.ring_of(127), 7)


## The simulator's Scrounger trips against the real crew's: one Scrounger on a globe whose ground
## holds one part a hex, for a quarter of an hour. The calibration's path_factor is fitted here.
func test_the_simulators_scrounger_keeps_pace_with_the_real_one() -> void:
	var crew: SphereCrew = _crew_world()
	crew.chain = _chain()
	var rings: int = 6
	for c: int in _g5.cells_around(HUB, rings):
		if c != HUB:
			crew.chain.seed_cell(c, "")
	var brought: Array[float] = [0.0]
	crew.parts_delivered.connect(func(p: float, _hub: int) -> void: brought[0] += p)
	var u: Dictionary = crew.spawn("scrounger", 0, HUB)
	var seconds: float = 900.0
	crew.run_far(seconds, 0.5)
	var cal: Dictionary = CrewSim.load_calibration()
	var spacing: float = _g5.distance_m(HUB, _g5.cells_around(HUB, 1)[1]) * float(cal["path_factor"])
	var speed: float = Economy.robot_stat("scrounger", "speed", 0)
	var sack: int = int(SphereScrounge.sack(u))
	var t: float = 0.0
	var expected: float = 0.0
	var hex: int = 1
	while true:
		t += CrewSim.trip_seconds(CrewSim.ring_of(hex), sack - 1, CrewSim.ring_of(hex + sack - 1), float(sack), spacing, speed, SphereScrounge.dig_rate(u))
		if t > seconds:
			break
		expected += float(sack)
		hex += sack
	assert_gt(brought[0], 0.0)
	assert_between(brought[0], expected * 0.75, expected * 1.25, "real %.0f Parts against the simulator's %.0f in %d s" % [brought[0], expected, int(seconds)])


# --- Keeping 200 robots cheap ----------------------------------------------------------------------------

## A dirty world of far records round HUB (the crew's cells are all junk).
func _dirty_crew_world() -> SphereCrew:
	var crew: SphereCrew = _crew_world()
	crew.cells.junk.fill(1.0)
	crew.cells.state.fill(0)
	crew.cells.refresh_all()
	return crew


func test_a_search_that_found_nothing_is_not_repeated_at_once() -> void:
	var crew: SphereCrew = _crew_world()  # all clean: nothing to do
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "clean", "a"), -1)
	var cell: int = _g5.cells_around(HUB, 2)[9]
	crew.cells.set_state(cell, 0)
	crew.cells.set_junk(cell, 1.0)
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "clean", "b"), -1, "the answer is kept for a moment: no second search of the whole region")
	crew.run_far(SphereCrew.NOTHING_FOUND_S + 0.5, 0.5)
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "clean", "c"), cell, "then the new work is found")
	crew.release(cell)
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "water", "d"), -1)
	assert_ne(crew.claim_dirty(HUB, HUB, crew.rings, "plant", "f"), -1, "each job's answer is its own: clean ground is a planter's work")
	crew.set_zone_cell("clean", cell, true)
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "clean", "e"), cell, "painting an area looks again at once")


func test_land_robots_take_no_work_across_water() -> void:
	var crew: SphereCrew = _crew_world()
	var island: int = _g5.cells_around(HUB, 4)[40]
	crew.cells.set_state(island, 0)
	crew.cells.set_junk(island, 1.0)
	for c: int in _g5.cells_around(island, 1):
		if c != island:
			crew.cells.set_state(c, 5)  # a ring of lake round it
	assert_true(crew.route(HUB, island).is_empty(), "no way over the water")
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "clean", "a"), -1, "so the hex is never claimed, and no route search is spent on it")
	crew.set_zone_cell("clean", island, true)
	assert_eq(crew.claim_dirty(HUB, HUB, crew.rings, "clean", "b"), island, "unless the player painted it: the robot tries")


func test_looking_for_work_is_spread_over_the_ticks() -> void:
	var crew: SphereCrew = _dirty_crew_world()
	for i: int in 60:
		crew.spawn("scoopie", 0, HUB)
	crew.tick(crew.far_every + 0.01)
	var busy: int = 0
	for u: Dictionary in crew.robots():
		if str(u["mode"]) != "idle":
			busy += 1
	assert_gt(busy, 0, "some set off on the first tick")
	assert_lt(busy, 60, "not all sixty: a tick has a budget for searching")
	for i: int in 400:
		crew.tick(0.05)
	busy = 0
	for u: Dictionary in crew.robots():
		if str(u["mode"]) != "idle":
			busy += 1
	assert_eq(busy, 60, "a few seconds later every robot has work")


func test_far_robots_step_on_their_own_clocks() -> void:
	var crew: SphereCrew = _dirty_crew_world()
	for i: int in 80:
		crew.spawn("scoopie", 0, HUB)
	var stepped_per_tick: Array[int] = []
	for i: int in 10:
		crew.tick(crew.far_every / 5.0)
		var n: int = 0
		for u: Dictionary in crew.robots():
			if is_equal_approx(float(u["far_at"]), crew._t):
				n += 1
		stepped_per_tick.append(n)
	var total: int = 0
	for n: int in stepped_per_tick:
		total += n
		assert_lt(n, 50, "the far robots do not all step on the same tick")
	assert_between(total, 80, 170, "and each of the 80 stepped once or twice in two periods")
