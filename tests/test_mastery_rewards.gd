extends GutTest
## What mastery levels pay (systems/mastery_rewards.gd): the rewards of the parked Lumi Level bar,
## same formula and numbers, paid per mastery level Lumi gains by hand. The dummy planet has no
## reward block and pays nothing.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"

var _saved: Dictionary = {}
var _world: Node


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.set_current(FIRST)
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = {"currencies": GameState.currencies, "flags": GameState.flags, "stats": GameState.stats}
	GameState.currencies = {}
	GameState.flags = {}
	GameState.stats = {}
	Planets.set_current(FIRST)


func after_each() -> void:
	if is_instance_valid(_world):
		_world.free()
	GameState.currencies = _saved["currencies"]
	GameState.flags = _saved["flags"]
	GameState.stats = _saved["stats"]


## A bare world with Lumi's mastery and the rewards listening to it.
func _make_world() -> Mastery:
	_world = Node.new()
	add_child(_world)
	var m := Mastery.new()
	_world.add_child(m)
	m.setup(Planets.current())
	var r := MasteryRewards.new()
	r.world = _world
	_world.add_child(r)
	return m


func test_the_schedule_is_the_old_level_bars() -> void:
	var c: Dictionary = MasteryRewards.cfg()
	assert_false(c.is_empty(), "the first planet pays for mastery levels")
	assert_gt(float(MasteryRewards.reward_plan(2, 0.0, 0.0, true, c)["cubes"]), 0.0, "every step pays cubes (floor)")
	var se: int = int(c["seeds_every"])
	assert_gt(int(MasteryRewards.reward_plan(se, 0.0, 0.0, true, c)["seeds"]), 0,
		"every seeds_every-th step pays seeds once the garden is open")
	assert_eq(int(MasteryRewards.reward_plan(se, 0.0, 0.0, false, c)["seeds"]), 0, "no seeds before the garden")
	assert_eq(int(MasteryRewards.reward_plan(se + 1, 0.0, 0.0, true, c)["seeds"]), 0)
	# Early income spikes are capped; lifetime earnings lift the cap late.
	assert_lt(float(MasteryRewards.reward_plan(3, 100000.0, 500.0, false, c)["cubes"]), 300.0)
	assert_almost_eq(float(MasteryRewards.reward_plan(3, 100000.0, 1.0e8, false, c)["cubes"]), 100000.0, 0.5)
	# The numbers Lumi Level paid for its levels 2 to 4 (bot run before task M3-13: 23, 42, 64).
	for pair: Array in [[2, 23.0], [3, 42.0], [4, 64.0]]:
		var plan: Dictionary = MasteryRewards.reward_plan(int(pair[0]), 1.0e6, 0.0, false, c)
		assert_almost_eq(float(plan["cubes"]), float(pair[1]), 0.5, "step %d at its cap" % pair[0])
	assert_eq(MasteryRewards.reward_plan(5, 1000.0, 0.0, true, {}), {"cubes": 0.0, "seeds": 0}, "no block, no pay")


func test_a_level_lumi_learns_pays_and_seeding_does_not() -> void:
	var m: Mastery = _make_world()
	assert_eq(MasteryRewards.step_of(m), 1)
	m.seed_legacy({"litter": 1.0e6}, [])
	assert_eq(GameState.get_currency("cubes").to_float(), 0.0, "a save's credited levels are not paid again")
	var before: int = MasteryRewards.step_of(m)
	m.add_work("wrecks", 1.0e9)
	assert_gt(MasteryRewards.step_of(m), before)
	assert_gt(GameState.get_currency("cubes").to_float(), 0.0, "Lumi's own level-ups pay cubes")
	assert_eq(float(GameState.stats.get("mastery_rewards", 0.0)), float(m.level("wrecks")), "one reward per level gained")


func test_a_planet_without_the_block_pays_nothing() -> void:
	Planets.set_current(DUMMY)
	assert_true(MasteryRewards.cfg().is_empty())
	var m: Mastery = _make_world()
	for kind: String in m.kinds():
		m.add_work(kind, 1.0e9)
	assert_eq(GameState.get_currency("cubes").to_float(), 0.0)
