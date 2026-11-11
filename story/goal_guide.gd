class_name GoalGuide
extends RefCounted
## Where a goal sends the player (story/goals.gd), in the same form as a story step's guidance
## (Objectives.step_target): {"to": "bench" | "depot" | "bin" | "hex" | "place" | "source",
## "row": [tab, row id] or [], "pos": Vector3 or null, "district": id (for "source")}.
## "hex" = the nearest dirty hex, outlined on the ground; "source" = the city's source job.
## A goal's own `guide` entry in the planet's table wins; otherwise the goal's type decides.

const TO_BENCH: String = "bench"
const TO_DEPOT: String = "depot"
const TO_BIN: String = "bin"
const TO_HEX: String = "hex"
const TO_PLACE: String = "place"
const TO_SOURCE: String = "source"

## Lifetime stats that rise at the workbench, at the scale, and out on the ground.
const BENCH_STATS: Array[String] = ["upgrades_bought", "robots_built", "research_done", "robots_assembled", "looks_worn"]
const DEPOT_STATS: Array[String] = ["cubes_cashed", "junk_dumps", "robot_bales"]
## The workbench tab a bench stat is raised on ("" = the tab the bench opens on).
const STAT_TABS: Dictionary = {"research_done": "research", "robots_built": "bots", "robots_assembled": "bots"}


static func target(world: Node, def: Dictionary) -> Dictionary:
	var guide: Variant = def.get("guide", null)
	if guide is Dictionary:
		var out: Dictionary = {"to": str((guide as Dictionary).get("to", TO_HEX)), "row": (guide as Dictionary).get("row", [])}
		if (guide as Dictionary).has("district"):
			out["district"] = str((guide as Dictionary)["district"])
		return out
	var key: String = str(def.get("key", ""))
	var patch: Patch = world.get("patch") as Patch if world else null
	var carrying: bool = patch != null and not patch.carried.is_empty()
	match str(def.get("type", "stat")):
		"upgrade":
			return {"to": TO_BENCH, "row": ["patch", key]}
		"robot", "tier":
			return {"to": TO_BENCH, "row": ["bots", ""]}
		"research":
			return {"to": TO_BENCH, "row": ["research", key]}
		"hub_level":
			return {"to": TO_BENCH, "row": ["patch", "hub_level"]}
		"rig":
			return {"to": TO_BENCH, "row": ["rigs", key]}
		"build":
			return {"to": TO_BENCH, "row": ["build", key]}
		"earned":
			return {"to": TO_DEPOT if carrying else TO_HEX, "row": []}
		"source":
			return {"to": TO_SOURCE, "district": key, "row": []}
		"flag":
			if key == "seeds_unlocked" and world != null and world.get("first_seed") != null:
				return {"to": TO_PLACE, "pos": (world.get("first_seed") as FirstSeed).greenhouse_point(), "row": []}
		"stat":
			return _stat_target(key, patch, carrying)
	return {"to": TO_HEX, "row": []}


static func _stat_target(key: String, patch: Patch, carrying: bool) -> Dictionary:
	if key == "junk_dumps":  # the chest goes into the bin's body, not onto the scale
		return {"to": TO_BIN if patch != null and not patch.compartment.is_empty() else TO_HEX, "row": []}
	if key in DEPOT_STATS:
		return {"to": TO_DEPOT if key != "cubes_cashed" or carrying else TO_HEX, "row": []}
	if key in BENCH_STATS:
		var tab: String = str(STAT_TABS.get(key, ""))
		return {"to": TO_BENCH, "row": [tab, ""] if tab != "" else []}
	return {"to": TO_HEX, "row": []}
