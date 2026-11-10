class_name OrbitPreload
extends RefCounted
## [orbE] Load time on the globe (docs/PERFORMANCE.md): the near ring's junk needs every junk and
## landmark model, and AssetLib loaded them one by one on the main thread inside the streamer's
## first settle (7 s on the largest globe). start() asks the resource loader for all of them on its threads
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


static func start() -> int:
	_paths.clear()
	if DevHooks.has("orbit-no-preload"):  # A/B for load timing
		return 0
	for id: String in model_ids():
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
		var r: Resource = ResourceLoader.load_threaded_get(path)
		if r:
			_held.append(r)
	_paths.clear()
