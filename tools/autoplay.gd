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
##     places Water Tanks, reads memory shards;
##   - does a city's source job as soon as a step is on offer (systems/sources.gd).
## Writes a timeline to screenshots/autoplay_report.json on exit (goal completions, hex level-ups,
## robots, research, base levels, gaps > 3 min with no goal and no new purchase). Run:
##   godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=950
## Research fills from field data the work earns (systems/field_data.gd); the bot keeps one node
## running from the moment the Research tab opens and reports how long none was (research_idle_*).

const AT_BASE_R: float = 7.5
const GAP_S: float = 180.0
const SNAPSHOT_S: float = 60.0
## Research order a planner would follow: unlock the planting/watering robots first.
const RESEARCH_PRIORITY: Array[String] = ["salvage_logic", "soil_survey", "water_testing", "field_notebook", "scoop_beam",
	"hardy_weeds", "seedling_blueprint", "big_tanks", "drip_blueprint", "wild_mint", "pollinator_survey", "conveyor", "wide_beam",
	"auto_baler", "recycler", "bigger_hopper", "auto_sort", "haul_routes", "spray_heads", "bale_tuning", "multibot_blueprint",
	"rocket_cargo", "silt_filters", "pump_lines", "irrigation", "dune_charts", "field_magnet", "tractor_beam", "dew_condensers",
	"thermal_lance", "pump_works", "ark_beacon", "hedgerows", "evergreens", "dune_fences", "cold_hardy_seeds", "heat_pumps"]

