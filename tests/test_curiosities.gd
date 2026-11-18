extends GutTest
## Codex Curiosities page data (systems/codex.gd), wilderness-only eggs (story/eggs.gd) and the
## biome junk sets for wilderness districts (data/junk.json "biomes", planet/hex_field.gd).

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	GameState.flags = {}
	GameState.currencies = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur


func _egg_data() -> Array:
	var defs: Dictionary = {}
	var order: Array[String] = []
	for e: Dictionary in Economy.read_json("res://data/eggs.json")["eggs"]:
		defs[str(e["id"])] = e
		order.append(str(e["id"]))
	return [order, defs]


func test_curiosities_list_every_egg_with_hint_and_found_state() -> void:
	var list: Array[Dictionary] = Codex.curiosities()
	assert_eq(list.size(), Codex.egg_defs().size())
	assert_gte(list.size(), 27, "at least 10 new eggs on top of the first 17")
	for c: Dictionary in list:
		assert_ne(str(c["hint"]), "", str(c["id"]) + " has a hint for the Codex")
		assert_ne(str(c["lore"]), "", str(c["id"]) + " has flavour text")
		assert_false(bool(c["found"]))
	assert_eq(Codex.curiosities_found(), 0)
	GameState.flags["egg_campfire"] = true
	GameState.flags["eggs_found"] = ["campfire"]
	var after: Array[Dictionary] = Codex.curiosities()
	var camp: Dictionary = after.filter(func(c: Dictionary) -> bool: return c["id"] == "campfire")[0]
	assert_true(bool(camp["found"]))
	assert_string_contains(str(camp["where"]), "Wilderness")
	assert_eq(Codex.curiosities_found(), 1)


func test_chain_eggs_report_parts_progress() -> void:
	GameState.flags["egg_gnomes_parts"] = [0, 2]
	var g: Dictionary = Codex.curiosities().filter(func(c: Dictionary) -> bool: return c["id"] == "gnomes")[0]
	assert_eq(int(g["parts"]), 5)
	assert_eq(int(g["parts_seen"]), 2)


func test_new_eggs_have_props_and_wren_lines() -> void:
	var wren: Dictionary = Economy.read_json("res://data/wren_lines.json")
	var wild: int = 0
	for e: Dictionary in Codex.egg_defs():
		var id: String = str(e["id"])
		assert_true(wren.has("egg_" + id), id + " has WREN lines")
		var node: Node3D = EggProps.build(str(e["kind"]), 0)
		assert_true(node.get_child_count() > 1 or node.get_child(0).name == "Anim", id + " has its own prop (not the fallback box)")
		node.free()
		if str(e.get("where", "")) == "wild":
			wild += 1
	assert_gte(wild, 4, "some eggs only live in wilderness bases")


func test_wild_eggs_only_in_wilderness_districts() -> void:
	var d: Array = _egg_data()
	var order: Array[String] = d[0]
	var defs: Dictionary = d[1]
	for seed_v: int in [101, 2024, 9999]:
		var city: Array[String] = EasterEggs.district_eggs(order, defs, 5, seed_v, 10)
		assert_eq(city.size(), 10)
		for id: String in city:
			assert_ne(str(defs[id].get("where", "")), "wild", "no wild egg %s in a city" % id)
		var wild: Array[String] = EasterEggs.district_eggs(order, defs, 28, seed_v, 10, true, "dust_dunes", 4)
		assert_eq(wild.size(), 10)
		var n_wild: int = wild.filter(func(id: String) -> bool: return str(defs[id].get("where", "")) == "wild").size()
		assert_eq(n_wild, 4)
		assert_true("parking" in wild, "the dunes always get their biome's egg")
		assert_eq(wild, EasterEggs.district_eggs(order, defs, 28, seed_v, 10, true, "dust_dunes", 4), "deterministic")
	# Old Town keeps its starter set.
	assert_eq(EasterEggs.district_eggs(order, defs, 0, 4471, 10).size(), 12)


func test_biome_sets_reference_real_models() -> void:
	assert_false(Economy.biome_sets.is_empty())
	for b: String in Economy.biome_sets:
		assert_true(b in PlanetData.BIOMES, b + " is a planet biome")
		var bs: Dictionary = Economy.biome_sets[b]
		for t: String in bs.get("models", {}):
			assert_true(Economy.junk_types.has(t), "%s: junk type %s exists" % [b, t])
			for m: Dictionary in bs["models"][t]:
				assert_true(AssetLib.has_model(str(m["id"])), "%s: model %s" % [b, m["id"]])
		for l: Dictionary in Economy.landmarks_for(b):
			assert_true(AssetLib.has_model(str(l["id"])), "%s: landmark %s" % [b, l["id"]])
		for h: String in bs.get("horizon", []):
			assert_true(AssetLib.has_model(h), "%s: horizon prop %s" % [b, h])


func test_biome_junk_keeps_piece_count_and_types() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var plain := HexField.new(5, 3.2, 7007, CityLayout.new(7007, 150.0, true))
	plain.generate(types, Vector2i(6, 12))
	var dunes := HexField.new(5, 3.2, 7007, CityLayout.new(7007, 150.0, true))
	dunes.biome = "dust_dunes"
	dunes.biome_set = Economy.biome_set("dust_dunes")
	dunes.generate(types, Vector2i(6, 12))
	assert_eq(dunes.piece_count(), plain.piece_count(), "saves (alive bits) stay compatible")
	var changed: int = 0
	for pid: int in plain.piece_count():
		assert_eq(dunes.piece_type[pid], plain.piece_type[pid])
		assert_eq(dunes.piece_pos[pid], plain.piece_pos[pid])
		if dunes.piece_model[pid] != plain.piece_model[pid]:
			changed += 1
	@warning_ignore("integer_division")
	assert_gt(changed, plain.piece_count() / 10, "the dunes look different")
	# A saved plain field still applies to the biome field.
	assert_true(dunes.apply_dict(plain.to_dict()))
	assert_eq(Economy.landmarks_for("dust_dunes"), Economy.biome_set("dust_dunes")["landmarks"])
	assert_eq(Economy.landmarks_for(""), Economy.landmarks)


func test_codex_lists_biome_landmarks() -> void:
	assert_false(Codex.entry("landmarks:old_drill_press").is_empty())
	assert_false(Codex.entry("landmarks:ocean_buoy").is_empty())


func test_wild_egg_found_counts_for_achievement() -> void:
	var eggs := EasterEggs.new()
	for e: Dictionary in Codex.egg_defs():
		eggs.defs[str(e["id"])] = e
	add_child_autofree(eggs)
	eggs.found("cairn")
	assert_eq(GameState.flags.get("eggs_wild", []), ["cairn"])
	assert_almost_eq(Achievements.value_of({"type": "list", "key": "eggs_wild"}), 1.0, 0.001)
	assert_gt(GameState.get_currency("cubes").to_float(), 0.0, "[money] trinket rewards pay cubes now")
