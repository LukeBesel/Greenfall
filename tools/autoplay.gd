class_name AutoplayBot
extends InputSource
## Simple-rules playtest bot: scoop the nearest junk, cube near the Perfect band, carry cubes to the
## Depot, buy the cheapest upgrade. Measures pacing (first cube / cash-in / upgrade / hex) and
## writes screenshots/autoplay_report.json on exit. Run:
##   godot --path . -- --fresh --autoplay --time-scale=4 --quit-after=150

var world: Node
var _move := Vector3.ZERO
var _scoop: bool = false
var _cube: bool = false
var _interact: bool = false
var _cooldown: float = 0.0
var _stuck_timer: float = 0.0
var _last_pos := Vector3.ZERO
var _report: Dictionary = {}
var _log: Array = []
var _log_timer: float = 0.0
var _ignore_piece: Dictionary = {}
var _target_piece: int = -1


func _init(p_world: Node) -> void:
	world = p_world
	EventBus.cube_made.connect(func(_i: Dictionary) -> void: _mark("first_cube_s"))
	EventBus.cube_cashed.connect(func(_v: BigNum, _p: Vector3) -> void: _mark("first_cashin_s"))
	EventBus.upgrade_bought.connect(func(id: String, lv: int) -> void:
		_mark("first_upgrade_s")
		_log.append({"t": _now(), "event": "upgrade", "id": id, "level": lv}))
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _mark("first_hex_s"))
	world.tree_exiting.connect(write_report)


func _now() -> float:
	return snappedf(float(GameState.stats.get("time_played", 0.0)), 0.1)


func _mark(key: String) -> void:
	if not _report.has(key):
		_report[key] = _now()
		print("[Autoplay] %s at %.1fs" % [key, _report[key]])


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


var _detour_t: float = 0.0
var _detour := Vector3.ZERO
var _progress_pos := Vector3.ZERO
var _progress_t: float = 0.0


func _go(p: Patch, target: Vector3, stop_dist: float = 0.3) -> float:
	var d: Vector3 = target - p.global_position
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
			var side := Vector3(d.z, 0, -d.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
			_detour = side
			_detour_t = 1.4
			_progress_t = 0.0
	return dist


func update(delta: float) -> void:
	var p: Patch = world.patch
	if p == null:
		return
	_cooldown -= delta
	_detour_t -= delta
	_progress_t += delta
	_scoop = false
	_move = Vector3.ZERO
	_log_timer += delta
	if _log_timer >= 30.0:
		_log_timer = 0.0
		_log.append({"t": _now(), "cubes": GameState.get_currency("cubes").to_float(), "hexes": world.field.cleaned_count, "made": GameState.stats.get("cubes_made", 0)})
		var lc: JunkCube = _nearest_loose(p)
		print("[Autoplay] state pos=%s carried=%d fill=%.1f pending=%.1f cubing=%.1f loose=%s target=%d stuck=%.1f" % [str(p.global_position.snappedf(0.1)), p.carried.size(), p.compartment.fill, p.compartment.pending, p._cubing, str(lc.global_position.snappedf(0.1)) if lc else "none", _target_piece, _stuck_timer])
	_buy_cheapest()
	if p._cubing > 0.0:
		return
	var cap: float = p.capacity()
	var carry_cap: int = p.carry_cap()
	var loose: JunkCube = _nearest_loose(p)
	var depot: Depot = world.depot
	# 1) Deliver when the stack is full, or when nothing else is worth grabbing.
	if not p.carried.is_empty() and (p.carried.size() >= carry_cap or (loose == null and p.compartment.is_empty())):
		_go(p, depot.global_position, 0.6)
		return
	# 2) Pick up loose cubes.
	if loose and p.carried.size() < carry_cap:
		var dist: float = _go(p, loose.global_position, 0.9)
		if dist < 1.5 and _cooldown <= 0.0:
			_interact = true
			_cooldown = 0.4
		return
	# 3) Compact when in or past the Perfect band (and nothing still in flight).
	if p.compartment.ratio(cap) >= 0.9 and p.compartment.pending <= 0.0:
		_cube = true
		return
	if p.compartment.fill + p.compartment.pending >= cap * 0.9:
		return  # wait for in-flight pieces to land
	# 4) Scoop the nearest junk.
	var field: HexField = world.field
	if _target_piece < 0 or field.piece_alive[_target_piece] == 0:
		_target_piece = _nearest_piece(p)
	if _target_piece < 0:
		if not p.compartment.is_empty():
			_cube = true
		return
	var tp: Vector3 = field.piece_pos[_target_piece]
	var dist2: float = _go(p, tp, 0.8)
	if dist2 < p.stat("scoop_reach") + 0.5:
		_scoop = true
		_move *= 0.6
	# Unstick: if not moving for a while, give up on this piece.
	if p.global_position.distance_to(_last_pos) < 0.02 and dist2 > 1.2:
		_stuck_timer += delta
		if _stuck_timer > 1.5:
			_ignore_piece[_target_piece] = true
			_target_piece = -1
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	_last_pos = p.global_position


func _nearest_piece(p: Patch) -> int:
	var field: HexField = world.field
	var best: int = -1
	var best_d: float = INF
	for hid: int in field.hexes_near(p.global_position, 1):
		for pid: int in field.hex_pieces[hid]:
			if field.piece_alive[pid] == 0 or _ignore_piece.has(pid):
				continue
			var d: float = field.piece_pos[pid].distance_squared_to(p.global_position)
			if d < best_d:
				best_d = d
				best = pid
	if best < 0:
		best = field.nearest_alive(p.global_position)
	return best


func _nearest_loose(p: Patch) -> JunkCube:
	var best: JunkCube = null
	var best_d: float = 14.0
	for n: Node in p.get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed:
			continue
		var d: float = c.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _buy_cheapest() -> void:
	var best: String = ""
	var best_cost: BigNum = null
	for id: String in Economy.upgrade_order:
		if not Economy.is_unlocked(id) or Economy.is_maxed(id):
			continue
		var c: BigNum = Economy.upgrade_cost(id)
		if best_cost == null or c.lt(best_cost):
			best_cost = c
			best = id
	if best != "" and GameState.can_afford("cubes", best_cost):
		Economy.buy_upgrade(best, 1)


func write_report() -> void:
	_report["game_time_s"] = _now()
	_report["cubes"] = GameState.get_currency("cubes").to_float()
	_report["cubes_made"] = GameState.stats.get("cubes_made", 0)
	_report["perfect_cubes"] = GameState.stats.get("perfect_cubes", 0)
	_report["pure_cubes"] = GameState.stats.get("pure_cubes", 0)
	_report["hexes_cleaned"] = world.field.cleaned_count
	_report["upgrades"] = GameState.upgrades.duplicate()
	_report["log"] = _log
	var path: String = ProjectSettings.globalize_path("res://screenshots/autoplay_report.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_report, "  "))
	print("[Autoplay] report: ", JSON.stringify(_report))