var world: Node
var _move := Vector3.ZERO
var _scoop: bool = false
var _cube: bool = false
var _interact: bool = false
var _dt: float = 0.0
var _cooldown: float = 0.0
var _stuck_timer: float = 0.0
var _shore_blocks: int = 0  # [v4bots] escapes with water straight ahead (no Hover Jets yet)
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
	_hook(EventBus.cube_made, func(_i: Dictionary) -> void: _mark("first_cube_s"))
	_hook(EventBus.cube_cashed, func(_v: BigNum, _p: Vector3) -> void:
		_mark("first_cashin_s")
		_mark("first_payout_s")
		_pace_cashed())  # [pace]
	_hook(EventBus.load_tipped, func(_c: float, _p: Vector3) -> void: _mark("first_payout_s"))
	_hook(EventBus.currency_changed, _on_currency)
	_hook(EventBus.upgrade_bought, func(id: String, lv: int) -> void:
		_mark("first_upgrade_s")
		_pace_bought(id, lv)  # [pace]
		_progress()
		_log.append({"t": _now(), "event": "upgrade", "id": id, "level": lv}))
	_hook(EventBus.hex_cleaned, func(h: int, _p: Vector3, _b: BigNum) -> void:
		_mark("first_hex_s")
		_hex_times.append(_now())
		_progress()
		var dd: Districts = _districts()
		if dd != null:
			_cadence.hex_cleaned(dd.district_of_cell(h), _now())
		_event("hex_clean", {"hex": h, "n": world.field.cleaned_count}))
	_hook(EventBus.hex_level_changed, func(h: int, lv: int) -> void:
		_mark("first_hexlv_%d_s" % lv)
		_stall.progress(_now())
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
	_hook(EventBus.pollution_cleared, _mastery.on_cleared)
	_hook(EventBus.mastery_gained, func(kind: String, level: int) -> void:
		_mastery.on_gained(kind, level, _now())
		_cadence.mastery_gained(kind, level, _now())
		_event("mastery", {"kind": kind, "level": level}))
	_hook(EventBus.surge_charged, func() -> void:
		_surge.on_charged(_now())
		_event("surge_charged", {"n": _surge.charged.size()}))
	_hook(EventBus.source_step_done, func(district: String, i: int) -> void:
		_progress()
		_event("source_step", {"district": district, "step": i}))
	_hook(EventBus.source_shut_down, func(district: String) -> void:
		_mark("source_%s_s" % district)
		_cadence.source_shut(district, _now())
		_progress()
		_event("source_shut", {"district": district}))
	_hook_whole_game()
	world.tree_exiting.connect(write_report)
	world.tree_exiting.connect(_unhook)  # [beat] rocket travel reloads the scene: drop the old bot's hooks


var _hooks: Array = []
## Who cleared what, when each mastery level came, and what to learn next (tools/autoplay_mastery.gd).
var _mastery := AutoplayMastery.new()
## When to let a full Bloom Core go, and when each Surge came (tools/autoplay_surge.gd).
var _surge := AutoplaySurge.new()
## When each goal was finished, by tier, and the gaps between them (tools/autoplay_goals.gd).
var _goal_log := AutoplayGoals.new()
var _learn_hex: int = -1
var _learn_scan_t: float = 0.0
## Score (metres) by which the bot prefers a hex holding a scooped kind robots are still shut out of.
const LEARN_PULL_M: float = 60.0
const LEARN_SCAN_S: float = 3.0
const LEARN_WORK_M: float = 3.0
## Pacing record (docs/reviews/M3-19_ECONOMY.md): every spend (a purchase) with its time, the most
## cubes held, and the time each of the first hexes came clean. Times are game seconds.
var _spend_times: Array[float] = []
var _held: Dictionary = {}
var _max_cubes: float = 0.0
var _hex_times: Array[float] = []
var _pacing_printed: bool = false
const PACING_WINDOW_S: float = 1200.0


## A currency went down: something was bought. Cubes held are tracked for the ceiling check.
func _on_currency(id: String, amount: BigNum) -> void:
	var now: float = amount.to_float()
	var was: float = float(_held.get(id, 0.0))
	_held[id] = now
	if id == "cubes":
		_max_cubes = maxf(_max_cubes, now)
	if now < was - 0.5 and id in ["cubes", "parts"]:
		_spend_times.append(_now())
		_cadence.spent(_now())
		_stall.progress(_now())


## Seconds since the bot took control (the load and landing before it are not play).
func _since_control(t: float) -> float:
	return t - float(_report.get("control_s", _start_t))


## The longest wait between two purchases inside the first `window_s` seconds of control.
func _longest_purchase_gap(window_s: float) -> float:
	var prev: float = 0.0
	var worst: float = 0.0
	for t: float in _spend_times:
		var at: float = _since_control(t)
		if at > window_s:
			break
		worst = maxf(worst, at - prev)
		prev = at
	return maxf(worst, minf(_since_control(_now()), window_s) - prev)


## Dev: --hand-log=N prints Lumi's hand loop once a second up to N seconds of control, from
## --hand-log-from=M when given (what
## he is doing, the chest, how far the bin is, how clean the hex under him is), to see where the
## first minutes go.
func _hand_log(p: Patch) -> void:
	var at: float = _since_control(_now())
	if not DevHooks.has("hand-log") or at > DevHooks.get_f("hand-log", 120.0) or at < DevHooks.get_f("hand-log-from", 0.0):
		return
	var f: HexField = world.field
	var h: int = f.hex_at(p.global_position)
	print("[hand] %5.1f s task=%-7s chest=%4.1f/%2.0f bin=%4.1f m hex=%d clean=%3.0f%% cubes=%.0f" % [_since_control(_now()), _task, p.compartment.fill, p.capacity(),
		p.global_position.distance_to((world.depot as Depot).bin_world()), h, f.removed_fraction(h) * 100.0 if h >= 0 else 0.0, GameState.get_currency("cubes").to_float()])


## One line with the beats the economy review compares against the accepted proposal.
func _print_pacing(tag: String) -> void:
	var beats: Array[String] = []
	for key: String in ["first_payout_s", "first_upgrade_s", "first_hex_s", "first_surge_s", "baler_s", "tower_s", "bench_2_s", "first_robot_s", "base_2_s"]:
		if _report.has(key):
			beats.append("%s=%.0f" % [key.trim_suffix("_s"), _since_control(float(_report[key]))])
	var hexes: Array[String] = []
	for i: int in mini(_hex_times.size(), 24):
		hexes.append("%.0f" % _since_control(_hex_times[i]))
	var buys: Array[String] = []
	for t: float in _spend_times:
		if _since_control(t) <= PACING_WINDOW_S:
			buys.append("%.0f" % _since_control(t))
	print("[Autoplay] pacing %s (s from control at %.0f s): %s | hexes at %s | purchases=%d longest gap in first %d min=%.0f s | most cubes held=%.0f | purchases at %s" % [
		tag, float(_report.get("control_s", _start_t)), " ".join(beats), ",".join(hexes), _spend_times.size(), int(PACING_WINDOW_S / 60.0),
		_longest_purchase_gap(PACING_WINDOW_S), _max_cubes, ",".join(buys)])
	var levels: Array[String] = []
	for key: String in _mastery.times:
		levels.append("%s=%.0f" % [key, _since_control(float(_mastery.times[key]))])
	print("[Autoplay] mastery %s: levels at %s | hand %.0f units, crew %.0f units, hand share %.0f%% (lowest %d-min window %.0f%%)" % [
		tag, " ".join(levels), _mastery.hand_units, _mastery.crew_units, _mastery.hand_share() * 100.0, int(AutoplayMastery.WINDOW_S / 60.0),
		_mastery.lowest_window_share() * 100.0])


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
	_stall.progress(_now())


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
var _play_set: Dictionary = {}


## The hexes the bot plays: the ground round the start hub (of the globe's 164k+ cells): the first
## district and the land just past it (HubFrame.AREA_RINGS rings), so it never runs out of work.
## With cities (districts) the bot plays the city whose pad the rocket stands on; the wider ring
## is kept for when that city has nothing left to clean (_pick_focus).
func _hexes() -> PackedInt32Array:
	var d: Districts = _districts()
	var city: String = d.district_of_site(_here_site()) if d != null else ""
	if city != _area_city or _play_area.is_empty():
		_area_city = city
		var sf: SphereField = world.field
		var centre: int = int(_orbit().globe.sites[_here_site()]["cell"]) if _orbit().globe.sites.size() > _here_site() else _orbit().globe.start_cell()
		_wide_area = sf.grid.cells_around(centre, HubFrame.AREA_RINGS)
		_play_area = d.cells_of(city) if city != "" else _wide_area
		_play_set.clear()
		for c: int in _play_area:
			_play_set[c] = true
	return _play_area


## The city in play as a set of hexes (see _hexes).
func _area_set() -> Dictionary:
	_hexes()
	return _play_set


func _go(p: Patch, target: Vector3, stop_dist: float = 0.3) -> float:
	var sm: SiteManager = (world.orbit as SliceOrbit).globe.site_manager  # on a hub site: round its buildings along the streets
	var aim: Vector3 = target
	if sm:
		aim = sm.detour(p.global_position, target)
	var dry: Vector3 = _round_lake(p, aim)
	if dry.distance_to(target) > 0.5:
		_go_raw(p, dry, 1.0)
		return maxf(target.distance_to(p.global_position), stop_dist + 1.0)
	return _go_raw(p, target, stop_dist)


## How far ahead Lumi looks for a lake on his way, the spacing of the looks, how far past the
## shore the way round is aimed, and the turns he tries (degrees, nearest first; the side that
## worked last is tried first).
const LAKE_LOOK_M: float = 36.0
const LAKE_STEP_M: float = 2.0
const LAKE_PAST_M: float = 6.0
const LAKE_TURNS_DEG: Array[float] = [20.0, 40.0, 60.0, 80.0, 100.0, 120.0]
var _lake_side: float = 1.0


## Metres of dry ground from `from` along `dir` (unit, along the ground), looking up to `reach`.
func _dry_run(p: Patch, from: Vector3, dir: Vector3, reach: float) -> float:
	var at: float = LAKE_STEP_M
	while at < reach:
		if bool(p.call("_water_at", from + dir * at)):
			return at - LAKE_STEP_M
		at += LAKE_STEP_M
	return reach


## Lakes are whole hexes and Lumi cannot cross one without Hover Jets: when the straight line to
## `target` runs into water, the point to walk to instead (a person walks round a pond; the bot used
## to push at the shore until its stuck timer fired). `target` itself when the way is dry.
func _round_lake(p: Patch, target: Vector3) -> Vector3:
	if not p.has_method("can_hover_water") or p.can_hover_water():
		return target
	var from: Vector3 = p.global_position
	var u: Vector3 = from.normalized()
	var d: Vector3 = target - from
	d -= u * d.dot(u)
	var dist: float = d.length()
	if dist < LAKE_STEP_M * 2.0:
		return target
	var dir: Vector3 = d / dist
	var reach: float = minf(dist - 1.0, LAKE_LOOK_M)
	var dry: float = _dry_run(p, from, dir, reach)
	if dry >= reach:
		return target
	var want: float = dry + LAKE_PAST_M
	for deg: float in LAKE_TURNS_DEG:
		for side: float in [_lake_side, -_lake_side]:
			var turned: Vector3 = dir.rotated(u, deg_to_rad(deg) * side)
			if _dry_run(p, from, turned, want) >= want:
				_lake_side = side
				return from + turned * want
	return target


func _go_raw(p: Patch, target: Vector3, stop_dist: float = 0.3) -> float:
	var d: Vector3 = target - p.global_position
	var u: Vector3 = p.global_position.normalized()  # [orbB] along the ground: drop the local-up part
	d -= u * d.dot(u)
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
			var side := d.cross(u).normalized() * (1.0 if randf() < 0.5 else -1.0)  # [orbB]
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
	if not _report.has("control_s") and world.get("depot") != null and world.get("orbit") is SliceOrbit:
		for line: String in YardReport.lines((world.orbit as SliceOrbit).globe, (world.depot as Depot).bin_world(), (world.depot as Depot).global_position):
			print(line)  # the walking the start layout costs, for the pacing fit
	_mark("control_s")
	if not _pacing_printed and _since_control(_now()) >= PACING_WINDOW_S:
		_pacing_printed = true
		_print_pacing("first %d min" % int(PACING_WINDOW_S / 60.0))
	RocketTiers.now_override = 1000.0 + float(GameState.stats.get("time_played", 0.0))  # [beat]
	if DevHooks.has("game-minutes") and _now() >= DevHooks.get_f("game-minutes", 60.0) * 60.0 and not _stopping:
		_stopping = true
		_stop_run("game-minutes")
		return
	_hook_goals()
	if DevHooks.has("garden-audit") and _since_control(_now()) > 40.0 and not _report.has("garden_audit"):
		_garden_audit()
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
		_hand_log(p)
		_mastery.sample(_now())
		if world.get("goals"):
			_goal_log.sample(world.goals, _now())
		_watch_whole_game(_not_play())
	if world.first_seed and world.first_seed.get("_active"):
		return  # the seed-tin cinematic
	if p._cubing > 0.0 or p.detector.digging > 0.0:
		return
	if _escape_t > 0.0:
		_escape_t -= delta
		_move = _escape_dir
		return
	if not (_do_source(p) or _do_travel(p) or _do_bench(p) or _do_tin(p) or _do_find(p) or _do_shard(p) or _do_dump(p) or _do_deliver(p) or _do_pickup(p) or _do_dig(p) or _do_pet(p) or _do_learn(p) or _do_garden(p)):
		_do_clean(p)
	if _surge.tick(Surge.of(world), _scoop and (_task == "clean" or _task == "learn"), p.compartment.ratio(p.capacity()), _now()):
		_mark("first_surge_s")
		_event("surge", {"n": _surge.times.size(), "output": snappedf(Surge.of(world).output_mult(), 0.01)})
	_watch_stuck(p, delta)


## Blocks at a shore in a row, the side Lumi is walking round the lake on, how long one walk along
## the shore lasts and how many blocks before he tries the other way round.
var _shore_run: int = 0
var _shore_side: float = 1.0
const SHORE_WALK_S: float = 3.5
## Once Lumi is walking round a lake, the shore ahead is seen this fast (6 s for anything else).
const SHORE_SEEN_S: float = 1.5
const SHORE_TURN_AFTER: int = 5


## No Hover Jets and water straight ahead of where Lumi is trying to go.
func _at_shore(p: Patch) -> bool:
	if not p.has_method("can_hover_water") or p.can_hover_water():
		return false
	var ahead: Vector3 = p.global_position + (_move - p.up() * _move.dot(p.up())).normalized() * 1.5
	return bool(p.call("_water_at", ahead))


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
				p.place_on_sphere(_base_at() + _base_at().normalized() * 0.3, p.forward())
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
	elif _watch_t > (SHORE_SEEN_S if _shore_run > 0 and _at_shore(p) else 6.0):
		_watch_t = 0.0
		_escapes += 1
		if _target_piece >= 0 and DevHooks.has("bot-debug"):
			var f: HexField = world.field
			print("[bot-esc] t=%.1f task=%s pos=%s piece=%d at %s size=%d embed=%.2f" % [_now() / 60.0, _task, str(p.global_position), _target_piece, str(f.piece_pos[_target_piece]), Pace.piece_size(f, _target_piece), f.piece_embed[_target_piece] if _target_piece < f.piece_embed.size() else -1.0])
		if DevHooks.has("bot-debug"):  # every escape: what it was doing, where, and what is in the way (B7 triage)
			var fwd: Vector3 = (_move - p.up() * _move.dot(p.up())).normalized()
			var wet: Array[int] = []
			for m: float in [1.5, 5.0, 15.0]:
				wet.append(int(bool(p.call("_water_at", p.global_position + fwd * m))))
			print("[bot-esc2] t=%.1f n=%d task=%s pos=%s cell=%d water_ahead(1.5/5/15m)=%s hover=%d piece=%d water_target=%d" % [_now() / 60.0, _escapes, _task,
				str(p.global_position.snappedf(0.1)), world.field.hex_at(p.global_position), str(wet), int(p.can_hover_water()), _target_piece, _water_target])
		if p.has_method("can_hover_water") and not p.can_hover_water():  # [v4bots] a lake in the way (item 54)
			var ahead: Vector3 = p.global_position + (_move - p.up() * _move.dot(p.up())).normalized() * 1.5
			if p.call("_water_at", ahead):
				_shore_blocks += 1
				_report["shore_blocks"] = _shore_blocks
				if _shore_blocks <= 12:
					print("[bot-shore] t=%.1f task=%s pos=%s: a lake in the way" % [_now() / 60.0, _task, str(p.global_position.snappedf(0.1))])
		# [pace2] Sidestep around the obstacle (perpendicular to where we were heading, alternating
		# sides, a little backwards) instead of a random direction that often points back into it.
		var head: Vector3 = Vector3(_move.x, 0, _move.z).normalized()
		_escape_side = -_escape_side
		_escape_dir = (Vector3(head.z, 0, -head.x) * _escape_side - head * 0.35).normalized()
		_escape_t = 1.6 + 0.4 * float(_escapes % 3)
		if _at_shore(p):
			# A lake is walked round, not bounced off: keep to one side along the shore, and try the
			# other side only after several blocks in a row (a person sees the way round at once).
			_shore_run += 1
			if _shore_run == 1:
				_shore_side = _escape_side
			elif _shore_run % SHORE_TURN_AFTER == 0:
				_shore_side = -_shore_side
			var flat: Vector3 = (_move - p.up() * _move.dot(p.up())).normalized()
			_escape_dir = (flat.cross(p.up()) * _shore_side - flat * 0.2).normalized()
			_escape_t = SHORE_WALK_S
		else:
			_shore_run = 0
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
		_goal_log.on_completed(world.goals, i, _now())
		_cadence.goal_done(_now())
		_progress()
		_event("goal", {"id": str(g["id"]), "tier": world.goals.tier_of(i), "n": world.goals.done_count()}))
	(world.goals as Goals).tier_changed.connect(func(tier: String, i: int) -> void:
		_event("goal_up", {"tier": tier, "id": str(world.goals.chain[i]["id"]) if i >= 0 else ""}))


func _haulers() -> int:
	return world.fleet.count("haulbug") if world.fleet else 0


func _at_base(p: Patch) -> bool:
	return p.global_position.distance_to(_bench_at()) < AT_BASE_R


## The workbench: the start site's bench anchor.
func _bench_at() -> Vector3:
	return world.bench_pos()


## [v4bots] Where the can refills: on hub ground only (Patch._handle_tools reads hex_hub). On the
## globe that is the one cell the scale stands on; the bench is in the next cell, where the can
## stays empty and the bot pushed at the bench until its stuck-escape fired (B7: 85 of 89 escapes).
func _water_at() -> Vector3:
	var d: Variant = world.get("depot")
	if _away():
		return _base_at()
	return (d as Node3D).global_position if d is Node3D else _bench_at()


