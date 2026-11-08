class_name OrbitDev
extends Node
## [orbB] Phase A's dev checks on the orbit slice (scenes/slice_orbit.gd):
## --orbit-walk[=boost] --orbit-lap-quit  walk a full lap, print "LAP ... PASS"
## --orbit-scoop                         autowalk with the scoop held, log every 10 s
## --orbit-cash [--orbit-cash-quit]      scripted dump + bale-to-depot test, print PASS/FAIL
## Every 5 s (not while lapping) an [orbit-perf] line: frame times, junk, draw calls, streamer.

const LAP_PATH := "res://screenshots/orbit/lap_trail_v2.json"

var so: SliceOrbit
var _lap_on: bool = false
var _lap_start := Vector3.ZERO
var _lap_min: float = INF
var _lap_done: bool = false
var _lap_t: float = 0.0
var _trail: Array = []
var _trail_d: float = 0.0
var _perf: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _perf_n: int = 0
var _scoop_t: float = 0.0


func _ready() -> void:
	if DevHooks.has("orbit-walk") and not DevHooks.has("orbit-scoop"):
		_lap_on = true
		_lap_start = _lumi().global_position
	if DevHooks.has("orbit-cash"):
		_cash_test.call_deferred()


func _lumi() -> Patch:
	return so.w.get("patch")


func _physics_process(delta: float) -> void:
	_lap_tick(delta)
	_scoop_log(delta)


