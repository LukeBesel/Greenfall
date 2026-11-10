class_name PaceSimRdEconomyChecks
extends RefCounted
## The owner's economy rules (design spec section 14) as checks on a redesign run: small numbers,
## no income jump or burst reward, one job per currency, scarce Parts at the start, a small crew
## where building and repairing are both worth doing.

## Scale limits in cubes.
const BALE_MIN: float = 10.0
const BALE_MAX: float = 100.0
const FIRST_UPGRADE_MAX: float = 100.0
const DISTRICT_1_MAX: float = 5000.0
const PURCHASE_MAX: float = 50000.0
const ON_HAND_MAX: float = 100000.0
## No purchase may multiply income by more than this; no one-off reward may be worth more than
## this many times three player minutes of income.
const INCOME_JUMP_MAX: float = 3.0
const REWARD_MAX: float = 1.0
## District 1: Parts per hex Lumi cleaned, and the player minute of the first robot.
const D1_PARTS_PER_HEX_MAX: float = 3.0
const FIRST_ROBOT_MIN: float = 20.0
const FIRST_ROBOT_SLACK_MIN: float = 5.0
const CREW_MIN: int = 10
const CREW_MAX: int = 12
## Building and repairing: each must be the choice at least this share of the times both were affordable.
const CHOICE_MIN_SHARE: float = 0.15
## Player seconds a Parts-priced offer may stay out of reach (reported, not required: see the proposal).
const PARTS_WAIT_MAX_S: float = 240.0
## Which currency each kind of offer must cost.
const CUBE_TYPES: PackedStringArray = ["track", "unlock"]
const PARTS_TYPES: PackedStringArray = ["robot", "repair", "module"]