# --- Patch tasks -------------------------------------------------------------------------

## The Maker seed tin in the greenhouse, once enough hexes are clean.
## How close to the seed tin Lumi stops (FirstSeed.near_tin reaches 2.2 m).
const TIN_STOP_M: float = 1.5
## How close the bot walks to a source step's spot, and how long it tries before giving the step
## a rest (a spot it cannot reach must not hold the whole run).
const SOURCE_STOP_M: float = 1.2
const SOURCE_TRY_S: float = 150.0
const SOURCE_REST_S: float = 120.0
var _source_rest_until: float = 0.0
var _source_step_seen: int = -1


## The source job of the city the readouts follow: walk to the spot of the step on offer and use
## it; stand still while the work runs. True while it has a step to do.
func _do_source(p: Patch) -> bool:
	var so: SliceOrbit = world.get("orbit") as SliceOrbit
	if so == null or so.sources == null or so.source_sites == null or not p.carried.is_empty() or _now() < _source_rest_until:
		return false
	var id: String = so.districts.focus_id()
	if not so.sources.is_open(id) or not so.sources.can_afford(id):
		return false
	var at: Variant = so.source_sites.target_pos(id)
	if at == null:
		return false
	if so.sources.is_building(id):
		# The part is being built: stand by where it will be ready. (A player would clean meanwhile;
		# the bot has no way back through a city's streets it can count on.)
		_set_task("source_wait")
		if not so.source_sites.in_reach(id):
			_go(p, at, SOURCE_STOP_M)
		return true
	_set_task("source")
	var seen: int = so.sources.steps_done()
	if seen != _source_step_seen:  # a step or a pickup done: the next one gets its own time
		_source_step_seen = seen
		_task_t = 0.0
	if so.sources.is_engaged(id):
		return true  # at work: stay in reach
	_go(p, at, SOURCE_STOP_M)
	if so.source_sites.in_reach(id) and _cooldown <= 0.0:
		_interact = true
		_cooldown = 0.6
	if _task_t > SOURCE_TRY_S:
		_source_rest_until = _now() + SOURCE_REST_S
		_event("source_unreached", {"district": id, "step": so.sources.step_index(id)})
	return true


func _do_tin(p: Patch) -> bool:
	var fs: FirstSeed = world.first_seed
	if fs == null or _away() or not fs.ready_to_find() or fs._tin == null or not fs._tin.visible:
		return false
	if not p.carried.is_empty():
		return false  # deliver first (interact would drop the bale)
	_set_task("tin")
	# Straight to the tin, stopping inside its reach. (The old stand point was a flat-world offset,
	# which on the globe can lie inside the greenhouse wall: the bot pushed at it for a minute.)
	_go(p, fs._tin.global_position, TIN_STOP_M)
	if fs.near_tin(p.global_position) and _cooldown <= 0.0:
		_interact = true
		_cooldown = 1.0
	return true


## A buried find the detector pings, or a wreck to clear and salvage: walk up and use it, as a
## person would on seeing the glint (systems/find_sites.gd).
const FIND_REACH_M: float = 22.0


func _do_find(p: Patch) -> bool:
	var fsites: FindSites = world.orbit.find_sites if world.orbit else null
	if fsites == null or not p.carried.is_empty():
		return false
	var job: Dictionary = fsites.nearest_job(p.global_position, FIND_REACH_M)
	if job.is_empty() or _skip_hex.has("find/" + str(job["id"])):
		return false
	_set_task("find")
	_go(p, job["pos"], float(job["reach"]) * 0.6)
	if _task_t > 40.0:
		_skip_hex["find/" + str(job["id"])] = true  # cannot get to it; leave it
		return false
	if OrbitUp.ground_dist(p.global_position, job["pos"]) < float(job["reach"]) and _cooldown <= 0.0:
		_interact = true
		_cooldown = 0.6
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
	_go(p, _bench_at(), 2.2)  # [v1guide] walk up to the bench
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


## Seconds Lumi has carried a part-full stack while still cleaning, and the most he will.
var _carry_hold_s: float = 0.0
const CARRY_HOLD_MAX_S: float = 40.0
## The garden's share of Lumi's time once it is open: a person tends between loads. Cubes come only
## from Lumi's own hands, so a bot that waters without end earns nothing.
const GARDEN_SHARE: float = 0.25
## Seeds held past which the bot plants even when its garden share is used up.
const SEEDS_PILE: float = 5.0
var _garden_s: float = 0.0
var _garden_open_s: float = -1.0


func _do_deliver(p: Patch) -> bool:
	if p.carried.is_empty():
		return false
	var full: bool = p.carried.size() >= p.carry_cap()
	if _haulers() > 0 or _away():
		# Away from the start yard there is no scale to walk to: the crew's Haul Bugs fetch them.
		# Haul Bugs take bales; set the stack down and get back to work.
		_drop_all(p)
		return false
	if not full and _nearest_loose(p) != null:
		return false
	# Room on the stack and junk still to press: fill the stack first, but never hold a bale long.
	if not full and _carry_hold_s < CARRY_HOLD_MAX_S and _pick_focus(p) >= 0:
		_carry_hold_s += _dt
		return false
	_carry_hold_s = 0.0
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
	# The bin body or the weigh plate, whichever is nearer: a loose load tips at either.
	var depot: Depot = world.depot
	var bin_at: Vector3 = depot.bin_world()
	var nearer_bin: bool = p.global_position.distance_to(bin_at) < p.global_position.distance_to(depot.global_position)
	_go(p, bin_at if nearer_bin else depot.global_position, 0.6)
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
		"hover_jets":  # [v4bots]
			_mark("hover_jets_s")
		"auto_compactor":
			_mark("auto_compactor_s")


## The next slow-start unlock worth buying now ("" = none): the Baler first, then Lift Strength.
func _pace_upgrade() -> String:
	for id: String in [Pace.UP_BALER, Pace.UP_LIFT]:
		if id == Pace.UP_LIFT and GameState.level_of(id) >= 1 and not _card_purchase().is_empty():
			continue  # the heavier lift can wait: the card's purchase comes first
		if Economy.upgrade_defs.has(id) and Economy.is_unlocked(id) and not Economy.is_maxed(id):
			if GameState.can_afford("cubes", Economy.upgrade_cost(id)):
				return id
			if id == Pace.UP_BALER:
				return ""  # save for the Baler
	return ""


## [pace] The helper / automation research a planner works toward once the base allows it.
func _pace_research_next() -> String:
	for id: String in ["salvage_logic", "conveyor", "auto_baler"]:
		if not Research.exists(id) or Research.has(id) or Research.is_active(id):
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
			if not Research.exists(id) or Research.has(id) or Research.is_active(id):
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
	if _haulers() > 0 or _away() or p.carried.size() >= p.carry_cap():
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
## How far Lumi walks off his work to a buried-part ping, and how far before the first hex is clean.
const DIG_REACH_M: float = 14.0
const DIG_REACH_FIRST_HEX_M: float = 6.0


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
		# The card says "clean the glowing hex": until the first hex is clean a far ping waits
		# (one walk to a ping 19 m off cost 28 s of the first 86 in a Nov 11 run).
		var reach: float = DIG_REACH_M if world.field.cleaned_count > 0 else DIG_REACH_FIRST_HEX_M
		if pp.distance_to(p.global_position) > reach:
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
	if world.field.is_clean(h):
		g.ensure_hex(h)  # [v3clear] the globe's garden makes a clean cell's slots on demand
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


## The hex to plant: a quarter of a hex's open slots makes it Planted (stage 2), so hexes under
## that come first, nearest Lumi; the hex being planted is kept until it has its quarter; then the
## rest of each hex is filled (its life, and so stages 3 to 5, counts every open slot).
func _pick_plant_hex(g: Garden) -> int:
	var here: Vector3 = world.patch.global_position
	if _plant_hex >= 0 and _area_set().has(_plant_hex) and not _plant_skip.has(_plant_hex):
		var pc0: Vector2i = _hex_planted(g, _plant_hex)
		if pc0.x < pc0.y and (pc0.x * 4 < pc0.y or _now() < _plant_scan_at):
			return _plant_hex
	elif _now() < _plant_scan_at:
		return -1  # nothing to plant at the last look: look again in a moment
	_plant_scan_at = _now() + PLANT_SCAN_S
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	var best: int = -1
	var best_s: float = INF
	for h: int in _hexes():
		if not _land(h) or not world.field.is_clean(h) or _plant_skip.has(h):
			continue
		var pc: Vector2i = _hex_planted(g, h)
		if pc.y == 0 or pc.x >= pc.y:
			continue
		var s: float = world.field.hex_center(h).distance_to(here) - (PLANT_QUARTER_PULL_M if pc.x * 4 < pc.y else 0.0)
		if hl != null and hl.level_of(h) == 2:
			s -= PLANT_GROW_PULL_M  # planted but not Growing yet: more plants raise its life
		if s < best_s:
			best_s = s
			best = h
	_plant_hex = best
	return best


## Metres by which a hex short of its quarter (stage 2) is preferred for planting, and how often
## the whole city is looked over for the next hex (game seconds).
const PLANT_QUARTER_PULL_M: float = 150.0
## Metres by which a Planted hex that is not Growing yet is preferred (the city's next stage waits
## on its last hexes).
const PLANT_GROW_PULL_M: float = 100.0
const PLANT_SCAN_S: float = 3.0
var _plant_scan_at: float = 0.0
## Hexes whose open slots were all out of reach (hex -> true).
var _plant_skip: Dictionary = {}


func _drips() -> int:
	if world.fleet == null:
		return 0
	var n: int = world.fleet.count("drip")
	for r: Robot in world.fleet.robots():
		if r.type_id == "multibot" and r.job == "water":
			n += 1
	return n


## Thirstiest planted slot Patch should water (none once Drips cover the garden).
## [M3-06] A planted hex that is not growing yet and can take a watering burst now.
func _burst_wanted(g: Garden, hid: int) -> bool:
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	return hl != null and hl.level_of(hid) == 2 and Tending.burst_ready(g, hid)


