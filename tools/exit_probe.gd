extends Node
## Exit-state probe (bug B2): does a reload resume from the moment of exit or from the last autosave?
## Two processes share a dev save folder:
##   godot --headless --path . res://tools/exit_probe.tscn -- --fresh --autoplay --time-scale=8 --save-dir=b2probe --probe=write --exit-at=170
##   godot --headless --path . res://tools/exit_probe.tscn -- --save-dir=b2probe --probe=read [--no-away]
## --no-away reloads as if no real time passed since the save (no offline jump for the crews), so a
## late save can be compared key by key; research still finishes on the real clock.
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
var _away_s: float = -1.0
var _carry_t: float = 0.0
## Frames the bale has been carried: at --time-scale=8 one slow frame is a whole game second, and a
## bale measured before its pick-up tween has stepped reads as lying at Lumi's feet.
var _carry_frames: int = 0


func _ready() -> void:
	_exit_at = DevHooks.get_f("exit-at", 170.0)
	if DevHooks.has("no-away") and DevHooks.get_s("probe", "write") != "write":
		# The slice loads the save and restores the crews in one go, so the save's own clock is moved
		# to now (this dev save only): their offline jump then finds no time away.
		var d: Dictionary = SaveManager.read_dict(SaveManager.slot_path())
		if not d.is_empty():
			d["saved_unix"] = Time.get_unix_time_from_system()
			SaveManager.write_dict(SaveManager.slot_path(), d)
	_slice = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_slice)
	if DevHooks.get_s("probe", "write") == "write":
		EventBus.game_saved.connect(_on_saved)
	else:
		SaveManager.set_process(false)  # a slow reload must not autosave over the save it is checking
		_read.call_deferred()


func _process(_delta: float) -> void:
	if _away_s < 0.0 and GameState.saved_unix > 0.0:
		_away_s = Time.get_unix_time_from_system() - GameState.saved_unix
		print("[b2] the save is %.0f s old (real time away)" % _away_s)
	if _done or DevHooks.get_s("probe", "write") != "write" or not _ready_world():
		return
	if float(GameState.stats.get("time_played", 0.0)) < _exit_at:
		return
	if DevHooks.has("exit-carrying"):  # wait for a bale that has sat on Lumi for a second (its pick-up tween is over)
		_carry_t = _carry_t + _delta if not (_slice.get("patch") as Patch).carried.is_empty() else 0.0
		_carry_frames = _carry_frames + 1 if _carry_t > 0.0 else 0
		if _carry_t > 0.0 and DevHooks.has("probe-verbose"):  # the bale's height on the stack, frame by frame
			var cp: Patch = _slice.get("patch") as Patch
			var b: JunkCube = cp.carried[0]
			print("[b8] carried %.2f s: bale y on the stack %.2f (rest %.2f), frozen=%s can_process=%s paused=%s tweens=%d lumi_speed=%.2f" % [_carry_t, b.position.y, b.size * 0.5,
				str(b.freeze), str(b.can_process()), str(get_tree().paused), get_tree().get_processed_tweens().size(), cp.velocity.length()])
			if _carry_frames == 6:  # is the height held by something? lift it by hand once and watch the next frames
				b.position.y = 2.0
				print("[b8] bale set to y 2.00 by the probe")
		if _carry_t < 1.0 or _carry_frames < 12:
			return
	_done = true
	EventBus.game_saved.disconnect(_on_saved)
	if DevHooks.has("exit-carrying"):
		print("[b8] %s" % JSON.stringify(carry_gap(_slice.get("patch") as Patch)))
		if DevHooks.has("probe-verbose"):
			var pp: Patch = _slice.get("patch") as Patch
			var b0: JunkCube = pp.carried[0]
			print("[b8] parent=%s top_level=%s bale.position=%s parent.position=%s patch.scale=%s model.scale=%s model.position=%s task_carried_for=%.2f s" % [b0.get_parent().name, str(b0.top_level),
				str(b0.position.snappedf(0.01)), str((b0.get_parent() as Node3D).position.snappedf(0.01)), str(pp.scale), str(pp.model.scale), str(pp.model.position.snappedf(0.01)), _carry_t])
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
	var marks: GardenMarks = _find_marks(_slice)
	if marks != null:  # B9: what the reloaded garden draws for its plants (counts only; the look needs a render)
		for i: int in 20:
			await get_tree().process_frame
		print("[b9] garden marks after the reload: %s" % JSON.stringify(marks.shown))
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
	# Found parts by saved key: the field's own array only knows the cells built so far, and a reload
	# builds fewer of them than a long session has.
	out["parts_found"] = Marshalls.base64_to_raw(str(g.field.to_dict().get("parts_found", ""))).to_int32_array().size()
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


## B8, the part a headless run can measure: how far the lowest point of the first carried bale sits
## above the top of Lumi's model, in Lumi's own space (m; negative = the bale's box dips into the
## body's box). "solid" skips thin parts the way CarryPoint does; "all" counts every visible mesh.
static func carry_gap(p: Patch) -> Dictionary:
	var inv: Transform3D = p.global_transform.affine_inverse()
	var top_solid: float = 0.0
	var top_all: float = 0.0
	for n: Node in p.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var ab: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		if ab.position.y > 2.5:
			continue
		top_all = maxf(top_all, ab.end.y)
		if ab.size.x >= 0.12 or ab.size.z >= 0.12:
			top_solid = maxf(top_solid, ab.end.y)
	# The bale's own box (its size around its origin): its child meshes include a ground shadow.
	var bale: JunkCube = p.carried[0]
	var bottom: float = (inv * bale.global_position).y - bale.size * 0.5
	return {"bale_bottom": snappedf(bottom, 0.01), "model_top_solid": snappedf(top_solid, 0.01), "model_top_all": snappedf(top_all, 0.01),
		"gap_solid": snappedf(bottom - top_solid, 0.01), "gap_all": snappedf(bottom - top_all, 0.01), "bales": p.carried.size(),
		"bale_size": snappedf(bale.size, 0.01), "carry_point_y": snappedf(CarryPoint.of(p.model, p).y, 0.01)}


static func _find_marks(n: Node) -> GardenMarks:
	if n is GardenMarks:
		return n as GardenMarks
	for c: Node in n.get_children():
		var m: GardenMarks = _find_marks(c)
		if m != null:
			return m
	return null
