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
const MAX_FLIPS_PER_MIN: float = 6.0
const MAX_CLIP: float = 0.01
const MIN_TRAVEL: float = 0.5  # m/s

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
			st = {"type": u["type"], "h": b.heading, "w": 0.0, "flip_t": INF, "flips": 0, "t": 0.0, "move_t": 0.0, "turn": 0.0, "in": 0, "n": 0}
			_s[u["name"]] = st
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
	var ok: bool = true
	var tot_flips: float = 0.0
	var tot_min: float = 0.0
	var tot_in: int = 0
	var tot_n: int = 0
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
		print("[motion] %-12s %-8s %4.1f min  reversals/min %4.1f  turn %.2f rad/s  in buildings %4.1f%%  junk %.0f bales %d hauled %d" % [nm, st["type"], mins, fpm, turn,
			clip * 100.0, float(lg.get("junk", 0.0)), int(lg.get("bales", 0.0)), int(lg.get("hauled", 0.0))])
		if fpm > MAX_FLIPS_PER_MIN or clip > MAX_CLIP:
			ok = false
	var obs_n: int = (crew.swarm.obstacles as Array).size() if crew.swarm else 0
	print("[motion] %d near robots watched, %d building circles nearby, %d blocked hexes: reversals/min %.1f, in buildings %.2f%% %s" % [
		_s.size(), obs_n, crew.blocked.size(), tot_flips / maxf(tot_min, 0.01), float(tot_in) / maxf(float(tot_n), 1.0) * 100.0, "PASS" if ok else "FAIL"])
	return ok
