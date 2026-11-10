class_name OrbitPreload
extends RefCounted
## [orbE] Load time on the globe (docs/PERFORMANCE.md): the near ring's junk needs every junk and
## landmark model, and AssetLib loaded them one by one on the main thread inside the streamer's
## first settle (7 s on Anvil). start() asks the resource loader for all of them on its threads
## at the top of the build; by the time the planet, grid and field are made they are in memory,
## and AssetLib's load() is a cache hit. finish() collects them (and keeps them referenced).

static var _held: Array[Resource] = []
static var _paths: PackedStringArray = []


static func model_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for tid: Variant in Economy.junk_types:
		for m: Variant in (Economy.junk_types[tid] as Dictionary).get("models", []):
			var id: String = str((m as Dictionary).get("id", "")) if m is Dictionary else str(m)
			if id != "" and not ids.has(id):
				ids.append(id)
	for d: Variant in Economy.landmarks_for(""):
		var id2: String = str((d as Dictionary).get("id", "")) if d is Dictionary else ""
		if id2 != "" and not ids.has(id2):
			ids.append(id2)
	return ids


## [v5load] Models the rest of the build loads one by one on the main thread (street props, the
## yard, wildlife, outposts ...), recorded with `--orbit --fresh --record-preload`. A missing or
## stale entry only means that model loads where it is used, as before.
const LIST: String = "res://data/orbit_preload.json"


static func listed() -> Array:
	return Economy.read_json(LIST).get("models", []) if FileAccess.file_exists(LIST) else []


static func record(traced: Array[String]) -> void:
	var have: Array = listed()
	for id: String in traced:
		if not have.has(id):
			have.append(id)
	var f := FileAccess.open(LIST, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_note": "Models the globe build loads on the main thread (planet/orbit_preload.gd warm). Regenerate: godot --headless --path . -- --fresh --orbit --record-preload --quit-after=30", "models": have}, "\t") + "\n")
	f.close()
	print("[orbit-load] preload list: %d models (%d this build)" % [have.size(), traced.size()])


## [v5load] Behind the loading screen: wait (yielding frames) for each listed model's file, which
## the loader threads have been reading since start(), then build its mesh within the frame
## budget, so the builders' model_mesh() / model_part() calls are cache hits.
static func warm() -> void:
	if not BuildBudget.active() or DevHooks.has("orbit-no-preload") or DevHooks.has("record-preload"):
		return
	var was: bool = AssetLib.tracing
	for tp: String in _paths.duplicate():  # the build's textures: wait for them, then hold them
		if not tp.contains("/textures/"):
			continue
		while BuildBudget.active() and ResourceLoader.load_threaded_get_status(tp) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await BuildBudget.pause("preload texture")
		var r: Resource = ResourceLoader.load_threaded_get(tp)
		if r:
			_held.append(r)
		_paths.remove_at(_paths.find(tp))
	# Meshing a model (merging its parts) and simplifying it (the "lite" meshes) are 50-150 ms
	# each and can't be split, so one worker task does them all while the loader keeps drawing.
	# Nothing else builds meanwhile (the build awaits this), so AssetLib's caches have one writer.
	var todo: Array = listed()
	var work := func() -> void:
		for e: Variant in todo:
			var id: String = str(e)
			if id.begins_with("tex:"):
				continue  # textures: start() asked for them; held above
			if id.begins_with("lite:"):
				var spec: String = id.substr(5)
				if AssetLib.has_model(spec.get_slice("@", 0)):
					AssetLib.model_mesh_lite(spec.get_slice("@", 0), int(spec.get_slice("@", 1)))
			elif id.begins_with("part:"):
				if AssetLib.has_model(id.substr(5).get_slice("::", 0)):
					AssetLib.model_part(id.substr(5).get_slice("::", 0), id.substr(5).get_slice("::", 1))
			elif AssetLib.has_model(id):
				AssetLib.model_mesh(id)
	AssetLib.tracing = false  # fetched: not blocking loads
	await BuildBudget.join(BuildBudget.add_task(work, "preload meshes"))
	AssetLib.tracing = was


static func start() -> int:
	_paths.clear()
	if DevHooks.has("orbit-no-preload"):  # A/B for load timing
		return 0
	var ids: PackedStringArray = PackedStringArray()
	for e: Variant in listed():  # [v5load] the build's own models first: they are needed first
		var lid: String = str(e)
		if lid.begins_with("lite:"):
			lid = lid.substr(5).get_slice("@", 0)
		if lid.begins_with("tex:"):  # a texture the build loads: its path
			var tp: String = lid.substr(4)
			if not ResourceLoader.has_cached(tp) and ResourceLoader.exists(tp) and ResourceLoader.load_threaded_request(tp, "", false) == OK:
				_paths.append(tp)
			continue
		if lid.begins_with("part:"):
			lid = lid.substr(5).get_slice("::", 0)
		if not ids.has(lid):
			ids.append(lid)
	for jid: String in model_ids():
		if not ids.has(jid):
			ids.append(jid)
	for id: String in ids:
		if not AssetLib.has_model(id):
			continue
		var path: String = AssetLib.MODEL_DIR % [id, id]
		if ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_paths.append(path)
	return _paths.size()


## Wait for the requests (normally long done) and hold the results.
static func finish() -> void:
	for path: String in _paths:
		while BuildBudget.active() and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await BuildBudget.pause("preload wait")  # [v5load] never block a frame on a slow disk
		var r: Resource = ResourceLoader.load_threaded_get(path)
		if r:
			_held.append(r)
	_paths.clear()
