extends GutTest
## [v6yard] Yard machines and hub landmarks on the art kit: the picture signs, the rebuilt baler and
## belt drive, the six landmark models and their data (data/machine_art.json, data/landmarks.json).

const TRI_BUDGET_MACHINE: int = 30000     # docs/PERFORMANCE.md "Yard machines and landmarks"
const TRI_BUDGET_LANDMARK: int = 50000
const SURFACES_LANDMARK: int = 14


func _tris(n: Node) -> int:
	var t: int = 0
	var all: Array[Node] = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		all.append(n)
	for c: Node in all:
		var m: Mesh = (c as MeshInstance3D).mesh
		if m == null:
			continue
		for s: int in m.get_surface_count():
			var idx: Variant = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array:
				@warning_ignore("integer_division")
				t += (idx as PackedInt32Array).size() / 3
	return t


func _surfaces(n: Node) -> int:
	var t: int = 0
	var all: Array[Node] = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		all.append(n)
	for c: Node in all:
		if (c as MeshInstance3D).mesh:
			t += (c as MeshInstance3D).mesh.get_surface_count()
	return t


func test_every_machine_has_a_sign_with_its_own_picture() -> void:
	var icons: Dictionary = {}
	for id: String in ["workbench", "trash_bin", "baler", "belt", "composter", "signal_tower", "fabricator", "recycler"]:
		var d: Dictionary = MachineArt.sign_def(id)
		assert_true(bool(d["show"]), id + " shows its sign")
		assert_false(icons.has(d["icon"]), id + ": no two machines share a picture")
		icons[d["icon"]] = true
		var mi: MeshInstance3D = MachineArt.sign_post(id).mi(0.15)
		add_child_autofree(mi)
		assert_gt(_tris(mi), 500, id + " sign has geometry")
		assert_lt(_tris(mi), 9000, id + " sign stays light")


func test_sign_data_overrides_defaults() -> void:
	var d: Dictionary = MachineArt.sign_def("workbench")
	assert_eq(str(d["icon"]), "wrench")
	assert_eq(str(d["face"]), str((MachineArt.cfg()["signs"] as Dictionary)["defaults"]["face"]), "defaults fill what a machine leaves out")
	assert_eq(str(MachineArt.sign_def("nothing_here")["icon"]), "nothing_here", "an unknown machine still gets a sign (an arrow)")


func test_baler_keeps_its_moving_parts() -> void:
	var b := AutoBaler.new()
	add_child_autofree(b)
	b.process_mode = Node.PROCESS_MODE_DISABLED
	assert_not_null(b.get_node_or_null("Body"))
	assert_not_null(b.get_node_or_null("Platen/Head"))
	assert_not_null(b.get_node_or_null("Gate/Bars"))
	var top: float = b._platen.position.y
	b.phase = "press"
	b._dur = 4.0
	b._t = 2.0
	b._bale_info = {"fill": 1.0}
	b._update_visuals(0.0)
	assert_lt(b._platen.position.y, top - 0.5, "the press head comes down")
	assert_lt(b._gate.position.y, 0.1, "the gate is down while pressing")
	assert_lt(_tris(b), TRI_BUDGET_MACHINE)
	assert_lt(_surfaces(b), 20, "baler draw calls")


func test_belt_drive_builds_within_budget() -> void:
	var c := Conveyor.new()
	add_child_autofree(c)
	c.process_mode = Node.PROCESS_MODE_DISABLED
	assert_not_null(c.get_node_or_null("Pad"))
	assert_not_null(c.get_node_or_null("Turntable/Disc"))
	assert_true(c.lines.has("depot"))
	assert_lt(_tris(c), TRI_BUDGET_MACHINE)
	assert_lt(_surfaces(c), 30, "belt drive draw calls (was 60+ single meshes)")


func test_landmarks_build_in_every_state_within_budget() -> void:
	for kind: String in HubLandmarks.kinds():
		assert_true(HubLandmarks.has(kind), kind)
		for st: String in ["broken", "repaired", "restored"]:
			var n: HubLandmarkNode = HubLandmarks.build(kind, st, 1, "verdance")
			add_child_autofree(n)
			var nm: String = "%s/%s" % [kind, st]
			assert_gt(n.data.tris, 5000, nm + " is a real model")
			assert_lt(_tris(n), TRI_BUDGET_LANDMARK, nm + " triangles")
			assert_lte(_surfaces(n), SURFACES_LANDMARK + (6 if kind == "ferris_wheel" else 0), nm + " draw calls")
			assert_gt(n.data.top.y, 3.0, nm + " has a top for the hub's beacon")
			assert_gt(n.data.solids.size(), 0, nm + " is solid")
			assert_ne(n.data.kiosk, Vector3.ZERO, nm + " has its wake console")
			assert_eq(n.powered, st != "broken", nm + ": only a woken landmark is lit")
			assert_eq(n.find_children("*", "OmniLight3D", true, false).size() > 0, st != "broken", nm + " lights")


