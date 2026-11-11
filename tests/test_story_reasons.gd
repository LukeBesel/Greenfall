extends GutTest
## [v6story] Owner item 60: "real reasons we are doing things". Every step the player is given on
## Verdance says why: story objectives carry a reason line (desc; hint while waiting), every goal
## in the chain resolves to a reason (data/story_reasons.json), and the exit beat has its lines.

const HOW_ONLY: Array[String] = ["Workbench, Build tab.", "Workbench, Upgrades tab.", "Workbench.", "Workbench, Bots tab."]


func test_every_story_objective_has_a_reason_line() -> void:
	var cfg: Dictionary = Economy.read_json("res://data/objectives.json")
	var chain: Array = cfg.get("objectives", [])
	assert_gt(chain.size(), 10)
	for def: Dictionary in chain:
		var id: String = str(def.get("id", "?"))
		var why: String = str(def.get("desc", "")).strip_edges()
		assert_gt(why.length(), 12, "objective %s has a reason line" % id)
		assert_false(why in HOW_ONLY, "objective %s: the line says more than where to click: %s" % [id, why])
		assert_true(why.length() <= 96, "objective %s: reason fits the card (%d)" % [id, why.length()])
		if def.has("wait_flag"):
			assert_gt(str(def.get("hint", "")).length(), 12, "objective %s has a line while it waits" % id)
		var lines: Array = def.get("lines", [])
		assert_false(lines.is_empty(), "objective %s has WREN's line" % id)


func test_every_goal_has_a_reason() -> void:
	var goals: Array = (Economy.read_json("res://data/goals.json") as Dictionary).get("goals", [])
	var generic: String = str(((Economy.read_json("res://data/story_reasons.json") as Dictionary)["goal_reasons"] as Dictionary)["default"])
	var n_generic: int = 0
	for g: Dictionary in goals:
		var why: String = Objectives.goal_reason(g)
		assert_gt(why.length(), 12, "goal %s has a reason" % str(g.get("id", "?")))
		assert_true(why.length() <= 80, "goal %s: reason fits the card: %s" % [str(g.get("id", "?")), why])
		if why == generic:
			n_generic += 1
	# The catch-all line is for late-game odds and ends, not for the Verdance chain.
	assert_lt(n_generic, goals.size() / 3, "%d of %d goals fall back to the generic reason" % [n_generic, goals.size()])
	for g2: Dictionary in goals:
		if str(g2.get("id", "")) == "home_land_1":  # flying to the next planet: Verdance ends here
			break
		assert_ne(Objectives.goal_reason(g2), generic, "Verdance goal %s has its own reason" % str(g2.get("id", "?")))


func test_goal_reason_lookup_order() -> void:
	var why: String = Objectives.goal_reason({"id": "hex_5", "type": "stat", "key": "hexes_cleaned"})
	assert_eq(why, "Plants only grow on clean ground.")
	assert_eq(Objectives.goal_reason({"id": "x", "type": "research", "key": "nope"}), "The bench learns to build something new.")
	assert_eq(Objectives.goal_reason({"id": "rocket", "type": "districts"}), "Other old stations are waiting to be woken up.")


func test_exit_beat_lines_exist_and_say_why() -> void:
	var ex: Dictionary = (Economy.read_json("res://data/story_reasons.json") as Dictionary).get("exit", {})
	for key: String in ["system_open", "drive_built"]:
		var ls: Array = ex.get(key, [])
		assert_between(ls.size(), 1, 3, "%s: one to three lines" % key)
		for l: Variant in ls:
			assert_true(str(l).length() <= 110, "short line: %s" % str(l))
	var all: String = " ".join(ex["system_open"]) + " " + " ".join(ex["drive_built"])
	assert_true(all.contains("robots"), "says who looks after Verdance")
	assert_true(all.contains("Five worlds") or all.contains("five worlds"), "says why fly on")
	# WREN speaks them through a real Wren node, in order.
	var holder := Node.new()
	add_child_autofree(holder)
	var wr := Wren.new()
	holder.add_child(wr)
	var bag := StoryBag.new()
	bag.wren = wr
	add_child_autofree(bag)
	assert_eq(HomewardDirector.say_exit(bag, "system_open"), (ex["system_open"] as Array).size())
	assert_eq(wr._queue.size(), (ex["system_open"] as Array).size())
	assert_eq(str(wr._queue[0]["text"]), tr(str(ex["system_open"][0])))


class StoryBag extends Node:
	var wren: Wren
