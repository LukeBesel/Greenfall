class_name PaceSimRdRates
extends RefCounted
## Every rate of the redesign model, computed from the proposal tables and the model's state:
## stats (tracks, unlocks, research, rig modules), Lumi's rate per pollution kind, what a unit
## pays, robot speed from mastery, tending speed, and the Surge's average effect.

## Rate used for a kind Lumi has no tool for, so that "cannot work it" still compares as a number.
const NO_TOOL_RATE: float = 0.02
## Bisection steps when solving how long a district still takes.
const SOLVE_STEPS: int = 24

## Set whenever something that feeds a stat changes; the cache is rebuilt on the next read.
var dirty: bool = true

var _m: PaceSimRdModel
var _d: PaceSimRdData
var _mult: Dictionary[String, float] = {}
var _add: Dictionary[String, float] = {}


func _init(model: PaceSimRdModel) -> void:
	_m = model
	_d = model.data


## A multiplying stat (1.0 when nothing touches it).
func stat(id: String) -> float:
	if dirty:
		_rebuild()
	return _mult.get(id, 1.0)


## An additive stat (0.0 when nothing touches it).
func added(id: String) -> float:
	if dirty:
		_rebuild()
	return _add.get(id, 0.0)


func capacity() -> float:
	return _d.num("balance.hand.capacity") * stat("capacity")


func has_baler() -> bool:
	return _m.owned.has(str(_d.tables["balance"]["hand"]["baler_unlock"]))


## Seconds of handling per chest load: one bin trip loose, or a press and a share of a carry.
func handle_s(baled: bool) -> float:
	var hand: Dictionary = _d.tables["balance"]["hand"]
	if not baled:
		return float(hand["tip_s"]) * stat("handle")
	var carry: float = float(hand["carry_s"]) / (float(hand["carry_stack"]) + added("carry_stack")) * (1.0 - haul_cover())
	return (float(hand["press_s"]) + carry) * stat("handle")


## Share of Lumi's bale carrying the crew's haulers take over, 0..1.
func haul_cover() -> float:
	var n: int = 0
	for type: String in _m.robots:
		if bool(_d.robot_types[type].get("hauls", false)):
			n += _m.robots[type]
	return minf(1.0, float(n) * _d.num("robots.haul_share"))


func kind_usable(kind: String) -> bool:
	var tool: String = str(_d.kinds[kind].get("tool", ""))
	return tool == "" or _m.owned.has(tool)


## Units a second Lumi sweeps of a kind before chest handling.
func kind_rate(kind: String) -> float:
	if not kind_usable(kind):
		return NO_TOOL_RATE
	var row: Dictionary = _d.kinds[kind]
	var rate: float = _d.num("balance.hand.base_rate") * stat("hand_rate") * float(row["hand_factor"]) * stat("kind_" + kind)
	rate *= 1.0 + _d.num("balance.mastery.hand_bonus_per_level") * float(_m.mastery.get(kind, 0))
	var module: String = str(row.get("needs_module", ""))
	if module != "" and not _m.rig.values().has(module):
		rate *= float(row.get("without_module_factor", 1.0))
	return rate


## Units a second Lumi clears of a kind, chest handling included.
func throughput(kind: String) -> float:
	var rate: float = kind_rate(kind)
	if not bool(_d.kinds[kind].get("loads", false)):
		return rate
	return _loaded(rate, has_baler())


## Cubes one unit of a kind pays when Lumi clears it.
func unit_value(kind: String) -> float:
	var row: Dictionary = _d.kinds[kind]
	var value: float = float(row["yield"]["cubes"]) * stat("value")
	if bool(row.get("loads", false)):
		value *= _d.kept_bale_mult * stat("bale_value") if has_baler() else _d.num("balance.hand.loose_mult")
	return value


func unit_parts(kind: String) -> float:
	return float(_d.kinds[kind]["yield"].get("parts", 0.0)) * stat("parts_yield")


## Cubes a second from tipping loose over cubes a second from pressing bales, for a chest kind.
## Above 1.0 means tipping out-earns pressing.
func loose_over_bale(kind: String) -> float:
	var rate: float = kind_rate(kind)
	var loose: float = _loaded(rate, false) * _d.num("balance.hand.loose_mult")
	var baled: float = _loaded(rate, true) * _d.kept_bale_mult * stat("bale_value")
	return loose / maxf(baled, 0.0001)


## Lumi's cleaning power in a district: units a second over its mix of kinds.
func hand_power(z: PaceSimRdDistrict) -> float:
	var s_per_unit: float = 0.0
	for kind: String in z.mix:
		s_per_unit += z.mix[kind] / throughput(kind)
	return 1.0 / s_per_unit


## Cubes a second (Parts counted at `parts_weight` cubes each) from Lumi cleaning in a district.
func hand_income(z: PaceSimRdDistrict, parts_weight: float) -> float:
	var per_unit: float = 0.0
	for kind: String in z.mix:
		per_unit += z.mix[kind] * (unit_value(kind) + unit_parts(kind) * parts_weight)
	return per_unit * hand_power(z) + z.hex_bonus * hand_power(z) / z.hex_work


