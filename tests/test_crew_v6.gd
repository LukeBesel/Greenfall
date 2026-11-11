extends GutTest
## [v6crew] Robots as the heart of the mid-game: the hello, sensible defaults without the Command
## view, one robot one hub, readable states and reasons, hub readouts and the away note.

var _g: SphereGrid
var _t: SphereTerrain


func before_all() -> void:
	_g = SphereGrid.new()
	_g.generate(5)
	_g.radius_m = SphereGrid.radius_for(5, 10.0)
	_t = SphereTerrain.new(_g, 7)


func _world(junk: bool = true) -> Dictionary:
	var cells := SphereCells.new(_g.cell_count())
	if not junk:
		cells.junk.fill(0.0)
		cells.state.fill(1)
		cells.refresh_all()
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
	var lumi := Node3D.new()
	add_child_autofree(lumi)
	lumi.global_position = surface.ground(_g.centers[100])
	crew.focus = lumi
	return {"cells": cells, "surface": surface, "crew": crew, "lumi": lumi}


func _run(crew: SphereCrew, seconds: float, dt: float = 0.1) -> void:
	for i: int in int(seconds / dt):
		for u: Dictionary in crew.robots():
			if u["bot"] != null:
				(u["bot"] as SphereBot).step(dt)
		crew.tick(dt)


## A hub far from hub 100 on the level-5 grid (regions do not overlap).
func _far_hub() -> int:
	var best: int = 0
	var bd: float = 0.0
	for c: int in range(0, _g.cell_count(), 37):
		var d: float = _g.distance_m(100, c)
		if d > bd:
			bd = d
			best = c
	return best


func test_a_new_robot_says_hello_then_starts_on_the_nearest_dirty_hex_by_itself() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var u: Dictionary = crew.spawn("scoopie", 0, 100)
	crew.greet(u)
	assert_eq(str(u["mode"]), "hello")
	assert_eq(CrewTalk.state(crew, u), CrewTalk.HELLO)
	var from: Vector3 = crew.unit_dir(u)
	_run(crew, 1.5)
	assert_eq(str(u["mode"]), "hello", "still looking around after 1.5 s")
	assert_gt(from.angle_to(crew.unit_dir(u)) * crew.surface.radius, 1.0, "it rolled out of the bay")
	var h0: Vector3 = (u["bot"] as SphereBot).heading
	_run(crew, 0.8)
	assert_gt(h0.angle_to((u["bot"] as SphereBot).heading), 0.2, "it looks around")
	_run(crew, SphereCrew.HELLO_S)
	assert_true(str(u["mode"]) in ["go", "work"], "then it works with no zone painted (mode %s)" % u["mode"])
	assert_true(crew.zones.is_empty())
	assert_lt(_g.distance_m(int(u["job"]), 100), 40.0, "on a dirty hex right by the base")


func test_robots_take_near_work_first_and_never_idle_while_work_is_in_reach() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	for i: int in 3:
		crew.spawn("scoopie", 0, _g.cells_around(100, 1)[i + 1])
	_run(crew, 240.0, 0.2)
	for u: Dictionary in crew.robots():
		assert_lt(float(u["log"]["idle_s"]), 6.0, "%s idled %.1f s with a dirty region around it" % [u["name"], float(u["log"]["idle_s"])])
		assert_lt(_g.distance_m(crew.unit_cell(u), 100), 80.0, "%s stays near the base" % u["name"])


func test_a_robot_belongs_to_the_hub_it_is_built_at() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	assert_eq(crew.nearest_hub(_g.centers[_g.cells_around(far, 2)[7]]), far)
	assert_eq(crew.nearest_hub(_g.centers[100]), 100)
	var a: Dictionary = crew.spawn("scoopie", 0, 100, 100)
	var b: Dictionary = crew.spawn("scoopie", 0, far, far)
	var hb: Dictionary = crew.spawn("haulbug", 0, far, far)
	crew.run_far(600.0, 0.5)
	_run(crew, 5.0)
	assert_lt(_g.distance_m(crew.unit_cell(b), far), crew.region_m(), "the far hub's robot stays and cleans around its hub")
	assert_lt(_g.distance_m(crew.unit_cell(hb), far), crew.region_m(), "its hauler too")
	assert_lt(_g.distance_m(crew.unit_cell(a), 100), crew.region_m())
	assert_gt(float(b["log"]["junk"]), 50.0, "and works while Lumi is at the other hub")
	assert_gt(float(hb["log"]["hauled"]), 0.0, "bales are cashed at the far hub, not carried across the planet")
	assert_gt(float(crew.hub_log[far]["cubes"]), 0.0)


