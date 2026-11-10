class_name PaceSimRdEconomyChecks
extends RefCounted
## The owner's economy and crew rules (design spec sections 9 and 14) as checks on a redesign
## run: small early numbers, no income jump or burst reward, one job per currency, scarce Parts
## at the start, a crew that climbs steadily to 100-200 at the launch point, and hands that still
## matter early. Also the figures the owner asked to judge: largest price, peak income, cubes held.

## Scale limits in cubes.
const BALE_MIN: float = 10.0
const BALE_MAX: float = 100.0
const FIRST_UPGRADE_MAX: float = 100.0
const DISTRICT_1_MAX: float = 5000.0
## Numbers stay whole (no "k") in the first two districts: under this.
const EARLY_NUMBER_MAX: float = 10000.0
## No purchase may multiply income by more than this; no one-off reward may be worth more than
## this many times three player minutes of income.
const INCOME_JUMP_MAX: float = 3.0
const REWARD_MAX: float = 1.0
## District 1: Parts per hex Lumi cleaned, and the player minute of the first robot.
const D1_PARTS_PER_HEX_MAX: float = 3.0
const FIRST_ROBOT_MIN: float = 20.0
const FIRST_ROBOT_SLACK_MIN: float = 5.0
## Crew size at the launch point, in district 1 ("a handful") and by the end of district 3 ("tens").
const CREW_LAUNCH: Vector2i = Vector2i(100, 200)
const CREW_DISTRICT_1: Vector2i = Vector2i(3, 9)
const CREW_DISTRICT_3: Vector2i = Vector2i(20, 99)
## The crew may not double faster than this, nor go longer than this without a new robot (player
## seconds). The stall rule is required from district 2 on and only reported for district 1,
## where every robot is hand-built from Parts that are scarce by rule.
const CREW_DOUBLE_MIN_S: float = 180.0
const CREW_DOUBLE_FROM: int = 4
const CREW_STALL_MAX_S: float = 360.0
## Building and upgrading: each must be the choice at least this share of the times both were affordable.
const CHOICE_MIN_SHARE: float = 0.15
## Hand work is at least this share of cleaning volume in each of the first districts.
const HAND_SHARE_MIN: float = 0.1
const HAND_SHARE_DISTRICTS: int = 3
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
	var d1_max: float = _dearest(rec, 0.0, _entered(m, 1, end_s))
	out.append(_check("scale_district_1", d1_max <= DISTRICT_1_MAX, d1_max, "%.0f cubes" % d1_max, "at most %.0f" % DISTRICT_1_MAX,
		"dearest purchase before district 2"))
	var early: float = maxf(_dearest(rec, 0.0, _entered(m, 2, end_s)), rec.held_before_third)
	out.append(_check("scale_first_two_districts", early < EARLY_NUMBER_MAX, early, "%.0f cubes" % early, "under %.0f" % EARLY_NUMBER_MAX,
		"largest price or cubes held before district 3 (whole numbers, no abbreviation)"))
	out.append(_check("income_jump", float(rec.jump["ratio"]) <= INCOME_JUMP_MAX, float(rec.jump["ratio"]), "x%.2f" % float(rec.jump["ratio"]),
		"at most x%.1f" % INCOME_JUMP_MAX, "largest income jump from one purchase: %s at bot minute %.1f" % [rec.jump["id"], float(rec.jump["t"]) / 60.0]))
	out.append(_check("reward_size", float(rec.lump_worst["ratio"]) <= REWARD_MAX, float(rec.lump_worst["ratio"]),
		"%.2f" % float(rec.lump_worst["ratio"]), "at most %.2f" % REWARD_MAX,
		"largest one-off reward over 3 player minutes of income, at bot minute %.1f" % (float(rec.lump_worst["t"]) / 60.0)))
	out.append(_currency(rec))
	out.append_array(_parts(m, end_s, k))
	out.append_array(_crew(m, end_s, k))
	return out


