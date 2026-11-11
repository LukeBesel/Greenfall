class_name MasteryRules
extends RefCounted
## The mastery rules (design spec section 3) as plain maths with no state, so the game
## (systems/mastery.gd) and the simulators (tools/pace_sim, tools/crew_sim) share one copy.
##
## Lumi's own work on a pollution kind fills that kind's mastery, level 0 to max_level:
##   level L is held at  level1_units x growth^(L-1)  units of hand work in all
##   Lumi's rate on the kind      1 + hand_bonus_per_level x level
##   a robot's rate on the kind   base + per_level x level, and 0 under min_level (it may not
##                                work the kind at all)
##   a robot within radius_m of Lumi works (1 + bonus) times as fast
##
## Numbers come from two planet tables: "pollution_kinds" (the `mastery` block and each kind's
## mastery_level1_units and mastery_per_unit) and "robots" (`mastery_speed`, `proximity`). A
## planet without a robots table may give the last two inside its `mastery` block as robot_speed
## and proximity. A planet without a `mastery` block has no mastery: every factor is 1.
##
## Use: var cfg := MasteryRules.config(def.table("pollution_kinds"), def.table("robots"))

const KEY: String = "mastery"
const KEY_SPEED: String = "mastery_speed"
const KEY_NEAR: String = "proximity"


## The rules of a planet in one dictionary: {enabled, max_level, growth, hand_bonus, legacy_credit,
## robot_base, robot_per_level, robot_min, dev_level, near_m, near_bonus, hand_share,
## kinds: {id: {level1, per_unit, name, roles}}}.
static func config(kinds_table: Dictionary, robots_table: Dictionary) -> Dictionary:
	var block: Dictionary = kinds_table.get(KEY, {})
	var speed: Dictionary = robots_table.get(KEY_SPEED, block.get("robot_speed", {}))
	var near: Dictionary = robots_table.get(KEY_NEAR, block.get("proximity", {}))
	var kinds: Dictionary = {}
	var raw: Dictionary = kinds_table.get("kinds", {})
	for id: String in raw:
		var kd: Dictionary = raw[id]
		kinds[id] = {"level1": float(kd.get("mastery_level1_units", 0.0)), "per_unit": float(kd.get("mastery_per_unit", 1.0)),
			"name": str(kd.get("name", id)), "roles": kd.get("robot_roles", [])}
	return {
		"enabled": not block.is_empty(),
		"max_level": int(block.get("max_level", 0)),
		"growth": maxf(float(block.get("growth", 1.0)), 1.0),
		"hand_bonus": float(block.get("hand_bonus_per_level", 0.0)),
		"legacy_credit": float(block.get("legacy_credit", 1.0)),
		"hand_share": block.get("hand_share", {}),
		"robot_base": float(speed.get("base", 1.0)),
		"robot_per_level": float(speed.get("per_level", 0.0)),
		"robot_min": int(speed.get("min_level", 0)),
		"dev_level": int(speed.get("dev_level", int(block.get("max_level", 0)))),
		"near_m": float(near.get("radius_m", 0.0)),
		"near_bonus": float(near.get("bonus", 0.0)),
		"kinds": kinds,
	}


static func enabled(cfg: Dictionary) -> bool:
	return bool(cfg.get("enabled", false))


## Whether a kind takes part in mastery (a kind with no level1 units never levels: always open).
static func tracks(cfg: Dictionary, kind: String) -> bool:
	return enabled(cfg) and float((cfg["kinds"] as Dictionary).get(kind, {}).get("level1", 0.0)) > 0.0


## Units of hand work on a kind, in all, that hold `level` (0 for level 0).
static func units_for(cfg: Dictionary, kind: String, level: int) -> float:
	if level <= 0 or not tracks(cfg, kind):
		return 0.0
	return float(cfg["kinds"][kind]["level1"]) * pow(float(cfg["growth"]), float(level - 1))


## The level `units` of hand work on a kind hold.
static func level_for(cfg: Dictionary, kind: String, units: float) -> int:
	if not tracks(cfg, kind):
		return 0
	var level: int = 0
	while level < int(cfg["max_level"]) and units >= units_for(cfg, kind, level + 1) - 0.0001:
		level += 1
	return level


## Mastery one unit of Lumi's work on a kind gives.
static func gain(cfg: Dictionary, kind: String, amount: float) -> float:
	return amount * float((cfg["kinds"] as Dictionary).get(kind, {}).get("per_unit", 1.0)) if tracks(cfg, kind) else 0.0


## Lumi's rate multiplier on a kind at `level`.
static func hand_bonus(cfg: Dictionary, level: int) -> float:
	return 1.0 + float(cfg.get("hand_bonus", 0.0)) * float(level) if enabled(cfg) else 1.0


## Whether robots may work a kind at `level` at all.
static func robots_allowed(cfg: Dictionary, kind: String, level: int) -> bool:
	return not tracks(cfg, kind) or level >= int(cfg["robot_min"])


## A robot's rate multiplier on a kind at `level` (0 while robots may not work it).
static func robot_factor(cfg: Dictionary, kind: String, level: int) -> float:
	if not tracks(cfg, kind):
		return 1.0
	if level < int(cfg["robot_min"]):
		return 0.0
	return float(cfg["robot_base"]) + float(cfg["robot_per_level"]) * float(level)


## Rate multiplier of a robot working `dist_m` metres from Lumi.
static func near_factor(cfg: Dictionary, dist_m: float) -> float:
	if not enabled(cfg) or float(cfg["near_m"]) <= 0.0 or dist_m > float(cfg["near_m"]):
		return 1.0
	return 1.0 + float(cfg["near_bonus"])


## Kind ids a robot role works, in table order.
static func kinds_of_role(cfg: Dictionary, role: String) -> Array[String]:
	var out: Array[String] = []
	var kinds: Dictionary = cfg.get("kinds", {})
	for id: String in kinds:
		if role in (kinds[id]["roles"] as Array):
			out.append(id)
	return out