func _thirsty_slot(g: Garden, p: Patch) -> int:
	var drips: int = _drips()
	var best: int = -1
	var best_score: float = INF
	var dry: int = 0
	var planted: int = 0
	var limit: float = 25.0 if drips == 0 else 0.0
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	var here: Dictionary = _area_set()
	for s: int in g.slot_species.size():
		if g.slot_species[s] < 0 or not here.has(g.slot_hex[s]):
			continue  # unplanted, or in another city (a flight away)
		planted += 1
		var w: float = g.slot_water[s]
		if w <= 0.0:
			dry += 1
		# [M3-06] A planted hex not yet growing whose burst is ready: a pour pushes it on now.
		var push: bool = hl != null and _burst_wanted(g, g.slot_hex[s])
		if w > limit and not push:
			continue
		var sc: float = (0.0 if push else w * 2.0) + g.slot_pos[s].distance_to(p.global_position)
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
	if _garden_open_s < 0.0:
		_garden_open_s = _now()
	# The share holds while the city still has junk; a clean city is all garden (the wider land
	# round it is cleaned only when there is nothing to tend).
	if _garden_s > GARDEN_SHARE * (_now() - _garden_open_s) and _pick_focus(p) >= 0 and _city_has_work(_hexes(), false):
		# Tended enough for now: back to the junk. Once the city is mostly clean (its first stage),
		# seeds piling up are planted anyway: a patch is one quick action and nothing else turns
		# seeds into regrowth. Before that the cleaning is what moves the city on.
		var d: Districts = _districts()
		var stage1: bool = d == null or _area_city == "" or d.stage_of(_area_city) >= 1
		var h: int = _pick_plant_hex(g) if stage1 and GameState.get_currency("seeds").to_float() >= SEEDS_PILE else -1
		if h >= 0 and _plant_task(p, g, h):
			_garden_s += _dt
			return true
		if p.tool != Patch.Tool.SCOOP:
			p.set_tool(Patch.Tool.SCOOP)
		return false
	if _garden_task(p, g):
		_garden_s += _dt
		return true
	return false


func _garden_task(p: Patch, g: Garden) -> bool:
	var cap: float = p.water_cap()
	# Refill the can at the base barrel (anywhere in the hub hex).
	if _refilling:
		if p.water >= cap - 0.5:
			_refilling = false
		else:
			_set_task("refill")
			_go(p, _water_at(), 0.5)
			return true
	if _water_target >= 0 and (g.slot_species[_water_target] < 0 or (g.slot_water[_water_target] > 50.0 and not _burst_wanted(g, g.slot_hex[_water_target]))):
		_water_target = -1
	if _water_target < 0:
		_water_target = _thirsty_slot(g, p)
	var plant_h: int = _pick_plant_hex(g) if GameState.get_currency("seeds").to_float() >= 1.0 else -1
	# Seeds first (each patch moves a hex toward its next stage); water first only for a burst.
	if _water_target >= 0 and (plant_h < 0 or _burst_wanted(g, g.slot_hex[_water_target])):
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
	return plant_h >= 0 and _plant_task(p, g, plant_h)


## Walks to the nearest open slot of hex `h` and sets a patch there. False when it has none left.
func _plant_task(p: Patch, g: Garden, h: int) -> bool:
	var best: int = -1
	var best_d: float = INF
	for s: int in g.hex_slots[h]:
		if g.slot_species[s] >= 0 or _ignore_piece.has(-10 - s) or not g.plantable(s):
			continue
		var d2: float = g.slot_pos[s].distance_to(p.global_position)
		if d2 < best_d:
			best_d = d2
			best = s
	if best < 0:
		_plant_skip[h] = true  # every open slot left here was out of reach: plant elsewhere
		_plant_hex = -1
		_plant_scan_at = 0.0
		return false
	_set_task("plant")
	p.set_tool(Patch.Tool.PLANT)
	var dd: float = _go(p, g.slot_pos[best], 0.9)
	if dd < 1.6:
		_scoop = true
		_move = Vector3.ZERO
	if _task_t > 15.0:
		if DevHooks.has("bot-debug"):
			print("[bot-plant] t=%.1f slot=%d hex=%d dist=%.2f free_near=%d seeds=%.0f pos=%s" % [_now() / 60.0, best, h, dd,
				g.free_slot_near(p.global_position, p.forward()), GameState.get_currency("seeds").to_float(), str(p.global_position.snappedf(0.1))])
		_ignore_piece[-10 - best] = true
		_task_t = 0.0
	return true


# --- Mastery: some hand work on each new kind ---------------------------------------------

## A kind worked with a tool (misting, cleansing plants) that robots may not touch until Lumi has
## learnt it: the bot works the nearest hex of it by hand until the first level. Scooped kinds
## need no step of their own: _pick_focus puts their hexes first. True while it has work here.
func _do_learn(p: Patch) -> bool:
	var so: SliceOrbit = world.get("orbit") as SliceOrbit
	var kind: String = AutoplayMastery.kind_to_learn(so.mastery, so.pollution, true) if so != null else ""
	if kind == "":
		_learn_hex = -1
		return false
	var pol: Pollution = so.pollution
	var kd: Dictionary = pol.kind(kind)
	var cost: Dictionary = kd.get("cost", {})
	if not cost.is_empty() and GameState.get_currency(str(cost["currency"])).to_float() < 1.0:
		return false
	if p.compartment.ratio(p.capacity()) >= 0.9:
		return false  # the chest is full of it: bale first (_do_clean)
	var with_water: bool = str(kd.get("tool", "")) == "water"
	if with_water and (_refilling or p.water < 1.5):
		_refilling = p.water < p.water_cap() - 0.5
		if _refilling:
			_set_task("refill")
			_go(p, _water_at(), 0.5)
			return true
	if _learn_hex < 0 or pol.held_left(_learn_hex, kind) <= Pollution.LEFT_EPS:
		_learn_hex = -1
		_learn_scan_t -= _dt
		if _learn_scan_t > 0.0:
			return false
		_learn_scan_t = LEARN_SCAN_S
		var best_d: float = INF
		for h: int in _hexes():
			if _land(h) and pol.held_left(h, kind) > Pollution.LEFT_EPS and not _skip_hex.has(h):
				var d: float = world.field.hex_center(h).distance_to(p.global_position)
				if d < best_d:
					best_d = d
					_learn_hex = h
		if _learn_hex < 0:
			return false
	_set_task("learn")
	p.set_tool(Patch.Tool.WATER if with_water else Patch.Tool.PLANT)
	if _go(p, world.field.hex_center(_learn_hex), 1.0) < LEARN_WORK_M:
		_scoop = true
	if _task_t > 90.0:  # cannot get there, or nothing is coming off: try another hex
		_skip_hex[_learn_hex] = true
		_learn_hex = -1
		_task_t = 0.0
	return true


# --- Cleaning --------------------------------------------------------------------------

## The unfinished hex to work: keep the current one until it flips; else the started or nearest one.
func _pick_focus(p: Patch) -> int:
	var f: HexField = world.field
	if _focus_hex >= 0 and not f.is_clean(_focus_hex) and not _skip_hex.has(_focus_hex):
		return _focus_hex
	var best: int = -1
	var best_s: float = INF
	var base: Vector3 = (world.depot as Depot).bin_world() if world.depot and not _away() else _base_at()
	# A scooped kind robots are shut out of until Lumi learns it: its hexes come first.
	var so: SliceOrbit = world.get("orbit") as SliceOrbit
	var learn: String = AutoplayMastery.kind_to_learn(so.mastery, so.pollution, false) if so != null else ""
	# With the hover skirt on, lakes are ground too (their floating waste is a city's kind).
	var wet_ok: bool = p.has_method("can_hover_water") and p.can_hover_water()
	var area: PackedInt32Array = _hexes()
	if not _city_has_work(area, wet_ok):
		area = _wide_area
	for h: int in area:
		var ground: bool = _land(h) or (wet_ok and world.field.hex_hub[h] == 0 and f.is_water(h))
		if not ground or f.is_clean(h) or _skip_hex.has(h) or f.locked.has(h):
			continue
		var c: Vector3 = f.hex_center(h)
		# Near the bin first (short tips), then near Lumi, and finish what is started. The first term
		# was the flat world's distance from the base at the origin; on the globe that is the depot.
		var s: float = c.distance_to(base) + 0.6 * c.distance_to(p.global_position) - 25.0 * f.removed_fraction(h)
		if learn != "" and learn in so.pollution.kinds_left(h):
			s -= LEARN_PULL_M
		if s < best_s:
			best_s = s
			best = h
	if best < 0 and not _skip_hex.is_empty():
		for k: Variant in _skip_hex.keys():
			if int(k) >= 0:
				_skip_hex.erase(k)
	_focus_hex = best
	return best


## Whether the city in play still has a hex to clean (else the bot works the land round it).
func _city_has_work(area: PackedInt32Array, wet_ok: bool) -> bool:
	var f: HexField = world.field
	for h: int in area:
		if (_land(h) or (wet_ok and f.hex_hub[h] == 0 and f.is_water(h))) and not f.is_clean(h) and not _skip_hex.has(h) and not f.locked.has(h):
			return true
	return false


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
		elif p.global_position.distance_to(_water_at()) > 4.0:
			_go(p, _water_at(), 1.0)
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
	_set_mix()
	_paint_search()
	if _away():
		_bench_trip = false  # the only workbench is in the start yard: a home trip (_do_travel) goes there
		_want_home()
		return
	var want: Dictionary = _shopping_list()
	if not _at_base(p):
		# Head back when something worth the walk is affordable (or the trip home was for the bench).
		if (want.get("trip", false) or _travel.home_trip) and _now() - _last_bench_t > 20.0:
			_bench_trip = true
		return
	_last_bench_t = _now()
	if _travel.home_trip:
		_travel.shopped(_now())
		_event("shopped", {})
	var cp: Camp = Camp.of(world)  # [v3clear] at the bench a person repairs it first (the checklist's step 1)
	if cp and not Camp.bench_ok():
		cp.repair_now()
	_shop(want)