## The numbers the owner asked to see, as report notes.
static func figures(m: PaceSimRdModel, end_s: float) -> PackedStringArray:
	var rec: PaceSimRdLog = m.record
	var peak_income: float = 0.0
	var peak_units: float = 0.0
	for i: int in rec.minutes.size():
		peak_income = maxf(peak_income, float(rec.minutes[i]["income_rate"]))
		if i > 0:
			peak_units = maxf(peak_units, (float(rec.minutes[i]["hand_units"]) + float(rec.minutes[i]["crew_units"])
				- float(rec.minutes[i - 1]["hand_units"]) - float(rec.minutes[i - 1]["crew_units"])) / PaceSimRdLog.SAMPLE_S)
	var out: PackedStringArray = ["numbers to judge: largest price %.0f cubes, peak income %.0f cubes a second (bot speed), most cubes held %.0f, cubes held at the launch point %.0f, cubes earned in all %.0f" % [
		_dearest(rec, 0.0, end_s), peak_income, rec.max_cubes_on_hand, m.cubes, m.earned]]
	var city_hexes: int = 0
	for z: PaceSimRdDistrict in m.zones:
		city_hexes += z.hexes
	var cells: int = m.data.planet_cells
	var left_work: float = float(cells - city_hexes) * m.data.num("restoration.planet.open_ground_hex_work")
	var hours: float = left_work / maxf(peak_units, 0.001) / 3600.0
	var examples: PackedStringArray = []
	for n: Variant in m.data.tables["restoration"]["planet"]["finish_in_hours"]:
		examples.append("%.0f more bot hours needs about %.0f robots" % [float(n), float(m.robot_total()) * hours / float(n)])
	out.append("the whole planet: the six cities are %d of %d cells (%.1f%%); cleaning the rest at the launch-point rate (%.0f units a second, %d robots) takes about %.0f bot hours; %s" % [
		city_hexes, cells, float(city_hexes) / float(cells) * 100.0, peak_units, m.robot_total(), hours, "; ".join(examples)])
	return out


static func _check(id: String, passed: bool, value: float, shown: String, limit_shown: String, note: String) -> Dictionary:
	return {"id": id, "pass": passed, "value": value, "shown": shown, "limit_shown": limit_shown, "note": note}


static func _entered(m: PaceSimRdModel, index: int, fallback: float) -> float:
	return m.zones[index].entered_at if m.zones.size() > index and m.zones[index].entered_at >= 0.0 else fallback


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
		"cubes buy tracks, base levels and builds; Parts buy robots, upgrades and modules; research costs one of the two" +
		("" if wrong.is_empty() else ": " + ", ".join(wrong)))


