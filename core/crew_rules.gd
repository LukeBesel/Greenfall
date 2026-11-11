class_name CrewRules
extends RefCounted
## Crew size and robot prices, read from a planet's "robots" table (design spec section 14). Pure
## rules with no state: the fleet, the Assembler, the bot and the simulators all ask here, so a
## number is tuned in one place, the table.
##
## Table keys (each explained in the table's own _doc):
##   crew_cap {by_base_level: [..], by_cities_open: [..]}   most robots in all
##   price {parts_growth, cubes_growth, tier_per_robot, tier_max_parts, tier_cities_open}
##   tiers [{name, look, mult, build_mult}]                 robot tiers
##   types[] {parts, cost, tier_parts: [..]}                per type
## A table from before these keys keeps its old cap rule (base + per_level x base level) and gets
## fixed prices.
##
## Use: CrewRules.cap(Economy.robot_cfg, base_level, cities_open)

const KEY_CAP: String = "crew_cap"
const KEY_PRICE: String = "price"
const KEY_TIERS: String = "tiers"
## A table with no cap of any kind: the rule tables before crew caps were data.
const LEGACY_BASE: int = 3
const LEGACY_PER_LEVEL: int = 3


## The most robots the crew may hold: the smaller of the base level's and the open cities' limit.
static func cap(cfg: Dictionary, base_level: int, cities_open: int) -> int:
	var c: Dictionary = cfg.get(KEY_CAP, {})
	var by_level: Array = c.get("by_base_level", [])
	var by_cities: Array = c.get("by_cities_open", [])
	if by_level.is_empty() and by_cities.is_empty():
		return int(c.get("base", LEGACY_BASE)) + int(c.get("per_level", LEGACY_PER_LEVEL)) * maxi(base_level, 1)
	var out: int = -1
	if not by_level.is_empty():
		out = int(by_level[clampi(base_level - 1, 0, by_level.size() - 1)])
	if not by_cities.is_empty():
		var n: int = int(by_cities[clampi(cities_open - 1, 0, by_cities.size() - 1)])
		out = n if out < 0 else mini(out, n)
	return out


## The cap at the next base level with the same cities open (the same number when the base level
## is not what holds the crew back). For "what does the next level give" texts.
static func cap_gain_at_level(cfg: Dictionary, base_level: int, cities_open: int) -> int:
	return cap(cfg, base_level + 1, cities_open) - cap(cfg, base_level, cities_open)


## Parts for the next robot of a type: its price, times the growth for each one owned, times the
## build multiplier of the tier the type stands at. Whole Parts, rounded up.
static func build_parts(cfg: Dictionary, type_def: Dictionary, owned: int, tier: int) -> float:
	var growth: float = float((cfg.get(KEY_PRICE, {}) as Dictionary).get("parts_growth", 1.0))
	return ceilf(float(type_def.get("parts", 0.0)) * pow(growth, float(owned)) * _build_mult(cfg, tier))


## Cubes for the next robot of a type (0 where robots cost Parts only).
static func build_cubes(cfg: Dictionary, type_def: Dictionary, owned: int) -> float:
	var growth: float = float((cfg.get(KEY_PRICE, {}) as Dictionary).get("cubes_growth", 1.0))
	return float(type_def.get("cost", 0.0)) * pow(growth, float(owned))


## Number of tiers a robot type can stand at on this planet.
static func tier_count(cfg: Dictionary) -> int:
	return (cfg.get(KEY_TIERS, []) as Array).size()


## Parts to raise a type from `tier` to the next: the type's own step price plus a share of its
## build price for every robot of the type already owned (they are all rebuilt), never more than
## the table's tier_max_parts. -1 when there is no next tier.
static func tier_parts(cfg: Dictionary, type_def: Dictionary, tier: int, owned: int) -> float:
	if tier + 1 >= tier_count(cfg):
		return -1.0
	var steps: Array = type_def.get("tier_parts", [])
	var step: float = float(steps[clampi(tier, 0, steps.size() - 1)]) if not steps.is_empty() else 0.0
	var price: Dictionary = cfg.get(KEY_PRICE, {})
	var total: float = ceilf(step + float(price.get("tier_per_robot", 0.0)) * float(type_def.get("parts", 0.0)) * float(owned))
	return minf(total, float(price["tier_max_parts"])) if price.has("tier_max_parts") else total


## Whether tier steps are on offer yet: the table's price.tier_cities_open is the number of cities
## that must be open (a better crew is a choice from the city where Parts open up).
static func tiers_open(cfg: Dictionary, cities_open: int) -> bool:
	return cities_open >= int((cfg.get(KEY_PRICE, {}) as Dictionary).get("tier_cities_open", 1))


## Cubes for the same step (the tier row's cost_mult times the type's cube price; 0 where robots
## cost Parts only).
static func tier_cubes(cfg: Dictionary, type_def: Dictionary, tier: int) -> float:
	var tiers: Array = cfg.get(KEY_TIERS, [])
	if tier + 1 >= tiers.size():
		return 0.0
	return float(type_def.get("cost", 0.0)) * float((tiers[tier + 1] as Dictionary).get("cost_mult", 0.0))


## The dearest Parts price the crew can ask for with `owned` robots of every type: a build, a
## tier step or a fleet upgrade level. The tests hold it under the planet's largest Parts price.
static func dearest_parts(cfg: Dictionary, owned: int) -> float:
	var out: float = 0.0
	var top: int = maxi(tier_count(cfg) - 1, 0)
	for raw: Variant in cfg.get("types", []):
		var t: Dictionary = raw
		out = maxf(out, build_parts(cfg, t, owned, top))
		for tier: int in top:
			out = maxf(out, tier_parts(cfg, t, tier, owned))
		for u: Variant in t.get("upgrades", []):
			var ud: Dictionary = u
			out = maxf(out, float(ud.get("base_cost", 0.0)) * pow(float(ud.get("growth", 1.0)), float(int(ud.get("max_level", 1)) - 1)))
	return out


static func _build_mult(cfg: Dictionary, tier: int) -> float:
	var tiers: Array = cfg.get(KEY_TIERS, [])
	if tiers.is_empty():
		return 1.0
	return float((tiers[clampi(tier, 0, tiers.size() - 1)] as Dictionary).get("build_mult", 1.0))
