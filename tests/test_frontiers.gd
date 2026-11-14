extends GutTest
## [biomes] Frontier data (planet/frontiers.gd): planet hubs, unlock gates, field toughness and
## species rules. [v6flat] The live frontier districts (storms, thawing, water levels, the Cradle
## pad) went with the flat world, and their tests with them.

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func _types() -> Array:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	return types


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


func test_frontier_fields_are_bigger_and_tougher() -> void:
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	for k: Dictionary in Frontiers.kinds():
		# [world2] Old Town grew to radius 4 (gen-2 junk); frontiers keep 4 with denser, tougher junk.
		assert_true(int(k["radius"]) >= int(cfg.get("radius", 3)), "%s has at least as many hexes" % k["id"])
		assert_gt(float(k["vol_mult"]), 1.0, "%s junk is bulkier" % k["id"])
		assert_gt(float(k["value_mult"]), 1.0)
		assert_true(Economy.biome_sets.has(str(k["biome"])), "%s has a junk set" % k["id"])
		assert_true(Codex.entry("frontiers:" + str(k["id"])).size() > 0, "%s has a codex entry" % k["id"])
		for layer: Variant in k.get("ground_layers", {}).values():
			assert_not_null(AssetLib.tex(str(layer), "diff"), "ground texture %s" % layer)
	var f := HexField.new(2, 10.0, 9, null)
	f.generate(_types(), Vector2i(10, 12))
	var before: float = f.hex_total[3]
	Frontiers.toughen(f, 1.5)
	assert_almost_eq(f.hex_total[3], before * 1.5, 0.01)
	assert_almost_eq(f.hex_left[3], f.hex_total[3], 0.01)


## [v6flat] Frontier species rules (Frontiers.species_mult). The live Frozen Port checks (cold,
## greenhouses) went with the flat frontier districts.
func test_frontier_species_rules() -> void:
	var species: Array = Economy.read_json("res://data/plants.json").get("species", [])
	for sp: Dictionary in species:
		if Frontiers.species_mult(sp, "frozen_port", false) > 0.0:
			assert_true(bool(sp.get("cold_hardy", false)), "%s is cold-hardy" % sp["id"])
	var ice_plant: Dictionary = {}
	for sp: Dictionary in species:
		if sp["id"] == "iceplant":
			ice_plant = sp
	assert_false(ice_plant.is_empty())
	assert_eq(Frontiers.species_mult(ice_plant, "dust_flats"), 1.0)
	assert_eq(Frontiers.species_mult(ice_plant, ""), 0.0, "natives never turn up in old districts")
	assert_eq(Frontiers.species_mult(ice_plant, "frozen_port", true), 0.0)
