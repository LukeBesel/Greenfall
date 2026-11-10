class_name PaceSimRdPolicy
extends RefCounted
## A player of the redesign model. This base class is the default player: sweeps and presses by
## hand all the time, tends as soon as there is something to tend, does the source job when it
## opens, buys the best amplifier it can afford, moves on when a district reaches stage 4 and
## comes back to finish stage 5. One script per variant in tools/pace_sim/rd_policies/ overrides
## the two switches below. A policy can only call the model's buy, fit and act choices, which
## enforce every cost and rule.

## How the default player weighs what a purchase improves (natural logs of each rate).
const W_POWER: float = 1.0
const W_HAND: float = 0.5
const W_INCOME: float = 0.7
const W_TEND: float = 0.5
## Parts are counted in cubes at the player's lifetime cubes-per-Part rate times this share
## (Parts buy about this share of what matters), inside the two limits.
const PARTS_SHARE: float = 0.25
const PARTS_WEIGHT_MIN: float = 2.0
const PARTS_WEIGHT_MAX: float = 400.0
## While saving for a gate, other things are bought only up to this share of the gate's cost.
const SIDE_BUY_SHARE: float = 0.35
## Lumi stops sweeping to plant or water once this many hexes are waiting (or nothing is left to sweep).
const TEND_BATCH_HEXES: float = 6.0
## Lumi hops back to an older district when this share of its hexes can take a watering.
const RETURN_SHARE: float = 0.3
## Seconds before the offers are weighed again after a look that bought nothing.
const LOOK_AGAIN_S: float = 5.0

## False: never builds robots or anything only robots need.
var buys_robots: bool = true
## True: every robot on offer is saved for before anything else is bought.
var rushes_robots: bool = false
## Slot -> module to keep fitted whenever it is owned (empty = fit the best for the district).
var fixed_rig: Dictionary[String, String] = {}

var _next_look: float = 0.0


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
		if gate.is_empty() or float(item["cubes"]) < float(gate["cubes"]):
			gate = item
	var node: Dictionary = _cheapest_research(m, offers)
	if not node.is_empty() and _fits_beside(m, node, gate):
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
		if z.count[1] >= batch:
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


## Whether a full Surge is released during this kind of action.
func releases_surge(_m: PaceSimRdModel, action: String) -> bool:
	return action == "clean" or action == "source"


## How good the player's position is: the weighted logs of cleaning power, Lumi's own power,
## income and tending speed in the district Lumi is in.
func value(m: PaceSimRdModel, z: PaceSimRdDistrict) -> float:
	var r: PaceSimRdRates = m.rates
	var hand: float = r.hand_power(z) * r.surge_factor()
	var crew: float = r.crew_power(z)
	var v: float = W_POWER * log(hand + crew) + W_HAND * log(hand) + W_INCOME * log(r.hand_income(z, parts_weight(m)) * r.surge_factor() + crew)
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


## Cubes one Part is worth to this player right now.
func parts_weight(m: PaceSimRdModel) -> float:
	return clampf(PARTS_SHARE * m.earned / maxf(m.parts_earned, 1.0), PARTS_WEIGHT_MIN, PARTS_WEIGHT_MAX)


## While saving for a gate, a side purchase must be cheap in cubes and leave the gate's Parts alone.
func _fits_beside(m: PaceSimRdModel, item: Dictionary, gate: Dictionary) -> bool:
	if gate.is_empty():
		return true
	if float(item["cubes"]) > float(gate["cubes"]) * SIDE_BUY_SHARE:
		return false
	return float(item["parts"]) <= 0.0 or m.parts - float(item["parts"]) >= float(gate["parts"])


## After a purchase the bench is looked at again at once; after none, a little later.
func _bought(m: PaceSimRdModel, did: bool) -> void:
	if did:
		_next_look = m.t


func _is_gate(item: Dictionary) -> bool:
	return bool(item["gate"]) or (rushes_robots and str(item["type"]) == "robot")


func _cheapest_research(m: PaceSimRdModel, offers: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	for item: Dictionary in offers:
		if str(item["type"]) == "research" and m.can_afford(item) and (best.is_empty() or float(item["data"]) < float(best["data"])):
			best = item
	return best


## Buys the affordable offer with the most value gained per cube; records which track led.
func _buy_best(m: PaceSimRdModel, offers: Array[Dictionary], gate: Dictionary) -> void:
	var z: PaceSimRdDistrict = m.work.zone()
	var before: float = value(m, z)
	var best: Dictionary = {}
	var best_score: float = 0.0
	var top_track: String = ""
	var top_track_score: float = 0.0
	for item: Dictionary in offers:
		var type: String = str(item["type"])
		if type == "research" or _is_gate(item):
			continue
		if type != "track" and not m.can_afford(item):
			continue
		var score: float = _gain(m, z, item, before) / maxf(float(item["cubes"]) + float(item["parts"]) * parts_weight(m), 1.0)
		if type == "track" and score > top_track_score:
			top_track_score = score
			top_track = str(item["id"])
		if not m.can_afford(item) or not _fits_beside(m, item, gate):
			continue
		if score > best_score:
			best_score = score
			best = item
	if best.is_empty() or not m.buy(best):
		return
	_bought(m, true)
	if str(best["type"]) == "track":
		m.record.track_buys[str(best["id"])] = m.record.track_buys.get(str(best["id"]), 0) + 1
		m.record.track_tops[top_track] = m.record.track_tops.get(top_track, 0) + 1
	m.rig_dirty = m.rig_dirty or str(best["type"]) == "module"


func _gain(m: PaceSimRdModel, z: PaceSimRdDistrict, item: Dictionary, before: float) -> float:
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
