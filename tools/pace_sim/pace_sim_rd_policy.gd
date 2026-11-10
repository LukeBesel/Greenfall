class_name PaceSimRdPolicy
extends RefCounted
## A player of the redesign model. This base class is the default player: sweeps and presses by
## hand all the time, tends as soon as there is something to tend, does the source job when it
## opens, buys the best amplifier it can afford, moves on when a district reaches stage 4 and
## comes back to finish stage 5. One script per variant in tools/pace_sim/rd_policies/ overrides
## the switches below. A policy can only call the model's buy, fit and act choices, which
## enforce every cost and rule.

## How the default player weighs what a purchase improves (natural logs of each rate).
const W_POWER: float = 1.0
const W_HAND: float = 0.5
const W_INCOME: float = 0.7
const W_TEND: float = 0.5
## Cubes one Part counts as when a rig module is weighed by the income it brings.
const PARTS_AS_CUBES: float = 10.0
## While saving for a gate, other things are bought only up to this share of the gate's cost.
const SIDE_BUY_SHARE: float = 0.35
## Lumi stops sweeping to plant or water once this many hexes are waiting (or nothing is left to sweep).
const TEND_BATCH_HEXES: float = 6.0
## Lumi hops back to an older district when this share of its hexes can take a watering.
const RETURN_SHARE: float = 0.3
## Seconds the Assembler's chosen robot type is kept before the mix is weighed again.
const MIX_HOLD_S: float = 10.0
## Added to a research node's field-data cost when ranking a node that only adds to a stat.
const AMPLIFIER_NODE_RANK: float = 100000.0
## Seconds before the offers are weighed again after a look that bought nothing.
const LOOK_AGAIN_S: float = 5.0
## What the first parts finder or robot builder is worth to the player's ranking: they add no
## cleaning of their own, so they are given a fixed gain large enough to be built when offered.
const CHAIN_ROBOT_GAIN: float = 1.0
## Another robot builder is bought once this many times its price in Parts is lying unused.
const PARTS_PILE_FACTOR: float = 2.0

## False: never builds robots or anything only robots need.
var buys_robots: bool = true
## True: every robot on offer is bought before any other Parts purchase.
var rushes_robots: bool = false
## The Assembler's build mix: the share of the crew kept as Scroungers (parts finders). The rest
## of its builds go to whichever working robot type speeds the district up most per Part.
var scrounger_share: float = 0.15
## Slot -> module to keep fitted whenever it is owned (empty = fit the best for the district).
var fixed_rig: Dictionary[String, String] = {}

var _next_look: float = 0.0
var _mix_type: String = ""
var _mix_until: float = 0.0


## Called when Lumi is free: buy at most one thing.
func shop(m: PaceSimRdModel) -> void:
	if m.rig_dirty:
		m.rig_dirty = false
		refit(m)
	if m.t < _next_look or not m.any_affordable():
		return
	_next_look = m.t + LOOK_AGAIN_S
	var offers: Array[Dictionary] = []
	for item: Dictionary in m.items():
		if buys_robots or not bool(item["crew"]):
			offers.append(item)
	var gate: Dictionary = {}
	for item: Dictionary in offers:
		if not _is_gate(item):
			continue
		if m.can_afford(item):
			_bought(m, m.buy(item))
			return
		if float(item["cubes"]) > 0.0 and (gate.is_empty() or float(item["cubes"]) < float(gate["cubes"])):
			gate = item
	var node: Dictionary = _cheapest_research(m, offers)
	if not node.is_empty() and _fits_beside(node, gate):
		_bought(m, m.buy(node))
		return
	_buy_best(m, offers, gate)


## What Lumi does this tick.
func choose(m: PaceSimRdModel) -> String:
	var w: PaceSimRdWork = m.work
	var z: PaceSimRdDistrict = w.zone()
	if w.source_open(z):
		return "source"
	var can_clean: bool = w.can_clean(z)
	if w.tending_open():
		var batch: float = TEND_BATCH_HEXES if can_clean else 0.0001
		if z.count[1] >= batch and m.seeds >= m.data.num("regrowth.seeds.per_hex"):
			return "plant"
		if z.thirsty(m.t, true) >= batch:
			return "water"
	if not w.wreck_here(z).is_empty():
		return "explore"
	var moving_on: bool = z.stage >= 4 or not can_clean
	var target: int = _target_district(m)
	if target != m.here and moving_on:
		return "travel:%d" % target
	if not can_clean and w.tending_open() and z.stage < PaceSimRdDistrict.TOP_STAGE and z.thirsty(m.t, false) > 0.0:
		return "boost"
	var back: int = _district_to_water(m)
	if back >= 0 and moving_on:
		return "travel:%d" % back
	return "clean" if can_clean else "idle"


