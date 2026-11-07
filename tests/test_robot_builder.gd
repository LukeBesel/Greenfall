extends GutTest
## [drones] Robot Builder rules (systems/robot_builder.gd): balance of the part data, stat
## multipliers, fitting and the parts bin, crafting, Haggle's stall, the Maker set, presets,
## traits, renaming, the kit visuals and robot save data.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _parts: Array
var _world: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate()
	_parts = GameState.parts.duplicate(true)
	_world = GameState.world
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies = {}
	GameState.parts = []
	GameState.world = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	GameState.parts = _parts
	GameState.world = _world


func _bot(type_id: String = "scoopie", rname: String = "Tester-01") -> Robot:
	var r := Robot.new()
	r.type_id = type_id
	r.robot_name = rname
	add_child_autofree(r)
	return r


func test_every_part_is_a_tradeoff_and_gentle() -> void:
	var slots: Array = []
	for s: Dictionary in RobotBuilder.cfg()["slots"]:
		slots.append(str(s["id"]))
	assert_eq(slots, Array(RobotBuilder.SLOTS))
	for p: Dictionary in RobotBuilder.all_parts():
		assert_true(str(p["slot"]) in slots, "%s has a known slot" % p["id"])
		assert_true(p.has("source") and str(p["source"].get("kind", "")) in ["craft", "haggle", "token", "research", "drop", "set"], "%s has a source" % p["id"])
		var mods: Dictionary = p.get("mods", {})
		if str(p["slot"]) == "topper":
			assert_true(mods.is_empty(), "%s: toppers are cosmetic" % p["id"])
			continue
		var up: bool = false
		var down: bool = false
		for k: String in mods:
			assert_true(RobotBuilder.CONCRETE.has(k), "%s: known stat %s" % [p["id"], k])
			var v: float = float(mods[k])
			assert_between(v, 0.7, 1.6, "%s %s stays gentle" % [p["id"], k])
			up = up or v > 1.0
			down = down or v < 1.0
		assert_true(up and down, "%s is specialised: an upside and a downside" % p["id"])
		if str(p["source"]["kind"]) == "research":
			assert_false(Research.def(str(p["source"]["research"])).is_empty(), "%s research node exists" % p["id"])


func test_some_parts_from_each_economy() -> void:
	var kinds: Dictionary = {}
	for p: Dictionary in RobotBuilder.all_parts():
		kinds[str(p["source"]["kind"])] = true
	for k: String in ["craft", "haggle", "token", "research", "drop", "set"]:
		assert_true(kinds.has(k), "parts come from " + k)
	for it: Dictionary in Contracts.shop():
		if str(it.get("kind", "")) == "builder" and it.has("part"):
			assert_false(RobotBuilder.part(str(it["part"])).is_empty(), "shop part %s exists" % it["id"])


func test_mods_scale_robot_stats() -> void:
	var r := _bot()
	r.trait_id = "chatty"  # scan only
	RobotBuilder.refresh_mods(r)
	var base_speed: float = r.stat("speed")
	var base_cap: float = r.stat("capacity")
	RobotBuilder.add_part("treads")
	assert_eq(RobotBuilder.equip(r, "mobility", "treads"), "")
	assert_almost_eq(r.stat("speed"), base_speed * 0.88, 0.0001)
	assert_almost_eq(r.stat("capacity"), base_cap * 1.2, 0.0001)
	assert_eq(RobotBuilder.count("treads"), 0, "fitting takes it out of the bin")
	assert_eq(RobotBuilder.equip(r, "mobility", ""), "")
	assert_eq(RobotBuilder.count("treads"), 1, "unfitting puts it back")
	assert_almost_eq(r.stat("speed"), base_speed, 0.0001)


func test_tools_fit_their_crew_only() -> void:
	var h := _bot("haulbug", "Hauler-01")
	RobotBuilder.add_part("wide_scoop")
	assert_ne(RobotBuilder.equip(h, "tool", "wide_scoop"), "", "a scoop doesn't fit a forklift")
	assert_eq(RobotBuilder.count("wide_scoop"), 1)
	assert_true(RobotBuilder.fits("long_forks", "haulbug"))
	assert_true(RobotBuilder.fits("wide_scoop", "multibot"), "multibots take any tool")
	assert_false(RobotBuilder.fits("mist_sprayer", "scoopie"))
	assert_ne(RobotBuilder.equip(h, "head", "big_eye"), "", "nothing in the bin")


