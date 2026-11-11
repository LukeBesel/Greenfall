class_name Offline
extends RefCounted
## Offline progress: computed from aggregated rates (never by simulating ticks).
## Cleaners clean at OFFLINE_RATE of their online rate and earn no cubes (robots never do: design
## spec section 16.1). Air scrubbers keep filtering. World geometry is not advanced offline (assumption: keeps saves simple; the
## player still sees their own progress happen live).

const OFFLINE_RATE: float = 0.5
const CAP_S: float = 8.0 * 3600.0


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
		units += unit_rate(type_id, tier) * t * OFFLINE_RATE
	units = minf(units, maxf(junk_left, 0.0))
	# Robots earn no cubes (design spec section 16.1): the time away cleans, it does not pay. The
	# two cube keys stay in the result at zero for the welcome-back card and older callers.
	return {
		"seconds": t,
		"units": units,
		"haulers": haulers,
		"cubes": 0.0,
		"waiting_value": 0.0,
		"air": scrubbers * filter_per_s * t,
	}


## [orbC] Junk units one cleaner robot takes per second while it works (its online rate):
## seconds per piece = travel + pick, roughly 0.9 units of junk per piece. Offline earns
## OFFLINE_RATE of this; far crews on the round planet (robots/sphere/sphere_crew.gd) earn it in
## full. One code path for "off-screen" and "offline".
static func unit_rate(type_id: String, tier: int) -> float:
	return Economy.robot_stat(type_id, "scoop_rate", tier) * 0.35 * 0.9


## [extras] The one entry point for idle gains on a district (the welcome-back card): what `world_state` (a
## GameState.districts entry) earns over `seconds` away. Hard cap: CAP_S of time, and the junk the
## district has left. Junk already paid for offline (`world_state.offline_units`) is counted against
## what is left and the new units are added to it, so calling this again for the same time (or the
## same junk from another view) never pays twice. Does NOT add currency: call `apply()` once on the
## result. Arguments:
##   junk_left      the district's remaining junk volume; < 0 reads world_state.junk_left (written
##                  at every save by systems/extras/extras_director.gd; 0 if never saved)
##   scrubbers, filter_per_s   the base's air scrubbers
##   garden         the live Garden to grow (optional; null grows no plants)
## Returns compute()'s keys plus: away_raw (uncapped seconds), robots (the fleet), and garden
## {grew, bloomed, seeds, hexes} (the seeds are credited by apply()).
static func simulate(world_state: Dictionary, seconds: float, junk_left: float = -1.0, scrubbers: int = 0, filter_per_s: float = 1.0, garden: Garden = null) -> Dictionary:
	var robots: Array = world_state.get("robots", [])
	if junk_left < 0.0:
		junk_left = float(world_state.get("junk_left", 0.0))
	junk_left = maxf(0.0, junk_left - float(world_state.get("offline_units", 0.0)))
	var res: Dictionary = compute(robots, scrubbers, filter_per_s, seconds, junk_left)
	world_state["offline_units"] = float(world_state.get("offline_units", 0.0)) + float(res["units"])
	res["away_raw"] = maxf(seconds, 0.0)
	res["robots"] = robots.duplicate(true)
	var g: Dictionary = {"grew": 0, "bloomed": 0, "seeds": 0.0, "hexes": {}}
	if garden != null:
		g = grow_garden(garden, float(res["seconds"]), has_waterer(robots), maxf(Economy.stat("plant_growth"), 0.1), maxf(Economy.stat("seed_yield"), 0.1))
	res["garden"] = g
	res["garden_grown"] = garden != null
	return res


## [extras] Planted slots keep growing while watered, at OFFLINE_RATE (moves the Garden's arrays).
## Slots dry out on their own water unless the fleet has a waterer. A plant blooms (and pays seeds)
## once, so reopening the game can't farm it. Returns {grew, bloomed, seeds, hexes}.
static func grow_garden(g: Garden, seconds: float, waterer: bool, grow_mult: float = 1.0, seed_mult: float = 1.0) -> Dictionary:
	var out: Dictionary = {"grew": 0, "bloomed": 0, "seeds": 0.0, "hexes": {}}
	if g == null or seconds <= 0.0:
		return out
	seconds = minf(seconds, CAP_S)
	for s: int in g.slot_species.size():
		if g.slot_species[s] < 0 or g.slot_stage[s] >= 4:
			continue
		var sp: Dictionary = g.species[g.slot_species[s]]
		var wet_s: float = seconds if waterer else minf(seconds, g.slot_water[s])
		if not waterer:
			g.slot_water[s] = maxf(0.0, g.slot_water[s] - seconds)
		if wet_s <= 0.0:
			continue
		var before: int = g.slot_stage[s]
		var prog: float = g.slot_progress[s] + wet_s * OFFLINE_RATE * grow_mult / float(sp.get("grow_s", 40))
		while prog >= 1.0 and g.slot_stage[s] < 4:
			prog -= 1.0
			g.slot_stage[s] += 1
			if g.slot_stage[s] == 4:
				out["bloomed"] = int(out["bloomed"]) + 1
				out["seeds"] = float(out["seeds"]) + float(sp.get("seed_yield", 0.5)) * seed_mult
		g.slot_progress[s] = 0.0 if g.slot_stage[s] >= 4 else prog
		if g.slot_stage[s] != before:
			out["grew"] = int(out["grew"]) + 1
			(out["hexes"] as Dictionary)[g.slot_hex[s]] = true
	return out


static func has_waterer(robots: Array) -> bool:
	for r: Dictionary in robots:
		var role: String = str(Economy.robots.get(str(r.get("type", "")), {}).get("role", ""))
		if role == "water" or role == "any":
			return true
	return false


static func apply(result: Dictionary) -> void:
	var gr: Dictionary = result.get("garden", {})  # [extras] simulate()'s garden: seeds and bloom count
	if float(gr.get("seeds", 0.0)) > 0.0:
		GameState.add_currency("seeds", BigNum.from_float(float(gr["seeds"])))
	if int(gr.get("bloomed", 0)) > 0:
		GameState.inc_stat("plants_bloomed", float(gr["bloomed"]))
	GameState.inc_stat("air_filtered", float(result["air"]))


static func summary_text(result: Dictionary) -> String:
	var t: float = float(result["seconds"])
	var when: String = (TranslationServer.translate("%d min") % int(t / 60.0)) if t < 3600.0 else ("%.1f h" % (t / 3600.0))
	var lines: Array[String] = [TranslationServer.translate("While you were away (%s):") % when]
	if float(result.get("units", 0.0)) > 0.0:
		lines.append(TranslationServer.translate("The crew kept cleaning. The city is a little clearer."))
	if float(result["air"]) > 0.0:
		lines.append(TranslationServer.translate("The scrubbers filtered the air the whole time. It's a little clearer."))
	return "\n".join(lines)
