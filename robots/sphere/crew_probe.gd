class_name CrewProbe
extends Node
## [orbC] Dev (--bot-motion, with --quit-after): watches the near robots of a SphereCrew and
## reports how they move, so "believable" can be checked headless:
## - jitter: steering reversals while travelling (above MIN_TRAVEL, the turn rate flips sign at
##   more than JITTER_RATE within FLIP_S) per robot-minute, and the mean |turn rate| while moving;
## - clipping: share of samples a robot's centre is inside a building circle (SphereObstacles);
## - the loop: pieces scooped, bales dropped and hauled (from the crew's logs).
## Prints one [motion] line per robot and a PASS / FAIL summary just before quitting.

const JITTER_RATE: float = 1.2  # rad/s
const FLIP_S: float = 0.5
## PASS on the crew's average (one robot's bad minute shouldn't hide a good crew, nor the reverse;
## the worst robot is printed too).
const MAX_FLIPS_PER_MIN: float = 4.0
const MAX_CLIP: float = 0.005
const MIN_TRAVEL: float = 0.5  # m/s
## [v6crew] Modes that are a trip somewhere (a detour is measured from start to arrival).
const TRIP_MODES: Array[String] = ["go", "to_bale", "to_depot", "to_refill", "to_baler"]
const BUNCH_M: float = 3.0

var crew: SphereCrew
var _s: Dictionary = {}  # name -> stats
var _done: bool = false


func _physics_process(delta: float) -> void:
	if crew == null or delta <= 0.0:
		return
	var obs: Array = crew.swarm.obstacles if crew.swarm else []
	for u: Dictionary in crew.robots():
		var b: SphereBot = u["bot"]
		if b == null:
			continue
		var st: Dictionary = _s.get(u["name"], {})
		if st.is_empty():
			st = {"type": u["type"], "h": b.heading, "w": 0.0, "flip_t": INF, "flips": 0, "t": 0.0, "move_t": 0.0, "turn": 0.0, "in": 0, "n": 0,
				"m": 0.0, "mode": "", "trip_from": b.dir, "trip_m": 0.0, "trips": 0, "trip_path": 0.0, "trip_line": 0.0, "bunch_t": 0.0}
			_s[u["name"]] = st
		# [v6crew] trips: from the moment a robot heads somewhere to its arrival, path length vs the
		# straight line (detour), and for haulers the time spent within BUNCH_M of another hauler.
		var mode: String = str(u["mode"])
		if mode != str(st["mode"]):
			if str(st["mode"]) in TRIP_MODES:
				var line: float = (st["trip_from"] as Vector3).angle_to(b.dir) * crew.surface.radius
				if line > 8.0:
					st["trips"] = int(st["trips"]) + 1
					st["trip_path"] = float(st["trip_path"]) + float(st["trip_m"])
					st["trip_line"] = float(st["trip_line"]) + line
			st["mode"] = mode
			st["trip_from"] = b.dir
			st["trip_m"] = 0.0
		st["m"] = float(st["m"]) + b.moving_speed * delta
		st["trip_m"] = float(st["trip_m"]) + b.moving_speed * delta
		if str(u["role"]) == "haul" and b.moving_speed > MIN_TRAVEL:
			for o: Dictionary in crew.robots():
				if not is_same(o, u) and str(o["role"]) == "haul" and o["bot"] != null and (o["bot"] as SphereBot).dir.angle_to(b.dir) * crew.surface.radius < BUNCH_M:
					st["bunch_t"] = float(st["bunch_t"]) + delta
					break
		var w: float = (st["h"] as Vector3).signed_angle_to(b.heading, b.dir) / delta
		st["h"] = b.heading
		st["t"] = float(st["t"]) + delta
		st["flip_t"] = float(st["flip_t"]) + delta
		if b.moving_speed > 0.2:
			st["move_t"] = float(st["move_t"]) + delta
			st["turn"] = float(st["turn"]) + absf(w) * delta
		if absf(w) > JITTER_RATE and b.moving_speed > MIN_TRAVEL:  # turning on the spot to a new piece isn't jitter
			if signf(w) != signf(float(st["w"])) and float(st["flip_t"]) < FLIP_S:
				st["flips"] = int(st["flips"]) + 1
				if DevHooks.has("motion-debug") and str(u["role"]) == "haul":  # [v6crew] what was near at the flip
					var nb_m: float = INF
					for o: Dictionary in crew.robots():
						if not is_same(o, u) and o["bot"] != null:
							nb_m = minf(nb_m, (o["bot"] as SphereBot).dir.angle_to(b.dir) * crew.surface.radius)
					var ob_m: float = INF
					var ob_r: float = 0.0
					for ob2: Array in crew.swarm.obstacles_near(b.dir, 6.0):
						var e: float = b.dir.angle_to(ob2[0]) * crew.surface.radius - float(ob2[1])
						if e < ob_m:
							ob_m = e
							ob_r = float(ob2[1])
					var dep_m: float = crew.drop_dir(int(u["hub"])).angle_to(b.dir) * crew.surface.radius
					var fin: Vector3 = b.path[b.path.size() - 1] if not b.path.is_empty() else b.goal
					var fin_m: float = -1.0
					for ob3: Array in crew.swarm.obstacles_near(b.dir, 6.0):
						if absf(b.dir.angle_to(ob3[0]) * crew.surface.radius - float(ob3[1]) - ob_m) < 0.01 and fin != Vector3.ZERO:
							fin_m = fin.angle_to(ob3[0]) * crew.surface.radius - float(ob3[1])
					var drop_s: String = str(u.get("drop", ""))
					var g_m: float = b.dir.angle_to(b.goal) * crew.surface.radius if b.has_goal() else -1.0
					print("[flip] %s %s goal %.1fm wps %d bot %.1fm wall %.1fm spd %.1f r %.1f depot %.0fm end-to-prop %.1fm drop %s held %s" % [u["name"], u["mode"], g_m, b.path.size(), nb_m, ob_m, b.moving_speed, ob_r, dep_m, fin_m, drop_s, str(b._wall_s)])
			st["w"] = w
			st["flip_t"] = 0.0
		st["n"] = int(st["n"]) + 1
		for ob: Array in obs:
			if b.dir.angle_to(ob[0]) * crew.surface.radius < float(ob[1]) * 0.7:  # inside the box, not just its circle
				st["in"] = int(st["in"]) + 1
				break


