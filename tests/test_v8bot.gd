extends GutTest
## [v8bot] Owner: "paint the hex to control bot? doesnt make any sense. Dont say anything about
## telling it where to go it just goes on its own for the scoopies". No zone step, no zone goal, and
## old saves on or past the zone step move on cleanly.

var _flags: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags


func _chain() -> Array:
	return Economy.read_json("res://data/objectives.json").get("objectives", [])


func _index(id: String) -> int:
	var ch: Array = _chain()
	for i: int in ch.size():
		if str((ch[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func test_no_step_or_goal_asks_for_a_zone() -> void:
	for d: Dictionary in _chain():
		assert_ne(str(d.get("type", "")), "zone", "%s asks for a zone" % d.get("id", ""))
	for g: Dictionary in Economy.read_json("res://data/goals.json").get("goals", []):
		assert_ne(str(g.get("type", "")), "zone", "%s asks for a zone" % g.get("id", ""))


func test_no_early_text_tells_the_player_to_direct_the_robot() -> void:
	var stop: int = _index("seed")
	assert_gt(stop, 0)
	var ch: Array = _chain()
	for i: int in stop + 1:
		var d: Dictionary = ch[i]
		var all: String = " ".join([str(d.get("text", "")), str(d.get("desc", "")), str(d.get("hint", "")), " ".join(d.get("lines", []))]).to_lower()
		for bad: String in ["paint", "zone", "open_command", "show your robot", "show it where", "where to clean"]:
			assert_false(all.contains(bad), "%s says '%s'" % [d.get("id", ""), bad])
	var after: Dictionary = ch[_index("robot") + 1]
	assert_eq(str(after["id"]), "hex2", "the story goes straight on after the first robot")
	assert_string_contains(str(after.get("desc", "")), "on its own")
	# hex2 is often done before the robot (the card skips it silently): WREN says it at hex3.
	assert_string_contains(" ".join((ch[_index("hex3")] as Dictionary).get("lines", [])), "on its own")


func _migrate(step: int, has_step: bool = true) -> int:
	GameState.flags.erase("objectives_v3")
	if has_step:
		GameState.flags["objective_step"] = step
	else:
		GameState.flags.erase("objective_step")
	var o := Objectives.new()
	o.chain = _chain()
	o.step = step
	o._drop_zone_step()
	var out: int = o.step
	o.free()
	return out


func test_old_save_on_the_zone_step_moves_on() -> void:
	var hex2: int = _index("hex2")
	# The old chain had "zone" at hex2's index now: a save sitting on it lands on hex2.
	assert_eq(_migrate(hex2), hex2)
	assert_eq(int(GameState.flags["objective_step"]), hex2)
	# Past it: one step fewer in front.
	assert_eq(_migrate(hex2 + 3), hex2 + 2)
	assert_eq(int(GameState.flags["objective_step"]), hex2 + 2)
	# Before it: unchanged.
	assert_eq(_migrate(hex2 - 1), hex2 - 1)
	assert_true(GameState.flags.get("objectives_v3", false))


func test_migration_runs_once_and_not_for_new_games() -> void:
	var hex2: int = _index("hex2")
	assert_eq(_migrate(0, false), 0)
	assert_false(GameState.flags.has("objective_step"))
	GameState.flags["objective_step"] = hex2 + 4
	var o := Objectives.new()
	o.chain = _chain()
	o.step = hex2 + 4
	o._drop_zone_step()  # the flag is set: a save made by this build keeps its step
	assert_eq(o.step, hex2 + 4)
	o.free()


func test_painted_zones_still_count_and_load() -> void:
	var crew := SphereCrew.new()
	var d: Dictionary = {"v": 1, "robots": [], "bales": [], "cashed": 0.0, "zones": {"clean": [5, 6]}, "hub_log": {}}
	crew.from_dict(d)
	assert_eq(crew.zone_cells().size(), 2, "a save's painted zones load")
	assert_eq(crew.to_dict()["zones"]["clean"].size(), 2, "and save again")
	crew.free()


# --- [v8bot] Owner: "painter is fine but it doesnt work to call robots there and you should be
# able to select how many robots come and it should choose the closest ones."

var _g: SphereGrid
var _t: SphereTerrain


func before_all() -> void:
	_g = SphereGrid.new()
	_g.generate(5)
	_g.radius_m = SphereGrid.radius_for(5, 10.0)
	_t = SphereTerrain.new(_g, 7)


func _crew() -> SphereCrew:
	var cells := SphereCells.new(_g.cell_count())
	var surface := SphereSurface.new(_g.radius_m)
	surface.height_fn = _t.height
	surface.cell_fn = func(p: Vector3, _h: int) -> int: return _g.cell_at(p)
	surface.center_fn = func(c: int) -> Vector3: return _g.centers[c]
	var crew := SphereCrew.new()
	crew.visuals = false
	add_child_autofree(crew)
	crew.setup(_g, cells, null, surface, SphereSwarm.new(surface))
	crew.hub_cell = 100
	crew.depot_cell = 100
	crew.hubs = PackedInt32Array([100])
	var lumi := Node3D.new()
	add_child_autofree(lumi)
	lumi.global_position = surface.ground(_g.centers[100])
	crew.focus = lumi
	return crew


func _run(crew: SphereCrew, seconds: float, dt: float = 0.1) -> void:
	for i: int in int(seconds / dt):
		for u: Dictionary in crew.robots():
			if u["bot"] != null:
				(u["bot"] as SphereBot).step(dt)
		crew.tick(dt)


func test_scoopies_keep_working_with_bales_piled_and_no_haul_bug() -> void:
	GameState.flags["research"] = {"done": []}  # no Haul Bug plans yet
	var crew: SphereCrew = _crew()
	var a: Dictionary = crew.spawn("scoopie", 0, 100)
	var b: Dictionary = crew.spawn("scoopie", 0, 100)
	for i: int in 40:
		crew.bales.append({"id": 900 + i, "cell": 100, "dir": _g.centers[100], "value": 5.0, "units": 10.0, "claimed": ""})
	_run(crew, 30.0)
	var junk0: float = float(a["log"]["junk"]) + float(b["log"]["junk"])
	_run(crew, 30.0)
	assert_gt(float(a["log"]["junk"]) + float(b["log"]["junk"]), junk0, "they keep cleaning with 40 bales lying about")
	assert_false(CrewTalk.needs_hauler(crew, 100), "and nobody asks for a Haul Bug that can't be built yet")
	for u: Dictionary in [a, b]:
		assert_ne(CrewTalk.state(crew, u), CrewTalk.HELP, "no '!' on a working Scoopie")
		assert_true(CrewTalk.busy(u))
	assert_eq(int(CrewTalk.hub_summary(crew, 100)["working"]), 2, "the card counts them as working, not waiting")


## Three Scoopies at increasing distances from a painted hex; returns [crew, units nearest first, zone cell].
func _three_and_a_zone() -> Array:
	var crew: SphereCrew = _crew()
	var ring: PackedInt32Array = _g.cells_around(100, 3)
	var zc: int = ring[ring.size() - 1]
	var by_d: Array = []
	for c: int in ring:
		if c != zc and c != 100:
			by_d.append([_g.distance_m(c, zc), c])
	by_d.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var us: Array = []
	for k: int in [0, by_d.size() / 2, by_d.size() - 1]:  # near, middling, far
		us.append(crew.spawn("scoopie", 0, int(by_d[k][1])))
	_run(crew, 5.0)  # past the hello
	return [crew, us, zc]


func test_painting_with_one_robot_sends_exactly_the_closest() -> void:
	var r: Array = _three_and_a_zone()
	var crew: SphereCrew = r[0]
	var us: Array = r[1]
	var zc: int = r[2]
	crew.set_zone_count("clean", 1)
	crew.set_zone_cell("clean", zc, true)
	_run(crew, 1.0)
	var called: Array = us.filter(func(u: Dictionary) -> bool: return crew.is_called(u))
	assert_eq(called.size(), 1, "exactly one robot is called")
	assert_eq(called[0]["name"], us[0]["name"], "and it is the closest one")
	assert_eq(int(us[0]["job"]), zc, "it heads for the painted hex at once")
	assert_ne(int(us[1]["job"]), zc, "the others keep working on their own")
	assert_ne(int(us[2]["job"]), zc)
	var zcrew: Dictionary = crew.zone_crew("clean", 100)
	assert_eq(int(zcrew["called"]), 1)
	assert_eq(int(zcrew["coming"]) + int(zcrew["working"]), 1, "the card shows it on the way or working there")
	# Saved and loaded with the zone.
	var d: Dictionary = crew.to_dict()
	assert_eq(int(d["zone_n"]["clean"]), 1)
	# Erasing the paint releases it.
	crew.set_zone_cell("clean", zc, false)
	_run(crew, 1.0)
	assert_false(crew.is_called(us[0]), "erasing the paint releases the robot")
	# Back to "all": every robot is called.
	crew.set_zone_cell("clean", zc, true)
	crew.set_zone_count("clean", 0)
	_run(crew, 1.0)
	for u: Dictionary in us:
		assert_true(crew.is_called(u), "all robots come by default")


func test_zone_count_survives_a_reload() -> void:
	var crew: SphereCrew = _crew()
	crew.set_zone_cell("clean", 120, true)
	crew.set_zone_count("clean", 2)
	var d: Dictionary = JSON.parse_string(JSON.stringify(crew.to_dict()))
	var crew2: SphereCrew = _crew()
	crew2.from_dict(d)
	assert_eq(crew2.zone_count("clean"), 2)
	assert_true(crew2.zone_cells().has(120))
