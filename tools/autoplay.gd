class_name AutoplayBot
extends InputSource
## Playtest bot that plays like a sensible human through the first couple of hours:
##   - cleans one focus hex at a time (the nearest unfinished one), bales near the Perfect band,
##     sells bales (until Haul Bugs take over), digs up detector parts on the way;
##   - shops at the workbench: goal-unblocking upgrades first, then robots ([ui2] Parts + cubes;
##     Parts for the next base level are kept unless the robot can't wait), base levels, stations,
##     research, cheap upgrades;
##   - paints Command zones (cleaners to the frontier, planters/waterers to the garden hexes);
##   - picks up the seed tin, plants one hex at a time, waters by hand until Drips take over,
##     places Water Tanks, reads memory shards.
## Writes a timeline to screenshots/autoplay_report.json on exit (goal completions, hex level-ups,
## robots, research, base levels, gaps > 3 min with no goal and no new purchase). Run:
##   godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=950
## Research runs on wall-clock time in the real game; the bot drives Research.now_override from the
## game clock so a time-scaled run sees research at the same pace a player would.

const BENCH_POS := Vector3(-3.6, 0, 2.2)
const BENCH_STAND := Vector3(-1.4, 0, 2.2)
const WATER_STAND := Vector3(2.0, 0, 3.0)
const AT_BASE_R: float = 7.5
const GAP_S: float = 180.0
const SNAPSHOT_S: float = 60.0
## Research order a planner would follow: unlock the planting/watering robots first.
const RESEARCH_PRIORITY: Array[String] = ["salvage_logic", "soil_survey", "water_testing", "field_notebook", "scoop_beam",
	"hardy_weeds", "seedling_blueprint", "big_tanks", "drip_blueprint", "wild_mint", "pollinator_survey", "conveyor", "wide_beam",
	"auto_baler", "recycler", "bigger_hopper", "auto_sort", "haul_routes", "spray_heads", "bale_tuning", "multibot_blueprint",
	"rocket_cargo", "silt_filters", "pump_lines", "irrigation", "dune_charts", "field_magnet", "tractor_beam", "dew_condensers",
	"thermal_lance", "pump_works", "ark_beacon", "hedgerows", "evergreens", "dune_fences", "cold_hardy_seeds", "heat_pumps"]
## [beat] From here on the bot saves Data for the next priority node instead of spending it on side nodes.
const RESEARCH_SAVE_FROM: String = "rocket_cargo"

var world: Node
var _move := Vector3.ZERO
var _scoop: bool = false
var _cube: bool = false
var _interact: bool = false
var _dt: float = 0.0
var _cooldown: float = 0.0
var _stuck_timer: float = 0.0
var _escape_side: float = 1.0  # [pace2]
var _trap_pos: Vector3 = Vector3.INF
var _trap_t: float = 0.0
var _traps: int = 0
var _last_pos := Vector3.ZERO
var _report: Dictionary = {}
var _log: Array = []
var _timeline: Array = []
var _log_timer: float = 0.0
var _pct_quit: bool = false  # [orbC] --quit-at-pct fired
var _ignore_piece: Dictionary = {}
var _skip_hex: Dictionary = {}
var _target_piece: int = -1
var _focus_hex: int = -1
var _plant_hex: int = -1
var _task: String = ""
var _task_t: float = 0.0
var _mgmt_t: float = 0.0
var _bench_trip: bool = false
var _last_bench_t: float = -999.0
var _refilling: bool = false
var _goals_hooked: bool = false
var _hub_level_seen: int = 1
var _goal_times: Array[float] = []
var _progress_times: Array[float] = []
var _research_idle_s: float = 0.0
var _research_idle_run: float = 0.0
var _research_idle_max: float = 0.0
var _research_starved_s: float = 0.0
var _parts_bought: int = 0
var _water_target: int = -1
var _dig_target: int = -1
var _stall_check_t: float = 0.0
var _escape_t: float = 0.0
var _escape_dir := Vector3.ZERO
var _watch_pos := Vector3.ZERO
var _watch_t: float = 0.0
var _escapes: int = 0
var _bench_fails: int = 0
var _remote_shops: int = 0
var _skip_shard: Dictionary = {}
var _shard_t: Dictionary = {}
var _stopping: bool = false
var _start_t: float = 0.0


func _init(p_world: Node) -> void:
	world = p_world
	var pw := PauseWatch.new()  # [qafix] a paused tree never stalls the bot (tools/pause_watch.gd)
	pw.world = p_world
	p_world.add_child.call_deferred(pw)
	_start_t = float(GameState.stats.get("time_played", 0.0))
	Research.now_override = 1000.0
	_hook(EventBus.cube_made, func(_i: Dictionary) -> void: _mark("first_cube_s"))
	_hook(EventBus.cube_cashed, func(_v: BigNum, _p: Vector3) -> void:
		_mark("first_cashin_s")
		_pace_cashed())  # [pace]
	_hook(EventBus.upgrade_bought, func(id: String, lv: int) -> void:
		_mark("first_upgrade_s")
		_pace_bought(id, lv)  # [pace]
		_progress()
		_log.append({"t": _now(), "event": "upgrade", "id": id, "level": lv}))
	_hook(EventBus.hex_cleaned, func(h: int, _p: Vector3, _b: BigNum) -> void:
		_mark("first_hex_s")
		_event("hex_clean", {"hex": h, "n": world.field.cleaned_count}))
	_hook(EventBus.hex_level_changed, func(h: int, lv: int) -> void:
		_mark("first_hexlv_%d_s" % lv)
		_event("hex_level", {"hex": h, "level": lv}))
	_hook(EventBus.robot_built, func(n: String) -> void:
		_mark("first_robot_s")
		_progress()
		var r: Robot = world.fleet.find_robot(n) if world.fleet else null
		var tid: String = r.type_id if r else "?"
		if r == null and world.fleet is SphereFleet:  # [v3qa] globe crews: the unit by name
			for u: Dictionary in (world.fleet as SphereFleet).crew.robots():
				if str(u["name"]) == n:
					tid = str(u["type"])
		_mark("first_%s_s" % tid)
		_event("robot", {"type": tid, "name": n, "fleet": world.fleet.robot_total() if world.fleet else 0}))
	_hook(EventBus.research_completed, func(id: String) -> void:
		_mark("first_research_s")
		_event("research", {"id": id}))
	_hook(EventBus.part_found, func(t: int, r: int) -> void: _event("part", {"type": t, "rarity": r, "parts": snappedf(GameState.get_currency("parts").to_float(), 1.0)}))
	world.tree_exiting.connect(write_report)
	world.tree_exiting.connect(_unhook)  # [beat] rocket travel reloads the scene: drop the old bot's hooks


var _hooks: Array = []


func _hook(sig: Signal, f: Callable) -> void:
	sig.connect(f)
	_hooks.append([sig, f])


func _unhook() -> void:
	for h: Array in _hooks:
		if (h[0] as Signal).is_connected(h[1]):
			(h[0] as Signal).disconnect(h[1])
	_hooks.clear()


func _now() -> float:
	return snappedf(float(GameState.stats.get("time_played", 0.0)), 0.1)


func _mark(key: String) -> void:
	if not _report.has(key):
		_report[key] = _now()
		print("[Autoplay] %s at %.1fs" % [key, _report[key]])
		AutoplayCampaign.mark(key, _now())
		if DevHooks.get_s("stop-at", "") == key:
			_stop_run("stop-at " + key)


## Ends a staged run: save (with --save-dir), write the report, quit.
func _stop_run(why: String) -> void:
	print("[Autoplay] stopping: %s at %.1f min" % [why, _now() / 60.0])
	SaveManager.save_game()
	write_report()
	world.get_tree().quit()


func _event(kind: String, data: Dictionary = {}) -> void:
	var e: Dictionary = {"t": _now(), "kind": kind}
	e.merge(data)
	_timeline.append(e)
	if kind != "part":
		print("[Autoplay] %6.1f min  %s %s" % [_now() / 60.0, kind, JSON.stringify(data)])


func _progress() -> void:
	_progress_times.append(_now())


func get_world_move(_cam_yaw: float) -> Vector3:
	return _move


func scoop_held() -> bool:
	return _scoop


func cube_pressed() -> bool:
	var c: bool = _cube
	_cube = false
	return c


func interact_pressed() -> bool:
	var i: bool = _interact
	_interact = false
	return i


# --- Movement --------------------------------------------------------------------------

var _detour_t: float = 0.0
var _detour := Vector3.ZERO
var _progress_pos := Vector3.ZERO
var _progress_t: float = 0.0


## [orbB] On the globe moves are world vectors along the ground (Patch projects them on local up).
var world_space: bool = false
var _play_area := PackedInt32Array()


## [orbB] The hexes the bot plays: the whole field on the flat game; on the globe (164k+ cells) the
## start hub's region, the cells that count for planet % (SiteManager.REGION_RINGS rings).
func _hexes() -> Variant:
	var f: HexField = world.field
	if not (f is SphereField):
		return f.hex_count()
	if _play_area.is_empty():
		var sf: SphereField = f
		var so: Variant = world.get("orbit")
		var hub: int = (so as SliceOrbit).globe.start_cell() if so else sf.grid.cell_at(world.patch.global_position)
		_play_area = sf.grid.cells_around(hub, SiteManager.REGION_RINGS)
	return _play_area


