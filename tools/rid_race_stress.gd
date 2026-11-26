extends Node
## [v12load] Stress repro for the headless dummy renderer's RID race. In Godot 4.7 its mesh
## (multimesh, material, shader, texture) owners are not thread-safe and a mesh's RID is allocated
## on the thread that makes it, so meshes made on two threads at once can be handed the same slot
## and one of them is left with a dead RID: in the save round trip's town build "Attempting to use
## an uninitialized RID", then SCRIPT ERROR in AssetLib.lite (BuildBudget.threads_ok).
## Each round opens a build budget and runs the game's threaded paths while this thread makes and
## frees meshes every frame, as a build does: OrbitPreload.start/finish (the globe's model files on
## loader threads), BuildBudget.fetch (the town kits) and BuildBudget.run_mesh_task (a worker that
## makes meshes). Then every mesh made or loaded must still be alive in the rendering server.
##   godot --headless --path . res://tools/rid_race_stress.tscn -- [--rounds=3] [--rid-threads]
## --rid-threads switches the fix off (the old threaded paths, headless too): dead meshes, or a
## crash, show the fault. Prints "[ridrace] PASS ..." and exits 0; "[ridrace] FAIL ..." exits 1.

const PER_FRAME: int = 300  # meshes made each frame on this thread; one in KEEP is kept, the rest freed
const KEEP: int = 10
const WORKER_MESHES: int = 3000

var _making: bool = false
var _made: Array[Mesh] = []
var _n_made: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var rounds: int = maxi(1, int(DevHooks.get_f("rounds", 3.0)))
	var mode: String = "the old threaded paths (--rid-threads)" if DevHooks.has("rid-threads") else "the game's paths"
	print("[ridrace] %d rounds, %s, threads_ok=%s, display %s" % [rounds, mode, BuildBudget.threads_ok(), DisplayServer.get_name()])
	var seen: int = 0
	var dead: int = 0
	for r: int in rounds:
		var res: Dictionary = await _round()
		seen += int(res["meshes"])
		dead += int(res["dead"])
		print("[ridrace] round %d: %d threaded requests, %d meshes alive to check (%d loaded, %d made here of %d, %d by the worker task): %d dead" % [
			r + 1, res["requests"], res["meshes"], res["loaded"], res["here"], res["made"], res["worker"], res["dead"]])
	var ok: bool = dead == 0
	print("[ridrace] %s: %d meshes checked, %d with a dead RID (%s)" % ["PASS" if ok else "FAIL", seen, dead, mode])
	get_tree().quit(0 if ok else 1)


func _process(_delta: float) -> void:
	if not _making:
		return
	for i: int in PER_FRAME:
		var m: ArrayMesh = _mesh()
		_n_made += 1
		if _n_made % KEEP == 0:
			_made.append(m)


static func _mesh() -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _round() -> Dictionary:
	_made.clear()
	_n_made = 0
	BuildBudget.begin(get_tree())
	_making = true
	var requests: int = OrbitPreload.start()
	var kits: Array[Resource] = []
	for id: String in [CityView.APT, CityView.FAC]:
		var path: String = AssetLib.MODEL_DIR % [id, id]
		var kit: Resource = await BuildBudget.fetch(path)
		if kit == null:
			kit = load(path)
		kits.append(kit)
	var box: Array = []
	var work := func() -> void:
		var out: Array = []
		for i: int in WORKER_MESHES:
			out.append(_mesh())
		box.append_array(out)
	await BuildBudget.run_mesh_task(work, "rid race meshes")
	await OrbitPreload.finish()
	_making = false
	BuildBudget.end()
	RenderingServer.force_sync()
	var loaded: Array[Mesh] = []
	for ps: Resource in kits + OrbitPreload._held:
		_scene_meshes(ps, loaded)
	var all: Array = []
	all.append_array(loaded)
	all.append_array(_made)
	all.append_array(box)
	var n_dead: int = 0
	for m: Mesh in all:
		if RenderingServer.mesh_get_surface_count(m.get_rid()) != m.get_surface_count():
			n_dead += 1
	var res: Dictionary = {"requests": requests, "meshes": all.size(), "loaded": loaded.size(), "here": _made.size(),
		"made": _n_made, "worker": box.size(), "dead": n_dead}
	# Let go of everything, so the next round loads the files afresh.
	OrbitPreload._held.clear()
	kits.clear()
	box.clear()
	all.clear()
	loaded.clear()
	_made.clear()
	for i: int in 3:
		await get_tree().process_frame
	return res


## The meshes a scene file holds (its nodes' Mesh properties), without instancing it.
static func _scene_meshes(ps: Resource, out: Array[Mesh]) -> void:
	if not ps is PackedScene:
		return
	var st: SceneState = (ps as PackedScene).get_state()
	for n: int in st.get_node_count():
		for p: int in st.get_node_property_count(n):
			var v: Variant = st.get_node_property_value(n, p)
			if v is Mesh and not out.has(v):
				out.append(v)
