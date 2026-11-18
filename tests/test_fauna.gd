extends GutTest
## [wild] Spawn rules for the ambient animals (fauna/fauna_rules.gd, data/fauna.json), meshes,
## and the persisted bits of fauna/fauna.gd (sightings, photos, the adopted cat).

class FakeWorld:
	extends Node
	var field: HexField
	var hub_index: int = 0

var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats


func _ctx(level: int, extra: Dictionary = {}) -> Dictionary:
	var c: Dictionary = {"hex": 7, "level": level, "hub": false, "water": false, "shore": false, "clean": level >= 1,
		"removed": 1.0 if level >= 1 else 0.3, "locked": false, "edge": false, "near_level": level}
	c.merge(extra, true)
	return c


func test_city_cats_and_birds_need_clean_ground() -> void:
	var cat: Dictionary = FaunaRules.def("cat")
	assert_false(FaunaRules.suits(cat, _ctx(0), ["city"], false), "no cats on junk")
	assert_true(FaunaRules.suits(cat, _ctx(1), ["city"], false))
	assert_true(FaunaRules.suits(cat, _ctx(-1, {"hub": true, "clean": true}), ["city"], false), "cats like the base yard")
	assert_false(FaunaRules.suits(cat, _ctx(1), ["wild"], false), "stray cats are a city thing")
	assert_false(FaunaRules.suits(FaunaRules.def("pigeon"), _ctx(1), ["city"], true), "pigeons roost at night")


func test_rats_live_in_junk_and_leave_as_it_is_cleaned() -> void:
	var rat: Dictionary = FaunaRules.def("rat")
	assert_true(FaunaRules.suits(rat, _ctx(0, {"removed": 0.1}), ["city"], false))
	assert_false(FaunaRules.suits(rat, _ctx(1), ["city"], false), "gone once clean")
	assert_false(FaunaRules.suits(rat, _ctx(0, {"removed": 0.95}), ["city"], false), "gone when nearly clean")
	# Count thins out with cleaning (same hex, same seed).
	var most: int = 0
	var less: int = 0
	for h: int in 40:
		most += FaunaRules.count_for(rat, _ctx(0, {"hex": h, "removed": 0.0}), ["city"], false, 11)
		less += FaunaRules.count_for(rat, _ctx(0, {"hex": h, "removed": 0.7}), ["city"], false, 11)
	assert_gt(most, 0)
	assert_lt(less, most)


func test_green_levels_bring_their_animals() -> void:
	var regs: Array = ["city"]
	assert_false(FaunaRules.suits(FaunaRules.def("rabbit"), _ctx(2), regs, false))
	assert_true(FaunaRules.suits(FaunaRules.def("rabbit"), _ctx(3), regs, false), "rabbits at Growing")
	var deer: Dictionary = FaunaRules.def("deer")
	assert_false(FaunaRules.suits(deer, _ctx(3, {"edge": true}), regs, false))
	assert_false(FaunaRules.suits(deer, _ctx(4, {"edge": false}), regs, false), "deer keep to the edges")
	assert_true(FaunaRules.suits(deer, _ctx(4, {"edge": true}), regs, false))
	assert_true(FaunaRules.suits(FaunaRules.def("fox"), _ctx(4), regs, false))
	assert_true(FaunaRules.suits(FaunaRules.def("bee"), _ctx(4), regs, false))
	assert_false(FaunaRules.suits(FaunaRules.def("songbird"), _ctx(4), regs, false))
	assert_true(FaunaRules.suits(FaunaRules.def("songbird"), _ctx(5), regs, false), "songbirds at Thriving")
	assert_false(FaunaRules.suits(FaunaRules.def("firefly"), _ctx(5), regs, false), "fireflies only at night")
	assert_true(FaunaRules.suits(FaunaRules.def("firefly"), _ctx(5), regs, true))