func _go(p: Patch, target: Vector3, stop_dist: float = 0.3) -> float:
	var orb: Variant = world.get("orbit")  # [orbD] on a globe hub site: round its buildings along the streets
	if orb is SliceOrbit and (orb as SliceOrbit).globe.site_manager:
		var via: Vector3 = (orb as SliceOrbit).globe.site_manager.detour(p.global_position, target)
		if via.distance_to(target) > 0.5:
			_go_raw(p, via, 1.0)
			return maxf(target.distance_to(p.global_position), stop_dist + 1.0)
	return _go_raw(p, target, stop_dist)


func _go_raw(p: Patch, target: Vector3, stop_dist: float = 0.3) -> float:
	var d: Vector3 = target - p.global_position
	if JunkCube.planet_radius > 0.0:  # [orbB] round planet: drop the local-up part
		var u: Vector3 = p.global_position.normalized()
		d -= u * d.dot(u)
	else:
		d.y = 0.0
	var dist: float = d.length()
	_move = d.normalized() * clampf(dist / 1.5, 0.35, 1.0) if dist > stop_dist else Vector3.ZERO
	# Obstacle unstick: no progress for a while -> sidestep around it.
	if _detour_t > 0.0:
		_move = (_detour + d.normalized() * 0.3).normalized()
	elif dist > stop_dist + 0.5:
		if p.global_position.distance_to(_progress_pos) > 0.5:
			_progress_pos = p.global_position
			_progress_t = 0.0
		elif _progress_t > 1.2:
			var side := (Vector3(d.z, 0, -d.x) if JunkCube.planet_radius <= 0.0 else d.cross(p.global_position.normalized())).normalized() * (1.0 if randf() < 0.5 else -1.0)  # [orbB]
			_detour = side
			_detour_t = 1.4
			_progress_t = 0.0
	return dist


func _set_task(t: String) -> void:
	if t != _task:
		_task = t
		_task_t = 0.0


# --- Main loop -------------------------------------------------------------------------

func update(delta: float) -> void:
	var p: Patch = world.patch
	if p == null:
		return
	_dt = delta
	Research.now_override = 1000.0 + float(GameState.stats.get("time_played", 0.0))
	RocketTiers.now_override = 1000.0 + float(GameState.stats.get("time_played", 0.0))  # [beat]
	if DevHooks.has("game-minutes") and _now() >= DevHooks.get_f("game-minutes", 60.0) * 60.0 and not _stopping:
		_stopping = true
		_stop_run("game-minutes")
		return
	_hook_goals()
	if DevHooks.has("probe") and not _report.has("probed"):
		_report["probed"] = true
		for h: int in _hexes():
			print("[probe] hex %d hub=%d water=%d pieces=%d vol=%.0f slots=%d dist=%.0f" % [h, world.field.hex_hub[h], int(world.field.is_water(h)), world.field.hex_pieces[h].size(), world.field.hex_total[h], (world.garden.hex_slots.get(h, PackedInt32Array()) as PackedInt32Array).size(), world.field.hex_center(h).length()])
		print("[probe] parts buried=%d" % world.field.part_pos.size())
	_cooldown -= delta
	_detour_t -= delta
	_progress_t += delta
	_task_t += delta
	_scoop = false
	_move = Vector3.ZERO
	_log_timer += delta
	_mgmt_t += delta
	if _log_timer >= SNAPSHOT_S:
		_log_timer = 0.0
		_snapshot()
	if _mgmt_t >= 1.0:
		_track_research(_mgmt_t)
		_mgmt_t = 0.0
		_manage(p)
	if world.first_seed and world.first_seed.get("_active"):
		return  # the seed-tin cinematic
	if p._cubing > 0.0 or p.detector.digging > 0.0:
		return
	if _escape_t > 0.0:
		_escape_t -= delta
		_move = _escape_dir
		return
	if not (_do_tin(p) or _do_bench(p) or _do_shard(p) or _do_dump(p) or _do_deliver(p) or _do_pickup(p) or _do_dig(p) or _do_pet(p) or _do_garden(p)):
		_do_clean(p)
	_watch_stuck(p, delta)


## Wedged against something for a long time while trying to move: back off in a random direction.
func _watch_stuck(p: Patch, delta: float) -> void:
	# [pace2] Last resort: boxed in for 90 s (heaps or props all round): hop back to the yard, as a
	# player would call for help, and log the spot so the world can be checked for traps.
	if _move.length() >= 0.2:
		if p.global_position.distance_to(_trap_pos) > 2.5:
			_trap_pos = p.global_position
			_trap_t = 0.0
		else:
			_trap_t += delta
			if _trap_t > 90.0:
				_trap_t = 0.0
				_traps += 1
				_report["bot_traps"] = _report.get("bot_traps", []) + [[snappedf(_now() / 60.0, 0.1), str(p.global_position.snapped(Vector3.ONE * 0.1)), _task]]
				print("[bot-trap] t=%.1f task=%s pos=%s: back to the yard" % [_now() / 60.0, _task, str(p.global_position)])
				if world.get("orbit") != null and p.has_method("place_on_sphere"):  # [v1guide] the globe's yard
					p.place_on_sphere(_bench_at() + _bench_at().normalized() * 0.3, p.forward())
				else:
					p.global_position = BENCH_STAND + Vector3(0, 0.3, 1.5)
				p.velocity = Vector3.ZERO
				_target_piece = -1
				_set_task("")
				return
	if _move.length() < 0.2:
		_watch_t = 0.0
		_watch_pos = p.global_position
		return
	_watch_t += delta
	if p.global_position.distance_to(_watch_pos) > 1.0:
		_watch_t = 0.0
		_watch_pos = p.global_position
	elif _watch_t > 6.0:
		_watch_t = 0.0
		_escapes += 1
		if _target_piece >= 0 and DevHooks.has("bot-debug"):
			var f: HexField = world.field
			print("[bot-esc] t=%.1f task=%s pos=%s piece=%d at %s size=%d embed=%.2f" % [_now() / 60.0, _task, str(p.global_position), _target_piece, str(f.piece_pos[_target_piece]), Pace.piece_size(f, _target_piece), f.piece_embed[_target_piece] if _target_piece < f.piece_embed.size() else -1.0])
		# [pace2] Sidestep around the obstacle (perpendicular to where we were heading, alternating
		# sides, a little backwards) instead of a random direction that often points back into it.
		var head: Vector3 = Vector3(_move.x, 0, _move.z).normalized()
		_escape_side = -_escape_side
		_escape_dir = (Vector3(head.z, 0, -head.x) * _escape_side - head * 0.35).normalized()
		_escape_t = 1.6 + 0.4 * float(_escapes % 3)
		if _target_piece >= 0 and _escapes % 2 == 0:
			_ignore_piece[_target_piece] = true
		_target_piece = -1


func _hook_goals() -> void:
	if _goals_hooked or world.get("goals") == null:
		return
	_goals_hooked = true
	(world.goals as Goals).completed.connect(func(i: int) -> void:
		var g: Dictionary = world.goals.chain[i]
		_goal_times.append(_now())
		_progress()
		_event("goal", {"id": str(g["id"]), "n": world.goals.done_count()}))


func _haulers() -> int:
	return world.fleet.count("haulbug") if world.fleet else 0


func _at_base(p: Patch) -> bool:
	return p.global_position.distance_to(_bench_at()) < AT_BASE_R


## [v1guide] The workbench: the flat BENCH_POS, or the globe's bench anchor (the bot used to walk to
## the flat spot on the globe for 60 s and then shop "remotely", which slowed every globe run).
func _bench_at() -> Vector3:
	return world.call("bench_pos") if world.get("orbit") != null and world.has_method("bench_pos") else BENCH_POS


# --- Patch tasks -------------------------------------------------------------------------

## The Maker seed tin in the greenhouse, once enough hexes are clean.
func _do_tin(p: Patch) -> bool:
	var fs: FirstSeed = world.first_seed
	if fs == null or not fs.ready_to_find() or fs._tin == null or not fs._tin.visible:
		return false
	if not p.carried.is_empty():
		return false  # deliver first (interact would drop the bale)
	_set_task("tin")
	var tin: Vector3 = fs._tin.global_position
	var stand: Vector3 = tin + Vector3(1.3, 0, 0)
	_go(p, stand, 0.25)
	if fs.near_tin(p.global_position) and _cooldown <= 0.0:
		_interact = true
		_cooldown = 1.0
	return true


func _do_bench(p: Patch) -> bool:
	if not _bench_trip:
		return false
	if p.global_position.distance_to(_bench_at()) < 3.0:  # [v1guide]
		_bench_trip = false
		var cp: Camp = Camp.of(world)  # [camp] fix the broken bench first (the player presses E once)
		if cp and not Camp.bench_ok():
			cp.repair_now()
		_manage(p)
		return false
	_set_task("bench")
	if world.get("orbit") != null:  # [v1guide] the globe's bench: walk up to it
		_go(p, _bench_at(), 2.2)
	else:
		_go(p, BENCH_STAND, 0.4)
	if _task_t > 60.0:
		# Can't get there: count it, and shop anyway (the sim must not stall on pathing).
		_bench_trip = false
		_bench_fails += 1
		_remote_shops += 1
		_last_bench_t = _now()
		_shop(_shopping_list())
	return true


