class_name RigStudy
extends RefCounted
## The rig study (design spec section 7: "No module may be best in every district; the simulator
## checks this"). It reads the planet's own tables (rigs, districts, pollution kinds, player) and
## scores every module of every slot in every city for a Lumi who plays that city with it fitted.
## Nothing here names a planet or a module: a planet with another rig table is studied the same way.
##
## The model, per city (numbers in the rig table's `study` block):
##   - A hex holds the city's kinds in their data shares. Lumi clears a kind at her scoop rate,
##     times the sweep of her arm (width and reach) for pieces, times the kind's hand factor for
##     held kinds, times any kind_<id> mod. A kind whose tool is not fitted she cannot clear.
##   - Her chest fills, she presses a bale (press_s) and walks some bales to the scale herself
##     (lumi_hauls_share of them, carry_stack at a time, at move_speed).
##   - The crew cleans beside her; the share of it near her gets the proximity bonus, which
##     crew_near and crew_radius stretch. Robots work a kind at the rate of Lumi's mastery of it:
##     a kind she keeps working by hand is worked at the practised rate, one she has left to them
##     at the rate of the first level (both from the robots table's mastery_speed).
##   - While a city's own new kind is not learnt, robots must leave every hex that holds it
##     (learn_share of the city's time). Only Lumi's tool learns it: a loadout without that tool
##     never opens those hexes, to her or to the crew, so its score is cut by their share.
##   - Parts come from what she takes, by each kind's parts yield, times parts_yield.
##   The score is cubes a minute, cleaning a minute and Parts a minute, weighted city by city
##   (geometric mean): cubes count most early, the crew's cleaning most once the crew is large.
##
## Use: var study: Dictionary = RigStudy.run(Planets.current())
##      godot --headless --path . res://tools/pace_sim/pace_sim.tscn -- --rig-study=1

const NO_MODULE: String = ""


## {ok, error, cities: [{id, best: {slot: module}, scores: {slot: {module: score}}}], dominant: [module],
## never_best: [module], slots}. A module is dominant when it is the best fit of its slot in every
## city where the slot has a choice (two or more cities).
static func run(def: PlanetDefinition) -> Dictionary:
	var rigs: Dictionary = def.table(Rigs.TABLE) if def else {}
	var out: Dictionary = {"ok": false, "error": "", "cities": [], "dominant": [], "never_best": [], "slots": []}
	if rigs.is_empty() or not rigs.has("study"):
		out["error"] = "the planet has no rig table with a study block"
		return out
	var specs: Array[Dictionary] = Districts.specs_for(def)
	var slots: Array[String] = []
	for row: Variant in rigs.get("slots", []):
		slots.append(str((row as Dictionary)["id"]))
	out["slots"] = slots
	var wins: Dictionary[String, int] = {}
	var judged: Dictionary[String, int] = {}
	for i: int in specs.size():
		var city: Dictionary = {"id": str(specs[i]["id"]), "best": {}, "scores": {}}
		for slot: String in slots:
			var options: Array[String] = _options(rigs, specs, slot, i)
			if options.size() < 2:
				continue
			var scores: Dictionary = {}
			var best: String = NO_MODULE
			for id: String in options:
				scores[id] = score(def, i, {slot: id})
				if best == NO_MODULE or float(scores[id]) > float(scores[best]):
					best = id
			city["scores"][slot] = scores
			city["best"][slot] = best
			wins[best] = wins.get(best, 0) + 1
			judged[slot] = judged.get(slot, 0) + 1
		(out["cities"] as Array).append(city)
	var modules: Dictionary = rigs.get("modules", {})
	for id: String in modules:
		var slot: String = str(modules[id]["slot"])
		if wins.get(id, 0) == 0:
			(out["never_best"] as Array).append(id)
		elif judged.get(slot, 0) >= 2 and wins[id] == judged[slot]:
			(out["dominant"] as Array).append(id)
	out["ok"] = true
	return out


## The modules of a slot whose plan has arrived by city `index`.
static func _options(rigs: Dictionary, specs: Array[Dictionary], slot: String, index: int) -> Array[String]:
	var open: Array[String] = []
	for i: int in index + 1:
		open.append(str(specs[i]["id"]))
	var out: Array[String] = []
	var modules: Dictionary = rigs.get("modules", {})
	for id: String in modules:
		var district: String = str(modules[id].get("district", ""))
		if str(modules[id]["slot"]) == slot and (district == "" or district in open):
			out.append(id)
	return out


