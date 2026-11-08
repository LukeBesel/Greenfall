extends GutTest
## [home] Homeward (systems/homeward.gd, data/homeward.json) and the binary suns
## (systems/solar_system.gd): planet restoration math, the system %, charts and drive gates,
## relics and Heirloom picks, fixed planet worlds in the profile, the finale redirect rule and the
## companion sun's geometry. The profile is kept in memory (not written).

var _keep: Array
var _profile: Dictionary


func before_each() -> void:
	_keep = [GameState.currencies.duplicate(), GameState.flags.duplicate(true), GameState.stats.duplicate(true), GameState.world,
		GameState.districts, GameState.current_hub, SaveManager.slot, Economy.planet.get("name", "Verdance")]
	_profile = CradleMode.profile.duplicate(true)
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	GameState.current_hub = 0


func after_each() -> void:
	CradleMode.profile = _profile
	GameState.currencies = _keep[0]
	GameState.flags = _keep[1]
	GameState.stats = _keep[2]
	GameState.world = _keep[3]
	GameState.districts = _keep[4]
	GameState.current_hub = _keep[5]
	SaveManager.slot = _keep[6]
	Economy.planet["name"] = _keep[7]


func test_five_fixed_planets_in_order() -> void:
	var ids: Array = []
	for d: Dictionary in Homeward.planets():
		ids.append(str(d["id"]))
	assert_eq(ids, ["verdance", "ochre", "tidewell", "rime", "anvil"])
	assert_eq(int(Homeward.planet_def(0)["seed"]), WorldGen.VERDANCE_SEED, "Verdance keeps its seed")
	for k: int in range(1, 5):
		var d: Dictionary = Homeward.planet_def(k)
		assert_false(WorldGen.world_type(str(d["type"])).is_empty(), "%s uses a real world type" % d["id"])
		assert_false(Homeward.relic_def(str(d["relic"])).is_empty(), "%s has a relic" % d["id"])
		assert_true(SolarSystem.cfg().get("planets", {}).has(str(d["id"])), "%s is in the solar system file" % d["id"])


func test_planet_pct_weights_and_cap() -> void:
	var d: Dictionary = Homeward.planet_def(1)  # Ochre: 110 thriving, 1 base
	assert_almost_eq(Homeward.planet_pct(d, 0, 0, 0.0), 0.0, 0.0001)
	assert_almost_eq(Homeward.planet_pct(d, 55, 0, 0.0), 0.25, 0.0001, "half the thriving target = half of 0.5")
	assert_almost_eq(Homeward.planet_pct(d, 110, 1, 0.6), 1.0, 0.0001)
	assert_almost_eq(Homeward.planet_pct(d, 999, 9, 1.0), 1.0, 0.0001, "capped at 100%")
	assert_almost_eq(Homeward.system_pct_of([1.0, 1.0, 0.5, 0.0, 0.0]), 0.5, 0.0001)


func test_store_never_drops_and_restoring_gives_relic_and_pick() -> void:
	CradleMode.profile["worlds"].append({"index": 1, "planet": "ochre", "seed": 51207, "name": "Ochre", "type": "desert_world", "slot": 1})
	CradleMode.profile["current"] = 1
	assert_eq(Homeward.current_planet(), 1)
	assert_eq(Homeward.store_current(0.4), [] as Array[int])
	Homeward.store_current(0.2)
	assert_almost_eq(Homeward.stored_pct(1), 0.4, 0.0001, "never drops")
	assert_eq(Homeward.store_current(1.0), [1] as Array[int])
	assert_true("ochre_glass" in Homeward.relics())
	assert_eq(Homeward.picks(), 1)
	assert_eq(Homeward.store_current(1.0), [] as Array[int], "only once")
	assert_eq(int(GameState.stats["planets_restored"]), 1)


func test_verdance_pct_is_the_bloom_core() -> void:
	GameState.flags["core_charge"] = 0.42
	assert_almost_eq(Homeward.measure_current(), 0.42, 0.0001)
	GameState.flags["cradle_returned"] = true
	assert_almost_eq(Homeward.measure_current(), 1.0, 0.0001)


func test_reach_needs_drive_and_chart() -> void:
	var pcts: Array = [1.0, 0.0, 0.0, 0.0, 0.0]
	assert_ne(Homeward.reach_blocker(1, 0, pcts), "", "no drive")
	assert_eq(Homeward.reach_blocker(1, 5, pcts), "", "Mk V reaches Ochre")
	assert_ne(Homeward.reach_blocker(2, 5, pcts), "", "Tidewell needs Ochre's chart")
	pcts[1] = 0.5
	assert_eq(Homeward.reach_blocker(2, 5, pcts), "")
	pcts[2] = 0.6
	assert_ne(Homeward.reach_blocker(3, 5, pcts), "", "Rime needs Mk VI")
	assert_eq(Homeward.reach_blocker(3, 6, pcts), "")