func _do_shard(p: Patch) -> bool:
	var sh: ShardSystem = world.shards
	if sh == null or sh._visible.is_empty() or not p.carried.is_empty():
		return false
	var best: Node3D = null
	var best_d: float = 30.0
	for hid: int in sh._visible:
		var n: Node3D = sh._visible[hid]
		if _skip_shard.has(n):
			continue
		var d: float = n.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		return false
	if _skip_shard.has(best):
		return false
	_shard_t[best] = float(_shard_t.get(best, 0.0)) + _dt
	if float(_shard_t[best]) > 40.0:
		_skip_shard[best] = true  # can't reach it: a person would give up on it
		return false
	_set_task("shard")
	_go(p, best.global_position, 0.6)
	if sh.nearby(p.global_position) >= 0 and _cooldown <= 0.0 and p.nearest_loose_cube() == null:
		_interact = true
		_cooldown = 1.0
		# The document pauses the tree; a human reads it and closes it.
		world.get_tree().create_timer(0.8, true).timeout.connect(func() -> void:
			if world.doc_view and world.doc_view.is_open:
				world.doc_view.close_doc())
	return true


var _pet_t: float = 0.0


## [wild] Pet a stray cat once (the "Pet a stray cat" goal), like a person would when one is near.
func _do_pet(p: Patch) -> bool:
	if float(GameState.stats.get("cats_petted", 0.0)) >= 1.0 or _pet_t > 30.0 or not p.carried.is_empty():
		return false
	var fa: Fauna = world.get("fauna") as Fauna
	if fa == null:
		return false
	var best: Fauna.Animal = null
	for a: Fauna.Animal in fa.animals:
		if a.kind == "cat" and a.state != Fauna.St.LEAVE and a.pos.distance_to(p.global_position) < 15.0:
			if best == null or a.pos.distance_to(p.global_position) < best.pos.distance_to(p.global_position):
				best = a
	if best == null:
		return false
	_pet_t += _dt
	_set_task("pet")
	_go(p, best.pos, 1.0)
	if best.pos.distance_to(p.global_position) < 1.6 and _cooldown <= 0.0 and p.nearest_loose_cube() == null:
		_interact = true
		_cooldown = 1.0
	return true


func _do_deliver(p: Patch) -> bool:
	if p.carried.is_empty():
		return false
	var full: bool = p.carried.size() >= p.carry_cap()
	if _haulers() > 0:
		# Haul Bugs take bales; set the stack down and get back to work.
		_drop_all(p)
		return false
	if not full and _nearest_loose(p) != null:
		return false
	_set_task("deliver")
	_go(p, world.depot.global_position, 0.6)
	return true


## [pace] Before the Baler: roll to the trash bin (or the scale pad) when the chest is full, or
## when there is nothing left to scoop.
func _do_dump(p: Patch) -> bool:
	if not Pace.dump_allowed() or p.compartment.is_empty() or not p.carried.is_empty():
		return false
	var full: bool = p.compartment.ratio(p.capacity()) >= 0.85
	if not full and not (_task == "idle" or _task == "dump"):
		return false
	_set_task("dump")
	var bin: Node3D = Pace.trash_bin(p.get_tree(), world.depot.global_position)
	_go(p, bin.global_position if bin else world.depot.global_position, 0.6)
	if _task_t > 60.0:
		_set_task("")
		return false
	return true


var _pace_cash_n: int = 0


func _pace_cashed() -> void:
	_pace_cash_n += 1
	if _pace_cash_n == 2:
		_report["pace_upgrades_at_2nd_bale"] = int(GameState.stats.get("upgrades_bought", 0))
		_report["pace_affordable_at_2nd_bale"] = _pace_affordable()
		_report["pace_cubes_at_2nd_bale"] = GameState.get_currency("cubes").to_float()


## Distinct upgrades the purse could buy one level of right now.
func _pace_affordable() -> int:
	var n: int = 0
	for id: String in Economy.upgrade_order:
		if Economy.upgrade_defs[id].get("tab", "") == "patch" and Economy.is_unlocked(id) and not Economy.is_maxed(id) and GameState.can_afford("cubes", Economy.upgrade_cost(id)):
			n += 1
	return n


func _pace_bought(id: String, lv: int) -> void:
	match id:
		Pace.UP_BALER:
			_mark("baler_s")
		Pace.UP_LIFT:
			_mark("lift_%d_s" % lv)
			_skip_hex.clear()  # heavy pieces are fair game now
			_ignore_piece.clear()
		"signal_finder":
			_mark("signal_finder_s")
		"auto_compactor":
			_mark("auto_compactor_s")


## The next slow-start unlock worth buying now ("" = none): the Baler first, then Lift Strength.
func _pace_upgrade() -> String:
	for id: String in [Pace.UP_BALER, Pace.UP_LIFT]:
		if Economy.upgrade_defs.has(id) and Economy.is_unlocked(id) and not Economy.is_maxed(id):
			if GameState.can_afford("cubes", Economy.upgrade_cost(id)):
				return id
			if id == Pace.UP_BALER:
				return ""  # save for the Baler
	return ""


## [pace] The helper / automation research a planner works toward once the base allows it.
func _pace_research_next() -> String:
	for id: String in ["salvage_logic", "conveyor", "auto_baler"]:
		if not Research.exists(id) or Research.has(id) or Research.is_active(id) or Research.is_queued(id):
			continue
		if Research.status(id) != "available":
			return ""
		var mb: int = int(Research.def(id).get("min_base_level", 0))
		if int(GameState.world.get("hub_level", 1)) < mb:
			return ""
		return id
	# [pace2] Once base 3 is up, the garden chain (Pollinator Survey = the garden taking off).
	if int(GameState.world.get("hub_level", 1)) >= 3:
		for id: String in PACE_GARDEN_CHAIN:
			if not Research.exists(id) or Research.has(id) or Research.is_active(id) or Research.is_queued(id):
				continue
			return id if Research.status(id) == "available" else ""
	return ""


const PACE_GARDEN_CHAIN: Array[String] = ["soil_survey", "hardy_weeds", "wild_mint", "pollinator_survey"]


func _drop_all(p: Patch) -> void:
	var guard: int = 0
	while not p.carried.is_empty() and guard < 12:
		p.place_top_cube()
		guard += 1


func _do_pickup(p: Patch) -> bool:
	if _haulers() > 0 or p.carried.size() >= p.carry_cap():
		return false
	var loose: JunkCube = _nearest_loose(p)
	if loose == null:
		return false
	_set_task("pickup")
	var dist: float = _go(p, loose.global_position, 0.9)
	if dist < 1.5 and _cooldown <= 0.0:
		_interact = true
		_cooldown = 0.4
	return true


## Buried parts: dig the ones the detector finds close by (a person follows the beeping).
func _do_dig(p: Patch) -> bool:
	if not p.carried.is_empty():
		return false
	var det: PartDetector = p.detector
	if _dig_target >= 0 and world.field.part_found[_dig_target] == 1:
		_dig_target = -1
	if _dig_target < 0:
		if det.target < 0 or _skip_hex.has(-100 - det.target):
			return false
		var pp: Vector3 = world.field.part_pos[det.target]
		if (Vector2(pp.x - p.global_position.x, pp.z - p.global_position.z).length() if JunkCube.planet_radius <= 0.0 else pp.distance_to(p.global_position)) > 14.0:  # [orbB]
			return false
		_dig_target = det.target
	_set_task("dig")
	if _task_t > 40.0:
		_skip_hex[-100 - _dig_target] = true  # can't reach it; forget it
		_dig_target = -1
		_set_task("")
		return false
	_go(p, world.field.part_pos[_dig_target], 0.5)
	if det.can_dig() and _cooldown <= 0.0 and p.nearest_loose_cube() == null:
		_interact = true
		_cooldown = 0.6
	return true


# --- Garden --------------------------------------------------------------------------

func _land(h: int) -> bool:
	return world.field.hex_hub[h] == 0 and not world.field.is_water(h)


func _hex_planted(g: Garden, h: int) -> Vector2i:
	var planted: int = 0
	var ids: PackedInt32Array = g.hex_slots.get(h, PackedInt32Array())
	var total: int = 0
	for s: int in ids:
		if g.slot_species[s] >= 0:
			planted += 1
			total += 1
		elif g.plantable(s):
			total += 1  # [beat] frontier rules (cold, flood): only slots that can take a seed
	return Vector2i(planted, total)


## The hex to plant: keep filling the one already started, else the clean hex nearest the base.
func _pick_plant_hex(g: Garden) -> int:
	if _plant_hex >= 0:
		var pc0: Vector2i = _hex_planted(g, _plant_hex)
		if pc0.x < pc0.y:
			return _plant_hex
	var best: int = -1
	var best_s: float = INF
	var pad: Array[int] = AutoplayCampaign.pad_hexes(world)
	for h: int in _hexes():
		if not _land(h) or not world.field.is_clean(h):
			continue
		var pc: Vector2i = _hex_planted(g, h)
		if pc.y == 0 or pc.x >= pc.y:
			continue
		var s: float = world.field.hex_center(h).length() - (100.0 if pc.x > 0 else 0.0) - (500.0 if h in pad else 0.0)
		if s < best_s:
			best_s = s
			best = h
	_plant_hex = best
	return best


func _drips() -> int:
	if world.fleet == null:
		return 0
	var n: int = world.fleet.count("drip")
	for r: Robot in world.fleet.robots():
		if r.type_id == "multibot" and r.job == "water":
			n += 1
	return n