static func _parts(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	var rec: PaceSimRdLog = m.record
	var out: Array[Dictionary] = []
	var per_hex: float = rec.d1_parts / maxf(rec.d1_hand_hexes, 1.0)
	out.append(_check("parts_scarce_district_1", rec.d1_hand_hexes > 0.0 and per_hex <= D1_PARTS_PER_HEX_MAX, per_hex, "%.2f a hex" % per_hex,
		"at most %.0f" % D1_PARTS_PER_HEX_MAX, "Parts per hex Lumi cleaned in district 1 (%.0f Parts in all, the source's included)" % rec.d1_parts))
	var robot_at: float = rec.events.get("first_robot", -1.0)
	var robot_min: float = robot_at / 60.0 * k
	out.append(_check("first_robot", robot_at >= 0.0 and absf(robot_min - FIRST_ROBOT_MIN) <= FIRST_ROBOT_SLACK_MIN, robot_min,
		"%.1f min" % robot_min if robot_at >= 0.0 else "never", "%.0f +/- %.0f min" % [FIRST_ROBOT_MIN, FIRST_ROBOT_SLACK_MIN], "player minute of the first robot"))
	var gap: Vector2 = PaceSimReport.longest_gap(_floats(rec.parts_ok), 0.0, end_s)
	var wait: Dictionary = _check("parts_wait", gap.x * k <= PARTS_WAIT_MAX_S, gap.x * k, "%.0f s" % (gap.x * k), "%.0f s" % PARTS_WAIT_MAX_S,
		"longest time a Parts-priced offer was on the table with none affordable, from bot minute %.1f" % (gap.y / 60.0))
	wait["advisory"] = true
	out.append(wait)
	return out


static func _crew(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	var rec: PaceSimRdLog = m.record
	var out: Array[Dictionary] = []
	var crew: int = m.robot_total()
	out.append(_check("crew_at_launch", crew >= CREW_LAUNCH.x and crew <= CREW_LAUNCH.y, float(crew), "%d robots" % crew,
		"%d-%d" % [CREW_LAUNCH.x, CREW_LAUNCH.y], "robots when all six cities thrive"))
	var first: int = m.zones[0].crew_at_stage4
	var third: int = m.zones[mini(2, m.zones.size() - 1)].crew_at_stage4
	var climb_ok: bool = first >= CREW_DISTRICT_1.x and first <= CREW_DISTRICT_1.y and third >= CREW_DISTRICT_3.x and third <= CREW_DISTRICT_3.y
	out.append(_check("crew_climb", climb_ok, float(third), "%d then %d" % [first, third],
		"%d-%d then %d-%d" % [CREW_DISTRICT_1.x, CREW_DISTRICT_1.y, CREW_DISTRICT_3.x, CREW_DISTRICT_3.y], "robots when district 1 and district 3 reach stage 4"))
	var fastest: float = INF
	for i: int in range(CREW_DOUBLE_FROM - 1, rec.builds.size()):
		var doubled: int = (i + 1) * 2 - 1
		if doubled < rec.builds.size():
			fastest = minf(fastest, rec.builds[doubled] - rec.builds[i])
	out.append(_check("crew_doubling", fastest * k >= CREW_DOUBLE_MIN_S, fastest * k, "%.0f s" % (fastest * k), "at least %.0f s" % CREW_DOUBLE_MIN_S,
		"fastest the crew ever doubled, from %d robots up (player seconds)" % CREW_DOUBLE_FROM))
	var second_city: float = _entered(m, 1, end_s)
	var stall: Vector2 = PaceSimReport.longest_gap(_floats(rec.builds), second_city, end_s)
	out.append(_check("crew_stall", stall.x * k <= CREW_STALL_MAX_S, stall.x * k, "%.0f s" % (stall.x * k), "%.0f s" % CREW_STALL_MAX_S,
		"longest time without a new robot from district 2 on, from bot minute %.1f" % (stall.y / 60.0)))
	var early: Vector2 = PaceSimReport.longest_gap(_floats(rec.builds), rec.events.get("first_robot", second_city), second_city)
	var early_check: Dictionary = _check("crew_stall_district_1", early.x * k <= CREW_STALL_MAX_S, early.x * k, "%.0f s" % (early.x * k),
		"%.0f s" % CREW_STALL_MAX_S, "longest time without a new robot in district 1 after the first (Parts are scarce there by rule), from bot minute %.1f" % (early.y / 60.0))
	early_check["advisory"] = true
	out.append(early_check)
	var builds: int = rec.crew_choices.get("robot", 0)
	var upgrades: int = rec.crew_choices.get("repair", 0)
	var low: float = float(mini(builds, upgrades)) / float(maxi(builds + upgrades, 1))
	out.append(_check("build_or_upgrade_choice", builds + upgrades > 0 and low >= CHOICE_MIN_SHARE, low, "%d build / %d upgrade" % [builds, upgrades],
		"each at least %.0f%%" % (CHOICE_MIN_SHARE * 100.0), "what was chosen when one more robot and a better robot type were both affordable"))
	var worst: float = 1.0
	var shares: PackedStringArray = []
	for z: PaceSimRdDistrict in m.zones:
		var total: float = z.hand_units + z.crew_units
		var share: float = z.hand_units / total if total > 0.0 else 1.0
		shares.append("%.0f%%" % (share * 100.0))
		if z.index < HAND_SHARE_DISTRICTS:
			worst = minf(worst, share)
	out.append(_check("hand_share_early", worst >= HAND_SHARE_MIN, worst, "%.0f%%" % (worst * 100.0), "at least %.0f%%" % (HAND_SHARE_MIN * 100.0),
		"lowest hand share of cleaning volume in districts 1-%d; by district: %s" % [HAND_SHARE_DISTRICTS, ", ".join(shares)]))
	return out


static func _floats(a: PackedFloat64Array) -> Array[float]:
	var out: Array[float] = []
	out.assign(a)
	return out