## [beat] The whole-game layer: campaign milestones and rocket trips (tools/autoplay_campaign.gd).
func _campaign(_p: Patch) -> void:
	if bool(world.get("launching")):
		return
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
	if _now() < 30.0 or DevHooks.has("no-travel") or _districts() != null:
		return  # settle in after landing; a planet with cities travels by _do_travel
	var to: int = AutoplayCampaign.next_hub(world)
	if to >= 0 and world.rocket_status() == "" and p_ok(_p) and OrbitSites.of(world).can_hop_to_hub(to):
		_event("launch", {"from": int(world.hub_index), "to": to, "kind": world.planet.frontier_kind(to)})
		AutoplayCampaign.mark("launch_%d_s" % GameState.districts.size(), _now())
		OrbitSites.of(world).hop_to_hub(to)


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
	var card: Dictionary = _card_purchase()
	if not card.is_empty():
		# The step on the card is a purchase: a player saves for it and walks back when it is paid for.
		out["reserve"] = maxf(float(out["reserve"]), float(card.get("cubes", 0.0)))
		if GameState.can_afford_all(card):
			out["trip"] = true
	if not nxt.is_empty() and hub.block_reason() == "":
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
	if BenchTiers.can_buy(world):
		out["trip"] = true  # a new bench tab is on offer and paid for: nobody leaves that waiting
	if not _rig_tools().is_empty():
		out["trip"] = true  # a city's tool is waiting at the bench: without it that city's waste stays shut
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


## The cost of what the objective card asks Lumi to buy right now, when it is the signal tower or
## a workbench tier that waits only for its price ({} otherwise).
func _card_purchase() -> Dictionary:
	var obj: Objectives = world.get("objectives") as Objectives
	if obj == null:
		return {}
	match str(obj.current().get("type", "")):
		"tower":
			return SignalTower.next_cost() if SignalTower.tier() < SignalTower.max_tier() else {}
		"bench":
			return BenchTiers.next_cost() if BenchTiers.block_reason(world) == "" else {}
	return {}


## The tools at the bench that Lumi needs and has not fitted (systems/rigs.gd): the tools for the
## kinds of every open city, the city the bot is heading for first, then the newest city and its
## newest kind first, so where two tools share a slot the one for the city in play wins.
func _rig_tools() -> Array[String]:
	var rigs: Rigs = Rigs.of(world)
	var r: Restoration = Restoration.active()
	if rigs == null or r == null or r.districts == null:
		return []
	var kinds: Array = []
	var open_ids: Array[String] = r.districts.ids().filter(func(id: String) -> bool: return r.districts.is_unlocked(id))
	open_ids.reverse()
	# The city the bot is heading for comes first: where two tools share a slot, its kind wins.
	var target: String = AutoplayTravel.target_city(r.districts, _sources())
	if target != "":
		open_ids.erase(target)
		open_ids.push_front(target)
	for id: String in open_ids:
		var listed: Array = (r.districts.spec_of(id).get("pollution", []) as Array).duplicate()
		listed.reverse()
		for kind: Variant in listed:
			if not kinds.has(kind):
				kinds.append(kind)
	return rigs.tools_wanted(kinds)


func _shop(want: Dictionary) -> void:
	var fleet: Fleet = world.fleet
	# The city's tool first: it is free and nothing in that city's new waste moves without it.
	var rigs: Rigs = Rigs.of(world)
	for tool_id: String in _rig_tools():
		if rigs.fit(tool_id):
			_event("rig_fit", {"module": tool_id, "slot": rigs.slot_of(tool_id)})
	# A build a goal on show asks for, before the cubes go to upgrades.
	_build_for_goals()
	# 0) [onboard] The Signal Tower: the first tier right away (WREN), later tiers with the base level.
	# When the card asks for it, it is bought the moment it is paid for; otherwise with cubes to spare.
	var tower: SignalTower = world.get_node_or_null("SignalTower") as SignalTower
	var obj_now: Objectives = world.get("objectives") as Objectives
	var tower_asked: bool = obj_now != null and str(obj_now.current().get("type", "")) == "tower"
	if tower and SignalTower.tier() < mini(SignalTower.max_tier(), maxi(1, int(GameState.world.get("hub_level", 1)))) \
			and GameState.can_afford_all(SignalTower.next_cost(), 1.0 if tower_asked else 1.5) and (tower_asked or _keeps_robot_parts(SignalTower.next_cost(), want)):
		GameState.spend_all(SignalTower.next_cost())
		tower.raise()
		_mark("tower_s")
		_event("signal_tower", {"tier": SignalTower.tier()})
	# 0b) [v1guide] The workbench tiers (ui/bench_tiers.gd): the Bots / Research / Requests tabs only
	# open by upgrading the bench, so a player buys the next tier as soon as it's offered and paid.
	if BenchTiers.can_buy(world) and BenchTiers.buy(world):
		_progress()
		_mark("bench_%d_s" % BenchTiers.tier())
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
	# Not a dear one while the card asks for a purchase: a player saves for what the step says.
	var gu: String = _goal_upgrade()
	var card_cubes: float = float(_card_purchase().get("cubes", 0.0))
	if gu != "" and (card_cubes <= 0.0 or Economy.upgrade_cost(gu).to_float() <= card_cubes * LEAK_OF_RESERVE):
		Economy.buy_upgrade(gu, 1)
	# 2b) [pace] The slow-start unlocks (Baler, Lift Strength) before anything else.
	var pu: String = _pace_upgrade()
	if pu != "":
		Economy.buy_upgrade(pu, 1)
	# 2b2) [v4calm] Repair Glim (the workbench Build entry) as soon as it's listed and paid for.
	if HubBuilds.listed(world, GlimDirector.BUILD_ID) and str(HubBuilds.entry(world, GlimDirector.BUILD_ID)["reason"]) == "" \
			and HubBuilds.build(world, GlimDirector.BUILD_ID):
		_event("build", {"id": "glim"})
		_mark("glim_repair_s")
	# 2c) [buddy] Glim's Lantern and Hex Scanner when affordable (1.5x margin: never starves the core loop).
	for gid: String in ["light", "scan"]:
		if Glim.block_reason(gid) == "" and GameState.can_afford_all(Glim.next_cost(gid), 1.5) and _keeps_robot_parts(Glim.next_cost(gid), want) and Glim.buy(gid):
			var gd: GlimDirector = GlimDirector.of(world)
			if gd:
				gd.refresh()
			_event("glim_" + gid, {"tier": Glim.tier(gid)})
	# 3) Robots ([ui2] Parts + cubes; keep the next base level's Parts unless the robot can't wait).
	var robot: String = str(want.get("robot", "")) if fleet != null and BenchTiers.tab_open("bots") else ""  # [orbB] no Fleet on the globe yet (orbC)  # [v1guide] the Bots tab is open
	var built_n: int = 0
	while robot != "" and built_n < ROBOTS_PER_VISIT:  # a player at the Bots tab builds what is paid for
		var hub_save: float = 0.0 if _crew_first() else float(want.get("hub_save", 0.0))
		var spare: float = GameState.get_currency("cubes").to_float() - fleet.build_cost(robot).to_float()
		var must: bool = _robot_goal(robot) or _essential(robot)
		var ok: bool = hub_save <= 0.0 or spare >= hub_save or must
		ok = ok and (must or hub_save <= 0.0 or _mats_spare({"parts": fleet.build_parts(robot).to_float()}, false))
		if not ok or not fleet.can_build(robot):
			break
		var at: Vector3 = world.upgrades.build_at.call()
		fleet.build(robot, at)
		built_n += 1
		robot = _next_robot()
	# The Assembler as soon as it is on offer: from then on the line builds the crew.
	if RobotChain.of(world) != null and RobotChain.of(world).listed() and HubBuilds.build(world, RobotChain.BUILD_ID):
		_progress()
		_event("assembler", {})
	# A bigger crew before a better one: Parts go to tiers and crew upgrades only when the crew is
	# full. While there is room they are kept for the next robot, whose plans may be on the way:
	# in the first city Parts are scarce, and 8 of them on a faster Haul Bug put the first Scoopie
	# back by six minutes.
	var crew_full: bool = fleet != null and not fleet.has_room()
	if crew_full and BenchTiers.tab_open("bots"):
		_crew_upgrade(fleet)
	for t: String in (Economy.robot_order if crew_full and BenchTiers.tab_open("bots") else []):  # [orbB] [v1guide]
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
			var force: bool = id == "recycler" or (id == "conveyor" and (Research.has("recycler") or Research.is_active("recycler")))
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
		reserve = maxf(float(want.get("hub_save", 0.0)), float(_card_purchase().get("cubes", 0.0)))  # the card's purchase is still saved for
	var prn: String = _pace_research_next()
	if prn != "":
		reserve = maxf(reserve, Research.cost(prn).to_float())  # [pace]
	if not Pace.baler_unlocked() and Economy.is_unlocked(Pace.UP_BALER):
		reserve = maxf(reserve, Economy.upgrade_cost(Pace.UP_BALER).to_float())  # [pace] a person saves for the Baler
	if not BenchTiers.next_def().is_empty() and BenchTiers.block_reason(world) == "":
		reserve = maxf(reserve, float(BenchTiers.next_cost().get("cubes", 0.0)))  # [v1guide] a person saves for the next bench tier
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


## Past the first city the crew is the engine and robots are paid in Parts: the cubes saved for the
## next base level no longer hold a robot back (the base matters again when its level caps the crew).
func _crew_first() -> bool:
	var d: Districts = _districts()
	var fleet: Fleet = world.fleet
	if d == null or fleet == null or d.unlocked_count() < 2:
		return false
	var cap: Dictionary = Economy.robot_cfg.get("crew_cap", {})
	var by_base: Array = cap.get("by_base_level", [])
	var lv: int = int(world.hub.level)
	return by_base.is_empty() or lv > by_base.size() or fleet.robot_total() + 1 < int(by_base[lv - 1])


## Whether paying `cost` leaves the Parts for the robot the bot is working toward: from the second
## city on Parts are the crew, so side purchases (the tower, Glim) wait for them.
func _keeps_robot_parts(cost: Dictionary, want: Dictionary) -> bool:
	var robot: String = str(want.get("robot", ""))
	if robot == "" or world.fleet == null or not cost.has("parts"):
		return true
	return GameState.get_currency("parts").to_float() - float(cost["parts"]) >= world.fleet.build_parts(robot).to_float()


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
	var need: Dictionary = _hub_need().duplicate()
	need["parts"] = float(need.get("parts", 0.0)) + _job_parts()
	for k: String in cost:
		if k == "cubes":
			continue
		var have: float = GameState.get_currency(k).to_float()
		if have - float(cost[k]) < float(need.get(k, 0.0)):
			return false
	return true


