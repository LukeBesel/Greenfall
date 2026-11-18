extends GutTest
## [v4calm] Owner item 43: Glim clings to the crashed pod until the workbench build "Repair Glim"
## brings him back; the objective chain asks for it right after the signal tower.

var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()


func after_each() -> void:
	GameState.from_dict(_saved)


func test_he_clings_to_the_pod_until_repaired() -> void:
	var pod := Node3D.new()
	add_child_autofree(pod)
	var g: GlimBot = GlimDirector.cling_to(pod)
	assert_not_null(g)
	assert_eq(String(g.name), GlimDirector.STUCK_NAME)
	assert_true(g.broken, "dark and stuck")
	assert_eq(g.get_parent(), pod, "on the pod (it flies and lands with it)")
	var front: Vector3 = g.basis * Vector3(0, 0, -1)
	assert_gt(front.dot(Vector3(g.position.x, 0, g.position.z).normalized()), 0.9, "faces out from the shell")
	Glim.set_found(true)
	var pod2 := Node3D.new()
	add_child_autofree(pod2)
	assert_null(GlimDirector.cling_to(pod2), "once repaired, pods are built without him")


func test_intro_pod_carries_him() -> void:
	var pod: Node3D = Intro.build_pod()
	add_child_autofree(pod)
	assert_not_null(pod.get_node_or_null(GlimDirector.STUCK_NAME))


func test_build_entry_is_listed_after_the_tower_and_cheap() -> void:
	var d: Dictionary = YardBuilds.def(GlimDirector.BUILD_ID)
	assert_false(d.is_empty())
	assert_true(GlimDirector.BUILD_ID in HubBuilds.ids(), "in data/builds.json")
	assert_lte(float((d["cost"] as Dictionary).get("cubes", 0.0)), 150.0, "an early cost")
	assert_false(YardBuilds.listed(GlimDirector.BUILD_ID, 1), "not before glim_ready")
	GameState.flags["glim_ready"] = true
	assert_true(YardBuilds.listed(GlimDirector.BUILD_ID, 1))


func test_buying_it_completes_the_step_and_queues_the_moment() -> void:
	var gd := GlimDirector.new()
	add_child_autofree(gd)
	gd._on_yard_built(GlimDirector.BUILD_ID)
	assert_true(bool(GameState.flags.get("glim_repaired", false)))
	assert_true(bool(GameState.flags.get("glim_repair_pending", false)), "the moment plays once menus close")
	assert_false(Glim.is_found(), "he wakes in the moment, not at purchase")


func test_objective_follows_the_tower() -> void:
	var objs: Array = (Economy.read_json("res://data/objectives.json") as Dictionary)["objectives"]
	var ids: Array = objs.map(func(o: Dictionary) -> String: return str(o["id"]))
	var i: int = ids.find("glim")
	assert_gt(i, 0)
	assert_eq(ids[i - 1], "tower")
	assert_eq(str(objs[i]["type"]), "flag")
	assert_eq(str(objs[i]["key"]), "glim_repaired")
