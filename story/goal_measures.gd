class_name GoalMeasures
extends RefCounted
## What a goal counts (story/goals.gd): the value of a goal's `type` and `key` in the world being
## played. Every measure reads a lifetime stat, a save flag or a system's public state; a system
## that is not in the world counts as 0, so a goal about it simply waits.
##
## Types: stat, earned, upgrade, robot, tier, zone, hub_level, hex_level, flag, research, and the
## planet measures of systems/restoration.gd (launch, city_stage, cities_restored; city_stage
## also carries the share of the way to the next stage, see city_stage()), plus
## mastery (Lumi's mastery level of pollution kind `key`), source (steps done of city `key`'s
## source job), sources_shut (jobs finished), rig (1 while module `key` is fitted), build (1 once
## base build `key` stands), set_pieces (found pieces of design `key`), pieces (found pieces of
## any look), planet_share (share of the globe restored, 0..1), cities_open (cities unlocked).

const TYPES: Array[String] = ["stat", "earned", "upgrade", "robot", "tier", "zone", "hub_level", "hex_level", "flag", "research",
	Restoration.MEASURE_LAUNCH, Restoration.MEASURE_CITY_STAGE, Restoration.MEASURE_CITIES_RESTORED, "mastery", "source", "sources_shut",
	"rig", "build", "set_pieces", "pieces", "planet_share", "cities_open"]
## How far into the next stage a city_stage value may read before the city gets there.
const STAGE_SHARE_CAP: float = 0.99


static func value(world: Node, def: Dictionary) -> float:
	var key: String = str(def.get("key", ""))
	var type: String = str(def.get("type", "stat"))
	if type == Restoration.MEASURE_CITY_STAGE:
		return city_stage(key)
	var planet_measure: float = Restoration.measure(type, key)
	if planet_measure >= 0.0:
		return planet_measure
	match type:
		"stat":
			return _stat(key)
		"earned":
			return BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
		"upgrade":
			return float(GameState.level_of(key))
		"flag":
			return 1.0 if GameState.flags.get(key, false) else 0.0
		"hub_level":
			return float(GameState.world.get("hub_level", 1))
		"research":
			return 1.0 if Research.has(key) else 0.0
		"zone":
			return float(zone_hex_count())
		"tier":
			return float(_best_tier(key))
		"set_pieces":
			return float(Looks.set_progress(key)[0])
		"pieces":
			return float(Looks.found_count())
	return _world_value(world, type, key, def)


## The measures that ask a system of the world.
static func _world_value(world: Node, type: String, key: String, def: Dictionary) -> float:
	if world == null:
		return 0.0
	match type:
		"robot":
			var fleet: Node = world.get("fleet")
			if fleet == null:
				return 0.0
			return float(fleet.call("robot_total")) if key == "any" else float(fleet.call("count", key))
		"hex_level":
			var levels: HexLevels = world.get("hex_levels") as HexLevels
			return float(levels.count_at_least(int(def.get("key", 1)))) if levels else 0.0
		"mastery":
			var mastery: Mastery = Mastery.of(world)
			return float(mastery.level(key)) if mastery else 0.0
		"rig":
			var rigs: Rigs = Rigs.of(world)
			return 1.0 if rigs and rigs.is_fitted(key) else 0.0
		"build":
			return 1.0 if HubBuilds.is_built(world, key) else 0.0
		"source":
			var sources: Sources = _sources(world)
			return float(sources.step_index(key)) if sources and sources.has(key) else 0.0
		"sources_shut":
			var all: Sources = _sources(world)
			return float(all.shut_count()) if all else 0.0
		"planet_share":
			var planet: Restoration = Restoration.active()
			return planet.planet_share() if planet else 0.0
		"cities_open":
			var live: Restoration = Restoration.active()
			return float(live.districts.unlocked_count()) if live and live.districts else 0.0
	return 0.0


## A city's regrowth stage plus its share of the way to the next one, so a goal that asks for a
## stage fills its gauge as the city's hexes come clean instead of standing still for minutes. It
## never reaches the next whole stage before the city does.
static func city_stage(key: String) -> float:
	var stage: float = Restoration.measure(Restoration.MEASURE_CITY_STAGE, key)
	var r: Restoration = Restoration.active()
	if r == null or r.districts == null or not r.districts.has(key) or stage >= float(Districts.MAX_STAGE):
		return stage
	return stage + minf(r.districts.share_of(key), STAGE_SHARE_CAP)


static func _stat(key: String) -> float:
	var v: Variant = GameState.stats.get(key, 0.0)
	return float(v) if (v is float or v is int) else 0.0


## The best repair tier of robot type `key` ("any" = of any type).
static func _best_tier(key: String) -> int:
	var best: int = 0
	for k: String in GameState.flags:
		if k.begins_with("tier_") and (key == "any" or k == "tier_" + key):
			best = maxi(best, int(GameState.flags[k]))
	return best


static func _sources(world: Node) -> Sources:
	var orbit: SliceOrbit = world.get("orbit") as SliceOrbit
	return orbit.sources if orbit else null


## Distinct hexes painted into any Command zone (crew or single robot) in this district.
static func zone_hex_count() -> int:
	var orders: Dictionary = GameState.world.get("orders", {})
	var seen: Dictionary = {}
	for kind: String in ["groups", "bots"]:
		var by_owner: Dictionary = orders.get(kind, {})
		for owner: Variant in by_owner:
			var order: Variant = by_owner[owner]
			if order is Dictionary:
				for h: Variant in (order as Dictionary).get("zone", []):
					seen[int(h)] = true
	if SphereCrew.active != null and is_instance_valid(SphereCrew.active):
		seen.merge(SphereCrew.active.zone_cells())
	return seen.size()