func test_water_animals_need_a_clean_lake() -> void:
	var regs: Array = ["city"]
	var lake: Dictionary = _ctx(-1, {"water": true, "clean": true, "near_level": 1})
	var murky: Dictionary = _ctx(-1, {"water": true, "clean": false, "near_level": 1})
	assert_true(FaunaRules.suits(FaunaRules.def("fish"), lake, regs, false))
	assert_false(FaunaRules.suits(FaunaRules.def("fish"), murky, regs, false))
	assert_false(FaunaRules.suits(FaunaRules.def("duck"), lake, regs, false), "ducks want a green shore")
	lake["near_level"] = 2
	assert_true(FaunaRules.suits(FaunaRules.def("duck"), lake, regs, false))
	assert_false(FaunaRules.suits(FaunaRules.def("frog"), _ctx(3), regs, false), "frogs only on shores")
	assert_true(FaunaRules.suits(FaunaRules.def("frog"), _ctx(3, {"shore": true}), regs, false))
	assert_false(FaunaRules.suits(FaunaRules.def("rabbit"), lake, regs, false), "no rabbits in the lake")
	# Clearer water, bigger schools.
	var fish: Dictionary = FaunaRules.def("fish")
	var dim: int = 0
	var clear: int = 0
	for h: int in 20:
		lake["hex"] = h
		dim += FaunaRules.count_for(fish, lake, regs, false, 3, 0.0)
		clear += FaunaRules.count_for(fish, lake, regs, false, 3, 1.0)
	assert_gt(clear, dim)


func test_frontier_biomes_have_their_own_animals() -> void:
	assert_eq(str(FaunaRules.regions("")), str(["city"]))
	assert_true("wild_dust" in FaunaRules.regions("dust_dunes"))
	var dust: Array = FaunaRules.regions("dust_flats")
	assert_true(FaunaRules.suits(FaunaRules.def("lizard"), _ctx(1), dust, false))
	assert_true(FaunaRules.suits(FaunaRules.def("fennec"), _ctx(2), dust, false))
	assert_false(FaunaRules.suits(FaunaRules.def("deer"), _ctx(5, {"edge": true}), dust, false), "no deer in the desert")
	var port: Array = FaunaRules.regions("frozen_port")
	assert_true(FaunaRules.suits(FaunaRules.def("seal"), _ctx(1, {"shore": true, "locked": true}), port, false), "seals on the ice")
	assert_false(FaunaRules.suits(FaunaRules.def("arctic_fox"), _ctx(1), port, false))
	assert_true(FaunaRules.suits(FaunaRules.def("arctic_fox"), _ctx(2), port, false))
	assert_true(FaunaRules.suits(FaunaRules.def("gull"), _ctx(1), port, false))
	var sunk: Array = FaunaRules.regions("sunken_city")
	assert_true(FaunaRules.suits(FaunaRules.def("turtle"), _ctx(-1, {"water": true, "clean": true}), sunk, false))
	assert_true(FaunaRules.suits(FaunaRules.def("heron"), _ctx(1, {"shore": true}), sunk, false))
	assert_false(FaunaRules.suits(FaunaRules.def("cat"), _ctx(1), sunk, false))
	# The Cradle's cranes are district-wide.
	var plan: Array = FaunaRules.plan([], FaunaRules.regions("cradle_landing"), false, 5)
	var cranes: int = 0
	for e: Dictionary in plan:
		if e["sp"] == "crane":
			cranes += int(e["n"])
	assert_between(cranes, 4, 5)


func test_plan_respects_caps_and_is_stable() -> void:
	var ctxs: Array = []
	for h: int in 60:
		ctxs.append(_ctx(5, {"hex": h, "edge": h % 2 == 0}))
	var a: Array = FaunaRules.plan(ctxs, ["city"], false, 42)
	var b: Array = FaunaRules.plan(ctxs, ["city"], false, 42)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same district, same plan")
	var per: Dictionary = {}
	var total: int = 0
	for e: Dictionary in a:
		per[e["sp"]] = int(per.get(e["sp"], 0)) + int(e["n"])
		var kind: String = str(FaunaRules.def(str(e["sp"])).get("kind", ""))
		total += 1 if kind in ["swarm", "school"] else int(e["n"])
	for sp: String in per:
		if not (str(FaunaRules.def(sp).get("kind", "")) in ["swarm", "school"]):
			assert_lte(int(per[sp]), int(FaunaRules.def(sp).get("cap", 99)), "cap for " + sp)
	assert_lte(total, int(FaunaRules.cfg().get("max_agents", 90)))
	assert_true(per.has("deer") and per.has("songbird") and per.has("cat"))
	assert_false(per.has("rat"), "no rats in a thriving district")
	# Nearest hexes win when a cap bites.
	var fd: Dictionary = {}
	for h: int in 60:
		fd[h] = float(60 - h)
	var near: Array = FaunaRules.plan(ctxs, ["city"], false, 42, fd)
	var cat_hexes: Array = near.filter(func(e: Dictionary) -> bool: return e["sp"] == "cat").map(func(e: Dictionary) -> int: return int(e["hex"]))
	for h: int in cat_hexes:
		assert_gt(h, 20, "cats placed near Lumi first")


