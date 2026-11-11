extends GutTest
## Goals in tiers (task M3-10, design spec section 10; story/goals.gd, story/goal_measures.gd,
## story/goal_guide.gd, ui/goal_readout.gd, the planet's "goals" table): one goal of each tier is
## always active; a finished goal pays at once and the next of its tier takes its place; repeating
## goals keep a tier from standing empty; every goal points somewhere; the story card stays the
## first guide; old saves keep what they finished. Tier ids, goals and amounts are the planet's:
## the first planet has short, medium and long, the dummy planet has its own two.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]


class FakeFleet extends Node:
	var counts: Dictionary = {}

	func count(type_id: String) -> int:
		return int(counts.get(type_id, 0))

	func robot_total() -> int:
		var n: int = 0
		for k: String in counts:
			n += int(counts[k])
		return n


class FakeWorld extends Node:
	var fleet: FakeFleet
	var hex_levels: HexLevels
	var goals: Goals
	var patch: Patch
	var field: HexField
	var hud: Node
	var depot: Node3D


var _saved: Dictionary = {}
var _planet: StringName
var _tier_events: Array = []


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)
	_planet = Planets.current().id


func after_all() -> void:
	Planets.set_current(_planet)


func before_each() -> void:
	_saved = {"cur": GameState.currencies, "flags": GameState.flags, "stats": GameState.stats, "world": GameState.world,
		"upgrades": GameState.upgrades, "global": GameState.global.duplicate(true)}
	GameState.flags = {}
	GameState.currencies = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.upgrades = {}
	_tier_events = []


func after_each() -> void:
	GameState.currencies = _saved["cur"]
	GameState.flags = _saved["flags"]
	GameState.stats = _saved["stats"]
	GameState.world = _saved["world"]
	GameState.upgrades = _saved["upgrades"]
	GameState.global = _saved["global"]
	Planets.set_current(_planet)


func _make(planet_id: StringName = FIRST) -> Goals:
	Planets.set_current(planet_id)
	var w := FakeWorld.new()
	w.fleet = FakeFleet.new()
	w.add_child(w.fleet)
	add_child_autofree(w)
	var g := Goals.new()
	g.world = w
	w.goals = g
	w.add_child(g)
	g.set_process(false)
	return g


func _index(g: Goals, id: String) -> int:
	for i: int in g.chain.size():
		if str(g.chain[i]["id"]) == id:
			return i
	return -1


func _cubes() -> float:
	return GameState.get_currency("cubes").to_float()


## Makes goal `i` hold: raises what it counts to its target.
func _satisfy(g: Goals, i: int) -> void:
	var d: Dictionary = g.chain[i]
	var key: String = str(d.get("key", ""))
	var need: float = g.target_of(i)
	match str(d.get("type", "stat")):
		"stat":
			GameState.stats[key] = need
		"earned":
			GameState.stats["cubes_earned_total"] = BigNum.from_float(need).serialize()
		"upgrade":
			GameState.upgrades[key] = int(need)
		"flag":
			GameState.flags[key] = true
		"robot":
			(g.world as FakeWorld).fleet.counts["scoopie" if key == "any" else key] = int(need)
		"zone":
			var zone: Array = []
			for h: int in int(need):
				zone.append(h)
			GameState.world["orders"] = {"groups": {"clean": {"zone": zone}}}


# --- The table ----------------------------------------------------------------------------------

