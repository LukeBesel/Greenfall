extends GutTest
## [late] Cradle Mode (systems/cradle_mode.gd, systems/world_gen.gd, data/cradle.json): prestige
## math, Heirloom costs and effects, world generation variety, and the multi-world profile
## (new world, travel back, persistence). Runs in its own save dir; the profile is not written.

var _keep: Array
var _profile: Dictionary
var _dir: String
var _slot: int


func before_each() -> void:
	_keep = [GameState.currencies.duplicate(), GameState.flags.duplicate(true), GameState.stats.duplicate(true), GameState.world,
		GameState.districts, GameState.current_hub, Economy.planet.get("name", "Verdance")]
	_profile = CradleMode.profile.duplicate(true)
	_dir = SaveManager.dev_dir
	_slot = SaveManager.slot
	SaveManager.dev_dir = "late_test"
	DirAccess.make_dir_recursive_absolute(SaveManager.save_dir())
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	GameState.current_hub = 0


func after_each() -> void:
	for s: int in 12:
		SaveManager.delete_save(s)
	SaveManager.dev_dir = _dir
	SaveManager.slot = _slot
	CradleMode.profile = _profile
	GameState.currencies = _keep[0]
	GameState.flags = _keep[1]
	GameState.stats = _keep[2]
	GameState.world = _keep[3]
	GameState.districts = _keep[4]
	GameState.current_hub = _keep[5]
	Economy.planet["name"] = _keep[6]


# --- Prestige -----------------------------------------------------------------------------

func test_prestige_earned_adds_up_each_source() -> void:
	var c: Dictionary = WorldGen.cfg()["prestige"]
	assert_eq(CradleMode.prestige_earned({}), 0)
	assert_eq(CradleMode.prestige_earned({"ark_waves": 3}), int(3 * float(c["per_ark_wave"])))
	assert_eq(CradleMode.prestige_earned({"cradle": true}), int(c["cradle_bonus"]))
	assert_eq(CradleMode.prestige_earned({"thriving": 400}), int(floor(20.0 * float(c["per_sqrt_thriving"]))))
	var full: Dictionary = {"ark_waves": 2, "bloom_milestones": 4, "thriving": 100, "cradle": true, "bases_l5": 5}
	var want: float = 2 * float(c["per_ark_wave"]) + 4 * float(c["per_bloom_milestone"]) + 10.0 * float(c["per_sqrt_thriving"]) \
		+ float(c["cradle_bonus"]) + 5 * float(c["per_base_l5"])
	assert_eq(CradleMode.prestige_earned(full), int(floor(want)))
	assert_gt(CradleMode.prestige_earned({"ark_waves": 4}), CradleMode.prestige_earned({"ark_waves": 3}), "more waves, more Starseeds")


func test_bank_pays_only_what_is_new() -> void:
	GameState.stats["ark_waves"] = 2.0
	GameState.flags["cradle_returned"] = true
	var first: int = CradleMode.bank()
	assert_gt(first, 0)
	assert_eq(int(CradleMode.starseeds()), first)
	assert_eq(CradleMode.bank(), 0, "banking twice pays nothing more")
	GameState.stats["ark_waves"] = 3.0
	assert_eq(CradleMode.bank(), int(WorldGen.cfg()["prestige"]["per_ark_wave"]), "one more wave pays one wave")
	assert_eq(CradleMode.claimable({"ark_waves": 1}, 999), 0, "never negative")


# --- Heirlooms ----------------------------------------------------------------------------

func test_heirloom_costs_grow_and_buying_spends_starseeds() -> void:
	var d: Dictionary = CradleMode.heirloom_def("green_thumb")
	assert_false(d.is_empty())
	var c0: int = CradleMode.heirloom_cost(d, 0)
	var c1: int = CradleMode.heirloom_cost(d, 1)
	assert_eq(c0, int(d["cost"]))
	assert_gt(c1, c0)
	assert_false(CradleMode.buy("green_thumb"), "can't buy with no Starseeds")
	CradleMode.profile["starseeds"] = float(c0 + c1)
	assert_true(CradleMode.buy("green_thumb"))
	assert_true(CradleMode.buy("green_thumb"))
	assert_eq(CradleMode.heirloom_level("green_thumb"), 2)
	assert_almost_eq(CradleMode.starseeds(), 0.0, 0.001)
	assert_eq(int(GameState.stats["heirloom_levels"]), 2, "mirrored for goals and achievements")


func test_heirlooms_cap_at_max() -> void:
	var d: Dictionary = CradleMode.heirloom_def("archivist")
	CradleMode.profile["starseeds"] = 99999.0
	for i: int in int(d["max"]) + 2:
		CradleMode.buy("archivist")
	assert_eq(CradleMode.heirloom_level("archivist"), int(d["max"]))
	assert_ne(CradleMode.buy_block_reason("archivist"), "")


