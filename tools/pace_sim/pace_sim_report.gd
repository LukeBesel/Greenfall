class_name PaceSimReport
extends RefCounted
## Turns a finished run into the beats table and the cadence checks of docs/PLAN.md section 9.
## Times are simulator (bot-speed) times; the player estimate multiplies by bot_to_player.

const FIRST_HOUR_S: float = 3600.0
const SPIKE_WINDOW_MIN: int = 5
const SHARE_WINDOW_MIN: int = 10

## Limits from docs/PLAN.md section 9, in seconds unless named otherwise.
const LIMITS: Dictionary[String, float] = {
	"first_payout": 20.0, "first_upgrade": 90.0, "first_hex": 180.0, "small_win": 40.0,
	"purchase_first_hour": 180.0, "purchase_later": 240.0, "goal_gap": 240.0,
	"mechanic_first_hour": 900.0, "mechanic_later": 2400.0, "spike_gap": 2400.0, "spike_factor": 2.0, "hand_share": 0.3,
}


## {beats: [[name, seconds]], checks: [{id, pass, value, limit, unit, note}], notes: [String]}
static func build(m: PaceSimModel, run_s: float) -> Dictionary:
	var record: PaceSimLog = m.record
	var beats: Array[Array] = []
	for id: String in record.beats:
		beats.append([id, record.beats[id]])
	for row: Dictionary in record.objectives:
		beats.append(["objective:" + str(row["id"]), row["t"]])
	beats.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var checks: Array[Dictionary] = []
	checks.append(_at_most("first_payout", record.beats.get("first_payout", -1.0), "s"))
	checks.append(_at_most("first_upgrade", record.beats.get("first_upgrade", -1.0), "s"))
	checks.append(_at_most("first_hex", record.beats.get("hexes_1", -1.0), "s"))
	checks.append(_gap_check("small_win", _floats(record.wins), 0.0, run_s))
	checks.append(_gap_check("purchase_first_hour", _times(record.purchases), 0.0, minf(run_s, FIRST_HOUR_S)))
	if run_s > FIRST_HOUR_S:
		checks.append(_gap_check("purchase_later", _times(record.purchases), FIRST_HOUR_S, run_s))
	var judged_to: float = m.chains.unmodelled_since if m.chains.unmodelled_since >= 0.0 else run_s
	checks.append(_gap_check("goal_gap", _times(record.goals), 0.0, judged_to))
	checks.append(_gap_check("mechanic_first_hour", _times(record.mechanics), 0.0, minf(run_s, FIRST_HOUR_S)))
	if run_s > FIRST_HOUR_S:
		checks.append(_gap_check("mechanic_later", _times(record.mechanics), FIRST_HOUR_S, run_s))
	checks.append(_spike_check(record, run_s))
	checks.append(_share_check(record))
	checks.append(_apprentice_check(m))
	var notes: PackedStringArray = []
	for id: String in m.chains.unmodelled:
		notes.append("not modelled, never completes: %s (the card reached it at minute %.1f; goal gaps are judged up to then)" % [
			id, m.chains.unmodelled_since / 60.0])
	var step: Dictionary = m.chains.card_step()
	if str(step["id"]) != "":
		notes.append("the card ends the run on %s '%s' (%d of %d goals done)" % [step["kind"], step["id"], m.chains.goals_done.size(), m.data.goals.size()])
	if m.work.stuck_s > 0.0:
		notes.append("Lumi stood %.0f s in front of junk too heavy to lift" % m.work.stuck_s)
	if m.work.region_done():
		notes.append("the hub region ran out of dirty hexes at %d: travel to other hubs is not modelled" % m.work.hexes_done)
	return {"beats": beats, "checks": checks, "notes": notes}


