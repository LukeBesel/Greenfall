extends GutTest
## [v7planet] A new planet is data (docs/NEW_PLANET.md): every planet in data/planets.json has the
## blocks it needs (PlanetCfg.problems), the "_default" blocks give Verdance exactly what it had,
## and the dev planet "testworld" stays out of the campaign.

var _cur: String
var _active: String


func before_each() -> void:
	_cur = PlanetCfg.current
	_active = HubPlan.active_planet
	HubPlan.reload()
	SoundCfg._cfg = {}


func after_each() -> void:
	PlanetCfg.current = _cur
	HubPlan.active_planet = _active
	LifeCfg.use_planet(_cur if _cur != "" else "verdance")
	HubPlan.reload()


func _raw(id: String) -> Dictionary:
	return Economy.read_json("res://data/planets.json").get(id, {})


func test_every_planet_has_its_blocks() -> void:
	var ids: Array[String] = PlanetCfg.ids(true)
	assert_true(ids.has("verdance") and ids.has("testworld"), "planets listed: %s" % [ids])
	for id: String in ids:
		var bad: Array[String] = PlanetCfg.problems(id)
		assert_eq(bad, [] as Array[String], "%s: %s" % [id, bad])


func test_a_missing_block_is_reported() -> void:
	var all: Dictionary = PlanetEnvs.all()
	all["zz_broken"] = {"globe": {"frequency": 32}, "hubs": [{"site": 0, "order": 1, "id": "a", "home": true, "name": "A", "town": "moon", "landmark": {"kind": "statue"}}, {"site": 12, "order": 1, "id": "b", "name": "B"}]}
	var bad: Array[String] = PlanetCfg.problems("zz_broken")
	all.erase("zz_broken")
	var text: String = "\n".join(bad)
	for want: String in ["no name", "hub_count", "town 'moon'", "landmark 'statue'", "site 12 is outside", "order 1 used twice", "data/homeward.json"]:
		assert_true(text.contains(want), "reports '%s' in:\n%s" % [want, text])


func test_every_campaign_planet_has_a_data_block() -> void:
	for p: Dictionary in Homeward.planets():
		assert_true(PlanetCfg.has(str(p["id"])), "data/homeward.json planet %s has a data/planets.json block" % p["id"])


func test_verdance_unchanged_by_the_defaults() -> void:
	var raw: Dictionary = _raw("verdance")
	var hd: Dictionary = HubPlan.defaults("verdance")
	for k: String in (raw["hub_defaults"] as Dictionary):
		assert_eq(hd.get(k), raw["hub_defaults"][k], "hub_defaults.%s" % k)
	var g: Dictionary = GlobeSpec.of("verdance")
	assert_eq(int(g["frequency"]), 128)
	assert_eq(int(g["hub_count"]), 10)
	assert_false(g.has("seed"), "no seed key: the slice's 4471 stands")
	assert_true(PlanetCfg.uses_towns("verdance") and PlanetCfg.uses_towns(""), "Verdance builds towns")
	assert_true(PlanetCfg.has_hinterland("verdance"))
	assert_eq(SiteBuilders.site_for_hub("verdance", 0), "start_yard")
	assert_eq(SiteBuilders.site_for_hub("verdance", 3), "ruin_block")
	var snd: Dictionary = (Economy.read_json("res://data/sound.json")["planets"] as Dictionary)["verdance"]
	assert_eq(SoundCfg.planet("verdance"), snd, "Verdance's sound block as it is")
	var lg: Dictionary = PlanetCfg.look("verdance").get("ground", {})
	for k: String in ["dirt", "clean", "grass"]:
		assert_eq(lg.get(k), [1.0, 1.0, 1.0], "Verdance's ground %s tint is 1" % k)


func test_prefab_planets_keep_their_sites() -> void:
	for id: String in ["rime", "ochre", "tidewell", "anvil"]:
		assert_eq(PlanetCfg.site_kit(id), "prefab", id)
		assert_false(PlanetCfg.has_hinterland(id), id)
		assert_false(SiteBuilders.sites_of(id).is_empty(), "%s lists its site prefabs" % id)


func test_testworld_is_data_only_and_dev_only() -> void:
	assert_true(PlanetCfg.is_dev("testworld"))
	assert_false(PlanetCfg.ids().has("testworld"), "not in the player's planet list")
	assert_eq(Homeward.planet_index("testworld"), -1, "not in the campaign")
	var g: Dictionary = GlobeSpec.of("testworld")
	assert_eq(int(g["frequency"]), 64)
	assert_eq(int(g["hub_count"]), 2)
	assert_lt(GlobeSize.radius_m("testworld"), GlobeSize.radius_m("verdance"), "smaller than Verdance")
	assert_gt(GlobeSize.radius_m("anvil"), GlobeSize.radius_m("verdance"), "Anvil is larger")
	assert_true(PlanetCfg.uses_towns("testworld"))
	assert_eq(SiteBuilders.site_for_hub("testworld", 1), "ruin_block")
	assert_eq(HubPlan.main_total("testworld"), 2)
	assert_eq(int(HubPlan.defaults("testworld")["clean_hexes"]), 4, "its own override")
	assert_eq(float(HubPlan.defaults("testworld")["hop"]["leg_s"]), 2.8, "the rest from _default")
	assert_eq(HubPlan.landmark_kind("testworld", 0), "radio_mast")
	assert_eq(SoundCfg.theme_of("testworld"), "ochre", "its own score")
	assert_true(SoundCfg.ambience("testworld").has("life"), "Verdance's life bed through like")
	assert_eq(str(HubLandmarks.kind_cfg("radio_mast", "testworld")["main"]), "orange", "its own landmark colour")