func _process(_d: float) -> void:
	if _done or not DevHooks.has("quit-after"):
		return
	if DevHooks._elapsed >= DevHooks.get_f("quit-after", 30.0) - 1.2:
		_done = true
		report()


func report() -> bool:
	var worst_f: float = 0.0
	var worst_c: float = 0.0
	var tot_flips: float = 0.0
	var tot_min: float = 0.0
	var tot_in: int = 0
	var tot_n: int = 0
	var h_m: float = 0.0
	var h_turn: float = 0.0
	var h_path: float = 0.0
	var h_line: float = 0.0
	var h_bunch: float = 0.0
	var h_t: float = 0.0
	var h_flips: float = 0.0
	for nm: String in _s:
		var st: Dictionary = _s[nm]
		var mins: float = maxf(float(st["t"]) / 60.0, 0.01)
		var fpm: float = float(st["flips"]) / mins
		var clip: float = float(st["in"]) / maxf(float(st["n"]), 1.0)
		var turn: float = float(st["turn"]) / maxf(float(st["move_t"]), 0.01)
		tot_flips += float(st["flips"])
		tot_min += mins
		tot_in += int(st["in"])
		tot_n += int(st["n"])
		var u: Dictionary = {}
		for x: Dictionary in crew.robots():
			if x["name"] == nm:
				u = x
		var lg: Dictionary = u.get("log", {})
		var deg100: float = rad_to_deg(float(st["turn"])) / maxf(float(st["m"]), 1.0) * 100.0
		var detour: float = float(st["trip_path"]) / maxf(float(st["trip_line"]), 1.0)
		print("[motion] %-12s %-8s %4.1f min  reversals/min %4.1f  turn %.2f rad/s  in buildings %4.1f%%  junk %.0f bales %d hauled %d | %4.0f m, %3.0f deg/100m, %d trips detour x%.2f, bunched %.0fs" % [nm, st["type"], mins, fpm, turn,
			clip * 100.0, float(lg.get("junk", 0.0)), int(lg.get("bales", 0.0)), int(lg.get("hauled", 0.0)), float(st["m"]), deg100, int(st["trips"]), detour, float(st["bunch_t"])])
		if str(st["type"]) == "haulbug":
			h_m += float(st["m"])
			h_turn += float(st["turn"])
			h_path += float(st["trip_path"])
			h_line += float(st["trip_line"])
			h_bunch += float(st["bunch_t"])
			h_t += float(st["t"])
			h_flips += float(st["flips"])
		worst_f = maxf(worst_f, fpm)
		worst_c = maxf(worst_c, clip)
	var obs_n: int = (crew.swarm.obstacles as Array).size() if crew.swarm else 0
	var avg_f: float = tot_flips / maxf(tot_min, 0.01)
	var avg_c: float = float(tot_in) / maxf(float(tot_n), 1.0)
	var ok: bool = avg_f <= MAX_FLIPS_PER_MIN and avg_c <= MAX_CLIP
	if h_t > 0.0:  # [v6crew] the Haul Bugs on their own: weaving and bunching
		print("[motion] haulers: %.0f m, reversals/min %.1f, %.0f deg/100m, detour x%.2f, bunched %.1f%% of the time" % [h_m, h_flips / (h_t / 60.0),
			rad_to_deg(h_turn) / maxf(h_m, 1.0) * 100.0, h_path / maxf(h_line, 1.0), h_bunch / h_t * 100.0])
	print("[motion] %d near robots watched, %d building circles nearby, %d blocked hexes: reversals/min %.1f (worst %.1f), in buildings %.2f%% (worst %.1f%%) %s" % [
		_s.size(), obs_n, crew.blocked.size(), avg_f, worst_f, avg_c * 100.0, worst_c * 100.0, "PASS" if ok else "FAIL"])
	return ok