## Parts the next step of an open source job still waits for (a player saves for the rocket's part
## before a crew upgrade).
func _job_parts() -> float:
	var src: Sources = _sources()
	if src == null:
		return 0.0
	var out: float = 0.0
	for id: String in src.ids():
		if src.is_open(id) and not src.is_shut(id) and not src.can_afford(id):
			out += float((src.current_step(id).get("cost", {}) as Dictionary).get("parts", 0.0))
	return out


## A base build a goal on show asks for (its guide names the Build row) is built once it is
## affordable, as a player following the goal would.
func _build_for_goals() -> void:
	var gl: Goals = world.get("goals")
	if gl == null:
		return
	for i: int in gl.current():
		var row: Array = GoalGuide.target(world, gl.chain[i]).get("row", [])
		if row.size() < 2 or str(row[0]) != "build":
			continue
		var id: String = str(row[1])
		if HubBuilds.listed(world, id) and str(HubBuilds.entry(world, id)["reason"]) == "" and HubBuilds.build(world, id):
			_event("build", {"id": id})


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
			if Research.is_active(want):
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
		# [v4bots] The Skimmer's plans come mid-save for base 2 (Research story_unlocks): the card
		# says base 2, so the bot saves first, as a player following it would.
		return type_id != "skimmer" or int(GameState.world.get("hub_level", 1)) >= 2
	match type_id:
		"drip":
			return _target_stage() >= 1 and _drips() * HEXES_PER_DRIP < _city_gardens()
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


## The cheapest crew upgrade priced in Parts, for a type the crew has, bought when the Parts are
## spare (the base's needs are kept).
func _crew_upgrade(fleet: Fleet) -> void:
	var best: String = ""
	var best_c: float = INF
	for id: String in Economy.upgrade_order:
		var type_id: String = str(Economy.upgrade_defs[id].get("robot", ""))
		if type_id == "" or fleet.count(type_id) == 0 or Economy.upgrade_currency(id) != "parts":
			continue
		if not Economy.is_unlocked(id) or Economy.is_maxed(id):
			continue
		var c: float = Economy.upgrade_cost(id).to_float()
		if c < best_c:
			best_c = c
			best = id
	if best != "" and GameState.get_currency("parts").to_float() >= best_c and _mats_spare({"parts": best_c}, false):
		if Economy.buy_upgrade(best, 1) > 0:
			_progress()
			_event("crew_upgrade", {"id": best, "level": GameState.level_of(best)})


## Cheapest useful upgrade affordable while keeping `reserve` cubes (or, with leak, under 15% of the purse).
const LEAK_OF_RESERVE: float = 0.2


func _best_upgrade(reserve: float, leak: bool = true) -> String:
	var cubes: float = GameState.get_currency("cubes").to_float()
	# [v4bots] Stopped at a shore (the one-time hint): Hover Jets first, as a player would.
	if GameState.flags.get("shore_hint", false) and Economy.is_unlocked("hover_jets") and not Economy.is_maxed("hover_jets") \
			and Economy.upgrade_cost("hover_jets").to_float() <= cubes:
		return "hover_jets"
	var best: String = ""
	var best_c: float = INF
	for id: String in Economy.upgrade_order:
		if not Economy.is_unlocked(id) or Economy.is_maxed(id) or not _useful_upgrade(id):
			continue
		if Economy.upgrade_currency(id) != "cubes":
			continue  # the crew's upgrades cost Parts: _crew_upgrade buys those
		var c: float = Economy.upgrade_cost(id).to_float()
		if c < best_c:
			best_c = c
			best = id
	if best == "" or best_c > cubes:
		return ""
	# While saving for something, a person still picks up the cheap levels: under 15% of the purse,
	# or under a fifth of what is being saved for.
	if cubes - best_c >= reserve or (leak and best_c <= maxf(cubes * 0.15, reserve * LEAK_OF_RESERVE)):
		return best
	return ""


## The bot keeps one parts finder for every this many robots.
const FINDER_ONE_IN: int = 6
## Planted hexes one watering robot is bought for (it walks between them).
const HEXES_PER_DRIP: int = 8
## Cleaners per planting robot once seeds pile up, and planted hexes per planting robot.
const SCOOPIES_PER_SEEDLING: int = 4
const HEXES_PER_SEEDLING: int = 16
## Robots the bot builds in one visit to the Bots tab, at most.
const ROBOTS_PER_VISIT: int = 6


## The robot to work toward next (research done, crew room), or "".
func _next_robot() -> String:
	var fleet: Fleet = world.fleet
	if fleet == null:
		return ""
	var seeds_on: bool = world.garden != null and world.garden.unlocked()
	var scoop: int = fleet.count("scoopie")
	var haul: int = fleet.count("haulbug")
	var gardens: int = _city_gardens()
	var order: Array[String] = []
	# Nearly all land junk gone: no more cleaners or haulers (the lake still wants a Skimmer).
	var late: bool = _land_left_frac() < 0.12
	var saving: bool = not _hub_need().is_empty() and not _hub_mats_short() and not _crew_first()
	if AutoplayCampaign.frontier_kid(world) == "sunken_city" and _lake_dirty() and fleet.count("skimmer") < 14:
		order.append("skimmer")  # [beat] the flooded city is skimmed, not scooped
	# Planters and waterers once the city has its first stage: before that its stage waits on
	# cleaning, and their Parts buy cleaners. A planter for every two planted-hex waterers' worth
	# of garden comes first: a hex's life counts every open slot, more than Lumi's patches fill.
	var planting: bool = seeds_on and _target_stage() >= 1
	if planting and fleet.count("seedling") * HEXES_PER_SEEDLING < maxi(1, gardens) and GameState.get_currency("seeds").to_float() > 50.0:
		order.append("seedling")
	if seeds_on and gardens > 0 and _drips() * HEXES_PER_DRIP < gardens and _target_stage() >= 1:
		order.append("drip")
	if haul == 0:
		order.append("haulbug")  # the first helper carries the bales, so Lumi stays at the work
	if scoop == 0:
		order.append("scoopie")
	if haul * 2 < scoop:
		order.append("haulbug")
	# A parts finder for every FINDER_ONE_IN robots, once its plans are in (the default build mix).
	var finder: String = str((Economy.robot_cfg.get("chain", {}) as Dictionary).get("finder", ""))
	if finder != "" and Research.robot_unlocked(finder) and fleet.count(finder) * FINDER_ONE_IN <= fleet.robot_total():
		order.append(finder)
	if planting and fleet.count("seedling") == 0 and GameState.get_currency("seeds").to_float() > 8.0:
		order.append("seedling")
	if planting and fleet.count("seedling") * SCOOPIES_PER_SEEDLING < scoop and GameState.get_currency("seeds").to_float() > 50.0:
		order.append("seedling")  # seeds piling up: a planter for every few cleaners
	order.append("scoopie")
	if scoop >= 2 and fleet.count("skimmer") == 0 and _lake_dirty():
		order.append("skimmer")
	if seeds_on:
		if _target_stage() >= 1:
			order.append("drip")
	order.append("multibot")
	if haul < scoop:
		order.append("haulbug")
	if finder != "" and fleet.count(finder) == 0:
		order.push_front(finder)  # the first parts finder starts the chain: the crew grows from what it digs up
	for t: String in order:
		if not Research.robot_unlocked(t) or fleet.join_crew(t) == "":
			continue
		if late and (t == "scoopie" or (t == "haulbug" and haul > 0)):
			continue
		if saving and not _essential(t) and not _robot_goal(t):
			continue  # saving for the base: only the robots that can't wait
		return t
	return ""


## Planted hexes (stage 2 and up) of the city in play: what its watering robots have to keep wet.
## A finished city's garden keeps its own waterers; the next city's needs are its own.
func _city_gardens() -> int:
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	if hl == null:
		return 0
	if _now() - _gardens_t < 5.0:
		return _gardens_n
	_gardens_t = _now()
	_gardens_n = 0
	for h: int in _target_cells():
		if hl.level_of(h) >= 2:
			_gardens_n += 1
	return _gardens_n


## The regrowth stage of the city the bot is heading for (5 when there are no cities).
func _target_stage() -> int:
	var d: Districts = _districts()
	var target: String = AutoplayTravel.target_city(d, _sources()) if d != null else ""
	return d.stage_of(target) if target != "" else Districts.MAX_STAGE


## The hexes of the city the bot is heading for (the one it stands in, unless it is only home for
## the bench): robots bought at the bench are for that city.
func _target_cells() -> PackedInt32Array:
	var d: Districts = _districts()
	var target: String = AutoplayTravel.target_city(d, _sources()) if d != null else ""
	if target == "" or target == _area_city:
		return _hexes()
	return d.cells_of(target)


var _gardens_t: float = -100.0
var _gardens_n: int = 0


## Share of the land junk volume still on the ground.
func _land_left_frac() -> float:
	var f: HexField = world.field
	var left: float = 0.0
	var total: float = 0.0
	for h: int in _target_cells():
		if _land(h):
			total += f.hex_total[h]
			if not f.is_clean(h):
				left += f.hex_left[h]
	return left / maxf(total, 1.0)


func _lake_dirty() -> bool:
	var f: HexField = world.field
	for h: int in _target_cells():
		if f.is_water(h) and not f.is_clean(h):
			return true
	return false


## [M3-06] Research costs stock once and field data, which the work earns. A node already paid
## for is free to pick again (its bar is kept); a new one is bought when its cubes leave what the
## story card is saving for, or cost no more than a fifth of it (as other side purchases), and the
## helper / automation / garden unlocks as soon as they are paid.
func _research_ok(id: String) -> bool:
	if Research.is_paid(id):
		return true
	var c: float = Research.cost(id).to_float()
	var cubes: float = GameState.get_currency("cubes").to_float()
	if (id in ["salvage_logic", "conveyor", "auto_baler"] or id in PACE_GARDEN_CHAIN) and cubes >= c:
		return true  # [pace] the helper and automation unlocks come before saving for base 3
	var card: float = float(_card_purchase().get("cubes", 0.0))
	return cubes >= c and (c <= card * LEAK_OF_RESERVE or cubes - c >= card)


