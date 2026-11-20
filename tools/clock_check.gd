class_name ClockCheck
extends Node
## Owner item 110 (20 Nov): "Also i think we remove the robots worked when I got off the game
## thing. They work when I am in different locations and on different planets but not when i log
## off type thing." Two dev checks, both headless on the globe (`-- --orbit --no-intro`):
##
##   --clock-check=save   (with --fresh --robots=scoopie:2,haulbug:1 --save-dir=NAME) cleans 8 hexes, plays
##                        --clock-wait=S game seconds (default 45) with robots out, a few seeds
##                        planted, a research running and the rocket's cells refilling, saves, and
##                        writes what the world holds to the save folder (clock_snap.json).
##   --clock-check=load   (same --save-dir) loads that save and compares the world right after the
##                        robots are restored, where the away pay used to run: cubes, parts,
##                        seeds, clean hexes, junk left, bales, plants, every robot, the research
##                        and rocket timers. Then plays 8 s and fails on any "while you were away"
##                        message. Exit 1 on a difference.
## tools/check_clock_save.sh runs the load with the save's time stamp moved hours and days both
## ways (tools/clock_save.gd), and once as an old save that still has the away keys.
##
##   --work-watch[=S]     a "[work]" line every S game seconds (default 30): where Lumi stands, the
##                        cubes, the clean hexes, and what each base's robots and keepers did; with
##                        --work-pause=T the game is paused for 5 real seconds at game second T and
##                        the numbers before and after must be the same ("[work] pause PASS").
## Lines: "[clock] ...", "[work] ...".

const SNAP: String = "clock_snap.json"
const BANNED: Array[String] = ["while you were away", "welcome back", "away for"]

static var _node: ClockCheck

var so: SliceOrbit
var toasts: Array[String] = []
var diffs: Array[String] = []
var _loaded: Dictionary = {}
var _watch_t: float = 0.0
var _watch_next: float = 0.0
var _pause_done: bool = false


static func wanted() -> bool:
	return DevHooks.has("clock-check") or DevHooks.has("work-watch")


## Called by scenes/slice_orbit.gd just before the saved robots come back: listens from here on.
static func before_restore(p_so: SliceOrbit) -> void:
	if _node != null and is_instance_valid(_node):
		return
	_node = ClockCheck.new()
	_node.name = "ClockCheck"
	_node.so = p_so
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.toast.connect(_node._on_toast)
	p_so.w.add_child(_node)


## Called right after the robots are restored and a landing's catch-up has run.
static func after_restore(p_so: SliceOrbit) -> void:
	if _node == null or not is_instance_valid(_node) or DevHooks.get_s("clock-check", "") != "load":
		return
	_node._compare()


## Called once the world's sites are up (planet/sites/orbit_sites.gd).
static func run_dev(p_so: SliceOrbit) -> void:
	before_restore(p_so)
	match DevHooks.get_s("clock-check", ""):
		"save":
			_node._run_save.call_deferred()
		"load":
			_node._run_load.call_deferred()


func _on_toast(text: String, _kind: String = "") -> void:
	toasts.append(text)


# --- What the world holds ------------------------------------------------------------------------

