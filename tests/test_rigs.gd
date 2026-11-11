extends GutTest
## Rigs (task M3-08; systems/rigs.gd, the planet's "rigs" table): three slots, modules with
## trade-offs, each city's tool as the gate of its pollution kind, fitting, saving, the parts on
## Lumi's model, the workbench panel, the bot's rule and the rig study.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const PRICE_CAP: float = 4200.0
const MIN_SLOTS: int = 3
const MIN_MODULES: int = 3
## Kind -> what used to open it before rigs: none of these may open it now.
const OLD_KEYS: Dictionary = {
	"wrecks": {"upgrades": {"lift_strength": 2}},
	"slick": {"upgrades": {"hover_jets": 1}},
	"smog": {"flags": {"seeds_unlocked": true}},
	"blight": {"flags": {"seeds_unlocked": true}},
}
const TOOL_KINDS: Array[String] = ["wrecks", "slick", "smog", "blight"]

var _saved: Dictionary = {}
var _nodes: Array[Node] = []
var _fitted: Array[Array] = []
var _unlocked: Array[String] = []


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = {"currencies": GameState.currencies, "flags": GameState.flags, "upgrades": GameState.upgrades}
	GameState.currencies = {}
	GameState.flags = {}
	GameState.upgrades = {}
	_fitted.clear()
	_unlocked.clear()
	EventBus.rig_fitted.connect(_on_fitted)
	EventBus.rig_module_unlocked.connect(_on_unlocked)


func after_each() -> void:
	EventBus.rig_fitted.disconnect(_on_fitted)
	EventBus.rig_module_unlocked.disconnect(_on_unlocked)
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.upgrades = _saved["upgrades"]


func _on_fitted(slot: String, id: String) -> void:
	_fitted.append([slot, id])


func _on_unlocked(id: String) -> void:
	_unlocked.append(id)


func _rigs(planet_id: StringName = FIRST, saved: Dictionary = {}) -> Rigs:
	var r := Rigs.new()
	_nodes.append(r)
	r.setup(Planets.by_id(planet_id), saved)
	return r


## The cities of the first planet in order, opened one after another up to `district`.
func _open_to(district: String) -> void:
	for spec: Dictionary in Districts.specs_for(Planets.by_id(FIRST)):
		EventBus.district_unlocked.emit(str(spec["id"]))
		if str(spec["id"]) == district:
			return


func _pollution(rigs: Rigs) -> Pollution:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var grid: SphereGrid = SphereGrid.cached(DistrictFixture.LEVEL)
	grid.radius_m = SphereGrid.radius_for(DistrictFixture.LEVEL, 10.0)
	var cells := SphereCells.new(grid.cell_count())
	cells.junk.fill(1.0)
	var p := Pollution.new()
	_nodes.append(p)
	p.setup(def, grid, cells, null, DistrictFixture.face_centre_cells(grid, def.hub_count), {})
	p.set_rigs(rigs)
	return p


# --- The table: three slots, modules with trade-offs, prices ------------------------------------

func test_three_slots_with_at_least_three_modules_each() -> void:
	var r: Rigs = _rigs()
	assert_true(r.enabled())
	assert_gte(r.slots().size(), MIN_SLOTS, "three slots on Lumi")
	for slot: String in r.slots():
		assert_gte(r.modules_of(slot).size(), MIN_MODULES, "slot %s has at least three modules" % slot)
		assert_ne(r.slot_name(slot), "", slot)


func test_every_module_gives_something_and_costs_something() -> void:
	# A real trade-off: a module with a gain (a kind it opens, or a stat it raises) also has a
	# loss (a stat it lowers), so no module is a plain upgrade.
	var r: Rigs = _rigs()
	for id: String in r.ids():
		var m: Dictionary = r.module(id)
		var gains: int = 1 if r.is_tool(id) else 0
		var losses: int = 0
		for key: String in (m.get("mods", {}) as Dictionary):
			if float(m["mods"][key]) > 1.0:
				gains += 1
			elif float(m["mods"][key]) < 1.0:
				losses += 1
		gains += (m.get("adds", {}) as Dictionary).size()
		assert_gt(gains, 0, id + " gives something")
		assert_gt(losses, 0, id + " costs something")
		assert_ne(str(m.get("desc", "")), "", id + " says what it is")
		assert_false(r.effect_lines(id).is_empty(), id + " lists its effects")