## Printable lines for a report.
static func lines(report: Dictionary, bot_to_player: float) -> PackedStringArray:
	var out: PackedStringArray = ["beat                              sim min   player est. min"]
	for b: Array in report["beats"]:
		out.append("%-32s %8.1f %12.1f" % [b[0], float(b[1]) / 60.0, float(b[1]) / 60.0 * bot_to_player])
	out.append("")
	out.append("cadence checks (docs/PLAN.md section 9), on simulator time:")
	for c: Dictionary in report["checks"]:
		out.append("%s  %-22s %s%s  (limit %s%s)  %s" % ["PASS" if c["pass"] else "FAIL", c["id"], _num(float(c["value"])), c["unit"],
			_num(float(c["limit"])), c["unit"], c["note"]])
	for n: String in report["notes"]:
		out.append("note: " + n)
	return out


static func _num(v: float) -> String:
	return "%.2f" % v if absf(v) < 10.0 else "%.0f" % v


static func _at_most(id: String, value: float, unit: String) -> Dictionary:
	var limit: float = LIMITS[id]
	return {"id": id, "pass": value >= 0.0 and value <= limit, "value": value, "limit": limit, "unit": unit,
		"note": "never happened" if value < 0.0 else ""}


static func _floats(a: PackedFloat64Array) -> Array[float]:
	var out: Array[float] = []
	out.assign(a)
	return out


