extends GutTest
## [drones] Robot Builder rules (systems/robot_builder.gd). [ui2] Parts are cosmetics (the
## Locker): no stat mods except the Maker set's small perk, owned parts fit every robot, unlocks
## cost Parts (+ cubes), the shop lists every shop part. Also presets, traits, renaming, the kit
## visuals and robot save data.

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


func test_parts_are_cosmetic() -> void:
	var slots: Array = []
	for s: Dictionary in RobotBuilder.cfg()["slots"]:
		slots.append(str(s["id"]))
	assert_eq(slots, Array(RobotBuilder.SLOTS))
	for p: Dictionary in RobotBuilder.all_parts():
		assert_true(str(p["slot"]) in slots, "%s has a known slot" % p["id"])
		assert_true(p.has("source") and str(p["source"].get("kind", "")) in ["craft", "haggle", "request", "research", "drop", "set"], "%s has a source" % p["id"])
		assert_true((p.get("mods", {}) as Dictionary).is_empty(), "%s changes no stats" % p["id"])
		assert_true(RobotBuilder.generic_mods({str(p["slot"]): str(p["id"])}).is_empty(), "%s alone: no mods" % p["id"])
		if str(p["source"]["kind"]) == "research":
			assert_false(Research.def(str(p["source"]["research"])).is_empty(), "%s research node exists" % p["id"])

func test_some_parts_from_each_economy() -> void:
	var kinds: Dictionary = {}
	for p: Dictionary in RobotBuilder.all_parts():
		kinds[str(p["source"]["kind"])] = true
	for k: String in ["craft", "haggle", "request", "research", "drop", "set"]:
		assert_true(kinds.has(k), "parts come from " + k)
	# [money] Request-source parts are on the Requests reward track at the count they name.
	for t: Dictionary in Contracts.track():
		if str(t.get("kind", "")) == "builder":
			var p: Dictionary = RobotBuilder.part(str(t["id"]))
			assert_false(p.is_empty(), "track part %s exists" % t["id"])
			assert_eq(int(p["source"].get("requests", -1)), int(t["n"]), "%s: requests count matches the track" % t["id"])


func test_fitting_uses_nothing_and_changes_no_stats() -> void:
	var r := _bot()
	r.trait_id = "chatty"
	RobotBuilder.refresh_mods(r)
	var base_speed: float = r.stat("speed")
	var base_cap: float = r.stat("capacity")
	assert_ne(RobotBuilder.equip(r, "mobility", "treads"), "", "locked parts can't be fitted")
	RobotBuilder.add_part("treads")
	assert_eq(RobotBuilder.equip(r, "mobility", "treads"), "")
	assert_almost_eq(r.stat("speed"), base_speed, 0.0001, "cosmetic")
	assert_almost_eq(r.stat("capacity"), base_cap, 0.0001, "cosmetic")
	assert_eq(RobotBuilder.count("treads"), 1, "an unlocked part stays unlocked")
	var r2 := _bot("scoopie", "Second-02")
	assert_eq(RobotBuilder.equip(r2, "mobility", "treads"), "", "one unlock fits every robot")
	assert_eq(RobotBuilder.equip(r, "mobility", ""), "")
	assert_eq(RobotBuilder.count("treads"), 1)

func test_tools_fit_their_crew_only() -> void:
	var h := _bot("haulbug", "Hauler-01")
	RobotBuilder.add_part("wide_scoop")
	assert_ne(RobotBuilder.equip(h, "tool", "wide_scoop"), "", "a scoop doesn't fit a forklift")
	assert_eq(RobotBuilder.count("wide_scoop"), 1)
	assert_true(RobotBuilder.fits("long_forks", "haulbug"))
	assert_true(RobotBuilder.fits("wide_scoop", "multibot"), "multibots take any tool")
	assert_false(RobotBuilder.fits("mist_sprayer", "scoopie"))
	assert_ne(RobotBuilder.equip(h, "head", "big_eye"), "", "not unlocked")


func test_unlock_costs_parts_only() -> void:
	assert_ne(RobotBuilder.craft_block_reason("treads"), "")
	var need: float = RobotBuilder.craft_parts("treads")
	assert_almost_eq(need, 30.0 + RobotParts.value(0), 0.001, "parts + the old robot part's worth")
	assert_string_contains(RobotBuilder.craft_block_reason("treads"), "parts")
	GameState.add_currency("parts", BigNum.from_float(need + 5.0))
	assert_eq(RobotBuilder.craft_block_reason("treads"), "")
	assert_true(RobotBuilder.craft("treads"))
	assert_eq(RobotBuilder.count("treads"), 1)
	assert_eq(GameState.parts.size(), 0, "no robot part items involved")
	assert_almost_eq(GameState.get_currency("parts").to_float(), 5.0, 0.001)
	assert_string_starts_with(RobotBuilder.cost_text("antenna"), "Unlock")

func test_research_gate() -> void:
	GameState.add_currency("parts", BigNum.from_float(500))
	assert_string_contains(RobotBuilder.craft_block_reason("rotor"), "Research")
	Research.grant("swarm_sync")
	assert_eq(RobotBuilder.craft_block_reason("rotor"), "")


func test_maker_set_needs_parts_and_gives_bonus() -> void:
	# [money] Maker Fragments are Parts now: a fragment find pays FRAGMENT_PARTS parts.
	RobotBuilder.add_fragments(3)
	assert_almost_eq(GameState.get_currency("parts").to_float(), 3.0 * RobotBuilder.fragment_parts(), 0.001)
	var need: float = RobotBuilder.craft_parts("maker_shell")
	assert_almost_eq(need, 250.0 + RobotParts.value(3), 0.001, "250 parts + a Vintage part's worth")
	assert_string_contains(RobotBuilder.craft_block_reason("maker_shell"), "parts")
	GameState.add_currency("parts", BigNum.from_float(need - 3.0 * RobotBuilder.fragment_parts()))
	assert_true(RobotBuilder.craft("maker_shell"))
	assert_almost_eq(GameState.get_currency("parts").to_float(), 0.0, 0.001)
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
		assert_true(RobotBuilder.concrete_mods({}, str(t["id"])).is_empty(), "trait %s is flavour only" % t["id"])
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


func test_shop_lists_every_shop_part() -> void:
	var a: Array[String] = RobotBuilder.haggle_offers()
	assert_gt(a.size(), 3, "no rotation: every shop part is on offer")
	for id: String in a:
		assert_eq(RobotBuilder.source_kind(id), "haggle")
	assert_ne(RobotBuilder.buy_haggle(a[0]), "")
	GameState.add_currency("cubes", BigNum.from_float(5000))
	GameState.add_currency("parts", BigNum.from_float(250))
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