func test_prices_stay_inside_the_city_price_cap() -> void:
	var r: Rigs = _rigs()
	var priced: int = 0
	for id: String in r.ids():
		var cost: Dictionary = r.cost_of(id)
		for currency: String in cost:
			assert_true(currency in ["cubes", "parts"], "%s is paid in cubes or Parts" % id)
			assert_lt(float(cost[currency]), PRICE_CAP, "%s %s under the cap" % [id, currency])
		priced += 0 if cost.is_empty() else 1
		assert_eq(cost.is_empty(), r.is_tool(id), id + ": a city's tool is free, every other module is built")
	assert_gt(priced, 0)


func test_every_slot_has_a_module_that_acts_on_the_crew() -> void:
	# Design decision 16.8.
	var r: Rigs = _rigs()
	for slot: String in r.slots():
		var crew: int = 0
		for id: String in r.modules_of(slot):
			for key: String in ["crew_near", "crew_radius", "parts_yield"]:
				crew += 1 if (r.module(id).get("mods", {}) as Dictionary).has(key) else 0
		assert_gt(crew, 0, "slot %s has a crew module" % slot)


func test_no_city_one_module_and_nothing_known_at_the_start() -> void:
	# The first city's pacing (M3-21) is untouched: no plan arrives before the second city opens.
	var r: Rigs = _rigs()
	for id: String in r.ids():
		assert_eq(r.state(id), Rigs.LOCKED, id)
		assert_ne(r.district_of(id), "old_town", id)
	assert_false(bool(GameState.flags.get(Rigs.FLAG_OPEN, false)), "the Rig tab is not shown yet")


# --- Gates: each city's kind needs its tool ------------------------------------------------------

func test_every_kind_beside_the_base_kind_is_gated_by_a_tool() -> void:
	var r: Rigs = _rigs()
	var kinds: Dictionary = Planets.by_id(FIRST).table(Pollution.TABLE)["kinds"]
	for kind: String in TOOL_KINDS:
		var tool: String = str(kinds[kind]["gate"].get("module", ""))
		assert_ne(tool, "", kind + " names a module")
		assert_eq(r.tool_for(kind), tool, "and that module is the tool for " + kind)
		assert_false((kinds[kind]["gate"] as Dictionary).has("stat"), kind + " is not opened by an upgrade")
	assert_eq(r.tool_for("litter"), "", "litter needs no tool")


func test_the_tool_arrives_with_its_city_not_before(kind: String = use_parameters(TOOL_KINDS)) -> void:
	var r: Rigs = _rigs()
	var tool: String = r.tool_for(kind)
	var specs: Array[Dictionary] = Districts.specs_for(Planets.by_id(FIRST))
	var first_city: String = ""
	for spec: Dictionary in specs:
		if kind in (spec.get("pollution", []) as Array):
			first_city = str(spec["id"])
			break
	assert_eq(r.district_of(tool), first_city, "the tool for %s comes with the first city that holds it" % kind)
	for spec: Dictionary in specs:
		if str(spec["id"]) == first_city:
			break
		EventBus.district_unlocked.emit(str(spec["id"]))
		assert_eq(r.state(tool), Rigs.LOCKED, "not before %s opens" % first_city)
	assert_false(tool in _unlocked)
	EventBus.district_unlocked.emit(first_city)
	assert_eq(r.state(tool), Rigs.OWNED, "handed over when the city opens, not fitted")
	assert_true(tool in _unlocked, "and the game is told")
	assert_true(bool(GameState.flags.get(Rigs.FLAG_OPEN, false)), "the Rig tab opens")