func test_unknown_planet_falls_back() -> void:
	assert_eq(SoundCfg.theme_of("no_such_planet"), "", "an id that is no planet has no sound block (Audio ignores it)")
	var all: Dictionary = PlanetEnvs.all()
	all["zz_quiet"] = {"name": "Quiet"}
	assert_eq(SoundCfg.theme_of("zz_quiet"), "verdance", "a planet with no sound block sounds like Verdance (planets._default)")
	all.erase("zz_quiet")
	assert_eq(int(GlobeSpec.of("no_such_planet")["frequency"]), 128)
	assert_true(PlanetCfg.uses_towns("no_such_planet"))


func test_use_planet_points_the_lookups() -> void:
	PlanetCfg.use_planet("testworld")
	assert_eq(LifeCfg.planet_id, "testworld")
	assert_eq(HubPlan.active_planet, "testworld")
	assert_eq(SkyDirector.current_planet_id(), "testworld")
	assert_eq(LifeCfg.num("ground", "grow_s", 0.0), 120.0, "data/life.json testworld block")
	assert_eq(HubPlan.hop_cfg("leg_s", 0.0), 2.8)


## [v7planet] The card's hub steps come from the planet's own hubs[] (story/planet_steps.gd).
func test_hub_steps_per_planet() -> void:
	var obj: Array = Economy.read_json("res://data/objectives.json").get("objectives", [])
	var gls: Array = Economy.read_json("res://data/goals.json").get("goals", [])
	assert_false(PlanetSteps.generated("verdance"), "Verdance keeps the shared steps")
	assert_eq(PlanetSteps.objectives(obj, "verdance"), obj, "Verdance's objectives as they are")
	assert_eq(PlanetSteps.goals(gls, "verdance"), gls, "Verdance's goals as they are")
	# Testworld: two hubs, so one fly and one wake, where the shared hub steps stood.
	var tw: Array = PlanetSteps.objectives(obj, "testworld")
	var ids: Array = tw.filter(func(d: Dictionary) -> bool: return PlanetSteps.is_hub_step(d)).map(func(d: Dictionary) -> String: return str(d["id"]))
	assert_eq(ids, ["hub_fly_2", "hub_wake_2"])
	var first: int = obj.find(obj.filter(func(d: Dictionary) -> bool: return PlanetSteps.is_hub_step(d))[0])
	assert_eq(str(tw[first]["id"]), "hub_fly_2", "in the place of the first shared hub step")
	assert_eq(tw.size(), obj.size() - 7 + 2)
	assert_eq(PlanetSteps.goals(gls, "testworld").filter(func(d: Dictionary) -> bool: return PlanetSteps.is_hub_step(d)), [], "no shared hub goals")
	assert_eq(Objectives.step_why(tw[first]), "The second test hub.", "the fly step's why is the hub's own")
	# An 8-hub planet: rocket tiers where Mk I (3 hubs) and Mk II (5) run out.
	var all: Dictionary = PlanetEnvs.all()
	var hubs: Array = [{"site": 0, "order": 1, "id": "h0", "home": true, "name": "H0", "town": "suburb", "landmark": {"kind": "radio_mast"}}]
	for i: int in range(1, 8):
		hubs.append({"site": i, "order": i + 1, "id": "h%d" % i, "name": "H%d" % i, "town": "oldtown", "landmark": {"kind": "crane"}, "reason": "Why %d" % i})
	var e8: Dictionary = {"name": "Eight", "globe": {"frequency": 64, "hub_count": 8}, "hub_defaults": {"main_path": 8}, "hubs": hubs}
	all["zz_eight"] = e8
	HubPlan.reload()
	HubPlan.planet_data("verdance")
	HubPlan._data["zz_eight"] = e8
	var eight: Array = PlanetSteps.steps_for("zz_eight").map(func(d: Dictionary) -> String: return "%s>%d" % [d["id"], int(d["target"])])
	HubPlan._data.erase("zz_eight")
	all.erase("zz_eight")
	HubPlan.reload()
	assert_eq(eight, ["hub_fly_2>1", "hub_wake_2>1", "hub_fly_3>2", "hub_wake_3>2", "rocket_tier_2>2", "hub_fly_4>3", "hub_wake_4>3",
		"hub_fly_5>4", "hub_wake_5>4", "rocket_tier_3>3", "hub_fly_6>5", "hub_wake_6>5", "hub_fly_7>6", "hub_wake_7>6", "hub_fly_8>7", "hub_wake_8>7"])