func test_haulers_leave_another_hubs_bales_alone() -> void:
	var w: Dictionary = _world(false)
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	crew.bales.append({"id": 1, "cell": far, "dir": _g.centers[far], "value": 5.0, "units": 10.0, "claimed": ""})
	var hb: Dictionary = crew.spawn("haulbug", 0, 100, 100)
	_run(crew, 3.0)
	assert_eq(str(hb["mode"]), "idle")
	assert_eq(str(hb["idle"]), "no bales")
	assert_eq(crew.bales_waiting(100), 0)
	assert_eq(crew.bales_waiting(far), 1)


func test_a_zone_belongs_to_the_hub_it_is_painted_at() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	var zc: int = _g.cells_around(100, 2)[9]
	crew.set_zone_cell("clean", zc, true)
	assert_eq(crew.claim_dirty(100, 100, -1, "clean", "a"), zc, "the home crew cleans the painted hex first")
	var fc: int = crew.claim_dirty(far, far, -1, "clean", "b")
	assert_lt(_g.distance_m(fc, far), crew.region_m(), "the other hub's crew carries on around its own hub")


func test_every_state_has_a_short_line_and_a_reason() -> void:
	var w: Dictionary = _world(false)
	var crew: SphereCrew = w["crew"]
	var sc: Dictionary = crew.spawn("scoopie", 0, 100)
	var hb: Dictionary = crew.spawn("haulbug", 0, 100)
	var dr: Dictionary = crew.spawn("drip", 0, 100)
	_run(crew, 3.0)
	assert_eq(CrewTalk.line(crew, sc), tr("No dirty ground left around this base."))
	assert_eq(CrewTalk.line(crew, hb), tr("No bales to carry right now."))
	assert_eq(CrewTalk.line(crew, dr), tr("Nothing to water yet. Plant something first."))
	assert_eq(CrewTalk.state(crew, sc), CrewTalk.IDLE)
	assert_eq(CrewTalk.state(crew, dr), CrewTalk.HELP, "the Drip needs the player: its light is amber")
	assert_true(CrewTalk.look_text(crew, sc).contains(str(sc["name"])))
	for why: String in ["zone clean", "zone done", "no bales", "nothing to plant", "out of seeds", "nothing to water", "no water", "no lake junk", "no path"]:
		assert_true(CrewTalk.IDLE_LINE.has(why), "idle reason '%s' has a line" % why)
		assert_lt(str(CrewTalk.IDLE_LINE[why]).length(), 50, "and it is short")
	for st: int in [CrewTalk.WORK, CrewTalk.MOVE, CrewTalk.CARRY, CrewTalk.IDLE, CrewTalk.HELP, CrewTalk.HELLO]:
		assert_eq(BotBadge.look(st, "clean").size(), 3)
	assert_eq(str(BotBadge.look(CrewTalk.HELP, "clean")[1]), "!")
	assert_ne(BotBadge.look(CrewTalk.WORK, "clean")[0], BotBadge.look(CrewTalk.WORK, "haul")[0], "jobs differ by colour")


func test_scoopies_ask_for_a_haul_bug_when_bales_pile_up() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var sc: Dictionary = crew.spawn("scoopie", 0, 100)
	for i: int in CrewTalk.PILE_NO_HAULER:
		crew.bales.append({"id": 100 + i, "cell": 100, "dir": _g.centers[100], "value": 5.0, "units": 10.0, "claimed": ""})
	_run(crew, 12.0)
	assert_true(CrewTalk.needs_hauler(crew, 100))
	assert_eq(CrewTalk.line(crew, sc), tr("Bales are piling up. Build a Haul Bug."))
	assert_true(bool(CrewTalk.hub_summary(crew, 100)["needs_hauler"]))
	crew.spawn("haulbug", 0, 100)
	_run(crew, 2.0)
	assert_false(CrewTalk.needs_hauler(crew, 100), "one Haul Bug is enough for a small pile")