func test_drive_gates_and_costs() -> void:
	assert_ne(Homeward.drive_blocker(), "", "Mk V waits for the Cradle's answer")
	Homeward.state()["answered"] = true
	assert_string_contains(Homeward.drive_blocker(), "cubes")
	GameState.add_currency("cubes", BigNum.from_float(5.0e6))
	GameState.add_currency("parts", BigNum.from_float(1000))
	assert_eq(Homeward.drive_blocker(), "")
	assert_true(Homeward.buy_drive())
	assert_eq(Homeward.drive(), 5)
	assert_ne(Homeward.drive_blocker(), "", "Mk VI needs a relic")
	Homeward.relics().append("ochre_glass")
	assert_eq(Homeward.drive_blocker(), "")
	assert_true(Homeward.buy_drive())
	assert_eq(Homeward.drive(), 6)
	for r: String in ["tidewell_pearl", "rime_core", "anvil_ingot"]:
		Homeward.relics().append(r)
	GameState.add_currency("cubes", BigNum.from_float(1.0e7))
	GameState.add_currency("parts", BigNum.from_float(3000))
	assert_ne(Homeward.drive_blocker(true), "", "Mk VII needs the whole system")
	for d: Dictionary in Homeward.planets():
		(Homeward.state()["pct"] as Dictionary)[str(d["id"])] = 1.0
	assert_ne(Homeward.drive_blocker(false), "", "only at the Homeward complex")
	assert_eq(Homeward.drive_blocker(true), "")


func test_planet_world_keeps_its_type_and_seed() -> void:
	var w: Dictionary = Homeward.make_planet_world(3)
	assert_eq(str(w["name"]), "Rime")
	assert_eq(int(w["seed"]), int(Homeward.planet_def(3)["seed"]))
	CradleMode.profile["current"] = CradleMode.worlds().size() - 1
	assert_eq(Homeward.current_planet(), 3)
	assert_eq(Homeward.world_of(3), CradleMode.worlds().size() - 1)
	assert_almost_eq(float(CradleMode.planet_mix().get("frost_lat", 0.0)), float(WorldGen.world_type("ice_moon")["mix"]["frost_lat"]), 0.0001,
		"the fixed type's mix, not the index cycle")
	assert_eq(CradleMode.modifiers(), Homeward.planet_def(3)["mods"])


func test_profile_keeps_homeward_through_from_dict() -> void:
	Homeward.state()["drive"] = 6
	Homeward.relics().append("rime_core")
	var p: Dictionary = CradleMode.from_dict(JSON.parse_string(JSON.stringify(CradleMode.to_dict())))
	assert_eq(int(p["homeward"]["drive"]), 6)
	assert_eq(p["homeward"]["relics"], ["rime_core"])


func test_picks_buy_heirlooms_without_starseeds() -> void:
	assert_ne(CradleMode.buy_block_reason("green_thumb"), "", "no Starseeds, no picks")
	Homeward.state()["picks"] = 1
	assert_eq(CradleMode.buy_block_reason("green_thumb"), "")
	assert_true(CradleMode.buy("green_thumb"))
	assert_eq(CradleMode.heirloom_level("green_thumb"), 1)
	assert_eq(Homeward.picks(), 0)
	assert_almost_eq(CradleMode.starseeds(), 0.0, 0.0001)


func test_finale_redirect_rule() -> void:
	Homeward.state()["answered"] = true
	assert_true(Homeward.redirect_finale(null, false), "before the ending the Cradle finale never plays")
	Homeward.state()["done"] = true
	assert_false(Homeward.redirect_finale(null, false), "after Homecoming every world keeps its finale")


func test_binary_suns_scale_with_distance() -> void:
	var v: Dictionary = SolarSystem.suns_for("verdance", Vector3(0, 1, -1).normalized())
	var o: Dictionary = SolarSystem.suns_for("ochre", Vector3(0, 1, -1).normalized())
	var r: Dictionary = SolarSystem.suns_for("rime", Vector3(0, 1, -1).normalized())
	assert_gt(float(o["a"]["size"]), float(v["a"]["size"]), "Ochre is closest: bigger suns")
	assert_lt(float(r["a"]["size"]), float(v["a"]["size"]), "Rime is farthest: small suns")
	assert_lt(float(r["a"]["energy"]), float(v["a"]["energy"]))
	assert_lt(float(v["b"]["size"]), float(v["a"]["size"]), "the companion is smaller")
	for d: Dictionary in [v, o, r]:
		var sep: float = rad_to_deg((d["a"]["dir"] as Vector3).angle_to(d["b"]["dir"]))
		assert_gt(sep, 3.0, "two distinct suns")
		assert_lt(sep, 25.0, "close enough to rise and set together")
	var vs: float = rad_to_deg((v["a"]["dir"] as Vector3).angle_to(v["b"]["dir"]))
	assert_almost_eq(vs, float(SolarSystem.planet("verdance")["sep_deg"]), 0.5)


func test_rocket_targets_are_out_of_hub_range() -> void:
	assert_lt(Homeward.PLANET_BASE - 4, Homeward.PLANET_BASE + 1)
	assert_lt(Homeward.HOME, Homeward.PLANET_BASE - Homeward.planets().size())
	assert_false(HomewardDirector.travel(null, 3), "ordinary hub hops are untouched")


func test_score_track_waits_for_the_ending() -> void:
	GameState.stats["ark_waves"] = 2.0
	GameState.flags["cradle_returned"] = true
	assert_gt(CradleMode.bank(), 0)
	assert_almost_eq(float(CradleMode.profile.get("starseeds_total", 0.0)), 0.0, 0.0001, "no score during the campaign: planet picks instead")
	Homeward.state()["done"] = true
	GameState.stats["ark_waves"] = 4.0
	assert_gt(CradleMode.bank(), 0)
	assert_gt(float(CradleMode.profile.get("starseeds_total", 0.0)), 0.0, "post-game: the score track runs")
