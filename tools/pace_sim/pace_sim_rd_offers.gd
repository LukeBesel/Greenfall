class_name PaceSimRdOffers
extends RefCounted
## Builds the list of things the redesign model has on offer at the bench right now, with their
## costs: track levels, one-off unlocks, research nodes, robots, robot repairs and rig modules.
## Every offer costs one currency only (design spec section 14: one job per currency).


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
	var crew_row: Dictionary = {"crew": true}
	var cfg: Dictionary = m.data.tables["robots"]
	var room: bool = m.robot_total() < m.crew_cap()
	var by_hand: bool = m.assemblers() == 0
	for id: String in m.data.robot_types:
		var row: Dictionary = m.data.robot_types[id]
		if not m.conditions_met(row):
			continue
		var have: int = m.robots.get(id, 0)
		var is_repaired: bool = m.repaired.get(id, 0) > 0
		# Lumi builds by hand until an Assembler stands; after that only the first of a type,
		# and further Assemblers.
		if room and have < int(row.get("max", have + 1)) and (by_hand or have == 0 or id == str(cfg["chain"]["assembler"])):
			out.append(_offer("robot", id, 0.0, m.robot_parts(id), crew_row))
		if have > 0 and not is_repaired and m.owned.has(str(cfg["repair_requires"])):
			out.append(_offer("repair", id, 0.0, float(row["repair_parts"]) + float(row["parts"]) * float(cfg["repair_per_robot"]) * float(have), crew_row))


static func _modules(m: PaceSimRdModel, out: Array[Dictionary]) -> void:
	for id: String in m.data.modules:
		var row: Dictionary = m.data.modules[id]
		if m.owned.has(id) or str(row["source"]) != "build" or int(row.get("district", 0)) >= m.unlocked:
			continue
		if not m.owned.has(str(m.data.tables["rigs"]["slot_unlock"][str(row["slot"])])):
			continue
		out.append(_offer("module", id, float(row["cost"].get("cubes", 0.0)), float(row["cost"].get("parts", 0.0)), row))