## Thirstiest planted slot Patch should water (none once Drips cover the garden).
func _thirsty_slot(g: Garden, p: Patch) -> int:
	var drips: int = _drips()
	var best: int = -1
	var best_score: float = INF
	var dry: int = 0
	var planted: int = 0
	var limit: float = 25.0 if drips == 0 else 0.0
	for s: int in g.slot_species.size():
		if g.slot_species[s] < 0:
			continue
		planted += 1
		var w: float = g.slot_water[s]
		if w <= 0.0:
			dry += 1
		if w > limit:
			continue
		var sc: float = w * 2.0 + g.slot_pos[s].distance_to(p.global_position)
		if sc < best_score:
			best_score = sc
			best = s
	@warning_ignore("integer_division")
	if drips > 0 and (_pick_focus(p) >= 0 or dry < maxi(4, planted / 5)):
		return -1  # the Drips have it in hand (Patch keeps cleaning while there is junk)
	return best


func _do_garden(p: Patch) -> bool:
	var g: Garden = world.garden
	if g == null or not g.unlocked():
		return false
	var cap: float = p.water_cap()
	# Refill the can at the base barrel (anywhere in the hub hex).
	if _refilling:
		if p.water >= cap - 0.5:
			_refilling = false
		else:
			_set_task("refill")
			_go(p, WATER_STAND, 0.5)
			return true
	if _water_target >= 0 and (g.slot_species[_water_target] < 0 or g.slot_water[_water_target] > 50.0):
		_water_target = -1
	if _water_target < 0:
		_water_target = _thirsty_slot(g, p)
	if _water_target >= 0:
		if p.water < 1.5:
			_refilling = true
			return true
		_set_task("water")
		p.set_tool(Patch.Tool.WATER)
		var d: float = _go(p, g.slot_pos[_water_target], 1.0)
		if d < 1.8:
			_scoop = true
			_move = Vector3.ZERO
		if _task_t > 30.0:
			_water_target = -1
			_task_t = 0.0
		return true
	if GameState.get_currency("seeds").to_float() >= 1.0:
		var h: int = _pick_plant_hex(g)
		if h >= 0:
			var best: int = -1
			var best_d: float = INF
			for s: int in g.hex_slots[h]:
				if g.slot_species[s] >= 0 or _ignore_piece.has(-10 - s) or not g.plantable(s):
					continue
				var d2: float = g.slot_pos[s].distance_to(p.global_position)
				if d2 < best_d:
					best_d = d2
					best = s
			if best >= 0:
				_set_task("plant")
				p.set_tool(Patch.Tool.PLANT)
				var dd: float = _go(p, g.slot_pos[best], 0.9)
				if dd < 1.6:
					_scoop = true
					_move = Vector3.ZERO
				if _task_t > 15.0:
					_ignore_piece[-10 - best] = true
					_task_t = 0.0
				return true
	return false


# --- Cleaning --------------------------------------------------------------------------

## The unfinished hex to work: keep the current one until it flips; else the started or nearest one.
func _pick_focus(p: Patch) -> int:
	var f: HexField = world.field
	if _focus_hex >= 0 and not f.is_clean(_focus_hex) and not _skip_hex.has(_focus_hex):
		return _focus_hex
	var best: int = -1
	var best_s: float = INF
	for h: int in _hexes():
		if not _land(h) or f.is_clean(h) or _skip_hex.has(h) or f.locked.has(h):
			continue
		var c: Vector3 = f.hex_center(h)
		var s: float = c.length() + 0.6 * c.distance_to(p.global_position) - 25.0 * f.removed_fraction(h)
		if s < best_s:
			best_s = s
			best = h
	if best < 0 and not _skip_hex.is_empty():
		for k: Variant in _skip_hex.keys():
			if int(k) >= 0:
				_skip_hex.erase(k)
	_focus_hex = best
	return best


func _do_clean(p: Patch) -> void:
	if p.tool != Patch.Tool.SCOOP:
		p.set_tool(Patch.Tool.SCOOP)
	var cap: float = p.capacity()
	if p.compartment.ratio(cap) >= 0.9 and p.compartment.pending <= 0.0:
		_cube = Pace.baler_unlocked()  # [pace] no Baler: _do_dump empties the chest at the bin
		return
	if Pace.press_ready(p, world.field):  # [orbC] nothing near fits: press now, don't wait under 90% forever
		_cube = true
		return
	if p.compartment.fill + p.compartment.pending >= cap * 0.9:
		return  # wait for in-flight pieces to land
	var field: HexField = world.field
	var h: int = _pick_focus(p)
	if h < 0 and _thaw_ice(p):
		return
	if h < 0:
		_set_task("idle")
		if not p.compartment.is_empty() and Pace.baler_unlocked():  # [pace]
			_cube = true
		elif p.global_position.distance_to(WATER_STAND) > 4.0:
			_go(p, WATER_STAND, 1.0)
		return
	_set_task("clean")
	if _target_piece < 0 or field.piece_alive[_target_piece] == 0 or field.piece_hex[_target_piece] != h:
		_target_piece = _nearest_piece_in(p, h)
		_stall_check_t = 0.0
	if _target_piece < 0:
		_skip_hex[h] = true
		_focus_hex = -1
		return
	var tp: Vector3 = field.piece_pos[_target_piece]
	var dist2: float = _go(p, tp, 0.8)
	if dist2 < p.stat("scoop_reach") + 0.5:
		_scoop = true
		_move *= 0.6
	# Unstick: if not moving for a while, give up on this piece.
	if p.global_position.distance_to(_last_pos) < 0.02 and dist2 > 1.2:
		_stuck_timer += _dt
		if _stuck_timer > 1.5:
			_ignore_piece[_target_piece] = true
			_target_piece = -1
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	# The same piece for a long time without it disappearing: skip it.
	_stall_check_t += _dt
	if _stall_check_t > 15.0 and _target_piece >= 0:
		_ignore_piece[_target_piece] = true
		_target_piece = -1
		_stall_check_t = 0.0
	_last_pos = p.global_position


## [beat] Frozen Port: nothing loose left to clean, so stand at the nearest iced hex and hold the
## beam on it (it thaws; heaters do the rest).
func _thaw_ice(p: Patch) -> bool:
	var f: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for h: Variant in f.locked:
		var d: float = f.hex_center(int(h)).distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = int(h)
	if best < 0:
		return false
	_set_task("thaw")
	var c: Vector3 = f.hex_center(best)
	var to_c: Vector3 = c - p.global_position
	to_c.y = 0.0
	if to_c.length() > f.hex_size * 0.6:
		_go(p, c, f.hex_size * 0.5)
	else:
		_move = to_c.normalized() * 0.05
	_scoop = true
	return true


func _nearest_piece_in(p: Patch, h: int) -> int:
	var field: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for pid: int in field.hex_pieces[h]:
		if field.piece_alive[pid] == 0 or _ignore_piece.has(pid) or not Pace.can_lift(field, pid):  # [pace] Lift Strength
			continue
		var d: float = field.piece_pos[pid].distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = pid
	return best


func _nearest_loose(p: Patch) -> JunkCube:
	var best: JunkCube = null
	var best_d: float = 14.0
	for n: Node in p.get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed or Stations.on_feeder(c):
			continue
		if world.depot.pad_contains(c.global_position):
			continue
		var d: float = c.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


# --- Management (the workbench, Command view, research) ----------------------------------

func _manage(p: Patch) -> void:
	_paint_zones()
	_campaign(p)
	if world.get("hub") != null and int(world.hub.level) != _hub_level_seen:
		_hub_level_seen = int(world.hub.level)
		_mark("base_%d_s" % _hub_level_seen)
		_progress()
		_event("base", {"level": _hub_level_seen})
	var want: Dictionary = _shopping_list()
	if not _at_base(p):
		# Head back when something worth the walk is affordable.
		if want.get("trip", false) and _now() - _last_bench_t > 20.0:
			_bench_trip = true
		return
	_last_bench_t = _now()
	_shop(want)


## [beat] The whole-game layer: frontier chores and rocket trips (tools/autoplay_campaign.gd).
func _campaign(_p: Patch) -> void:
	if bool(world.get("launching")):
		return
	var chore: String = AutoplayCampaign.frontier_chores(world)
	if chore != "":
		_progress()
		_event("frontier", {"what": chore})
	var kid: String = AutoplayCampaign.frontier_kid(world)
	if kid != "":
		_mark("arrive_%s_s" % kid)
		var fr: FrontierDistrict = world.get("frontier")
		if fr and fr.growing_frac >= 0.5:
			_mark("%s_growing50_s" % kid)
		if int(world.hub.level) >= 5:
			_mark("%s_base5_s" % kid)
	for b: Variant in CoreCharge.beats_done():
		_mark("core_%d_s" % int(b))
	if GameState.flags.get("seeds_unlocked", false):
		_mark("seed_tin_s")
	if Research.has("pollinator_survey"):
		_mark("garden_takes_off_s")
	if GameState.flags.get("cradle_returned", false):
		_mark("cradle_complete_s")
	if GameState.flags.get("bloom_finale_seen", false):
		_mark("finale_done_s")
	if int(GameState.stats.get("ark_waves", 0)) > 0:
		_mark("ark_wave_1_s")
	var home: String = AutoplayHome.step(world)  # [home] the system campaign: planets, Homeward rocket, the ending
	if home != "":
		if home != "wait" and home != "ending":
			_event("home", {"what": home})
		return
	if not Homeward.done() and Homeward.current_planet() > 0 and DevHooks.has("home-ff"):
		return  # [home] fast-forwarded planets: no district hops
	var late: String = AutoplayLate.step(world)  # [late] post-game: decorate, Heirlooms, seed a new world
	if late != "":
		_event("late", {"what": late})
		if late == "seed new world":
			return
	if _now() < 30.0 or DevHooks.has("no-travel"):
		return  # settle in after landing
	var to: int = AutoplayCampaign.next_hub(world)
	if to >= 0 and world.rocket_status() == "" and p_ok(_p):
		_event("launch", {"from": int(world.hub_index), "to": to, "kind": world.planet.frontier_kind(to)})
		AutoplayCampaign.mark("launch_%d_s" % GameState.districts.size(), _now())
		world._launch(to)