## How well a loadout ({slot: module}) serves Lumi in city `index` (higher is better).
static func score(def: PlanetDefinition, index: int, loadout: Dictionary) -> float:
	var rigs: Dictionary = def.table(Rigs.TABLE)
	var study: Dictionary = rigs["study"]
	var specs: Array[Dictionary] = Districts.specs_for(def)
	var learn: float = float(study["learn_share"]) if not _new_kinds(specs, index).is_empty() else 0.0
	var before: Dictionary = _rates(def, index, loadout, true)
	var after: Dictionary = _rates(def, index, loadout, false)
	var weights: Dictionary = study["weights"]
	var total: float = 0.0
	for key: String in weights:
		var rate: float = learn * float(before[key]) + (1.0 - learn) * float(after[key])
		total += float(_at(weights[key], index)) * log(maxf(rate, 0.000001))
	return exp(total) * (1.0 - _stalled(def, index, loadout))


## The share of a city's hexes a loadout can never open: those holding a kind the city is the
## first to hold, when the kind's tool is not in the loadout.
static func _stalled(def: PlanetDefinition, index: int, loadout: Dictionary) -> float:
	var specs: Array[Dictionary] = Districts.specs_for(def)
	var kinds: Dictionary = def.table(Pollution.TABLE).get("kinds", {})
	var shares: Dictionary = _hex_shares(specs[index], kinds, str(def.table(Pollution.TABLE).get("base", "")),
		float(def.table(Rigs.TABLE)["study"]["float_hex_share"]))
	var stalled: float = 0.0
	for id: String in _new_kinds(specs, index):
		var tool: String = str((kinds.get(id, {}).get("gate", {}) as Dictionary).get("module", ""))
		if tool != "" and not (tool in loadout.values()) and shares.has(id):
			stalled = maxf(stalled, float(shares[id]["hexes"]))
	return stalled


## The kinds a city is the first to hold.
static func _new_kinds(specs: Array[Dictionary], index: int) -> Array[String]:
	var seen: Dictionary[String, bool] = {}
	for i: int in index:
		for kind: Variant in specs[i].get("pollution", []):
			seen[str(kind)] = true
	var out: Array[String] = []
	for kind: Variant in specs[index].get("pollution", []):
		if not seen.has(str(kind)):
			out.append(str(kind))
	return out


## {cubes, cleaning, parts} a minute in city `index` with `loadout` fitted. `learning`: the city's
## new kinds are not learnt yet, so robots leave the hexes that hold them.
static func _rates(def: PlanetDefinition, index: int, loadout: Dictionary, learning: bool) -> Dictionary:
	var rigs: Dictionary = def.table(Rigs.TABLE)
	var study: Dictionary = rigs["study"]
	var specs: Array[Dictionary] = Districts.specs_for(def)
	var spec: Dictionary = specs[index]
	var kinds: Dictionary = def.table(Pollution.TABLE).get("kinds", {})
	var base: Dictionary = def.table("player").get("stats", {})
	var scale: float = float(_at(study["hand_scale_by_city"], index))
	var mods: Dictionary = _mods(rigs, loadout)
	var rate: float = float(def.table("player").get("scoop", {}).get("bite_vol", 1.0)) * _stat(base, mods, "pickup_count") * _stat(base, mods, "scoop_rate") * scale
	var sweep: float = sqrt(_mul(mods, "scoop_width") * _mul(mods, "scoop_reach"))
	var fitted: Array = loadout.values()
	var new_kinds: Array[String] = _new_kinds(specs, index)
	var shares: Dictionary = _hex_shares(spec, kinds, str(def.table(Pollution.TABLE).get("base", "")), float(study["float_hex_share"]))
	var work: float = float(spec.get("hex_work", 1.0))
	var seconds: float = 0.0
	var units: float = 0.0
	var value: float = 0.0
	var value_all: float = 0.0
	var parts: float = 0.0
	var shut: float = 0.0
	var speed: Dictionary = def.table("robots").get("mastery_speed", {})
	var practised: float = float(speed.get("base", 1.0)) + float(speed.get("per_level", 0.0)) * float(speed.get("dev_level", 0))
	var left_to_crew: float = (float(speed.get("base", 1.0)) + float(speed.get("per_level", 0.0)) * float(speed.get("min_level", 0))) / maxf(practised, 0.01)
	var crew_share: float = 0.0
	for id: String in shares:
		var kd: Dictionary = kinds.get(id, {})
		var share: float = float(shares[id]["units"])
		var weight: float = float((kd.get("yield", {}) as Dictionary).get("cubes", 1.0))
		value_all += share * weight
		if learning and id in new_kinds:
			shut = maxf(shut, float(shares[id]["hexes"]))
		var tool: String = str((kd.get("gate", {}) as Dictionary).get("module", ""))
		if tool != "" and not (tool in fitted):
			crew_share += share * left_to_crew
			continue
		crew_share += share
		var held: bool = str(kd.get("work", "")) == Pollution.WORK_HELD
		var kind_rate: float = rate * _mul(mods, Rigs.KIND_PREFIX + id) * (float(kd.get("hand_factor", 1.0)) if held else sweep)
		seconds += share * work / kind_rate
		units += share * work
		value += share * weight
		parts += share * work * float((kd.get("yield", {}) as Dictionary).get("parts", 1.0))
	var bales: float = units / maxf(_stat(base, mods, "capacity") * scale, 1.0)
	var walk_s: float = float(spec.get("rings", 1)) * float(study["walk_m_per_ring"]) / maxf(_stat(base, mods, "move_speed"), 0.1)
	seconds += bales * float(study["press_s"]) + bales * float(_at(study["lumi_hauls_share"], index)) / maxf(_stat(base, mods, "carry_stack"), 1.0) * walk_s
	seconds = maxf(seconds, 0.001)
	var near: float = minf(1.0, float(study["crew_near_share"]) * _mul(mods, "crew_radius"))
	var bonus: float = float((def.table("robots").get("proximity", {}) as Dictionary).get("bonus", 0.0)) * _mul(mods, "crew_near")
	var crew: float = float(_at(study["crew_by_city"], index)) * float(study["robot_units_s"]) * (1.0 + near * bonus) * (1.0 - shut) * crew_share
	return {
		"cubes": float(spec.get("hex_cubes", 1.0)) * value / maxf(value_all, 0.001) * _mul(mods, "cube_value_mult") / seconds * 60.0,
		"cleaning": (units / seconds + crew) * 60.0,
		"parts": parts / seconds * float(study["parts_per_unit"]) * _mul(mods, "parts_yield") * 60.0,
	}


