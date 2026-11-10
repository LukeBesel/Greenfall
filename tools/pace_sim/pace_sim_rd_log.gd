class_name PaceSimRdLog
extends RefCounted
## What happened in a redesign run, as plain records: events (first time each happened), small
## wins, purchases, moments something was affordable, goal completions by tier, one row per
## minute, and the design checks sampled along the way.

const SAMPLE_S: float = 60.0

## Event id -> first time it happened.
var events: Dictionary[String, float] = {}
var wins: PackedFloat64Array = []
var purchases: Array[Dictionary] = []
var affordable: PackedFloat64Array = []
var now_goals: PackedFloat64Array = []
var district_goals: Array[Dictionary] = []
var hex_times: PackedFloat64Array = []
var minutes: Array[Dictionary] = []
## Track id -> times it was bought, and times it was the best-scoring open track when one was bought.
var track_buys: Dictionary[String, int] = {}
var track_tops: Dictionary[String, int] = {}
## District id -> {slot: best module there}.
var rig_best: Dictionary[String, Dictionary] = {}
## Highest ratio seen of tipping income over pressing income, and when.
var loose_over_bale: float = 0.0
var loose_over_bale_at: float = 0.0
var data_lost: float = 0.0

var _next_sample: float = SAMPLE_S
var _earned_at_sample: float = 0.0


func event(id: String, t: float) -> void:
	if not events.has(id):
		events[id] = t


func win(t: float) -> void:
	if wins.is_empty() or wins[wins.size() - 1] != t:
		wins.append(t)


func purchase(t: float, type: String, id: String, cubes: float, parts: float) -> void:
	purchases.append({"t": t, "type": type, "id": id, "cubes": cubes, "parts": parts})
	win(t)
	now_goal(t)


func can_afford(t: float) -> void:
	affordable.append(t)


func now_goal(t: float) -> void:
	if now_goals.is_empty() or now_goals[now_goals.size() - 1] != t:
		now_goals.append(t)


func district_goal(t: float, id: String) -> void:
	district_goals.append({"t": t, "id": id})


func hex(t: float) -> void:
	hex_times.append(t)


func sample(m: PaceSimRdModel) -> void:
	if m.t < _next_sample:
		return
	_next_sample += SAMPLE_S
	var stages: PackedInt32Array = []
	for z: PaceSimRdDistrict in m.zones:
		stages.append(z.stage)
	minutes.append({
		"minute": int(round(m.t / 60.0)), "cubes": m.cubes, "parts": m.parts, "income_rate": (m.earned - _earned_at_sample) / SAMPLE_S,
		"hexes": m.hexes_clean, "robots": m.robot_total(), "purchases": purchases.size(), "hand_units": m.hand_units, "crew_units": m.crew_units,
		"hand_hexes": m.hand_hexes, "crew_hexes": m.crew_hexes, "here": m.here, "stages": stages, "restoration": m.restoration(),
		"hand_power": m.rates.hand_power(m.zones[m.here]),
	})
	_earned_at_sample = m.earned
	if m.rates.has_baler():
		for kind: String in m.zones[m.here].mix:
			if bool(m.data.kinds[kind].get("loads", false)) and m.rates.kind_usable(kind) and m.rates.loose_over_bale(kind) > loose_over_bale:
				loose_over_bale = m.rates.loose_over_bale(kind)
				loose_over_bale_at = m.t


## The time series as CSV text.
func csv() -> String:
	var lines: PackedStringArray = ["minute,cubes,parts,income_rate,hexes,robots,purchases,hand_units,crew_units,district,restoration"]
	for row: Dictionary in minutes:
		lines.append("%d,%.0f,%.0f,%.2f,%d,%d,%d,%.0f,%.0f,%d,%.3f" % [row["minute"], row["cubes"], row["parts"], row["income_rate"], row["hexes"],
			row["robots"], row["purchases"], row["hand_units"], row["crew_units"], row["here"], row["restoration"]])
	return "\n".join(lines) + "\n"
