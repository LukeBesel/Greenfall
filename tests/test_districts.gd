extends GutTest
## Districts (systems/districts.gd): the cities of a planet as chapters. Hex sets from sites and
## rings, per-district stage and share, unlock rules, the player's district, the travel rule, and
## saving. Tests that can run on any planet take the planet id: the first planet (six cities from
## its table), the dummy planet and a parked planet (no table: one implicit district).

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PARKED: StringName = &"ochre"
const PLANETS: Array[StringName] = [FIRST, DUMMY, PARKED]
const OLD_SAVE: String = "res://tests/fixtures/saves/pre_districts_cells.json"
const OLD_SAVE_LEVEL: int = 5

var _fx: DistrictFixture


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func after_each() -> void:
	if _fx:
		_fx.free_systems()
	_fx = null


func _fixture(planet_id: StringName, with_systems: bool = true, level: int = DistrictFixture.LEVEL) -> DistrictFixture:
	_fx = DistrictFixture.new(planet_id, with_systems, level)
	return _fx


# --- Hex sets -----------------------------------------------------------------------------------

func test_a_region_of_r_rings_has_one_plus_3r_r_plus_1_hexes() -> void:
	var grid: SphereGrid = SphereGrid.cached(DistrictFixture.LEVEL)
	var centre: int = DistrictFixture.face_centre_cells(grid, 1)[0]
	for rings: int in [0, 1, 6, 9, 12, 16, 20, 26]:
		assert_eq(Districts.region_cells(grid, centre, rings).size(), Districts.hexes_for_rings(rings), "%d rings" % rings)
	assert_eq(Districts.hexes_for_rings(6), 127)
	assert_eq(Districts.hexes_for_rings(16), 817)


func test_the_first_planet_lists_six_cities_in_order_with_the_accepted_sizes() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	assert_eq(d.ids(), ["old_town", "scrapyard", "kettle_bay", "highreach", "lowmeadow", "old_capital"] as Array[String])
	var sites: Array[int] = []
	var rings: Array[int] = []
	var total: int = 0
	for id: String in d.ids():
		sites.append(d.site_of(id))
		rings.append(int(d.spec_of(id)["rings"]))
		assert_eq(d.cells_of(id).size(), Districts.hexes_for_rings(int(d.spec_of(id)["rings"])), "%s has every hex of its rings" % id)
		assert_eq(d.land_of(id), d.cells_of(id).size(), "%s: all land on the fixture globe" % id)
		assert_ne(d.name_of(id), "", "%s has a name" % id)
		assert_false((d.spec_of(id)["pollution"] as Array).is_empty(), "%s lists its pollution kinds" % id)
		total += d.cells_of(id).size()
	assert_eq(sites, [0, 7, 3, 8, 9, 1] as Array[int], "the six hub sites of the world audit")
	assert_eq(rings, [6, 9, 12, 16, 20, 26] as Array[int])
	assert_eq(total, 5052, "the accepted size of the six cities")
	assert_almost_eq(d.stage_share, 0.8, 0.0001)


