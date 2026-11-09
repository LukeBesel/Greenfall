extends GutTest
## [camp2] Everything but the bench and the bin is a Hub build (systems/camp/hub_builds.gd,
## data/builds.json): one-time builds drop off once built, tiered ones offer only their next tier,
## nothing is listed before it is unlocked, and old saves keep what already stood.

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary
var _world: Dictionary
var _districts: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_world = GameState.world
	_districts = GameState.districts
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.world = _world
	GameState.districts = _districts


func _ids(kind: String) -> Array:
	return HubBuilds.available(null, kind).map(func(e: Dictionary) -> String: return str(e["id"]))


func test_every_build_has_a_kind_and_a_name() -> void:
	assert_gte(HubBuilds.ids().size(), 12)
	for id: String in HubBuilds.ids():
		assert_true(str(HubBuilds.def(id).get("kind", "")) in ["one_time", "tiered"], "%s has a kind" % id)
	for id: String in YardBuilds.IDS:
		assert_true(id in HubBuilds.ids(), "%s is in data/builds.json" % id)
		assert_ne(str(HubBuilds.entry(null, id)["name"]), id, "%s has a display name" % id)


func test_fresh_base_offers_only_unlocked_things() -> void:
	var once: Array = _ids("one_time")
	for id: String in ["shack", "generator", "lamps"]:
		assert_has(once, id)
	for id: String in ["composter", "nursery", "conveyor", "telescope", "museum"]:
		assert_does_not_have(once, id, "%s isn't offered before it is unlocked" % id)
	assert_eq(_ids("tiered"), ["trash_bin"], "the bin's next level is the only upgrade")
	GameState.flags["first_sprout"] = true
	assert_has(_ids("one_time"), "composter", "the compost press opens once something grows")


func test_one_time_builds_drop_off_and_need_the_bench() -> void:
	GameState.add_currency("cubes", BigNum.from_float(1.0e5))
	GameState.add_currency("parts", BigNum.from_float(1.0e3))
	assert_ne(str(HubBuilds.entry(null, "shack")["reason"]), "", "the bench comes first")
	assert_false(HubBuilds.build(null, "shack"))
	Camp.set_bench_ok(true)
	assert_true(HubBuilds.build(null, "shack"))
	assert_does_not_have(_ids("one_time"), "shack", "built: off the list")
	assert_has(HubBuilds.built_names(null), "Lean-to")
	assert_false(HubBuilds.build(null, "shack"), "only once")


func test_tiered_shows_only_the_next_tier() -> void:
	GameState.add_currency("cubes", BigNum.from_float(1.0e6))
	var e: Dictionary = HubBuilds.entry(null, "trash_bin")
	assert_eq(str(e["kind"]), "tiered")
	assert_eq(str(e["name"]), str(TrashBin.level_def(2)["name"]))
	assert_true(HubBuilds.build(null, "trash_bin"))
	assert_eq(str(HubBuilds.entry(null, "trash_bin")["name"]), str(TrashBin.level_def(3)["name"]), "then the one after")
	assert_eq(HubBuilds.kind_now("signal_tower"), "one_time", "the first tower is a building")
	GameState.flags["signal_tower"] = 1
	assert_eq(HubBuilds.kind_now("signal_tower"), "tiered", "its next tiers are upgrades")


func test_old_saves_keep_what_stood() -> void:
	GameState.world = {"field": {}, "hub_level": 2}
	GameState.flags["first_sprout"] = true
	Camp.migrate2()
	for id: String in ["shack", "generator", "lamps", "composter"]:
		assert_true(YardBuilds.built(id), "%s already stood: built" % id)
	GameState.world = {}
	GameState.flags = {}
	Camp.migrate2()
	for id: String in ["shack", "generator", "lamps", "composter"]:
		assert_false(YardBuilds.built(id), "a fresh base has no %s" % id)
	var comp := Composter.new()
	assert_false(comp.active(), "an unbuilt compost press does nothing")
	comp.free()