func test_craft_uses_bolts_and_a_stored_part() -> void:
	assert_ne(RobotBuilder.craft_block_reason("treads"), "")
	GameState.parts.append({"type": Fleet.part_index("locomotion"), "rarity": 2})
	GameState.parts.append({"type": Fleet.part_index("locomotion"), "rarity": 0})
	assert_string_contains(RobotBuilder.craft_block_reason("treads"), "bolts")
	GameState.add_currency("bolts", BigNum.from_float(10))
	assert_eq(RobotBuilder.craft_block_reason("treads"), "")
	assert_true(RobotBuilder.craft("treads"))
	assert_eq(RobotBuilder.count("treads"), 1)
	assert_eq(GameState.parts.size(), 1)
	assert_eq(int(GameState.parts[0]["rarity"]), 2, "the cheapest part of the type was used")
	assert_almost_eq(GameState.get_currency("bolts").to_float(), 4.0, 0.001)


func test_research_gate() -> void:
	GameState.parts.append({"type": Fleet.part_index("locomotion"), "rarity": 0})
	GameState.add_currency("bolts", BigNum.from_float(100))
	assert_string_contains(RobotBuilder.craft_block_reason("rotor"), "Research")
	Research.grant("swarm_sync")
	assert_eq(RobotBuilder.craft_block_reason("rotor"), "")


func test_maker_set_needs_fragments_and_gives_bonus() -> void:
	GameState.parts.append({"type": Fleet.part_index("chassis"), "rarity": 1})
	GameState.add_currency("bolts", BigNum.from_float(500))
	RobotBuilder.add_fragments(3)
	assert_string_contains(RobotBuilder.craft_block_reason("maker_shell"), "Fragments")
	RobotBuilder.add_fragments(1)
	assert_string_contains(RobotBuilder.craft_block_reason("maker_shell"), "Vintage", "needs a Vintage+ chassis")
	GameState.parts.append({"type": Fleet.part_index("chassis"), "rarity": 3})
	assert_true(RobotBuilder.craft("maker_shell"))
	assert_eq(RobotBuilder.fragments(), 0)
	var b: Dictionary = {"chassis": "maker_shell", "head": "maker_optic", "mobility": "maker_glider"}
	assert_true(RobotBuilder.has_set(b))
	var with_set: Dictionary = RobotBuilder.generic_mods(b)
	var speed_parts: float = 0.95 * 1.12
	assert_almost_eq(float(with_set["speed"]), speed_parts * 1.05, 0.0001, "set bonus on top")
	b.erase("head")
	assert_false(RobotBuilder.has_set(b))


func test_full_custom_goal_stat() -> void:
	var r := _bot()
	for id: String in ["light_frame", "big_eye", "treads", "wide_scoop", "top_hat"]:
		RobotBuilder.add_part(id)
	for s_id: Array in [["chassis", "light_frame"], ["head", "big_eye"], ["mobility", "treads"], ["tool", "wide_scoop"]]:
		RobotBuilder.equip(r, s_id[0], s_id[1])
	assert_eq(float(GameState.stats.get("builder_full_custom", 0.0)), 0.0)
	RobotBuilder.equip(r, "topper", "top_hat")
	assert_eq(float(GameState.stats.get("builder_full_custom", 0.0)), 1.0)
	assert_eq(float(GameState.stats.get("builder_parts_fitted", 0.0)), 5.0)
	assert_eq(float(GameState.stats.get("builder_toppers", 0.0)), 1.0)