func test_site_regions_take_their_size_from_the_planet(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var def: PlanetDefinition = Planets.by_id(planet_id)
	var specs: Array[Dictionary] = Districts.specs_for(def)
	assert_gt(specs.size(), 0, "every planet has at least one district")
	var by_site: Dictionary = {}
	for spec: Dictionary in specs:
		by_site[int(spec["site"])] = int(spec["rings"])
	var open_rings: int = int(def.table(Districts.TABLE).get("open_ground_rings", Districts.FALLBACK_RINGS))
	for site: int in def.hub_count:
		assert_eq(Districts.rings_for_site(def, site), int(by_site.get(site, open_rings)), "site %d" % site)


func test_site_manager_builds_its_regions_from_the_districts_table() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var globe := FakeGlobe.new()
	globe.grid = fx.grid
	globe.terrain = SphereTerrain.new(fx.grid, 7)
	globe.cells = fx.cells
	add_child_autofree(globe)
	var sites: Array[Dictionary] = []
	for c: int in fx.site_cells:
		sites.append({"cell": c, "transform": Transform3D(Basis(), fx.grid.centers[c]), "cells": PackedInt32Array()})
	var sm := SiteManager.new()
	globe.add_child(sm)
	sm.setup(globe, String(FIRST), sites)
	sm.set_process(false)
	for id: String in fx.districts.ids():
		var site: int = fx.districts.site_of(id)
		assert_eq(sm.rings_of(site), int(fx.districts.spec_of(id)["rings"]), id)
		assert_eq(Array(sm.regions[site]), Array(fx.districts.cells_of(id)), "%s: the manager's region is the district" % id)
	assert_eq(sm.rings_of(2), 18, "an open-ground site keeps the open-ground size")
	assert_eq(sm.regions[2].size(), Districts.hexes_for_rings(18))


# --- Stage and share ----------------------------------------------------------------------------

func test_stage_is_the_highest_stage_that_the_share_of_land_has_reached() -> void:
	# Ten land hexes, 80%: eight must have reached a stage.
	assert_eq(Districts.hexes_needed(PackedInt32Array([10, 0, 0, 0, 0, 0]), 0.8), 8)
	assert_eq(Districts.stage_from_counts(PackedInt32Array([10, 0, 0, 0, 0, 0]), 0.8), 0)
	assert_eq(Districts.stage_from_counts(PackedInt32Array([3, 7, 0, 0, 0, 0]), 0.8), 0, "seven of ten is short")
	assert_eq(Districts.stage_from_counts(PackedInt32Array([2, 8, 0, 0, 0, 0]), 0.8), 1, "eight of ten is the share")
	assert_eq(Districts.stage_from_counts(PackedInt32Array([2, 1, 0, 7, 0, 0]), 0.8), 1, "seven Growing: still Clean")
	assert_eq(Districts.stage_from_counts(PackedInt32Array([2, 0, 0, 4, 2, 2]), 0.8), 3, "higher stages count for lower ones")
	assert_eq(Districts.stage_from_counts(PackedInt32Array([0, 0, 0, 0, 2, 8]), 0.8), 5)
	assert_eq(Districts.stage_from_counts(PackedInt32Array([0, 0, 0, 0, 0, 0]), 0.8), 0, "no land: no stage")
	# 80% of 127 hexes is 101.6: 102 are needed.
	assert_eq(Districts.hexes_needed(PackedInt32Array([127, 0, 0, 0, 0, 0]), 0.8), 102)
	assert_eq(Districts.stage_from_counts(PackedInt32Array([26, 101, 0, 0, 0, 0]), 0.8), 0)
	assert_eq(Districts.stage_from_counts(PackedInt32Array([25, 102, 0, 0, 0, 0]), 0.8), 1)


func test_share_runs_from_zero_to_one_toward_the_next_stage() -> void:
	var share: float = 0.8
	assert_almost_eq(Districts.share_from_counts(PackedInt32Array([10, 0, 0, 0, 0, 0]), share, 0), 0.0, 0.0001)
	assert_almost_eq(Districts.share_from_counts(PackedInt32Array([6, 4, 0, 0, 0, 0]), share, 0), 0.5, 0.0001, "four of the eight needed")
	assert_almost_eq(Districts.share_from_counts(PackedInt32Array([2, 6, 2, 0, 0, 0]), share, 1), 0.25, 0.0001, "two Planted of eight")
	assert_almost_eq(Districts.share_from_counts(PackedInt32Array([0, 0, 0, 0, 0, 10]), share, 3), 1.0, 0.0001, "never over 1")
	assert_almost_eq(Districts.share_from_counts(PackedInt32Array([0, 0, 0, 0, 0, 10]), share, 5), 1.0, 0.0001, "the last stage is full")
	assert_almost_eq(Districts.share_from_counts(PackedInt32Array([0, 0, 0, 0, 0, 0]), share, 0), 0.0, 0.0001, "no land")


func test_a_district_follows_its_hexes_one_change_at_a_time(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	var d: Districts = fx.districts
	var id: String = d.ids()[0]
	var land: int = d.land_of(id)
	var need: int = ceili(d.stage_share * land - 0.000001)
	watch_signals(EventBus)
	assert_eq(d.stage_of(id), 0)
	assert_eq(d.count_at_least(id, 1), 0)
	fx.set_district_stage(id, 1, need - 1)
	assert_eq(d.count_at_least(id, 1), need - 1, "counted as the hexes change")
	assert_eq(d.stage_of(id), 0, "one hex short of the share")
	assert_almost_eq(d.share_of(id), float(need - 1) / float(need), 0.0001)
	assert_signal_not_emitted(EventBus, "district_stage_changed")
	fx.set_district_stage(id, 1, need)
	assert_eq(d.stage_of(id), 1, "the share is reached")
	assert_signal_emitted_with_parameters(EventBus, "district_stage_changed", [id, 1])
	assert_almost_eq(d.share_of(id), 0.0, 0.0001, "and the share starts again toward the next stage")
	fx.set_district_stage(id, 3, need)
	assert_eq(d.stage_of(id), 3)
	assert_eq(d.count_at_least(id, 3), need)
	assert_eq(d.land_of(id), land, "land does not change with stages")


func test_water_and_hub_ground_are_not_land() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	var own: PackedInt32Array = d.cells_of("old_town")
	var land: int = d.land_of("old_town")
	fx.cells.set_state(own[0], PlanetData.State.WATER)
	assert_eq(d.land_of("old_town"), land - 1, "a lake hex is not land")
	fx.cells.set_flag(own[1], SphereCells.F_HUB)
	assert_eq(d.land_of("old_town"), land - 2, "hub ground (the yard, under a building) is not land")
	fx.set_cell_stage(own[1], 5)
	assert_eq(d.count_at_least("old_town", 1), 0, "and never counts toward a stage")
	assert_eq(Districts.cell_stage(fx.cells, own[0]), Districts.NOT_LAND)
	assert_eq(d.district_of_cell(own[0]), "old_town", "it still belongs to the district")
	assert_eq(d.district_of_cell(-5), "")


func test_a_district_stage_never_drops_but_its_share_does() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	fx.set_district_stage("old_town", 2)
	assert_eq(d.stage_of("old_town"), 2)
	watch_signals(EventBus)
	fx.set_district_stage("old_town", 0, 60)  # dumped on again: 60 hexes dirty
	assert_eq(d.stage_of("old_town"), 2, "the stage it reached stays")
	assert_signal_not_emitted(EventBus, "district_stage_changed")
	assert_eq(d.count_at_least("old_town", 1), d.land_of("old_town") - 60, "the counts follow the ground")


# --- Unlocks ------------------------------------------------------------------------------------

func test_only_the_start_district_is_open_on_a_new_game(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var d: Districts = _fixture(planet_id).districts
	assert_eq(d.unlocked_count(), 1)
	assert_true(d.is_unlocked(d.ids()[0]))
	assert_true(d.is_visited(d.ids()[0]), "the player starts there")
	assert_eq(d.focus_id(), d.ids()[0], "the readout shows it before the player has moved")
	assert_eq(d.current_id(), "", "nobody has said where the player is yet")
	assert_eq(d.all_unlocked(), d.count() == 1)


func test_the_next_city_opens_when_the_current_one_is_sustained() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	watch_signals(EventBus)
	fx.set_district_stage("old_town", 3)
	assert_false(d.is_unlocked("scrapyard"), "Growing is not enough")
	assert_signal_not_emitted(EventBus, "district_unlocked")
	fx.set_district_stage("old_town", 4)
	assert_true(d.is_unlocked("scrapyard"), "stage 4 opens the next city")
	assert_signal_emit_count(EventBus, "district_unlocked", 1)
	assert_signal_emitted_with_parameters(EventBus, "district_unlocked", ["scrapyard"])
	assert_false(d.is_unlocked("kettle_bay"), "one city at a time")
	fx.set_district_stage("old_town", 5)
	assert_signal_emit_count(EventBus, "district_unlocked", 1, "never twice")
	# A later city worked on early does not skip the order.
	fx.set_district_stage("highreach", 5)
	assert_false(d.is_unlocked("kettle_bay"))
	assert_false(d.is_unlocked("lowmeadow"), "its rule asks for a city that is itself reached in order")
	fx.set_district_stage("scrapyard", 4)
	assert_true(d.is_unlocked("kettle_bay"))


func test_every_city_can_be_unlocked_in_order() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	var ids: Array[String] = d.ids()
	for i: int in ids.size() - 1:
		assert_false(d.is_unlocked(ids[i + 1]), "%s is locked until %s is sustained" % [ids[i + 1], ids[i]])
		fx.set_district_stage(ids[i], 4)
		assert_true(d.is_unlocked(ids[i + 1]))
	assert_true(d.all_unlocked())
	assert_eq(d.count_at_stage(4), 5)
	assert_eq(d.count_at_stage(5), 0)


# --- The player and travel ----------------------------------------------------------------------

func test_first_arrival_in_an_unlocked_city_is_announced_once() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	watch_signals(EventBus)
	d.set_player_cell(d.cells_of("old_town")[3])
	assert_eq(d.current_id(), "old_town")
	assert_signal_not_emitted(EventBus, "district_entered", "the city the game starts in is not an arrival")
	d.set_player_cell(d.cells_of("scrapyard")[0])
	assert_eq(d.current_id(), "scrapyard", "the districts know where the player stands")
	assert_eq(d.focus_id(), "old_town", "but a locked city is not the one the readout shows")
	assert_signal_not_emitted(EventBus, "district_entered")
	fx.set_district_stage("old_town", 4)
	assert_signal_emitted_with_parameters(EventBus, "district_entered", ["scrapyard"])
	assert_eq(d.focus_id(), "scrapyard", "it unlocked under the player's feet")
	d.set_player_cell(-1)
	assert_eq(d.current_id(), "")
	assert_eq(d.focus_id(), "scrapyard", "between cities the readout keeps the last one")
	d.set_player_cell(d.cells_of("old_town")[0])
	d.set_player_cell(d.cells_of("scrapyard")[5])
	assert_signal_emit_count(EventBus, "district_entered", 1, "only the first arrival")


func test_the_node_polls_the_player_cell() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	add_child(d)
	fx.set_district_stage("old_town", 4)
	var at: int = d.cells_of("scrapyard")[2]
	d.player_cell_fn = func() -> int: return at
	watch_signals(EventBus)
	d._process(Districts.POLL_S)
	assert_eq(d.current_id(), "scrapyard")
	assert_signal_emit_count(EventBus, "district_entered", 1)
	remove_child(d)


func test_the_rocket_is_offered_unlocked_cities_then_open_ground() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	var d: Districts = fx.districts
	var offered: Array[int] = []
	for site: int in fx.def.hub_count:
		if d.site_offered(site):
			offered.append(site)
	assert_eq(offered, [0] as Array[int], "a new game: only the first city")
	fx.set_district_stage("old_town", 4)
	assert_true(d.site_offered(7), "the second city's site")
	assert_false(d.site_offered(3))
	assert_false(d.site_offered(2), "open ground waits for every city")
	for id: String in d.ids():
		fx.set_district_stage(id, 4)
	for site: int in fx.def.hub_count:
		assert_true(d.site_offered(site), "site %d once every city is unlocked" % site)
	assert_eq(d.district_of_site(7), "scrapyard")
	assert_eq(d.district_of_site(2), "", "open ground")


func test_a_planet_without_a_table_is_one_district_and_open_ground(planet_id: StringName = use_parameters([DUMMY, PARKED])) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	var d: Districts = fx.districts
	assert_false(fx.def.has_table(Districts.TABLE))
	assert_eq(d.count(), 1)
	var id: String = d.ids()[0]
	assert_eq(id, String(planet_id))
	assert_eq(d.name_of(id), fx.def.display_name, "named after the planet")
	assert_eq(d.site_of(id), 0, "its start site")
	assert_eq(int(d.spec_of(id)["rings"]), Districts.FALLBACK_RINGS)
	assert_true(d.is_unlocked(id))
	assert_true(d.all_unlocked())
	for site: int in fx.def.hub_count:
		assert_true(d.site_offered(site), "every site is open to the rocket, as before districts")
	fx.set_district_stage(id, 5)
	assert_eq(d.stage_of(id), 5)


# --- Saving -------------------------------------------------------------------------------------

func test_state_survives_a_save_and_load(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var fx: DistrictFixture = _fixture(planet_id)
	var d: Districts = fx.districts
	var ids: Array[String] = d.ids()
	fx.set_district_stage(ids[0], 4)
	if ids.size() > 1:
		d.set_player_cell(d.cells_of(ids[1])[0])
		fx.set_district_stage(ids[1], 2, 30)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(d.save_state()))  # as a save file returns it
	var before: Dictionary = _snapshot(d)
	fx.free_systems()
	fx.build_systems()
	watch_signals(EventBus)
	fx.districts.load_state(saved)
	assert_eq(_snapshot(fx.districts), before)
	assert_signal_not_emitted(EventBus, "district_unlocked", "loading is silent")
	assert_signal_not_emitted(EventBus, "district_stage_changed")
	assert_signal_not_emitted(EventBus, "district_entered")


func test_a_saved_stage_outlives_ground_dirtied_since() -> void:
	var fx: DistrictFixture = _fixture(FIRST)
	fx.set_district_stage("old_town", 4)
	var saved: Dictionary = fx.districts.save_state()
	fx.set_district_stage("old_town", 0, 100)
	fx.free_systems()
	fx.build_systems()
	assert_eq(fx.districts.stage_of("old_town"), 0, "from the ground alone the city reads lower")
	fx.districts.load_state(saved)
	assert_eq(fx.districts.stage_of("old_town"), 4, "the save remembers the stage it reached")
	assert_true(fx.districts.is_unlocked("scrapyard"))


func test_an_old_save_without_district_state_derives_it_from_its_hexes() -> void:
	# The fixture is the cells section of a save written before districts existed: every Old Town
	# hex Sustained (stage 4), half of the second city cleaned, the rest of the globe untouched.
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OLD_SAVE))
	assert_false(file.has("districts"), "the old save has no district state")
	var fx: DistrictFixture = _fixture(FIRST, false, OLD_SAVE_LEVEL)
	assert_true(fx.cells.apply_dict(file["cells"]), "the fixture's cells load")
	watch_signals(EventBus)
	fx.build_systems()
	var d: Districts = fx.districts
	d.load_state(file.get("districts", {}))
	assert_eq(d.stage_of("old_town"), 4)
	assert_true(d.is_unlocked("scrapyard"), "unlocked by the rule")
	assert_true(d.is_visited("scrapyard"), "the player had cleaned there: not a first arrival")
	assert_eq(d.stage_of("scrapyard"), 0)
	assert_almost_eq(d.share_of("scrapyard"), 0.5 / d.stage_share, 0.02, "half its land is clean")
	assert_false(d.is_unlocked("kettle_bay"))
	assert_false(d.is_visited("kettle_bay"))
	assert_signal_not_emitted(EventBus, "district_unlocked", "deriving is silent")
	assert_signal_not_emitted(EventBus, "district_stage_changed")
	fx.restoration.load_state(file.get("restoration", {}))
	assert_false(fx.restoration.is_launched())
	assert_gt(fx.restoration.launch_value(), 0.0)


func _snapshot(d: Districts) -> Dictionary:
	var out: Dictionary = {"focus": d.focus_id()}
	for id: String in d.ids():
		out[id] = [d.stage_of(id), snappedf(d.share_of(id), 0.0001), d.is_unlocked(id), d.is_visited(id), d.land_of(id)]
	return out


class FakeGlobe:
	extends Node3D
	var grid: SphereGrid
	var terrain: SphereTerrain
	var cells: SphereCells
	var field: Variant = null
	var lumi: Node3D = null