## Everything the owner's wish covers, as plain numbers and strings (JSON-safe).
static func state(p_so: SliceOrbit) -> Dictionary:
	var g: OrbitPlanet = p_so.globe
	var out: Dictionary = {}
	for id: String in ["cubes", "parts", "seeds"]:
		out[id] = snappedf(GameState.get_currency(id).to_float(), 0.001)
	out["hexes_stat"] = int(GameState.stats.get("hexes_cleaned", 0))
	out["hexes_clean"] = g.field.cleaned_count
	var junk: float = 0.0
	var dirty: int = 0
	for c: int in g.cells.junk.size():
		junk += g.cells.junk[c]
		dirty += 1 if g.cells.is_dirty(c) else 0
	out["junk_left"] = snappedf(junk, 0.01)
	out["dirty_cells"] = dirty
	var cubes_root: Node = p_so.w.get("_cubes_root")
	var loose: int = 0
	for n: Node in cubes_root.get_children():
		var jc: JunkCube = n as JunkCube
		loose += 1 if jc != null and not jc.carried and not jc.claimed and not jc.is_queued_for_deletion() else 0
	out["bales_loose"] = loose
	var crew: SphereCrew = p_so.crews.crew if p_so.crews != null else null
	var robots: Array = []
	if crew != null:
		var cd: Dictionary = crew.to_dict()
		out["bales_crew"] = (cd["bales"] as Array).size()
		out["crew_cashed"] = snappedf(float(cd["cashed"]), 0.001)
		for r: Dictionary in cd["robots"]:
			var d: Array = r["dir"]
			robots.append("%s %s t%d hub %d hopper %.2f carry %d junk %.2f at %.4f,%.4f,%.4f" % [str(r["name"]), str(r["type"]), int(r["tier"]), int(r["hub"]),
				float(r["hopper"]), (r["carry"] as Array).size(), float((r["log"] as Dictionary).get("junk", 0.0)), float(d[0]), float(d[1]), float(d[2])])
	out["robots"] = robots
	var gdn: Garden = p_so.w.get("garden") as Garden
	var plants: Array = []
	if gdn != null:
		for s: int in gdn.slot_species.size():
			if gdn.slot_species[s] >= 0:
				plants.append("hex %d species %d stage %d progress %.3f water %.1f" % [gdn.slot_hex[s], gdn.slot_species[s], gdn.slot_stage[s], gdn.slot_progress[s], gdn.slot_water[s]])
		plants.sort()
	out["plants"] = plants
	out["plants_saved"] = JSON.stringify(GameState.world.get("garden", {})).md5_text()
	out["research"] = Research.active_id()
	out["research_left"] = snappedf(Research.remaining(), 0.01)
	out["research_done"] = Research.done_list().size()
	out["rocket_left"] = snappedf(RocketTiers.recharge_left(), 0.01)
	out["played"] = snappedf(float(GameState.stats.get("time_played", 0.0)), 0.01)
	return out


static func _snap_path() -> String:
	return SaveManager.save_dir().path_join(SNAP)


# --- save ---------------------------------------------------------------------------------------

func _run_save() -> void:
	var tree: SceneTree = get_tree()
	await tree.create_timer(2.0).timeout
	# A few seeds in the ground, watered, on the land hexes round the pad.
	GameState.add_currency("seeds", BigNum.from_float(12.0))
	GameState.add_currency("cubes", BigNum.from_float(6000.0))
	var gdn: Garden = so.w.get("garden") as Garden
	var planted: int = 0
	var start: int = int((so.globe.sites[0] as Dictionary)["cell"])
	# Eight hexes by the pad cleaned the way a robot's last scoop does it (so the count, the pay and
	# the ground all know), for seeds to go into.
	var cleaned: int = 0
	for c: int in so.globe.grid.cells_around(start, 6):
		if cleaned >= 8:
			break
		if so.globe.field.is_water(c) or so.globe.field.hex_hub[c] != 0 or not so.globe.cells.is_dirty(c):
			continue
		var gone: PackedInt32Array = SphereWork.write_cell(so.globe.cells, so.globe.field, c, 0.0)
		if so.globe.get("junk_view") != null:
			for pid: int in gone:
				so.globe.get("junk_view").call("hide_piece", pid)
		so.on_hex_clean(c, true)
		cleaned += 1
	await tree.create_timer(1.0).timeout
	if gdn != null:
		for c: int in so.globe.grid.cells_around(start, 5):
			if planted >= 6 or so.globe.field.is_water(c) or so.globe.cells.is_dirty(c):
				continue  # seeds go in clean ground, as in play
			gdn.ensure_hex(c)
			for s: int in gdn.hex_slots.get(c, PackedInt32Array()):
				if planted < 6 and gdn.slot_species[s] < 0 and gdn.plantable(s) and gdn.plant(s):
					gdn.water(s, 20.0 + 10.0 * planted)
					planted += 1
					break
	# A research on the go and the rocket's cells refilling: the two timers that used the system clock.
	var started: String = ""
	for id: String in Research.ids():
		if Research.can_start(id) and Research.duration(id) > 120.0 and Research.start(id):
			started = id
			break
	if started == "":  # a new game has no research bench yet: put one on the go as the bench would
		for id: String in Research.ids():
			if not Research.has(id) and Research.duration(id) > 120.0:
				Research.state()["active"] = {"id": id, "start": Research.now(), "dur": Research.duration(id)}
				started = id
				break
	RocketTiers.mark_launched()
	var wait_s: float = DevHooks.get_f("clock-wait", 45.0)
	var t0: float = float(GameState.stats.get("time_played", 0.0))
	while float(GameState.stats.get("time_played", 0.0)) - t0 < wait_s:
		await tree.create_timer(0.5).timeout
	var ok: bool = SaveManager.save_game()
	var st: Dictionary = ClockCheck.state(so)
	var f := FileAccess.open(ClockCheck._snap_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(st, "\t"))
		f.close()
	print("[clock] saved (%s): cubes %s, parts %s, seeds %s, hexes %d, junk left %s, bales %d + %d, plants %d (planted %d), robots %d, research %s %.1f s left, rocket %.1f s left, played %.1f s" % [
		"ok" if ok and f != null else "FAILED", str(st["cubes"]), str(st["parts"]), str(st["seeds"]), int(st["hexes_clean"]), str(st["junk_left"]), int(st["bales_loose"]), int(st.get("bales_crew", 0)),
		(st["plants"] as Array).size(), planted, (st["robots"] as Array).size(), str(st["research"]), float(st["research_left"]), float(st["rocket_left"]), float(st["played"])])
	var thin: Array[String] = []
	if (st["robots"] as Array).is_empty():
		thin.append("no robots")
	if (st["plants"] as Array).is_empty():
		thin.append("no plants")
	if str(st["research"]) == "":
		thin.append("no research running")
	if float(st["rocket_left"]) <= 0.0:
		thin.append("rocket cells full")
	print("[clock] %s" % ("PASS save" if ok and f != null and thin.is_empty() else "FAIL save: %s" % ", ".join(thin)))
	tree.quit(0 if ok and f != null and thin.is_empty() else 1)


