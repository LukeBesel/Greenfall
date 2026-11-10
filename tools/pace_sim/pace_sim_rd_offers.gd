class_name PaceSimRdOffers
extends RefCounted
## Builds the list of things the redesign model has on offer at the bench right now, with their
## costs: track levels, one-off unlocks, research nodes, robots, Mk refits and rig modules.


## Every offer as {type, id, cubes, parts, gate, crew}.
static func build(m: PaceSimRdModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_tracks(m, out)
	_unlocks(m, out)
	_research(m, out)
	_robots(m, out)
	_modules(m, out)
	return out


static func _offer(type: String, id: String, cubes: float, parts: float, row: Dictionary) -> Dictionary:
	return {"type": type, "id": id, "cubes": cubes, "parts": parts, "gate": bool(row.get("gate", false)), "crew": bool(row.get("crew", false))}


static func _tracks(m: PaceSimRdModel, out: Array[Dictionary]) -> void:
	for id: String in m.data.tracks:
		var row: Dictionary = m.data.tracks[id]
		var level: int = m.levels.get(id, 0)
		var cost: float = m.data.track_cost(id, level)
		if cost < 0.0 or m.data.track_tier(id, level) >= m.unlocked:
			continue
		if row.has("requires") and not m.owned.has(str(row["requires"])):
			continue
		out.append(_offer("track", id, cost, 0.0, row))


static func _unlocks(m: PaceSimRdModel, out: Array[Dictionary]) -> void:
	for id: String in m.data.unlocks:
		var row: Dictionary = m.data.unlocks[id]
		if m.owned.has(id) or not row.has("cost") or not m.conditions_met(row):
			continue
		out.append(_offer("unlock", id, float(row["cost"].get("cubes", 0.0)), float(row["cost"].get("parts", 0.0)), row))


static func _research(m: PaceSimRdModel, out: Array[Dictionary]) -> void:
	if m.research_active != "":
		return
	for id: String in m.data.nodes:
		var row: Dictionary = m.data.nodes[id]
		if m.owned.has(id) or not m.conditions_met(row):
			continue
		var offer: Dictionary = _offer("research", id, float(row["cost"].get("cubes", 0.0)), float(row["cost"].get("parts", 0.0)), row)
		offer["data"] = float(row["cost"].get("data", 0.0))
		out.append(offer)


static func _robots(m: PaceSimRdModel, out: Array[Dictionary]) -> void:
	var cfg: Dictionary = m.data.tables["robots"]
	var tiers: Array = cfg["tiers"]
	for id: String in m.data.robot_types:
		var row: Dictionary = m.data.robot_types[id]
		if not m.conditions_met(row):
			continue
		var have: int = m.robots.get(id, 0)
		var crew_row: Dictionary = {"crew": true}
		if have < int((row["cap"] as Array)[m.base_level - 1]):
			out.append(_offer("robot", id, float(row["cost"]["cubes"]) * pow(float(cfg["cost_growth"]), float(have)),
				float(row["cost"]["parts"]) * pow(float(cfg["parts_growth"]), float(have)), crew_row))
		var next_tier: int = m.mk.get(id, 0) + 1
		if have > 0 and next_tier < tiers.size() and m.owned.has(str(tiers[next_tier]["requires"])):
			var mult: float = float(tiers[next_tier]["cost_mult"]) * float(have)
			out.append(_offer("mk", id, float(row["cost"]["cubes"]) * mult, float(row["cost"]["parts"]) * mult, crew_row))


static func _modules(m: PaceSimRdModel, out: Array[Dictionary]) -> void:
	for id: String in m.data.modules:
		var row: Dictionary = m.data.modules[id]
		if m.owned.has(id) or str(row["source"]) != "build" or int(row.get("district", 0)) >= m.unlocked:
			continue
		if not m.owned.has(str(m.data.tables["rigs"]["slot_unlock"][str(row["slot"])])):
			continue
		out.append(_offer("module", id, float(row["cost"].get("cubes", 0.0)), float(row["cost"].get("parts", 0.0)), row))