func test_a_kind_stays_shut_until_its_tool_is_fitted(kind: String = use_parameters(TOOL_KINDS)) -> void:
	var r: Rigs = _rigs()
	var pol: Pollution = _pollution(r)
	var tool: String = r.tool_for(kind)
	# Everything that used to open the kind, and arriving in its city, is not enough any more.
	for id: String in (OLD_KEYS[kind].get("upgrades", {}) as Dictionary):
		GameState.upgrades[id] = int(OLD_KEYS[kind]["upgrades"][id])
	for id: String in (OLD_KEYS[kind].get("flags", {}) as Dictionary):
		GameState.flags[id] = OLD_KEYS[kind]["flags"][id]
	_open_to(r.district_of(tool))
	assert_false(pol.can_work(kind), "%s is shut on arrival" % kind)
	assert_true(r.fit(tool))
	assert_true(pol.can_work(kind), "fitted: %s opens" % kind)
	r.unfit(r.slot_of(tool))
	assert_false(pol.can_work(kind), "taken off: shut again")


func test_a_tool_needs_nothing_bought_in_the_first_city() -> void:
	# The Cutter brings the lift wrecks need and the Skirt the hover: no upgrade is a hidden gate.
	var r: Rigs = _rigs()
	_open_to("kettle_bay")
	assert_lt(Economy.stat("lift_class"), 2.0)
	assert_lt(Economy.stat("hover_water"), 1.0)
	r.fit(r.tool_for("wrecks"))
	r.fit(r.tool_for("slick"))
	assert_gte(Economy.stat("lift_class"), 2.0, "the Plate Cutter lifts what it cuts")
	assert_gte(Economy.stat("hover_water"), 1.0, "the Skim Skirt floats")


func test_a_gate_that_names_a_module_stays_shut_with_no_rig() -> void:
	var pol: Pollution = _pollution(null)
	assert_false(pol.can_work("wrecks"))
	assert_true(pol.can_work("litter"))


# --- Building and fitting ------------------------------------------------------------------------

func test_a_module_is_built_once_for_its_price_then_fitted_free() -> void:
	var r: Rigs = _rigs()
	_open_to("scrapyard")
	var id: String = "deep_hold"
	assert_eq(r.state(id), Rigs.PLAN)
	assert_false(r.fit(id), "a plan cannot be fitted")
	assert_false(r.build(id), "nor built without its price")
	for currency: String in r.cost_of(id):
		GameState.add_currency(currency, BigNum.from_float(float(r.cost_of(id)[currency]) * 2.0))
	watch_signals(EventBus)
	assert_true(r.build(id))
	assert_signal_emitted_with_parameters(EventBus, "rig_module_built", [id])
	assert_eq(r.state(id), Rigs.OWNED)
	for currency: String in r.cost_of(id):
		assert_almost_eq(GameState.get_currency(currency).to_float(), float(r.cost_of(id)[currency]), 0.01, "paid once")
	assert_false(r.build(id), "not built twice")
	assert_true(r.fit(id))
	r.unfit(r.slot_of(id))
	assert_true(r.fit(id))
	for currency: String in r.cost_of(id):
		assert_almost_eq(GameState.get_currency(currency).to_float(), float(r.cost_of(id)[currency]), 0.01, "fitting is free")
	assert_eq(_fitted, [["chest", id], ["chest", ""], ["chest", id]])


func test_one_module_per_slot_and_slots_are_independent() -> void:
	var r: Rigs = _rigs()
	for id: String in ["plate_cutter", "wide_sweep", "deep_hold", "sprint_coils"]:
		r.grant(id, false)
	r.fit("plate_cutter")
	r.fit("deep_hold")
	r.fit("sprint_coils")
	assert_eq([r.fitted("arm"), r.fitted("chest"), r.fitted("drive")], ["plate_cutter", "deep_hold", "sprint_coils"])
	r.fit("wide_sweep")
	assert_eq(r.fitted("arm"), "wide_sweep", "the new module takes the slot")
	assert_eq(r.state("plate_cutter"), Rigs.OWNED, "the old one goes back on the shelf")
	assert_eq(r.fitted("chest"), "deep_hold")