# --- load ---------------------------------------------------------------------------------------

func _compare() -> void:
	var want: Variant = JSON.parse_string(FileAccess.get_file_as_string(ClockCheck._snap_path())) if FileAccess.file_exists(ClockCheck._snap_path()) else null
	if not (want is Dictionary):
		diffs.append("no %s in the save folder" % SNAP)
		return
	_loaded = ClockCheck.state(so)
	var w: Dictionary = want
	for k: String in w:
		var a: Variant = w[k]
		var b: Variant = _loaded.get(k)
		var same: bool
		if a is float or a is int:
			var tol: float = 0.06 if k in ["research_left", "rocket_left", "played"] else 0.0011
			same = (b is float or b is int) and absf(float(a) - float(b)) <= tol
		else:
			same = JSON.stringify(a) == JSON.stringify(b)
		if not same:
			diffs.append("%s: saved %s, loaded %s" % [k, _short(a), _short(b)])
	# The old keys are gone from what the game holds now (an old save carried them).
	var text: String = JSON.stringify([GameState.stats, GameState.world, GameState.orbit.get("hub_worlds", {}), GameState.flags.get("rocket_ready_unix", "")])
	for key: String in ["welcome_backs", "offline_best_s", "offline_units", "\"junk_left\""]:
		if text.contains(key):
			diffs.append("old key %s still in the loaded state" % key)
	if GameState.flags.has("rocket_ready_unix"):
		diffs.append("old key rocket_ready_unix still in the loaded state")
	var gap: float = Time.get_unix_time_from_system() - GameState.saved_unix
	print("[clock] loaded a save stamped %s (%.1f h %s the system clock): cubes %s, parts %s, seeds %s, hexes %d, junk left %s, bales %d + %d, plants %d, robots %d, research %s %.1f s left, rocket %.1f s left, played %.1f s" % [
		Time.get_datetime_string_from_unix_time(int(GameState.saved_unix)), absf(gap) / 3600.0, "behind" if gap >= 0.0 else "AHEAD of",
		str(_loaded["cubes"]), str(_loaded["parts"]), str(_loaded["seeds"]), int(_loaded["hexes_clean"]), str(_loaded["junk_left"]), int(_loaded["bales_loose"]), int(_loaded.get("bales_crew", 0)),
		(_loaded["plants"] as Array).size(), (_loaded["robots"] as Array).size(), str(_loaded["research"]), float(_loaded["research_left"]), float(_loaded["rocket_left"]), float(_loaded["played"])])


static func _short(v: Variant) -> String:
	var s: String = JSON.stringify(v)
	return s if s.length() <= 160 else s.substr(0, 157) + "..."


func _run_load() -> void:
	var tree: SceneTree = get_tree()
	var t0: float = float(GameState.stats.get("time_played", 0.0))
	var left0: float = Research.remaining()
	while float(GameState.stats.get("time_played", 0.0)) - t0 < 8.0:
		await tree.create_timer(0.5).timeout
	if _loaded.is_empty() and diffs.is_empty():
		diffs.append("the world came up without restoring a save")
	for t: String in toasts:
		for b: String in BANNED:
			if t.to_lower().contains(b):
				diffs.append("message after loading: \"%s\"" % t)
	# The timers do run, on play time: 8 s of play took about 8 s off the research.
	var ran: float = left0 - Research.remaining()
	if Research.active_id() != "" and left0 > 20.0 and (ran < 6.0 or ran > 11.0):
		diffs.append("8 s of play took %.1f s off the research (the play clock should run it)" % ran)
	print("[clock] after 8 s of play: %d messages, none about being away: %s; research went on by %.1f s" % [toasts.size(), str(not diffs.any(func(d: String) -> bool: return d.begins_with("message"))), ran])
	for d: String in diffs:
		print("[clock] DIFF %s" % d)
	print("[clock] %s" % ("PASS the world is the saved one" if diffs.is_empty() else "FAIL (%d differences)" % diffs.size()))
	tree.quit(0 if diffs.is_empty() else 1)