static func build(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	var rec: PaceSimRdLog = m.record
	var out: Array[Dictionary] = []
	out.append(_check("scale_bale_value", rec.first_bale_value >= BALE_MIN and rec.first_bale_value < BALE_MAX, rec.first_bale_value,
		"%.0f cubes" % rec.first_bale_value, "%.0f-%.0f" % [BALE_MIN, BALE_MAX - 1.0], "what the first pressed bale sells for"))
	var first_cost: float = float(rec.purchases[0]["cubes"]) if not rec.purchases.is_empty() else -1.0
	out.append(_check("scale_first_upgrade", first_cost > 0.0 and first_cost < FIRST_UPGRADE_MAX, first_cost, "%.0f cubes" % first_cost,
		"under %.0f" % FIRST_UPGRADE_MAX, "cost of the first purchase"))
	var second_district_at: float = m.zones[1].entered_at if m.zones.size() > 1 and m.zones[1].entered_at >= 0.0 else end_s
	var d1_max: float = _dearest(rec, 0.0, second_district_at)
	out.append(_check("scale_district_1", d1_max <= DISTRICT_1_MAX, d1_max, "%.0f cubes" % d1_max, "at most %.0f" % DISTRICT_1_MAX,
		"dearest purchase before district 2"))
	var dearest: float = _dearest(rec, 0.0, end_s)
	out.append(_check("scale_max_purchase", dearest < PURCHASE_MAX, dearest, "%.0f cubes" % dearest, "under %.0f" % PURCHASE_MAX, "dearest single purchase of the run"))
	out.append(_check("scale_on_hand", rec.max_cubes_on_hand < ON_HAND_MAX, rec.max_cubes_on_hand, "%.0f cubes" % rec.max_cubes_on_hand,
		"under %.0f" % ON_HAND_MAX, "most cubes held at once (most Parts: %.0f)" % rec.max_parts_on_hand))
	out.append(_check("income_jump", float(rec.jump["ratio"]) <= INCOME_JUMP_MAX, float(rec.jump["ratio"]), "x%.2f" % float(rec.jump["ratio"]),
		"at most x%.1f" % INCOME_JUMP_MAX, "largest income jump from one purchase: %s at bot minute %.1f" % [rec.jump["id"], float(rec.jump["t"]) / 60.0]))
	out.append(_check("reward_size", float(rec.lump_worst["ratio"]) <= REWARD_MAX, float(rec.lump_worst["ratio"]),
		"%.2f" % float(rec.lump_worst["ratio"]), "at most %.2f" % REWARD_MAX,
		"largest one-off reward over 3 player minutes of income, at bot minute %.1f" % (float(rec.lump_worst["t"]) / 60.0)))
	out.append(_currency(rec))
	out.append_array(_parts_and_crew(m, end_s, k))
	return out


static func _check(id: String, passed: bool, value: float, shown: String, limit_shown: String, note: String) -> Dictionary:
	return {"id": id, "pass": passed, "value": value, "shown": shown, "limit_shown": limit_shown, "note": note}


static func _dearest(rec: PaceSimRdLog, from: float, to: float) -> float:
	var best: float = 0.0
	for row: Dictionary in rec.purchases:
		if float(row["t"]) >= from and float(row["t"]) <= to:
			best = maxf(best, float(row["cubes"]))
	return best


## Every purchase cost one currency, and the right one for what it was.
static func _currency(rec: PaceSimRdLog) -> Dictionary:
	var wrong: PackedStringArray = []
	if rec.mixed_cost_offer != "":
		wrong.append(rec.mixed_cost_offer + " (two currencies)")
	for row: Dictionary in rec.purchases:
		var type: String = str(row["type"])
		if (type in CUBE_TYPES and float(row["parts"]) > 0.0) or (type in PARTS_TYPES and float(row["cubes"]) > 0.0):
			if not wrong.has(str(row["id"])):
				wrong.append(str(row["id"]))
	return _check("one_job_per_currency", wrong.is_empty(), float(wrong.size()), "%d wrong" % wrong.size(), "0",
		"cubes buy tracks, base levels and builds; Parts buy robots, repairs and modules; research costs one of the two" +
		("" if wrong.is_empty() else ": " + ", ".join(wrong)))


static func _parts_and_crew(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	var rec: PaceSimRdLog = m.record
	var out: Array[Dictionary] = []
	var per_hex: float = rec.d1_parts / maxf(rec.d1_hand_hexes, 1.0)
	out.append(_check("parts_scarce_district_1", rec.d1_hand_hexes > 0.0 and per_hex <= D1_PARTS_PER_HEX_MAX, per_hex, "%.2f a hex" % per_hex,
		"at most %.0f" % D1_PARTS_PER_HEX_MAX, "Parts per hex Lumi cleaned in district 1 (%.0f Parts in all, the source's included)" % rec.d1_parts))
	var robot_at: float = rec.events.get("first_robot", -1.0)
	var robot_min: float = robot_at / 60.0 * k
	out.append(_check("first_robot", robot_at >= 0.0 and absf(robot_min - FIRST_ROBOT_MIN) <= FIRST_ROBOT_SLACK_MIN, robot_min,
		"%.1f min" % robot_min if robot_at >= 0.0 else "never", "%.0f +/- %.0f min" % [FIRST_ROBOT_MIN, FIRST_ROBOT_SLACK_MIN], "player minute of the first robot"))
	var crew: int = m.robot_total()
	out.append(_check("crew_size", crew >= CREW_MIN and crew <= CREW_MAX, float(crew), "%d robots" % crew, "%d-%d" % [CREW_MIN, CREW_MAX], "robots at the ending"))
	var builds: int = rec.crew_choices.get("robot", 0)
	var repairs: int = rec.crew_choices.get("repair", 0)
	var low: float = float(mini(builds, repairs)) / float(maxi(builds + repairs, 1))
	out.append(_check("build_or_repair_choice", builds + repairs > 0 and low >= CHOICE_MIN_SHARE, low, "%d build / %d repair" % [builds, repairs],
		"each at least %.0f%%" % (CHOICE_MIN_SHARE * 100.0), "what was chosen when one more robot and one better robot were both affordable"))
	var gap: Vector2 = PaceSimReport.longest_gap(_floats(rec.parts_ok), 0.0, end_s)
	var wait: Dictionary = _check("parts_wait", gap.x * k <= PARTS_WAIT_MAX_S, gap.x * k, "%.0f s" % (gap.x * k), "%.0f s" % PARTS_WAIT_MAX_S,
		"longest time a Parts-priced offer was on the table with none affordable, from bot minute %.1f" % (gap.y / 60.0))
	wait["advisory"] = true
	out.append(wait)
	return out


static func _floats(a: PackedFloat64Array) -> Array[float]:
	var out: Array[float] = []
	out.assign(a)
	return out