## One node at a time. With one running the bot only switches for an on-screen goal (the running
## node keeps its bar); with none it takes the goal's node, the helper unlock, a paused node, then
## the priority list.
func _research_pick() -> String:
	if not BenchTiers.tab_open("research"):  # [v1guide] the Research tab opens with the workbench's Mk III
		return ""
	var gr: String = _goal_research()  # [pace2] the goal on screen first
	if gr != "":
		return gr
	if not Research.active().is_empty():
		return ""
	var need: String = _pace_research_next()  # [pace] save for the helper / automation unlock
	if need != "" and _research_ok(need) and Research.can_start(need):
		return need
	var paused: String = ""
	for id: String in Research.ids():
		if Research.status(id) == "paused" and (paused == "" or FieldData.left(id) < FieldData.left(paused)):
			paused = id
	if paused != "":
		return paused
	var prio: Array[String] = AutoplayCampaign.research_first(world)
	prio.append_array(RESEARCH_PRIORITY)
	for id: String in prio:
		if Research.exists(id) and Research.can_start(id) and _research_ok(id):
			return id
	var best: String = ""
	var best_c: float = INF
	for id: String in Research.ids():
		if Research.can_start(id) and _research_ok(id) and Research.cost(id).to_float() < best_c:
			best_c = Research.cost(id).to_float()
			best = id
	return best


## Research bookkeeping, from the moment the Research tab exists: idle time (nothing running) and
## starved time (idle while a node is open to start).
func _track_research(dt: float) -> void:
	if not BenchTiers.tab_open("research"):
		return
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


## The most hexes in the cleaners' zone: a hex or so per cleaner, so a big crew is not crowded
## onto a few hexes.
const ZONE_MAX_HEXES: int = 60


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
	var want_n: int = clampi(2 + cleaners, 3, ZONE_MAX_HEXES)
	var zone_goal: int = _zone_goal_target()
	want_n = maxi(want_n, zone_goal)
	if cleaners == 0 and zone_goal == 0:
		return
	var cand: Array = []
	for h: int in _hexes():
		if _land(h) and not f.is_clean(h) and h != _focus_hex:
			cand.append(h)
	var o: Vector3 = _base_at()  # [v3qa] nearest the base first
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


# --- The whole planet: cities, travel, the cadence table, stalls --------------------------------

## Where to be and when to fly (tools/autoplay_travel.gd), the per-city cadence table
## (tools/autoplay_cadence.gd) and the stall watch (tools/autoplay_stall.gd).
var _travel := AutoplayTravel.new()
var _stall := AutoplayStall.new()
var _cadence := AutoplayCadence.new()
var _area_city: String = "?"
var _wide_area := PackedInt32Array()
var _ended: bool = false
var _mix: Dictionary = {}


func _hook_whole_game() -> void:
	_hook(EventBus.district_entered, func(id: String) -> void:
		_cadence.arrive(id, _now(), _crew())
		_progress()
		_event("arrive", {"city": id, "crew": _crew()}))
	_hook(EventBus.district_unlocked, func(id: String) -> void:
		_progress()
		_event("city_open", {"city": id}))
	_hook(EventBus.district_stage_changed, func(id: String, stage: int) -> void:
		_cadence.stage_reached(id, stage, _now())
		_mark("city_%s_stage%d_s" % [id, stage])
		_progress()
		_event("city_stage", {"city": id, "stage": stage}))
	_hook(EventBus.launch_ready, func(_pid: String) -> void:
		_mark("launch_ready_s")
		_cadence.launched(_now())
		_progress())
	_hook(EventBus.ending_shown, func(_pid: String) -> void:
		_mark("ending_s")
		_end_run("the ending was shown", 0))


func _orbit() -> SliceOrbit:
	return world.get("orbit") as SliceOrbit


func _districts() -> Districts:
	var so: SliceOrbit = _orbit()
	return so.districts if so != null else null


func _sources() -> Sources:
	var so: SliceOrbit = _orbit()
	return so.sources if so != null else null


func _crew() -> int:
	return world.fleet.robot_total() if world.fleet else 0


## The site whose pad the rocket stands on: where Lumi landed last (0 = the start yard).
func _here_site() -> int:
	var os: OrbitSites = OrbitSites.of(world)
	return os.rocket_site() if os != null else 0


func _away() -> bool:
	return _here_site() != 0


## The middle of the base Lumi works from: the start yard's scale, or the pad of the city she flew
## to (its middle cell is base ground, where the watering can refills).
func _base_at() -> Vector3:
	if not _away() and world.get("depot") is Node3D:
		return (world.depot as Node3D).global_position
	return _orbit().globe.site_point(_here_site(), Vector3.ZERO)


## The city table for the cadence rows, once the districts exist; the first city counts as reached
## when the bot takes control.
func _setup_cadence() -> void:
	var d: Districts = _districts()
	if d == null or not _cadence.rows.is_empty():
		return
	var cities: Array[Dictionary] = []
	for id: String in d.ids():
		cities.append({"id": id, "name": d.name_of(id), "pollution": d.spec_of(id).get("pollution", [])})
	_cadence.setup(cities)
	var saved: String = _cadence_path()
	if saved != "" and not DevHooks.has("fresh") and FileAccess.file_exists(saved):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved))
		if v is Dictionary:
			_cadence.from_dict(v)  # a staged run goes on with the table so far
	var first: String = d.district_of_site(_here_site())
	if first != "":
		_cadence.arrive(first, _now(), _crew())


## A staged run keeps its table on disk every minute, so a stage cut short loses at most a minute.
func _save_cadence() -> void:
	if _cadence_path() == "" or _cadence.rows.is_empty():
		return
	var cf := FileAccess.open(_cadence_path(), FileAccess.WRITE)
	if cf:
		cf.store_string(JSON.stringify(_cadence.to_dict()))


## Where a staged run (--save-dir) keeps its cadence table between stages ("" for a single run).
func _cadence_path() -> String:
	var dir: String = DevHooks.get_s("save-dir", "")
	return "" if dir == "" else ProjectSettings.globalize_path("res://screenshots/autoplay_cadence_%s.json" % dir.validate_filename())


## Travel, as a player: when the planner points at another site and the rocket's cells are full,
## set any bales down, walk to the parked rocket and fly. True while boarding.
func _do_travel(p: Patch) -> bool:
	var os: OrbitSites = OrbitSites.of(world)
	var d: Districts = _districts()
	if os == null or d == null or DevHooks.has("no-travel") or not os.rocket_unlocked() or os.rocket_spot == null:
		return false
	if os.hop.flying:
		return true
	var here: int = os.rocket_site()
	var want: int = _travel.want_site(d, _sources())
	if want < 0 or want == here or not os.site_offered(want) or os.hop_blocker() != "" or p._cubing > 0.0 or _now() < _hop_retry_at:
		return false
	if here == 0 and _now() - _last_bench_t > 60.0 and (not _rig_tools().is_empty() or bool(_shopping_list().get("trip", false))):
		_bench_trip = true  # leaving the start yard: the bench first (a city's tool may be waiting there)
		return false
	if not p.carried.is_empty():
		_drop_all(p)
	if p.tool != Patch.Tool.SCOOP:
		p.set_tool(Patch.Tool.SCOOP)
	_set_task("board")
	var to_rocket: float = _go(p, os.rocket_spot.global_position, 1.5)
	if DevHooks.has("bot-debug") and int(_task_t * 10.0) % 100 == 0:
		print("[bot-board] t=%.1f walk %.0f s, %.1f m to the rocket at %s, Lumi at %s" % [_now() / 60.0, _task_t, to_rocket,
			str(os.rocket_spot.global_position.snappedf(0.1)), str(p.global_position.snappedf(0.1))])
	if to_rocket > AutoplayTravel.BOARD_M and _task_t < AutoplayTravel.WALK_GIVE_UP_S:
		return true
	if to_rocket > AutoplayTravel.BOARD_M:
		# Boxed in on the way (a person would call the rocket over): logged, as the bot's traps are.
		_travel.board_stuck += 1
		_event("board_stuck", {"rocket_m": snappedf(to_rocket, 0.1), "at": str(p.global_position.snappedf(0.1))})
	_travel.hops += 1
	if here == 0:
		_travel.last_home_s = _now()  # the bench was just visited on the way out
	_event("hop", {"from": here, "to": want, "city": d.district_of_site(want), "home_trip": _travel.home_trip, "why": _travel.why,
		"walk_s": snappedf(_task_t, 0.1), "rocket_m": snappedf(to_rocket, 0.1)})
	_area_city = "?"
	_focus_hex = -1
	_plant_hex = -1
	_learn_hex = -1
	_water_target = -1
	_target_piece = -1
	os.hop_to(want)
	if not os.hop.flying:  # refused (the flight starts at once when it goes): try again later
		_hop_retry_at = _now() + HOP_RETRY_S
		_event("hop_refused", {"from": here, "to": want})
	return true


## A refused hop is tried again after this many game seconds.
const HOP_RETRY_S: float = 30.0
var _hop_retry_at: float = 0.0


## Away from the start yard: whether to fly home for the bench (checked once a second).
func _want_home() -> void:
	if _travel.home_trip:
		return
	var asm: RobotChain = RobotChain.of(world)
	var asm_ready: bool = asm != null and asm.listed() and asm.block_reason() == ""
	if _travel.home_wanted(not _rig_tools().is_empty(), asm_ready, bool(_shopping_list().get("trip", false)), _now()):
		_travel.home_trip = true
		_event("home_trip", {"why": _travel.why})


## What the bot is trying to do, for the stall line and the report.
func _doing() -> String:
	var d: Districts = _districts()
	var target: String = AutoplayTravel.target_city(d, _sources()) if d != null else ""
	var here: String = d.district_of_site(_here_site()) if d != null else ""
	return "task=%s city=%s stage=%d target=%s home_trip=%s hex=%d cubes=%.0f parts=%.0f crew=%d research=%s rocket=%s" % [_task, here,
		d.stage_of(here) if d != null and here != "" else -1, target, str(_travel.home_trip), _focus_hex,
		GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float(), _crew(), Research.active_id(),
		OrbitSites.of(world).hop_blocker() if OrbitSites.of(world) != null else "-"]


## Once a second: the cadence samples, and the stall watch. A stall ends the run with exit code 1.
func _watch_whole_game(paused: bool) -> void:
	_setup_cadence()
	_cadence.sample(_now(), GameState.get_currency("cubes").to_float(), GameState.get_currency("parts").to_float())
	if paused:
		_stall.pause(_now())
		return
	if _stall.tick(_now(), _doing()) and not DevHooks.has("no-stall-exit"):
		print("[Autoplay] STALL: nothing progressed for %.1f game minutes (no purchase, goal, hex or stage). Doing: %s" % [
			_stall.idle_s(_now()) / 60.0, str(_stall.stalled["doing"])])
		_end_run("stall", 1)