func test_landmark_follows_the_hub_level() -> void:
	assert_eq(HubLandmarks.state_for_level(1), "broken")
	assert_eq(HubLandmarks.state_for_level(2), "repaired")
	assert_eq(HubLandmarks.state_for_level(5), "restored")
	var n: HubLandmarkNode = HubLandmarks.create("windpump", 1, 3, "verdance")
	add_child_autofree(n)
	assert_false(n.is_processing(), "asleep: the fan stands still")
	n.set_level(2)
	assert_eq(n.state, "repaired")
	assert_true(n.is_processing(), "awake: the fan turns")
	var a0: Basis = (n.get_node("Spin") as Node3D).basis
	n._process(0.5)
	assert_false((n.get_node("Spin") as Node3D).basis.is_equal_approx(a0))


func test_big_wheel_gondolas_hang_level_and_break() -> void:
	var w: HubLandmarkNode = HubLandmarks.build("ferris_wheel", "restored", 1, "verdance")
	add_child_autofree(w)
	var total: int = 0
	for g: Node in w.find_children("Gondolas*", "MultiMeshInstance3D", true, false):
		var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
		total += mm.instance_count
		w._process(1.0)
		assert_true(mm.get_instance_transform(0).basis.is_equal_approx(Basis()), "a gondola never tilts")
	assert_eq(total, w.data.gondola_n)
	var b: HubLandmarkNode = HubLandmarks.build("ferris_wheel", "broken", 1, "verdance")
	add_child_autofree(b)
	var left: int = 0
	for g: Node in b.find_children("Gondolas*", "MultiMeshInstance3D", true, false):
		left += (g as MultiMeshInstance3D).multimesh.instance_count
	assert_lt(left, total, "a broken wheel has lost gondolas")


func test_every_verdance_main_hub_has_a_kit_landmark() -> void:
	var seen: Dictionary = {}
	for e: Dictionary in HubPlan.entries("verdance"):
		if not HubPlan.is_main("verdance", int(e["site"])):
			continue
		var kind: String = HubPlan.landmark_kind("verdance", int(e["site"]))
		assert_true(HubLandmarks.has(kind), "%s: %s" % [e["id"], kind])
		assert_false(seen.has(kind), "%s: each main hub has its own landmark" % e["id"])
		seen[kind] = true
	assert_eq(seen.size(), 6)


func test_landmark_data_is_per_planet() -> void:
	var base: Dictionary = HubLandmarks.kind_cfg("water_tower", "")
	assert_gt(float(base["height"]), 5.0)
	var saved: Dictionary = HubLandmarks._cfg.duplicate(true)
	(HubLandmarks._cfg["planets"] as Dictionary)["testworld"] = {"water_tower": {"height": 7.0, "main": "plum"}}
	var o: Dictionary = HubLandmarks.kind_cfg("water_tower", "testworld")
	assert_eq(float(o["height"]), 7.0)
	assert_eq(str(o["main"]), "plum")
	assert_eq(float(o["radius"]), float(base["radius"]), "what a planet leaves out comes from the kind")
	assert_lt(HubLandmarks.data_for("water_tower", "repaired", 1, "testworld").top.y, HubLandmarks.data_for("water_tower", "repaired", 1, "").top.y)
	HubLandmarks._cfg = saved


func test_pod_repair_cart_shows_only_while_mending() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var site: CrashSite = CrashSite.attach(root, EscapePod.build(), Vector3.ZERO, 0.5)
	var cart: Node3D = site.get_node("Service")
	site.set_stage(0)
	assert_false(cart.visible, "freshly crashed: nothing tidy yet")
	site.set_stage(1)
	assert_true(cart.visible)
	site.set_stage(3)
	assert_false(cart.visible, "the planter-beacon pod needs no cart")
	assert_true((cart.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D).disabled)


func test_recycler_keeps_its_moving_parts() -> void:
	var r := Recycler.new()
	add_child_autofree(r)
	r.process_mode = Node.PROCESS_MODE_DISABLED
	assert_not_null(r.get_node_or_null("Body"))
	assert_eq(r._drums.size(), 2, "two shredder drums")
	assert_not_null(r._glow_mat)
	assert_not_null(r._ingots)
	assert_eq(str(MachineArt.sign_def("recycler")["icon"]), "parts")
	assert_lt(_tris(r), TRI_BUDGET_MACHINE)
	assert_lt(_surfaces(r), 20, "recycler draw calls (was 40+ single meshes)")


func test_every_verdance_hub_has_a_kit_landmark() -> void:
	for e: Dictionary in HubPlan.entries("verdance"):
		assert_true(HubLandmarks.has(HubPlan.landmark_kind("verdance", int(e["site"]))), str(e["id"]))