## Units a second one robot of a type clears of a kind; 0 below the mastery it needs.
func robot_rate(type: String, kind: String, near: bool) -> float:
	var speed: Dictionary = _d.tables["robots"]["mastery_speed"]
	var level: int = _m.mastery.get(kind, 0)
	if level < int(speed["min_level"]):
		return 0.0
	var tier: Dictionary = (_d.tables["robots"]["tiers"] as Array)[_m.mk.get(type, 0)]
	var rate: float = float(_d.robot_types[type]["rate"]) * (float(speed["base"]) + float(speed["per_level"]) * float(level))
	rate *= float(tier["mult"]) * stat("crew_rate")
	return rate * (1.0 + _d.num("robots.near_bonus")) if near else rate


## Units a second the whole crew would clear in a district with Lumi there.
func crew_power(z: PaceSimRdDistrict) -> float:
	var total: float = 0.0
	for type: String in _m.robots:
		var best: float = 0.0
		for kind: Variant in _d.robot_types[type].get("kinds", []):
			if z.mix.has(str(kind)):
				best = maxf(best, robot_rate(type, str(kind), true))
		total += best * float(_m.robots[type])
	return total


## How fast Lumi and the crew together finish what is left of a district, in units a second.
## The crew can only work the kinds it has robots and mastery for, so Lumi fills in where the
## crew falls short: the time T to finish solves sum over kinds of max(0, left - crew x T) / hand = T.
func district_power(z: PaceSimRdDistrict) -> float:
	var left: Dictionary[String, float] = {}
	var crew: Dictionary[String, float] = {}
	var total: float = 0.0
	var slowest: float = 0.0
	for kind: String in z.mix:
		left[kind] = maxf(z.remaining(kind), 0.0)
		crew[kind] = 0.0
		total += left[kind]
		slowest += left[kind] / throughput(kind)
	if total <= 0.0:
		return hand_power(z) + crew_power(z)
	for type: String in _m.robots:
		var best: String = ""
		var best_rate: float = 0.0
		for kind: Variant in _d.robot_types[type].get("kinds", []):
			if z.mix.has(str(kind)) and robot_rate(type, str(kind), true) > best_rate:
				best_rate = robot_rate(type, str(kind), true)
				best = str(kind)
		if best != "":
			crew[best] += best_rate * float(_m.robots[type])
	var low: float = 0.0
	var high: float = slowest
	for i: int in SOLVE_STEPS:
		var mid: float = (low + high) * 0.5
		var hand_s: float = 0.0
		for kind: String in left:
			hand_s += maxf(0.0, left[kind] - crew[kind] * mid) / throughput(kind)
		if hand_s > mid:
			low = mid
		else:
			high = mid
	return total / maxf(high, 0.0001)


## Hexes a second Lumi plants, and hexes a second Lumi waters.
func plant_rate() -> float:
	return stat("tend") / _d.num("regrowth.plant_s_per_hex")


func water_rate() -> float:
	return stat("tend") * _d.num("regrowth.water_hexes") * stat("water_hexes") / _d.num("regrowth.water_s")


## Hexes a second the crew's tenders handle (`field` is "plant_rate" or "water_rate").
func crew_tend_rate(field: String) -> float:
	var total: float = 0.0
	for type: String in _m.robots:
		var tier: Dictionary = (_d.tables["robots"]["tiers"] as Array)[_m.mk.get(type, 0)]
		total += float(_d.robot_types[type].get(field, 0.0)) * float(_m.robots[type]) * float(tier["mult"]) * stat("crew_rate")
	return total


func surge_owned() -> bool:
	return _m.owned.has(str(_d.tables["balance"]["surge"]["unlock"]))


## Seconds of hand work for a full Surge charge.
func surge_charge_s() -> float:
	return _d.num("balance.surge.charge_s") / stat("surge_rate")


## Lumi's average output multiplier from charging and releasing Surges back to back.
func surge_factor() -> float:
	if not surge_owned():
		return 1.0
	var burst: float = _d.num("balance.surge.duration_s")
	return (surge_charge_s() + burst * _d.num("balance.surge.mult")) / (surge_charge_s() + burst)


func _loaded(rate: float, baled: bool) -> float:
	var cap: float = capacity()
	return cap / (cap / rate + handle_s(baled))


func _rebuild() -> void:
	dirty = false
	_mult.clear()
	_add.clear()
	for id: String in _m.levels:
		var row: Dictionary = _d.tracks[id]
		var key: String = str(row["stat"])
		_mult[key] = _mult.get(key, 1.0) * (1.0 + float(row["add"]) * float(_m.levels[id]))
	for id: String in _m.owned:
		if _d.unlocks.has(id):
			_apply(_d.unlocks[id])
		elif _d.nodes.has(id):
			_apply(_d.nodes[id])
	for slot: String in _m.rig:
		_apply(_d.modules[_m.rig[slot]])


func _apply(row: Dictionary) -> void:
	var mods: Dictionary = row.get("mods", {})
	for key: String in mods:
		_mult[key] = _mult.get(key, 1.0) * float(mods[key])
	var adds: Dictionary = row.get("adds", {})
	for key: String in adds:
		_add[key] = _add.get(key, 0.0) + float(adds[key])
