extends GutTest
## [biomes] Frontier rules that outlive the flat frontier districts: the planet's frontier hubs and
## their unlock gates (goals, research and the campaign read them).

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


# --- Planet and unlocks ----------------------------------------------------------------------

func test_planet_appends_one_hub_per_frontier() -> void:
	var p := PlanetData.new(4471, 6, 10.0)
	p.generate()
	assert_eq(p.frontier_hubs.size(), 4, "four frontier hubs")
	assert_eq(p.base_hub_count + 4, p.hubs.size(), "appended after the ordinary hubs")
	for k: String in PlanetData.FRONTIER_KINDS:
		var hi: int = int(p.frontier_hubs[k])
		assert_gte(hi, p.base_hub_count)
		assert_eq(p.frontier_kind(hi), k)
		assert_false(Frontiers.def(k).is_empty(), "%s has data" % k)
		assert_eq(PlanetData.BIOMES[p.biome[p.hubs[hi]]], str(Frontiers.def(k)["biome"]), "%s cell painted" % k)
	assert_eq(p.frontier_kind(0), "", "Old Town is not a frontier")


func test_frontier_unlocks_follow_research_and_bases() -> void:
	var p := PlanetData.new(4471, 6, 10.0)
	p.generate()
	var dust: int = int(p.frontier_hubs["dust_flats"])
	assert_false(Frontiers.can_launch(p, dust), "locked on a new game")
	assert_true(Frontiers.can_launch(p, 1), "ordinary hubs always open")
	Research.grant("dune_charts")
	assert_false(bool(Frontiers.unlock_status("dust_flats", p.frontier_hubs)["ok"]), "research alone is not enough")
	GameState.world["hub_level"] = 5
	GameState.districts[3] = {"hub_level": 5}
	var st: Dictionary = Frontiers.unlock_status("dust_flats", p.frontier_hubs)
	assert_true(bool(st["ok"]), str(st["lines"]))
	assert_true(Frontiers.can_launch(p, dust))
	# Frozen Port also needs the Dust Flats base at level 3.
	Research.grant("thermal_lance")
	GameState.districts[4] = {"hub_level": 5}
	assert_false(bool(Frontiers.unlock_status("frozen_port", p.frontier_hubs)["ok"]))
	GameState.districts[dust] = {"hub_level": 3, "frontier": {}}
	assert_true(bool(Frontiers.unlock_status("frozen_port", p.frontier_hubs)["ok"]))
	# The Cradle needs all three frontiers at level 5 and Growing.
	Research.grant("ark_beacon")
	assert_false(bool(Frontiers.unlock_status("cradle_returns", p.frontier_hubs)["ok"]))
	for k: String in ["dust_flats", "frozen_port", "sunken_city"]:
		GameState.districts[int(p.frontier_hubs[k])] = {"hub_level": 5, "frontier": {"growing_frac": 0.6}}
	assert_true(bool(Frontiers.unlock_status("cradle_returns", p.frontier_hubs)["ok"]))
