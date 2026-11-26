class_name CrewRate
extends RefCounted
## How fast robots work, as plain numbers: junk units a second per robot and what a unit is worth.
## Used by the crews that work while the game runs: far crews on the round planet
## (robots/sphere/sphere_crew.gd) and the crews of other planets (systems/remote_progress.gd).
## Nothing here reads a clock. Owner item 110: robots only work while the game is running, so
## no rate for a closed game exists; time that passes with the game off counts for nothing.

const AVG_VALUE_PER_UNIT: float = 0.75


## Junk units one cleaner robot takes per second while it works: seconds per piece = travel +
## pick, roughly 0.9 units of junk per piece.
static func unit_rate(type_id: String, tier: int) -> float:
	return Economy.robot_stat(type_id, "scoop_rate", tier) * 0.35 * 0.9


## Cube value of `units` of baled junk for this fleet (the first robot's efficiency).
static func units_value(robots: Array, units: float) -> float:
	var eff: float = 1.0
	if not robots.is_empty():
		eff = Economy.robot_stat(str(robots[0].get("type", "scoopie")), "efficiency", int(robots[0].get("tier", 0)))
	return units * AVG_VALUE_PER_UNIT * eff


## What a fleet [{type, tier}] bales in `play_s` seconds of play at `pace` (1 = the full rate),
## never more than `junk_left` units. Haulers carry, they don't clean. With no hauler the bales
## wait at the base (waiting_value); Lumi cashes them in all the same.
## Returns {seconds, units, cubes, waiting_value}.
static func fleet_work(robots: Array, play_s: float, junk_left: float = INF, pace: float = 1.0) -> Dictionary:
	var t: float = maxf(play_s, 0.0)
	var units: float = 0.0
	var haulers: int = 0
	for r: Dictionary in robots:
		var type_id: String = str(r.get("type", ""))
		if str(Economy.robots.get(type_id, {}).get("role", "clean")) == "haul":
			haulers += 1
			continue
		units += unit_rate(type_id, int(r.get("tier", 0))) * t * maxf(pace, 0.0)
	units = minf(units, maxf(junk_left, 0.0))
	var value: float = units_value(robots, units)
	return {"seconds": t, "units": units, "cubes": value if haulers > 0 else 0.0, "waiting_value": 0.0 if haulers > 0 else value}