static func _times(rows: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for row: Dictionary in rows:
		out.append(float(row["t"]))
	return out


## The longest stretch inside [from, to] without one of `times` (the window's edges count).
static func longest_gap(times: Array[float], from: float, to: float) -> Vector2:
	var last: float = from
	var best := Vector2(0.0, from)
	for t: float in times:
		if t < from or t > to:
			continue
		if t - last > best.x:
			best = Vector2(t - last, last)
		last = t
	if to - last > best.x:
		best = Vector2(to - last, last)
	return best


static func _gap_check(id: String, times: Array[float], from: float, to: float) -> Dictionary:
	var gap: Vector2 = longest_gap(times, from, to)
	var limit: float = LIMITS[id]
	return {"id": id, "pass": gap.x <= limit, "value": gap.x, "limit": limit, "unit": "s",
		"note": "longest gap starts at minute %.1f" % (gap.y / 60.0)}


## Cleaning rate (hexes a minute over the last few minutes) by minute row.
static func _rates(record: PaceSimLog) -> Array[float]:
	var out: Array[float] = []
	for i: int in record.minutes.size():
		var j: int = maxi(0, i - SPIKE_WINDOW_MIN)
		var done: float = _output(record.minutes[i]) - _output(record.minutes[j])
		out.append(done / float(maxi(i - j, 1)))
	return out


static func _output(row: Dictionary) -> float:
	return float(row["hand_hexes"]) + float(row["crew_hexes"])


## A power spike is the first minute the cleaning rate reaches spike_factor x the rate at the
## previous spike. The rule asks for one at least every spike_gap.
static func _spike_check(record: PaceSimLog, run_s: float) -> Dictionary:
	var rates: Array[float] = _rates(record)
	var spikes: Array[float] = []
	var base: float = 0.0
	for i: int in rates.size():
		if i < SPIKE_WINDOW_MIN:
			continue
		if base <= 0.0:
			base = rates[i]
			continue
		if rates[i] >= base * LIMITS["spike_factor"]:
			spikes.append(float(i + 1) * 60.0)
			base = rates[i]
	var gap: Vector2 = longest_gap(spikes, 0.0, run_s)
	var at: PackedStringArray = []
	for s: float in spikes:
		at.append("%.0f" % (s / 60.0))
	return {"id": "spike_gap", "pass": gap.x <= LIMITS["spike_gap"], "value": gap.x, "limit": LIMITS["spike_gap"], "unit": "s",
		"note": "spikes (rate x2) at minutes [%s]" % ", ".join(at)}


## Lowest share of cleaning done by hand over any window of a few minutes.
static func _share_check(record: PaceSimLog) -> Dictionary:
	var worst: float = 1.0
	var worst_at: int = 0
	for i: int in range(SHARE_WINDOW_MIN, record.minutes.size()):
		var a: Dictionary = record.minutes[i - SHARE_WINDOW_MIN]
		var b: Dictionary = record.minutes[i]
		var total: float = _output(b) - _output(a)
		if total <= 0.0:
			continue
		var share: float = (float(b["hand_hexes"]) - float(a["hand_hexes"])) / total
		if share < worst:
			worst = share
			worst_at = int(b["minute"])
	return {"id": "hand_share", "pass": worst >= LIMITS["hand_share"], "value": worst, "limit": LIMITS["hand_share"], "unit": "",
		"note": "lowest %d-minute window ends at minute %d" % [SHARE_WINDOW_MIN, worst_at]}


## A robot must be useful the moment it is built: no cleaner ever stands waiting for Lumi to
## learn the kind it works (design spec section 3).
static func _apprentice_check(m: PaceSimModel) -> Dictionary:
	var first_level: float = float(m.record.beats.get("mastery_1", -1.0))
	return {"id": "robots_never_wait_on_mastery", "pass": m.work.cleaner_wait_s <= 0.0, "value": m.work.cleaner_wait_s, "limit": 0.0, "unit": "s",
		"note": "mastery level 1 at %.0f s, first robot at %.0f s, mastery level %d at the end" % [first_level,
			float(m.record.beats.get("first_robot", -1.0)), m.work.mastery_level]}


# --- The first city's fit (docs/DECISIONS.md, Nov 11; docs/reviews/M3-21_PACING_FIT.md) ----------

## The window of the "no long wait between purchases" rule and of the hex cadence, in bot seconds.
const FIT_PURCHASE_WINDOW_S: float = 1200.0
const FIT_HEX_WINDOW_S: float = 900.0


## What the first-city targets are judged on: {first_hex_s, first_robot_s (-1: none),
## purchase_gap_s (longest wait between purchases in the first 20 minutes), hex_gaps_s (seconds
## each hex took, through minute 15), most_held, largest_price}.
static func city_fit(m: PaceSimModel) -> Dictionary:
	var record: PaceSimLog = m.record
	var gap: Vector2 = longest_gap(_times(record.purchases), 0.0, FIT_PURCHASE_WINDOW_S)
	var hex_gaps: Array[float] = []
	var prev: float = 0.0
	for t: float in record.hex_times:
		if t > FIT_HEX_WINDOW_S:
			break
		hex_gaps.append(t - prev)
		prev = t
	var largest: float = 0.0
	for row: Dictionary in record.purchases:
		largest = maxf(largest, float(row["cubes"]))
	var done: float = m.work.hand_hexes + m.work.crew_hexes
	return {"first_hex_s": float(record.beats.get("hexes_1", -1.0)), "first_robot_s": float(record.beats.get("first_robot", -1.0)),
		"purchase_gap_s": gap.x, "hex_gaps_s": hex_gaps, "most_held": m.most_held, "largest_price": largest,
		"mastery_1_s": float(record.beats.get("mastery_1", -1.0)), "mastery_5_s": float(record.beats.get("mastery_5", -1.0)),
		"mastery_level": m.work.mastery_level, "cleaner_wait_s": m.work.cleaner_wait_s,
		"hand_share": m.work.hand_hexes / done if done > 0.0 else 1.0}


static func fit_line(m: PaceSimModel) -> String:
	var fit: Dictionary = city_fit(m)
	var gaps: PackedStringArray = []
	for g: float in fit["hex_gaps_s"]:
		gaps.append("%.0f" % g)
	return "first-city fit: first hex %.0f s, first robot %.1f min, longest purchase wait in 20 min %.0f s, most cubes held %.0f, largest price %.0f, seconds per hex to minute 15: %s\nmastery: level 1 at %.0f s, level 5 at %.1f min, level %d at the end, cleaners waited %.0f s for it, hand share of all cleaning %.0f%%" % [
		fit["first_hex_s"], float(fit["first_robot_s"]) / 60.0, fit["purchase_gap_s"], fit["most_held"], fit["largest_price"], ",".join(gaps),
		fit["mastery_1_s"], float(fit["mastery_5_s"]) / 60.0, fit["mastery_level"], fit["cleaner_wait_s"], float(fit["hand_share"]) * 100.0]
