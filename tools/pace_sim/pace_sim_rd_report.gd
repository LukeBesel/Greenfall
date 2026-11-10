class_name PaceSimRdReport
extends RefCounted
## Turns a finished redesign run into the beat timeline, the per-district table and the cadence
## and design checks. The run is in bot seconds; the rules of docs/PLAN.md section 9 are written
## for a player, so every measured time is multiplied by bot_to_player before it is compared.

## Limits from docs/PLAN.md section 9 in PLAYER seconds (shares and counts where named).
const LIMITS: Dictionary[String, float] = {
	"first_payout": 20.0, "first_upgrade": 90.0, "first_hex": 180.0, "small_win": 40.0,
	"purchase_first_hour": 180.0, "purchase_later": 240.0, "goal_gap": 240.0,
	"mechanic_first_hour": 900.0, "mechanic_later": 2400.0, "spike_gap": 2400.0, "spike_factor": 2.0,
}
const FIRST_HOUR_S: float = 3600.0
## Player minutes the cleaning rate is averaged over for the spike rule.
const SPIKE_WINDOW_MIN: float = 6.0
## The crew-size curve in the notes shows one point every this many bot minutes.
const CREW_CURVE_STEP_MIN: int = 10
## A track is called dominant when it leads the ranking in more than this share of track purchases.
const DOMINANT_TRACK_SHARE: float = 0.5
## The first found piece should land within this many player minutes of the spec's minute 25.
const FIRST_PIECE_MIN: float = 25.0
const FIRST_PIECE_SLACK_MIN: float = 5.0
## The design set should complete in the last part of the run.
const SET_NEAR_END_SHARE: float = 0.85


## {beats, checks, districts, spikes, notes}.
static func build(m: PaceSimRdModel) -> Dictionary:
	var k: float = m.data.num("balance.bot_to_player")
	var end_s: float = m.ended_at if m.ended_at >= 0.0 else m.t
	var rec: PaceSimRdLog = m.record
	var checks: Array[Dictionary] = []
	checks.append(_at_most("first_payout", rec.events.get("first_payout", -1.0), k))
	checks.append(_at_most("first_upgrade", rec.events.get("first_upgrade", -1.0), k))
	checks.append(_at_most("first_hex", rec.events.get("hexes_1", -1.0), k))
	checks.append(_gap("small_win", _floats(rec.wins), 0.0, end_s, k, LIMITS["small_win"]))
	var hour: float = FIRST_HOUR_S / k
	checks.append(_gap("purchase_first_hour", _floats(rec.affordable), 0.0, minf(end_s, hour), k, LIMITS["purchase_first_hour"]))
	if end_s > hour:
		checks.append(_gap("purchase_later", _floats(rec.affordable), hour, end_s, k, LIMITS["purchase_later"]))
	var goal_times: Array[float] = _floats(rec.now_goals)
	goal_times.append_array(_times(rec.district_goals))
	goal_times.sort()
	checks.append(_gap("goal_gap", goal_times, 0.0, end_s, k, LIMITS["goal_gap"]))
	checks.append(_gap("now_goal", _floats(rec.now_goals), 0.0, end_s, k, m.data.num("goals.tiers.now_max_s")))
	checks.append(_gap("district_goal_gap", _times(rec.district_goals), 0.0, end_s, k, m.data.num("goals.tiers.district_gap_max_s")))
	var mechanics: Array[float] = _mechanic_times(m)
	checks.append(_gap("mechanic_first_hour", mechanics, 0.0, minf(end_s, hour), k, LIMITS["mechanic_first_hour"]))
	if end_s > hour:
		checks.append(_gap("mechanic_later", mechanics, hour, end_s, k, LIMITS["mechanic_later"]))
	var spikes: Dictionary = _spikes(rec, "hand_units", "crew_units", k)
	checks.append(_spike_check(spikes, end_s, k))
	checks.append_array(PaceSimRdDesignChecks.build(m, end_s, k))
	checks.append_array(PaceSimRdEconomyChecks.build(m, end_s, k))
	return {"beats": _beats(m, k), "checks": checks, "districts": _districts(m, end_s, k), "spikes": spikes,
		"hex_spikes": _spikes(rec, "hand_hexes", "crew_hexes", k), "notes": _notes(m, end_s, k), "ended": m.ended_at >= 0.0, "end_min": end_s / 60.0}


## True when every check of the report passed.
static func all_pass(report: Dictionary) -> bool:
	for c: Dictionary in report["checks"]:
		if not c["pass"] and not bool(c.get("advisory", false)):
			return false
	return true


