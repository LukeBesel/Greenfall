extends GutTest
## [v7arc] The whole-game story spine (data/story_arc.json, systems/story_arc.gd,
## docs/STORY_ARC.md): every planet has a complete story block, the fuel and power the planets
## give add up to exactly what home needs, and Verdance's exit beat reports the right numbers and
## says the reason to fly on once. The profile is kept in memory (not written).

var _keep: Array
var _profile: Dictionary


func before_each() -> void:
	_keep = [GameState.flags.duplicate(true), GameState.stats.duplicate(true), GameState.world, GameState.districts, GameState.current_hub]
	_profile = CradleMode.profile.duplicate(true)
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()
	GameState.flags = {}
	GameState.stats = {}
	GameState.world = {}
	GameState.districts = {0: GameState.world}
	GameState.current_hub = 0


func after_each() -> void:
	CradleMode.profile = _profile
	GameState.flags = _keep[0]
	GameState.stats = _keep[1]
	GameState.world = _keep[2]
	GameState.districts = _keep[3]
	GameState.current_hub = _keep[4]


func test_every_planet_has_a_complete_story_block() -> void:
	assert_eq(Homeward.planets().size(), 5)
	for k: int in Homeward.planets().size():
		var id: String = str(Homeward.planet_def(k)["id"])
		var b: Dictionary = StoryArc.block(k)
		assert_false(b.is_empty(), "%s has a story block" % id)
		var g: Vector2i = StoryArc.gives(k)
		assert_true(g.x > 0 or g.y > 0, "%s gives fuel or power" % id)
		for key: String in ["reason", "question", "from", "answers", "ledger"]:
			assert_gt(str(b.get(key, "")).length(), 12, "%s has its %s" % [id, key])
		assert_true(str(b.get("reason", "")).length() <= 80, "%s: the reason is one short line" % id)
		assert_true(str(b.get("question", "")).ends_with("?"), "%s: the question is a question" % id)
		for key2: String in ["arrive", "leave"]:
			var ls: Array = b.get(key2, [])
			assert_between(ls.size(), 1, 2, "%s: one or two %s lines" % [id, key2])
			for l: Variant in ls:
				assert_true(str(l).length() > 12 and str(l).length() <= 100, "%s %s: short line: %s" % [id, key2, str(l)])
	var c: Dictionary = StoryArc.cfg().get("cradle", {})
	assert_gt(str(c.get("reason", "")).length(), 12, "the Cradle, the last stop, has its line")
	# No story block for a planet that is not in the game's order.
	for id2: Variant in (StoryArc.cfg()["planets"] as Dictionary):
		assert_gt(Homeward.planet_index(str(id2)), -1, "%s is a planet in data/homeward.json" % str(id2))


func test_the_meters_add_up_to_exactly_home() -> void:
	var n: Vector2i = StoryArc.need()
	assert_gt(n.x, 0)
	assert_gt(n.y, 0)
	var sum := Vector2i.ZERO
	var ids: Array = []
	for k: int in Homeward.planets().size():
		sum += StoryArc.gives(k)
		ids.append(str(Homeward.planet_def(k)["id"]))
	assert_eq(sum, n, "all planets together give exactly what home needs")
	assert_eq(StoryArc.meter_of(ids), n)
	# One planet short is never enough.
	for k2: int in ids.size():
		var rest: Array = ids.duplicate()
		rest.remove_at(k2)
		var m: Vector2i = StoryArc.meter_of(rest)
		assert_true(m.x < n.x or m.y < n.y, "without %s home is not reached" % ids[k2])
	assert_eq(StoryArc.meter_of([]), Vector2i.ZERO)


func test_meter_follows_the_exit_beats() -> void:
	assert_eq(StoryArc.meter(), Vector2i.ZERO)
	assert_false(StoryArc.given(0))
	Homeward.mark_beat("verdance_exit")  # the beat older saves already have
	assert_true(StoryArc.given(0))
	assert_eq(StoryArc.meter(), StoryArc.gives(0))
	for k: int in Homeward.planets().size():
		Homeward.mark_beat(StoryArc.exit_beat(k))
	assert_true(StoryArc.full())
	assert_eq(StoryArc.home_line(StoryArc.meter()), tr(str(StoryArc.home()["full"])))


func test_leave_open_is_generic() -> void:
	assert_false(StoryArc.leave_open(1), "Ochre at 0% is not done")
	(Homeward.state()["pct"] as Dictionary)["ochre"] = float(Homeward.cfg().get("chart_at", 0.5))
	assert_true(StoryArc.leave_open(1), "a planet without a leave gate opens at chart_at")
	assert_false(StoryArc.leave_open(-1))


func test_verdance_exit_shows_the_right_numbers() -> void:
	var holder := Node.new()
	add_child_autofree(holder)
	var wr := Wren.new()
	holder.add_child(wr)
	var bag := StoryBag.new()
	bag.wren = wr
	add_child_autofree(bag)
	var d := HomewardDirector.new()
	d.world = bag
	add_child_autofree(d)
	d.set_process(false)
	var toasts: Array = []
	var cb := func(t: String, _kind: String) -> void: toasts.append(t)
	EventBus.toast.connect(cb)
	d._exit_beat(0)
	EventBus.toast.disconnect(cb)
	var g: Vector2i = StoryArc.gives(0)
	var n: Vector2i = StoryArc.need()
	assert_true(StoryArc.given(0), "Verdance's gift is in")
	assert_eq(StoryArc.meter(), g)
	var meter: String = "Home: fuel %d/%d, power %d/%d" % [g.x, n.x, g.y, n.y]
	assert_eq(StoryArc.meter_text(), meter)
	assert_true(meter in toasts, "the exit beat shows the meters: %s" % str(toasts))
	var said: Array = []
	for l: Dictionary in wr._queue:
		said.append(str(l["text"]))
	var all: String = " | ".join(said)
	assert_true(all.contains("We have %d fuel and %d power" % [g.x, g.y]), "WREN says how far home is: %s" % all)
	assert_true(all.contains("we need %d fuel and %d power" % [n.x, n.y]), all)
	var nxt: String = StoryArc.next_line(0)
	assert_true(nxt.begins_with("Ochre is next."), nxt)
	assert_eq(said.count(nxt), 1, "the reason to fly on is said once")
	assert_lt(said.size(), 6, "the exit beat stays short")
	assert_eq(StoryArc.gives_text(0), "Gave fuel %d and power %d" % [g.x, g.y])
	assert_eq(StoryArc.gives_text(1), "Gives fuel %d and power %d" % [StoryArc.gives(1).x, StoryArc.gives(1).y])


func test_last_planet_points_home() -> void:
	var last: int = Homeward.planets().size() - 1
	assert_eq(StoryArc.next_line(last), tr(str(StoryArc.cfg()["cradle"]["reason"])))


class StoryBag extends Node:
	var wren: Wren