## {kind: {units: share of an average hex's waste, hexes: share of the city's hexes that hold it}}.
static func _hex_shares(spec: Dictionary, kinds: Dictionary, base_id: String, float_share: float) -> Dictionary:
	var out: Dictionary = {}
	var water: float = 0.0
	for id: Variant in spec.get("pollution", []):
		if str(kinds.get(str(id), {}).get("work", "")) == Pollution.WORK_FLOAT:
			water = float_share
			out[str(id)] = {"units": water, "hexes": water}
	var rest: float = 1.0 - water
	for id: Variant in spec.get("pollution", []):
		var kd: Dictionary = kinds.get(str(id), {})
		if str(id) == base_id or out.has(str(id)):
			continue
		var spawn: Dictionary = kd.get("spawn", {})
		var hexes: float = float(spawn.get("density", 0.0)) * (1.0 - water)
		var units: float = hexes * float(spawn.get("share", 0.0))
		out[str(id)] = {"units": units, "hexes": hexes}
		rest -= units
	out[base_id] = {"units": maxf(rest, 0.0), "hexes": 1.0 - water}
	return out


## The loadout's multipliers, additions and floors by stat: {mul, add, floor}.
static func _mods(rigs: Dictionary, loadout: Dictionary) -> Dictionary:
	var out: Dictionary = {"mul": {}, "add": {}, "floor": {}}
	for slot: Variant in loadout:
		var row: Dictionary = (rigs.get("modules", {}) as Dictionary).get(str(loadout[slot]), {})
		for key: String in (row.get("mods", {}) as Dictionary):
			out["mul"][key] = float(out["mul"].get(key, 1.0)) * float(row["mods"][key])
		for key: String in (row.get("adds", {}) as Dictionary):
			out["add"][key] = float(out["add"].get(key, 0.0)) + float(row["adds"][key])
		for key: String in (row.get("floors", {}) as Dictionary):
			out["floor"][key] = maxf(float(out["floor"].get(key, -INF)), float(row["floors"][key]))
	return out


static func _mul(mods: Dictionary, key: String) -> float:
	return float(mods["mul"].get(key, 1.0))


static func _stat(base: Dictionary, mods: Dictionary, key: String) -> float:
	return maxf((float(base.get(key, 1.0)) + float(mods["add"].get(key, 0.0))) * _mul(mods, key), float(mods["floor"].get(key, -INF)))


## Entry `index` of a per-city list (the last entry for cities beyond it).
static func _at(list: Variant, index: int) -> Variant:
	var rows: Array = list
	return rows[mini(index, rows.size() - 1)]


## The study as a table: one line per city and slot, then the verdict.
static func lines(study: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	if not bool(study["ok"]):
		out.append("[rig study] " + str(study["error"]))
		return out
	for city: Dictionary in study["cities"]:
		for slot: String in city["scores"]:
			var row: PackedStringArray = []
			var scores: Dictionary = city["scores"][slot]
			var top: float = float(scores[city["best"][slot]])
			for id: String in scores:
				row.append("%s %.0f%%" % [id, float(scores[id]) / top * 100.0])
			out.append("[rig study] %-12s %-6s best %-14s %s" % [city["id"], slot, city["best"][slot], "  ".join(row)])
	out.append("[rig study] dominant: %s" % (", ".join(study["dominant"]) if not (study["dominant"] as Array).is_empty() else "none"))
	out.append("[rig study] never the best fit: %s" % (", ".join(study["never_best"]) if not (study["never_best"] as Array).is_empty() else "none"))
	return out