func test_kit_meshes_follow_the_build() -> void:
	var r := _bot()
	var kit: RobotKit = RobotKit.of(r.visual)
	assert_not_null(kit, "every robot gets a kit root")
	var n0: int = kit.find_children("*", "MeshInstance3D", true, false).size()
	RobotBuilder.set_build(r, {"mobility": "rotor", "topper": "antenna"})
	kit = RobotKit.of(r.visual)
	assert_gt(kit.find_children("*", "MeshInstance3D", true, false).size(), n0 + 10, "rotor + antenna add meshes")
	assert_gt(kit.lift, 0.0, "rotors lift the model")
	for w: Node3D in r.visual._wheels:
		assert_false(w.visible, "wheels hidden under a custom drive")
	assert_not_null(r.get_node_or_null(RobotPersona.NODE_NAME), "name tag + personality")
	# Every part builds on every body type and look without errors.
	for t: String in Economy.robot_order:
		for look: String in ["salvage", "restored", "modern", "hover"]:
			var v := RobotVisual.new()
			add_child_autofree(v)
			v.build(t, look)
			for p: Dictionary in RobotBuilder.all_parts():
				if RobotBuilder.fits(str(p["id"]), t):
					var k: RobotKit = RobotKit.fit(v, {str(p["slot"]): str(p["id"])}, str(Economy.robots[t].get("role", "clean")))
					assert_not_null(k)


func test_traits_are_stable_and_gentle() -> void:
	assert_eq(RobotBuilder.trait_for_name("Rivet-12"), RobotBuilder.trait_for_name("Rivet-12"))
	var seen: Dictionary = {}
	for i: int in 60:
		seen[RobotBuilder.trait_for_name("Bot-%d" % i)] = true
	assert_gte(seen.size(), 4, "names spread over the traits")
	for t: Dictionary in RobotBuilder.traits():
		for k: String in t.get("mods", {}):
			assert_between(float(t["mods"][k]), 0.94, 1.16, "trait %s is flavour, not a build" % t["id"])
		assert_true(Audio.has_sound(str(t.get("beep", ""))), "trait %s beep exists" % t["id"])


func test_presets_and_save_dict() -> void:
	var r := _bot()
	RobotBuilder.add_part("treads")
	RobotBuilder.add_part("bobble_plant")
	RobotBuilder.equip(r, "mobility", "treads")
	RobotBuilder.equip(r, "topper", "bobble_plant")
	RobotBuilder.save_preset("clean", r.build)
	assert_eq(RobotBuilder.preset("clean"), {"mobility": "treads", "topper": "bobble_plant"})
	var d: Dictionary = r.to_dict()
	assert_eq(d["build"], {"mobility": "treads", "topper": "bobble_plant"})
	assert_eq(str(d["trait"]), RobotBuilder.trait_of(r))
	var r2 := _bot("scoopie", "Copy-02")
	RobotBuilder.set_build(r2, JSON.parse_string(JSON.stringify(d["build"])))
	assert_eq(r2.build, r.build, "builds survive JSON")
	assert_almost_eq(r2.stat("capacity"), r.stat("capacity") / float(r.build_mods.get("capacity", 1.0)) * float(r2.build_mods.get("capacity", 1.0)), 0.0001)


func test_haggle_stall_rotates_and_sells() -> void:
	var a: Array[String] = RobotBuilder.haggle_offers(10.0)
	assert_eq(a.size(), 3)
	assert_eq(a, RobotBuilder.haggle_offers(100.0), "same stock inside one rotation")
	for id: String in a:
		assert_eq(RobotBuilder.source_kind(id), "haggle")
	var differs: bool = false
	for k: int in 6:
		if RobotBuilder.haggle_offers(10.0 + 480.0 * (k + 1)) != a:
			differs = true
	assert_true(differs, "stock rotates")
	GameState.stats["time_played"] = 10.0
	assert_ne(RobotBuilder.buy_haggle(a[0]), "")
	GameState.add_currency("cubes", BigNum.from_float(5000))
	GameState.add_currency("bolts", BigNum.from_float(50))
	assert_eq(RobotBuilder.buy_haggle(a[0]), "")
	assert_eq(RobotBuilder.count(a[0]), 1)


func test_rename_moves_orders() -> void:
	var r := _bot("scoopie", "Old-01")
	GameState.world["orders"] = {"groups": {}, "bots": {"Old-01": {"zone": [1], "mode": "stay"}}}
	var f := Fleet.new()
	add_child_autofree(f)
	assert_ne(RobotBuilder.rename(f, r, "x"), "")
	assert_eq(RobotBuilder.rename(f, r, "Sunny-07"), "")
	assert_eq(r.robot_name, "Sunny-07")
	assert_true((GameState.world["orders"]["bots"] as Dictionary).has("Sunny-07"))