func test_heirloom_and_modifier_stat_multipliers() -> void:
	assert_almost_eq(CradleMode.heirloom_mult("plant_growth", {}), 1.0, 0.0001)
	assert_almost_eq(CradleMode.heirloom_mult("plant_growth", {"green_thumb": 2}), 1.16, 0.0001)
	assert_almost_eq(CradleMode.heirloom_mult("capacity", {"green_thumb": 2}), 1.0, 0.0001, "only its own stat")
	assert_almost_eq(CradleMode.mod_mult("cube_value_mult", ["rich_salvage"]), 1.3, 0.0001)
	assert_almost_eq(CradleMode.mod_mult("cube_value_mult", ["rich_salvage", "long_nights"]), 1.43, 0.0001)
	# Through Economy.stat: Verdance with no Heirlooms is untouched; Heirlooms apply everywhere.
	var base: float = Economy.stat("scoop_rate")
	(CradleMode.profile["heirlooms"] as Dictionary)["quick_beam"] = 2
	assert_almost_eq(Economy.stat("scoop_rate"), base * 1.16, 0.0001)


func test_start_kit_from_heirloom_levels() -> void:
	var kit: Dictionary = CradleMode.start_kit({"head_start": 2, "old_crew": 2, "archivist": 1, "seed_vault": 1, "data_cache": 3})
	assert_almost_eq(float(kit["cubes"]), 3000.0, 0.01)
	assert_almost_eq(float(kit["data"]), 180.0, 0.01)
	assert_true(bool(kit["seeds_unlocked"]))
	assert_eq((kit["robots"] as Array).size(), 2)
	assert_eq(int(kit["research_tier"]), 1)
	var none: Dictionary = CradleMode.start_kit({})
	assert_eq(float(none["cubes"]), 0.0)
	assert_true((none["robots"] as Array).is_empty())


func test_long_nights_slow_only_the_night() -> void:
	(CradleMode.current_world())["modifiers"] = ["long_nights"]
	assert_almost_eq(CradleMode.day_speed(0.5), 1.0, 0.0001)
	assert_almost_eq(CradleMode.day_speed(0.05), 0.5, 0.0001)
	(CradleMode.current_world())["modifiers"] = ["heavy_rain"]
	assert_almost_eq(CradleMode.event_weight("rain_shower"), 4.0, 0.0001)
	assert_almost_eq(CradleMode.event_weight("supply_drop"), 1.0, 0.0001)


# --- World generation ---------------------------------------------------------------------

func test_world_zero_is_verdance_exactly() -> void:
	var w: Dictionary = WorldGen.make(0)
	assert_eq(str(w["name"]), "Verdance")
	assert_eq(int(w["seed"]), 4471)
	assert_true((w["mix"] as Dictionary).is_empty())
	assert_true((w["modifiers"] as Array).is_empty())
	assert_eq(CradleMode.world_seed(), int(Economy.planet["slice_field"]["seed"]), "the campaign seed is unchanged")


func test_new_worlds_differ_and_are_deterministic() -> void:
	var names: Dictionary = {}
	var types: Dictionary = {}
	for i: int in range(1, 5):
		var w: Dictionary = WorldGen.make(i)
		names[str(w["name"])] = true
		types[str(w["type"])] = true
		assert_eq((w["modifiers"] as Array).size(), 2, "two twists per world")
		assert_ne((w["modifiers"] as Array)[0], (w["modifiers"] as Array)[1])
		assert_ne(int(w["seed"]), 4471)
		assert_eq(JSON.stringify(WorldGen.make(i)), JSON.stringify(w), "same index and seed, same world")
	assert_eq(types.size(), 4, "the first four new worlds are four different types")
	assert_gt(names.size(), 2, "and mostly different names")


func test_world_types_change_the_biome_mix() -> void:
	var share: Dictionary = {}
	for tid: String in ["verdance", "ice_moon", "desert_world", "ocean_world"]:
		var p := PlanetData.new(4471 + 17, 4, 10.0)
		p.mix = WorldGen.world_type(tid).get("mix", {})
		p.generate()
		var h: Dictionary = WorldGen.biome_histogram(p)
		var n: float = float(p.cell_count())
		share[tid] = {"frost": float(h.get("frostcap", 0)) / n, "dust": float(h.get("dust_dunes", 0)) / n, "lake": float(h.get("lake", 0)) / n}
	assert_gt(share["ice_moon"]["frost"], share["verdance"]["frost"] * 2.0, "an ice moon is mostly frost")
	assert_gt(share["desert_world"]["dust"], share["verdance"]["dust"] * 1.5, "a desert world is mostly dunes")
	assert_lt(share["desert_world"]["lake"], share["verdance"]["lake"], "and dry")
	assert_gt(share["ocean_world"]["lake"], share["verdance"]["lake"] * 1.6, "an ocean world is mostly water")


