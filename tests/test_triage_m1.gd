extends GutTest
## M1-01 bug triage (docs/reviews/TRIAGE_M1.md). B4: the story objectives finish in order whatever
## order the player does them in. The checks that need the whole world are tools, not tests:
## tools/exit_probe.tscn (B2) and tools/hex_stick_probe.tscn (B3).

class StubFleet extends Node:
	var counts: Dictionary = {}

	func robot_total() -> int:
		var n: int = 0
		for k: String in counts:
			n += int(counts[k])
		return n

	func count(type_id: String) -> int:
		return int(counts.get(type_id, 0))


class StubWorld extends Node:
	var fleet: StubFleet
	var goals: Goals
	var hud: Node
	var patch: Patch
	var field: HexField
	var intro: Node
	var wren: Node


var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	GameState.flags["onboard_brief"] = true  # past WREN's brief: the card shows
	GameState.flags["objectives_v2"] = true


func after_each() -> void:
	GameState.from_dict(_saved)


func _chain() -> Array:
	return (JSON.parse_string(FileAccess.get_file_as_string(Objectives.PATH)) as Dictionary)["objectives"]


## The story objectives on a stub world, in the tree (complete() starts a timer), not processing.
func _objectives(w: StubWorld) -> Objectives:
	w.fleet = StubFleet.new()
	w.add_child(w.fleet)
	add_child_autofree(w)
	var o := Objectives.new()
	o.world = w
	w.add_child(o)
	o.set_process(false)
	for c: Node in o.get_children():
		c.set_process(false)
	return o


## Makes one step's condition hold, the way play would (the state its value_of reads).
func _satisfy(def: Dictionary, w: StubWorld) -> void:
	var key: String = str(def.get("key", ""))
	var target: int = int(def.get("target", 1))
	match str(def.get("type", "stat")):
		"stat":
			GameState.stats[key] = maxf(float(GameState.stats.get(key, 0.0)), float(target))
		"upgrade":
			GameState.upgrades[key] = maxi(int(GameState.upgrades.get(key, 0)), target)
		"tower":
			GameState.flags["signal_tower"] = maxi(SignalTower.tier(), target)
		"flag":
			GameState.flags[key] = true
		"bench":
			GameState.flags["bench_tier"] = maxi(BenchTiers.tier(), target)
		"robot":
			var type_id: String = "scoopie" if key == "any" else key
			w.fleet.counts[type_id] = maxi(int(w.fleet.counts.get(type_id, 0)), target)
		"zone":
			GameState.world["orders"] = {"groups": {"scoopie": {"zone": range(target)}}}
		"hub_level":
			GameState.world["hub_level"] = maxi(int(GameState.world.get("hub_level", 1)), target)
		_:
			fail_test("no way to satisfy objective type %s" % def.get("type"))


## What Objectives._process does on its refresh tick for the step on the card.
func _tick(o: Objectives) -> void:
	var def: Dictionary = o.current()
	if not def.is_empty() and o.value_of(def) >= o.target_of(def):
		o.complete()


func test_b4_chain_has_the_21_steps_this_triage_checked() -> void:
	assert_eq(_chain().size(), 21, "a changed chain needs the out-of-order check read again")


func test_b4_objectives_play_through_in_order() -> void:
	var w := StubWorld.new()
	var o := _objectives(w)
	for k: int in o.chain.size():
		assert_eq(o.step, k, "waits on step %s until it is done" % o.chain[k]["id"])
		_satisfy(o.chain[k], w)
		_tick(o)
	assert_eq(o.step, o.chain.size(), "every step finishes")


