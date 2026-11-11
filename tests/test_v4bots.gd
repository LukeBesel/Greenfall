extends GutTest
## [v4bots] Owner playtest 3 (docs/OWNER_FEEDBACK.md): items 44 and 46 (the Scoopie comes alone,
## the Haul Bug a while later, the water bot later still), 52 (Haul Bugs fetch Lumi's bales too)
## and 54 (Lumi needs Hover Jets to cross water).

var _flags: Dictionary
var _stats: Dictionary
var _ups: Dictionary
var _g5: SphereGrid
var _t5: SphereTerrain


class FakeWorld extends Node3D:
	var _cubes_root: Node3D
	var depot: Node3D = null


func before_all() -> void:
	_g5 = SphereGrid.new()
	_g5.generate(5)
	_g5.radius_m = SphereGrid.radius_for(5, 10.0)
	_t5 = SphereTerrain.new(_g5, 7)


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_ups = GameState.upgrades.duplicate()
	GameState.flags = {}
	GameState.upgrades = {}


func after_each() -> void:
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.upgrades = _ups


# --- 44 / 46: unlock order ----------------------------------------------------------------------

## Task M3-21 (docs/DECISIONS.md, Nov 11): the first robot is the answer to walking, so the Bot
## Bay brings the Haul Bug's plans and the Scoopie's follow.
func test_bot_bay_brings_only_the_haul_bug() -> void:
	for e: Dictionary in Research.def("salvage_logic").get("effects", []):
		assert_false(e.has("unlock_robot"), "Salvage Logic unlocks %s" % str(e))
	assert_eq(Research.robot_requirement("haulbug"), "haul_rig")
	assert_eq(Research.robot_requirement("scoopie"), "scoopie_rig")
	assert_eq(Research.robot_requirement("skimmer"), "skimmer_rig")
	assert_eq(Research.robot_requirement("drip"), "drip_blueprint", "Drip stays where it was (base 3)")


func test_story_unlocks_are_not_tree_cards() -> void:
	for id: String in Research.story_ids():
		assert_false(id in Research.ids(), "%s is not in the research graph" % id)
		assert_true(Research.exists(id))
		assert_ne(Research.reason(id), "", "%s can't be started" % id)
		assert_eq(Research.status(id), "locked")


func test_haul_bug_comes_with_the_bot_bay_and_the_scoopie_later() -> void:
	GameState.stats["robots_built"] = 0.0
	GameState.stats["time_played"] = 1000.0
	GameState.flags["bench_tier"] = 1
	Research.grant("salvage_logic")
	var done0: float = float(GameState.stats.get("research_done", 0.0))
	assert_true(Research.check_story().is_empty(), "no Bot Bay yet")
	GameState.flags["bench_tier"] = 2
	assert_eq(Research.check_story(), ["haul_rig"] as Array[String], "the Bot Bay brings the Haul Bug's plans")
	assert_true(Research.robot_unlocked("haulbug"))
	assert_true(bool(GameState.flags.get("haul_rig", false)))
	assert_false(Research.robot_unlocked("scoopie"), "the cleaner comes later")
	GameState.stats["robots_built"] = 1.0
	GameState.stats["hexes_cleaned"] = 14.0
	Research.check_story()
	assert_eq(float(GameState.flags.get("first_robot_t", -1.0)), 1000.0, "the first robot's time is kept")
	GameState.stats["time_played"] = 1000.0 + 400.0
	assert_true(Research.check_story().is_empty(), "too soon: the Haul Bug works alone for a while")
	GameState.stats["time_played"] = 1000.0 + 500.0
	GameState.stats["hexes_cleaned"] = 13.0
	assert_true(Research.check_story().is_empty(), "and not before 14 hexes are clean")
	GameState.stats["hexes_cleaned"] = 14.0
	assert_eq(Research.check_story(), ["scoopie_rig"] as Array[String])
	assert_true(Research.robot_unlocked("scoopie"))
	assert_true(bool(GameState.flags.get("scoopie_rig", false)), "the objective's wait_flag")
	assert_false(Research.robot_unlocked("skimmer"), "the water bot waits for a plant and more time")
	assert_eq(float(GameState.stats.get("research_done", 0.0)), done0, "plans that arrive are not research")
	GameState.stats["plants_planted"] = 1.0
	GameState.stats["time_played"] = 1000.0 + 2200.0
	assert_eq(Research.check_story(), ["skimmer_rig"] as Array[String])
	assert_true(Research.robot_unlocked("skimmer"))


func test_late_bases_get_the_plans_at_once() -> void:
	Research.grant("salvage_logic")
	var hl: Variant = GameState.world.get("hub_level", 1)
	GameState.world["hub_level"] = 3
	Research.check_story()
	assert_true(Research.robot_unlocked("haulbug"))
	assert_true(Research.robot_unlocked("scoopie"))
	assert_true(Research.robot_unlocked("skimmer"))
	GameState.world["hub_level"] = hl


func test_scoopie_objective_waits_after_base_two() -> void:
	var ids: Array = []
	var scoopie: Dictionary = {}
	for o: Dictionary in Economy.planet_table("tutorial")["objectives"]:
		ids.append(str(o["id"]))
		if str(o["id"]) == "scoopie":
			scoopie = o
	assert_gt(ids.find("robot"), ids.find("bench2"), "the first robot follows the Bot Bay")
	assert_gt(ids.find("scoopie"), ids.find("base2"), "the Scoopie comes well after the first robot")
	assert_gt(ids.find("zone"), ids.find("scoopie"), "a work zone is for the cleaner")
	assert_eq(str(scoopie.get("wait_flag", "")), "scoopie_rig")
	assert_true(scoopie.has("hint"))


