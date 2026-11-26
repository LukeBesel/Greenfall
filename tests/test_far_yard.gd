extends GutTest
## [v10base] Owner playtest 3 #100-104: every far base's own yard (planet/sites/far_yard.gd), the
## junk round its pad (YardKeepOut.add_pad) and the ship's heading in the hop (HubHop.nose_along).

var _orbit: Dictionary
var _flags: Dictionary
var _active: String


func before_each() -> void:
	_orbit = GameState.orbit
	_flags = GameState.flags.duplicate(true)
	_active = HubPlan.active_planet
	GameState.orbit = {"schema": 1}
	HubPlan.active_planet = "verdance"


func after_each() -> void:
	GameState.orbit = _orbit
	GameState.flags = _flags
	HubPlan.active_planet = _active
	HubPlan.reload()


func test_every_far_base_asks_for_its_own_workbench_before_the_wake() -> void:
	for e: Dictionary in HubPlan.entries("verdance"):
		var s: int = int(e["site"])
		if HubPlan.is_home("verdance", s):
			continue
		var does: Array = HubPlan.chain("verdance", s).map(func(d: Dictionary) -> String: return str(d["do"]))
		assert_eq(does[0], "clean", "base %d starts with its junk" % s)
		assert_true(does.has("build"), "base %d has a build step (%s)" % [s, str(does)])
		assert_lt(does.find("build"), does.find("wake"), "base %d: the bench before the wake" % s)
		assert_eq(does[does.size() - 1], "wake")


func test_the_spots_have_prices_and_signs() -> void:
	for id: String in FarYard.ORDER:
		var c: Dictionary = FarYard.cost("verdance", id)
		assert_gt(float(c.get("cubes", 0)), 0.0, "%s has a price" % id)
		var sign_id: String = str((FarYard.SPOTS[id] as Array)[3])
		assert_ne(str(MachineArt.sign_def(sign_id).get("icon", "")), "", "%s has a picture sign" % id)
		assert_ne(FarYard.title(id), id)
	assert_gt(MachineArt.sign_post("locker", 2.1).mi(0.12, "S").mesh.get_surface_count(), 0, "the locker's sign draws")


func test_built_state_is_per_base_and_saved_in_the_orbit() -> void:
	assert_false(FarYard.is_built(9, "bench"))
	FarYard.mark_built(9, "bench")
	assert_true(FarYard.is_built(9, "bench"))
	assert_false(FarYard.is_built(7, "bench"), "another base's bench is its own")
	assert_false(FarYard.is_built(9, "locker"))
	FarYard.mark_built(9, "bot_bay")
	assert_true(BotBay.built("9"), "the Bot Bay's own store knows")
	assert_false(BotBay.built("7"))
	assert_true(bool(((GameState.orbit["hub_plan"] as Dictionary)["9"] as Dictionary)["yard"]["bench"]), "kept in the orbit save")
	FarYard.mark_built(9, "locker")
	assert_true(bool(GameState.flags.get("locker_owned", false)), "a locker at any base counts as owning one")


func test_an_older_saves_woken_base_keeps_its_bench() -> void:
	HubPlan.state(7)["woken"] = true
	assert_true(FarYard.is_built(7, "bench"), "the free field bench of an older save")
	assert_false(FarYard.is_built(7, "locker"))
	FarYard.mark_built(7, "locker")
	assert_true(FarYard.is_built(7, "bench"), "still there once the yard's own state exists")


func test_a_far_pad_keeps_junk_and_parts_off_itself_only() -> void:
	var ko := YardKeepOut.new()
	ko.radius = 1800.0
	ko.xf_inv = Transform3D(Basis(), Vector3(0, -1800.0, 0)).affine_inverse()
	var dir := Vector3(1, 0.4, 0.2).normalized()
	var xf := Transform3D(SphereGrid.frame(dir), dir * 1800.0)
	ko.add_pad(4, xf)
	var at := func(x: float, z: float) -> Vector3: return (xf * Vector3(x, 0, z)).normalized()
	assert_true(ko.blocks(at.call(0.0, 0.0)), "the pad's middle")
	assert_true(ko.blocks(at.call(9.5, -9.5)), "its corner")
	assert_false(ko.blocks(at.call(12.0, 0.0)), "junk lies 1.5 m off the pad's edge")
	assert_false(ko.in_building(at.call(0.0, 0.0)), "Lumi walks on the pad")
	assert_true(ko.near_e_point(at.call(14.0, 3.0)), "no buried part by the pad's machines")
	assert_false(ko.near_e_point(at.call(20.0, 3.0)), "parts lie further out")
	assert_false(ko.near_e_point(-dir), "nor on the far side of the planet")


func test_the_ship_flies_nose_first() -> void:
	var up := Vector3(0.2, 1.0, 0.1).normalized()
	for fwd: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-0.6, 0.3, 0.7)]:
		var b: Basis = HubHop.nose_along(fwd, up)
		var flat: Vector3 = (fwd - up * fwd.dot(up)).normalized()
		assert_gt(b.z.dot(flat), 0.99, "the nose (+Z) leads along %s" % str(fwd))
		assert_gt(b.y.dot(up), 0.99, "the right way up")
		assert_almost_eq(b.determinant(), 1.0, 0.001, "not mirrored")