## The robot type the Assemblers build next ("" = nothing now). Only types Lumi has built once
## by hand can be assembled.
func next_build(m: PaceSimRdModel) -> String:
	var chain: Dictionary = m.data.tables["robots"]["chain"]
	var finder: String = str(chain["scrounger"])
	if not buys_robots:
		return ""
	if m.robots.get(finder, 0) > 0 and float(m.robots[finder]) < scrounger_share * float(m.robot_total() + 1):
		return finder
	if m.t < _mix_until and _mix_type != "":
		return _mix_type
	var z: PaceSimRdDistrict = m.work.zone()
	var before: float = value(m, z)
	var best: String = ""
	var best_score: float = 0.0
	for type: String in m.data.robot_types:
		if m.robots.get(type, 0) <= 0 or type == finder or type == str(chain["assembler"]):
			continue
		var score: float = _gain(m, z, {"type": "robot", "id": type}, before) / m.robot_parts(type)
		if score > best_score:
			best_score = score
			best = type
	_mix_type = best
	_mix_until = m.t + MIX_HOLD_S
	return best


## Whether a full Surge is released during this kind of action.
func releases_surge(_m: PaceSimRdModel, action: String) -> bool:
	return action == "clean" or action == "source"


## How good the player's position is: the weighted logs of how fast the district gets finished
## (Lumi and crew together, the lagging kind counted), Lumi's own power, income and tending speed.
func value(m: PaceSimRdModel, z: PaceSimRdDistrict) -> float:
	var r: PaceSimRdRates = m.rates
	var hand: float = r.hand_power(z) * r.surge_factor()
	var v: float = W_POWER * log(r.district_power(z)) + W_HAND * log(hand)
	v += W_INCOME * log(r.hand_income(z, PARTS_AS_CUBES) * r.surge_factor() + r.crew_power(z))
	if m.work.tending_open():
		var plant: float = r.plant_rate() + r.crew_tend_rate("plant_rate")
		var water: float = r.water_rate() + r.crew_tend_rate("water_rate")
		v += W_TEND * log(1.0 / (1.0 / plant + 1.0 / water))
	return v


## Fits, in every open slot, the fixed module if one is set and owned, else the best owned one.
func refit(m: PaceSimRdModel) -> void:
	var z: PaceSimRdDistrict = m.work.zone()
	for slot: Variant in m.data.tables["rigs"]["slots"]:
		var want: String = fixed_rig.get(str(slot), "")
		if want != "" and m.fit(want):
			continue
		var best: String = ""
		var best_v: float = -INF
		for id: String in m.data.modules:
			if str(m.data.modules[id]["slot"]) != str(slot) or not m.fit(id):
				continue
			var v: float = value(m, z)
			if v > best_v:
				best_v = v
				best = id
		if best != "":
			m.fit(best)


## For the design check: the best module of every slot in district `z` as things stand, whether
## owned yet or not. Returns {slot: module id}.
func best_modules(m: PaceSimRdModel, z: PaceSimRdDistrict) -> Dictionary:
	var out: Dictionary = {}
	var kept: Dictionary[String, String] = m.rig.duplicate()
	for slot: Variant in m.data.tables["rigs"]["slots"]:
		var best_v: float = -INF
		for id: String in m.data.modules:
			if str(m.data.modules[id]["slot"]) != str(slot):
				continue
			m.rig[str(slot)] = id
			m.rates.dirty = true
			var v: float = value(m, z)
			if v > best_v:
				best_v = v
				out[str(slot)] = id
		m.rig = kept.duplicate()
	m.rates.dirty = true
	return out


## While saving cubes for a gate, a side purchase in cubes must be cheap. Parts are never held back.
func _fits_beside(item: Dictionary, gate: Dictionary) -> bool:
	return gate.is_empty() or float(item["cubes"]) <= float(gate["cubes"]) * SIDE_BUY_SHARE


func _crew_buy(item: Dictionary) -> bool:
	return str(item["type"]) == "robot" or str(item["type"]) == "repair"


## After a purchase the bench is looked at again at once; after none, a little later.
func _bought(m: PaceSimRdModel, did: bool) -> void:
	if did:
		_next_look = m.t


func _is_gate(item: Dictionary) -> bool:
	return bool(item["gate"]) or (rushes_robots and str(item["type"]) == "robot")


