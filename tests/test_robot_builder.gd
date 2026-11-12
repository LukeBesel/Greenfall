extends GutTest
## [drones] Robot Builder rules (systems/robot_builder.gd). Parts are cosmetics (the Locker): no
## stat mods except the Maker set's small perk; a part is a found piece (CrewLooks) and fits every
## robot once found; nothing is crafted, bought or won. Also presets, traits, renaming, the kit
## visuals and robot save data.

var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _parts: Array
var _world: Dictionary
var _global: Dictionary


func before_each() -> void:
	_global = GameState.global.duplicate(true)
	GameState.global = {}
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
	GameState.global = _global


func _find(part_id: String) -> void:
	Looks.grant(CrewLooks.piece(CrewLooks.CREW, str(RobotBuilder.part(part_id)["slot"]), part_id), "buried")


func _bot(type_id: String = "scoopie", rname: String = "Tester-01") -> Robot:
	var r := Robot.new()
	r.type_id = type_id
	r.robot_name = rname
	add_child_autofree(r)
	return r


func test_parts_are_cosmetic() -> void:
	var slots: Array = []
	for s: Dictionary in RobotBuilder.cfg()["slots"]:
		slots.append(str(s["id"]))
	assert_eq(slots, Array(RobotBuilder.SLOTS))
	for p: Dictionary in RobotBuilder.all_parts():
		assert_true(str(p["slot"]) in slots, "%s has a known slot" % p["id"])
		assert_false(p.has("source"), "%s: no price, recipe or counter" % p["id"])
		assert_ne(CrewLooks.piece(CrewLooks.CREW, str(p["slot"]), str(p["id"])), "", "%s is a piece" % p["id"])
		assert_true((p.get("mods", {}) as Dictionary).is_empty(), "%s changes no stats" % p["id"])
		assert_true(RobotBuilder.generic_mods({str(p["slot"]): str(p["id"])}).is_empty(), "%s alone: no mods" % p["id"])

func test_no_way_to_get_a_part_but_finding_it() -> void:
	for gone: String in ["craft", "craft_parts", "craft_block_reason", "obtain", "buy_haggle", "haggle_offers", "get_block_reason",
			"cost_text", "roll_unowned", "add_part", "count", "inv"]:
		var found: bool = false
		for m: Dictionary in (load("res://systems/robot_builder.gd") as Script).get_script_method_list():
			found = found or str(m["name"]) == gone
		assert_false(found, "RobotBuilder.%s is gone" % gone)
	GameState.stats["builder_parts_got"] = 999.0
	GameState.add_currency("parts", BigNum.from_float(99999))
	for p: Dictionary in RobotBuilder.all_parts():
		assert_false(RobotBuilder.owned(str(p["id"])), "%s: not held without being found" % p["id"])


func test_fitting_uses_nothing_and_changes_no_stats() -> void:
	var r := _bot()
	r.trait_id = "chatty"
	RobotBuilder.refresh_mods(r)
	var base_speed: float = r.stat("speed")
	var base_cap: float = r.stat("capacity")
	assert_ne(RobotBuilder.equip(r, "mobility", "treads"), "", "unfound parts can't be fitted")
	_find("treads")
	assert_eq(RobotBuilder.equip(r, "mobility", "treads"), "")
	assert_almost_eq(r.stat("speed"), base_speed, 0.0001, "cosmetic")
	assert_almost_eq(r.stat("capacity"), base_cap, 0.0001, "cosmetic")
	assert_true(RobotBuilder.owned("treads"), "a found part stays found")
	var r2 := _bot("scoopie", "Second-02")
	assert_eq(RobotBuilder.equip(r2, "mobility", "treads"), "", "one find fits every robot")
	assert_eq(RobotBuilder.equip(r, "mobility", ""), "")
	assert_true(RobotBuilder.owned("treads"))

func test_tools_fit_their_crew_only() -> void:
	var h := _bot("haulbug", "Hauler-01")
	_find("wide_scoop")
	assert_ne(RobotBuilder.equip(h, "tool", "wide_scoop"), "", "a scoop doesn't fit a forklift")
	assert_true(RobotBuilder.fits("long_forks", "haulbug"))
	assert_true(RobotBuilder.fits("wide_scoop", "multibot"), "multibots take any tool")
	assert_false(RobotBuilder.fits("mist_sprayer", "scoopie"))
	assert_ne(RobotBuilder.equip(h, "head", "big_eye"), "", "not found")


func test_maker_set_gives_its_bonus() -> void:
	# [money] Maker Fragments are Parts now: a fragment find pays FRAGMENT_PARTS parts.
	RobotBuilder.add_fragments(3)
	assert_almost_eq(GameState.get_currency("parts").to_float(), 3.0 * RobotBuilder.fragment_parts(), 0.001)
	var b: Dictionary = {"chassis": "maker_shell", "head": "maker_optic", "mobility": "maker_glider"}
	assert_true(RobotBuilder.has_set(b))
	var with_set: Dictionary = RobotBuilder.generic_mods(b)
	assert_almost_eq(float(with_set["speed"]), 1.05, 0.0001, "the one perk: the Maker set")
	assert_almost_eq(float(with_set["work"]), 1.06, 0.0001)
	b.erase("head")
	assert_false(RobotBuilder.has_set(b))
	assert_true(RobotBuilder.generic_mods(b).is_empty())

func test_full_custom_goal_stat() -> void:
	var r := _bot()
	for id: String in ["light_frame", "big_eye", "treads", "wide_scoop", "top_hat"]:
		_find(id)
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
		assert_true(RobotBuilder.concrete_mods({}, str(t["id"])).is_empty(), "trait %s is flavour only" % t["id"])
		assert_true(Audio.has_sound(str(t.get("beep", ""))), "trait %s beep exists" % t["id"])


func test_presets_and_save_dict() -> void:
	var r := _bot()
	_find("treads")
	_find("bobble_plant")
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


func test_rename_moves_orders() -> void:
	var r := _bot("scoopie", "Old-01")
	GameState.world["orders"] = {"groups": {}, "bots": {"Old-01": {"zone": [1], "mode": "stay"}}}
	var f := Fleet.new()
	add_child_autofree(f)
	assert_ne(RobotBuilder.rename(f, r, "x"), "")
	assert_eq(RobotBuilder.rename(f, r, "Sunny-07"), "")
	assert_eq(r.robot_name, "Sunny-07")
	assert_true((GameState.world["orders"]["bots"] as Dictionary).has("Sunny-07"))
