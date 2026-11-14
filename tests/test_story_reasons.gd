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
		var why: String = Objectives.step_why(def).strip_edges()  # [v6pace] hub steps: their story reason
		assert_gt(why.length(), 12, "objective %s has a reason line" % id)
		assert_false(why in HOW_ONLY, "objective %s: the line says more than where to click: %s" % [id, why])
		assert_lt(why.length(), 60 if def.has("desc") else 81, "objective %s: the reason is one short line (%d)" % [id, why.length()])  # [v6pace] a story reason fits the goal card (80)
		if def.has("wait_flag"):
			assert_gt(str(def.get("hint", "")).length(), 12, "objective %s has a line while it waits" % id)
		var lines: Array = Objectives.step_lines(def)  # [v6pace] hub steps: WREN speaks their story reason
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
		# Verdance's first visit ends where the old frontier districts (retired on the globe) or the next planet begin.
		if str(g2.get("id", "")) in ["research_dunes", "home_land_1"] or str(g2.get("type", "")).begins_with("frontier"):
			break
		assert_ne(Objectives.goal_reason(g2), generic, "Verdance goal %s has its own reason" % str(g2.get("id", "?")))


func test_goal_reason_lookup_order() -> void:
	var why: String = Objectives.goal_reason({"id": "hex_5", "type": "stat", "key": "hexes_cleaned"})
	assert_eq(why, "Plants only grow on clean ground.")
	assert_eq(Objectives.goal_reason({"id": "x", "type": "research", "key": "nope"}), "The bench learns to build something new.")
	assert_eq(Objectives.goal_reason({"id": "rocket", "type": "districts"}), "Other old stations are waiting to be woken up.")
	assert_true(Objectives.goal_reason({"id": "hub_fly_4", "type": "flag"}).contains("star chart"))
	assert_true(Objectives.goal_reason({"id": "hub_wake_2", "type": "flag"}).contains("rocket piece"))  # [v7play] the prefix line; 3-6 have their own
	assert_true(Objectives.goal_reason({"id": "hub_wake_3", "type": "flag"}).contains("hull plates"))
	assert_true(Objectives.goal_reason({"id": "rocket_tier_2", "type": "stat"}).contains("supplies"))
	assert_true(Objectives.goal_reason({"id": "hub_fly_9", "type": "flag"}).contains("stations"))


func test_exit_beat_lines_exist_and_say_why() -> void:
	# [v7arc] The way-onward lines are the planet's story block (data/story_arc.json,
	# tests/test_story_arc.gd); here: the drive-built lines and that the whole beat says why.
	var ex: Dictionary = (Economy.read_json("res://data/story_reasons.json") as Dictionary).get("exit", {})
	assert_false(ex.has("system_open"), "the old star-map lines are the story arc's now")
	var ls: Array = ex.get("drive_built", [])
	assert_between(ls.size(), 1, 3, "drive_built: one to three lines")
	for l: Variant in ls:
		assert_true(str(l).length() <= 110, "short line: %s" % str(l))
	var leave: String = str(((Homeward.planet_def(0).get("leave", {}) as Dictionary)).get("toast", ""))  # said first (v6pace)
	var arc: Array[String] = StoryArc.exit_lines(0, StoryArc.gives(0))
	var all: String = leave + " " + " ".join(arc) + " " + " ".join(ls)
	assert_lt(arc.size() + (1 if leave != "" else 0), 5, "the exit beat is four lines at most")
	assert_true(all.contains("robots"), "says who looks after Verdance")
	assert_true(all.contains("four more worlds"), "says why fly on")
	# WREN speaks them through a real Wren node, in order.
	var holder := Node.new()
	add_child_autofree(holder)
	var wr := Wren.new()
	holder.add_child(wr)
	var bag := StoryBag.new()
	bag.wren = wr
	add_child_autofree(bag)
	assert_eq(HomewardDirector.say_exit(bag, "drive_built"), ls.size())
	assert_eq(wr._queue.size(), ls.size())
	assert_eq(str(wr._queue[0]["text"]), tr(str(ls[0])))


class StoryBag extends Node:
	var wren: Wren


func test_wren_drops_a_step_line_that_comes_too_late() -> void:
	var wr := Wren.new()
	add_child_autofree(wr)
	wr.set_process(false)
	var live: Array = [true]
	wr.speak("first", 1, true)
	wr.speak("late step line", 1, true, func() -> bool: return live[0])
	wr.speak("after", 1, true)
	var heard: Array = []
	wr.line_started.connect(func(t: String, _s: int) -> void: heard.append(t))
	wr._process(0.1)
	live[0] = false  # the step finished while she read the first line
	wr._cooldown = 0.0
	wr._process(0.1)
	assert_eq(heard, ["first", "after"])
