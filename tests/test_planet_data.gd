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
	assert_eq(SoundCfg.theme_of("no_such_planet"), "verdance", "planets._default sounds like Verdance")
	assert_eq(int(GlobeSpec.of("no_such_planet")["frequency"]), 128)
	assert_true(PlanetCfg.uses_towns("no_such_planet"))


func test_use_planet_points_the_lookups() -> void:
	PlanetCfg.use_planet("testworld")
	assert_eq(LifeCfg.planet_id, "testworld")
	assert_eq(HubPlan.active_planet, "testworld")
	assert_eq(SkyDirector.current_planet_id(), "testworld")
	assert_eq(LifeCfg.num("ground", "grow_s", 0.0), 120.0, "data/life.json testworld block")
	assert_eq(HubPlan.hop_cfg("leg_s", 0.0), 2.8)