## Not carrying, not pressing a bale: a calm moment to board.
func p_ok(p: Patch) -> bool:
	return p.carried.is_empty() and p._cubing <= 0.0


## What a player would want to do at the bench right now. trip = worth walking back for.
func _shopping_list() -> Dictionary:
	var out: Dictionary = {"trip": false, "reserve": 0.0}
	var cubes: float = GameState.get_currency("cubes").to_float()
	var robot: String = _next_robot()
	out["robot"] = robot
	if robot != "":
		var cost: float = world.fleet.build_cost(robot).to_float()
		out["robot_cost"] = cost
		out["reserve"] = cost
		if cubes >= cost and GameState.can_afford("parts", world.fleet.build_parts(robot)):  # [ui2]
			out["trip"] = true
	var hub: Hub = world.hub
	var nxt: Dictionary = hub.level_def(hub.level + 1)
	if not nxt.is_empty():
		var c: Dictionary = nxt.get("cost", {})
		var mats_ok: bool = true
		for k: String in c:
			if k != "cubes" and not GameState.can_afford(k, BigNum.from_float(float(c[k]))):
				mats_ok = false
		if mats_ok:
			# Materials are in: save the cubes for the base (a person sees "needs N cubes" and saves).
			var hc: float = float(c.get("cubes", 0.0))
			out["hub_save"] = hc
			out["reserve"] = maxf(float(out["reserve"]), hc)
			if Hub.can_pay(c):
				out["trip"] = true
	if _research_pick() != "":
		out["trip"] = true
	var st: Stations = Stations.of(world)
	if st:
		for id: String in ["conveyor", "auto_baler", "recycler"]:
			if st.block_reason(id) == "":
				out["trip"] = true
	if _pace_upgrade() != "":
		out["trip"] = true  # [pace]
	var up: String = _best_upgrade(float(out["reserve"]), float(out.get("hub_save", 0.0)) <= 0.0)
	if up != "" and (_goal_upgrade() != "" or Economy.upgrade_cost(up).to_float() * 3.0 < cubes):
		out["trip"] = true
	return out


func _shop(want: Dictionary) -> void:
	var fleet: Fleet = world.fleet
	# 0) [onboard] The Signal Tower: the first tier right away (WREN), later tiers with the base level.
	var tower: SignalTower = world.get_node_or_null("SignalTower") as SignalTower
	if tower and SignalTower.tier() < mini(SignalTower.max_tier(), maxi(1, int(GameState.world.get("hub_level", 1)))) \
			and GameState.can_afford_all(SignalTower.next_cost(), 1.5):
		GameState.spend_all(SignalTower.next_cost())
		tower.raise()
		_event("signal_tower", {"tier": SignalTower.tier()})
	# 0b) [v1guide] The workbench tiers (ui/bench_tiers.gd): the Bots / Research / Requests tabs only
	# open by upgrading the bench, so a player buys the next tier as soon as it's offered and paid.
	if BenchTiers.can_buy(world) and BenchTiers.buy(world):
		_progress()
		_event("bench_tier", {"tier": BenchTiers.tier()})
	# 0c) [v1guide] The story objective's upgrade (Compartment, Scoop Size, the Baler): what the card asks for.
	var obj: Objectives = world.get("objectives") as Objectives
	if obj and str(obj.current().get("type", "")) == "upgrade":
		var oid: String = str(obj.current().get("key", ""))
		if Economy.upgrade_defs.has(oid) and Economy.is_unlocked(oid) and not Economy.is_maxed(oid) and GameState.can_afford("cubes", Economy.upgrade_cost(oid)):
			Economy.buy_upgrade(oid, 1)
	# 1) Research ([money] cubes from the research fund, see _research_ok).
	var guard: int = 0
	var rid: String = _research_pick()
	while rid != "" and guard < 4:
		var rc: float = Research.cost(rid).to_float()
		if not Research.start(rid):
			break
		GameState.inc_stat("bot_research_spent", rc)
		_progress()
		_event("research_start", {"id": rid})
		rid = _research_pick()
		guard += 1
	# 2) Goal-unblocking upgrades.
	var gu: String = _goal_upgrade()
	if gu != "":
		Economy.buy_upgrade(gu, 1)
	# 2b) [pace] The slow-start unlocks (Baler, Lift Strength) before anything else.
	var pu: String = _pace_upgrade()
	if pu != "":
		Economy.buy_upgrade(pu, 1)
	# 2c) [buddy] Glim's Lantern and Hex Scanner when affordable (1.5x margin: never starves the core loop).
	for gid: String in ["light", "scan"]:
		if Glim.block_reason(gid) == "" and GameState.can_afford_all(Glim.next_cost(gid), 1.5) and Glim.buy(gid):
			var gd: GlimDirector = GlimDirector.of(world)
			if gd:
				gd.refresh()
			_event("glim_" + gid, {"tier": Glim.tier(gid)})
	# 2d) [orbC] The Bot Fabricator (3rd planet on): built as soon as it is paid for; until then
	# ordinary robot builds wait (it builds them cheaper), and the upgrade loop saves for it.
	var fab_wait: bool = false
	if HubBuilds.listed(world, "bot_fabricator") and not BotFabricator.built(world):
		if str(HubBuilds.entry(world, "bot_fabricator")["reason"]) == "" and HubBuilds.build(world, "bot_fabricator"):
			_event("build", {"id": "bot_fabricator"})
			_mark("fabricator_s")
			_progress()
		else:
			fab_wait = true
	_fabricator_mix(world)
	# 3) Robots ([ui2] Parts + cubes; keep the next base level's Parts unless the robot can't wait).
	var robot: String = str(want.get("robot", "")) if fleet != null and BenchTiers.tab_open("bots") else ""  # [orbB] no Fleet on the globe yet (orbC)  # [v1guide] the Bots tab is open
	if robot != "":
		var hub_save: float = float(want.get("hub_save", 0.0))
		var spare: float = GameState.get_currency("cubes").to_float() - float(want.get("robot_cost", 0.0))
		var must: bool = _robot_goal(robot) or _essential(robot)
		if fab_wait and not must:
			robot = ""  # [orbC] saving for the Fabricator
		var ok: bool = hub_save <= 0.0 or spare >= hub_save or must
		ok = ok and (must or hub_save <= 0.0 or _mats_spare({"parts": fleet.build_parts(robot).to_float()}, false))
		if ok and robot != "" and fleet.can_build(robot):
			var at: Vector3 = world.upgrades.build_at.call() if world.upgrades.build_at.is_valid() else BENCH_STAND
			fleet.build(robot, at)
	for t: String in (Economy.robot_order if fleet != null and BenchTiers.tab_open("bots") else []):  # [orbB] [v1guide]
		var treq: Dictionary = fleet.tier_requirements(t)
		var keep_cubes: float = float(want.get("hub_save", 0.0)) * 0.5  # [ui2] a tier keeps half the base's cubes
		if fleet.count(t) > 0 and treq.get("ok", false) and _mats_spare({"parts": (treq["parts"] as BigNum).to_float()}, false) \
				and GameState.get_currency("cubes").to_float() - (treq["cost"] as BigNum).to_float() >= keep_cubes:
			if fleet.upgrade_tier(t):
				_progress()
				_event("tier", {"type": t, "tier": fleet.tier_of(t)})
	# 3b) [beat] The Builder tab, when a builder goal is up.
	if _stat_goal("builder_parts_fitted") or _stat_goal("builder_full_custom") or _stat_goal("builder_presets"):
		var tk: String = AutoplayCampaign.tinker(world)
		if tk != "":
			_progress()
			_event("builder", {"what": tk})
	# 4) Base level (logged by _manage on the next tick). [v1guide] Not while the card asks for the
	# workbench's next tier: a player saves for what the step says.
	if not (obj and str(obj.current().get("type", "")) == "bench" and BenchTiers.block_reason(world) == ""):
		world.hub.upgrade()
	# 5) Stations once researched.
	var st: Stations = Stations.of(world)
	if st:
		for id: String in ["conveyor", "recycler", "auto_baler"]:
			var force: bool = id == "recycler" or (id == "conveyor" and (Research.has("recycler") or Research.is_active("recycler") or Research.is_queued("recycler")))
			if st.block_reason(id) != "" or not _mats_spare(st.def(id).get("cost", {}), force):
				continue
			if st.build(id):
				_mark("first_station_s")  # [pace]
				_mark("first_%s_s" % id)
				_progress()
				_event("station", {"id": id})
		# Recycle every 2nd bale while the next base level is short of materials, else none.
		if st.recycler:
			var want_n: int = 2 if _hub_mats_short() else 4
			var g2: int = 0
			while st.route_n != want_n and g2 < 8:
				st.cycle_route()
				g2 += 1
		if st.baler and st.baler.idle() and st.baler.global_position.distance_to(st.frontier_pos()) > 25.0:
			st.relocate_baler()
	# 6) Water tanks near planted hexes far from the barrel.
	_place_tanks()
	# 7) Upgrades: cheapest useful one, keeping the reserve for the next robot/base level.
	var reserve: float = float(want.get("reserve", 0.0))
	var leak: bool = float(want.get("hub_save", 0.0)) <= 0.0
	if robot == "" or fleet.can_build(robot):
		reserve = float(want.get("hub_save", 0.0))
	var prn: String = _pace_research_next()
	if prn != "":
		reserve = maxf(reserve, Research.cost(prn).to_float())  # [pace]
	if not Pace.baler_unlocked() and Economy.is_unlocked(Pace.UP_BALER):
		reserve = maxf(reserve, Economy.upgrade_cost(Pace.UP_BALER).to_float())  # [pace] a person saves for the Baler
	if not BenchTiers.next_def().is_empty() and BenchTiers.block_reason(world) == "":
		reserve = maxf(reserve, float(BenchTiers.next_cost().get("cubes", 0.0)))  # [v1guide] a person saves for the next bench tier
	if HubBuilds.listed(world, "bot_fabricator") and not BotFabricator.built(world):
		reserve = maxf(reserve, float(BotFabricator.cost().get("cubes", 0)))  # [orbC] a person saves for the Fabricator
	var fab_now: BotFabricator = BotFabricator.of(world)
	if fab_now != null and fab_now.fleet_size() < fab_now.cap_now():
		reserve = maxf(reserve, float(BotFabricator.robot_cost("scoopie")["cubes"]))  # [orbC] keep the line running
	guard = 0
	while guard < 20:
		guard += 1
		var up: String = _best_upgrade(reserve, leak)
		if up == "" or Economy.buy_upgrade(up, 1) == 0:
			break
	# 8) Air scrubbers when rich.
	var sd: Dictionary = world.hub.scrubber_def()
	var sc: float = float(sd.get("cost", {}).get("cubes", 1e9)) * world.hub.scrubber_cost_mult()
	var air_goal: bool = _stat_goal("air_filtered") and world.hub.scrubbers == 0
	if world.hub.level >= int(sd.get("requires_level", 2)) and (air_goal or GameState.get_currency("cubes").to_float() > sc * 3.0 + reserve):
		if world.hub.build_scrubber():
			_progress()
			_event("scrubber", {"n": world.hub.scrubbers})
	# 9) Compost press when seeds run short. [camp2] It is a Hub build now: build it once offered.
	if HubBuilds.listed(world, "composter") and str(HubBuilds.entry(world, "composter")["reason"]) == "":
		if HubBuilds.build(world, "composter"):
			_event("build", {"id": "composter"})
	var cp: Composter = world.get("composter")
	if cp and cp.active() and cp.level < cp.max_level() and GameState.get_currency("seeds").to_float() < 10.0:
		if cp.upgrade_cost().to_float() <= GameState.get_currency("cubes").to_float() * 0.25:
			cp.interact()
			_progress()
			_event("composter", {"level": cp.level})