## B4: each step in turn is done first, before anything else; the chain must still pass it when
## its turn comes, with no second action from the player.
func test_b4_a_step_done_before_its_turn_completes_when_it_comes_up() -> void:
	var n: int = _chain().size()
	for early: int in n:
		GameState.new_game()
		GameState.flags["onboard_brief"] = true
		GameState.flags["objectives_v2"] = true
		var w := StubWorld.new()
		var o := _objectives(w)
		_satisfy(o.chain[early], w)
		var stalled: String = ""
		for k: int in n:
			if k != early:
				_satisfy(o.chain[k], w)
			_tick(o)
			if o.step != k + 1 and stalled == "":
				stalled = str(o.chain[k]["id"])
		assert_eq(stalled, "", "step %s done early: the chain stalls at %s" % [o.chain[early]["id"], stalled])
		w.queue_free()


## B4: everything done before the first step is even on the card (a player who ignores the card).
func test_b4_all_steps_done_up_front_drain_one_per_tick() -> void:
	var w := StubWorld.new()
	var o := _objectives(w)
	for def: Dictionary in o.chain:
		_satisfy(def, w)
	for k: int in o.chain.size():
		_tick(o)
	assert_eq(o.step, o.chain.size(), "one step per tick, none left behind")


## B4: a save made out of order catches up silently on load (Objectives._catch_up).
func test_b4_load_catches_up_past_steps_done_out_of_order() -> void:
	var chain: Array = _chain()
	var holder := StubWorld.new()
	holder.fleet = StubFleet.new()
	holder.add_child(holder.fleet)
	add_child_autofree(holder)
	for def: Dictionary in chain:
		if str(def.get("type", "")) != "robot":  # no robots in the loading stub
			_satisfy(def, holder)
	var o := Objectives.new()
	o.world = holder
	holder.add_child(o)
	o.set_process(false)
	var robot_step: int = chain.map(func(d: Dictionary) -> String: return str(d["type"])).find("robot")
	assert_eq(o.step, robot_step, "the load stops at the first step that does not hold (%s)" % chain[robot_step]["id"])


## B4: the values the chain reads only ever grow in play, except the zone, which the player can
## erase. An erased zone must put the step back to "not done", not strand it.
func test_b4_zone_step_reads_the_current_zone() -> void:
	var w := StubWorld.new()
	var o := _objectives(w)
	var zone_def: Dictionary = o.chain.filter(func(d: Dictionary) -> bool: return str(d["type"]) == "zone")[0]
	_satisfy(zone_def, w)
	assert_eq(o.value_of(zone_def), 1.0)
	GameState.world["orders"] = {}
	assert_eq(o.value_of(zone_def), 0.0, "erased before its turn: the step asks again, and painting one hex finishes it")
	_satisfy(zone_def, w)
	assert_gte(o.value_of(zone_def), o.target_of(zone_def))


## B4 (prerequisites): nothing a step needs is locked behind a later step. Bench tiers and story
## unlocks name their conditions in data; each must be something an earlier step already asks for
## or something outside the chain.
func test_b4_bench_tiers_wait_only_on_earlier_steps() -> void:
	var chain: Array = _chain()
	var ids: Array = chain.map(func(d: Dictionary) -> String: return str(d["id"]))
	var bench2: int = ids.find("bench2")
	for c: Variant in BenchTiers.def(2).get("requires", []):
		match str(c[0]):
			"tower":
				assert_lt(ids.find("tower"), bench2, "the Bot Bay waits for the tower, an earlier step")
			"stat":
				assert_eq(str(c[1]), "hexes_cleaned")
				assert_lte(int(c[2]), 3, "the Bot Bay waits for 3 clean hexes, the step before it")
				assert_lt(ids.find("hex3"), bench2)
			_:
				fail_test("unchecked Bot Bay condition %s" % str(c))
	assert_lt(bench2, ids.find("robot"), "the Bots tab opens before the first robot is asked for")
	assert_true("salvage_logic" in BenchTiers.def(2).get("grants_research", []), "the Bot Bay brings the Scoopie's research")
	for c: Variant in BenchTiers.def(3).get("requires", []):
		assert_eq(str(c[0]), "hub_level", "the Research Desk waits on the base level only")
		assert_lte(int(c[1]), 2)
	assert_lt(ids.find("base2"), ids.find("research1"), "base level 2 (the Research Desk's gate) is asked before research")