func test_locked_scoopie_says_it_comes_later() -> void:
	Research.grant("salvage_logic")
	assert_false(Research.robot_lock_text("scoopie").begins_with("Research"), Research.robot_lock_text("scoopie"))
	assert_true(Research.robot_lock_text("seedling").begins_with("Research"))


# --- 52: haulers fetch Lumi's bales ------------------------------------------------------------

func _crew_world() -> Array:
	var cells := SphereCells.new(_g5.cell_count())
	var surface := SphereSurface.new(_g5.radius_m)
	surface.height_fn = _t5.height
	var w := FakeWorld.new()
	add_child_autofree(w)
	w._cubes_root = Node3D.new()
	w.add_child(w._cubes_root)
	var crew := SphereCrew.new()
	w.add_child(crew)
	crew.setup(_g5, cells, null, surface, SphereSwarm.new(surface))
	crew.world = w
	crew.set_process(false)
	crew.bale_view.set_process(false)
	var lumi := Node3D.new()
	w.add_child(lumi)
	lumi.global_position = surface.ground(_g5.centers[100])
	crew.focus = lumi
	return [crew, w, surface]


func _loose_bale(w: FakeWorld, surface: SphereSurface, v: float) -> JunkCube:
	var c := JunkCube.create(BigNum.from_float(v), SphereBales.bale_info(10.0))
	w._cubes_root.add_child(c)
	c.freeze = true
	var d: Vector3 = _g5.centers[100]
	var at: Vector3 = SphereMath.advance(d, SphereMath.any_perpendicular(d), 3.0 / surface.radius)[0]
	c.global_position = surface.ground(at) + at * 0.3  # 3 m from Lumi
	return c


func test_haulers_adopt_lumis_resting_bales() -> void:
	var a: Array = _crew_world()
	var crew: SphereCrew = a[0]
	var w: FakeWorld = a[1]
	var c: JunkCube = _loose_bale(w, a[2], 42.0)
	assert_eq(crew.bale_view.adopt_loose(5.0), 0, "no Haul Bug on the crew: Lumi's bales stay his")
	crew.spawn("haulbug", 0, 100)
	assert_eq(crew.bale_view.adopt_loose(1.0), 0, "just put down: not yet")
	assert_eq(crew.bale_view.adopt_loose(2.5), 1, "lying still a few seconds: the haulers' now")
	assert_eq(c.get_parent(), crew.bale_view)
	assert_eq(crew.bales.size(), 1)
	assert_almost_eq(float(crew.bales[0]["value"]), 42.0, 0.01, "no Depot here: the bale's value")
	assert_eq(crew.bale_view.cube_of(int(crew.bales[0]["id"])), c, "the same cube, not a copy")
	crew.bale_view.sync()
	assert_eq(crew.bales.size(), 1, "sync keeps it")
	c.carried = true  # Lumi takes it back
	crew.bale_view.sync()
	assert_true(crew.bales.is_empty(), "picked up again: his")
	var saved: Dictionary = crew.to_dict()
	assert_true((saved["bales"] as Array).is_empty())


func test_bales_on_a_pad_or_by_the_depot_stay_put() -> void:
	var a: Array = _crew_world()
	var crew: SphereCrew = a[0]
	var w: FakeWorld = a[1]
	var c: JunkCube = _loose_bale(w, a[2], 10.0)
	var dp := Node3D.new()
	w.add_child(dp)
	dp.global_position = c.global_position + Vector3(1, 0, 0)
	w.depot = dp
	crew.spawn("haulbug", 0, 100)
	assert_eq(crew.bale_view.adopt_loose(5.0), 0, "right by the scale: Lumi is cashing it himself")
	assert_eq(c.get_parent(), w._cubes_root)


# --- 54: Hover Jets -----------------------------------------------------------------------------

func test_shore_stops_and_slides() -> void:
	var lake: Callable = func(p: Vector3) -> bool: return p.x > 1.0  # water east of x = 1
	var up := Vector3.UP
	var east := Vector3(4, 0, 0)
	assert_eq(Patch.shore_clamp_at(Vector3.ZERO, up, east, 0.9, lake), east, "far from the shore: unchanged")
	var head_on: Vector3 = Patch.shore_clamp_at(Vector3(0.5, 0, 0), up, east, 0.9, lake)
	assert_lt(head_on.length(), east.length() * 0.5, "straight at the lake: (nearly) stops")
	assert_lt(0.5 + head_on.normalized().x * 0.9, 1.0, "never into it")
	assert_eq(Patch.shore_clamp_at(Vector3(0.5, 0, 0), up, east, 0.9, func(_p: Vector3) -> bool: return true), Vector3.ZERO, "water all round: stops")
	var diag := Vector3(3, 0, -3)
	var slid: Vector3 = Patch.shore_clamp_at(Vector3(0.5, 0, 0), up, diag, 0.9, lake)
	assert_gt(slid.length(), 0.1, "at an angle: slides along the shore")
	assert_lt(slid.x * 0.9 / slid.length() + 0.5, 1.0, "and stays on land")


func test_hover_jets_upgrade() -> void:
	var u: Dictionary = Economy.upgrade_defs.get("hover_jets", {})
	assert_false(u.is_empty())
	assert_eq(str(u["stat"]), "hover_water")
	assert_eq(int(u["max_level"]), 1)
	assert_eq(Economy.stat("hover_water"), 0.0, "Lumi starts without them")
	GameState.upgrades["hover_jets"] = 1
	assert_eq(Economy.stat("hover_water"), 1.0)
	assert_true("hover_jets" in Economy.read_json("res://data/workbench.json")["upgrade_order"])