## [orbC] The Fabricator's mix: cleaners and haulers, plus planters and waterers once researched
## (Thriving hexes are half of a planet's restoration).
func _fabricator_mix(world: Node) -> void:
	var fab: BotFabricator = BotFabricator.of(world)
	if fab == null:
		return
	var want: Dictionary = {"scoopie": 3, "haulbug": 1}
	var ok: Array[String] = BotFabricator.types()
	var seeds: float = GameState.get_currency("seeds").to_float()
	if ok.has("seedling"):
		want["seedling"] = 3 if seeds > 100.0 else 1  # seeds piling up: more planters
	if ok.has("drip"):
		want["drip"] = 2
	if seeds > 100.0:
		want["scoopie"] = 2
	if fab.mix() != want:
		fab.set_mix(want)


## Materials the next base level still needs (cubes ignored).
func _hub_need() -> Dictionary:
	var nxt: Dictionary = world.hub.level_def(world.hub.level + 1)
	return nxt.get("cost", {}) if not nxt.is_empty() else {}


func _hub_mats_short() -> bool:
	var c: Dictionary = _hub_need()
	for k: String in c:
		if k != "cubes" and not GameState.can_afford(k, BigNum.from_float(float(c[k]))):
			return true
	return false


## True if paying `cost` leaves enough materials for the next base level (or `force`).
func _mats_spare(cost: Dictionary, force: bool) -> bool:
	if force:
		return true
	var need: Dictionary = _hub_need()
	for k: String in cost:
		if k == "cubes":
			continue
		var have: float = GameState.get_currency(k).to_float()
		if have - float(cost[k]) < float(need.get(k, 0.0)):
			return false
	return true


func _goal_upgrade() -> String:
	var gl: Goals = world.get("goals")
	if gl == null:
		return ""
	for i: int in gl.current():
		var g: Dictionary = gl.chain[i]
		match str(g.get("type", "")):
			"upgrade":
				var id: String = str(g["key"])
				if Economy.upgrade_defs.has(id) and Economy.is_unlocked(id) and not Economy.is_maxed(id) and GameState.can_afford("cubes", Economy.upgrade_cost(id)):
					return id
			"stat":
				if str(g.get("key", "")) == "upgrades_bought":
					var c: String = _best_upgrade(0.0)
					if c != "":
						return c
	return ""


## [pace2] Research an on-screen goal needs right now (a robot's blueprint, a "Research X" goal),
## walking back through its prerequisites; "" when none can start.
func _goal_research() -> String:
	var gl: Goals = world.get("goals")
	if gl == null:
		return ""
	for i: int in gl.current():
		var g: Dictionary = gl.chain[i]
		var want: String = ""
		match str(g.get("type", "")):
			"robot":
				if not Research.robot_unlocked(str(g["key"])):
					want = Research.robot_requirement(str(g["key"]))
			"research":
				want = str(g.get("key", ""))
		var guard: int = 0
		while want != "" and Research.exists(want) and not Research.has(want) and guard < 8:
			guard += 1
			if Research.is_active(want) or Research.is_queued(want):
				break
			if Research.status(want) == "available":
				if Research.can_start(want):
					return want
				break
			var nxt: String = ""
			for r: String in Research.requires(want):
				if not Research.has(r):
					nxt = r
					break
			want = nxt
	return ""


const CLEANING_UPGRADES: Array[String] = ["compartment_size", "scoop_width", "carry_stack", "compactor_pressure", "scoop_speed",
	"auto_compactor", "magnet_arm", "detector_range", "belt_speed", "baler_speed", "recycler_yield", "laser_reach", "multi_lock"]


func _useful_upgrade(id: String) -> bool:
	var u: Dictionary = Economy.upgrade_defs[id]
	var cleaning_over: bool = _land_left_frac() < 0.04
	if u.has("robot"):
		var rt: String = str(u["robot"])
		if cleaning_over and (rt in ["scoopie", "haulbug"] or (rt == "skimmer" and not _lake_dirty())):
			return false
		return world.get("fleet") != null and world.fleet.count(rt) > 0  # [orbB] no Fleet on the globe yet
	if cleaning_over and id in CLEANING_UPGRADES:
		return false
	var st: Stations = Stations.of(world)
	match id:
		"carry_stack":
			return _haulers() == 0
		"belt_speed":
			return st != null and st.conveyor != null
		"baler_speed":
			return st != null and st.baler != null
		"recycler_yield":
			return st != null and st.recycler != null
	return true


## Robots a person would buy even while saving for the base: the garden's waterers, the lake's
## Skimmer, and the first of each kind.
func _essential(type_id: String) -> bool:
	var fleet: Fleet = world.fleet
	if fleet.count(type_id) == 0:
		return true
	match type_id:
		"drip":
			return _drips() < (world.hex_levels.count_at_least(2) if world.get("hex_levels") else 0)
		"skimmer":
			return _lake_dirty()
		"scoopie":  # [beat] a small cleaning crew is worth more than saving a few minutes for the base
			return fleet.count("scoopie") < 3 and _land_left_frac() > 0.2
		"haulbug":
			return fleet.count("haulbug") * 2 < fleet.count("scoopie")
	return false


func _stat_goal(key: String) -> bool:
	var gl: Goals = world.get("goals")
	if gl == null:
		return false
	for i: int in gl.current():
		if str(gl.chain[i].get("key", "")) == key:
			return true
	return false


func _robot_goal(type_id: String) -> bool:
	var ob: Objectives = world.get("objectives") as Objectives  # [v1guide] the timeline's current step
	if ob:
		var od: Dictionary = ob.current()
		if str(od.get("type", "")) == "robot" and str(od.get("key", "")) in [type_id, "any"]:
			return true
	var gl: Goals = world.get("goals")
	if gl == null:
		return false
	for i: int in gl.current():
		var g: Dictionary = gl.chain[i]
		if str(g.get("type", "")) == "robot" and str(g.get("key", "")) == type_id:
			return true
	return false


## Cheapest useful upgrade affordable while keeping `reserve` cubes (or, with leak, under 15% of the purse).
func _best_upgrade(reserve: float, leak: bool = true) -> String:
	var cubes: float = GameState.get_currency("cubes").to_float()
	var best: String = ""
	var best_c: float = INF
	for id: String in Economy.upgrade_order:
		if not Economy.is_unlocked(id) or Economy.is_maxed(id) or not _useful_upgrade(id):
			continue
		var c: float = Economy.upgrade_cost(id).to_float()
		if c < best_c:
			best_c = c
			best = id
	if best == "" or best_c > cubes:
		return ""
	if cubes - best_c >= reserve or (leak and best_c <= cubes * 0.15):
		return best
	return ""