## The research node to start: one that opens something new (no stat of its own) before one that
## only adds to a stat, and the least field data first within each group.
func _cheapest_research(m: PaceSimRdModel, offers: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_rank: float = INF
	for item: Dictionary in offers:
		if str(item["type"]) != "research" or not m.can_afford(item):
			continue
		var opens: bool = (m.data.nodes[str(item["id"])].get("mods", {}) as Dictionary).is_empty()
		var rank: float = float(item["data"]) + (0.0 if opens else AMPLIFIER_NODE_RANK)
		if rank < best_rank:
			best_rank = rank
			best = item
	return best


## Buys the best affordable offer: the most value gained per Part among Parts-priced offers
## first, then per cube among cube-priced ones (the two currencies never compete). Records which
## track led, and what was chosen when a new robot and a type upgrade were both affordable.
func _buy_best(m: PaceSimRdModel, offers: Array[Dictionary], gate: Dictionary) -> void:
	var z: PaceSimRdDistrict = m.work.zone()
	var before: float = value(m, z)
	var best: Dictionary[String, Dictionary] = {"parts": {}, "cubes": {}}
	var best_score: Dictionary[String, float] = {"parts": 0.0, "cubes": 0.0}
	var top_track: String = ""
	var top_track_score: float = 0.0
	var seen: Dictionary[String, bool] = {}
	for item: Dictionary in offers:
		var type: String = str(item["type"])
		if type == "research" or _is_gate(item) or (type != "track" and not m.can_afford(item)):
			continue
		var pool: String = "parts" if float(item["parts"]) > 0.0 else "cubes"
		var score: float = _gain(m, z, item, before) / maxf(float(item[pool]), 1.0)
		if type == "track" and score > top_track_score:
			top_track_score = score
			top_track = str(item["id"])
		if not m.can_afford(item) or not _fits_beside(item, gate):
			continue
		seen[type] = true
		if score > best_score[pool]:
			best_score[pool] = score
			best[pool] = item
	var pick: Dictionary = best["parts"] if not best["parts"].is_empty() else best["cubes"]
	if pick.is_empty() or not m.buy(pick):
		return
	_bought(m, true)
	if _crew_buy(pick) and seen.has("robot") and seen.has("repair"):
		m.record.crew_choices[str(pick["type"])] = m.record.crew_choices.get(str(pick["type"]), 0) + 1
	if str(pick["type"]) == "track":
		m.record.track_buys[str(pick["id"])] = m.record.track_buys.get(str(pick["id"]), 0) + 1
		m.record.track_tops[top_track] = m.record.track_tops.get(top_track, 0) + 1
	m.rig_dirty = m.rig_dirty or str(pick["type"]) == "module"


## Value gained by an offer, tried and taken back. The chain's own robots add no cleaning, so
## they follow rules: the first of each always; more parts finders up to the mix's share; one
## more robot builder when Parts pile up faster than they are assembled.
func _gain(m: PaceSimRdModel, z: PaceSimRdDistrict, item: Dictionary, before: float) -> float:
	if str(item["type"]) == "robot" and str(m.data.robot_types[str(item["id"])]["role"]) in ["find", "build"]:
		var id: String = str(item["id"])
		var have: int = m.robots.get(id, 0)
		var wanted: bool = have == 0
		if str(m.data.robot_types[id]["role"]) == "find":
			wanted = wanted or float(have) < scrounger_share * float(m.robot_total() + 1)
		else:
			wanted = wanted or m.parts >= m.robot_parts(id) * PARTS_PILE_FACTOR
		return CHAIN_ROBOT_GAIN * m.robot_parts(id) if wanted else 0.0
	m.peek(item)
	var after: float = value(m, z)
	if str(item["type"]) == "module":
		var kept: Dictionary[String, String] = m.rig.duplicate()
		refit(m)
		after = value(m, z)
		m.rig = kept
	m.peek(item, true)
	return after - before


## The district Lumi should be working in: the first open one below stage 4, else the first below 5.
func _target_district(m: PaceSimRdModel) -> int:
	for goal: int in [4, 5]:
		for z: PaceSimRdDistrict in m.zones:
			if z.index < m.unlocked and z.stage < goal:
				return z.index
	return m.here


## An older district worth a hop to water, or -1.
func _district_to_water(m: PaceSimRdModel) -> int:
	if not m.work.tending_open():
		return -1
	for z: PaceSimRdDistrict in m.zones:
		if z.index < m.unlocked and z.index != m.here and z.stage < 5 and z.entered_at >= 0.0 \
				and z.thirsty(m.t, false) >= RETURN_SHARE * float(z.hexes):
			return z.index
	return -1
