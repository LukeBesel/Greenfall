extends GutTest
## [v12load] Headless (the dummy renderer) no game path makes rendering resources on another thread
## while the main thread makes its own: in Godot 4.7 that renderer's mesh, material and texture
## owners are not thread-safe, and meshes made on two threads at once could share a slot (one dead
## RID: the save round trip failed now and then in the town build, SCRIPT ERROR in AssetLib.lite).
## BuildBudget.threads_ok() says so; tools/rid_race_stress.tscn shows the fault itself.


func after_each() -> void:
	BuildBudget.end()


func test_headless_says_no_threads() -> void:
	assert_eq(DisplayServer.get_name(), "headless")
	assert_false(BuildBudget.threads_ok(), "the dummy renderer's resource owners are not thread-safe")


func test_globe_preload_requests_nothing_on_threads() -> void:
	assert_eq(OrbitPreload.start(), 0, "no model file on a loader thread")
	for id: String in OrbitPreload.model_ids():
		var path: String = AssetLib.MODEL_DIR % [id, id]
		assert_ne(ResourceLoader.load_threaded_get_status(path), ResourceLoader.THREAD_LOAD_IN_PROGRESS, path)
	await OrbitPreload.finish()


func test_fetch_leaves_the_load_to_the_main_thread() -> void:
	BuildBudget.begin(get_tree())
	var path: String = AssetLib.MODEL_DIR % [CityView.APT, CityView.APT]
	var r: Resource = await BuildBudget.fetch(path)
	assert_null(r, "the caller's own load() does it")
	assert_eq(ResourceLoader.load_threaded_get_status(path), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "never requested")


func test_mesh_task_runs_on_the_main_thread() -> void:
	BuildBudget.begin(get_tree())
	var box: Array = [-1]
	var work := func() -> void:
		box[0] = OS.get_thread_caller_id()
	await BuildBudget.run_mesh_task(work, "test")
	assert_eq(box[0], OS.get_main_thread_id())