func _process(delta: float) -> void:
	_perf[0] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_perf[1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_perf[2] = maxf(_perf[2], Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_perf[3] += delta
	_perf_n += 1
	if _perf[3] >= 5.0 * Engine.time_scale and (not DevHooks.has("orbit-walk") or DevHooks.has("orbit-scoop")):
		print("[orbit-perf] " + perf_line())


func perf_line() -> String:
	var g: OrbitPlanet = so.globe
	var s: String = "process_ms avg=%.2f max=%.2f physics_ms avg=%.2f junk=%d (near %d far %d) junk_ms=%d mounds=%d landmarks=%d draw_calls=%d prims=%d streamer=%s" % [
		_perf[0] / maxi(_perf_n, 1), _perf[2], _perf[1] / maxi(_perf_n, 1), int(g.stats.get("junk", 0)), g.junk_view.counts().x, g.junk_view.counts().y, int(g.stats.get("junk_ms", 0)),
		g.junk_view.mound_count(), g.junk_view.landmark_count(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), JSON.stringify(g.streamer.stats)]
	_perf = [0.0, 0.0, 0.0, 0.0]
	_perf_n = 0
	return s


func _lap_tick(delta: float) -> void:
	if not _lap_on or _lap_done:
		return
	var lumi: Patch = _lumi()
	var g: OrbitPlanet = so.globe
	_lap_t += delta
	_trail_d += lumi.velocity.length() * delta
	if _trail_d > 20.0:
		_trail_d = 0.0
		var p: Vector3 = lumi.global_position
		_trail.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	if int(_lap_t / 60.0) != int((_lap_t - delta) / 60.0):
		print("[orbit] t=%.0fs walked=%.0fm cell=%d %s" % [_lap_t, lumi.sphere_motor.distance, g.grid.cell_at(lumi.global_position), perf_line()])
	var circ: float = TAU * g.grid.radius_m
	if lumi.sphere_motor.distance > circ * 0.8:
		var dd: float = lumi.global_position.distance_to(_lap_start)
		if dd < _lap_min:
			_lap_min = dd
		elif dd > _lap_min + 15.0:
			_lap_done = true
			_trail.append([_lap_start.x, _lap_start.y, _lap_start.z])
			var ok: bool = _lap_min < 12.0
			print("[orbit] LAP walked=%.0fm around=%.0fm game_time=%.0fs (%.1f min) closest_to_start=%.2fm %s" % [
				lumi.sphere_motor.distance, circ, _lap_t, _lap_t / 60.0, _lap_min, "PASS" if ok else "FAIL"])
			var abs_path: String = ProjectSettings.globalize_path(LAP_PATH)
			DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
			var fa := FileAccess.open(abs_path, FileAccess.WRITE)
			if fa:
				fa.store_string(JSON.stringify({"trail": _trail, "R": g.grid.radius_m, "time_s": _lap_t, "closest": _lap_min}))
			if DevHooks.has("orbit-lap-quit"):
				get_tree().quit(0 if ok else 1)


func _scoop_log(delta: float) -> void:
	if not DevHooks.has("orbit-scoop"):
		return
	var lumi: Patch = _lumi()
	_scoop_t += delta
	if int(_scoop_t / 10.0) != int((_scoop_t - delta) / 10.0):
		print("[orbit] scoop t=%.0fs walked=%.0fm fill=%.2f/%.2f hexes_cleaned=%d cubes=%s junk_drawn=%d time=%.2f day=%.2f" % [
			_scoop_t, lumi.sphere_motor.distance, lumi.compartment.fill, lumi.capacity(),
			int(GameState.stats.get("hexes_cleaned", 0)), Settings.fmt(GameState.get_currency("cubes")), int(so.globe.stats.get("junk", 0)),
			float(so.day.stats.get("local_time", 0.0)), float(so.day.stats.get("daylight", 0.0))])


## The start loop on the planet, headless. Before the Baler: scoop, roll to the bin (the Depot)
## and empty the chest for cubes. With the Baler: press a bale, carry it, cash it.
func _cash_test() -> void:
	var lumi: Patch = _lumi()
	var g: OrbitPlanet = so.globe
	var depot: Depot = so.w.get("depot")
	var c0: float = GameState.get_currency("cubes").to_float()
	for k: int in 12:
		var pid: int = g.field.nearest_alive(lumi.global_position)
		if pid >= 0:
			lumi._take_piece(pid)
	await get_tree().create_timer(1.0).timeout
	var fill: float = lumi.compartment.fill
	lumi.place_on_sphere(depot.global_position + depot.global_basis.y * 0.5, lumi.forward())
	await get_tree().create_timer(1.5).timeout
	var c1: float = GameState.get_currency("cubes").to_float()
	var dumped: bool = c1 > c0 and lumi.compartment.is_empty()
	print("[orbit] cash: dump (no Baler) fill=%.1f cubes %.0f -> %.0f %s" % [fill, c0, c1, "ok" if dumped else "FAIL"])
	GameState.upgrades["baler"] = 1
	var spot: Vector3 = g.terrain.local_to_dir(g.start_cell(), 0.0, 9.0)
	lumi.place_on_sphere(g.terrain.ground(spot), -SphereGrid.frame(spot).z)
	await get_tree().create_timer(0.5).timeout
	for k: int in 12:
		var pid: int = g.field.nearest_alive(lumi.global_position)
		if pid >= 0:
			lumi._take_piece(pid)
	await get_tree().create_timer(1.0).timeout
	lumi.start_cube()
	await get_tree().create_timer(2.4).timeout
	var c: JunkCube = lumi.nearest_loose_cube()
	var alt: float = g.surface.altitude(c.global_position) if c else -99.0
	print("[orbit] cash: bale made=%s alt_above_ground=%.2f" % [str(c != null), alt])
	if c:
		lumi.pick_up(c)
	await get_tree().create_timer(0.6).timeout
	lumi.place_on_sphere(depot.global_position + depot.global_basis.y * 0.5, lumi.forward())
	await get_tree().create_timer(3.0).timeout
	var c2: float = GameState.get_currency("cubes").to_float()
	var ok: bool = dumped and depot.cashed >= 1 and c2 > c1
	print("[orbit] cash: bale cashed=%d cubes %.0f -> %.0f %s" % [depot.cashed, c1, c2, "PASS" if ok else "FAIL"])
	if DevHooks.has("orbit-lap-quit") or DevHooks.has("orbit-cash-quit"):
		get_tree().quit(0 if ok else 1)
