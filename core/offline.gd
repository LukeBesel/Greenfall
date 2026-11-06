class_name Offline
extends RefCounted
## Offline progress: computed from aggregated rates (never by simulating ticks).
## Cleaners earn bale value at OFFLINE_RATE of their online rate, delivered only if the fleet has
## at least one hauler (otherwise the bales are counted as "waiting at the hub"). Air scrubbers
## keep filtering. World geometry is not advanced offline (assumption: keeps saves simple; the
## player still sees their own progress happen live).

const OFFLINE_RATE: float = 0.5
const CAP_S: float = 8.0 * 3600.0
const AVG_VALUE_PER_UNIT: float = 0.75


## junk_left caps the junk volume the fleet can bale offline (the district's remaining junk), so a
## fully clean district stops paying out (no infinite income from closing and reopening the game).
static func compute(robots: Array, scrubbers: int, filter_per_s: float, elapsed_s: float, junk_left: float = INF) -> Dictionary:
	var t: float = clampf(elapsed_s, 0.0, CAP_S)
	var units: float = 0.0
	var haulers: int = 0
	for r: Dictionary in robots:
		var type_id: String = str(r.get("type", ""))
		var role: String = str(Economy.robots.get(type_id, {}).get("role", "clean"))
		var tier: int = int(r.get("tier", 0))
		if role == "haul":
			haulers += 1
			continue
		# Seconds per piece: travel + pick. Roughly 0.9 units of junk per piece.
		var rate: float = Economy.robot_stat(type_id, "scoop_rate", tier) * 0.35
		units += rate * 0.9 * t * OFFLINE_RATE
	units = minf(units, maxf(junk_left, 0.0))
	var eff: float = 1.0
	if not robots.is_empty():
		eff = Economy.robot_stat(str(robots[0].get("type", "scoopie")), "efficiency", int(robots[0].get("tier", 0)))
	var value: float = units * AVG_VALUE_PER_UNIT * eff
	return {
		"seconds": t,
		"units": units,
		"cubes": value if haulers > 0 else 0.0,
		"waiting_value": 0.0 if haulers > 0 else value,
		"air": scrubbers * filter_per_s * t,
	}


static func apply(result: Dictionary) -> void:
	if float(result["cubes"]) > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(float(result["cubes"])))
	# With no hauler the bales pile up at the hub; Patch cashes them in on his way back.
	if float(result.get("waiting_value", 0.0)) > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(float(result["waiting_value"])))
	GameState.inc_stat("air_filtered", float(result["air"]))


static func summary_text(result: Dictionary) -> String:
	var t: float = float(result["seconds"])
	var when: String = ("%d min" % int(t / 60.0)) if t < 3600.0 else ("%.1f h" % (t / 3600.0))
	var lines: Array[String] = ["While you were away (%s):" % when]
	if float(result["cubes"]) > 0.0:
		lines.append("The fleet baled and delivered %s cubes." % Settings.fmt(BigNum.from_float(float(result["cubes"]))))
	elif float(result["waiting_value"]) > 0.0:
		lines.append("Bales worth %s were stacked at the hub with nobody to haul them. Lumi cashed them in. A Haul Bug would keep them moving." % Settings.fmt(BigNum.from_float(float(result["waiting_value"]))))
	if float(result["air"]) > 0.0:
		lines.append("The scrubbers filtered the air the whole time. It's a little clearer.")
	return "\n".join(lines)