## Printable lines for a report.
static func lines(report: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = ["beat                                                    bot min  player min  target"]
	for b: Dictionary in report["beats"]:
		var target: String = "" if float(b["target"]) < 0.0 else "%6.0f" % float(b["target"])
		var when: String = "   never" if float(b["t"]) < 0.0 else "%8.1f" % (float(b["t"]) / 60.0)
		var player: String = "       -" if float(b["t"]) < 0.0 else "%8.1f" % float(b["player_min"])
		out.append("%-54s %s  %s  %s%s" % [b["label"], when, player, target, "  (mechanic)" if b["mechanic"] else ""])
	out.append("")
	out.append("district        hexes  clean  enter  st1    st2    st3    source st4    st5    in-district(player min / target)  crew@st4/target  hand share/target")
	for d: Dictionary in report["districts"]:
		out.append("%-15s %5d  %4.0f%%  %s %s %s %s %s %s %s   %6.1f / %-4.0f                 %3d / %-3d         %3.0f%% / %.0f%%" % [d["id"], d["hexes"], float(d["clean_share"]) * 100.0,
			_min(d["enter"]), _min(d["stage_at"][1]), _min(d["stage_at"][2]), _min(d["stage_at"][3]), _min(d["source"]), _min(d["stage_at"][4]), _min(d["stage_at"][5]),
			d["player_min"], d["target_min"], d["crew"], d["target_crew"], float(d["hand_share"]) * 100.0, float(d["target_share"]) * 100.0])
	out.append("")
	out.append("checks (every limit is on the PLAYER's clock; measured bot time x bot_to_player):")
	for c: Dictionary in report["checks"]:
		var mark: String = "PASS" if c["pass"] else ("NOTE" if bool(c.get("advisory", false)) else "FAIL")
		out.append("%s  %-26s %10s  (limit %s)  %s" % [mark, c["id"], c["shown"], c["limit_shown"], c["note"]])
	for n: String in report["notes"]:
		out.append("note: " + n)
	return out


static func _min(seconds: float) -> String:
	return "   -  " if seconds < 0.0 else "%6.1f" % (seconds / 60.0)


static func _check(id: String, passed: bool, value: float, shown: String, limit_shown: String, note: String) -> Dictionary:
	return {"id": id, "pass": passed, "value": value, "shown": shown, "limit_shown": limit_shown, "note": note}


static func _at_most(id: String, bot_s: float, k: float) -> Dictionary:
	var limit: float = LIMITS[id]
	if bot_s < 0.0:
		return _check(id, false, -1.0, "never", "%.0f s" % limit, "")
	return _check(id, bot_s * k <= limit, bot_s * k, "%.0f s" % (bot_s * k), "%.0f s" % limit, "bot %.0f s" % bot_s)


static func _gap(id: String, times: Array[float], from: float, to: float, k: float, limit: float) -> Dictionary:
	var gap: Vector2 = PaceSimReport.longest_gap(times, from, to)
	return _check(id, gap.x * k <= limit, gap.x * k, "%.0f s" % (gap.x * k), "%.0f s" % limit,
		"longest gap starts at bot minute %.1f (player %.1f)" % [gap.y / 60.0, gap.y / 60.0 * k])


static func _floats(a: PackedFloat64Array) -> Array[float]:
	var out: Array[float] = []
	out.assign(a)
	return out


static func _times(rows: Array[Dictionary]) -> Array[float]:
	var out: Array[float] = []
	for row: Dictionary in rows:
		out.append(float(row["t"]))
	return out


static func _mechanic_times(m: PaceSimRdModel) -> Array[float]:
	var out: Array[float] = []
	for beat: Dictionary in m.data.beats:
		if bool(beat.get("mechanic", false)) and m.record.events.has(str(beat["event"])):
			out.append(m.record.events[str(beat["event"])])
	out.sort()
	return out


static func _beats(m: PaceSimRdModel, k: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for beat: Dictionary in m.data.beats:
		var at: float = m.record.events.get(str(beat["event"]), -1.0)
		out.append({"id": beat["id"], "label": beat["label"], "t": at, "player_min": at / 60.0 * k, "target": float(beat.get("player_min", -1.0)),
			"mechanic": bool(beat.get("mechanic", false))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (float(a["t"]) if float(a["t"]) >= 0.0 else INF) < (float(b["t"]) if float(b["t"]) >= 0.0 else INF))
	return out


static func _districts(m: PaceSimRdModel, end_s: float, k: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z: PaceSimRdDistrict in m.zones:
		var next_enter: float = end_s
		if z.index + 1 < m.zones.size() and m.zones[z.index + 1].entered_at >= 0.0:
			next_enter = m.zones[z.index + 1].entered_at
		var total: float = z.hand_units + z.crew_units
		var target: Dictionary = z.row["target"]
		out.append({"id": z.id, "hexes": z.hexes, "clean_share": z.clean_share(), "enter": z.entered_at, "stage_at": z.stage_at, "source": z.source_at,
			"player_min": (next_enter - z.entered_at) / 60.0 * k if z.entered_at >= 0.0 else 0.0, "target_min": float(target["player_min"]),
			"crew": z.crew_at_stage4, "target_crew": int(target["crew"]), "hand_share": z.hand_units / total if total > 0.0 else 0.0,
			"target_share": float(target["hand_share"])})
	return out


## Moments the cleaning rate (averaged over the spike window) reached spike_factor x its value at
## the previous spike. {times: [bot s], rates: [per bot minute], first_rate}.
static func _spikes(rec: PaceSimRdLog, hand_key: String, crew_key: String, k: float) -> Dictionary:
	var window: int = maxi(1, int(round(SPIKE_WINDOW_MIN / k)))
	var times: Array[float] = []
	var at_rates: Array[float] = []
	var base: float = 0.0
	var first: float = 0.0
	for i: int in range(window, rec.minutes.size()):
		var a: Dictionary = rec.minutes[i - window]
		var b: Dictionary = rec.minutes[i]
		var rate: float = (float(b[hand_key]) + float(b[crew_key]) - float(a[hand_key]) - float(a[crew_key])) / float(window)
		if base <= 0.0:
			base = rate
			first = rate
		elif rate >= base * LIMITS["spike_factor"]:
			times.append(float(i + 1) * PaceSimRdLog.SAMPLE_S)
			at_rates.append(rate)
			base = rate
	return {"times": times, "rates": at_rates, "first_rate": first}


static func _spike_check(spikes: Dictionary, end_s: float, k: float) -> Dictionary:
	var gap: Vector2 = PaceSimReport.longest_gap(spikes["times"], 0.0, end_s)
	var at: PackedStringArray = []
	for s: float in spikes["times"]:
		at.append("%.0f" % (s / 60.0 * k))
	return _check("spike_gap", gap.x * k <= LIMITS["spike_gap"], gap.x * k, "%.0f s" % (gap.x * k), "%.0f s" % LIMITS["spike_gap"],
		"cleaning power (work units a second) doubled at player minutes [%s]" % ", ".join(at))


static func _notes(m: PaceSimRdModel, end_s: float, k: float) -> PackedStringArray:
	var notes: PackedStringArray = []
	if m.ended_at < 0.0:
		notes.append("the ending was not reached in %.0f bot minutes; restoration %.0f%%" % [end_s / 60.0, m.restoration() * 100.0])
	var gap: Vector2 = PaceSimReport.longest_gap(_times(m.record.purchases), 0.0, end_s)
	notes.append("%d purchases; longest gap between purchases actually made: %.0f player s from bot minute %.1f" % [m.record.purchases.size(), gap.x * k, gap.y / 60.0])
	var levels: PackedStringArray = []
	for kind: String in m.mastery:
		levels.append("%s %d" % [kind, m.mastery[kind]])
	notes.append("mastery at the end: " + ", ".join(levels))
	var crew: PackedStringArray = []
	for type: String in m.robots:
		crew.append("%s x%d%s" % [type, m.robots[type], " repaired" if m.repaired.get(type, 0) > 0 else ""])
	notes.append("crew at the end: %d robots (listed with the factory buildings: %s), base level %d" % [m.robot_total(), ", ".join(crew), m.base_level])
	var curve: PackedStringArray = []
	for i: int in range(CREW_CURVE_STEP_MIN - 1, m.record.minutes.size(), CREW_CURVE_STEP_MIN):
		curve.append("%d: %d" % [m.record.minutes[i]["minute"], m.record.minutes[i]["robots"]])
	notes.append("crew over time (bot minute: robots): " + ", ".join(curve))
	var by_city: PackedStringArray = []
	for z: PaceSimRdDistrict in m.zones:
		by_city.append("%s %d" % [z.id, z.crew_at_stage4])
	notes.append("crew when each city reached stage 4: %s; Parts the Scroungers carried in: %.0f of %.0f earned; robots the Assemblers built: %d" % [
		", ".join(by_city), m.scrounged, m.parts_earned, m.assembled])
	var spent: PackedStringArray = []
	for key: String in m.work.seconds:
		spent.append("%s %.0f%%" % [key, m.work.seconds[key] / end_s * 100.0])
	notes.append("Lumi's time: " + ", ".join(spent))
	notes.append_array(PaceSimRdEconomyChecks.figures(m, end_s))
	for line: String in PaceSimRdEconomyChecks.city_rows(m, end_s, k):
		notes.append("city " + line)
	notes.append("seeds: earned %.0f, spent on planting %.0f, spent on cleansing plants (blight) %.0f, left %.0f; blight work waited on seeds for %.0f bot s" % [
		m.seeds_earned, m.seeds_planted, m.seeds_cleansing, m.seeds, m.seed_short_s])
	notes.append("field data: earned %.0f, unspent in the bank at the end %.0f; pieces found: %d; cubes left %.0f, Parts left %.0f of %.0f earned" % [
		m.data_earned, m.data_bank, m.pieces.size(), m.cubes, m.parts, m.parts_earned])
	return notes