func test_spots_keep_clear_of_junk() -> void:
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var f := HexField.new(2, 10.0, 5)
	f.generate(types, Vector2i(40, 60))
	var h: int = f.hex_count() - 1
	var pid: int = f.hex_pieces[h][0]
	var p: Vector3 = f.piece_pos[pid]
	assert_false(FaunaRules.spot_ok(f, p, 0.4, true), "never on a junk piece")
	assert_false(FaunaRules.spot_ok(f, f.hex_center(h) + Vector3(1, 0, 1), 0.3, false), "junk hex is off limits for clean-ground animals")
	for q: int in f.hex_pieces[h].duplicate():
		f.remove_piece(q)
	assert_true(f.is_clean(h))
	assert_true(FaunaRules.spot_ok(f, p, 0.05, false), "free once the pieces are gone")
	assert_false(FaunaRules.spot_ok(f, Vector3(500, 0, 500), 0.3, true), "off the field")
	var ctxs: Array = FaunaRules.contexts(f, func(hid: int) -> int: return 1 if f.is_clean(hid) else 0)
	assert_eq(ctxs.size(), f.hex_count())
	assert_true(bool(ctxs[h]["clean"]))


func test_every_model_builds_with_a_rig() -> void:
	for id: String in ["cat", "cat_sit", "cat_curl", "rabbit", "deer", "deer_stag", "fox", "fennec", "arctic_fox", "lizard", "frog",
			"seal", "turtle", "fish", "bee", "pigeon", "pigeon_fly", "sparrow", "songbird", "songbird_fly", "gull_fly", "duck", "heron", "crane_fly"]:
		var m: Mesh = FaunaModels.mesh(id)
		assert_not_null(m, id)
		assert_true(Fauna.is_rigged(m), id + " carries CUSTOM0")
		var tris: int = (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_between(tris, 20, 12000, id + " triangle budget")
	var rat: Mesh = FaunaModels.mesh("rat")
	assert_not_null(rat)
	var bb: AABB = rat.get_aabb()
	gut.p("rat mesh aabb %s rigged=%s" % [str(bb), str(Fauna.is_rigged(rat))])
	assert_gt(maxf(bb.size.x, bb.size.z), 0.05)


func test_custom_data_packs_head_and_coat() -> void:
	var c: Color = Fauna.pack_custom(1.0, 0.5, 0.6, 0.9, 3, 0.4)
	var yaw: float = floor(c.b) / 50.0 - 2.0
	var pitch: float = fposmod(c.b, 1.0) / 0.99 * 2.5 - 1.0
	assert_almost_eq(yaw, 0.6, 0.03)
	assert_almost_eq(pitch, 0.9, 0.02)
	assert_eq(int(floor(c.a / 2.0)), 3)
	assert_almost_eq(fposmod(c.a, 2.0), 0.4, 0.001)


func test_sightings_photos_and_adoption_persist_in_flags() -> void:
	GameState.flags.erase("fauna_seen")
	GameState.flags.erase("fauna_photos")
	GameState.flags.erase("fauna_cat")
	var w := FakeWorld.new()
	w.field = HexField.new(1, 10.0, 3)
	add_child_autofree(w)
	var fa := Fauna.new()
	fa.world = w
	w.add_child(fa)
	fa.set_process(false)
	assert_true(fa.mark_seen("deer"))
	assert_false(fa.mark_seen("deer"), "once")
	assert_true(bool(GameState.flags.get("seen_deer", false)))
	assert_true(Codex.is_unlocked("animals:deer"))
	fa.record_photo("fish")
	assert_true("fish" in GameState.flags["fauna_photos"])
	assert_true(Collection.has("pic_fish"))
	assert_true(bool(GameState.flags.get("seen_fish", false)))
	var cat := Fauna.Animal.new()
	cat.sp = "cat"
	cat.kind = "cat"
	cat.key = "cat|3|0"
	cat.coat = 2
	fa.adopt(cat)
	var info: Dictionary = fa.adopted_cat()
	assert_true(str(info.get("name", "")) in Fauna.CAT_NAMES)
	assert_eq(int(info["coat"]), 2)
	assert_eq(int(info["hub"]), 0)
	assert_true(cat.named)
	# Round trip through the save format.
	var back: Dictionary = JSON.parse_string(JSON.stringify(GameState.flags))
	assert_eq(str(back["fauna_cat"]["name"]), str(info["name"]))