func test_every_goal_belongs_to_a_tier_of_the_table(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var tiers: Array[String] = g.tier_ids()
	assert_gte(tiers.size(), 2, "the planet names its tiers")
	assert_true(str(g.cfg.get("_doc", "")).length() > 40, "the table documents its fields")
	var ids: Dictionary = {}
	var per_tier: Dictionary = {}
	for i: int in g.chain.size():
		var e: Dictionary = g.chain[i]
		assert_false(ids.has(e["id"]), "duplicate goal id " + str(e["id"]))
		ids[e["id"]] = true
		assert_true(e.has("text") and e.has("type") and e.has("reward"), "goal %s has text, type and reward" % e["id"])
		assert_has(tiers, g.tier_of(i), "goal %s names a tier of the table" % e["id"])
		assert_has(GoalMeasures.TYPES, str(e["type"]), "goal %s counts something the game measures" % e["id"])
		assert_true(e.has("target") != e.has("repeat"), "goal %s has a target or repeats, not both" % e["id"])
		per_tier[g.tier_of(i)] = int(per_tier.get(g.tier_of(i), 0)) + 1
	for tier: String in tiers:
		assert_gt(int(per_tier.get(tier, 0)), 0, "tier %s has goals" % tier)
		assert_ne(g.tier_name(tier), "", "tier %s has a label" % tier)


func test_the_first_planet_has_short_medium_and_long() -> void:
	var g: Goals = _make()
	assert_eq(g.tier_ids(), ["short", "medium", "long"] as Array[String])
	var kinds: Dictionary = {}
	for i: int in g.chain.size():
		kinds["%s:%s" % [g.tier_of(i), str(g.chain[i]["type"])]] = true
	for want: String in ["medium:mastery", "medium:source", "medium:robot", "medium:city_stage", "long:launch", "long:set_pieces",
			"long:planet_share", "short:rig", "short:build", "short:mastery"]:
		assert_true(kinds.has(want), "the chain has a %s goal" % want)


func test_the_chain_follows_what_the_game_has_now() -> void:
	var g: Goals = _make()
	var ids: Array = g.chain.map(func(x: Dictionary) -> String: return str(x["id"]))
	for id: String in ["surge_1", "rig_plate_cutter", "wrecks_1", "scrounger_1", "assembler", "locker_build", "old_town_source", "sprout_set"]:
		assert_has(ids, id)
	for gone: String in ["rocket", "visit_dust", "cradle_home", "frontiers_growing", "base5_2", "late_garden_1", "extras_radio",
			"extras_retire", "builder_full", "shards_1", "pet_cat", "tank_1", "air_1k", "recycle_5"]:
		assert_does_not_have(ids, gone, "%s pointed at a parked or side system" % gone)
	var kinds: Array = (Economy.planet_table(Pollution.TABLE)["kinds"] as Dictionary).keys()
	var rigs: Dictionary = Economy.planet_table(Rigs.TABLE)["modules"]
	var cities: Array = (Economy.planet_table(Districts.TABLE)["districts"] as Array).map(func(c: Dictionary) -> String: return str(c["id"]))
	for e: Dictionary in g.chain:
		var all: Array = [e]
		if e.has("when"):
			all.append(e["when"])
		for d: Dictionary in all:
			match str(d.get("type", "")):
				"mastery":
					assert_has(kinds, str(d["key"]), "%s names a real pollution kind" % e["id"])
				"rig":
					assert_true(rigs.has(str(d["key"])), "%s names a real rig module" % e["id"])
				"city_stage", "source":
					assert_has(cities, str(d["key"]), "%s names a real city" % e["id"])
				"robot":
					assert_true(str(d["key"]) == "any" or Economy.robots.has(str(d["key"])), "%s names a real robot" % e["id"])
				"upgrade":
					assert_true(Economy.upgrade_defs.has(str(d["key"])), "%s names a real upgrade" % e["id"])
	for kind: String in kinds:
		assert_true(g.chain.any(func(e: Dictionary) -> bool: return str(e["type"]) == "mastery" and str(e["key"]) == kind), "a goal for %s" % kind)
	for city: String in cities:
		assert_has(ids, city + "_source", "a goal for %s's source job" % city)


# --- One active goal per tier ---------------------------------------------------------------------

func test_a_fresh_game_has_one_active_goal_per_tier(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var cur: Array[int] = g.current()
	assert_eq(cur.size(), g.tier_ids().size(), "one goal for every tier")
	for k: int in cur.size():
		assert_eq(g.tier_of(cur[k]), g.tier_ids()[k], "in the table's tier order")


func test_a_tier_with_a_repeating_goal_never_stands_empty(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var endless: Array[String] = []
	for i: int in g.chain.size():
		if g.is_repeat(i) and not g.tier_of(i) in endless and not g.chain[i].has("when"):
			endless.append(g.tier_of(i))
	assert_false(endless.is_empty(), "the planet has a tier that never runs out")
	for round_: int in 150:
		for tier: String in endless:
			var i: int = g.active(tier)
			assert_gte(i, 0, "tier %s has an active goal after %d completions" % [tier, round_])
			if i < 0:
				return
			g.check()  # a repeating goal starts counting once it is the active one
			g.complete(i)
	if planet_id == FIRST:
		assert_has(endless, "short")
		assert_has(endless, "medium")
		assert_gte(g.active("long"), 0, "the planet's arc is still running")


func test_the_next_goal_of_the_tier_takes_its_place(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	g.tier_changed.connect(func(tier: String, index: int) -> void: _tier_events.append([tier, index]))
	g.check()
	var tier: String = g.tier_ids()[0]
	var other: String = g.tier_ids()[1]
	var first: int = g.active(tier)
	var kept: int = g.active(other)
	g.complete(first)
	var next: int = g.active(tier)
	assert_gte(next, 0)
	assert_true(next != first or g.is_repeat(first), "a new goal, or the same job asked again")
	assert_eq(g.active(other), kept, "the other tier keeps its goal")
	assert_eq(_tier_events, [[tier, next]], "and the change is announced once, for that tier only")


# --- Paying ---------------------------------------------------------------------------------------

func test_a_finished_goal_pays_at_once_and_is_saved() -> void:
	var g: Goals = _make()
	var first: int = g.active("short")
	assert_eq(g.check(), -1, "nothing done yet")
	_satisfy(g, first)
	assert_eq(g.check(), first)
	assert_true(g.is_done(first))
	assert_almost_eq(_cubes(), float(g.reward_of(first)["cubes"]), 0.01)
	assert_ne(g.active("short"), first, "the next short goal is up")
	assert_eq(GameState.flags[Goals.FLAG_DONE], [str(g.chain[first]["id"])])
	var again: Goals = _make()
	assert_true(again.is_done(first), "a reload keeps it")
	assert_eq(again.active("short"), g.active("short"))


func test_goals_pay_one_per_beat_wherever_they_stand() -> void:
	var g: Goals = _make()
	var far: int = _index(g, "hex_5")
	assert_ne(g.active(g.tier_of(far)), far, "a goal that is not on show yet")
	GameState.stats["hexes_cleaned"] = 5
	GameState.stats["junk_scooped"] = 100.0
	var done: Array[int] = []
	for _beat: int in 3:
		done.append(g.check())
	assert_eq(done.count(-1), 0, "one goal per beat")
	assert_eq(g.done_count(), 3)
	assert_true(g.is_done(far), "it pays although another goal of its tier is the active one")
	assert_true(g.is_done(_index(g, "hex_3")))
	var expect: float = 0.0
	for i: int in done:
		expect += float(g.reward_of(i).get("cubes", 0.0))
	assert_almost_eq(_cubes(), expect, 0.001)
	assert_eq(g.check(), -1, "paid once")


func test_a_goal_waits_for_what_it_belongs_to() -> void:
	var g: Goals = _make()
	var cutter: int = _index(g, "rig_plate_cutter")
	var surge: int = _index(g, "surge_1")
	assert_false(g.is_offered(cutter), "a second city's tool is not asked for in the first")
	assert_false(g.is_offered(surge), "nor a Surge before the first robot opens it")
	GameState.stats["surges_released"] = 1
	assert_eq(g.check(), -1, "and a goal that is not on offer does not pay")
	GameState.stats["robots_built"] = 1
	assert_true(g.is_offered(surge))
	assert_ne(g.active("short"), surge, "the HUD's goal changes on the beat, not in between")
	assert_eq(g.check(), surge)


func test_a_goal_nobody_works_on_steps_aside_and_still_pays() -> void:
	var g: Goals = _make()
	var limit: float = g.patience_s("short")
	assert_gt(limit, 0.0, "the short tier has a patience")
	assert_eq(g.patience_s("medium"), 0.0, "a city milestone may take as long as it takes")
	GameState.stats["time_played"] = 100.0
	g.check()
	var first: int = g.active("short")
	var medium: int = g.active("medium")
	GameState.stats["time_played"] = 100.0 + limit - 1.0
	g.check()
	assert_eq(g.active("short"), first, "inside its patience it keeps the row")
	GameState.stats[str(g.chain[first]["key"])] = g.target_of(first) - 1.0
	GameState.stats["time_played"] = 100.0 + limit + 50.0
	g.check()
	assert_eq(g.active("short"), first, "progress starts the wait again")
	GameState.stats["time_played"] = 100.0 + limit * 2.0 + 60.0
	g.check()
	assert_ne(g.active("short"), first, "no progress for the whole patience: the next goal takes the row")
	assert_true(g.is_aside(first))
	assert_false(g.is_done(first))
	assert_eq(g.active("medium"), medium, "the medium goal is not hurried")
	assert_true(_make().is_aside(first), "a reload does not bring it back to the row")
	_satisfy(g, first)
	assert_eq(g.check(), first, "it still pays when it is finished")
	assert_gt(_cubes(), 0.0)


# --- Repeating goals ------------------------------------------------------------------------------

func test_a_repeating_goal_counts_from_when_it_came_up(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var rep: int = -1
	for i: int in g.chain.size():
		if g.is_repeat(i) and not g.chain[i].has("when") and rep < 0:
			rep = i
	var tier: String = g.tier_of(rep)
	var key: String = str(g.chain[rep]["key"])
	GameState.stats[key] = 1000.0
	for i: int in g.chain.size():  # every authored goal is behind us
		if not g.is_repeat(i):
			g.complete(i)
	GameState.currencies = {}
	assert_eq(g.active(tier), rep)
	assert_eq(g.check(), -1, "work done before it came up does not count")
	var amount: int = g.repeat_amount(rep)
	assert_eq(amount, int(g.chain[rep]["repeat"]))
	assert_eq(g.counts(rep), [0.0, float(amount)] as Array[float], "the HUD counts from zero")
	assert_true(g.text_of(rep).contains(str(amount)), "the title says how many: %s" % g.text_of(rep))
	GameState.stats[key] = 1000.0 + amount - 1
	assert_eq(g.check(), -1)
	assert_almost_eq(g.progress(rep), float(amount - 1) / float(amount), 0.001)
	GameState.stats[key] = 1000.0 + amount
	assert_eq(g.check(), rep)
	assert_eq(g.times_done(rep), 1)
	assert_false(g.is_done(rep), "it comes round again")
	assert_almost_eq(_cubes(), float(g.reward_of(rep).get("cubes", 0.0)), 0.001, "paid each time")
	if int(g.chain[rep].get("repeat_grow", 0)) > 0:
		assert_gt(g.repeat_amount(rep), amount, "and asks for more next time")
	for _n: int in 40:
		g.complete(rep)
	assert_lte(g.repeat_amount(rep), int(g.chain[rep]["repeat_max"]), "up to the table's cap")


## Runs the beats until nothing more completes; returns what was finished.
func _settle(g: Goals) -> Array[int]:
	var done: Array[int] = []
	for _beat: int in 40:
		var i: int = g.check()
		if i < 0:
			break
		done.append(i)
	return done


func test_repeating_goals_count_side_by_side_and_the_row_shows_the_nearest() -> void:
	var g: Goals = _make()
	for i: int in g.chain.size():
		if not g.is_repeat(i):
			g.complete(i)
	var ground: int = _index(g, "more_ground")
	var crew: int = _index(g, "more_crew")
	_settle(g)
	assert_eq(g.active("medium"), ground, "nothing started: the first in the table")
	GameState.stats["hexes_cleaned"] = 0.35 * g.repeat_amount(ground)
	GameState.stats["robots_built"] = 0.4 * g.repeat_amount(crew)
	_settle(g)
	assert_eq(g.active("medium"), ground, "a job a little further along does not take the row")
	GameState.stats["robots_built"] = 0.8 * g.repeat_amount(crew)
	_settle(g)
	assert_eq(g.active("medium"), crew, "the job clearly nearest done is the one on show")
	var again: Goals = _make()
	assert_eq(again.active("medium"), crew, "a reload keeps the row")
	assert_almost_eq(again.counts(ground)[0], 0.35 * again.repeat_amount(ground), 0.001, "and every count so far")
	var asked: int = again.repeat_amount(ground)
	GameState.stats["hexes_cleaned"] = float(asked)
	assert_has(_settle(again), ground, "a job off the row still pays when it is finished")
	assert_eq(again.times_done(ground), 1)
	assert_eq(again.active("medium"), crew, "and the row keeps its job")
	assert_gt(again.repeat_amount(ground), asked, "the finished job asks for more next time")
	assert_eq(again.counts(ground)[0], 0.0, "counted from now")
	assert_eq(_make().times_done(ground), 1)


func test_repeating_goals_wait_until_the_tier_falls_back_on_them() -> void:
	var g: Goals = _make()
	var hexes: int = _index(g, "more_hexes")
	GameState.stats["hexes_cleaned"] = 2.0
	var done: Array[int] = _settle(g)
	assert_does_not_have(done, hexes, "while the firsts are running a repeating goal does not pay")
	assert_false(g.is_repeat(g.active("short")))


# --- Measures -------------------------------------------------------------------------------------

func test_value_types() -> void:
	var g: Goals = _make()
	(g.world as FakeWorld).fleet.counts["scoopie"] = 1
	(g.world as FakeWorld).fleet.counts["haulbug"] = 2
	assert_eq(g.value_of(_index(g, "crew_2")), 3.0, "a crew goal counts every robot")
	assert_eq(GoalMeasures.value(g.world, {"type": "robot", "key": "scoopie"}), 1.0)
	GameState.world["hub_level"] = 2
	assert_eq(GoalMeasures.value(g.world, {"type": "hub_level"}), 2.0)
	GameState.world["orders"] = {"groups": {"clean": {"zone": [3, 4], "mode": "stay"}}, "bots": {"Bolt-01": {"zone": [4, 5]}}}
	assert_eq(g.value_of(_index(g, "zone_6")), 3.0)
	GameState.flags["tier_drip"] = 2
	assert_eq(GoalMeasures.value(g.world, {"type": "tier", "key": "any"}), 2.0)
	assert_eq(g.value_of(_index(g, "hexlv_4")), 0.0, "no hex levels node -> 0")
	GameState.add_currency("cubes", BigNum.from_float(1500))
	assert_gte(g.value_of(_index(g, "earn_1k")), 1500.0)
	assert_almost_eq(g.progress(_index(g, "earn_1k")), 1.0, 0.001)
	for id: String in ["litter_2", "rig_plate_cutter", "assembler", "old_town_source", "planet_1", "launch_point", "old_town_1"]:
		assert_eq(g.value_of(_index(g, id)), 0.0, "%s waits while its system is not in the world" % id)


func test_mastery_and_rig_goals_read_the_live_systems() -> void:
	var g: Goals = _make()
	var mastery := Mastery.new()
	g.world.add_child(mastery)
	mastery.setup(Planets.current())
	mastery.grant("litter", 2)
	assert_eq(g.value_of(_index(g, "litter_2")), 2.0)
	assert_eq(g.check(), _index(g, "litter_2"), "a mastery level finishes its goal")
	var rigs := Rigs.new()
	g.world.add_child(rigs)
	rigs.setup(Planets.current())
	rigs.grant("plate_cutter", true)
	assert_eq(g.value_of(_index(g, "rig_plate_cutter")), 1.0)
	rigs.unfit("arm")
	assert_eq(g.value_of(_index(g, "rig_plate_cutter")), 0.0, "the goal asks for the tool to be on Lumi")


func test_the_set_goal_counts_found_pieces() -> void:
	var g: Goals = _make()
	var set_goal: int = _index(g, "sprout_set")
	var pieces: Array[String] = Looks.set_ids(str(g.chain[set_goal]["key"]))
	assert_eq(float(pieces.size()), g.target_of(set_goal), "the goal asks for the whole set")
	assert_eq(g.value_of(set_goal), 0.0)
	Looks.grant(pieces[0], "buried", true)
	assert_eq(g.value_of(set_goal), 1.0)


func test_a_city_stage_goal_fills_as_the_city_comes_clean(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var fx := DistrictFixture.new(planet_id)
	var d: Districts = fx.districts
	var id: String = d.ids()[0]
	var need: int = ceili(d.stage_share * d.land_of(id) - 0.000001)
	var def: Dictionary = {"type": Restoration.MEASURE_CITY_STAGE, "key": id, "target": 2}
	assert_eq(GoalMeasures.value(null, def), 0.0)
	fx.set_district_stage(id, 1, need / 2)
	var part: float = GoalMeasures.value(null, def)
	assert_gt(part, 0.0, "the gauge moves before the first stage")
	assert_lt(part, 1.0, "but does not read as the stage")
	fx.set_district_stage(id, 1, need)
	assert_eq(d.stage_of(id), 1)
	assert_gte(GoalMeasures.value(null, def), 1.0)
	assert_lt(GoalMeasures.value(null, def), 2.0, "a stage goal is met only by the stage itself")
	fx.free_systems()


# --- Guidance -------------------------------------------------------------------------------------

func test_every_goal_points_somewhere(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var o := Objectives.new()
	o.world = g.world
	for i: int in g.chain.size():
		var t: Dictionary = o.step_target(o.goal_def(i))
		assert_ne(str(t.get("to", "")), "", "goal %s points somewhere" % g.chain[i]["id"])
		assert_true(t.has("row"))
	o.free()


func test_goals_point_at_what_they_ask_for() -> void:
	var g: Goals = _make()
	var cases: Dictionary = {"rig_plate_cutter": ["bench", ["rigs", "plate_cutter"]], "assembler": ["bench", ["build", "assembler"]],
		"locker_build": ["bench", ["build", "locker"]], "scrounger_1": ["bench", ["bots", ""]], "lift_1": ["bench", ["patch", "lift_strength"]],
		"wrecks_1": ["hex", []], "old_town_1": ["hex", []], "hex_5": ["hex", []]}
	for id: String in cases:
		var t: Dictionary = GoalGuide.target(g.world, g.chain[_index(g, id)])
		assert_eq(str(t["to"]), str(cases[id][0]), id)
		assert_eq(t["row"], cases[id][1], id)
	var job: Dictionary = GoalGuide.target(g.world, g.chain[_index(g, "old_town_source")])
	assert_eq(str(job["to"]), GoalGuide.TO_SOURCE)
	assert_eq(str(job["district"]), "old_town")
	var o := Objectives.new()
	o.world = g.world
	assert_eq(str(o.step_target(o.goal_def(_index(g, "old_town_source")))["to"]), "hex", "no job on offer yet: clean the city meanwhile")
	o.free()


# --- The story card stays the first guide ------------------------------------------------------------

func _objectives(g: Goals) -> Objectives:
	var o := Objectives.new()
	o.world = g.world
	o.chain = [{"id": "a", "text": "A", "desc": "a", "type": "stat", "key": "m310_a", "target": 1}]
	o.revealed = true
	return o


func test_the_card_keeps_its_story_step_beside_three_goals() -> void:
	var g: Goals = _make()
	var o: Objectives = _objectives(g)
	assert_eq(str(o.current().get("id", "")), "a", "the story step is on the card")
	assert_false(o.current().has("_goal"))
	assert_eq(g.current().size(), 3, "and one goal of each tier beside it")
	o.sync_goals()
	assert_eq(g.card_goal, -1, "the card carries no goal while the story runs")
	o.free()


func test_after_the_story_the_card_carries_the_short_goal() -> void:
	var g: Goals = _make()
	var o: Objectives = _objectives(g)
	o.step = 1
	var d: Dictionary = o.current()
	assert_eq(int(d.get("_goal", -1)), g.active("short"), "the next concrete thing")
	o.sync_goals()
	assert_eq(g.card_goal, g.active("short"))
	_satisfy(g, g.card_goal)
	assert_ne(g.check(), g.card_goal, "the card completes its own goal")
	var readout := GoalReadout.new()
	add_child_autofree(readout)
	readout.bind(g)
	readout._process(0.1)
	assert_eq(readout.visible_rows(), 2, "the readout leaves out the row the card is carrying")
	o.free()


func test_the_beam_can_follow_a_goal_and_falls_back_to_the_card() -> void:
	var g: Goals = _make()
	var o: Objectives = _objectives(g)
	assert_eq(str(o.guided().get("id", "")), "a", "the card's step by default")
	var medium: int = g.active("medium")
	o.track(medium)
	assert_eq(int(o.guided().get("_goal", -1)), medium)
	assert_eq(str(o.current().get("id", "")), "a", "the card itself does not change")
	o.track(_index(g, "launch_point"))
	assert_eq(o.tracked_goal, -1, "only an active goal can be followed")
	o.track(medium)
	g.complete(medium)
	o.sync_goals()
	assert_eq(o.tracked_goal, -1, "a finished goal lets go of the beam")
	assert_eq(str(o.guided().get("id", "")), "a")
	o.free()


# --- The readout ----------------------------------------------------------------------------------

func test_the_readout_shows_a_row_per_tier(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var readout := GoalReadout.new()
	add_child_autofree(readout)
	readout.bind(g)
	readout._process(0.1)
	var rows: Array = readout.row_texts()
	assert_eq(rows.size(), g.tier_ids().size())
	for k: int in rows.size():
		var i: int = g.active(g.tier_ids()[k])
		assert_eq(str(rows[k][0]), tr(g.tier_name(g.tier_ids()[k])), "the tier's label")
		assert_eq(str(rows[k][1]), g.text_of(i), "the tier's active goal")


func test_a_finished_row_is_stamped_then_the_next_goal_comes_in() -> void:
	var g: Goals = _make()
	var readout := GoalReadout.new()
	add_child_autofree(readout)
	readout.bind(g)
	readout._process(0.1)
	var first: int = g.active("short")
	var title: String = g.text_of(first)
	g.complete(first)
	readout._process(0.1)
	assert_eq(str(readout.row_texts()[0][1]), title, "the finished goal stays for a beat")
	assert_eq(str(readout.row_texts()[0][2]), tr("DONE"))
	assert_does_not_have(readout.shown_goals(), first, "and cannot be followed any more")
	readout._process(GoalReadout.DONE_S)
	readout._process(0.01)
	assert_eq(str(readout.row_texts()[0][1]), g.text_of(g.active("short")), "then the next of its tier is revealed")
	assert_gt(float(readout._rows[0]["reveal"]), 0.0, "sliding in")
	readout._process(GoalReadout.REVEAL_S)
	assert_eq(float(readout._rows[0]["reveal"]), 0.0)


func test_goal_titles_fit_the_readout(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var g: Goals = _make(planet_id)
	var font: Font = UITheme.font()
	for i: int in g.chain.size():
		for n: int in ([0, 60] if g.is_repeat(i) else [0]):
			g._counts[str(g.chain[i]["id"])] = n
			var w: float = font.get_string_size(g.text_of(i), HORIZONTAL_ALIGNMENT_LEFT, -1, GoalReadout.FONT_PX).x
			assert_lte(w, GoalReadout.TITLE_W, "'%s' fits its row (%.0f px)" % [g.text_of(i), w])
	assert_gte(GoalReadout.FONT_PX, 16, "the style guide's smallest type")


func test_counts_read_as_counts_shares_and_single_things() -> void:
	var g: Goals = _make()
	GameState.stats["hexes_cleaned"] = 2
	assert_eq(GoalReadout.count_text(g, _index(g, "hex_5")), "2 / 5")
	assert_eq(GoalReadout.count_text(g, _index(g, "dump_1")), "", "one thing to do needs no count")
	assert_eq(GoalReadout.count_text(g, _index(g, "launch_point")), "0%")
	assert_eq(GoalReadout.count_text(g, _index(g, "planet_5")), "0%")


# --- Old saves ------------------------------------------------------------------------------------

func test_an_old_save_keeps_what_it_finished() -> void:
	# A save from the single chain: finished ids, some of them gone from the table since.
	GameState.flags = {"goals_done": ["scoop_15", "dump_1", "upgrade_1", "hex_1", "rocket", "extras_radio", "hex_5"]}
	GameState.stats = {"junk_scooped": 400.0, "junk_dumps": 9.0, "upgrades_bought": 14.0, "hexes_cleaned": 16.0, "cubes_cashed": 30.0}
	GameState.upgrades = {"baler": 1}
	var g: Goals = _make()
	for id: String in ["scoop_15", "dump_1", "upgrade_1", "hex_5"]:
		assert_true(g.is_done(_index(g, id)), "%s stays finished" % id)
	assert_eq(g.done_count(), 4, "ids the table no longer has are not counted")
	g.check()
	for id: String in ["upgrades_5", "upgrades_12", "hex_3", "hex_12", "cash_10"]:
		assert_true(g.is_done(_index(g, id)), "%s already holds: caught up" % id)
	assert_eq(_cubes(), 0.0, "without a payout for work done long ago")
	assert_eq(int(GameState.stats.get(Goals.STAT_DONE, 0)), 0, "and without a run of notices")
	assert_has(GameState.flags["goals_done"] as Array, "rocket", "the save keeps every id it had")
	assert_eq(g.current().size(), 3, "and every tier goes on")
	GameState.stats["hexes_cleaned"] = 25.0
	assert_eq(g.check(), _index(g, "hex_25"), "from here on goals pay as usual")
	assert_gt(_cubes(), 0.0)
	var again: Goals = _make()
	GameState.upgrades["lift_strength"] = 1
	assert_eq(again.check(), _index(again, "lift_1"), "a migrated save is not caught up twice")


func test_a_new_game_is_not_treated_as_an_old_save() -> void:
	var g: Goals = _make()
	_satisfy(g, g.active("short"))
	assert_gte(g.check(), 0)
	assert_gt(_cubes(), 0.0, "a first goal pays")


# --- The bot's gap table ----------------------------------------------------------------------------

func test_the_bot_reports_the_longest_gap_by_tier() -> void:
	var g: Goals = _make()
	var log := AutoplayGoals.new()
	assert_eq(AutoplayGoals.longest_gap([100.0, 130.0, 400.0], 30.0, 500.0), [270.0, 130.0] as Array[float])
	assert_eq(AutoplayGoals.longest_gap([], 30.0, 500.0), [470.0, 30.0] as Array[float], "nothing finished: the whole run is the gap")
	log.on_completed(g, g.active("short"), 100.0)
	log.on_completed(g, g.active("medium"), 200.0)
	log.on_completed(g, g.active("short"), 330.0)
	var report: Dictionary = {}
	log.write(report, g, 30.0, 400.0)
	var rows: Array = report["goal_tiers"]
	assert_eq(rows.size(), 4, "a row per tier and one for all")
	assert_eq(str(rows[0]["tier"]), "short")
	assert_eq(int(rows[0]["done"]), 2)
	assert_almost_eq(float(rows[0]["longest_gap_s"]), 230.0, 0.01)
	assert_almost_eq(float(rows[2]["longest_gap_s"]), 370.0, 0.01, "the long tier finished nothing")
	assert_almost_eq(float(report["goal_gap_longest_s"]), 130.0, 0.01, "over all tiers")
	assert_true(bool(report["goal_gap_ok"]))
	log.write(report, g, 30.0, 1000.0)
	assert_false(bool(report["goal_gap_ok"]), "more than four minutes with nothing finished fails")
	assert_eq(AutoplayGoals.GAP_LIMIT_S, 240.0)