## The robot to work toward next (research done, crew room), or "".
func _next_robot() -> String:
	var fleet: Fleet = world.fleet
	if fleet == null:
		return ""
	var seeds_on: bool = world.garden != null and world.garden.unlocked()
	var scoop: int = fleet.count("scoopie")
	var haul: int = fleet.count("haulbug")
	var gardens: int = world.hex_levels.count_at_least(2) if world.get("hex_levels") else 0
	var order: Array[String] = []
	# Nearly all land junk gone: no more cleaners or haulers (the lake still wants a Skimmer).
	var late: bool = _land_left_frac() < 0.12
	var saving: bool = not _hub_need().is_empty() and not _hub_mats_short()
	if AutoplayCampaign.frontier_kid(world) == "sunken_city" and _lake_dirty() and fleet.count("skimmer") < 14:
		order.append("skimmer")  # [beat] the flooded city is skimmed, not scooped
	if seeds_on and _drips() < maxi(1, gardens):
		order.append("drip")
	if scoop == 0:
		order.append("scoopie")
	if haul * 2 < scoop:
		order.append("haulbug")
	if seeds_on and fleet.count("seedling") == 0 and GameState.get_currency("seeds").to_float() > 8.0:
		order.append("seedling")
	order.append("scoopie")
	if scoop >= 2 and fleet.count("skimmer") == 0 and _lake_dirty():
		order.append("skimmer")
	if seeds_on:
		order.append("drip")
	order.append("multibot")
	if haul < scoop:
		order.append("haulbug")
	for t: String in order:
		if not Research.robot_unlocked(t) or fleet.join_crew(t) == "":
			continue
		if late and (t == "scoopie" or (t == "haulbug" and haul > 0)):
			continue
		if saving and not _essential(t) and not _robot_goal(t):
			continue  # saving for the base: only the robots that can't wait
		return t
	return ""


## Share of the land junk volume still on the ground.
func _land_left_frac() -> float:
	var f: HexField = world.field
	var left: float = 0.0
	var total: float = 0.0
	for h: int in _hexes():
		if _land(h):
			total += f.hex_total[h]
			if not f.is_clean(h):
				left += f.hex_left[h]
	return left / maxf(total, 1.0)


func _lake_dirty() -> bool:
	var f: HexField = world.field
	for h: int in _hexes():
		if f.is_water(h) and not f.is_clean(h):
			return true
	return false


## [money] Research costs cubes now. The bot treats the field-note cubes (the old Data income)
## as its research fund, like a player who spends the research share on research (so research and
## the base levels pace as they did with Data); it also starts research when it is rich.
func _research_ok(id: String) -> bool:
	var c: float = Research.cost(id).to_float()
	if (id in ["salvage_logic", "conveyor", "auto_baler"] or id in PACE_GARDEN_CHAIN) and GameState.get_currency("cubes").to_float() >= c:
		return true  # [pace] the helper and automation unlocks come before saving for base 3
	var fund: float = float(GameState.stats.get("notes_cubes", 0.0)) + float(GameState.stats.get("wildlife_cubes", 0.0)) - float(GameState.stats.get("bot_research_spent", 0.0))
	return c <= fund or GameState.get_currency("cubes").to_float() > maxf(c * 4.0, _research_reserve())


## Cubes the bot keeps for the next base level / robot before dipping into them for research.
func _research_reserve() -> float:
	var nxt: Dictionary = world.hub.level_def(world.hub.level + 1) if world.get("hub") != null else {}
	if world.get("hub") != null and int(world.hub.level) >= 2:
		# [pace2] mid game: a player researches with spare cubes instead of hoarding 1.5x the next base
		return float(nxt.get("cost", {}).get("cubes", 0.0)) * 0.5 + 1000.0
	return float(nxt.get("cost", {}).get("cubes", 0.0)) * 1.5 + 2000.0


func _research_pick() -> String:
	if not BenchTiers.tab_open("research"):  # [v1guide] the Research tab opens with the workbench's Mk III
		return ""
	if not Research.active().is_empty() and Research.queue().size() >= Research.max_queue():
		return ""
	var saving: bool = false
	var gr: String = _goal_research()  # [pace2] the goal on screen first
	if gr != "":
		return gr
	var need: String = _pace_research_next()  # [pace] save for the helper / automation unlock
	if need != "":
		return need if _research_ok(need) and Research.can_start(need) else ""
	var prio: Array[String] = AutoplayCampaign.research_first(world)
	prio.append_array(RESEARCH_PRIORITY)
	for id: String in prio:
		if Research.exists(id) and Research.can_start(id) and _research_ok(id):
			return id
		if id == RESEARCH_SAVE_FROM:
			saving = true
		if saving and Research.exists(id) and Research.status(id) == "available":
			return ""  # [beat] critical-path node open but not affordable yet: save Data for it
	var best: String = ""
	var best_c: float = INF
	for id: String in Research.ids():
		if Research.can_start(id) and _research_ok(id) and Research.cost(id).to_float() < best_c:
			best_c = Research.cost(id).to_float()
			best = id
	return best


## Research bookkeeping: idle time (nothing running) and starved time (idle, nodes open, no Data).
func _track_research(dt: float) -> void:
	if Research.active().is_empty():
		_research_idle_s += dt
		_research_idle_run += dt
		_research_idle_max = maxf(_research_idle_max, _research_idle_run)
		var any_open: bool = false
		for id: String in Research.ids():
			if Research.status(id) == "available":
				any_open = true
				break
		if any_open:
			_research_starved_s += dt
	else:
		_research_idle_run = 0.0


## Command zones: cleaners to the frontier, planters and waterers to the garden.
func _paint_zones() -> void:
	var fleet: Fleet = world.fleet
	if fleet == null:
		return
	# Land clean: Multibots on the clean crew go water the garden (Allocation board).
	if _land_left_frac() <= 0.0 and world.garden and world.garden.unlocked():
		var a: Dictionary = fleet.allocation()
		if int(a.get("clean", 0)) > 0 and fleet.move_job("clean", "water"):
			_event("allocate", {"from": "clean", "to": "water"})
	var f: HexField = world.field
	var cleaners: int = fleet.crew_size("clean") if fleet is SphereFleet else fleet.robots_with_role("clean").size()  # [v3qa] globe crew
	var want_n: int = clampi(2 + cleaners, 3, 6)
	var zone_goal: int = _zone_goal_target()
	want_n = maxi(want_n, zone_goal)
	if cleaners == 0 and zone_goal == 0:
		return
	var cand: Array = []
	for h: int in _hexes():
		if _land(h) and not f.is_clean(h) and h != _focus_hex:
			cand.append(h)
	var o: Vector3 = world.depot.global_position if f is SphereField and world.get("depot") != null else Vector3.ZERO  # [v3qa] the globe's centre is the planet's
	cand.sort_custom(func(a: int, b: int) -> bool: return f.hex_center(a).distance_to(o) - 8.0 * f.removed_fraction(a) < f.hex_center(b).distance_to(o) - 8.0 * f.removed_fraction(b))
	_set_zone("clean", cand.slice(0, want_n))
	var g: Garden = world.garden
	if g == null or not g.unlocked():
		return
	var garden: Array = []
	for h: int in _hexes():
		if _land(h) and f.is_clean(h) and _hex_planted(g, h).x > 0:
			garden.append(h)
	if _drips() > 0:
		_set_zone("water", garden)
	if fleet.robots_with_role("plant").size() > 0:
		var pz: Array = garden.duplicate()
		var ph: int = _pick_plant_hex(g)
		if ph >= 0 and not pz.has(ph):
			pz.append(ph)
		_set_zone("plant", pz)


func _zone_goal_target() -> int:
	var ob: Objectives = world.get("objectives") as Objectives  # [v3qa] the story step "Send your robot to work"
	if ob and str(ob.current().get("type", "")) == "zone":
		return int(ob.current().get("target", 1))
	var gl: Goals = world.get("goals")
	if gl == null:
		return 0
	for i: int in gl.current():
		if str(gl.chain[i].get("type", "")) == "zone":
			return int(gl.chain[i].get("target", 1))
	return 0


func _set_zone(key: String, hexes: Array) -> void:
	var fleet: Fleet = world.fleet
	if fleet is SphereFleet:  # [v3qa] the globe crew's painted zones (what Command view B paints)
		var crew: SphereCrew = (fleet as SphereFleet).crew
		var had: Dictionary = (crew.zones.get(key, {}) as Dictionary).duplicate()
		var ch: bool = false
		for c: Variant in had:
			if not hexes.has(int(c)):
				crew.set_zone_cell(key, int(c), false)
				ch = true
		for h: Variant in hexes:
			if not had.has(int(h)):
				crew.set_zone_cell(key, int(h), true)
				ch = true
		if ch:
			_log.append({"t": _now(), "event": "zone", "key": key, "hexes": hexes})
		return
	var cur: Array = (fleet.order(key, false)["zone"] as Array).duplicate()
	var changed: bool = false
	for h: Variant in cur:
		if not hexes.has(int(h)):
			fleet.toggle_zone_hex(key, false, int(h), false)
			changed = true
	for h: Variant in hexes:
		if not cur.has(int(h)):
			fleet.toggle_zone_hex(key, false, int(h), true)
			changed = true
	if changed:
		_log.append({"t": _now(), "event": "zone", "key": key, "hexes": hexes})


