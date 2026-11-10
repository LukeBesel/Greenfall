class_name PaceSimRdLog
extends RefCounted
## What happened in a redesign run, as plain records: events (first time each happened), small
## wins, purchases, moments something was affordable, goal completions by tier, one row per
## minute, and the design checks sampled along the way.

const SAMPLE_S: float = 60.0
## A one-off reward is compared with this many player seconds of income. Only Lumi's own bales
## pay, so income stops whenever she tends, travels or fits a rocket part: "current income" is
## taken as the best run of LUMP_WINDOW_MIN bot minutes in the last LUMP_LOOKBACK_MIN.
const LUMP_PLAYER_S: float = 180.0
const LUMP_WINDOW_MIN: int = 3
const LUMP_LOOKBACK_MIN: int = 12

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
## The same count with every open track priced the same (the track with the largest gain).
var track_tops_equal: Dictionary[String, float] = {}
## District id -> {slot: best module there}.
var rig_best: Dictionary[String, Dictionary] = {}
## Highest ratio seen of tipping income over pressing income, and when.
var loose_over_bale: float = 0.0
var loose_over_bale_at: float = 0.0
## Moments a Parts-priced offer could be bought (or none was on the table), and the same for cubes.
var parts_ok: PackedFloat64Array = []
var cubes_ok: PackedFloat64Array = []
## Times a robot build or a robot repair was chosen when both could be afforded.
var crew_choices: Dictionary[String, int] = {}
## Time of every robot build.
var builds: PackedFloat64Array = []
## Largest income jump from one purchase {ratio, id, t}, largest one-off reward against three
## player minutes of income {ratio, t}, and the scale records.
var jump: Dictionary = {"ratio": 1.0, "id": "", "t": 0.0}
var lump_worst: Dictionary = {"ratio": 0.0, "t": 0.0}
var max_cubes_on_hand: float = 0.0
var max_parts_on_hand: float = 0.0
## An offer that cost two currencies at once, if one was ever built.
var mixed_cost_offer: String = ""
## Cubes the first pressed bale sold for; Parts earned and hexes' worth cleaned by hand when
## Lumi first left district 1.
var first_bale_value: float = 0.0
var d1_parts: float = 0.0
var d1_hand_hexes: float = 0.0
## Most cubes held before the third district was entered.
var held_before_third: float = 0.0

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


## Records, for this tick, whether anything can be bought and whether Parts are what is short.
func offers(m: PaceSimRdModel) -> void:
	var any: bool = false
	var parts_offer: bool = false
	var parts_can: bool = false
	var cubes_can: bool = false
	for item: Dictionary in m.items():
		var can: bool = m.can_afford(item)
		any = any or can
		cubes_can = cubes_can or (can and float(item["cubes"]) > 0.0)
		if float(item["parts"]) > 0.0:
			parts_offer = true
			parts_can = parts_can or can
			if float(item["cubes"]) > 0.0:
				mixed_cost_offer = str(item["id"])
	if any:
		affordable.append(m.t)
	if parts_can or not parts_offer:
		parts_ok.append(m.t)
	if cubes_can:
		cubes_ok.append(m.t)
	max_cubes_on_hand = maxf(max_cubes_on_hand, m.cubes)
	if m.zones.size() > 2 and m.zones[2].entered_at < 0.0:
		held_before_third = maxf(held_before_third, m.cubes)
	max_parts_on_hand = maxf(max_parts_on_hand, m.parts)


func income_jump(m: PaceSimRdModel, id: String, before: float, after: float) -> void:
	if before > 0.0 and after / before > float(jump["ratio"]):
		jump = {"ratio": after / before, "id": id, "t": m.t}


## A one-off reward against the income of the last few minutes (three player minutes' worth).
func lump(m: PaceSimRdModel, amount: float) -> void:
	if minutes.size() < LUMP_WINDOW_MIN:
		return
	var rate: float = 0.0
	for i: int in range(maxi(LUMP_WINDOW_MIN, minutes.size() - LUMP_LOOKBACK_MIN), minutes.size() + 1):
		var to_earned: float = float(minutes[i]["earned"]) if i < minutes.size() else m.earned
		var to_t: float = float(minutes[i]["minute"]) * SAMPLE_S if i < minutes.size() else m.t
		var from: Dictionary = minutes[i - LUMP_WINDOW_MIN]
		rate = maxf(rate, (to_earned - float(from["earned"])) / maxf(to_t - float(from["minute"]) * SAMPLE_S, 1.0))
	var allowed: float = rate * LUMP_PLAYER_S / m.data.num("balance.bot_to_player")
	if allowed > 0.0 and amount / allowed > float(lump_worst["ratio"]):
		lump_worst = {"ratio": amount / allowed, "t": m.t}


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
		"hand_hexes": m.hand_hexes, "crew_hexes": m.crew_hexes, "here": m.here, "stages": stages, "restoration": m.restoration(), "earned": m.earned, "seeds": m.seeds,
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
		lines.append("%d,%.0f,%.1f,%.2f,%d,%d,%d,%.0f,%.0f,%d,%.3f" % [row["minute"], row["cubes"], row["parts"], row["income_rate"], row["hexes"],
			row["robots"], row["purchases"], row["hand_units"], row["crew_units"], row["here"], row["restoration"]])
	return "\n".join(lines) + "\n"
