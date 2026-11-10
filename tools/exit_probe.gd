extends Node
## Exit-state probe (bug B2): does a reload resume from the moment of exit or from the last autosave?
## Two processes share a dev save folder:
##   godot --headless --path . res://tools/exit_probe.tscn -- --fresh --autoplay --time-scale=8 --save-dir=b2probe --probe=write --exit-at=170
##   godot --headless --path . res://tools/exit_probe.tscn -- --save-dir=b2probe --probe=read
## "write" plays the globe under the bot, snapshots the state at every autosave and at --exit-at
## (game seconds; with --exit-carrying, the first moment after it with a bale on Lumi's back), then quits the way closing the window does (NOTIFICATION_WM_CLOSE_REQUEST to the
## whole tree). "read" starts the slice from that save and prints, per key, whether the reloaded
## value matches the exit snapshot, the last autosave, or neither. Exit code 1 if any key misses the
## exit snapshot.

const SNAP_PATH: String = "user://exit_probe_snaps.json"
## Lumi may drift this far (m) in the frames between the reload and the snapshot.
const POS_TOL_M: float = 1.5

var _slice: Node
var _autosave: Dictionary = {}
var _exit_at: float = 170.0
var _done: bool = false


func _ready() -> void:
	_exit_at = DevHooks.get_f("exit-at", 170.0)
	_slice = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_slice)
	if DevHooks.get_s("probe", "write") == "write":
		EventBus.game_saved.connect(_on_saved)
	else:
		_read.call_deferred()


func _process(_delta: float) -> void:
	if _done or DevHooks.get_s("probe", "write") != "write" or not _ready_world():
		return
	if float(GameState.stats.get("time_played", 0.0)) < _exit_at:
		return
	if DevHooks.has("exit-carrying") and (_slice.get("patch") as Patch).carried.is_empty():
		return  # wait for a moment with a bale on Lumi's back
	_done = true
	EventBus.game_saved.disconnect(_on_saved)
	var snaps: Dictionary = {"exit": snapshot(_slice), "autosave": _autosave}
	var f: FileAccess = FileAccess.open(SNAP_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(snaps))
	f.close()
	print("[b2] exit at %.1f s game time (last autosave at %.1f s)" % [float(snaps["exit"]["time_played"]), float(_autosave.get("time_played", -1.0))])
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)  # what a window close sends
	get_tree().quit()


func _ready_world() -> bool:
	return is_instance_valid(_slice) and _slice.is_inside_tree() and _slice.get("orbit") != null and (_slice.get("orbit") as SliceOrbit).globe != null and _slice.get("patch") != null


func _on_saved() -> void:
	if _ready_world():
		_autosave = snapshot(_slice)


func _read() -> void:
	while not _ready_world():
		await get_tree().process_frame
	var p: Patch = _slice.get("patch")
	p.set_process(false)  # nothing may scoop or walk between the reload and the snapshot
	p.set_physics_process(false)
	for i: int in 5:
		await get_tree().process_frame
		OrbitRoundtrip._freeze_crew(_slice)
	var got: Dictionary = snapshot(_slice)
	var snaps: Variant = JSON.parse_string(FileAccess.get_file_as_string(SNAP_PATH))
	if not snaps is Dictionary:
		print("[b2] FAIL no snapshots at %s (run --probe=write first)" % SNAP_PATH)
		get_tree().quit(1)
		return
	var ex: Dictionary = (snaps as Dictionary)["exit"]
	var au: Dictionary = (snaps as Dictionary)["autosave"]
	var misses: int = 0
	for k: String in ex:
		var at_exit: bool = same(k, ex[k], got.get(k))
		var at_auto: bool = au.has(k) and same(k, au[k], got.get(k))
		var verdict: String = "MATCH_EXIT" if at_exit else ("MATCH_AUTOSAVE" if at_auto else "NEITHER")
		if not at_exit:
			misses += 1
		print("[b2] %s %s: exit=%s autosave=%s reloaded=%s" % [verdict, k, str(ex[k]), str(au.get(k, "-")), str(got.get(k))])
	print("[b2] %s (%d keys differ from the exit moment)" % ["PASS" if misses == 0 else "FAIL", misses])
	get_tree().quit(1 if misses > 0 else 0)


static func same(key: String, a: Variant, b: Variant) -> bool:
	if key == "lumi_at" and a is Array and b is Array and (a as Array).size() == 3 and (b as Array).size() == 3:
		var pa := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var pb := Vector3(float(b[0]), float(b[1]), float(b[2]))
		return pa.distance_to(pb) <= POS_TOL_M
	return JSON.stringify(_num(a)) == JSON.stringify(_num(b))


## Ints and floats compare equal after the JSON trip (6 and 6.0).
static func _num(v: Variant) -> Variant:
	if v is int or v is float:
		return float(v)
	if v is Array:
		return (v as Array).map(func(e: Variant) -> Variant: return _num(e))
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in v:
			d[str(k)] = _num((v as Dictionary)[k])
		return d
	return v


## The state a player would notice after a reload. Values are JSON-safe so the read side can compare.
static func snapshot(s: Node) -> Dictionary:
	s.set_meta("rt_target", 0)
	var base: Dictionary = OrbitRoundtrip._snap(s)
	var out: Dictionary = {}
	for k: String in ["cubes", "cleaned", "lumi_fill", "parts_found", "hexes_paid", "hub_level", "robots", "loose_cubes", "yard_built", "garden"]:
		out[k] = JSON.parse_string(JSON.stringify(base[k]))
	var p: Patch = s.get("patch")
	var g: OrbitPlanet = (s.get("orbit") as SliceOrbit).globe
	out["lumi_at"] = [p.global_position.x, p.global_position.y, p.global_position.z]
	out["carried_bales"] = p.carried.size()
	out["time_played"] = snappedf(float(GameState.stats.get("time_played", 0.0)), 1.0)
	out["parts"] = snappedf(GameState.get_currency("parts").to_float(), 0.01)
	out["seeds"] = snappedf(GameState.get_currency("seeds").to_float(), 0.01)
	out["objective_step"] = int(GameState.flags.get("objective_step", 0))
	out["junk_dumps"] = int(GameState.stats.get("junk_dumps", 0))
	out["cubes_cashed"] = int(GameState.stats.get("cubes_cashed", 0))
	out["upgrade_levels"] = JSON.parse_string(JSON.stringify(GameState.upgrades))
	out["research_done"] = Research.done_list().duplicate()
	out["zone_cells"] = Goals.zone_hex_count()
	out["cells_junk_hash"] = hash(g.cells.to_dict()["junk"])
	return out