func _place_tanks() -> void:
	var fleet: Fleet = world.fleet
	if _drips() == 0 or fleet.water_net == null:
		return
	var wn: WaterNet = fleet.water_net
	if wn.tanks.size() >= int(WaterNet.cfg().get("max", 6)):
		return
	var g: Garden = world.garden
	var f: HexField = world.field
	for h: int in _hexes():
		if not _land(h) or not f.is_clean(h) or _hex_planted(g, h).x == 0:
			continue
		var c: Vector3 = f.hex_center(h)
		var near: Dictionary = wn.nearest_refill(c)
		if not near.is_empty():  # [beat] no refill point at all (Dust Flats dry well): place one
			var np: Vector3 = near["pos"]
			if Vector2(np.x - c.x, np.z - c.z).length() < 14.0:
				continue
		if wn.tank_cost().to_float() * 2.0 > GameState.get_currency("cubes").to_float():
			return
		for off: Vector3 in [Vector3.ZERO, Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 0, -2), Vector3(3, 0, 3)]:
			if wn.place_block_reason(c + off) == "" and wn.place_tank(c + off):
				_progress()
				_event("tank", {"hex": h, "n": wn.tanks.size()})
				return


# --- Report ---------------------------------------------------------------------------

## [beat] Robots that report busy work but haven't moved for three snapshots (3 game-min).
var _bot_pos: Dictionary = {}
var _bot_still: Dictionary = {}
var _stuck_bots: Dictionary = {}


func _robot_health() -> Dictionary:
	var counts: Dictionary = {}
	var fl: Fleet = world.fleet
	if fl == null:
		return counts
	var re := RegEx.create_from_string("[0-9]+")
	for r: Robot in fl.robots():
		var st: String = re.sub(r.status_text(), "#", true)
		counts[st] = int(counts.get(st, 0)) + 1
		var busy: bool = not (st.begins_with("idle") or st.begins_with("parked") or st.begins_with("waiting") or st.contains("nothing left") or st.contains("is clean") or st.contains("out of seeds") or st.contains("zone clean") or st.begins_with("looking for"))
		var last: Vector3 = _bot_pos.get(r.robot_name, Vector3.INF)
		if busy and last != Vector3.INF and last.distance_to(r.global_position) < 0.5:
			_bot_still[r.robot_name] = int(_bot_still.get(r.robot_name, 0)) + 1
			if int(_bot_still[r.robot_name]) >= 3 and not _stuck_bots.has(r.robot_name):
				_stuck_bots[r.robot_name] = "%s %s at %s" % [r.type_id, st, str(r.global_position.snappedf(0.1))]
				print("[Autoplay] STUCK robot %s: %s" % [r.robot_name, _stuck_bots[r.robot_name]])
		else:
			_bot_still[r.robot_name] = 0
		_bot_pos[r.robot_name] = r.global_position
	return counts


func _snapshot() -> void:
	var fl: Fleet = world.fleet
	var types: Dictionary = {}
	if fl:
		for r: Robot in fl.robots():
			types[r.type_id] = int(types.get(r.type_id, 0)) + 1
	var hl: HexLevels = world.get("hex_levels")
	var lv: Array = []
	if hl:
		for l: int in range(1, 6):
			lv.append(hl.count_at_least(l))
	var ngoals: int = world.goals.done_count() if world.get("goals") else 0
	_log.append({"t": _now(), "pos": [snappedf(world.patch.global_position.x, 0.1), snappedf(world.patch.global_position.z, 0.1)], "escapes": _escapes, "remote_shops": _remote_shops, "cubes": snappedf(GameState.get_currency("cubes").to_float(), 1.0),
		"rate": snappedf(GameState.income_rate(), 0.01), "earned": snappedf(BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float(), 1.0), "parts_cur": snappedf(GameState.get_currency("parts").to_float(), 0.1),  # [money]
		"seeds": snappedf(GameState.get_currency("seeds").to_float(), 0.1), "parts": snappedf(GameState.get_currency("parts").to_float(), 1.0),
		"hexes": world.field.cleaned_count, "hex_levels": lv, "robots": types, "hub": int(world.hub.level),
		"task": _task, "research": Research.active_id(), "upgrades": int(GameState.stats.get("upgrades_bought", 0)),
		"bots": _robot_health(), "goals": ngoals, "stats": _stat_pick(["research_done", "plants_bloomed", "garden_stipend", "air_filtered", "robots_built", "robot_bales", "bales_recycled", "plants_planted"]),
		"planet": str(Homeward.planet_def(Homeward.current_planet()).get("id", "")), "pct": snappedf(Homeward.measure_current(), 0.001)})  # [orbC] planet restoration
	var pk: int = Homeward.current_planet()  # [orbC] pacing marks: 25% / 50% of each planet
	if pk >= 0:
		var pid: String = str(Homeward.planet_def(pk).get("id", ""))
		var pct: float = Homeward.measure_current()
		for th: int in [25, 50, 75]:
			if pct * 100.0 >= th:
				AutoplayCampaign.mark("pct%d_%s_s" % [th, pid], _now())
		# Staged pacing runs: --quit-at-pct=50 saves and stops once this planet is that restored.
		if DevHooks.has("quit-at-pct") and pct * 100.0 >= DevHooks.get_f("quit-at-pct", 50.0) and not _pct_quit:
			_pct_quit = true
			print("[autoplay] %s at %.0f%% after %.1f game min (campaign %.1f min): saving and quitting" % [pid, pct * 100.0, _now() / 60.0,
				float(GameState.stats.get("time_played", 0.0)) / 60.0])
			write_report()
			SaveManager.save_game()
			world.get_tree().quit()
	print("[Autoplay] %5.1f min cubes=%d rate=%.2f/s partscur=%.0f seeds=%.0f parts=%d hexes=%d lv=%s robots=%s hub=%d task=%s goals=%d research=%s pos=%s esc=%d" % [_now() / 60.0,  # [money]
		int(GameState.get_currency("cubes").to_float()), GameState.income_rate(), GameState.get_currency("parts").to_float(),
		GameState.get_currency("seeds").to_float(), GameState.parts.size(),
		world.field.cleaned_count, str(lv), str(types), int(world.hub.level), _task, ngoals, Research.active_id(), str(world.patch.global_position.snappedf(0.1)), _escapes])


func _stat_pick(keys: Array) -> Dictionary:
	var out: Dictionary = {}
	for k: String in keys:
		out[k] = snappedf(float(GameState.stats.get(k, 0.0)), 1.0)
	return out


func _gaps(times: Array[float], end_t: float) -> Array:
	var out: Array = []
	var prev: float = _start_t  # [beat] this scene's start (continued saves and rocket trips)
	var ts: Array[float] = times.duplicate()
	ts.sort()
	ts.append(end_t)
	for t: float in ts:
		if t - prev > GAP_S:
			out.append([snappedf(prev / 60.0, 0.1), snappedf(t / 60.0, 0.1), snappedf((t - prev) / 60.0, 0.1)])
		prev = maxf(prev, t)
	return out


func write_report() -> void:
	var end_t: float = _now()
	_report["game_time_s"] = end_t
	_report["game_time_min"] = snappedf(end_t / 60.0, 0.1)
	_report["cubes"] = GameState.get_currency("cubes").to_float()
	_report["earned_total"] = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	_report["cubes_made"] = GameState.stats.get("cubes_made", 0)
	_report["perfect_cubes"] = GameState.stats.get("perfect_cubes", 0)
	_report["hexes_cleaned"] = world.field.cleaned_count
	_report["junk_hexes"] = world.field.junk_hex_count
	_report["upgrades"] = GameState.upgrades.duplicate()
	var next_goals: Array = []
	if world.get("goals"):
		_report["goals_done"] = world.goals.done_count()
		_report["goals_total"] = world.goals.chain.size()
		for i: int in world.goals.current():
			next_goals.append(str(world.goals.chain[i]["id"]))
	_report["next_goals"] = next_goals
	_report["research_done"] = Research.done_list().duplicate()
	_report["research_idle_s"] = snappedf(_research_idle_s, 1.0)
	_report["research_idle_max_s"] = snappedf(_research_idle_max, 1.0)
	_report["research_starved_s"] = snappedf(_research_starved_s, 1.0)
	_report["parts_bought"] = _parts_bought
	_report["stuck_escapes"] = _escapes
	_report["fell_through"] = GameState.stats.get("fell_through", 0)
	_report["cubes_fell"] = GameState.stats.get("cubes_fell", 0)  # [beat]
	_report["stuck_robots"] = _stuck_bots
	_report["remote_shops"] = _remote_shops
	_report["parts_found"] = GameState.stats.get("parts_found", 0)
	_report["hub_level"] = int(world.hub.level)
	var types: Dictionary = {}
	if world.fleet:
		for r: Robot in world.fleet.robots():
			types[r.type_id] = int(types.get(r.type_id, 0)) + 1
	_report["robots"] = types
	# Gaps: stretches > 3 min with no goal completed; and with no goal and nothing new bought.
	_report["goal_gaps_min"] = _gaps(_goal_times, end_t)
	var both: Array[float] = _goal_times.duplicate()
	both.append_array(_progress_times)
	_report["dead_gaps_min"] = _gaps(both, end_t)
	_report["timeline"] = _timeline
	_report["log"] = _log
	_report["ignored_pieces"] = _ignore_piece.size()
	_report["campaign_min"] = AutoplayCampaign.timeline_min()  # [beat] milestones across stages
	_report["district"] = str(world.get("district_name"))
	var path: String = ProjectSettings.globalize_path("res://screenshots/autoplay_report.json")
	if DevHooks.get_s("save-dir", "") != "":  # [orbC] parallel staged runs keep their own report
		path = path.replace(".json", "_%s.json" % DevHooks.get_s("save-dir", "").validate_filename())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_report, "  "))
	var summary: Dictionary = _report.duplicate()
	summary.erase("timeline")
	summary.erase("log")
	print("[Autoplay] report: ", JSON.stringify(summary))