func test_more_robots_clean_faster_and_the_readout_says_so() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	crew.spawn("scoopie", 0, 100)
	var one: Dictionary = CrewTalk.hub_summary(crew, 100)
	assert_eq(int(one["robots"]), 1)
	assert_between(float(one["hexes_per_hour"]), 10.0, 30.0, "a Mk I Scoopie: roughly 18 hexes an hour")
	crew.spawn("scoopie", 0, 100)
	crew.spawn("scoopie", 1, 100)
	crew.spawn("haulbug", 0, 100)
	var four: Dictionary = CrewTalk.hub_summary(crew, 100)
	assert_eq(int(four["robots"]), 4)
	assert_gt(float(four["hexes_per_hour"]), float(one["hexes_per_hour"]) * 3.2, "three Scoopies, one of them Mk II")
	assert_true(str(four["text"]).contains("4"))
	assert_eq(int(CrewTalk.hub_summary(crew, 5)["robots"]), 0)
	assert_eq(str(CrewTalk.hub_summary(crew, 5)["text"]), tr("No robots here yet"))
	# Measured: three Scoopies clean about three times what one does.
	var w1: Dictionary = _world()
	(w1["crew"] as SphereCrew).focus = null  # all far: run_far steps them
	(w1["crew"] as SphereCrew).spawn("scoopie", 0, 100)
	(w1["crew"] as SphereCrew).run_far(900.0, 0.5)
	var w3: Dictionary = _world()
	(w3["crew"] as SphereCrew).focus = null
	for i: int in 3:
		(w3["crew"] as SphereCrew).spawn("scoopie", 0, 100)
	(w3["crew"] as SphereCrew).run_far(900.0, 0.5)
	var j1: float = float((w1["crew"] as SphereCrew).units[0]["log"]["junk"])
	var j3: float = 0.0
	for u: Dictionary in (w3["crew"] as SphereCrew).units:
		j3 += float(u["log"]["junk"])
	assert_gt(j3, j1 * 2.6, "3 robots: %.0f units against %.0f for one" % [j3, j1])


func test_transfer_moves_a_robot_to_another_hub() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	crew.spawn("scoopie", 0, 100, 100)
	crew.spawn("scoopie", 0, 100, 100)
	assert_eq(crew.transfer_some(100, far, 1), 1)
	assert_eq(crew.hub_robots(far).size(), 1)
	assert_eq(crew.hub_robots(100).size(), 1)
	var u: Dictionary = crew.hub_robots(far)[0]
	assert_lt(_g.distance_m(crew.unit_cell(u), far), 30.0, "it stands at the new hub")
	crew.run_far(120.0, 0.5)
	assert_gt(float(u["log"]["junk"]), 0.0, "and cleans there")


func test_hub_log_and_hubs_survive_a_save() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	crew.spawn("scoopie", 0, far, far)
	crew.spawn("haulbug", 0, far, far)
	crew.run_far(400.0, 0.5)
	crew.set_zone_cell("clean", 101, true)
	var d: Dictionary = JSON.parse_string(JSON.stringify(crew.to_dict()))
	var w2: Dictionary = _world()
	var c2: SphereCrew = w2["crew"]
	c2.hubs = crew.hubs
	c2.from_dict(d)
	assert_eq(c2.hub_robots(far).size(), 2, "robots keep their hub")
	assert_almost_eq(float(c2.hub_log[far]["cubes"]), float(crew.hub_log[far]["cubes"]), 0.01)
	assert_true((c2.zones["clean"] as Dictionary).has(101))


func test_away_note_is_one_line_and_only_when_there_is_something_to_say() -> void:
	assert_eq(CrewTalk.away_text(0, 0.0), "")
	assert_true(CrewTalk.away_text(14, 0.0).contains("14"))
	var both: String = CrewTalk.away_text(14, 320.0)
	assert_true(both.contains("14") and both.contains("320"))
	assert_false(both.contains("\n"))


func test_away_note_shows_once_on_return() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	crew.spawn("scoopie", 0, far, far)
	crew.spawn("haulbug", 0, far, far)
	var oc := OrbitCrews.new()
	oc.set_process(false)
	add_child_autofree(oc)
	oc.crew = crew
	var got: Array = []
	var on_toast: Callable = func(text: String, _kind: String) -> void: got.append(text)
	EventBus.toast.connect(on_toast)
	for i: int in 200:  # Lumi at hub 100; the far crew works 400 s unwatched
		crew.run_far(2.0, 0.5)
		oc._away_tick(2.0)
	assert_eq(got.size(), 0, "nothing while he is away")
	(w["lumi"] as Node3D).global_position = (w["surface"] as SphereSurface).ground(_g.centers[far])
	oc._away_tick(1.0)
	assert_eq(got.size(), 1, "one note on return")
	oc._away_tick(1.0)
	crew.run_far(30.0, 0.5)
	oc._away_tick(1.0)
	assert_eq(got.size(), 1, "and not again while he stays")
	EventBus.toast.disconnect(on_toast)


