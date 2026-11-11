extends GutTest
## B33: nothing asked the player to buy the Research Desk, so "Finish a research project" could sit
## open with its tab shut. While the Research tab is shut the step asks for the workbench tier that
## opens it, and a tier that waits for a flag says what it waits for.

const GENERAL_LINE: String = "Not yet. Keep playing."


class StubWorld extends Node:
	func bench_pos() -> Vector3:
		return Vector3(1.0, 2.0, 3.0)


var _flags: Dictionary
var _stats: Dictionary
var _cur: Dictionary
var _world_state: Dictionary
var _o: Objectives
var _w: StubWorld


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	_cur = GameState.currencies.duplicate(true)
	_world_state = GameState.world.duplicate(true)
	GameState.flags = {}
	GameState.stats = {}
	GameState.currencies["cubes"] = BigNum.from_float(0.0)
	_w = StubWorld.new()
	_o = Objectives.new()
	_o.world = _w


func after_each() -> void:
	_o.free()
	_w.free()
	GameState.flags = _flags
	GameState.stats = _stats
	GameState.currencies = _cur
	GameState.world = _world_state


func _research_step() -> Dictionary:
	for d: Dictionary in Economy.planet_table("tutorial")["objectives"]:
		if str(d.get("key", "")) == "research_done":
			return d
	return {}


## The Bot Bay is fitted and the Research Desk is the next tier; `ready` meets what the Desk waits for.
func _at_bot_bay(ready: bool) -> void:
	GameState.flags["bench_tier"] = 2
	if ready:
		for c: Array in BenchTiers.next_def().get("requires", []):
			match str(c[0]):
				"hub_level":
					GameState.world["hub_level"] = int(c[1])
				"flag":
					GameState.flags[str(c[1])] = true


func test_every_tier_requirement_says_what_it_waits_for() -> void:
	for i: int in range(2, BenchTiers.max_tier() + 1):
		for c: Array in BenchTiers.def(i).get("requires", []):
			var text: String = BenchTiers.requirement_text(c)
			assert_ne(text, GENERAL_LINE, "%s names what it waits for: %s" % [BenchTiers.def(i)["name"], str(c)])
			assert_ne(text, "")
	assert_eq(BenchTiers.requirement_text(["flag", "seeds_unlocked"]), "Find the seed tin first.")
	assert_eq(BenchTiers.requirement_text(["flag", "no_such_flag"]), GENERAL_LINE, "an unknown flag keeps the general line")


func test_research_step_asks_for_the_desk_while_the_tab_is_shut() -> void:
	var d: Dictionary = _research_step()
	assert_false(d.is_empty(), "the chain has a research step")
	assert_eq(Objectives.step_tab(d), "research", "the research step names its workbench tab")
	_at_bot_bay(true)
	assert_eq(BenchTiers.block_reason(_w), "", "the Desk waits only for its price")
	assert_true(Objectives.waits_for_tab(d))
	assert_eq(Objectives.texts(d)[1], str(d["hint"]), "the card says to add the Research Desk")
	assert_string_contains(str(d["hint"]), "Research Desk")
	var t: Dictionary = _o.step_target(d)
	assert_eq(t["row"], ["patch", "bench_tier"], "the bench opens on the Research Desk's row")
	assert_eq(str(t["to"]), "bench")


func test_research_step_shows_cubes_saved_toward_the_desk() -> void:
	var d: Dictionary = _research_step()
	_at_bot_bay(true)
	var need: float = float(BenchTiers.next_cost().get("cubes", 0.0))
	assert_gt(need, 0.0)
	GameState.currencies["cubes"] = BigNum.from_float(need * 0.5)
	_o.chain = [d]
	_o.step = 0
	_o.revealed = true
	assert_almost_eq(float(_o.progress()[0]), 0.5, 0.001, "half the Desk's price saved reads as half")
	assert_eq(_o._step_price(), BenchTiers.next_cost(), "the price the step saves for is the Desk's")


func test_research_step_says_what_the_desk_waits_for() -> void:
	var d: Dictionary = _research_step()
	_at_bot_bay(false)
	var why: String = BenchTiers.block_reason(_w)
	assert_ne(why, "", "the Desk is not on offer yet")
	assert_ne(why, GENERAL_LINE)
	assert_eq(Objectives.texts(d)[1], why, "the card gives the reason, not a dead end")
	assert_eq(str(_o.step_target(d)["to"]), "hex", "nothing to buy at the bench yet: keep cleaning")


func test_research_step_points_at_research_once_the_desk_is_in() -> void:
	var d: Dictionary = _research_step()
	GameState.flags["bench_tier"] = 3
	assert_false(Objectives.waits_for_tab(d))
	assert_eq(Objectives.texts(d)[1], str(d["desc"]))
	assert_eq(_o.step_target(d)["row"], ["research", ""])


func test_research_goals_ask_for_the_desk_too() -> void:
	_at_bot_bay(true)
	for g: Dictionary in [{"_goal": 0, "type": "stat", "key": "research_done", "target": 1},
			{"_goal": 0, "type": "research", "key": "pollinator_survey", "target": 1}]:
		assert_eq(_o.step_target(g)["row"], ["patch", "bench_tier"], "%s waits for the Desk" % g["type"])
	GameState.flags["bench_tier"] = 3
	assert_eq(_o.step_target({"_goal": 0, "type": "research", "key": "pollinator_survey", "target": 1})["row"],
		["research", "pollinator_survey"])