func test_fitted_modules_change_lumis_stats_both_ways() -> void:
	var r: Rigs = _rigs()
	var base: Dictionary = {}
	for stat: String in ["capacity", "move_speed", "carry_stack", "scoop_width", "scoop_reach", "cube_value_mult", "detector_range"]:
		base[stat] = Economy.stat(stat)
	r.grant("deep_hold")
	var mods: Dictionary = r.module("deep_hold")["mods"]
	assert_almost_eq(Economy.stat("capacity"), float(base["capacity"]) * float(mods["capacity"]), 0.001, "a bigger chest")
	assert_almost_eq(Economy.stat("move_speed"), float(base["move_speed"]) * float(mods["move_speed"]), 0.001, "and a slower Lumi")
	r.grant("tow_hitch")
	assert_almost_eq(Economy.stat("carry_stack"), float(base["carry_stack"]) + float(r.module("tow_hitch")["adds"]["carry_stack"]), 0.001)
	assert_almost_eq(Economy.stat("move_speed"), float(base["move_speed"]) * float(mods["move_speed"]) * float(r.module("tow_hitch")["mods"]["move_speed"]), 0.001, "two slots stack")
	assert_false(Rigs.breakdown("capacity").is_empty(), "the stat tooltip names the module")
	r.unfit("chest")
	r.unfit("drive")
	for stat: String in base:
		assert_almost_eq(Economy.stat(stat), float(base[stat]), 0.0001, stat + " is back to what it was")


func test_modules_reach_kind_rate_parts_and_the_crew() -> void:
	var r: Rigs = _rigs()
	var m := Mastery.new()
	_nodes.append(m)
	m.setup(Planets.by_id(FIRST), {})
	var near_m: float = float(m.config()["near_m"])
	var bonus: float = m.near_factor(1.0) - 1.0
	assert_gt(bonus, 0.0)
	assert_eq(m.near_factor(near_m * 1.5), 1.0, "out of reach")
	assert_eq(Rigs.factor("parts_yield"), 1.0)
	r.grant("guide_arm")
	assert_almost_eq(m.near_factor(1.0) - 1.0, bonus * float(r.module("guide_arm")["mods"]["crew_near"]), 0.0001, "the Guide Arm grows the bonus")
	r.grant("relay_mast")
	assert_gt(m.near_factor(near_m * 1.5), 1.0, "the Relay Mast reaches further")
	r.grant("sorter")
	assert_almost_eq(Rigs.factor("parts_yield"), float(r.module("sorter")["mods"]["parts_yield"]), 0.0001)
	r.grant("long_reach")
	var pol: Pollution = _pollution(r)
	assert_almost_eq(pol.hand_bonus("slick"), float(r.module("long_reach")["mods"]["kind_slick"]), 0.0001, "a kind rate reaches Lumi's hand work")
	assert_eq(pol.hand_bonus("litter"), 1.0)


func test_a_freed_rig_takes_its_effects_with_it() -> void:
	var base: float = Economy.stat("capacity")
	var r: Rigs = _rigs()
	r.grant("deep_hold")
	assert_gt(Economy.stat("capacity"), base)
	r.free()
	assert_almost_eq(Economy.stat("capacity"), base, 0.0001)
	assert_eq(Rigs.factor("crew_near"), 1.0)


# --- Saving --------------------------------------------------------------------------------------

func test_the_rig_round_trips_and_ignores_what_it_does_not_know() -> void:
	var r: Rigs = _rigs()
	_open_to("kettle_bay")
	r.grant("deep_hold")
	r.fit("plate_cutter")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(r.save_state()))
	var again: Rigs = _rigs(FIRST, saved)
	for id: String in r.ids():
		assert_eq(again.state(id), r.state(id), id)
	assert_eq(again.save_state(), r.save_state())
	saved["owned"].append("no_such_module")
	saved["fit"]["arm"] = "sprint_coils"  # owned or not, a drive module is not an arm module
	saved["fit"]["nose"] = "plate_cutter"
	var odd: Rigs = _rigs(FIRST, saved)
	assert_eq(odd.fitted("arm"), "")
	assert_eq(odd.fitted("nose"), "")
	assert_false(odd.is_owned("no_such_module"))