func test_command_view_offers_only_jobs_you_have_robots_for() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var cmd := SphereCommand.new()
	cmd.crew = crew
	cmd.grid = _g
	cmd.surface = w["surface"]
	add_child_autofree(cmd)
	assert_eq(cmd.roles(), ["clean"] as Array[String])
	crew.spawn("scoopie", 0, 100)
	crew.spawn("haulbug", 0, 100)
	assert_eq(cmd.roles(), ["clean"] as Array[String], "Haul Bugs follow the bales: nothing to paint")
	crew.spawn("drip", 0, 100)
	assert_eq(cmd.roles(), ["clean", "water"] as Array[String])
	cmd.next_role()
	assert_eq(cmd.role, "water")
	cmd.next_role()
	assert_eq(cmd.role, "clean")
	var lines: Array = CommandOverlay.card_lines(cmd)
	var all: String = ""
	for l: Dictionary in lines:
		all += str(l["text"]) + "|"
	assert_true(all.contains("3"), "the card counts the hub's robots: %s" % all)
	assert_true(all.contains(tr("Cleaners")) and all.contains(tr("Haulers")) and all.contains(tr("Waterers")), "with a legend row per job: %s" % all)
	var hints: Array = CommandOverlay.hint_lines(cmd)
	assert_eq(str(hints[0]), tr("Paint the ground you want cleaned first."))
	cmd.using_pad = true
	assert_true(str(CommandOverlay.hint_lines(cmd)[1]).contains("A"), "the pad gets pad keys")
	cmd.painted_now = 2
	assert_eq(str(CommandOverlay.hint_lines(cmd)[0]), tr("Good! Your robots will work here first."))
	assert_true(CommandOverlay.other_bases(crew, 100).is_empty(), "one base: no other-bases rows")


## [v6crew] The card also lists the other bases' crews, so one glance shows every robot.
func test_command_card_lists_other_bases() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	var far: int = _far_hub()
	crew.hubs = PackedInt32Array([100, far])
	crew.spawn("scoopie", 0, far, far)
	crew.spawn("scoopie", 0, far, far)
	var rows: Array = CommandOverlay.other_bases(crew, 100)
	assert_eq(rows.size(), 2, "a header and one row: %s" % [rows])
	assert_true(str(rows[1]["text"]).contains("2"), "the row counts that base's robots: %s" % rows[1]["text"])
	assert_true(CommandOverlay.other_bases(crew, far).is_empty(), "seen from the far base, the start base has none")


## No dead ends: every type goes from built to working, and what it bales is cashed, also after
## a save and a load in the middle and with Lumi far away.
func test_every_robot_type_works_from_build_to_cash_across_a_save() -> void:
	var w: Dictionary = _world()
	var crew: SphereCrew = w["crew"]
	crew.focus = null  # Lumi is far: every robot is a record
	crew.spend_seeds = false
	var hub_ring: PackedInt32Array = _g.cells_around(100, 3)
	var lake: int = hub_ring[20]
	(w["cells"] as SphereCells).set_state(lake, 5)
	(w["cells"] as SphereCells).set_junk(lake, 1.0)
	for c: int in [hub_ring[8], hub_ring[9]]:  # clean ground to plant, and one planted hex to water
		(w["cells"] as SphereCells).set_junk(c, 0.0)
		(w["cells"] as SphereCells).set_state(c, 1)
	(w["cells"] as SphereCells).set_state(hub_ring[9], 2)
	for t: String in ["scoopie", "haulbug", "skimmer", "seedling", "drip", "multibot"]:
		crew.greet(crew.spawn(t, 0, 100))
	crew.run_far(300.0, 0.5)
	var d: Dictionary = JSON.parse_string(JSON.stringify(crew.to_dict()))
	crew.from_dict(d)
	assert_eq(crew.robots().size(), 6, "all six come back from the save")
	crew.run_far(900.0, 0.5)
	var by: Dictionary = {}
	for u: Dictionary in crew.robots():
		by[str(u["type"])] = u
		assert_ne(str(u["mode"]), "hello", "%s is past its hello" % u["type"])
	assert_gt(float(by["scoopie"]["log"]["junk"]), 100.0, "the Scoopie scooped")
	assert_gt(float(by["multibot"]["log"]["junk"]), 100.0, "the Multibot cleaned")
	assert_gt(float(by["skimmer"]["log"]["junk"]), 5.0, "the Skimmer skimmed the lake")
	assert_gt(float(by["seedling"]["log"]["planted"]), 0.0, "the Seedling planted")
	assert_gt(float(by["drip"]["log"]["watered"]), 0.0, "the Drip watered")
	assert_gt(float(by["haulbug"]["log"]["hauled"]), 5.0, "the Haul Bug carried the bales")
	assert_gt(crew.cashed, 0.0, "and they were cashed")
	for u: Dictionary in crew.robots():
		assert_ne(CrewTalk.line(crew, u), "", "%s always has a line" % u["type"])