## Game time that is not play: the seed tin's cinematic, a rocket flight, the launch.
func _not_play() -> bool:
	var os: OrbitSites = OrbitSites.of(world)
	return (world.first_seed != null and bool(world.first_seed.get("_active"))) or (os != null and os.hop.flying) or bool(world.get("launching"))


func _end_run(why: String, code: int) -> void:
	if _ended:
		return
	_ended = true
	print("[Autoplay] run over: %s at %.1f game min (exit %d)" % [why, _now() / 60.0, code])
	write_report()
	world.get_tree().quit(code)


## The Assembler's build mix, set as a player would for the city in play: cleaners and haulers
## always, a parts finder, a skimmer while the city's lakes are dirty, planters and waterers once
## the garden is open. Paused while the rocket's job waits for Parts the line would spend.
func _set_mix() -> void:
	var rc: RobotChain = RobotChain.of(world)
	if rc == null or not rc.is_built():
		return
	var g: Garden = world.garden
	var garden: bool = g != null and g.unlocked()
	var want: Dictionary = {"scoopie": 3, "haulbug": 2, "scrounger": 2, "skimmer": 2 if _lake_dirty() else 0,
		"seedling": 2 if garden else 0, "drip": 2 if garden else 0, "multibot": 1}
	for t: String in want:
		if int(_mix.get(t, -1)) != int(want[t]):
			rc.set_weight(t, int(want[t]))
			_mix[t] = int(want[t])
	var src: Sources = _sources()
	var hold: bool = false
	if src != null:
		for id: String in src.ids():
			if src.is_open(id) and not src.is_shut(id) and not src.can_afford(id) and not src.is_building(id):
				hold = true
	if hold != bool(_mix.get("_paused", false)):
		rc.set_paused(hold)
		_mix["_paused"] = hold
		_event("assembler_pause" if hold else "assembler_run", {})


## Scroungers' search area: the clean ground of the city in play that still holds buried parts,
## nearest the base first.
func _paint_search() -> void:
	var fleet: Fleet = world.fleet
	if not fleet is SphereFleet or (fleet as SphereFleet).crew.chain == null:
		return
	var finder: String = str((Economy.robot_cfg.get("chain", {}) as Dictionary).get("finder", ""))
	if finder == "" or fleet.count(finder) == 0:
		return
	var stock: Dictionary = (fleet as SphereFleet).crew.chain.stock
	var f: HexField = world.field
	var o: Vector3 = _base_at()
	var cand: Array = []
	for h: int in _hexes():
		if _land(h) and f.is_clean(h) and float(stock.get(h, 0.0)) > 0.0:
			cand.append(h)
	cand.sort_custom(func(a: int, b: int) -> bool: return f.hex_center(a).distance_to(o) < f.hex_center(b).distance_to(o))
	_set_zone(SphereScrounge.ROLE, cand.slice(0, 24))


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


## Robots owned, by type. On the globe they live in the crew, not in Fleet.robots() (B21: the
## report showed none), so this asks the fleet's own count.
func _robot_counts() -> Dictionary:
	var out: Dictionary = {}
	var fl: Fleet = world.fleet
	if fl == null:
		return out
	for id: String in Economy.robot_order:
		var n: int = fl.count(id)
		if n > 0:
			out[id] = n
	return out


func _snapshot() -> void:
	var types: Dictionary = _robot_counts()
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
		"planet": String(Planets.current_id()), "pct": snappedf(Restoration.value(), 0.001),  # launch progress
		"city": _city_id(), "city_stage": int(Restoration.measure(Restoration.MEASURE_CITY_STAGE)), "city_share": snappedf(_city_share(), 0.001)})
	var pid: String = String(Planets.current_id())  # [orbC] pacing marks: 25% / 50% / 75% of the planet
	var pct: float = Restoration.value()
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
	_print_garden()
	_print_crew_here()
	_save_cadence()
	print("[Autoplay] %5.1f min city=%s stage=%d share=%d%% launch=%.1f%% cubes=%d rate=%.2f/s partscur=%.0f seeds=%.0f parts=%d hexes=%d lv=%s robots=%s hub=%d task=%s goals=%d research=%s pos=%s esc=%d" % [_now() / 60.0,  # [money]
		_city_id(), int(Restoration.measure(Restoration.MEASURE_CITY_STAGE)), int(floor(_city_share() * 100.0)), pct * 100.0,
		int(GameState.get_currency("cubes").to_float()), GameState.income_rate(), GameState.get_currency("parts").to_float(),
		GameState.get_currency("seeds").to_float(), GameState.parts.size(),
		world.field.cleaned_count, str(lv), str(types), int(world.hub.level), _task, ngoals, Research.active_id(), str(world.patch.global_position.snappedf(0.1)), _escapes])


## Where the crew works, once a minute: robots of the base Lumi works from, and by job.
func _print_crew_here() -> void:
	var rc: RobotChain = RobotChain.of(world)
	if rc == null or not world.fleet is SphereFleet:
		return
	var hub: int = rc.work_hub()
	var here: Dictionary = {}
	var n_here: int = 0
	var n_all: int = 0
	for u: Dictionary in (world.fleet as SphereFleet).crew.robots():
		n_all += 1
		if int(u["hub"]) == hub:
			n_here += 1
			here[str(u["type"])] = int(here.get(str(u["type"]), 0)) + 1
	print("[crew] %5.1f min %d of %d robots work for the base Lumi is at: %s" % [_now() / 60.0, n_here, n_all, JSON.stringify(here)])


## The garden of the city in play, once a minute: clean land hexes, hexes with slots, planted
## slots and plantable ones, hexes past a quarter planted, and the hex being planted.
func _print_garden() -> void:
	var g: Garden = world.garden
	if g == null or not g.unlocked():
		return
	var land: int = 0
	var with_slots: int = 0
	var planted: int = 0
	var room: int = 0
	var quarter: int = 0
	for h: int in _hexes():
		if not _land(h) or not world.field.is_clean(h):
			continue
		land += 1
		var pc: Vector2i = _hex_planted(g, h)
		if pc.y > 0:
			with_slots += 1
		planted += pc.x
		room += pc.y
		if pc.y > 0 and pc.x * 4 >= pc.y:
			quarter += 1
	print("[garden] %5.1f min clean land %d, with plantable slots %d, planted %d of %d plantable, a quarter planted %d, planting hex %d, seeds %.0f, garden time %.0f s" % [
		_now() / 60.0, land, with_slots, planted, room, quarter, _plant_hex, GameState.get_currency("seeds").to_float(), _garden_s])


## Dev: --garden-audit (with --district-stage=<city>:1 so every land hex is clean, and
## --orbit-hop=<site> for a city other than the first). For the city Lumi stands in: how many land
## hexes can hold a plant at all. Slots on paving take no seed, so a hex with none of the other
## kind stays at stage 1 for good; a city whose share of plantable hexes is under its stage share
## can never pass stage 1. Prints one line and quits.
func _garden_audit() -> void:
	var g: Garden = world.garden
	var d: Districts = _districts()
	var city: String = d.district_of_site(_here_site()) if d != null else ""
	var land: int = 0
	var bare: int = 0
	for h: int in _hexes():
		if not _land(h):
			continue
		land += 1
		g.ensure_hex(h)
		var room: int = 0
		for sl: int in g.hex_slots.get(h, PackedInt32Array()):
			if g.plantable(sl):
				room += 1
		if room == 0:
			bare += 1
	var share: float = float(land - bare) / maxf(1.0, float(land))
	_report["garden_audit"] = {"city": city, "land": land, "no_plantable_slot": bare, "plantable_share": snappedf(share, 0.001)}
	print("[garden-audit] %s: land %d, no plantable slot %d, plantable %.0f%% (stage share %.0f%%): %s" % [city, land, bare, share * 100.0,
		100.0 * d.stage_share, "PASS" if share >= d.stage_share else "FAIL"])
	world.get_tree().quit(0 if share >= d.stage_share else 1)


## The city (district) the readout shows, and its share toward its next regrowth stage.
func _city_id() -> String:
	var r: Restoration = Restoration.active()
	return r.districts.focus_id() if r and r.districts else ""


func _city_share() -> float:
	var r: Restoration = Restoration.active()
	return r.districts.share_of(r.districts.focus_id()) if r and r.districts else 0.0


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
	_print_pacing("end of run")
	_report["purchases"] = _spend_times.size()
	_report["longest_purchase_gap_first_20_min_s"] = snappedf(_longest_purchase_gap(PACING_WINDOW_S), 0.1)
	_report["max_cubes_held"] = snappedf(_max_cubes, 1.0)
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
		_report["goals_total"] = world.goals.authored_count()
		_goal_log.write(_report, world.goals, float(_report.get("control_s", _start_t)), end_t)
		for i: int in world.goals.current():
			next_goals.append(str(world.goals.chain[i]["id"]))
	_report["next_goals"] = next_goals
	_report["research_done"] = Research.done_list().duplicate()
	_report["research_idle_s"] = snappedf(_research_idle_s, 1.0)
	_report["research_idle_max_s"] = snappedf(_research_idle_max, 1.0)
	_report["research_starved_s"] = snappedf(_research_starved_s, 1.0)
	_report["field_data_earned"] = snappedf(float(GameState.stats.get("data_earned", 0.0)), 0.1)
	_report["field_data_banked"] = snappedf(FieldData.bank(), 0.1)
	_report["parts_bought"] = _parts_bought
	_report["stuck_escapes"] = _escapes
	_report["fell_through"] = GameState.stats.get("fell_through", 0)
	_report["cubes_fell"] = GameState.stats.get("cubes_fell", 0)  # [beat]
	_report["stuck_robots"] = _stuck_bots
	_report["remote_shops"] = _remote_shops
	_report["parts_found"] = GameState.stats.get("parts_found", 0)
	_report["hub_level"] = int(world.hub.level)
	var types: Dictionary = _robot_counts()
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
	_mastery.write(_report, Mastery.of(world))
	_surge.write(_report)
	_report["hops"] = _travel.hops
	_report["board_stuck"] = _travel.board_stuck
	_stall.write(_report, end_t)
	_cadence.write(_report, end_t, _crew())
	_save_cadence()
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