func test_a_save_from_before_rigs_keeps_its_cities_workable() -> void:
	var fx := DistrictFixture.new(FIRST)
	_nodes.append(fx.districts)
	_nodes.append(fx.restoration)
	for id: String in ["old_town", "scrapyard", "kettle_bay"]:
		fx.set_district_stage(id, 5)
	fx.districts.load_state({})
	assert_true(fx.districts.is_unlocked("highreach"))
	var r: Rigs = _rigs()
	r.sync_districts(fx.districts, true)
	for id: String in ["plate_cutter", "skim_skirt", "mist_scrubber"]:
		assert_true(r.is_fitted(id), id + " is on")
	assert_eq(r.state("soil_doser"), Rigs.LOCKED, "Lowmeadow is not open yet")
	assert_eq(r.state("wide_sweep"), Rigs.PLAN, "what is built stays to be built")
	var fresh: Rigs = _rigs()
	fresh.sync_districts(fx.districts, false)
	assert_eq(fresh.state("plate_cutter"), Rigs.OWNED, "a save with a rig section is not fitted for the player")


func test_a_rig_loads_on_any_planet(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var r: Rigs = _rigs(planet_id)
	var def: PlanetDefinition = Planets.by_id(planet_id)
	assert_eq(r.enabled(), def.has_table(Rigs.TABLE))
	var again: Rigs = _rigs(planet_id, r.save_state())
	assert_eq(again.save_state(), r.save_state())
	for id: String in r.ids():
		assert_true(r.slot_of(id) in r.slots(), id)
	if not r.enabled():
		assert_eq(r.parts(), [] as Array[Dictionary])
		assert_eq(Economy.stat("capacity"), Rigs.stat_mod("capacity", Economy.stat("capacity")), "no rig changes nothing")


# --- On the model --------------------------------------------------------------------------------

func test_every_module_has_a_part_the_model_can_build() -> void:
	var r: Rigs = _rigs()
	var seen: Dictionary[String, bool] = {}
	for id: String in r.ids():
		var shape: String = str(Rigs.part_of(id, r.module(id))["shape"])
		assert_true(shape in RigParts.shapes(), "%s: shape '%s'" % [id, shape])
		assert_false(seen.has(shape), "%s has a part of its own" % id)
		seen[shape] = true
		var node: Node3D = RigParts.build(shape, Color.WHITE)
		assert_gt(node.get_child_count(), 1, id + " is more than one block")
		node.free()


func test_fitted_modules_show_on_lumi_and_survive_a_change_of_look() -> void:
	var r: Rigs = _rigs()
	var m := PatchModel.new()
	m.preview_variant = "aurora"
	add_child_autofree(m)
	assert_eq(m.rig_shown(), [] as Array[String], "nothing fitted, nothing shown")
	for id: String in ["plate_cutter", "mist_scrubber", "skim_skirt"]:
		r.grant(id)
	m.set_rig(r.parts())
	assert_eq(m.rig_shown(), ["plate_cutter", "mist_scrubber", "skim_skirt"] as Array[String])
	var wrist: Node3D = m.rig_mount(RigParts.MOUNT_WRIST)
	assert_not_null(wrist.get_node_or_null("Rig_plate_cutter"), "the arm tool rides the wrist")
	assert_not_null(m.rig_mount(RigParts.MOUNT_BODY).get_node_or_null("Rig_skim_skirt"), "the drive gear is on the body")
	m.set_variant("sprout")
	assert_eq(m.rig_shown(), ["plate_cutter", "mist_scrubber", "skim_skirt"] as Array[String], "a new look keeps the rig")
	r.unfit("arm")
	m.set_rig(r.parts())
	await get_tree().process_frame
	assert_eq(m.rig_shown(), ["mist_scrubber", "skim_skirt"] as Array[String], "a module taken off is gone from the model")


func test_rig_slots_and_modules_are_not_look_slots_or_pieces() -> void:
	var r: Rigs = _rigs()
	var looks: Dictionary = Economy.read_json("res://data/cosmetics.json")
	var text: String = JSON.stringify(looks)
	for id: String in r.ids():
		assert_false(text.contains("\"%s\"" % id), id + " is not a cosmetic piece")
	GameState.flags["patch_skin"] = "aurora"
	var before: String = JSON.stringify(GameState.global)
	r.grant("deep_hold")
	r.unfit("chest")
	assert_eq(JSON.stringify(GameState.global), before, "fitting never touches the found pieces")
	assert_eq(str(GameState.flags["patch_skin"]), "aurora")


# --- Workbench panel -----------------------------------------------------------------------------

func test_the_rig_tab_opens_with_the_first_plan() -> void:
	var ids: Array = UpgradesScreen.TABS.map(func(t: Dictionary) -> String: return str(t["id"]))
	assert_true("rigs" in ids)
	GameState.flags["bench_tabs"] = []
	assert_false(UpgradesScreen.tab_visible("rigs"), "no plan, no tab")
	_rigs()
	_open_to("scrapyard")
	assert_true(UpgradesScreen.tab_visible("rigs"))


func test_the_panel_lists_every_module_and_fits_on_a_press() -> void:
	var world := Node.new()
	add_child_autofree(world)
	var r := Rigs.new()
	world.add_child(r)
	r.setup(Planets.by_id(FIRST), {})
	_open_to("scrapyard")
	var panel := RigPanel.new()
	panel.world = world
	world.add_child(panel)
	assert_eq(panel._cols.get_child_count(), r.slots().size(), "one column per slot")
	assert_eq(panel._buttons.size(), 4, "the four modules whose plans have arrived can be acted on")
	assert_true(panel._buttons["wide_sweep"].disabled, "a module that is not paid for cannot be built")
	assert_eq(panel.first_button(), panel._buttons["plate_cutter"])
	panel._buttons["plate_cutter"].pressed.emit()
	assert_true(r.is_fitted("plate_cutter"))
	assert_eq(panel._buttons["plate_cutter"].text, "Take off", "the fitted row offers to take it off")
	GameState.add_currency("cubes", BigNum.from_float(5000.0))
	assert_false(panel._buttons["wide_sweep"].disabled, "paid for: it can be built")
	panel._buttons["wide_sweep"].pressed.emit()
	assert_true(r.is_fitted("wide_sweep"), "a built module is fitted at once")
	assert_eq(r.state("plate_cutter"), Rigs.OWNED)
	await wait_process_frames(2)  # the rows the panel replaced are freed


# --- The bot and the study -----------------------------------------------------------------------

func test_the_bot_is_told_the_tools_the_open_cities_need() -> void:
	var r: Rigs = _rigs()
	_open_to("lowmeadow")
	# Newest kind first: blight's tool and slick's share the drive slot, blight wins.
	var wanted: Array[String] = r.tools_wanted(["blight", "smog", "slick", "wrecks", "litter"])
	assert_eq(wanted, ["soil_doser", "mist_scrubber", "plate_cutter"] as Array[String])
	for id: String in wanted:
		r.fit(id)
	assert_eq(r.tools_wanted(["blight", "smog", "slick", "wrecks", "litter"]), [] as Array[String], "all fitted: nothing to do")
	assert_eq(r.tools_wanted(["slick"]), ["skim_skirt"] as Array[String], "back in the lake city the skirt is wanted again")


func test_the_study_finds_no_module_that_is_best_in_every_city() -> void:
	var study: Dictionary = RigStudy.run(Planets.by_id(FIRST))
	assert_true(bool(study["ok"]), str(study["error"]))
	assert_eq(study["dominant"], [], "no module is the best fit of its slot in every city")
	var winners: Dictionary[String, Dictionary] = {}
	for city: Dictionary in study["cities"]:
		for slot: String in city["best"]:
			if not winners.has(slot):
				winners[slot] = {}
			winners[slot][city["best"][slot]] = true
	for slot: String in study["slots"]:
		assert_gte(winners.get(slot, {}).size(), 2, "slot %s has more than one best fit across the cities" % slot)
	assert_gt(RigStudy.lines(study).size(), 3, "the study prints")


func test_the_study_makes_each_citys_tool_the_best_fit_in_that_city() -> void:
	var def: PlanetDefinition = Planets.by_id(FIRST)
	var r: Rigs = _rigs()
	var study: Dictionary = RigStudy.run(def)
	for kind: String in TOOL_KINDS:
		var tool: String = r.tool_for(kind)
		for city: Dictionary in study["cities"]:
			if str(city["id"]) == r.district_of(tool):
				assert_eq(str(city["best"].get(r.slot_of(tool), "")), tool, "%s in %s" % [tool, city["id"]])


func test_a_planet_with_no_rig_table_has_no_study() -> void:
	var study: Dictionary = RigStudy.run(Planets.by_id(DUMMY))
	assert_false(bool(study["ok"]))
	assert_ne(str(study["error"]), "")