# --- work watch ---------------------------------------------------------------------------------

func _work() -> Dictionary:
	var sm: SiteManager = so.globe.site_manager
	var crew: SphereCrew = so.crews.crew if so.crews != null else null
	var by_hub: Dictionary = {}  # site index -> [robots, junk units taken]
	var taken: float = 0.0
	if crew != null:
		for u: Dictionary in crew.units:
			var site: int = -1
			for i: int in so.globe.sites.size():
				if int((so.globe.sites[i] as Dictionary)["cell"]) == int(u["hub"]):
					site = i
			var rec: Array = by_hub.get(site, [0, 0.0])
			rec[0] = int(rec[0]) + 1
			rec[1] = float(rec[1]) + float((u["log"] as Dictionary).get("junk", 0.0))
			by_hub[site] = rec
			taken += float((u["log"] as Dictionary).get("junk", 0.0))
	var keep: int = so.sites.keepers.cleared if so.sites != null and so.sites.keepers != null else 0
	return {"lumi": sm.nearest if sm != null else -1, "cubes": GameState.get_currency("cubes").to_float(), "hexes": so.globe.field.cleaned_count,
		"taken": taken, "cashed": crew.cashed if crew != null else 0.0, "keep": keep, "by_hub": by_hub,
		"robot_bales": float(GameState.stats.get("robot_bales", 0.0))}


func _work_line(tag: String) -> void:
	var r: Dictionary = _work()
	var parts: Array[String] = []
	var hubs: Array = (r["by_hub"] as Dictionary).keys()
	hubs.sort()
	for h: int in hubs:
		var rec: Array = r["by_hub"][h]
		parts.append("base %d: %d robots took %.1f junk" % [h + 1, int(rec[0]), float(rec[1])])
	print("[work] %s t=%.0f s  Lumi at base %d  cubes %.1f  clean hexes %d  robots' bales %d sold for %.1f cubes  keepers cleaned %d hexes  %s" % [tag, float(GameState.stats.get("time_played", 0.0)),
		int(r["lumi"]) + 1, float(r["cubes"]), int(r["hexes"]), int(r["robot_bales"]), float(r["cashed"]), int(r["keep"]), "; ".join(parts)])


func _process(delta: float) -> void:
	if not DevHooks.has("work-watch") or so == null or so.globe == null or so.globe.site_manager == null:
		return
	var tree: SceneTree = get_tree()
	if tree.paused:
		return
	_watch_t += delta
	if _watch_t >= _watch_next:
		var every: float = DevHooks.get_f("work-watch", 30.0)
		_watch_next = _watch_t + (every if every > 1.0 else 30.0)  # a bare flag reads as 1
		_work_line("")
	if DevHooks.has("work-pause") and not _pause_done and _watch_t >= DevHooks.get_f("work-pause", 60.0):
		_pause_done = true
		_pause_test()


## Pausing the game pauses the robots: 5 real seconds paused, the numbers must not move.
func _pause_test() -> void:
	var tree: SceneTree = get_tree()
	var a: Dictionary = _work()
	var at: Dictionary = ClockCheck.state(so)
	_work_line("pause: before")
	tree.paused = true
	var until: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until:
		await tree.process_frame
	var b: Dictionary = _work()
	var bt: Dictionary = ClockCheck.state(so)
	tree.paused = false
	_work_line("pause: after 5 s paused")
	var same: bool = JSON.stringify(at) == JSON.stringify(bt) and float(a["taken"]) == float(b["taken"]) and float(a["cubes"]) == float(b["cubes"]) and int(a["keep"]) == int(b["keep"])
	print("[work] pause %s: junk taken %.2f -> %.2f, cubes %.1f -> %.1f, clean hexes %d -> %d, research left %.2f -> %.2f s, play clock %.2f -> %.2f s" % ["PASS" if same else "FAIL",
		float(a["taken"]), float(b["taken"]), float(a["cubes"]), float(b["cubes"]), int(a["hexes"]), int(b["hexes"]), float(at["research_left"]), float(bt["research_left"]), float(at["played"]), float(bt["played"])])
