extends GutTest
## [v1guide] Owner playtest 2026-11-08: the objective beam stands straight on the globe (#17), WREN
## says why Lumi picks up junk (#18), the bale how-to names the key (#21).


func test_beam_and_ring_follow_the_local_up() -> void:
	for up: Vector3 in [Vector3(0.7, 0.16, -0.68).normalized(), Vector3.UP, Vector3(0, -1, 0), Vector3.FORWARD]:
		var b: Basis = Waypoint._up_basis(up)
		assert_almost_eq(b.y.dot(up), 1.0, 0.001, "ring lies flat on the local ground")
		assert_gt(b.determinant(), 0.0, "not mirrored")


func test_beam_is_a_tall_sky_beam() -> void:
	var w := Waypoint.new()
	add_child_autofree(w)
	assert_gte(Waypoint.BEAM_H, 40.0)
	assert_almost_eq(((w._beam.mesh as QuadMesh).size.y), Waypoint.BEAM_H, 0.01)
	assert_gt(Waypoint.RING_R, 1.5, "a ring you can see around the target")


func test_brief_says_why() -> void:
	var lines: Array = Intro.brief_lines()
	var all: String = " ".join(lines).to_lower()
	assert_true((all.contains("junk") or all.contains("trash")) and all.contains("parts") and all.contains("signal tower"), "pick up junk, find parts, build the tower")
	assert_true(all.contains("[glitch]"), "WREN still breaks up")


func test_glyphs_and_bale_howto_name_the_key() -> void:
	var g: String = "[%s]" % Settings.glyph("cube")
	assert_true(Objectives.glyphs("Press {cube} now").contains(g))
	assert_eq(Objectives.glyphs("no {such_action} here"), "no {such_action} here")
	assert_true(Objectives.bale_howto().contains(g))
	var o: Array[String] = Objectives.texts({"text": "Power", "desc": "Press {cube} for a bale"})
	assert_false(o[1].contains("{cube}"))


# --- One goal timeline (owner 2026-11-08) ---------------------------------------------------------

class FakeWorld extends Node:
	var goals: Goals
	var patch: Patch
	var field: HexField
	var hud: Node
	var fleet: Node
	var depot: Node3D


func _timeline() -> Array:
	var w := FakeWorld.new()
	add_child_autofree(w)
	var g := Goals.new()
	w.add_child(g)
	w.goals = g
	var o := Objectives.new()
	o.world = w
	o.chain = [{"id": "a", "text": "A", "desc": "a", "type": "stat", "key": "v1g_a", "target": 1}]
	o.revealed = true
	return [w, g, o]


func test_one_step_at_a_time_story_then_goals() -> void:
	var saved_f: Dictionary = GameState.flags.duplicate(true)
	var saved_s: Dictionary = GameState.stats.duplicate(true)
	GameState.flags = {}
	GameState.stats = {}
	var t: Array = _timeline()
	var g: Goals = t[1]
	var o: Objectives = t[2]
	g.driven = true
	assert_eq(str(o.current().get("id", "")), "a", "the story step first")
	GameState.stats["junk_scooped"] = 99.0
	assert_eq(g.check(), 0, "a goal that holds pays at once, whatever step the card shows")
	assert_true(g.is_done(0))
	o.step = 1
	var d: Dictionary = o.current()
	assert_true(d.has("_goal"), "then the goal chain, on the same card")
	assert_eq(int(d["_goal"]), g.current()[0])
	g.card_goal = int(d["_goal"])
	GameState.stats["junk_dumps"] = 1.0
	assert_ne(g.check(), g.card_goal, "the card completes its own goal")
	o.free()
	GameState.flags = saved_f
	GameState.stats = saved_s


func test_goals_that_hold_pay_one_per_beat_not_in_a_burst() -> void:
	var saved_f: Dictionary = GameState.flags.duplicate(true)
	var saved_s: Dictionary = GameState.stats.duplicate(true)
	GameState.flags = {}
	GameState.stats = {"junk_scooped": 99.0, "junk_dumps": 1.0}
	var t: Array = _timeline()
	var g: Goals = t[1]
	var purse: Dictionary = GameState.currencies
	GameState.currencies = {}
	assert_eq(g.check(), 0)
	assert_false(g.is_done(1), "one goal per beat")
	var first: float = GameState.get_currency("cubes").to_float()
	assert_almost_eq(first, float(g.reward_of(0).get("cubes", 0.0)), 0.001, "paid as it completes")
	assert_eq(g.check(), 1)
	assert_true(g.is_done(0) and g.is_done(1), "scoop and dump goals done")
	assert_gt(GameState.get_currency("cubes").to_float(), first)
	GameState.currencies = purse
	(t[2] as Objectives).free()
	GameState.flags = saved_f
	GameState.stats = saved_s


func test_every_step_has_a_target() -> void:
	var t: Array = _timeline()
	var g: Goals = t[1]
	var o: Objectives = t[2]
	var cfg: Dictionary = Economy.planet_table("tutorial")
	for d: Dictionary in cfg["objectives"]:
		assert_ne(str(o.step_target(d).get("to", "")), "", "story step %s points somewhere" % d["id"])
	for i: int in g.chain.size():
		var d2: Dictionary = (g.chain[i] as Dictionary).duplicate()
		d2["_goal"] = i
		assert_ne(str(o.step_target(d2).get("to", "")), "", "goal %s points somewhere" % d2["id"])
	o.free()


## [M3-21] Regression: the card's "scoopie" step had no guidance case and pointed at the bench
## before the Scoopie's plans arrived. Until then it sends Lumi to the junk; after, to the bench.
func test_scoopie_step_waits_on_its_plans() -> void:
	var saved_f: Dictionary = GameState.flags.duplicate(true)
	var t: Array = _timeline()
	var o: Objectives = t[2]
	var step: Dictionary = {"id": "scoopie", "type": "stat", "key": "robots_built", "target": 2}
	GameState.flags["research"] = {"done": []}
	assert_eq(str(o.step_target(step).get("to", "")), "hex", "locked: clean meanwhile")
	GameState.flags["research"] = {"done": ["scoopie_rig"]}
	assert_eq(str(o.step_target(step).get("to", "")), "bench", "plans in: to the bench")
	GameState.flags = saved_f
	o.free()