func test_new_world_towns_have_new_names() -> void:
	var p := PlanetData.new(WorldGen.seed_for(1), 4, 10.0)
	p.mix = WorldGen.make(1)["mix"]
	p.generate(0.25, 8)
	var names: Array = (WorldGen.make(1)["mix"] as Dictionary)["city_names"]
	assert_true(str(p.cities[0]["name"]) in names)
	assert_ne(str(p.cities[0]["name"]), "Old Town")


# --- Multi-world profile ------------------------------------------------------------------

func test_launch_a_new_world_then_travel_back() -> void:
	GameState.flags["achievements"] = {"hex_1": 1.0}
	GameState.flags["bloom_finale_seen"] = true
	GameState.stats["ark_waves"] = 4.0
	GameState.add_currency("cubes", BigNum.from_float(123456))
	SaveManager.slot = 0
	SaveManager.enabled = true
	assert_true(SaveManager.write_dict(SaveManager.slot_path(0), GameState.to_dict()), "Verdance saved in slot 0")
	(CradleMode.profile["heirlooms"] as Dictionary)["head_start"] = 1
	var w: Dictionary = CradleMode.launch_new_world()
	assert_eq(CradleMode.worlds().size(), 2)
	assert_eq(CradleMode.current_index(), 1)
	assert_ne(SaveManager.slot, 0, "a new world gets its own slot")
	assert_eq(str(Economy.planet["name"]), str(w["name"]))
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 1500.0, 0.01, "fresh world: only the Head Start kit")
	assert_eq(JSON.stringify(GameState.flags.get("achievements")), JSON.stringify({"hex_1": 1.0}), "achievements carry over")
	assert_false(GameState.flags.has("bloom_finale_seen"), "the new world's story starts over")
	assert_true(CradleMode.unlocked(), "but Cradle Mode stays open (profile)")
	assert_gt(int(CradleMode.worlds()[0]["claimed"]), 0, "Verdance banked its Starseeds on leaving")
	assert_eq(int(GameState.stats["worlds_seeded"]), 1)
	# Back to Verdance: its save comes back as it was.
	assert_true(CradleMode.switch_world(0))
	assert_eq(SaveManager.slot, 0)
	assert_almost_eq(GameState.get_currency("cubes").to_float(), 123456.0, 0.01)
	assert_eq(str(Economy.planet["name"]), "Verdance")
	assert_true(GameState.reload_in_memory)
	GameState.reload_in_memory = false


func test_profile_round_trips_through_its_dict() -> void:
	CradleMode.profile["starseeds"] = 42.0
	(CradleMode.profile["heirlooms"] as Dictionary)["deep_hopper"] = 3
	CradleMode._add_world()
	CradleMode.profile["current"] = 1
	var back: Dictionary = CradleMode.from_dict(JSON.parse_string(JSON.stringify(CradleMode.to_dict())))
	assert_eq(int(back["current"]), 1)
	assert_almost_eq(float(back["starseeds"]), 42.0, 0.001)
	assert_eq(int(back["heirlooms"]["deep_hopper"]), 3)
	assert_eq((back["worlds"] as Array).size(), 2)
	assert_eq(int(back["worlds"][1]["seed"]), int(CradleMode.worlds()[1]["seed"]))
	assert_eq(CradleMode.from_dict({})["worlds"].size(), 1, "an empty file is just Verdance")
	assert_eq(int(CradleMode.from_dict({"current": 9, "worlds": [{"index": 0, "seed": 4471, "slot": 0}]})["current"]), 0, "current is clamped")


func test_new_world_landing_town_is_dry() -> void:
	for i: int in [1, 3]:  # ice moon, ocean world
		var w: Dictionary = WorldGen.make(i)
		var p := PlanetData.new(int(w["seed"]), 6, 10.0)
		p.mix = w["mix"]
		p.generate()
		var wet: int = 0
		var cells: Array[int] = p.cells_within(p.hubs[0], 6)
		for c: int in cells:
			if p.state[c] == PlanetData.State.WATER:
				wet += 1
		assert_lt(float(wet) / cells.size(), 0.2, "%s lands in a dry town (%d / %d wet)" % [w["type"], wet, cells.size()])
		assert_true(p.city[p.hubs[0]] >= 0, "hub 0 is a town")
